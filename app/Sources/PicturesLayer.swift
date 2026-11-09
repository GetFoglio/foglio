import AppKit

/// Owns the picture views of the grid's current sheet. They live in the chart layer's panes (frozen / scrolling
/// part), stacked with the charts in the sheet's drawing order. Positions come from the anchors, like charts.
final class PictureLayer {
    private weak var grid: GridView?
    let book: Workbook
    private(set) var views: [PictureView] = []
    private(set) var pictures: [PictureInfo] = []
    private var order: [DrawingRef] = []
    private(set) var selectedIndex: Int?

    init(grid: GridView) {
        self.grid = grid
        self.book = grid.book
        grid.registerForDraggedTypes(PicturesUI.dropTypes)
    }

    var sheet: Int { grid?.sheet ?? 0 }
    var zoom: CGFloat { grid?.zoom ?? 1 }
    var gridView: GridView? { grid }

    /// Re-reads the pictures of the sheet (the chart layer calls this before laying out).
    func reloadData() {
        let list = book.pictures(sheet: sheet)
        pictures = list
        order = list.isEmpty ? [] : book.drawingOrder(sheet: sheet)
        if let s = selectedIndex, s >= list.count { selectedIndex = nil }
        while views.count > list.count { views.removeLast().removeFromSuperview() }
        while views.count < list.count { views.append(PictureView(layer: self)) }
        for (v, p) in zip(views, list) {
            if v.info != p { v.info = p; v.endCrop(commit: false) }
            v.isSelected = p.index == selectedIndex
        }
    }

    /// Logical rectangle of a picture: anchored corner + size; in-cell pictures fitted in their cell.
    func logicalRect(_ p: PictureInfo, _ g: ChartGridGeometry) -> CGRect {
        if p.inCell {
            let cell = CGRect(x: g.x(p.from.col), y: g.y(p.from.row), width: g.colW(p.from.col), height: g.rowH(p.from.row))
            return PictureLayer.fit(aspect: p.size, in: cell.insetBy(dx: 1.5, dy: 1.5))
        }
        let x = g.x(p.from.col) + CGFloat(p.from.fx) * g.colW(p.from.col)
        let y = g.y(p.from.row) + CGFloat(p.from.fy) * g.rowH(p.from.row)
        let k = displayScale(p, g)
        return CGRect(x: x, y: y, width: p.size.width * k, height: p.size.height * k)
    }

    /// Pictures are sized in Excel pixels (EMU), but the grid has its own units: columns are wider than Excel's and
    /// rows with a custom height a little shorter (1.25 pt per point instead of 4/3). Drawn at their EMU size, the
    /// pictures of a sheet with tall custom rows (product photos in a price list) would spill over the next row's
    /// text. A floating picture is therefore shrunk, aspect ratio kept, to fit the cells its anchor spans (`from`…`to`,
    /// the corner where its size ends in the file's geometry). Never enlarged; 0 when a two-cell picture's cells are
    /// all hidden (Excel hides it too).
    func displayScale(_ p: PictureInfo, _ g: ChartGridGeometry) -> CGFloat {
        guard !p.inCell, p.size.width > 0, p.size.height > 0 else { return 1 }
        let box = g.rect(from: p.from, to: p.to)
        if p.editAs == .twoCell && (box.width <= 0 || box.height <= 0) { return 0 }
        guard box.width > 0, box.height > 0 else { return 1 }
        let k = min(box.width / p.size.width, box.height / p.size.height)
        return k < 0.995 ? k : 1
    }

