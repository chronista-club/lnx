# Testing Strategy for LNX Experience

> **Status**: Deprecated — 2025-08 の Swift 時代のテスト戦略。現在のテストの三層（Rust の実 QUIC、Swift の単体、実サーバ相手の UI テスト）は [design 01](../../design/01-lnx-server-link.md)。経緯の参照用に残す

## 概要

本ドキュメントは、LNX Experienceのリアルタイム音響/視覚処理システムに対する包括的なテスト戦略を定義します。Swift Testing frameworkとXCTestの使い分け指針、パフォーマンステストの自動化、リアルタイム処理のテスト手法を提供します。

## 1. テストフレームワークの選択基準

### 1.1 Swift Testing Framework（推奨）

**適用領域:**
- 単体テスト（ビジネスロジック、DSP処理）
- 並列実行可能なテスト
- パラメータ化テスト
- タグベースのテスト管理

```swift
import Testing
import Foundation

// ✅ Swift Testing: パラメータ化テストの例
@Suite("Audio Processing Tests")
struct AudioProcessorTests {
    
    @Test("FFT produces correct frequency spectrum",
          arguments: [256, 512, 1024, 2048])
    func testFFTWithDifferentSizes(bufferSize: Int) async throws {
        // Arrange
        let processor = LNXDSPProcessor()
        let testSignal = generateSineWave(
            frequency: 440.0,
            sampleRate: 48000.0,
            samples: bufferSize
        )
        
        // Act
        let spectrum = try await processor.performFFT(testSignal)
        
        // Assert
        #expect(spectrum.count == bufferSize / 2)
        let peakIndex = spectrum.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let peakFrequency = Double(peakIndex) * 48000.0 / Double(bufferSize)
        #expect(abs(peakFrequency - 440.0) < 50.0) // 50Hz tolerance
    }
    
    @Test("Biquad filter attenuates correctly",
          arguments: zip([100.0, 1000.0, 5000.0], [-40.0, -20.0, -3.0]))
    func testLowpassFilter(frequency: Double, expectedAttenuation: Double) async throws {
        let filter = BiquadCoefficients.lowpass(
            sampleRate: 48000,
            cutoff: 2000,
            q: 0.707
        )
        
        let testSignal = generateSineWave(frequency: frequency)
        let filtered = try await applyFilter(testSignal, coefficients: filter)
        
        let attenuation = calculateAttenuation(original: testSignal, filtered: filtered)
        #expect(abs(attenuation - expectedAttenuation) < 3.0) // 3dB tolerance
    }
}

// タグベースのテスト組織化
extension Tag {
    @Tag static var audio: Self
    @Tag static var performance: Self
    @Tag static var integration: Self
    @Tag static var realtime: Self
}

@Suite("Latency Measurement", .tags(.audio, .performance))
struct LatencyTests {
    
    @Test("Audio session latency is under 5ms", .tags(.realtime))
    func testAudioSessionLatency() async throws {
        let engine = LNXAudioEngine()
        try await engine.setupLowLatencyAudioSession()
        
        let measurement = LNXLatencyMeasurement()
        let latency = try await measurement.measureRoundtripLatency()
        
        #expect(latency < 0.005) // 5ms threshold
        
        // 詳細な統計情報
        let stats = measurement.getLatencyStatistics()
        Issue.record("""
            Latency Statistics:
            - Min: \(stats.min)ms
            - Max: \(stats.max)ms
            - Mean: \(stats.mean)ms
            - Median: \(stats.median)ms
            - P99: \(stats.p99)ms
            """)
    }
}
```

### 1.2 XCTest Framework

**適用領域:**
- UI テスト
- 統合テスト
- パフォーマンス計測（XCTMetric）
- レガシー互換性が必要なテスト

