import Foundation

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
    static let noColor: UInt32 = 0xFFFF_FFFF
}

struct EngineError: Error, CustomStringConvertible {
    let description: String
}

/// Swift wrapper around the Rust/IronCalc core (foglio_core.h). Converts 0-based <-> 1-based.
final class Workbook {
    private let ptr: OpaquePointer
    /// Bumped on every mutation so views can invalidate caches.
    private(set) var version = 0
    var fileURL: URL?

    init() {
        guard let p = foglio_new() else { fatalError("engine init failed") }
        ptr = p
    }

    init(xlsx url: URL) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard let p = foglio_open_xlsx(url.path, &err) else {
            throw EngineError(description: Workbook.take(err) ?? "Impossibile aprire il file")
        }
        ptr = p
        fileURL = url
    }

    deinit { foglio_free(ptr) }

    private static func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
        guard let p else { return nil }
        defer { foglio_string_free(p) }
        return String(cString: p)
    }

    private func bump() { version &+= 1 }

    func save(to url: URL) throws {
        var err: UnsafeMutablePointer<CChar>?
        if foglio_save_xlsx(ptr, url.path, &err) != 0 {
            throw EngineError(description: Workbook.take(err) ?? "Salvataggio non riuscito")
        }
        fileURL = url
    }

    // MARK: sheets
    var sheetNames: [String] {
        (0..<foglio_sheet_count(ptr)).map { Workbook.take(foglio_sheet_name(ptr, $0)) ?? "?" }
    }
    func addSheet() { _ = foglio_add_sheet(ptr); bump() }

    // MARK: cells
    func setInput(sheet: Int, row: Int, col: Int, _ s: String) {
        _ = foglio_set_input(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1), s)
        bump()
    }
    func input(sheet: Int, row: Int, col: Int) -> String {
        Workbook.take(foglio_get_input(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1))) ?? ""
    }
    func formatted(sheet: Int, row: Int, col: Int) -> String {
        Workbook.take(foglio_get_formatted(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1))) ?? ""
    }
    func clear(sheet: Int, _ r: GridRange) {
        _ = foglio_clear_range(ptr, UInt32(sheet), Int32(r.r0 + 1), Int32(r.c0 + 1), Int32(r.r1 + 1), Int32(r.c1 + 1))
        bump()
    }
    func setStyle(sheet: Int, _ r: GridRange, path: String, value: String) {
        _ = foglio_set_style(ptr, UInt32(sheet), Int32(r.r0 + 1), Int32(r.c0 + 1), Int32(r.r1 + 1), Int32(r.c1 + 1), path, value)
        bump()
    }
    /// toRow / toCol are 0-based target indices; pass nil for the other axis.
    func autofill(sheet: Int, _ r: GridRange, toRow: Int?, toCol: Int?) {
        _ = foglio_autofill(ptr, UInt32(sheet), Int32(r.r0 + 1), Int32(r.c0 + 1), Int32(r.r1 + 1), Int32(r.c1 + 1),
                            Int32((toRow ?? -1) + 1), Int32((toCol ?? -1) + 1))
        bump()
    }
    func pasteTSV(sheet: Int, row: Int, col: Int, _ tsv: String) {
        _ = foglio_paste_tsv(ptr, UInt32(sheet), Int32(row + 1), Int32(col + 1), tsv)
        bump()
    }

    // MARK: undo
    var canUndo: Bool { foglio_can_undo(ptr) }
    var canRedo: Bool { foglio_can_redo(ptr) }
    func undo() { _ = foglio_undo(ptr); bump() }
    func redo() { _ = foglio_redo(ptr); bump() }

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
                             bold: c.bold != 0, italic: c.italic != 0, fg: c.fg, bg: c.bg))
        }
        return out
    }

    func evaluateMicros() -> UInt64 { foglio_evaluate_us(ptr) }
}