    static func fit(aspect s: CGSize, in r: CGRect) -> CGRect {
        guard s.width > 0, s.height > 0, r.width > 0, r.height > 0 else { return CGRect(x: r.midX, y: r.midY, width: 0, height: 0) }
        let k = min(r.width / s.width, r.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    /// Positions the views (the chart layer calls this after placing the charts) and stacks them with the charts.
    func layout() {
        guard let grid else { return }
        let g = grid.chartGeometry()
        let panes = (main: grid.chartLayer.mainPane, scroll: grid.chartLayer.scrollPane)
        for v in views where v.dragging == nil {
            guard let p = v.info else { continue }
            let pane = p.from.row >= g.fr && p.from.col >= g.fc ? panes.scroll : panes.main
            if v.superview !== pane { pane.addSubview(v) }
            v.logical = logicalRect(p, g)
            place(v)
        }
        applyOrder()
    }

    /// Sets the frame of a view from its logical rectangle(s).
    func place(_ v: PictureView) {
        guard let pane = v.superview else { return }
        let z = zoom
        func toPane(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * z - pane.frame.minX, y: r.minY * z - pane.frame.minY, width: r.width * z, height: r.height * z)
        }
        let pic = toPane(v.cropState?.frame ?? v.logical)
        var all = pic
        if let c = v.cropState { all = all.union(toPane(c.full)) }
        let f = all.insetBy(dx: -PictureView.margin, dy: -PictureView.margin).integral
        let picRect = pic.offsetBy(dx: -f.minX, dy: -f.minY)
        let fullRect = v.cropState.map { toPane($0.full).offsetBy(dx: -f.minX, dy: -f.minY) }
        // Scrolling only moves the frame: redraw when what is drawn inside it changes. Compared with a tolerance:
        // the same rectangle recomputed after a scroll differs in the last bits (fractional anchors), and an exact
        // comparison redrew (and re-decoded) every picture on screen at every scroll step.
        func moved(_ a: CGRect?, _ b: CGRect?) -> Bool {
            guard let a, let b else { return (a == nil) != (b == nil) }
            return abs(a.minX - b.minX) > 0.01 || abs(a.minY - b.minY) > 0.01 || abs(a.width - b.width) > 0.01 || abs(a.height - b.height) > 0.01
        }
        if moved(picRect, v.pictureRect) || moved(fullRect, v.fullRect) || f.size != v.frame.size {
            v.needsDisplay = true
            v.pictureRect = picRect
            v.fullRect = fullRect
        }
        if v.frame != f { v.frame = f }
    }

    /// Orders the subviews of each pane like the drawing objects of the sheet (back to front).
    private func applyOrder() {
        guard let grid, !views.isEmpty else { return }
        let charts = grid.chartLayer.views
        let ordered: [NSView] = order.compactMap {
            switch $0 {
            case .chart(let i): return charts[safe: i]
            case .picture(let i): return views[safe: i]
            }
        }
        for pane in [grid.chartLayer.mainPane, grid.chartLayer.scrollPane] {
            let current = pane.subviews
            var desired = ordered.filter { $0.superview === pane }
            desired += current.filter { v in !desired.contains { $0 === v } }
            if desired.count == current.count && !zip(desired, current).allSatisfy({ $0 === $1 }) {
                pane.subviews = desired
            }
        }
    }

    // MARK: Selection and edits

    func select(_ index: Int?, focus: Bool = true) {
        selectedIndex = index
        for v in views { v.isSelected = v.info?.index == index }
        if let i = index, focus, let v = views[safe: i] { grid?.window?.makeFirstResponder(v) }
    }

    func deselect(_ v: PictureView) {
        if selectedIndex == v.info?.index { selectedIndex = nil }
        v.isSelected = false
    }

    /// After an engine change: mark the document edited and redraw (keeps the selection).
    func committed() { grid?.contentChanged() }

    func update(_ index: Int, _ patch: PicturePatch, data: Data? = nil) {
        guard book.updatePicture(sheet: sheet, index: index, patch, data: data) else { NSSound.beep(); return }
        committed()
    }

    func delete(index: Int) {
        guard book.deletePicture(sheet: sheet, index: index) else { return }
        selectedIndex = nil
        committed()
        if let grid { grid.window?.makeFirstResponder(grid) }
    }

    /// Moves/resizes picture `index` to a logical rectangle (in-cell pictures: to the cell under its centre).
    func setRect(index: Int, logical r: CGRect, crop: PictureCrop? = nil) {
        guard let grid, let p = pictures[safe: index] else { return }
        let g = grid.chartGeometry()
        if p.inCell {
            let c = g.cellAt(CGPoint(x: r.midX, y: r.midY))
            var patch = PicturePatch(from: ChartCorner(row: c.row, col: c.col, fy: 0, fx: 0), crop: crop)
            if crop != nil { patch.size = r.size }   // new aspect ratio
            update(index, patch)
            return
        }
        // Back to the picture's own size (see displayScale): what the user dragged is what stays on screen.
        let k = displayScale(p, g)
        let size = k > 0 ? CGSize(width: r.width / k, height: r.height / k) : r.size
        update(index, PicturePatch(from: g.corner(at: r.origin), size: size, crop: crop))
    }

    func restack(index: Int, _ how: String) {
        guard book.restack(sheet: sheet, .picture(index), how) else { return }
        committed()
    }

    /// Converts a rectangle of a pane (view points) into logical grid coordinates.
    func logicalRect(_ r: CGRect, in pane: NSView) -> CGRect {
        guard let grid else { return r }
        let gr = grid.convert(r, from: pane)
        return CGRect(x: gr.minX / zoom, y: gr.minY / zoom, width: gr.width / zoom, height: gr.height / zoom)
    }
}

/// One picture on the sheet: draws it (cropped), selection handles, move/resize by dragging, crop mode,
/// keyboard (arrows nudge, Delete, Esc, Return), clipboard and a context menu.
final class PictureView: NSView, NSMenuItemValidation {
    static let margin: CGFloat = 8
    private unowned let pictureLayer: PictureLayer
    var info: PictureInfo? { didSet { if info != oldValue { needsDisplay = true; setAccessibilityLabel(info.map { $0.descr.isEmpty ? $0.name : $0.descr }) } } }
    var isSelected = false { didSet { if isSelected != oldValue { if !isSelected { endCrop(commit: true) }; needsDisplay = true; window?.invalidateCursorRects(for: self) } } }
    /// Picture rectangle in logical grid coordinates (set by the layer).
    var logical = CGRect.zero
    /// Where the picture (crop frame) and, in crop mode, the whole image are drawn, in view coordinates.
    var pictureRect = CGRect.zero
    var fullRect: CGRect?
    /// Crop mode: the crop frame and the uncropped image, logical coordinates.
    private(set) var cropState: (frame: CGRect, full: CGRect)?

