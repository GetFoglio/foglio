import AppKit

/// Small building blocks for the Excel-style format bar: flat buttons, menu buttons, colour buttons with a palette.
enum ToolbarKit {
    /// Template image with short text (".0", "A→Z", "000"), so it tints like SF Symbols.
    static func textImage(_ text: String, size: CGFloat = 11, weight: NSFont.Weight = .semibold, width: CGFloat? = nil) -> NSImage {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let s = (text as NSString).size(withAttributes: attrs)
        let w = width ?? ceil(s.width) + 2
        let img = NSImage(size: NSSize(width: w, height: 16), flipped: false) { r in
            (text as NSString).draw(at: NSPoint(x: (r.width - s.width) / 2, y: (r.height - s.height) / 2), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Symbol (or text image) with a small arrow, used for "decimal places" style icons.
    static func symbol(_ name: String, _ tip: String) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: tip) ?? textImage("?")
        return img.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? img
    }

    static func button(image: NSImage, tip: String, target: AnyObject?, action: Selector, toggle: Bool = false) -> NSButton {
        let b = NSButton(image: image, target: target, action: action)
        b.title = ""
        b.imagePosition = .imageOnly
        b.bezelStyle = .accessoryBarAction
        b.showsBorderOnlyWhileMouseInside = true
        if toggle { b.setButtonType(.pushOnPushOff) }
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.imageScaling = .scaleProportionallyDown
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }
}

/// Image button with a chevron that opens a menu below it (borders, AutoSum…).
final class MenuButton: NSButton {
    var menuProvider: (() -> NSMenu)?

    convenience init(image: NSImage, tip: String, menu: @escaping () -> NSMenu) {
        self.init(frame: .zero)
        self.image = MenuButton.withChevron(image)
        title = ""
        imagePosition = .imageOnly
        bezelStyle = .accessoryBarAction
        showsBorderOnlyWhileMouseInside = true
        toolTip = tip
        setAccessibilityLabel(tip)
        menuProvider = menu
        target = self
        action = #selector(open)
        widthAnchor.constraint(equalToConstant: 38).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    static func withChevron(_ base: NSImage) -> NSImage {
        let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 7, weight: .bold)) ?? NSImage()
        let size = NSSize(width: base.size.width + 10, height: max(base.size.height, 16))
        let img = NSImage(size: size, flipped: false) { r in
            base.draw(in: NSRect(x: 0, y: (r.height - base.size.height) / 2, width: base.size.width, height: base.size.height))
            chevron.draw(in: NSRect(x: base.size.width + 3, y: (r.height - chevron.size.height) / 2,
                                    width: chevron.size.width, height: chevron.size.height))
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc private func open() {
        guard let m = menuProvider?() else { return }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }
}

/// Excel's "Font Color" / "Fill Color" control: main part applies the last colour, the arrow opens a palette.
final class ColorButton: NSView {
    private(set) var color: NSColor?
    private let main = NSButton()
    private let arrow = NSButton()
    private let symbolName: String
    private let allowsNone: Bool
    private let noneTitle: String
    var onPick: ((NSColor?) -> Void)?
    private var popover: NSPopover?

