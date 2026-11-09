import AppKit
import CoreText
import ImageIO

/// A small player for Windows metafiles (EMF and WMF), the vector formats old Office clip art and pasted Visio or
/// chart pictures are stored in. macOS can't decode them, so pictures in this format are drawn with CoreGraphics:
/// shapes, paths, pens and brushes, text and embedded bitmaps. EMF+ records are skipped (dual files keep a plain
/// EMF version, which is what is drawn); rare records (palettes, ROP2 modes, hatches) are approximated or ignored.
final class Metafile {
    enum Kind { case emf, wmf }
    let kind: Kind
    private let bytes: [UInt8]
    /// The picture's area in the metafile's reference coordinates (EMF device units, WMF logical units).
    let frame: CGRect
    /// Natural size in points.
    let size: CGSize
    private var wmfStart = 0
    private var devPerMM: CGSize = CGSize(width: 3.78, height: 3.78)

    static func isMetafile(_ d: Data) -> Bool {
        guard d.count >= 44 else { return false }
        let b = [UInt8](d.prefix(44))
        if b[0] == 1, b[1] == 0, b[2] == 0, b[3] == 0, b[40] == 0x20, b[41] == 0x45, b[42] == 0x4D, b[43] == 0x46 { return true }
        return (b[0] == 0xD7 && b[1] == 0xCD && b[2] == 0xC6 && b[3] == 0x9A) || ((b[0] == 1 || b[0] == 2) && b[1] == 0 && b[2] == 9 && b[3] == 0)
    }

    init?(_ data: Data) {
        guard Metafile.isMetafile(data) else { return nil }
        bytes = [UInt8](data)
        let r = Reader(bytes)
        if r.u32(0) == 1 && r.u32(40) == 0x464D4520 {
            kind = .emf
            let bounds = r.rectl(8), fr = r.rectl(24)
            let dev = CGSize(width: CGFloat(r.i32(72)), height: CGFloat(r.i32(76)))
            let mm = CGSize(width: CGFloat(r.i32(80)), height: CGFloat(r.i32(84)))
            if dev.width > 0, dev.height > 0, mm.width > 0, mm.height > 0 {
                devPerMM = CGSize(width: dev.width / mm.width, height: dev.height / mm.height)
            }
            let k = CGSize(width: devPerMM.width / 100, height: devPerMM.height / 100)
            let frameDev = CGRect(x: fr.minX * k.width, y: fr.minY * k.height, width: fr.width * k.width, height: fr.height * k.height)
            frame = frameDev.width >= 1 && frameDev.height >= 1 ? frameDev : bounds
            let ptW = fr.width > 0 ? fr.width / 2540 * 72 : bounds.width * 0.75
            let ptH = fr.height > 0 ? fr.height / 2540 * 72 : bounds.height * 0.75
            size = CGSize(width: max(1, ptW), height: max(1, ptH))
        } else {
            kind = .wmf
            var start = 0
            var box: CGRect?
            var inch: CGFloat = 1440
            if r.u32(0) == 0x9AC6CDD7 {
                let l = CGFloat(r.i16(6)), t = CGFloat(r.i16(8)), rr = CGFloat(r.i16(10)), b = CGFloat(r.i16(12))
                box = CGRect(x: min(l, rr), y: min(t, b), width: abs(rr - l), height: abs(b - t))
                let i = CGFloat(r.u16(14)); if i > 0 { inch = i }
                start = 22
            }
            let headerWords = Int(r.u16(start + 2))
            wmfStart = start + max(9, headerWords) * 2
            if let box, box.width > 0, box.height > 0 {
                frame = box
            } else {
                // No placeable header: the first window origin/extent gives the picture's area.
                frame = Metafile.wmfWindow(r, from: wmfStart) ?? CGRect(x: 0, y: 0, width: 1000, height: 1000)
            }
            if box == nil {
                // No placeable header: units are usually screen pixels (96 dpi).
                inch = 96
            }
            size = CGSize(width: max(1, frame.width / inch * 72), height: max(1, frame.height / inch * 72))
        }
        guard frame.width > 0, frame.height > 0, frame.width.isFinite, frame.height.isFinite else { return nil }
    }

    private static func wmfWindow(_ r: Reader, from start: Int) -> CGRect? {
        var off = start, org = CGPoint.zero, ext: CGSize?
        while off + 6 <= r.count {
            let words = Int(r.u32(off)), fn = r.u16(off + 4)
            if fn == 0x020B { org = CGPoint(x: CGFloat(r.i16(off + 8)), y: CGFloat(r.i16(off + 6))) }
            if fn == 0x020C { ext = CGSize(width: CGFloat(r.i16(off + 8)), height: CGFloat(r.i16(off + 6))) }
            if fn == 0 || words < 3 { break }
            off += words * 2
        }
        guard let ext, ext.width != 0, ext.height != 0 else { return nil }
        return CGRect(x: min(org.x, org.x + ext.width), y: min(org.y, org.y + ext.height), width: abs(ext.width), height: abs(ext.height))
    }

    /// Renders the picture with `maxPixels` on its longer side (transparent background).
    func image(maxPixels: Int) -> CGImage? {
        let ar = frame.width / frame.height
        let w = max(1, ar >= 1 ? maxPixels : Int((CGFloat(maxPixels) * ar).rounded()))
        let h = max(1, ar >= 1 ? Int((CGFloat(maxPixels) / ar).rounded()) : maxPixels)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        draw(in: CGRect(x: 0, y: 0, width: w, height: h), ctx: ctx)
        return ctx.makeImage()
    }

    /// Plays the metafile into `rect` of a y-down context.
    func draw(in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / frame.width, y: rect.height / frame.height)
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        ctx.setShouldAntialias(true)
        let p = Player(ctx: ctx, devPerMM: devPerMM, pixel: max(frame.width / rect.width, frame.height / rect.height))
        switch kind {
        case .emf: p.playEMF(Reader(bytes))
        case .wmf:
            p.wmfFrame = frame
            p.playWMF(Reader(bytes), from: wmfStart)
        }
        ctx.restoreGState()
    }
}

// MARK: - Reading

private struct Reader {
    let b: [UInt8]
    init(_ b: [UInt8]) { self.b = b }
    var count: Int { b.count }
    func u8(_ o: Int) -> UInt8 { o >= 0 && o < b.count ? b[o] : 0 }
    func u16(_ o: Int) -> UInt16 { guard o >= 0, o + 2 <= b.count else { return 0 }; return UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
    func i16(_ o: Int) -> Int16 { Int16(bitPattern: u16(o)) }
    func u32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    func i32(_ o: Int) -> Int32 { Int32(bitPattern: u32(o)) }
    func f32(_ o: Int) -> CGFloat { CGFloat(Float(bitPattern: u32(o))) }
    func point32(_ o: Int) -> CGPoint { CGPoint(x: CGFloat(i32(o)), y: CGFloat(i32(o + 4))) }
    func point16(_ o: Int) -> CGPoint { CGPoint(x: CGFloat(i16(o)), y: CGFloat(i16(o + 2))) }
    /// RECTL (left, top, right, bottom) as a normalized rect.
    func rectl(_ o: Int) -> CGRect {
        let l = CGFloat(i32(o)), t = CGFloat(i32(o + 4)), r = CGFloat(i32(o + 8)), bt = CGFloat(i32(o + 12))
        return CGRect(x: min(l, r), y: min(t, bt), width: abs(r - l), height: abs(bt - t))
    }
    func color(_ o: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(u8(o)) / 255, green: CGFloat(u8(o + 1)) / 255, blue: CGFloat(u8(o + 2)) / 255, alpha: 1)
    }
    func slice(_ o: Int, _ n: Int) -> ArraySlice<UInt8>? {
        guard o >= 0, n >= 0, o + n <= b.count else { return nil }
        return b[o..<(o + n)]
    }
}

