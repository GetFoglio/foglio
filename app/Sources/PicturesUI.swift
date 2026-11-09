import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Rendering

/// Draws pictures with CoreGraphics. Images are decoded lazily with ImageIO and cached as thumbnails sized for
/// the display (bucketed, so zooming doesn't re-decode at every step); the crop is applied when drawing.
enum PictureRenderer {
    private final class Source { let src: CGImageSource; let size: CGSize; init(_ s: CGImageSource, _ z: CGSize) { src = s; size = z } }
    private static let sources: NSCache<NSString, Source> = { let c = NSCache<NSString, Source>(); c.countLimit = 64; return c }()
    private static let thumbs: NSCache<NSString, CGImage> = { let c = NSCache<NSString, CGImage>(); c.totalCostLimit = 192 << 20; return c }()

    /// ImageIO source and oriented pixel size of an image (nil for formats ImageIO can't read, e.g. EMF).
    private static func source(_ key: String, book: Workbook, sheet: Int) -> Source? {
        if let s = sources.object(forKey: key as NSString) { return s }
        guard let data = book.pictureImageData(sheet: sheet, key: key),
              let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        var w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        if let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue, o >= 5 { swap(&w, &h) }
        guard w > 0, h > 0 else { return nil }
        let s = Source(src, CGSize(width: w, height: h))
        sources.setObject(s, forKey: key as NSString)
        return s
    }

    /// Pixel size of the picture's image (oriented).
    static func pixelSize(_ p: PictureInfo, book: Workbook, sheet: Int) -> CGSize? {
        if let s = source(p.image, book: book, sheet: sheet) { return s.size }
        return p.pixelW > 0 ? CGSize(width: p.pixelW, height: p.pixelH) : nil
    }

    /// The whole image, decoded with at least `minPixels` on its longer side (full size if smaller).
    static func image(_ key: String, book: Workbook, sheet: Int, minPixels: CGFloat) -> CGImage? {
        guard let s = source(key, book: book, sheet: sheet) else { return nil }
        let longest = max(s.size.width, s.size.height)
        var bucket: CGFloat = 256
        while bucket < minPixels && bucket < longest { bucket *= 2 }
        let n = Int(min(bucket, longest))
        let cacheKey = "\(key)@\(n)" as NSString
        if let img = thumbs.object(forKey: cacheKey) { return img }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: n,
                                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(s.src, 0, opts as CFDictionary) else { return nil }
        thumbs.setObject(img, forKey: cacheKey, cost: img.bytesPerRow * img.height)
        return img
    }

    /// Draws picture `p` in `rect` of a flipped context (cropped unless `uncropped`).
    static func draw(_ p: PictureInfo, book: Workbook, sheet: Int, in rect: CGRect, ctx: CGContext, scale: CGFloat, uncropped: Bool = false) {
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        let crop = uncropped ? PictureCrop() : p.crop
        let need = max(rect.width / crop.visibleW, rect.height / crop.visibleH) * scale
        guard let img = image(p.image, book: book, sheet: sheet, minPixels: need) else {
            drawPlaceholder(p, in: rect, ctx: ctx)
            return
        }
        let src = crop.sourceRect(width: CGFloat(img.width), height: CGFloat(img.height)).integral
            .intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        guard !src.isNull, let part = crop.isEmpty ? img : img.cropping(to: src) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    /// Images macOS can't decode (EMF/WMF): a light frame with a picture symbol.
    private static func drawPlaceholder(_ p: PictureInfo, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(NSColor(white: 0.7, alpha: 1).cgColor)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
        if let sym = NSImage(systemSymbolName: "photo", accessibilityDescription: nil), rect.width > 24, rect.height > 24 {
            let s = min(32, min(rect.width, rect.height) * 0.5)
            sym.draw(in: CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s * 0.8), from: .zero, operation: .sourceOver, fraction: 0.4)
        }
    }
}

// MARK: - Image data (import, compression)

