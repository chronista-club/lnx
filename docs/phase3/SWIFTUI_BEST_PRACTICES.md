# SwiftUI Best Practices for LNX Experience

## 概要

本ドキュメントは、LNX Experience (LNXX) のリアルタイム音響/視覚表現に特化したSwiftUIベストプラクティスを定義します。60fps維持とレスポンシブな操作性を実現するための具体的な実装パターンを提供します。

## 1. MVVM アーキテクチャの最適化

### 1.1 ViewModelの設計原則

```swift
// ✅ Good: MainActorを活用した非同期処理の分離
@MainActor
final class AudioVisualizationViewModel: ObservableObject {
    // UI更新用のPublished properties
    @Published private(set) var waveformData: [Float] = []
    @Published private(set) var spectrumData: [Float] = []
    @Published private(set) var peakLevel: Float = 0
    
    // 非UI状態の管理（Publishedを避ける）
    private var audioProcessor: AudioProcessor
    private var updateTimer: Timer?
    
    // バックグラウンド処理用のActor
    private let processingActor = AudioProcessingActor()
    
    func startVisualization() async {
        // 重い処理はActorで実行
        let processedData = await processingActor.processAudioBuffer()
        
        // UI更新はMainActorで
        await MainActor.run {
            self.waveformData = processedData.waveform
            self.spectrumData = processedData.spectrum
        }
    }
}

// 専用Actorで重い処理を隔離
actor AudioProcessingActor {
    func processAudioBuffer() async -> ProcessedAudioData {
        // FFT、波形解析などの重い処理
    }
}
```

### 1.2 状態管理の最適化

```swift
// ✅ Good: 必要最小限の@Published使用
struct AudioControlsView: View {
    @StateObject private var audioEngine = AudioEngine()
    
    // ローカル状態は@Stateで管理
    @State private var localVolume: Float = 0.5
    @State private var isDragging = false
    
    var body: some View {
        VStack {
            // Binding使用時は.animationを適切に設定
            Slider(value: $localVolume, in: 0...1) { isDragging in
                if !isDragging {
                    // ドラッグ終了時のみ実際の値を更新
                    audioEngine.setVolume(localVolume)
                }
            }
            .animation(.linear(duration: 0.05), value: localVolume)
        }
    }
}
```

## 2. パフォーマンス最適化パターン

### 2.1 レンダリング最適化

```swift
// ✅ Good: Canvas APIを使用した高速描画
struct WaveformView: View {
    let samples: [Float]
    
    var body: some View {
        Canvas { context, size in
            // 描画コンテキストの再利用
            let path = Path { path in
                let stride = max(1, samples.count / Int(size.width))
                
                for (index, sample) in samples.enumerated() where index % stride == 0 {
                    let x = CGFloat(index) * size.width / CGFloat(samples.count)
                    let y = size.height * 0.5 * (1 - CGFloat(sample))
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            
            context.stroke(path, with: .color(.green), lineWidth: 2)
        }
        .drawingGroup() // Metal最適化を有効化
    }
}
```

### 2.2 更新頻度の制御

```swift
// ✅ Good: TimelineViewで制御された更新
struct SpectrumAnalyzer: View {
    @ObservedObject var audioEngine: AudioEngine
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            SpectrumBars(data: audioEngine.currentSpectrum)
                .onChange(of: timeline.date) { _ in
                    // 60fpsで更新をトリガー
                    audioEngine.updateSpectrum()
                }
        }
    }
}

// ✅ Good: 適応的な更新頻度
struct AdaptiveVisualization: View {
    @State private var complexity: VisualizationComplexity = .normal
    
    var updateInterval: TimeInterval {
        switch complexity {
        case .simple: return 1.0 / 30.0  // 30fps
        case .normal: return 1.0 / 60.0  // 60fps
        case .complex: return 1.0 / 120.0 // 120fps (ProMotion)
        }
    }
}
```

## 3. リアルタイム処理との統合

### 3.1 非同期処理パターン

```swift
// ✅ Good: Structured Concurrencyの活用
@MainActor
class RealtimeAudioViewModel: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var latencyMs: Double = 0
    
    private var processingTask: Task<Void, Never>?
    
    func startProcessing() {
        processingTask?.cancel()
        
        processingTask = Task {
            isProcessing = true
            
            // AsyncStreamで継続的な更新
            for await audioData in audioEngine.audioStream() {
                guard !Task.isCancelled else { break }
                
                // バックプレッシャー対策
                if !isOverloaded() {
                    await processAudioData(audioData)
                }
            }
            
            isProcessing = false
        }
    }
    
    private func isOverloaded() -> Bool {
        // CPU使用率やバッファ状態を確認
        return ProcessInfo.processInfo.systemUptime < 0.016 // 16ms threshold
    }
}
```

### 3.2 Combineを使用したリアクティブ処理

