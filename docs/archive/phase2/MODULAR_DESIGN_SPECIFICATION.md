# LNX Experience モジュラー設計詳細仕様書

## 文書情報
- **バージョン**: 2.0.0
- **作成日**: 2025-08-09
- **対象フェーズ**: Phase 2-4
- **ステータス**: Draft

---

## 1. モジュール設計概要

### 1.1 設計原則

#### 基本方針
1. **単一責任原則**: 各モジュールは明確に定義された単一の責任を持つ
2. **疎結合**: モジュール間の依存は最小限に抑え、プロトコルを介した通信を行う
3. **高凝集**: 関連する機能は同一モジュール内に配置
4. **置換可能性**: インターフェースを通じてモジュールの実装を交換可能に
5. **テスタビリティ**: 各モジュールは独立してテスト可能

#### 依存関係ルール
```
UI Layer → Domain Layer → Core Layer
         ↘             ↙
           Utils Layer
```

---

## 2. Audio モジュール

### 2.1 責任範囲
リアルタイムオーディオ処理、再生、録音、エフェクト処理を担当

### 2.2 インターフェース定義

```swift
// AudioEngine.swift
public protocol AudioEngineProtocol {
    // セッション管理
    func setupSession(config: AudioSessionConfig) async throws
    func startEngine() async throws
    func stopEngine() async
    
    // デバイス管理
    func getAvailableDevices() -> [AudioDevice]
    func setInputDevice(_ device: AudioDevice) throws
    func setOutputDevice(_ device: AudioDevice) throws
    
    // 遅延管理
    func getCurrentLatency() -> TimeInterval
    func setTargetLatency(_ latency: TimeInterval) throws
}

// AudioProcessor.swift
public protocol AudioProcessorProtocol {
    associatedtype ProcessorConfig
    
    func configure(_ config: ProcessorConfig) throws
    func process(_ buffer: AudioBuffer) -> AudioBuffer
    func reset()
    var latency: TimeInterval { get }
}

// AudioPlayer.swift
public protocol AudioPlayerProtocol {
    func load(url: URL) async throws
    func play() async
    func pause()
    func stop()
    func seek(to time: TimeInterval) async
    
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
}
```

### 2.3 内部構造

```
Audio/
├── Core/
│   ├── AudioEngine.swift         # Core Audio セッション管理
│   ├── AudioBuffer.swift         # バッファ管理
│   ├── AudioFormat.swift         # フォーマット定義
│   └── AudioDevice.swift         # デバイス抽象化
├── Processing/
│   ├── AudioProcessor.swift      # 処理チェーン管理
│   ├── Effects/
│   │   ├── ReverbProcessor.swift
│   │   ├── DelayProcessor.swift
│   │   └── EQProcessor.swift
│   └── Analysis/
│       ├── FFTAnalyzer.swift     # 周波数解析
│       └── LevelMeter.swift      # レベル測定
├── Playback/
│   ├── AudioPlayer.swift         # 再生制御
│   ├── AudioStreamer.swift       # ストリーミング再生
│   └── AudioFileReader.swift     # ファイル読み込み
└── Recording/
    ├── AudioRecorder.swift       # 録音機能
    └── AudioFileWriter.swift     # ファイル書き込み
```

### 2.4 パフォーマンス要件

| メトリクス | 現在目標 | 将来目標 |
|-----------|---------|---------|
| 入出力遅延 | < 20ms | < 5ms |
| バッファサイズ | 512 samples | 64 samples |
| サンプルレート | 48kHz | 96kHz |
| ビット深度 | 24-bit | 32-bit float |
| CPU使用率 | < 30% | < 15% |

---

## 3. Visual モジュール

### 3.1 責任範囲
リアルタイムビジュアルエフェクト、レンダリング、GPU処理を担当

### 3.2 インターフェース定義

