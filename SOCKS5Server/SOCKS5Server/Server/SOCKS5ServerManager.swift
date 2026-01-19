//
//  SOCKS5ServerManager.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import Foundation
import Network
import Combine
import UIKit

class SOCKS5ServerManager: ObservableObject {
    // MARK: - Constants
    private static let fallbackIPAddress = "0.0.0.0"
    private static let relayBufferSize = 65536
    private static let httpRequestBufferSize = 8192
    private static let defaultHTTPPort: UInt16 = 80
    private static let wifiInterfaceName = "en0"
    private static let bridgeInterfacePrefix = "bridge"
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var ipAddress = SOCKS5ServerManager.fallbackIPAddress
    @Published var port: Int = 4884
    @Published var connectedClients = 0
    @Published var uploadBytes: Int64 = 0
    @Published var downloadBytes: Int64 = 0
    @Published var uploadSpeed: Double = 0.0  // Mbps
    @Published var downloadSpeed: Double = 0.0  // Mbps
    
    // Proxy type
    var proxyType: ProxyType = .socks5
    
    // Speed calculation - use internal counters to avoid main queue dispatches per packet
    private var lastUploadBytes: Int64 = 0
    private var lastDownloadBytes: Int64 = 0
    private var speedTimer: Timer?
    private var pendingUploadBytes: Int64 = 0
    private var pendingDownloadBytes: Int64 = 0
    private let bytesLock = NSLock()
    
    // App lifecycle - only update UI when in foreground for optimization
    private var isInForeground = true
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    
    // MARK: - Private Properties
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.socks5server.network", qos: .userInteractive)
    
    init() {
        updateIPAddress()
        setupAppLifecycleObservers()
    }
    
    deinit {
        if let foregroundObserver = foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        if let backgroundObserver = backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }
    
