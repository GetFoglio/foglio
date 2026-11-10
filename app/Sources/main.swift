import AppKit
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let env = ProcessInfo.processInfo.environment

    func applicationWillFinishLaunching(_ n: Notification) {
        Perf.shared.mark("WILL_FINISH")
        if let a = env["FOGLIO_APPEARANCE"] { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
        FormulaLocale.current.apply()
        NSApp.mainMenu = Menus.mainMenu()
        NSWindow.allowsAutomaticWindowTabbing = true
        // Crash safety: unsaved changes are backed up every 30 s and offered again after a crash.
        NSDocumentController.shared.autosavingDelay = 30
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        Perf.shared.mark("DID_FINISH")
        // Command-line paths (handy for scripts/tests): open them like Finder would.
        let args = AppDelegate.pathArguments.filter { FileManager.default.fileExists(atPath: $0) }
        for path in args {
            NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { [weak self] _, _, err in
                if let err {
                    // Automated corpus runs: report and quit instead of waiting on an alert.
                    if self?.env["FOGLIO_EXIT_AFTER_FIRST_FRAME"] != nil { print("OPEN_ERROR=\(((err as NSError).userInfo[NSUnderlyingErrorKey] as? Error)?.localizedDescription ?? err.localizedDescription)"); fflush(stdout); exit(3) }
                    NSApp.presentError(err)
                }
            }
        }
        setUpBenchmarks()
        if !Perf.shared.enabled { NSApp.activate() }
        // Scripted runs open their blank workbook themselves: AppKit's launch-time untitled document depends on how
        // the process was started (it never comes when another copy of Foglio is already running).
        else if AppDelegate.pathArguments.isEmpty { NSDocumentController.shared.newDocument(nil) }
    }

    /// Command-line arguments that are paths (not `-Key value` user-default pairs such as `-ApplePersistenceIgnoreState YES`).
    static let pathArguments: [String] = {
        var out: [String] = [], skipValue = false
        for a in CommandLine.arguments.dropFirst() {
            if skipValue { skipValue = false; continue }
            if a.hasPrefix("-") { skipValue = true; continue }
            out.append(a)
        }
        return out
    }()

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        AppDelegate.pathArguments.isEmpty && !Perf.shared.enabled
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private var settingsWindow: NSWindow?

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 170), styleMask: [.titled, .closable], backing: .buffered, defer: true)
            w.title = L("Settings")
            w.isReleasedWhenClosed = false
            let grid = NSGridView(numberOfColumns: 2, rows: 0)
            grid.rowSpacing = 10
            grid.columnSpacing = 10
            let langs: [(String, String?)] = [(L("Automatic"), nil), ("English", "en"), ("Italiano", "it"), ("Deutsch", "de"), ("Español", "es"), ("Français", "fr")]
            let locales: [(String, String?)] = [(L("Automatic"), nil), ("English (US)", "en"), ("English (UK)", "en-GB"), ("Italiano", "it"),
                                                ("Deutsch", "de"), ("Español", "es"), ("Français", "fr")]
            func popup(_ items: [(String, String?)], key: String) -> NSPopUpButton {
                let p = NSPopUpButton(frame: .zero, pullsDown: false)
                for (t, v) in items { p.addItem(withTitle: t); p.lastItem?.representedObject = v }
                let current = UserDefaults.standard.string(forKey: key)
                p.selectItem(at: items.firstIndex { $0.1 == current } ?? 0)
                p.target = self
                p.action = #selector(settingChanged(_:))
                p.identifier = NSUserInterfaceItemIdentifier(key)
                return p
            }
            grid.addRow(with: [NSTextField(labelWithString: L("Function names:")), popup(langs, key: "FormulaLanguage")])
            grid.addRow(with: [NSTextField(labelWithString: L("Numbers and dates:")), popup(locales, key: "FormulaLocale")])
            let note = NSTextField(wrappingLabelWithString: L("Changes apply after restarting Foglio. Files always store formulas in Excel's standard format, so they open correctly in any language."))
            note.font = .systemFont(ofSize: 11)
            note.textColor = .secondaryLabelColor
            note.preferredMaxLayoutWidth = 380
            grid.addRow(with: [NSGridCell.emptyContentView, note])
            grid.column(at: 0).xPlacement = .trailing
            let container = NSView()
            container.addSubview(grid)
            grid.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                                         grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20)])
            w.contentView = container
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func settingChanged(_ p: NSPopUpButton) {
        guard let key = p.identifier?.rawValue else { return }
        if let v = p.selectedItem?.representedObject as? String { UserDefaults.standard.set(v, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    // MARK: - Benchmarks / demo (only with FOGLIO_* environment variables)

    private var firstController: SheetWindowController? {
        (NSDocumentController.shared.documents.first as? SpreadsheetDocument)?.windowController
    }

    /// N rows of a small sales table with formulas, written in the current formula language.
    private func fillDemo(_ c: SheetWindowController, rows: Int) {
        let sep = Workbook.argSeparator
        let dec = FormulaLocale.current.language == "en" || FormulaLocale.current.locale.hasPrefix("en") ? "." : ","
        let IF = Workbook.localName("IF"), SUM = Workbook.localName("SUM"), COUNTIF = Workbook.localName("COUNTIF")
        var tsv = "Prodotto\tQuantità\tPrezzo\tImponibile\tIVA\tTotale\tFascia\n"
        tsv.reserveCapacity(rows * 90)
        for i in 1...rows {
            let r = i + 1
            let price = String(format: "%.2f", Double((i * 13) % 400) / 4 + 1).replacingOccurrences(of: ".", with: dec)
            tsv += "Articolo \(i)\t\((i * 7) % 50 + 1)\t\(price)\t=B\(r)*C\(r)\t=D\(r)*0\(dec)22\t=D\(r)+E\(r)\t=\(IF)(F\(r)>2000\(sep)\"alto\"\(sep)\"basso\")\n"
        }
        let n = rows + 1
        tsv += "Totale\t=\(SUM)(B2:B\(n))\t\t=\(SUM)(D2:D\(n))\t=\(SUM)(E2:E\(n))\t=\(SUM)(F2:F\(n))\t=\(COUNTIF)(G2:G\(n)\(sep)\"alto\")\n"
        let t = Date()
        c.grid.book.pasteText(sheet: 0, row: 0, col: 0, tsv)
        Perf.shared.emit("DEMO_FILL_MS", String(format: "%.1f", Date().timeIntervalSince(t) * 1000))
        c.grid.book.setStyle(sheet: 0, GridRange(r0: 0, c0: 0, r1: 0, c1: 6), path: "font.b", value: "true")
        c.grid.contentChanged()
    }

    private func setUpBenchmarks() {
        let frames = env["FOGLIO_AUTOSCROLL"].flatMap(Int.init)
        let exitAfterFirst = env["FOGLIO_EXIT_AFTER_FIRST_FRAME"] != nil
        let snapshot = env["FOGLIO_SNAPSHOT"]
        if let demo = env["FOGLIO_DEMO"].flatMap(Int.init) {
            DispatchQueue.main.async { if let c = self.firstController { self.fillDemo(c, rows: demo) } }
        }
        Perf.shared.onFirstFrame = { [weak self] in
            if exitAfterFirst { exit(0) }
            guard let c = self?.firstController else { return }
            if let w = c.window { Perf.shared.emit("WINDOW_ID", "\(w.windowNumber)") }
            if let snapshot {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let script = self?.env["FOGLIO_SCRIPT"] ?? ""
                    c.window?.makeKey()   // key within the app, without activating it (no focus stealing)
                    UIScript.runAsync(script, on: c) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            if snapshot != "/dev/null" { Snapshot.write(c.window, to: snapshot) }
                            exit(0)
                        }
                    }
                }
            } else if let frames {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { c.grid.startAutoScroll(frames: frames) }
            }
        }
        NotificationCenter.default.addObserver(forName: .foglioBenchmarkDone, object: nil, queue: .main) { [weak self] _ in
            guard self?.env["FOGLIO_EXIT"] != nil else { return }
            exit(0)
        }
    }
}

