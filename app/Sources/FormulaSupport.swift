import AppKit

/// Lightweight lexical helpers over formula text (UTF-16 offsets, matching NSRange).
enum FormulaText {
    static let palette: [NSColor] = [.systemBlue, .systemRed, .systemPurple, .systemGreen, .systemOrange, .systemTeal, .systemPink, .systemBrown]

    private static let refRegex: NSRegularExpression = {
        let cell = "\\$?[A-Za-z]{1,3}\\$?[0-9]{1,7}"
        let pattern = "(?<![A-Za-z0-9_.$])((?:'[^']+'|[A-Za-z_][A-Za-z0-9_.]*)!)?(\(cell)(?::\(cell))?|\\$?[A-Za-z]{1,3}:\\$?[A-Za-z]{1,3}|\\$?[0-9]{1,7}:\\$?[0-9]{1,7})(?![A-Za-z0-9_(!])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Ranges inside "string literals".
    static func stringRanges(_ s: NSString) -> [NSRange] {
        var out: [NSRange] = []
        var start = -1
        var i = 0
        while i < s.length {
            if s.character(at: i) == 34 { // "
                if start < 0 { start = i } else if i + 1 < s.length && s.character(at: i + 1) == 34 { i += 1 } else {
                    out.append(NSRange(location: start, length: i - start + 1)); start = -1
                }
            }
            i += 1
        }
        if start >= 0 { out.append(NSRange(location: start, length: s.length - start)) }
        return out
    }

    struct Ref {
        let textRange: NSRange
        let sheet: String?
        let range: GridRange
    }

    static func references(in text: String) -> [Ref] {
        let s = text as NSString
        guard s.length > 1, s.character(at: 0) == 61 else { return [] } // '='
        let strings = stringRanges(s)
        var out: [Ref] = []
        for m in refRegex.matches(in: text, range: NSRange(location: 0, length: s.length)) {
            if strings.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
            var sheet: String?
            if m.range(at: 1).location != NSNotFound {
                sheet = s.substring(with: m.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: "!'"))
            }
            let body = s.substring(with: m.range(at: 2)).replacingOccurrences(of: "$", with: "").uppercased()
            guard let g = gridRange(body) else { continue }
            out.append(Ref(textRange: m.range, sheet: sheet, range: g))
        }
        return out
    }

    static func gridRange(_ body: String) -> GridRange? {
        if let r = parseA1Range(body) { return r }
        let parts = body.split(separator: ":").map(String.init)
        guard parts.count == 2 else { return nil }
        if let a = Int(parts[0]), let b = Int(parts[1]), a > 0, b > 0 {
            return GridRange(r0: a - 1, c0: 0, r1: b - 1, c1: Sheet.maxCols - 1)
        }
        if let a = parseA1(parts[0] + "1"), let b = parseA1(parts[1] + "1") {
            return GridRange(r0: 0, c0: a.col, r1: Sheet.maxRows - 1, c1: b.col)
        }
        return nil
    }

    private static func isIdent(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 46 || c == 95
    }
    private static func isLetter(_ c: unichar) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }

    private static func inString(_ s: NSString, _ caret: Int) -> Bool {
        stringRanges(s).contains { caret > $0.location && caret < $0.location + $0.length || (caret == $0.location + $0.length && s.character(at: $0.location + $0.length - 1) != 34) }
    }

    /// The function whose argument list contains the caret, and the 0-based argument index.
    static func enclosingFunction(_ text: String, caret: Int) -> (name: String, arg: Int)? {
        let s = text as NSString
        guard s.length > 0, s.character(at: 0) == 61 else { return nil }
        var stack: [(String, Int)] = []
        var quoted = false
        var i = 1
        while i < min(caret, s.length) {
            let c = s.character(at: i)
            if c == 34 { quoted.toggle() } else if !quoted {
                switch c {
                case 40: // (
                    var j = i - 1
                    while j >= 0 && isIdent(s.character(at: j)) { j -= 1 }
                    stack.append((s.substring(with: NSRange(location: j + 1, length: i - j - 1)).uppercased(), 0))
                case 44, 59: // , ;
                    if !stack.isEmpty { stack[stack.count - 1].1 += 1 }
                case 41: // )
                    if !stack.isEmpty { stack.removeLast() }
                default: break
                }
            }
            i += 1
        }
        guard let top = stack.last, !top.0.isEmpty else { return nil }
        return (top.0, top.1)
    }

    /// A function-name prefix being typed right before the caret.
    static func nameToken(_ text: String, caret: Int) -> (NSRange, String)? {
        let s = text as NSString
        guard s.length > 1, s.character(at: 0) == 61, caret <= s.length, caret > 1 else { return nil }
        if caret < s.length && isIdent(s.character(at: caret)) { return nil }
        if inString(s, caret) { return nil }
        var j = caret - 1
        while j >= 1 && isIdent(s.character(at: j)) { j -= 1 }
        let start = j + 1
        guard start < caret, isLetter(s.character(at: start)) else { return nil }
        let prev = s.character(at: j)
        guard "=+-*/^&(,;<> :".utf16.contains(prev) else { return nil }
        let token = s.substring(with: NSRange(location: start, length: caret - start))
        // Looks like a cell reference: no function list.
        if token.range(of: "^[A-Za-z]{1,3}[0-9]+$", options: .regularExpression) != nil { return nil }
        return (NSRange(location: start, length: caret - start), token)
    }

    /// True when a reference may be inserted at the caret (after an operator, '(' or separator).
    static func canInsertReference(_ text: String, caret: Int) -> Bool {
        let s = text as NSString
        guard s.length >= 1, s.character(at: 0) == 61, caret >= 1, caret <= s.length else { return false }
        if caret < s.length, isIdent(s.character(at: caret)) { return false }
        if inString(s, caret) { return false }
        var j = caret - 1
        while j > 0 && s.character(at: j) == 32 { j -= 1 }
        return "=+-*/^&(,;<>:".utf16.contains(s.character(at: j))
    }
}

