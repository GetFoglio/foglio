import AppKit

/// Excel-style note / input-message box shown next to a cell.
final class NotePopup: NSPanel {
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 60), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        let box = NoteBox()
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 6), label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
        ])
        contentView = box
    }

    /// `topLeft` in screen coordinates.
    func show(_ text: String, at topLeft: NSPoint, parent: NSWindow) {
        label.stringValue = text
        label.preferredMaxLayoutWidth = 240
        let size = label.fittingSize
        setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height - 12, width: min(256, size.width + 16), height: size.height + 12), display: true)
        if self.parent != parent { parent.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    func hide() {
        guard isVisible || parent != nil else { return }
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}

/// The note's yellow box: colours are resolved for the current appearance on every update.
private final class NoteBox: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer.backgroundColor = (dark ? NSColor(srgbRed: 0.27, green: 0.26, blue: 0.2, alpha: 1)
                                          : NSColor(srgbRed: 1, green: 0.98, blue: 0.83, alpha: 1)).cgColor
            layer.borderColor = NSColor.separatorColor.cgColor
        }
        layer.cornerRadius = 4
        layer.borderWidth = 0.5
    }
}