    init(symbol: String, tip: String, initial: NSColor, allowsNone: Bool, noneTitle: String) {
        self.symbolName = symbol
        self.color = initial
        self.allowsNone = allowsNone
        self.noneTitle = noneTitle
        super.init(frame: .zero)
        for b in [main, arrow] {
            b.bezelStyle = .accessoryBarAction
            b.showsBorderOnlyWhileMouseInside = true
            b.title = ""
            b.imagePosition = .imageOnly
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
        }
        main.toolTip = tip
        main.setAccessibilityLabel(tip)
        main.target = self
        main.action = #selector(applyCurrent)
        arrow.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 7, weight: .bold))
        arrow.target = self
        arrow.action = #selector(openPalette)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: leadingAnchor), main.topAnchor.constraint(equalTo: topAnchor),
            main.bottomAnchor.constraint(equalTo: bottomAnchor), main.widthAnchor.constraint(equalToConstant: 28),
            arrow.leadingAnchor.constraint(equalTo: main.trailingAnchor, constant: -2), arrow.topAnchor.constraint(equalTo: topAnchor),
            arrow.bottomAnchor.constraint(equalTo: bottomAnchor), arrow.widthAnchor.constraint(equalToConstant: 14),
            arrow.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func refresh() {
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium)) ?? NSImage()
        let c = color
        // Not a template: the colour bar must keep its colour; the glyph follows the label colour.
        main.image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let glyph = base.copy() as! NSImage
            glyph.isTemplate = false
            glyph.lockFocus()
            NSColor.labelColor.set()
            NSRect(origin: .zero, size: glyph.size).fill(using: .sourceAtop)
            glyph.unlockFocus()
            glyph.draw(in: NSRect(x: (r.width - glyph.size.width) / 2, y: 5, width: glyph.size.width, height: glyph.size.height))
            let bar = NSRect(x: 2, y: 0, width: r.width - 4, height: 3.5)
            if let c { c.setFill(); NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill() }
            else { NSColor.tertiaryLabelColor.setStroke(); NSBezierPath(roundedRect: bar.insetBy(dx: 0.5, dy: 0.5), xRadius: 1, yRadius: 1).stroke() }
            return true
        }
    }

    @objc private func applyCurrent() { onPick?(color) }

    @objc private func openPalette() {
        let vc = ColorPaletteController(allowsNone: allowsNone, noneTitle: noneTitle) { [weak self] picked in
            guard let self else { return }
            self.popover?.performClose(nil)
            self.color = picked
            self.refresh()
            self.onPick?(picked)
        }
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        popover = p
    }
}

/// Excel-like palette: theme colours with tints, standard colours, "No Fill"/"Automatic", "More Colors…".
final class ColorPaletteController: NSViewController {
    private let allowsNone: Bool
    private let noneTitle: String
    private let pick: (NSColor?) -> Void

    static let theme: [UInt32] = [0xFFFFFF, 0x000000, 0xE7E6E6, 0x44546A, 0x4472C4, 0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47]
    static let standard: [UInt32] = [0xC00000, 0xFF0000, 0xFFC000, 0xFFFF00, 0x92D050, 0x00B050, 0x00B0F0, 0x0070C0, 0x002060, 0x7030A0]

    init(allowsNone: Bool, noneTitle: String, pick: @escaping (NSColor?) -> Void) {
        self.allowsNone = allowsNone
        self.noneTitle = noneTitle
        self.pick = pick
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func tint(_ v: UInt32, _ f: CGFloat) -> NSColor {
        let c = SheetPainter.rgb(v)
        return f >= 0 ? (c.blended(withFraction: f, of: .white) ?? c) : (c.blended(withFraction: -f, of: .black) ?? c)
    }

    override func loadView() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 6
        root.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        if allowsNone {
            let none = NSButton(title: noneTitle, target: self, action: #selector(pickNone))
            none.bezelStyle = .accessoryBarAction
            root.addArrangedSubview(none)
        }
        root.addArrangedSubview(label(L("Theme Colors")))
        let themeGrid = NSGridView()
        themeGrid.rowSpacing = 2
        themeGrid.columnSpacing = 3
        for f: CGFloat in [0, 0.8, 0.6, 0.4, -0.25, -0.5] {
            themeGrid.addRow(with: ColorPaletteController.theme.map { swatch(tint($0, f)) })
        }
        root.addArrangedSubview(themeGrid)
        root.addArrangedSubview(label(L("Standard Colors")))
        let std = NSStackView(views: ColorPaletteController.standard.map { swatch(SheetPainter.rgb($0)) })
        std.spacing = 3
        root.addArrangedSubview(std)
        let more = NSButton(title: L("More Colors…"), target: self, action: #selector(moreColors))
        more.bezelStyle = .accessoryBarAction
        root.addArrangedSubview(more)
        view = root
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func swatch(_ c: NSColor) -> NSView {
        let b = SwatchButton(color: c) { [weak self] in self?.pick(c) }
        return b
    }

    @objc private func pickNone() { pick(nil) }

    @objc private func moreColors() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPanelChanged(_ p: NSColorPanel) { pick(p.color) }
}

private final class SwatchButton: NSView {
    private let color: NSColor
    private let action: () -> Void
    private var hover = false { didSet { needsDisplay = true } }

    init(color: NSColor, action: @escaping () -> Void) {
        self.color = color
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.insetBy(dx: 1, dy: 1).fill()
        (hover ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: hover ? 1 : 1.5, dy: hover ? 1 : 1.5))
        p.lineWidth = hover ? 2 : 1
        p.stroke()
    }
    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func mouseUp(with event: NSEvent) { action() }
}
