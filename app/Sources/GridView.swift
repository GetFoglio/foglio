import AppKit
import QuartzCore

struct CellRef: Equatable {
    var row: Int
    var col: Int
}

struct GridRange: Equatable {
    var r0: Int, c0: Int, r1: Int, c1: Int
    init(_ a: CellRef, _ b: CellRef) {
        r0 = min(a.row, b.row); r1 = max(a.row, b.row)
        c0 = min(a.col, b.col); c1 = max(a.col, b.col)
    }
    init(r0: Int, c0: Int, r1: Int, c1: Int) { self.r0 = r0; self.c0 = c0; self.r1 = r1; self.c1 = c1 }
    var isSingle: Bool { r0 == r1 && c0 == c1 }
    var cellCount: Int { (r1 - r0 + 1) * (c1 - c0 + 1) }
    var a1: String {
        let a = "\(columnName(c0))\(r0 + 1)"
        return isSingle ? a : "\(a):\(columnName(c1))\(r1 + 1)"
    }
}

func columnName(_ c: Int) -> String {
    var n = c + 1
    var s = ""
    while n > 0 {
        let m = (n - 1) % 26
        s = String(UnicodeScalar(UInt8(65 + m))) + s
        n = (n - 1) / 26
    }
    return s
}

/// Parses "B12" into a 0-based CellRef.
func parseA1(_ s: String) -> CellRef? {
    let u = s.uppercased().trimmingCharacters(in: .whitespaces)
    var col = 0, row = 0, i = u.startIndex
    while i < u.endIndex, let a = u[i].asciiValue, a >= 65, a <= 90 { col = col * 26 + Int(a - 64); i = u.index(after: i) }
    guard col > 0, i < u.endIndex, let r = Int(u[i...]), r > 0 else { return nil }
    row = r
    return CellRef(row: row - 1, col: col - 1)
}

protocol GridViewDelegate: AnyObject {
    func gridSelectionChanged(_ grid: GridView)
    func gridEditingTextChanged(_ grid: GridView, text: String)
    func gridContentChanged(_ grid: GridView)
}