```swift
// ✅ Good: Combineでのストリーム処理
import Combine

class AudioStreamProcessor: ObservableObject {
    @Published var processedSamples: [Float] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init(audioEngine: AudioEngine) {
        // バッファリングとスロットリング
        audioEngine.samplePublisher
            .buffer(size: 512, prefetch: .byRequest, whenFull: .dropOldest)
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .map { samples in
                // 軽量な前処理
                samples.map { $0 * 0.8 }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.processedSamples, on: self)
            .store(in: &cancellables)
    }
}
```

## 4. メモリ管理とリソース最適化

### 4.1 大容量データの効率的な扱い

```swift
// ✅ Good: メモリマップドファイルの活用
struct LargeWaveformView: View {
    let fileURL: URL
    @State private var visibleSamples: [Float] = []
    @State private var zoomLevel: Float = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            WaveformCanvas(samples: visibleSamples)
                .onAppear {
                    loadVisibleSamples(for: geometry.size)
                }
                .onChange(of: zoomLevel) { _ in
                    loadVisibleSamples(for: geometry.size)
                }
        }
    }
    
    private func loadVisibleSamples(for size: CGSize) {
        Task {
            // 表示領域のみをメモリに読み込み
            let samples = await AudioFileReader.readSamples(
                from: fileURL,
                range: visibleRange(for: size),
                decimation: decimationFactor(for: size)
            )
            visibleSamples = samples
        }
    }
}
```

### 4.2 View階層の最適化

```swift
// ✅ Good: LazyスタックとIDによる効率化
struct MultiTrackView: View {
    let tracks: [AudioTrack]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(tracks) { track in
                    TrackRow(track: track)
                        .id(track.id) // 明示的なID指定
                        .frame(height: 100)
                        .equatable() // カスタムEquatable実装
                }
            }
        }
    }
}

// Equatable実装で不要な再描画を防ぐ
struct TrackRow: View, Equatable {
    let track: AudioTrack
    
    static func == (lhs: TrackRow, rhs: TrackRow) -> Bool {
        // 表示に影響する属性のみ比較
        lhs.track.id == rhs.track.id &&
        lhs.track.name == rhs.track.name &&
        lhs.track.isPlaying == rhs.track.isPlaying
    }
    
    var body: some View {
        // ...
    }
}
```

## 5. ジェスチャーとインタラクション

### 5.1 低レイテンシージェスチャー処理

```swift
// ✅ Good: 高頻度ジェスチャーの最適化
struct ScrubberView: View {
    @Binding var position: Double
    @State private var localPosition: Double = 0
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.blue)
                .frame(width: 4)
                .position(x: localPosition * geometry.size.width)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                            }
                            // ローカル更新のみ（高速）
                            localPosition = value.location.x / geometry.size.width
                        }
                        .onEnded { value in
                            isDragging = false
                            // 最終値のみ親に伝達
                            position = localPosition
                        }
                )
                .highPriorityGesture(TapGesture()) // タップを優先
        }
    }
}
```

## 6. カスタムレンダリング

### 6.1 Metal統合

```swift
// ✅ Good: MetalKitビューの統合
import MetalKit

struct MetalVisualizerView: UIViewRepresentable {
    @ObservedObject var audioEngine: AudioEngine
    
    func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.delegate = context.coordinator
        metalView.preferredFramesPerSecond = 60
        metalView.enableSetNeedsDisplay = false
        return metalView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.audioData = audioEngine.currentBuffer
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalVisualizerView
        var audioData: AudioBuffer?
        
        init(_ parent: MetalVisualizerView) {
            self.parent = parent
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            // Metal描画処理
            guard let audioData = audioData else { return }
            // シェーダーによる高速レンダリング
        }
    }
}
```

## 7. デバッグとプロファイリング

### 7.1 パフォーマンス計測

```swift
// ✅ Good: 計測用モディファイア
struct PerformanceOverlay: ViewModifier {
    @State private var frameRate: Double = 0
    @State private var lastUpdate = Date()
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Text("FPS: \(Int(frameRate))")
                    .font(.caption)
                    .padding(4)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.green)
            }
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                let now = Date()
                let delta = now.timeIntervalSince(lastUpdate)
                frameRate = 1.0 / delta
                lastUpdate = now
            }
    }
}

extension View {
    func measurePerformance() -> some View {
        self.modifier(PerformanceOverlay())
    }
}
```

## まとめ

LNX Experienceの60fps目標達成には：

1. **MainActorの適切な使用** - UI更新と重い処理の分離
2. **Canvas/Metalの活用** - 高速描画の実現
3. **メモリ効率** - 大容量ファイルの段階的読み込み
4. **更新制御** - TimelineViewとCombineの活用
5. **ジェスチャー最適化** - ローカル状態での高速応答

これらのパターンを組み合わせることで、プロフェッショナルグレードのリアルタイム音響/視覚表現を実現します。