import AppKit

/// Dialogs for comments, data validation, hyperlinks, tab colours, summaries and fonts.
extension SheetWindowController {
    private func sheetAlert(_ title: String, accessory: NSView?, ok: String = L("OK"), extra: String? = nil,
                            done: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = title
        a.accessoryView = accessory
        a.addButton(withTitle: ok)
        a.addButton(withTitle: L("Cancel"))
        if let extra { a.addButton(withTitle: extra) }
        a.beginSheetModal(for: w, completionHandler: done)
        if let first = accessory?.subviews.first(where: { $0 is NSTextField && ($0 as! NSTextField).isEditable }) ?? accessory as? NSTextField {
            a.window.makeFirstResponder(first)
        }
    }

    // MARK: Comments (Excel "Notes")

    @objc func editComment(_ sender: Any?) {
        guard grid.commitIfEditing() else { return }
        let c = grid.active
        let existing = grid.book.comment(sheet: grid.sheet, row: c.row, col: c.col)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 110))
        let tv = NSTextView(frame: scroll.bounds)
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 12)
        tv.string = existing?.text ?? ""
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let title = existing == nil ? L("New Comment") : L("Edit Comment")
        sheetAlert(title, accessory: scroll, extra: existing == nil ? nil : L("Delete")) { [weak self] r in
            guard let self else { return }
            if r == .alertFirstButtonReturn {
                let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { self.grid.book.deleteComment(sheet: self.grid.sheet, row: c.row, col: c.col) }
                else { self.grid.book.setComment(sheet: self.grid.sheet, row: c.row, col: c.col, text, author: NSFullUserName()) }
            } else if r == .alertThirdButtonReturn {
                self.grid.book.deleteComment(sheet: self.grid.sheet, row: c.row, col: c.col)
            } else { return }
            self.grid.contentChanged()
        }
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
    }

    @objc func deleteComment(_ sender: Any?) {
        let s = grid.selection
        for c in grid.book.commentCells(sheet: grid.sheet, rows: s.r0...min(s.r1, s.r0 + 100_000), cols: s.c0...min(s.c1, s.c0 + 2_000)) {
            grid.book.deleteComment(sheet: grid.sheet, row: c.row, col: c.col)
        }
        grid.contentChanged()
    }

    // MARK: Hyperlinks (⌘K)

    @objc func insertLink(_ sender: Any?) {
        guard grid.commitIfEditing() else { return }
        let c = grid.active
        let current = grid.book.link(sheet: grid.sheet, row: c.row, col: c.col)
        let text = NSTextField(string: grid.book.formatted(sheet: grid.sheet, row: c.row, col: c.col))
        let address = NSTextField(string: current?.address ?? "")
        address.placeholderString = "https://… · nome@esempio.it · #Foglio2!A1"
        for f in [text, address] { f.widthAnchor.constraint(equalToConstant: 300).isActive = true }
        let g = NSGridView(views: [[NSTextField(labelWithString: L("Text to display:")), text],
                                   [NSTextField(labelWithString: L("Address:")), address]])
        g.rowSpacing = 8
        g.frame = NSRect(x: 0, y: 0, width: 420, height: 56)
        sheetAlert(L("Insert Link"), accessory: g, extra: current == nil ? nil : L("Remove Link")) { [weak self] r in
            guard let self else { return }
            if r == .alertFirstButtonReturn {
                let a = Workbook.normalizedLinkAddress(address.stringValue)
                guard !a.isEmpty else { return }
                self.grid.book.setLink(sheet: self.grid.sheet, row: c.row, col: c.col, address: a, display: text.stringValue)
            } else if r == .alertThirdButtonReturn {
                self.grid.book.removeLink(sheet: self.grid.sheet, row: c.row, col: c.col)
            } else { return }
            self.grid.contentChanged()
        }
    }

    // MARK: Tab colour

    @objc func setTabColor(_ sender: NSMenuItem) {
        let rgb = UInt32(truncatingIfNeeded: sender.tag)
        grid.book.setSheetColor(grid.sheet, rgb)
        reloadTabs()
        grid.contentChanged()
    }

    static func tabColorMenu() -> NSMenuItem {
        var items: [NSMenuItem] = []
        let none = Menus.item("No Color", #selector(setTabColor(_:)))
        none.tag = Int(VCell.noColor)
        items.append(none)
        items.append(.separator())
        for v in ColorPaletteController.standard + [0x4472C4, 0x70AD47, 0xED7D31, 0xA5A5A5] {
            let it = NSMenuItem(title: "", action: #selector(setTabColor(_:)), keyEquivalent: "")
            it.tag = Int(v)
            it.image = NSImage(size: NSSize(width: 28, height: 12), flipped: false) { r in
                SheetPainter.rgb(v).setFill(); NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill(); return true
            }
            items.append(it)
        }
        return Menus.submenu("Tab Color", items)
    }

    // MARK: Data validation

    @objc func dataValidation(_ sender: Any?) {
        guard grid.commitIfEditing() else { return }
        guard let w = window else { return }
        let range = grid.selection
        let vc = DataValidationController(rule: grid.book.validation(sheet: grid.sheet, row: grid.active.row, col: grid.active.col)) { [weak self] rule in
            guard let self else { return }
            if let rule {
                do { try self.grid.book.setValidation(sheet: self.grid.sheet, range, rule: rule) }
                catch {
                    let e = NSAlert(); e.messageText = L("Invalid rule"); e.informativeText = error.localizedDescription
                    e.beginSheetModal(for: w)
                }
            } else {
                self.grid.book.clearValidation(sheet: self.grid.sheet, range)
            }
            self.grid.contentChanged()
        }
        let win = NSWindow(contentViewController: vc)
        win.title = L("Data Validation")
        w.beginSheet(win)
    }

    // MARK: Summarize by (pivot-lite)

    @objc func summarize(_ sender: Any?) {
        guard grid.commitIfEditing() else { return }
        let s = grid.selection
        var r = s.isSingle ? grid.book.currentRegion(sheet: grid.sheet, row: grid.active.row, col: grid.active.col) : s
        let l = grid.book.layout(sheet: grid.sheet)
        // Clip to the used range; a selection below or right of the data holds nothing to summarize.
        guard r.r0 <= l.maxRow, r.c0 <= l.maxCol else { NSSound.beep(); return }
        r = GridRange(r0: r.r0, c0: r.c0, r1: min(r.r1, l.maxRow), c1: min(r.c1, l.maxCol))
        guard r.rows >= 2, r.c0 <= r.c1 else { NSSound.beep(); return }
        let headers = grid.book.viewport(sheet: grid.sheet, rows: r.r0...r.r0, cols: r.c0...r.c1)
        func title(_ c: Int) -> String {
            let t = headers.first { $0.col == c }?.text ?? ""
            return t.isEmpty ? String(format: L("Column %@"), columnName(c)) : t
        }
        let group = NSPopUpButton(), value = NSPopUpButton(), agg = NSPopUpButton()
        for c in r.c0...r.c1 {
            group.addItem(withTitle: title(c)); group.lastItem?.tag = c
            value.addItem(withTitle: title(c)); value.lastItem?.tag = c
        }
        // Default: first text column groups, last numeric column is summed.
        let second = grid.book.viewport(sheet: grid.sheet, rows: (r.r0 + 1)...(r.r0 + 1), cols: r.c0...r.c1)
        if let t = second.first(where: { $0.kind == 0 && !$0.text.isEmpty }) { group.selectItem(withTag: t.col) }
        if let n = second.last(where: { $0.kind == 1 }) { value.selectItem(withTag: n.col) }
        agg.addItems(withTitles: [L("Sum"), L("Count"), L("Average"), L("Min"), L("Max")])
        let g = NSGridView(views: [[NSTextField(labelWithString: L("Group by:")), group],
                                   [NSTextField(labelWithString: L("Values:")), value],
                                   [NSTextField(labelWithString: L("Function:")), agg]])
        g.rowSpacing = 8
        g.frame = NSRect(x: 0, y: 0, width: 320, height: 90)
        sheetAlert(L("Summarize by"), accessory: g) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn, let gc = group.selectedItem?.tag, let vc = value.selectedItem?.tag else { return }
            do {
                let i = try self.grid.book.summarize(sheet: self.grid.sheet, r, groupCol: gc, valueCol: vc, aggregation: agg.indexOfSelectedItem, name: nil)
                self.selectSheetForTesting(i)
                self.grid.contentChanged()
            } catch {
                let e = NSAlert(); e.messageText = L("The summary could not be created."); e.informativeText = error.localizedDescription
                if let w = self.window { e.beginSheetModal(for: w) }
            }
        }
    }

    // MARK: Font family

    static let fontFamilies: [String] = {
        let common = ["Arial", "Avenir Next", "Calibri", "Courier New", "Georgia", "Gill Sans", "Helvetica", "Helvetica Neue",
                      "Menlo", "Palatino", "Times New Roman", "Trebuchet MS", "Verdana"]
        return common   // availability is checked lazily when rendering (falls back to the system font)
    }()

    @objc func fontFamilyChanged(_ sender: NSPopUpButton) {
        let name = sender.indexOfSelectedItem == 0 ? "Calibri" : (sender.titleOfSelectedItem ?? "Calibri")
        grid.setStyle("font.name", name)
        window?.makeFirstResponder(grid)
    }
}

