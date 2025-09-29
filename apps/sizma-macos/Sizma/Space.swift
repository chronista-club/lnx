import Foundation
import SceneKit

class Space: Loggable {
    let id: UUID
    var name: String
    private var objects: [SCNNode] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        log("Space created: \(name)")
    }

    func addObject(_ node: SCNNode) {
        objects.append(node)
        log("Object added to space \(name)")
    }

    func removeObject(_ node: SCNNode) {
        if let index = objects.firstIndex(of: node) {
            objects.remove(at: index)
            log("Object removed from space \(name)")
        } else {
            logWarning("Object not found in space \(name)")
        }
    }

    func getAllObjects() -> [SCNNode] {
        return objects
    }

    func clear() {
        objects.removeAll()
        log("Space \(name) cleared")
    }
}