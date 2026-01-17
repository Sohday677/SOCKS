//
//  SOCKS5ServerApp.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import SwiftUI
import Combine

@main
struct SOCKS5ServerApp: App {
    @StateObject private var serverManager = SOCKS5ServerManager()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var backgroundManager = BackgroundManager()
    
    /// Track previous running state for notification purposes
    @State private var wasRunning = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
                .environmentObject(settingsManager)
                .environmentObject(backgroundManager)
                .onReceive(serverManager.$isRunning) { isRunning in
                    if isRunning {
                        // Start background method with IP and port for Live Activity
                        backgroundManager.startBackgroundMethod(
                            settingsManager.backgroundAwakeMethod,
                            ipAddress: serverManager.ipAddress,
                            port: serverManager.port
                        )
                    } else {
                        // Send disconnection notification if server was previously running
                        backgroundManager.stopBackgroundMethod(sendNotification: wasRunning)
                    }
                    wasRunning = isRunning
                }
                .onReceive(settingsManager.$backgroundAwakeMethod) { method in
                    if serverManager.isRunning {
                        backgroundManager.startBackgroundMethod(
                            method,
                            ipAddress: serverManager.ipAddress,
                            port: serverManager.port
                        )
                    }
                }
                .onReceive(serverManager.$connectedClients) { clients in
                    // Update Live Activity when client count changes
                    if serverManager.isRunning && settingsManager.backgroundAwakeMethod == .location {
                        backgroundManager.updateLiveActivity(
                            ipAddress: serverManager.ipAddress,
                            port: serverManager.port,
                            connectedClients: clients
                        )
                    }
                }
        }
    }
}
