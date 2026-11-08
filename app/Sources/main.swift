import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [SheetWindowController] = []
    private let env = ProcessInfo.processInfo.environment

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.mainMenu = buildMenu()
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if let path = args.first {
            open(URL(fileURLWithPath: path))
        } else {
            newDocument(nil)
        }
        if let demo = env["FOGLIO_DEMO"].flatMap(Int.init), let c = controllers.first {
            fillDemo(c, rows: demo)
        }
        setUpBenchmarks()
        // Measurement runs must never steal focus (keystrokes meant for other apps would land here).
        if !Perf.shared.enabled { NSApp.activate() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(URL(fileURLWithPath: filename)); return true
    }

    // MARK: - Documents

    private func show(_ book: Workbook) {
        let c = SheetWindowController(book: book)
        c.onClose = { [weak self] c in self?.controllers.removeAll { $0 === c } }
        controllers.append(c)
        c.showWindow(nil)
        c.window?.makeFirstResponder(c.grid)
    }

    @objc func newDocument(_ sender: Any?) { show(Workbook()) }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(open) }
    }

    private func open(_ url: URL) {
        do {
            let t = Date()
            let book = try Workbook(xlsx: url)
            Perf.shared.emit("OPEN_MS", String(format: "%.1f", Date().timeIntervalSince(t) * 1000))
            show(book)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            let a = NSAlert()
            a.messageText = "Impossibile aprire \(url.lastPathComponent)"
            a.informativeText = "\(error)"
            a.runModal()
            if controllers.isEmpty { newDocument(nil) }
        }
    }

    /// N rows of a small sales table with formulas, to exercise rendering and recalculation.
    private func fillDemo(_ c: SheetWindowController, rows: Int) {
        var tsv = "Prodotto\tQuantità\tPrezzo\tImponibile\tIVA\tTotale\tFascia\n"
        tsv.reserveCapacity(rows * 80)
        for i in 1...rows {
            let r = i + 1
            tsv += "Articolo \(i)\t\((i * 7) % 50 + 1)\t\(Double((i * 13) % 400) / 4 + 1)\t=B\(r)*C\(r)\t=D\(r)*0.22\t=D\(r)+E\(r)\t=IF(F\(r)>2000,\"alto\",\"basso\")\n"
        }
        tsv += "Totale\t=SUM(B2:B\(rows + 1))\t\t=SUM(D2:D\(rows + 1))\t=SUM(E2:E\(rows + 1))\t=SUM(F2:F\(rows + 1))\t=COUNTIF(G2:G\(rows + 1),\"alto\")\n"
        let t = Date()
        c.book.pasteTSV(sheet: 0, row: 0, col: 0, tsv)
        Perf.shared.emit("DEMO_FILL_MS", String(format: "%.1f", Date().timeIntervalSince(t) * 1000))
        c.book.setStyle(sheet: 0, GridRange(r0: 0, c0: 0, r1: 0, c1: 6), path: "font.b", value: "true")
        c.grid.contentChanged()
    }

    private func setUpBenchmarks() {
        let frames = env["FOGLIO_AUTOSCROLL"].flatMap(Int.init)
        let exitAfterFirst = env["FOGLIO_EXIT_AFTER_FIRST_FRAME"] != nil
        let snapshot = env["FOGLIO_SNAPSHOT"]
        Perf.shared.onFirstFrame = { [weak self] in
            if exitAfterFirst { exit(0) }
            if let w = self?.controllers.first?.window { Perf.shared.emit("WINDOW_ID", "\(w.windowNumber)") }
            if let snapshot, let c = self?.controllers.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    c.grid.select(CellRef(row: 3, col: 1))
                    c.grid.select(CellRef(row: 8, col: 3), extend: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let v = c.window?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                            v.cacheDisplay(in: v.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshot))
                        }
                        exit(0)
                    }
                }
            }
            if let frames, let g = self?.controllers.first?.grid {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { g.startAutoScroll(frames: frames) }
            }
        }
        NotificationCenter.default.addObserver(forName: .foglioBenchmarkDone, object: nil, queue: .main) { [weak self] _ in
            guard self?.env["FOGLIO_EXIT"] != nil else { return }
            exit(0)
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let host = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            host.submenu = m
            main.addItem(host)
        }
        func item(_ t: String, _ a: Selector?, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.keyEquivalentModifierMask = mods
            return i
        }
        submenu("Foglio", [
            item("Informazioni su Foglio", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Nascondi Foglio", #selector(NSApplication.hide(_:)), "h"),
            item("Nascondi altre", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item("Esci da Foglio", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("File", [
            item("Nuovo", #selector(newDocument(_:)), "n"),
            item("Apri…", #selector(openDocument(_:)), "o"),
            .separator(),
            item("Chiudi", #selector(NSWindow.performClose(_:)), "w"),
            item("Salva", #selector(SheetWindowController.saveDocument(_:)), "s"),
            item("Salva con nome…", #selector(SheetWindowController.saveDocumentAs(_:)), "s", [.command, .shift]),
        ])
        submenu("Modifica", [
            item("Annulla", #selector(GridView.undo(_:)), "z"),
            item("Ripeti", #selector(GridView.redo(_:)), "z", [.command, .shift]),
            .separator(),
            item("Taglia", #selector(NSText.cut(_:)), "x"),
            item("Copia", #selector(NSText.copy(_:)), "c"),
            item("Incolla", #selector(NSText.paste(_:)), "v"),
            item("Elimina", #selector(NSText.delete(_:))),
            item("Seleziona tutto", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("Formato", [
            item("Grassetto", #selector(SheetWindowController.boldAction), "b"),
            item("Corsivo", #selector(SheetWindowController.italicAction), "i"),
            item("Sottolineato", #selector(SheetWindowController.underlineAction), "u"),
        ])
        let windowMenu = NSMenu(title: "Finestra")
        windowMenu.addItem(item("Riduci a icona", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        let wi = NSMenuItem(title: "Finestra", action: nil, keyEquivalent: "")
        wi.submenu = windowMenu
        main.addItem(wi)
        NSApp.windowsMenu = windowMenu
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