// MARK: - Player

private struct Pen {
    var color = CGColor(gray: 0, alpha: 1)
    var width: CGFloat = 0          // logical units; 0 = one device pixel
    var style: UInt32 = 0           // PS_* (low 4 bits), end cap and join flags
    var null: Bool { style & 0xF == 5 }
}
private struct Brush { var color: CGColor? = CGColor(gray: 1, alpha: 1) }   // nil = hollow
private struct Font {
    var height: CGFloat = 12, weight = 400, italic = false, underline = false, strike = false
    var escapement: CGFloat = 0     // tenths of a degree
    var face = ""
    var charset: UInt8 = 1
}
private enum Obj { case pen(Pen), brush(Brush), font(Font), other }

private struct DC {
    var pen = Pen()
    var brush = Brush()
    var font = Font()
    var textColor = CGColor(gray: 0, alpha: 1)
    var bkColor = CGColor(gray: 1, alpha: 1)
    var bkOpaque = true
    var textAlign: UInt32 = 0
    var evenOdd = true
    var mapMode: UInt32 = 1
    var winOrg = CGPoint.zero, winExt = CGSize(width: 1, height: 1)
    var vpOrg = CGPoint.zero, vpExt = CGSize(width: 1, height: 1)
    var world = CGAffineTransform.identity
    var clips: [CGPath] = []        // device space, intersected
    var cur = CGPoint.zero          // logical
    var arcClockwise = false
}

private final class Player {
    let ctx: CGContext
    let devPerMM: CGSize
    let pixel: CGFloat              // one output pixel, in device units (cosmetic pen width)
    var wmfFrame: CGRect = .zero
    var dc = DC()
    var stack: [DC] = []
    var objects: [Int: Obj] = [:]
    var path: CGMutablePath?        // open BeginPath bracket (device space)
    var wmfObjects: [Obj?] = []

    init(ctx: CGContext, devPerMM: CGSize, pixel: CGFloat) {
        self.ctx = ctx; self.devPerMM = devPerMM; self.pixel = pixel
    }

    // Transform ---------------------------------------------------------------

    /// Logical -> device (EMF) or logical -> frame (WMF) transform.
    var T: CGAffineTransform {
        var sx: CGFloat = 1, sy: CGFloat = 1
        switch dc.mapMode {
        case 2: sx = 0.1 * devPerMM.width; sy = -0.1 * devPerMM.height
        case 3: sx = 0.01 * devPerMM.width; sy = -0.01 * devPerMM.height
        case 4: sx = 0.254 * devPerMM.width; sy = -0.254 * devPerMM.height
        case 5: sx = 0.0254 * devPerMM.width; sy = -0.0254 * devPerMM.height
        case 6: sx = 25.4 / 1440 * devPerMM.width; sy = -25.4 / 1440 * devPerMM.height
        case 7, 8:
            if dc.winExt.width != 0, dc.winExt.height != 0 {
                sx = dc.vpExt.width / dc.winExt.width; sy = dc.vpExt.height / dc.winExt.height
                if dc.mapMode == 7 {
                    let m = min(abs(sx), abs(sy)); sx = sx < 0 ? -m : m; sy = sy < 0 ? -m : m
                }
            }
        default: break
        }
        let page = CGAffineTransform(translationX: -dc.winOrg.x, y: -dc.winOrg.y)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            .concatenating(CGAffineTransform(translationX: dc.vpOrg.x, y: dc.vpOrg.y))
        return dc.world.concatenating(page)
    }

    /// WMF: the window is mapped onto the picture's frame (placeable files) or used as is.
    var wmfT: CGAffineTransform {
        guard dc.winExt.width != 0, dc.winExt.height != 0, !(dc.winExt.width == 1 && dc.winExt.height == 1) else { return .identity }
        return CGAffineTransform(translationX: -dc.winOrg.x, y: -dc.winOrg.y)
            .concatenating(CGAffineTransform(scaleX: wmfFrame.width / abs(dc.winExt.width) * (dc.winExt.width < 0 ? -1 : 1),
                                             y: wmfFrame.height / abs(dc.winExt.height) * (dc.winExt.height < 0 ? -1 : 1)))
            .concatenating(CGAffineTransform(translationX: wmfFrame.minX, y: wmfFrame.minY))
    }
    var isWMF = false
    var xf: CGAffineTransform { isWMF ? wmfT : T }
    func dev(_ p: CGPoint) -> CGPoint { p.applying(xf) }
    var scale: CGFloat { let t = xf; return sqrt(abs(t.a * t.d - t.b * t.c)) }

    // Drawing -----------------------------------------------------------------

    private func withClip(_ body: () -> Void) {
        ctx.saveGState()
        for c in dc.clips { ctx.addPath(c); ctx.clip() }
        body()
        ctx.restoreGState()
    }

    private func applyPen() -> Bool {
        let p = dc.pen
        guard !p.null else { return false }
        let w = p.width <= 0 ? pixel : max(pixel, p.width * scale)
        ctx.setStrokeColor(p.color)
        ctx.setLineWidth(w)
        switch p.style & 0xF00 { case 0x100: ctx.setLineCap(.square); case 0x200: ctx.setLineCap(.butt); default: ctx.setLineCap(.round) }
        switch p.style & 0xF000 { case 0x1000: ctx.setLineJoin(.bevel); case 0x2000: ctx.setLineJoin(.miter); default: ctx.setLineJoin(.round) }
        let u = max(w, pixel)
        switch p.style & 0xF {
        case 1: ctx.setLineDash(phase: 0, lengths: [6 * u, 2 * u]); ctx.setLineCap(.butt)
        case 2: ctx.setLineDash(phase: 0, lengths: [u, u]); ctx.setLineCap(.butt)
        case 3: ctx.setLineDash(phase: 0, lengths: [3 * u, 2 * u, u, 2 * u]); ctx.setLineCap(.butt)
        case 4: ctx.setLineDash(phase: 0, lengths: [3 * u, u, u, u, u, u]); ctx.setLineCap(.butt)
        default: ctx.setLineDash(phase: 0, lengths: [])
        }
        return true
    }

    /// Fills (closed shapes) and strokes a device-space path, or adds it to the open path bracket.
    func render(_ p: CGPath, fill: Bool, stroke: Bool = true) {
        if let path { path.addPath(p); return }
        withClip {
            if fill, let c = dc.brush.color {
                ctx.addPath(p); ctx.setFillColor(c)
                ctx.fillPath(using: dc.evenOdd ? .evenOdd : .winding)
            }
            if stroke, applyPen() { ctx.addPath(p); ctx.strokePath() }
        }
    }

    func poly(_ pts: [CGPoint], closed: Bool) -> CGPath {
        let m = CGMutablePath()
        guard let f = pts.first else { return m }
        m.move(to: dev(f))
        for q in pts.dropFirst() { m.addLine(to: dev(q)) }
        if closed { m.closeSubpath() }
        return m
    }

    func beziers(_ pts: [CGPoint], from start: CGPoint?) -> CGPath {
        let m = CGMutablePath()
        var i = 0
        if let start { m.move(to: dev(start)) } else if let f = pts.first { m.move(to: dev(f)); i = 1 }
        while i + 2 < pts.count {
            m.addCurve(to: dev(pts[i + 2]), control1: dev(pts[i]), control2: dev(pts[i + 1]))
            i += 3
        }
        return m
    }

