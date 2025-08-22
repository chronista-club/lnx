# LNX Experience 技術スタック統合アーキテクチャ

## 文書情報
- **バージョン**: 2.0.0
- **作成日**: 2025-08-09
- **対象**: SwiftUI + Core Audio + Metal 統合設計
- **目標レイテンシ**: 5ms以下

---

## 1. 統合アーキテクチャ概要

### 1.1 技術スタック全体像

```
┌──────────────────────────────────────────────────────────┐
│                    User Interface Layer                    │
│                        (SwiftUI)                           │
├──────────────────────────────────────────────────────────┤
│                    Coordination Layer                      │
│              (Combine + Swift Concurrency)                 │
├─────────────────────┬────────────────┬──────────────────┤
│    Audio Engine     │  Sync Manager   │  Visual Engine   │
│   (Core Audio)      │(DispatchSource) │     (Metal)      │
├─────────────────────┴────────────────┴──────────────────┤
│                    Hardware Abstraction                    │
│              (AVAudioSession, MTLDevice)                  │
├──────────────────────────────────────────────────────────┤
│                      macOS Kernel                         │
│            (Audio HAL, GPU Driver, IOKit)                 │
└──────────────────────────────────────────────────────────┘
```

### 1.2 データフロー

```
Audio Input → Core Audio → Processing → Sync Manager → Visual Engine → Metal → Display
     ↓                          ↓            ↓              ↓
  SwiftUI ← State Updates ← Combine ← Notifications ← Event Bus
```

---

## 2. Core Audio 統合

### 2.1 低レイテンシオーディオパイプライン

```swift
// AudioEngineConfiguration.swift
import AVFoundation
import CoreAudio

class LNXAudioEngine {
    private let audioEngine = AVAudioEngine()
    private var ioBufferDuration: TimeInterval = 0.001 // 1ms target
    
    // MARK: - 低レイテンシ設定
    func configureForLowLatency() async throws {
        let session = AVAudioSession.sharedInstance()
        
        // 1. カテゴリとモード設定
        try session.setCategory(.playAndRecord,
                               mode: .measurement,  // 最低レイテンシモード
                               options: [.allowBluetooth, .defaultToSpeaker])
        
        // 2. バッファサイズ最小化
        try session.setPreferredIOBufferDuration(ioBufferDuration)
        
        // 3. サンプルレート最適化
        try session.setPreferredSampleRate(48000) // 標準プロ仕様
        
        // 4. ハードウェアフォーマット取得
        let hwFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        
        // 5. レンダーコールバック設定
        installTapOnBus(audioEngine.inputNode, format: hwFormat)
        
        // 6. エンジン起動
        try audioEngine.start()
        try session.setActive(true)
    }
    
    // MARK: - リアルタイム処理コールバック
    private func installTapOnBus(_ node: AVAudioNode, format: AVAudioFormat) {
        let bufferSize = AVAudioFrameCount(64) // 64サンプル @ 48kHz = 1.33ms
        
        node.installTap(onBus: 0,
                       bufferSize: bufferSize,
                       format: format) { [weak self] buffer, when in
            // リアルタイムスレッドで実行
            self?.processAudioBuffer(buffer, when: when)
        }
    }
    
    // MARK: - オーディオ処理（リアルタイムセーフ）
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        // 重要: このメソッド内では絶対に以下を行わない
        // - メモリアロケーション
        // - ロック取得
        // - Objective-Cメッセージ送信
        // - ディスパッチ
        
        // プリアロケートされたバッファに処理
        AudioProcessor.process(buffer, into: preallocatedBuffer)
        
        // ロックフリーキューで他スレッドに通知
        audioDataQueue.enqueue(preallocatedBuffer)
    }
}
```

### 2.2 Audio Unit 統合

