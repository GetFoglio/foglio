import AppKit

private func currentController() -> SheetWindowController? {
    (NSApp.mainWindow?.windowController as? SheetWindowController)
        ?? (NSDocumentController.shared.currentDocument as? SpreadsheetDocument)?.windowController
}

/// Find & Replace utility panel acting on the frontmost workbook.
final class FindPanel: NSPanel, NSSearchFieldDelegate {
    static let shared = FindPanel()

    private let findField = NSSearchField()
    private let replaceField = NSTextField()
    private let replaceRow = NSStackView()
    private let matchCase = NSButton(checkboxWithTitle: L("Match case"), target: nil, action: nil)
    private let wholeCell = NSButton(checkboxWithTitle: L("Entire cell"), target: nil, action: nil)
    private let inFormulas = NSButton(checkboxWithTitle: L("Search formulas"), target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")

    var query: String { findField.stringValue }
    var flags: UInt32 {
        (matchCase.state == .on ? 1 : 0) | (wholeCell.state == .on ? 2 : 0) | (inFormulas.state == .on ? 4 : 0)
    }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 170), styleMask: [.titled, .closable, .utilityWindow],
                   backing: .buffered, defer: true)
        title = L("Find and Replace")
        isFloatingPanel = true
        hidesOnDeactivate = true
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        findField.placeholderString = L("Find")
        findField.delegate = self
        findField.target = self
        findField.action = #selector(findNextAction)
        replaceField.placeholderString = L("Replace with")
        for f in [findField, replaceField] as [NSTextField] { f.widthAnchor.constraint(equalToConstant: 300).isActive = true }

        let findRow = NSStackView(views: [label(L("Find:")), findField])
        replaceRow.setViews([label(L("Replace:")), replaceField], in: .leading)
        let options = NSStackView(views: [matchCase, wholeCell, inFormulas])
        options.spacing = 12
        let prev = NSButton(title: L("Previous"), target: self, action: #selector(findPrevAction))
        let next = NSButton(title: L("Next"), target: self, action: #selector(findNextAction))
        next.keyEquivalent = "\r"
        let replace = NSButton(title: L("Replace"), target: self, action: #selector(replaceAction))
        let replaceAll = NSButton(title: L("Replace All"), target: self, action: #selector(replaceAllAction))
        let buttons = NSStackView(views: [status, NSView(), replaceAll, replace, prev, next])
        buttons.setHuggingPriority(.defaultLow, for: .horizontal)
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        for v in [findRow, replaceRow, options, buttons] { root.addArrangedSubview(v) }
        buttons.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28).isActive = true
        contentView = root
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        l.widthAnchor.constraint(equalToConstant: 80).isActive = true
        return l
    }

    func show(replace: Bool) {
        replaceRow.isHidden = !replace
        if let w = NSApp.mainWindow, !isVisible {
            setFrameTopLeftPoint(NSPoint(x: w.frame.maxX - frame.width - 30, y: w.frame.maxY - 110))
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(findField)
        status.stringValue = ""
    }

    @objc private func findNextAction() { find(back: false) }
    @objc private func findPrevAction() { find(back: true) }

    private func find(back: Bool) {
        guard let c = currentController(), !query.isEmpty else { return }
        let ok = c.grid.find(query, flags: flags | (back ? 8 : 0))
        status.stringValue = ok ? "" : L("No matches")
    }

    @objc private func replaceAction() {
        guard let c = currentController(), !query.isEmpty else { return }
        let g = c.grid!
        let content = g.book.input(sheet: g.sheet, row: g.active.row, col: g.active.col)
        let opts: String.CompareOptions = matchCase.state == .on ? [] : [.caseInsensitive]
        if content.range(of: query, options: opts) != nil {
            let new = wholeCell.state == .on ? replaceField.stringValue
                : content.replacingOccurrences(of: query, with: replaceField.stringValue, options: opts)
            g.book.setInput(sheet: g.sheet, row: g.active.row, col: g.active.col, new)
            g.contentChanged()
        }
        find(back: false)
    }

    @objc private func replaceAllAction() {
        guard let c = currentController(), !query.isEmpty else { return }
        let n = c.grid.book.replaceAll(sheet: c.grid.sheet, query, with: replaceField.stringValue, flags: flags)
        c.grid.contentChanged()
        status.stringValue = String(format: L("%d replaced"), n)
    }
}

/// Searchable list of all functions with their signature and description.
final class FunctionBrowser: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let shared = FunctionBrowser()
    private let search = NSSearchField()
    private let table = NSTableView()
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var items: [String] = []
    private var onPick: ((String) -> Void)?

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440), styleMask: [.titled, .closable, .resizable, .utilityWindow],
                   backing: .buffered, defer: true)
        title = L("Insert Function")
        isFloatingPanel = true
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        search.placeholderString = L("Search functions")
        search.delegate = self
        let col = NSTableColumn(identifier: .init("n"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(insert)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        detail.font = .systemFont(ofSize: 12)
        let insertButton = NSButton(title: L("Insert"), target: self, action: #selector(insert))
        insertButton.keyEquivalent = "\r"
        for v in [search, scroll, detail, insertButton] as [NSView] { root.addArrangedSubview(v) }
        for v in [search, scroll, detail] as [NSView] { v.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24).isActive = true }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        contentView = root
        filter("")
    }

    private func filter(_ q: String) {
        let all = Workbook.functionNames
        items = q.isEmpty ? all : all.filter {
            $0.localizedCaseInsensitiveContains(q)
                || (FunctionDocs.doc(Workbook.englishName($0))?.summary.localizedCaseInsensitiveContains(q) ?? false)
                || (FunctionDocs.doc(Workbook.englishName($0))?.summaryIT.localizedCaseInsensitiveContains(q) ?? false)
        }
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateDetail()
    }

    func show(relativeTo w: NSWindow?, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        if let w, !isVisible { setFrameTopLeftPoint(NSPoint(x: w.frame.midX - frame.width / 2, y: w.frame.maxY - 120)) }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
    }

    func controlTextDidChange(_ n: Notification) { filter(search.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): moveSel(1); return true
        case #selector(NSResponder.moveUp(_:)): moveSel(-1); return true
        case #selector(NSResponder.insertNewline(_:)): insert(); return true
        default: return false
        }
    }

    private func moveSel(_ d: Int) {
        let r = min(max(0, table.selectedRow + d), items.count - 1)
        table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    @objc private func insert() {
        guard let name = items[safe: table.selectedRow] else { return }
        orderOut(nil)
        NSApp.mainWindow?.makeKey()
        onPick?(name)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let t = NSTextField(labelWithString: items[row])
        t.font = .systemFont(ofSize: 12, weight: .medium)
        return t
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateDetail() }

    private func updateDetail() {
        guard let name = items[safe: table.selectedRow] else { detail.stringValue = ""; return }
        let en = Workbook.englishName(name)
        guard let d = FunctionDocs.doc(en) else { detail.stringValue = name + "()"; return }
        let it = Locale.preferredLanguages.first?.hasPrefix("it") == true
        let sig = Workbook.localizedSignature(name)
        detail.stringValue = "\(sig)\n\n\(it ? d.summaryIT : d.summary)"
    }
}
