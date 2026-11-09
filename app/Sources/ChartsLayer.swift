import AppKit

/// Grid geometry the chart layer needs, in logical points (view points / zoom). Provided by GridView.chartGeometry().
struct ChartGridGeometry {
    var zoom: CGFloat
    var header: CGSize          // row header width, column header height
    var frozen: CGSize          // width of the frozen columns, height of the frozen rows
    var fr: Int, fc: Int        // frozen rows / columns
    var visible: CGSize         // view points: grid bounds without the scrollers
    var x: (Int) -> CGFloat     // left edge of a column (scroll aware)
    var y: (Int) -> CGFloat     // top edge of a row
    var colW: (Int) -> CGFloat
    var rowH: (Int) -> CGFloat
    var cellAt: (CGPoint) -> CellRef

    /// Logical rectangle of a chart.
    func rect(from a: ChartCorner, to b: ChartCorner) -> CGRect {
        let x0 = x(a.col) + CGFloat(a.fx) * colW(a.col), y0 = y(a.row) + CGFloat(a.fy) * rowH(a.row)
        let x1 = x(b.col) + CGFloat(b.fx) * colW(b.col), y1 = y(b.row) + CGFloat(b.fy) * rowH(b.row)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    /// Cell + fractions under a logical point.
    func corner(at p: CGPoint) -> ChartCorner {
        let c = cellAt(p)
        let w = colW(c.col), h = rowH(c.row)
        let fx = w > 0 ? min(1, max(0, (p.x - x(c.col)) / w)) : 0
        let fy = h > 0 ? min(1, max(0, (p.y - y(c.row)) / h)) : 0
        return ChartCorner(row: c.row, col: c.col, fy: Double(fy), fx: Double(fx))
    }
}

/// Transparent container for chart views: clips them to the grid area and lets clicks elsewhere reach the grid.
final class ChartPane: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let v = super.hitTest(point)
        return v === self ? nil : v
    }
}

/// Owns the chart views of the grid's current sheet and keeps them positioned on the cells.
final class ChartLayer {
    /// Weak: the grid owns this layer; pending async work must not outlive a closed window.
    private weak var grid: GridView?
    let book: Workbook
    /// Charts anchored in frozen rows/columns (above everything) and charts in the scrolling part (clipped by the frozen panes).
    private let mainPane = ChartPane(), scrollPane = ChartPane()
    private(set) var views: [ChartView] = []
    private(set) var charts: [ChartInfo] = []
    private var selected: Int?
    private var lastHeader = CGSize.zero

    init(grid: GridView) {
        self.grid = grid
        self.book = grid.book
        for p in [mainPane, scrollPane] {
            p.wantsLayer = true
            p.clipsToBounds = true
            grid.addSubview(p)
        }
    }

    var sheet: Int { grid?.sheet ?? 0 }
    var zoom: CGFloat { grid?.zoom ?? 1 }
    var selectedIndex: Int? { selected }

    /// Re-reads the charts of the sheet (after any change to the workbook or a sheet switch).
    func reload() {
        let list = book.charts(sheet: sheet)
        charts = list
        if let s = selected, s >= list.count { selected = nil }
        while views.count > list.count { views.removeLast().removeFromSuperview() }
        while views.count < list.count { views.append(ChartView(layer: self)) }
        for (v, c) in zip(views, list) {
            v.info = c
            v.isSelected = c.index == selected
            v.invalidateData()
        }
        layoutCharts()
    }

