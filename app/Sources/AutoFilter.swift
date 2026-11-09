import AppKit

/// Excel-style AutoFilter on one table per sheet: header dropdowns, value checklists, row hiding.
struct FilterState {
    var range: GridRange                 // header row + data rows
    var excluded: [Int: Set<String>] = [:]  // column -> hidden values
    var dataRows: ClosedRange<Int>? { range.r1 > range.r0 ? (range.r0 + 1)...range.r1 : nil }
}

/// Popover content: search + checklist of distinct values + sort buttons.
final class FilterPopoverController: NSViewController {
    private let values: [String]
    private var checked: Set<String>
    private let onApply: (Set<String>) -> Void
    private let onSort: (Bool) -> Void
    private var boxes: [NSButton] = []
    var closeAction: (() -> Void)?
    private let stack = NSStackView()
    private let search = NSSearchField()
    private let allBox = NSButton(checkboxWithTitle: L("(Select All)"), target: nil, action: nil)

    init(values: [String], excluded: Set<String>, onApply: @escaping (Set<String>) -> Void, onSort: @escaping (Bool) -> Void) {
        self.values = values
        self.checked = Set(values).subtracting(excluded)
        self.onApply = onApply
        self.onSort = onSort
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        let asc = NSButton(title: L("Sort A to Z"), target: self, action: #selector(sortAsc))
        let desc = NSButton(title: L("Sort Z to A"), target: self, action: #selector(sortDesc))
        asc.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil); asc.imagePosition = .imageLeading
        desc.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil); desc.imagePosition = .imageLeading
        let sortRow = NSStackView(views: [asc, desc])
        search.placeholderString = L("Search")
        search.target = self
        search.action = #selector(filterList)
        allBox.target = self
        allBox.action = #selector(toggleAll)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        let scroll = NSScrollView()
        let clip = FlippedView()
        clip.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: 4),
                                     stack.topAnchor.constraint(equalTo: clip.topAnchor, constant: 4),
                                     clip.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 4),
                                     clip.trailingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor)])
        clip.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = clip
        clip.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        let ok = NSButton(title: L("OK"), target: self, action: #selector(apply))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(close))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), cancel, ok])
        for v in [sortRow, search, allBox, scroll, buttons] as [NSView] { root.addArrangedSubview(v) }
        for v in [search, scroll, buttons] as [NSView] { v.widthAnchor.constraint(equalToConstant: 240).isActive = true }
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        view = root
        rebuild("")
    }

    private func label(_ v: String) -> String { v.isEmpty ? L("(Blanks)") : v }

    private func rebuild(_ q: String) {
        boxes.forEach { $0.removeFromSuperview() }
        boxes = values.filter { q.isEmpty || label($0).localizedCaseInsensitiveContains(q) }.prefix(2000).map { v in
            let b = NSButton(checkboxWithTitle: label(v), target: self, action: #selector(toggleOne(_:)))
            b.state = checked.contains(v) ? .on : .off
            b.identifier = NSUserInterfaceItemIdentifier(v)
            stack.addArrangedSubview(b)
            return b
        }
        allBox.state = checked.count == values.count ? .on : (checked.isEmpty ? .off : .mixed)
    }

    @objc private func filterList() { rebuild(search.stringValue) }
    @objc private func toggleOne(_ b: NSButton) {
        let v = b.identifier?.rawValue ?? ""
        if b.state == .on { checked.insert(v) } else { checked.remove(v) }
        allBox.state = checked.count == values.count ? .on : (checked.isEmpty ? .off : .mixed)
    }
    @objc private func toggleAll() {
        if allBox.state == .off { checked.removeAll() } else { allBox.state = .on; checked = Set(values) }
        boxes.forEach { $0.state = checked.contains($0.identifier?.rawValue ?? "") ? .on : .off }
    }
    @objc private func apply() { onApply(Set(values).subtracting(checked)); close() }
    @objc private func sortAsc() { onSort(true); close() }
    @objc private func sortDesc() { onSort(false); close() }
    @objc private func close() { closeAction?() }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }
