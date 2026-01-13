//
//  HelpView.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Introduction
                    IntroSection()
                    
                    // Step-by-step Guide
                    SetupGuideSection()
                    
                    // Router Configuration
                    RouterConfigSection()
                    
                    // Troubleshooting
                    TroubleshootingSection()
                }
                .padding()
            }
            .navigationTitle("Help")
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
}

// MARK: - Intro Section
struct IntroSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("About SOCKS5 Server")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            Text("This app turns your iPhone into a SOCKS5 proxy server, allowing you to improve hotspot speeds by routing traffic through your device. This is particularly useful when sharing your mobile data with other devices through a portable router.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Setup Guide Section
struct SetupGuideSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.number")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("Setup Guide")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                // Step 1
                HelpStepView(
                    stepNumber: 1,
                    icon: "wifi.router",
                    title: "Create WiFi Network",
                    description: "Create a WiFi network from your portable router. Connect to its admin panel and configure the WiFi settings."
                )
                
                // Step 2
                HelpStepView(
                    stepNumber: 2,
                    icon: "iphone",
                    title: "Connect iPhone",
                    description: "Connect your iPhone to the WiFi network you created from the portable router."
                )
                
                // Step 3
                HelpStepView(
                    stepNumber: 3,
                    icon: "gear",
                    title: "Configure WiFi Settings",
                    description: "Go to Settings → WiFi → tap the info (i) button next to your network → under 'Configure IP', set Router field to empty or 0.0.0.0 so mobile data is used for internet."
                )
                
                // Step 4
                HelpStepView(
                    stepNumber: 4,
                    icon: "play.circle.fill",
                    title: "Start SOCKS5 Server",
                    description: "Open this app and tap 'Start Server'. Note the IP address and port displayed."
                )
                
                // Step 5
                HelpStepView(
                    stepNumber: 5,
                    icon: "gearshape.2",
                    title: "Configure Router Proxy",
                    description: "Access your router's admin panel and configure the SOCKS5 proxy settings with the IP and port from this app. The router will now route all traffic through your iPhone's mobile data.",
                    stepColor: .green
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Help Step View
struct HelpStepView: View {
    let stepNumber: Int
    let icon: String
    let title: String
    let description: String
    var stepColor: Color = .blue
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step Number Circle
            ZStack {
                Circle()
                    .fill(stepColor)
                    .frame(width: 32, height: 32)
                Text("\(stepNumber)")
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(stepColor)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Router Configuration Section
struct RouterConfigSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "wifi.router.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("GL.iNet Router Configuration")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("To configure your GL.iNet portable router:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint(text: "Access router admin at 192.168.8.1")
                    BulletPoint(text: "Navigate to Applications → Remote Access")
                    BulletPoint(text: "Enable SOCKS5 Proxy")
                    BulletPoint(text: "Enter the IP and Port from this app")
                    BulletPoint(text: "Save settings and connect devices")
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Bullet Point
struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(.blue)
                .padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Troubleshooting Section
struct TroubleshootingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text("Troubleshooting")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                TroubleshootItem(
                    question: "Server won't start?",
                    answer: "Make sure you're connected to a WiFi network. The server requires a local network to broadcast the proxy."
                )
                
                TroubleshootItem(
                    question: "Devices can't connect?",
                    answer: "Verify the IP address and port are correctly entered in the client device's proxy settings. Make sure all devices are on the same network."
                )
                
                TroubleshootItem(
                    question: "Slow speeds?",
                    answer: "Check your cellular signal strength. The SOCKS5 server forwards all traffic through your mobile data connection."
                )
                
                TroubleshootItem(
                    question: "Connection drops?",
                    answer: "Keep the app open and prevent iPhone from sleeping. Go to Settings → Display & Brightness → Auto-Lock → Never (while using)."
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Troubleshoot Item
struct TroubleshootItem: View {
    let question: String
    let answer: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(answer)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    HelpView()
}
