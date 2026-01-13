//
//  ContentView.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    @State private var showingHelp = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Server Status Card
                    ServerStatusCard()
                    
                    // Proxy Configuration Card
                    ProxyConfigCard()
                    
                    // Server Control Button
                    ServerControlButton()
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("SOCKS5 Server")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingHelp) {
                HelpView()
            }
        }
    }
}

// MARK: - Server Status Card
struct ServerStatusCard: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: serverManager.isRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(serverManager.isRunning ? .green : .red)
                
                Text(serverManager.isRunning ? "Server Running" : "Server Stopped")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            if serverManager.isRunning {
                VStack(spacing: 12) {
                    HStack {
                        Label("IP Address", systemImage: "network")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(serverManager.ipAddress)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Label("Port", systemImage: "number")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(serverManager.port)")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Label("Protocol", systemImage: "lock.shield")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("SOCKS5")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Proxy Configuration Card
struct ProxyConfigCard: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Proxy Configuration")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Port Configuration
                HStack {
                    Text("Port:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("Port", value: Binding(
                        get: { serverManager.port },
                        set: { serverManager.port = $0 }
                    ), formatter: NumberFormatter())
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 100)
                    .disabled(serverManager.isRunning)
                }
            }
            
            // Copy Configuration Button
            if serverManager.isRunning {
                Button(action: {
                    let config = "SOCKS5 \(serverManager.ipAddress):\(serverManager.port)"
                    UIPasteboard.general.string = config
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Proxy Configuration")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Server Control Button
struct ServerControlButton: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    
    var body: some View {
        Button(action: {
            if serverManager.isRunning {
                serverManager.stopServer()
            } else {
                serverManager.startServer()
            }
        }) {
            HStack {
                Image(systemName: serverManager.isRunning ? "stop.fill" : "play.fill")
                    .font(.title2)
                Text(serverManager.isRunning ? "Stop Server" : "Start Server")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(serverManager.isRunning ? Color.red : Color.green)
            )
        }
        .shadow(color: (serverManager.isRunning ? Color.red : Color.green).opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(SOCKS5ServerManager())
}
