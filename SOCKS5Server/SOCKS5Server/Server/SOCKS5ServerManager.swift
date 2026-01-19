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
    private static let wifiInterfaceName = "en0"
    private static let bridgeInterfacePrefix = "bridge"
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var ipAddress = SOCKS5ServerManager.fallbackIPAddress
    @Published var port: Int = 4884
    @Published var udpPort: Int = 4885
    @Published var connectedClients = 0
    @Published var uploadBytes: Int64 = 0
    @Published var downloadBytes: Int64 = 0
    @Published var uploadSpeed: Double = 0.0  // Mbps
    @Published var downloadSpeed: Double = 0.0  // Mbps
    
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
    private var udpListener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.socks5server.network", qos: .userInteractive)
    private let udpQueue = DispatchQueue(label: "com.socks5server.udp", qos: .userInteractive)
    
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
            // Start TCP listener for SOCKS5 control connection
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
            
            // Start UDP listener for UDP ASSOCIATE
            startUDPListener()
            
        } catch {
            print("Failed to create listener: \(error)")
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        
        udpListener?.cancel()
        udpListener = nil
        
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
        
        guard version == 0x05 else {
            sendSOCKS5Error(connection, errorCode: 0x07)
            return
        }
        
        // Support both CONNECT (0x01) and UDP ASSOCIATE (0x03)
        guard command == 0x01 || command == 0x03 else {
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
            host = NWEndpoint.Host(formatIPv6FromBytes(ipBytes))
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
        
        // Route based on command type
        if command == 0x01 {
            // CONNECT command - TCP relay
            connectToTarget(connection, host: targetHost, port: targetPort)
        } else if command == 0x03 {
            // UDP ASSOCIATE command
            handleUDPAssociate(connection)
        }
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
    
    // MARK: - UDP Support
    
    private func startUDPListener() {
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            
            udpListener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(udpPort)))
            
            udpListener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("UDP listener started on port \(self?.udpPort ?? 4885)")
                case .failed(let error):
                    print("UDP listener failed: \(error)")
                case .cancelled:
                    print("UDP listener cancelled")
                default:
                    break
                }
            }
            
            udpListener?.newConnectionHandler = { [weak self] connection in
                self?.handleUDPConnection(connection)
            }
            
            udpListener?.start(queue: udpQueue)
            
        } catch {
            print("Failed to create UDP listener: \(error)")
        }
    }
    
    private func handleUDPAssociate(_ connection: NWConnection) {
        // For UDP ASSOCIATE, we send back our UDP relay address and port
        // Response format is same as success response
        var response = Data([0x05, 0x00, 0x00, 0x01])
        
        // Return the server's IP address for UDP relay
        if let ip = getWiFiAddress(), let ipData = ipv4StringToData(ip) {
            response.append(ipData)
        } else {
            response.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        }
        
        // Return UDP port
        let portBytes = withUnsafeBytes(of: UInt16(udpPort).bigEndian) { Data($0) }
        response.append(portBytes)
        
        connection.send(content: response, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Send UDP associate response error: \(error)")
                connection.cancel()
                return
            }
            
            // Keep the TCP control connection alive for UDP association
            // The connection will remain open until client closes it
            self?.keepConnectionAlive(connection)
        })
    }
    
    private func keepConnectionAlive(_ connection: NWConnection) {
        // Keep receiving on the control connection to detect when client disconnects
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            // Continue keeping connection alive
            self?.keepConnectionAlive(connection)
        }
    }
    
    private func handleUDPConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveUDPPacket(connection)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        
        connection.start(queue: udpQueue)
    }
    
    private func receiveUDPPacket(_ connection: NWConnection) {
        // Note: This uses asynchronous recursion which is safe - the completion handler
        // is called asynchronously when data arrives, not synchronously in a loop
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("UDP receive error: \(error)")
                return
            }
            
            guard let data = data, !data.isEmpty else {
                self.receiveUDPPacket(connection)
                return
            }
            
            // Track download bytes for UDP
            self.bytesLock.lock()
            self.pendingDownloadBytes += Int64(data.count)
            self.bytesLock.unlock()
            
            // Process UDP relay packet
            self.processUDPRelayPacket(data, sourceConnection: connection)
            
            // Continue receiving (asynchronous tail recursion is safe here)
            self.receiveUDPPacket(connection)
        }
    }
    
    private func processUDPRelayPacket(_ data: Data, sourceConnection: NWConnection) {
        // SOCKS5 UDP Request format:
        // +----+------+------+----------+----------+----------+
        // |RSV | FRAG | ATYP | DST.ADDR | DST.PORT |   DATA   |
        // +----+------+------+----------+----------+----------+
        // | 2  |  1   |  1   | Variable |    2     | Variable |
        // +----+------+------+----------+----------+----------+
        
        guard data.count >= 4 else { return }
        
        // Skip RSV (2 bytes) and FRAG (1 byte)
        let frag = data[2]
        guard frag == 0x00 else {
            // Fragment handling not supported
            return
        }
        
        let addressType = data[3]
        var offset = 4
        var host: NWEndpoint.Host?
        var port: NWEndpoint.Port?
        
        // Parse destination address
        switch addressType {
        case 0x01: // IPv4
            guard data.count >= offset + 6 else { return }
            let ipBytes = data[offset..<offset+4]
            let ipString = ipBytes.map { String($0) }.joined(separator: ".")
            host = NWEndpoint.Host(ipString)
            offset += 4
            
        case 0x03: // Domain name
            guard data.count > offset else { return }
            let domainLength = Int(data[offset])
            offset += 1
            guard data.count >= offset + domainLength + 2 else { return }
            let domainData = data[offset..<offset+domainLength]
            if let domain = String(data: domainData, encoding: .utf8) {
                host = NWEndpoint.Host(domain)
            }
            offset += domainLength
            
        case 0x04: // IPv6
            guard data.count >= offset + 18 else { return }
            let ipBytes = data[offset..<offset+16]
            host = NWEndpoint.Host(formatIPv6FromBytes(ipBytes))
            offset += 16
            
        default:
            return
        }
        
        // Parse destination port
        guard data.count >= offset + 2 else { return }
        let portValue = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        port = NWEndpoint.Port(rawValue: portValue)
        offset += 2
        
        guard let targetHost = host, let targetPort = port else { return }
        
        // Extract actual UDP payload
        let payload = data[offset...]
        
        // Keep original address info for response (we need addressType and the raw address portion)
        let addressData = data[3..<offset] // From ATYP to end of port
        
        // Forward to target
        forwardUDPPacket(payload: Data(payload), to: targetHost, port: targetPort, replyTo: sourceConnection, originalAddressData: addressData)
    }
    
    private func forwardUDPPacket(payload: Data, to host: NWEndpoint.Host, port: NWEndpoint.Port, replyTo sourceConnection: NWConnection, originalAddressData: Data) {
        let parameters = NWParameters.udp
        let connection = NWConnection(host: host, port: port, using: parameters)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Send the payload
                connection.send(content: payload, completion: .contentProcessed { error in
                    if let error = error {
                        print("UDP forward send error: \(error)")
                        connection.cancel()
                        return
                    }
                    
                    // Track upload bytes
                    self?.bytesLock.lock()
                    self?.pendingUploadBytes += Int64(payload.count)
                    self?.bytesLock.unlock()
                    
                    // Wait for response
                    self?.receiveUDPResponse(connection, replyTo: sourceConnection, originalAddressData: originalAddressData)
                })
            case .failed(let error):
                print("UDP forward connection failed: \(error)")
            default:
                break
            }
        }
        
        connection.start(queue: udpQueue)
    }
    
    private func receiveUDPResponse(_ connection: NWConnection, replyTo sourceConnection: NWConnection, originalAddressData: Data) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("UDP response receive error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            
            // Track download bytes for response from target
            self.bytesLock.lock()
            self.pendingDownloadBytes += Int64(data.count)
            self.bytesLock.unlock()
            
            // Build SOCKS5 UDP response packet
            // +----+------+------+----------+----------+----------+
            // |RSV | FRAG | ATYP | DST.ADDR | DST.PORT |   DATA   |
            // +----+------+------+----------+----------+----------+
            var response = Data([0x00, 0x00, 0x00]) // RSV + FRAG
            
            // Append original address data (includes ATYP, address, and port)
            response.append(originalAddressData)
            
            // Add payload
            response.append(data)
            
            // Send back to client
            sourceConnection.send(content: response, completion: .contentProcessed { error in
                if let error = error {
                    print("UDP reply send error: \(error)")
                }
            })
            
            connection.cancel()
        }
    }
    
    private func ipv4StringToData(_ ipString: String) -> Data? {
        let components = ipString.split(separator: ".").compactMap { UInt8($0) }
        guard components.count == 4 else { return nil }
        return Data(components)
    }
    
    private func formatIPv6FromBytes(_ ipBytes: Data.SubSequence) -> String {
        var ipString = ""
        for i in stride(from: 0, to: 16, by: 2) {
            if !ipString.isEmpty { ipString += ":" }
            let value = UInt16(ipBytes[ipBytes.startIndex + i]) << 8 | UInt16(ipBytes[ipBytes.startIndex + i + 1])
            ipString += String(format: "%04x", value)
        }
        return ipString
    }
}
