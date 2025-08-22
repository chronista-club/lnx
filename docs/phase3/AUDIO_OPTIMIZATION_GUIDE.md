# Audio Processing Optimization Guide for LNX Experience

## 概要

本ガイドは、LNX Experienceにおいて5ms以下のレイテンシーを実現するためのCore Audio統合とオーディオ処理最適化の具体的手法を提供します。304MBの大容量WAVファイルを効率的に処理しながら、プロフェッショナルグレードの音質を維持する実装パターンを定義します。

## 1. Core Audio アーキテクチャ

### 1.1 低レイテンシーセッション設定

```swift
import AVFoundation
import CoreAudio

class LNXAudioEngine {
    private let audioEngine = AVAudioEngine()
    private var audioSession: AVAudioSession!
    
    func setupLowLatencyAudioSession() async throws {
        audioSession = AVAudioSession.sharedInstance()
        
        // ✅ プロフェッショナルオーディオカテゴリ設定
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,  // 最低レイテンシーモード
            options: [.mixWithOthers, .allowBluetooth]
        )
        
        // ✅ サンプルレート設定（ハードウェアネイティブ）
        let preferredSampleRate = 48000.0  // または44100.0
        try audioSession.setPreferredSampleRate(preferredSampleRate)
        
        // ✅ I/Oバッファサイズ最小化（5ms目標）
        // 48kHz時: 64サンプル = 1.33ms, 128サンプル = 2.67ms, 256サンプル = 5.33ms
        let targetLatencySeconds = 0.005  // 5ms
        try audioSession.setPreferredIOBufferDuration(targetLatencySeconds)
        
        // ✅ アクティベート
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // 実際の設定値を確認
        let actualBufferDuration = audioSession.ioBufferDuration
        let actualSampleRate = audioSession.sampleRate
        print("Audio Session Configuration:")
        print("  Buffer Duration: \(actualBufferDuration * 1000)ms")
        print("  Sample Rate: \(actualSampleRate)Hz")
        print("  Buffer Size: \(Int(actualBufferDuration * actualSampleRate)) samples")
    }
}
```

### 1.2 Audio Unit直接制御

```swift
import AudioToolbox

class LNXCoreAudioProcessor {
    private var audioUnit: AudioComponentInstance?
    private let processingQueue = DispatchQueue(
        label: "com.lnx.audio.processing",
        qos: .userInteractive,
        attributes: .concurrent
    )
    
    func setupAudioUnit() throws {
        // RemoteIO Audio Unitの設定（最低レイテンシー）
        var desc = AudioComponentDescription()
        desc.componentType = kAudioUnitType_Output
        desc.componentSubType = kAudioUnitSubType_RemoteIO
        desc.componentManufacturer = kAudioUnitManufacturer_Apple
        desc.componentFlags = 0
        desc.componentFlagsMask = 0
        
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioError.componentNotFound
        }
        
        var instance: AudioComponentInstance?
        let status = AudioComponentInstanceNew(component, &instance)
        guard status == noErr, let audioUnit = instance else {
            throw AudioError.initializationFailed
        }
        
        self.audioUnit = audioUnit
        
        // コールバック設定
        var callbackStruct = AURenderCallbackStruct(
            inputProc: audioRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        
        // バッファサイズ設定
        var frameSize: UInt32 = 64  // 64サンプル @ 48kHz = 1.33ms
        AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &frameSize,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        AudioUnitInitialize(audioUnit)
    }
}

// リアルタイムセーフなレンダーコールバック
private func audioRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    // ⚠️ 重要: このコールバック内では以下を避ける
    // - メモリアロケーション
    // - ロック取得
    // - Objective-C/Swiftランタイム呼び出し
    // - システムコール
    
    let processor = Unmanaged<LNXCoreAudioProcessor>
        .fromOpaque(inRefCon)
        .takeUnretainedValue()
    
    guard let ioData = ioData else { return kAudioUnitErr_InvalidParameter }
    
    // Lock-freeバッファからデータ読み取り
    processor.processAudioBufferRealtime(ioData, frameCount: inNumberFrames)
    
    return noErr
}
```

## 2. 大容量ファイル処理

### 2.1 メモリマップドI/O

