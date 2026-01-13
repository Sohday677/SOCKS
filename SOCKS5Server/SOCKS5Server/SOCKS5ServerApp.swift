//
//  SOCKS5ServerApp.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import SwiftUI

@main
struct SOCKS5ServerApp: App {
    @StateObject private var serverManager = SOCKS5ServerManager()
    @StateObject private var settingsManager = SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
                .environmentObject(settingsManager)
        }
    }
}
