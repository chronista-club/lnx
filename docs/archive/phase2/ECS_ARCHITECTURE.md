# LNX Experience ECS (Entity-Component-System) アーキテクチャ設計

> **Status**: Deprecated — 2025-08 の Swift / SwiftUI（LNXX）時代の ECS 設計。現在の Rust + SwiftUI 実装とは合わない（Bevy の ECS を使う窓は `crates/lnx-creare` の骨格だけ）。構成は [design 02](../../design/02-architecture.md)。経緯の参照用に残す

## 文書情報
- **バージョン**: 2.0.0
- **作成日**: 2025-08-09
- **目的**: リアルタイム処理のためのECSパターン実装設計
- **対象**: Audio/Visual処理の効率的な管理

---

## 1. ECSアーキテクチャ概要

### 1.1 なぜECSを採用するか

#### 従来のOOPアプローチの問題点
1. **継承階層の複雑化**: AudioVisualEffectクラスの多重継承問題
2. **パフォーマンス**: キャッシュミスによる処理速度低下
3. **柔軟性の欠如**: 実行時の動的な振る舞い変更が困難

#### ECSの利点
1. **データ指向設計**: キャッシュフレンドリーなメモリレイアウト
2. **組み合わせの柔軟性**: コンポーネントの動的な追加・削除
3. **並列処理**: システム間の独立性による効率的な並列実行
4. **テスタビリティ**: 各システムの独立したテスト

### 1.2 LNX Experience特有の要件

```
リアルタイムオーディオ/ビジュアル処理における要件:
- レイテンシ: < 5ms
- 更新頻度: Audio 48kHz, Visual 120fps
- メモリ: プリアロケーション必須
- スレッド: リアルタイムスレッドでの実行
```

---

## 2. コア設計

### 2.1 基本構造

```swift
// Entity: 一意のIDのみを持つ
typealias Entity = UUID

// Component: データのみを持つ構造体
protocol Component {
    static var componentId: ComponentID { get }
}

// System: ロジックを実装
protocol System {
    associatedtype RequiredComponents
    func update(deltaTime: TimeInterval, entities: [Entity], world: World)
}

// World: ECS全体を管理
class World {
    private var entities: Set<Entity> = []
    private var componentStorage: ComponentStorage
    private var systems: [any System] = []
}
```

### 2.2 アーキテクチャ図

```
┌──────────────────────────────────────────────────────────┐
│                         World                             │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐ │
│  │   Entities   │  │  Components   │  │    Systems     │ │
│  ├─────────────┤  ├──────────────┤  ├────────────────┤ │
│  │ Entity #001  │  │ AudioSource   │  │ AudioSystem    │ │
│  │ Entity #002  │  │ Transform     │  │ RenderSystem   │ │
│  │ Entity #003  │  │ VisualEffect  │  │ PhysicsSystem  │ │
│  │     ...      │  │ Velocity      │  │ InputSystem    │ │
│  └─────────────┘  └──────────────┘  └────────────────┘ │
│                                                           │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Component Storage                     │   │
│  │  ┌────────────────────────────────────────────┐  │   │
│  │  │ Entity #001: [AudioSource, Transform, ...] │  │   │
│  │  │ Entity #002: [VisualEffect, Velocity, ...] │  │   │
│  │  └────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

---

## 3. Component設計

### 3.1 Audio Components

```swift
// AudioSource.swift
struct AudioSource: Component {
    static let componentId = ComponentID("audio.source")
    
    var bufferID: AudioBufferID
    var volume: Float = 1.0
    var pitch: Float = 1.0
    var isPlaying: Bool = false
    var loopCount: Int = 0
    var position: TimeInterval = 0
}

// AudioEffect.swift
struct AudioEffect: Component {
    static let componentId = ComponentID("audio.effect")
    
    enum EffectType {
        case reverb(mix: Float, roomSize: Float)
        case delay(time: TimeInterval, feedback: Float)
        case distortion(gain: Float, level: Float)
        case eq(bands: [FrequencyBand])
    }
    