```swift
// AudioUnitProcessor.swift
import AudioToolbox

class AudioUnitProcessor {
    private var processingGraph: AUGraph?
    private var mixerUnit: AudioUnit?
    private var outputUnit: AudioUnit?
    
    func setupProcessingGraph() throws {
        // 1. グラフ作成
        NewAUGraph(&processingGraph)
        
        // 2. ノード追加
        var mixerNode = AUNode()
        var outputNode = AUNode()
        
        var mixerDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_MultiChannelMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        AUGraphAddNode(processingGraph!, &mixerDesc, &mixerNode)
        
        // 3. 接続
        AUGraphConnectNodeInput(processingGraph!,
                                mixerNode, 0,
                                outputNode, 0)
        
        // 4. レンダーコールバック設定
        let renderCallback = AURenderCallbackStruct(
            inputProc: audioRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        AudioUnitSetProperty(mixerUnit!,
                           kAudioUnitProperty_SetRenderCallback,
                           kAudioUnitScope_Input,
                           0,
                           &renderCallback,
                           UInt32(MemoryLayout<AURenderCallbackStruct>.size))
    }
}

// C関数（最高パフォーマンス）
private func audioRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    // DSP処理をここで実行
    return noErr
}
```

---

## 3. Metal 統合

### 3.1 リアルタイムビジュアルパイプライン

```swift
// MetalVisualEngine.swift
import Metal
import MetalKit
import MetalPerformanceShaders

class MetalVisualEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let computePipeline: MTLComputePipelineState
    
    // MARK: - Triple Buffering for smooth rendering
    private var frameBuffers: [MTLBuffer] = []
    private var currentBufferIndex = 0
    private let bufferSemaphore = DispatchSemaphore(value: 3)
    
    init() throws {
        // 1. デバイス取得（統合GPU優先）
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalError.noDevice
        }
        self.device = device
        
        // 2. コマンドキュー作成
        guard let queue = device.makeCommandQueue() else {
            throw MetalError.noCommandQueue
        }
        self.commandQueue = queue
        
        // 3. シェーダーライブラリロード
        let library = try device.makeDefaultLibrary()
        
        // 4. パイプライン作成
        self.pipelineState = try createRenderPipeline(device: device, library: library)
        self.computePipeline = try createComputePipeline(device: device, library: library)
        
        // 5. バッファ事前確保
        setupTripleBuffering()
    }
    
    // MARK: - レンダリングループ
    func render(audioData: AudioAnalysisData, drawable: CAMetalDrawable) {
        bufferSemaphore.wait()
        
        autoreleasepool {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            
            // セマフォ解放をコマンドバッファ完了時に
            commandBuffer.addCompletedHandler { [weak self] _ in
                self?.bufferSemaphore.signal()
            }
            
            // 1. Compute Pass: オーディオデータ処理
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                processAudioVisualization(encoder: computeEncoder, audioData: audioData)
                computeEncoder.endEncoding()
            }
            
            // 2. Render Pass: ビジュアル描画
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderVisuals(encoder: renderEncoder)
                renderEncoder.endEncoding()
            }
            
            // 3. プレゼント
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    // MARK: - GPU計算シェーダー
    private func processAudioVisualization(encoder: MTLComputeCommandEncoder, audioData: AudioAnalysisData) {
        encoder.setComputePipelineState(computePipeline)
        
        // オーディオデータをGPUバッファにコピー
        let dataBuffer = device.makeBuffer(bytes: audioData.samples,
                                          length: audioData.samples.count * MemoryLayout<Float>.size,
                                          options: .storageModeShared)
        
        encoder.setBuffer(dataBuffer, offset: 0, index: 0)
        encoder.setBuffer(frameBuffers[currentBufferIndex], offset: 0, index: 1)
        
        // スレッドグループ設定
        let threadsPerGroup = MTLSize(width: 32, height: 1, depth: 1)
        let numGroups = MTLSize(width: (audioData.samples.count + 31) / 32, height: 1, depth: 1)
        
        encoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
    }
}
```

### 3.2 Metal Performance Shaders 活用

```swift
// MPSAcceleration.swift
import MetalPerformanceShaders

class MPSAccelerator {
    private let device: MTLDevice
    private var fftProcessor: MPSFFTT?
    
    // MARK: - FFT高速化
    func setupFFTProcessor(size: Int) {
        let descriptor = MPSFFTDescriptor(size: size)
        fftProcessor = MPSFFTT(device: device, descriptor: descriptor)
    }
    
    func performFFT(inputBuffer: MTLBuffer, outputBuffer: MTLBuffer, commandBuffer: MTLCommandBuffer) {
        fftProcessor?.encode(commandBuffer: commandBuffer,
                            inputBuffer: inputBuffer,
                            outputBuffer: outputBuffer)
    }
    
    // MARK: - 画像処理
    func applyBlur(texture: MTLTexture, sigma: Float) -> MTLTexture {
        let blur = MPSImageGaussianBlur(device: device, sigma: sigma)
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return texture
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        blur.encode(commandBuffer: commandBuffer,
                   sourceTexture: texture,
                   destinationTexture: outputTexture)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputTexture
    }
}
```

