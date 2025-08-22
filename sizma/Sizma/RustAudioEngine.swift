//
//  RustAudioEngine.swift
//  LNXX
//
//  Created by Claude on 2025/08/11.
//

import Foundation
import SwiftUI

// MARK: - Rust Audio Engine Bridge

// Dynamic library loading
class RustLibrary {
    static let shared = RustLibrary()
    
    private var handle: UnsafeMutableRawPointer?
    private var isLoaded = false
    
    // Function pointers
    var lnx_engine_create: (() -> OpaquePointer?)?
    var lnx_engine_destroy: ((OpaquePointer?) -> Void)?
    var lnx_engine_initialize: ((OpaquePointer?) -> Int32)?
    var lnx_engine_start: ((OpaquePointer?) -> Int32)?
    var lnx_engine_stop: ((OpaquePointer?) -> Int32)?
    var lnx_engine_is_running: ((OpaquePointer?) -> Int32)?
    var lnx_engine_get_sample_rate: ((OpaquePointer?) -> UInt32)?
    var lnx_engine_get_buffer_size: ((OpaquePointer?) -> UInt32)?
    var lnx_engine_set_buffer_size: ((OpaquePointer?, UInt32) -> Int32)?
    var lnx_engine_process_messages: ((OpaquePointer?) -> Int32)?
    
    private init() {
        loadLibrary()
    }
    
    private func loadLibrary() {
        // Try to load from multiple possible locations
        let paths = [
            // Bundle path
            Bundle.main.bundlePath + "/Contents/Frameworks/libaudio_engine.dylib",
            // Local development path
            NSHomeDirectory() + "/repos/sizma/audio-engine/target/release/libaudio_engine.dylib",
            // Copy in project directory
            Bundle.main.bundlePath + "/../../../sizma/libaudio_engine.dylib",
        ]
        
        for path in paths {
            if let handle = dlopen(path, RTLD_NOW) {
                self.handle = handle
                print("✅ Loaded Rust library from: \(path)")
                loadFunctions()
                isLoaded = true
                return
            }
        }
        
        print("❌ Failed to load Rust audio engine library")
        print("Tried paths:")
        for path in paths {
            print("  - \(path)")
        }
    }
    
    private func loadFunctions() {
        guard let handle = handle else { return }
        
        // Load all function pointers
        lnx_engine_create = unsafeBitCast(dlsym(handle, "lnx_engine_create"), to: (() -> OpaquePointer?)?.self)
        lnx_engine_destroy = unsafeBitCast(dlsym(handle, "lnx_engine_destroy"), to: ((OpaquePointer?) -> Void)?.self)
        lnx_engine_initialize = unsafeBitCast(dlsym(handle, "lnx_engine_initialize"), to: ((OpaquePointer?) -> Int32)?.self)
        lnx_engine_start = unsafeBitCast(dlsym(handle, "lnx_engine_start"), to: ((OpaquePointer?) -> Int32)?.self)
        lnx_engine_stop = unsafeBitCast(dlsym(handle, "lnx_engine_stop"), to: ((OpaquePointer?) -> Int32)?.self)
        lnx_engine_is_running = unsafeBitCast(dlsym(handle, "lnx_engine_is_running"), to: ((OpaquePointer?) -> Int32)?.self)
        lnx_engine_get_sample_rate = unsafeBitCast(dlsym(handle, "lnx_engine_get_sample_rate"), to: ((OpaquePointer?) -> UInt32)?.self)
        lnx_engine_get_buffer_size = unsafeBitCast(dlsym(handle, "lnx_engine_get_buffer_size"), to: ((OpaquePointer?) -> UInt32)?.self)
        lnx_engine_set_buffer_size = unsafeBitCast(dlsym(handle, "lnx_engine_set_buffer_size"), to: ((OpaquePointer?, UInt32) -> Int32)?.self)
        lnx_engine_process_messages = unsafeBitCast(dlsym(handle, "lnx_engine_process_messages"), to: ((OpaquePointer?) -> Int32)?.self)
    }
    
    var isAvailable: Bool {
        return isLoaded
    }
}