```swift
import Foundation

class LNXAudioFileStreamer {
    private var fileHandle: FileHandle?
    private var mappedData: Data?
    private let chunkSize = 1024 * 1024  // 1MBチャンク
    
    func openLargeAudioFile(url: URL) throws {
        fileHandle = try FileHandle(forReadingFrom: url)
        
        // メモリマップドI/Oの使用
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            mappedData = data
            print("Memory-mapped file: \(data.count / 1024 / 1024)MB")
        }
    }
    
    // 非同期ストリーミング読み込み
    func streamAudioData() -> AsyncStream<AudioBuffer> {
        AsyncStream { continuation in
            Task {
                guard let data = mappedData else { return }
                
                var offset = 0
                let totalSize = data.count
                
                while offset < totalSize {
                    let remainingBytes = totalSize - offset
                    let currentChunkSize = min(chunkSize, remainingBytes)
                    
                    // チャンクごとに処理
                    let chunkData = data[offset..<offset + currentChunkSize]
                    let audioBuffer = try await processChunk(chunkData)
                    
                    continuation.yield(audioBuffer)
                    offset += currentChunkSize
                    
                    // CPUに余裕を持たせる
                    await Task.yield()
                }
                
                continuation.finish()
            }
        }
    }
}
```

### 2.2 リングバッファ実装

```swift
import Accelerate

class LNXLockFreeRingBuffer {
    private let capacity: Int
    private var buffer: UnsafeMutablePointer<Float>
    private var writeIndex = AtomicInt(0)
    private var readIndex = AtomicInt(0)
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.buffer.initialize(repeating: 0, count: capacity)
    }
    
    deinit {
        buffer.deallocate()
    }
    
    // Lock-free書き込み（プロデューサー側）
    func write(_ samples: UnsafePointer<Float>, count: Int) -> Int {
        let currentWrite = writeIndex.load(ordering: .relaxed)
        let currentRead = readIndex.load(ordering: .acquire)
        
        let availableSpace = (currentRead + capacity - currentWrite - 1) % capacity
        let samplesToWrite = min(count, availableSpace)
        
        if samplesToWrite == 0 { return 0 }
        
        // 循環バッファへの書き込み
        let firstPartSize = min(samplesToWrite, capacity - currentWrite)
        let secondPartSize = samplesToWrite - firstPartSize
        
        // SIMD最適化コピー
        vDSP_mmov(samples, 
                  buffer.advanced(by: currentWrite),
                  vDSP_Length(firstPartSize),
                  1, 1, 1)
        
        if secondPartSize > 0 {
            vDSP_mmov(samples.advanced(by: firstPartSize),
                     buffer,
                     vDSP_Length(secondPartSize),
                     1, 1, 1)
        }
        
        let newWriteIndex = (currentWrite + samplesToWrite) % capacity
        writeIndex.store(newWriteIndex, ordering: .release)
        
        return samplesToWrite
    }
    
    // Lock-free読み込み（コンシューマー側）
    func read(_ samples: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let currentRead = readIndex.load(ordering: .relaxed)
        let currentWrite = writeIndex.load(ordering: .acquire)
        
        let availableData = (currentWrite + capacity - currentRead) % capacity
        let samplesToRead = min(count, availableData)
        
        if samplesToRead == 0 { return 0 }
        
        // 循環バッファからの読み込み
        let firstPartSize = min(samplesToRead, capacity - currentRead)
        let secondPartSize = samplesToRead - firstPartSize
        
        vDSP_mmov(buffer.advanced(by: currentRead),
                  samples,
                  vDSP_Length(firstPartSize),
                  1, 1, 1)
        
        if secondPartSize > 0 {
            vDSP_mmov(buffer,
                     samples.advanced(by: firstPartSize),
                     vDSP_Length(secondPartSize),
                     1, 1, 1)
        }
        
        let newReadIndex = (currentRead + samplesToRead) % capacity
        readIndex.store(newReadIndex, ordering: .release)
        
        return samplesToRead
    }
}

// Atomic整数実装
class AtomicInt {
    private var value: Int32
    private let lock = os_unfair_lock()
    
    init(_ initialValue: Int) {
        self.value = Int32(initialValue)
    }
    
    func load(ordering: MemoryOrder) -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return Int(value)
    }
    
    func store(_ newValue: Int, ordering: MemoryOrder) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value = Int32(newValue)
    }
}

enum MemoryOrder {
    case relaxed, acquire, release, sequentiallyConsistent
}
```