    var effects: [EffectType] = []
    var bypassState: Set<Int> = []
}

// AudioAnalysis.swift
struct AudioAnalysis: Component {
    static let componentId = ComponentID("audio.analysis")
    
    var spectrum: [Float] = Array(repeating: 0, count: 512)
    var peakLevel: Float = 0
    var rmsLevel: Float = 0
    var zeroCrossingRate: Float = 0
    var spectralCentroid: Float = 0
}

// AudioSync.swift
struct AudioSync: Component {
    static let componentId = ComponentID("audio.sync")
    
    var bpm: Double = 120.0
    var beat: Int = 0
    var bar: Int = 0
    var phase: Double = 0
    var isQuantized: Bool = false
}
```

### 3.2 Visual Components

```swift
// Transform.swift
struct Transform: Component {
    static let componentId = ComponentID("transform")
    
    var position: SIMD3<Float> = .zero
    var rotation: simd_quatf = simd_quatf(angle: 0, axis: .init(0, 1, 0))
    var scale: SIMD3<Float> = .one
    
    var worldMatrix: float4x4 {
        let T = float4x4(translation: position)
        let R = float4x4(rotation)
        let S = float4x4(scale: scale)
        return T * R * S
    }
}

// VisualEffect.swift
struct VisualEffect: Component {
    static let componentId = ComponentID("visual.effect")
    
    var shaderName: String
    var parameters: [String: Any] = [:]
    var blendMode: BlendMode = .normal
    var opacity: Float = 1.0
}

// Mesh.swift
struct Mesh: Component {
    static let componentId = ComponentID("mesh")
    
    var vertexBuffer: MTLBuffer
    var indexBuffer: MTLBuffer?
    var vertexCount: Int
    var primitiveType: MTLPrimitiveType = .triangle
}

// Material.swift
struct Material: Component {
    static let componentId = ComponentID("material")
    
    var diffuseTexture: MTLTexture?
    var normalTexture: MTLTexture?
    var roughness: Float = 0.5
    var metallic: Float = 0.0
    var emissiveColor: SIMD3<Float> = .zero
}

// ParticleEmitter.swift
struct ParticleEmitter: Component {
    static let componentId = ComponentID("particle.emitter")
    
    var maxParticles: Int = 1000
    var emissionRate: Float = 100
    var lifetime: ClosedRange<Float> = 1.0...2.0
    var velocity: ClosedRange<SIMD3<Float>>
    var size: ClosedRange<Float> = 0.1...0.5
    var colorOverLifetime: Gradient
}
```

### 3.3 共通Components

```swift
// Velocity.swift
struct Velocity: Component {
    static let componentId = ComponentID("velocity")
    
    var linear: SIMD3<Float> = .zero
    var angular: SIMD3<Float> = .zero
    var damping: Float = 0.99
}

// Tag.swift
struct Tag: Component {
    static let componentId = ComponentID("tag")
    
    var tags: Set<String> = []
    
    func has(_ tag: String) -> Bool {
        tags.contains(tag)
    }
}

// Lifetime.swift
struct Lifetime: Component {
    static let componentId = ComponentID("lifetime")
    
    var remainingTime: TimeInterval
    var onExpire: (() -> Void)?
}
```

---

## 4. System設計

### 4.1 Audio Systems

```swift
// AudioPlaybackSystem.swift
class AudioPlaybackSystem: System {
    typealias RequiredComponents = (AudioSource, Transform?)
    
    private let audioEngine: AudioEngineProtocol
    private let bufferCache: AudioBufferCache
    
    func update(deltaTime: TimeInterval, entities: [Entity], world: World) {
        for entity in entities {
            guard let source = world.getComponent(AudioSource.self, for: entity) else { continue }
            
            if source.isPlaying {
                // 3D音源の場合は位置を考慮
                if let transform = world.getComponent(Transform.self, for: entity) {
                    update3DAudio(source: source, position: transform.position)
                }
                
                // バッファを進める
                advancePlayback(source: &source, deltaTime: deltaTime)
            }
        }
    }
    
