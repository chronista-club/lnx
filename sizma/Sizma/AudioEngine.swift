//
//  AudioEngine.swift
//  LNXX
//
//  Created by m.ito on 2025/08/11.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
class AudioEngine: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isLoaded = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.7
    
    private var audioPlayer: AVAudioPlayer?
    private var displayLink: Timer?
    
    override init() {
        super.init()
    }
    
    func loadAudioFile(filename: String = "20250802_160053") {
        guard let url = Bundle.main.url(
            forResource: filename,
            withExtension: "wav",
            subdirectory: "Assets"
        ) else {
            print("オーディオファイルが見つかりません: \(filename).wav")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = volume
            
            duration = audioPlayer?.duration ?? 0
            isLoaded = true
            
            print("オーディオファイルをロードしました: \(filename).wav")
            print("Duration: \(duration) seconds")
            
        } catch {
            print("オーディオファイルのロードに失敗: \(error)")
            isLoaded = false
        }
    }
    
    func play() {
        print("🎵 AudioEngine: play() called")
        guard let player = audioPlayer, isLoaded else {
            print("❌ AudioEngine: オーディオファイルがロードされていません")
            return
        }
        
        if player.play() {
            isPlaying = true
            startTimeUpdate()
            print("✅ AudioEngine: 再生開始")
        } else {
            print("❌ AudioEngine: 再生開始に失敗")
        }
    }
    
    func pause() {
        print("⏸ AudioEngine: pause() called")
        audioPlayer?.pause()
        isPlaying = false
        stopTimeUpdate()
        print("✅ AudioEngine: 一時停止")
    }
    
    func stop() {
        print("⏹ AudioEngine: stop() called")
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimeUpdate()
        print("✅ AudioEngine: 停止")
    }
    
    func togglePlayPause() {
        print("🔄 AudioEngine: togglePlayPause() called - Current state: \(isPlaying ? "Playing" : "Paused")")
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    func setVolume(_ newVolume: Float) {
        volume = newVolume
        audioPlayer?.volume = volume
    }
    
    private func startTimeUpdate() {
        stopTimeUpdate()
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }
        }
    }
    
    private func stopTimeUpdate() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    // 時間のフォーマット
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimeUpdate()
            print("再生完了")
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimeUpdate()
            print("デコードエラー: \(error?.localizedDescription ?? "不明")")
        }
    }
}