//
//  BackgroundManager.swift
//  SOCKS5Server
//
//  Created by SOCKS5 Team
//

import Foundation
import CoreLocation
import AVFoundation
import Combine
import UIKit
import ActivityKit
import UserNotifications

class BackgroundManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var notificationPermissionGranted: Bool = false
    
    // MARK: - Private Properties
    private var locationManager: CLLocationManager?
    private var audioPlayer: AVAudioPlayer?
    private var silentAudioTimer: Timer?
    private var currentMethod: BackgroundAwakeMethod = .none
    private var cancellables = Set<AnyCancellable>()
    
    // Live Activity for Dynamic Island
    private var currentActivity: Activity<ProxyActivityAttributes>?
    
    override init() {
        super.init()
        setupLocationManager()
        setupNotifications()
    }
    
    // MARK: - Notification Setup
    private func setupNotifications() {
        // Check current notification permission status
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationPermissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }
    
    /// Request notification permission (called automatically when location method is selected)
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.notificationPermissionGranted = granted
                if let error = error {
                    print("BackgroundManager: Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Location Manager Setup
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager?.distanceFilter = 1000 // 1km minimum distance for updates
        locationManager?.pausesLocationUpdatesAutomatically = false
        
        // Get initial authorization status
        locationAuthorizationStatus = locationManager?.authorizationStatus ?? .notDetermined
    }
    
    // MARK: - Public Methods
    
    /// Request location permission from the user
    func requestLocationPermission() {
        locationManager?.requestAlwaysAuthorization()
    }
    
    /// Start the specified background method
    /// - Parameters:
    ///   - method: The background awake method to use
    ///   - ipAddress: Optional IP address for Live Activity (location mode)
    ///   - port: Optional port for Live Activity (location mode)
    func startBackgroundMethod(_ method: BackgroundAwakeMethod, ipAddress: String? = nil, port: Int? = nil) {
        // Stop any existing method first
        stopBackgroundMethod()
        
        currentMethod = method
        
        switch method {
        case .location:
            // Request notification permission automatically for location mode
            requestNotificationPermission()
            startLocationUpdates()
            // Start Live Activity for Dynamic Island if IP and port are provided
            if let ip = ipAddress, let p = port {
                startLiveActivity(ipAddress: ip, port: p)
            }
        case .audio:
            startSilentAudio()
        case .none:
            break
        }
    }
    
    /// Stop the current background method
    /// - Parameter sendNotification: Whether to send a disconnection notification (default: false)
    func stopBackgroundMethod(sendNotification: Bool = false) {
        // End Live Activity if it was running
        endLiveActivity()
        
        // Send disconnection notification if requested and location method was active
        if sendNotification && currentMethod == .location {
            sendDisconnectionNotification()
        }
        
        stopLocationUpdates()
        stopSilentAudio()
        currentMethod = .none
    }
    
    /// Check if location services are available and authorized
    func isLocationAuthorized() -> Bool {
        let status = locationManager?.authorizationStatus ?? .notDetermined
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }
    
    // MARK: - Location Updates
    
    private func startLocationUpdates() {
        guard isLocationAuthorized() else {
            // Request permission if not authorized
            requestLocationPermission()
            return
        }
        
        // Enable background location updates only when starting location updates
        // This is safe because we've verified authorization and background modes are in Info.plist
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.startUpdatingLocation()
        print("BackgroundManager: Started location updates for background mode")
    }
    
    private func stopLocationUpdates() {
        locationManager?.stopUpdatingLocation()
        locationManager?.allowsBackgroundLocationUpdates = false
        print("BackgroundManager: Stopped location updates")
    }
    
    // MARK: - Silent Audio
    
    private func startSilentAudio() {
        // Configure audio session for background playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("BackgroundManager: Failed to configure audio session: \(error)")
            return
        }
        
        // Create silent audio player
        setupSilentAudioPlayer()
        
        // Play silent audio
        audioPlayer?.play()
        
        // Set up timer to ensure audio keeps playing (check every 15 seconds to save battery)
        silentAudioTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.ensureAudioPlaying()
        }
        
        print("BackgroundManager: Started silent audio for background mode")
    }
    
    private func setupSilentAudioPlayer() {
        // Generate silent audio data (1 second of silence at 44100 Hz, 16-bit)
        let sampleRate = 44100.0
        let duration = 1.0
        let numSamples = Int(sampleRate * duration)
        
        // Create WAV header and silent audio data
        var wavData = Data()
        
        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        let fileSize = UInt32(36 + numSamples * 2)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // audio format (PCM)
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // num channels
        wavData.append(withUnsafeBytes(of: UInt32(44100).littleEndian) { Data($0) }) // sample rate
        wavData.append(withUnsafeBytes(of: UInt32(88200).littleEndian) { Data($0) }) // byte rate
        wavData.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) }) // block align
        wavData.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // bits per sample
        
        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(withUnsafeBytes(of: UInt32(numSamples * 2).littleEndian) { Data($0) })
        
        // Silent audio samples (zeros)
        let silentSamples = Data(count: numSamples * 2)
        wavData.append(silentSamples)
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = 0.0 // Completely silent
            audioPlayer?.prepareToPlay()
        } catch {
            print("BackgroundManager: Failed to create audio player: \(error)")
        }
    }
    
    private func ensureAudioPlaying() {
        if currentMethod == .audio && !(audioPlayer?.isPlaying ?? false) {
            audioPlayer?.play()
        }
    }
    
    private func stopSilentAudio() {
        silentAudioTimer?.invalidate()
        silentAudioTimer = nil
        
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("BackgroundManager: Failed to deactivate audio session: \(error)")
        }
        
        print("BackgroundManager: Stopped silent audio")
    }
    
    // MARK: - Live Activity (Dynamic Island) for Location Mode
    
    /// Start Live Activity for Dynamic Island navigation-style display
    /// - Parameters:
    ///   - ipAddress: The IP address of the proxy server
    ///   - port: The port of the proxy server
    ///   - connectedClients: Number of connected clients
    func startLiveActivity(ipAddress: String, port: Int, connectedClients: Int = 0) {
        // Only start if location method is active and Live Activities are supported
        guard currentMethod == .location else { return }
        
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                print("BackgroundManager: Live Activities not enabled")
                return
            }
            
            // End any existing activity first
            endLiveActivity()
            
            let attributes = ProxyActivityAttributes(serverName: "SOCKS5 Proxy")
            let statusText = connectedClients > 0 ? "\(connectedClients) client\(connectedClients == 1 ? "" : "s")" : "Active"
            let contentState = ProxyActivityAttributes.ContentState(
                isActive: true,
                statusText: statusText,
                ipAddress: ipAddress,
                port: port
            )
            
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: contentState, staleDate: nil),
                    pushType: nil
                )
                currentActivity = activity
                print("BackgroundManager: Started Live Activity with ID: \(activity.id)")
            } catch {
                print("BackgroundManager: Failed to start Live Activity: \(error.localizedDescription)")
            }
        }
    }
    
    /// Update the Live Activity with new status
    /// - Parameters:
    ///   - ipAddress: The IP address of the proxy server
    ///   - port: The port of the proxy server
    ///   - connectedClients: Number of connected clients
    ///   - isActive: Whether the server is still active
    func updateLiveActivity(ipAddress: String, port: Int, connectedClients: Int, isActive: Bool = true) {
        if #available(iOS 16.1, *) {
            guard let activity = currentActivity else { return }
            
            let statusText = isActive ? (connectedClients > 0 ? "\(connectedClients) client\(connectedClients == 1 ? "" : "s")" : "Active") : "Disconnected"
            let contentState = ProxyActivityAttributes.ContentState(
                isActive: isActive,
                statusText: statusText,
                ipAddress: ipAddress,
                port: port
            )
            
            Task {
                await activity.update(using: contentState)
            }
        }
    }
    
    /// End the current Live Activity
    func endLiveActivity() {
        if #available(iOS 16.1, *) {
            guard let activity = currentActivity else { return }
            
            let finalState = ProxyActivityAttributes.ContentState(
                isActive: false,
                statusText: "Stopped",
                ipAddress: "—",
                port: 0
            )
            
            Task {
                await activity.end(using: finalState, dismissalPolicy: .immediate)
                await MainActor.run {
                    self.currentActivity = nil
                }
                print("BackgroundManager: Ended Live Activity")
            }
        }
    }
    
    // MARK: - Disconnection Notification
    
    /// Send a notification when the proxy server disconnects or stops
    /// - Parameter reason: Optional reason for the disconnection
    func sendDisconnectionNotification(reason: String? = nil) {
        guard notificationPermissionGranted else {
            // Request permission if not granted yet
            requestNotificationPermission()
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "SOCKS5 Proxy Stopped"
        content.body = reason ?? "The proxy server has been disconnected."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        
        let request = UNNotificationRequest(
            identifier: "proxy-disconnection-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("BackgroundManager: Failed to send disconnection notification: \(error.localizedDescription)")
            } else {
                print("BackgroundManager: Sent disconnection notification")
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension BackgroundManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // We don't need to process location data, just receiving updates keeps the app alive
        // Minimal logging to reduce overhead
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("BackgroundManager: Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            self?.locationAuthorizationStatus = manager.authorizationStatus
            
            // If we're supposed to be using location and just got authorized, start updates
            if self?.currentMethod == .location && (manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse) {
                self?.startLocationUpdates()
            }
        }
    }
}