    func rect(_ r: CGRect) -> CGPath { var t = xf; return CGPath(rect: r, transform: &t) }
    func ellipse(_ r: CGRect) -> CGPath { var t = xf; return CGPath(ellipseIn: r, transform: &t) }
    func roundRect(_ r: CGRect, _ corner: CGSize) -> CGPath {
        var t = xf
        let cw = min(abs(corner.width) / 2, r.width / 2), ch = min(abs(corner.height) / 2, r.height / 2)
        return CGPath(roundedRect: r, cornerWidth: cw, cornerHeight: ch, transform: &t)
    }

    /// Arc (0), chord (1) or pie (2) of the ellipse in `box`, from the radial through `a` to the one through `b`.
    func arc(_ box: CGRect, _ a: CGPoint, _ b: CGPoint, kind: Int, continueFrom: Bool = false) -> CGPath {
        let c = CGPoint(x: box.midX, y: box.midY), rx = max(box.width / 2, 0.0001), ry = max(box.height / 2, 0.0001)
        let t0 = atan2((a.y - c.y) / ry, (a.x - c.x) / rx)
        var t1 = atan2((b.y - c.y) / ry, (b.x - c.x) / rx)
        // GDI's default direction is counterclockwise on screen (y down): decreasing angles.
        if dc.arcClockwise { while t1 <= t0 { t1 += 2 * .pi } } else { while t1 >= t0 { t1 -= 2 * .pi } }
        let n = max(8, Int(abs(t1 - t0) / (2 * .pi) * 96))
        let m = CGMutablePath()
        for i in 0...n {
            let t = t0 + (t1 - t0) * CGFloat(i) / CGFloat(n)
            let q = dev(CGPoint(x: c.x + rx * cos(t), y: c.y + ry * sin(t)))
            if i == 0 {
                if kind == 2 { m.move(to: dev(c)); m.addLine(to: q) }
                else if continueFrom { m.move(to: dev(dc.cur)); m.addLine(to: q) }
                else { m.move(to: q) }
            } else { m.addLine(to: q) }
        }
        if kind > 0 { m.closeSubpath() }
        return m
    }

    func lineTo(_ p: CGPoint) {
        let m = CGMutablePath()
        m.move(to: dev(dc.cur)); m.addLine(to: dev(p))
        dc.cur = p
        if let path { path.addLine(to: dev(p)) } else { render(m, fill: false) }
    }

    func moveTo(_ p: CGPoint) {
        dc.cur = p
        path?.move(to: dev(p))
    }

    // Text --------------------------------------------------------------------

