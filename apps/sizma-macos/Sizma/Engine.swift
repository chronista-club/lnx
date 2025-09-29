import Foundation
import SceneKit

@MainActor
final class Engine: Loggable {
    static let shared = Engine()

    private var scene: SCNScene
    private var isRunning: Bool = false

    private init() {
        self.scene = SCNScene()
        log("Engine initialized")
    }

    func start() {
        guard !isRunning else {
            logWarning("Engine already running")
            return
        }
        isRunning = true
        log("Engine started")
    }

    func stop() {
        guard isRunning else {
            logWarning("Engine already stopped")
            return
        }
        isRunning = false
        log("Engine stopped")
    }

    func getScene() -> SCNScene {
        return scene
    }

    func update(deltaTime: TimeInterval) {
        // Update engine state
    }
}