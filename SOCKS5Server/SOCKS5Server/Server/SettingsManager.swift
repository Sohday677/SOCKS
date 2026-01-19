//
//  SettingsManager.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import Foundation
import Combine

enum ProxyType: String, CaseIterable, Identifiable {
    case socks5 = "SOCKS5"
    case http = "HTTP"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .socks5:
            return "SOCKS5 protocol - Full proxy support for TCP and UDP connections."
        case .http:
            return "HTTP protocol - Proxy for HTTP/HTTPS web traffic."
        }
    }
    
    var icon: String {
        switch self {
        case .socks5:
            return "network"
        case .http:
            return "globe"
        }
    }
}

enum BackgroundAwakeMethod: String, CaseIterable, Identifiable {
    case location = "Location"
    case audio = "Silent Audio"
    case none = "None"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .location:
            return "Uses location services to keep the app active. Most reliable but uses more battery."
        case .audio:
            return "Plays silent audio to prevent the app from being suspended. Lower battery usage."
        case .none:
            return "No background method. App may be suspended when in background."
        }
    }
    
    var icon: String {
        switch self {
        case .location:
            return "location.fill"
        case .audio:
            return "speaker.wave.2.fill"
        case .none:
            return "moon.fill"
        }
    }
}

class SettingsManager: ObservableObject {
    // MARK: - Keys
    private enum Keys {
        static let autoStartServer = "autoStartServer"
        static let backgroundAwakeMethod = "backgroundAwakeMethod"
        static let proxyType = "proxyType"
    }
    
    // MARK: - Published Properties
    @Published var autoStartServer: Bool {
        didSet {
            UserDefaults.standard.set(autoStartServer, forKey: Keys.autoStartServer)
        }
    }
    
    @Published var backgroundAwakeMethod: BackgroundAwakeMethod {
        didSet {
            UserDefaults.standard.set(backgroundAwakeMethod.rawValue, forKey: Keys.backgroundAwakeMethod)
        }
    }
    
    @Published var proxyType: ProxyType {
        didSet {
            UserDefaults.standard.set(proxyType.rawValue, forKey: Keys.proxyType)
        }
    }
    
    // MARK: - Initialization
    init() {
        // Set defaults if not set
        if UserDefaults.standard.object(forKey: Keys.autoStartServer) == nil {
            UserDefaults.standard.set(true, forKey: Keys.autoStartServer)
        }
        if UserDefaults.standard.object(forKey: Keys.backgroundAwakeMethod) == nil {
            UserDefaults.standard.set(BackgroundAwakeMethod.audio.rawValue, forKey: Keys.backgroundAwakeMethod)
        }
        if UserDefaults.standard.object(forKey: Keys.proxyType) == nil {
            UserDefaults.standard.set(ProxyType.socks5.rawValue, forKey: Keys.proxyType)
        }
        
        // Load settings
        self.autoStartServer = UserDefaults.standard.bool(forKey: Keys.autoStartServer)
        
        let methodString = UserDefaults.standard.string(forKey: Keys.backgroundAwakeMethod) ?? BackgroundAwakeMethod.audio.rawValue
        self.backgroundAwakeMethod = BackgroundAwakeMethod(rawValue: methodString) ?? .audio
        
        let proxyTypeString = UserDefaults.standard.string(forKey: Keys.proxyType) ?? ProxyType.socks5.rawValue
        self.proxyType = ProxyType(rawValue: proxyTypeString) ?? .socks5
    }
}