    private func update3DAudio(source: AudioSource, position: SIMD3<Float>) {
        // 3D音源処理（距離減衰、パンニング）
        let listenerPos = audioEngine.listenerPosition
        let distance = simd_distance(position, listenerPos)
        let attenuation = 1.0 / max(1.0, distance)
        
        audioEngine.setVolume(source.volume * attenuation, for: source.bufferID)
    }
}

// AudioEffectSystem.swift
class AudioEffectSystem: System {
    typealias RequiredComponents = (AudioSource, AudioEffect)
    
    private let effectProcessors: [EffectType: AudioProcessorProtocol]
    
    func update(deltaTime: TimeInterval, entities: [Entity], world: World) {
        for entity in entities {
            guard let source = world.getComponent(AudioSource.self, for: entity),
                  let effects = world.getComponent(AudioEffect.self, for: entity) else { continue }
            
            // エフェクトチェーン処理
            var buffer = getAudioBuffer(for: source)
            
            for (index, effect) in effects.effects.enumerated() {
                if !effects.bypassState.contains(index) {
                    buffer = processEffect(effect, buffer: buffer)
                }
            }
            
            outputBuffer(buffer, to: source)
        }
    }
}

// AudioAnalysisSystem.swift
class AudioAnalysisSystem: System {
    typealias RequiredComponents = (AudioSource, AudioAnalysis)
    
    private let fftProcessor: FFTProcessor
    
    func update(deltaTime: TimeInterval, entities: [Entity], world: World) {
        for entity in entities {
            guard let source = world.getComponent(AudioSource.self, for: entity),
                  var analysis = world.getComponent(AudioAnalysis.self, for: entity) else { continue }
            
            let buffer = getAudioBuffer(for: source)
            
            // FFT解析
            analysis.spectrum = fftProcessor.analyze(buffer)
            
            // レベル計算
            analysis.peakLevel = calculatePeakLevel(buffer)
            analysis.rmsLevel = calculateRMSLevel(buffer)
            
            // スペクトル特徴
            analysis.spectralCentroid = calculateSpectralCentroid(analysis.spectrum)
            
            world.setComponent(analysis, for: entity)
        }
    }
}
```

### 4.2 Visual Systems

```swift
// RenderSystem.swift
class RenderSystem: System {
    typealias RequiredComponents = (Transform, Mesh, Material)
    
    private let renderer: MetalVisualEngine
    private var renderQueue: [RenderCommand] = []
    
    func update(deltaTime: TimeInterval, entities: [Entity], world: World) {
        renderQueue.removeAll(keepingCapacity: true)
        
        // カメラ取得
        let camera = findCamera(in: world)
        let viewMatrix = camera.viewMatrix
        let projectionMatrix = camera.projectionMatrix
        
        // レンダーコマンド生成
        for entity in entities {
            guard let transform = world.getComponent(Transform.self, for: entity),
                  let mesh = world.getComponent(Mesh.self, for: entity),
                  let material = world.getComponent(Material.self, for: entity) else { continue }
            
            let command = RenderCommand(
                worldMatrix: transform.worldMatrix,
                mesh: mesh,
                material: material,
                viewProjectionMatrix: projectionMatrix * viewMatrix
            )
            
            renderQueue.append(command)
        }
        
        // Z-sort（透明オブジェクト用）
        renderQueue.sort { $0.distanceFromCamera > $1.distanceFromCamera }
        
        // GPU実行
        renderer.execute(renderQueue)
    }
}

// ParticleSystem.swift
class ParticleSystem: System {
    typealias RequiredComponents = (Transform, ParticleEmitter)
    
    private var particlePool: ParticlePool
    private let maxGlobalParticles = 100_000
    
    struct Particle {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var size: Float
        var lifetime: Float
        var age: Float = 0
    }
    