/// Renders a window's content to PNG (for automated visual checks; no screen-recording permission needed).
enum Snapshot {
    /// Renders the whole window (title bar, toolbar controls, grid) from its layer tree to PNG.
    /// No screen-recording permission needed: the app draws itself.
    static func write(_ window: NSWindow?, to path: String) {
        guard let w = window, let frameView = w.contentView?.superview else { return }
        frameView.wantsLayer = true
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        CATransaction.flush()
        let scale = w.backingScaleFactor
        let size = frameView.bounds.size
        guard let layer = frameView.layer,
              let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        if !frameView.isFlipped { ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1) }
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)   // CALayer render is y-up
        layer.render(in: ctx)
        // Child windows (autocomplete list, hints) on top, at their positions relative to the window.
        var overlays = (w.childWindows ?? []).filter(\.isVisible)
        if let sheet = w.attachedSheet { overlays.append(sheet) }
        for child in overlays {
            guard let cl = child.contentView?.superview?.layer ?? child.contentView?.layer else { continue }
            child.contentView?.superview?.wantsLayer = true
            let r = child.frame
            ctx.saveGState()
            ctx.translateBy(x: r.minX - w.frame.minX, y: r.minY - w.frame.minY)
            cl.render(in: ctx)
            ctx.restoreGState()
        }
        guard let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// Tiny scripting hook for automated UI checks: "select B4:D9; type =SUM(B2:B5); key return; ..."
