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
    /// List items with what to enter when one is picked (the source value as typed, not its formatted text).
    func validationListItems(sheet: Int, row: Int, col: Int) -> [(display: String, input: String)]? {
        guard let s = Workbook.take(foglio_validation_list_items(rawPtr, UInt32(sheet), Int32(row + 1), Int32(col + 1))),
              let a = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [[String: Any]] else { return nil }
        return a.map { (($0["display"] as? String) ?? "", ($0["input"] as? String) ?? "") }
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

    // MARK: undo groups, moving ranges
    /// Everything `body` changes is one undo step.
    func grouped<T>(_ body: () -> T) -> T {
        foglio_begin_group(rawPtr)
        defer { foglio_end_group(rawPtr) }
        return body()
    }
    /// Moves (or copies) `src` so its top-left corner lands on `to`, keeping the user's internal clipboard.
    @discardableResult
    func moveRange(sheet: Int, _ src: GridRange, to: CellRef, copy: Bool = false) -> Bool {
        let rc = foglio_move_range(rawPtr, UInt32(sheet), Int32(src.r0 + 1), Int32(src.c0 + 1), Int32(src.r1 + 1), Int32(src.c1 + 1), Int32(to.row + 1), Int32(to.col + 1), !copy)
        notifyChanged()
        return rc == 0
    }

    // MARK: names and references
    /// "Sheet!A1:B5", "'O''Brien'!$A$1", "A1" or a defined name → (sheet index, range). nil if not a plain range.
    func resolveReference(_ text: String, currentSheet: Int) -> (sheet: Int, range: GridRange)? {
        var f = text.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        guard !f.isEmpty else { return nil }
        var sheetIndex = currentSheet
        if let bang = f.lastIndex(of: "!") {
            var sname = String(f[..<bang]).trimmingCharacters(in: .whitespaces)
            if sname.hasPrefix("'") && sname.hasSuffix("'") && sname.count >= 2 {
                sname = String(sname.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            guard let i = sheetNames.firstIndex(of: sname) ?? sheetNames.firstIndex(where: { $0.caseInsensitiveCompare(sname) == .orderedSame })
            else { return nil }
            sheetIndex = i
            f = String(f[f.index(after: bang)...])
        }
        if let r = FormulaText.gridRange(f.replacingOccurrences(of: "$", with: "").uppercased()) { return (sheetIndex, r) }
        return nil
    }
    /// A defined name that refers to a plain range (sheet-scoped names of the current sheet first).
    func resolveName(_ name: String, currentSheet: Int) -> (sheet: Int, range: GridRange)? {
        let matches = definedNames.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame && ($0.scope == nil || $0.scope == currentSheet) }
        guard let n = matches.first(where: { $0.scope != nil }) ?? matches.first else { return nil }
        return resolveReference(n.formula, currentSheet: currentSheet)
    }
    func nameExists(_ name: String) -> Bool { definedNames.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } }

    /// A typed link address made openable: "a@b.it" → mailto:, "example.com" / "host:8080/x" → https://.
    static func normalizedLinkAddress(_ address: String) -> String {
        let a = address.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, !a.hasPrefix("#") else { return a }
        // A real scheme ("https:", "mailto:") is letters followed by ':' that is not a port number.
        let hasScheme = a.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:(?!\\d+(/|$|\\?|#))", options: .regularExpression) != nil
        if hasScheme { return a }
        return a.contains("@") && !a.contains("/") ? "mailto:" + a : "https://" + a
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