/// The spreadsheet grid: one layer-backed view, own scroll offset, draws only the visible cells.
final class GridView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    static let maxRows = 1_048_576
    static let maxCols = 16_384

    let rowH: CGFloat = 21
    let colW: CGFloat = 84
    let headerH: CGFloat = 22
    let headerW: CGFloat = 52

    var book: Workbook { didSet { cache = nil; needsDisplay = true } }
    var sheet = 0 {
        didSet {
            offset = .zero
            anchor = CellRef(row: 0, col: 0); cursor = anchor
            cache = nil; needsDisplay = true; notifySelection()
        }
    }
    weak var delegate: GridViewDelegate?

    private(set) var offset = CGPoint.zero
    /// Active cell (what the formula bar shows). Shift+move extends `cursor`, like Excel.
    private(set) var anchor = CellRef(row: 0, col: 0)
    private(set) var cursor = CellRef(row: 0, col: 0)
    var selection: GridRange { GridRange(anchor, cursor) }

    enum EditMode { case enter, edit }
    private var editor: NSTextField?
    private var editMode = EditMode.enter
    var isEditing: Bool { editor != nil }

    private enum Drag { case none, select, fill(GridRange) }
    private var drag = Drag.none
    private var fillTarget: GridRange?

    private struct CacheKey: Equatable { let sheet, version, r0, r1, c0, c1: Int }
    private var cache: (key: CacheKey, cells: [VCell], occupied: Set<Int64>, byKey: [Int64: Int])?

    private let baseFont = NSFont.systemFont(ofSize: 13)
    private let headerFont = NSFont.systemFont(ofSize: 11)
    private var attrCache: [Int: [NSAttributedString.Key: Any]] = [:]

    // Benchmark: synthetic scrolling driven by the display link.
    private var autoScrollFrames = 0
    private var frameStamps: [CFTimeInterval] = []
    private var link: CADisplayLink?

    init(book: Workbook) {
        self.book = book
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidChangeEffectiveAppearance() { attrCache.removeAll(); needsDisplay = true }

    // MARK: - Geometry

    private var gridRect: CGRect {
        CGRect(x: headerW, y: headerH, width: max(0, bounds.width - headerW), height: max(0, bounds.height - headerH))
    }
    private var maxOffset: CGPoint {
        CGPoint(x: max(0, CGFloat(Self.maxCols) * colW - gridRect.width),
                y: max(0, CGFloat(Self.maxRows) * rowH - gridRect.height))
    }
    func cellRect(_ r: Int, _ c: Int) -> CGRect {
        CGRect(x: headerW + CGFloat(c) * colW - offset.x, y: headerH + CGFloat(r) * rowH - offset.y, width: colW, height: rowH)
    }
    private func rangeRect(_ g: GridRange) -> CGRect { cellRect(g.r0, g.c0).union(cellRect(g.r1, g.c1)) }
    private var visibleRows: ClosedRange<Int> {
        let f = max(0, Int(offset.y / rowH))
        return f...max(f, min(Self.maxRows - 1, Int((offset.y + gridRect.height) / rowH)))
    }
    private var visibleCols: ClosedRange<Int> {
        let f = max(0, Int(offset.x / colW))
        return f...max(f, min(Self.maxCols - 1, Int((offset.x + gridRect.width) / colW)))
    }
    private func cellAt(_ p: CGPoint) -> CellRef {
        let c = Int(floor((p.x - headerW + offset.x) / colW))
        let r = Int(floor((p.y - headerH + offset.y) / rowH))
        return CellRef(row: min(max(r, 0), Self.maxRows - 1), col: min(max(c, 0), Self.maxCols - 1))
    }
    private var fillHandleRect: CGRect {
        let r = rangeRect(selection)
        return CGRect(x: r.maxX - 4, y: r.maxY - 4, width: 7, height: 7)
    }

    private func setOffset(_ p: CGPoint) {
        let m = maxOffset
        let n = CGPoint(x: min(max(0, p.x), m.x).rounded(), y: min(max(0, p.y), m.y).rounded())
        guard n != offset else { return }
        offset = n
        positionEditor()
        needsDisplay = true
    }

    private func ensureVisible(_ c: CellRef) {
        var o = offset
        let x = CGFloat(c.col) * colW, y = CGFloat(c.row) * rowH
        if x < o.x { o.x = x } else if x + colW > o.x + gridRect.width { o.x = x + colW - gridRect.width }
        if y < o.y { o.y = y } else if y + rowH > o.y + gridRect.height { o.y = y + rowH - gridRect.height }
        setOffset(o)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        setOffset(offset)
    }

    // MARK: - Data

    private static func key(_ r: Int, _ c: Int) -> Int64 { Int64(r) << 16 | Int64(c) }

    private func fetch(_ rows: ClosedRange<Int>, _ cols: ClosedRange<Int>) -> (cells: [VCell], occupied: Set<Int64>, byKey: [Int64: Int]) {
        let k = CacheKey(sheet: sheet, version: book.version, r0: rows.lowerBound, r1: rows.upperBound,
                         c0: cols.lowerBound, c1: cols.upperBound)
        if let c = cache, c.key == k { return (c.cells, c.occupied, c.byKey) }
        // Over-fetch columns to the right a bit so text overflow knows its neighbours.
        let cells = book.viewport(sheet: sheet, rows: rows, cols: cols.lowerBound...min(Self.maxCols - 1, cols.upperBound + 4))
        var occ = Set<Int64>(minimumCapacity: cells.count)
        var by = [Int64: Int](minimumCapacity: cells.count)
        for (i, c) in cells.enumerated() {
            let kk = Self.key(c.row, c.col)
            by[kk] = i
            if !c.text.isEmpty { occ.insert(kk) }
        }
        cache = (k, cells, occ, by)
        return (cells, occ, by)
    }

    func cellAtAnchor() -> VCell? {
        let cells = book.viewport(sheet: sheet, rows: anchor.row...anchor.row, cols: anchor.col...anchor.col)
        return cells.first
    }

    // MARK: - Drawing

    private func attrs(bold: Bool, italic: Bool, fg: UInt32, kind: UInt8) -> [NSAttributedString.Key: Any] {
        let k = (bold ? 1 : 0) | (italic ? 2 : 0) | (kind == 3 ? 4 : 0) | Int(fg == VCell.noColor ? 0xFFFFFF : fg) << 3
        if let a = attrCache[k] { return a }
        var font = bold ? NSFont.systemFont(ofSize: 13, weight: .semibold) : baseFont
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        let color: NSColor = fg == VCell.noColor ? (kind == 3 ? .systemRed : .textColor) : rgb(fg)
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        attrCache[k] = a
        return a
    }

    private func rgb(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        let t0 = CACurrentMediaTime()
        let rows = visibleRows, cols = visibleCols
        let data = fetch(rows, cols)
        let scale = window?.backingScaleFactor ?? 2
        let hair = 1 / scale
        let grid = gridRect
        let bg = NSColor.textBackgroundColor
        let lineColor = NSColor.separatorColor.blended(withFraction: 0.35, of: bg) ?? .separatorColor
        let accent = NSColor.controlAccentColor

        bg.setFill()
        bounds.fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: grid).setClip()

        // 1. cell fills
        for c in data.cells where c.bg != VCell.noColor && cols.contains(c.col) {
            rgb(c.bg).setFill()
            cellRect(c.row, c.col).fill()
        }

        // 2. grid lines (hairlines on the right/bottom edge of each cell)
        lineColor.setFill()
        for r in rows {
            let y = cellRect(r, cols.lowerBound).maxY - hair
            CGRect(x: grid.minX, y: y, width: grid.width, height: hair).fill()
        }
        for c in cols {
            let x = cellRect(rows.lowerBound, c).maxX - hair
            CGRect(x: x, y: grid.minY, width: hair, height: grid.height).fill()
        }

        // 3. text (with Excel-style overflow into empty neighbours)
        for c in data.cells where !c.text.isEmpty && cols.contains(c.col) {
            var text = c.text
            let a = attrs(bold: c.bold, italic: c.italic, fg: c.fg, kind: c.kind)
            var size = (text as NSString).size(withAttributes: a)
            let rect = cellRect(c.row, c.col)
            let effAlign: UInt8 = c.align != 0 ? c.align : (c.kind == 1 ? 3 : (c.kind >= 2 ? 2 : 1))
            var clip = rect
            if size.width > colW - 6 {
                if c.kind == 1 {
                    // Numbers never overflow: Excel shows ####.
                    let hash = ("#" as NSString).size(withAttributes: a).width
                    text = String(repeating: "#", count: max(1, Int((colW - 6) / max(hash, 1))))
                    size = (text as NSString).size(withAttributes: a)
                } else if effAlign == 1 {
                    var end = c.col
                    var width = colW
                    while width < size.width + 6, end + 1 < Self.maxCols,
                          !data.occupied.contains(Self.key(c.row, end + 1)), end + 1 <= cols.upperBound + 4 {
                        end += 1; width += colW
                    }
                    if end > c.col {
                        clip = rect.union(cellRect(c.row, end))
                        let fill = data.byKey[Self.key(c.row, c.col)].map { data.cells[$0].bg } ?? VCell.noColor
                        (fill == VCell.noColor ? bg : rgb(fill)).setFill()
                        CGRect(x: clip.minX, y: clip.minY, width: clip.width - hair, height: clip.height - hair).fill()
                    }
                }
            }
            let x: CGFloat
            switch effAlign {
            case 3: x = rect.maxX - 4 - size.width
            case 2: x = rect.midX - size.width / 2
            default: x = rect.minX + 4
            }
            let y = rect.minY + (rowH - size.height) / 2
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: clip.insetBy(dx: 1, dy: 0)).addClip()
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: a)
            NSGraphicsContext.restoreGraphicsState()
        }

        // 4. selection
        let sel = selection
        let selRect = rangeRect(sel).intersection(grid.insetBy(dx: -4, dy: -4))
        if !selRect.isNull {
            if !sel.isSingle {
                let path = NSBezierPath(rect: selRect)
                path.appendRect(cellRect(anchor.row, anchor.col))
                path.windingRule = .evenOdd
                accent.withAlphaComponent(0.13).setFill()
                path.fill()
            }
            accent.setStroke()
            let border = NSBezierPath(rect: selRect.insetBy(dx: 0.5, dy: 0.5).offsetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 2
            border.stroke()
            let h = fillHandleRect
            bg.setFill(); h.insetBy(dx: -1, dy: -1).fill()
            accent.setFill(); h.fill()
        }
        if let t = fillTarget {
            let r = rangeRect(t).intersection(grid.insetBy(dx: -4, dy: -4))
            let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
            p.setLineDash([3, 2], count: 2, phase: 0)
            p.lineWidth = 1
            NSColor.secondaryLabelColor.setStroke()
            p.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        drawHeaders(rows: rows, cols: cols, sel: sel, hair: hair, accent: accent)

        Perf.shared.frameDrawn(ms: (CACurrentMediaTime() - t0) * 1000)
    }

    private func drawHeaders(rows: ClosedRange<Int>, cols: ClosedRange<Int>, sel: GridRange, hair: CGFloat, accent: NSColor) {
        let headerBG = NSColor.windowBackgroundColor
        let line = NSColor.separatorColor
        let normal: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: NSColor.secondaryLabelColor]
        let selected: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                                       .foregroundColor: accent]
        // column header
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: headerW, y: 0, width: bounds.width - headerW, height: headerH)).setClip()
        headerBG.setFill(); CGRect(x: headerW, y: 0, width: bounds.width, height: headerH).fill()
        for c in cols {
            var r = cellRect(0, c); r.origin.y = 0; r.size.height = headerH
            let isSel = c >= sel.c0 && c <= sel.c1
            if isSel {
                accent.withAlphaComponent(0.15).setFill(); r.fill()
                accent.setFill(); CGRect(x: r.minX, y: headerH - 2, width: r.width, height: 2).fill()
            }
            line.setFill(); CGRect(x: r.maxX - hair, y: 0, width: hair, height: headerH).fill()
            let s = columnName(c) as NSString
            let a = isSel ? selected : normal
            let sz = s.size(withAttributes: a)
            s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: (headerH - sz.height) / 2), withAttributes: a)
        }
        line.setFill(); CGRect(x: headerW, y: headerH - hair, width: bounds.width, height: hair).fill()
        NSGraphicsContext.restoreGraphicsState()

        // row header
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: 0, y: headerH, width: headerW, height: bounds.height - headerH)).setClip()
        headerBG.setFill(); CGRect(x: 0, y: headerH, width: headerW, height: bounds.height).fill()
        for r in rows {
            var rr = cellRect(r, 0); rr.origin.x = 0; rr.size.width = headerW
            let isSel = r >= sel.r0 && r <= sel.r1
            if isSel {
                accent.withAlphaComponent(0.15).setFill(); rr.fill()
                accent.setFill(); CGRect(x: headerW - 2, y: rr.minY, width: 2, height: rr.height).fill()
            }
            line.setFill(); CGRect(x: 0, y: rr.maxY - hair, width: headerW, height: hair).fill()
            let s = String(r + 1) as NSString
            let a = isSel ? selected : normal
            let sz = s.size(withAttributes: a)
            s.draw(at: CGPoint(x: headerW - 6 - sz.width, y: rr.minY + (rowH - sz.height) / 2), withAttributes: a)
        }
        line.setFill(); CGRect(x: headerW - hair, y: headerH, width: hair, height: bounds.height).fill()
        NSGraphicsContext.restoreGraphicsState()

        // corner
        headerBG.setFill(); CGRect(x: 0, y: 0, width: headerW, height: headerH).fill()
        line.setFill()
        CGRect(x: headerW - hair, y: 0, width: hair, height: headerH).fill()
        CGRect(x: 0, y: headerH - hair, width: headerW, height: hair).fill()
    }

    // MARK: - Selection & navigation

    private func notifySelection() {
        delegate?.gridSelectionChanged(self)
        window?.invalidateCursorRects(for: self)
    }

    func select(_ c: CellRef, extend: Bool = false) {
        let c = CellRef(row: min(max(c.row, 0), Self.maxRows - 1), col: min(max(c.col, 0), Self.maxCols - 1))
        if extend { cursor = c } else { anchor = c; cursor = c }
        ensureVisible(cursor)
        needsDisplay = true
        notifySelection()
    }

    private func move(_ dr: Int, _ dc: Int, extend: Bool = false) {
        let from = extend ? cursor : anchor
        select(CellRef(row: from.row + dr, col: from.col + dc), extend: extend)
    }

    private var pageRows: Int { max(1, Int(gridRect.height / rowH) - 1) }

    override func keyDown(with e: NSEvent) {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = flags.contains(.shift), cmd = flags.contains(.command)
        let from = shift ? cursor : anchor
        switch e.keyCode {
        case 126: cmd ? select(CellRef(row: 0, col: from.col), extend: shift) : move(-1, 0, extend: shift)
        case 125: cmd ? select(CellRef(row: Self.maxRows - 1, col: from.col), extend: shift) : move(1, 0, extend: shift)
        case 123: cmd ? select(CellRef(row: from.row, col: 0), extend: shift) : move(0, -1, extend: shift)
        case 124: cmd ? select(CellRef(row: from.row, col: Self.maxCols - 1), extend: shift) : move(0, 1, extend: shift)
        case 36, 76: move(shift ? -1 : 1, 0)
        case 48: move(0, shift ? -1 : 1)
        case 116: move(-pageRows, 0, extend: shift)
        case 121: move(pageRows, 0, extend: shift)
        case 115: select(CellRef(row: cmd ? 0 : from.row, col: 0), extend: shift)
        case 51, 117: clearSelection()
        case 120: beginEditing(.edit, initial: nil) // F2
        default:
            if !cmd, !flags.contains(.control), let ch = e.characters, let s = ch.unicodeScalars.first,
               s.value >= 32, s.value != 127, !(0xF700...0xF8FF).contains(s.value) {
                beginEditing(.enter, initial: ch)
            } else {
                super.keyDown(with: e)
            }
        }
    }

    override func scrollWheel(with e: NSEvent) {
        var dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
        if !e.hasPreciseScrollingDeltas { dx *= colW / 2; dy *= rowH * 3 }
        if e.modifierFlags.contains(.shift) && dx == 0 { dx = dy; dy = 0 }
        setOffset(CGPoint(x: offset.x - dx, y: offset.y - dy))
    }

    // MARK: - Mouse

    override func resetCursorRects() {
        addCursorRect(fillHandleRect.insetBy(dx: -3, dy: -3), cursor: .crosshair)
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if isEditing { commitEditing(move: nil) }
        window?.makeFirstResponder(self)
        let shift = e.modifierFlags.contains(.shift)
        if fillHandleRect.insetBy(dx: -3, dy: -3).contains(p) {
            drag = .fill(selection)
            return
        }
        if p.y < headerH && p.x > headerW { // column header
            let c = cellAt(p).col
            anchor = CellRef(row: 0, col: shift ? anchor.col : c); cursor = CellRef(row: Self.maxRows - 1, col: c)
        } else if p.x < headerW && p.y > headerH { // row header
            let r = cellAt(p).row
            anchor = CellRef(row: shift ? anchor.row : r, col: 0); cursor = CellRef(row: r, col: Self.maxCols - 1)
        } else if p.x < headerW && p.y < headerH {
            selectAll(nil); return
        } else {
            let c = cellAt(p)
            if shift { cursor = c } else { anchor = c; cursor = c }
            if e.clickCount == 2 { beginEditing(.edit, initial: nil) }
        }
        drag = .select
        needsDisplay = true
        notifySelection()
    }

    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        // Autoscroll when dragging past the edges.
        var o = offset
        if p.y > bounds.maxY { o.y += rowH } else if p.y < headerH { o.y -= rowH }
        if p.x > bounds.maxX { o.x += colW } else if p.x < headerW { o.x -= colW }
        setOffset(o)
        let c = cellAt(p)
        switch drag {
        case .select:
            if cursor != c { cursor = c; needsDisplay = true; notifySelection() }
        case .fill(let s):
            let down = c.row - s.r1, right = c.col - s.c1
            if down > 0 && down >= right {
                fillTarget = GridRange(r0: s.r0, c0: s.c0, r1: c.row, c1: s.c1)
            } else if right > 0 {
                fillTarget = GridRange(r0: s.r0, c0: s.c0, r1: s.r1, c1: c.col)
            } else {
                fillTarget = nil
            }
            needsDisplay = true
        case .none: break
        }
    }

    override func mouseUp(with e: NSEvent) {
        if case .fill(let s) = drag, let t = fillTarget {
            if t.r1 > s.r1 {
                book.autofill(sheet: sheet, s, toRow: t.r1, toCol: nil)
            } else {
                book.autofill(sheet: sheet, s, toRow: nil, toCol: t.c1)
            }
            anchor = CellRef(row: t.r0, col: t.c0); cursor = CellRef(row: t.r1, col: t.c1)
            delegate?.gridContentChanged(self)
            notifySelection()
        }
        fillTarget = nil
        drag = .none
        needsDisplay = true
    }

    // MARK: - In-cell editing

    private var editorFrame: CGRect { cellRect(anchor.row, anchor.col).insetBy(dx: 1, dy: 1) }

    private func positionEditor() {
        guard let f = editor else { return }
        f.frame = editorFrame
    }

    func beginEditing(_ mode: EditMode, initial: String?) {
        guard editor == nil else { return }
        ensureVisible(anchor)
        let f = NSTextField(frame: editorFrame)
        f.isBordered = false
        f.focusRingType = .none
        f.drawsBackground = true
        f.backgroundColor = .textBackgroundColor
        f.font = baseFont
        f.delegate = self
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.stringValue = initial ?? book.input(sheet: sheet, row: anchor.row, col: anchor.col)
        editor = f
        editMode = mode
        addSubview(f)
        window?.makeFirstResponder(f)
        if let ed = f.currentEditor() {
            ed.selectedRange = NSRange(location: (f.stringValue as NSString).length, length: 0)
        }
        delegate?.gridEditingTextChanged(self, text: f.stringValue)
    }

    /// Called by the formula bar so both editors stay in sync.
    func setEditorText(_ s: String) { editor?.stringValue = s }

    func commitEditing(move delta: (Int, Int)?) {
        guard let f = editor else { return }
        let s = f.stringValue
        editor = nil
        f.removeFromSuperview()
        window?.makeFirstResponder(self)
        book.setInput(sheet: sheet, row: anchor.row, col: anchor.col, s)
        delegate?.gridContentChanged(self)
        if let m = delta { move(m.0, m.1) } else { notifySelection() }
        needsDisplay = true
    }

    func cancelEditing() {
        guard let f = editor else { return }
        editor = nil
        f.removeFromSuperview()
        window?.makeFirstResponder(self)
        notifySelection()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)): commitEditing(move: (1, 0)); return true
        case #selector(NSResponder.insertTab(_:)): commitEditing(move: (0, 1)); return true
        case #selector(NSResponder.insertBacktab(_:)): commitEditing(move: (0, -1)); return true
        case #selector(NSResponder.cancelOperation(_:)): cancelEditing(); return true
        default: break
        }
        guard editMode == .enter else { return false }
        switch sel {
        case #selector(NSResponder.moveUp(_:)): commitEditing(move: (-1, 0)); return true
        case #selector(NSResponder.moveDown(_:)): commitEditing(move: (1, 0)); return true
        case #selector(NSResponder.moveLeft(_:)): commitEditing(move: (0, -1)); return true
        case #selector(NSResponder.moveRight(_:)): commitEditing(move: (0, 1)); return true
        default: return false
        }
    }

    func controlTextDidChange(_ n: Notification) {
        if let f = editor { delegate?.gridEditingTextChanged(self, text: f.stringValue) }
    }

    func controlTextDidEndEditing(_ n: Notification) {
        if let f = editor, (n.object as? NSTextField) === f { commitEditing(move: nil) }
    }

    // MARK: - Commands (menu / toolbar)

    func contentChanged() {
        needsDisplay = true
        delegate?.gridContentChanged(self)
        notifySelection()
    }

    func clearSelection() {
        book.clear(sheet: sheet, selection)
        contentChanged()
    }

    @objc func undo(_ sender: Any?) { book.undo(); contentChanged() }
    @objc func redo(_ sender: Any?) { book.redo(); contentChanged() }
    @objc func delete(_ sender: Any?) { clearSelection() }

    @objc override func selectAll(_ sender: Any?) {
        anchor = CellRef(row: 0, col: 0)
        cursor = CellRef(row: Self.maxRows - 1, col: Self.maxCols - 1)
        needsDisplay = true
        notifySelection()
    }

    @objc func copy(_ sender: Any?) {
        let s = selection
        // Clamp huge selections (whole columns) to the cells that actually hold data.
        let cells = book.viewport(sheet: sheet, rows: s.r0...s.r1, cols: s.c0...s.c1)
        guard !cells.isEmpty || s.cellCount <= 1 else { return }
        let lastRow = s.cellCount > 1_000_000 ? (cells.map(\.row).max() ?? s.r0) : s.r1
        let lastCol = s.cellCount > 1_000_000 ? (cells.map(\.col).max() ?? s.c0) : s.c1
        var grid: [[String]] = Array(repeating: Array(repeating: "", count: lastCol - s.c0 + 1), count: lastRow - s.r0 + 1)
        for c in cells where c.row <= lastRow && c.col <= lastCol { grid[c.row - s.r0][c.col - s.c0] = c.text }
        let tsv = grid.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tsv, forType: .string)
    }

    @objc func cut(_ sender: Any?) { copy(sender); clearSelection() }

    @objc func paste(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return }
        book.pasteTSV(sheet: sheet, row: anchor.row, col: anchor.col, s)
        let lines = s.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        let width = lines.map { $0.components(separatedBy: "\t").count }.max() ?? 1
        cursor = CellRef(row: anchor.row + lines.count - 1, col: anchor.col + width - 1)
        contentChanged()
    }

    func toggleStyle(_ path: String) {
        let current = cellAtAnchor()
        let on: Bool
        switch path {
        case "font.b": on = !(current?.bold ?? false)
        case "font.i": on = !(current?.italic ?? false)
        default: on = true
        }
        book.setStyle(sheet: sheet, selection, path: path, value: on ? "true" : "false")
        contentChanged()
    }

    func setStyle(_ path: String, _ value: String) {
        book.setStyle(sheet: sheet, selection, path: path, value: value)
        contentChanged()
    }

    /// Σ: write =SUM() over the contiguous numbers above the active cell, then let the user confirm.
    func autoSum() {
        let r = anchor.row, c = anchor.col
        guard r > 0 else { beginEditing(.edit, initial: "=SUM()"); return }
        let cells = book.viewport(sheet: sheet, rows: max(0, r - 2000)...(r - 1), cols: c...c)
        let numeric = Set(cells.filter { $0.kind == 1 }.map(\.row))
        var top = r - 1
        while top >= 0 && numeric.contains(top) { top -= 1 }
        let formula = top == r - 1 ? "=SUM()" : "=SUM(\(columnName(c))\(top + 2):\(columnName(c))\(r))"
        beginEditing(.edit, initial: formula)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return book.canUndo
        case #selector(redo(_:)): return book.canRedo
        default: return true
        }
    }

    // MARK: - Benchmark

    func startAutoScroll(frames: Int) {
        autoScrollFrames = frames
        frameStamps.removeAll(keepingCapacity: true)
        Perf.shared.beginRecording()
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        frameStamps.append(l.timestamp)
        if frameStamps.count >= autoScrollFrames {
            l.invalidate(); link = nil
            Perf.shared.endRecording(frameStamps: frameStamps, refresh: 1 / (l.targetTimestamp - l.timestamp))
            return
        }
        // ~3 rows and a bit sideways per frame: a fast flick.
        setOffset(CGPoint(x: offset.x + 2, y: offset.y + rowH * 3))
    }
}
