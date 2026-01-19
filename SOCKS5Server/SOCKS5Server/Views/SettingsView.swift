//
//  SettingsView.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import SwiftUI
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var backgroundManager: BackgroundManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // Auto Start Section
                Section {
                    Toggle(isOn: $settingsManager.autoStartServer) {
                        HStack(spacing: 12) {
                            Image(systemName: "power")
                                .foregroundColor(.green)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Start Server")
                                    .font(.body)
                                Text("Start server when app opens")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.green)
                } header: {
                    Text("Startup")
                }
                
                // Proxy Type Section
                Section {
                    ForEach(ProxyType.allCases) { type in
                        Button(action: {
                            selectProxyType(type)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .foregroundColor(proxyTypeColor(type))
                                    .font(.title3)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.rawValue)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(type.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                if settingsManager.proxyType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    Text("Proxy Type")
                } footer: {
                    Text("Choose proxy protocol. SOCKS5 for TCP/UDP connections, HTTP for web traffic. Restart server to apply changes.")
                }
                
                // Background Awake Method Section
                Section {
                    ForEach(BackgroundAwakeMethod.allCases) { method in
                        Button(action: {
                            selectBackgroundMethod(method)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: method.icon)
                                    .foregroundColor(methodColor(method))
                                    .font(.title3)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(method.rawValue)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(method.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                    
                                    // Show location authorization status if location method
                                    if method == .location {
                                        locationStatusView
                                    }
                                }
                                
                                Spacer()
                                
                                if settingsManager.backgroundAwakeMethod == method {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    Text("Background Method")
                } footer: {
                    Text("Choose how the app stays active in the background to maintain your proxy connection.")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var locationStatusView: some View {
        let status = backgroundManager.locationAuthorizationStatus
        
        HStack(spacing: 4) {
            switch status {
            case .authorizedAlways:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption2)
                Text("Always authorized")
                    .font(.caption2)
                    .foregroundColor(.green)
            case .authorizedWhenInUse:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
                Text("Enable 'Always' in Settings > Privacy > Location")
                    .font(.caption2)
                    .foregroundColor(.orange)
            case .denied, .restricted:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption2)
                Text("Permission denied - enable in Settings")
                    .font(.caption2)
                    .foregroundColor(.red)
            case .notDetermined:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.gray)
                    .font(.caption2)
                Text("Tap to request permission")
                    .font(.caption2)
                    .foregroundColor(.gray)
            @unknown default:
                EmptyView()
            }
        }
    }
    
    private func selectBackgroundMethod(_ method: BackgroundAwakeMethod) {
        settingsManager.backgroundAwakeMethod = method
        
        // Request location permission if location method is selected
        if method == .location {
            backgroundManager.requestLocationPermission()
        }
    }
    
    private func selectProxyType(_ type: ProxyType) {
        settingsManager.proxyType = type
    }
    
    private func methodColor(_ method: BackgroundAwakeMethod) -> Color {
        switch method {
        case .location:
            return .blue
        case .audio:
            return .orange
        case .none:
            return .gray
        }
    }
    
    private func proxyTypeColor(_ type: ProxyType) -> Color {
        switch type {
        case .socks5:
            return .blue
        case .http:
            return .green
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
        .environmentObject(BackgroundManager())
}
