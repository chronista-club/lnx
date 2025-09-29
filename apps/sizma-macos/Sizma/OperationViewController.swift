import Cocoa
import SceneKit

class OperationViewController: NSViewController, Loggable {
    @IBOutlet weak var operationView: OperationView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOperationView()
        log("OperationViewController loaded")
    }

    private func setupOperationView() {
        if operationView != nil {
            operationView.setScene(Engine.shared.getScene())
            log("Operation view configured")
        } else {
            logError("Operation view outlet not connected")
        }
    }

    @IBAction func resetButtonClicked(_ sender: Any) {
        Engine.shared.stop()
        Engine.shared.start()
        log("Engine reset")
    }

    @IBAction func pauseButtonClicked(_ sender: Any) {
        operationView?.isPaused = !(operationView?.isPaused ?? false)
        log("View paused state toggled")
    }
}