```swift
import XCTest

// ✅ XCTest: UIテストの例
class LNXXUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testAudioFileLoading() throws {
        // ファイル選択
        app.buttons["LoadFileButton"].tap()
        
        // ファイルピッカーで選択
        let fileCell = app.cells["20250802_145427.wav"]
        XCTAssertTrue(fileCell.waitForExistence(timeout: 5))
        fileCell.tap()
        
        // ロード完了確認
        let loadedIndicator = app.staticTexts["FileLoadedIndicator"]
        XCTAssertTrue(loadedIndicator.waitForExistence(timeout: 10))
        
        // 再生ボタンが有効になっていることを確認
        XCTAssertTrue(app.buttons["PlayButton"].isEnabled)
    }
    
    func testPlaybackControls() throws {
        // 事前条件: ファイルをロード
        loadTestAudioFile()
        
        // 再生開始
        let playButton = app.buttons["PlayButton"]
        playButton.tap()
        
        // 再生中状態の確認
        XCTAssertEqual(app.staticTexts["PlaybackStatus"].label, "Playing")
        
        // ボリューム調整
        let volumeSlider = app.sliders["VolumeSlider"]
        volumeSlider.adjust(toNormalizedSliderPosition: 0.8)
        
        // 停止
        app.buttons["StopButton"].tap()
        XCTAssertEqual(app.staticTexts["PlaybackStatus"].label, "Stopped")
    }
}

// ✅ XCTest: パフォーマンス測定
class LNXXPerformanceTests: XCTestCase {
    
    func testLargeFileLoadingPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        
        measure(metrics: [
            XCTClockMetric(),           // 実行時間
            XCTMemoryMetric(),          // メモリ使用量
            XCTCPUMetric(),             // CPU使用率
            XCTStorageMetric()          // ディスクI/O
        ], options: options) {
            // 201MBファイルのロード
            let url = Bundle(for: type(of: self)).url(
                forResource: "20250802_145427",
                withExtension: "wav"
            )!
            
            let loader = LNXAudioFileStreamer()
            try! loader.openLargeAudioFile(url: url)
        }
    }
    
    func testRealtimeProcessingPerformance() throws {
        measure(metrics: [XCTClockMetric()]) {
            let processor = LNXDSPProcessor()
            let buffer = generateTestBuffer(size: 1024)
            
            for _ in 0..<1000 {
                _ = processor.performFFT(buffer)
            }
        }
    }
}
```

## 2. リアルタイム処理のテスト

### 2.1 オーディオコールバックのテスト

```swift
@Suite("Realtime Audio Processing")
struct RealtimeAudioTests {
    
    @Test("Audio callback meets deadline")
    func testAudioCallbackDeadline() async throws {
        let processor = MockAudioProcessor()
        let bufferSize = 128  // 128 samples @ 48kHz = 2.67ms
        let deadline = 2.67e-3  // 2.67ms
        
        // コールバック実行時間の測定
        let executionTime = try await measureCallbackExecution(
            processor: processor,
            bufferSize: bufferSize
        )
        
        #expect(executionTime < deadline)
        #expect(executionTime < deadline * 0.5) // 50%以下が理想
    }
    
    @Test("Ring buffer is lock-free")
    func testRingBufferConcurrency() async throws {
        let buffer = LNXLockFreeRingBuffer(capacity: 4096)
        let iterations = 10000
        
        // 並行書き込み/読み込みテスト
        async let writer = writeToBuffer(buffer, count: iterations)
        async let reader = readFromBuffer(buffer, count: iterations)
        
        let (writeCount, readCount) = try await (writer, reader)
        
        #expect(writeCount == iterations)
        #expect(readCount == iterations)
    }
    
    private func measureCallbackExecution(
        processor: MockAudioProcessor,
        bufferSize: Int
    ) async throws -> TimeInterval {
        let startTime = CACurrentMediaTime()
        
        // オーディオコールバックをシミュレート
        let inputBuffer = UnsafeMutablePointer<Float>.allocate(capacity: bufferSize)
        defer { inputBuffer.deallocate() }
        
        let outputBuffer = UnsafeMutablePointer<Float>.allocate(capacity: bufferSize)
        defer { outputBuffer.deallocate() }
        
        processor.processBuffer(
            input: inputBuffer,
            output: outputBuffer,
            frameCount: bufferSize
        )
        
        return CACurrentMediaTime() - startTime
    }
}
```

### 2.2 メモリ管理のテスト

```swift
@Suite("Memory Management")
struct MemoryManagementTests {
    
    @Test("No memory leaks in audio processing chain")
    func testMemoryLeaks() async throws {
        // ベースラインメモリ使用量
        let baseline = getCurrentMemoryUsage()
        
        // 処理チェーンの実行
        for _ in 0..<100 {
            autoreleasepool {
                let engine = LNXAudioEngine()
                let processor = LNXDSPProcessor()
                let buffer = generateLargeBuffer(size: 1024 * 1024) // 1MB
                
                _ = processor.performFFT(buffer)
            }
        }
        
        // メモリ使用量の確認
        let final = getCurrentMemoryUsage()
        let leaked = final - baseline
        
        #expect(leaked < 1024 * 1024) // 1MB以下の増加
    }
    
    @Test("Memory mapped file handles large files efficiently")
    func testMemoryMappedFile() async throws {
        let url = largeTestFileURL() // 201MB file
        let streamer = LNXAudioFileStreamer()
        
        let memoryBefore = getCurrentMemoryUsage()
        try streamer.openLargeAudioFile(url: url)
        let memoryAfter = getCurrentMemoryUsage()
        
        let memoryIncrease = memoryAfter - memoryBefore
        
        // メモリマップドI/Oなので、全体をメモリに読み込まない
        #expect(memoryIncrease < 50 * 1024 * 1024) // 50MB以下
    }
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
```

