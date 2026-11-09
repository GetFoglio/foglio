import AppKit

/// Main menu and context menus. Actions travel the responder chain:
/// GridView (cells) -> SheetWindowController (formatting, sheets, export) -> SpreadsheetDocument -> app.
enum Menus {
    static func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                     tag: Int = 0, symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: L(title), action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.tag = tag
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: L(title))
        items.forEach(m.addItem)
        let host = NSMenuItem(title: L(title), action: nil, keyEquivalent: "")
        host.submenu = m
        return host
    }

    typealias W = SheetWindowController

    static func numberFormatItems() -> [NSMenuItem] {
        // Excel for Mac shortcuts: ⌃⇧~ General, ⌃⇧! Number, ⌃⇧$ Currency, ⌃⇧# Date, ⌃⇧@ Time, ⌃⇧% Percent, ⌃⇧^ Scientific
        let keys: [Int: String] = [0: "~", 1: "!", 2: "$", 4: "#", 6: "@", 7: "%", 9: "^"]
        return NumberFormats.all.enumerated().map { i, f in
            item(f.title, #selector(W.applyNumberFormat(_:)), keys[i] ?? "", [.control, .shift], tag: i)
        }
    }

    static func borderItems() -> [NSMenuItem] {
        // ⌥⌘0 outline, ⌥⌘- no border (Excel for Mac)
        Borders.all.enumerated().map { i, b in
            let key = b.kind == "Outer" && b.style == "thin" ? "0" : (b.kind == "None" ? "-" : "")
            return item(b.title, #selector(W.applyBorder(_:)), key, [.command, .option], tag: i, symbol: b.symbol)
        }
    }

    static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appName = "Foglio"

        let services = NSMenu()
        NSApp.servicesMenu = services
        let servicesItem = NSMenuItem(title: L("Services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        main.addItem(submenu(appName, [
            NSMenuItem(title: String(format: L("About %@"), appName), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            servicesItem,
            .separator(),
            NSMenuItem(title: String(format: L("Hide %@"), appName), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            NSMenuItem(title: String(format: L("Quit %@"), appName), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))

        let recent = submenu("Open Recent", [item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))])
        main.addItem(submenu("File", [
            item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            recent,
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save", #selector(NSDocument.save(_:)), "s"),
            item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            item("Duplicate", #selector(NSDocument.duplicate(_:))),
            item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))),
            .separator(),
            item("Export as CSV…", #selector(W.exportCSV(_:))),
            item("Export as PDF…", #selector(W.exportPDF(_:))),
            .separator(),
            item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]),
            item("Print…", #selector(NSDocument.printDocument(_:)), "p"),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", #selector(GridView.undo(_:)), "z"),
            item("Redo", #selector(GridView.redo(_:)), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste Special…", #selector(GridView.pasteSpecial(_:)), "v", [.command, .control]),
            item("Paste Values", #selector(GridView.pasteValues(_:)), "v", [.command, .option, .shift]),
            item("Repeat", #selector(GridView.repeatLastAction(_:)), "y"),
            .separator(),
            item("Delete", #selector(NSText.delete(_:))),
            item("Delete Cells…", #selector(GridView.deleteCellsDialog(_:)), "-", [.command]),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Fill Down", #selector(GridView.fillDown(_:)), "d"),
            item("Fill Right", #selector(GridView.fillRight(_:)), "r"),
            submenu("Clear", [
                item("Contents", #selector(NSText.delete(_:))),
                item("Formats", #selector(GridView.clearFormatsAction(_:))),
                item("All", #selector(GridView.clearAll(_:))),
            ]),
            .separator(),
            item("Find…", #selector(W.showFind(_:)), "f"),
            item("Find Next", #selector(W.findNext(_:)), "g"),
            item("Find Previous", #selector(W.findPrevious(_:)), "g", [.command, .shift]),
            item("Replace…", #selector(W.showReplace(_:)), "f", [.command, .option]),
            item("Go To…", #selector(W.goTo(_:)), "g", [.control]),
        ]))

        main.addItem(submenu("View", [
            item("Zoom In", #selector(GridView.zoomIn(_:)), "=", [.command, .option]),
            item("Zoom Out", #selector(GridView.zoomOut(_:)), "-", [.command, .option]),
            item("Actual Size", #selector(GridView.actualSize(_:)), "0"),
            .separator(),
            item("Freeze Panes", #selector(GridView.freezePanes(_:))),
            item("Freeze Top Row", #selector(GridView.freezeTopRow(_:))),
            item("Freeze First Column", #selector(GridView.freezeFirstColumn(_:))),
            .separator(),
            item("Gridlines", #selector(GridView.toggleGridlines(_:))),
            item("Show Formulas", #selector(GridView.toggleShowFormulas(_:)), "`", [.control]),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        main.addItem(submenu("Insert", [
            item("Cells…", #selector(GridView.insertCellsDialog(_:)), "i", [.control]),
            item("Rows", #selector(GridView.insertRows(_:))),
            item("Columns", #selector(GridView.insertColumns(_:))),
            item("Sheet", #selector(W.addSheet(_:)), "n", [.command, .shift]),
            .separator(),
            item("AutoSum", #selector(W.autoSumMenu(_:)), "t", [.command, .shift], tag: 0),
            item("Function…", #selector(W.insertFunction(_:))),
            ChartsUI.insertMenuItem(),   // Foglio charts: Insert ▸ Chart (ChartsLayer.swift)
            submenu("Name", [
                item("Define Name…", #selector(W.defineName(_:))),
                item("Name Manager…", #selector(W.nameManager(_:)), "l", [.command, .control]),
            ]),
            .separator(),
            item("Current Date", #selector(W.insertDate(_:)), ";", [.control]),
            item("Current Time", #selector(W.insertTime(_:)), ";", [.command]),
        ]))

        main.addItem(submenu("Format", [
            item("Bold", #selector(W.boldAction(_:)), "b"),
            item("Italic", #selector(W.italicAction(_:)), "i"),
            item("Underline", #selector(W.underlineAction(_:)), "u"),
            item("Strikethrough", #selector(W.strikeAction(_:)), "x", [.command, .shift]),
            .separator(),
            item("Cells…", #selector(W.formatCells(_:)), "1"),
            submenu("Number", numberFormatItems()),
            item("Increase Decimal", #selector(W.increaseDecimals(_:))),
            item("Decrease Decimal", #selector(W.decreaseDecimals(_:))),
            .separator(),
            submenu("Alignment", [
                item("Align Left", #selector(W.alignLeft(_:)), "{", [.command]),
                item("Center", #selector(W.alignCenter(_:)), "|", [.command]),
                item("Align Right", #selector(W.alignRight(_:)), "}", [.command]),
                .separator(),
                item("Top", #selector(W.valignTop(_:))),
                item("Middle", #selector(W.valignMiddle(_:))),
                item("Bottom", #selector(W.valignBottom(_:))),
            ]),
            item("Wrap Text", #selector(W.wrapAction(_:))),
            item("Merge & Center", #selector(GridView.mergeAndCenter(_:))),
            submenu("Borders", borderItems()),
            ConditionalFormatMenu.menu(),
            .separator(),
            submenu("Row", [
                item("Height…", #selector(GridView.rowHeight(_:))),
                item("AutoFit", #selector(GridView.autofitSelectedRows(_:))),
                item("Hide", #selector(GridView.hideRows(_:)), "9", [.control]),
                item("Unhide", #selector(GridView.unhideRows(_:)), "9", [.control, .shift]),
            ]),
            submenu("Column", [
                item("Width…", #selector(GridView.columnWidth(_:))),
                item("AutoFit Selection", #selector(GridView.autofitSelectedColumns(_:))),
                item("Hide", #selector(GridView.hideColumns(_:)), "0", [.control]),
                item("Unhide", #selector(GridView.unhideColumns(_:)), "0", [.control, .shift]),
            ]),
            submenu("Sheet", [
                item("Rename…", #selector(W.renameSheet(_:))),
                item("Duplicate", #selector(W.duplicateSheet(_:))),
                item("Delete", #selector(W.deleteSheet(_:))),
                item("Hide", #selector(W.hideSheet(_:))),
                item("Unhide…", #selector(W.unhideSheet(_:))),
            ]),
            .separator(),
            item("Clear Formats", #selector(GridView.clearFormatsAction(_:))),
        ]))

        main.addItem(submenu("Data", [
            item("Sort A to Z", #selector(GridView.sortAscending(_:)), symbol: "arrow.up"),
            item("Sort Z to A", #selector(GridView.sortDescending(_:)), symbol: "arrow.down"),
            item("Sort…", #selector(GridView.sortDialog(_:)), "r", [.command, .shift]),
            .separator(),
            item("Filter", #selector(GridView.toggleFilter(_:)), "f", [.command, .shift], symbol: "line.3.horizontal.decrease.circle"),
            .separator(),
            item("Remove Duplicates…", #selector(GridView.removeDuplicates(_:))),
            item("Text to Columns…", #selector(GridView.textToColumns(_:))),
            .separator(),
            item("Calculate Now", #selector(GridView.recalculate(_:)), "=", [.command]),
        ]))

        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        let wi = NSMenuItem(title: L("Window"), action: nil, keyEquivalent: "")
        wi.submenu = windowMenu
        main.addItem(wi)
        NSApp.windowsMenu = windowMenu

        let help = NSMenu(title: L("Help"))
        help.addItem(item("Function Reference", #selector(W.insertFunction(_:))))
        let hi = NSMenuItem(title: L("Help"), action: nil, keyEquivalent: "")
        hi.submenu = help
        main.addItem(hi)
        NSApp.helpMenu = help
        return main
    }

    static func cellMenu() -> NSMenu {
        let m = NSMenu()
        [item("Cut", #selector(NSText.cut(_:))), item("Copy", #selector(NSText.copy(_:))),
         item("Paste", #selector(NSText.paste(_:))), item("Paste Special…", #selector(GridView.pasteSpecial(_:))),
         .separator(),
         item("Insert…", #selector(GridView.insertCellsDialog(_:))), item("Delete…", #selector(GridView.deleteCellsDialog(_:))),
         .separator(),
         item("Insert Rows", #selector(GridView.insertRows(_:))), item("Insert Columns", #selector(GridView.insertColumns(_:))),
         item("Delete Rows", #selector(GridView.deleteRows(_:))), item("Delete Columns", #selector(GridView.deleteColumns(_:))),
         item("Clear Contents", #selector(NSText.delete(_:))),
         .separator(),
         item("Sort A to Z", #selector(GridView.sortAscending(_:))), item("Sort Z to A", #selector(GridView.sortDescending(_:))),
         .separator(),
         item("Format Cells…", #selector(W.formatCells(_:))),
         submenu("Number", numberFormatItems()),
         submenu("Borders", borderItems()),
         item("Merge & Center", #selector(GridView.mergeAndCenter(_:))),
         item("Wrap Text", #selector(W.wrapAction(_:))),
         item("Clear Formats", #selector(GridView.clearFormatsAction(_:))),
        ].forEach(m.addItem)
        return m
    }

    static func columnMenu() -> NSMenu {
        let m = NSMenu()
        [item("Cut", #selector(NSText.cut(_:))), item("Copy", #selector(NSText.copy(_:))), item("Paste", #selector(NSText.paste(_:))),
         .separator(),
         item("Insert Columns", #selector(GridView.insertColumns(_:))), item("Delete Columns", #selector(GridView.deleteColumns(_:))),
         item("Clear Contents", #selector(NSText.delete(_:))),
         .separator(),
         item("Column Width…", #selector(GridView.columnWidth(_:))), item("AutoFit Selection", #selector(GridView.autofitSelectedColumns(_:))),
         item("Hide", #selector(GridView.hideColumns(_:))), item("Unhide", #selector(GridView.unhideColumns(_:))),
         .separator(),
         item("Sort A to Z", #selector(GridView.sortAscending(_:))), item("Sort Z to A", #selector(GridView.sortDescending(_:))),
        ].forEach(m.addItem)
        return m
    }

    static func rowMenu() -> NSMenu {
        let m = NSMenu()
        [item("Cut", #selector(NSText.cut(_:))), item("Copy", #selector(NSText.copy(_:))), item("Paste", #selector(NSText.paste(_:))),
         .separator(),
         item("Insert Rows", #selector(GridView.insertRows(_:))), item("Delete Rows", #selector(GridView.deleteRows(_:))),
         item("Clear Contents", #selector(NSText.delete(_:))),
         .separator(),
         item("Row Height…", #selector(GridView.rowHeight(_:))),
         item("Hide", #selector(GridView.hideRows(_:))), item("Unhide", #selector(GridView.unhideRows(_:))),
        ].forEach(m.addItem)
        return m
    }
}

/// Excel number formats offered in the UI (codes follow the user's locale for dates and currency).
enum NumberFormats {
    struct F { let title: String; let code: String }
    static var all: [F] {
        let loc = FormulaLocale.current.locale
        let cur = Locale.current.currencySymbol ?? "€"
        let shortDate = loc == "en" ? "m/d/yyyy" : (loc == "de" ? "dd.mm.yyyy" : "dd/mm/yyyy")
        let longDate = loc.hasPrefix("en") ? "dddd, mmmm d, yyyy" : "dddd d mmmm yyyy"
        let prefixCurrency = cur == "$" || cur == "£"
        return [
            F(title: L("General"), code: "general"),
            F(title: L("Number"), code: "#,##0.00"),
            F(title: L("Currency"), code: prefixCurrency ? "\(cur)#,##0.00" : "#,##0.00 \"\(cur)\""),
            F(title: L("Accounting"), code: cur == "$" ? "_($* #,##0.00_);_($* (#,##0.00);_($* \"-\"??_);_(@_)" : "_-* #,##0.00 \"\(cur)\"_-;-* #,##0.00 \"\(cur)\"_-;_-* \"-\"?? \"\(cur)\"_-;_-@_-"),
            F(title: L("Short Date"), code: shortDate),
            F(title: L("Long Date"), code: longDate),
            F(title: L("Time"), code: "hh:mm:ss"),
            F(title: L("Percentage"), code: "0.00%"),
            F(title: L("Fraction"), code: "# ?/?"),
            F(title: L("Scientific"), code: "0.00E+00"),
            F(title: L("Text"), code: "@"),
        ]
    }

    /// Adds or removes one decimal place in the first section of a format code.
    static func adjustDecimals(_ code: String, by d: Int) -> String {
        var c = code
        if c.lowercased() == "general" { c = d > 0 ? "0.0" : "0" ; return c }
        let sections = c.components(separatedBy: ";")
        let adjusted = sections.map { s -> String in
            var s = s
            if let dot = s.firstIndex(of: ".") {
                var end = s.index(after: dot)
                while end < s.endIndex, s[end] == "0" || s[end] == "#" { end = s.index(after: end) }
                let decimals = s.distance(from: dot, to: end) - 1
                if d > 0 { s.insert("0", at: end) }
                else if decimals > 1 { s.remove(at: s.index(before: end)) }
                else { s.removeSubrange(dot..<end) }
            } else if d > 0, let last = s.lastIndex(where: { $0 == "0" || $0 == "#" }) {
                s.insert(contentsOf: ".0", at: s.index(after: last))
            }
            return s
        }
        return adjusted.joined(separator: ";")
    }
}

enum Borders {
    struct B { let title: String; let kind: String; let style: String; let symbol: String }
    static let all: [B] = [
        B(title: L("Bottom Border"), kind: "Bottom", style: "thin", symbol: "square.bottomhalf.filled"),
        B(title: L("Top Border"), kind: "Top", style: "thin", symbol: "square.tophalf.filled"),
        B(title: L("Left Border"), kind: "Left", style: "thin", symbol: "square.lefthalf.filled"),
        B(title: L("Right Border"), kind: "Right", style: "thin", symbol: "square.righthalf.filled"),
        B(title: L("No Border"), kind: "None", style: "thin", symbol: "square.dashed"),
        B(title: L("All Borders"), kind: "All", style: "thin", symbol: "square.grid.2x2"),
        B(title: L("Outside Borders"), kind: "Outer", style: "thin", symbol: "square"),
        B(title: L("Thick Outside Borders"), kind: "Outer", style: "medium", symbol: "square.fill"),
        B(title: L("Thick Bottom Border"), kind: "Bottom", style: "medium", symbol: "underline"),
    ]
}