    func update(deltaTime: TimeInterval, entities: [Entity], world: World) {
        for entity in entities {
            guard let transform = world.getComponent(Transform.self, for: entity),
                  let emitter = world.getComponent(ParticleEmitter.self, for: entity) else { continue }
            
            // 新規パーティクル生成
            let particlesToEmit = Int(emitter.emissionRate * Float(deltaTime))
            
            for _ in 0..<particlesToEmit {
                if let particle = particlePool.acquire() {
                    initializeParticle(particle, emitter: emitter, origin: transform.position)
                }
            }
            
            // 既存パーティクル更新
            updateParticles(deltaTime: deltaTime)
        }
    }
    
    private func updateParticles(deltaTime: TimeInterval) {
        particlePool.forEach { particle in
            particle.age += Float(deltaTime)
            
            if particle.age > particle.lifetime {
                particlePool.release(particle)
            } else {
                // 物理更新
                particle.velocity.y -= 9.8 * Float(deltaTime) // 重力
                particle.position += particle.velocity * Float(deltaTime)
            }
        }
    }
}

// VisualEffectSystem.swift
class VisualEffectSystem: System {
    typealias RequiredComponents = (VisualEffect, AudioAnalysis?)
    
    private let shaderLibrary: ShaderLibrary
    
    func update(deltaTime: TimeInterval, entities: [Entity], world: World) {
        for entity in entities {
            guard let effect = world.getComponent(VisualEffect.self, for: entity) else { continue }
            
            // オーディオリアクティブエフェクト
            if let analysis = world.getComponent(AudioAnalysis.self, for: entity) {
                updateAudioReactiveParameters(effect: &effect, analysis: analysis)
            }
            
            // シェーダーパラメータ更新
            applyShaderParameters(effect)
        }
    }
    
    private func updateAudioReactiveParameters(effect: inout VisualEffect, analysis: AudioAnalysis) {
        // 低域でサイズ変更
        let bassLevel = analysis.spectrum[0..<8].reduce(0, +) / 8.0
        effect.parameters["scale"] = 1.0 + bassLevel * 0.5
        
        // 中域で色変更
        let midLevel = analysis.spectrum[64..<128].reduce(0, +) / 64.0
        effect.parameters["colorIntensity"] = midLevel
    }
}
```

### 4.3 同期Systems

```swift
// AudioVisualSyncSystem.swift
class AudioVisualSyncSystem: System {
    typealias RequiredComponents = (AudioSync, Transform)
    
    func update(deltaTime: TimeInterval, entities: [Entity], world: World) {
        for entity in entities {
            guard let sync = world.getComponent(AudioSync.self, for: entity),
                  var transform = world.getComponent(Transform.self, for: entity) else { continue }
            
            // ビート同期アニメーション
            let beatPhase = sync.phase
            let pulseMagnitude = sin(Float(beatPhase * .pi * 2))
            
            // スケールパルス
            transform.scale = .one * (1.0 + pulseMagnitude * 0.1)
            
            // 回転
            if sync.beat % 4 == 0 {
                transform.rotation = simd_quatf(angle: Float.pi / 4, axis: .init(0, 1, 0))
            }
            
            world.setComponent(transform, for: entity)
        }
    }
}
```

---

## 5. Component Storage最適化

### 5.1 メモリレイアウト

```swift
// ComponentStorage.swift
class ComponentStorage {
    // Sparse Set実装で高速アクセス
    private class SparseSet<T: Component> {
        private var dense: [T] = []
        private var entities: [Entity] = []
        private var sparse: [Entity: Int] = [:]
        
        func add(_ component: T, for entity: Entity) {
            if let index = sparse[entity] {
                dense[index] = component
            } else {
                dense.append(component)
                entities.append(entity)
                sparse[entity] = dense.count - 1
            }
        }
        
        func get(for entity: Entity) -> T? {
            guard let index = sparse[entity] else { return nil }
            return dense[index]
        }
        