enum PictureData {
    /// Bytes ready for the engine (PNG or JPEG kept as they are, other formats converted: JPEG for opaque photos,
    /// PNG otherwise; EXIF orientation applied) and the natural size in points (pixels at the image's dpi).
    static func prepare(_ data: Data) -> (Data, CGSize)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0,
              let type = CGImageSourceGetType(src) as String? else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        var w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if orientation >= 5 { swap(&w, &h) }
        guard w > 0, h > 0 else { return nil }
        let dpi = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let k = 72 / (dpi >= 36 && dpi <= 1200 ? dpi : 72)
        let size = CGSize(width: w * k, height: h * k)
        let isPNG = type == UTType.png.identifier, isJPEG = type == UTType.jpeg.identifier
        if (isPNG || isJPEG) && orientation == 1 { return (data, size) }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: Int(max(w, h)),
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let photo = isJPEG || type == UTType.heic.identifier || type == "public.heif" || type == UTType.webP.identifier
        let out = (photo && !hasAlpha(img)) ? encode(img, jpeg: true) : encode(img, jpeg: false)
        return out.map { ($0, size) }
    }

    static func hasAlpha(_ img: CGImage) -> Bool {
        switch img.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        // An alpha channel that is opaque everywhere doesn't count (sampled at 64 x 64).
        guard let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let buf = ctx.data else { return true }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let p = buf.bindMemory(to: UInt8.self, capacity: 64 * 64 * 4)
        for i in 0..<(64 * 64) where p[i * 4 + 3] < 250 { return true }
        return false
    }

    /// Few distinct colours (screenshots, diagrams, logos): PNG keeps them sharp and small.
    static func isGraphic(_ img: CGImage) -> Bool {
        guard let ctx = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 384, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let buf = ctx.data else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        let p = buf.bindMemory(to: UInt32.self, capacity: 96 * 96)
        var colors = Set<UInt32>()
        for i in 0..<(96 * 96) {
            colors.insert(p[i])
            if colors.count > 256 { return false }
        }
        return true
    }

    static func encode(_ img: CGImage, jpeg: Bool, quality: Double = 0.9) -> Data? {
        let out = NSMutableData()
        let type = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        var opts: [CFString: Any] = [:]
        if jpeg { opts[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, img, opts as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// Compress Pictures for one picture: optionally drops the cropped areas, downsamples to `ppi` of the displayed
    /// size, re-encodes (JPEG 0.82 for photos, PNG for transparency or few colours). Nil when nothing would improve.
    static func compress(_ data: Data, crop: PictureCrop, displayed: CGSize, ppi: Double?, deleteCropped: Bool) -> (Data, PictureCrop)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, let ph = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              pw > 0, ph > 0 else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max(pw, ph),
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard var img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        var crop = crop
        var changed = false
        if deleteCropped && !crop.isEmpty {
            let r = crop.sourceRect(width: CGFloat(img.width), height: CGFloat(img.height)).integral
                .intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))
            if !r.isNull, r.width >= 1, r.height >= 1, let c = img.cropping(to: r) { img = c; crop = PictureCrop(); changed = true }
        }
        if let ppi {
            // Pixels needed for the whole (still cropped) image at `ppi` of its displayed size (points = 1/72 in).
            let needW = displayed.width / 72 * ppi / crop.visibleW, needH = displayed.height / 72 * ppi / crop.visibleH
            let k = max(needW / CGFloat(img.width), needH / CGFloat(img.height))
            if k < 0.95 {
                let w = max(1, Int((CGFloat(img.width) * k).rounded())), h = max(1, Int((CGFloat(img.height) * k).rounded()))
                let alpha = hasAlpha(img)
                if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue) {
                    ctx.interpolationQuality = .high
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                    if let s = ctx.makeImage() { img = s; changed = true }
                }
            }
        }
        // High fidelity without deleting anything: never re-encode (that would only lose quality).
        guard changed else { return nil }
        let png = hasAlpha(img) || isGraphic(img)
        guard let out = encode(img, jpeg: !png, quality: 0.82) else { return nil }
        return out.count < data.count ? (out, crop) : nil
    }
}

// MARK: - Commands, clipboard, drag and drop

