# LNX Experience 技術アーキテクチャドキュメント

## 概要

LNX Experience (LNXX) は、リアルタイムオーディオ/ビジュアルパフォーマンスのためのmacOSアプリケーションです。本ドキュメントは、現在の実装状況と将来のアーキテクチャ設計を包括的に記述し、Phase 2以降の開発指針を提供します。

**バージョン**: 1.0.0  
**最終更新**: 2025-08-09  
**対象フェーズ**: Phase 1-4 (2025-2026)

---

## 1. 技術アーキテクチャ

### 1.1 現在のアーキテクチャ (Phase 1)

```
┌─────────────────────────────────────────────────────────┐
│                    LNXX Application                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │              SwiftUI Views                      │    │
│  │  ┌──────────────┐  ┌─────────────────────┐    │    │
│  │  │ ContentView  │  │  Future Views...    │    │    │
│  │  └──────────────┘  └─────────────────────┘    │    │
│  └────────────────────────────────────────────────┘    │
│                           │                             │
│  ┌────────────────────────────────────────────────┐    │
│  │              LNXXApp (@main)                    │    │
│  └────────────────────────────────────────────────┘    │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │              App Sandbox                        │    │
│  │   - File Access (user-selected)                 │    │
│  │   - No Network                                  │    │
│  │   - No Hardware Access                          │    │
│  └────────────────────────────────────────────────┘    │
│                                                          │
└─────────────────────────────────────────────────────────┘
                              │
                    ┌─────────▼──────────┐
                    │   macOS 15.5+      │
                    └────────────────────┘
```

### 1.2 目標アーキテクチャ (Phase 2-3)

```
┌──────────────────────────────────────────────────────────────────┐
│                        LNXX Application                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                     Presentation Layer                    │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │    │
│  │  │ SwiftUI  │  │  MVVM    │  │ Combine  │  │  State │ │    │
│  │  │  Views   │◄─┤ViewModels│◄─┤Publishers│◄─┤ Store  │ │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                     Core Modules                          │    │
│  │                                                           │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │    │
│  │  │    Audio    │  │   Visual    │  │    Sync     │     │    │
│  │  │   Module    │◄─┤   Module    │◄─┤   Module    │     │    │
│  │  │             │  │             │  │             │     │    │
│  │  │ • Core     │  │ • Metal     │  │ • Clock     │     │    │
│  │  │   Audio    │  │   Shaders   │  │   Sync     │     │    │
│  │  │ • DSP      │  │ • Compute   │  │ • Network   │     │    │
│  │  │   Engine   │  │   Kernels   │  │   Sync     │     │    │
│  │  │ • Buffer   │  │ • Renderer  │  │ • MIDI      │     │    │
│  │  │   Manager  │  │             │  │   Clock     │     │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │    │
│  │                                                           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Platform Layer                         │    │
│  │                                                           │    │
│  │  ┌────────────┐  ┌────────────┐  ┌─────────────────┐   │    │
│  │  │Core Audio  │  │   Metal    │  │  AVFoundation   │   │    │
│  │  │    API     │  │Performance │  │                 │   │    │
│  │  └────────────┘  │  Shaders   │  └─────────────────┘   │    │
│  │                   └────────────┘                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### 1.3 ECS (Entity-Component-System) アーキテクチャ統合

```
┌─────────────────────────────────────────────────────────────┐
│                    ECS Architecture                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Entities                                                    │
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐           │
│  │ Track  │  │ Effect │  │ Visual │  │  Sync  │           │
│  │Entity  │  │Entity  │  │Entity  │  │Entity  │           │
│  └────────┘  └────────┘  └────────┘  └────────┘           │
│       │           │           │           │                 │
│  ┌────▼───────────▼───────────▼───────────▼────┐           │
│  │              Component Pool                   │           │
│  │  ┌─────────────────────────────────────┐    │           │
│  │  │ • AudioBuffer    • Transform        │    │           │
│  │  │ • WaveformData   • ColorGradient    │    │           │
│  │  │ • MIDIMapping    • ShaderParams     │    │           │
│  │  │ • TimeSignature  • NetworkSync      │    │           │
│  │  └─────────────────────────────────────┘    │           │
│  └──────────────────────────────────────────────┘           │
│                           │                                  │
│  ┌────────────────────────▼─────────────────────┐           │
│  │                   Systems                     │           │
│  │  ┌───────────┐  ┌───────────┐  ┌──────────┐│           │
│  │  │  Audio    │  │  Visual   │  │  Sync    ││           │
│  │  │Processing │  │ Rendering │  │  System  ││           │
│  │  │  System   │  │  System   │  │          ││           │
│  │  └───────────┘  └───────────┘  └──────────┘│           │
│  └──────────────────────────────────────────────┘           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. データフロー設計

