//
//  SettingsView.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
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
                
                // Background Awake Method Section
                Section {
                    ForEach(BackgroundAwakeMethod.allCases) { method in
                        Button(action: {
                            settingsManager.backgroundAwakeMethod = method
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
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