    private func setupAppLifecycleObservers() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInForeground = true
        }
        
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInForeground = false
        }
    }
    
    func startServer() {
        guard !isRunning else { return }
        
        updateIPAddress()
        resetStats()
        startSpeedTimer()
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("SOCKS5 Server started on port \(self?.port ?? 4884)")
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
        
        stopSpeedTimer()
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
            self.uploadSpeed = 0.0
            self.downloadSpeed = 0.0
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
                // Route to appropriate protocol handler based on proxy type
                if self?.proxyType == .socks5 {
                    self?.receiveSOCKS5Request(connection)
                } else {
                    self?.receiveHTTPRequest(connection)
                }
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
        // Client -> Target (upload: data going out from proxy to target)
        relayWithTracking(from: client, to: target, isUpload: true)
        // Target -> Client (download: data coming back from target to client)
        relayWithTracking(from: target, to: client, isUpload: false)
    }
    
    private func relayWithTracking(from source: NWConnection, to destination: NWConnection, isUpload: Bool) {
        source.receive(minimumIncompleteLength: 1, maximumLength: Self.relayBufferSize) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Relay receive error: \(error)")
                source.cancel()
                destination.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Track bytes using lock for thread safety - avoids main queue dispatch per packet
                self.bytesLock.lock()
                if isUpload {
                    self.pendingUploadBytes += Int64(data.count)
                } else {
                    self.pendingDownloadBytes += Int64(data.count)
                }
                self.bytesLock.unlock()
                
                destination.send(content: data, completion: .contentProcessed { [weak self] error in
                    if let error = error {
                        print("Relay send error: \(error)")
                        source.cancel()
                        destination.cancel()
                        return
                    }
                    
                    if !isComplete {
                        self?.relayWithTracking(from: source, to: destination, isUpload: isUpload)
                    }
                })
            } else if isComplete {
                source.cancel()
                destination.cancel()
            } else {
                self.relayWithTracking(from: source, to: destination, isUpload: isUpload)
            }
        }
    }
    
    private func relay(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: Self.relayBufferSize) { [weak self] data, _, isComplete, error in
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
    
    // MARK: - HTTP Proxy Methods
    
    private func receiveHTTPRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.httpRequestBufferSize) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("Receive HTTP error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }
            
            self?.processHTTPRequest(connection, data: data)
        }
    }
    
    private func processHTTPRequest(_ connection: NWConnection, data: Data) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            connection.cancel()
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            connection.cancel()
            return
        }
        
        let requestLine = lines[0]
        let components = requestLine.components(separatedBy: " ")
        
        // Handle CONNECT method for HTTPS tunneling
        if components.count >= 2 && components[0] == "CONNECT" {
            handleHTTPConnect(connection, hostPort: components[1])
        } else {
            // Handle regular HTTP requests (GET, POST, etc.)
            handleHTTPProxy(connection, requestData: data, requestString: requestString)
        }
    }
    
    private func handleHTTPConnect(_ clientConnection: NWConnection, hostPort: String) {
        // Parse host:port
        let parts = hostPort.components(separatedBy: ":")
        guard parts.count == 2,
              let portValue = UInt16(parts[1]),
              portValue > 0 && portValue <= 65535 else {
            sendHTTPError(clientConnection, statusCode: 400, message: "Bad Request")
            return
        }
        
        let host = NWEndpoint.Host(parts[0])
        guard let port = NWEndpoint.Port(rawValue: portValue) else {
            sendHTTPError(clientConnection, statusCode: 400, message: "Bad Request")
            return
        }
        
        let parameters = NWParameters.tcp
        let targetConnection = NWConnection(host: host, port: port, using: parameters)
        
        targetConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendHTTPConnectSuccess(clientConnection)
                self?.startBidirectionalRelay(client: clientConnection, target: targetConnection)
            case .failed:
                self?.sendHTTPError(clientConnection, statusCode: 502, message: "Bad Gateway")
            default:
                break
            }
        }
        
        targetConnection.start(queue: queue)
        connections.append(targetConnection)
    }
    
    private func handleHTTPProxy(_ clientConnection: NWConnection, requestData: Data, requestString: String) {
        // Parse the request to extract host and construct proper request
        let lines = requestString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            sendHTTPError(clientConnection, statusCode: 400, message: "Bad Request")
            return
        }
        
        var host: String?
        var port: UInt16 = Self.defaultHTTPPort
        
        // Find Host header
        for line in lines {
            if line.lowercased().hasPrefix("host:") {
                let hostValue = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                let parts = hostValue.components(separatedBy: ":")
                host = parts[0]
                if parts.count > 1, let portValue = UInt16(parts[1]), portValue > 0 && portValue <= 65535 {
                    port = portValue
                }
                break
            }
        }
        
        guard let targetHost = host else {
            sendHTTPError(clientConnection, statusCode: 400, message: "Bad Request - No Host header")
            return
        }
        
        // Create connection to target server
        let nwHost = NWEndpoint.Host(targetHost)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            sendHTTPError(clientConnection, statusCode: 400, message: "Bad Request - Invalid Port")
            return
        }
        
        let parameters = NWParameters.tcp
        let targetConnection = NWConnection(host: nwHost, port: nwPort, using: parameters)
        
        targetConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Forward the original request
                targetConnection.send(content: requestData, completion: .contentProcessed { [weak self] error in
                    if let error = error {
                        print("HTTP proxy send error: \(error)")
                        clientConnection.cancel()
                        targetConnection.cancel()
                        return
                    }
                    // Start relaying responses
                    self?.startBidirectionalRelay(client: clientConnection, target: targetConnection)
                })
            case .failed:
                self?.sendHTTPError(clientConnection, statusCode: 502, message: "Bad Gateway")
            default:
                break
            }
        }
        
        targetConnection.start(queue: queue)
        connections.append(targetConnection)
    }
    
    private func sendHTTPConnectSuccess(_ connection: NWConnection) {
        let response = "HTTP/1.1 200 Connection Established\r\n\r\n"
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("Send HTTP success error: \(error)")
                }
            })
        }
    }
    
    private func sendHTTPError(_ connection: NWConnection, statusCode: Int, message: String) {
        let response = "HTTP/1.1 \(statusCode) \(message)\r\nContent-Length: 0\r\n\r\n"
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } else {
            connection.cancel()
        }
    }
    
    private func updateIPAddress() {
        ipAddress = getWiFiAddress() ?? Self.fallbackIPAddress
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
                    if name == Self.wifiInterfaceName || name.hasPrefix(Self.bridgeInterfacePrefix) {
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
    
    // MARK: - Stats and Speed Tracking
    
    private func resetStats() {
        bytesLock.lock()
        pendingUploadBytes = 0
        pendingDownloadBytes = 0
        bytesLock.unlock()
        
        uploadBytes = 0
        downloadBytes = 0
        lastUploadBytes = 0
        lastDownloadBytes = 0
        uploadSpeed = 0.0
        downloadSpeed = 0.0
    }
    
    private func startSpeedTimer() {
        // Create timer on main run loop for consistent behavior
        DispatchQueue.main.async { [weak self] in
            self?.speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.calculateSpeed()
            }
        }
    }
    
    private func stopSpeedTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.speedTimer?.invalidate()
            self?.speedTimer = nil
        }
    }
    
    private func calculateSpeed() {
        // Collect pending bytes under lock - always track bytes even in background
        bytesLock.lock()
        let pendingUp = pendingUploadBytes
        let pendingDown = pendingDownloadBytes
        pendingUploadBytes = 0
        pendingDownloadBytes = 0
        bytesLock.unlock()
        
        // Skip UI updates when app is in background for optimization
        guard isInForeground else {
            // Still accumulate bytes internally for when we return to foreground
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.uploadBytes += pendingUp
                self.downloadBytes += pendingDown
                self.lastUploadBytes = self.uploadBytes
                self.lastDownloadBytes = self.downloadBytes
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Add pending bytes to totals
            self.uploadBytes += pendingUp
            self.downloadBytes += pendingDown
            
            // Calculate bytes transferred in the last second
            let uploadDelta = self.uploadBytes - self.lastUploadBytes
            let downloadDelta = self.downloadBytes - self.lastDownloadBytes
            
            // Convert to Mbps (megabits per second)
            // bytes * 8 (to bits) / 1,000,000 (to megabits)
            self.uploadSpeed = Double(uploadDelta) * 8.0 / 1_000_000.0
            self.downloadSpeed = Double(downloadDelta) * 8.0 / 1_000_000.0
            
            self.lastUploadBytes = self.uploadBytes
            self.lastDownloadBytes = self.downloadBytes
        }
    }
    
    func formattedUploadBytes() -> String {
        return formatBytes(uploadBytes)
    }
    
    func formattedDownloadBytes() -> String {
        return formatBytes(downloadBytes)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f GB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }
}