### 2.1 オーディオ処理パイプライン

```
入力ソース                     処理                        出力
─────────────              ──────────────              ─────────

┌─────────────┐           ┌──────────────┐           ┌─────────┐
│  WAV File   │──────────►│ File Stream  │──────────►│ Decoder │
│  (304MB)    │           │   Reader     │           │         │
└─────────────┘           └──────────────┘           └────┬────┘
                                                           │
┌─────────────┐           ┌──────────────┐                ▼
│  Microphone │──────────►│ Audio Input  │           ┌─────────┐
│             │           │   Buffer     │──────────►│  Mixer  │
└─────────────┘           └──────────────┘           └────┬────┘
                                                           │
┌─────────────┐           ┌──────────────┐                ▼
│    MIDI     │──────────►│ MIDI Event   │           ┌─────────┐
│   Device    │           │  Processor   │──────────►│   DSP   │
└─────────────┘           └──────────────┘           │ Engine  │
                                                      └────┬────┘
                                                           │
                          ┌──────────────┐                ▼
                          │   Latency    │           ┌─────────┐
                          │ Compensation │◄──────────│ Output  │
                          └──────────────┘           │ Buffer  │
                                                      └────┬────┘
                                                           │
                                                           ▼
                                                      ┌─────────┐
                                                      │ Speaker │
                                                      └─────────┘

レイテンシー測定ポイント: 
━━━━━━━━━━━━━━━━━━━━━►
Input → DSP → Output
Target: <5ms (Phase 3)
Current: <20ms (Phase 2)
```

### 2.2 大容量ファイル処理戦略

```swift
// メモリ効率的なストリーミング処理
struct AudioFileStreamer {
    private let chunkSize = 1024 * 1024  // 1MB chunks
    private var fileHandle: ExtAudioFileRef?
    
    func streamProcess(url: URL) async throws {
        // 1. ファイルを開くがメモリにロードしない
        // 2. チャンク単位で読み込み
        // 3. リングバッファで管理
        // 4. 処理済みチャンクは即座に解放
    }
}

// リングバッファ実装
class RingBuffer<T> {
    private var buffer: UnsafeMutablePointer<T>
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private let capacity: Int
    
    // Lock-freeアトミック操作で高速化
}
```

### 2.3 リアルタイム処理フロー

```
┌──────────────────────────────────────────────────────┐
│                 Real-time Thread                      │
│  優先度: Highest (時間制約あり)                        │
│  ┌──────────────────────────────────────────────┐   │
│  │  Audio Callback (Core Audio)                  │   │
│  │  - No Memory Allocation                       │   │
│  │  - No Locks (Lock-free algorithms)            │   │
│  │  - Fixed Time Budget (5ms)                    │   │
│  └──────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
                          │
                    Message Passing
                    (Lock-free Queue)
                          │
┌──────────────────────────────────────────────────────┐
│                 UI Update Thread                      │
│  優先度: Normal                                        │
│  ┌──────────────────────────────────────────────┐   │
│  │  SwiftUI View Updates                         │   │
│  │  - 60fps (16.67ms budget)                     │   │
│  │  - Async State Updates                        │   │
│  │  - Smooth Animations                          │   │
│  └──────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

---

## 3. 開発ロードマップ詳細

### Phase 1: 基盤構築（現在進行中）
**期間**: 2025年8月 - 2025年9月  
**目標**: 基本的なSwiftUIアプリケーション構造の確立

```
完了タスク:
├── ✓ プロジェクト初期設定
├── ✓ SwiftUIアプリ基本構造
├── ✓ Git LFS設定（大容量WAVファイル）
└── ○ LNX-4: 基本オーディオ機能
    ├── □ オーディオデバイス列挙
    ├── □ 単一トラック再生/停止
    ├── □ ボリューム制御
    └── □ レイテンシー測定（<20ms）
```

### Phase 2: Core Audio統合（v0.2 "Rising Tide"）
**期間**: 2025年9月 - 2025年10月  
**リリース**: 2025年10月31日

```
主要機能:
├── Core Audio統合
│   ├── オーディオセッション管理
│   ├── リアルタイムオーディオ処理
│   └── 低レイテンシー最適化
├── マルチトラック（8トラック）
│   ├── 並列再生
│   ├── ミキシング
│   └── 個別コントロール
├── 基本MIDI
│   ├── MIDIデバイス検出
│   ├── ノートオン/オフ
│   └── コントロールチェンジ
└── プロジェクトファイル（.lnxproj）
    ├── セッション保存/読み込み
    ├── 設定の永続化
    └── オーディオファイル参照