// Wrapper functions
func lnx_engine_create() -> OpaquePointer? {
    return RustLibrary.shared.lnx_engine_create?() ?? nil
}

func lnx_engine_destroy(_ engine: OpaquePointer?) {
    RustLibrary.shared.lnx_engine_destroy?(engine)
}

func lnx_engine_initialize(_ engine: OpaquePointer?) -> Int32 {
    return RustLibrary.shared.lnx_engine_initialize?(engine) ?? -1
}

func lnx_engine_start(_ engine: OpaquePointer?) -> Int32 {
    return RustLibrary.shared.lnx_engine_start?(engine) ?? -1
}

func lnx_engine_stop(_ engine: OpaquePointer?) -> Int32 {
    return RustLibrary.shared.lnx_engine_stop?(engine) ?? -1
}

func lnx_engine_is_running(_ engine: OpaquePointer?) -> Int32 {
    return RustLibrary.shared.lnx_engine_is_running?(engine) ?? 0
}

func lnx_engine_get_sample_rate(_ engine: OpaquePointer?) -> UInt32 {
    return RustLibrary.shared.lnx_engine_get_sample_rate?(engine) ?? 0
}

func lnx_engine_get_buffer_size(_ engine: OpaquePointer?) -> UInt32 {
    return RustLibrary.shared.lnx_engine_get_buffer_size?(engine) ?? 0
}

func lnx_engine_set_buffer_size(_ engine: OpaquePointer?, _ size: UInt32) -> Int32 {
    return RustLibrary.shared.lnx_engine_set_buffer_size?(engine, size) ?? -1
}

func lnx_engine_process_messages(_ engine: OpaquePointer?) -> Int32 {
    return RustLibrary.shared.lnx_engine_process_messages?(engine) ?? -1
}

// Stub functions for graph operations (these need to be added to RustLibrary class)
func lnx_graph_add_node(_ engine: OpaquePointer?, _ nodeType: Int32, _ name: UnsafePointer<CChar>?) -> UInt32 {
    // TODO: Implement dynamic loading for this function
    return 0
}

func lnx_graph_remove_node(_ engine: OpaquePointer?, _ nodeId: UInt32) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

func lnx_graph_connect_nodes(_ engine: OpaquePointer?, _ sourceNode: UInt32, _ sourceChannel: UInt32, _ destNode: UInt32, _ destChannel: UInt32) -> UInt32 {
    // TODO: Implement dynamic loading for this function
    return 0
}

func lnx_graph_disconnect(_ engine: OpaquePointer?, _ connectionId: UInt32) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

func lnx_node_set_gain(_ engine: OpaquePointer?, _ nodeId: UInt32, _ gain: Float) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

func lnx_node_set_pan(_ engine: OpaquePointer?, _ nodeId: UInt32, _ pan: Float) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

func lnx_node_set_enabled(_ engine: OpaquePointer?, _ nodeId: UInt32, _ enabled: Int32) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

func lnx_effect_set_parameter(_ engine: OpaquePointer?, _ nodeId: UInt32, _ paramName: UnsafePointer<CChar>?, _ value: Float) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

func lnx_effect_get_parameter(_ engine: OpaquePointer?, _ nodeId: UInt32, _ paramName: UnsafePointer<CChar>?, _ value: UnsafeMutablePointer<Float>?) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

func lnx_device_select_input(_ engine: OpaquePointer?, _ deviceName: UnsafePointer<CChar>?) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

func lnx_device_select_output(_ engine: OpaquePointer?, _ deviceName: UnsafePointer<CChar>?) -> Int32 {
    // TODO: Implement dynamic loading for this function
    return -1
}

// MARK: - Node Types

enum RustNodeType: Int32 {
    case input = 0
    case output = 1
    case mixer = 2
    case effect = 3
    case generator = 4
    case analyzer = 5
}

// MARK: - Rust Audio Engine Manager

class RustAudioEngineManager: ObservableObject {
    @Published var isRunning = false
    @Published var sampleRate: UInt32 = 48000
    @Published var bufferSize: UInt32 = 256
    @Published var nodes: [NodeInfo] = []
    @Published var connections: [ConnectionInfo] = []
    @Published var cpuUsage: Float = 0.0
    @Published var latency: Double = 0.0
    
