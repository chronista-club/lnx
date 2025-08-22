//
//  SplashView.swift
//  LNXX
//
//  Created by m.ito on 2025/08/11.
//

import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    @State private var showMainView = false
    @EnvironmentObject var midiManager: MIDIManager
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        Group {
            if showMainView {
                MainView()
                    .environmentObject(midiManager)
                    .environmentObject(audioEngine)
            } else {
                VStack(spacing: 30) {
                    Image(systemName: "waveform")
                        .font(.system(size: 80))
                        .foregroundStyle(.tint)
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0.3)
                    
                    VStack(spacing: 10) {
                        Text("LNX Experience")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .opacity(isAnimating ? 1.0 : 0.0)
                        
                        Text("音と映像の波を起こし、新たな体験を創造する")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .opacity(isAnimating ? 1.0 : 0.0)
                    }
                }
                .padding()
                .frame(width: 800, height: 600)
                .task {
                    withAnimation(.easeInOut(duration: 1.5)) {
                        isAnimating = true
                    }
                    
                    // 2秒待機
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    
                    showMainView = true
                }
            }
        }
    }
}

#Preview {
    SplashView()
}