```

### Phase 3: Visual統合（v0.3 "Wave Rider"）
**期間**: 2025年11月 - 2025年12月  
**リリース**: 2025年12月31日

```
主要機能:
├── Metal Performance Shaders
│   ├── リアルタイムビジュアライザー
│   ├── オーディオ反応型エフェクト
│   └── GPU最適化レンダリング
├── 高度な作曲機能
│   ├── オートメーション
│   ├── エフェクトチェーン
│   └── サイドチェーン
├── Vision Pro対応
│   ├── 空間オーディオ
│   ├── 3Dビジュアライゼーション
│   └── ハンドトラッキング制御
└── ネットワーク同期
    ├── 複数デバイス同期
    ├── リモートコントロール
    └── ストリーミング
```

### Phase 4: エンタープライズ機能（2026年）
**期間**: 2026年1月 - 2026年6月

```
拡張機能:
├── プラグインシステム
│   ├── AudioUnit v3対応
│   ├── VST3ブリッジ
│   └── カスタムDSP
├── AI統合
│   ├── 自動ミキシング
│   ├── スタイル変換
│   └── 生成的作曲
├── クラウド連携
│   ├── プロジェクト同期
│   ├── コラボレーション
│   └── バックアップ
└── プロフェッショナル機能
    ├── タイムコード同期
    ├── ハードウェアコントローラー
    └── 放送品質出力
```

---

## 4. API設計仕様

### 4.1 モジュール間インターフェース

```swift
// MARK: - Audio Module Protocol
protocol LNXAudioModule {
    associatedtype Configuration
    associatedtype Output
    
    func configure(_ config: Configuration) async throws
    func process(buffer: AudioBuffer) -> Output
    func reset()
    var latency: TimeInterval { get }
}

// MARK: - Visual Module Protocol  
protocol LNXVisualModule {
    associatedtype RenderTarget
    
    func render(to target: RenderTarget, 
                audioData: AudioAnalysisData) async
    func updateShaderParams(_ params: ShaderParameters)
    var frameRate: Double { get }
}

// MARK: - Sync Module Protocol
protocol LNXSyncModule {
    func getCurrentTime() -> AudioTime
    func sync(with remote: RemoteTimeSource) async throws
    func registerSyncListener(_ listener: SyncListener)
}
```

### 4.2 Core Audioラッパー設計

```swift
// MARK: - Low-Level Audio Engine
final class LNXAudioEngine {
    private var audioUnit: AudioComponentInstance?
    private var renderCallback: AURenderCallback?
    
    struct Configuration {
        let sampleRate: Double = 48000
        let bufferSize: UInt32 = 256  // ~5.3ms @ 48kHz
        let channels: UInt32 = 2
        let format: AudioStreamBasicDescription
    }
    
    func start() async throws {
        // 1. Audio Sessionセットアップ
        // 2. Audio Unit初期化
        // 3. Render Callback登録
        // 4. リアルタイムスレッド優先度設定
    }
    
    func processBuffer(
        _ buffer: UnsafeMutablePointer<Float>,
        frameCount: UInt32
    ) {
        // Lock-free処理
        // SIMD最適化
        // DSPアルゴリズム適用
    }
}
```

### 4.3 プロジェクトファイル形式（.lnxproj）

```json
{
  "version": "1.0.0",
  "metadata": {
    "title": "Project Name",
    "author": "Artist Name",
    "created": "2025-10-31T00:00:00Z",
    "modified": "2025-10-31T00:00:00Z",
    "tempo": 120.0,
    "timeSignature": "4/4"
  },
  "tracks": [
    {
      "id": "track-001",
      "name": "Track 1",
      "type": "audio",
      "source": {
        "type": "file",
        "path": "./audio/sample.wav",
        "offset": 0,
        "length": 240000
      },
      "effects": [
        {
          "type": "reverb",
          "params": {
            "roomSize": 0.7,
            "damping": 0.5
          }
        }
      ],
      "automation": [
        {
          "parameter": "volume",
          "points": [
            {"time": 0, "value": 0.8},
            {"time": 1000, "value": 1.0}
          ]
        }
      ]
    }
  ],
  "visuals": {
    "scenes": [
      {
        "id": "scene-001",
        "shader": "waveform",
        "params": {
          "color": "#00FF00",
          "intensity": 0.8
        }
      }
    ]
  },
  "sync": {
    "masterClock": "internal",
    "bpm": 120,
    "offset": 0
  }
}
```

---

## 5. パフォーマンス仕様

### 5.1 レイテンシー要件

| Phase | 目標レイテンシー | バッファサイズ | 用途 |
|-------|-----------------|---------------|------|
| Phase 1 | <100ms | 2048 samples | 開発/テスト |
| Phase 2 | <20ms | 512 samples | 一般使用 |
| Phase 3 | <10ms | 256 samples | プロ使用 |
| Phase 4 | <5ms | 128 samples | ライブパフォーマンス |

### 5.2 メモリ管理戦略

```
メモリ階層:
┌─────────────────────────────────────┐
│ Static Allocation (起動時)           │
│ - Audio Buffers: 50MB               │
│ - Shader Cache: 100MB               │
│ - UI Resources: 50MB                │
├─────────────────────────────────────┤
│ Dynamic Allocation (実行時)          │
│ - File Streaming: 10MB/track        │
│ - Effect Processing: 5MB/effect     │
│ - Visual Rendering: 200MB           │
├─────────────────────────────────────┤
│ Memory Pool (事前割り当て)           │
│ - Real-time Buffers: 20MB          │
│ - Lock-free Queues: 10MB           │
└─────────────────────────────────────┘