    private var engineHandle: OpaquePointer?
    private var messageTimer: Timer?
    
    struct NodeInfo: Identifiable {
        let id: UInt32
        let name: String
        let type: RustNodeType
        var gain: Float = 1.0
        var pan: Float = 0.0
        var enabled: Bool = true
    }
    
    struct ConnectionInfo: Identifiable {
        let id: UInt32
        let sourceNode: UInt32
        let sourceChannel: UInt32
        let destNode: UInt32
        let destChannel: UInt32
        var gain: Float = 1.0
        var enabled: Bool = true
    }
    
    init() {
        createEngine()
        startMessageProcessing()
    }
    
    deinit {
        stopEngine()
        destroyEngine()
    }
    
    // MARK: - Engine Lifecycle
    
    private func createEngine() {
        // Check if library is available
        guard RustLibrary.shared.isAvailable else {
            print("⚠️ Rust audio engine library not available")
            return
        }
        
        engineHandle = lnx_engine_create()
        guard engineHandle != nil else {
            print("❌ Failed to create Rust audio engine")
            return
        }
        
        let result = lnx_engine_initialize(engineHandle)
        if result == 0 {
            print("✅ Rust audio engine initialized")
            updateEngineInfo()
        } else {
            print("❌ Failed to initialize Rust audio engine")
        }
    }
    
    private func destroyEngine() {
        stopMessageProcessing()
        if let handle = engineHandle {
            lnx_engine_destroy(handle)
            engineHandle = nil
        }
    }
    
    func startEngine() {
        guard let handle = engineHandle else { return }
        
        let result = lnx_engine_start(handle)
        if result == 0 {
            isRunning = true
            print("▶️ Rust audio engine started")
        } else {
            print("❌ Failed to start Rust audio engine")
        }
    }
    
    func stopEngine() {
        guard let handle = engineHandle else { return }
        
        let result = lnx_engine_stop(handle)
        if result == 0 {
            isRunning = false
            print("⏸ Rust audio engine stopped")
        } else {
            print("❌ Failed to stop Rust audio engine")
        }
    }
    
    // MARK: - Configuration
    
    func setBufferSize(_ size: UInt32) {
        guard let handle = engineHandle else { return }
        
        let result = lnx_engine_set_buffer_size(handle, size)
        if result == 0 {
            bufferSize = size
            print("📊 Buffer size set to \(size)")
        }
    }
    
    private func updateEngineInfo() {
        guard let handle = engineHandle else { return }
        
        sampleRate = lnx_engine_get_sample_rate(handle)
        bufferSize = lnx_engine_get_buffer_size(handle)
        isRunning = lnx_engine_is_running(handle) != 0
    }
    
    // MARK: - Graph Operations
    
    func addNode(type: RustNodeType, name: String) -> UInt32? {
        guard let handle = engineHandle else { return nil }
        
        let nodeId = name.withCString { cString in
            lnx_graph_add_node(handle, type.rawValue, cString)
        }
        
        if nodeId > 0 {
            let nodeInfo = NodeInfo(id: nodeId, name: name, type: type)
            nodes.append(nodeInfo)
            print("➕ Added node: \(name) (ID: \(nodeId))")
            return nodeId
        }
        
        return nil
    }
    
    func removeNode(nodeId: UInt32) {
        guard let handle = engineHandle else { return }
        
        let result = lnx_graph_remove_node(handle, nodeId)
        if result == 0 {
            nodes.removeAll { $0.id == nodeId }
            connections.removeAll { $0.sourceNode == nodeId || $0.destNode == nodeId }
            print("➖ Removed node: \(nodeId)")
        }
    }
    
    func connectNodes(sourceNode: UInt32, sourceChannel: UInt32, destNode: UInt32, destChannel: UInt32) -> UInt32? {
        guard let handle = engineHandle else { return nil }
        
        let connectionId = lnx_graph_connect_nodes(handle, sourceNode, sourceChannel, destNode, destChannel)
        
        if connectionId > 0 {
            let connectionInfo = ConnectionInfo(
                id: connectionId,
                sourceNode: sourceNode,
                sourceChannel: sourceChannel,
                destNode: destNode,
                destChannel: destChannel
            )
            connections.append(connectionInfo)
            print("🔗 Connected nodes: \(sourceNode) -> \(destNode) (ID: \(connectionId))")
            return connectionId
        }
        
        return nil
    }
    
