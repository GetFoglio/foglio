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
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { onDoubleClick?(); return }
        super.mouseDown(with: e)
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
    private let numberFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let textColorWell = NSColorWell(style: .minimal)
    private let fillColorWell = NSColorWell(style: .minimal)
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
        formulaField.onFocus = { [weak g] in if let g, let f = g.window?.firstResponder as? NSTextView, f.delegate === self.formulaField { g.beginBarEditing(self.formulaField) } }
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

    private func button(_ symbol: String, _ tip: String, _ action: Selector, toggle: Bool = false) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: L(tip)) ?? NSImage()
        let b = NSButton(image: img, target: self, action: action)
        b.bezelStyle = .accessoryBarAction
        b.showsBorderOnlyWhileMouseInside = !toggle
        if toggle { b.setButtonType(.pushOnPushOff) }
        b.toolTip = L(tip)
        b.imageScaling = .scaleProportionallyDown
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return b
    }

    private func group(_ views: [NSView], priority: NSStackView.VisibilityPriority = .mustHold) -> NSStackView {
        let s = NSStackView(views: views)
        s.spacing = 1
        s.setHuggingPriority(.required, for: .horizontal)
        return s
    }

    private func divider() -> NSView {
        let b = NSBox(); b.boxType = .separator
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }

    private func makeFormatBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        bar.detachesHiddenViews = true

        fontSizeBox.addItems(withObjectValues: [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72].map { "\($0)" })
        fontSizeBox.controlSize = .small
        fontSizeBox.font = .systemFont(ofSize: 11)
        fontSizeBox.numberOfVisibleItems = 14
        fontSizeBox.widthAnchor.constraint(equalToConstant: 54).isActive = true
        fontSizeBox.target = self
        fontSizeBox.action = #selector(fontSizeChanged(_:))
        fontSizeBox.toolTip = L("Font Size")

        boldButton = button("bold", "Bold (⌘B)", #selector(boldAction(_:)), toggle: true)
        italicButton = button("italic", "Italic (⌘I)", #selector(italicAction(_:)), toggle: true)
        underlineButton = button("underline", "Underline (⌘U)", #selector(underlineAction(_:)), toggle: true)
        let strike = button("strikethrough", "Strikethrough", #selector(strikeAction(_:)))

        textColorWell.color = .systemRed
        textColorWell.target = self
        textColorWell.action = #selector(textColorChanged(_:))
        textColorWell.toolTip = L("Font Color")
        fillColorWell.color = NSColor(srgbRed: 1, green: 0.95, blue: 0.6, alpha: 1)
        fillColorWell.target = self
        fillColorWell.action = #selector(fillColorChanged(_:))
        fillColorWell.toolTip = L("Fill Color")
        let textColorIcon = NSImageView(image: NSImage(systemSymbolName: "character", accessibilityDescription: nil)!)
        let fillIcon = NSImageView(image: NSImage(systemSymbolName: "paintbrush.fill", accessibilityDescription: nil)!)
        for i in [textColorIcon, fillIcon] { i.contentTintColor = .secondaryLabelColor }
        for w in [textColorWell, fillColorWell] { w.widthAnchor.constraint(equalToConstant: 38).isActive = true }

        let borders = NSPopUpButton(frame: .zero, pullsDown: true)
        borders.bezelStyle = .accessoryBarAction
        borders.isBordered = false
        let head = NSMenuItem(); head.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: L("Borders"))
        borders.menu?.addItem(head)
        Menus.borderItems().forEach { $0.target = self; borders.menu?.addItem($0) }
        borders.toolTip = L("Borders")
        borders.widthAnchor.constraint(equalToConstant: 44).isActive = true

        alignButtons = [button("text.alignleft", "Align Left", #selector(alignLeft(_:)), toggle: true),
                        button("text.aligncenter", "Center", #selector(alignCenter(_:)), toggle: true),
                        button("text.alignright", "Align Right", #selector(alignRight(_:)), toggle: true)]
        wrapButton = button("text.word.spacing", "Wrap Text", #selector(wrapAction(_:)), toggle: true)
        let merge = button("rectangle.split.3x1", "Merge & Center", #selector(GridView.mergeAndCenter(_:)))
        merge.target = nil

        numberFormatPopup.controlSize = .small
        numberFormatPopup.font = .systemFont(ofSize: 11)
        NumberFormats.all.forEach { numberFormatPopup.addItem(withTitle: $0.title) }
        numberFormatPopup.target = self
        numberFormatPopup.action = #selector(numberFormatPopupChanged(_:))
        numberFormatPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        numberFormatPopup.toolTip = L("Number Format")
        let percent = button("percent", "Percentage", #selector(percentAction(_:)))
        let thousands = button("number", "Number", #selector(thousandsAction(_:)))
        let incDec = button("increase.indent", "Increase Decimal", #selector(increaseDecimals(_:)))
        let decDec = button("decrease.indent", "Decrease Decimal", #selector(decreaseDecimals(_:)))

        let sum = NSPopUpButton(frame: .zero, pullsDown: true)
        sum.bezelStyle = .accessoryBarAction
        sum.isBordered = false
        let sumHead = NSMenuItem(); sumHead.image = NSImage(systemSymbolName: "sum", accessibilityDescription: L("AutoSum"))
        sum.menu?.addItem(sumHead)
        for (i, f) in ["SUM", "AVERAGE", "COUNT", "MAX", "MIN"].enumerated() {
            let it = NSMenuItem(title: Workbook.localName(f), action: #selector(autoSumMenu(_:)), keyEquivalent: "")
            it.tag = i; it.target = self
            sum.menu?.addItem(it)
        }
        sum.toolTip = L("AutoSum")
        sum.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let sortUp = button("arrow.up.arrow.down", "Sort A to Z", #selector(GridView.sortAscending(_:)))
        sortUp.target = nil
        let sortDown = button("arrow.down.arrow.up", "Sort Z to A", #selector(GridView.sortDescending(_:)))
        sortDown.target = nil
        let freeze = button("snowflake", "Freeze Panes", #selector(GridView.freezePanes(_:)))
        freeze.target = nil
        let filter = button("line.3.horizontal.decrease.circle", "Filter", #selector(GridView.toggleFilter(_:)))
        filter.target = nil

        let undo = button("arrow.uturn.backward", "Undo (⌘Z)", #selector(GridView.undo(_:)))
        undo.target = nil
        let redo = button("arrow.uturn.forward", "Redo (⇧⌘Z)", #selector(GridView.redo(_:)))
        redo.target = nil

        let groups: [(NSView, NSStackView.VisibilityPriority)] = [
            (group([undo, redo]), .mustHold),
            (divider(), .mustHold),
            (group([fontSizeBox, boldButton, italicButton, underlineButton, strike]), .mustHold),
            (divider(), .detachOnlyIfNecessary),
            (group([textColorIcon, textColorWell, fillIcon, fillColorWell, borders]), NSStackView.VisibilityPriority(800)),
            (divider(), NSStackView.VisibilityPriority(800)),
            (group(alignButtons + [wrapButton, merge]), NSStackView.VisibilityPriority(900)),
            (divider(), NSStackView.VisibilityPriority(900)),
            (group([numberFormatPopup, percent, thousands, incDec, decDec]), NSStackView.VisibilityPriority(700)),
            (divider(), NSStackView.VisibilityPriority(700)),
            (group([sum, sortUp, sortDown, filter, freeze]), NSStackView.VisibilityPriority(600)),
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
        cancelButton.bezelStyle = .accessoryBarAction
        cancelButton.target = self; cancelButton.action = #selector(cancelEdit)
        enterButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: L("Enter"))
        enterButton.bezelStyle = .accessoryBarAction
        enterButton.target = self; enterButton.action = #selector(confirmEdit)
        let fx = NSButton(title: "fx", target: self, action: #selector(insertFunction(_:)))
        fx.bezelStyle = .accessoryBarAction
        fx.font = NSFont(descriptor: NSFont.systemFont(ofSize: 13, weight: .medium).fontDescriptor.withSymbolicTraits(.italic), size: 13)
        fx.toolTip = L("Insert Function")
        formulaField.font = .systemFont(ofSize: 13)
        formulaField.cell?.isScrollable = true
        formulaField.cell?.wraps = false
        formulaField.placeholderString = ""
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
        add.bezelStyle = .accessoryBarAction
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
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.target = self; zoomLabel.action = #selector(zoomReset)
        zoomLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        for v in [tabsScroll, add, modeLabel, statusLabel, zoomSlider, zoomLabel] as [NSView] { bar.addArrangedSubview(v) }
        bar.setCustomSpacing(16, after: add)
        return bar
    }

    // MARK: - Sheet tabs

    func reloadTabs() {
        tabsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let names = grid.book.sheetNames
        for (i, name) in names.enumerated() where !grid.book.isSheetHidden(i) {
            let b = SheetTab(title: name, target: self, action: #selector(selectSheet(_:)))
            b.bezelStyle = .accessoryBarAction
            b.setButtonType(.pushOnPushOff)
            b.tag = i
            b.state = i == grid.sheet ? .on : .off
            b.font = .systemFont(ofSize: 12, weight: i == grid.sheet ? .semibold : .regular)
            b.onDoubleClick = { [weak self] in self?.renameSheet(nil) }
            b.contextMenu = { [weak self] in self?.tabMenu() ?? NSMenu() }
            tabsStack.addArrangedSubview(b)
        }
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
        return m
    }

    private func switchTo(sheet i: Int) {
        if grid.isEditing && !grid.isPointing { grid.commitEditing(move: nil) }
        grid.sheet = i
        doc?.activeSheet = i
        reloadTabs()
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
            self.switchTo(sheet: max(0, s - 1))
            self.changed()
        }
    }

    @objc func moveSheetLeft(_ sender: Any?) {
        guard grid.sheet > 0 else { return }
        grid.book.moveSheet(grid.sheet, to: grid.sheet - 1); switchTo(sheet: grid.sheet - 1); changed()
    }
    @objc func moveSheetRight(_ sender: Any?) {
        guard grid.sheet < grid.book.sheetNames.count - 1 else { return }
        grid.book.moveSheet(grid.sheet, to: grid.sheet + 1); switchTo(sheet: grid.sheet + 1); changed()
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

    func gridContentChanged(_ g: GridView) { changed() }

    func gridModeChanged(_ g: GridView) {
        cancelButton.isEnabled = g.isEditing
        enterButton.isEnabled = g.isEditing
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
    @objc private func textColorChanged(_ sender: NSColorWell) { grid.setStyle("font.color", hex(sender.color)) }
    @objc private func fillColorChanged(_ sender: NSColorWell) { grid.setStyle("fill.fg_color", hex(sender.color)) }

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
        grid.commitEditing(move: nil)
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
            let decimals = text.split(separator: ".").dropFirst().first?.count ?? 0
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
}
