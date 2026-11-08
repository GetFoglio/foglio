import AppKit
import UniformTypeIdentifiers

/// One workbook window: format bar, formula bar, grid, sheet tabs + status.
final class SheetWindowController: NSWindowController, NSWindowDelegate, GridViewDelegate, NSTextFieldDelegate {
    let book: Workbook
    let grid: GridView
    private let nameBox = NSTextField()
    private let formulaField = NSTextField()
    private let tabsStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var tabButtons: [NSButton] = []
    var onClose: ((SheetWindowController) -> Void)?

    init(book: Workbook) {
        self.book = book
        self.grid = GridView(book: book)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.minSize = NSSize(width: 520, height: 320)
        win.tabbingMode = .preferred
        super.init(window: win)
        win.delegate = self
        win.title = book.fileURL?.lastPathComponent ?? "Cartella1"
        if let url = book.fileURL { win.representedURL = url }
        buildUI(in: win)
        grid.delegate = self
        reloadTabs()
        gridSelectionChanged(grid)
        win.center()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    private func buildUI(in win: NSWindow) {
        let root = NSView()
        win.contentView = root

        let formatBar = makeFormatBar()
        let formulaBar = makeFormulaBar()
        let bottom = makeBottomBar()
        let sep1 = NSBox(); sep1.boxType = .separator
        let sep2 = NSBox(); sep2.boxType = .separator
        let sep3 = NSBox(); sep3.boxType = .separator

        let views: [NSView] = [formatBar, sep1, formulaBar, sep2, grid, sep3, bottom]
        for v in views { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        var c: [NSLayoutConstraint] = []
        var prev: NSLayoutYAxisAnchor = root.safeAreaLayoutGuide.topAnchor
        for v in views {
            c += [v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                  v.topAnchor.constraint(equalTo: prev)]
            prev = v.bottomAnchor
        }
        c += [formatBar.heightAnchor.constraint(equalToConstant: 36),
              formulaBar.heightAnchor.constraint(equalToConstant: 30),
              bottom.heightAnchor.constraint(equalToConstant: 28),
              bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor)]
        NSLayoutConstraint.activate(c)
    }

    private func symbolButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
        let b = NSButton(image: img, target: self, action: action)
        b.bezelStyle = .accessoryBarAction
        b.isBordered = true
        b.showsBorderOnlyWhileMouseInside = true
        b.toolTip = tip
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    private func makeFormatBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        let group = { (views: [NSView]) -> NSView in
            let s = NSStackView(views: views); s.spacing = 1; return s
        }
        let divider = { () -> NSView in
            let b = NSBox(); b.boxType = .separator
            b.heightAnchor.constraint(equalToConstant: 20).isActive = true
            return b
        }
        bar.addArrangedSubview(group([
            symbolButton("arrow.uturn.backward", "Annulla (⌘Z)", #selector(undoAction)),
            symbolButton("arrow.uturn.forward", "Ripeti (⇧⌘Z)", #selector(redoAction)),
        ]))
        bar.addArrangedSubview(divider())
        bar.addArrangedSubview(group([
            symbolButton("bold", "Grassetto (⌘B)", #selector(boldAction)),
            symbolButton("italic", "Corsivo (⌘I)", #selector(italicAction)),
            symbolButton("underline", "Sottolineato (⌘U)", #selector(underlineAction)),
        ]))
        bar.addArrangedSubview(divider())
        bar.addArrangedSubview(group([
            symbolButton("text.alignleft", "Allinea a sinistra", #selector(alignLeft)),
            symbolButton("text.aligncenter", "Centra", #selector(alignCenter)),
            symbolButton("text.alignright", "Allinea a destra", #selector(alignRight)),
        ]))
        bar.addArrangedSubview(divider())
        bar.addArrangedSubview(group([
            symbolButton("paintbrush.fill", "Colore riempimento (giallo)", #selector(fillYellow)),
            symbolButton("eraser", "Cancella formati", #selector(clearFill)),
        ]))
        bar.addArrangedSubview(divider())
        let fmt = NSPopUpButton(frame: .zero, pullsDown: false)
        fmt.addItems(withTitles: ["Generale", "Numero", "Valuta", "Percentuale", "Data", "Testo"])
        fmt.controlSize = .small
        fmt.target = self
        fmt.action = #selector(numberFormat(_:))
        bar.addArrangedSubview(fmt)
        bar.addArrangedSubview(divider())
        bar.addArrangedSubview(symbolButton("sum", "Somma automatica", #selector(autoSumAction)))
        bar.addArrangedSubview(NSView()) // spacer
        bar.setHuggingPriority(.defaultLow, for: .horizontal)
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
        nameBox.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let fx = NSTextField(labelWithString: "fx")
        fx.font = .systemFont(ofSize: 13, weight: .medium).withTraits(.italic)
        fx.textColor = .secondaryLabelColor
        formulaField.font = .systemFont(ofSize: 13)
        formulaField.delegate = self
        formulaField.placeholderString = ""
        formulaField.cell?.isScrollable = true
        formulaField.cell?.wraps = false
        bar.addArrangedSubview(nameBox)
        bar.addArrangedSubview(fx)
        bar.addArrangedSubview(formulaField)
        return bar
    }

    private func makeBottomBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 12)
        tabsStack.orientation = .horizontal
        tabsStack.spacing = 2
        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Nuovo foglio")!,
                           target: self, action: #selector(addSheet))
        add.bezelStyle = .accessoryBarAction
        add.toolTip = "Nuovo foglio"
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(tabsStack)
        bar.addArrangedSubview(add)
        bar.addArrangedSubview(statusLabel)
        return bar
    }

    // MARK: - Sheet tabs

    private func reloadTabs() {
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons = book.sheetNames.enumerated().map { i, name in
            let b = NSButton(title: name, target: self, action: #selector(selectSheet(_:)))
            b.bezelStyle = .accessoryBarAction
            b.setButtonType(.pushOnPushOff)
            b.tag = i
            b.state = i == grid.sheet ? .on : .off
            b.font = .systemFont(ofSize: 12, weight: i == grid.sheet ? .semibold : .regular)
            return b
        }
        tabButtons.forEach { tabsStack.addArrangedSubview($0) }
    }

    @objc private func selectSheet(_ sender: NSButton) {
        grid.commitEditing(move: nil)
        grid.sheet = sender.tag
        reloadTabs()
    }

    @objc private func addSheet() {
        book.addSheet()
        grid.sheet = book.sheetNames.count - 1
        reloadTabs()
    }

    // MARK: - GridViewDelegate

    func gridSelectionChanged(_ g: GridView) {
        nameBox.stringValue = g.selection.isSingle ? g.selection.a1 : "\(g.selection.r1 - g.selection.r0 + 1)R × \(g.selection.c1 - g.selection.c0 + 1)C"
        if !g.isEditing {
            formulaField.stringValue = book.input(sheet: g.sheet, row: g.anchor.row, col: g.anchor.col)
        }
        updateStatus()
    }

    func gridEditingTextChanged(_ g: GridView, text: String) {
        formulaField.stringValue = text
    }

    func gridContentChanged(_ g: GridView) {
        window?.isDocumentEdited = true
        updateStatus()
    }

    /// Excel's status bar: Media / Conteggio / Somma of the selection.
    private func updateStatus() {
        let s = grid.selection
        guard !s.isSingle else { statusLabel.stringValue = ""; return }
        let cells = book.viewport(sheet: grid.sheet, rows: s.r0...min(s.r1, s.r0 + 200_000), cols: s.c0...s.c1)
        var sum = 0.0, nums = 0, count = 0
        for c in cells where !c.text.isEmpty {
            count += 1
            if c.kind == 1, let v = Double(c.text.replacingOccurrences(of: ",", with: "")) { sum += v; nums += 1 }
        }
        guard count > 0 else { statusLabel.stringValue = ""; return }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 4
        var parts: [String] = []
        if nums > 0 { parts.append("Media: \(f.string(from: NSNumber(value: sum / Double(nums))) ?? "")") }
        parts.append("Conteggio: \(count)")
        if nums > 0 { parts.append("Somma: \(f.string(from: NSNumber(value: sum)) ?? "")") }
        statusLabel.stringValue = parts.joined(separator: "     ")
    }

    // MARK: - Formula bar & name box

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if control === formulaField {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                commitFormulaBar(); grid.select(CellRef(row: grid.anchor.row + 1, col: grid.anchor.col)); return true
            }
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                grid.cancelEditing(); gridSelectionChanged(grid); window?.makeFirstResponder(grid); return true
            }
        } else if control === nameBox, sel == #selector(NSResponder.insertNewline(_:)) {
            if let ref = parseA1(nameBox.stringValue) { grid.select(ref) }
            window?.makeFirstResponder(grid)
            return true
        }
        return false
    }

    func controlTextDidChange(_ n: Notification) {
        if (n.object as? NSTextField) === formulaField { grid.setEditorText(formulaField.stringValue) }
    }

    private func commitFormulaBar() {
        if grid.isEditing { grid.cancelEditing() }
        book.setInput(sheet: grid.sheet, row: grid.anchor.row, col: grid.anchor.col, formulaField.stringValue)
        grid.contentChanged()
        window?.makeFirstResponder(grid)
    }

    // MARK: - Format actions

    @objc func undoAction() { grid.undo(nil) }
    @objc func redoAction() { grid.redo(nil) }
    @objc func boldAction() { grid.toggleStyle("font.b") }
    @objc func italicAction() { grid.toggleStyle("font.i") }
    @objc func underlineAction() { grid.toggleStyle("font.u") }
    @objc private func alignLeft() { grid.setStyle("alignment.horizontal", "left") }
    @objc private func alignCenter() { grid.setStyle("alignment.horizontal", "center") }
    @objc private func alignRight() { grid.setStyle("alignment.horizontal", "right") }
    @objc private func fillYellow() { grid.setStyle("fill.fg_color", "#FFF2CC") }
    @objc private func clearFill() { grid.setStyle("fill.fg_color", "") }
    @objc private func autoSumAction() { window?.makeFirstResponder(grid); grid.autoSum() }
    @objc private func numberFormat(_ sender: NSPopUpButton) {
        let codes = ["general", "#,##0.00", "€ #,##0.00", "0.00%", "dd/mm/yyyy", "@"]
        grid.setStyle("num_fmt", codes[sender.indexOfSelectedItem])
        window?.makeFirstResponder(grid)
    }

    // MARK: - Saving

    @objc func saveDocument(_ sender: Any?) {
        if let url = book.fileURL { write(to: url) } else { saveDocumentAs(sender) }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let win = window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = (book.fileURL?.deletingPathExtension().lastPathComponent ?? "Cartella1") + ".xlsx"
        panel.beginSheetModal(for: win) { [weak self] r in
            if r == .OK, let url = panel.url { self?.write(to: url) }
        }
    }

    private func write(to url: URL) {
        grid.commitEditing(move: nil)
        do {
            try book.save(to: url)
            window?.title = url.lastPathComponent
            window?.representedURL = url
            window?.isDocumentEdited = false
        } catch {
            let a = NSAlert(error: error as NSError)
            a.messageText = "Impossibile salvare"
            a.informativeText = "\(error)"
            a.beginSheetModal(for: window!)
        }
    }

    func windowWillClose(_ notification: Notification) { onClose?(self) }
}

private extension NSFont {
    func withTraits(_ t: NSFontDescriptor.SymbolicTraits) -> NSFont {
        NSFont(descriptor: fontDescriptor.withSymbolicTraits(t), size: pointSize) ?? self
    }
}
