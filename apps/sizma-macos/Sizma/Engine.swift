import Foundation
import SceneKit

/// Sizmaのメインエンジン
/// SceneKitを使用した3Dシーンの管理とレンダリングを担当する
@MainActor
final class Engine: Loggable {
    // MARK: - Singleton
    static let shared = Engine()

    // MARK: - Properties
    private var scene: SCNScene
    private var isRunning: Bool = false

    // MARK: - Initialization
    private init() {
        self.scene = SCNScene()
        log("Engine initialized")
    }

    // MARK: - Lifecycle
    /// エンジンを起動する
    func start() {
        guard !isRunning else {
            logWarning("Engine already running")
            return
        }
        isRunning = true
        log("Engine started")
    }

    /// エンジンを停止する
    func stop() {
        guard isRunning else {
            logWarning("Engine already stopped")
            return
        }
        isRunning = false
        log("Engine stopped")
    }

    // MARK: - Scene Access
    /// 現在のSceneKitシーンを取得する
    /// - Returns: SCNSceneインスタンス
    func getScene() -> SCNScene {
        return scene
    }
}