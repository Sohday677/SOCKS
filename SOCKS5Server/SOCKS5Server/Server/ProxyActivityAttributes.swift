//
//  ProxyActivityAttributes.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import Foundation
import ActivityKit

/// ActivityAttributes for the proxy server Live Activity displayed in Dynamic Island
struct ProxyActivityAttributes: ActivityAttributes {
    /// Dynamic state that updates during the Live Activity
    public struct ContentState: Codable, Hashable {
        /// Whether the proxy server is currently active
        var isActive: Bool
        /// Connection status text (e.g., "Connected", "2 clients")
        var statusText: String
        /// Current IP address
        var ipAddress: String
        /// Current port
        var port: Int
    }
    
    /// Static attributes set when activity starts (name shown in navigation-style display)
    var serverName: String
}