## 3. DSP最適化

### 3.1 Accelerate Framework活用

```swift
import Accelerate

class LNXDSPProcessor {
    
    // FFT設定
    private var fftSetup: FFTSetup?
    private let log2n = vDSP_Length(10)  // 1024ポイントFFT
    private let n = vDSP_Length(1024)
    
    init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    // 高速フーリエ変換
    func performFFT(_ input: UnsafePointer<Float>) -> [Float] {
        var realp = [Float](repeating: 0, count: Int(n/2))
        var imagp = [Float](repeating: 0, count: Int(n/2))
        
        var splitComplex = DSPSplitComplex(
            realp: &realp,
            imagp: &imagp
        )
        
        // 実数からcomplex形式へ変換
        input.withMemoryRebound(to: DSPComplex.self, capacity: Int(n/2)) { complexInput in
            vDSP_ctoz(complexInput, 2, &splitComplex, 1, n/2)
        }
        
        // FFT実行
        guard let setup = fftSetup else { return [] }
        vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // パワースペクトラム計算
        var magnitudes = [Float](repeating: 0, count: Int(n/2))
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, n/2)
        
        // 対数スケール変換
        var logMagnitudes = [Float](repeating: 0, count: Int(n/2))
        var one: Float = 1.0
        vDSP_vdbcon(&magnitudes, 1, &one, &logMagnitudes, 1, n/2, 0)
        
        return logMagnitudes
    }
    
    // リアルタイムフィルタリング
    func applyBiquadFilter(
        _ input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        coefficients: BiquadCoefficients,
        frameCount: Int
    ) {
        var delay = [Float](repeating: 0, count: 4)
        
        vDSP_biquad(
            input, 1,
            coefficients.coefficientsArray(), 
            output, 1,
            &delay,
            vDSP_Length(frameCount)
        )
    }
}

struct BiquadCoefficients {
    let b0, b1, b2: Float  // フィードフォワード係数
    let a1, a2: Float      // フィードバック係数
    
    func coefficientsArray() -> [Float] {
        return [b0, b1, b2, a1, a2]
    }
    
    // ローパスフィルター係数計算
    static func lowpass(sampleRate: Float, cutoff: Float, q: Float = 0.707) -> BiquadCoefficients {
        let w = 2.0 * Float.pi * cutoff / sampleRate
        let cosw = cos(w)
        let sinw = sin(w)
        let alpha = sinw / (2.0 * q)
        
        let b0 = (1.0 - cosw) / 2.0
        let b1 = 1.0 - cosw
        let b2 = (1.0 - cosw) / 2.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosw
        let a2 = 1.0 - alpha
        
        // 正規化
        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}
```

## 4. スレッド管理

### 4.1 リアルタイムスレッド設定

```swift
import Foundation

class LNXRealtimeThread {
    private var thread: Thread?
    private let threadPriority = 0.99  // 最高優先度
    
    func createRealtimeThread(name: String, work: @escaping () -> Void) {
        thread = Thread {
            // スレッド優先度設定
            Thread.current.threadPriority = self.threadPriority
            Thread.current.name = name
            
            // Core Affinityの設定（特定CPUコアに固定）
            self.setThreadAffinity()
            
            // リアルタイムスケジューリング
            self.setRealtimeScheduling()
            
            work()
        }
        
        thread?.start()
    }
    
    private func setThreadAffinity() {
        // macOS特有のthread affinity設定
        var set = thread_affinity_policy_data_t(affinity_tag: 1)
        let result = withUnsafePointer(to: &set) { ptr in
            thread_policy_set(
                pthread_mach_thread_np(pthread_self()),
                THREAD_AFFINITY_POLICY,
                ptr.withMemoryRebound(
                    to: integer_t.self,
                    capacity: 1
                ) { $0 },
                THREAD_AFFINITY_POLICY_COUNT
            )
        }
        
        if result != KERN_SUCCESS {
            print("Failed to set thread affinity")
        }
    }
    
    private func setRealtimeScheduling() {
        var policy = thread_time_constraint_policy_data_t()
        
        // タイムコンストレイント設定（ナノ秒単位）
        policy.period = 5_000_000       // 5ms周期
        policy.computation = 2_500_000   // 2.5ms計算時間
        policy.constraint = 5_000_000    // 5ms制約
        policy.preemptible = 0           // プリエンプト不可
        
        let result = withUnsafePointer(to: &policy) { ptr in
            thread_policy_set(
                pthread_mach_thread_np(pthread_self()),
                THREAD_TIME_CONSTRAINT_POLICY,
                ptr.withMemoryRebound(
                    to: integer_t.self,
                    capacity: MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size
                ) { $0 },
                THREAD_TIME_CONSTRAINT_POLICY_COUNT
            )
        }
        
        if result != KERN_SUCCESS {
            print("Failed to set realtime scheduling")
        }
    }
}
```