Total Memory Budget: ~500MB (通常使用)
                     ~1GB (最大負荷時)
```

### 5.3 CPU使用率目標

```
CPU配分:
┌──────────────────────────────┐
│ Audio Processing: 30%        │
│ Visual Rendering: 25%        │
│ UI Updates: 10%              │
│ System Overhead: 10%         │
│ Reserved: 25%                │
└──────────────────────────────┘

最適化技術:
- SIMD (Accelerate.framework)
- マルチスレッド並列処理
- GPU オフロード (Metal)
- キャッシュ最適化
```

### 5.4 GUI応答性

```
フレームレート要件:
┌────────────────────────────────────────┐
│ 通常操作: 60fps (16.67ms/frame)        │
│ アニメーション: 120fps (8.33ms/frame)  │
│ 最小許容: 30fps (33.33ms/frame)        │
└────────────────────────────────────────┘

最適化戦略:
- 差分更新 (SwiftUI @State)
- 遅延レンダリング
- LOD (Level of Detail)
- 非同期更新
```

---

## 6. 技術スタック詳細

### 6.1 コア技術

| レイヤー | 技術 | 用途 |
|---------|------|------|
| UI | SwiftUI, Combine | リアクティブUI |
| Audio | Core Audio, AVFoundation | 低レイテンシー処理 |
| Visual | Metal, Core Image | GPU処理 |
| Data | Core Data, Codable | 永続化 |
| Network | Network.framework | 同期/ストリーミング |
| Testing | XCTest, Swift Testing | 品質保証 |

### 6.2 外部依存関係

```swift
// Package.swift (将来的なSPM統合)
dependencies: [
    // オーディオ処理
    .package(url: "https://github.com/AudioKit/AudioKit", from: "5.0.0"),
    
    // MIDI
    .package(url: "https://github.com/AudioKit/MIDIKit", from: "1.0.0"),
    
    // DSP
    .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
]
```

---

## 7. セキュリティとサンドボックス

### 7.1 現在の権限（Phase 1）

```xml
<!-- LNXX.entitlements -->
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
```

### 7.2 将来必要な権限（Phase 2-4）

```xml
<!-- 追加予定の権限 -->
<dict>
    <!-- オーディオ入力 -->
    <key>com.apple.security.device.microphone</key>
    <true/>
    
    <!-- ネットワーク -->
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    
    <!-- USB/MIDI -->
    <key>com.apple.security.device.usb</key>
    <true/>
    
    <!-- ファイル書き込み -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
```

---

## 8. テスト戦略

### 8.1 テストピラミッド

```
                 E2E Tests
                    /\
                   /  \
                  /    \
           Integration Tests
                /      \
               /        \
              /          \
           Unit Tests (Base)

配分:
- Unit Tests: 70%
- Integration Tests: 20%  
- E2E Tests: 10%
```

### 8.2 パフォーマンステスト

```swift
// オーディオレイテンシー測定
func testAudioLatency() async throws {
    let engine = LNXAudioEngine()
    await engine.start()
    
    let startTime = CACurrentMediaTime()
    let signal = TestSignal.impulse
    
    await engine.process(signal)
    let endTime = CACurrentMediaTime()
    
    let latency = (endTime - startTime) * 1000
    XCTAssertLessThan(latency, 20.0, "Latency exceeds 20ms")
}

