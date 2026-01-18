# SOCKS5 Server for iOS

A clean and intuitive iOS app that turns your iPhone into a SOCKS5 proxy server, allowing you to improve hotspot speeds by routing traffic through your device's mobile data connection.

![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-green.svg)
![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)

## ✨ Features

- **Native SOCKS5 Server**: Full implementation of the SOCKS5 protocol
- **Clean SwiftUI Interface**: Modern, intuitive design with live statistics
- **One-Tap Control**: Start/Stop server with a single tap
- **Auto IP Detection**: Automatically detects your local network IP
- **Live Data Stats**: Real-time upload/download speed monitoring in Mbps
- **Auto-Start Option**: Optionally start the server automatically when the app opens
- **Background Modes**: Multiple options to keep the app active (Location, Silent Audio)
- **Comprehensive Help Menu**: Step-by-step setup guide with GL.iNet router instructions
- **Copy Configuration**: Easy copy of proxy settings to clipboard

### 🆕 VPN Configuration Features

- **TCP Forwarding**: Forward TCP connections to remote VPN servers (similar to socat)
- **VPN Config Import**: Import existing OpenVPN (.ovpn) or WireGuard (.conf) files
- **Config Generation**: Generate modified VPN configs pointing to local forwarder
- **PAC File Generation**: Create Proxy Auto-Config files for browser configuration
- **Export & Share**: Export generated configs to use on PC or other devices

## 📱 Screenshots

The app features a clean, card-based interface with:
- Server status display (running/stopped indicator)
- IP address and port information
- Live upload/download statistics (Mbps)
- Configuration options
- Start/Stop control button
- Settings page for auto-start and background options
- Help menu with setup instructions

## 🚀 How to Use

### Setup Guide

1. **Create WiFi Network**
   - Create a WiFi network from your portable router (e.g., GL.iNet)
   - Connect to its admin panel and configure WiFi settings

2. **Connect iPhone**
   - Connect your iPhone to the WiFi network created by the router

3. **Configure WiFi Settings**
   - Go to Settings → WiFi → tap (i) next to your network
   - Under 'Configure IP', set Router field to empty or 0.0.0.0
   - This ensures mobile data is used for internet

4. **Start SOCKS5 Server**
   - Open the SOCKS5 Server app
   - Tap 'Start Server'
   - Note the IP address and port displayed

5. **Configure Router Proxy**
   - Access your router's admin panel (typically 192.168.8.1 for GL.iNet)
   - Navigate to Applications → Remote Access → SOCKS5 Proxy
   - Enter the IP and Port from the app
   - Save settings

### GL.iNet Router Configuration

For GL.iNet portable routers:
- Access router admin at `192.168.8.1`
- Navigate to **Applications → Remote Access**
- Enable **SOCKS5 Proxy**
- Enter the IP and Port from this app
- Save settings and connect devices

### VPN Configuration (TCP Forwarding)

Use the VPN Configuration feature to route VPN traffic through your iPhone's cellular connection:

1. **Open VPN Config**
   - Tap the "Configure VPN" button on the main screen

2. **Configure VPN Endpoint**
   - Enter your VPN server address (e.g., `vpn.example.com`)
   - Enter the VPN server port (e.g., `1194` for OpenVPN)
   - Set a local forwarding port (e.g., `51821`)

3. **Start TCP Forwarder**
   - Tap "Start Forwarder" to begin forwarding connections

4. **Generate Config**
   - Import your existing VPN config file, OR
   - Generate a template config
   - The app will create a modified config pointing to your iPhone's IP

5. **Use on PC**
   - Export the generated config
   - Use it in your VPN client on PC
   - Connect to your VPN through your iPhone!

**Note:** WireGuard uses UDP and requires wrapping with wstunnel or similar tools for TCP forwarding.

## 🛠️ Building the App

### Prerequisites

- Xcode 15.0 or later
- macOS Sonoma or later
- iOS 16.0+ deployment target

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/Sohday677/SOCKS.git
   cd SOCKS/SOCKS5Server
   ```

2. Open in Xcode:
   ```bash
   open SOCKS5Server.xcodeproj
   ```

3. Build and run on your device or simulator

### Using GitHub Actions

You can also build the IPA directly using GitHub Actions:

1. Go to **Actions** tab
2. Select **Build SOCKS5 Server IPA**
3. Click **Run workflow**
4. Configure options:
   - App Name
   - Bundle ID
   - Output options (Artifact, Catbox, Draft Release)
5. Download the built IPA

## 📦 Installation

You can install the IPA using:
- **AltStore** - Recommended for most users
- **Sideloadly** - Alternative sideloading tool
- **TrollStore** - If available on your iOS version

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| Server won't start | Ensure you're connected to a WiFi network |
| Devices can't connect | Verify IP and port are correct; check all devices are on same network |
| Slow speeds | Check cellular signal strength |
| Connection drops | Keep app open; disable auto-lock while using |

## 📁 Project Structure

```
SOCKS5Server/
├── SOCKS5Server.xcodeproj/
├── SOCKS5Server/
│   ├── SOCKS5ServerApp.swift    # App entry point
│   ├── Info.plist               # App configuration
│   ├── Views/
│   │   ├── ContentView.swift    # Main UI
│   │   ├── HelpView.swift       # Help menu
│   │   ├── SettingsView.swift   # Settings page
│   │   └── VPNConfigView.swift  # VPN configuration UI
│   ├── Server/
│   │   ├── SOCKS5ServerManager.swift  # SOCKS5 implementation
│   │   ├── SettingsManager.swift      # App settings
│   │   ├── BackgroundManager.swift    # Background mode handling
│   │   ├── TCPForwarderManager.swift  # TCP forwarding (socat-like)
│   │   └── VPNConfigGenerator.swift   # VPN config generation
│   └── Assets.xcassets/         # App assets
└── README.md
```

## 🔄 GitHub Actions Workflows

- **build.yml** - Builds the iOS IPA
- **delete-old-draft-releases.yml** - Cleans up old draft releases
- **delete-old-workflows-run.yml** - Cleans up old workflow runs

## 📄 License

This project is available under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