/// Excel's Data ▸ Data Validation dialog (Settings, Input Message, Error Alert in one sheet).
final class DataValidationController: NSViewController {
    private let done: ([String: Any]?) -> Void
    private let rule: [String: Any]?
    private let allow = NSPopUpButton(), op = NSPopUpButton(), errStyle = NSPopUpButton()
    private let f1 = NSTextField(), f2 = NSTextField(), promptTitle = NSTextField(), prompt = NSTextField()
    private let errTitle = NSTextField(), errMsg = NSTextField()
    private let ignoreBlank = NSButton(checkboxWithTitle: L("Ignore blank"), target: nil, action: nil)
    private let dropdown = NSButton(checkboxWithTitle: L("In-cell dropdown"), target: nil, action: nil)
    private let f1Label = NSTextField(labelWithString: ""), f2Label = NSTextField(labelWithString: "")

    private let types = ["none", "whole", "decimal", "list", "date", "time", "textLength", "custom"]
    private let ops = ["between", "notBetween", "equal", "notEqual", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual"]

    init(rule: [String: Any]?, done: @escaping ([String: Any]?) -> Void) {
        self.rule = rule
        self.done = done
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        allow.addItems(withTitles: [L("Any value"), L("Whole number"), L("Decimal"), L("List"), L("Date"), L("Time"), L("Text length"), L("Custom")])
        op.addItems(withTitles: [L("between"), L("not between"), L("equal to"), L("not equal to"), L("greater than"), L("less than"),
                                 L("greater than or equal to"), L("less than or equal to")])
        errStyle.addItems(withTitles: [L("Stop"), L("Warning"), L("Information")])
        for p in [allow, op, errStyle] { p.target = self; p.action = #selector(update) }
        for f in [f1, f2, promptTitle, prompt, errTitle, errMsg] { f.widthAnchor.constraint(equalToConstant: 260).isActive = true }
        f1.placeholderString = ""
        let g = NSGridView(views: [
            [NSTextField(labelWithString: L("Allow:")), allow],
            [NSTextField(labelWithString: L("Data:")), op],
            [f1Label, f1], [f2Label, f2],
            [NSGridCell.emptyContentView, ignoreBlank], [NSGridCell.emptyContentView, dropdown],
            [section(L("Input Message")), NSGridCell.emptyContentView],
            [NSTextField(labelWithString: L("Title:")), promptTitle], [NSTextField(labelWithString: L("Message:")), prompt],
            [section(L("Error Alert")), NSGridCell.emptyContentView],
            [NSTextField(labelWithString: L("Style:")), errStyle],
            [NSTextField(labelWithString: L("Title:")), errTitle], [NSTextField(labelWithString: L("Message:")), errMsg],
        ])
        g.rowSpacing = 8
        g.column(at: 0).xPlacement = .trailing
        let clear = NSButton(title: L("Clear All"), target: self, action: #selector(clearAll))
        let ok = NSButton(title: L("OK"), target: self, action: #selector(okPressed)); ok.keyEquivalent = "\r"
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(close)); cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [clear, NSView(), cancel, ok])
        let root = NSStackView(views: [g, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 16, right: 24)
        buttons.widthAnchor.constraint(equalTo: g.widthAnchor).isActive = true
        view = root
        load()
        update()
    }

    private func section(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        return l
    }

    private func load() {
        guard let r = rule else { ignoreBlank.state = .on; dropdown.state = .on; return }
        allow.selectItem(at: types.firstIndex(of: r["type"] as? String ?? "none") ?? 0)
        op.selectItem(at: ops.firstIndex(of: r["operator"] as? String ?? "between") ?? 0)
        f1.stringValue = r["formula1"] as? String ?? ""
        f2.stringValue = r["formula2"] as? String ?? ""
        ignoreBlank.state = (r["allowBlank"] as? Bool ?? true) ? .on : .off
        dropdown.state = (r["inCellDropdown"] as? Bool ?? true) ? .on : .off
        promptTitle.stringValue = r["promptTitle"] as? String ?? ""
        prompt.stringValue = r["prompt"] as? String ?? ""
        errStyle.selectItem(at: ["stop", "warning", "information"].firstIndex(of: r["errorStyle"] as? String ?? "stop") ?? 0)
        errTitle.stringValue = r["errorTitle"] as? String ?? ""
        errMsg.stringValue = r["error"] as? String ?? ""
    }

    @objc private func update() {
        let t = types[allow.indexOfSelectedItem]
        let ranged = ["whole", "decimal", "date", "time", "textLength"].contains(t)
        op.isEnabled = ranged
        let between = ranged && op.indexOfSelectedItem < 2
        f1.isEnabled = t != "none"
        f2.isEnabled = between
        f2.isHidden = !between
        f2Label.isHidden = !between
        dropdown.isEnabled = t == "list"
        switch t {
        case "list": f1Label.stringValue = L("Source:"); f1.placeholderString = L("e.g. Yes;No;Maybe  or  =$A$1:$A$10")
        case "custom": f1Label.stringValue = L("Formula:"); f1.placeholderString = "="
        default: f1Label.stringValue = between ? L("Minimum:") : L("Value:"); f1.placeholderString = ""
        }
        f2Label.stringValue = L("Maximum:")
    }

    @objc private func okPressed() {
        let t = types[allow.indexOfSelectedItem]
        if t == "none" { done(nil); close(); return }
        var r: [String: Any] = ["type": t, "formula1": f1.stringValue, "allowBlank": ignoreBlank.state == .on,
                                "inCellDropdown": dropdown.state == .on, "showErrorMessage": true,
                                "errorStyle": ["stop", "warning", "information"][errStyle.indexOfSelectedItem]]
        if ["whole", "decimal", "date", "time", "textLength"].contains(t) {
            r["operator"] = ops[op.indexOfSelectedItem]
            if op.indexOfSelectedItem < 2 { r["formula2"] = f2.stringValue }
        }
        if !promptTitle.stringValue.isEmpty || !prompt.stringValue.isEmpty {
            r["showInputMessage"] = true; r["promptTitle"] = promptTitle.stringValue; r["prompt"] = prompt.stringValue
        }
        if !errTitle.stringValue.isEmpty { r["errorTitle"] = errTitle.stringValue }
        if !errMsg.stringValue.isEmpty { r["error"] = errMsg.stringValue }
        done(r)
        close()
    }
    @objc private func clearAll() { done(nil); close() }
    @objc private func close() {
        guard let w = view.window else { return }
        w.sheetParent?.endSheet(w)
    }
}