    enum Drag { case move, resize(left: Bool, right: Bool, top: Bool, bottom: Bool), crop(left: Bool, right: Bool, top: Bool, bottom: Bool), pan }
    private(set) var dragging: Drag?
    private var dragStart = CGPoint.zero
    private var startLogical = CGRect.zero
    private var startCrop: (frame: CGRect, full: CGRect)?
    private var moved = false

    init(layer: PictureLayer) {
        pictureLayer = layer
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    var isCropping: Bool { cropState != nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return nil }
        let p = convert(point, from: sv)
        if isCropping { return bounds.contains(p) ? self : nil }
        if pictureRect.contains(p) { return self }
        if isSelected && handle(at: p) != nil { return self }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let info, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = window?.backingScaleFactor ?? 2
        if let full = fullRect {
            // Crop mode: the whole image dimmed, the part that stays at full strength.
            PictureRenderer.draw(info, book: pictureLayer.book, sheet: pictureLayer.sheet, in: full, ctx: ctx, scale: scale, uncropped: true)
            ctx.saveGState()
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.addRect(full); ctx.addRect(pictureRect)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
            drawCropHandles()
            return
        }
        PictureRenderer.draw(info, book: pictureLayer.book, sheet: pictureLayer.sheet, in: pictureRect, ctx: ctx, scale: scale)
        if isSelected { drawSelection() }
    }