```swift
// VisualRenderer.swift
public protocol VisualRendererProtocol {
    func setup(metalDevice: MTLDevice) throws
    func render(frame: VisualFrame, to drawable: CAMetalDrawable)
    func setEffect(_ effect: VisualEffect)
    func updateParameters(_ params: EffectParameters)
}

// VisualEffect.swift
public protocol VisualEffectProtocol {
    var name: String { get }
    var parameters: [EffectParameter] { get }
    
    func compile(device: MTLDevice) throws -> MTLFunction
    func process(input: MTLTexture, output: MTLTexture, encoder: MTLCommandEncoder)
}

// VisualizationEngine.swift
public protocol VisualizationEngineProtocol {
    func visualize(audioData: AudioAnalysisData) -> VisualFrame
    func setVisualizationType(_ type: VisualizationType)
    func updateConfiguration(_ config: VisualizationConfig)
}
```

### 3.3 内部構造

```
Visual/
├── Core/
│   ├── VisualRenderer.swift      # Metal レンダリングエンジン
│   ├── RenderPipeline.swift      # レンダーパイプライン
│   ├── TextureManager.swift      # テクスチャ管理
│   └── ShaderLibrary.swift       # シェーダー管理
├── Effects/
│   ├── Filters/
│   │   ├── BlurEffect.swift
│   │   ├── GlowEffect.swift
│   │   └── ColorGrading.swift
│   ├── Generators/
│   │   ├── ParticleSystem.swift
│   │   ├── WaveformGenerator.swift
│   │   └── SpectrumVisualizer.swift
│   └── Compositors/
│       ├── BlendModes.swift
│       └── LayerCompositor.swift
├── Shaders/
│   ├── Vertex/
│   │   └── BasicVertex.metal
│   └── Fragment/
│       ├── AudioReactive.metal
│       └── PostProcessing.metal
└── Utils/
    ├── ColorSpace.swift
    └── GeometryUtils.swift
```

### 3.4 GPU最適化戦略

1. **バッチレンダリング**: 描画呼び出しの最小化
2. **テクスチャアトラス**: テクスチャ切り替えの削減
3. **計算シェーダー**: 並列処理の活用
4. **メモリプール**: GPU メモリの効率的な再利用

---

## 4. Sync モジュール

### 4.1 責任範囲
オーディオとビジュアルの同期、タイミング管理、ネットワーク同期を担当

### 4.2 インターフェース定義

```swift
// SyncEngine.swift
public protocol SyncEngineProtocol {
    func startSync() async throws
    func stopSync()
    
    // タイミング管理
    func getCurrentTime() -> TimeInterval
    func scheduleEvent(_ event: SyncEvent, at time: TimeInterval)
    func cancelEvent(_ eventId: UUID)
    
    // 同期ソース
    func setMasterClock(_ clock: ClockSource)
    func addSyncTarget(_ target: SyncTarget)
}

// NetworkSync.swift
public protocol NetworkSyncProtocol {
    func startServer(port: Int) async throws
    func connectToServer(host: String, port: Int) async throws
    func disconnect()
    
    func broadcast(_ message: SyncMessage) async
    func onReceive(_ handler: @escaping (SyncMessage) -> Void)
}

// MIDISync.swift
public protocol MIDISyncProtocol {
    func setupMIDIClock() throws
    func startClock()
    func stopClock()
    func setTempo(_ bpm: Double)
    
    var isClockMaster: Bool { get set }
}
```

### 4.3 内部構造

```
Sync/
├── Core/
│   ├── SyncEngine.swift          # 同期エンジン
│   ├── MasterClock.swift         # マスタークロック
│   ├── TimelineManager.swift     # タイムライン管理
│   └── EventScheduler.swift      # イベントスケジューリング
├── AudioVisual/
│   ├── AVSyncManager.swift       # A/V同期
│   ├── LatencyCompensation.swift # 遅延補正
│   └── FrameSync.swift          # フレーム同期
├── Network/
│   ├── NetworkSync.swift         # ネットワーク同期
│   ├── SyncProtocol.swift        # 同期プロトコル
│   ├── PeerDiscovery.swift       # ピア発見
│   └── ClockSync.swift          # クロック同期（NTP-like）
└── MIDI/
    ├── MIDIClock.swift           # MIDIクロック
    ├── MIDITimeCode.swift        # MTC対応
    └── BeatSync.swift            # ビート同期
```

### 4.5 同期精度要件

| 同期タイプ | 許容誤差 | 測定方法 |
|-----------|---------|----------|
| ローカルA/V | < 1ms | サンプル精度 |
| ネットワーク | < 10ms | RTT補正後 |
| MIDIクロック | < 1 tick | 24 ppqn |
| タイムコード | < 1 frame | 30fps基準 |

