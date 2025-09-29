import Cocoa

class SettingsWindowController: NSWindowController, Loggable {

    override func windowDidLoad() {
        super.windowDidLoad()

        // Configure window
        window?.title = "Settings"
        window?.styleMask = [.titled, .closable, .miniaturizable]
        window?.center()

        log("Settings window loaded")
    }

    convenience init() {
        self.init(windowNibName: "Settings")
    }

    // MARK: - Actions

    @IBAction func closeButtonClicked(_ sender: Any) {
        close()
    }
}