// メモリ使用量測定
func testMemoryUsage() async throws {
    let baseline = memoryFootprint()
    
    // 大容量ファイル処理
    let processor = AudioFileProcessor()
    await processor.process(largeWAVFile)
    
    let peak = memoryFootprint()
    let usage = peak - baseline
    
    XCTAssertLessThan(usage, 100_000_000, "Memory usage exceeds 100MB")
}
```

---

## 9. 開発ガイドライン

### 9.1 コーディング規約

```swift
// MARK: - Naming Conventions
// Types: PascalCase
struct LNXAudioProcessor { }

// Functions: camelCase, descriptive
func processAudioBuffer(input: AudioBuffer) -> ProcessedBuffer

// Constants: lowerCamelCase
let maximumLatency: TimeInterval = 0.020

// MARK: - Error Handling
enum LNXError: Error {
    case audioDeviceNotFound
    case bufferOverflow
    case fileNotSupported(String)
}

// MARK: - Documentation
/// Processes audio buffer with DSP effects
/// - Parameters:
///   - buffer: Input audio buffer
///   - effects: Array of effects to apply
/// - Returns: Processed audio buffer
/// - Throws: `LNXError.bufferOverflow` if buffer size exceeds limit
func applyEffects(to buffer: AudioBuffer, 
                  effects: [AudioEffect]) throws -> AudioBuffer
```

### 9.2 Git コミット規約

```bash
# フォーマット
<type>(<scope>): <subject>

# タイプ
feat: 新機能
fix: バグ修正
perf: パフォーマンス改善
refactor: リファクタリング
docs: ドキュメント
test: テスト
chore: ビルド/ツール

# 例
feat(audio): implement low-latency audio engine
fix(ui): resolve memory leak in waveform view
perf(dsp): optimize FFT processing with SIMD
```

---

## 10. リスクと緩和策

### 10.1 技術的リスク

| リスク | 影響度 | 緩和策 |
|-------|-------|-------|
| Core Audio APIの複雑性 | 高 | AudioKitフレームワークの活用 |
| リアルタイム制約違反 | 高 | プロファイリングとベンチマーク |
| メモリ不足（大容量ファイル） | 中 | ストリーミング処理実装 |
| Metal/GPUの互換性 | 中 | フォールバック実装 |
| App Store審査リジェクト | 低 | ガイドライン準拠確認 |

### 10.2 プロジェクトリスク

| リスク | 影響度 | 緩和策 |
|-------|-------|-------|
| スケジュール遅延 | 中 | アジャイル開発、MVP優先 |
| スコープクリープ | 中 | 厳格なフェーズ管理 |
| 技術的負債 | 低 | 継続的リファクタリング |

---

## 11. 参考資料とリソース

### 11.1 技術ドキュメント

- [Core Audio Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)
- [Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders)
- [SwiftUI Layout System](https://developer.apple.com/documentation/swiftui/layout)
- [Combine Framework](https://developer.apple.com/documentation/combine)

### 11.2 関連プロジェクト

- [AudioKit](https://github.com/AudioKit/AudioKit) - Swiftオーディオフレームワーク
- [JUCE](https://juce.com/) - クロスプラットフォームオーディオ
- [openFrameworks](https://openframeworks.cc/) - クリエイティブコーディング

### 11.3 パフォーマンス最適化

- [Optimizing Swift Performance](https://github.com/apple/swift/blob/main/docs/OptimizationTips.rst)
- [Metal Best Practices](https://developer.apple.com/documentation/metal/metal_best_practices_guide)
- [Real-time Audio Programming](http://www.rossbencina.com/code/real-time-audio-programming-101-time-waits-for-nothing)

---

## 12. 付録

### A. 用語集

| 用語 | 説明 |
|------|------|
| DSP | Digital Signal Processing - デジタル信号処理 |
| FFT | Fast Fourier Transform - 高速フーリエ変換 |
| SIMD | Single Instruction Multiple Data - 並列演算 |
| DAW | Digital Audio Workstation - 音楽制作ソフト |
| VST | Virtual Studio Technology - オーディオプラグイン規格 |
| AU | Audio Unit - macOSオーディオプラグイン規格 |

### B. バージョン履歴

| バージョン | 日付 | 変更内容 |
|-----------|------|----------|
| 1.0.0 | 2025-08-09 | 初版作成 |

### C. 連絡先

- プロジェクトリード: [TBD]
- 技術リード: [TBD]
- Linear Team: LNX (b0875e10-fcb9-41cd-bada-9d25c3963eea)

---

*このドキュメントは、LNX Experienceプロジェクトの進行に応じて継続的に更新されます。*