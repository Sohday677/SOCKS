//
//  ContentView.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showingHelp = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Server Status Card
                    ServerStatusCard()
                    
                    // Live Data Stats (only when server is running)
                    if serverManager.isRunning {
                        LiveStatsCard()
                    }
                    
                    // Proxy Configuration Card
                    ProxyConfigCard()
                    
                    // Server Control Button
                    ServerControlButton()
                    
                    Spacer()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("SOCKS5 Server")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingHelp) {
                HelpView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(settingsManager)
            }
        }
        .onAppear {
            if settingsManager.autoStartServer && !serverManager.isRunning {
                serverManager.proxyType = settingsManager.proxyType
                serverManager.startServer()
            }
        }
        .onChange(of: settingsManager.proxyType) { newProxyType in
            // Update server manager proxy type when settings change
            serverManager.proxyType = newProxyType
        }
    }
}

// MARK: - Server Status Card
struct ServerStatusCard: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(serverManager.isRunning ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: serverManager.isRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(serverManager.isRunning ? .green : .red)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(serverManager.isRunning ? "Server Running" : "Server Stopped")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(serverManager.isRunning ? "Ready to accept connections" : "Tap Start to begin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if serverManager.isRunning {
                Divider()
                
                VStack(spacing: 12) {
                    InfoRow(icon: settingsManager.proxyType.icon, label: "Protocol", value: settingsManager.proxyType.rawValue)
                    InfoRow(icon: "network", label: "IP Address", value: serverManager.ipAddress)
                    InfoRow(icon: "number", label: "Port", value: "\(serverManager.port)")
                    InfoRow(icon: "person.2.fill", label: "Connected Clients", value: "\(serverManager.connectedClients)")
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

// MARK: - Live Stats Card
struct LiveStatsCard: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text("Live Statistics")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            HStack(spacing: 16) {
                // Upload Stats
                StatBox(
                    icon: "arrow.up.circle.fill",
                    iconColor: .orange,
                    title: "Upload",
                    speed: String(format: "%.2f Mbps", serverManager.uploadSpeed),
                    total: serverManager.formattedUploadBytes()
                )
                
                // Download Stats
                StatBox(
                    icon: "arrow.down.circle.fill",
                    iconColor: .blue,
                    title: "Download",
                    speed: String(format: "%.2f Mbps", serverManager.downloadSpeed),
                    total: serverManager.formattedDownloadBytes()
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let icon: String
    let iconColor: Color
    let title: String
    let speed: String
    let total: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text(speed)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(total)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Proxy Configuration Card
struct ProxyConfigCard: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var portText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Configuration")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Port Configuration
                HStack {
                    Image(systemName: "number")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Port")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)
                        .disabled(serverManager.isRunning)
                        .onChange(of: portText) { newValue in
                            // Filter to only digits
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                portText = filtered
                            }
                            // Update port if valid, otherwise keep showing the input
                            if let port = Int(filtered), port > 0, port <= 65535 {
                                serverManager.port = port
                            }
                        }
                        .onSubmit {
                            // On submit, validate and reset to current port if invalid
                            if let port = Int(portText), port > 0, port <= 65535 {
                                serverManager.port = port
                            } else {
                                portText = String(serverManager.port)
                            }
                        }
                }
            }
            
            // Copy Configuration Button
            if serverManager.isRunning {
                Divider()
                
                Button(action: {
                    let config = "\(settingsManager.proxyType.rawValue) \(serverManager.ipAddress):\(serverManager.port)"
                    UIPasteboard.general.string = config
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Proxy Configuration")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
        .onAppear {
            portText = String(serverManager.port)
        }
        .onChange(of: serverManager.port) { newPort in
            // Sync text field when port changes externally
            if !serverManager.isRunning {
                portText = String(newPort)
            }
        }
    }
}

// MARK: - Server Control Button
struct ServerControlButton: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if serverManager.isRunning {
                    serverManager.stopServer()
                } else {
                    serverManager.proxyType = settingsManager.proxyType
                    serverManager.startServer()
                }
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: serverManager.isRunning ? "stop.fill" : "play.fill")
                    .font(.title2)
                Text(serverManager.isRunning ? "Stop Server" : "Start Server")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: serverManager.isRunning 
                                ? [Color.red, Color.red.opacity(0.8)] 
                                : [Color.green, Color.green.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .shadow(color: (serverManager.isRunning ? Color.red : Color.green).opacity(0.4), radius: 12, x: 0, y: 6)
    }
}

#Preview {
    ContentView()
        .environmentObject(SOCKS5ServerManager())
        .environmentObject(SettingsManager())
}
