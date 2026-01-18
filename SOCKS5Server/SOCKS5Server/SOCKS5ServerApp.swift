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
    @StateObject private var tcpForwarderManager = TCPForwarderManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
                .environmentObject(settingsManager)
                .environmentObject(backgroundManager)
                .environmentObject(tcpForwarderManager)
                .onReceive(serverManager.$isRunning) { isRunning in
                    if isRunning {
                        backgroundManager.startBackgroundMethod(settingsManager.backgroundAwakeMethod)
                    } else {
                        backgroundManager.stopBackgroundMethod()
                    }
                }
                .onReceive(settingsManager.$backgroundAwakeMethod) { method in
                    if serverManager.isRunning {
                        backgroundManager.startBackgroundMethod(method)
                    }
                }
        }
    }
}