enum PicturesUI {
    static let pasteboardType = NSPasteboard.PasteboardType("org.foglio.picture")
    static let dropTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
    private static let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)

    /// Largest size of an inserted picture, in points (bigger ones are scaled down, aspect ratio kept).
    static let maxInsertSize = CGSize(width: 480, height: 360)

    static func fittedInsertSize(_ s: CGSize) -> CGSize {
        let k = min(1, maxInsertSize.width / max(1, s.width), maxInsertSize.height / max(1, s.height))
        return CGSize(width: max(4, (s.width * k).rounded()), height: max(4, (s.height * k).rounded()))
    }

    /// Insert ▸ Picture… (Menus.swift).
    static func insertMenuItem() -> NSMenuItem {
        Menus.item("Picture…", #selector(SheetWindowController.insertPictureFromFile(_:)), symbol: "photo")
    }

    /// Picture format commands, shared by Format ▸ Picture and the picture's context menu.
    static func formatItems() -> [NSMenuItem] {
        [
            Menus.item("Crop", #selector(PictureView.cropPicture(_:)), symbol: "crop"),
            Menus.item("Reset Crop", #selector(PictureView.resetPictureCrop(_:))),
            Menus.item("Reset Size", #selector(PictureView.resetPictureSize(_:))),
            .separator(),
            Menus.item("Place in Cell", #selector(PictureView.placePictureInCell(_:))),
            Menus.item("Place over Cells", #selector(PictureView.placePictureOverCells(_:))),
            .separator(),
            Menus.item("Bring Forward", #selector(PictureView.bringForward(_:))),
            Menus.item("Send Backward", #selector(PictureView.sendBackward(_:))),
            Menus.item("Bring to Front", #selector(PictureView.bringToFront(_:))),
            Menus.item("Send to Back", #selector(PictureView.sendToBack(_:))),
            .separator(),
            Menus.item("Alt Text…", #selector(PictureView.editAltText(_:))),
            Menus.item("Change Picture…", #selector(PictureView.changePicture(_:))),
            Menus.item("Compress Pictures…", #selector(PictureView.compressPictures(_:))),
        ]
    }

    /// Format ▸ Picture submenu.
    static func formatMenuItem() -> NSMenuItem { Menus.submenu("Picture", formatItems()) }

    static func contextItems() -> [NSMenuItem] {
        [Menus.item("Cut", #selector(PictureView.cut(_:))), Menus.item("Copy", #selector(PictureView.copy(_:))),
         Menus.item("Paste", #selector(PictureView.paste(_:))), Menus.item("Delete", #selector(PictureView.deletePicture(_:))),
         .separator()] + formatItems()
    }

    // Clipboard ---------------------------------------------------------------

    /// Copies a picture: its bytes and placement for pasting in Foglio, PNG (and JPEG) for other apps.
    static func copyToPasteboard(_ p: PictureInfo, book: Workbook, sheet: Int) {
        guard let data = book.pictureImageData(sheet: sheet, key: p.image) else { return }
        let meta: [String: Any] = ["descr": p.descr, "w": p.size.width, "h": p.size.height, "crop": [p.crop.l, p.crop.t, p.crop.r, p.crop.b],
                                   "data": data.base64EncodedString()]
        let pb = NSPasteboard.general
        pb.clearContents()
        if let json = try? JSONSerialization.data(withJSONObject: meta) { pb.setData(json, forType: pasteboardType) }
        if p.format == "png" { pb.setData(data, forType: .png) }
        else {
            if p.format == "jpeg" { pb.setData(data, forType: jpegType) }
            if let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
               let png = PictureData.encode(img, jpeg: false) { pb.setData(png, forType: .png) }
        }
    }

    static func pasteboardHasPicture(_ pb: NSPasteboard = .general) -> Bool {
        pb.availableType(from: [pasteboardType, .png, .tiff, jpegType]) != nil
    }

    /// ⌘V hook (GridView.paste): pastes a picture when the clipboard holds one of ours, or image data without
    /// text or cells. Returns false to let the grid paste cells/text.
    static func pasteIfPicture(_ grid: GridView) -> Bool {
        let pb = NSPasteboard.general
        if pb.availableType(from: [GridView.pasteboardType]) != nil { return false }
        if let json = pb.data(forType: pasteboardType), let meta = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
           let b64 = meta["data"] as? String, let data = Data(base64Encoded: b64) {
            let c = meta["crop"] as? [Int] ?? []
            let crop = c.count == 4 ? PictureCrop(l: c[0], t: c[1], r: c[2], b: c[3]) : PictureCrop()
            let size = CGSize(width: meta["w"] as? CGFloat ?? 100, height: meta["h"] as? CGFloat ?? 100)
            insert(data: data, size: size, crop: crop, descr: meta["descr"] as? String ?? "", in: grid, at: nil)
            return true
        }
        if pb.string(forType: .string) != nil { return false }
        for t in [NSPasteboard.PasteboardType.png, jpegType, .tiff] {
            if let d = pb.data(forType: t), let (data, size) = PictureData.prepare(d) {
                insert(data: data, size: fittedInsertSize(size), in: grid, at: nil)
                return true
            }
        }
        return false
    }

    // Insert ------------------------------------------------------------------

    /// Adds a picture with its top-left corner at `at` (a logical grid point) or at the active cell; a picture
    /// pasted where an identical one already is goes a little lower and to the right. Selects it.
    @discardableResult
    static func insert(data: Data, size: CGSize, crop: PictureCrop = PictureCrop(), descr: String = "", in grid: GridView, at: CGPoint?) -> Int? {
        guard grid.commitIfEditing() else { return nil }
        let g = grid.chartGeometry()
        var origin = at ?? CGPoint(x: g.x(grid.active.col), y: g.y(grid.active.row))
        let existing = grid.pictureLayer.pictures.map { grid.pictureLayer.logicalRect($0, g).origin }
        while existing.contains(where: { abs($0.x - origin.x) < 1 && abs($0.y - origin.y) < 1 }) { origin.x += 12; origin.y += 12 }
        let patch = PicturePatch(from: g.corner(at: origin), size: size, crop: crop, descr: descr)
        guard let i = grid.book.addPicture(sheet: grid.sheet, data: data, patch) else { NSSound.beep(); return nil }
        grid.contentChanged()
        grid.pictureLayer.select(i)
        return i
    }

    /// Inserts image files (one undo step), cascading them from `at` or the active cell. Unreadable files are reported.
    static func insert(urls: [URL], in grid: GridView, at: CGPoint? = nil) {
        var failed: [String] = []
        var last: Int?
        grid.book.grouped {
            for (k, url) in urls.enumerated() {
                guard let d = try? Data(contentsOf: url), let (data, size) = PictureData.prepare(d) else { failed.append(url.lastPathComponent); continue }
                let p = at.map { CGPoint(x: $0.x + CGFloat(k) * 20, y: $0.y + CGFloat(k) * 20) }
                last = insert(data: data, size: fittedInsertSize(size), descr: url.deletingPathExtension().lastPathComponent, in: grid, at: p) ?? last
            }
        }
        if let last { grid.pictureLayer.select(last) }
        if !failed.isEmpty, let w = grid.window {
            let a = NSAlert()
            a.messageText = L("Some pictures could not be inserted")
            a.informativeText = String(format: L("These files are not images Foglio can read: %@"), failed.joined(separator: ", "))
            a.beginSheetModal(for: w)
        }
    }

    /// Change Picture: the new image keeps the width; the height follows its aspect ratio.
    static func replace(_ p: PictureInfo, with url: URL, layer: PictureLayer) {
        guard let d = try? Data(contentsOf: url), let (data, size) = PictureData.prepare(d) else { NSSound.beep(); return }
        let w = p.size.width
        let newSize = CGSize(width: w, height: w * size.height / max(1, size.width))
        layer.update(p.index, PicturePatch(from: p.inCell ? nil : p.from, size: newSize, crop: PictureCrop()), data: data)
    }

    /// Alt Text… (the picture's description, read by screen readers and kept in the file).
    static func altText(for p: PictureInfo, on w: NSWindow, done: @escaping (String) -> Void) {
        let a = NSAlert()
        a.messageText = L("Alt Text")
        a.informativeText = L("Describe the picture for people who use a screen reader.")
        let field = NSTextField(string: p.descr)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 48)
        field.placeholderString = L("Description")
        a.accessoryView = field
        a.addButton(withTitle: L("OK"))
        a.addButton(withTitle: L("Cancel"))
        a.window.initialFirstResponder = field
        a.beginSheetModal(for: w) { r in if r == .alertFirstButtonReturn { done(field.stringValue) } }
    }

    // Printing ------------------------------------------------------------------

    /// Last row/column (0-based) covered by the sheet's pictures and charts, to print them with the cells.
    static func drawingExtent(book: Workbook, sheet: Int) -> (row: Int, col: Int) {
        var r = -1, c = -1
        for p in book.pictures(sheet: sheet) {
            // Size not known in cells here: assume it ends at its anchor's "to" corner.
            r = max(r, p.to.row); c = max(c, p.to.col)
        }
        for ch in book.charts(sheet: sheet) { r = max(r, ch.to.row); c = max(c, ch.to.col) }
        return (r, c)
    }

    /// Draws the charts and pictures of a sheet for printing/PDF, back to front. `cellRect` gives a cell's
    /// rectangle on the page (.zero if not printed); `pointScale` converts grid points to page points.
    static func drawDrawings(book: Workbook, sheet: Int, cellRect: (Int, Int) -> CGRect, pointScale: CGFloat, clip: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let pictures = book.pictures(sheet: sheet)
        let charts = book.charts(sheet: sheet)
        guard !pictures.isEmpty || !charts.isEmpty else { return }
        func point(_ c: ChartCorner) -> CGPoint? {
            let r = cellRect(c.row, c.col)
            return r == .zero ? nil : CGPoint(x: r.minX + CGFloat(c.fx) * r.width, y: r.minY + CGFloat(c.fy) * r.height)
        }
        ctx.saveGState()
        ctx.clip(to: clip)
        for ref in book.drawingOrder(sheet: sheet) {
            switch ref {
            case .picture(let i):
                guard let p = pictures[safe: i] else { continue }
                var rect: CGRect
                if p.inCell {
                    let cell = cellRect(p.from.row, p.from.col)
                    if cell == .zero { continue }
                    rect = PictureLayer.fit(aspect: p.size, in: cell.insetBy(dx: 1, dy: 1))
                } else {
                    guard let o = point(p.from) else { continue }
                    rect = CGRect(origin: o, size: CGSize(width: p.size.width * pointScale, height: p.size.height * pointScale))
                }
                if rect.intersects(clip) { PictureRenderer.draw(p, book: book, sheet: sheet, in: rect, ctx: ctx, scale: 3) }
            case .chart(let i):
                guard let ch = charts[safe: i], let a = point(ch.from), let b = point(ch.to) else { continue }
                let rect = CGRect(x: a.x, y: a.y, width: max(0, b.x - a.x), height: max(0, b.y - a.y))
                guard rect.intersects(clip), rect.width > 4, rect.height > 4 else { continue }
                ctx.saveGState()
                ctx.translateBy(x: rect.minX, y: rect.minY)
                ctx.scaleBy(x: pointScale, y: pointScale)
                ChartRenderer(chart: ch, data: book.chartData(sheet: sheet, index: i), dark: false)
                    .draw(in: CGRect(x: 0, y: 0, width: rect.width / pointScale, height: rect.height / pointScale))
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    // UI test script -------------------------------------------------------------

    /// UIScript "pic …" commands (main.swift):
    ///   pic make /path.png W H [jpeg]   write a test image        pic insert /path [B2]   insert a file (at a cell)
    ///   pic list                          print the pictures       pic click N / pic drag N dx dy / pic resize N dx dy
    ///   pic crop N edge delta             crop mode, drag a crop handle (left/right/top/bottom), Return
    ///   pic incell N / pic overcells N    Place in Cell / over Cells
    ///   pic compress all|sel PPI [crop]   Compress Pictures (PPI 0 = high fidelity)
    ///   pic pbimage /path                 put an image file's data on the clipboard (as another app would)
    ///   pic roundtrip /path.xlsx          save, reopen, list         pic panes   picture views per pane
///   pic rowheight ROW PX              set a row height           pic front|back|forward|backward N, pic alt N text
    static func script(_ arg: String, on c: SheetWindowController) {
        let p = arg.split(separator: " ").map(String.init)
        guard let verb = p.first, let grid = c.grid else { return }
        let layer = grid.pictureLayer
        func view(_ s: String?) -> PictureView? { s.flatMap(Int.init).flatMap { layer.views[safe: $0] } }
        func drag(_ v: PictureView, from: CGPoint, dx: CGFloat, dy: CGFloat) {
            guard let w = c.window else { return }
            let start = v.convert(from, to: nil)
            func ev(_ t: NSEvent.EventType, _ pt: NSPoint) {
                if let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { NSApp.sendEvent(e) }
            }
            ev(.leftMouseDown, start)
            for i in 1...5 { let t = CGFloat(i) / 5; ev(.leftMouseDragged, NSPoint(x: start.x + dx * t, y: start.y - dy * t)) }
            ev(.leftMouseUp, NSPoint(x: start.x + dx, y: start.y - dy))
        }
        switch verb {
        case "make":
            guard p.count >= 4, let w = Int(p[2]), let h = Int(p[3]) else { return }
            let jpeg = p.count > 4 && p[4] == "jpeg"
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: (jpeg ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue) else { return }
            // A photo-like gradient with a few shapes (so JPEG makes sense and crops are visible).
            let colors = [CGColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1), CGColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1)] as CFArray
            if let gr = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gr, start: .zero, end: CGPoint(x: w, y: h), options: [])
            }
            for i in 0..<40 {
                let x = CGFloat((i * 97) % w), y = CGFloat((i * 61) % h), r = CGFloat(8 + (i * 13) % 40)
                ctx.setFillColor(CGColor(red: CGFloat(i % 5) / 5, green: CGFloat(i % 7) / 7, blue: CGFloat(i % 3) / 3, alpha: 0.6))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: w / 10, y: h / 10, width: w / 5, height: h / 5))
            if let img = ctx.makeImage(), let d = PictureData.encode(img, jpeg: jpeg, quality: 0.95) {
                try? d.write(to: URL(fileURLWithPath: p[1]))
                print("MADE \(p[1]) \(d.count)")
            }
        case "insert":
            guard p.count >= 2 else { return }
            if p.count > 2, let ref = FormulaText.gridRange(p[2].uppercased()) { grid.select(range: ref) }
            insert(urls: [URL(fileURLWithPath: p[1])], in: grid)
        case "list":
            let pics = grid.book.pictures(sheet: grid.sheet)
            print("PICTURES \(pics.count) selected=\(layer.selectedIndex.map(String.init) ?? "none") cropping=\(layer.views.contains { $0.isCropping })")
            for x in pics {
                let r = layer.views[safe: x.index]?.logical ?? .zero
                print("PICTURE \(x.index) from=\(columnName(x.from.col))\(x.from.row + 1) to=\(columnName(x.to.col))\(x.to.row + 1) size=\(Int(x.size.width.rounded()))x\(Int(x.size.height.rounded())) crop=\(x.crop.l),\(x.crop.t),\(x.crop.r),\(x.crop.b) incell=\(x.inCell) edit=\(x.editAs.rawValue) format=\(x.format) bytes=\(x.bytes) px=\(x.pixelW)x\(x.pixelH) rect=\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height)) descr=\(x.descr)")
            }
            print("ORDER \(grid.book.drawingOrder(sheet: grid.sheet).map { if case .chart(let i) = $0 { return "c\(i)" } else if case .picture(let i) = $0 { return "p\(i)" }; return "" }.joined(separator: ","))")
        case "click":
            guard let v = view(p[safe: 1]), let w = c.window else { return }
            UIScript.sendClick(at: v.convert(CGPoint(x: v.pictureRect.midX, y: v.pictureRect.midY), to: nil), count: 1, to: w)
        case "drag", "resize":
            guard let v = view(p[safe: 1]), p.count == 4, let dx = Double(p[2]), let dy = Double(p[3]) else { return }
            let r = v.pictureRect
            drag(v, from: verb == "drag" ? CGPoint(x: r.midX, y: r.midY) : CGPoint(x: r.maxX, y: r.maxY), dx: dx, dy: dy)
        case "crop":
            guard let v = view(p[safe: 1]), p.count == 4, let delta = Double(p[3]), let w = c.window else { return }
            if !v.isCropping { v.cropPicture(nil) }
            let r = v.pictureRect
            switch p[2] {
            case "left": drag(v, from: CGPoint(x: r.minX, y: r.midY), dx: delta, dy: 0)
            case "right": drag(v, from: CGPoint(x: r.maxX, y: r.midY), dx: delta, dy: 0)
            case "top": drag(v, from: CGPoint(x: r.midX, y: r.minY), dx: 0, dy: delta)
            default: drag(v, from: CGPoint(x: r.midX, y: r.maxY), dx: 0, dy: delta)
            }
            if p[2] != "keep" { UIScript.sendKey("\r", code: 36, mods: [], to: w) }
        case "cropmode":
            view(p[safe: 1])?.cropPicture(nil)
        case "incell": if let v = view(p[safe: 1]) { layer.select(v.info?.index); v.placePictureInCell(nil) }
        case "overcells": if let v = view(p[safe: 1]) { layer.select(v.info?.index); v.placePictureOverCells(nil) }
        case "front", "back", "forward", "backward":
            if let i = p[safe: 1].flatMap(Int.init) { layer.restack(index: i, verb) }
        case "alt":
            if let i = p[safe: 1].flatMap(Int.init), p.count > 2 { layer.update(i, PicturePatch(descr: p[2...].joined(separator: " "))) }
        case "compress":
            guard p.count >= 3, let ppi = Double(p[2]) else { return }
            let sheet = CompressPicturesSheet(grid: grid, selected: p[1] == "all" ? nil : layer.selectedIndex)
            sheet.configureForTesting(all: p[1] == "all", ppi: ppi == 0 ? nil : ppi, deleteCropped: p.count > 3 && p[3] == "crop")
            let (before, after) = sheet.estimate()
            print("COMPRESS before=\(before) after=\(after) smaller=\(after < before)")
            sheet.apply()
        case "pbimage":
            guard p.count >= 2, let d = try? Data(contentsOf: URL(fileURLWithPath: p[1])) else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(d, forType: p[1].lowercased().hasSuffix(".png") ? .png : jpegType)
        case "roundtrip":
            guard p.count >= 2 else { return }
            do {
                try grid.book.saveXLSX(to: URL(fileURLWithPath: p[1]))
                let back = try Workbook(contentsOf: URL(fileURLWithPath: p[1]))
                let pics = back.pictures(sheet: grid.sheet)
                print("REOPENED PICTURES \(pics.count) charts=\(back.charts(sheet: grid.sheet).count) incell=\(pics.filter(\.inCell).count) cropped=\(pics.filter { !$0.crop.isEmpty }.count) formats=\(pics.map(\.format).joined(separator: ","))")
            } catch { print("ROUNDTRIP_ERROR", error) }
        case "rowheight":   // rowheight ROW PX (1-based row, engine pixels)
            guard p.count == 3, let r = Int(p[1]), let px = Double(p[2]) else { return }
            grid.book.setRowHeight(sheet: grid.sheet, r - 1, r - 1, px: CGFloat(px))
            grid.contentChanged()
        case "pdf":   // pdf /path.pdf: the print view of the sheet, as one PDF page (printing check)
            guard p.count >= 2 else { return }
            let v = PrintView(book: grid.book, sheet: grid.sheet, selection: GridRange(r0: 0, c0: 0, r1: 0, c1: 0), printInfo: NSPrintInfo.shared.copy() as! NSPrintInfo)
            try? v.dataWithPDF(inside: v.bounds).write(to: URL(fileURLWithPath: p[1]))
            print("PDF \(Int(v.bounds.width))x\(Int(v.bounds.height))")
        case "panes":
            for v in grid.subviews where v is ChartPane { for pv in v.subviews where pv is PictureView { print("PICTUREVIEW \(NSStringFromRect(pv.frame))") } }
        default: break
        }
    }
}

// MARK: - Compress Pictures

/// Excel's Compress Pictures: selected picture or all pictures of the sheet, delete cropped areas, target resolution.
/// Shows the size of the affected images before and after; one undo step.
final class CompressPicturesSheet: NSObject {
    private weak var grid: GridView?
    private let selected: Int?
    private let panel: NSPanel
    private let onlySelected = NSButton(checkboxWithTitle: L("Apply only to this picture"), target: nil, action: nil)
    private let deleteCropped = NSButton(checkboxWithTitle: L("Delete cropped areas of pictures"), target: nil, action: nil)
    private var resolutionButtons: [NSButton] = []
    private static let resolutions: [(String, Double?)] = [("High fidelity: keeps the original quality", nil), ("Print (220 ppi)", 220),
                                                          ("Web (150 ppi)", 150), ("E-mail (96 ppi)", 96)]
    private let sizes = NSTextField(labelWithString: "")
    private static var open: CompressPicturesSheet?
    private var generation = 0

    init(grid: GridView, selected: Int?) {
        self.grid = grid
        self.selected = selected
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        panel.title = L("Compress Pictures")
        onlySelected.state = selected != nil ? .on : .off
        onlySelected.isEnabled = selected != nil
        deleteCropped.state = .on
        for b in [onlySelected, deleteCropped] { b.target = self; b.action = #selector(optionsChanged) }
        let title = NSTextField(labelWithString: L("Resolution:"))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        resolutionButtons = CompressPicturesSheet.resolutions.enumerated().map { i, r in
            let b = NSButton(radioButtonWithTitle: L(r.0), target: self, action: #selector(optionsChanged))
            b.tag = i
            return b
        }
        resolutionButtons[1].state = .on
        sizes.textColor = .secondaryLabelColor
        sizes.font = .systemFont(ofSize: 11)
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: L("OK"), target: self, action: #selector(apply))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, ok])
        let options = NSStackView(views: [onlySelected, deleteCropped, title] + resolutionButtons + [sizes])
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 7
        options.setCustomSpacing(14, after: deleteCropped)
        options.setCustomSpacing(12, after: resolutionButtons.last!)
        let stack = NSStackView(views: [options, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                                     options.widthAnchor.constraint(greaterThanOrEqualToConstant: 340)])
        panel.contentView = content
    }

    func begin(on window: NSWindow) {
        guard let grid, !grid.book.pictures(sheet: grid.sheet).isEmpty else {
            let a = NSAlert()
            a.messageText = L("There are no pictures on this sheet.")
            a.beginSheetModal(for: window)
            return
        }
        CompressPicturesSheet.open = self
        optionsChanged()
        window.beginSheet(panel) { _ in CompressPicturesSheet.open = nil }
    }

    private var ppi: Double? { CompressPicturesSheet.resolutions[resolutionButtons.first { $0.state == .on }?.tag ?? 0].1 }

    private var targets: [PictureInfo] {
        guard let grid else { return [] }
        let all = grid.book.pictures(sheet: grid.sheet)
        if onlySelected.state == .on, let s = selected { return all.filter { $0.index == s } }
        return all
    }

    /// New bytes for each affected picture (nil: left as it is).
    private func results() -> [(PictureInfo, Data, (Data, PictureCrop)?)] {
        guard let grid else { return [] }
        let ppi = self.ppi, del = deleteCropped.state == .on
        return targets.compactMap { p in
            guard let data = grid.book.pictureImageData(sheet: grid.sheet, key: p.image) else { return nil }
            return (p, data, PictureData.compress(data, crop: p.crop, displayed: p.size, ppi: ppi, deleteCropped: del))
        }
    }

    /// Total bytes of the affected images before and after.
    func estimate() -> (Int, Int) {
        let r = results()
        return (r.reduce(0) { $0 + $1.1.count }, r.reduce(0) { $0 + ($1.2?.0.count ?? $1.1.count) })
    }

    @objc private func optionsChanged() {
        generation += 1
        let g = generation
        sizes.stringValue = L("Calculating…")
        DispatchQueue.main.async { [weak self] in
            guard let self, g == self.generation else { return }
            let (a, b) = self.estimate()
            self.sizes.stringValue = String(format: L("Size of the pictures: %@ → %@"),
                                            ByteCountFormatter.string(fromByteCount: Int64(a), countStyle: .file),
                                            ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file))
        }
    }

    @objc private func cancel() { panel.sheetParent?.endSheet(panel) }

    @objc func apply() {
        defer { panel.sheetParent?.endSheet(panel) }
        guard let grid else { return }
        let r = results().filter { $0.2 != nil }
        guard !r.isEmpty else { return }
        grid.book.grouped {
            for (p, _, new) in r {
                guard let (data, crop) = new else { continue }
                _ = grid.book.updatePicture(sheet: grid.sheet, index: p.index, PicturePatch(crop: crop), data: data)
            }
        }
        grid.contentChanged()
    }

    func configureForTesting(all: Bool, ppi: Double?, deleteCropped del: Bool) {
        onlySelected.state = all ? .off : .on
        deleteCropped.state = del ? .on : .off
        let i = CompressPicturesSheet.resolutions.firstIndex { $0.1 == ppi } ?? 0
        for b in resolutionButtons { b.state = b.tag == i ? .on : .off }
    }
}

// MARK: - Hooks

extension SheetWindowController {
    /// Insert ▸ Picture…: one or more image files at the active cell.
    @objc func insertPictureFromFile(_ sender: Any?) {
        guard let grid, let w = window, grid.commitIfEditing() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = L("Choose the pictures to insert")
        panel.beginSheetModal(for: w) { r in
            guard r == .OK else { return }
            PicturesUI.insert(urls: panel.urls, in: grid)
        }
    }

    /// Compress Pictures… with no picture selected: all pictures of the sheet.
    @objc func compressPictures(_ sender: Any?) {
        guard let grid, let w = window else { return }
        CompressPicturesSheet(grid: grid, selected: nil).begin(on: w)
    }
}

/// Image files and image data dropped on the grid become pictures where they are dropped.
extension GridView {
    private func droppedURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { (UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image)) ?? false }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        !droppedURLs(sender).isEmpty || sender.draggingPasteboard.availableType(from: [.png, .tiff]) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let p = convert(sender.draggingLocation, from: nil)
        let at = CGPoint(x: p.x / zoom, y: p.y / zoom)
        let urls = droppedURLs(sender)
        if !urls.isEmpty { PicturesUI.insert(urls: urls, in: self, at: at); return true }
        for t in [NSPasteboard.PasteboardType.png, .tiff] {
            if let d = sender.draggingPasteboard.data(forType: t), let (data, size) = PictureData.prepare(d) {
                PicturesUI.insert(data: data, size: PicturesUI.fittedInsertSize(size), in: self, at: at)
                return true
            }
        }
        return false
    }
}