enum UIScript {
    /// State of the "visible" command between steps.
    static var lastVisible: (rows: ClosedRange<Int>, cols: ClosedRange<Int>)?
    static var visibleCount = 0
    /// Pointer of the last mousedown/mousedrag step (window coordinates).
    static var lastMouse = NSPoint.zero
    /// Runs steps one per run-loop turn (80 ms apart) so popups, focus changes and redraws happen like real use.
    static func runAsync(_ script: String, on c: SheetWindowController, done: @escaping () -> Void) {
        var steps = script.components(separatedBy: ";;").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func next() {
            guard !steps.isEmpty else { done(); return }
            let step = steps.removeFirst()
            run(step, on: c)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { next() }
        }
        next()
    }

    private static let keyCodes: [String: (UInt16, String)] = [
        "return": (36, "\r"), "tab": (48, "\t"), "esc": (53, "\u{1b}"), "delete": (51, "\u{7f}"),
        "up": (126, "\u{F700}"), "down": (125, "\u{F701}"), "left": (123, "\u{F702}"), "right": (124, "\u{F703}"),
        "f2": (120, "\u{F705}"), "f9": (101, "\u{F70C}"), "pagedown": (121, "\u{F72D}"), "pageup": (116, "\u{F72C}"), "f4": (118, "\u{F707}"), "space": (49, " "), "home": (115, "\u{F729}"),
    ]

