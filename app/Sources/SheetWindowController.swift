import AppKit
import UniformTypeIdentifiers

/// Formula bar field: tells the grid when it gains focus so it can become the cell editor.
final class FormulaBarField: NSTextField {
    var onFocus: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { DispatchQueue.main.async { self.onFocus?() } }
        return ok
    }
}

/// Sheet tab with a context menu and double-click rename.
final class SheetTab: NSButton {
    var onDoubleClick: (() -> Void)?
    var contextMenu: (() -> NSMenu)?
    var tabColor: NSColor?
    var onDragTo: ((CGFloat) -> Void)?     // x in the tab bar where the tab was dropped
    var isCurrent = false { didSet { needsDisplay = true } }
    private var hover = false { didSet { needsDisplay = true } }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { onDoubleClick?(); return }
        // Click selects; dragging sideways reorders the sheet (Excel).
        let start = e.locationInWindow
        var dragged = false
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            if abs(next.locationInWindow.x - start.x) > 8 { dragged = true; NSCursor.closedHand.set() }
        }
        NSCursor.arrow.set()
        if dragged, let up = window?.currentEvent, let bar = superview {
            onDragTo?(bar.convert(up.locationInWindow, from: nil).x)
        } else {
            sendAction(action, to: target)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
        return NSSize(width: max(56, ceil(w) + 26), height: 24)
    }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0, dy: 1)
        if isCurrent {
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
            (tabColor ?? NSColor.controlAccentColor).setFill()
            NSBezierPath(roundedRect: NSRect(x: r.minX + 6, y: isFlipped ? r.maxY - 3.5 : r.minY + 1, width: r.width - 12, height: 2.5), xRadius: 1, yRadius: 1).fill()
        } else {
            if hover { NSColor.quaternaryLabelColor.setFill(); NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill() }
            if let c = tabColor { c.setFill(); NSRect(x: r.minX + 6, y: isFlipped ? r.maxY - 3.5 : r.minY + 1, width: r.width - 12, height: 2.5).fill() }
        }
        let font = NSFont.systemFont(ofSize: 12, weight: isCurrent ? .semibold : .regular)
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor]
        let sz = (title as NSString).size(withAttributes: a)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2), withAttributes: a)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        performClick(nil)
        return contextMenu?()
    }
}

/// One workbook window: format bar, formula bar, grid, sheet tabs + status bar.
final class SheetWindowController: NSWindowController, NSWindowDelegate, GridViewDelegate, NSTextFieldDelegate {
    private(set) var grid: GridView!
    private let root = NSView()
    private let nameBox = NSTextField()
    private let formulaField = FormulaBarField()
    private let cancelButton = NSButton()
    private let enterButton = NSButton()
    private let tabsStack = NSStackView()
    private let tabsScroll = NSScrollView()
    private let modeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSButton()
    private let zoomSlider = NSSlider()
    private var boldButton: NSButton!, italicButton: NSButton!, underlineButton: NSButton!, wrapButton: NSButton!
    private var alignButtons: [NSButton] = []
    private let fontSizeBox = NSComboBox()
    private let fontFamilyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPreviewer = FontMenuPreviewer()
    private let numberFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let textColor = ColorButton(symbol: "textformat", tip: L("Font Color"), initial: NSColor(srgbRed: 0.75, green: 0, blue: 0, alpha: 1),
                                        allowsNone: true, noneTitle: L("Automatic"))
    private let fillColor = ColorButton(symbol: "drop.halffull", tip: L("Fill Color"), initial: NSColor(srgbRed: 1, green: 0.92, blue: 0.61, alpha: 1),
                                        allowsNone: true, noneTitle: L("No Fill"))
    private var gridConstraints: [NSLayoutConstraint] = []
    private var formulaBar: NSView!
    private var bottomBar: NSView!

    var doc: SpreadsheetDocument? { document as? SpreadsheetDocument }

