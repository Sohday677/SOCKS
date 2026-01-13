//
//  SOCKS5ServerManager.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import Foundation
import Network
import Combine

class SOCKS5ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var ipAddress = "0.0.0.0"
    @Published var port: Int = 1080
    @Published var connectedClients = 0
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.socks5server.network", qos: .userInteractive)
    
    init() {
        updateIPAddress()
    }
    
    func startServer() {
        guard !isRunning else { return }
        
        updateIPAddress()
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("SOCKS5 Server started on port \(self?.port ?? 1080)")
                    case .failed(let error):
                        print("Server failed: \(error)")
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: queue)
            
        } catch {
            print("Failed to create listener: \(error)")
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        DispatchQueue.main.async {
            self.connectedClients += 1
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveSOCKS5Request(connection)
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func removeConnection(_ connection: NWConnection) {
        if let index = connections.firstIndex(where: { $0 === connection }) {
            connections.remove(at: index)
            DispatchQueue.main.async {
                self.connectedClients = max(0, self.connectedClients - 1)
            }
        }
    }
    
    private func receiveSOCKS5Request(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }
            
            self?.processSOCKS5Handshake(connection, data: data)
        }
    }
    
    private func processSOCKS5Handshake(_ connection: NWConnection, data: Data) {
        // SOCKS5 Greeting
        // +----+----------+----------+
        // |VER | NMETHODS | METHODS  |
        // +----+----------+----------+
        // | 1  |    1     | 1 to 255 |
        // +----+----------+----------+
        
        guard data.count >= 2 else {
            connection.cancel()
            return
        }
        
        let version = data[0]
        
        // Only support SOCKS5
        guard version == 0x05 else {
            connection.cancel()
            return
        }
        
        // Respond with no authentication required
        let response = Data([0x05, 0x00])
        
        connection.send(content: response, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Send error: \(error)")
                connection.cancel()
                return
            }
            
            self?.receiveSOCKS5ConnectRequest(connection)
        })
    }
    
    private func receiveSOCKS5ConnectRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }
            
            self?.processSOCKS5ConnectRequest(connection, data: data)
        }
    }
    
    private func processSOCKS5ConnectRequest(_ connection: NWConnection, data: Data) {
        // SOCKS5 Request
        // +----+-----+-------+------+----------+----------+
        // |VER | CMD |  RSV  | ATYP | DST.ADDR | DST.PORT |
        // +----+-----+-------+------+----------+----------+
        // | 1  |  1  | X'00' |  1   | Variable |    2     |
        // +----+-----+-------+------+----------+----------+
        
        guard data.count >= 4 else {
            connection.cancel()
            return
        }
        
        let version = data[0]
        let command = data[1]
        // data[2] is reserved
        let addressType = data[3]
        
        guard version == 0x05, command == 0x01 else {
            // Only support CONNECT command
            sendSOCKS5Error(connection, errorCode: 0x07)
            return
        }
        
        var host: NWEndpoint.Host?
        var port: NWEndpoint.Port?
        var offset = 4
        
        switch addressType {
        case 0x01: // IPv4
            guard data.count >= offset + 6 else {
                sendSOCKS5Error(connection, errorCode: 0x01)
                return
            }
            let ipBytes = data[offset..<offset+4]
            let ipString = ipBytes.map { String($0) }.joined(separator: ".")
            host = NWEndpoint.Host(ipString)
            offset += 4
            
        case 0x03: // Domain name
            guard data.count > offset else {
                sendSOCKS5Error(connection, errorCode: 0x01)
                return
            }
            let domainLength = Int(data[offset])
            offset += 1
            guard data.count >= offset + domainLength + 2 else {
                sendSOCKS5Error(connection, errorCode: 0x01)
                return
            }
            let domainData = data[offset..<offset+domainLength]
            if let domain = String(data: domainData, encoding: .utf8) {
                host = NWEndpoint.Host(domain)
            }
            offset += domainLength
            
        case 0x04: // IPv6
            guard data.count >= offset + 18 else {
                sendSOCKS5Error(connection, errorCode: 0x01)
                return
            }
            let ipBytes = data[offset..<offset+16]
            var ipString = ""
            for i in stride(from: 0, to: 16, by: 2) {
                if !ipString.isEmpty { ipString += ":" }
                ipString += String(format: "%02x%02x", ipBytes[ipBytes.startIndex + i], ipBytes[ipBytes.startIndex + i + 1])
            }
            host = NWEndpoint.Host(ipString)
            offset += 16
            
        default:
            sendSOCKS5Error(connection, errorCode: 0x08)
            return
        }
        
        // Parse port
        guard data.count >= offset + 2 else {
            sendSOCKS5Error(connection, errorCode: 0x01)
            return
        }
        
        let portValue = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        port = NWEndpoint.Port(rawValue: portValue)
        
        guard let targetHost = host, let targetPort = port else {
            sendSOCKS5Error(connection, errorCode: 0x01)
            return
        }
        
        // Create outbound connection
        connectToTarget(connection, host: targetHost, port: targetPort)
    }
    
    private func connectToTarget(_ clientConnection: NWConnection, host: NWEndpoint.Host, port: NWEndpoint.Port) {
        let parameters = NWParameters.tcp
        let targetConnection = NWConnection(host: host, port: port, using: parameters)
        
        targetConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendSOCKS5Success(clientConnection)
                self?.startBidirectionalRelay(client: clientConnection, target: targetConnection)
            case .failed:
                self?.sendSOCKS5Error(clientConnection, errorCode: 0x05)
            default:
                break
            }
        }
        
        targetConnection.start(queue: queue)
        connections.append(targetConnection)
    }
    
    private func sendSOCKS5Success(_ connection: NWConnection) {
        // +----+-----+-------+------+----------+----------+
        // |VER | REP |  RSV  | ATYP | BND.ADDR | BND.PORT |
        // +----+-----+-------+------+----------+----------+
        // | 1  |  1  | X'00' |  1   |    4     |    2     |
        // +----+-----+-------+------+----------+----------+
        
        var response = Data([0x05, 0x00, 0x00, 0x01])
        response.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Bound address
        response.append(contentsOf: [0x00, 0x00]) // Bound port
        
        connection.send(content: response, completion: .contentProcessed { error in
            if let error = error {
                print("Send success error: \(error)")
            }
        })
    }
    
    private func sendSOCKS5Error(_ connection: NWConnection, errorCode: UInt8) {
        var response = Data([0x05, errorCode, 0x00, 0x01])
        response.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        response.append(contentsOf: [0x00, 0x00])
        
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func startBidirectionalRelay(client: NWConnection, target: NWConnection) {
        // Client -> Target
        relay(from: client, to: target)
        // Target -> Client
        relay(from: target, to: client)
    }
    
    private func relay(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("Relay receive error: \(error)")
                source.cancel()
                destination.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { error in
                    if let error = error {
                        print("Relay send error: \(error)")
                        source.cancel()
                        destination.cancel()
                        return
                    }
                    
                    if !isComplete {
                        self?.relay(from: source, to: destination)
                    }
                })
            } else if isComplete {
                source.cancel()
                destination.cancel()
            } else {
                self?.relay(from: source, to: destination)
            }
        }
    }
    
    private func updateIPAddress() {
        ipAddress = getWiFiAddress() ?? "0.0.0.0"
    }
    
    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { continue }
                
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name.hasPrefix("bridge") {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
}
