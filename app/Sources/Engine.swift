import Foundation
import QuartzCore

/// One cell returned by a viewport fetch. Coordinates are 0-based.
struct VCell {
    let row: Int
    let col: Int
    let text: String
    let kind: UInt8      // 0 text, 1 number, 2 bool, 3 error
    let align: UInt8     // 0 general, 1 left, 2 center, 3 right
    let bold: Bool
    let italic: Bool
    let fg: UInt32       // 0xRRGGBB or noColor
    let bg: UInt32
    let fontSize: UInt8
    let underline: Bool
    let strike: Bool
    let wrap: Bool
    let valign: UInt8    // 0 bottom, 1 center, 2 top
    let borderMask: UInt8
    let borderWeight: UInt8          // 2 bits per side
    let borderColors: (UInt32, UInt32, UInt32, UInt32)
    func borderWeight(side i: Int) -> Int { Int((borderWeight >> (2 * UInt8(i))) & 3) }
    func borderColor(side i: Int) -> UInt32 { [borderColors.0, borderColors.1, borderColors.2, borderColors.3][i] }
    static let noColor: UInt32 = 0xFFFF_FFFF
}

struct CellStyle {
    var bold = false, italic = false, underline = false, strike = false
    var align: UInt8 = 0, valign: UInt8 = 0, wrap = false
    var fontSize: Int = 11
    var fg: UInt32 = VCell.noColor, bg: UInt32 = VCell.noColor
    var numFmt = "general"
}

struct SheetLayout {
    var cols: [(Int, CGFloat, Bool)] = []   // 0-based index, engine px, hidden
    var rows: [(Int, CGFloat, Bool)] = []
    var defaultCol: CGFloat = 90
    var defaultRow: CGFloat = 25
    var frozenRows = 0
    var frozenCols = 0
    var showGrid = true
    var maxRow = 0                          // 0-based last used row
    var maxCol = 0
}

struct Stats {
    var count = 0, numeric = 0
    var sum = 0.0, min = 0.0, max = 0.0
}

struct Completion {
    enum Kind { case none, functionPrefix, argument, range }
    var kind: Kind
    var replaceFrom: Int
    var argIndex: Int
    var name: String
}

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Swift wrapper around the Rust/IronCalc core. Converts 0-based (Swift) <-> 1-based (engine).
final class Workbook {
    private let ptr: OpaquePointer
    /// Bumped on every mutation so views can invalidate caches.
    private(set) var version = 0
    var onChange: (() -> Void)?

    init() {
        let t = CACurrentMediaTime()
        guard let p = foglio_new() else { fatalError("engine init failed") }
        ptr = p
        Perf.shared.emit("ENGINE_NEW_MS", String(format: "%.1f", (CACurrentMediaTime() - t) * 1000))
    }