/// Floating list for function autocomplete.
final class CompletionPopup: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private(set) var items: [String] = []
    var onAccept: ((String) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        let fx = NSVisualEffectView()
        fx.material = .menu
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 8
        fx.layer?.masksToBounds = true
        contentView = fx
        let col = NSTableColumn(identifier: .init("f"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 30
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.style = .plain
        table.intercellSpacing = .zero
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.frame = fx.bounds.insetBy(dx: 4, dy: 4)
        scroll.autoresizingMask = [.width, .height]
        fx.addSubview(scroll)
    }

    var selected: String? { table.selectedRow >= 0 && table.selectedRow < items.count ? items[table.selectedRow] : nil }

    func show(_ items: [String], below rect: NSRect, parent: NSWindow) {
        self.items = items
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.scrollRowToVisible(0)
        let h = CGFloat(min(items.count, 7)) * table.rowHeight + 8
        setFrame(NSRect(x: rect.minX, y: rect.minY - h - 2, width: 420, height: h), display: true)
        if parent != self.parent { parent.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    func hide() {
        guard isVisible || !items.isEmpty else { return }
        parent?.removeChildWindow(self)
        orderOut(nil)
        items = []
        table.reloadData()
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        let r = min(max(0, table.selectedRow + d), items.count - 1)
        table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    @objc private func doubleClicked() { if let s = selected { onAccept?(s) } }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let v = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let t = NSTextField(labelWithString: "")
            t.lineBreakMode = .byTruncatingTail
            t.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(t)
            c.textField = t
            NSLayoutConstraint.activate([t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8),
                                         t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -8),
                                         t.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
            return c
        }()
        guard row < items.count else { return nil }
        let name = items[row]
        let s = NSMutableAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        if let d = FunctionDocs.doc(Workbook.englishName(name)) {
            let summary = Locale.preferredLanguages.first?.hasPrefix("it") == true ? d.summaryIT : d.summary
            s.append(NSAttributedString(string: "  " + summary, attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                                              .foregroundColor: NSColor.secondaryLabelColor]))
        }
        v.textField?.attributedStringValue = s
        return v
    }
}

/// Tooltip showing the signature of the function being typed, current argument in bold.
final class HintPopup: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 24), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = .popUpMenu
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        let fx = NSVisualEffectView()
        fx.material = .toolTip
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 5
        contentView = fx
        label.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 8),
                                     label.centerYAnchor.constraint(equalTo: fx.centerYAnchor)])
    }

    func show(function: String, arg: Int, below rect: NSRect, parent: NSWindow) {
        let (sig, ranges) = Workbook.signatureParts(function)
        let s = NSMutableAttributedString(string: sig, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        if !ranges.isEmpty {
            let r = ranges[min(arg, ranges.count - 1)]
            if NSMaxRange(r) <= s.length { s.addAttribute(.font, value: NSFont.systemFont(ofSize: 11, weight: .bold), range: r) }
        }
        label.attributedStringValue = s
        let w = s.size().width + 18
        setFrame(NSRect(x: rect.minX, y: rect.minY - 26, width: max(80, w), height: 22), display: true)
        if parent != self.parent { parent.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    func hide() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}

/// Live state while a cell (or the formula bar) is being edited.
final class FormulaSession {
    let field: NSTextField
    private let popup = CompletionPopup()
    private let hint = HintPopup()
    /// Text range of the reference inserted by pointing (mouse/arrows), replaced while pointing continues.
    private(set) var pointRange: NSRange?
    var pointAnchor: CellRef?
    var pointCursor: CellRef?
    private var inserting = false
    private var token: NSRange?
    var onRefs: (([FormulaText.Ref]) -> Void)?

    init(field: NSTextField) {
        self.field = field
        popup.onAccept = { [weak self] name in self?.accept(name) }
    }

    var textView: NSTextView? { field.currentEditor() as? NSTextView }
    var text: String { textView?.string ?? field.stringValue }
    var caret: Int { textView?.selectedRange().location ?? (text as NSString).length }
    var isFormula: Bool { text.hasPrefix("=") }

    /// Pointing replaces the last pointed reference, or inserts at a position that accepts one.
    func canPoint() -> Bool {
        guard isFormula, textView?.selectedRange().length == 0 else { return false }
        if let p = pointRange, NSMaxRange(p) == caret { return true }
        return FormulaText.canInsertReference(text, caret: caret)
    }

    func insertReference(_ s: String) {
        guard let tv = textView else { return }
        let r: NSRange
        if let p = pointRange, NSMaxRange(p) == caret { r = p } else { r = NSRange(location: caret, length: 0) }
        inserting = true
        tv.insertText(s, replacementRange: r)
        pointRange = NSRange(location: r.location, length: (s as NSString).length)
        textChanged()
        inserting = false
    }

    func textChanged() {
        if !inserting { pointRange = nil; pointAnchor = nil; pointCursor = nil }
        let refs = FormulaText.references(in: text)
        recolor(refs)
        onRefs?(refs)
        updatePopups()
    }

    func recolor(_ refs: [FormulaText.Ref]) {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let full = NSRange(location: 0, length: ts.length)
        ts.beginEditing()
        ts.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
        for (i, r) in refs.enumerated() where NSMaxRange(r.textRange) <= ts.length {
            ts.addAttribute(.foregroundColor, value: FormulaText.palette[i % FormulaText.palette.count], range: r.textRange)
        }
        ts.endEditing()
    }

    private func caretRect() -> NSRect? {
        guard let tv = textView, let win = field.window else { return nil }
        let r = tv.firstRect(forCharacterRange: NSRange(location: caret, length: 0), actualRange: nil)
        let fieldScreen = win.convertToScreen(field.convert(field.bounds, to: nil))
        return NSRect(x: r.minX, y: fieldScreen.minY, width: 1, height: 1)
    }

    private func updatePopups() {
        guard let win = field.window, isFormula, let rect = caretRect() else { popup.hide(); hint.hide(); return }
        if let (range, prefix) = FormulaText.nameToken(text, caret: caret) {
            let p = prefix.uppercased()
            let names = Workbook.functionNames.filter { $0.hasPrefix(p) }
            if !names.isEmpty, !(names.count == 1 && names[0] == p) {
                token = range
                popup.show(Array(names.prefix(60)), below: rect, parent: win)
                hint.hide()
                return
            }
        }
        token = nil
        popup.hide()
        if let (name, arg) = FormulaText.enclosingFunction(text, caret: caret), FunctionDocs.doc(Workbook.englishName(name)) != nil {
            hint.show(function: name, arg: arg, below: rect, parent: win)
        } else {
            hint.hide()
        }
    }

    private func accept(_ name: String) {
        guard let tv = textView, let t = token else { return }
        let s = text as NSString
        let hasParen = NSMaxRange(t) < s.length && s.character(at: NSMaxRange(t)) == 40
        tv.insertText(hasParen ? name : name + "(", replacementRange: t)
        popup.hide()
        textChanged()
    }

    /// Returns true when the popup consumed the command.
    func handle(_ sel: Selector) -> Bool {
        guard popup.isVisible, !popup.items.isEmpty else { return false }
        switch sel {
        case #selector(NSResponder.moveUp(_:)): popup.move(-1); return true
        case #selector(NSResponder.moveDown(_:)): popup.move(1); return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertNewline(_:)):
            if let s = popup.selected { accept(s) }
            return true
        case #selector(NSResponder.cancelOperation(_:)): popup.hide(); return true
        default: return false
        }
    }

    func end() {
        popup.hide()
        hint.hide()
        onRefs?([])
    }
}
