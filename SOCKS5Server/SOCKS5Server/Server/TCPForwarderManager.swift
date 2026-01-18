//
//  TCPForwarderManager.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import Foundation
import Network
import Combine
import UIKit

/// Manages TCP forwarding (similar to socat tcp-listen:port,fork tcp:host:port)
/// This allows the iPhone to act as a TCP relay, forwarding connections to a remote VPN endpoint
class TCPForwarderManager: ObservableObject {
    // MARK: - Constants
    private static let fallbackIPAddress = "0.0.0.0"
    private static let relayBufferSize = 65536
    private static let wifiInterfaceName = "en0"
    private static let bridgeInterfacePrefix = "bridge"
    
    // MARK: - Published Properties
    @Published var isForwarding = false
    @Published var localIPAddress = TCPForwarderManager.fallbackIPAddress
    @Published var localPort: Int = 51821
    @Published var remoteHost: String = ""
    @Published var remotePort: Int = 1194
    @Published var connectedClients = 0
    @Published var forwardedBytes: Int64 = 0
    
    // MARK: - Private Properties
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.socks5server.tcpforwarder", qos: .userInteractive)
    
    // App lifecycle
    private var isInForeground = true
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    
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
    
    // MARK: - Public Methods
    
    func startForwarding() {
        guard !isForwarding else { return }
        guard !remoteHost.isEmpty else {
            print("TCPForwarder: Remote host not configured")
            return
        }
        
        updateIPAddress()
        forwardedBytes = 0
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(localPort)))
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isForwarding = true
                        print("TCPForwarder: Started on port \(self?.localPort ?? 51821) -> \(self?.remoteHost ?? ""):\(self?.remotePort ?? 0)")
                    case .failed(let error):
                        print("TCPForwarder: Failed - \(error)")
                        self?.isForwarding = false
                    case .cancelled:
                        self?.isForwarding = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            listener?.start(queue: queue)
            
        } catch {
            print("TCPForwarder: Failed to create listener - \(error)")
        }
    }
    
    func stopForwarding() {
        listener?.cancel()
        listener = nil
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        DispatchQueue.main.async {
            self.isForwarding = false
            self.connectedClients = 0
        }
    }
    
    // MARK: - Private Methods
    
    private func handleIncomingConnection(_ clientConnection: NWConnection) {
        connections.append(clientConnection)
        
        DispatchQueue.main.async {
            self.connectedClients += 1
        }
        
        clientConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.connectToRemote(clientConnection: clientConnection)
            case .failed, .cancelled:
                self?.removeConnection(clientConnection)
            default:
                break
            }
        }
        
        clientConnection.start(queue: queue)
    }
    
    private func connectToRemote(clientConnection: NWConnection) {
        let parameters = NWParameters.tcp
        let targetHost = NWEndpoint.Host(remoteHost)
        let targetPort = NWEndpoint.Port(integerLiteral: UInt16(remotePort))
        
        let remoteConnection = NWConnection(host: targetHost, port: targetPort, using: parameters)
        
        remoteConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Start bidirectional relay
                self?.startBidirectionalRelay(client: clientConnection, remote: remoteConnection)
            case .failed(let error):
                print("TCPForwarder: Remote connection failed - \(error)")
                clientConnection.cancel()
            case .cancelled:
                clientConnection.cancel()
            default:
                break
            }
        }
        
        remoteConnection.start(queue: queue)
        connections.append(remoteConnection)
    }
    
    private func startBidirectionalRelay(client: NWConnection, remote: NWConnection) {
        // Client -> Remote
        relay(from: client, to: remote)
        // Remote -> Client
        relay(from: remote, to: client)
    }
    
    private func relay(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: Self.relayBufferSize) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("TCPForwarder: Relay error - \(error)")
                source.cancel()
                destination.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Track forwarded bytes
                DispatchQueue.main.async {
                    self.forwardedBytes += Int64(data.count)
                }
                
                destination.send(content: data, completion: .contentProcessed { [weak self] error in
                    if let error = error {
                        print("TCPForwarder: Send error - \(error)")
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
                self.relay(from: source, to: destination)
            }
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        if let index = connections.firstIndex(where: { $0 === connection }) {
            connections.remove(at: index)
            DispatchQueue.main.async {
                self.connectedClients = max(0, self.connectedClients - 1)
            }
        }
    }
    
    private func updateIPAddress() {
        localIPAddress = getWiFiAddress() ?? Self.fallbackIPAddress
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
    
    func formattedForwardedBytes() -> String {
        return formatBytes(forwardedBytes)
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
