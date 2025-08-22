//
//  AudioGraphManager.swift
//  LNXX
//
//  Created by Claude on 2025/08/11.
//

import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import SwiftUI

// MARK: - Audio Node Types
enum AudioNodeType: String, CaseIterable {
    case input = "Input"
    case output = "Output"
    case mixer = "Mixer"
    case effect = "Effect"
    case generator = "Generator"
    case recorder = "Recorder"
    case player = "Player"
}

// MARK: - Audio Node Protocol
protocol AudioNode: Identifiable {
    var id: UUID { get }
    var name: String { get set }
    var type: AudioNodeType { get }
    var audioUnit: AudioUnit? { get set }
    var isEnabled: Bool { get set }
    var inputBusCount: Int { get }
    var outputBusCount: Int { get }
}

// MARK: - Audio Connection
struct AudioConnection: Identifiable {
    let id = UUID()
    let sourceNodeId: UUID
    let sourceBus: Int
    let destinationNodeId: UUID
    let destinationBus: Int
    var gain: Float = 1.0
    var isActive: Bool = true
}

// MARK: - Audio Device Info
struct AudioDeviceInfo: Identifiable {
    let id: AudioDeviceID
    let name: String
    let manufacturer: String
    let channelCount: Int
    let sampleRate: Double
    let isInput: Bool
    let isOutput: Bool
    var isDefault: Bool
    var isEnabled: Bool = true
}

// MARK: - Audio Graph Manager
class AudioGraphManager: ObservableObject {
    // Published properties for UI
    @Published var nodes: [any AudioNode] = []
    @Published var connections: [AudioConnection] = []
    @Published var audioDevices: [AudioDeviceInfo] = []
    @Published var currentInputDevice: AudioDeviceInfo?
    @Published var currentOutputDevice: AudioDeviceInfo?
    @Published var isRunning = false
    @Published var currentLatency: Double = 0.0
    @Published var cpuUsage: Float = 0.0
    
    // Core Audio properties
    private var augraph: AUGraph?
    private var ioNode: AUNode = 0
    private var mixerNode: AUNode = 0
    private var ioUnit: AudioUnit?
    private var mixerUnit: AudioUnit?
    
    // Audio format
    private var audioFormat = AudioStreamBasicDescription(
        mSampleRate: 48000.0,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
        mBytesPerPacket: 4,
        mFramesPerPacket: 1,
        mBytesPerFrame: 4,
        mChannelsPerFrame: 2,
        mBitsPerChannel: 32,
        mReserved: 0
    )
    
    // Buffer settings
    private let preferredBufferSize: UInt32 = 256  // Low latency
    private let maxBufferSize: UInt32 = 4096
    
