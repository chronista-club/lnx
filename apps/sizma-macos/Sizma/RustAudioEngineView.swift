//
//  RustAudioEngineView.swift
//  LNXX
//
//  Created by Claude on 2025/08/11.
//

import SwiftUI

struct RustAudioEngineView: View {
    @EnvironmentObject var rustAudioEngine: RustAudioEngineManager
    
    var body: some View {
        VStack(spacing: 20) {
            // エンジン状態
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Engine Status", systemImage: "waveform.circle")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        Label(rustAudioEngine.isRunning ? "Running" : "Stopped", 
                              systemImage: rustAudioEngine.isRunning ? "play.circle.fill" : "stop.circle")
                            .foregroundColor(rustAudioEngine.isRunning ? .green : .gray)
                        
                        Text("Sample Rate: \(rustAudioEngine.sampleRate) Hz")
                            .font(.caption)
                        
                        Text("Buffer: \(rustAudioEngine.bufferSize) samples")
                            .font(.caption)
                        
                        Text(String(format: "Latency: %.2f ms", rustAudioEngine.latency))
                            .font(.caption)
                        
                        Text(String(format: "CPU: %.1f%%", rustAudioEngine.cpuUsage))
                            .font(.caption)
                    }
                }
                
                Spacer()
                
                // コントロールボタン
                HStack(spacing: 10) {
                    Button(action: {
                        if rustAudioEngine.isRunning {
                            rustAudioEngine.stopEngine()
                        } else {
                            rustAudioEngine.startEngine()
                        }
                    }) {
                        Label(rustAudioEngine.isRunning ? "Stop" : "Start", 
                              systemImage: rustAudioEngine.isRunning ? "stop.fill" : "play.fill")
                    }
                    .controlSize(.large)
                    
                    Button("Reset Graph") {
                        rustAudioEngine.setupDemoGraph()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // ノードリスト
            if !rustAudioEngine.nodes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Audio Nodes", systemImage: "circle.grid.3x3")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rustAudioEngine.nodes) { node in
                                HStack {
                                    Image(systemName: nodeIcon(for: node.type))
                                        .foregroundColor(node.enabled ? .accentColor : .gray)
                                    Text(node.name)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    
                                    // Gain control
                                    Text("Gain:")
                                        .font(.caption)
                                    Slider(value: Binding(
                                        get: { node.gain },
                                        set: { rustAudioEngine.setNodeGain(nodeId: node.id, gain: $0) }
                                    ), in: 0...2)
                                    .frame(width: 100)
                                    
                                    // Enable toggle
                                    Toggle("", isOn: Binding(
                                        get: { node.enabled },
                                        set: { rustAudioEngine.setNodeEnabled(nodeId: node.id, enabled: $0) }
                                    ))
                                    .toggleStyle(SwitchToggleStyle())
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // 接続リスト
            if !rustAudioEngine.connections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connections", systemImage: "arrow.left.and.right")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rustAudioEngine.connections) { connection in
                                HStack {
                                    Text("Node \(connection.sourceNode)")
                                        .font(.caption)
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                    Text("Node \(connection.destNode)")
                                        .font(.caption)
                                    Spacer()
                                    Text("Ch \(connection.sourceChannel) → \(connection.destChannel)")
                                        .font(.caption.monospaced())
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(connection.enabled ? 
                                    Color.accentColor.opacity(0.1) : 
                                    Color.gray.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
    }
    
    func nodeIcon(for type: RustNodeType) -> String {
        switch type {
        case .input: return "waveform.path.ecg"
        case .output: return "speaker.wave.2"
        case .mixer: return "slider.horizontal.below.rectangle"
        case .effect: return "wand.and.stars"
        case .generator: return "waveform"
        case .analyzer: return "chart.xyaxis.line"
        }
    }
}