---

## 4. SwiftUI 統合

### 4.1 リアクティブUI設計

```swift
// AudioVisualView.swift
import SwiftUI
import Combine

struct AudioVisualView: View {
    @StateObject private var viewModel = AudioVisualViewModel()
    @State private var displayLink: CADisplayLink?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Metal レンダリングビュー
                MetalView(viewModel: viewModel)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                // SwiftUI オーバーレイ
                ControlOverlay(viewModel: viewModel)
            }
        }
        .onAppear {
            setupDisplayLink()
        }
        .onDisappear {
            displayLink?.invalidate()
        }
    }
    
    // MARK: - 120Hz ProMotion対応
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: viewModel, selector: #selector(viewModel.update))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink?.add(to: .current, forMode: .common)
    }
}

// MARK: - Metal統合View
struct MetalView: NSViewRepresentable {
    @ObservedObject var viewModel: AudioVisualViewModel
    
    func makeNSView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.delegate = context.coordinator
        metalView.preferredFramesPerSecond = 120 // ProMotion
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        return metalView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // ViewModel変更をMetalレンダラーに伝達
        context.coordinator.updateFromViewModel(viewModel)
    }
    
    func makeCoordinator() -> MetalCoordinator {
        MetalCoordinator(viewModel: viewModel)
    }
}

// MARK: - Coordinator for Metal/SwiftUI Bridge
class MetalCoordinator: NSObject, MTKViewDelegate {
    private let viewModel: AudioVisualViewModel
    private var renderer: MetalVisualEngine?
    
    init(viewModel: AudioVisualViewModel) {
        self.viewModel = viewModel
        super.init()
        setupRenderer()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.resize(to: size)
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let audioData = viewModel.currentAudioData else { return }
        
        renderer?.render(audioData: audioData, drawable: drawable)
    }
}
```

### 4.2 State Management with Combine

```swift
// AudioVisualViewModel.swift
import Combine
import SwiftUI

@MainActor
class AudioVisualViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var spectrumData: [Float] = []
    
    // MARK: - Audio Data Stream
    private let audioDataSubject = PassthroughSubject<AudioAnalysisData, Never>()
    var currentAudioData: AudioAnalysisData?
    
    private var cancellables = Set<AnyCancellable>()
    private let audioEngine = LNXAudioEngine()
    
    init() {
        setupBindings()
    }
    
    // MARK: - Reactive Bindings
    private func setupBindings() {
        // オーディオデータストリーム処理
        audioDataSubject
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true) // 60fps
            .sink { [weak self] data in
                self?.processAudioData(data)
            }
            .store(in: &cancellables)
        
        // レベルメーター更新
        $audioLevel
            .removeDuplicates()
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] level in
                self?.updateLevelMeter(level)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Audio Processing
    private func processAudioData(_ data: AudioAnalysisData) {
        currentAudioData = data
        
        // FFT実行
        Task {
            let spectrum = await performFFT(data.samples)
            await MainActor.run {
                self.spectrumData = spectrum
            }
        }
    }
    
    @objc func update() {
        // DisplayLink コールバック（高頻度更新）
        // ここでリアルタイムデータを取得
    }
}
```

---

## 5. メモリ管理とGPU最適化

### 5.1 メモリプール設計

```swift
// MemoryPoolManager.swift
class MemoryPoolManager {
    // MARK: - Buffer Pool
    private class BufferPool {
        private var availableBuffers: [MTLBuffer] = []
        private let device: MTLDevice
        private let bufferSize: Int
        private let maxBuffers: Int
        
        init(device: MTLDevice, bufferSize: Int, maxBuffers: Int = 10) {
            self.device = device
            self.bufferSize = bufferSize
            self.maxBuffers = maxBuffers
            preallocate()
        }
        
        private func preallocate() {
            for _ in 0..<maxBuffers {
                if let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) {
                    availableBuffers.append(buffer)
                }
            }
        }
        
        func acquire() -> MTLBuffer? {
            if availableBuffers.isEmpty {
                return device.makeBuffer(length: bufferSize, options: .storageModeShared)
            }
            return availableBuffers.removeLast()
        }
        
        func release(_ buffer: MTLBuffer) {
            if availableBuffers.count < maxBuffers {
                availableBuffers.append(buffer)
            }
        }
    }
    
    // MARK: - Texture Cache
    private class TextureCache {
        private var cache: [TextureKey: MTLTexture] = [:]
        private let device: MTLDevice
        private let maxCacheSize: Int
        
        struct TextureKey: Hashable {
            let width: Int
            let height: Int
            let pixelFormat: MTLPixelFormat
        }
        
        func getTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
            let key = TextureKey(width: width, height: height, pixelFormat: pixelFormat)
            
            if let cached = cache[key] {
                return cached
            }
            
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                return nil
            }
            
            cache[key] = texture
            return texture
        }
    }
}
```