---

## 5. UI モジュール

### 5.1 責任範囲
ユーザーインターフェース、インタラクション、ビジュアルフィードバックを担当

### 5.2 インターフェース定義

```swift
// UICoordinator.swift
public protocol UICoordinatorProtocol {
    func navigate(to screen: Screen)
    func present(_ modal: Modal)
    func dismiss()
    
    func showAlert(_ alert: AlertConfiguration)
    func showProgress(_ progress: ProgressConfiguration)
}

// ThemeManager.swift
public protocol ThemeManagerProtocol {
    var currentTheme: Theme { get }
    func setTheme(_ theme: Theme)
    func toggleDarkMode()
    
    func color(for element: UIElement) -> Color
    func font(for textStyle: TextStyle) -> Font
}

// GestureHandler.swift
public protocol GestureHandlerProtocol {
    func handleTap(at location: CGPoint)
    func handleDrag(from: CGPoint, to: CGPoint)
    func handlePinch(scale: CGFloat)
    func handleRotation(angle: CGFloat)
}
```

### 5.3 内部構造

```
UI/
├── Views/
│   ├── Main/
│   │   ├── MainView.swift
│   │   ├── SidebarView.swift
│   │   └── WorkspaceView.swift
│   ├── Audio/
│   │   ├── WaveformView.swift
│   │   ├── MixerView.swift
│   │   └── EffectsRackView.swift
│   ├── Visual/
│   │   ├── CanvasView.swift
│   │   ├── EffectsPanelView.swift
│   │   └── PreviewView.swift
│   └── Common/
│       ├── ControlKnob.swift
│       ├── Fader.swift
│       └── LEDMeter.swift
├── ViewModels/
│   ├── AudioViewModel.swift
│   ├── VisualViewModel.swift
│   └── ProjectViewModel.swift
├── Coordinators/
│   ├── AppCoordinator.swift
│   ├── NavigationCoordinator.swift
│   └── ModalCoordinator.swift
└── Theme/
    ├── ThemeManager.swift
    ├── ColorPalette.swift
    └── Typography.swift
```

### 5.4 レスポンシブデザイン要件

1. **フレームレート**: 60fps 維持（120fps ProMotion対応）
2. **タッチ遅延**: < 50ms
3. **アニメーション**: Spring physics ベース
4. **適応レイアウト**: ウィンドウサイズに応じた動的配置

---

## 6. Models モジュール

### 6.1 責任範囲
データモデル、永続化、プロジェクトファイル管理を担当

### 6.2 インターフェース定義

```swift
// Project.swift
public struct Project: Codable, Identifiable {
    let id: UUID
    var name: String
    var created: Date
    var modified: Date
    
    var audioTracks: [AudioTrack]
    var visualLayers: [VisualLayer]
    var syncSettings: SyncConfiguration
    var metadata: ProjectMetadata
}

// DataStore.swift
public protocol DataStoreProtocol {
    func save<T: Codable>(_ object: T, key: String) async throws
    func load<T: Codable>(_ type: T.Type, key: String) async throws -> T?
    func delete(key: String) async throws
    func list() async throws -> [String]
}

// ProjectManager.swift
public protocol ProjectManagerProtocol {
    func createProject(name: String) -> Project
    func openProject(url: URL) async throws -> Project
    func saveProject(_ project: Project, to url: URL) async throws
    func exportProject(_ project: Project, format: ExportFormat) async throws -> Data
    
    var currentProject: Project? { get }
    var recentProjects: [ProjectInfo] { get }
}
```

### 6.3 内部構造

