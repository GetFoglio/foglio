import AppKit

/// Excel's Home ▸ Conditional Formatting rules, applied to the selection.
enum ConditionalFormatMenu {
    struct Rule { let title: String; let kind: UInt32; let op: UInt32; let needsValue: Int; let defaultValue: String }
    static let highlight: [Rule] = [
        Rule(title: "Greater Than…", kind: 0, op: 1, needsValue: 1, defaultValue: ""),
        Rule(title: "Less Than…", kind: 0, op: 3, needsValue: 1, defaultValue: ""),
        Rule(title: "Between…", kind: 0, op: 6, needsValue: 2, defaultValue: ""),
        Rule(title: "Equal To…", kind: 0, op: 0, needsValue: 1, defaultValue: ""),
        Rule(title: "Text That Contains…", kind: 1, op: 0, needsValue: 1, defaultValue: ""),
        Rule(title: "Duplicate Values…", kind: 2, op: 0, needsValue: 0, defaultValue: ""),
        Rule(title: "Unique Values…", kind: 3, op: 0, needsValue: 0, defaultValue: ""),
        Rule(title: "Top 10 Items…", kind: 4, op: 0, needsValue: 1, defaultValue: "10"),
        Rule(title: "Bottom 10 Items…", kind: 5, op: 0, needsValue: 1, defaultValue: "10"),
        Rule(title: "Above Average…", kind: 6, op: 0, needsValue: 0, defaultValue: ""),
        Rule(title: "Below Average…", kind: 7, op: 0, needsValue: 0, defaultValue: ""),
        Rule(title: "Blanks…", kind: 11, op: 0, needsValue: 0, defaultValue: ""),
        Rule(title: "Errors…", kind: 12, op: 0, needsValue: 0, defaultValue: ""),
    ]
    static let styles = ["Light Red Fill with Dark Red Text", "Yellow Fill with Dark Yellow Text", "Green Fill with Dark Green Text",
                         "Light Red Fill", "Red Text", "Bold"]
    static let scales: [(String, UInt32)] = [("Green - Yellow - Red", 8), ("Red - Yellow - Green", 9), ("White - Blue", 10)]

    static func menu() -> NSMenuItem {
        var items: [NSMenuItem] = highlight.enumerated().map { i, r in
            Menus.item(r.title, #selector(SheetWindowController.conditionalRule(_:)), tag: i)
        }
        items.insert(.separator(), at: 5)
        items.insert(.separator(), at: 8)
        items.append(.separator())
        items.append(Menus.submenu("Color Scales", scales.enumerated().map { i, s in
            Menus.item(s.0, #selector(SheetWindowController.conditionalScale(_:)), tag: i)
        }))
        items.append(.separator())
        items.append(Menus.item("Clear Rules from Selected Cells", #selector(SheetWindowController.clearConditionalRules(_:)), tag: 0))
        items.append(Menus.item("Clear Rules from Entire Sheet", #selector(SheetWindowController.clearConditionalRules(_:)), tag: 1))
        return Menus.submenu("Conditional Formatting", items)
    }
}

extension SheetWindowController {
    @objc func conditionalRule(_ sender: NSMenuItem) {
        guard let rule = ConditionalFormatMenu.highlight[safe: sender.tag], let w = window else { return }
        guard grid.commitIfEditing() else { return }
        let range = grid.selection
        let a = NSAlert()
        a.messageText = L(rule.title).replacingOccurrences(of: "…", with: "")
        a.informativeText = L("Format cells in the selection that match the rule:")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        let f1 = NSTextField(string: rule.defaultValue), f2 = NSTextField(string: "")
        for f in [f1, f2] { f.widthAnchor.constraint(equalToConstant: 220).isActive = true }
        if rule.needsValue >= 1 { stack.addArrangedSubview(f1) }
        if rule.needsValue >= 2 {
            stack.addArrangedSubview(NSTextField(labelWithString: L("and")))
            stack.addArrangedSubview(f2)
        }
        let style = NSPopUpButton(frame: .zero, pullsDown: false)
        ConditionalFormatMenu.styles.forEach { style.addItem(withTitle: L($0)) }
        stack.addArrangedSubview(NSTextField(labelWithString: L("with")))
        stack.addArrangedSubview(style)
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: CGFloat(rule.needsValue * 28 + 60))
        a.accessoryView = stack
        a.addButton(withTitle: L("OK"))
        a.addButton(withTitle: L("Cancel"))
        a.window.initialFirstResponder = rule.needsValue > 0 ? f1 : style
        a.beginSheetModal(for: w) { [weak self] r in
            guard let self, r == .alertFirstButtonReturn else { return }
            if rule.needsValue >= 1 && f1.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { NSSound.beep(); return }
            _ = self.grid.book.addConditionalFormat(sheet: self.grid.sheet, range, kind: rule.kind, op: rule.op,
                                                    v1: f1.stringValue, v2: f2.stringValue, style: UInt32(style.indexOfSelectedItem))
            self.grid.contentChanged()
        }
    }

    @objc func conditionalScale(_ sender: NSMenuItem) {
        guard let s = ConditionalFormatMenu.scales[safe: sender.tag] else { return }
        guard grid.commitIfEditing() else { return }
        _ = grid.book.addConditionalFormat(sheet: grid.sheet, grid.selection, kind: s.1)
        grid.contentChanged()
    }

    @objc func clearConditionalRules(_ sender: NSMenuItem) {
        guard grid.commitIfEditing() else { return }
        grid.book.clearConditionalFormats(sheet: grid.sheet, sender.tag == 0 ? grid.selection : nil)
        grid.contentChanged()
    }
}
