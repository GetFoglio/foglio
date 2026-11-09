import AppKit

/// "Format Cells" (⌘1): number category, decimals, thousands separator, custom code, live preview.
final class FormatCellsController: NSViewController {
    private enum Category: Int, CaseIterable {
        case general, number, currency, accounting, date, time, percentage, fraction, scientific, text, custom
        var title: String {
            [L("General"), L("Number"), L("Currency"), L("Accounting"), L("Date"), L("Time"), L("Percentage"),
             L("Fraction"), L("Scientific"), L("Text"), L("Custom")][rawValue]
        }
    }

    private let book: Workbook
    private let sheet: Int
    private let cell: CellRef
    private let apply: (String) -> Void
    private let list = NSPopUpButton(frame: .zero, pullsDown: false)
    private let decimals = NSStepper()
    private let decimalsField = NSTextField()
    private let thousands = NSButton(checkboxWithTitle: L("Use 1000 separator"), target: nil, action: nil)
    private let datePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let codeField = NSTextField()
    private let preview = NSTextField(labelWithString: "")
    private let sampleValue: String
    private var category = Category.general

    private let dateCodes = ["dd/mm/yyyy", "d/m/yy", "dd-mmm-yyyy", "d mmmm yyyy", "dddd d mmmm yyyy", "mmm yyyy", "yyyy-mm-dd", "dd/mm/yyyy hh:mm"]
    private let timeCodes = ["hh:mm", "hh:mm:ss", "h:mm AM/PM", "[h]:mm:ss", "mm:ss"]

