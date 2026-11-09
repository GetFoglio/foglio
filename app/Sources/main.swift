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
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
        for path in args {
            NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, err in
                if let err { NSApp.presentError(err) }
            }
        }
        setUpBenchmarks()
        if !Perf.shared.enabled { NSApp.activate() }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.isEmpty
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
        for child in w.childWindows ?? [] where child.isVisible {
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
            case "state":
                let g = c.grid!
                let fr = g.window?.firstResponder
                print("STATE active=\(columnName(g.active.col))\(g.active.row + 1) sel=\(g.selection.a1) editing=\(g.isEditing) pointing=\(g.isPointing) responder=\(fr.map { String(describing: type(of: $0)) } ?? "nil") text=\((fr as? NSTextView)?.string ?? "")")
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