        func remove(for entity: Entity) {
            guard let index = sparse[entity] else { return }
            
            // Swap and pop
            let lastIndex = dense.count - 1
            if index != lastIndex {
                dense[index] = dense[lastIndex]
                entities[index] = entities[lastIndex]
                sparse[entities[lastIndex]] = index
            }
            
            dense.removeLast()
            entities.removeLast()
            sparse[entity] = nil
        }
        
        // イテレーション最適化
        func forEach(_ closure: (Entity, inout T) -> Void) {
            for (index, entity) in entities.enumerated() {
                closure(entity, &dense[index])
            }
        }
    }
    
    private var storage: [ComponentID: Any] = [:]
    
    func register<T: Component>(_ type: T.Type) {
        storage[T.componentId] = SparseSet<T>()
    }
}
```

### 5.2 アーキタイプ最適化

```swift
// Archetype.swift
struct Archetype {
    let signature: Set<ComponentID>
    var entities: [Entity] = []
    var componentArrays: [ComponentID: Any] = [:]
    
    // Structure of Arrays (SoA)レイアウト
    func addEntity(_ entity: Entity, components: [any Component]) {
        entities.append(entity)
        
        for component in components {
            let id = type(of: component).componentId
            // 型消去されたArrayに追加
            appendComponent(component, to: id)
        }
    }
    
    // キャッシュ効率的なイテレーション
    func iterate<T: Component>(_ type: T.Type, _ closure: (Entity, T) -> Void) {
        guard let array = componentArrays[T.componentId] as? [T] else { return }
        
        for (index, entity) in entities.enumerated() {
            closure(entity, array[index])
        }
    }
}

// ArchetypeManager.swift
class ArchetypeManager {
    private var archetypes: [Set<ComponentID>: Archetype] = [:]
    private var entityArchetypes: [Entity: Archetype] = [:]
    
    func moveEntity(_ entity: Entity, to newSignature: Set<ComponentID>) {
        // 既存アーキタイプから削除
        if let oldArchetype = entityArchetypes[entity] {
            oldArchetype.removeEntity(entity)
        }
        
        // 新規アーキタイプに追加
        let newArchetype = archetypes[newSignature] ?? Archetype(signature: newSignature)
        newArchetype.addEntity(entity)
        
        entityArchetypes[entity] = newArchetype
        archetypes[newSignature] = newArchetype
    }
}
```

---

## 6. クエリシステム

### 6.1 エンティティクエリ

```swift
// Query.swift
struct Query<Components> {
    let world: World
    
    func entities() -> [Entity] {
        // コンポーネントシグネチャにマッチするエンティティを返す
        world.queryEntities(matching: Components.self)
    }
    
    func forEach(_ closure: (Entity, Components) -> Void) {
        for entity in entities() {
            if let components = world.getComponents(Components.self, for: entity) {
                closure(entity, components)
            }
        }
    }
}

// 使用例
let audioSourceQuery = Query<(AudioSource, Transform)>(world: world)
audioSourceQuery.forEach { entity, (source, transform) in
    // 処理
}
```

### 6.2 フィルタリング

```swift
// QueryBuilder.swift
class QueryBuilder {
    enum Filter {
        case has(ComponentID)
        case not(ComponentID)
        case any([ComponentID])
        case all([ComponentID])
        case tag(String)
    }
    
    private var filters: [Filter] = []
    
    func with<T: Component>(_ type: T.Type) -> Self {
        filters.append(.has(T.componentId))
        return self
    }
    
    func without<T: Component>(_ type: T.Type) -> Self {
        filters.append(.not(T.componentId))
        return self
    }
    
    func tagged(_ tag: String) -> Self {
        filters.append(.tag(tag))
        return self
    }
    
    func build() -> [Entity] {
        // フィルタ適用してエンティティリスト生成
    }
}
```

---

## 7. SwiftUIとの統合

### 7.1 ECS ViewModel Bridge

```swift
// ECSViewModel.swift
@MainActor
class ECSViewModel: ObservableObject {
    @Published var entities: [EntityViewModel] = []
    
