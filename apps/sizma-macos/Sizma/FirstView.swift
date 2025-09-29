import Cocoa

class FirstView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.darkGray.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Use light gray background instead of black
        NSColor.lightGray.setFill()
        dirtyRect.fill()

        // Draw title at the top
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]

        let title = "Sizma Audio"
        let titleSize = title.size(withAttributes: attributes)
        let titleRect = NSRect(
            x: (bounds.width - titleSize.width) / 2,
            y: bounds.height - titleSize.height - 30,  // Position near the top
            width: titleSize.width,
            height: titleSize.height
        )

        title.draw(in: titleRect, withAttributes: attributes)
    }
}