    init() {
        setupAudioSession()
        createAudioGraph()
        enumerateAudioDevices()
        setupNotifications()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    private func setupAudioSession() {
        // macOSではAVAudioSessionは使用しないが、Audio HALの初期設定を行う
        print("🎛 Initializing Core Audio System...")
    }
    
    private func createAudioGraph() {
        var status: OSStatus
        
        // Create new AUGraph
        status = NewAUGraph(&augraph)
        guard status == noErr else {
            print("❌ Failed to create AUGraph: \(status)")
            return
        }
        
        // Open the graph
        status = AUGraphOpen(augraph!)
        guard status == noErr else {
            print("❌ Failed to open AUGraph: \(status)")
            return
        }
        
        // Add IO Unit (for input/output)
        var ioComponentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        status = AUGraphAddNode(augraph!, &ioComponentDesc, &ioNode)
        guard status == noErr else {
            print("❌ Failed to add IO node: \(status)")
            return
        }
        
        // Add Mixer Unit
        var mixerComponentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_MultiChannelMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        status = AUGraphAddNode(augraph!, &mixerComponentDesc, &mixerNode)
        guard status == noErr else {
            print("❌ Failed to add mixer node: \(status)")
            return
        }
        
        // Get Audio Unit instances
        status = AUGraphNodeInfo(augraph!, ioNode, nil, &ioUnit)
        guard status == noErr else {
            print("❌ Failed to get IO unit: \(status)")
            return
        }
        
        status = AUGraphNodeInfo(augraph!, mixerNode, nil, &mixerUnit)
        guard status == noErr else {
            print("❌ Failed to get mixer unit: \(status)")
            return
        }
        
        // Enable IO for input and output
        var enableIO: UInt32 = 1
        AudioUnitSetProperty(
            ioUnit!,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,  // input element
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        AudioUnitSetProperty(
            ioUnit!,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,  // output element
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        // Set audio format
        AudioUnitSetProperty(
            ioUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &audioFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        
        // Connect mixer to output
        status = AUGraphConnectNodeInput(augraph!, mixerNode, 0, ioNode, 0)
        guard status == noErr else {
            print("❌ Failed to connect nodes: \(status)")
            return
        }
        
        // Initialize the graph
        status = AUGraphInitialize(augraph!)
        guard status == noErr else {
            print("❌ Failed to initialize graph: \(status)")
            return
        }
        
        print("✅ Audio Graph created successfully")
    }
    
    // MARK: - Device Management
    
    func enumerateAudioDevices() {
        var devices: [AudioDeviceInfo] = []
        
        // Get all audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("❌ Failed to get audio devices size: \(status)")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("❌ Failed to get audio devices: \(status)")
            return
        }
        
        // Get info for each device
        for deviceID in deviceIDs {
            if let deviceInfo = getDeviceInfo(deviceID: deviceID) {
                devices.append(deviceInfo)
            }
        }
        
        DispatchQueue.main.async {
            self.audioDevices = devices
            
            // Set default devices
            self.currentInputDevice = devices.first { $0.isInput && $0.isDefault }
            self.currentOutputDevice = devices.first { $0.isOutput && $0.isDefault }
        }
        
        print("📱 Found \(devices.count) audio devices")
    }
    
    private func getDeviceInfo(deviceID: AudioDeviceID) -> AudioDeviceInfo? {
        var name = ""
        var manufacturer = ""
        
        // Get device name
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        if status == noErr && dataSize > 0 {
            var deviceName = "" as CFString
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0, nil,
                &dataSize,
                &deviceName
            )
            if status == noErr {
                name = deviceName as String
            }
        }
        
        // Get manufacturer
        propertyAddress.mSelector = kAudioObjectPropertyManufacturer
        status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        if status == noErr && dataSize > 0 {
            var mfg = "" as CFString
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0, nil,
                &dataSize,
                &mfg
            )
            if status == noErr {
                manufacturer = mfg as String
            }
        }
        
        // Check if it's input or output
        propertyAddress.mSelector = kAudioDevicePropertyStreams
        propertyAddress.mScope = kAudioDevicePropertyScopeInput
        
        var inputDataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &inputDataSize
        )
        let hasInput = inputDataSize > 0
        
        propertyAddress.mScope = kAudioDevicePropertyScopeOutput
        var outputDataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &outputDataSize
        )
        let hasOutput = outputDataSize > 0
        