    private func handleRects(_ r: CGRect) -> [(CGRect, Bool, Bool, Bool, Bool)] {
        let s: CGFloat = 8
        func h(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s) }
        return [
            (h(r.minX, r.minY), true, false, true, false), (h(r.midX, r.minY), false, false, true, false),
            (h(r.maxX, r.minY), false, true, true, false), (h(r.maxX, r.midY), false, true, false, false),
            (h(r.maxX, r.maxY), false, true, false, true), (h(r.midX, r.maxY), false, false, false, true),
            (h(r.minX, r.maxY), true, false, false, true), (h(r.minX, r.midY), true, false, false, false),
        ]
    }

    private func handle(at p: CGPoint) -> Drag? {
        guard let info, !info.inCell || isCropping else { return nil }
        guard let (_, l, r, t, b) = handleRects(pictureRect).first(where: { $0.0.insetBy(dx: -3, dy: -3).contains(p) }) else { return nil }
        return isCropping ? .crop(left: l, right: r, top: t, bottom: b) : .resize(left: l, right: r, top: t, bottom: b)
    }

    private func drawSelection() {
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        let frame = NSBezierPath(rect: pictureRect.insetBy(dx: -0.5, dy: -0.5))
        frame.lineWidth = 1
        frame.stroke()
        guard info?.inCell == false else { return }
        for (r, _, _, _, _) in handleRects(pictureRect) {
            let p = NSBezierPath(ovalIn: r)
            NSColor.white.setFill(); p.fill()
            NSColor(white: 0.45, alpha: 1).setStroke(); p.lineWidth = 1; p.stroke()
        }
    }