    /// Draws `s` at the logical reference point with the current font, colour and alignment. `dx`: advance of
    /// each UTF-16 unit in logical units (GDI's inter-character spacing), when the record has it.
    func text(_ raw: String, at ref: CGPoint, dx rawDx: [CGFloat]? = nil) {
        var s = raw, dx = rawDx
        if dc.font.charset == 2 || Metafile.isSymbolFace(dc.font.face) {   // symbol fonts: their codes as Unicode
            s = String(String.UnicodeScalarView(raw.unicodeScalars.map { Metafile.symbolScalar($0) }))
            if dx != nil, s.utf16.count != raw.utf16.count { dx = nil }
        }
        guard !s.isEmpty else { return }
        let f = dc.font
        let t = xf
        let ys = sqrt(t.c * t.c + t.d * t.d), xs = sqrt(t.a * t.a + t.b * t.b)
        var em = abs(f.height) * ys
        if f.height > 0 { em *= 0.82 }
        if em < 0.5 { em = 12 * ys }
        var traits: NSFontTraitMask = []
        if f.weight >= 600 { traits.insert(.boldFontMask) }
        if f.italic { traits.insert(.italicFontMask) }
        let family = Metafile.macFamily(f.face.isEmpty ? "Helvetica" : f.face, charset: f.charset)
        let font = NSFontManager.shared.font(withFamily: family, traits: traits, weight: f.weight >= 600 ? 9 : 5, size: em)
            ?? NSFontManager.shared.convert(NSFont.systemFont(ofSize: em), toHaveTrait: traits)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: dc.textColor) ?? .black]
        if f.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if f.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        // Runs: the whole string, or one per character placed at GDI's advances.
        var runs: [(CTLine, CGFloat)] = []
        var width: CGFloat = 0
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        if let dx, dx.count >= s.utf16.count {
            var i = 0
            for ch in s {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(ch), attributes: attrs))
                var a: CGFloat = 0, d: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &a, &d, &lead)
                asc = max(asc, a); desc = max(desc, d)
                runs.append((line, width))
                let k = String(ch).utf16.count
                width += dx[i..<min(dx.count, i + k)].reduce(0, +) * xs
                i += k
            }
        } else {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
            width = CGFloat(CTLineGetTypographicBounds(line, &asc, &desc, &lead))
            runs = [(line, 0)]
        }
        let align = dc.textAlign
        let x: CGFloat = align & 6 == 6 ? -width / 2 : (align & 6 == 2 ? -width : 0)
        let y: CGFloat = align & 24 == 24 ? 0 : (align & 8 == 8 ? desc : -asc)
        let p = dev(ref)
        let flipY = t.d < 0       // logical y up: text is still upright on screen
        withClip {
            ctx.translateBy(x: p.x, y: p.y)
            ctx.scaleBy(x: 1, y: -1)
            var angle = f.escapement / 10 * .pi / 180
            if flipY { angle = -angle }
            if angle != 0 { ctx.rotate(by: angle) }
            for (line, off) in runs {
                ctx.textPosition = CGPoint(x: x + off, y: y)
                CTLineDraw(line, ctx)
            }
        }
        if align & 1 != 0, xs > 0 { dc.cur.x += (align & 6 == 2 ? -width : width) / xs }   // TA_UPDATECP
    }

    // Bitmaps -----------------------------------------------------------------

    /// Draws a DIB (BITMAPINFO + bits) into the logical rect `dest`, cropped to the source rect.
    func dib(_ r: Reader, bmi: Int, bmiLen: Int, bits: Int, bitsLen: Int, src: CGRect?, dest: CGRect, rop: UInt32, alpha: CGFloat? = nil) {
        guard let img = Metafile.decodeDIB(r, bmi: bmi, bmiLen: bmiLen, bits: bits, bitsLen: bitsLen, forceAlpha: alpha != nil) else { return }
        var part = img
        if let src, src.width > 0, src.height > 0,
           !(src.minX == 0 && src.minY == 0 && Int(src.width) == img.width && Int(src.height) == img.height),
           let c = img.cropping(to: src.intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))) { part = c }
        let a = dev(dest.origin), b = dev(CGPoint(x: dest.maxX, y: dest.maxY))
        let d = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        let flipX = (b.x - a.x) < 0, flipY = (b.y - a.y) < 0
        withClip {
            switch rop {
            case 0x008800C6, 0x00BB0226: ctx.setBlendMode(.multiply)     // SRCAND, MERGEPAINT ≈ multiply
            case 0x00EE0086: ctx.setBlendMode(.lighten)                    // SRCPAINT (OR)
            case 0x00660046: ctx.setBlendMode(.difference)                 // SRCINVERT (XOR)
            default: break
            }
            if let alpha { ctx.setAlpha(alpha) }
            ctx.interpolationQuality = .high
            ctx.translateBy(x: flipX ? d.maxX : d.minX, y: flipY ? d.minY : d.maxY)
            ctx.scaleBy(x: flipX ? -1 : 1, y: flipY ? 1 : -1)
            ctx.draw(part, in: CGRect(x: 0, y: 0, width: d.width, height: d.height))
        }
    }

    /// BitBlt without a source bitmap: a pattern (brush) fill, or black/white.
    func patBlt(_ dest: CGRect, rop: UInt32) {
        let color: CGColor?
        switch rop {
        case 0x00000042: color = CGColor(gray: 0, alpha: 1)
        case 0x00FF0062: color = CGColor(gray: 1, alpha: 1)
        case 0x00F00021: color = dc.brush.color
        default: color = nil
        }
        guard let color else { return }
        let p = rect(dest)
        withClip { ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath() }
    }

    // Objects -----------------------------------------------------------------

    func select(_ o: Obj?) {
        switch o {
        case .pen(let p): dc.pen = p
        case .brush(let b): dc.brush = b
        case .font(let f): dc.font = f
        default: break
        }
    }

    func stock(_ i: UInt32) -> Obj? {
        switch i & 0x7FFFFFFF {
        case 0: return .brush(Brush(color: CGColor(gray: 1, alpha: 1)))
        case 1: return .brush(Brush(color: CGColor(gray: 0.75, alpha: 1)))
        case 2: return .brush(Brush(color: CGColor(gray: 0.5, alpha: 1)))
        case 3: return .brush(Brush(color: CGColor(gray: 0.25, alpha: 1)))
        case 4: return .brush(Brush(color: CGColor(gray: 0, alpha: 1)))
        case 5: return .brush(Brush(color: nil))
        case 6: return .pen(Pen(color: CGColor(gray: 1, alpha: 1)))
        case 7: return .pen(Pen())
        case 8: return .pen(Pen(style: 5))
        case 10...17: return .font(Font())
        case 18: return .brush(Brush(color: CGColor(gray: 1, alpha: 1)))   // DC_BRUSH
        case 19: return .pen(Pen())                                         // DC_PEN
        default: return nil
        }
    }

    static func font(_ r: Reader, at o: Int, wide: Bool) -> Font {
        var f = Font()
        f.height = CGFloat(wide ? r.i32(o) : Int32(r.i16(o)))
        let s = wide ? 4 : 2
        f.escapement = CGFloat(wide ? r.i32(o + 2 * s) : Int32(r.i16(o + 2 * s)))
        f.weight = Int(wide ? r.i32(o + 4 * s) : Int32(r.i16(o + 4 * s)))
        let b = o + 5 * s
        f.italic = r.u8(b) != 0; f.underline = r.u8(b + 1) != 0; f.strike = r.u8(b + 2) != 0
        f.charset = r.u8(b + 3)
        let face = b + 8
        if wide {
            var u: [UInt16] = []
            for i in 0..<32 { let c = r.u16(face + i * 2); if c == 0 { break }; u.append(c) }
            f.face = String(utf16CodeUnits: u, count: u.count)
        } else {
            var a: [UInt8] = []
            for i in 0..<32 { let c = r.u8(face + i); if c == 0 { break }; a.append(c) }
            f.face = Metafile.decodeANSI(a, charset: f.charset, dx: nil).0
        }
        return f
    }

    // EMF -----------------------------------------------------------------------

    func playEMF(_ r: Reader) {
        var off = 0
        var guardCount = 0
        while off + 8 <= r.count, guardCount < 2_000_000 {
            guardCount += 1
            let type = r.u32(off), size = Int(r.u32(off + 4))
            guard size >= 8, off + size <= r.count else { break }
            emfRecord(type, r, off, size)
            if type == 14 { break }
            off += size
        }
    }

    func points32(_ r: Reader, _ o: Int, _ n: Int) -> [CGPoint] { (0..<max(0, min(n, (r.count - o) / 8))).map { r.point32(o + $0 * 8) } }
    func points16(_ r: Reader, _ o: Int, _ n: Int) -> [CGPoint] { (0..<max(0, min(n, (r.count - o) / 4))).map { r.point16(o + $0 * 4) } }

    func emfRecord(_ type: UInt32, _ r: Reader, _ o: Int, _ size: Int) {
        switch type {
        // Polygons and lines (32-bit points: 2..8, 16-bit: 85..91)
        case 2, 85:   // POLYBEZIER
            let n = Int(r.u32(o + 24)); let pts = type == 2 ? points32(r, o + 28, n) : points16(r, o + 28, n)
            render(beziers(pts, from: nil), fill: false)
        case 3, 86:   // POLYGON
            let n = Int(r.u32(o + 24)); let pts = type == 3 ? points32(r, o + 28, n) : points16(r, o + 28, n)
            render(poly(pts, closed: true), fill: true)
        case 4, 87:   // POLYLINE
            let n = Int(r.u32(o + 24)); let pts = type == 4 ? points32(r, o + 28, n) : points16(r, o + 28, n)
            if let path { if let f = pts.first { path.move(to: dev(f)); pts.dropFirst().forEach { path.addLine(to: dev($0)) } } }
            else { render(poly(pts, closed: false), fill: false) }
        case 5, 88:   // POLYBEZIERTO
            let n = Int(r.u32(o + 24)); let pts = type == 5 ? points32(r, o + 28, n) : points16(r, o + 28, n)
            if let path {
                var i = 0
                while i + 2 < pts.count { path.addCurve(to: dev(pts[i + 2]), control1: dev(pts[i]), control2: dev(pts[i + 1])); i += 3 }
            } else { render(beziers(pts, from: dc.cur), fill: false) }
            if let l = pts.last { dc.cur = l }
        case 6, 89:   // POLYLINETO
            let n = Int(r.u32(o + 24)); let pts = type == 6 ? points32(r, o + 28, n) : points16(r, o + 28, n)
            if let path { pts.forEach { path.addLine(to: dev($0)) } }
            else { render(poly([dc.cur] + pts, closed: false), fill: false) }
            if let l = pts.last { dc.cur = l }
        case 7, 8, 90, 91:   // POLYPOLYLINE, POLYPOLYGON
            let polys = Int(r.u32(o + 24)), wide = type == 7 || type == 8
            let closed = type == 8 || type == 91
            var counts: [Int] = []
            for i in 0..<min(polys, 100_000) { counts.append(Int(r.u32(o + 32 + i * 4))) }
            var p = o + 32 + polys * 4
            let m = CGMutablePath()
            for c in counts {
                let pts = wide ? points32(r, p, c) : points16(r, p, c)
                p += c * (wide ? 8 : 4)
                m.addPath(poly(pts, closed: closed))
            }
            render(m, fill: closed)
        case 27: moveTo(r.point32(o + 8))   // MOVETOEX
        case 54: lineTo(r.point32(o + 8))   // LINETO
        case 42: render(ellipse(r.rectl(o + 8)), fill: true)
        case 43: render(rect(r.rectl(o + 8)), fill: true)
        case 44: render(roundRect(r.rectl(o + 8), CGSize(width: CGFloat(r.i32(o + 24)), height: CGFloat(r.i32(o + 28)))), fill: true)
        case 45, 46, 47:   // ARC, CHORD, PIE
            render(arc(r.rectl(o + 8), r.point32(o + 24), r.point32(o + 32), kind: Int(type - 45)), fill: type != 45)
        case 55:   // ARCTO
            let box = r.rectl(o + 8), b = r.point32(o + 32)
            let p = arc(box, r.point32(o + 24), b, kind: 0, continueFrom: true)
            if let path { path.addPath(p) } else { render(p, fill: false) }
            let c = CGPoint(x: box.midX, y: box.midY), t = atan2((b.y - c.y) / max(box.height / 2, 0.0001), (b.x - c.x) / max(box.width / 2, 0.0001))
            dc.cur = CGPoint(x: c.x + box.width / 2 * cos(t), y: c.y + box.height / 2 * sin(t))
        case 57: dc.arcClockwise = r.u32(o + 8) == 2   // SETARCDIRECTION

        // Paths
        case 59: path = CGMutablePath(); path?.move(to: dev(dc.cur))   // BEGINPATH
        case 60: break                                                  // ENDPATH (kept until used)
        case 61: path?.closeSubpath()                                   // CLOSEFIGURE
        case 62, 63, 64:   // FILLPATH, STROKEANDFILLPATH, STROKEPATH
            if let p = path {
                path = nil
                render(p, fill: type != 64, stroke: type != 62)
            }
        case 67:   // SELECTCLIPPATH
            if let p = path { path = nil; clip(p, mode: r.u32(o + 8)) }
        case 68: path = nil   // ABORTPATH
        case 65, 66: break    // FLATTENPATH, WIDENPATH

        // State
        case 9: dc.winExt = CGSize(width: CGFloat(r.i32(o + 8)), height: CGFloat(r.i32(o + 12)))
        case 10: dc.winOrg = r.point32(o + 8)
        case 11: dc.vpExt = CGSize(width: CGFloat(r.i32(o + 8)), height: CGFloat(r.i32(o + 12)))
        case 12: dc.vpOrg = r.point32(o + 8)
        case 17: dc.mapMode = r.u32(o + 8)
        case 18: dc.bkOpaque = r.u32(o + 8) == 2
        case 19: dc.evenOdd = r.u32(o + 8) != 2
        case 22: dc.textAlign = r.u32(o + 8)
        case 24: dc.textColor = r.color(o + 8)
        case 25: dc.bkColor = r.color(o + 8)
        case 32, 30:   // EXCLUDECLIPRECT (ignored), INTERSECTCLIPRECT
            if type == 30 { clip(rect(r.rectl(o + 8)), mode: 1) }
        case 33: stack.append(dc)   // SAVEDC
        case 34:   // RESTOREDC
            let n = Int(r.i32(o + 8))
            let target = n < 0 ? stack.count + n : n - 1
            if target >= 0, target < stack.count { dc = stack[target]; stack.removeSubrange(target...) }
        case 35:   // SETWORLDTRANSFORM
            dc.world = xform(r, o + 8)
        case 36:   // MODIFYWORLDTRANSFORM
            let x = xform(r, o + 8)
            switch r.u32(o + 32) {
            case 1: dc.world = .identity
            case 2: dc.world = x.concatenating(dc.world)
            case 3: dc.world = dc.world.concatenating(x)
            case 4: dc.world = x
            default: break
            }
        case 75:   // EXTSELECTCLIPRGN
            let cb = Int(r.u32(o + 8)), mode = r.u32(o + 12)
            if cb == 0 { if mode == 5 { dc.clips = [] } }
            else { clip(region(r, o + 16, logical: false), mode: mode) }

        // Objects
        case 37:   // SELECTOBJECT
            let i = r.u32(o + 8)
            select(i & 0x80000000 != 0 ? stock(i) : objects[Int(i)])
        case 38:   // CREATEPEN
            objects[Int(r.u32(o + 8))] = .pen(Pen(color: r.color(o + 24), width: CGFloat(r.i32(o + 16)), style: r.u32(o + 12)))
        case 95:   // EXTCREATEPEN
            let style = r.u32(o + 28), brushStyle = r.u32(o + 36)
            var pen = Pen(color: r.color(o + 40), width: CGFloat(r.u32(o + 32)), style: style)
            if style & 0x10000 == 0 { pen.width = 0 }         // cosmetic
            if brushStyle == 1 { pen.style = 5 }              // hollow brush: no line
            objects[Int(r.u32(o + 8))] = .pen(pen)
        case 39:   // CREATEBRUSHINDIRECT
            let style = r.u32(o + 12)
            objects[Int(r.u32(o + 8))] = .brush(Brush(color: style == 1 ? nil : r.color(o + 16)))
        case 93, 94:   // CREATEMONOBRUSH, CREATEDIBPATTERNBRUSHPT: average-ish gray
            objects[Int(r.u32(o + 8))] = .brush(Brush(color: CGColor(gray: 0.6, alpha: 1)))
        case 82:   // EXTCREATEFONTINDIRECTW
            objects[Int(r.u32(o + 8))] = .font(Player.font(r, at: o + 12, wide: true))
        case 49: objects[Int(r.u32(o + 8))] = .other   // CREATEPALETTE
        case 40: objects[Int(r.u32(o + 8))] = nil       // DELETEOBJECT

        // Regions
        case 71, 74:   // FILLRGN, PAINTRGN
            let cb = Int(r.u32(o + 24))
            let data = type == 71 ? o + 32 : o + 28
            let saved = dc.brush
            if type == 71, case .brush(let b)? = objects[Int(r.u32(o + 28))] { dc.brush = b }
            if cb > 0 { render(region(r, data, logical: true), fill: true, stroke: false) }
            dc.brush = saved

        // Bitmaps
        case 81:   // STRETCHDIBITS
            let dest = CGRect(x: CGFloat(r.i32(o + 24)), y: CGFloat(r.i32(o + 28)), width: CGFloat(r.i32(o + 72)), height: CGFloat(r.i32(o + 76)))
            let src = CGRect(x: CGFloat(r.i32(o + 32)), y: CGFloat(r.i32(o + 36)), width: CGFloat(r.i32(o + 40)), height: CGFloat(r.i32(o + 44)))
            let bmi = Int(r.u32(o + 48)), cbBmi = Int(r.u32(o + 52)), bits = Int(r.u32(o + 56)), cbBits = Int(r.u32(o + 60))
            let rop = r.u32(o + 68)
            if cbBmi > 0 { dib(r, bmi: o + bmi, bmiLen: cbBmi, bits: o + bits, bitsLen: cbBits, src: flipSrc(r, o + bmi, src), dest: dest, rop: rop) }
            else { patBlt(dest, rop: rop) }
        case 80:   // SETDIBITSTODEVICE
            let src = CGRect(x: CGFloat(r.i32(o + 32)), y: CGFloat(r.i32(o + 36)), width: CGFloat(r.i32(o + 40)), height: CGFloat(r.i32(o + 44)))
            let dest = CGRect(x: CGFloat(r.i32(o + 24)), y: CGFloat(r.i32(o + 28)), width: src.width, height: src.height)
            let bmi = Int(r.u32(o + 48)), cbBmi = Int(r.u32(o + 52)), bits = Int(r.u32(o + 56)), cbBits = Int(r.u32(o + 60))
            if cbBmi > 0 { dib(r, bmi: o + bmi, bmiLen: cbBmi, bits: o + bits, bitsLen: cbBits, src: flipSrc(r, o + bmi, src), dest: dest, rop: 0x00CC0020) }
        case 76, 77, 114:   // BITBLT, STRETCHBLT, ALPHABLEND
            let dest = CGRect(x: CGFloat(r.i32(o + 24)), y: CGFloat(r.i32(o + 28)), width: CGFloat(r.i32(o + 32)), height: CGFloat(r.i32(o + 36)))
            let rop = r.u32(o + 40)
            let bmi = Int(r.u32(o + 84)), cbBmi = Int(r.u32(o + 88)), bits = Int(r.u32(o + 92)), cbBits = Int(r.u32(o + 96))
            var src = CGRect(x: CGFloat(r.i32(o + 44)), y: CGFloat(r.i32(o + 48)), width: dest.width, height: dest.height)
            if type != 76 { src.size = CGSize(width: CGFloat(r.i32(o + 100)), height: CGFloat(r.i32(o + 104))) }
            if cbBmi > 0 {
                let alpha: CGFloat? = type == 114 ? CGFloat(r.u8(o + 42)) / 255 : nil
                dib(r, bmi: o + bmi, bmiLen: cbBmi, bits: o + bits, bitsLen: cbBits, src: src, dest: dest,
                    rop: type == 114 ? 0x00CC0020 : rop, alpha: alpha)
            } else if type != 114 { patBlt(dest, rop: rop) }

        // Text
        case 84, 83:   // EXTTEXTOUTW, EXTTEXTOUTA
            let ref = r.point32(o + 36), n = Int(r.u32(o + 44)), offStr = Int(r.u32(o + 48)), offDx = Int(r.u32(o + 72))
            guard n > 0, n < 100_000 else { return }
            let s: String
            if type == 84 {
                let u = (0..<n).map { r.u16(o + offStr + $0 * 2) }
                s = String(utf16CodeUnits: u, count: u.count)
            } else {
                s = ""
            }
            var dx: [CGFloat]? = offDx > 0 && o + offDx + n * 4 <= o + size ? (0..<n).map { CGFloat(r.i32(o + offDx + $0 * 4)) } : nil
            var text = s
            if type == 83 { (text, dx) = Metafile.decodeANSI((0..<n).map { r.u8(o + offStr + $0) }, charset: dc.font.charset, dx: dx) }
            let opts = r.u32(o + 52)
            if opts & 0x2 != 0 {   // ETO_OPAQUE: background rectangle
                let saved = dc.brush; dc.brush = Brush(color: dc.bkColor)
                let rr = r.rectl(o + 56); if rr.width > 0 { render(rect(rr), fill: true, stroke: false) }
                dc.brush = saved
            }
            self.text(text, at: dc.textAlign & 1 != 0 ? dc.cur : ref, dx: dx)
        default: break   // header, GDI comments (EMF+), palettes, ICM, stretch/ROP2 modes, miter limit…
        }
    }

    /// StretchDIBits/SetDIBitsToDevice source rects of a bottom-up DIB (positive height) count from its
    /// bottom-left corner; CGImage's origin is top-left.
    func flipSrc(_ r: Reader, _ bmi: Int, _ src: CGRect) -> CGRect? {
        let core = r.u32(bmi) == 12
        let hRaw = core ? Int(r.i16(bmi + 6)) : Int(r.i32(bmi + 8))
        guard hRaw > 0 else { return src }
        return CGRect(x: src.minX, y: CGFloat(hRaw) - src.maxY, width: src.width, height: src.height)
    }

    func xform(_ r: Reader, _ o: Int) -> CGAffineTransform {
        CGAffineTransform(a: r.f32(o), b: r.f32(o + 4), c: r.f32(o + 8), d: r.f32(o + 12), tx: r.f32(o + 16), ty: r.f32(o + 20))
    }

    /// RGNDATA rectangles as a device-space path.
    func region(_ r: Reader, _ o: Int, logical: Bool) -> CGPath {
        let n = Int(r.u32(o + 8))
        let m = CGMutablePath()
        for i in 0..<min(n, 100_000) {
            let rr = r.rectl(o + 32 + i * 16)
            if logical { m.addPath(rect(rr)) } else { m.addRect(rr) }
        }
        return m
    }

    /// RGN_AND (1) and RGN_COPY (5) are what metafiles use in practice; others reset or are ignored.
    func clip(_ p: CGPath, mode: UInt32) {
        switch mode {
        case 1: dc.clips.append(p)
        case 5: dc.clips = [p]
        default: break
        }
    }

    // WMF -----------------------------------------------------------------------

    func playWMF(_ r: Reader, from start: Int) {
        isWMF = true
        dc.mapMode = 8
        var off = start
        var guardCount = 0
        while off + 6 <= r.count, guardCount < 2_000_000 {
            guardCount += 1
            let words = Int(r.u32(off)), fn = r.u16(off + 4)
            guard words >= 3, off + words * 2 <= r.count else { break }
            if fn == 0 { break }
            wmfRecord(fn, r, off + 6, words * 2 - 6)
            off += words * 2
        }
    }

    func addWMFObject(_ o: Obj) {
        if let i = wmfObjects.firstIndex(where: { $0 == nil }) { wmfObjects[i] = o } else { wmfObjects.append(o) }
    }

    /// RECT in WMF parameter order (bottom, right, top, left).
    func wrect(_ r: Reader, _ p: Int) -> CGRect {
        let b = CGFloat(r.i16(p)), rr = CGFloat(r.i16(p + 2)), t = CGFloat(r.i16(p + 4)), l = CGFloat(r.i16(p + 6))
        return CGRect(x: min(l, rr), y: min(t, b), width: abs(rr - l), height: abs(b - t))
    }
    func wpt(_ r: Reader, _ p: Int) -> CGPoint { CGPoint(x: CGFloat(r.i16(p + 2)), y: CGFloat(r.i16(p))) }   // y, x

    func wmfRecord(_ fn: UInt16, _ r: Reader, _ p: Int, _ len: Int) {
        switch fn {
        case 0x020B: dc.winOrg = wpt(r, p)
        case 0x020C: dc.winExt = CGSize(width: CGFloat(r.i16(p + 2)), height: CGFloat(r.i16(p)))
        case 0x020F: let d = wpt(r, p); dc.winOrg.x += d.x; dc.winOrg.y += d.y
        case 0x020D, 0x020E, 0x0211, 0x0103: break   // viewport and map mode: the window maps onto the frame
        case 0x0106: dc.evenOdd = r.u16(p) != 2
        case 0x0102: dc.bkOpaque = r.u16(p) == 2
        case 0x0209: dc.textColor = r.color(p)
        case 0x0201: dc.bkColor = r.color(p)
        case 0x012E: dc.textAlign = UInt32(r.u16(p))
        case 0x001E: stack.append(dc)
        case 0x0127:
            let n = Int(r.i16(p))
            let target = n < 0 ? stack.count + n : n - 1
            if target >= 0, target < stack.count { dc = stack[target]; stack.removeSubrange(target...) }
        case 0x02FA: addWMFObject(.pen(Pen(color: r.color(p + 6), width: CGFloat(r.i16(p + 2)), style: UInt32(r.u16(p)))))
        case 0x02FC:
            let style = r.u16(p)
            addWMFObject(.brush(Brush(color: style == 1 ? nil : r.color(p + 2))))
        case 0x02FB: addWMFObject(.font(Player.font(r, at: p, wide: false)))
        case 0x0142, 0x01F9, 0x06FF, 0x00F7: addWMFObject(.other)   // pattern brushes, regions, palettes
        case 0x012D:
            let i = Int(r.u16(p))
            if i < wmfObjects.count { select(wmfObjects[i]) }
        case 0x01F0:
            let i = Int(r.u16(p))
            if i < wmfObjects.count { wmfObjects[i] = nil }
        case 0x0324, 0x0325:   // POLYGON, POLYLINE
            let n = Int(r.i16(p))
            render(poly(points16(r, p + 2, n), closed: fn == 0x0324), fill: fn == 0x0324)
        case 0x0538:   // POLYPOLYGON
            let polys = Int(r.u16(p))
            var q = p + 2 + polys * 2
            let m = CGMutablePath()
            for i in 0..<polys {
                let c = Int(r.u16(p + 2 + i * 2))
                m.addPath(poly(points16(r, q, c), closed: true))
                q += c * 4
            }
            render(m, fill: true)
        case 0x0214: moveTo(wpt(r, p))
        case 0x0213: lineTo(wpt(r, p))
        case 0x0418: render(ellipse(wrect(r, p)), fill: true)
        case 0x041B: render(rect(wrect(r, p)), fill: true)
        case 0x061C: render(roundRect(wrect(r, p + 4), CGSize(width: CGFloat(r.i16(p + 2)), height: CGFloat(r.i16(p)))), fill: true)
        case 0x0817, 0x081A, 0x0830:   // ARC, PIE, CHORD
            let end = wpt(r, p), start = wpt(r, p + 4), box = wrect(r, p + 8)
            let kind = fn == 0x0817 ? 0 : (fn == 0x081A ? 2 : 1)
            render(arc(box, start, end, kind: kind), fill: kind != 0)
        case 0x0416: clip(rect(wrect(r, p)), mode: 1)   // INTERSECTCLIPRECT
        case 0x0521:   // TEXTOUT
            let n = Int(r.i16(p))
            guard n > 0 else { return }
            let s = Metafile.decodeANSI((0..<n).map { r.u8(p + 2 + $0) }, charset: dc.font.charset, dx: nil).0
            let sp = p + 2 + ((n + 1) & ~1)
            text(s, at: dc.textAlign & 1 != 0 ? dc.cur : wpt(r, sp))
        case 0x0A32:   // EXTTEXTOUT
            let at = wpt(r, p), n = Int(r.i16(p + 4)), opts = r.u16(p + 6)
            guard n > 0 else { return }
            var sp = p + 8
            if opts & 0x6 != 0 {
                if opts & 0x2 != 0 {
                    let saved = dc.brush; dc.brush = Brush(color: dc.bkColor)
                    let rr = CGRect(x: CGFloat(r.i16(sp)), y: CGFloat(r.i16(sp + 2)), width: CGFloat(r.i16(sp + 4) - r.i16(sp)), height: CGFloat(r.i16(sp + 6) - r.i16(sp + 2)))
                    if rr.width > 0, rr.height > 0 { render(rect(rr), fill: true, stroke: false) }
                    dc.brush = saved
                }
                sp += 8
            }
            let raw = (0..<n).map { r.u8(sp + $0) }
            let dxAt = sp + ((n + 1) & ~1)
            let rawDx: [CGFloat]? = dxAt + n * 2 <= p + len ? (0..<n).map { CGFloat(r.i16(dxAt + $0 * 2)) } : nil
            let (s, dx) = Metafile.decodeANSI(raw, charset: dc.font.charset, dx: rawDx)
            text(s, at: dc.textAlign & 1 != 0 ? dc.cur : at, dx: dx)
        case 0x0F43:   // STRETCHDIB
            let rop = r.u32(p)
            let src = CGRect(x: CGFloat(r.i16(p + 12)), y: CGFloat(r.i16(p + 10)), width: CGFloat(r.i16(p + 8)), height: CGFloat(r.i16(p + 6)))
            let dest = CGRect(x: CGFloat(r.i16(p + 20)), y: CGFloat(r.i16(p + 18)), width: CGFloat(r.i16(p + 16)), height: CGFloat(r.i16(p + 14)))
            let bmi = p + 22
            dib(r, bmi: bmi, bmiLen: len - 22, bits: -1, bitsLen: 0, src: flipSrc(r, bmi, src), dest: dest, rop: rop)
        case 0x0B41, 0x0940:   // DIBSTRETCHBLT, DIBBITBLT
            let rop = r.u32(p)
            let words = (len + 6) / 2
            let hasBitmap = words != 3 + Int(fn >> 8)
            let stretch = fn == 0x0B41
            var q = p + 4
            var srcSize: CGSize?
            if stretch { srcSize = CGSize(width: CGFloat(r.i16(q + 2)), height: CGFloat(r.i16(q))); q += 4 }
            let srcOrigin = CGPoint(x: CGFloat(r.i16(q + 2)), y: CGFloat(r.i16(q))); q += 4
            if !hasBitmap { q += 2 }
            let dest = CGRect(x: CGFloat(r.i16(q + 6)), y: CGFloat(r.i16(q + 4)), width: CGFloat(r.i16(q + 2)), height: CGFloat(r.i16(q)))
            q += 8
            if hasBitmap {
                let src = CGRect(origin: srcOrigin, size: srcSize ?? dest.size)
                dib(r, bmi: q, bmiLen: p + len - q, bits: -1, bitsLen: 0, src: flipSrc(r, q, src), dest: dest, rop: rop)
            } else { patBlt(dest, rop: rop) }
        default: break
        }
    }
}

