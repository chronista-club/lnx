//
//  MIDIManager.swift
//  LNXX
//
//  Created by m.ito on 2025/08/11.
//

import Foundation
import CoreMIDI
import SwiftUI

// デバイス情報構造体
struct DeviceInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: DeviceType
    var isEnabled: Bool = true
    var isConnected: Bool = false
    
    enum DeviceType {
        case midiInput
        case midiOutput
        case audioInput
        case audioOutput
        case video
    }
}

class MIDIManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectedDeviceName = ""
    @Published var lastReceivedNote: UInt8 = 0
    @Published var lastReceivedVelocity: UInt8 = 0
    @Published var currentBPM: Double = 0.0
    @Published var isReceivingClock = false
    @Published var availableDevices: [String] = []
    @Published var deviceInfoList: [DeviceInfo] = []
    
    // デバイスの有効/無効状態を管理
    private var disabledDevices: Set<String> = []
    
    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var inputPortMIDI2: MIDIPortRef = 0  // MIDI 2.0用の別ポート
    private var lpd8Source: MIDIEndpointRef = 0
    private var keystageSource: MIDIEndpointRef = 0
    private var connectedSources: [MIDIEndpointRef] = []
    
    // Timing Clock計測用
    private var lastClockTime: TimeInterval = 0
    private var clockIntervals: [TimeInterval] = []
    private let maxClockSamples = 96 // 4拍分のクロック数（24クロック×4拍）
    private var clockTimeoutTimer: Timer?
    
    // LPD8のパッドマッピング (デフォルトのノート番号)
    enum LPD8Pad: UInt8 {
        case pad1 = 36  // C1
        case pad2 = 37  // C#1
        case pad3 = 38  // D1
        case pad4 = 39  // D#1
        case pad5 = 40  // E1
        case pad6 = 41  // F1
        case pad7 = 42  // F#1
        case pad8 = 43  // G1
    }
    
    // コールバック用のハンドラー
    var onNoteOn: ((UInt8, UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?
    var onControlChange: ((UInt8, UInt8, UInt8) -> Void)?
    
    init() {
        print("\n🎹 === MIDI Manager Initialization ===")
        setupMIDI()
        // 初期化時にCoreMIDIデバイス情報を表示
        printCoreMIDIDeviceInfo()
        // 利用可能なすべてのMIDIデバイスを表示
        listAllMIDIDevices()
        print("🎹 === End of MIDI Initialization ===\n")
    }
    
    deinit {
        cleanup()
    }
    
    private func setupMIDI() {
        // MIDIクライアントを作成
        let clientName = "LNXX MIDI Client" as CFString
        let status = MIDIClientCreate(clientName, nil, nil, &midiClient)
        
        guard status == noErr else {
            print("MIDIクライアントの作成に失敗: \(status)")
            return
        }
        
        // MIDI 1.0入力ポートを作成（LPD8など用）
        let portName1 = "LNXX MIDI 1.0 Port" as CFString
        print("📱 Creating MIDI 1.0 input port...")
        let inputStatus1 = MIDIInputPortCreateWithProtocol(
            midiClient,
            portName1,
            MIDIProtocolID._1_0,
            &inputPort,
            { [weak self] (eventList, srcConnRefCon) in
                self?.handleMIDIEventList(eventList)
            }
        )
        
        if inputStatus1 == noErr {
            print("✅ MIDI 1.0 input port created successfully")
        } else {
            print("❌ Failed to create MIDI 1.0 port: \(inputStatus1)")
        }
        
        // MIDI 2.0入力ポートを作成（Keystage用）
        // 注: KeystageがMIDI 2.0に対応していても、macOSドライバがMIDI 1.0で動作する可能性がある
        let portName2 = "LNXX MIDI 2.0 Port" as CFString
        print("📱 Creating MIDI 2.0 input port...")
        let inputStatus2 = MIDIInputPortCreateWithProtocol(
            midiClient,
            portName2,
            MIDIProtocolID._2_0,
            &inputPortMIDI2,
            { [weak self] (eventList, srcConnRefCon) in
                print("🎹 MIDI 2.0 Event received!")
                self?.handleMIDIEventList(eventList)
            }
        )
        
        if inputStatus2 == noErr {
            print("✅ MIDI 2.0 input port created successfully")
            print("   • Bidirectional communication enabled")
            print("   • High-resolution velocity support")
            print("   • Property Exchange capability")
        } else {
            print("⚠️ MIDI 2.0 port creation failed: \(inputStatus2)")
            print("   Error code: \(inputStatus2)")
            print("   Note: Keystage will use MIDI 1.0 port instead")
        }
        
        guard inputStatus1 == noErr else {
            print("❌ Critical: No MIDI ports could be created")
            return
        }
        
        // LPD8を探して接続
        connectToLPD8()
        
        // MIDI通知を設定
        setupNotifications()
    }
    
    private func connectToLPD8() {
        // MIDIソースとデスティネーションの両方をチェック
        let sourceCount = MIDIGetNumberOfSources()
        let destCount = MIDIGetNumberOfDestinations()
        let deviceCount = MIDIGetNumberOfDevices()
        
        var devicesFound: [(source: MIDIEndpointRef, name: String, type: String)] = []
        
        print("\n🔍 Scanning for MIDI devices...")
        print("MIDI System Status:")
        print("  Sources: \(sourceCount)")
        print("  Destinations: \(destCount)")
        print("  Devices: \(deviceCount)")
        
        // デバイスから直接エンドポイントを取得
        if deviceCount > 0 {
            print("\n📱 Checking devices directly...")
            for i in 0..<deviceCount {
                let device = MIDIGetDevice(i)
                var deviceName: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(device, kMIDIPropertyName, &deviceName)
                
                let name = deviceName?.takeRetainedValue() as String? ?? "Unknown Device"
                print("  Device \(i+1): '\(name)'")
                
                // デバイスのエンティティを確認
                let entityCount = MIDIDeviceGetNumberOfEntities(device)
                for j in 0..<entityCount {
                    let entity = MIDIDeviceGetEntity(device, j)
                    
                    // エンティティのソースを確認
                    let entitySourceCount = MIDIEntityGetNumberOfSources(entity)
                    for k in 0..<entitySourceCount {
                        let source = MIDIEntityGetSource(entity, k)
                        print("    → Found source in entity \(j+1): \(source)")
                        
                        // このソースをデバイスリストに追加
                        if name.lowercased().contains("keystage") {
                            devicesFound.append((source: source, name: name, type: "Keystage"))
                            print("      ✅ Adding Keystage to connection list")
                        } else if name.lowercased().contains("lpd8") {
                            devicesFound.append((source: source, name: name, type: "LPD8"))
                            print("      ✅ Adding LPD8 to connection list")
                        }
                    }
                }
            }
        }
        
        // 従来の方法でもソースを確認
        if sourceCount == 0 && deviceCount == 0 {
            print("❌ No MIDI devices detected at all!")
            return
        }
        
        // まず全デバイスをスキャン
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            
            MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name)
            
            if let deviceName = name?.takeRetainedValue() as String? {
                print("  [\(i+1)] Found: '\(deviceName)'")
                print("       Raw name bytes: \(deviceName.data(using: .utf8)?.map { String(format: "%02X", $0) }.joined(separator: " ") ?? "N/A")")
                
                // デバイスのプロパティを詳しく調査
                checkDeviceCapabilities(source: source, name: deviceName)
                
                // デバイス名の詳細なマッチング（大文字小文字、スペースを考慮）
                let lowerName = deviceName.lowercased()
                let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("       Lowercase: '\(lowerName)'")
                print("       Trimmed: '\(trimmedName)'")
                
                // Keystageの検出（より柔軟なマッチング）
                // macOSでは単に "Keystage" として認識される可能性
                if lowerName.contains("keystage") || 
                   lowerName == "keystage" ||
                   trimmedName.lowercased() == "keystage" ||
                   lowerName.contains("key stage") ||
                   (lowerName.contains("korg") && lowerName.contains("key")) {
                    devicesFound.append((source: source, name: deviceName, type: "Keystage"))
                    print("    → 🎹 Korg Keystage detected!")
                    print("       Actual name: '\(deviceName)'")
                }
                // LPD8を検出
                else if lowerName.contains("lpd8") || lowerName.contains("lpd 8") {
                    devicesFound.append((source: source, name: deviceName, type: "LPD8"))
                    print("    → 🎮 Akai LPD8 detected!")
                }
                // その他のKorgデバイス
                else if lowerName.contains("korg") {
                    devicesFound.append((source: source, name: deviceName, type: "Korg"))
                    print("    → 🎹 Korg device detected!")
                    print("       Actual name: '\(deviceName)'")
                    print("       Consider connecting as Keystage? Adding to list...")
                    // Korgデバイスは念のためKeystageとして扱う
                    devicesFound.append((source: source, name: deviceName, type: "Keystage"))
                }
                // USB-MIDIデバイス（汎用）
                else if lowerName.contains("usb") || lowerName.contains("midi") {
                    print("    → 🎵 Generic USB-MIDI device: '\(deviceName)'")
                    print("       Checking if this might be Keystage...")
                    // 念のため接続を試みる
                    devicesFound.append((source: source, name: deviceName, type: "Generic"))
                }
                else {
                    print("    → ❓ Unknown device: '\(deviceName)'")
                    print("       Attempting to connect anyway...")
                    // 不明なデバイスも念のため接続を試みる
                    devicesFound.append((source: source, name: deviceName, type: "Unknown"))
                }
            } else {
                // 名前が取得できない場合でも接続を試みる
                print("  [\(i+1)] Found: Unnamed MIDI Source (ID: \(source))")
                devicesFound.append((source: source, name: "MIDI Source \(i+1)", type: "Unknown"))
            }
        }
        
        // 見つかったすべてのデバイスに接続
        if !devicesFound.isEmpty {
            print("\n📌 Found \(devicesFound.count) device(s) to connect:")
            for (index, device) in devicesFound.enumerated() {
                print("   [\(index + 1)] \(device.name) (Type: \(device.type))")
            }
            
            print("\n📌 Attempting connections...")
            for device in devicesFound {
                connectToDevice(source: device.source, priority: device.type)
            }
            
            // 接続状態をまとめて表示
            updateConnectionStatus()
        } else {
            print("⚠️ No MIDI devices found at all!")
            print("   Please check:")
            print("   - Is Keystage powered on?")
            print("   - Is USB cable connected?")
            print("   - Try a different USB port")
            print("   - Check System Settings > Security & Privacy > Privacy")
        }
    }
    
    private func connectToDevice(source: MIDIEndpointRef, priority: String) {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name)
        let deviceName = name?.takeRetainedValue() as String? ?? "Unknown Device"
        
        print("\n🔌 Attempting to connect to \(priority): \(deviceName)")
        
        // デバイスに応じて適切なポートを選択
        // 重要: KeystageもMIDI 1.0ポートで試す（macOSドライバの制限の可能性）
        let selectedPort: MIDIPortRef
        let isKeystage = deviceName.lowercased().contains("keystage")
        
        if isKeystage {
            keystageSource = source
            
            // まずMIDI 1.0で接続を試みる（より互換性が高い）
            print("   → Trying MIDI 1.0 port for Keystage (better compatibility)")
            selectedPort = inputPort
            
            // MIDI 2.0ポートも試す（将来の対応のため）
            if inputPortMIDI2 != 0 {
                print("   → Also connecting to MIDI 2.0 port for future compatibility")
                let connect2 = MIDIPortConnectSource(inputPortMIDI2, source, nil)
                if connect2 == noErr {
                    print("   ✓ MIDI 2.0 port connected (secondary)")
                }
            }
        } else {
            // その他のデバイスはMIDI 1.0ポートを使用
            selectedPort = inputPort
            print("   → Using MIDI 1.0 port")
            if priority == "LPD8" {
                lpd8Source = source
            }
        }
        
        // ソースを適切なポートに接続
        let connectStatus = MIDIPortConnectSource(selectedPort, source, nil)
        
        if connectStatus == noErr {
            // 接続されたソースをリストに追加
            connectedSources.append(source)
            
            print("✅ Successfully connected to: \(deviceName)")
            
            // MIDI 2.0対応チェック
            if isKeystage {
                print("🎹 Korg Keystage connected")
                checkMIDI2Support(source: source)
                print("\n📝 Keystage Connection Info:")
                print("   • Primary: MIDI 1.0 port (for compatibility)")
                print("   • Secondary: MIDI 2.0 port (if available)")
                print("   • Device should work with standard MIDI messages")
                
                // 接続診断
                print("\n🔧 Connection Diagnostics:")
                print("   MIDI 1.0 Port: \(inputPort)")
                if inputPortMIDI2 != 0 {
                    print("   MIDI 2.0 Port: \(inputPortMIDI2)")
                }
                print("   Source: \(source)")
                print("   Primary Protocol: MIDI 1.0")
                
                // テストメッセージ
                print("\n🎵 Please press a key on Keystage to test...")
                print("   Expected: Note On/Off messages should appear")
                print("   If nothing appears, check:")
                print("   - Keystage power and USB connection")
                print("   - MIDI channel settings on Keystage")
                print("   - Try unplugging and reconnecting USB")
            } else if priority == "LPD8" {
                print("🎮 Akai LPD8 - MIDI 1.0 device connected")
                print("   Port: \(inputPort)")
            }
        } else {
            print("❌ Failed to connect to \(deviceName). Error code: \(connectStatus)")
            
            // エラー詳細
            switch connectStatus {
            case kMIDIInvalidPort:
                print("   Error: Invalid port")
            case kMIDIInvalidClient:
                print("   Error: Invalid client")
            case kMIDIObjectNotFound:
                print("   Error: Object not found")
            default:
                print("   Error: Unknown error \(connectStatus)")
            }
        }
    }
    
    private func updateConnectionStatus() {
        DispatchQueue.main.async {
            self.isConnected = !self.connectedSources.isEmpty
            
            // 接続されているデバイス名をまとめて表示
            var deviceNames: [String] = []
            for source in self.connectedSources {
                var name: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name)
                if let deviceName = name?.takeRetainedValue() as String? {
                    deviceNames.append(deviceName)
                }
            }
            
            if deviceNames.count > 1 {
                self.connectedDeviceName = deviceNames.joined(separator: " + ")
            } else if deviceNames.count == 1 {
                self.connectedDeviceName = deviceNames[0]
            } else {
                self.connectedDeviceName = ""
            }
            
            print("\n✨ Connection Summary:")
            print("   Total connected devices: \(self.connectedSources.count)")
            if !deviceNames.isEmpty {
                for (index, name) in deviceNames.enumerated() {
                    print("   [\(index + 1)] \(name)")
                }
            }
        }
    }
    
    private func checkDeviceCapabilities(source: MIDIEndpointRef, name: String) {
        print("\n📋 Device Capabilities for: \(name)")
        
        // デバイスプロトコルバージョンを確認
        var protocolID: Int32 = 0
        
        let result = MIDIObjectGetIntegerProperty(source, kMIDIPropertyProtocolID, &protocolID)
        if result == noErr {
            // MIDIProtocolIDの値を確認
            // _1_0 = 1, _2_0 = 2
            let protocolName = protocolID == 2 ? "MIDI 2.0" : "MIDI 1.0"
            print("   Protocol: \(protocolName)")
        }
        
        // その他のプロパティ
        var manufacturer: Int32 = 0
        if MIDIObjectGetIntegerProperty(source, kMIDIPropertyManufacturer, &manufacturer) == noErr {
            print("   Manufacturer ID: 0x\(String(format: "%06X", manufacturer))")
        }
    }
    
    private func checkMIDI2Support(source: MIDIEndpointRef) {
        print("\n🔍 Checking MIDI 2.0 capabilities...")
        
        // MIDI-CIでの能力確認（将来の実装用）
        print("   - Universal MIDI Packet support: Expected")
        print("   - 16-bit velocity resolution: Expected")
        print("   - Per-Note Controllers: Expected")
        print("   - Property Exchange: Expected")
    }
    
    private var lastEventTime = Date()
    private var eventCount = 0
    
    // 修正版: MIDIEventListを正しく処理
    private func handleMIDIEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        // 頻繁なログを制限
        eventCount += 1
        let now = Date()
        let timeSinceLastEvent = now.timeIntervalSince(lastEventTime)
        
        let list = eventList.pointee
        
        // パケット数が0の場合は静かに無視
        if list.numPackets == 0 {
            return
        }
        
        // 1秒に1回程度のログ出力に制限（ただし重要なイベントは常に表示）
        let shouldLogDetails = timeSinceLastEvent > 1.0
        
        if shouldLogDetails {
            print("\n===== MIDI Event (\(eventCount) events in \(String(format: "%.1f", timeSinceLastEvent))s) =====")
            print("Device: \(connectedDeviceName)")
            lastEventTime = now
            eventCount = 0
        }
        
        // MIDIEventListのパケットを正しく反復処理
        withUnsafePointer(to: list.packet) { firstPacketPtr in
            var currentPacketPtr = UnsafeRawPointer(firstPacketPtr)
            
            for packetIndex in 0..<list.numPackets {
                let packet = currentPacketPtr.load(as: MIDIEventPacket.self)
                
                // ログ詳細の制御
                if shouldLogDetails {
                    print("\n--- Packet \(packetIndex + 1) ---")
                    print("Word Count: \(packet.wordCount)")
                }
                
                // パケットのワードデータを処理（常に実行）
                processPacketWords(packet, verbose: shouldLogDetails)
                
                // 次のパケットへ移動
                // MIDIEventPacketのサイズ = 基本構造 + (wordCount - 1) * UInt32
                let packetSize = MemoryLayout<MIDIEventPacket>.offset(of: \.words)! + 
                                Int(packet.wordCount) * MemoryLayout<UInt32>.size
                currentPacketPtr = currentPacketPtr.advanced(by: packetSize)
            }
        }
        
        if shouldLogDetails {
            print("=====================================\n")
        }
    }
    
    private func processPacketWords(_ packet: MIDIEventPacket, verbose: Bool = true) {
        // wordsをバイト配列として扱う
        withUnsafeBytes(of: packet.words) { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            let byteCount = Int(packet.wordCount) * 4  // 1 word = 4 bytes
            
            // 詳細ログは必要な時のみ
            if verbose {
                print("\n📊 MIDI Data Analysis:")
                var hexString = "Raw Bytes: "
                for i in 0..<min(byteCount, 16) {  // 最大16バイトまで表示
                    hexString += String(format: "0x%02X ", bytes[i])
                }
                print(hexString)
            }
            
            // バイトごとの解析（詳細モードのみ）
            if verbose && byteCount >= 4 {
                print("Byte 0: 0x\(String(format: "%02X", bytes[0])) = Message Type: \((bytes[0] >> 4) & 0x0F), Group: \(bytes[0] & 0x0F)")
                print("Byte 1: 0x\(String(format: "%02X", bytes[1])) = Status/Channel or Data")
                print("Byte 2: 0x\(String(format: "%02X", bytes[2])) = Data 1")
                print("Byte 3: 0x\(String(format: "%02X", bytes[3])) = Data 2")
            }
            
            // MIDI Universal Packet (MIDI 2.0) の処理
            if packet.wordCount > 0 {
                let messageType = (bytes[0] >> 4) & 0x0F
                
                if verbose {
                    print("\n🔍 Detected Message Type: \(messageType) (\(getUMPMessageTypeName(messageType)))")
                }
                
                // MIDI 1.0 Channel Voice Messages (Message Type 2)
                if messageType == 0x2 {
                    if verbose {
                        print("→ Processing as MIDI 1.0 Channel Voice Message")
                    }
                    processMIDI1ChannelVoice(bytes: bytes.baseAddress!, byteCount: byteCount)
                }
                // MIDI 2.0 Channel Voice Messages (Message Type 4)
                else if messageType == 0x4 {
                    if verbose {
                        print("→ Processing as MIDI 2.0 Channel Voice Message (High Resolution)")
                    }
                    processMIDI2ChannelVoice(bytes: bytes.baseAddress!, byteCount: byteCount)
                }
                // System Common/Real Time Messages (Message Type 1)
                else if messageType == 0x1 {
                    // システムメッセージは静かに処理
                    processMIDI1SystemMessage(bytes: bytes.baseAddress!, byteCount: byteCount)
                }
                // その他のメッセージタイプ
                else {
                    // warningログを出力
                    if verbose {
                        print("⚠️ Unknown message type: \(messageType) - Processing as fallback")
                    }
                    // 従来のMIDI 1.0形式として解釈を試みる
                    if bytes[1] >= 0x80 && bytes[1] <= 0xFF {
                        let status = bytes[1]
                        let channel = (status & 0x0F) + 1
                        let msgType = status & 0xF0
                        
                        if msgType == 0x90 && byteCount >= 4 {
                            handleNoteOn(channel: UInt8(channel), note: bytes[2], velocity: bytes[3])
                        } else if msgType == 0x80 && byteCount >= 4 {
                            handleNoteOff(channel: UInt8(channel), note: bytes[2], velocity: bytes[3])
                        }
                    } else {
                        processRawMIDIData(bytes: bytes.baseAddress!, byteCount: byteCount)
                    }
                }
            }
        }
    }
    
    private func processMIDI1ChannelVoice(bytes: UnsafePointer<UInt8>, byteCount: Int) {
        guard byteCount >= 4 else { return }
        
        // MIDI 1.0 Channel Voice Message in UMP format
        // Byte 0: Message Type (4 bits) + Group (4 bits)
        // Byte 1: Status (メッセージタイプ + チャンネル)
        // Byte 2: Data 1 (ノート番号、コントローラー番号など)
        // Byte 3: Data 2 (ベロシティ、値など)
        
        let status = bytes[1]
        let data1 = bytes[2]
        let data2 = bytes[3]
        
        // チャンネルは0-15で内部管理、表示は1-16
        let channel = (status & 0x0F) + 1
        let messageType = status & 0xF0
        
        print("\n📝 MIDI 1.0 Message Decoded:")
        print("   Status: 0x\(String(format: "%02X", status))")
        print("   Channel: \(channel) (MIDI Channel)")
        print("   Message Type: 0x\(String(format: "%02X", messageType)) (\(getMessageTypeName(messageType)))")
        print("   Data 1: \(data1)")
        print("   Data 2: \(data2)")
        
        switch messageType {
        case 0x90: // Note On
            handleNoteOn(channel: channel, note: data1, velocity: data2)
        case 0x80: // Note Off
            handleNoteOff(channel: channel, note: data1, velocity: data2)
        case 0xB0: // Control Change
            handleControlChange(channel: channel, controller: data1, value: data2)
        case 0xC0: // Program Change
            print("🎸 PROGRAM CHANGE - Channel: \(channel), Program: \(data1)")
        case 0xD0: // Channel Pressure
            print("👇 CHANNEL PRESSURE - Channel: \(channel), Pressure: \(data1)")
        case 0xE0: // Pitch Bend
            handlePitchBend(channel: channel, lsb: data1, msb: data2)
        default:
            print("❓ Unknown/Unhandled message type: 0x\(String(format: "%02X", messageType))")
        }
    }
    
    private func getMessageTypeName(_ type: UInt8) -> String {
        switch type {
        case 0x80: return "Note Off"
        case 0x90: return "Note On"
        case 0xA0: return "Polyphonic Aftertouch"
        case 0xB0: return "Control Change"
        case 0xC0: return "Program Change"
        case 0xD0: return "Channel Pressure"
        case 0xE0: return "Pitch Bend"
        case 0xF0: return "System"
        default: return "Unknown"
        }
    }
    
    private func getUMPMessageTypeName(_ type: UInt8) -> String {
        switch type {
        case 0x0: return "Utility Message"
        case 0x1: return "System Real Time/Common"
        case 0x2: return "MIDI 1.0 Channel Voice"
        case 0x3: return "Data Messages"
        case 0x4: return "MIDI 2.0 Channel Voice"
        case 0x5: return "Data Messages (128-bit)"
        case 0xD: return "Flex Data"
        case 0xF: return "Stream Messages"
        default: 
            print("⚠️ Unknown/Reserved message type: 0x\(String(format: "%X", type))")
            return "Unknown/Reserved (0x\(String(format: "%X", type)))"
        }
    }
    
    private func processMIDI2ChannelVoice(bytes: UnsafePointer<UInt8>, byteCount: Int) {
        guard byteCount >= 8 else { 
            print("⚠️ MIDI 2.0 message too short: \(byteCount) bytes")
            return 
        }
        
        // MIDI 2.0 Channel Voice Message (64-bit UMP)
        // Word 1: Message Type, Group, Status, Channel, Note
        let group = bytes[0] & 0x0F
        let status = (bytes[1] >> 4) & 0x0F
        let channel = (bytes[1] & 0x0F) + 1
        let note = bytes[3]
        
        // Word 2: High resolution data
        let velocity16 = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
        let attribute16 = (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
        
        print("\n🎹 MIDI 2.0 High Resolution Message:")
        print("   Group: \(group)")
        print("   Channel: \(channel)")
        print("   Status: \(getMIDI2StatusName(status))")
        print("   Note: \(note) (\(getNoteName(note)))")
        print("   Velocity: \(velocity16) (16-bit resolution)")
        print("   Attribute: \(attribute16)")
        
        // MIDI 1.0との比較表示
        let velocity7bit = velocity16 >> 9  // 16-bit to 7-bit conversion
        print("   → MIDI 1.0 equivalent velocity: \(velocity7bit)")
        
        switch status {
        case 0x9: // Note On
            handleMIDI2NoteOn(channel: UInt8(channel), note: note, velocity16: velocity16, attribute: attribute16)
        case 0x8: // Note Off
            handleMIDI2NoteOff(channel: UInt8(channel), note: note, velocity16: velocity16)
        case 0xA: // Poly Pressure
            print("   🎛 Poly Pressure - Value: \(velocity16)")
        case 0xB: // Control Change
            print("   🎛 Per-Note Control Change")
        case 0x6: // Per-Note Pitch Bend
            let pitchBend32 = (UInt32(velocity16) << 16) | UInt32(attribute16)
            print("   🎚 Per-Note Pitch Bend: \(pitchBend32) (32-bit)")
        default:
            print("   ❓ Unknown MIDI 2.0 status: \(status)")
        }
    }
    
    private func getMIDI2StatusName(_ status: UInt8) -> String {
        switch status {
        case 0x8: return "Note Off"
        case 0x9: return "Note On"
        case 0xA: return "Poly Pressure"
        case 0xB: return "Control Change"
        case 0xC: return "Program Change"
        case 0xD: return "Channel Pressure"
        case 0xE: return "Pitch Bend"
        case 0x0: return "Per-Note RCC"
        case 0x1: return "Per-Note ACC"
        case 0x2: return "RPN"
        case 0x3: return "NRPN"
        case 0x4: return "Relative RPN"
        case 0x5: return "Relative NRPN"
        case 0x6: return "Per-Note Pitch Bend"
        default: return "Unknown"
        }
    }
    
    private func getNoteName(_ note: UInt8) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(note) / 12 - 1
        let noteName = noteNames[Int(note) % 12]
        return "\(noteName)\(octave)"
    }
    
    private func handleMIDI2NoteOn(channel: UInt8, note: UInt8, velocity16: UInt16, attribute: UInt16) {
        print("\n🎹 MIDI 2.0 NOTE ON")
        print("   Channel: \(channel)")
        print("   Note: \(note) (\(getNoteName(note)))")
        print("   Velocity (16-bit): \(velocity16) / 65535")
        print("   Velocity (%): \(String(format: "%.2f", Double(velocity16) / 655.35))%")
        print("   Attribute: \(attribute)")
        
        // Keystage特有の解析
        if connectedDeviceName.lowercased().contains("keystage") {
            print("\n🎮 Keystage Specific:")
            if note >= 21 && note <= 108 {  // Piano range A0-C8
                print("   → Piano key pressed")
            }
            print("   → High-resolution velocity detected")
            if attribute != 0 {
                print("   → Additional expression data: \(attribute)")
            }
        }
        
        // MIDI 1.0互換のため7ビットベロシティも計算
        let velocity7bit = UInt8(velocity16 >> 9)
        
        DispatchQueue.main.async {
            self.lastReceivedNote = note
            self.lastReceivedVelocity = velocity7bit
            
            if velocity16 > 0 {
                self.onNoteOn?(note, velocity7bit)
            }
        }
    }
    
    private func handleMIDI2NoteOff(channel: UInt8, note: UInt8, velocity16: UInt16) {
        print("\n🎹 MIDI 2.0 NOTE OFF")
        print("   Channel: \(channel)")
        print("   Note: \(note) (\(getNoteName(note)))")
        print("   Release Velocity (16-bit): \(velocity16)")
        
        DispatchQueue.main.async {
            self.lastReceivedNote = note
            self.lastReceivedVelocity = 0
            self.onNoteOff?(note)
        }
    }
    
    private func processMIDI1SystemMessage(bytes: UnsafePointer<UInt8>, byteCount: Int) {
        // System messages processing
        print("System Message received")
        if byteCount >= 2 {
            let systemType = bytes[1]
            switch systemType {
            case 0xF8: print("   → Timing Clock")
            case 0xFA: print("   → Start")
            case 0xFB: print("   → Continue")
            case 0xFC: print("   → Stop")
            case 0xFE: print("   → Active Sensing")
            case 0xFF: print("   → System Reset")
            default: print("   → System Message: 0x\(String(format: "%02X", systemType))")
            }
        }
    }
    
    private func processRawMIDIData(bytes: UnsafePointer<UInt8>, byteCount: Int) {
        // Timing Clock (0xF8) のチェック
        if byteCount >= 3 && bytes[2] == 0xF8 {
            handleTimingClock()
            return
        }
        
        // LPD8の特定パターンをチェック
        if byteCount >= 4 {
            // パターン: 0x20 0x90 XX 7F (Note On)
            if bytes[0] == 0x20 && bytes[1] == 0x90 {
                let note = bytes[2]
                let velocity = bytes[3]
                print("🎯 LPD8 Note On Pattern - Note: \(note), Velocity: \(velocity)")
                handleNoteOn(channel: 1, note: note, velocity: velocity)
                return
            }
            
            // パターン: 0x20 0x80 XX 00 (Note Off)
            if bytes[0] == 0x20 && bytes[1] == 0x80 {
                let note = bytes[2]
                print("📴 LPD8 Note Off Pattern - Note: \(note)")
                handleNoteOff(channel: 1, note: note, velocity: 0)
                return
            }
            
            // 不明な形式の場合はwarningログを出力
            var hexString = ""
            for i in 0..<min(byteCount, 8) {
                hexString += String(format: "0x%02X ", bytes[i])
            }
            print("⚠️ Processing as Raw/Unknown format: \(hexString)")
        }
    }
    
    private func handleTimingClock() {
        let currentTime = Date().timeIntervalSinceReferenceDate
        
        // 初回クロック
        if lastClockTime == 0 {
            lastClockTime = currentTime
            DispatchQueue.main.async {
                self.isReceivingClock = true
            }
            resetClockTimeout()
            return
        }
        
        // クロック間隔を計算
        let interval = currentTime - lastClockTime
        lastClockTime = currentTime
        
        // 異常値を除外（0.001秒未満または1秒以上の間隔は無視）
        if interval > 0.001 && interval < 1.0 {
            clockIntervals.append(interval)
            
            // サンプル数を制限
            if clockIntervals.count > maxClockSamples {
                clockIntervals.removeFirst()
            }
            
            // BPMを計算（最低4拍分のデータが必要）
            if clockIntervals.count >= 24 {
                calculateBPM()
            }
        }
        
        resetClockTimeout()
    }
    
    private func calculateBPM() {
        guard !clockIntervals.isEmpty else { return }
        
        // 平均間隔を計算（外れ値を除外）
        let sortedIntervals = clockIntervals.sorted()
        let trimCount = clockIntervals.count / 10 // 上下10%をトリム
        let trimmedIntervals = Array(sortedIntervals.dropFirst(trimCount).dropLast(trimCount))
        
        guard !trimmedIntervals.isEmpty else { return }
        
        let averageInterval = trimmedIntervals.reduce(0, +) / Double(trimmedIntervals.count)
        
        // BPM計算: 60秒 / (24クロック × 平均間隔) = BPM
        let bpm = 60.0 / (24.0 * averageInterval)
        
        // 妥当な範囲のBPMのみ更新（30-300 BPM）
        if bpm >= 30 && bpm <= 300 {
            DispatchQueue.main.async {
                self.currentBPM = round(bpm * 10) / 10 // 小数点1位まで
            }
        }
    }
    
    private func resetClockTimeout() {
        clockTimeoutTimer?.invalidate()
        clockTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.isReceivingClock = false
                self.currentBPM = 0
                self.clockIntervals.removeAll()
                self.lastClockTime = 0
            }
        }
    }
    
    private func handleNoteOn(channel: UInt8, note: UInt8, velocity: UInt8) {
        print("🎹 NOTE ON - Channel: \(channel), Note: \(note), Velocity: \(velocity)")
        
        // パッド番号を表示
        if note >= 36 && note <= 43 {
            let padNumber = Int(note - 35)
            print("   → LPD8 PAD \(padNumber) pressed")
        }
        
        DispatchQueue.main.async {
            self.lastReceivedNote = note
            self.lastReceivedVelocity = velocity
            
            if velocity > 0 {
                print("   → Triggering onNoteOn callback")
                self.onNoteOn?(note, velocity)
            } else {
                // Velocity 0はNote Offとして扱う
                print("   → Velocity 0 - treating as Note Off")
                self.onNoteOff?(note)
            }
        }
    }
    
    private func handleNoteOff(channel: UInt8, note: UInt8, velocity: UInt8) {
        print("🎹 NOTE OFF - Channel: \(channel), Note: \(note)")
        
        // パッド番号を表示
        if note >= 36 && note <= 43 {
            let padNumber = Int(note - 35)
            print("   → LPD8 PAD \(padNumber) released")
        }
        
        DispatchQueue.main.async {
            self.lastReceivedNote = note
            self.lastReceivedVelocity = 0
            print("   → Triggering onNoteOff callback")
            self.onNoteOff?(note)
        }
    }
    
    private func handleControlChange(channel: UInt8, controller: UInt8, value: UInt8) {
        print("🎛 CONTROL CHANGE - Channel: \(channel), Controller: \(controller), Value: \(value)")
        
        // Keystage特有のコントローラー解析
        if connectedDeviceName.lowercased().contains("keystage") {
            switch controller {
            case 1: print("   → Modulation Wheel: \(value)")
            case 7: print("   → Volume: \(value)")
            case 10: print("   → Pan: \(value)")
            case 11: print("   → Expression: \(value)")
            case 64: print("   → Sustain Pedal: \(value > 63 ? "ON" : "OFF")")
            case 67: print("   → Soft Pedal: \(value > 63 ? "ON" : "OFF")")
            default: break
            }
        }
        
        DispatchQueue.main.async {
            self.onControlChange?(channel, controller, value)
        }
    }
    
    private func handlePitchBend(channel: UInt8, lsb: UInt8, msb: UInt8) {
        let value = (Int(msb) << 7) | Int(lsb)
        let centered = value - 8192  // Center is 8192 for 14-bit
        let percentage = Double(centered) / 81.92  // -100% to +100%
        print("🎚 PITCH BEND - Channel: \(channel)")
        print("   Raw Value: \(value) / 16383")
        print("   Centered: \(centered)")
        print("   Percentage: \(String(format: "%.1f", percentage))%")
    }
    
    private func setupNotifications() {
        // MIDI設定変更の通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(midiSetupChanged),
            name: .MIDISetupChanged,
            object: nil
        )
    }
    
    @objc private func midiSetupChanged() {
        print("MIDI設定が変更されました")
        
        // 再接続を試みる
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectedDeviceName = ""
        }
        
        connectToLPD8()
    }
    
    private func cleanup() {
        // すべての接続を切断
        for source in connectedSources {
            // MIDI 1.0ポートからの切断
            if inputPort != 0 {
                MIDIPortDisconnectSource(inputPort, source)
            }
            // MIDI 2.0ポートからの切断
            if inputPortMIDI2 != 0 {
                MIDIPortDisconnectSource(inputPortMIDI2, source)
            }
        }
        connectedSources.removeAll()
        
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        
        if inputPortMIDI2 != 0 {
            MIDIPortDispose(inputPortMIDI2)
            inputPortMIDI2 = 0
        }
        
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }
        
        lpd8Source = 0
        keystageSource = 0
    }
    
    // デバイスを手動で再スキャン
    func rescanDevices() {
        print("\n🔄 Rescanning MIDI devices...")
        cleanup()
        setupMIDI()
    }
    
    // 特定のデバイスに手動接続
    func connectToPreferredDevice(preferKeystage: Bool = true) {
        print("\n🎯 Manual connection attempt...")
        print("   Preference: \(preferKeystage ? "Korg Keystage" : "Any supported device")")
        connectToLPD8()  // この関数名は歴史的理由で残っているが、実際は全デバイスをスキャン
    }
    
    // Keystage接続テスト
    // デバイスの有効/無効を切り替え
    func toggleDeviceEnabled(_ deviceName: String) {
        if disabledDevices.contains(deviceName) {
            disabledDevices.remove(deviceName)
            print("✅ Enabled device: \(deviceName)")
            
            // デバイスが有効化された場合、再接続を試みる
            if deviceName.lowercased().contains("keystage") || deviceName.lowercased().contains("lpd8") {
                rescanDevices()
            }
        } else {
            disabledDevices.insert(deviceName)
            print("⛔ Disabled device: \(deviceName)")
            
            // デバイスが無効化された場合、接続を切断
            if connectedDeviceName.contains(deviceName) {
                disconnectDevice(deviceName)
            }
        }
        
        // デバイスリストを更新
        if let index = deviceInfoList.firstIndex(where: { $0.name == deviceName }) {
            deviceInfoList[index].isEnabled = !disabledDevices.contains(deviceName)
        }
    }
    
    // 特定のデバイスを切断
    private func disconnectDevice(_ deviceName: String) {
        if deviceName.lowercased().contains("keystage") {
            if keystageSource != 0 {
                MIDIPortDisconnectSource(inputPort, keystageSource)
                MIDIPortDisconnectSource(inputPortMIDI2, keystageSource)
                keystageSource = 0
            }
        } else if deviceName.lowercased().contains("lpd8") {
            if lpd8Source != 0 {
                MIDIPortDisconnectSource(inputPort, lpd8Source)
                lpd8Source = 0
            }
        }
        
        // 接続状態を更新
        updateConnectionStatus()
    }
    
    func testKeystageConnection() {
        print("\n🔧 Testing Keystage Connection...")
        
        if keystageSource != 0 {
            print("✅ Keystage source is valid: \(keystageSource)")
            
            // MIDI 2.0ポートの状態を確認
            if inputPortMIDI2 != 0 {
                print("✅ MIDI 2.0 port is active: \(inputPortMIDI2)")
                
                // 接続状態を再確認
                var name: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(keystageSource, kMIDIPropertyName, &name)
                if let deviceName = name?.takeRetainedValue() as String? {
                    print("✅ Device name confirmed: \(deviceName)")
                }
                
                // プロトコル情報を取得
                var protocolID: Int32 = 0
                let result = MIDIObjectGetIntegerProperty(keystageSource, kMIDIPropertyProtocolID, &protocolID)
                if result == noErr {
                    print("📊 Protocol version: \(protocolID == 2 ? "MIDI 2.0" : "MIDI 1.0")")
                }
                
                print("\n🎵 Keystage is ready. Please play a note...")
            } else {
                print("❌ MIDI 2.0 port is not active")
                print("   Attempting to reconnect...")
                rescanDevices()
            }
        } else {
            print("❌ Keystage source is not connected")
            print("   Please check the USB connection")
        }
    }
    
    // デバッグ用: 接続状態を出力
    func printConnectionStatus() {
        print("\n=== MIDI Connection Status ===")
        print("Connected: \(isConnected)")
        print("Device: \(connectedDeviceName)")
        print("Last Note: \(lastReceivedNote)")
        print("Last Velocity: \(lastReceivedVelocity)")
        print("==============================\n")
    }
    
    // 接続可能なMIDI機器の一覧を取得
    func listAllMIDIDevices() {
        print("\n╔══════════════════════════════════════════════════════════════════╗")
        print("║                    MIDI DEVICES AVAILABLE                        ║")
        print("╚══════════════════════════════════════════════════════════════════╝")
        
        var devices: [String] = []
        var newDeviceInfoList: [DeviceInfo] = []
        
        let sourceCount = MIDIGetNumberOfSources()
        let destCount = MIDIGetNumberOfDestinations()
        
        print("\n📥 MIDI Input Sources: \(sourceCount)")
        print("─────────────────────────────────────")
        
        if sourceCount == 0 {
            print("   No input devices found")
            devices.append("📥 入力デバイス: なし")
        } else {
            for i in 0..<sourceCount {
                let source = MIDIGetSource(i)
                printDeviceInfo(endpoint: source, index: i, type: "Input")
                
                // デバイス名を取得して配列に追加
                var name: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name)
                if let deviceName = name?.takeRetainedValue() as String? {
                    devices.append("📥 入力: \(deviceName)")
                    
                    // DeviceInfo構造体も作成
                    let deviceInfo = DeviceInfo(
                        name: deviceName,
                        type: .midiInput,
                        isEnabled: !disabledDevices.contains(deviceName),
                        isConnected: connectedDeviceName.contains(deviceName)
                    )
                    newDeviceInfoList.append(deviceInfo)
                }
            }
        }
        
        print("\n📤 MIDI Output Destinations: \(destCount)")
        print("─────────────────────────────────────")
        
        if destCount == 0 {
            print("   No output devices found")
            devices.append("📤 出力デバイス: なし")
        } else {
            for i in 0..<destCount {
                let dest = MIDIGetDestination(i)
                printDeviceInfo(endpoint: dest, index: i, type: "Output")
                
                // デバイス名を取得して配列に追加
                var name: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(dest, kMIDIPropertyName, &name)
                if let deviceName = name?.takeRetainedValue() as String? {
                    devices.append("📤 出力: \(deviceName)")
                    
                    // DeviceInfo構造体も作成
                    let deviceInfo = DeviceInfo(
                        name: deviceName,
                        type: .midiOutput,
                        isEnabled: !disabledDevices.contains(deviceName),
                        isConnected: false // 出力デバイスの接続状態は別途管理
                    )
                    newDeviceInfoList.append(deviceInfo)
                }
            }
        }
        
        // UIを更新
        DispatchQueue.main.async {
            self.availableDevices = devices
            self.deviceInfoList = newDeviceInfoList
        }
        
        print("\n════════════════════════════════════════════════════════════════════\n")
    }
    
    // CoreMIDIの詳細なデバイス情報を表示
    func printCoreMIDIDeviceInfo() {
        print("\n╔════════════════════════════════════════════════════════════════════╗")
        print("║                     CoreMIDI SYSTEM INFORMATION                      ║")
        print("╚════════════════════════════════════════════════════════════════════╝")
        
        // MIDIデバイス数
        let deviceCount = MIDIGetNumberOfDevices()
        print("\n📱 Total MIDI Devices: \(deviceCount)")
        print("══════════════════════════════════════════════════")
        
        for i in 0..<deviceCount {
            let device = MIDIGetDevice(i)
            printDetailedDeviceInfo(device: device, index: i)
        }
        
        // 外部デバイス
        let externalCount = MIDIGetNumberOfExternalDevices()
        if externalCount > 0 {
            print("\n🔌 External MIDI Devices: \(externalCount)")
            print("══════════════════════════════════════════════════")
            
            for i in 0..<externalCount {
                let device = MIDIGetExternalDevice(i)
                printDetailedDeviceInfo(device: device, index: i, isExternal: true)
            }
        }
        
        // ソースとデスティネーション
        print("\n📊 MIDI Endpoints Summary:")
        print("══════════════════════════════════════════════════")
        print("   Input Sources: \(MIDIGetNumberOfSources())")
        print("   Output Destinations: \(MIDIGetNumberOfDestinations())")
        
        print("\n════════════════════════════════════════════════════════════════════\n")
    }
    
    private func printDetailedDeviceInfo(device: MIDIDeviceRef, index: Int, isExternal: Bool = false) {
        var name: Unmanaged<CFString>?
        var manufacturer: Unmanaged<CFString>?
        var model: Unmanaged<CFString>?
        var uniqueID: Int32 = 0
        var isOffline: Int32 = 0
        var driver: Unmanaged<CFString>?
        
        MIDIObjectGetStringProperty(device, kMIDIPropertyName, &name)
        MIDIObjectGetStringProperty(device, kMIDIPropertyManufacturer, &manufacturer)
        MIDIObjectGetStringProperty(device, kMIDIPropertyModel, &model)
        MIDIObjectGetIntegerProperty(device, kMIDIPropertyUniqueID, &uniqueID)
        MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &isOffline)
        MIDIObjectGetStringProperty(device, kMIDIPropertyDriverOwner, &driver)
        
        let deviceName = name?.takeRetainedValue() as String? ?? "Unknown Device"
        let manufacturerName = manufacturer?.takeRetainedValue() as String? ?? "Unknown"
        let modelName = model?.takeRetainedValue() as String? ?? "Unknown"
        let driverName = driver?.takeRetainedValue() as String? ?? "Core MIDI"
        
        print("\n[\(index + 1)] \(deviceName)")
        print("    Type: \(isExternal ? "External" : "Internal") Device")
        print("    Manufacturer: \(manufacturerName)")
        print("    Model: \(modelName)")
        print("    Driver: \(driverName)")
        print("    Unique ID: \(uniqueID)")
        print("    Status: \(isOffline == 0 ? "🟢 Online" : "🔴 Offline")")
        
        // エンティティ情報
        let entityCount = MIDIDeviceGetNumberOfEntities(device)
        if entityCount > 0 {
            print("    Entities: \(entityCount)")
            
            for j in 0..<entityCount {
                let entity = MIDIDeviceGetEntity(device, j)
                printEntityInfo(entity: entity, index: j)
            }
        }
    }
    
    private func printEntityInfo(entity: MIDIEntityRef, index: Int) {
        var entityName: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(entity, kMIDIPropertyName, &entityName)
        let name = entityName?.takeRetainedValue() as String? ?? "Entity \(index + 1)"
        
        let sourceCount = MIDIEntityGetNumberOfSources(entity)
        let destCount = MIDIEntityGetNumberOfDestinations(entity)
        
        print("      Entity \(index + 1): \(name)")
        print("        Sources: \(sourceCount), Destinations: \(destCount)")
    }
    
    private func printDeviceInfo(endpoint: MIDIEndpointRef, index: Int, type: String) {
        var name: Unmanaged<CFString>?
        var displayName: Unmanaged<CFString>?
        var manufacturer: Int32 = 0
        var model: Unmanaged<CFString>?
        var uniqueID: Int32 = 0
        var protocolID: Int32 = 0
        
        // デバイス名
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        let deviceName = name?.takeRetainedValue() as String? ?? "Unknown Device"
        
        // 表示名
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &displayName)
        let deviceDisplayName = displayName?.takeRetainedValue() as String? ?? ""
        
        // モデル名
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyModel, &model)
        let modelName = model?.takeRetainedValue() as String? ?? ""
        
        // 製造者ID
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyManufacturer, &manufacturer)
        
        // ユニークID
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
        
        // プロトコルバージョン
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyProtocolID, &protocolID)
        let protocolName = protocolID == 2 ? "MIDI 2.0" : "MIDI 1.0"
        
        // デバイス情報を出力
        print("\n   [\(index + 1)] \(deviceName)")
        
        if !deviceDisplayName.isEmpty && deviceDisplayName != deviceName {
            print("       Display Name: \(deviceDisplayName)")
        }
        
        if !modelName.isEmpty {
            print("       Model: \(modelName)")
        }
        
        print("       Type: \(type)")
        print("       Protocol: \(protocolName)")
        
        if manufacturer != 0 {
            print("       Manufacturer ID: 0x\(String(format: "%06X", manufacturer))")
        }
        
        print("       Unique ID: \(uniqueID)")
        
        // 現在接続中のデバイスか確認
        if deviceName == connectedDeviceName {
            print("       ✅ Currently Connected")
        }
        
        // 特別な機器の識別
        if deviceName.lowercased().contains("lpd8") {
            print("       🎮 Akai LPD8 Pad Controller")
        } else if deviceName.lowercased().contains("keystage") {
            print("       🎹 Korg Keystage (MIDI 2.0 Ready)")
        } else if deviceName.lowercased().contains("korg") {
            print("       🎹 Korg Device")
        }
    }
}

// MIDI通知名の定義
extension Notification.Name {
    static let MIDISetupChanged = Notification.Name("MIDISetupChanged")
}