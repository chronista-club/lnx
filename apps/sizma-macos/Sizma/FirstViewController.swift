import Cocoa
import SceneKit

/// Sizmaのメインビューコントローラー
class FirstViewController: NSViewController, Loggable {
    // MARK: - Properties
    var space: Space?
    private var sceneView: SCNView!
    private var synth: FirstSynth!
    private var settingsWindowController: SettingsWindowController?
    @IBOutlet weak var playButton: NSButton!

    // MARK: - Constants
    private enum AudioResource {
        static let fileName = "20250802_160053"
        static let fileExtension = "wav"
    }

    // MARK: - Lifecycle
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

    // MARK: - Setup
    private func setupSynth() {
        synth = FirstSynth()
        do {
            try synth.start()
            log("Synth setup completed")
        } catch {
            logError("Failed to start synth: \(error)")
            showAudioEngineError()
        }
    }

    // MARK: - Actions
    @IBAction func playButtonClicked(_ sender: Any) {
        guard let audioPath = Bundle.main.url(
            forResource: AudioResource.fileName,
            withExtension: AudioResource.fileExtension
        ) else {
            logError("Audio file not found: \(AudioResource.fileName).\(AudioResource.fileExtension)")
            showAudioFileNotFoundAlert()
            return
        }

        synth.togglePlayback(at: audioPath)
        updatePlayButtonState()
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

    // MARK: - Error Handling
    private func showAudioEngineError() {
        let alert = NSAlert()
        alert.messageText = "オーディオエンジンエラー"
        alert.informativeText = "オーディオエンジンの起動に失敗しました。システムのオーディオ設定を確認してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showAudioFileNotFoundAlert() {
        let alert = NSAlert()
        alert.messageText = "オーディオファイルが見つかりません"
        alert.informativeText = "再生するオーディオファイルが見つかりませんでした。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // Note: deinit removed - AVAudioEngine automatically cleans up resources
}