        // Get sample rate
        var sampleRate: Float64 = 0.0
        propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
        propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
        dataSize = UInt32(MemoryLayout<Float64>.size)
        
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &sampleRate
        )
        
        // Check if default device
        let isDefaultInput = deviceID == getDefaultDevice(isInput: true)
        let isDefaultOutput = deviceID == getDefaultDevice(isInput: false)
        
        return AudioDeviceInfo(
            id: deviceID,
            name: name.isEmpty ? "Unknown Device" : name,
            manufacturer: manufacturer.isEmpty ? "Unknown" : manufacturer,
            channelCount: 2, // Simplified - would need to query actual channel count
            sampleRate: sampleRate,
            isInput: hasInput,
            isOutput: hasOutput,
            isDefault: isDefaultInput || isDefaultOutput
        )
    }
    
    private func getDefaultDevice(isInput: Bool) -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceID
        )
        
        return deviceID
    }
    
    // MARK: - Device Selection
    
    func selectInputDevice(_ device: AudioDeviceInfo) {
        guard device.isInput else { return }
        
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            ioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            1,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        if status == noErr {
            currentInputDevice = device
            print("✅ Selected input device: \(device.name)")
        } else {
            print("❌ Failed to select input device: \(status)")
        }
    }
    
    func selectOutputDevice(_ device: AudioDeviceInfo) {
        guard device.isOutput else { return }
        
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            ioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        if status == noErr {
            currentOutputDevice = device
            print("✅ Selected output device: \(device.name)")
        } else {
            print("❌ Failed to select output device: \(status)")
        }
    }
    
    // MARK: - Graph Control
    
    func start() {
        guard let graph = augraph else { return }
        
        let status = AUGraphStart(graph)
        if status == noErr {
            isRunning = true
            print("▶️ Audio Graph started")
        } else {
            print("❌ Failed to start graph: \(status)")
        }
    }
    
    func stop() {
        guard let graph = augraph else { return }
        
        let status = AUGraphStop(graph)
        if status == noErr {
            isRunning = false
            print("⏸ Audio Graph stopped")
        } else {
            print("❌ Failed to stop graph: \(status)")
        }
    }
    
    // MARK: - Node Management
    
    func addEffectNode(type: String) -> UUID? {
        // Implementation for adding effect nodes
        // This would create specific Audio Unit effects
        return nil
    }
    
    func removeNode(nodeId: UUID) {
        nodes.removeAll { $0.id == nodeId }
        connections.removeAll { $0.sourceNodeId == nodeId || $0.destinationNodeId == nodeId }
    }
    
    func connectNodes(from sourceId: UUID, sourceBus: Int, to destId: UUID, destBus: Int) {
        let connection = AudioConnection(
            sourceNodeId: sourceId,
            sourceBus: sourceBus,
            destinationNodeId: destId,
            destinationBus: destBus
        )
        connections.append(connection)
    }
    
    // MARK: - Monitoring
    
    func updateLatency() {
        var latency: Float64 = 0.0
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        
        let status = AudioUnitGetProperty(
            ioUnit!,
            kAudioUnitProperty_Latency,
            kAudioUnitScope_Global,
            0,
            &latency,
            &dataSize
        )
        
        if status == noErr {
            DispatchQueue.main.async {
                self.currentLatency = latency * 1000.0 // Convert to milliseconds
            }
        }
    }
    
    func updateCPUUsage() {
        var cpuLoad: Float32 = 0.0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        
        let status = AudioUnitGetProperty(
            ioUnit!,
            kAudioUnitProperty_CPULoad,
            kAudioUnitScope_Global,
            0,
            &cpuLoad,
            &dataSize
        )
        
        if status == noErr {
            DispatchQueue.main.async {
                self.cpuUsage = cpuLoad * 100.0 // Convert to percentage
            }
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        // Setup device change notifications
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            { _, _, _, _ in
                // Device list changed
                return kAudioHardwareNoError
            },
            nil
        )
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        if let graph = augraph {
            AUGraphStop(graph)
            AUGraphUninitialize(graph)
            AUGraphClose(graph)
            DisposeAUGraph(graph)
        }
    }
}

// MARK: - Concrete Node Implementations

class InputNode: AudioNode {
    let id = UUID()
    var name: String
    let type = AudioNodeType.input
    var audioUnit: AudioUnit?
    var isEnabled = true
    let inputBusCount = 0
    let outputBusCount = 1
    
    init(name: String = "Audio Input") {
        self.name = name
    }
}

class OutputNode: AudioNode {
    let id = UUID()
    var name: String
    let type = AudioNodeType.output
    var audioUnit: AudioUnit?
    var isEnabled = true
    let inputBusCount = 1
    let outputBusCount = 0
    
    init(name: String = "Audio Output") {
        self.name = name
    }
}

class MixerNode: AudioNode {
    let id = UUID()
    var name: String
    let type = AudioNodeType.mixer
    var audioUnit: AudioUnit?
    var isEnabled = true
    let inputBusCount = 8  // Multi-channel mixer
    let outputBusCount = 1
    
    init(name: String = "Mixer") {
        self.name = name
    }
}

class EffectNode: AudioNode {
    let id = UUID()
    var name: String
    let type = AudioNodeType.effect
    var audioUnit: AudioUnit?
    var isEnabled = true
    let inputBusCount = 1
    let outputBusCount = 1
    var effectType: String
    
    init(name: String, effectType: String) {
        self.name = name
        self.effectType = effectType
    }
}