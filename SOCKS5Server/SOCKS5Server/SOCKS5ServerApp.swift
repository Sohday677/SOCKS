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
                            port: serverManager.port,
                            enableDynamicIsland: settingsManager.enableDynamicIsland
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
                            port: serverManager.port,
                            enableDynamicIsland: settingsManager.enableDynamicIsland
                        )
                    }
                }
                .onReceive(settingsManager.$enableDynamicIsland) { enabled in
                    // Restart background method when Dynamic Island setting changes
                    if serverManager.isRunning && settingsManager.backgroundAwakeMethod == .location {
                        backgroundManager.startBackgroundMethod(
                            .location,
                            ipAddress: serverManager.ipAddress,
                            port: serverManager.port,
                            enableDynamicIsland: enabled
                        )
                    }
                }
                .onReceive(serverManager.$connectedClients) { clients in
                    // Update Live Activity when client count changes (only if Dynamic Island is enabled)
                    if serverManager.isRunning && settingsManager.backgroundAwakeMethod == .location && settingsManager.enableDynamicIsland {
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
