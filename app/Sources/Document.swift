import AppKit
import UniformTypeIdentifiers

enum FileTypes {
    static let xlsx = "org.openxmlformats.spreadsheetml.sheet"
    static let csv = "public.comma-separated-values-text"
    static let tsv = "public.tab-separated-values-text"
}

/// A workbook document: native open/save/revert/recent files/print through AppKit.
@objc(SpreadsheetDocument)
final class SpreadsheetDocument: NSDocument {
    private(set) var book = Workbook()
    var activeSheet = 0

    override class var autosavesInPlace: Bool { false }
    override class var preservesVersions: Bool { false }
    override var autosavingFileType: String? { FileTypes.xlsx }

    override init() {
        super.init()
        // Sensible spreadsheet margins by default; Page Setup changes are kept.
        printInfo.topMargin = 36; printInfo.bottomMargin = 36; printInfo.leftMargin = 30; printInfo.rightMargin = 30
    }

    override func makeWindowControllers() {
        addWindowController(SheetWindowController(document: self))
    }

    var windowController: SheetWindowController? { windowControllers.first as? SheetWindowController }

    override func read(from url: URL, ofType typeName: String) throws {
        let t = Date()
        book = try Workbook(contentsOf: url)
        Perf.shared.emit("OPEN_MS", String(format: "%.1f", Date().timeIntervalSince(t) * 1000))
        windowController?.reload()
    }

    override func write(to url: URL, ofType typeName: String) throws {
        windowController?.grid.commitEditing(move: nil)
        if typeName == FileTypes.csv || typeName == FileTypes.tsv || url.pathExtension.lowercased() == "csv" {
            try book.saveCSV(sheet: activeSheet, to: url, delimiter: typeName == FileTypes.tsv ? "\t" : FormulaLocale.current.csvDelimiter)
        } else {
            try book.saveXLSX(to: url)
        }
    }

    private var csvWarningAccepted = false

    /// Excel-style warning before a lossy CSV save; offers to keep the workbook format instead.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        let isCSV = typeName == FileTypes.csv || typeName == FileTypes.tsv
        guard isCSV, saveOperation != .autosaveElsewhereOperation, !csvWarningAccepted, let w = windowController?.window else {
            super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
            return
        }
        let a = NSAlert()
        a.messageText = L("Some features will be lost in CSV format")
        a.informativeText = book.sheetNames.count > 1
            ? L("CSV keeps only the values of the current sheet. Other sheets, formulas and formatting will not be saved.")
            : L("CSV keeps only values. Formulas and formatting will not be saved.")
        a.addButton(withTitle: L("Save as CSV"))
        a.addButton(withTitle: L("Save as Excel Workbook…"))
        a.addButton(withTitle: L("Cancel"))
        a.beginSheetModal(for: w) { r in
            switch r {
            case .alertFirstButtonReturn:
                self.csvWarningAccepted = true
                self.saveSkippingWarning(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
            case .alertSecondButtonReturn:
                completionHandler(nil)
                DispatchQueue.main.async { self.saveAs(nil) }
            default:
                completionHandler(CocoaError(.userCancelled))
            }
        }
    }

    private func saveSkippingWarning(to url: URL, ofType typeName: String, for op: NSDocument.SaveOperationType,
                                     completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: op, completionHandler: completionHandler)
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [FileTypes.xlsx, FileTypes.csv]
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        typeName == FileTypes.csv ? "csv" : "xlsx"
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.isExtensionHidden = false
        return true
    }

    // MARK: Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let wc = windowController else { throw EngineError(message: L("Nothing to print.")) }
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        let view = PrintView(book: book, sheet: wc.grid.sheet, selection: wc.grid.selection, printInfo: info)
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = displayName
        return op
    }
}

/// Lays out the used range (or the selection) into pages: down, then across — like Excel.
final class PrintView: NSView {
    private let book: Workbook
    private let sheet: Int
    private let range: GridRange
    private let painter = SheetPainter()
    private var colX: [CGFloat] = []
    private var rowY: [CGFloat] = []
    private var pages: [CGRect] = []
    private let unit: CGFloat = 0.75
    private var merges: [GridRange] = []