    /// Opens any supported spreadsheet file (xlsx, xlsm, xls, xlsb, ods, csv, tsv, txt).
    init(contentsOf url: URL) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard let p = foglio_open_any(url.path, &err) else {
            throw EngineError(message: Workbook.take(err) ?? L("The file could not be read."))
        }
        ptr = p
    }

    deinit { foglio_free(ptr) }

    static func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
        guard let p else { return nil }
        defer { foglio_string_free(p) }
        return String(cString: p)
    }

    private func changed() {
        version &+= 1
        onChange?()
    }

    func saveXLSX(to url: URL) throws {
        var err: UnsafeMutablePointer<CChar>?
        if foglio_save_xlsx(ptr, url.path, &err) != 0 {
            throw EngineError(message: Workbook.take(err) ?? L("The file could not be saved."))
        }
    }

    func saveCSV(sheet: Int, to url: URL, delimiter: Character = ",") throws {
        var err: UnsafeMutablePointer<CChar>?
        if foglio_save_csv(ptr, UInt32(sheet), url.path, delimiter.asciiValue ?? 44, &err) != 0 {
            throw EngineError(message: Workbook.take(err) ?? L("The file could not be saved."))
        }
    }

    // MARK: sheets
    var sheetNames: [String] {
        (0..<foglio_sheet_count(ptr)).map { Workbook.take(foglio_sheet_name(ptr, $0)) ?? "?" }
    }
    func isSheetHidden(_ s: Int) -> Bool { foglio_sheet_hidden(ptr, UInt32(s)) == 1 }
    func addSheet() { _ = foglio_add_sheet(ptr); changed() }
    @discardableResult func renameSheet(_ s: Int, to name: String) -> Bool { let ok = foglio_sheet_op(ptr, UInt32(s), 0, 0, name) == 0; changed(); return ok }
    @discardableResult func deleteSheet(_ s: Int) -> Bool { let ok = foglio_sheet_op(ptr, UInt32(s), 1, 0, nil) == 0; changed(); return ok }
    func moveSheet(_ s: Int, to i: Int) { _ = foglio_sheet_op(ptr, UInt32(s), 2, UInt32(i), nil); changed() }
    func duplicateSheet(_ s: Int) { _ = foglio_sheet_op(ptr, UInt32(s), 3, 0, nil); changed() }
    func setSheetHidden(_ s: Int, _ h: Bool) { _ = foglio_sheet_op(ptr, UInt32(s), h ? 4 : 5, 0, nil); changed() }

    // MARK: cells
    func setInput(sheet: Int, row: Int, col: Int, _ s: String) {
        _ = foglio_set_input(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1), s)
        changed()
    }
    func input(sheet: Int, row: Int, col: Int) -> String {
        Workbook.take(foglio_get_input(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1))) ?? ""
    }
    func formatted(sheet: Int, row: Int, col: Int) -> String {
        Workbook.take(foglio_get_formatted(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1))) ?? ""
    }
    func clear(sheet: Int, _ r: GridRange) {
        _ = foglio_clear_range(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c)
        changed()
    }
    func clearFormats(sheet: Int, _ r: GridRange) {
        _ = foglio_clear_formats(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c)
        changed()
    }
    func setStyle(sheet: Int, _ r: GridRange, path: String, value: String) {
        _ = foglio_set_style(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c, path, value)
        changed()
    }
    func setBorder(sheet: Int, _ r: GridRange, kind: String, style: String = "thin", color: String = "#000000") {
        _ = foglio_set_border(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c, kind, style, color)
        changed()
    }
    func style(sheet: Int, row: Int, col: Int) -> CellStyle {
        var s = FoglioStyle()
        guard foglio_style_at(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1), &s) == 0 else { return CellStyle() }
        return CellStyle(bold: s.bold != 0, italic: s.italic != 0, underline: s.underline != 0, strike: s.strike != 0,
                         align: s.align, valign: s.valign, wrap: s.wrap != 0, fontSize: Int(s.font_size),
                         fg: s.fg, bg: s.bg, numFmt: Workbook.take(s.num_fmt) ?? "general")
    }
    func autofill(sheet: Int, _ r: GridRange, toRow: Int?, toCol: Int?) {
        _ = foglio_autofill(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c,
                            Int32((toRow ?? -1) + 1), Int32((toCol ?? -1) + 1))
        changed()
    }

    // MARK: structure
    func insertRows(sheet: Int, at r: Int, count: Int) { _ = foglio_structure(ptr, UInt32(sheet), 0, Int32(r + 1), Int32(count)); changed() }
    func deleteRows(sheet: Int, at r: Int, count: Int) { _ = foglio_structure(ptr, UInt32(sheet), 1, Int32(r + 1), Int32(count)); changed() }
    func insertCols(sheet: Int, at c: Int, count: Int) { _ = foglio_structure(ptr, UInt32(sheet), 2, Int32(c + 1), Int32(count)); changed() }
    func deleteCols(sheet: Int, at c: Int, count: Int) { _ = foglio_structure(ptr, UInt32(sheet), 3, Int32(c + 1), Int32(count)); changed() }

    func layout(sheet: Int) -> SheetLayout {
        guard let lp = foglio_layout(ptr, UInt32(sheet)) else { return SheetLayout() }
        defer { foglio_layout_free(lp) }
        let l = lp.pointee
        var out = SheetLayout()
        out.defaultCol = CGFloat(l.default_col)
        out.defaultRow = CGFloat(l.default_row)
        out.frozenRows = Int(l.frozen_rows)
        out.frozenCols = Int(l.frozen_cols)
        out.showGrid = l.show_grid != 0
        out.maxRow = max(0, Int(l.max_row) - 1)
        out.maxCol = max(0, Int(l.max_col) - 1)
        if let c = l.cols, l.ncols > 0 {
            out.cols = UnsafeBufferPointer(start: c, count: l.ncols).map { (Int($0.index) - 1, CGFloat($0.size), $0.hidden != 0) }
        }
        if let r = l.rows, l.nrows > 0 {
            out.rows = UnsafeBufferPointer(start: r, count: l.nrows).map { (Int($0.index) - 1, CGFloat($0.size), $0.hidden != 0) }
        }
        return out
    }
    func setColumnWidth(sheet: Int, _ c0: Int, _ c1: Int, px: CGFloat) { _ = foglio_set_col_width(ptr, UInt32(sheet), Int32(c0 + 1), Int32(c1 + 1), Double(px)); changed() }
    func setRowHeight(sheet: Int, _ r0: Int, _ r1: Int, px: CGFloat) { _ = foglio_set_row_height(ptr, UInt32(sheet), Int32(r0 + 1), Int32(r1 + 1), Double(px)); changed() }
    func setHidden(sheet: Int, rows: Bool, _ i0: Int, _ i1: Int, hidden: Bool) {
        _ = foglio_set_hidden(ptr, UInt32(sheet), rows, Int32(i0 + 1), Int32(i1 + 1), hidden); changed()
    }
    func setFrozen(sheet: Int, rows: Int, cols: Int) { _ = foglio_set_frozen(ptr, UInt32(sheet), Int32(rows), Int32(cols)); changed() }
    func setShowGrid(sheet: Int, _ show: Bool) { _ = foglio_set_show_grid(ptr, UInt32(sheet), show); changed() }

    func merges(sheet: Int) -> [GridRange] {
        var n = 0
        guard let p = foglio_merges(ptr, UInt32(sheet), &n) else { return [] }
        defer { foglio_ints_free(p, n * 4) }
        return (0..<n).map { i in
            let r = Int(p[i * 4]) - 1, c = Int(p[i * 4 + 1]) - 1, w = Int(p[i * 4 + 2]), h = Int(p[i * 4 + 3])
            return GridRange(r0: r, c0: c, r1: r + h - 1, c1: c + w - 1)
        }
    }
    /// mode: 0 unmerge, 1 merge, 2 merge & center
    func merge(sheet: Int, _ r: GridRange, mode: Int32) { _ = foglio_merge(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c, mode); changed() }

    // MARK: format painter
    func copyStyles(sheet: Int, _ r: GridRange) { _ = foglio_copy_styles(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c) }
    func pasteStyles(sheet: Int, _ r: GridRange) { _ = foglio_paste_styles(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c); changed() }

    // MARK: conditional formatting
    func addConditionalFormat(sheet: Int, _ r: GridRange, kind: UInt32, op: UInt32 = 0, v1: String = "", v2: String = "", style: UInt32 = 0) -> Bool {
        let ok = foglio_add_cf(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c, kind, op, v1, v2, style) == 0
        changed()
        return ok
    }
    @discardableResult func clearConditionalFormats(sheet: Int, _ r: GridRange?) -> Int {
        let n = r.map { foglio_clear_cf(ptr, UInt32(sheet), $0.e0r, $0.e0c, $0.e1r, $0.e1c) } ?? foglio_clear_cf(ptr, UInt32(sheet), 0, 0, 0, 0)
        changed()
        return Int(n)
    }

    // MARK: clipboard
    func copy(sheet: Int, _ r: GridRange) -> (text: String, token: UInt64)? {
        var token: UInt64 = 0
        guard let s = Workbook.take(foglio_copy(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c, &token)) else { return nil }
        return (s, token)
    }
    /// false if the token is stale (the internal copy is gone).
    func pasteInternal(sheet: Int, _ r: GridRange, token: UInt64, cut: Bool) -> Bool {
        let rc = foglio_paste_internal(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c, token, cut)
        changed()
        return rc == 0
    }
    func pasteText(sheet: Int, row: Int, col: Int, _ tsv: String) {
        _ = foglio_paste_text(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1), tsv)
        changed()
    }

    // MARK: data tools
    func sort(sheet: Int, _ r: GridRange, keyCol: Int, ascending: Bool) {
        _ = foglio_sort(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c, Int32(keyCol + 1), ascending)
        changed()
    }
    func currentRegion(sheet: Int, row: Int, col: Int) -> GridRange {
        var o = [Int32](repeating: 0, count: 4)
        guard foglio_current_region(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1), &o) == 0 else {
            return GridRange(r0: row, c0: col, r1: row, c1: col)
        }
        return GridRange(r0: Int(o[0]) - 1, c0: Int(o[1]) - 1, r1: Int(o[2]) - 1, c1: Int(o[3]) - 1)
    }
    func jump(sheet: Int, from c: CellRef, dr: Int, dc: Int) -> CellRef {
        var o = [Int32](repeating: 0, count: 2)
        guard foglio_jump(ptr, UInt32(sheet), Int32(c.row + 1), Int32(c.col + 1), Int32(dr), Int32(dc), &o) == 0 else { return c }
        return CellRef(row: Int(o[0]) - 1, col: Int(o[1]) - 1)
    }
    func stats(sheet: Int, _ r: GridRange) -> Stats {
        var s = FoglioStats()
        guard foglio_stats(ptr, UInt32(sheet), r.e0r, r.e0c, r.e1r, r.e1c, &s) == 0 else { return Stats() }
        return Stats(count: Int(s.count), numeric: Int(s.numeric), sum: s.sum, min: s.min, max: s.max)
    }
    func find(sheet: Int, after c: CellRef, _ q: String, flags: UInt32) -> CellRef? {
        var o = [Int32](repeating: 0, count: 2)
        guard foglio_find(ptr, UInt32(sheet), Int32(c.row + 1), Int32(c.col + 1), q, flags, &o) == 1 else { return nil }
        return CellRef(row: Int(o[0]) - 1, col: Int(o[1]) - 1)
    }
    func replaceAll(sheet: Int, _ q: String, with r: String, flags: UInt32) -> Int {
        let n = Int(foglio_replace_all(ptr, UInt32(sheet), q, r, flags))
        changed()
        return n
    }

    // MARK: formulas
    /// (localized, English) function names for the current formula language.
    private static let functionPairs: [(String, String)] = {
        (take(foglio_function_names()) ?? "").split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return p.count == 2 ? (p[0], p[1]) : nil
        }
    }()
    static let functionNames: [String] = functionPairs.map(\.0)
    private static let toEnglish: [String: String] = Dictionary(functionPairs.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    static func englishName(_ local: String) -> String { toEnglish[local.uppercased()] ?? local.uppercased() }
    private static let toLocal: [String: String] = Dictionary(functionPairs.map { ($0.1, $0.0) }, uniquingKeysWith: { a, _ in a })
    static func localName(_ english: String) -> String { toLocal[english.uppercased()] ?? english.uppercased() }

    /// Argument separator of the formula language (";" outside English).
    static var argSeparator: String { FormulaLocale.current.language == "en" ? "," : ";" }

    /// "SOMMA(num1; [num2]; ...)" plus the range of each argument (UTF-16).
    static func localizedSignature(_ local: String) -> String { signatureParts(local).0 }
    static func signatureParts(_ local: String) -> (String, [NSRange]) {
        guard let doc = FunctionDocs.doc(englishName(local)) else { return ("\(local)()", []) }
        var s = local + "("
        var ranges: [NSRange] = []
        for (i, a) in doc.args.enumerated() {
            if i > 0 { s += argSeparator + " " }
            ranges.append(NSRange(location: (s as NSString).length, length: (a as NSString).length))
            s += a
        }
        return (s + ")", ranges)
    }

    func completion(sheet: Int, row: Int, col: Int, formula: String, cursor: Int) -> Completion? {
        var c = FoglioCompletion()
        guard foglio_completion(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1), formula, UInt32(cursor), &c) == 0 else { return nil }
        let kind: Completion.Kind = [.none, .functionPrefix, .argument, .range][Int(min(c.kind, 3))]
        return Completion(kind: kind, replaceFrom: Int(c.replace_from), argIndex: Int(c.arg_index), name: Workbook.take(c.name) ?? "")
    }
    func cycleReference(_ text: String, start: Int, end: Int) -> (String, NSRange)? {
        var o = [Int32](repeating: 0, count: 2)
        guard let s = Workbook.take(foglio_cycle_reference(ptr, text, UInt32(start), UInt32(end), &o)) else { return nil }
        return (s, NSRange(location: Int(o[0]), length: Int(o[1] - o[0])))
    }

    // MARK: undo
    var canUndo: Bool { foglio_can_undo(ptr) }
    var canRedo: Bool { foglio_can_redo(ptr) }
    func undo() { _ = foglio_undo(ptr); changed() }
    func redo() { _ = foglio_redo(ptr); changed() }

    // MARK: viewport
    func viewport(sheet: Int, rows: ClosedRange<Int>, cols: ClosedRange<Int>) -> [VCell] {
        guard let vp = foglio_viewport(ptr, UInt32(sheet), Int32(rows.lowerBound + 1), Int32(cols.lowerBound + 1),
                                       Int32(rows.upperBound + 1), Int32(cols.upperBound + 1)) else { return [] }
        defer { foglio_viewport_free(vp) }
        let v = vp.pointee
        guard v.count > 0, let cellsPtr = v.cells else { return [] }
        let cells = UnsafeBufferPointer(start: cellsPtr, count: v.count)
        var out: [VCell] = []
        out.reserveCapacity(v.count)
        for c in cells {
            var text = ""
            if c.text_len > 0, let base = v.text {
                text = String(decoding: UnsafeBufferPointer(start: base + Int(c.text_off), count: Int(c.text_len)), as: UTF8.self)
            }
            out.append(VCell(row: Int(c.row) - 1, col: Int(c.col) - 1, text: text, kind: c.kind, align: c.align,
                             bold: c.bold != 0, italic: c.italic != 0, fg: c.fg, bg: c.bg,
                             fontSize: c.font_size, underline: c.underline != 0, strike: c.strike != 0, wrap: c.wrap != 0,
                             valign: c.valign, borderMask: c.border_mask, borderWeight: c.border_weight,
                             borderColors: c.border_colors))
        }
        return out
    }

    func evaluateMicros() -> UInt64 { foglio_evaluate_us(ptr) }
}

private extension GridRange {
    var e0r: Int32 { Int32(r0 + 1) }
    var e0c: Int32 { Int32(c0 + 1) }
    var e1r: Int32 { Int32(r1 + 1) }
    var e1c: Int32 { Int32(c1 + 1) }
}

/// Locale used by the engine, derived from the Mac's language/region (overridable in Settings).
struct FormulaLocale {
    let locale: String      // en, en-GB, it, de, es, fr
    let language: String    // en, it, de, es, fr
    let timezone: String

    static let supported = ["en", "it", "de", "es", "fr"]

    static let current: FormulaLocale = {
        let prefs = UserDefaults.standard
        let sysLang = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        let region = Locale.current.region?.identifier ?? ""
        let lang = prefs.string(forKey: "FormulaLanguage").flatMap { supported.contains($0) ? $0 : nil }
            ?? (supported.contains(sysLang) ? sysLang : "en")
        // Number/date formatting follows the region when it maps to a supported locale.
        let regionLocale: String
        switch region {
        case "IT", "SM", "VA": regionLocale = "it"
        case "DE", "AT", "CH", "LI", "LU": regionLocale = "de"
        case "ES", "MX", "AR", "CO", "CL", "PE": regionLocale = "es"
        case "FR", "BE", "MC": regionLocale = "fr"
        case "GB", "IE", "AU", "NZ", "IN", "ZA": regionLocale = "en-GB"
        default: regionLocale = supported.contains(sysLang) && sysLang != "en" ? sysLang : "en"
        }
        let locale = prefs.string(forKey: "FormulaLocale") ?? regionLocale
        return FormulaLocale(locale: locale, language: lang, timezone: TimeZone.current.identifier)
    }()

    func apply() { foglio_set_locale(locale, language, timezone) }

    /// Excel uses ";" in CSV files where the decimal separator is a comma.
    var csvDelimiter: Character { locale.hasPrefix("en") ? "," : ";" }

    /// Date pattern matching the engine's input parser for this locale.
    var datePattern: String {
        switch locale {
        case "en": return "MM/dd/yyyy"
        case "de": return "dd.MM.yyyy"
        default: return "dd/MM/yyyy"
        }
    }
}

/// Localized string (English source, Italian in it.lproj).
func L(_ s: String) -> String { NSLocalizedString(s, comment: "") }
