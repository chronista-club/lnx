//
//  SizmaApp.swift
//  Sizma
//
//  Created by m.ito on 2025/08/03.
//

import SwiftUI

@main
struct SizmaApp: App {
    @StateObject private var midiManager = MIDIManager()
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var audioGraphManager = AudioGraphManager()
    
    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(midiManager)
                .environmentObject(audioEngine)
                .environmentObject(audioGraphManager)
                .onAppear {
                    // アプリ起動時の初期化
                    setupApplication()
                }
        }
    }
    
    private func setupApplication() {
        print("🚀 Sizma (静馬) Application Starting...")
        print("════════════════════════════════════════")
        print("Version: 1.0.0")
        print("Platform: macOS")
        print("════════════════════════════════════════")
        
        // オーディオエンジンの初期化
        print("\n🎵 Initializing Audio Engine...")
        audioEngine.loadAudioFile()
        
        // MIDIマネージャーは既にinitで初期化されているので
        // 接続状態の確認のみ
        print("\n📱 MIDI System Status:")
        if midiManager.isConnected {
            print("✅ Connected to: \(midiManager.connectedDeviceName)")
            
            // Keystage接続時の診断
            if midiManager.connectedDeviceName.lowercased().contains("keystage") {
                print("\n🎹 Korg Keystage Connection Test:")
                print("   1. Press any key on Keystage")
                print("   2. Move the modulation wheel")
                print("   3. Press the sustain pedal")
                print("   4. Check console for MIDI events")
                print("\n   If no events appear:")
                print("   - Check USB connection")
                print("   - Verify Keystage is powered on")
                print("   - Try disconnecting and reconnecting")
                
                // 接続テストを実行
                midiManager.testKeystageConnection()
            }
        } else {
            print("⏳ Waiting for MIDI device connection...")
            print("   Supported devices: Korg Keystage (preferred), Akai LPD8")
        }
        
        print("\n════════════════════════════════════════")
        print("🎹 Ready for performance!")
        print("════════════════════════════════════════\n")
    }
}