```
Models/
├── Core/
│   ├── Project.swift             # プロジェクトモデル
│   ├── ProjectMetadata.swift     # メタデータ
│   ├── Identifiable.swift        # ID管理
│   └── Timestamped.swift         # タイムスタンプ
├── Audio/
│   ├── AudioTrack.swift          # オーディオトラック
│   ├── AudioClip.swift           # オーディオクリップ
│   ├── AudioEffect.swift         # エフェクト設定
│   └── MixerState.swift          # ミキサー状態
├── Visual/
│   ├── VisualLayer.swift         # ビジュアルレイヤー
│   ├── VisualClip.swift          # ビジュアルクリップ
│   ├── EffectChain.swift         # エフェクトチェーン
│   └── RenderSettings.swift      # レンダー設定
├── Sync/
│   ├── SyncConfiguration.swift   # 同期設定
│   ├── TimelineMarker.swift      # タイムラインマーカー
│   └── BeatGrid.swift            # ビートグリッド
└── Persistence/
    ├── ProjectFileFormat.swift   # .lnxproj フォーマット
    ├── DataStore.swift           # データストア
    ├── Migration/                # データ移行
    │   └── MigrationManager.swift
    └── Codable+Extensions.swift  # Codable拡張
```

### 6.4 データフォーマット仕様

#### .lnxproj ファイル構造
```
project.lnxproj/
├── manifest.json          # プロジェクトマニフェスト
├── project.json          # プロジェクト設定
├── audio/               # オーディオデータ
│   ├── tracks.json
│   └── clips/
├── visual/              # ビジュアルデータ
│   ├── layers.json
│   └── assets/
├── sync/                # 同期データ
│   └── timeline.json
└── resources/           # リソースファイル
    ├── samples/
    └── presets/
```

---

## 7. Utils モジュール

### 7.1 責任範囲
共通ユーティリティ、ヘルパー関数、拡張機能を提供

### 7.2 インターフェース定義

```swift
// Performance.swift
public struct PerformanceMonitor {
    static func measure<T>(_ label: String, _ block: () throws -> T) rethrows -> T
    static func startProfiling(_ category: ProfilingCategory)
    static func endProfiling(_ category: ProfilingCategory) -> ProfilingResult
}

// DSP.swift
public enum DSP {
    static func fft(_ samples: [Float], size: Int) -> [Complex<Float>]
    static func ifft(_ frequencies: [Complex<Float>], size: Int) -> [Float]
    static func convolve(_ signal: [Float], _ kernel: [Float]) -> [Float]
    static func resample(_ samples: [Float], from: Int, to: Int) -> [Float]
}

// Atomic.swift
@propertyWrapper
public struct Atomic<Value> {
    private var value: Value
    private let lock = NSLock()
    
    public var wrappedValue: Value {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
```

### 7.3 内部構造

```
Utils/
├── Performance/
│   ├── PerformanceMonitor.swift  # パフォーマンス監視
│   ├── MemoryTracker.swift       # メモリ追跡
│   ├── CPUProfiler.swift         # CPU プロファイリング
│   └── BenchmarkUtils.swift      # ベンチマーク
├── DSP/
│   ├── FFT.swift                 # 高速フーリエ変換
│   ├── Filters.swift             # デジタルフィルタ
│   ├── Resampling.swift          # リサンプリング
│   └── WindowFunctions.swift     # 窓関数
├── Concurrency/
│   ├── Atomic.swift              # アトミック操作
│   ├── ThreadSafeQueue.swift     # スレッドセーフキュー
│   ├── AsyncStream+Ext.swift     # AsyncStream拡張
│   └── TaskGroup+Ext.swift       # TaskGroup拡張
├── Math/
│   ├── Interpolation.swift       # 補間
│   ├── Easing.swift              # イージング関数
│   ├── Vector.swift              # ベクトル演算
│   └── Matrix.swift              # 行列演算
└── Extensions/
    ├── Collection+Ext.swift       # コレクション拡張
    ├── URL+Ext.swift             # URL拡張
    ├── Data+Ext.swift            # Data拡張
    └── Color+Ext.swift           # Color拡張
```

### 7.4 パフォーマンス最適化ユーティリティ

1. **メモリプール**: 頻繁なアロケーションの削減
2. **SIMD最適化**: ベクトル演算の高速化
3. **キャッシュ**: 計算結果のキャッシング
4. **並列処理**: GCDとSwift Concurrencyの活用

---

## 8. モジュール間連携

### 8.1 依存関係マトリクス

| モジュール | Audio | Visual | Sync | UI | Models | Utils |
|-----------|-------|--------|------|-----|--------|-------|
| Audio     | -     | ❌     | ✓    | ❌  | ✓      | ✓     |
| Visual    | ✓     | -      | ✓    | ❌  | ✓      | ✓     |
| Sync      | ❌    | ❌     | -    | ❌  | ✓      | ✓     |
| UI        | ✓     | ✓      | ✓    | -   | ✓      | ✓     |
| Models    | ❌    | ❌     | ❌   | ❌  | -      | ✓     |
| Utils     | ❌    | ❌     | ❌   | ❌  | ❌     | -     |