    init(document: SpreadsheetDocument) {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.minSize = NSSize(width: 600, height: 360)
        win.tabbingMode = .automatic
        win.tabbingIdentifier = "FoglioWorkbook"
        super.init(window: win)
        win.delegate = self
        shouldCascadeWindows = true
        buildUI(in: win)
        installGrid(for: document.book)
        windowFrameAutosaveName = "FoglioSheetWindow"
        if win.frame.origin == .zero { win.center() }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// (Re)creates the grid for the document's current workbook (after open/revert).
    func reload() {
        guard let book = doc?.book, book !== grid?.book else { return }
        installGrid(for: book)
    }

    private func installGrid(for book: Workbook) {
        let old = grid
        let g = GridView(book: book)
        g.delegate = self
        g.translatesAutoresizingMaskIntoConstraints = false
        if let old { old.removeFromSuperview() }
        NSLayoutConstraint.deactivate(gridConstraints)
        root.addSubview(g)
        gridConstraints = [g.leadingAnchor.constraint(equalTo: root.leadingAnchor), g.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                           g.topAnchor.constraint(equalTo: formulaBar.bottomAnchor), g.bottomAnchor.constraint(equalTo: bottomBar.topAnchor)]
        NSLayoutConstraint.activate(gridConstraints)
        grid = g
        formulaField.delegate = g
        formulaField.onFocus = { [weak self, weak g] in
            guard let self, let g, let f = g.window?.firstResponder as? NSTextView, f.delegate === self.formulaField else { return }
            g.beginBarEditing(self.formulaField)
        }
        doc?.activeSheet = 0
        reloadTabs()
        gridSelectionChanged(g)
        gridModeChanged(g)
        window?.makeFirstResponder(g)
    }

    // MARK: - Layout

    private func buildUI(in win: NSWindow) {
        win.contentView = root
        let formatBar = makeFormatBar()
        formulaBar = makeFormulaBar()
        bottomBar = makeBottomBar()
        let sep1 = NSBox(); sep1.boxType = .separator
        let sep2 = NSBox(); sep2.boxType = .separator
        for v in [formatBar, sep1, formulaBar!, sep2, bottomBar!] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
            NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor)])
        }
        NSLayoutConstraint.activate([
            formatBar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            formatBar.heightAnchor.constraint(equalToConstant: 40),
            sep1.topAnchor.constraint(equalTo: formatBar.bottomAnchor),
            formulaBar.topAnchor.constraint(equalTo: sep1.bottomAnchor),
            formulaBar.heightAnchor.constraint(equalToConstant: 32),
            sep2.topAnchor.constraint(equalTo: formulaBar.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 28),
            bottomBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    private func button(_ symbol: String, _ tip: String, _ action: Selector, toggle: Bool = false, responderChain: Bool = false) -> NSButton {
        let b = ToolbarKit.button(image: ToolbarKit.symbol(symbol, L(tip)), tip: L(tip), target: responderChain ? nil : self,
                                  action: action, toggle: toggle)
        return b
    }

    private func textButton(_ text: String, _ tip: String, _ action: Selector) -> NSButton {
        ToolbarKit.button(image: ToolbarKit.textImage(text), tip: L(tip), target: self, action: action)
    }

    private func group(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.spacing = 2
        s.setHuggingPriority(.required, for: .horizontal)
        return s
    }

    private func divider() -> NSView {
        let b = NSBox(); b.boxType = .separator
        b.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return b
    }

    private func makeFormatBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        bar.detachesHiddenViews = true

        fontSizeBox.addItems(withObjectValues: [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72].map { "\($0)" })
        fontSizeBox.controlSize = .small
        fontSizeBox.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        fontSizeBox.numberOfVisibleItems = 14
        fontSizeBox.widthAnchor.constraint(equalToConstant: 50).isActive = true
        fontSizeBox.target = self
        fontSizeBox.action = #selector(fontSizeChanged(_:))
        fontSizeBox.toolTip = L("Font Size")

        fontFamilyPopup.controlSize = .small
        fontFamilyPopup.font = .systemFont(ofSize: 11)
        fontFamilyPopup.addItem(withTitle: L("Default"))
        fontFamilyPopup.menu?.addItem(.separator())
        for f in SheetWindowController.fontFamilies { fontFamilyPopup.addItem(withTitle: f) }
        fontFamilyPopup.menu?.delegate = fontPreviewer   // font previews are loaded only when the menu opens (fast launch)
        fontFamilyPopup.target = self
        fontFamilyPopup.action = #selector(fontFamilyChanged(_:))
        fontFamilyPopup.toolTip = L("Font")
        fontFamilyPopup.widthAnchor.constraint(equalToConstant: 118).isActive = true
        boldButton = button("bold", "Bold (⌘B)", #selector(boldAction(_:)), toggle: true)
        italicButton = button("italic", "Italic (⌘I)", #selector(italicAction(_:)), toggle: true)
        underlineButton = button("underline", "Underline (⌘U)", #selector(underlineAction(_:)), toggle: true)
        let strike = button("strikethrough", "Strikethrough", #selector(strikeAction(_:)))

        textColor.onPick = { [weak self] c in self?.grid.setStyle("font.color", c.map(self!.hex) ?? "") }
        fillColor.onPick = { [weak self] c in self?.grid.setStyle("fill.fg_color", c.map(self!.hex) ?? "") }

        let borders = MenuButton(image: ToolbarKit.symbol("square.grid.2x2", L("Borders")), tip: L("Borders")) { [weak self] in
            let m = NSMenu()
            Menus.borderItems().forEach { $0.target = self; m.addItem($0) }
            return m
        }

        alignButtons = [button("text.alignleft", "Align Left", #selector(alignLeft(_:)), toggle: true),
                        button("text.aligncenter", "Center", #selector(alignCenter(_:)), toggle: true),
                        button("text.alignright", "Align Right", #selector(alignRight(_:)), toggle: true)]
        wrapButton = button("text.append", "Wrap Text", #selector(wrapAction(_:)), toggle: true)
        let merge = button("rectangle.compress.vertical", "Merge & Center", #selector(GridView.mergeAndCenter(_:)), responderChain: true)

        numberFormatPopup.controlSize = .small
        numberFormatPopup.font = .systemFont(ofSize: 11)
        NumberFormats.all.forEach { numberFormatPopup.addItem(withTitle: $0.title) }
        numberFormatPopup.target = self
        numberFormatPopup.action = #selector(numberFormatPopupChanged(_:))
        numberFormatPopup.widthAnchor.constraint(equalToConstant: 112).isActive = true
        numberFormatPopup.toolTip = L("Number Format")
        let dec = FormulaLocale.current.locale.hasPrefix("en") ? "." : ","
        let currency = textButton(Locale.current.currencySymbol ?? "€", "Currency", #selector(currencyAction(_:)))
        let percent = textButton("%", "Percentage", #selector(percentAction(_:)))
        let thousands = textButton("000", "Comma Style", #selector(thousandsAction(_:)))
        let incDec = textButton("\(dec)0→", "Increase Decimal", #selector(increaseDecimals(_:)))
        let decDec = textButton("←\(dec)0", "Decrease Decimal", #selector(decreaseDecimals(_:)))

        let sum = MenuButton(image: ToolbarKit.symbol("sum", L("AutoSum")), tip: L("AutoSum")) { [weak self] in
            let m = NSMenu()
            for (i, f) in ["SUM", "AVERAGE", "COUNT", "MAX", "MIN"].enumerated() {
                let it = NSMenuItem(title: Workbook.localName(f), action: #selector(SheetWindowController.autoSumMenu(_:)), keyEquivalent: "")
                it.tag = i; it.target = self
                m.addItem(it)
            }
            return m
        }
        let sortUp = ToolbarKit.button(image: ToolbarKit.textImage("A↓Z", size: 10), tip: L("Sort A to Z"), target: nil,
                                       action: #selector(GridView.sortAscending(_:)))
        let sortDown = ToolbarKit.button(image: ToolbarKit.textImage("Z↓A", size: 10), tip: L("Sort Z to A"), target: nil,
                                         action: #selector(GridView.sortDescending(_:)))
        let filter = button("line.3.horizontal.decrease.circle", "Filter", #selector(GridView.toggleFilter(_:)), responderChain: true)
        let freeze = button("snowflake", "Freeze Panes", #selector(GridView.freezePanes(_:)), responderChain: true)

        let painter = button("paintbrush.pointed", "Format Painter", #selector(formatPainter(_:)))
        let undo = button("arrow.uturn.backward", "Undo (⌘Z)", #selector(GridView.undo(_:)), responderChain: true)
        let redo = button("arrow.uturn.forward", "Redo (⇧⌘Z)", #selector(GridView.redo(_:)), responderChain: true)

        let groups: [(NSView, NSStackView.VisibilityPriority)] = [
            (group([undo, redo, painter]), .mustHold),
            (divider(), .mustHold),
            (group([fontFamilyPopup, fontSizeBox, boldButton, italicButton, underlineButton, strike]), .mustHold),
            (divider(), NSStackView.VisibilityPriority(800)),
            (group([textColor, fillColor, borders]), NSStackView.VisibilityPriority(800)),
            (divider(), NSStackView.VisibilityPriority(900)),
            (group(alignButtons + [wrapButton, merge]), NSStackView.VisibilityPriority(900)),
            (divider(), NSStackView.VisibilityPriority(700)),
            (group([numberFormatPopup, currency, percent, thousands, incDec, decDec]), NSStackView.VisibilityPriority(700)),
            (divider(), NSStackView.VisibilityPriority(600)),
            (group([sum, sortUp, sortDown, filter, freeze, ChartsUI.toolbarButton(target: self)]), NSStackView.VisibilityPriority(600)),   // Foglio charts
        ]
        for (v, p) in groups {
            bar.addView(v, in: .leading)
            bar.setVisibilityPriority(p, for: v)
        }
        return bar
    }

    private func makeFormulaBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        nameBox.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        nameBox.alignment = .center
        nameBox.delegate = self
        nameBox.toolTip = L("Name Box: type a cell like B12 and press Return")
        nameBox.widthAnchor.constraint(equalToConstant: 96).isActive = true
        cancelButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Cancel"))
        cancelButton.title = ""; cancelButton.imagePosition = .imageOnly
        cancelButton.bezelStyle = .accessoryBarAction
        cancelButton.showsBorderOnlyWhileMouseInside = true
        cancelButton.contentTintColor = .systemRed
        cancelButton.toolTip = L("Cancel")
        cancelButton.target = self; cancelButton.action = #selector(cancelEdit)
        enterButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: L("Enter"))
        enterButton.title = ""; enterButton.imagePosition = .imageOnly
        enterButton.bezelStyle = .accessoryBarAction
        enterButton.showsBorderOnlyWhileMouseInside = true
        enterButton.contentTintColor = .systemGreen
        enterButton.toolTip = L("Enter")
        enterButton.target = self; enterButton.action = #selector(confirmEdit)
        for b in [cancelButton, enterButton] { b.widthAnchor.constraint(equalToConstant: 24).isActive = true }
        let fx = NSButton(title: "fx", target: self, action: #selector(insertFunction(_:)))
        fx.bezelStyle = .accessoryBarAction
        fx.showsBorderOnlyWhileMouseInside = true
        fx.font = NSFont(descriptor: NSFont.systemFont(ofSize: 13, weight: .medium).fontDescriptor.withSymbolicTraits(.italic), size: 13)
        fx.toolTip = L("Insert Function")
        formulaField.font = .systemFont(ofSize: 13)
        formulaField.cell?.isScrollable = true
        formulaField.cell?.wraps = false
        formulaField.placeholderString = ""
        formulaField.bezelStyle = .roundedBezel
        nameBox.bezelStyle = .roundedBezel
        formulaField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for v in [nameBox, cancelButton, enterButton, fx, formulaField] as [NSView] { bar.addArrangedSubview(v) }
        return bar
    }

    private func makeBottomBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 4
        bar.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 10)
        tabsStack.orientation = .horizontal
        tabsStack.spacing = 1
        tabsScroll.documentView = tabsStack
        tabsScroll.drawsBackground = false
        tabsScroll.hasHorizontalScroller = false
        tabsStack.translatesAutoresizingMaskIntoConstraints = false
        tabsScroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabsStack.leadingAnchor.constraint(equalTo: tabsScroll.contentView.leadingAnchor),
            tabsStack.topAnchor.constraint(equalTo: tabsScroll.contentView.topAnchor),
            tabsStack.bottomAnchor.constraint(equalTo: tabsScroll.contentView.bottomAnchor),
            tabsScroll.heightAnchor.constraint(equalToConstant: 24),
        ])
        let wTabs = tabsScroll.widthAnchor.constraint(equalTo: tabsStack.widthAnchor)
        wTabs.priority = .defaultHigh
        wTabs.isActive = true
        tabsScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: L("New Sheet"))!,
                           target: self, action: #selector(addSheet(_:)))
        add.title = ""
        add.imagePosition = .imageOnly
        add.bezelStyle = .accessoryBarAction
        add.showsBorderOnlyWhileMouseInside = true
        add.toolTip = L("New Sheet")
        modeLabel.font = .systemFont(ofSize: 11)
        modeLabel.textColor = .secondaryLabelColor
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingHead
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        zoomSlider.minValue = 25; zoomSlider.maxValue = 400; zoomSlider.doubleValue = 100
        zoomSlider.controlSize = .mini
        zoomSlider.target = self; zoomSlider.action = #selector(zoomSliderChanged(_:))
        zoomSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        zoomLabel.title = "100%"
        zoomLabel.bezelStyle = .accessoryBarAction
        zoomLabel.showsBorderOnlyWhileMouseInside = true
        zoomLabel.toolTip = L("Actual Size")
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.target = self; zoomLabel.action = #selector(zoomReset)
        zoomLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let zoomOut = ToolbarKit.button(image: ToolbarKit.symbol("minus", L("Zoom Out")), tip: L("Zoom Out"), target: self, action: #selector(zoomStepOut))
        let zoomIn = ToolbarKit.button(image: ToolbarKit.symbol("plus", L("Zoom In")), tip: L("Zoom In"), target: self, action: #selector(zoomStepIn))
        for b in [zoomOut, zoomIn] { b.widthAnchor.constraint(equalToConstant: 20).isActive = true }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        statusLabel.setContentHuggingPriority(.init(200), for: .horizontal)
        for v in [tabsScroll, add, modeLabel, spacer, statusLabel, zoomOut, zoomSlider, zoomIn, zoomLabel] as [NSView] { bar.addArrangedSubview(v) }
        bar.setCustomSpacing(14, after: add)
        bar.setCustomSpacing(14, after: statusLabel)
        bar.setCustomSpacing(0, after: zoomOut)
        bar.setCustomSpacing(0, after: zoomSlider)
        return bar
    }

    // MARK: - Sheet tabs

    func reloadTabs() {
        tabsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let names = grid.book.sheetNames
        for (i, name) in names.enumerated() where !grid.book.isSheetHidden(i) {
            let b = SheetTab(title: name, target: self, action: #selector(selectSheet(_:)))
            b.isBordered = false
            b.tag = i
            b.isCurrent = i == grid.sheet
            let tc = grid.book.sheetColor(i)
            b.tabColor = tc == VCell.noColor ? nil : SheetPainter.rgb(tc)
            b.setAccessibilityLabel(name)
            b.onDoubleClick = { [weak self] in self?.renameSheet(nil) }
            b.onDragTo = { [weak self] x in self?.dropTab(i, atX: x) }
            b.contextMenu = { [weak self] in self?.tabMenu() ?? NSMenu() }
            tabsStack.addArrangedSubview(b)
        }
    }

    /// Finishes an in-cell edit before a command that changes sheets; false if the edit could not be
    /// committed (a data validation alert is waiting for an answer).
    private func commitBeforeSheetCommand() -> Bool {
        if grid.hasPendingCommit { NSSound.beep(); return false }
        if grid.isEditing && !grid.commitEditing(move: nil) { return false }
        return true
    }

    private func dropTab(_ sheet: Int, atX x: CGFloat) {
        let tabs = tabsStack.arrangedSubviews.compactMap { $0 as? SheetTab }
        guard let target = tabs.first(where: { $0.frame.maxX > x })?.tag ?? tabs.last?.tag, target != sheet else { return }
        guard commitBeforeSheetCommand() else { return }
        grid.clearAllFilters()
        grid.book.moveSheet(sheet, to: target)
        switchTo(sheet: target)
        changed()
    }

    private func tabMenu() -> NSMenu {
        let m = NSMenu()
        [Menus.item("Insert Sheet", #selector(addSheet(_:))),
         Menus.item("Rename…", #selector(renameSheet(_:))),
         Menus.item("Duplicate", #selector(duplicateSheet(_:))),
         Menus.item("Delete", #selector(deleteSheet(_:))),
         .separator(),
         Menus.item("Move Left", #selector(moveSheetLeft(_:))),
         Menus.item("Move Right", #selector(moveSheetRight(_:))),
         .separator(),
         Menus.item("Hide", #selector(hideSheet(_:))),
         Menus.item("Unhide…", #selector(unhideSheet(_:)))].forEach { $0.target = self; m.addItem($0) }
        m.addItem(.separator())
        let tc = SheetWindowController.tabColorMenu()
        tc.submenu?.items.forEach { $0.target = self }
        m.addItem(tc)
        return m
    }

    private func switchTo(sheet i: Int) { switchToSheet(i) }

    /// Shows sheet i (commits a pending edit first, unless a formula is pointing at cells).
    @discardableResult
    func switchToSheet(_ i: Int) -> Bool {
        if grid.hasPendingCommit { NSSound.beep(); return false }
        if grid.isEditing && !grid.isPointing && !grid.commitEditing(move: nil) { return false }
        grid.sheet = i
        doc?.activeSheet = i
        reloadTabs()
        return true
    }

    @objc private func selectSheet(_ sender: NSButton) { switchTo(sheet: sender.tag) }

    @objc func addSheet(_ sender: Any?) {
        grid.book.addSheet()
        switchTo(sheet: grid.book.sheetNames.count - 1)
        changed()
    }

    @objc func renameSheet(_ sender: Any?) {
        let current = grid.book.sheetNames[safe: grid.sheet] ?? ""
        prompt(L("Rename Sheet"), value: current) { [weak self] name in
            guard let self, !name.isEmpty, name != current else { return }
            if !self.grid.book.renameSheet(self.grid.sheet, to: name) {
                self.alert(L("Invalid sheet name"), L("The name may already exist or contain characters like : \\ / ? * [ ]."))
            }
            self.reloadTabs(); self.changed()
        }
    }

    @objc func duplicateSheet(_ sender: Any?) {
        grid.book.duplicateSheet(grid.sheet)
        switchTo(sheet: grid.sheet + 1)
        changed()
    }

    @objc func deleteSheet(_ sender: Any?) {
        guard grid.book.sheetNames.count > 1, let w = window else { NSSound.beep(); return }
        let a = NSAlert()
        a.messageText = String(format: L("Delete sheet “%@”?"), grid.book.sheetNames[safe: grid.sheet] ?? "")
        a.informativeText = L("You can undo this with ⌘Z.")
        a.addButton(withTitle: L("Delete"))
        a.addButton(withTitle: L("Cancel"))
        a.buttons.first?.hasDestructiveAction = true
        a.beginSheetModal(for: w) { [weak self] r in
            guard let self, r == .alertFirstButtonReturn else { return }
            let s = self.grid.sheet
            self.grid.book.deleteSheet(s)
            self.grid.clearAllFilters()
            let t = max(0, s - 1)
            self.switchTo(sheet: t)
            if t == s { self.grid.resetForSheet() }
            self.changed()
        }
    }

    @objc func moveSheetLeft(_ sender: Any?) {
        guard grid.sheet > 0, commitBeforeSheetCommand() else { return }
        grid.clearAllFilters(); grid.book.moveSheet(grid.sheet, to: grid.sheet - 1); switchTo(sheet: grid.sheet - 1); changed()
    }
    @objc func moveSheetRight(_ sender: Any?) {
        guard grid.sheet < grid.book.sheetNames.count - 1, commitBeforeSheetCommand() else { return }
        grid.clearAllFilters(); grid.book.moveSheet(grid.sheet, to: grid.sheet + 1); switchTo(sheet: grid.sheet + 1); changed()
    }
    @objc func hideSheet(_ sender: Any?) {
        let visible = (0..<grid.book.sheetNames.count).filter { !grid.book.isSheetHidden($0) }
        guard visible.count > 1 else { NSSound.beep(); return }
        let s = grid.sheet
        grid.book.setSheetHidden(s, true)
        switchTo(sheet: visible.first { $0 != s } ?? 0)
        changed()
    }
    @objc func unhideSheet(_ sender: Any?) {
        let hidden = (0..<grid.book.sheetNames.count).filter { grid.book.isSheetHidden($0) }
        guard let w = window, !hidden.isEmpty else { NSSound.beep(); return }
        let a = NSAlert()
        a.messageText = L("Unhide Sheet")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        hidden.forEach { pop.addItem(withTitle: grid.book.sheetNames[$0]) }
        a.accessoryView = pop
        a.addButton(withTitle: L("OK")); a.addButton(withTitle: L("Cancel"))
        a.beginSheetModal(for: w) { [weak self] r in
            guard let self, r == .alertFirstButtonReturn else { return }
            let s = hidden[pop.indexOfSelectedItem]
            self.grid.book.setSheetHidden(s, false)
            self.switchTo(sheet: s)
            self.changed()
        }
    }

    // MARK: - GridViewDelegate

    func gridSelectionChanged(_ g: GridView) {
        let s = g.selection
        nameBox.stringValue = s.isSingle || s == g.book.merges(sheet: g.sheet).first(where: { $0.contains(g.active) })
            ? "\(columnName(g.active.col))\(g.active.row + 1)" : s.a1
        if !g.isEditing {
            formulaField.stringValue = g.book.input(sheet: g.sheet, row: g.active.row, col: g.active.col)
        }
        updateFormatState()
        updateStatus()
        if g.sheet != doc?.activeSheet { doc?.activeSheet = g.sheet; reloadTabs() }
    }

    func gridEditingTextChanged(_ g: GridView, text: String) {
        if formulaField.currentEditor() == nil { formulaField.stringValue = text }
    }

    func gridRequestsSheet(_ g: GridView, offset: Int) {
        let visible = (0..<g.book.sheetNames.count).filter { !g.book.isSheetHidden($0) }
        guard let i = visible.firstIndex(of: g.sheet) else { return }
        let next = visible[(i + offset + visible.count) % visible.count]
        if next != g.sheet { switchTo(sheet: next) }
    }

    func gridContentChanged(_ g: GridView) {
        // Undo/redo can add or remove sheets: keep tabs and the grid's sheet valid.
        let n = g.book.sheetNames.count
        if g.sheet >= n { switchTo(sheet: max(0, n - 1)) }
        reloadTabs()
        changed()
    }

    func gridZoomChanged(_ g: GridView) { syncZoom() }
    var zoomStatusForTesting: String { "\(zoomLabel.title) slider=\(Int(zoomSlider.doubleValue.rounded()))" }

    func gridModeChanged(_ g: GridView) {
        cancelButton.isEnabled = g.isEditing
        enterButton.isEnabled = g.isEditing
        cancelButton.alphaValue = g.isEditing ? 1 : 0.25
        enterButton.alphaValue = g.isEditing ? 1 : 0.25
        modeLabel.stringValue = g.isEditing ? (g.isPointing ? L("Point") : (g.editMode == .enter ? L("Enter") : L("Edit"))) : L("Ready")
        if !g.isEditing { formulaField.stringValue = g.book.input(sheet: g.sheet, row: g.active.row, col: g.active.col) }
    }

    private func changed() {
        doc?.updateChangeCount(.changeDone)
        updateStatus()
    }

    private func updateFormatState() {
        let st = grid.book.style(sheet: grid.sheet, row: grid.active.row, col: grid.active.col)
        boldButton.state = st.bold ? .on : .off
        italicButton.state = st.italic ? .on : .off
        underlineButton.state = st.underline ? .on : .off
        wrapButton.state = st.wrap ? .on : .off
        for (i, b) in alignButtons.enumerated() { b.state = Int(st.align) == i + 1 ? .on : .off }
        fontSizeBox.stringValue = "\(st.fontSize)"
        if let name = grid.book.fontName(sheet: grid.sheet, row: grid.active.row, col: grid.active.col),
           !["calibri", "aptos", "aptos narrow"].contains(name.lowercased()), fontFamilyPopup.item(withTitle: name) != nil {
            fontFamilyPopup.selectItem(withTitle: name)
        } else {
            fontFamilyPopup.selectItem(at: 0)
        }
        let codes = NumberFormats.all.map(\.code)
        if let i = codes.firstIndex(where: { $0.lowercased() == st.numFmt.lowercased() }) {
            numberFormatPopup.selectItem(at: i)
        } else {
            numberFormatPopup.selectItem(at: -1)
            numberFormatPopup.setTitle(st.numFmt.lowercased() == "general" ? L("General") : L("Custom"))
        }
    }

    /// Excel's status bar: Average / Count / Sum of the selection.
    private func updateStatus() {
        let s = grid.selection
        guard !s.isSingle else { statusLabel.stringValue = ""; return }
        let st = grid.book.stats(sheet: grid.sheet, s)
        guard st.count > 0 else { statusLabel.stringValue = ""; return }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        var parts: [String] = []
        if st.numeric > 0 { parts.append("\(L("Average")): \(f.string(from: NSNumber(value: st.sum / Double(st.numeric))) ?? "")") }
        parts.append("\(L("Count")): \(st.count)")
        if st.numeric > 1 {
            parts.append("\(L("Min")): \(f.string(from: NSNumber(value: st.min)) ?? "")")
            parts.append("\(L("Max")): \(f.string(from: NSNumber(value: st.max)) ?? "")")
        }
        if st.numeric > 0 { parts.append("\(L("Sum")): \(f.string(from: NSNumber(value: st.sum)) ?? "")") }
        statusLabel.stringValue = parts.joined(separator: "    ")
    }

    // MARK: - Name box / formula bar buttons

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard control === nameBox else { return false }
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let text = nameBox.stringValue.trimmingCharacters(in: .whitespaces)
            var sheetIndex = grid.sheet
            var refText = text
            if let bang = text.lastIndex(of: "!") {
                let name = String(text[..<bang]).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                if let i = grid.book.sheetNames.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { sheetIndex = i }
                refText = String(text[text.index(after: bang)...])
            }
            if let r = FormulaText.gridRange(refText.uppercased()) {
                if sheetIndex != grid.sheet { switchTo(sheet: sheetIndex) }
                grid.select(range: r)
            } else if goToName(text) {
                return true
            } else if grid.book.nameExists(text) {
                // An existing name that is not a plain range (a constant, a formula): never redefine it here.
                NSSound.beep()
                gridSelectionChanged(grid)
            } else if !text.isEmpty, text.range(of: "^[A-Za-z_\\p{L}][A-Za-z0-9_.\\p{L}]*$", options: .regularExpression) != nil {
                // Excel: typing a new name in the Name Box names the selection.
                do { try grid.book.defineName(text, scope: nil, formula: selectionReference()); gridSelectionChanged(grid) } catch { NSSound.beep() }
            } else {
                NSSound.beep()
            }
            window?.makeFirstResponder(grid)
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            gridSelectionChanged(grid)
            window?.makeFirstResponder(grid)
            return true
        }
        return false
    }

    @objc private func cancelEdit() { grid.cancelEditing() }
    @objc private func confirmEdit() { grid.commitEditing(move: nil) }

    @objc func goTo(_ sender: Any?) {
        window?.makeFirstResponder(nameBox)
        nameBox.currentEditor()?.selectAll(nil)
    }

    @objc func insertFunction(_ sender: Any?) {
        if !grid.isEditing { grid.beginEditing(.edit, initial: "=") }
        FunctionBrowser.shared.show(relativeTo: window) { [weak self] name in
            guard let self, let tv = self.window?.firstResponder as? NSTextView else { return }
            tv.insertText(name + "(", replacementRange: tv.selectedRange())
        }
    }

    // MARK: - Formatting actions

    @objc func formatPainter(_ sender: Any?) {
        guard grid.commitIfEditing() else { return }
        grid.book.copyStyles(sheet: grid.sheet, grid.selection)
        grid.formatPainterArmed = true
        window?.makeFirstResponder(grid)
    }
    @objc func boldAction(_ sender: Any?) { grid.toggleStyle("font.b") }
    @objc func italicAction(_ sender: Any?) { grid.toggleStyle("font.i") }
    @objc func underlineAction(_ sender: Any?) { grid.toggleStyle("font.u") }
    @objc func strikeAction(_ sender: Any?) { grid.toggleStyle("font.strike") }
    @objc func wrapAction(_ sender: Any?) { grid.toggleStyle("alignment.wrap_text") }
    @objc func alignLeft(_ sender: Any?) { toggleAlign("left", 1) }
    @objc func alignCenter(_ sender: Any?) { toggleAlign("center", 2) }
    @objc func alignRight(_ sender: Any?) { toggleAlign("right", 3) }
    @objc func valignTop(_ sender: Any?) { grid.setStyle("alignment.vertical", "top") }
    @objc func valignMiddle(_ sender: Any?) { grid.setStyle("alignment.vertical", "center") }
    @objc func valignBottom(_ sender: Any?) { grid.setStyle("alignment.vertical", "bottom") }

    private func toggleAlign(_ v: String, _ code: UInt8) {
        let st = grid.book.style(sheet: grid.sheet, row: grid.active.row, col: grid.active.col)
        grid.setStyle("alignment.horizontal", st.align == code ? "general" : v)
    }

    @objc private func fontSizeChanged(_ sender: NSComboBox) {
        guard let v = Int(sender.stringValue), v >= 1, v <= 409 else { updateFormatState(); return }
        grid.setStyle("font.size", "\(v)")
        window?.makeFirstResponder(grid)
    }

    private func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return String(format: "#%02X%02X%02X", Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255))
    }
    @objc private func currencyAction(_ sender: Any?) {
        if let f = NumberFormats.all.first(where: { $0.title == L("Currency") }) { grid.setStyle("num_fmt", f.code) }
    }

    @objc func applyNumberFormat(_ sender: NSMenuItem) {
        guard let f = NumberFormats.all[safe: sender.tag] else { return }
        grid.setStyle("num_fmt", f.code)
    }
    @objc private func numberFormatPopupChanged(_ sender: NSPopUpButton) {
        guard let f = NumberFormats.all[safe: sender.indexOfSelectedItem] else { return }
        grid.setStyle("num_fmt", f.code)
        window?.makeFirstResponder(grid)
    }
    @objc private func percentAction(_ sender: Any?) { grid.setStyle("num_fmt", "0%") }
    @objc private func thousandsAction(_ sender: Any?) { grid.setStyle("num_fmt", "#,##0.00") }
    @objc func formatCells(_ sender: Any?) {
        guard grid.commitIfEditing() else { return }
        let vc = FormatCellsController(book: grid.book, sheet: grid.sheet, cell: grid.active) { [weak self] code in
            self?.grid.setStyle("num_fmt", code)
        }
        let w = NSWindow(contentViewController: vc)
        w.title = L("Format Cells")
        window?.beginSheet(w)
    }
    @objc func increaseDecimals(_ sender: Any?) { adjustDecimals(1) }
    @objc func decreaseDecimals(_ sender: Any?) { adjustDecimals(-1) }
    private func adjustDecimals(_ d: Int) {
        var code = grid.book.style(sheet: grid.sheet, row: grid.active.row, col: grid.active.col).numFmt
        if code.lowercased() == "general" {
            // Start from the decimals currently shown, like Excel.
            let text = grid.book.formatted(sheet: grid.sheet, row: grid.active.row, col: grid.active.col)
            let sep: Character = FormulaLocale.current.locale.hasPrefix("en") ? "." : ","
            let decimals = text.split(separator: sep).dropFirst().first.map { $0.prefix { $0.isNumber }.count } ?? 0
            code = decimals > 0 ? "0." + String(repeating: "0", count: decimals) : "0"
        }
        grid.setStyle("num_fmt", NumberFormats.adjustDecimals(code, by: d))
    }

    @objc func applyBorder(_ sender: NSMenuItem) {
        guard let b = Borders.all[safe: sender.tag] else { return }
        grid.setBorder(b.kind, style: b.style)
    }

    @objc func autoSumMenu(_ sender: Any?) {
        let fns = ["SUM", "AVERAGE", "COUNT", "MAX", "MIN"]
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        window?.makeFirstResponder(grid)
        grid.autoSum(fns[safe: tag] ?? "SUM")
    }

    @objc func insertDate(_ sender: Any?) {
        let f = DateFormatter(); f.dateFormat = FormulaLocale.current.datePattern
        grid.book.setInput(sheet: grid.sheet, row: grid.active.row, col: grid.active.col, f.string(from: Date()))
        grid.contentChanged()
    }
    @objc func insertTime(_ sender: Any?) {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        grid.book.setInput(sheet: grid.sheet, row: grid.active.row, col: grid.active.col, f.string(from: Date()))
        grid.contentChanged()
    }

    // MARK: - Zoom

    @objc private func zoomSliderChanged(_ s: NSSlider) {
        grid.zoom = CGFloat((s.doubleValue / 5).rounded() * 5) / 100
        zoomLabel.title = "\(Int((grid.zoom * 100).rounded()))%"
    }
    @objc private func zoomReset() { grid.zoom = 1; syncZoom() }
    @objc private func zoomStepIn() { grid.zoomIn(nil); syncZoom() }
    @objc private func zoomStepOut() { grid.zoomOut(nil); syncZoom() }
    func syncZoom() {
        zoomSlider.doubleValue = Double(grid.zoom * 100)
        zoomLabel.title = "\(Int((grid.zoom * 100).rounded()))%"
    }

    // MARK: - Find

    @objc func showFind(_ sender: Any?) { FindPanel.shared.show(replace: false) }
    @objc func showReplace(_ sender: Any?) { FindPanel.shared.show(replace: true) }
    @objc func findNext(_ sender: Any?) { _ = grid.find(FindPanel.shared.query, flags: FindPanel.shared.flags) }
    @objc func findPrevious(_ sender: Any?) { _ = grid.find(FindPanel.shared.query, flags: FindPanel.shared.flags | 8) }

    // MARK: - Export

    @objc func exportCSV(_ sender: Any?) {
        guard let w = window else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.commaSeparatedText]
        let base = doc?.displayName.replacingOccurrences(of: ".xlsx", with: "") ?? "Foglio"
        p.nameFieldStringValue = "\(base) - \(grid.book.sheetNames[safe: grid.sheet] ?? "").csv"
        p.beginSheetModal(for: w) { [weak self] r in
            guard let self, r == .OK, let url = p.url else { return }
            do { try self.grid.book.saveCSV(sheet: self.grid.sheet, to: url, delimiter: FormulaLocale.current.csvDelimiter) } catch { self.alert(L("Export failed"), error.localizedDescription) }
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let w = window, let doc else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.pdf]
        p.nameFieldStringValue = (doc.displayName as NSString).deletingPathExtension + ".pdf"
        p.beginSheetModal(for: w) { r in
            guard r == .OK, let url = p.url else { return }
            do {
                let op = try doc.printOperation(withSettings: [:])
                op.printInfo.jobDisposition = .save
                op.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
                op.showsPrintPanel = false
                op.showsProgressPanel = false
                op.run()
            } catch {
                self.alert(L("Export failed"), error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func prompt(_ title: String, value: String, _ done: @escaping (String) -> Void) {
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = title
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        f.stringValue = value
        a.accessoryView = f
        a.addButton(withTitle: L("OK")); a.addButton(withTitle: L("Cancel"))
        a.window.initialFirstResponder = f
        a.beginSheetModal(for: w) { r in if r == .alertFirstButtonReturn { done(f.stringValue.trimmingCharacters(in: .whitespaces)) } }
    }

    private func alert(_ title: String, _ text: String) {
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.beginSheetModal(for: w)
    }

    func windowDidBecomeKey(_ notification: Notification) { syncZoom() }
    func windowWillClose(_ notification: Notification) { grid?.hidePopups() }

    // Test hooks (scripts/ui_tests.sh)
    func focusFormulaBarForTesting() { window?.makeFirstResponder(formulaField) }
    func nameBoxForTesting(_ text: String) {
        nameBox.stringValue = text
        window?.makeFirstResponder(nameBox)
        if let tv = nameBox.currentEditor() as? NSTextView { _ = control(nameBox, textView: tv, doCommandBy: #selector(NSResponder.insertNewline(_:))) }
    }
    func selectSheetForTesting(_ i: Int) { switchToSheet(i) }
}


/// Shows each font name in its own typeface, lazily.
final class FontMenuPreviewer: NSObject, NSMenuDelegate {
    private var done = false
    func menuWillOpen(_ menu: NSMenu) {
        guard !done else { return }
        done = true
        for item in menu.items.dropFirst() where !item.isSeparatorItem {
            if let font = NSFont(name: item.title, size: 12) { item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: font]) }
        }
    }
}
