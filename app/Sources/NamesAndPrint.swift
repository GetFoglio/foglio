import AppKit

// MARK: - Defined names (Insert ▸ Name)

extension SheetWindowController {
    /// "'Sheet 1'!$A$1:$B$5" for the current selection.
    func selectionReference() -> String {
        let name = grid.book.sheetNames[safe: grid.sheet] ?? "Sheet1"
        let quoted = name.range(of: "^[A-Za-z_][A-Za-z0-9_.]*$", options: .regularExpression) != nil ? name : "'\(name.replacingOccurrences(of: "'", with: "''"))'"
        let s = grid.selection
        let a = "$\(columnName(s.c0))$\(s.r0 + 1)"
        return s.isSingle ? "\(quoted)!\(a)" : "\(quoted)!\(a):$\(columnName(s.c1))$\(s.r1 + 1)"
    }

    @objc func defineName(_ sender: Any?) {
        guard grid.commitIfEditing() else { return }
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = L("Define Name")
        let nameField = NSTextField(string: "")
        nameField.placeholderString = L("Name")
        let refField = NSTextField(string: "=" + selectionReference())
        for f in [nameField, refField] { f.widthAnchor.constraint(equalToConstant: 260).isActive = true }
        let grid = NSGridView(views: [[NSTextField(labelWithString: L("Name:")), nameField],
                                      [NSTextField(labelWithString: L("Refers to:")), refField]])
        grid.rowSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 340, height: 56)
        a.accessoryView = grid
        a.addButton(withTitle: L("OK")); a.addButton(withTitle: L("Cancel"))
        a.window.initialFirstResponder = nameField
        a.beginSheetModal(for: w) { [weak self] r in
            guard let self, r == .alertFirstButtonReturn else { return }
            do {
                try self.grid.book.defineName(nameField.stringValue.trimmingCharacters(in: .whitespaces), scope: nil, formula: refField.stringValue)
                self.grid.contentChanged()
            } catch {
                let e = NSAlert(); e.messageText = L("Invalid name"); e.informativeText = error.localizedDescription
                e.beginSheetModal(for: w)
            }
        }
    }

    @objc func nameManager(_ sender: Any?) {
        guard let w = window else { return }
        let vc = NameManagerController(book: grid.book) { [weak self] target in
            self?.goToName(target)
        }
        let win = NSWindow(contentViewController: vc)
        win.title = L("Name Manager")
        w.beginSheet(win)
    }

    /// Jumps to a defined name's range; returns false if the name is unknown or not a plain range.
    @discardableResult
    func goToName(_ name: String) -> Bool {
        guard let (sheetIndex, r) = grid.book.resolveName(name, currentSheet: grid.sheet) else { return false }
        if sheetIndex != grid.sheet { switchToSheet(sheetIndex) }
        grid.select(range: r)
        window?.makeFirstResponder(grid)
        return true
    }
}

final class NameManagerController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let book: Workbook
    private let onGo: (String) -> Void
    private var names: [Workbook.DefinedName] = []
    private let table = NSTableView()

    init(book: Workbook, onGo: @escaping (String) -> Void) {
        self.book = book
        self.onGo = onGo
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        for (id, title, w) in [("n", L("Name"), 140.0), ("f", L("Refers to"), 260.0), ("s", L("Scope"), 90.0)] {
            let c = NSTableColumn(identifier: .init(id)); c.title = title; c.width = w
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.doubleAction = #selector(go)
        table.target = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let del = NSButton(title: L("Delete"), target: self, action: #selector(deleteName))
        let goB = NSButton(title: L("Go To"), target: self, action: #selector(go))
        let close = NSButton(title: L("Close"), target: self, action: #selector(closeSheet))
        close.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [del, NSView(), goB, close])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        root.addSubview(scroll); root.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12), buttons.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: scroll.trailingAnchor), buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            root.widthAnchor.constraint(equalToConstant: 520), root.heightAnchor.constraint(equalToConstant: 320),
        ])
        view = root
        reload()
    }

    private func reload() { names = book.definedNames; table.reloadData() }

    func numberOfRows(in tableView: NSTableView) -> Int { names.count }
    func tableView(_ tableView: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let n = names[safe: row] else { return nil }
        let text: String
        switch col?.identifier.rawValue {
        case "n": text = n.name
        case "f": text = "=" + n.formula
        default: text = n.scope.map { book.sheetNames[safe: $0] ?? "?" } ?? L("Workbook")
        }
        let t = NSTextField(labelWithString: text)
        t.lineBreakMode = .byTruncatingTail
        return t
    }

    @objc private func deleteName() {
        guard let n = names[safe: table.selectedRow] else { NSSound.beep(); return }
        book.deleteName(n.name, scope: n.scope)
        reload()
    }
    @objc private func go() {
        guard let n = names[safe: table.selectedRow] else { return }
        closeSheet()
        onGo(n.name)
    }
    @objc private func closeSheet() {
        guard let w = view.window else { return }
        w.sheetParent?.endSheet(w)
    }
}

// MARK: - Print options (shown inside the Print panel)

final class PrintOptionsController: NSViewController, NSPrintPanelAccessorizing {
    weak var printView: PrintView?
    @objc dynamic var fitToWidth = true { didSet { printView?.fitToWidth = fitToWidth } }
    @objc dynamic var gridlines = false { didSet { printView?.printGridlines = gridlines } }

    override func loadView() {
        let fit = NSButton(checkboxWithTitle: L("Fit all columns on one page"), target: nil, action: nil)
        fit.bind(.value, to: self, withKeyPath: "fitToWidth")
        let grid = NSButton(checkboxWithTitle: L("Print gridlines"), target: nil, action: nil)
        grid.bind(.value, to: self, withKeyPath: "gridlines")
        let s = NSStackView(views: [fit, grid])
        s.orientation = .vertical
        s.alignment = .leading
        s.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        view = s
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        [[.itemName: L("Fit all columns on one page"), .itemDescription: fitToWidth ? L("On") : L("Off")],
         [.itemName: L("Print gridlines"), .itemDescription: gridlines ? L("On") : L("Off")]]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> { ["fitToWidth", "gridlines"] }
}