## 3. 統合テスト

### 3.1 エンドツーエンドテスト

```swift
@Suite("End-to-End Integration", .tags(.integration))
struct EndToEndTests {
    
    @Test("Complete audio playback workflow")
    func testCompletePlaybackWorkflow() async throws {
        // 1. セッション初期化
        let engine = LNXAudioEngine()
        try await engine.setupLowLatencyAudioSession()
        
        // 2. ファイル読み込み
        let fileURL = testAudioFileURL()
        let streamer = LNXAudioFileStreamer()
        try streamer.openLargeAudioFile(url: fileURL)
        
        // 3. 再生開始
        let player = LNXAudioPlayer(engine: engine, streamer: streamer)
        try await player.play()
        
        // 4. リアルタイム処理
        let processor = LNXDSPProcessor()
        var processedSamples = 0
        
        for await buffer in streamer.streamAudioData() {
            let spectrum = processor.performFFT(buffer.samples)
            processedSamples += buffer.frameCount
            
            // レイテンシーチェック
            let latency = await player.getCurrentLatency()
            #expect(latency < 0.020) // 20ms threshold
        }
        
        // 5. 停止とクリーンアップ
        await player.stop()
        
        #expect(processedSamples > 0)
    }
    
    @Test("Multi-track synchronization")
    func testMultiTrackSync() async throws {
        let tracks = [
            AudioTrack(id: "track1", url: testAudioFileURL()),
            AudioTrack(id: "track2", url: testAudioFileURL()),
            AudioTrack(id: "track3", url: testAudioFileURL())
        ]
        
        let mixer = LNXMultiTrackMixer()
        try await mixer.loadTracks(tracks)
        
        // 同期再生開始
        try await mixer.playAll()
        
        // 同期確認（各トラックの再生位置）
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms待機
        
        let positions = await mixer.getTrackPositions()
        let maxDrift = positions.max()! - positions.min()!
        
        #expect(maxDrift < 0.001) // 1ms以内のドリフト
    }
}
```

## 4. CI/CD統合

### 4.1 GitHub Actionsワークフロー

```yaml
# .github/workflows/test.yml
name: LNX Experience Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v3
      with:
        lfs: true  # Git LFSファイルを含める
    
    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_16.0.app
    
    - name: Run Unit Tests (Swift Testing)
      run: |
        xcodebuild test \
          -scheme LNXX \
          -destination 'platform=macOS' \
          -testPlan UnitTests \
          -resultBundlePath TestResults/unit.xcresult
    
    - name: Run Integration Tests
      run: |
        xcodebuild test \
          -scheme LNXX \
          -destination 'platform=macOS' \
          -only-testing:LNXXTests \
          -resultBundlePath TestResults/integration.xcresult
    
    - name: Run Performance Tests
      run: |
        xcodebuild test \
          -scheme LNXX \
          -destination 'platform=macOS' \
          -only-testing:LNXXPerformanceTests \
          -resultBundlePath TestResults/performance.xcresult \
          -baseline TestBaselines/performance.baseline
    
    - name: Upload Test Results
      uses: actions/upload-artifact@v3
      with:
        name: test-results
        path: TestResults/
    
    - name: Performance Regression Check
      run: |
        xcrun xcresulttool compare \
          --baseline TestBaselines/performance.baseline \
          --result TestResults/performance.xcresult \
          --threshold 10  # 10%の性能劣化まで許容
```

### 4.2 テスト計画（Test Plan）

