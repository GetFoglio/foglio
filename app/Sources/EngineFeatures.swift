import Foundation

/// Comments, data validation, fonts, tab colours, hyperlinks, summaries (core/include/foglio_features.h).
extension Workbook {
    // MARK: comments
    func comment(sheet: Int, row: Int, col: Int) -> (text: String, author: String)? {
        guard let t = Workbook.take(foglio_comment_get(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1))) else { return nil }
        let a = Workbook.take(foglio_comment_author(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1))) ?? ""
        return (t, a)
    }
    func setComment(sheet: Int, row: Int, col: Int, _ text: String, author: String) {
        _ = foglio_comment_set(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1), text, author)
        notifyChanged()
    }
    func deleteComment(sheet: Int, row: Int, col: Int) {
        _ = foglio_comment_delete(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1))
        notifyChanged()
    }
    func commentCells(sheet: Int, rows: ClosedRange<Int>, cols: ClosedRange<Int>) -> Set<CellRef> {
        var n = 0
        guard let p = foglio_comment_cells(rawPtr, UInt32(sheet), Int32(rows.lowerBound + 1), Int32(cols.lowerBound + 1),
                                           Int32(rows.upperBound + 1), Int32(cols.upperBound + 1), &n) else { return [] }
        defer { foglio_ints_free(p, n * 2) }
        return Set((0..<n).map { CellRef(row: Int(p[$0 * 2]) - 1, col: Int(p[$0 * 2 + 1]) - 1) })
    }

    // MARK: data validation
    func setValidation(sheet: Int, _ r: GridRange, rule: [String: Any]) throws {
        let json = String(data: try JSONSerialization.data(withJSONObject: rule), encoding: .utf8) ?? "{}"
        var err: UnsafeMutablePointer<CChar>?
        if foglio_validation_set(rawPtr, UInt32(sheet), Int32(r.r0 + 1), Int32(r.c0 + 1), Int32(r.r1 + 1), Int32(r.c1 + 1), json, &err) != 0 {
            throw EngineError(message: Workbook.take(err) ?? L("Invalid rule."))
        }
        notifyChanged()
    }
    func clearValidation(sheet: Int, _ r: GridRange) {
        _ = foglio_validation_clear(rawPtr, UInt32(sheet), Int32(r.r0 + 1), Int32(r.c0 + 1), Int32(r.r1 + 1), Int32(r.c1 + 1))
        notifyChanged()
    }
    func validation(sheet: Int, row: Int, col: Int) -> [String: Any]? {
        guard let s = Workbook.take(foglio_validation_get(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1))),
              let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return nil }
        return d
    }
    func validationList(sheet: Int, row: Int, col: Int) -> [String]? {
        guard let s = Workbook.take(foglio_validation_list(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1))) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String]
    }
    /// 0 ok, 1 stop, 2 warning, 3 information — with the rule's title/message ("" = default text).
    func checkValidation(sheet: Int, row: Int, col: Int, _ input: String) -> (code: Int, title: String, message: String) {
        var t: UnsafeMutablePointer<CChar>?, m: UnsafeMutablePointer<CChar>?
        let code = foglio_validation_check(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1), input, &t, &m)
        return (Int(code), Workbook.take(t) ?? "", Workbook.take(m) ?? "")
    }

    // MARK: fonts, tabs, links
    func fontName(sheet: Int, row: Int, col: Int) -> String? {
        Workbook.take(foglio_font_name_at(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1)))
    }
    func fontName(id: UInt8) -> String? { id == 0 ? nil : Workbook.take(foglio_font_name_by_id(rawPtr, id)) }
    func sheetColor(_ s: Int) -> UInt32 { foglio_sheet_color(rawPtr, UInt32(s)) }
    func setSheetColor(_ s: Int, _ rgb: UInt32) { _ = foglio_set_sheet_color(rawPtr, UInt32(s), rgb); notifyChanged() }
    func link(sheet: Int, row: Int, col: Int) -> (address: String, tooltip: String)? {
        guard let s = Workbook.take(foglio_link_get(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1))),
              let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return nil }
        return ((d["address"] as? String) ?? "", (d["tooltip"] as? String) ?? "")
    }
    func setLink(sheet: Int, row: Int, col: Int, address: String, display: String?) {
        _ = foglio_link_set(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1), address, display, nil)
        notifyChanged()
    }
    func removeLink(sheet: Int, row: Int, col: Int) {
        _ = foglio_link_remove(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1))
        notifyChanged()
    }

    // MARK: summary ("pivot-lite")
    /// Returns the index of the new sheet.
    func summarize(sheet: Int, _ r: GridRange, groupCol: Int, valueCol: Int, aggregation: Int, name: String?) throws -> Int {
        var err: UnsafeMutablePointer<CChar>?
        let i = foglio_summarize(rawPtr, UInt32(sheet), Int32(r.r0 + 1), Int32(r.c0 + 1), Int32(r.r1 + 1), Int32(r.c1 + 1),
                                 Int32(groupCol + 1), Int32(valueCol + 1), Int32(aggregation), name, &err)
        notifyChanged()
        if i < 0 { throw EngineError(message: Workbook.take(err) ?? L("The summary could not be created.")) }
        return Int(i)
    }
}