    /// Sends a real key event through the window (same path as the keyboard).
    static func sendKey(_ chars: String, code: UInt16, mods: NSEvent.ModifierFlags, to w: NSWindow) {
        GridView.testModifiers = mods
        defer { GridView.testModifiers = nil }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                // Same order as the run loop: the editor's key monitor first, then normal dispatch.
                if type == .keyDown, let g = (w.windowController as? SheetWindowController)?.grid, g.handleEditingKey(e) { continue }
                NSApp.sendEvent(e)
            }
        }
    }

    static func sendClick(at p: NSPoint, count: Int, mods: NSEvent.ModifierFlags = [], right: Bool = false, to w: NSWindow) {
        let types: [NSEvent.EventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1) {
                NSApp.sendEvent(e)
            }
        }
    }

    static func menuItem(key: String, mods: NSEvent.ModifierFlags, in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.keyEquivalent.lowercased() == key && item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) == mods.intersection([.command, .shift, .option, .control]) {
                return item
            }
            if let sub = menuItem(key: key, mods: mods, in: item.submenu) { return sub }
        }
        return nil
    }

    static func run(_ cmd: String, on c: SheetWindowController) {
        do {
            let parts = cmd.split(separator: " ", maxSplits: 1).map(String.init)
            guard let verb = parts.first else { return }
            let arg = parts.count > 1 ? parts[1] : ""
            switch verb {
            case "select": if let r = FormulaText.gridRange(arg.uppercased()) { c.grid.select(range: r) }
            case "input":
                let kv = arg.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2, let ref = parseA1(kv[0]) { c.grid.book.setInput(sheet: c.grid.sheet, row: ref.row, col: ref.col, kv[1]); c.grid.contentChanged() }
            case "edit": c.grid.beginEditing(.edit, initial: arg)
            case "freeze": c.grid.select(parseA1(arg) ?? CellRef(row: 1, col: 1)); c.grid.freezePanes(nil)
            case "bold": c.boldAction(nil)
            case "fill": c.grid.setStyle("fill.fg_color", arg)
            case "border": c.grid.setBorder(arg)
            case "merge": c.grid.mergeAndCenter(nil)
            case "zoom": c.grid.zoom = CGFloat(Double(arg) ?? 1)
            case "sheet": c.addSheet(nil)
            case "format": c.grid.setStyle("num_fmt", arg)
            case "wrap": c.wrapAction(nil)
            case "width": if let ref = parseA1(arg + "1") { c.grid.book.setColumnWidth(sheet: c.grid.sheet, ref.col, ref.col, px: 200); c.grid.contentChanged() }
            case "autofilter": c.grid.toggleFilter(nil)
            case "exclude": // exclude G alto
                let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if p.count == 2, let ref = parseA1(p[0] + "1") { c.grid.applyFilter(col: ref.col, excluded: [p[1]]) }
            case "savetypes": // what the Save panel offers for this document
                if let d = c.document as? SpreadsheetDocument {
                    print("SAVETYPES", d.writableTypes(for: .saveOperation).joined(separator: ","), "filetype=\(d.fileType ?? "")")
                }
            case "savedoc": // savedoc /path/file.xlsm|xlsx|csv|tsv  (the document's own write path)
                let url = URL(fileURLWithPath: arg)
                let type = ["xlsm": FileTypes.xlsm, "csv": FileTypes.csv, "tsv": FileTypes.tsv][url.pathExtension.lowercased()] ?? FileTypes.xlsx
                do { try (c.document as? SpreadsheetDocument)?.write(to: url, ofType: type); print("SAVEDDOC", arg, "macros=\(Workbook.hasMacros(url))") }
                catch { print("SAVE_ERROR", error) }
            case "savexlsx":
                do { try c.grid.book.saveXLSX(to: URL(fileURLWithPath: arg)); print("SAVED", arg) } catch { print("SAVE_ERROR", error) }
            case "print":
                if let ref = parseA1(arg) { print("CELL", arg, "=", c.grid.book.formatted(sheet: c.grid.sheet, row: ref.row, col: ref.col), "|", c.grid.book.input(sheet: c.grid.sheet, row: ref.row, col: ref.col)) }
            case "type": // type characters one key event each
                guard let w = c.window else { break }
                for ch in arg { sendKey(String(ch), code: 0, mods: [], to: w) }
            case "key": // key return | key shift+tab | key cmd+b
                guard let w = c.window else { break }
                var mods: NSEvent.ModifierFlags = []
                var name = arg.lowercased()
                var stripped = true
                while stripped {
                    stripped = false
                    for (prefix, flag) in [("shift+", NSEvent.ModifierFlags.shift), ("cmd+", .command), ("opt+", .option), ("ctrl+", .control)]
                    where name.hasPrefix(prefix) { mods.insert(flag); name.removeFirst(prefix.count); stripped = true }
                }
                if let (code, chars) = keyCodes[name] { sendKey(chars, code: code, mods: mods, to: w) }
                else if name.count == 1 {
                    if mods.contains(.command) || mods.contains(.control), let item = menuItem(key: name, mods: mods, in: NSApp.mainMenu) {
                        // Same as the menu bar: validate, then send the action down the window's responder chain.
                        let responder = w.firstResponder ?? w
                        if let action = item.action, responder.tryToPerform(action, with: item) { print("MENU", item.title) }
                        else { print("MENU_UNHANDLED", item.title) }
                    } else { sendKey(name, code: 0, mods: mods, to: w) }
                }
            case "click", "dblclick", "shiftclick", "rightclick": // click B5
                guard let w = c.window, let ref = parseA1(arg) else { break }
                let p = c.grid.windowPoint(for: ref)
                sendClick(at: p, count: cmd.hasPrefix("dbl") ? 2 : 1, mods: cmd.hasPrefix("shift") ? .shift : [], right: cmd.hasPrefix("right"), to: w)
            case "view": // zoom and AutoFilter of the current sheet (as shown and as saved)
                let g = c.grid!
                let f = g.filters[g.sheet]
                let ex = f?.excluded.sorted { $0.key < $1.key }.map { "\(columnName($0.key)):\($0.value.sorted().joined(separator: "|"))" }.joined(separator: ",") ?? ""
                print("VIEW zoom=\(Int((g.zoom * 100).rounded())) saved=\(g.book.sheetZoom(g.sheet)) filter=\(f?.range.a1 ?? "none") excluded=\(ex)")
            case "shown": // the text the grid shows in a cell (after "show zeros" and number formats)
                if let ref = parseA1(arg) {
                    let cell = c.grid.book.viewport(sheet: c.grid.sheet, rows: ref.row...ref.row, cols: ref.col...ref.col).first
                    print("SHOWN \(arg)=\(cell?.text ?? "")")
                }
            case "filtercol": // filtercol B a|b  — hides the listed values of column B (the filter must exist)
                let parts = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if let col = parts.first.flatMap({ parseA1($0 + "1")?.col }) {
                    c.grid.applyFilter(col: col, excluded: Set((parts.count > 1 ? parts[1] : "").split(separator: "|").map(String.init)))
                }
            case "state":
                let g = c.grid!
                let fr = g.window?.firstResponder
                print("STATE active=\(columnName(g.active.col))\(g.active.row + 1) sel=\(g.selection.a1) editing=\(g.isEditing) pointing=\(g.isPointing) responder=\(fr.map { String(describing: type(of: $0)) } ?? "nil") text=\((fr as? NSTextView)?.string ?? "")")
            case "dragborder": // dragborder B2 C5: grab the selection outline at its top edge and drop it on C5
                guard let w = c.window else { break }
                let p = arg.split(separator: " ").map(String.init)
                guard p.count == 2, let a = parseA1(p[0]), let b = parseA1(p[1]) else { break }
                let start = c.grid.borderWindowPoint(for: a), end = c.grid.borderWindowPoint(for: b)
                for (t, pt) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
                    if let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { NSApp.sendEvent(e) }
                }
            case "drag", "filldrag": // drag A1 C3  (filldrag starts at the selection's fill handle)
                guard let w = c.window else { break }
                let p = arg.split(separator: " ").map(String.init)
                guard p.count == 2, let a = parseA1(p[0]), let b = parseA1(p[1]) else { break }
                var start = c.grid.windowPoint(for: a)
                if cmd.hasPrefix("fill") { start = c.grid.fillHandleWindowPoint() }
                let end = c.grid.windowPoint(for: b)
                func ev(_ t: NSEvent.EventType, _ pt: NSPoint) {
                    if let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { NSApp.sendEvent(e) }
                }
                ev(.leftMouseDown, start)
                for i in 1...5 { let t = CGFloat(i) / 5; ev(.leftMouseDragged, NSPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)) }
                ev(.leftMouseUp, end)
            case "header": // header C  or header 5
                guard let w = c.window else { break }
                if let col = parseA1(arg + "1")?.col, Int(arg) == nil {
                    var p = c.grid.windowPoint(for: CellRef(row: 0, col: col)); p.y += c.grid.headerH * c.grid.zoom * 0.5 + 10
                    sendClick(at: c.grid.headerPoint(col: col), count: 1, to: w)
                    _ = p
                } else if let r = Int(arg) {
                    sendClick(at: c.grid.headerPoint(row: r - 1), count: 1, to: w)
                }
            case "fillsel": c.grid.commitEditing(move: nil, fillSelection: true)
            case "sortasc": c.grid.sortAscending(nil)
            case "panes":
                print("GRID \(NSStringFromRect(c.grid.frame)) bounds=\(NSStringFromRect(c.grid.bounds)) clips=\(c.grid.layer?.masksToBounds ?? false)")
                for v in c.grid.subviews where v is ChartPane { print("PANE \(NSStringFromRect(v.frame)) clips=\(v.clipsToBounds)"); for cv in v.subviews { print("  CHARTVIEW \(NSStringFromRect(cv.frame))") } }
            case "chartdata": if let i = Int(arg) { let d = c.grid.book.chartData(sheet: c.grid.sheet, index: i); print("CHARTDATA \(i) series=\(d.count) \(d.first.map { "\($0)" }?.prefix(300) ?? "")") }
            case "shiftcells": // shiftcells insert down | delete right …
                let p = arg.split(separator: " ")
                if p.count == 2 { c.grid.shiftCells(insert: p[0] == "insert", horizontal: p[1] == "right") }
            case "transpose": c.grid.pasteTransposed()
            case "removedups": c.grid.removeDuplicates(nil)
            case "insertrows": c.grid.insertRows(nil)
            case "comment": // comment B2 text
                let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if p.count == 2, let r = parseA1(p[0]) { c.grid.book.setComment(sheet: c.grid.sheet, row: r.row, col: r.col, p[1], author: "Test"); c.grid.contentChanged() }
            case "validlist": // validlist A1:A5 Sì;No
                let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if p.count == 2, let r = FormulaText.gridRange(p[0].uppercased()) {
                    do { try c.grid.book.setValidation(sheet: c.grid.sheet, r, rule: ["type": "list", "formula1": p[1], "inCellDropdown": true, "showErrorMessage": true, "errorStyle": "stop"]); print("VALID ok") }
                    catch { print("VALID err \(error)") }
                    c.grid.contentChanged()
                }
            case "checkvalid": // checkvalid A1 value
                let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if p.count == 2, let r = parseA1(p[0]) { print("CHECK \(c.grid.book.checkValidation(sheet: c.grid.sheet, row: r.row, col: r.col, p[1]).code)") }
            case "listitems": print("ITEMS \(c.grid.validationListItems()?.joined(separator: ",") ?? "-")")
            case "pick": if let i = Int(arg) { c.grid.pickValidationItemForTesting(i) }   // pick 0: first item of the active cell's list
            case "validwarn": // validwarn A1:A5 Sì;No  (list rule with Warning alerts)
                let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if p.count == 2, let r = FormulaText.gridRange(p[0].uppercased()) {
                    try? c.grid.book.setValidation(sheet: c.grid.sheet, r, rule: ["type": "list", "formula1": p[1], "inCellDropdown": true, "showErrorMessage": true, "errorStyle": "warning"])
                    c.grid.contentChanged()
                }
            case "alertbutton": // alertbutton 1: answers the window's alert sheet with its first button
                if let w = c.window, let sheet = w.attachedSheet, let n = Int(arg) {
                    print("ALERT \(n)")
                    w.endSheet(sheet, returnCode: NSApplication.ModalResponse(rawValue: 1000 + n - 1))
                }
            case "link": // link A1 https://…
                let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if p.count == 2, let r = parseA1(p[0]) { c.grid.book.setLink(sheet: c.grid.sheet, row: r.row, col: r.col, address: p[1], display: nil); c.grid.contentChanged() }
            case "linkof": if let r = parseA1(arg) { print("LINK \(arg) \(c.grid.book.link(sheet: c.grid.sheet, row: r.row, col: r.col)?.address ?? "-")") }
            case "defname": // defname Name formula
                let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
                if p.count == 2 { do { try c.grid.book.defineName(p[0], scope: nil, formula: p[1]) } catch { print("DEFNAME err \(error)") } }
            case "names": for n in c.grid.book.definedNames { print("NAMEDEF \(n.name)=\(n.formula)") }
            case "followlink": c.grid.followLink(arg)
            case "font": c.grid.setStyle("font.name", arg)
            case "tabcolor": c.grid.book.setSheetColor(c.grid.sheet, UInt32(arg, radix: 16) ?? 0); c.reloadTabs()
            case "summarize": // summarize A1:C10 groupCol valueCol agg
                let p = arg.split(separator: " ").map(String.init)
                if p.count == 4, let r = FormulaText.gridRange(p[0].uppercased()), let g = parseA1(p[1] + "1"), let v = parseA1(p[2] + "1"), let a = Int(p[3]) {
                    if let i = try? c.grid.book.summarize(sheet: c.grid.sheet, r, groupCol: g.col, valueCol: v.col, aggregation: a, name: nil) { c.selectSheetForTesting(i) }
                }
            case "dialog": // open a dialog for visual checks
                switch arg {
                case "formatcells": c.formatCells(nil)
                case "sort": c.grid.sortDialog(nil)
                case "pastespecial": c.grid.pasteSpecial(nil)
                case "names": c.nameManager(nil)
                case "insertcells": c.grid.insertCellsDialog(nil)
                case "summarize": c.summarize(nil)
                default: break
                }
            case "sortkeys": // sortkeys A2:B5 A+ B-
                let p = arg.split(separator: " ").map(String.init)
                if let r = FormulaText.gridRange(p[0].uppercased()) {
                    let keys = p.dropFirst().compactMap { k -> (Int, Bool)? in
                        guard let c = parseA1(String(k.dropLast()) + "1")?.col else { return nil }
                        return (c, k.hasSuffix("+"))
                    }
                    c.grid.book.sort(sheet: c.grid.sheet, r, keys: keys); c.grid.contentChanged()
                }
            case "findall": print("FOUND \(c.grid.book.findAll(sheet: c.grid.sheet, arg, flags: 0).count)")
            case "namebox": c.nameBoxForTesting(arg)
            case "showformulas": c.grid.toggleShowFormulas(nil)
            case "recalc": c.grid.recalculate(nil)
            case "painter": c.formatPainter(nil)
            case "styleof": if let ref = parseA1(arg) { let st = c.grid.book.style(sheet: c.grid.sheet, row: ref.row, col: ref.col); print("STYLE \(arg) bold=\(st.bold) bg=\(String(st.bg, radix: 16))") }
            case "cf": // cf kind op value
                let p = arg.split(separator: " ").map(String.init)
                if p.count >= 2, let k = UInt32(p[0]), let o = UInt32(p[1]) {
                    _ = c.grid.book.addConditionalFormat(sheet: c.grid.sheet, c.grid.selection, kind: k, op: o, v1: p.count > 2 ? p[2] : "", style: 0)
                    c.grid.contentChanged()
                }
            case "barclick": c.focusFormulaBarForTesting()
            case "sheets": print("SHEETS \(c.grid.book.sheetNames.joined(separator: ",")) current=\(c.grid.sheet)")
            case "tab": if let i = Int(arg) { c.selectSheetForTesting(i) }
            case "findtext": _ = c.grid.find(arg, flags: 0)
            case "rowhidden":
                if let r = Int(arg) { print("HIDDEN \(r) \(c.grid.book.layout(sheet: c.grid.sheet).rows.contains { $0.0 == r - 1 && $0.2 })") }
            case "sortdesc": c.grid.sortDescending(nil)
            case "debug":
                print("DEBUG keyWindow=\(NSApp.keyWindow != nil) isActive=\(NSApp.isActive) cycle=\(String(describing: c.grid.book.cycleReference("=B2*3", start: 3, end: 3))) cycle2=\(String(describing: c.grid.book.cycleReference("B2*3", start: 2, end: 2)))")
            case "popup":
                for w in NSApp.windows where w.isVisible && (w is CompletionPopup || w is HintPopup) {
                    print("POPUP \(type(of: w)) \((w as? CompletionPopup)?.items.prefix(5).joined(separator: ",") ?? "")")
                }
            case "setframe": // setframe 1400 900: resizes the window (top-left corner fixed), like dragging its corner
                let p = arg.split(separator: " ").compactMap { Double($0) }
                if p.count == 2, let w = c.window {
                    w.windowController?.windowFrameAutosaveName = ""   // a test must not change the size the user's windows open with
                    w.setFrameAutosaveName("")
                    var f = w.frame
                    f.origin.y += f.height - p[1]
                    f.size = NSSize(width: p[0], height: p[1])
                    w.setFrame(f, display: true)
                }
            case "mousedown", "mousedrag", "mouseup": // a drag in steps: mousedown B2;; mousedrag D9;; mousedrag above;; mouseup
                // Points: a cell (its centre) or above/below/left/right (20 pt outside the grid, where autoscroll kicks in).
                guard let w = c.window else { break }
                let g = c.grid!
                var p = UIScript.lastMouse
                if let ref = parseA1(arg) { p = g.windowPoint(for: ref) }
                else if !arg.isEmpty {
                    let b = g.convert(g.bounds, to: nil)   // window coordinates, y up
                    switch arg {
                    case "above": p.y = b.maxY + 20
                    case "below": p.y = b.minY - 20
                    case "left": p.x = b.minX - 20
                    case "right": p.x = b.maxX + 20
                    default: break
                    }
                }
                UIScript.lastMouse = p
                let type: NSEvent.EventType = verb == "mousedown" ? .leftMouseDown : verb == "mouseup" ? .leftMouseUp : .leftMouseDragged
                if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.sendEvent(e)   // the window routes drags and the release to the view that took the press
                }
            case "zoomui": print("ZOOMUI \(c.zoomStatusForTesting) grid=\(Int((c.grid.zoom * 100).rounded()))")   // the status bar's zoom
            case "scroll": // scroll 0 -600: a trackpad scroll by (dx, dy) points (negative dy = towards the end of the sheet)
                let p = arg.split(separator: " ").compactMap { Int32($0) }
                if p.count == 2, let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: p[1], wheel2: p[0], wheel3: 0),
                   let e = NSEvent(cgEvent: cg) { c.grid.scrollWheel(with: e) }
            case "visible": // the cells that fit in the grid now, whether the last draw covered them, and the drawing panes
                let g = c.grid!
                let v = g.visibleRangeForTesting
                func span(_ r: ClosedRange<Int>, cols: Bool) -> String { cols ? "\(columnName(r.lowerBound))-\(columnName(r.upperBound))" : "\(r.lowerBound + 1)-\(r.upperBound + 1)" }
                print("VISIBLE rows=\(span(v.rows, cols: false)) cols=\(span(v.cols, cols: true)) size=\(Int(g.bounds.width))x\(Int(g.bounds.height))")
                let d = g.lastDrawn
                let drawn = d.map { $0.rows == v.rows && $0.cols == v.cols && $0.size == g.bounds.size } ?? false
                // The chart/picture panes reach the scroll bars (they clip the charts and pictures).
                let sw = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
                let pane = g.chartLayer.mainPane.frame
                let panes = abs(pane.maxX - (g.bounds.width - sw)) < 1 && abs(pane.maxY - (g.bounds.height - sw)) < 1
                var grew = "-"
                if let p = UIScript.lastVisible {
                    grew = [v.rows.upperBound > p.rows.upperBound ? "rows" : nil, v.cols.upperBound > p.cols.upperBound ? "cols" : nil].compactMap { $0 }.joined(separator: ",")
                }
                UIScript.lastVisible = v
                UIScript.visibleCount += 1
                let h = g.lastDrawnHeaders
                let headers = h.rows == v.rows && h.cols == v.cols
                print("RESIZE \(UIScript.visibleCount) drawn=\(drawn ? "current" : "stale") headers=\(headers ? "current" : "stale") scrollers=\(g.scrollersFitForTesting ? "current" : "stale") panes=\(panes ? "current" : "stale") grew=\(grew.isEmpty ? "none" : grew)")
            case "chart": ChartsUI.script(arg, on: c)   // Foglio charts: see ChartsUI.script
            case "pic": PicturesUI.script(arg, on: c)   // Foglio pictures: see PicturesUI.script
            case "dump":
                func walk(_ v: NSView, _ depth: Int) {
                    if v is NSButton || v is NSTextField || v is NSPopUpButton {
                        print("VIEW", String(repeating: " ", count: depth), type(of: v), NSStringFromRect(v.frame), (v as? NSButton)?.title ?? "")
                    }
                    v.subviews.forEach { walk($0, depth + 1) }
                }
                if let v = c.window?.contentView { walk(v, 0) }
            default: break
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