```json
{
  "configurations": [
    {
      "name": "Unit Tests",
      "options": {
        "testExecutionOrdering": "random",
        "testRepetitionMode": "retryOnFailure",
        "maximumTestRepetitions": 3,
        "targetForVariableExpansion": "LNXX"
      },
      "testTargets": [
        {
          "target": {
            "containerPath": "container:LNXX.xcodeproj",
            "identifier": "LNXXTests",
            "name": "LNXXTests"
          },
          "selectedTests": [
            "AudioProcessorTests",
            "LatencyTests",
            "MemoryManagementTests"
          ]
        }
      ]
    },
    {
      "name": "Performance Tests",
      "options": {
        "testExecutionOrdering": "alphabetical",
        "environmentVariableEntries": [
          {
            "key": "PERFORMANCE_TEST_MODE",
            "value": "true"
          }
        ]
      }
    }
  ],
  "defaultOptions": {
    "codeCoverage": {
      "targets": ["LNXX"]
    },
    "testTimeoutsEnabled": true,
    "defaultTestExecutionTimeAllowance": 60,
    "maximumTestExecutionTimeAllowance": 600
  },
  "version": 1
}
```

## 5. テストデータ管理

### 5.1 テストフィクスチャ

```swift
// TestFixtures.swift
enum TestFixtures {
    
    // テスト用オーディオファイル生成
    static func generateTestAudioFile(
        duration: TimeInterval = 1.0,
        sampleRate: Double = 48000.0,
        frequency: Double = 440.0
    ) -> URL {
        let samples = Int(duration * sampleRate)
        var buffer = [Float](repeating: 0, count: samples)
        
        for i in 0..<samples {
            let phase = 2.0 * Double.pi * frequency * Double(i) / sampleRate
            buffer[i] = Float(sin(phase))
        }
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).wav")
        
        // WAVファイルとして保存
        saveAsWAV(buffer: buffer, sampleRate: sampleRate, to: url)
        
        return url
    }
    
    // モックデータ生成
    static func mockSpectrum(size: Int = 512) -> [Float] {
        (0..<size).map { i in
            Float.random(in: -60...0) // dB値
        }
    }
    
    // パフォーマンステスト用大容量データ
    static func largeSampleBuffer(megabytes: Int) -> [Float] {
        let samples = megabytes * 1024 * 1024 / MemoryLayout<Float>.size
        return [Float](repeating: 0, count: samples)
    }
}
```

### 5.2 モックオブジェクト

```swift
// Mocks.swift
actor MockAudioEngine: AudioEngineProtocol {
    private var isPlaying = false
    private var latencySimulation: TimeInterval = 0.003 // 3ms
    
    func play() async throws {
        isPlaying = true
        // レイテンシーをシミュレート
        try await Task.sleep(nanoseconds: UInt64(latencySimulation * 1_000_000_000))
    }
    
    func stop() async {
        isPlaying = false
    }
    
    func getCurrentLatency() async -> TimeInterval {
        return latencySimulation
    }
    
    func setSimulatedLatency(_ latency: TimeInterval) {
        latencySimulation = latency
    }
}

class MockAudioProcessor: AudioProcessorProtocol {
    var processCallCount = 0
    var lastProcessedBuffer: [Float]?
    
    func processBuffer(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        processCallCount += 1
        
        // 簡単な処理をシミュレート
        for i in 0..<frameCount {
            output[i] = input[i] * 0.5
        }
        
        lastProcessedBuffer = Array(UnsafeBufferPointer(start: input, count: frameCount))
    }
}
```

## 6. テストカバレッジ目標

### カバレッジ基準

| コンポーネント | 目標カバレッジ | 優先度 |
|--------------|--------------|--------|
| Core Audio処理 | 90% | Critical |
| DSPアルゴリズム | 95% | Critical |
| UI ViewModels | 80% | High |
| ユーティリティ | 85% | Medium |
| UIビュー | 60% | Low |

### カバレッジレポート生成

```bash
# カバレッジ付きでテスト実行
xcodebuild test \
  -scheme LNXX \
  -enableCodeCoverage YES \
  -resultBundlePath coverage.xcresult

# レポート生成
xcrun xccov view --report coverage.xcresult

# HTML形式でエクスポート
xcrun xccov view --report --json coverage.xcresult | \
  python3 -m json.tool > coverage.json
```

## まとめ

効果的なテスト戦略の要点：

1. **Swift Testing優先** - 新しいテストはSwift Testingで記述
2. **XCTest併用** - UIテストとパフォーマンス測定に活用
3. **リアルタイムテスト** - レイテンシーとデッドライン確認
4. **自動化** - CI/CDパイプラインへの統合
5. **カバレッジ監視** - クリティカルパスの高カバレッジ維持

これらの手法により、高品質で信頼性の高いリアルタイムオーディオアプリケーションを実現します。