    /// Positions the panes and the charts (after scrolling, zooming, resizing, freezing).
    func layoutCharts() {
        guard let grid else { return }
        let g = grid.chartGeometry()
        lastHeader = g.header
        let z = g.zoom
        let main = CGRect(x: g.header.width * z, y: g.header.height * z,
                          width: max(0, g.visible.width - g.header.width * z), height: max(0, g.visible.height - g.header.height * z))
        let scroll = CGRect(x: (g.header.width + g.frozen.width) * z, y: (g.header.height + g.frozen.height) * z,
                            width: max(0, g.visible.width - (g.header.width + g.frozen.width) * z),
                            height: max(0, g.visible.height - (g.header.height + g.frozen.height) * z))
        if mainPane.frame != main { mainPane.frame = main }
        if scrollPane.frame != scroll { scrollPane.frame = scroll }
        for v in views where v.dragging == nil {
            guard let c = v.info else { continue }
            let pane = c.from.row >= g.fr && c.from.col >= g.fc ? scrollPane : mainPane
            if v.superview !== pane { pane.addSubview(v) }
            let r = g.rect(from: c.from, to: c.to)
            let viewRect = CGRect(x: r.minX * z - pane.frame.minX, y: r.minY * z - pane.frame.minY, width: r.width * z, height: r.height * z)
            let f = viewRect.insetBy(dx: -ChartView.margin, dy: -ChartView.margin).integral
            if v.frame != f { v.frame = f } else { v.needsDisplay = true }
        }
    }

    /// The row header grows with the row numbers on screen: follow it.
    func gridDidDraw() {
        guard !views.isEmpty, let grid else { return }
        let h = grid.chartGeometry().header
        if h != lastHeader { DispatchQueue.main.async { [weak self] in self?.layoutCharts() } }
    }

    // MARK: Selection and edits

    func select(_ index: Int?, focus: Bool = true) {
        selected = index
        for v in views { v.isSelected = v.info?.index == index }
        if let i = index, focus, let v = views[safe: i] { grid?.window?.makeFirstResponder(v) }
    }

    func deselect(_ v: ChartView) {
        if selected == v.info?.index { selected = nil }
        v.isSelected = false
    }

    /// After an engine change: mark the document edited and redraw (keeps the selection).
    func committed() {
        grid?.contentChanged()
    }

    func delete(index: Int) {
        guard book.deleteChart(sheet: sheet, index: index) else { return }
        selected = nil
        committed()
        if let grid { grid.window?.makeFirstResponder(grid) }
    }

    func setAnchor(index: Int, logical r: CGRect) {
        guard let grid else { return }
        let g = grid.chartGeometry()
        let a = g.corner(at: CGPoint(x: r.minX, y: r.minY)), b = g.corner(at: CGPoint(x: r.maxX, y: r.maxY))
        book.setChartAnchor(sheet: sheet, index: index, from: a, to: b)
        committed()
    }

    /// Converts a rectangle of a pane (view points) into logical grid coordinates.
    func logicalRect(_ r: CGRect, in pane: NSView) -> CGRect {
        guard let grid else { return r }
        let gr = grid.convert(r, from: pane)
        return CGRect(x: gr.minX / zoom, y: gr.minY / zoom, width: gr.width / zoom, height: gr.height / zoom)
    }

    func showProperties(index: Int) {
        guard let w = grid?.window, let info = charts[safe: index] else { return }
        ChartPropertiesSheet(layer: self, info: info).begin(on: w)
    }

    var gridView: GridView? { grid }
}