// MARK: - DIB decoding and fonts

extension Metafile {
    /// Windows font families mapped to close Mac ones (others are used as is when installed).
    static func macFamily(_ face: String, charset: UInt8 = 1) -> String {
        let f = face.trimmingCharacters(in: .whitespaces)
        let installed = NSFontManager.shared.availableFontFamilies.contains(f)
        if !installed {
            switch charset {   // CJK and other scripts: a Mac font that has them
            case 128: return "Hiragino Sans"
            case 129: return "Apple SD Gothic Neo"
            case 134: return "PingFang SC"
            case 136: return "PingFang TC"
            case 2: return "Symbol"
            default: break
            }
        }
        switch f.lowercased() {
        case "arial", "helv", "ms sans serif", "microsoft sans serif", "tahoma", "segoe ui", "calibri", "verdana":
            return NSFontManager.shared.availableFontFamilies.contains(f) ? f : "Helvetica"
        case "times new roman", "tms rmn", "ms serif", "cambria", "times":
            return NSFontManager.shared.availableFontFamilies.contains(f) ? f : "Times"
        case "courier new", "courier", "consolas", "lucida console": return "Courier"
        case "symbol", "wingdings": return "Symbol"
        default: return NSFontManager.shared.availableFontFamilies.contains(f) ? f : "Helvetica"
        }
    }