    /// Excel-like crop handles: black L-shaped corners and bars on the edges, outlined in white.
    private func drawCropHandles() {
        let r = pictureRect, len: CGFloat = 12, w: CGFloat = 4
        let path = NSBezierPath()
        func bar(_ rect: CGRect) { path.appendRect(rect) }
        // corners
        bar(CGRect(x: r.minX - w, y: r.minY - w, width: len + w, height: w)); bar(CGRect(x: r.minX - w, y: r.minY, width: w, height: len))
        bar(CGRect(x: r.maxX - len, y: r.minY - w, width: len + w, height: w)); bar(CGRect(x: r.maxX, y: r.minY, width: w, height: len))
        bar(CGRect(x: r.minX - w, y: r.maxY, width: len + w, height: w)); bar(CGRect(x: r.minX - w, y: r.maxY - len, width: w, height: len))
        bar(CGRect(x: r.maxX - len, y: r.maxY, width: len + w, height: w)); bar(CGRect(x: r.maxX, y: r.maxY - len, width: w, height: len))
        // edges
        bar(CGRect(x: r.midX - len / 2, y: r.minY - w, width: len, height: w)); bar(CGRect(x: r.midX - len / 2, y: r.maxY, width: len, height: w))
        bar(CGRect(x: r.minX - w, y: r.midY - len / 2, width: w, height: len)); bar(CGRect(x: r.maxX, y: r.midY - len / 2, width: w, height: len))
        NSColor.white.setStroke(); path.lineWidth = 1.5; path.stroke()
        NSColor.black.setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let outline = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); outline.lineWidth = 1; outline.stroke()
    }

    override func resetCursorRects() {
        guard isSelected, info?.inCell == false || isCropping else { return }
        for (r, l, rt, t, b) in handleRects(pictureRect) {
            let cursor: NSCursor
            if (l || rt) && !(t || b) { cursor = .resizeLeftRight }
            else if (t || b) && !(l || rt) { cursor = .resizeUpDown }
            else if #available(macOS 15.0, *) {
                cursor = .frameResize(position: t ? (l ? .topLeft : .topRight) : (l ? .bottomLeft : .bottomRight), directions: .all)
            } else { cursor = .crosshair }
            addCursorRect(r.insetBy(dx: -3, dy: -3), cursor: cursor)
        }
    }

    // MARK: Crop mode

    /// Crop mode on: the frame stays, the whole image shows around it.
    func beginCrop() {
        guard let info, !isCropping else { return }
        let c = info.crop
        let fw = logical.width / c.visibleW, fh = logical.height / c.visibleH
        let full = CGRect(x: logical.minX - fw * CGFloat(c.l) / 100_000, y: logical.minY - fh * CGFloat(c.t) / 100_000, width: fw, height: fh)
        cropState = (logical, full)
        pictureLayer.place(self)
        window?.invalidateCursorRects(for: self)
    }

    /// Crop mode off; with `commit`, the new frame and crop become one undo step.
    func endCrop(commit: Bool) {
        guard let state = cropState, let info else { cropState = nil; return }
        cropState = nil
        window?.invalidateCursorRects(for: self)
        guard commit else { pictureLayer.place(self); return }
        let f = state.frame, full = state.full
        let crop = PictureCrop(l: Int(((f.minX - full.minX) / full.width * 100_000).rounded()),
                               t: Int(((f.minY - full.minY) / full.height * 100_000).rounded()),
                               r: Int(((full.maxX - f.maxX) / full.width * 100_000).rounded()),
                               b: Int(((full.maxY - f.maxY) / full.height * 100_000).rounded()))
        if crop == info.crop && f.origin == logical.origin { pictureLayer.place(self); return }
        pictureLayer.setRect(index: info.index, logical: f, crop: crop)
    }

    // MARK: Mouse

    override func mouseDown(with e: NSEvent) {
        guard let info else { return }
        if !isSelected || window?.firstResponder !== self { pictureLayer.select(info.index) }
        let p = convert(e.locationInWindow, from: nil)
        if isCropping {
            dragging = handle(at: p) ?? (pictureRect.contains(p) || fullRect?.contains(p) == true ? .pan : nil)
            if dragging == nil { endCrop(commit: true); return }
        } else {
            dragging = handle(at: p) ?? .move
        }
        dragStart = e.locationInWindow
        startLogical = logical
        startCrop = cropState
        moved = false
    }

    override func mouseDragged(with e: NSEvent) {
        guard let d = dragging, info != nil else { return }
        let z = pictureLayer.zoom
        let dx = (e.locationInWindow.x - dragStart.x) / z, dy = -(e.locationInWindow.y - dragStart.y) / z
        if !moved && abs(dx * z) < 2 && abs(dy * z) < 2 { return }
        moved = true
        let minSize: CGFloat = 8
        switch d {
        case .move:
            logical = startLogical.offsetBy(dx: dx, dy: dy)
            NSCursor.closedHand.set()
        case let .resize(l, rt, t, b):
            var r = startLogical
            if l { let x = min(r.maxX - minSize, r.minX + dx); r.size.width = r.maxX - x; r.origin.x = x }
            if rt { r.size.width = max(minSize, r.width + dx) }
            if t { let y = min(r.maxY - minSize, r.minY + dy); r.size.height = r.maxY - y; r.origin.y = y }
            if b { r.size.height = max(minSize, r.height + dy) }
            // Corners keep the aspect ratio; ⇧ frees them (Excel's picture default).
            let corner = (l || rt) && (t || b)
            let shift = (GridView.testModifiers ?? e.modifierFlags).contains(.shift)
            if corner && !shift && startLogical.width > 0 && startLogical.height > 0 {
                let kw = r.width / startLogical.width, kh = r.height / startLogical.height
                let k = abs(kw - 1) >= abs(kh - 1) ? kw : kh   // follow the side that moved most
                let w = max(minSize, startLogical.width * k), h = max(minSize, startLogical.height * k)
                r = CGRect(x: l ? startLogical.maxX - w : startLogical.minX, y: t ? startLogical.maxY - h : startLogical.minY, width: w, height: h)
            }
            logical = r
        case let .crop(l, rt, t, b):
            guard let start = startCrop else { return }
            var f = start.frame
            let full = start.full
            if l { f.origin.x = min(f.maxX - minSize, max(full.minX, f.minX + dx)); f.size.width = start.frame.maxX - f.minX }
            if rt { f.size.width = max(minSize, min(full.maxX, f.maxX + dx) - f.minX) }
            if t { f.origin.y = min(f.maxY - minSize, max(full.minY, f.minY + dy)); f.size.height = start.frame.maxY - f.minY }
            if b { f.size.height = max(minSize, min(full.maxY, f.maxY + dy) - f.minY) }
            cropState = (f, full)
        case .pan:
            // The image moves under the crop frame (Excel), never leaving a gap.
            guard let (f, full) = startCrop else { return }
            let mx = min(max(dx, f.maxX - full.maxX), f.minX - full.minX)
            let my = min(max(dy, f.maxY - full.maxY), f.minY - full.minY)
            cropState = (f, full.offsetBy(dx: mx, dy: my))
        }
        pictureLayer.place(self)
    }

    override func mouseUp(with e: NSEvent) {
        defer { dragging = nil; moved = false; NSCursor.arrow.set() }
        guard moved, let info, let d = dragging else { return }
        dragging = nil
        switch d {
        case .crop, .pan: pictureLayer.place(self)   // committed when crop mode ends
        case .move, .resize: pictureLayer.setRect(index: info.index, logical: logical)
        }
    }

    override func scrollWheel(with e: NSEvent) { pictureLayer.gridView?.scrollWheel(with: e) }

    // MARK: Keyboard

    override func becomeFirstResponder() -> Bool {
        if let i = info?.index, pictureLayer.selectedIndex != i { pictureLayer.select(i, focus: false) }
        return true
    }
    override func resignFirstResponder() -> Bool {
        pictureLayer.deselect(self)
        return true
    }

    override func keyDown(with e: NSEvent) {
        guard let info else { return }
        let step: CGFloat = (GridView.testModifiers ?? e.modifierFlags).contains(.shift) ? 10 : 1
        switch e.keyCode {
        case 51, 117: if !isCropping { deletePicture(nil) }                 // delete, forward delete
        case 53:                                                             // escape
            if isCropping { endCrop(commit: true) }
            else { pictureLayer.select(nil); window?.makeFirstResponder(pictureLayer.gridView) }
        case 36, 76: if isCropping { endCrop(commit: true) }                // return
        case 123, 124, 125, 126:                                             // arrows
            guard !isCropping else { return }
            let d: (CGFloat, CGFloat) = [123: (-1, 0), 124: (1, 0), 125: (0, 1), 126: (0, -1)][e.keyCode]!
            if info.inCell {
                let r = logical.offsetBy(dx: d.0 * logical.width, dy: d.1 * logical.height)
                pictureLayer.setRect(index: info.index, logical: r)
            } else {
                pictureLayer.setRect(index: info.index, logical: logical.offsetBy(dx: d.0 * step, dy: d.1 * step))
            }
        default: break
        }
    }

    // MARK: Commands

    @objc func deletePicture(_ sender: Any?) { if let i = info?.index { pictureLayer.delete(index: i) } }
    @objc func delete(_ sender: Any?) { deletePicture(sender) }
    @objc func copy(_ sender: Any?) { if let info { PicturesUI.copyToPasteboard(info, book: pictureLayer.book, sheet: pictureLayer.sheet) } }
    @objc func cut(_ sender: Any?) { copy(sender); deletePicture(sender) }
    @objc func paste(_ sender: Any?) { pictureLayer.gridView?.paste(sender) }

    @objc func cropPicture(_ sender: Any?) { isCropping ? endCrop(commit: true) : beginCrop() }
    @objc func resetPictureCrop(_ sender: Any?) {
        guard let info, !info.crop.isEmpty else { return }
        endCrop(commit: false)
        let c = info.crop
        let fw = logical.width / c.visibleW, fh = logical.height / c.visibleH
        let full = CGRect(x: logical.minX - fw * CGFloat(c.l) / 100_000, y: logical.minY - fh * CGFloat(c.t) / 100_000, width: fw, height: fh)
        pictureLayer.setRect(index: info.index, logical: full, crop: PictureCrop())
    }
    /// Reset Size: the image's own size (pixels at 96 dpi, as Excel), cropping kept.
    @objc func resetPictureSize(_ sender: Any?) {
        guard let info, let px = PictureRenderer.pixelSize(info, book: pictureLayer.book, sheet: pictureLayer.sheet) else { return }
        endCrop(commit: true)
        let size = CGSize(width: px.width * info.crop.visibleW, height: px.height * info.crop.visibleH)
        if info.inCell { pictureLayer.update(info.index, PicturePatch(size: size)) }
        else { pictureLayer.update(info.index, PicturePatch(from: info.from, size: size)) }
    }
    @objc func placePictureInCell(_ sender: Any?) {
        guard let info, !info.inCell, let grid = pictureLayer.gridView else { return }
        endCrop(commit: true)
        // The cell under the top-left corner, like Excel.
        let c = grid.chartGeometry().cellAt(CGPoint(x: logical.minX + 1, y: logical.minY + 1))
        pictureLayer.update(info.index, PicturePatch(from: ChartCorner(row: c.row, col: c.col, fy: 0, fx: 0), size: logical.size, inCell: true))
    }
    @objc func placePictureOverCells(_ sender: Any?) {
        guard let info, info.inCell, let grid = pictureLayer.gridView else { return }
        let g = grid.chartGeometry()
        pictureLayer.update(info.index, PicturePatch(from: g.corner(at: logical.origin), size: logical.size, editAs: .oneCell, inCell: false))
    }
    @objc func editAltText(_ sender: Any?) {
        guard let info, let w = window else { return }
        PicturesUI.altText(for: info, on: w) { [weak self] text in
            guard let self, let i = self.info?.index else { return }
            self.pictureLayer.update(i, PicturePatch(descr: text))
        }
    }
    @objc func bringForward(_ sender: Any?) { if let i = info?.index { pictureLayer.restack(index: i, "forward") } }
    @objc func sendBackward(_ sender: Any?) { if let i = info?.index { pictureLayer.restack(index: i, "backward") } }
    @objc func bringToFront(_ sender: Any?) { if let i = info?.index { pictureLayer.restack(index: i, "front") } }
    @objc func sendToBack(_ sender: Any?) { if let i = info?.index { pictureLayer.restack(index: i, "back") } }
    @objc func compressPictures(_ sender: Any?) {
        guard let grid = pictureLayer.gridView, let w = window else { return }
        endCrop(commit: true)
        CompressPicturesSheet(grid: grid, selected: info?.index).begin(on: w)
    }
    @objc func changePicture(_ sender: Any?) {
        guard let info, let w = window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let url = panel.url, let self else { return }
            PicturesUI.replace(info, with: url, layer: self.pictureLayer)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let info else { return nil }
        if !isSelected || window?.firstResponder !== self { pictureLayer.select(info.index) }
        let m = NSMenu()
        for it in PicturesUI.contextItems() { it.target = self; m.addItem(it) }
        return m
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let info else { return false }
        switch item.action {
        case #selector(cropPicture(_:)): item.state = isCropping ? .on : .off; return true
        case #selector(resetPictureCrop(_:)): return !info.crop.isEmpty
        case #selector(placePictureInCell(_:)): return !info.inCell
        case #selector(placePictureOverCells(_:)): return info.inCell
        case #selector(paste(_:)): return PicturesUI.pasteboardHasPicture() || NSPasteboard.general.string(forType: .string) != nil
        default: return true
        }
    }
}

/// Bring Forward / Send Backward for charts too (they share the stacking order with pictures).
extension ChartView {
    private var host: (GridView, Int)? {
        guard let grid = superview?.superview as? GridView, let i = info?.index else { return nil }
        return (grid, i)
    }
    private func restackChart(_ how: String) {
        guard let (grid, i) = host, grid.book.restack(sheet: grid.sheet, .chart(i), how) else { return }
        grid.contentChanged()
    }
    @objc func bringForward(_ sender: Any?) { restackChart("forward") }
    @objc func sendBackward(_ sender: Any?) { restackChart("backward") }
    @objc func bringToFront(_ sender: Any?) { restackChart("front") }
    @objc func sendToBack(_ sender: Any?) { restackChart("back") }
}
