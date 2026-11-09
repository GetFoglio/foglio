import AppKit
import QuartzCore

protocol GridViewDelegate: AnyObject {
    func gridSelectionChanged(_ grid: GridView)
    func gridEditingTextChanged(_ grid: GridView, text: String)
    func gridContentChanged(_ grid: GridView)
    func gridModeChanged(_ grid: GridView)
}

/// Text field used for in-cell editing.
final class CellEditorField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
}

/// The spreadsheet grid: one layer-backed view, own scroll offset and zoom, draws only what is visible.
/// Coordinates: "logical" points = view points / zoom. Engine sizes (px) are scaled by `unit`.
final class GridView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    let book: Workbook
    weak var delegate: GridViewDelegate?
    let painter = SheetPainter()

    var sheet = 0 {
        didSet {
            guard sheet != oldValue else { return }
            offset = .zero
            active = CellRef(row: 0, col: 0); cursor = active
            selection = GridRange(active, active)
            invalidateData()
            notifySelection()
        }
    }

    var zoom: CGFloat = 1 {
        didSet {
            zoom = min(4, max(0.25, zoom))
            positionEditor()
            setOffset(offset)
            updateScrollers()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    // Geometry ---------------------------------------------------------------
    /// Engine px -> logical points.
    /// Engine px -> points: columns 90px -> 81pt (fits a dd/mm/yyyy date), rows 25px -> 20pt.
    private let colUnit: CGFloat = 0.9
    private let rowUnit: CGFloat = 0.8
    private struct Geo {
        var cols: Axis
        var rows: Axis
        var fr = 0, fc = 0
        var showGrid = true
        var maxRow = 0, maxCol = 0
        var merges: [GridRange] = []
    }
    private var geoCache: Geo?
    private var geoKey = (-1, -1)
    private var resizePreview: (isCol: Bool, index: Int, size: CGFloat)?

    private var geo: Geo {
        if let g = geoCache, geoKey == (sheet, book.version), resizePreview == nil { return g }
        let l = book.layout(sheet: sheet)
        var colOverrides = l.cols.map { ($0.0, $0.2 ? 0 : ($0.1 * colUnit).rounded()) }
        var rowOverrides = l.rows.map { ($0.0, $0.2 ? 0 : ($0.1 * rowUnit).rounded()) }
        if let p = resizePreview {
            if p.isCol { colOverrides.removeAll { $0.0 == p.index }; colOverrides.append((p.index, p.size)) }
            else { rowOverrides.removeAll { $0.0 == p.index }; rowOverrides.append((p.index, p.size)) }
        }
        let g = Geo(cols: Axis(defaultSize: (l.defaultCol * colUnit).rounded(), count: Sheet.maxCols, overrides: colOverrides),
                    rows: Axis(defaultSize: (l.defaultRow * rowUnit).rounded(), count: Sheet.maxRows, overrides: rowOverrides),
                    fr: l.frozenRows, fc: l.frozenCols, showGrid: l.showGrid, maxRow: l.maxRow, maxCol: l.maxCol,
                    merges: book.merges(sheet: sheet))
        if resizePreview == nil { geoCache = g; geoKey = (sheet, book.version) }
        return g
    }

    private(set) var offset = CGPoint.zero
    let headerH: CGFloat = 20
    private var headerW: CGFloat = 40
    private var scrollerW: CGFloat { NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) }
    private var viewSize: CGSize { CGSize(width: (bounds.width - scrollerW) / zoom, height: (bounds.height - scrollerW) / zoom) }

    private func frozenW(_ g: Geo) -> CGFloat { g.cols.pos(g.fc) }
    private func frozenH(_ g: Geo) -> CGFloat { g.rows.pos(g.fr) }
    private func x(_ c: Int, _ g: Geo) -> CGFloat { headerW + g.cols.pos(c) - (c >= g.fc ? offset.x : 0) }
    private func y(_ r: Int, _ g: Geo) -> CGFloat { headerH + g.rows.pos(r) - (r >= g.fr ? offset.y : 0) }
    private func cellRect(_ r: Int, _ c: Int, _ g: Geo) -> CGRect {
        CGRect(x: x(c, g), y: y(r, g), width: g.cols.size(c), height: g.rows.size(r))
    }
    private func rangeRect(_ s: GridRange, _ g: Geo) -> CGRect { cellRect(s.r0, s.c0, g).union(cellRect(s.r1, s.c1, g)) }

    /// Scrolled (non-frozen) visible range along an axis.
    private func scrolledRows(_ g: Geo) -> ClosedRange<Int> {
        let fh = frozenH(g)
        let first = max(g.fr, g.rows.index(at: fh + offset.y))
        let last = g.rows.index(at: fh + offset.y + max(0, viewSize.height - headerH - fh))
        return first...max(first, last)
    }
    private func scrolledCols(_ g: Geo) -> ClosedRange<Int> {
        let fw = frozenW(g)
        let first = max(g.fc, g.cols.index(at: fw + offset.x))
        let last = g.cols.index(at: fw + offset.x + max(0, viewSize.width - headerW - fw))
        return first...max(first, last)
    }

    /// Cell under a logical point (frozen-aware).
    private func cellAt(_ p: CGPoint, _ g: Geo) -> CellRef {
        let fw = frozenW(g), fh = frozenH(g)
        let cx = p.x - headerW, cy = p.y - headerH
        let col = (g.fc > 0 && cx < fw) ? g.cols.index(at: max(0, cx)) : g.cols.index(at: max(fw, cx + offset.x))
        let row = (g.fr > 0 && cy < fh) ? g.rows.index(at: max(0, cy)) : g.rows.index(at: max(fh, cy + offset.y))
        return CellRef(row: row, col: col)
    }

    // Selection -------------------------------------------------------------
    /// Active cell (what the formula bar shows). Shift+move extends `cursor`, like Excel.
    private(set) var active = CellRef(row: 0, col: 0)
    private(set) var cursor = CellRef(row: 0, col: 0)
    private(set) var selection = GridRange(r0: 0, c0: 0, r1: 0, c1: 0)
    var refHighlights: [FormulaText.Ref] = [] { didSet { needsDisplay = true } }
    private(set) var cutRange: (sheet: Int, range: GridRange)?

    // Editing ---------------------------------------------------------------
    enum EditMode { case enter, edit }
    private(set) var editMode = EditMode.enter
    private var editField: NSTextField?
    private var overlay: CellEditorField?
    private var session: FormulaSession?
    private var editTarget = CellRef(row: 0, col: 0)
    private var editSheet = 0
    private var keyMonitor: Any?
    var isEditing: Bool { editField != nil }
    var isPointing: Bool { session?.canPoint() ?? false }

    // Mouse -----------------------------------------------------------------
    private enum Drag {
        case none, select, fill(GridRange), resizeCol(Int, CGFloat, CGFloat), resizeRow(Int, CGFloat, CGFloat)
        case point, cols(Int), rows(Int)
    }
    private var drag = Drag.none
    private var fillTarget: GridRange?
    private var autoscrollTimer: Timer?
    private var lastDragEvent: NSEvent?

    // Data cache ------------------------------------------------------------
    private struct RegionKey: Hashable { let r0, r1, c0, c1: Int }
    private var dataCache: [RegionKey: CellData] = [:]
    private var dataKey = (-1, -1)

    private let vScroller = NSScroller()
    private let hScroller = NSScroller()

    // Benchmark
    private var autoScrollFrames = 0
    private var frameStamps: [CFTimeInterval] = []

    static let pasteboardType = NSPasteboard.PasteboardType("org.foglio.cells")

    init(book: Workbook) {
        self.book = book
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        for s in [vScroller, hScroller] {
            s.scrollerStyle = .legacy
            s.isEnabled = true
            s.target = self
            s.action = #selector(scrollerAction(_:))
            addSubview(s)
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { !isPointing }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidChangeEffectiveAppearance() { painter.resetColors(); needsDisplay = true }

    func invalidateData() {
        dataCache.removeAll()
        geoCache = nil
        needsDisplay = true
        updateScrollers()
    }

    override func layout() {
        super.layout()
        let sw = scrollerW
        vScroller.frame = NSRect(x: bounds.width - sw, y: 0, width: sw, height: bounds.height - sw)
        hScroller.frame = NSRect(x: 0, y: bounds.height - sw, width: bounds.width - sw, height: sw)
        setOffset(offset)
        updateScrollers()
    }

    // MARK: - Scrolling

    private var maxOffset: CGPoint {
        let g = geo
        return CGPoint(x: max(0, g.cols.total - frozenW(g) - (viewSize.width - headerW - frozenW(g))),
                       y: max(0, g.rows.total - frozenH(g) - (viewSize.height - headerH - frozenH(g))))
    }

    private func setOffset(_ p: CGPoint) {
        let m = maxOffset
        let n = CGPoint(x: min(max(0, p.x), m.x).rounded(), y: min(max(0, p.y), m.y).rounded())
        guard n != offset else { return }
        offset = n
        positionEditor()
        updateScrollers()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    /// Excel-like scrollbar extent: the used range plus what you scrolled to.
    private func extents() -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let g = geo
        let visW = max(1, viewSize.width - headerW - frozenW(g)), visH = max(1, viewSize.height - headerH - frozenH(g))
        let usedW = g.cols.pos(min(Sheet.maxCols, max(g.maxCol, selection.c1) + 1)) - frozenW(g)
        let usedH = g.rows.pos(min(Sheet.maxRows, max(g.maxRow, selection.r1) + 1)) - frozenH(g)
        let contentW = max(usedW + visW * 0.5, offset.x + visW)
        let contentH = max(usedH + visH * 0.5, offset.y + visH)
        return (contentW, visW, contentH, visH)
    }

    private func updateScrollers() {
        let (cw, vw, ch, vh) = extents()
        hScroller.knobProportion = min(1, vw / cw)
        hScroller.doubleValue = cw > vw ? Double(offset.x / (cw - vw)) : 0
        vScroller.knobProportion = min(1, vh / ch)
        vScroller.doubleValue = ch > vh ? Double(offset.y / (ch - vh)) : 0
    }

    @objc private func scrollerAction(_ s: NSScroller) {
        let (cw, vw, ch, vh) = extents()
        let g = geo
        var o = offset
        let vertical = s === vScroller
        let line = vertical ? g.rows.defaultSize * 3 : g.cols.defaultSize
        let page = vertical ? vh * 0.9 : vw * 0.9
        switch s.hitPart {
        case .decrementLine: vertical ? (o.y -= line) : (o.x -= line)
        case .incrementLine: vertical ? (o.y += line) : (o.x += line)
        case .decrementPage: vertical ? (o.y -= page) : (o.x -= page)
        case .incrementPage: vertical ? (o.y += page) : (o.x += page)
        default:
            if vertical { o.y = CGFloat(s.doubleValue) * (ch - vh) } else { o.x = CGFloat(s.doubleValue) * (cw - vw) }
        }
        setOffset(o)
    }

    override func scrollWheel(with e: NSEvent) {
        var dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
        if e.modifierFlags.contains(.command) && !e.hasPreciseScrollingDeltas {
            zoom *= dy > 0 ? 1.1 : 1 / 1.1
            return
        }
        if !e.hasPreciseScrollingDeltas { dx *= geo.cols.defaultSize / 2; dy *= geo.rows.defaultSize * 3 }
        if e.modifierFlags.contains(.shift) && dx == 0 { dx = dy; dy = 0 }
        setOffset(CGPoint(x: offset.x - dx / zoom, y: offset.y - dy / zoom))
    }

    override func magnify(with e: NSEvent) { zoom *= 1 + e.magnification }

    private func ensureVisible(_ c: CellRef) {
        let g = geo
        var o = offset
        let fw = frozenW(g), fh = frozenH(g)
        let visW = viewSize.width - headerW - fw, visH = viewSize.height - headerH - fh
        if c.col >= g.fc {
            let cx = g.cols.pos(c.col) - fw, w = g.cols.size(c.col)
            if cx < o.x { o.x = cx } else if cx + w > o.x + visW { o.x = min(cx, cx + w - visW) }
        }
        if c.row >= g.fr {
            let cy = g.rows.pos(c.row) - fh, h = g.rows.size(c.row)
            if cy < o.y { o.y = cy } else if cy + h > o.y + visH { o.y = min(cy, cy + h - visH) }
        }
        setOffset(o)
    }

    // MARK: - Data

    private func data(rows: ClosedRange<Int>, cols: ClosedRange<Int>) -> CellData {
        if dataKey != (sheet, book.version) { dataCache.removeAll(); dataKey = (sheet, book.version) }
        let k = RegionKey(r0: rows.lowerBound, r1: rows.upperBound, c0: cols.lowerBound, c1: cols.upperBound)
        if let d = dataCache[k] { return d }
        // Over-fetch a few columns on both sides so overflowing text knows its neighbours.
        let c0 = max(0, cols.lowerBound - 8), c1 = min(Sheet.maxCols - 1, cols.upperBound + 8)
        let d = CellData(book.viewport(sheet: sheet, rows: rows, cols: c0...c1))
        if dataCache.count > 16 { dataCache.removeAll() }
        dataCache[k] = d
        return d
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let t0 = CACurrentMediaTime()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let g = geo
        let scale = (window?.backingScaleFactor ?? 2) * zoom
        let hair = 1 / scale
        let size = viewSize
        let bg = painter.background

        bg.setFill()
        bounds.fill()
        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)

        // Row header width follows the number of digits on screen (like Excel).
        let rowsScrolled = scrolledRows(g)
        let digits = String(rowsScrolled.upperBound + 1).count
        headerW = max(30, (CGFloat(digits) * 7.5 + 12).rounded())
        let colsScrolled = scrolledCols(g)

        let fw = frozenW(g), fh = frozenH(g)
        let gridColor = NSColor.separatorColor.blended(withFraction: 0.45, of: bg) ?? .separatorColor
        var rowParts: [(ClosedRange<Int>, CGFloat, CGFloat)] = []
        if g.fr > 0 { rowParts.append((0...(g.fr - 1), headerH, headerH + fh)) }
        rowParts.append((rowsScrolled, headerH + fh, size.height))
        var colParts: [(ClosedRange<Int>, CGFloat, CGFloat)] = []
        if g.fc > 0 { colParts.append((0...(g.fc - 1), headerW, headerW + fw)) }
        colParts.append((colsScrolled, headerW + fw, size.width))

        for (rr, y0, y1) in rowParts {
            for (cc, x0, x1) in colParts {
                let clip = CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
                guard clip.width > 0, clip.height > 0 else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: clip).setClip()
                painter.paint(rows: rr, cols: cc, data: data(rows: rr, cols: cc), merges: g.merges, showGrid: g.showGrid,
                              hair: hair, clip: clip, gridColor: gridColor,
                              rect: { self.cellRect($0, $1, g) }, colWidth: { g.cols.size($0) }, rowHeight: { g.rows.size($0) })
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        let gridArea = CGRect(x: headerW, y: headerH, width: size.width - headerW, height: size.height - headerH)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: gridArea).setClip()
        drawOverlays(g, hair: hair, gridArea: gridArea)
        // Freeze lines
        NSColor.secondaryLabelColor.setFill()
        if g.fr > 0 { CGRect(x: headerW, y: headerH + fh - hair, width: size.width, height: max(hair, 1)).fill() }
        if g.fc > 0 { CGRect(x: headerW + fw - hair, y: headerH, width: max(hair, 1), height: size.height).fill() }
        NSGraphicsContext.restoreGraphicsState()

        drawHeaders(g, rowParts: rowParts, colParts: colParts, hair: hair, size: size)
        ctx.restoreGState()

        Perf.shared.frameDrawn(ms: (CACurrentMediaTime() - t0) * 1000)
    }

    private func clipped(_ r: CGRect, _ area: CGRect) -> CGRect { r.intersection(area.insetBy(dx: -4, dy: -4)) }

    private func drawOverlays(_ g: Geo, hair: CGFloat, gridArea: CGRect) {
        let accent = NSColor.controlAccentColor
        // Formula references being edited
        let sheetName = book.sheetNames[safe: sheet]
        for (i, ref) in refHighlights.enumerated() where (ref.sheet == nil && editSheet == sheet) || ref.sheet == sheetName {
            let color = FormulaText.palette[i % FormulaText.palette.count]
            let r = clipped(rangeRect(ref.range, g), gridArea)
            guard !r.isNull else { continue }
            color.withAlphaComponent(0.10).setFill(); r.fill()
            color.setStroke()
            let p = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
            p.lineWidth = 1.5
            p.stroke()
        }

        // Selection
        var sel = selection
        if isEditing && editSheet != sheet { sel = GridRange(r0: -1, c0: -1, r1: -1, c1: -1) }
        if sel.r0 >= 0 {
            let selRect = clipped(rangeRect(sel, g), gridArea)
            if !selRect.isNull {
                let activeRect = rangeRect(mergeAt(active, g) ?? GridRange(active, active), g)
                if !sel.isSingle && mergeAt(active, g) != sel {
                    let path = NSBezierPath(rect: selRect)
                    path.appendRect(activeRect)
                    path.windingRule = .evenOdd
                    accent.withAlphaComponent(0.14).setFill()
                    path.fill()
                }
                accent.setStroke()
                let border = NSBezierPath(rect: selRect.insetBy(dx: 0, dy: 0).offsetBy(dx: -hair, dy: -hair))
                border.lineWidth = 2
                border.stroke()
                if !isEditing {
                    let h = fillHandleRect(g)
                    painter.background.setFill(); h.insetBy(dx: -1, dy: -1).fill()
                    accent.setFill(); h.fill()
                }
            }
        }
        if let t = fillTarget {
            let r = clipped(rangeRect(t, g), gridArea)
            let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
            p.setLineDash([3, 2], count: 2, phase: 0)
            NSColor.secondaryLabelColor.setStroke()
            p.stroke()
        }
        if let cut = cutRange, cut.sheet == sheet {
            let r = clipped(rangeRect(cut.range, g), gridArea)
            let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
            p.lineWidth = 1.5
            p.setLineDash([4, 3], count: 2, phase: 0)
            accent.setStroke()
            p.stroke()
        }
        if let p = resizePreview {
            NSColor.controlAccentColor.setFill()
            if p.isCol { CGRect(x: x(p.index, g) + p.size - 1, y: headerH, width: 1, height: viewSize.height).fill() }
            else { CGRect(x: headerW, y: y(p.index, g) + p.size - 1, width: viewSize.width, height: 1).fill() }
        }
    }

    private func fillHandleRect(_ g: Geo) -> CGRect {
        let r = rangeRect(selection, g)
        return CGRect(x: r.maxX - 4, y: r.maxY - 4, width: 7, height: 7)
    }

    private func drawHeaders(_ g: Geo, rowParts: [(ClosedRange<Int>, CGFloat, CGFloat)], colParts: [(ClosedRange<Int>, CGFloat, CGFloat)],
                             hair: CGFloat, size: CGSize) {
        let headerBG = NSColor.windowBackgroundColor
        let line = NSColor.separatorColor
        let accent = NSColor.controlAccentColor
        let font = NSFont.systemFont(ofSize: 11)
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let selected: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: accent]
        let sel = selection
        let fullCols = sel.isFullColumns, fullRows = sel.isFullRows

        headerBG.setFill()
        CGRect(x: 0, y: 0, width: size.width, height: headerH).fill()
        CGRect(x: 0, y: 0, width: headerW, height: size.height).fill()

        for (cc, x0, x1) in colParts {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: CGRect(x: x0, y: 0, width: max(0, x1 - x0), height: headerH)).setClip()
            for c in cc where g.cols.size(c) > 0 {
                var r = cellRect(0, c, g); r.origin.y = 0; r.size.height = headerH
                let isSel = c >= sel.c0 && c <= sel.c1
                if isSel {
                    accent.withAlphaComponent(fullCols ? 0.35 : 0.15).setFill(); r.fill()
                    accent.setFill(); CGRect(x: r.minX, y: headerH - 2, width: r.width, height: 2).fill()
                }
                line.setFill(); CGRect(x: r.maxX - hair, y: 3, width: hair, height: headerH - 3).fill()
                let s = columnName(c) as NSString
                let a = isSel ? selected : normal
                let sz = s.size(withAttributes: a)
                if sz.width < r.width { s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: (headerH - sz.height) / 2), withAttributes: a) }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        for (rr, y0, y1) in rowParts {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: CGRect(x: 0, y: y0, width: headerW, height: max(0, y1 - y0))).setClip()
            for r in rr where g.rows.size(r) > 0 {
                var rect = cellRect(r, 0, g); rect.origin.x = 0; rect.size.width = headerW
                let isSel = r >= sel.r0 && r <= sel.r1
                if isSel {
                    accent.withAlphaComponent(fullRows ? 0.35 : 0.15).setFill(); rect.fill()
                    accent.setFill(); CGRect(x: headerW - 2, y: rect.minY, width: 2, height: rect.height).fill()
                }
                line.setFill(); CGRect(x: 3, y: rect.maxY - hair, width: headerW - 3, height: hair).fill()
                let s = String(r + 1) as NSString
                let a = isSel ? selected : normal
                let sz = s.size(withAttributes: a)
                if sz.height < rect.height + 2 {
                    s.draw(at: CGPoint(x: headerW - 5 - sz.width, y: rect.minY + (rect.height - sz.height) / 2), withAttributes: a)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        line.setFill()
        CGRect(x: 0, y: headerH - hair, width: size.width, height: hair).fill()
        CGRect(x: headerW - hair, y: 0, width: hair, height: size.height).fill()
        // Corner: select-all triangle
        let tri = NSBezierPath()
        tri.move(to: CGPoint(x: headerW - 4, y: headerH - 12))
        tri.line(to: CGPoint(x: headerW - 4, y: headerH - 4))
        tri.line(to: CGPoint(x: headerW - 12, y: headerH - 4))
        tri.close()
        NSColor.tertiaryLabelColor.setFill()
        tri.fill()
    }

    // MARK: - Selection

    private func mergeAt(_ c: CellRef, _ g: Geo) -> GridRange? { g.merges.first { $0.contains(c) } }

    /// Grows a range so merges are never cut in half.
    private func expandForMerges(_ r: GridRange, _ g: Geo) -> GridRange {
        var out = r
        var changed = true
        var guardCount = 0
        while changed && guardCount < 20 {
            changed = false
            guardCount += 1
            for m in g.merges where m.intersects(out) {
                let u = out.union(m)
                if u != out { out = u; changed = true }
            }
        }
        return out
    }

    private func notifySelection() {
        delegate?.gridSelectionChanged(self)
        window?.invalidateCursorRects(for: self)
    }

    func select(_ c: CellRef, extend: Bool = false, scroll: Bool = true) {
        let g = geo
        let c = CellRef(row: min(max(c.row, 0), Sheet.maxRows - 1), col: min(max(c.col, 0), Sheet.maxCols - 1))
        if extend {
            cursor = c
            selection = expandForMerges(GridRange(active, cursor), g)
        } else {
            active = c; cursor = c
            if let m = mergeAt(c, g) { active = CellRef(row: m.r0, col: m.c0); selection = m } else { selection = GridRange(c, c) }
        }
        if scroll { ensureVisible(extend ? cursor : active) }
        needsDisplay = true
        updateScrollers()
        notifySelection()
    }

    func select(range r: GridRange, active a: CellRef? = nil) {
        selection = r
        active = a ?? CellRef(row: r.r0, col: r.c0)
        cursor = CellRef(row: r.r1, col: r.c1)
        ensureVisible(active)
        needsDisplay = true
        notifySelection()
    }

    private func move(_ dr: Int, _ dc: Int, extend: Bool = false) {
        let g = geo
        if extend {
            select(CellRef(row: g.rows.step(cursor.row, by: dr), col: g.cols.step(cursor.col, by: dc)), extend: true)
            return
        }
        // Leave a merged cell from its far edge.
        var from = active
        if let m = mergeAt(active, g) {
            if dr > 0 { from.row = m.r1 }
            if dc > 0 { from.col = m.c1 }
        }
        select(CellRef(row: g.rows.step(from.row, by: dr), col: g.cols.step(from.col, by: dc)))
    }

    /// Enter/Tab inside a multi-cell selection move the active cell within it (Excel behaviour).
    private func advance(_ dr: Int, _ dc: Int) {
        let s = selection
        guard !s.isSingle, mergeAt(active, geo) != s else { move(dr, dc); return }
        var r = active.row + dr, c = active.col + dc
        if r > s.r1 { r = s.r0; c += 1 } else if r < s.r0 { r = s.r1; c -= 1 }
        if c > s.c1 { c = s.c0; r = dr == 0 ? r + 1 : r } else if c < s.c0 { c = s.c1; r = dr == 0 ? r - 1 : r }
        if r > s.r1 { r = s.r0 } else if r < s.r0 { r = s.r1 }
        active = CellRef(row: r, col: c)
        ensureVisible(active)
        needsDisplay = true
        notifySelection()
    }

    private var pageRows: Int { max(1, Int((viewSize.height - headerH) / geo.rows.defaultSize) - 1) }

    override func keyDown(with e: NSEvent) {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = flags.contains(.shift), cmd = flags.contains(.command), opt = flags.contains(.option)
        let from = shift ? cursor : active
        func jump(_ dr: Int, _ dc: Int) {
            select(book.jump(sheet: sheet, from: from, dr: dr, dc: dc), extend: shift)
        }
        switch e.keyCode {
        case 126: cmd ? jump(-1, 0) : move(-1, 0, extend: shift)
        case 125: cmd ? jump(1, 0) : move(1, 0, extend: shift)
        case 123: cmd ? jump(0, -1) : move(0, -1, extend: shift)
        case 124: cmd ? jump(0, 1) : move(0, 1, extend: shift)
        case 36, 76:
            if cmd || opt { beginEditing(.edit, initial: nil) } else { advance(shift ? -1 : 1, 0) }
        case 48: advance(0, shift ? -1 : 1)
        case 116: // page up
            if opt { setOffset(CGPoint(x: offset.x - viewSize.width * 0.8, y: offset.y)) } else { move(-pageRows, 0, extend: shift) }
        case 121:
            if opt { setOffset(CGPoint(x: offset.x + viewSize.width * 0.8, y: offset.y)) } else { move(pageRows, 0, extend: shift) }
        case 115: // home
            select(CellRef(row: cmd ? 0 : from.row, col: 0), extend: shift)
        case 119: // end
            if cmd { let g = geo; select(CellRef(row: g.maxRow, col: g.maxCol), extend: shift) }
        case 51, 117:
            clearSelection()
        case 120: beginEditing(.edit, initial: nil) // F2
        case 53: // esc
            if cutRange != nil { cutRange = nil; needsDisplay = true }
        default:
            if cmd || flags.contains(.control) || (e.specialKey != nil && e.specialKey != .delete) {
                super.keyDown(with: e)
            } else {
                // Start typing: hand the very same key event to the field editor so IME and dead keys work.
                beginEditing(.enter, initial: "")
                if let ed = overlay?.currentEditor() { ed.keyDown(with: e) }
            }
        }
    }

    // MARK: - Mouse

    private func logical(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: p.x / zoom, y: p.y / zoom)
    }

    /// Column whose right edge is within 4pt of x (in the column header).
    private func colBoundary(at p: CGPoint, _ g: Geo) -> Int? {
        let c = cellAt(CGPoint(x: p.x, y: headerH + 1), g).col
        for cand in [c, c - 1] where cand >= 0 {
            let right = x(cand, g) + g.cols.size(cand)
            if abs(p.x - right) <= 4 { return cand }
        }
        return nil
    }
    private func rowBoundary(at p: CGPoint, _ g: Geo) -> Int? {
        let r = cellAt(CGPoint(x: headerW + 1, y: p.y), g).row
        for cand in [r, r - 1] where cand >= 0 {
            let bottom = y(cand, g) + g.rows.size(cand)
            if abs(p.y - bottom) <= 3 { return cand }
        }
        return nil
    }

    override func resetCursorRects() {
        let g = geo
        let z = zoom
        func scaled(_ r: CGRect) -> CGRect { CGRect(x: r.minX * z, y: r.minY * z, width: r.width * z, height: r.height * z) }
        if !isEditing { addCursorRect(scaled(fillHandleRect(g).insetBy(dx: -3, dy: -3)), cursor: .crosshair) }
        for c in scrolledCols(g).lowerBound...scrolledCols(g).upperBound {
            let right = x(c, g) + g.cols.size(c)
            addCursorRect(scaled(CGRect(x: right - 4, y: 0, width: 8, height: headerH)), cursor: .resizeLeftRight)
        }
        if g.fc > 0 {
            for c in 0..<g.fc { addCursorRect(scaled(CGRect(x: x(c, g) + g.cols.size(c) - 4, y: 0, width: 8, height: headerH)), cursor: .resizeLeftRight) }
        }
        for r in scrolledRows(g) {
            let bottom = y(r, g) + g.rows.size(r)
            addCursorRect(scaled(CGRect(x: 0, y: bottom - 3, width: headerW, height: 6)), cursor: .resizeUpDown)
        }
    }

    override func mouseDown(with e: NSEvent) {
        let p = logical(e)
        let g = geo
        let shift = e.modifierFlags.contains(.shift)
        let inColHeader = p.y < headerH && p.x > headerW
        let inRowHeader = p.x < headerW && p.y > headerH

        // Formula point mode: clicks insert references instead of moving the selection.
        if let s = session, s.canPoint() {
            let c = cellAt(p, g)
            if inColHeader {
                s.pointAnchor = CellRef(row: 0, col: c.col); s.pointCursor = CellRef(row: Sheet.maxRows - 1, col: c.col)
            } else if inRowHeader {
                s.pointAnchor = CellRef(row: c.row, col: 0); s.pointCursor = CellRef(row: c.row, col: Sheet.maxCols - 1)
            } else {
                if !(shift && s.pointAnchor != nil) { s.pointAnchor = c }
                s.pointCursor = c
            }
            insertPointedReference()
            drag = .point
            return
        }

        if isEditing { commitEditing(move: nil) }
        window?.makeFirstResponder(self)

        if inColHeader, let c = colBoundary(at: p, g) {
            if e.clickCount == 2 { autofitColumns(c...c); return }
            drag = .resizeCol(c, p.x, g.cols.size(c))
            return
        }
        if inRowHeader, let r = rowBoundary(at: p, g) {
            if e.clickCount == 2 { setRowHeights(r...r, px: nil); return }
            drag = .resizeRow(r, p.y, g.rows.size(r))
            return
        }
        if !inColHeader && !inRowHeader && fillHandleRect(g).insetBy(dx: -3, dy: -3).contains(p) && p.x > headerW && p.y > headerH {
            drag = .fill(selection)
            return
        }
        if p.x < headerW && p.y < headerH {
            selectAll(nil)
            return
        }
        let c = cellAt(p, g)
        if inColHeader {
            if !shift { active = CellRef(row: 0, col: c.col) }
            cursor = CellRef(row: Sheet.maxRows - 1, col: c.col)
            selection = GridRange(r0: 0, c0: min(active.col, c.col), r1: Sheet.maxRows - 1, c1: max(active.col, c.col))
            active = CellRef(row: scrolledRows(g).lowerBound == g.fr ? 0 : 0, col: shift ? active.col : c.col)
            drag = .cols(shift ? selection.c0 == c.col ? selection.c1 : selection.c0 : c.col)
        } else if inRowHeader {
            if !shift { active = CellRef(row: c.row, col: 0) }
            cursor = CellRef(row: c.row, col: Sheet.maxCols - 1)
            selection = GridRange(r0: min(active.row, c.row), c0: 0, r1: max(active.row, c.row), c1: Sheet.maxCols - 1)
            drag = .rows(shift ? (selection.r0 == c.row ? selection.r1 : selection.r0) : c.row)
        } else {
            if e.clickCount == 2 && !shift {
                select(c)
                beginEditing(.edit, initial: nil)
                return
            }
            select(c, extend: shift, scroll: false)
            drag = .select
        }
        needsDisplay = true
        notifySelection()
    }

    override func mouseDragged(with e: NSEvent) {
        lastDragEvent = e
        handleDrag(e)
        let p = convert(e.locationInWindow, from: nil)
        let outside = p.x < headerW * zoom || p.y < headerH * zoom || p.x > bounds.width - scrollerW || p.y > bounds.height - scrollerW
        if outside && autoscrollTimer == nil {
            autoscrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.autoscrollTick() }
        } else if !outside {
            autoscrollTimer?.invalidate(); autoscrollTimer = nil
        }
    }

    private func autoscrollTick() {
        guard let e = lastDragEvent else { return }
        let p = convert(e.locationInWindow, from: nil)
        var o = offset
        let g = geo
        let speed: (CGFloat) -> CGFloat = { d in min(8, 1 + d / 20) }
        if p.y > bounds.height - scrollerW { o.y += g.rows.defaultSize * speed(p.y - bounds.height + scrollerW) }
        else if p.y < headerH * zoom { o.y -= g.rows.defaultSize * speed(headerH * zoom - p.y) }
        if p.x > bounds.width - scrollerW { o.x += g.cols.defaultSize * 0.5 * speed(p.x - bounds.width + scrollerW) }
        else if p.x < headerW * zoom { o.x -= g.cols.defaultSize * 0.5 * speed(headerW * zoom - p.x) }
        setOffset(o)
        handleDrag(e)
    }

    private func handleDrag(_ e: NSEvent) {
        let p = logical(e)
        let g = geo
        let c = cellAt(CGPoint(x: max(p.x, headerW + 1), y: max(p.y, headerH + 1)), g)
        switch drag {
        case .select:
            if cursor != c { select(c, extend: true, scroll: false) }
        case .cols(let start):
            selection = GridRange(r0: 0, c0: min(start, c.col), r1: Sheet.maxRows - 1, c1: max(start, c.col))
            cursor = CellRef(row: Sheet.maxRows - 1, col: c.col)
            needsDisplay = true; notifySelection()
        case .rows(let start):
            selection = GridRange(r0: min(start, c.row), c0: 0, r1: max(start, c.row), c1: Sheet.maxCols - 1)
            cursor = CellRef(row: c.row, col: Sheet.maxCols - 1)
            needsDisplay = true; notifySelection()
        case .fill(let s):
            let down = c.row - s.r1, right = c.col - s.c1, up = s.r0 - c.row, left = s.c0 - c.col
            let best = max(down, right, up, left)
            if best <= 0 { fillTarget = nil }
            else if best == down { fillTarget = GridRange(r0: s.r0, c0: s.c0, r1: c.row, c1: s.c1) }
            else if best == right { fillTarget = GridRange(r0: s.r0, c0: s.c0, r1: s.r1, c1: c.col) }
            else if best == up { fillTarget = GridRange(r0: c.row, c0: s.c0, r1: s.r1, c1: s.c1) }
            else { fillTarget = GridRange(r0: s.r0, c0: c.col, r1: s.r1, c1: s.c1) }
            needsDisplay = true
        case .resizeCol(let i, let x0, let s0):
            resizePreview = (true, i, max(0, (s0 + p.x - x0).rounded()))
            needsDisplay = true
        case .resizeRow(let i, let y0, let s0):
            resizePreview = (false, i, max(0, (s0 + p.y - y0).rounded()))
            needsDisplay = true
        case .point:
            guard let s = session else { return }
            if s.pointAnchor?.row == 0 && s.pointCursor?.row == Sheet.maxRows - 1 {
                s.pointCursor = CellRef(row: Sheet.maxRows - 1, col: c.col)
            } else if s.pointAnchor?.col == 0 && s.pointCursor?.col == Sheet.maxCols - 1 {
                s.pointCursor = CellRef(row: c.row, col: Sheet.maxCols - 1)
            } else {
                s.pointCursor = c
            }
            insertPointedReference()
        case .none: break
        }
    }

    override func mouseUp(with e: NSEvent) {
        autoscrollTimer?.invalidate(); autoscrollTimer = nil
        lastDragEvent = nil
        switch drag {
        case .fill(let s):
            if let t = fillTarget {
                if t.r1 > s.r1 { book.autofill(sheet: sheet, s, toRow: t.r1, toCol: nil) }
                else if t.c1 > s.c1 { book.autofill(sheet: sheet, s, toRow: nil, toCol: t.c1) }
                else if t.r0 < s.r0 { book.autofill(sheet: sheet, s, toRow: t.r0, toCol: nil) }
                else if t.c0 < s.c0 { book.autofill(sheet: sheet, s, toRow: nil, toCol: t.c0) }
                select(range: t, active: active)
                contentChanged()
            }
        case .resizeCol(let i, _, _):
            if let p = resizePreview {
                let sel = selection
                let range = sel.isFullColumns && i >= sel.c0 && i <= sel.c1 ? sel.c0...sel.c1 : i...i
                resizePreview = nil
                if p.size == 0 { book.setHidden(sheet: sheet, rows: false, range.lowerBound, range.upperBound, hidden: true) }
                else { book.setColumnWidth(sheet: sheet, range.lowerBound, range.upperBound, px: p.size / colUnit) }
                contentChanged()
            }
        case .resizeRow(let i, _, _):
            if let p = resizePreview {
                let sel = selection
                let range = sel.isFullRows && i >= sel.r0 && i <= sel.r1 ? sel.r0...sel.r1 : i...i
                resizePreview = nil
                if p.size == 0 { book.setHidden(sheet: sheet, rows: true, range.lowerBound, range.upperBound, hidden: true) }
                else { book.setRowHeight(sheet: sheet, range.lowerBound, range.upperBound, px: p.size / rowUnit) }
                contentChanged()
            }
        default: break
        }
        resizePreview = nil
        fillTarget = nil
        drag = .none
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = logical(event)
        let g = geo
        let c = cellAt(p, g)
        if isEditing { return nil }
        if p.y < headerH && p.x > headerW {
            if !(selection.isFullColumns && c.col >= selection.c0 && c.col <= selection.c1) {
                select(range: GridRange(r0: 0, c0: c.col, r1: Sheet.maxRows - 1, c1: c.col), active: CellRef(row: 0, col: c.col))
            }
            return Menus.columnMenu()
        }
        if p.x < headerW && p.y > headerH {
            if !(selection.isFullRows && c.row >= selection.r0 && c.row <= selection.r1) {
                select(range: GridRange(r0: c.row, c0: 0, r1: c.row, c1: Sheet.maxCols - 1), active: CellRef(row: c.row, col: 0))
            }
            return Menus.rowMenu()
        }
        if !selection.contains(c) { select(c, scroll: false) }
        return Menus.cellMenu()
    }

    // MARK: - Editing

    private func editorFrame() -> CGRect {
        let g = geo
        let r = rangeRect(mergeAt(editTarget, g) ?? GridRange(editTarget, editTarget), g)
        return CGRect(x: r.minX * zoom, y: r.minY * zoom, width: r.width * zoom, height: r.height * zoom).insetBy(dx: 1, dy: 1)
    }

    private func positionEditor() {
        guard let f = overlay else { return }
        var fr = editorFrame()
        // Grow to the right with the text, like Excel.
        let w = (f.stringValue as NSString).size(withAttributes: [.font: f.font as Any]).width + 14
        fr.size.width = min(max(fr.width, w), bounds.width - scrollerW - fr.minX)
        f.frame = fr
    }

    private func startSession(field: NSTextField) {
        let s = FormulaSession(field: field)
        s.onRefs = { [weak self] refs in self?.refHighlights = refs }
        session = s
        editField = field
        editTarget = active
        editSheet = sheet
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.isEditing else { return e }
            if e.keyCode == 118 { self.cycleReference(); return nil } // F4
            return e
        }
        delegate?.gridModeChanged(self)
    }

    func beginEditing(_ mode: EditMode, initial: String?) {
        guard !isEditing else { return }
        ensureVisible(active)
        let f = CellEditorField(frame: .zero)
        f.isBordered = false
        f.focusRingType = .none
        f.drawsBackground = true
        f.backgroundColor = painter.background
        f.textColor = .textColor
        let st = book.style(sheet: sheet, row: active.row, col: active.col)
        f.font = painter.font(size: st.fontSize, bold: st.bold, italic: st.italic).withSize(CGFloat(st.fontSize) * painter.fontScale * zoom)
        f.delegate = self
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.stringValue = initial ?? book.input(sheet: sheet, row: active.row, col: active.col)
        f.wantsLayer = true
        f.layer?.borderColor = NSColor.controlAccentColor.cgColor
        f.layer?.borderWidth = 2
        overlay = f
        editMode = mode
        startSession(field: f)
        addSubview(f)
        positionEditor()
        window?.makeFirstResponder(f)
        if let ed = f.currentEditor() {
            ed.selectedRange = NSRange(location: (f.stringValue as NSString).length, length: 0)
        }
        session?.textChanged()
        delegate?.gridEditingTextChanged(self, text: f.stringValue)
        needsDisplay = true
    }

    /// The formula bar started editing: it becomes the editor for the active cell.
    func beginBarEditing(_ field: NSTextField) {
        guard !isEditing else { return }
        editMode = .edit
        startSession(field: field)
        session?.textChanged()
    }

    func setEditorText(_ s: String) {
        guard let f = overlay else { return }
        f.stringValue = s
        positionEditor()
    }

    private func finishEditing() {
        session?.end()
        session = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        let f = editField
        editField = nil
        if let o = overlay { overlay = nil; o.removeFromSuperview() }
        if f != nil { window?.makeFirstResponder(self) }
        refHighlights = []
        delegate?.gridModeChanged(self)
        needsDisplay = true
    }

    func commitEditing(move delta: (Int, Int)?, fillSelection: Bool = false) {
        guard let f = editField else { return }
        let text = (f.currentEditor()?.string) ?? f.stringValue
        let target = editTarget, targetSheet = editSheet
        finishEditing()
        if sheet != targetSheet { sheet = targetSheet }
        if fillSelection && !selection.isSingle {
            book.setInput(sheet: sheet, row: target.row, col: target.col, text)
            if let c = book.copy(sheet: sheet, GridRange(target, target)) {
                _ = book.pasteInternal(sheet: sheet, selection, token: c.token, cut: false)
            }
        } else {
            book.setInput(sheet: sheet, row: target.row, col: target.col, text)
        }
        if text.contains("\n") || book.style(sheet: sheet, row: target.row, col: target.col).wrap {
            if text.contains("\n") && !book.style(sheet: sheet, row: target.row, col: target.col).wrap {
                // Alt+Return line breaks turn on wrapping, like Excel.
                book.setStyle(sheet: sheet, GridRange(target, target), path: "alignment.wrap_text", value: "true")
            }
            fitRowHeights(target.row...target.row)
        }
        contentChanged()
        if let d = delta { advance(d.0, d.1) } else { notifySelection() }
    }

    func cancelEditing() {
        guard isEditing else { return }
        let targetSheet = editSheet
        finishEditing()
        if sheet != targetSheet { sheet = targetSheet }
        notifySelection()
    }

    private func insertPointedReference() {
        guard let s = session, let a = s.pointAnchor, let c = s.pointCursor else { return }
        let r = GridRange(a, c)
        var ref = r.a1
        if sheet != editSheet {
            let name = book.sheetNames[safe: sheet] ?? ""
            let quoted = name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil ? name : "'\(name.replacingOccurrences(of: "'", with: "''"))'"
            ref = "\(quoted)!\(ref)"
        }
        s.insertReference(ref)
        if let o = overlay { delegate?.gridEditingTextChanged(self, text: o.stringValue); positionEditor() }
        ensureVisible(c)
    }

    private func cycleReference() {
        guard let s = session, let tv = s.textView else { return }
        let sel = tv.selectedRange()
        guard let (text, newSel) = book.cycleReference(s.text, start: sel.location, end: NSMaxRange(sel)) else { return }
        tv.string = text
        tv.setSelectedRange(newSel)
        s.textChanged()
        delegate?.gridEditingTextChanged(self, text: text)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard control === editField, let s = session else { return false }
        if s.handle(sel) { return true }
        let cmd = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        let opt = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            if opt && !cmd { textView.insertNewlineIgnoringFieldEditor(nil); return true } // ⌥↩ new line in cell
            commitEditing(move: cmd ? nil : (1, 0), fillSelection: cmd)
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            textView.insertNewlineIgnoringFieldEditor(nil); return true
        case #selector(NSResponder.insertTab(_:)): commitEditing(move: (0, 1)); return true
        case #selector(NSResponder.insertBacktab(_:)): commitEditing(move: (0, -1)); return true
        case #selector(NSResponder.cancelOperation(_:)): cancelEditing(); return true
        default: break
        }
        guard editMode == .enter else { return false }
        let moves: [Selector: (Int, Int, Bool)] = [
            #selector(NSResponder.moveUp(_:)): (-1, 0, false), #selector(NSResponder.moveDown(_:)): (1, 0, false),
            #selector(NSResponder.moveLeft(_:)): (0, -1, false), #selector(NSResponder.moveRight(_:)): (0, 1, false),
            #selector(NSResponder.moveUpAndModifySelection(_:)): (-1, 0, true),
            #selector(NSResponder.moveDownAndModifySelection(_:)): (1, 0, true),
            #selector(NSResponder.moveLeftAndModifySelection(_:)): (0, -1, true),
            #selector(NSResponder.moveRightAndModifySelection(_:)): (0, 1, true),
        ]
        guard let m = moves[sel] else { return false }
        if s.canPoint() {
            // Excel "Point" mode: arrows pick a reference.
            let g = geo
            let base = s.pointCursor ?? editTarget
            let next = CellRef(row: g.rows.step(base.row, by: m.0), col: g.cols.step(base.col, by: m.1))
            if !m.2 || s.pointAnchor == nil { s.pointAnchor = next }
            s.pointCursor = next
            insertPointedReference()
            return true
        }
        if m.2 { return false }
        commitEditing(move: (m.0, m.1))
        return true
    }

    func controlTextDidChange(_ n: Notification) {
        guard let f = n.object as? NSTextField, f === editField else { return }
        session?.textChanged()
        if f === overlay {
            positionEditor()
            delegate?.gridEditingTextChanged(self, text: f.stringValue)
        }
    }

    func controlTextDidBeginEditing(_ n: Notification) {
        if let f = n.object as? NSTextField, f !== overlay, !isEditing { beginBarEditing(f) }
    }

    func controlTextDidEndEditing(_ n: Notification) {
        guard let f = n.object as? NSTextField, f === editField else { return }
        commitEditing(move: nil)
    }

    // MARK: - Commands

    func contentChanged() {
        invalidateData()
        delegate?.gridContentChanged(self)
        notifySelection()
    }

    private func commitIfEditing() { if isEditing { commitEditing(move: nil) } }

    func clearSelection() {
        commitIfEditing()
        book.clear(sheet: sheet, selection)
        contentChanged()
    }

    @objc func undo(_ sender: Any?) { commitIfEditing(); book.undo(); contentChanged() }
    @objc func redo(_ sender: Any?) { commitIfEditing(); book.redo(); contentChanged() }
    @objc func delete(_ sender: Any?) { clearSelection() }
    @objc func clearAll(_ sender: Any?) { book.clear(sheet: sheet, selection); book.clearFormats(sheet: sheet, selection); contentChanged() }
    @objc func clearFormatsAction(_ sender: Any?) { book.clearFormats(sheet: sheet, selection); contentChanged() }

    @objc override func selectAll(_ sender: Any?) {
        // ⌘A once selects the data region, twice the whole sheet (Excel).
        let region = book.currentRegion(sheet: sheet, row: active.row, col: active.col)
        if selection != region && !region.isSingle {
            select(range: region, active: active)
        } else {
            select(range: GridRange(r0: 0, c0: 0, r1: Sheet.maxRows - 1, c1: Sheet.maxCols - 1), active: active)
        }
    }

    @objc func copy(_ sender: Any?) { copySelection(cut: false) }
    @objc func cut(_ sender: Any?) { copySelection(cut: true) }

    private func copySelection(cut: Bool) {
        commitIfEditing()
        guard let (text, token) = book.copy(sheet: sheet, selection) else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.declareTypes([.string, GridView.pasteboardType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setString("\(token)", forType: GridView.pasteboardType)
        cutRange = cut ? (sheet, selection) : nil
        needsDisplay = true
    }

    @objc func paste(_ sender: Any?) {
        commitIfEditing()
        let pb = NSPasteboard.general
        if let t = pb.string(forType: GridView.pasteboardType), let token = UInt64(t),
           let text = pb.string(forType: .string) {
            let lines = text.components(separatedBy: "\n")
            let h = max(1, lines.count), w = max(1, lines.map { $0.components(separatedBy: "\t").count }.max() ?? 1)
            let target = selection.isSingle ? GridRange(r0: active.row, c0: active.col, r1: active.row + h - 1, c1: active.col + w - 1) : selection
            if book.pasteInternal(sheet: sheet, target, token: token, cut: cutRange != nil) {
                cutRange = nil
                select(range: target, active: active)
                contentChanged()
                return
            }
        }
        pasteValues(sender)
    }

    /// Paste plain text (values) — also used for data copied from other apps.
    @objc func pasteValues(_ sender: Any?) {
        commitIfEditing()
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return }
        let normalized = s.replacingOccurrences(of: "\r\n", with: "\n")
        book.pasteText(sheet: sheet, row: active.row, col: active.col, normalized)
        let lines = normalized.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        let w = lines.map { $0.components(separatedBy: "\t").count }.max() ?? 1
        cutRange = nil
        select(range: GridRange(r0: active.row, c0: active.col, r1: active.row + lines.count - 1, c1: active.col + w - 1), active: active)
        contentChanged()
    }

    // Rows / columns
    @objc func insertRows(_ sender: Any?) {
        book.insertRows(sheet: sheet, at: selection.r0, count: selection.isFullColumns ? 1 : selection.rows); contentChanged()
    }
    @objc func insertColumns(_ sender: Any?) {
        book.insertCols(sheet: sheet, at: selection.c0, count: selection.isFullRows ? 1 : selection.cols); contentChanged()
    }
    @objc func deleteRows(_ sender: Any?) {
        guard !selection.isFullColumns else { NSSound.beep(); return }
        book.deleteRows(sheet: sheet, at: selection.r0, count: selection.rows)
        select(CellRef(row: selection.r0, col: active.col)); contentChanged()
    }
    @objc func deleteColumns(_ sender: Any?) {
        guard !selection.isFullRows else { NSSound.beep(); return }
        book.deleteCols(sheet: sheet, at: selection.c0, count: selection.cols)
        select(CellRef(row: active.row, col: selection.c0)); contentChanged()
    }
    @objc func hideRows(_ sender: Any?) { book.setHidden(sheet: sheet, rows: true, selection.r0, selection.r1, hidden: true); contentChanged() }
    @objc func unhideRows(_ sender: Any?) {
        book.setHidden(sheet: sheet, rows: true, max(0, selection.r0 - 1), selection.r1 + 1, hidden: false); contentChanged()
    }
    @objc func hideColumns(_ sender: Any?) { book.setHidden(sheet: sheet, rows: false, selection.c0, selection.c1, hidden: true); contentChanged() }
    @objc func unhideColumns(_ sender: Any?) {
        book.setHidden(sheet: sheet, rows: false, max(0, selection.c0 - 1), selection.c1 + 1, hidden: false); contentChanged()
    }

    @objc func columnWidth(_ sender: Any?) {
        let g = geo
        askNumber(L("Column width"), value: g.cols.size(selection.c0) / colUnit / 9) { [weak self] v in
            guard let self else { return }
            self.book.setColumnWidth(sheet: self.sheet, self.selection.c0, self.selection.c1, px: CGFloat(v) * 9)
            self.contentChanged()
        }
    }
    @objc func rowHeight(_ sender: Any?) {
        let g = geo
        askNumber(L("Row height"), value: g.rows.size(selection.r0) / rowUnit / 1.5625) { [weak self] v in
            guard let self else { return }
            self.book.setRowHeight(sheet: self.sheet, self.selection.r0, self.selection.r1, px: CGFloat(v) * 1.5625)
            self.contentChanged()
        }
    }
    @objc func autofitSelectedColumns(_ sender: Any?) { autofitColumns(selection.c0...selection.c1) }

    func autofitColumns(_ cols: ClosedRange<Int>) {
        let g = geo
        let lastRow = min(g.maxRow, 20_000)
        let rows = (selection.isFullColumns || selection.isSingle) ? 0...lastRow : selection.r0...min(selection.r1, lastRow)
        let cells = book.viewport(sheet: sheet, rows: rows, cols: cols.lowerBound...min(cols.upperBound, g.maxCol + 1))
        var widths: [Int: CGFloat] = [:]
        for c in cells where !c.text.isEmpty {
            let w = (c.text as NSString).size(withAttributes: painter.attrs(c)).width + 10
            widths[c.col] = max(widths[c.col] ?? 0, w)
        }
        for c in cols where c <= g.maxCol {
            let w = max(widths[c] ?? g.cols.defaultSize, 16)
            book.setColumnWidth(sheet: sheet, c, c, px: w / colUnit)
        }
        contentChanged()
    }

    private func setRowHeights(_ rows: ClosedRange<Int>, px: CGFloat?) {
        book.setRowHeight(sheet: sheet, rows.lowerBound, rows.upperBound, px: px ?? 25)
        contentChanged()
    }

    private func askNumber(_ title: String, value: CGFloat, _ done: @escaping (Double) -> Void) {
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = title
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        f.stringValue = String(format: "%.2f", value)
        a.accessoryView = f
        a.addButton(withTitle: L("OK"))
        a.addButton(withTitle: L("Cancel"))
        a.window.initialFirstResponder = f
        a.beginSheetModal(for: w) { r in
            if r == .alertFirstButtonReturn, let v = Double(f.stringValue.replacingOccurrences(of: ",", with: ".")), v >= 0 { done(v) }
        }
    }

    // Freeze panes
    @objc func freezePanes(_ sender: Any?) {
        let g = geo
        if g.fr > 0 || g.fc > 0 { book.setFrozen(sheet: sheet, rows: 0, cols: 0) }
        else { book.setFrozen(sheet: sheet, rows: active.row, cols: active.col) }
        offset = .zero
        contentChanged()
    }
    @objc func freezeTopRow(_ sender: Any?) { book.setFrozen(sheet: sheet, rows: 1, cols: 0); offset = .zero; contentChanged() }
    @objc func freezeFirstColumn(_ sender: Any?) { book.setFrozen(sheet: sheet, rows: 0, cols: 1); offset = .zero; contentChanged() }
    @objc func toggleGridlines(_ sender: Any?) { book.setShowGrid(sheet: sheet, !geo.showGrid); contentChanged() }

    // Data
    private func sortRange() -> GridRange {
        var r = selection.isSingle ? book.currentRegion(sheet: sheet, row: active.row, col: active.col) : selection
        let g = geo
        r.r1 = min(r.r1, g.maxRow)
        r.c1 = min(r.c1, g.maxCol)
        return r
    }
    /// A first row of text over a column of numbers is a header (Excel's guess).
    private func hasHeader(_ r: GridRange) -> Bool {
        guard r.rows > 1 else { return false }
        let first = book.viewport(sheet: sheet, rows: r.r0...r.r0, cols: r.c0...r.c1)
        let second = book.viewport(sheet: sheet, rows: (r.r0 + 1)...(r.r0 + 1), cols: r.c0...r.c1)
        let firstText = first.filter { !$0.text.isEmpty }.allSatisfy { $0.kind == 0 } && !first.isEmpty
        let secondHasNumbers = second.contains { $0.kind == 1 }
        let firstBold = first.contains { $0.bold }
        return firstText && (secondHasNumbers || firstBold)
    }
    @objc func sortAscending(_ sender: Any?) { sort(true) }
    @objc func sortDescending(_ sender: Any?) { sort(false) }
    private func sort(_ asc: Bool) {
        commitIfEditing()
        var r = sortRange()
        if hasHeader(r) { r.r0 += 1 }
        guard r.rows > 1 else { return }
        book.sort(sheet: sheet, r, keyCol: active.col, ascending: asc)
        contentChanged()
    }

    @objc func fillDown(_ sender: Any?) {
        guard selection.rows > 1 else { return }
        let src = GridRange(r0: selection.r0, c0: selection.c0, r1: selection.r0, c1: selection.c1)
        if let c = book.copy(sheet: sheet, src) {
            _ = book.pasteInternal(sheet: sheet, GridRange(r0: selection.r0 + 1, c0: selection.c0, r1: selection.r1, c1: selection.c1), token: c.token, cut: false)
        }
        contentChanged()
    }
    @objc func fillRight(_ sender: Any?) {
        guard selection.cols > 1 else { return }
        let src = GridRange(r0: selection.r0, c0: selection.c0, r1: selection.r1, c1: selection.c0)
        if let c = book.copy(sheet: sheet, src) {
            _ = book.pasteInternal(sheet: sheet, GridRange(r0: selection.r0, c0: selection.c0 + 1, r1: selection.r1, c1: selection.c1), token: c.token, cut: false)
        }
        contentChanged()
    }

    @objc func mergeAndCenter(_ sender: Any?) {
        if geo.merges.contains(where: { $0.intersects(selection) }) {
            book.merge(sheet: sheet, selection, mode: 0)
        } else {
            guard !selection.isSingle else { return }
            book.merge(sheet: sheet, selection, mode: 2)
        }
        contentChanged()
    }

    // Formatting (also used by the toolbar)
    func toggleStyle(_ path: String) {
        commitIfEditing()
        let st = book.style(sheet: sheet, row: active.row, col: active.col)
        let on: Bool
        switch path {
        case "font.b": on = !st.bold
        case "font.i": on = !st.italic
        case "font.u": on = !st.underline
        case "font.strike": on = !st.strike
        case "alignment.wrap_text": on = !st.wrap
        default: on = true
        }
        setStyle(path, on ? "true" : "false")
    }

    func setStyle(_ path: String, _ value: String) {
        commitIfEditing()
        book.setStyle(sheet: sheet, selection, path: path, value: value)
        if path == "alignment.wrap_text" || path == "font.size" { fitRowHeights(selection.r0...min(selection.r1, selection.r0 + 500)) }
        contentChanged()
    }

    /// Grows rows so wrapped or larger text fits (Excel's automatic row height). Never shrinks below default.
    func fitRowHeights(_ rows: ClosedRange<Int>) {
        let g = geo
        let lastRow = min(rows.upperBound, g.maxRow)
        guard rows.lowerBound <= lastRow else { return }
        let cells = book.viewport(sheet: sheet, rows: rows.lowerBound...lastRow, cols: 0...g.maxCol)
        var need: [Int: CGFloat] = [:]
        for c in cells where !c.text.isEmpty && (c.wrap || c.fontSize > 11) {
            let a = painter.attrs(c)
            let h: CGFloat
            if c.wrap {
                h = (c.text as NSString).boundingRect(with: CGSize(width: max(10, g.cols.size(c.col) - 6), height: .greatestFiniteMagnitude),
                                                      options: [.usesLineFragmentOrigin], attributes: a).height + 4
            } else {
                h = (c.text as NSString).size(withAttributes: a).height + 4
            }
            need[c.row] = max(need[c.row] ?? 0, h)
        }
        for (r, h) in need where h > g.rows.size(r) + 0.5 {
            book.setRowHeight(sheet: sheet, r, r, px: (h / rowUnit).rounded(.up))
        }
    }

    func setBorder(_ kind: String, style: String = "thin") {
        commitIfEditing()
        book.setBorder(sheet: sheet, selection, kind: kind, style: style)
        contentChanged()
    }

    /// Σ: =SUM over the numbers above (or to the left of) the active cell.
    func autoSum(_ function: String = "SUM") {
        commitIfEditing()
        let r = active.row, c = active.col
        func contiguous(_ cells: [VCell], _ key: (VCell) -> Int, from start: Int) -> Int? {
            let numeric = Set(cells.filter { $0.kind == 1 }.map(key))
            var i = start
            while i >= 0 && numeric.contains(i) { i -= 1 }
            return i == start ? nil : i + 1
        }
        let function = Workbook.localName(function)
        var formula = "=\(function)()"
        if r > 0, let top = contiguous(book.viewport(sheet: sheet, rows: max(0, r - 5000)...(r - 1), cols: c...c), { $0.row }, from: r - 1) {
            formula = "=\(function)(\(columnName(c))\(top + 1):\(columnName(c))\(r))"
        } else if c > 0, let left = contiguous(book.viewport(sheet: sheet, rows: r...r, cols: max(0, c - 500)...(c - 1)), { $0.col }, from: c - 1) {
            formula = "=\(function)(\(columnName(left))\(r + 1):\(columnName(c - 1))\(r + 1))"
        }
        beginEditing(.edit, initial: formula)
    }

    // Zoom
    @objc func zoomIn(_ sender: Any?) { zoom = (zoom * 1.25 * 20).rounded() / 20 }
    @objc func zoomOut(_ sender: Any?) { zoom = (zoom / 1.25 * 20).rounded() / 20 }
    @objc func actualSize(_ sender: Any?) { zoom = 1 }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return book.canUndo && !isEditing
        case #selector(redo(_:)): return book.canRedo && !isEditing
        case #selector(freezePanes(_:)):
            let g = geo
            item.title = g.fr > 0 || g.fc > 0 ? L("Unfreeze Panes") : L("Freeze Panes")
            return true
        case #selector(toggleGridlines(_:)):
            item.state = geo.showGrid ? .on : .off
            return true
        case #selector(mergeAndCenter(_:)):
            item.title = geo.merges.contains(where: { $0.intersects(selection) }) ? L("Unmerge Cells") : L("Merge & Center")
            return true
        default: return true
        }
    }

    // Find support
    func find(_ q: String, flags: UInt32) -> Bool {
        guard let hit = book.find(sheet: sheet, after: active, q, flags: flags) else { NSSound.beep(); return false }
        select(hit)
        return true
    }

    // MARK: - Benchmark

    func startAutoScroll(frames: Int) {
        autoScrollFrames = frames
        frameStamps.removeAll(keepingCapacity: true)
        Perf.shared.beginRecording()
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ l: CADisplayLink) {
        frameStamps.append(l.timestamp)
        if frameStamps.count >= autoScrollFrames {
            l.invalidate()
            Perf.shared.endRecording(frameStamps: frameStamps, refresh: 1 / (l.targetTimestamp - l.timestamp))
            return
        }
        setOffset(CGPoint(x: offset.x + 2, y: offset.y + geo.rows.defaultSize * 3))
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