    /// A device-independent bitmap: BITMAPINFOHEADER (or the old CORE header) + palette + bits (`bits` < 0: right
    /// after the palette). Uncompressed 1/4/8/16/24/32-bit DIBs are decoded here; JPEG/PNG/RLE ones go to ImageIO.
    fileprivate static func decodeDIB(_ r: Reader, bmi: Int, bmiLen: Int, bits: Int, bitsLen: Int, forceAlpha: Bool) -> CGImage? {
        let hs = Int(r.u32(bmi))
        guard hs >= 12, bmiLen >= hs else { return nil }
        let core = hs == 12
        let w = core ? Int(r.u16(bmi + 4)) : Int(r.i32(bmi + 4))
        let hRaw = core ? Int(r.i16(bmi + 6)) : Int(r.i32(bmi + 8))
        let bpp = Int(r.u16(bmi + (core ? 10 : 14)))
        let comp = core ? 0 : r.u32(bmi + 16)
        var used = core ? 0 : Int(r.u32(bmi + 32))
        let h = abs(hRaw), topDown = hRaw < 0
        guard w > 0, h > 0, w < 32768, h < 32768 else { return nil }
        if bpp <= 8 { used = used == 0 ? 1 << bpp : min(used, 256) }
        let palEntry = core ? 3 : 4
        var masks: (UInt32, UInt32, UInt32, UInt32)?
        var palStart = bmi + hs
        if comp == 3 || comp == 6 {   // BI_BITFIELDS
            if hs >= 52 { masks = (r.u32(bmi + 40), r.u32(bmi + 44), r.u32(bmi + 48), hs >= 56 ? r.u32(bmi + 52) : 0) }
            else { masks = (r.u32(palStart), r.u32(palStart + 4), r.u32(palStart + 8), 0); palStart += 12 }
        }
        let palette: [(UInt8, UInt8, UInt8)] = bpp <= 8 ? (0..<used).map {
            let q = palStart + $0 * palEntry; return (r.u8(q + 2), r.u8(q + 1), r.u8(q))
        } : []
        let dataStart = bits >= 0 ? bits : palStart + (bpp <= 8 ? used * palEntry : 0)
        let dataLen = bits >= 0 ? bitsLen : r.count - dataStart

        if comp == 4 || comp == 5 || comp == 1 || comp == 2 {   // JPEG, PNG, RLE8, RLE4
            guard let raw = r.slice(dataStart, max(0, min(dataLen, r.count - dataStart))) else { return nil }
            var data = Data(raw)
            if comp == 1 || comp == 2 {   // wrap as a BMP file for ImageIO
                guard let info = r.slice(bmi, palStart - bmi + (bpp <= 8 ? used * palEntry : 0)) else { return nil }
                var file = Data([0x42, 0x4D])
                let total = 14 + info.count + data.count
                for v in [UInt32(total), 0, UInt32(14 + info.count)] { withUnsafeBytes(of: v.littleEndian) { file.append(contentsOf: $0) } }
                file.append(contentsOf: info); file.append(data); data = file
            }
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }

        let rowBytes = ((w * bpp + 31) / 32) * 4
        guard dataStart >= 0, dataStart < r.count else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        var anyAlpha = false
        for y in 0..<h {
            let srcRow = dataStart + (topDown ? y : h - 1 - y) * rowBytes
            for x in 0..<w {
                var R: UInt8 = 0, G: UInt8 = 0, B: UInt8 = 0, A: UInt8 = 255
                switch bpp {
                case 1, 4, 8:
                    let bitOff = x * bpp
                    let byte = r.u8(srcRow + bitOff / 8)
                    let shift = 8 - bpp - (bitOff % 8)
                    let idx = Int((byte >> UInt8(shift)) & UInt8((1 << bpp) - 1))
                    if idx < palette.count { (R, G, B) = palette[idx] }
                case 16:
                    let v = UInt32(r.u16(srcRow + x * 2))
                    if let m = masks {
                        R = channel(v, m.0); G = channel(v, m.1); B = channel(v, m.2)
                    } else {
                        R = UInt8(((v >> 10) & 31) * 255 / 31); G = UInt8(((v >> 5) & 31) * 255 / 31); B = UInt8((v & 31) * 255 / 31)
                    }
                case 24:
                    let q = srcRow + x * 3
                    B = r.u8(q); G = r.u8(q + 1); R = r.u8(q + 2)
                case 32:
                    let v = r.u32(srcRow + x * 4)
                    if let m = masks {
                        R = channel(v, m.0); G = channel(v, m.1); B = channel(v, m.2)
                        A = m.3 != 0 ? channel(v, m.3) : 255
                        if m.3 != 0 && A != 0 { anyAlpha = true }
                    } else {
                        B = UInt8(v & 0xFF); G = UInt8((v >> 8) & 0xFF); R = UInt8((v >> 16) & 0xFF); A = UInt8(v >> 24)
                        if A != 0 { anyAlpha = true }
                    }
                default: return nil
                }
                let o = (y * w + x) * 4
                out[o] = R; out[o + 1] = G; out[o + 2] = B; out[o + 3] = A
            }
        }
        // 32-bit DIBs usually leave the 4th byte at 0: opaque, unless an alpha blend says it carries alpha.
        let useAlpha = bpp == 32 && anyAlpha && (forceAlpha || masks?.3 ?? 0 != 0)
        if bpp == 32 && !useAlpha { for i in stride(from: 3, to: out.count, by: 4) { out[i] = 255 } }
        let info: CGBitmapInfo = useAlpha && masks == nil
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            : CGBitmapInfo(rawValue: useAlpha ? CGImageAlphaInfo.last.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Windows charset (LOGFONT lfCharSet) -> text encoding for 8-bit/DBCS strings.
    static func encoding(charset: UInt8) -> String.Encoding {
        let cp: UInt32
        switch charset {
        case 77: return .macOSRoman
        case 128: cp = 932
        case 129: cp = 949
        case 130: cp = 1361
        case 134: cp = 936
        case 136: cp = 950
        case 161: cp = 1253
        case 162: cp = 1254
        case 163: cp = 1258
        case 177: cp = 1255
        case 178: cp = 1256
        case 186: cp = 1257
        case 204: cp = 1251
        case 222: cp = 874
        case 238: cp = 1250
        case 255: cp = 437
        default: cp = 1252
        }
        let cf = CFStringConvertWindowsCodepageToEncoding(cp)
        return cf == kCFStringEncodingInvalidId ? .windowsCP1252 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    /// Decodes an 8-bit or double-byte string; per-byte advances (`dx`) become per-UTF-16-unit ones.
    static func decodeANSI(_ bytes: [UInt8], charset: UInt8, dx: [CGFloat]?) -> (String, [CGFloat]?) {
        let bytes = Array(bytes.prefix { $0 != 0 })
        if charset == 2 { return (String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) })), dx) }   // mapped when drawn
        let enc = encoding(charset: charset)
        let dbcs = [128, 129, 130, 134, 136].contains(Int(charset))
        guard dbcs else {
            let s = String(data: Data(bytes), encoding: enc) ?? String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
            return (s, dx != nil && s.utf16.count == bytes.count ? dx : nil)
        }
        var out = "", outDx: [CGFloat] = []
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            let lead = b >= 0x81 && b <= 0xFE && !(charset == 128 && b >= 0xA0 && b <= 0xDF)
            let n = lead && i + 1 < bytes.count ? 2 : 1
            let part = String(data: Data(bytes[i..<(i + n)]), encoding: enc) ?? "?"
            out += part
            if let dx {
                let adv = (i..<(i + n)).reduce(CGFloat(0)) { $0 + ($1 < dx.count ? dx[$1] : 0) }
                let units = part.utf16.count
                outDx += [adv] + Array(repeating: 0, count: max(0, units - 1))
            }
            i += n
        }
        return (out, dx == nil ? nil : outDx)
    }

    static func isSymbolFace(_ face: String) -> Bool {
        let f = face.lowercased()
        return f == "symbol" || f.hasSuffix(" symbol")
    }

    /// Adobe Symbol encoding -> Unicode (codes 0x20...0xFE, also in the 0xF020... private range).
    static func symbolScalar(_ u: Unicode.Scalar) -> Unicode.Scalar {
        var v = u.value
        if v >= 0xF020 && v <= 0xF0FF { v -= 0xF000 }
        guard v >= 0x20 && v <= 0xFE else { return u }
        let i = Int(v - 0x20)
        let scalars = Array(symbolTable.unicodeScalars)
        return i < scalars.count ? scalars[i] : u
    }

    private static let symbolTable =
        " !∀#∃%&∋()∗+,−./0123456789:;<=>?≅ΑΒΧΔΕΦΓΗΙϑΚΛΜΝΟΠΘΡΣΤΥςΩΞΨΖ[∴]⊥_‾αβχδεφγηιϕκλμνοπθρστυϖωξψζ{|}∼ " +
        "                                " +    // 0x80...0x9F (unused; 0x7F is the space above)
        "€ϒ′≤⁄∞ƒ♣♦♥♠↔←↑→↓°±″≥×∝∂•÷≠≡≈…⏐⎯↵ℵℑℜ℘⊗⊕∅∩∪⊃⊇⊄⊂⊆∈∉∠∇®©™∏√⋅¬∧∨⇔⇐⇑⇒⇓◊〈®©™∑⎛⎜⎝⎡⎢⎣⎧⎨⎩⎪ 〉∫⌠⎮⌡⎞⎟⎠⎤⎥⎦⎫⎬⎭"

    private static func channel(_ v: UInt32, _ mask: UInt32) -> UInt8 {
        guard mask != 0 else { return 0 }
        let shift = mask.trailingZeroBitCount
        let maxV = mask >> shift
        return UInt8(((v & mask) >> shift) * 255 / maxV)
    }
}