    func disconnect(connectionId: UInt32) {
        guard let handle = engineHandle else { return }
        
        let result = lnx_graph_disconnect(handle, connectionId)
        if result == 0 {
            connections.removeAll { $0.id == connectionId }
            print("🔗 Disconnected: \(connectionId)")
        }
    }
    
    // MARK: - Node Control
    
    func setNodeGain(nodeId: UInt32, gain: Float) {
        guard let handle = engineHandle else { return }
        
        let result = lnx_node_set_gain(handle, nodeId, gain)
        if result == 0 {
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[index].gain = gain
            }
        }
    }
    
    func setNodePan(nodeId: UInt32, pan: Float) {
        guard let handle = engineHandle else { return }
        
        let result = lnx_node_set_pan(handle, nodeId, pan)
        if result == 0 {
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[index].pan = pan
            }
        }
    }
    
    func setNodeEnabled(nodeId: UInt32, enabled: Bool) {
        guard let handle = engineHandle else { return }
        
        let result = lnx_node_set_enabled(handle, nodeId, enabled ? 1 : 0)
        if result == 0 {
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[index].enabled = enabled
            }
        }
    }
    
    // MARK: - Effect Parameters
    
    func setEffectParameter(nodeId: UInt32, paramName: String, value: Float) {
        guard let handle = engineHandle else { return }
        
        paramName.withCString { cString in
            let _ = lnx_effect_set_parameter(handle, nodeId, cString, value)
        }
    }
    
    func getEffectParameter(nodeId: UInt32, paramName: String) -> Float? {
        guard let handle = engineHandle else { return nil }
        
        var value: Float = 0.0
        let result = paramName.withCString { cString in
            lnx_effect_get_parameter(handle, nodeId, cString, &value)
        }
        
        return result == 0 ? value : nil
    }
    
    // MARK: - Device Selection
    
    func selectInputDevice(_ deviceName: String) {
        guard let handle = engineHandle else { return }
        
        deviceName.withCString { cString in
            let result = lnx_device_select_input(handle, cString)
            if result == 0 {
                print("🎙 Selected input device: \(deviceName)")
            }
        }
    }
    
    func selectOutputDevice(_ deviceName: String) {
        guard let handle = engineHandle else { return }
        
        deviceName.withCString { cString in
            let result = lnx_device_select_output(handle, cString)
            if result == 0 {
                print("🔊 Selected output device: \(deviceName)")
            }
        }
    }
    
    // MARK: - Message Processing
    
    private func startMessageProcessing() {
        messageTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.processMessages()
        }
    }
    
    private func stopMessageProcessing() {
        messageTimer?.invalidate()
        messageTimer = nil
    }
    
    private func processMessages() {
        guard let handle = engineHandle else { return }
        let _ = lnx_engine_process_messages(handle)
    }
    
    // MARK: - Demo Setup
    
    func setupDemoGraph() {
        // Create a simple audio graph for testing
        if let inputNode = addNode(type: .input, name: "System Input"),
           let mixerNode = addNode(type: .mixer, name: "Main Mixer"),
           let outputNode = addNode(type: .output, name: "System Output") {
            
            // Connect input to mixer
            _ = connectNodes(sourceNode: inputNode, sourceChannel: 0, destNode: mixerNode, destChannel: 0)
            _ = connectNodes(sourceNode: inputNode, sourceChannel: 1, destNode: mixerNode, destChannel: 1)
            
            // Connect mixer to output
            _ = connectNodes(sourceNode: mixerNode, sourceChannel: 0, destNode: outputNode, destChannel: 0)
            _ = connectNodes(sourceNode: mixerNode, sourceChannel: 1, destNode: outputNode, destChannel: 1)
            
            print("📊 Demo audio graph created")
        }
    }
}