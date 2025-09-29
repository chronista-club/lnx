import Cocoa
import SceneKit

class OperationView: SCNView {
    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        allowsCameraControl = true
        backgroundColor = NSColor.black
        showsStatistics = true
        autoenablesDefaultLighting = true
    }

    func setScene(_ scene: SCNScene) {
        self.scene = scene
    }
}