## 5. レイテンシー測定

### 5.1 ラウンドトリップ測定

```swift
class LNXLatencyMeasurement {
    private var inputTimestamp: TimeInterval = 0
    private var outputTimestamp: TimeInterval = 0
    private var measurements: [TimeInterval] = []
    private let maxMeasurements = 100
    
    // インパルス応答による測定
    func measureRoundtripLatency() async -> TimeInterval {
        // テストインパルス生成
        let impulse = generateImpulse()
        
        // タイムスタンプ記録
        inputTimestamp = CACurrentMediaTime()
        
        // オーディオ出力
        await playImpulse(impulse)
        
        // 入力モニタリング（ループバック）
        let detectedTime = await detectImpulse()
        
        let latency = detectedTime - inputTimestamp
        
        // 統計更新
        measurements.append(latency)
        if measurements.count > maxMeasurements {
            measurements.removeFirst()
        }
        
        return latency
    }
    
    // 統計情報
    func getLatencyStatistics() -> LatencyStats {
        guard !measurements.isEmpty else {
            return LatencyStats(min: 0, max: 0, mean: 0, median: 0, p99: 0)
        }
        
        let sorted = measurements.sorted()
        let mean = measurements.reduce(0, +) / Double(measurements.count)
        let median = sorted[sorted.count / 2]
        let p99Index = Int(Double(sorted.count) * 0.99)
        let p99 = sorted[min(p99Index, sorted.count - 1)]
        
        return LatencyStats(
            min: sorted.first! * 1000,     // ms変換
            max: sorted.last! * 1000,
            mean: mean * 1000,
            median: median * 1000,
            p99: p99 * 1000
        )
    }
    
    private func generateImpulse() -> [Float] {
        var impulse = [Float](repeating: 0, count: 1024)
        impulse[0] = 1.0  // ディラックデルタ
        return impulse
    }
}

struct LatencyStats {
    let min: Double     // 最小レイテンシー (ms)
    let max: Double     // 最大レイテンシー (ms)
    let mean: Double    // 平均レイテンシー (ms)
    let median: Double  // 中央値 (ms)
    let p99: Double     // 99パーセンタイル (ms)
}
```

## 6. 最適化チェックリスト

### レイテンシー削減の優先順位

1. **バッファサイズ最小化** (影響度: 極大)
   - 64サンプル @ 48kHz = 1.33ms
   - 128サンプル @ 48kHz = 2.67ms

2. **リアルタイムスレッド使用** (影響度: 大)
   - Time Constraint Policy設定
   - CPU Affinity設定

3. **Lock-freeアルゴリズム** (影響度: 大)
   - リングバッファ
   - Atomic操作

4. **SIMD最適化** (影響度: 中)
   - Accelerate Framework
   - vDSP関数

5. **メモリプリアロケーション** (影響度: 中)
   - バッファプール
   - オブジェクトプール

### パフォーマンスプロファイリング

```bash
# Instrumentsでのプロファイリング
instruments -t "Time Profiler" -D trace.trace LNXX.app
instruments -t "System Trace" -D system.trace LNXX.app

# Core Audio特有のデバッグ
# Console.appで以下をフィルタ:
# - com.apple.coreaudio
# - com.apple.audio.IOKit
```

## まとめ

5ms以下のレイテンシー実現には：

1. **Core Audio直接制御** - Audio Unit APIの活用
2. **メモリマップドI/O** - 大容量ファイルの効率的処理
3. **Lock-freeデータ構造** - リングバッファの実装
4. **SIMD最適化** - Accelerate Frameworkの活用
5. **リアルタイムスレッド** - 適切な優先度とスケジューリング

これらの技術を組み合わせることで、プロフェッショナルグレードの低レイテンシーオーディオ処理を実現します。