    private let world = World()
    private var displayLink: CADisplayLink?
    
    init() {
        setupSystems()
        startUpdateLoop()
    }
    
    private func setupSystems() {
        // システム登録
        world.addSystem(AudioPlaybackSystem())
        world.addSystem(AudioEffectSystem())
        world.addSystem(RenderSystem())
        world.addSystem(ParticleSystem())
        world.addSystem(AudioVisualSyncSystem())
    }
    
    private func startUpdateLoop() {
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func update() {
        let deltaTime = displayLink?.targetTimestamp ?? 0
        world.update(deltaTime: deltaTime)
        
        // UI更新用のデータ抽出
        updateViewModels()
    }
    
    private func updateViewModels() {
        entities = world.getAllEntities().compactMap { entity in
            EntityViewModel(
                id: entity,
                name: world.getComponent(Tag.self, for: entity)?.tags.first ?? "Unknown",
                transform: world.getComponent(Transform.self, for: entity),
                audioLevel: world.getComponent(AudioAnalysis.self, for: entity)?.peakLevel
            )
        }
    }
}

// EntityViewModel.swift
struct EntityViewModel: Identifiable {
    let id: Entity
    let name: String
    let transform: Transform?
    let audioLevel: Float?
}
```

### 7.2 SwiftUI Views

```swift
// ECSView.swift
struct ECSView: View {
    @StateObject private var viewModel = ECSViewModel()
    
    var body: some View {
        NavigationSplitView {
            // Entity List
            List(viewModel.entities) { entity in
                EntityRow(entity: entity)
            }
        } detail: {
            // Entity Inspector
            if let selected = viewModel.selectedEntity {
                EntityInspector(entity: selected)
            }
        }
    }
}

// EntityInspector.swift
struct EntityInspector: View {
    let entity: EntityViewModel
    
    var body: some View {
        Form {
            if let transform = entity.transform {
                TransformEditor(transform: transform)
            }
            
            if let audioLevel = entity.audioLevel {
                AudioLevelMeter(level: audioLevel)
            }
        }
    }
}
```

---

## 8. パフォーマンス最適化

### 8.1 並列処理戦略

```swift
// ParallelSystemScheduler.swift
class ParallelSystemScheduler {
    private let systemGraph: SystemDependencyGraph
    private let executionQueue = DispatchQueue(label: "ecs.execution", attributes: .concurrent)
    
    func schedule(systems: [any System]) async {
        let stages = systemGraph.topologicalSort(systems)
        
        for stage in stages {
            // 同一ステージ内のシステムは並列実行可能
            await withTaskGroup(of: Void.self) { group in
                for system in stage {
                    group.addTask {
                        await system.update()
                    }
                }
            }
        }
    }
}
```

### 8.2 メモリプール

```swift
// ObjectPool.swift
class ObjectPool<T> {
    private var available: [T] = []
    private var inUse: Set<ObjectIdentifier> = []
    private let factory: () -> T
    private let reset: (T) -> Void
    private let maxSize: Int
    
    init(maxSize: Int = 1000, factory: @escaping () -> T, reset: @escaping (T) -> Void) {
        self.maxSize = maxSize
        self.factory = factory
        self.reset = reset
        
        // 事前割り当て
        for _ in 0..<maxSize / 2 {
            available.append(factory())
        }
    }
    
    func acquire() -> T? {
        if let object = available.popLast() {
            inUse.insert(ObjectIdentifier(object as AnyObject))
            return object
        } else if inUse.count < maxSize {
            let object = factory()
            inUse.insert(ObjectIdentifier(object as AnyObject))
            return object
        }
        return nil
    }
    
    func release(_ object: T) {
        reset(object)
        inUse.remove(ObjectIdentifier(object as AnyObject))
        available.append(object)
    }
}
```

---

## 9. テスト戦略

### 9.1 System単体テスト

```swift
// AudioSystemTests.swift
class AudioSystemTests: XCTestCase {
    var world: World!
    var audioSystem: AudioPlaybackSystem!
    
