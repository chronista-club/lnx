//
//  MainView.swift
//  LNXX
//
//  Created by m.ito on 2025/08/11.
//

import SwiftUI

struct MainView: View {
    @State private var selectedTab = "workspace"
    @EnvironmentObject var midiManager: MIDIManager
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        HStack(spacing: 0) {
            // サイドバー
            VStack(alignment: .leading, spacing: 0) {
                Text("LNX")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .padding()
                
                Divider()
                
                VStack(alignment: .leading, spacing: 5) {
                    SidebarButton(
                        icon: "square.grid.2x2",
                        label: "Workspace",
                        isSelected: selectedTab == "workspace",
                        action: { selectedTab = "workspace" }
                    )
                    
                    SidebarButton(
                        icon: "waveform.path",
                        label: "Audio",
                        isSelected: selectedTab == "audio",
                        action: { selectedTab = "audio" }
                    )
                    
                    SidebarButton(
                        icon: "cable.connector",
                        label: "Devices",
                        isSelected: selectedTab == "devices",
                        action: { selectedTab = "devices" }
                    )
                    
                    SidebarButton(
                        icon: "sparkles.tv",
                        label: "Visual",
                        isSelected: selectedTab == "visual",
                        action: { selectedTab = "visual" }
                    )
                    
                    SidebarButton(
                        icon: "arrow.triangle.2.circlepath",
                        label: "Sync",
                        isSelected: selectedTab == "sync",
                        action: { selectedTab = "sync" }
                    )
                }
                .padding()
                
                Spacer()
                
                Divider()
                
                // 設定ボタン
                Button(action: {}) {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("設定")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .frame(width: 200)
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            
            // メインコンテンツエリア
            Group {
                switch selectedTab {
                case "workspace":
                    WorkspaceView()
                case "audio":
                    AudioView()
                        .environmentObject(midiManager)
                        .environmentObject(audioEngine)
                case "devices":
                    DevicesView()
                        .environmentObject(midiManager)
                case "visual":
                    VisualView()
                case "sync":
                    SyncView()
                default:
                    WorkspaceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct SidebarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// プレースホルダービュー
struct WorkspaceView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Workspace")
                .font(.largeTitle)
                .fontWeight(.medium)
            Text("プロジェクトの全体像を管理")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct AudioView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var midiManager: MIDIManager
    @State private var showMIDISettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                VStack(alignment: .leading) {
                    Text("Audio Player")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("20250802_160053.wav")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // MIDI接続状態とBPM表示
                HStack(spacing: 16) {
                    // BPM表示
                    if midiManager.isReceivingClock {
                        HStack(spacing: 4) {
                            Image(systemName: "metronome")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            
                            Text("\(String(format: "%.1f", midiManager.currentBPM)) BPM")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // MIDI接続状態
                    HStack(spacing: 8) {
                        Image(systemName: midiManager.isConnected ? "circle.fill" : "circle")
                            .foregroundColor(midiManager.isConnected ? .green : .gray)
                            .font(.system(size: 10))
                        
                        Text(midiManager.isConnected ? midiManager.connectedDeviceName : "MIDI未接続")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Button("設定") {
                            showMIDISettings.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .padding()
            
            Divider()
            
            // メインコンテンツ
            VStack(spacing: 30) {
                // 波形表示エリア（プレースホルダー）
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(height: 120)
                    .overlay(
                        VStack {
                            Image(systemName: "waveform")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                            if audioEngine.isPlaying {
                                Text("再生中...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                
                // 再生コントロール
                VStack(spacing: 20) {
                    // 時間表示
                    HStack {
                        Text(audioEngine.formatTime(audioEngine.currentTime))
                            .font(.system(.caption, design: .monospaced))
                        
                        Slider(
                            value: Binding(
                                get: { audioEngine.currentTime },
                                set: { audioEngine.seek(to: $0) }
                            ),
                            in: 0...max(audioEngine.duration, 1)
                        )
                        .disabled(!audioEngine.isLoaded)
                        
                        Text(audioEngine.formatTime(audioEngine.duration))
                            .font(.system(.caption, design: .monospaced))
                    }
                    
                    // 再生ボタン
                    HStack(spacing: 20) {
                        Button(action: {
                            audioEngine.stop()
                        }) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled(!audioEngine.isLoaded)
                        
                        Button(action: {
                            audioEngine.togglePlayPause()
                        }) {
                            Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.largeTitle)
                                .frame(width: 60, height: 60)
                                .background(audioEngine.isLoaded ? Color.accentColor : Color.gray)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!audioEngine.isLoaded)
                    }
                    
                    // ボリューム
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        
                        Slider(value: $audioEngine.volume, in: 0...1) { _ in
                            audioEngine.setVolume(audioEngine.volume)
                        }
                        .frame(maxWidth: 200)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // MIDI パッド表示
                VStack(alignment: .leading, spacing: 10) {
                    Text("LPD8 パッドマッピング")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 10) {
                        ForEach(1...8, id: \.self) { padNumber in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(padActivated(padNumber) ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Text("PAD\n\(padNumber)")
                                            .font(.system(size: 10))
                                            .multilineTextAlignment(.center)
                                            .foregroundColor(padActivated(padNumber) ? .white : .primary)
                                    )
                                
                                Text(padFunction(padNumber))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
            .padding()
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            setupMIDI()
            // AudioEngineは既にApp起動時に初期化済み
            // MIDI機器一覧も既に表示済み
        }
        .sheet(isPresented: $showMIDISettings) {
            MIDISettingsView()
                .environmentObject(midiManager)
        }
    }
    
    private func setupMIDI() {
        // MIDIコールバックを設定
        midiManager.onNoteOn = { note, velocity in
            handleMIDINoteOn(note: note, velocity: velocity)
        }
        
        midiManager.onNoteOff = { note in
            handleMIDINoteOff(note: note)
        }
    }
    
    private func handleMIDINoteOn(note: UInt8, velocity: UInt8) {
        print("📱 AudioView: handleMIDINoteOn - Note: \(note), Velocity: \(velocity)")
        
        // LPD8のパッド1 (Note 36) で再生/一時停止
        if note == MIDIManager.LPD8Pad.pad1.rawValue {
            print("   → PAD 1 triggered - Toggling Play/Pause")
            audioEngine.togglePlayPause()
        }
        // パッド2 (Note 37) で停止
        else if note == MIDIManager.LPD8Pad.pad2.rawValue {
            print("   → PAD 2 triggered - Stopping")
            audioEngine.stop()
        } else {
            print("   → Unmapped note: \(note)")
        }
    }
    
    private func handleMIDINoteOff(note: UInt8) {
        print("📱 AudioView: handleMIDINoteOff - Note: \(note)")
        // Note Offイベントの処理（必要に応じて）
    }
    
    private func padActivated(_ padNumber: Int) -> Bool {
        guard padNumber >= 1 && padNumber <= 8 else { return false }
        // LPD8のパッド: PAD1=36, PAD2=37, ... PAD8=43
        let noteNumber = UInt8(36 + padNumber - 1)
        return midiManager.lastReceivedNote == noteNumber && midiManager.lastReceivedVelocity > 0
    }
    
    private func padFunction(_ padNumber: Int) -> String {
        switch padNumber {
        case 1: return "Play/Pause"
        case 2: return "Stop"
        case 3...8: return "-"
        default: return ""
        }
    }
}

// MIDI設定ビュー
struct MIDISettingsView: View {
    @EnvironmentObject var midiManager: MIDIManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = "status"
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("MIDI設定")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            
            // タブ
            Picker("", selection: $selectedTab) {
                Text("接続状態").tag("status")
                Text("デバイス一覧").tag("devices")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // タブコンテンツ
            Group {
                if selectedTab == "status" {
                    // 接続状態タブ
                    VStack(alignment: .leading, spacing: 12) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("接続状態:")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Label(
                                        midiManager.isConnected ? "接続済み" : "未接続",
                                        systemImage: midiManager.isConnected ? "checkmark.circle.fill" : "xmark.circle"
                                    )
                                    .foregroundColor(midiManager.isConnected ? .green : .red)
                                }
                                
                                if midiManager.isConnected {
                                    Divider()
                                    
                                    HStack {
                                        Text("デバイス:")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(midiManager.connectedDeviceName)
                                            .fontWeight(.medium)
                                    }
                                }
                            }
                        }
                        
                        // MIDI情報セクション
                        if midiManager.isConnected {
                            GroupBox("MIDI情報") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("最後のノート:")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(midiManager.lastReceivedNote)")
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    
                                    HStack {
                                        Text("ベロシティ:")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(midiManager.lastReceivedVelocity)")
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    
                                    HStack {
                                        Text("MIDI Clock:")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if midiManager.isReceivingClock {
                                            HStack(spacing: 4) {
                                                Image(systemName: "metronome")
                                                    .foregroundColor(.orange)
                                                    .font(.system(size: 12))
                                                Text("\(String(format: "%.1f", midiManager.currentBPM)) BPM")
                                                    .foregroundColor(.orange)
                                                    .font(.system(.body, design: .monospaced))
                                            }
                                        } else {
                                            Text("受信なし")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // デバイス一覧タブ
                    VStack(alignment: .leading, spacing: 12) {
                        GroupBox {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    if midiManager.availableDevices.isEmpty {
                                        HStack {
                                            Spacer()
                                            VStack(spacing: 10) {
                                                Image(systemName: "pianokeys")
                                                    .font(.system(size: 40))
                                                    .foregroundStyle(.tertiary)
                                                Text("MIDIデバイスが検出されていません")
                                                    .foregroundStyle(.secondary)
                                                Button("スキャン") {
                                                    midiManager.listAllMIDIDevices()
                                                }
                                                .buttonStyle(.borderedProminent)
                                            }
                                            .padding(.vertical, 30)
                                            Spacer()
                                        }
                                    } else {
                                        ForEach(midiManager.availableDevices, id: \.self) { device in
                                            HStack {
                                                Text(device)
                                                    .font(.system(.body, design: .default))
                                                Spacer()
                                                if midiManager.connectedDeviceName.contains(
                                                    device.replacingOccurrences(of: "📥 入力: ", with: "")
                                                        .replacingOccurrences(of: "📤 出力: ", with: "")
                                                ) {
                                                    Label("接続中", systemImage: "checkmark.circle.fill")
                                                        .font(.caption)
                                                        .foregroundColor(.green)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                            
                                            if device != midiManager.availableDevices.last {
                                                Divider()
                                            }
                                        }
                                    }
                                }
                                .padding()
                            }
                            .frame(minHeight: 200, maxHeight: 300)
                        }
                        
                        HStack {
                            Button("更新") {
                                midiManager.listAllMIDIDevices()
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Text("デバイス数: \(midiManager.availableDevices.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .frame(minWidth: 400)
            
            Spacer()
            
            // アクションボタン
            HStack(spacing: 10) {
                if selectedTab == "status" {
                    Button("デバイスを再スキャン") {
                        midiManager.rescanDevices()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Divider()
            
            Button("閉じる") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.bottom)
        }
        .frame(minWidth: 450, minHeight: 400)
        .fixedSize(horizontal: false, vertical: true)  // 垂直方向のみ内容に合わせる
        .onAppear {
            // 初回表示時にデバイス一覧を取得
            midiManager.listAllMIDIDevices()
        }
    }
}

// デバイス管理ビュー
struct DevicesView: View {
    @EnvironmentObject var midiManager: MIDIManager
    @State private var selectedDevice: String? = nil
    @State private var showDetail = false
    @State private var selectedCategory = "all"
    
    var body: some View {
        HStack(spacing: 0) {
            // デバイスリスト（左側）
            VStack(alignment: .leading, spacing: 0) {
                // ヘッダー
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("External Devices")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: {
                            midiManager.listAllMIDIDevices()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // カテゴリーフィルター
                    Picker("", selection: $selectedCategory) {
                        Text("すべて").tag("all")
                        Text("MIDI").tag("midi")
                        Text("オーディオ").tag("audio")
                        Text("ビデオ").tag("video")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding()
                
                Divider()
                
                // デバイスリスト
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        // MIDIカテゴリ
                        if selectedCategory == "all" || selectedCategory == "midi" {
                            let midiDevices = midiManager.deviceInfoList.filter { 
                                $0.type == .midiInput || $0.type == .midiOutput 
                            }
                            DeviceCategorySection(
                                title: "MIDI Controllers",
                                icon: "pianokeys",
                                devices: midiDevices,
                                midiManager: midiManager,
                                selectedDevice: $selectedDevice,
                                showDetail: $showDetail
                            )
                        }
                        
                        // オーディオカテゴリ（将来の拡張用）
                        if selectedCategory == "all" || selectedCategory == "audio" {
                            let audioDevices = midiManager.deviceInfoList.filter { 
                                $0.type == .audioInput || $0.type == .audioOutput 
                            }
                            DeviceCategorySection(
                                title: "Audio Interfaces",
                                icon: "waveform",
                                devices: audioDevices,
                                midiManager: midiManager,
                                selectedDevice: $selectedDevice,
                                showDetail: $showDetail
                            )
                        }
                        
                        // ビデオカテゴリ（将来の拡張用）
                        if selectedCategory == "all" || selectedCategory == "video" {
                            let videoDevices = midiManager.deviceInfoList.filter { 
                                $0.type == .video
                            }
                            DeviceCategorySection(
                                title: "Video Devices",
                                icon: "video",
                                devices: videoDevices,
                                midiManager: midiManager,
                                selectedDevice: $selectedDevice,
                                showDetail: $showDetail
                            )
                        }
                        
                        if midiManager.availableDevices.isEmpty && selectedCategory == "midi" {
                            VStack(spacing: 20) {
                                Image(systemName: "cable.connector")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.tertiary)
                                Text("デバイスが検出されていません")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text("デバイスを接続してスキャンボタンを押してください")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Button("デバイスをスキャン") {
                                    midiManager.listAllMIDIDevices()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(40)
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // フッター
                HStack {
                    Text("\(midiManager.availableDevices.count) devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if midiManager.isConnected {
                        Label("Connected", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(width: 280)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 詳細パネル（右側）
            VStack(alignment: .leading, spacing: 0) {
                if showDetail, let device = selectedDevice {
                    // デバイス詳細ヘッダー
                    VStack(alignment: .leading, spacing: 10) {
                        Text(device.replacingOccurrences(of: "📥 入力: ", with: "")
                            .replacingOccurrences(of: "📤 出力: ", with: ""))
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 20) {
                            Label(
                                device.contains("📥") ? "Input Device" : "Output Device",
                                systemImage: device.contains("📥") ? "arrow.down.circle" : "arrow.up.circle"
                            )
                            .foregroundStyle(.secondary)
                            
                            if midiManager.connectedDeviceName.contains(
                                device.replacingOccurrences(of: "📥 入力: ", with: "")
                                    .replacingOccurrences(of: "📤 出力: ", with: "")
                            ) {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding()
                    
                    Divider()
                    
                    // MIDI情報パネル
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // リアルタイムステータス
                            GroupBox("リアルタイム情報") {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("最後のノート:")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(midiManager.lastReceivedNote)")
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    
                                    HStack {
                                        Text("ベロシティ:")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(midiManager.lastReceivedVelocity)")
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    
                                    HStack {
                                        Text("MIDI Clock:")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if midiManager.isReceivingClock {
                                            HStack(spacing: 4) {
                                                Image(systemName: "metronome")
                                                    .foregroundColor(.orange)
                                                Text("\(String(format: "%.1f", midiManager.currentBPM)) BPM")
                                                    .foregroundColor(.orange)
                                                    .font(.system(.body, design: .monospaced))
                                            }
                                        } else {
                                            Text("クロックなし")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                            
                            // アクション
                            GroupBox("アクション") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Button("デバイスを再スキャン") {
                                        midiManager.rescanDevices()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    
                                    Button("Keystage接続テスト") {
                                        midiManager.testKeystageConnection()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!device.lowercased().contains("keystage"))
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    // デバイス未選択時
                    VStack(spacing: 20) {
                        Image(systemName: "pianokeys")
                            .font(.system(size: 80))
                            .foregroundStyle(.tertiary)
                        Text("デバイスを選択してください")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("左側のリストからMIDIデバイスを選択すると\n詳細情報が表示されます")
                            .multilineTextAlignment(.center)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            // 初回表示時にデバイスリストを更新
            midiManager.listAllMIDIDevices()
        }
    }
}

// デバイスカテゴリーセクション
struct DeviceCategorySection: View {
    let title: String
    let icon: String
    let devices: [DeviceInfo]
    let midiManager: MIDIManager
    @Binding var selectedDevice: String?
    @Binding var showDetail: Bool
    
    var body: some View {
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                // カテゴリーヘッダー
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(devices.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.tertiaryLabelColor).opacity(0.1))
                        .cornerRadius(4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                
                // デバイスリスト
                ForEach(devices) { device in
                    DeviceRowWithToggle(
                        device: device,
                        isSelected: selectedDevice == device.name,
                        midiManager: midiManager
                    ) {
                        selectedDevice = device.name
                        showDetail = true
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }
}

// トグル付きデバイス行
struct DeviceRowWithToggle: View {
    let device: DeviceInfo
    let isSelected: Bool
    let midiManager: MIDIManager
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                // デバイスアイコン
                Image(systemName: device.type == .midiInput ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundColor(device.isEnabled ? 
                        (device.type == .midiInput ? .blue : .green) : .gray)
                    .opacity(device.isEnabled ? 1.0 : 0.5)
                
                // デバイス名
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundColor(device.isEnabled ? .primary : .secondary)
                    
                    Text(device.type == .midiInput ? "Input" : "Output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(device.isEnabled ? 1.0 : 0.6)
                }
                
                Spacer()
                
                // 接続状態
                if device.isConnected && device.isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                // Enable/Disableトグル
                Toggle("", isOn: Binding(
                    get: { device.isEnabled },
                    set: { _ in
                        midiManager.toggleDeviceEnabled(device.name)
                    }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// デバイスリストの行（旧版、互換性のため残す）
struct DeviceRow: View {
    let device: String
    let isSelected: Bool
    let isConnected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: device.contains("📥") ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundColor(device.contains("📥") ? .blue : .green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.replacingOccurrences(of: "📥 入力: ", with: "")
                        .replacingOccurrences(of: "📤 出力: ", with: ""))
                        .font(.system(size: 13))
                        .lineLimit(1)
                    
                    Text(device.contains("📥") ? "Input" : "Output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct VisualView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Visual")
                .font(.largeTitle)
                .fontWeight(.medium)
            Text("ビジュアルエフェクト")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SyncView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Sync")
                .font(.largeTitle)
                .fontWeight(.medium)
            Text("音声と映像の同期")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    MainView()
}