✓: 依存あり、❌: 依存なし

### 8.2 通信パターン

#### イベントドリブン通信
```swift
// EventBus を使用した疎結合通信
protocol EventBus {
    func publish<T: Event>(_ event: T)
    func subscribe<T: Event>(_ type: T.Type, handler: @escaping (T) -> Void) -> Cancellable
}

// 使用例
eventBus.publish(AudioPlaybackStarted(trackId: track.id))
eventBus.subscribe(AudioPlaybackStarted.self) { event in
    // ビジュアルエフェクトの開始
}
```

#### プロトコル指向インターフェース
```swift
// モジュール間の境界はプロトコルで定義
protocol AudioOutputProvider {
    var audioStream: AsyncStream<AudioBuffer> { get }
}

protocol VisualInputConsumer {
    func consume(audioData: AudioAnalysisData) async
}
```

---

## 9. テスト戦略

### 9.1 モジュール別テスト方針

| モジュール | 単体テスト | 統合テスト | パフォーマンステスト |
|-----------|-----------|-----------|-------------------|
| Audio     | 信号処理精度 | デバイス連携 | レイテンシ測定 |
| Visual    | シェーダー検証 | レンダリング | FPS測定 |
| Sync      | タイミング精度 | 同期精度 | ジッター測定 |
| UI        | View動作 | ユーザーフロー | 応答性測定 |
| Models    | シリアライゼーション | 永続化 | I/O性能 |
| Utils     | アルゴリズム正確性 | - | 処理速度 |

### 9.2 モックとスタブ

```swift
// テスト用モック実装
class MockAudioEngine: AudioEngineProtocol {
    var latency: TimeInterval = 0.005
    func getCurrentLatency() -> TimeInterval { latency }
    // ...
}

// 依存性注入
class AudioProcessor {
    init(engine: AudioEngineProtocol = AudioEngine()) {
        self.engine = engine
    }
}
```

---

## 10. 移行計画

### 10.1 段階的モジュール化

#### Phase 2.1: 基盤モジュール
1. Utils モジュールの実装
2. Models モジュールの実装
3. 既存コードのリファクタリング

#### Phase 2.2: コア機能モジュール
1. Audio モジュールの実装
2. 既存 AudioPlayer の移行
3. Core Audio 統合

#### Phase 2.3: 拡張モジュール
1. Visual モジュールの実装
2. Sync モジュールの実装
3. UI モジュールの強化

### 10.2 後方互換性

- 既存の SwiftUI Views は UI モジュールに段階的に移行
- 新機能は新モジュール内で実装
- 廃止予定APIは @deprecated でマーク

---

## 11. セキュリティとプライバシー

### 11.1 モジュール別セキュリティ要件

| モジュール | セキュリティ要件 |
|-----------|----------------|
| Audio | マイク権限、DRM対応 |
| Visual | GPU メモリ保護 |
| Sync | ネットワーク暗号化、認証 |
| UI | 入力検証、XSS防止 |
| Models | ファイル暗号化、署名検証 |
| Utils | セキュアランダム、ハッシュ |

### 11.2 App Sandbox 対応

```xml
<!-- 各モジュールが要求するentitlements -->
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
```

---

## 12. 付録

### 12.1 用語集

| 用語 | 定義 |
|-----|------|
| レイテンシ | 入力から出力までの遅延時間 |
| バッファ | 一時的にデータを保存するメモリ領域 |
| FFT | 高速フーリエ変換、時間領域から周波数領域への変換 |
| DSP | デジタル信号処理 |
| SIMD | 単一命令複数データ、並列処理技術 |

### 12.2 参考資料

- [Core Audio Programming Guide](https://developer.apple.com/documentation/coreaudio)
- [Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Audio Unit Programming Guide](https://developer.apple.com/documentation/audiounit)

---

**改訂履歴**
- 2025-08-09: v2.0.0 - Phase 2向け詳細仕様作成

**次回レビュー予定**: 2025-09-01