    init(book: Workbook, sheet: Int, cell: CellRef, apply: @escaping (String) -> Void) {
        self.book = book
        self.sheet = sheet
        self.cell = cell
        self.apply = apply
        self.sampleValue = book.input(sheet: sheet, row: cell.row, col: cell.col)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        Category.allCases.forEach { list.addItem(withTitle: $0.title) }
        list.target = self; list.action = #selector(categoryChanged)
        decimals.minValue = 0; decimals.maxValue = 15; decimals.increment = 1; decimals.valueWraps = false
        decimals.target = self; decimals.action = #selector(decimalsChanged)
        decimalsField.integerValue = 2
        decimalsField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        decimalsField.target = self; decimalsField.action = #selector(decimalsTyped)
        thousands.target = self; thousands.action = #selector(rebuildCode)
        dateCodes.forEach { datePopup.addItem(withTitle: $0) }
        datePopup.target = self; datePopup.action = #selector(rebuildCode)
        codeField.target = self; codeField.action = #selector(codeTyped)
        codeField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        preview.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let decRow = NSStackView(views: [decimalsField, decimals])
        grid.addRow(with: [NSTextField(labelWithString: L("Category:")), list])
        grid.addRow(with: [NSTextField(labelWithString: L("Decimal places:")), decRow])
        grid.addRow(with: [NSGridCell.emptyContentView, thousands])
        grid.addRow(with: [NSTextField(labelWithString: L("Type:")), datePopup])
        grid.addRow(with: [NSTextField(labelWithString: L("Format code:")), codeField])
        grid.addRow(with: [NSTextField(labelWithString: L("Sample:")), preview])
        grid.column(at: 0).xPlacement = .trailing
        let ok = NSButton(title: L("OK"), target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), cancel, ok])
        let root = NSStackView(views: [grid, buttons])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        view = root
        load(book.style(sheet: sheet, row: cell.row, col: cell.col).numFmt)
    }

    private func load(_ code: String) {
        let lower = code.lowercased()
        if lower == "general" { category = .general }
        else if code == "@" { category = .text }
        else if lower.contains("e+") { category = .scientific }
        else if code.contains("?/") { category = .fraction }
        else if code.contains("%") { category = .percentage }
        else if code.hasPrefix("_") { category = .accounting }
        else if dateCodes.contains(lower) { category = .date; datePopup.selectItem(withTitle: lower) }
        else if timeCodes.contains(lower) { category = .time }
        else if code.contains("€") || code.contains("$") || code.contains("£") { category = .currency }
        else if code.contains("0") || code.contains("#") { category = .number }
        else { category = .custom }
        let dec = code.split(separator: ".").dropFirst().first.map { $0.prefix { $0 == "0" }.count } ?? 0
        decimalsField.integerValue = dec
        decimals.integerValue = dec
        thousands.state = code.contains(",") ? .on : .off
        codeField.stringValue = code
        list.selectItem(at: category.rawValue)
        updateControls()
        updatePreview()
    }

    private func updateControls() {
        let numeric: Set<Category> = [.number, .currency, .accounting, .percentage, .scientific]
        decimals.isEnabled = numeric.contains(category)
        decimalsField.isEnabled = decimals.isEnabled
        thousands.isEnabled = category == .number
        datePopup.isEnabled = category == .date || category == .time
        if category == .time && datePopup.numberOfItems != timeCodes.count {
            datePopup.removeAllItems(); timeCodes.forEach { datePopup.addItem(withTitle: $0) }
        } else if category == .date && datePopup.numberOfItems != dateCodes.count {
            datePopup.removeAllItems(); dateCodes.forEach { datePopup.addItem(withTitle: $0) }
        }
    }

    @objc private func categoryChanged() {
        category = Category(rawValue: list.indexOfSelectedItem) ?? .general
        updateControls()
        rebuildCode()
    }
    @objc private func decimalsChanged() { decimalsField.integerValue = decimals.integerValue; rebuildCode() }
    @objc private func decimalsTyped() { decimals.integerValue = max(0, min(15, decimalsField.integerValue)); rebuildCode() }
    @objc private func codeTyped() { category = .custom; list.selectItem(at: category.rawValue); updatePreview() }

    @objc private func rebuildCode() {
        let d = decimals.integerValue
        let frac = d > 0 ? "." + String(repeating: "0", count: d) : ""
        let cur = Locale.current.currencySymbol ?? "€"
        let code: String
        switch category {
        case .general: code = "general"
        case .number: code = (thousands.state == .on ? "#,##0" : "0") + frac
        case .currency: code = cur == "$" ? "$#,##0\(frac)" : "#,##0\(frac) \"\(cur)\""
        case .accounting: code = "_-* #,##0\(frac) \"\(cur)\"_-;-* #,##0\(frac) \"\(cur)\"_-;_-* \"-\"?? \"\(cur)\"_-;_-@_-"
        case .date, .time: code = datePopup.titleOfSelectedItem ?? "dd/mm/yyyy"
        case .percentage: code = "0\(frac)%"
        case .fraction: code = "# ?/?"
        case .scientific: code = "0\(d > 0 ? frac : ".00")E+00"
        case .text: code = "@"
        case .custom: code = codeField.stringValue
        }
        codeField.stringValue = code
        updatePreview()
    }

    /// Renders the active cell's value with the candidate format using the engine itself.
    private func updatePreview() {
        let scratch = Workbook()
        let fallback = FormulaLocale.current.locale.hasPrefix("en") ? "1234.5" : "1234,5"
        let isFormula = sampleValue.hasPrefix("=")
        let sample = sampleValue.isEmpty || isFormula ? fallback : sampleValue
        scratch.setInput(sheet: 0, row: 0, col: 0, sample)
        scratch.setStyle(sheet: 0, GridRange(r0: 0, c0: 0, r1: 0, c1: 0), path: "num_fmt", value: codeField.stringValue)
        preview.stringValue = scratch.formatted(sheet: 0, row: 0, col: 0)
    }

    @objc private func okPressed() {
        apply(codeField.stringValue)
        close()
    }
    @objc private func cancelPressed() { close() }
    private func close() {
        guard let w = view.window else { return }
        w.sheetParent?.endSheet(w)
    }
}
