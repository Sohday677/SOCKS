//
//  VPNConfigView.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import SwiftUI
import UniformTypeIdentifiers

struct VPNConfigView: View {
    @EnvironmentObject var serverManager: SOCKS5ServerManager
    @EnvironmentObject var tcpForwarderManager: TCPForwarderManager
    @Environment(\.dismiss) var dismiss
    
    @State private var remoteHost: String = ""
    @State private var remotePort: String = "1194"
    @State private var localPort: String = "51821"
    @State private var selectedVPNType: VPNConfigGenerator.VPNType = .openVPN
    @State private var importedConfig: String = ""
    @State private var generatedConfig: String = ""
    @State private var showingImportPicker = false
    @State private var showingExportSheet = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var configFileName = "vpn-config"
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // TCP Forwarder Status
                    TCPForwarderStatusCard()
                    
                    // Configuration Input
                    VPNEndpointConfigCard()
                    
                    // Import Config Section
                    ImportConfigCard()
                    
                    // Generated Config Preview
                    if !generatedConfig.isEmpty {
                        GeneratedConfigCard()
                    }
                    
                    // Action Buttons
                    ActionButtonsCard()
                    
                    Spacer()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("VPN Config")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.text, .plainText, UTType(filenameExtension: "ovpn") ?? .text, UTType(filenameExtension: "conf") ?? .text],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showingExportSheet) {
                ShareSheet(items: [generateExportData()])
            }
            .alert("VPN Config", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear {
            // Sync with TCPForwarderManager
            localPort = String(tcpForwarderManager.localPort)
            remoteHost = tcpForwarderManager.remoteHost
            remotePort = String(tcpForwarderManager.remotePort)
        }
    }
    
    // MARK: - TCP Forwarder Status Card
    @ViewBuilder
    private func TCPForwarderStatusCard() -> some View {
        VStack(spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(tcpForwarderManager.isForwarding ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: tcpForwarderManager.isForwarding ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 24))
                        .foregroundColor(tcpForwarderManager.isForwarding ? .green : .gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tcpForwarderManager.isForwarding ? "TCP Forwarder Active" : "TCP Forwarder Stopped")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(tcpForwarderManager.isForwarding ? "Forwarding connections to VPN" : "Configure and start to forward traffic")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if tcpForwarderManager.isForwarding {
                Divider()
                
                VStack(spacing: 12) {
                    InfoRow(icon: "network", label: "Local Address", value: "\(tcpForwarderManager.localIPAddress):\(tcpForwarderManager.localPort)")
                    InfoRow(icon: "arrow.right", label: "Remote Target", value: "\(tcpForwarderManager.remoteHost):\(tcpForwarderManager.remotePort)")
                    InfoRow(icon: "person.2.fill", label: "Connections", value: "\(tcpForwarderManager.connectedClients)")
                    InfoRow(icon: "arrow.up.arrow.down", label: "Forwarded", value: tcpForwarderManager.formattedForwardedBytes())
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
    
    // MARK: - VPN Endpoint Config Card
    @ViewBuilder
    private func VPNEndpointConfigCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("VPN Endpoint Configuration")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 12) {
                // VPN Type Picker
                HStack {
                    Text("VPN Type")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("VPN Type", selection: $selectedVPNType) {
                        ForEach(VPNConfigGenerator.VPNType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                Divider()
                
                // Remote VPN Host
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remote VPN Server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g., vpn.example.com or 1.2.3.4", text: $remoteHost)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .disabled(tcpForwarderManager.isForwarding)
                }
                
                // Remote VPN Port
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remote VPN Port")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g., 1194", text: $remotePort)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .disabled(tcpForwarderManager.isForwarding)
                }
                
                // Local Forwarding Port
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Forwarding Port")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g., 51821", text: $localPort)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .disabled(tcpForwarderManager.isForwarding)
                }
            }
            
            // Start/Stop Forwarder Button
            Button(action: {
                toggleForwarder()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: tcpForwarderManager.isForwarding ? "stop.fill" : "play.fill")
                    Text(tcpForwarderManager.isForwarding ? "Stop Forwarder" : "Start Forwarder")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tcpForwarderManager.isForwarding ? Color.red : Color.green)
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
    
    // MARK: - Import Config Card
    @ViewBuilder
    private func ImportConfigCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Import VPN Config")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Text("Import an existing OpenVPN (.ovpn) or WireGuard (.conf) config file to automatically extract the endpoint and generate a modified config.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: {
                showingImportPicker = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Config File")
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
            }
            
            if !importedConfig.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Config imported successfully")
                        .font(.caption)
                        .foregroundColor(.green)
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
    
    // MARK: - Generated Config Card
    @ViewBuilder
    private func GeneratedConfigCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text("Generated Config")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                Button(action: {
                    UIPasteboard.general.string = generatedConfig
                    alertMessage = "Config copied to clipboard!"
                    showingAlert = true
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
            }
            
            ScrollView {
                Text(generatedConfig)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            Button(action: {
                showingExportSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Config File")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple)
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
    
    // MARK: - Action Buttons Card
    @ViewBuilder
    private func ActionButtonsCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundColor(.cyan)
                Text("Generate Configs")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Generate from imported config
                if !importedConfig.isEmpty {
                    Button(action: {
                        generateModifiedConfig()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Generate from Imported Config")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.cyan)
                        )
                    }
                }
                
                // Generate template
                Button(action: {
                    generateTemplateConfig()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.gearshape")
                        Text("Generate \(selectedVPNType.rawValue) Template")
                    }
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan, lineWidth: 1)
                    )
                }
                
                // Generate PAC file
                Button(action: {
                    generatePACFile()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text("Generate PAC File (Proxy Auto-Config)")
                    }
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan, lineWidth: 1)
                    )
                }
                
                // Generate simple proxy config
                Button(action: {
                    generateSimpleConfig()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.alignleft")
                        Text("Generate Simple Proxy Config")
                    }
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan, lineWidth: 1)
                    )
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
    
    // MARK: - Helper Methods
    
    private func toggleForwarder() {
        if tcpForwarderManager.isForwarding {
            tcpForwarderManager.stopForwarding()
        } else {
            guard !remoteHost.isEmpty else {
                alertMessage = "Please enter a remote VPN server address"
                showingAlert = true
                return
            }
            
            guard let port = Int(remotePort), port > 0, port <= 65535 else {
                alertMessage = "Please enter a valid remote port (1-65535)"
                showingAlert = true
                return
            }
            
            guard let localP = Int(localPort), localP > 0, localP <= 65535 else {
                alertMessage = "Please enter a valid local port (1-65535)"
                showingAlert = true
                return
            }
            
            tcpForwarderManager.remoteHost = remoteHost
            tcpForwarderManager.remotePort = port
            tcpForwarderManager.localPort = localP
            tcpForwarderManager.startForwarding()
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                importedConfig = content
                
                // Try to parse the config
                if let endpoint = VPNConfigGenerator.parseOpenVPNConfig(content) {
                    remoteHost = endpoint.host
                    remotePort = String(endpoint.port)
                    selectedVPNType = .openVPN
                    alertMessage = "OpenVPN config imported! Endpoint: \(endpoint.host):\(endpoint.port)"
                } else if let endpoint = VPNConfigGenerator.parseWireGuardConfig(content) {
                    remoteHost = endpoint.host
                    remotePort = String(endpoint.port)
                    selectedVPNType = .wireGuard
                    alertMessage = "WireGuard config imported! Endpoint: \(endpoint.host):\(endpoint.port)"
                } else {
                    alertMessage = "Config imported but couldn't parse endpoint. Please enter the VPN server details manually."
                }
                showingAlert = true
                
            } catch {
                alertMessage = "Failed to read config file: \(error.localizedDescription)"
                showingAlert = true
            }
            
        case .failure(let error):
            alertMessage = "Failed to import file: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func generateModifiedConfig() {
        guard !importedConfig.isEmpty else { return }
        
        let localHost = tcpForwarderManager.localIPAddress
        guard let localP = Int(localPort) else { return }
        
        switch selectedVPNType {
        case .openVPN:
            generatedConfig = VPNConfigGenerator.generateOpenVPNConfig(
                originalConfig: importedConfig,
                localHost: localHost,
                localPort: localP
            )
            configFileName = "modified-openvpn"
            
        case .wireGuard:
            generatedConfig = VPNConfigGenerator.generateWireGuardConfig(
                originalConfig: importedConfig,
                localHost: localHost,
                localPort: localP
            )
            configFileName = "modified-wireguard"
        }
    }
    
    private func generateTemplateConfig() {
        let localHost = tcpForwarderManager.localIPAddress
        guard let localP = Int(localPort), let remoteP = Int(remotePort) else { return }
        
        switch selectedVPNType {
        case .openVPN:
            generatedConfig = VPNConfigGenerator.generateOpenVPNTemplate(
                localHost: localHost,
                localPort: localP,
                remoteHost: remoteHost.isEmpty ? "YOUR_VPN_SERVER" : remoteHost,
                remotePort: remoteP
            )
            configFileName = "openvpn-template"
            
        case .wireGuard:
            generatedConfig = VPNConfigGenerator.generateWireGuardTemplate(
                localHost: localHost,
                localPort: localP,
                remoteHost: remoteHost.isEmpty ? "YOUR_VPN_SERVER" : remoteHost,
                remotePort: remoteP
            )
            configFileName = "wireguard-template"
        }
    }
    
    private func generatePACFile() {
        generatedConfig = VPNConfigGenerator.generatePACFile(
            proxyHost: serverManager.ipAddress,
            proxyPort: serverManager.port
        )
        configFileName = "proxy"
    }
    
    private func generateSimpleConfig() {
        let localHost = tcpForwarderManager.localIPAddress
        let localP = Int(localPort) ?? 51821
        let remoteP = Int(remotePort) ?? 1194
        
        generatedConfig = VPNConfigGenerator.generateSimpleProxyConfig(
            proxyHost: serverManager.ipAddress,
            proxyPort: serverManager.port,
            forwarderHost: localHost,
            forwarderPort: localP,
            remoteVPNHost: remoteHost.isEmpty ? nil : remoteHost,
            remoteVPNPort: remoteHost.isEmpty ? nil : remoteP
        )
        configFileName = "proxy-config"
    }
    
    private func generateExportData() -> URL {
        let fileExtension: String
        switch selectedVPNType {
        case .openVPN:
            fileExtension = generatedConfig.contains("FindProxyForURL") ? "pac" : "ovpn"
        case .wireGuard:
            fileExtension = generatedConfig.contains("FindProxyForURL") ? "pac" : "conf"
        }
        
        // For PAC files
        if generatedConfig.contains("FindProxyForURL") {
            configFileName = "proxy"
        }
        
        // For simple text config
        if generatedConfig.contains("SOCKS5 Server Configuration") {
            configFileName = "proxy-config"
        }
        
        let fileName = "\(configFileName).\(generatedConfig.contains("FindProxyForURL") ? "pac" : (generatedConfig.contains("SOCKS5 Server Configuration") ? "txt" : fileExtension))"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try? generatedConfig.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    VPNConfigView()
        .environmentObject(SOCKS5ServerManager())
        .environmentObject(TCPForwarderManager())
}