### 5.2 GPU同期戦略

```swift
// GPUSynchronization.swift
class GPUSynchronizer {
    private let device: MTLDevice
    private var fences: [MTLFence] = []
    private var currentFenceIndex = 0
    
    // MARK: - Triple Buffering Sync
    func setupTripleBuffering() {
        for _ in 0..<3 {
            if let fence = device.makeFence() {
                fences.append(fence)
            }
        }
    }
    
    func synchronizeFrame(commandBuffer: MTLCommandBuffer) {
        let fence = fences[currentFenceIndex]
        
        // Wait for previous frame
        commandBuffer.waitForFence(fence, before: .vertex)
        
        // Update fence after rendering
        commandBuffer.updateFence(fence, after: .fragment)
        
        currentFenceIndex = (currentFenceIndex + 1) % fences.count
    }
}
```

---

## 6. パフォーマンス最適化戦略

### 6.1 レイテンシ削減テクニック

| 最適化項目 | 実装方法 | 期待効果 |
|-----------|---------|----------|
| バッファサイズ | 64サンプル @ 48kHz | 1.33ms削減 |
| コールバック最適化 | C関数使用 | 0.5ms削減 |
| ロックフリーキュー | atomic操作 | 0.2ms削減 |
| GPU並列処理 | Compute Shader | 2ms削減 |
| メモリプール | 事前割り当て | 0.8ms削減 |

### 6.2 CPU/GPU負荷分散

```swift
// WorkloadDistribution.swift
class WorkloadDistributor {
    // MARK: - タスク分類
    enum ProcessingTarget {
        case cpu  // 低レイテンシ、シーケンシャル処理
        case gpu  // 並列処理可能、大量データ
        case both // ハイブリッド処理
    }
    
    func categorizeTask(_ task: ProcessingTask) -> ProcessingTarget {
        switch task.type {
        case .audioMixing:
            return .cpu  // リアルタイム性重視
        case .fftAnalysis:
            return .gpu  // 並列化可能
        case .visualEffect:
            return .gpu  // GPU最適
        case .midiProcessing:
            return .cpu  // 低レイテンシ必須
        case .complexAnalysis:
            return .both // 分散処理
        }
    }
}
```

### 6.3 プロファイリングとモニタリング

```swift
// PerformanceMonitor.swift
class PerformanceMonitor {
    struct Metrics {
        var audioLatency: TimeInterval
        var renderLatency: TimeInterval
        var cpuUsage: Double
        var gpuUsage: Double
        var memoryUsage: Double
        var frameRate: Double
    }
    
    private var metrics = Metrics(
        audioLatency: 0,
        renderLatency: 0,
        cpuUsage: 0,
        gpuUsage: 0,
        memoryUsage: 0,
        frameRate: 0
    )
    
    // MARK: - Real-time Monitoring
    func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateMetrics()
        }
    }
    
    private func updateMetrics() {
        // Audio Latency
        metrics.audioLatency = AVAudioSession.sharedInstance().outputLatency
        
        // CPU Usage
        metrics.cpuUsage = getCurrentCPUUsage()
        
        // GPU Usage (Metal Performance HUD)
        metrics.gpuUsage = getGPUUsage()
        
        // Memory
        metrics.memoryUsage = getCurrentMemoryUsage()
        
        // Publish metrics
        NotificationCenter.default.post(
            name: .performanceMetricsUpdated,
            object: metrics
        )
    }
}
```

---

## 7. エラーハンドリングとフォールバック

### 7.1 グレースフルデグラデーション