/// One chart on the sheet: draws it, selection handles, move/resize by dragging, Delete key, context menu.
final class ChartView: NSView, NSMenuItemValidation {
    static let margin: CGFloat = 5
    private unowned let chartLayer: ChartLayer
    var info: ChartInfo? { didSet { if info != oldValue { needsDisplay = true } } }
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true; window?.invalidateCursorRects(for: self) } } }
    private var data: [ChartSeriesData]?

    enum Drag { case move, resize(left: Bool, right: Bool, top: Bool, bottom: Bool) }
    private(set) var dragging: Drag?
    private var dragStart = CGPoint.zero
    private var startFrame = CGRect.zero
    private var moved = false

    init(layer: ChartLayer) {
        chartLayer = layer
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

    func invalidateData() { data = nil; needsDisplay = true }

    var chartRect: CGRect { bounds.insetBy(dx: ChartView.margin, dy: ChartView.margin) }
    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return nil }
        let p = convert(point, from: sv)
        if chartRect.contains(p) { return self }
        if isSelected && handle(at: p) != nil { return self }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let info, let ctx = NSGraphicsContext.current?.cgContext else { return }
        if data == nil { data = chartLayer.book.chartData(sheet: chartLayer.sheet, index: info.index) }
        let z = chartLayer.zoom
        let r = chartRect
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: z, y: z)
        ChartRenderer(chart: info, data: data ?? [], dark: isDark).draw(in: CGRect(x: 0, y: 0, width: r.width / z, height: r.height / z))
        ctx.restoreGState()
        if isSelected { drawSelection() }
        setAccessibilityLabel(info.title ?? info.name)
    }

    // MARK: Selection handles

    private func handleRects() -> [(CGRect, Drag)] {
        let r = chartRect, s: CGFloat = 7
        func h(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s) }
        return [
            (h(r.minX, r.minY), .resize(left: true, right: false, top: true, bottom: false)),
            (h(r.midX, r.minY), .resize(left: false, right: false, top: true, bottom: false)),
            (h(r.maxX, r.minY), .resize(left: false, right: true, top: true, bottom: false)),
            (h(r.maxX, r.midY), .resize(left: false, right: true, top: false, bottom: false)),
            (h(r.maxX, r.maxY), .resize(left: false, right: true, top: false, bottom: true)),
            (h(r.midX, r.maxY), .resize(left: false, right: false, top: false, bottom: true)),
            (h(r.minX, r.maxY), .resize(left: true, right: false, top: false, bottom: true)),
            (h(r.minX, r.midY), .resize(left: true, right: false, top: false, bottom: false)),
        ]
    }

    private func handle(at p: CGPoint) -> Drag? {
        handleRects().first { $0.0.insetBy(dx: -3, dy: -3).contains(p) }?.1
    }

    private func drawSelection() {
        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.8).setStroke()
        let frame = NSBezierPath(rect: chartRect.insetBy(dx: 0.5, dy: 0.5))
        frame.lineWidth = 1
        frame.stroke()
        for (r, _) in handleRects() {
            let p = NSBezierPath(ovalIn: r)
            NSColor.white.setFill(); p.fill()
            NSColor(white: 0.45, alpha: 1).setStroke(); p.lineWidth = 1; p.stroke()
        }
    }

    override func resetCursorRects() {
        guard isSelected else { return }
        for (r, d) in handleRects() {
            guard case let .resize(l, rt, t, b) = d else { continue }
            let cursor: NSCursor
            if (l || rt) && !(t || b) { cursor = .resizeLeftRight }
            else if (t || b) && !(l || rt) { cursor = .resizeUpDown }
            else if #available(macOS 15.0, *) {
                cursor = .frameResize(position: t ? (l ? .topLeft : .topRight) : (l ? .bottomLeft : .bottomRight), directions: .all)
            } else { cursor = .crosshair }
            addCursorRect(r.insetBy(dx: -3, dy: -3), cursor: cursor)
        }
    }

    // MARK: Mouse

    override func mouseDown(with e: NSEvent) {
        guard let info, let sv = superview else { return }
        if !isSelected || window?.firstResponder !== self { chartLayer.select(info.index) }
        if e.clickCount == 2 { chartLayer.showProperties(index: info.index); return }
        let p = convert(e.locationInWindow, from: nil)
        dragging = handle(at: p) ?? .move
        dragStart = sv.convert(e.locationInWindow, from: nil)
        startFrame = frame
        moved = false
    }

    override func mouseDragged(with e: NSEvent) {
        guard let d = dragging, let sv = superview else { return }
        let p = sv.convert(e.locationInWindow, from: nil)
        let dx = p.x - dragStart.x, dy = p.y - dragStart.y
        if !moved && abs(dx) < 2 && abs(dy) < 2 { return }
        moved = true
        let m = ChartView.margin, minSize: CGFloat = 24
        var r = startFrame.insetBy(dx: m, dy: m)
        switch d {
        case .move:
            r.origin.x += dx; r.origin.y += dy
            NSCursor.closedHand.set()
        case let .resize(l, rt, t, b):
            if l { let x = min(r.maxX - minSize, r.minX + dx); r.size.width = r.maxX - x; r.origin.x = x }
            if rt { r.size.width = max(minSize, r.width + dx) }
            if t { let y = min(r.maxY - minSize, r.minY + dy); r.size.height = r.maxY - y; r.origin.y = y }
            if b { r.size.height = max(minSize, r.height + dy) }
        }
        frame = r.insetBy(dx: -m, dy: -m)
    }

    override func mouseUp(with e: NSEvent) {
        defer { dragging = nil; moved = false; NSCursor.arrow.set() }
        guard moved, let info, let sv = superview else { return }
        let r = chartLayer.logicalRect(frame.insetBy(dx: ChartView.margin, dy: ChartView.margin), in: sv)
        dragging = nil
        chartLayer.setAnchor(index: info.index, logical: r)
    }

    override func scrollWheel(with e: NSEvent) { chartLayer.gridView?.scrollWheel(with: e) }

    // MARK: Keyboard and commands

    override func becomeFirstResponder() -> Bool {
        if let i = info?.index, chartLayer.selectedIndex != i { chartLayer.select(i, focus: false) }
        return true
    }
    override func resignFirstResponder() -> Bool {
        chartLayer.deselect(self)
        return true
    }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 51, 117: deleteChart(nil)                                               // delete, forward delete
        case 53: chartLayer.select(nil); window?.makeFirstResponder(chartLayer.gridView)   // escape
        case 36, 76: if let i = info?.index { chartLayer.showProperties(index: i) }        // return
        default: break
        }
    }

    @objc func deleteChart(_ sender: Any?) {
        guard let i = info?.index else { return }
        chartLayer.delete(index: i)
    }
    @objc func delete(_ sender: Any?) { deleteChart(sender) }
    @objc func cut(_ sender: Any?) { copy(sender); deleteChart(sender) }

    /// Copies the chart as an image (PDF + PNG), for pasting into other apps.
    @objc func copy(_ sender: Any?) {
        guard let info else { return }
        let z = chartLayer.zoom
        let size = CGSize(width: chartRect.width / z, height: chartRect.height / z)
        let data = self.data ?? chartLayer.book.chartData(sheet: chartLayer.sheet, index: info.index)
        let img = NSImage(size: size, flipped: true) { r in
            ChartRenderer(chart: info, data: data, dark: false).draw(in: r)
            return true
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        pb.writeObjects([img])
    }

    @objc func chartProperties(_ sender: Any?) { if let i = info?.index { chartLayer.showProperties(index: i) } }

    @objc func changeChartKind(_ sender: NSMenuItem) {
        guard let i = info?.index, let raw = sender.representedObject as? String, let k = ChartKind(rawValue: raw) else { return }
        chartLayer.book.updateChart(sheet: chartLayer.sheet, index: i, kind: k)
        chartLayer.committed()
    }
    @objc func changeChartLegend(_ sender: NSMenuItem) {
        guard let i = info?.index, let raw = sender.representedObject as? String, let l = ChartLegend(rawValue: raw) else { return }
        chartLayer.book.updateChart(sheet: chartLayer.sheet, index: i, legend: l)
        chartLayer.committed()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let info else { return nil }
        if !isSelected { chartLayer.select(info.index) }
        let m = NSMenu()
        let props = NSMenuItem(title: L("Chart Properties…"), action: #selector(chartProperties(_:)), keyEquivalent: "")
        m.addItem(props)
        let types = NSMenu()
        for k in ChartKind.allCases {
            let it = NSMenuItem(title: k.title, action: #selector(changeChartKind(_:)), keyEquivalent: "")
            it.representedObject = k.rawValue
            it.image = NSImage(systemSymbolName: k.symbol, accessibilityDescription: nil)
            types.addItem(it)
        }
        let typesItem = NSMenuItem(title: L("Chart Type"), action: nil, keyEquivalent: "")
        typesItem.submenu = types
        m.addItem(typesItem)
        let legends = NSMenu()
        for l in ChartLegend.allCases {
            let it = NSMenuItem(title: l.title, action: #selector(changeChartLegend(_:)), keyEquivalent: "")
            it.representedObject = l.rawValue
            legends.addItem(it)
        }
        let legendItem = NSMenuItem(title: L("Legend"), action: nil, keyEquivalent: "")
        legendItem.submenu = legends
        m.addItem(legendItem)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: L("Copy"), action: #selector(copy(_:)), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: L("Delete Chart"), action: #selector(deleteChart(_:)), keyEquivalent: ""))
        for it in m.items { it.target = self }
        for it in types.items + legends.items { it.target = self }
        return m
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(changeChartKind(_:)) { item.state = (item.representedObject as? String) == info?.kind.rawValue ? .on : .off }
        if item.action == #selector(changeChartLegend(_:)) { item.state = (item.representedObject as? String) == info?.legend.rawValue ? .on : .off }
        // Cell-only commands do nothing while a chart is selected.
        return true
    }
}

/// Chart properties: type, title, data range, legend, axis titles.
final class ChartPropertiesSheet: NSObject {
    private let chartLayer: ChartLayer
    private let info: ChartInfo
    private let panel: NSPanel
    private let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let legendPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let titleField = NSTextField()
    private let rangeField = NSTextField()
    private let catTitleField = NSTextField()
    private let valTitleField = NSTextField()
    private let error = NSTextField(labelWithString: "")
    private static var open: ChartPropertiesSheet?

    init(layer: ChartLayer, info: ChartInfo) {
        chartLayer = layer
        self.info = info
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 280), styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        panel.title = L("Chart Properties")
        for k in ChartKind.allCases {
            typePopup.addItem(withTitle: k.title)
            typePopup.lastItem?.image = NSImage(systemSymbolName: k.symbol, accessibilityDescription: nil)
            typePopup.lastItem?.representedObject = k.rawValue
        }
        typePopup.selectItem(at: ChartKind.allCases.firstIndex(of: info.kind) ?? 0)
        typePopup.target = self
        typePopup.action = #selector(kindChanged)
        for l in ChartLegend.allCases { legendPopup.addItem(withTitle: l.title); legendPopup.lastItem?.representedObject = l.rawValue }
        legendPopup.selectItem(at: ChartLegend.allCases.firstIndex(of: info.legend) ?? 0)
        titleField.stringValue = info.title ?? ""
        titleField.placeholderString = L("No title")
        rangeField.stringValue = info.dataRange ?? ""
        rangeField.placeholderString = "A1:C10"
        catTitleField.stringValue = info.categoryAxisTitle ?? ""
        valTitleField.stringValue = info.valueAxisTitle ?? ""
        for f in [titleField, rangeField, catTitleField, valTitleField] { f.widthAnchor.constraint(equalToConstant: 260).isActive = true }
        error.textColor = .systemRed
        error.font = .systemFont(ofSize: 11)

        let grid = NSGridView(views: [
            [label("Chart type:"), typePopup],
            [label("Title:"), titleField],
            [label("Data range:"), rangeField],
            [label("Legend:"), legendPopup],
            [label("Horizontal axis title:"), catTitleField],
            [label("Vertical axis title:"), valTitleField],
            [NSGridCell.emptyContentView, error],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: L("OK"), target: self, action: #selector(apply))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, ok])
        buttons.spacing = 10
        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        panel.contentView = content
        kindChanged()
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: L(s)) }

    func begin(on window: NSWindow) {
        ChartPropertiesSheet.open = self
        window.beginSheet(panel) { _ in ChartPropertiesSheet.open = nil }
    }

    /// For tests: the properties sheet currently shown, if any.
    static var current: ChartPropertiesSheet? { open }

    private var kind: ChartKind { ChartKind(rawValue: typePopup.selectedItem?.representedObject as? String ?? "") ?? info.kind }

    @objc private func kindChanged() {
        catTitleField.isEnabled = kind.hasAxes
        valTitleField.isEnabled = kind.hasAxes
    }

    @objc private func cancel() { panel.sheetParent?.endSheet(panel) }

    @objc func apply() {
        let book = chartLayer.book, sheet = chartLayer.sheet
        let range = rangeField.stringValue.trimmingCharacters(in: .whitespaces)
        if !range.isEmpty && range != (info.dataRange ?? "") {
            guard book.setChartRange(sheet: sheet, index: info.index, range) else {
                error.stringValue = L("The data range is not valid or contains no numbers.")
                return
            }
        }
        let legend = ChartLegend(rawValue: legendPopup.selectedItem?.representedObject as? String ?? "") ?? info.legend
        book.updateChart(sheet: sheet, index: info.index, kind: kind, title: titleField.stringValue, legend: legend,
                         categoryAxisTitle: catTitleField.stringValue, valueAxisTitle: valTitleField.stringValue)
        panel.sheetParent?.endSheet(panel)
        chartLayer.committed()
    }

    /// For tests.
    func setForTesting(title: String?, range: String?) {
        if let title { titleField.stringValue = title }
        if let range { rangeField.stringValue = range }
    }
}

// MARK: - Insert ▸ Chart

enum ChartsUI {
    /// Kinds in the Insert ▸ Chart menu: the six main types, then the variants.
    static let mainKinds: [ChartKind] = [.column, .bar, .line, .pie, .area, .scatter]
    static let moreKinds: [ChartKind] = [.columnStacked, .barStacked, .lineMarkers, .doughnut, .areaStacked]

    static func kindItems(target: AnyObject?) -> [NSMenuItem] {
        func item(_ k: ChartKind) -> NSMenuItem {
            let it = NSMenuItem(title: k.title, action: #selector(SheetWindowController.insertChartAction(_:)), keyEquivalent: "")
            it.representedObject = k.rawValue
            it.image = NSImage(systemSymbolName: k.symbol, accessibilityDescription: nil)
            it.target = target
            return it
        }
        return mainKinds.map(item) + [.separator()] + moreKinds.map(item)
    }

    /// Insert ▸ Chart submenu (for Menus.swift).
    static func insertMenuItem() -> NSMenuItem {
        let m = NSMenu(title: L("Chart"))
        kindItems(target: nil).forEach(m.addItem)
        let host = NSMenuItem(title: L("Chart"), action: nil, keyEquivalent: "")
        host.image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil)
        host.submenu = m
        return host
    }

    /// Format bar button (for SheetWindowController).
    static func toolbarButton(target: SheetWindowController) -> NSButton {
        MenuButton(image: ToolbarKit.symbol("chart.bar", L("Insert Chart")), tip: L("Insert Chart")) { [weak target] in
            let m = NSMenu()
            kindItems(target: target).forEach(m.addItem)
            return m
        }
    }

    /// UIScript "chart …" commands (main.swift):
    ///   chart column [A1:C5]   insert (selection or range)      chart list
    ///   chart click N          click on chart N                 chart drag N dx dy (points)
    ///   chart props N title=… range=…   apply the properties sheet
    ///   chart type N kind      chart roundtrip /path.xlsx (save, reopen, list)
    static func script(_ arg: String, on c: SheetWindowController) {
        let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = p.first else { return }
        let rest = p.count > 1 ? p[1] : ""
        let grid = c.grid!
        let layer = grid.chartLayer
        func view(_ s: String) -> ChartView? { Int(s.split(separator: " ").first ?? "").flatMap { layer.views[safe: $0] } }
        if let kind = ChartKind(rawValue: verb) {
            if let r = FormulaText.gridRange(rest.uppercased()) { grid.select(range: r) }
            c.insertChart(kind: kind)
            return
        }
        switch verb {
        case "list":
            let charts = grid.book.charts(sheet: grid.sheet)
            print("CHARTS \(charts.count) selected=\(layer.selectedIndex.map(String.init) ?? "none")")
            for ch in charts {
                print("CHART \(ch.index) kind=\(ch.kind.rawValue) title=\(ch.title ?? "") legend=\(ch.legend.rawValue) range=\(ch.dataRange ?? "") from=\(columnName(ch.from.col))\(ch.from.row + 1) to=\(columnName(ch.to.col))\(ch.to.row + 1) series=\(ch.series.count)")
            }
        case "click", "dblclick":
            guard let v = view(rest), let w = c.window else { return }
            let pt = v.convert(CGPoint(x: v.chartRect.midX, y: v.chartRect.midY), to: nil)
            UIScript.sendClick(at: pt, count: verb == "dblclick" ? 2 : 1, to: w)
        case "drag":
            let a = rest.split(separator: " ").compactMap { Double($0) }
            guard let v = view(rest), a.count == 3, let w = c.window else { return }
            let start = v.convert(CGPoint(x: v.chartRect.midX, y: v.chartRect.midY), to: nil)
            func ev(_ t: NSEvent.EventType, _ pt: NSPoint) {
                if let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { NSApp.sendEvent(e) }
            }
            ev(.leftMouseDown, start)
            for i in 1...5 { let t = CGFloat(i) / 5; ev(.leftMouseDragged, NSPoint(x: start.x + CGFloat(a[1]) * t, y: start.y - CGFloat(a[2]) * t)) }
            ev(.leftMouseUp, NSPoint(x: start.x + CGFloat(a[1]), y: start.y - CGFloat(a[2])))
        case "props":
            guard let i = Int(rest.split(separator: " ").first ?? "") else { return }
            layer.showProperties(index: i)
            var title: String?, range: String?
            for kv in rest.split(separator: " ").dropFirst() {
                let pair = kv.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                if pair[0] == "title" { title = pair[1].replacingOccurrences(of: "_", with: " ") }
                if pair[0] == "range" { range = pair[1] }
            }
            ChartPropertiesSheet.current?.setForTesting(title: title, range: range)
            ChartPropertiesSheet.current?.apply()
            // Extra keys straight to the engine: legend=right xtitle=… ytitle=…
            var legend: ChartLegend?, xt: String?, yt: String?
            for kv in rest.split(separator: " ").dropFirst() {
                let pair = kv.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                let v = pair[1].replacingOccurrences(of: "_", with: " ")
                if pair[0] == "legend" { legend = ChartLegend(rawValue: v) }
                if pair[0] == "xtitle" { xt = v }
                if pair[0] == "ytitle" { yt = v }
            }
            if legend != nil || xt != nil || yt != nil {
                grid.book.updateChart(sheet: grid.sheet, index: i, legend: legend, categoryAxisTitle: xt, valueAxisTitle: yt)
                layer.committed()
            }
        case "type":
            let a = rest.split(separator: " ").map(String.init)
            guard a.count == 2, let i = Int(a[0]), let k = ChartKind(rawValue: a[1]) else { return }
            grid.book.updateChart(sheet: grid.sheet, index: i, kind: k)
            layer.committed()
        case "roundtrip":
            do {
                try grid.book.saveXLSX(to: URL(fileURLWithPath: rest))
                let back = try Workbook(contentsOf: URL(fileURLWithPath: rest))
                let charts = back.charts(sheet: grid.sheet)
                print("REOPENED CHARTS \(charts.count) kinds=\(charts.map(\.kind.rawValue).joined(separator: ",")) titles=\(charts.map { $0.title ?? "" }.joined(separator: ","))")
            } catch { print("ROUNDTRIP_ERROR", error) }
        default: break
        }
    }
}

extension SheetWindowController {
    @objc func insertChartAction(_ sender: Any?) {
        let raw = (sender as? NSMenuItem)?.representedObject as? String ?? "column"
        insertChart(kind: ChartKind(rawValue: raw) ?? .column)
    }

    /// Inserts a chart for the selection (or the data region around the active cell), right of the data.
    func insertChart(kind: ChartKind) {
        guard let grid else { return }
        guard grid.commitIfEditing() else { return }
        var r = grid.selection
        let region = grid.book.currentRegion(sheet: grid.sheet, row: grid.active.row, col: grid.active.col)
        if r.isSingle { r = region }
        // Right of the whole table (not just the selected columns), one empty column in between.
        let at = CellRef(row: r.r0, col: min(Sheet.maxCols - 8, max(r.c1, region.c1) + 2))
        guard let index = grid.book.addChart(sheet: grid.sheet, kind: kind, range: r, at: at) else {
            let a = NSAlert()
            a.messageText = L("Select the data for the chart")
            a.informativeText = L("Select a range that contains numbers, with the series names in the first row or column, then choose the chart again.")
            if let w = window { a.beginSheetModal(for: w) } else { a.runModal() }
            return
        }
        grid.contentChanged()
        grid.chartLayer.select(index)
    }
}