    init(book: Workbook, sheet: Int, selection: GridRange, printInfo: NSPrintInfo) {
        self.book = book
        self.sheet = sheet
        let l = book.layout(sheet: sheet)
        if selection.cellCount > 1 && !selection.isFullColumns && !selection.isFullRows {
            range = selection
        } else {
            range = GridRange(r0: 0, c0: 0, r1: l.maxRow, c1: l.maxCol)
        }
        painter.printing = true
        painter.fontScale = 1
        super.init(frame: .zero)
        let colAxis = Axis(defaultSize: l.defaultCol * unit, count: Sheet.maxCols, overrides: l.cols.map { ($0.0, $0.2 ? 0 : $0.1 * unit) })
        let rowAxis = Axis(defaultSize: l.defaultRow * unit, count: Sheet.maxRows, overrides: l.rows.map { ($0.0, $0.2 ? 0 : $0.1 * unit) })
        colX = (range.c0...(range.c1 + 1)).map { colAxis.pos($0) - colAxis.pos(range.c0) }
        rowY = (range.r0...(range.r1 + 1)).map { rowAxis.pos($0) - rowAxis.pos(range.r0) }
        merges = book.merges(sheet: sheet)
        setFrameSize(NSSize(width: colX.last ?? 0, height: rowY.last ?? 0))
        paginate(printInfo)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private func breaks(_ edges: [CGFloat], _ size: CGFloat) -> [ClosedRange<CGFloat>] {
        // edges[k] = start of item k; a page always takes at least one item (oversized items get their own page).
        var out: [ClosedRange<CGFloat>] = []
        var i = 0
        while i < edges.count - 1 {
            var j = i + 1
            while j + 1 < edges.count && edges[j + 1] - edges[i] <= size { j += 1 }
            if edges[j] > edges[i] { out.append(edges[i]...edges[j]) }
            i = j
        }
        return out.isEmpty ? [0...max(1, edges.last ?? 1)] : out
    }

    private func paginate(_ info: NSPrintInfo) {
        let w = info.paperSize.width - info.leftMargin - info.rightMargin
        let h = info.paperSize.height - info.topMargin - info.bottomMargin
        let colPages = breaks(colX, w)
        let rowPages = breaks(rowY, h)
        pages = []
        for c in colPages {
            for r in rowPages {
                pages.append(CGRect(x: c.lowerBound, y: r.lowerBound, width: c.upperBound - c.lowerBound, height: r.upperBound - r.lowerBound))
            }
        }
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: pages.count)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect { pages[safe: page - 1] ?? .zero }

    private func rect(_ r: Int, _ c: Int) -> CGRect {
        let ci = c - range.c0, ri = r - range.r0
        guard ci >= 0, ri >= 0, ci + 1 < colX.count, ri + 1 < rowY.count else { return .zero }
        return CGRect(x: colX[ci], y: rowY[ri], width: colX[ci + 1] - colX[ci], height: rowY[ri + 1] - rowY[ri])
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        func first(_ edges: [CGFloat], _ v: CGFloat) -> Int { max(0, (edges.firstIndex { $0 > v } ?? edges.count) - 1) }
        let r0 = range.r0 + first(rowY, dirtyRect.minY), r1 = range.r0 + min(rowY.count - 2, first(rowY, dirtyRect.maxY - 0.5))
        let c0 = range.c0 + first(colX, dirtyRect.minX), c1 = range.c0 + min(colX.count - 2, first(colX, dirtyRect.maxX - 0.5))
        guard r1 >= r0, c1 >= c0 else { return }
        let data = CellData(book.viewport(sheet: sheet, rows: r0...r1, cols: c0...c1))
        painter.paint(rows: r0...r1, cols: c0...c1, data: data, merges: merges, showGrid: false, hair: 0.5, clip: dirtyRect,
                      gridColor: .lightGray, rect: rect, colWidth: { self.rect(r0, $0).width }, rowHeight: { self.rect($0, c0).height })
    }
}