```swift
// FallbackStrategy.swift
class FallbackManager {
    enum PerformanceMode {
        case highQuality    // 5ms target, full effects
        case balanced       // 10ms target, moderate effects
        case lowLatency     // 20ms target, minimal effects
        case compatibility  // 50ms target, basic functionality
    }
    
    private var currentMode = PerformanceMode.highQuality
    
    func adjustPerformanceMode(based metrics: PerformanceMonitor.Metrics) {
        if metrics.audioLatency > 20 {
            downgradeMode()
        } else if metrics.audioLatency < 5 && metrics.cpuUsage < 50 {
            upgradeMode()
        }
    }
    
    private func applyMode(_ mode: PerformanceMode) {
        switch mode {
        case .highQuality:
            AudioEngine.setBufferSize(64)
            VisualEngine.enableAllEffects()
        case .balanced:
            AudioEngine.setBufferSize(128)
            VisualEngine.enableCoreEffects()
        case .lowLatency:
            AudioEngine.setBufferSize(256)
            VisualEngine.disableComplexEffects()
        case .compatibility:
            AudioEngine.setBufferSize(512)
            VisualEngine.useBasicRendering()
        }
    }
}
```

---

## 8. テスト戦略

### 8.1 パフォーマンステスト

```swift
// PerformanceTests.swift
import XCTest

class AudioLatencyTests: XCTestCase {
    func testRoundTripLatency() async throws {
        let engine = LNXAudioEngine()
        try await engine.configureForLowLatency()
        
        let startTime = CACurrentMediaTime()
        // Generate test signal
        let testSignal = generateImpulse()
        
        // Process through engine
        let result = await engine.process(testSignal)
        
        let endTime = CACurrentMediaTime()
        let latency = (endTime - startTime) * 1000 // ms
        
        XCTAssertLessThan(latency, 5.0, "Latency exceeds 5ms target")
    }
    
    func testGPURenderingPerformance() {
        measure {
            // Render 1000 frames
            for _ in 0..<1000 {
                renderer.renderFrame()
            }
        }
    }
}
```

### 8.2 ストレステスト

```swift
// StressTests.swift
class StressTests: XCTestCase {
    func testSustainedLoad() async {
        let duration: TimeInterval = 300 // 5 minutes
        let engine = LNXAudioEngine()
        
        let expectation = XCTestExpectation(description: "Sustained load")
        
        Task {
            try await engine.runStressTest(duration: duration)
            
            // Check for memory leaks
            XCTAssertLessThan(memoryGrowth, 10_000_000) // 10MB
            
            // Check for performance degradation
            XCTAssertLessThan(finalLatency - initialLatency, 1.0) // 1ms
            
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: duration + 10)
    }
}
```

---

## 9. 実装ロードマップ

### Phase 2.2.1: Core Audio基盤（Week 1-2）
- [ ] AVAudioEngine セットアップ
- [ ] 低レイテンシ設定実装
- [ ] Audio Unit グラフ構築
- [ ] DSP処理基盤

### Phase 2.2.2: Metal統合（Week 3-4）
- [ ] MetalレンダラーSdsdfa 
- [ ] Compute Shader実装
- [ ] MPS統合
- [ ] Triple Buffering

### Phase 2.2.3: SwiftUI連携（Week 5-6）
- [ ] MetalView統合
- [ ] ViewModel実装
- [ ] Combine バインディング
- [ ] UI応答性最適化

### Phase 2.2.4: 最適化（Week 7-8）
- [ ] メモリプール実装
- [ ] GPU同期最適化
- [ ] パフォーマンステスト
- [ ] フォールバック実装

---

## 10. 参考資料

### Apple Documentation
- [Core Audio Overview](https://developer.apple.com/documentation/coreaudio)
- [Metal Programming Guide](https://developer.apple.com/metal/)
- [SwiftUI Performance](https://developer.apple.com/documentation/swiftui/performance)

### Technical Papers
- "Achieving Low Latency Audio on macOS" - WWDC
- "Metal Performance Shaders in Practice" - Apple
- "Real-time Audio Programming Best Practices" - Ross Bencina

### Open Source References
- [AudioKit](https://github.com/AudioKit/AudioKit) - Swift audio synthesis
- [MetalPetal](https://github.com/MetalPetal/MetalPetal) - GPU image processing

---

**改訂履歴**
- 2025-08-09: v2.0.0 - 初版作成、5msレイテンシ目標設定

**レビュー予定**: 2025-09-15