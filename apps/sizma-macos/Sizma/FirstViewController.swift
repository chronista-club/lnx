import Cocoa
import SceneKit

class FirstViewController: NSViewController, Loggable {
    var space: Space?
    private var sceneView: SCNView!
    private var synth: FirstSynth!
    private var settingsWindowController: SettingsWindowController?
    @IBOutlet weak var playButton: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        // SCNView disabled to show XIB buttons
        // setupSceneView()
        setupSynth()
        log("FirstViewController loaded")
    }

    private func setupSceneView() {
        sceneView = SCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.width, .height]
        sceneView.scene = Engine.shared.getScene()
        sceneView.allowsCameraControl = true
        sceneView.showsStatistics = true
        sceneView.backgroundColor = NSColor.black

        view.addSubview(sceneView)
        log("Scene view setup completed")
    }

    private func setupSynth() {
        synth = FirstSynth()
        synth.start()
        log("Synth setup completed")
    }

    @IBAction func playButtonClicked(_ sender: Any) {
        let audioPath = Bundle.main.url(forResource: "20250802_160053", withExtension: "wav")
        if let url = audioPath {
            synth.togglePlayback(at: url)
            updatePlayButtonState()
        } else {
            logError("Audio file not found")
        }
    }

    private func updatePlayButtonState() {
        if let button = playButton {
            if synth.isPlaying {
                button.image = NSImage(named: "NSPauseTemplate")
            } else {
                button.image = NSImage(named: "NSPlayTemplate")
            }
        }
    }

    @IBAction func settingsButtonClicked(_ sender: Any) {
        log("Settings button clicked")

        // Create settings window if it doesn't exist
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }

        // Show the settings window
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // Note: deinit removed - AVAudioEngine automatically cleans up resources
}
