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

class BackgroundManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    private var locationManager: CLLocationManager?
    private var audioPlayer: AVAudioPlayer?
    private var silentAudioTimer: Timer?
    private var currentMethod: BackgroundAwakeMethod = .none
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupLocationManager()
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
    func startBackgroundMethod(_ method: BackgroundAwakeMethod) {
        // Stop any existing method first
        stopBackgroundMethod()
        
        currentMethod = method
        
        switch method {
        case .location:
            startLocationUpdates()
        case .audio:
            startSilentAudio()
        case .none:
            break
        }
    }
    
    /// Stop the current background method
    func stopBackgroundMethod() {
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
