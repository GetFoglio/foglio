import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let env = ProcessInfo.processInfo.environment

    func applicationWillFinishLaunching(_ n: Notification) {
        FormulaLocale.current.apply()
        NSApp.mainMenu = Menus.mainMenu()
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ n: Notification) {
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
                    if let script = self?.env["FOGLIO_SCRIPT"] { UIScript.run(script, on: c) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        Snapshot.write(c.window, to: snapshot)
                        exit(0)
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
    static func write(_ window: NSWindow?, to path: String) {
        guard let v = window?.contentView else { return }
        let data = v.dataWithPDF(inside: v.bounds)
        guard let pdf = NSPDFImageRep(data: data) else { return }
        let scale: CGFloat = 2
        let size = NSSize(width: v.bounds.width * scale, height: v.bounds.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        pdf.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// Tiny scripting hook for automated UI checks: "select B4:D9; type =SUM(B2:B5); key return; ..."
enum UIScript {
    static func run(_ script: String, on c: SheetWindowController) {
        for raw in script.components(separatedBy: ";;") {
            let cmd = raw.trimmingCharacters(in: .whitespaces)
            let parts = cmd.split(separator: " ", maxSplits: 1).map(String.init)
            guard let verb = parts.first else { continue }
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