    override func setUp() {
        world = World()
        audioSystem = AudioPlaybackSystem()
    }
    
    func testAudioPlayback() {
        // エンティティ作成
        let entity = world.createEntity()
        
        // コンポーネント追加
        let audioSource = AudioSource(bufferID: "test", volume: 0.5)
        world.addComponent(audioSource, to: entity)
        
        // システム更新
        audioSystem.update(deltaTime: 0.016, entities: [entity], world: world)
        
        // 検証
        let updated = world.getComponent(AudioSource.self, for: entity)
        XCTAssertNotNil(updated)
        XCTAssertGreaterThan(updated!.position, 0)
    }
}
```

### 9.2 パフォーマンステスト

```swift
// ECSPerformanceTests.swift
class ECSPerformanceTests: XCTestCase {
    func testLargeScaleUpdate() {
        let world = World()
        
        // 10,000エンティティ生成
        for _ in 0..<10_000 {
            let entity = world.createEntity()
            world.addComponent(Transform(), to: entity)
            world.addComponent(Velocity(), to: entity)
        }
        
        let system = PhysicsSystem()
        
        // パフォーマンス測定
        measure {
            system.update(deltaTime: 0.016, entities: world.getAllEntities(), world: world)
        }
    }
}
```

---

## 10. 実装ロードマップ

### Phase 2.3.1: ECSコア実装（Week 1）
- [ ] Entity管理
- [ ] Component基盤
- [ ] System インターフェース
- [ ] World 実装

### Phase 2.3.2: Storage最適化（Week 2）
- [ ] Sparse Set実装
- [ ] Archetype システム
- [ ] メモリプール
- [ ] クエリ最適化

### Phase 2.3.3: Audio/Visual統合（Week 3）
- [ ] Audio Components
- [ ] Visual Components
- [ ] 各種Systems実装
- [ ] 同期メカニズム

### Phase 2.3.4: SwiftUI統合（Week 4）
- [ ] ViewModel Bridge
- [ ] リアクティブ更新
- [ ] Inspector UI
- [ ] パフォーマンステスト

---

## 11. 既存コードからの移行

### 11.1 移行戦略

```swift
// 既存コード
class AudioPlayer {
    func play() { }
    func stop() { }
}

// ECS移行後
extension World {
    func createAudioPlayer(file: URL) -> Entity {
        let entity = createEntity()
        
        // コンポーネント追加
        addComponent(AudioSource(file: file), to: entity)
        addComponent(Transform(), to: entity)
        
        return entity
    }
}

// 使用側
let player = world.createAudioPlayer(file: audioURL)
world.getComponent(AudioSource.self, for: player)?.isPlaying = true
```

### 11.2 互換性レイヤー

```swift
// LegacyAdapter.swift
class LegacyAudioPlayerAdapter {
    private let entity: Entity
    private let world: World
    
    init(world: World, file: URL) {
        self.world = world
        self.entity = world.createAudioPlayer(file: file)
    }
    
    // 既存APIを維持
    func play() {
        world.getComponent(AudioSource.self, for: entity)?.isPlaying = true
    }
    
    func stop() {
        world.getComponent(AudioSource.self, for: entity)?.isPlaying = false
    }
}
```

---

## 12. 参考資料

### ECS実装例
- [Unity DOTS](https://unity.com/dots) - Unity's Data-Oriented Technology Stack
- [Bevy Engine](https://bevyengine.org/) - Rust ECS game engine
- [entt](https://github.com/skypjack/entt) - C++ ECS library

### 技術文献
- "Data-Oriented Design" by Richard Fabian
- "Game Programming Patterns" by Robert Nystrom
- "Real-Time Rendering" by Akenine-Möller et al.

---

**改訂履歴**
- 2025-08-09: v2.0.0 - 初版作成

**次回レビュー**: 2025-09-30