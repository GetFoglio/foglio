#!/usr/bin/env swift
// Generates the Foglio app icon programmatically (CoreGraphics + CoreText, no external assets).
//
// Usage:  swift scripts/make_icon.swift
// Output: assets/icon-1024.png   master PNG (1024×1024)
//         assets/Foglio.icns     all iconset sizes, built with iconutil
//
// Design (macOS Big Sur+ icon grid: 1024 canvas, 824 body centred, drop shadow below):
//   • continuous-corner squircle with a teal gradient and a soft top sheen
//   • a white sheet with a dark-teal header row, a row-number column, a grid,
//     abstract "data" bars and a highlighted selected cell with a fill handle
//   • a coral "Σ" badge in the lower-right corner
// Sizes ≤ 32 px use a simplified, hand-tuned pixel-aligned variant so the grid stays crisp.

import AppKit
import CoreGraphics
import CoreText
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((hex >> 16) & 0xFF) / 255,
                                           CGFloat((hex >> 8) & 0xFF) / 255,
                                           CGFloat(hex & 0xFF) / 255, a])!
}

// Palette
let bgTop = color(0x34D1B2), bgBottom = color(0x0A7266)
let header = color(0x0F6E63), headerMark = color(0xFFFFFF, 0.55)
let rowCol = color(0xE3F3EF), rowMark = color(0x8DB5AD)
let gridLine = color(0xD3E2DE), dataBar = color(0xB3C6C1), dataBarDark = color(0x7FA39B)
let selection = color(0x12A893)
let badgeTop = color(0xFF9566), badgeBottom = color(0xEE4F37)

// MARK: - Geometry helpers

/// Apple-style continuous-corner rounded square (the "squircle" used by iOS/macOS icons).
/// Built from one corner (the widely reproduced UIBezierPath continuous-corner curve, which
/// extends 1.5287 × radius along each edge) rotated four times about the centre.
func squirclePath(_ r: CGRect, radius: CGFloat) -> CGPath {
    precondition(r.width == r.height, "squircle expects a square")
    let h = r.width / 2, k = radius
    // Top-right corner in centre-relative coordinates (y grows downward), from the top edge to
    // the right edge.
    func P(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: h - dx * k, y: -h + dy * k) }
    let p = CGMutablePath()
    for q in 0..<4 {
        let t = CGAffineTransform(translationX: r.midX, y: r.midY).rotated(by: CGFloat(q) * .pi / 2)
        if q == 0 { p.move(to: P(1.52866483, 0), transform: t) } else { p.addLine(to: P(1.52866483, 0), transform: t) }
        p.addCurve(to: P(0.66993427, 0.06549600), control1: P(1.08849323, 0), control2: P(0.86840689, 0.02221359), transform: t)
        p.addLine(to: P(0.63149399, 0.07491100), transform: t)
        p.addCurve(to: P(0.07491100, 0.63149399), control1: P(0.37282392, 0.16905899), control2: P(0.16905899, 0.37282392), transform: t)
        p.addLine(to: P(0.06549600, 0.66993427), transform: t)
        p.addCurve(to: P(0, 1.52866483), control1: P(0.02221359, 0.86840689), control2: P(0, 1.08849323), transform: t)
    }
    p.closeSubpath()
    return p
}

func roundRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
}

func linearGradient(_ ctx: CGContext, _ c0: CGColor, _ c1: CGColor, from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: sRGB, colors: [c0, c1] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// MARK: - Drawing

/// Draws the icon into `ctx`, whose user space is a 1024×1024 canvas with a top-left origin.
/// `px` is the final pixel size (used for level of detail and pixel snapping).
func drawIcon(_ ctx: CGContext, px: Int) {
    let small = px <= 32
    let u = 1024 / CGFloat(px)                       // canvas units per output pixel

    // ── Body (824 squircle centred on the 1024 grid) ────────────────────────────────────────
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = squirclePath(body, radius: 185.4)

    ctx.saveGState()
    if !small {
        ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.30))
    } else {
        ctx.setShadow(offset: CGSize(width: 0, height: u * 0.5), blur: u, color: color(0x000000, 0.25))
    }
    ctx.addPath(bodyPath); ctx.setFillColor(bgBottom); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    linearGradient(ctx, bgTop, bgBottom, from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    // soft sheen in the upper half
    let sheen = CGGradient(colorsSpace: sRGB, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 512, y: 60), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 60), endRadius: 620, options: [])
    ctx.restoreGState()

    // inner hairline for definition on light backgrounds
    if !small {
        ctx.saveGState()
        ctx.addPath(bodyPath); ctx.clip()
        ctx.addPath(bodyPath); ctx.setStrokeColor(color(0xFFFFFF, 0.18)); ctx.setLineWidth(6); ctx.strokePath()
        ctx.restoreGState()
    }

    // ── Sheet ───────────────────────────────────────────────────────────────────────────────
    // Small sizes use a hand-tuned pixel layout (16 px: 10×10 sheet; 32 px: 18×18 sheet).
    let sp: CGFloat = px <= 16 ? 1 : 2              // "small pixel" scale: 1 at 16 px, 2 at 32 px
    let sheet = small ? CGRect(x: (px <= 16 ? 3 : 7) * u, y: (px <= 16 ? 3 : 7) * u,
                               width: (px <= 16 ? 10 : 18) * u, height: (px <= 16 ? 10 : 18) * u)
                      : CGRect(x: 214, y: 222, width: 596, height: 590)
    let sheetRadius: CGFloat = small ? u * 0.9 * sp : 34
    let sheetPath = roundRect(sheet, sheetRadius)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: small ? u * 0.4 : 14), blur: small ? u : 30, color: color(0x003A33, 0.35))
    ctx.addPath(sheetPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(sheetPath); ctx.clip()
    linearGradient(ctx, color(0xFFFFFF), color(0xF1F6F5), from: CGPoint(x: 0, y: sheet.minY), to: CGPoint(x: 0, y: sheet.maxY))

    if small {
        // Simplified: header band + 2×3 grid with 1-px lines and one coral cell.
        // 16 px: header 2, rows 2|1|2|1|2, columns 5|1|4.   32 px: header 4, rows 4|1|4|1|4, columns 9|1|8.
        let headerH = 2 * sp * u, rowH = 2 * sp * u
        ctx.setFillColor(header)
        ctx.fill(CGRect(x: sheet.minX, y: sheet.minY, width: sheet.width, height: headerH))
        let colLineX = sheet.minX + (px <= 16 ? 5 : 9) * u
        let row1 = sheet.minY + headerH, line1 = row1 + rowH, row2 = line1 + u, line2 = row2 + rowH
        ctx.setFillColor(badgeBottom)
        ctx.fill(CGRect(x: colLineX + u, y: row2, width: sheet.maxX - colLineX - u, height: rowH))
        ctx.setFillColor(color(0xB0C8C2))
        ctx.fill(CGRect(x: colLineX, y: row1, width: u, height: sheet.maxY - row1))
        ctx.fill(CGRect(x: sheet.minX, y: line1, width: sheet.width, height: u))
        ctx.fill(CGRect(x: sheet.minX, y: line2, width: sheet.width, height: u))
        ctx.restoreGState()
        return
    }

    // Full detail
    let headerH: CGFloat = 104
    let rowColW: CGFloat = 78
    let cols = 3, rows = 5
    let gridTop = sheet.minY + headerH
    let gridLeft = sheet.minX + rowColW
    let cw = (sheet.maxX - gridLeft) / CGFloat(cols)
    let rh = (sheet.maxY - gridTop) / CGFloat(rows)

    // header row + subtle bottom shade
    ctx.setFillColor(header)
    ctx.fill(CGRect(x: sheet.minX, y: sheet.minY, width: sheet.width, height: headerH))
    linearGradient(ctx, color(0xFFFFFF, 0.10), color(0xFFFFFF, 0), from: CGPoint(x: 0, y: sheet.minY), to: CGPoint(x: 0, y: sheet.minY + headerH))
    ctx.setFillColor(header)

    // row-number column
    ctx.setFillColor(rowCol)
    ctx.fill(CGRect(x: sheet.minX, y: gridTop, width: rowColW, height: sheet.maxY - gridTop))

    // column letters as pills in the header
    ctx.setFillColor(headerMark)
    for c in 0..<cols {
        let cx = gridLeft + cw * (CGFloat(c) + 0.5)
        ctx.addPath(roundRect(CGRect(x: cx - 22, y: sheet.minY + headerH / 2 - 11, width: 44, height: 22), 11))
    }
    ctx.fillPath()
    // row-number pills
    ctx.setFillColor(rowMark)
    for r in 0..<rows {
        let cy = gridTop + rh * (CGFloat(r) + 0.5)
        ctx.addPath(roundRect(CGRect(x: sheet.minX + rowColW / 2 - 13, y: cy - 10, width: 26, height: 20), 10))
    }
    ctx.fillPath()

    // data bars (abstract numbers, right-aligned like a real sheet)
    let widths: [[CGFloat]] = [[0.62, 0.40, 0.52],
                               [0.48, 0.70, 0.34],
                               [0.70, 0.30, 0.58],
                               [0.36, 0.56, 0.44],
                               [0.54, 0.46, 0.66]]
    for r in 0..<rows {
        for c in 0..<cols {
            if r == 1 && c == 1 { continue }           // selected cell drawn separately
            let w = (cw - 52) * widths[r][c]
            let x = gridLeft + cw * CGFloat(c + 1) - 26 - w
            let y = gridTop + rh * (CGFloat(r) + 0.5) - 10
            ctx.setFillColor(r == rows - 1 ? dataBarDark : dataBar)
            ctx.addPath(roundRect(CGRect(x: x, y: y, width: w, height: 20), 10))
            ctx.fillPath()
        }
    }

    // grid lines
    let lw = max(4, u * 0.8)                       // keep lines visible at 64–128 px
    ctx.setFillColor(px <= 128 ? color(0xC4D6D2) : gridLine)
    for c in 0...cols {
        let x = gridLeft + cw * CGFloat(c) - lw / 2
        ctx.fill(CGRect(x: x, y: gridTop, width: lw, height: sheet.maxY - gridTop))
    }
    for r in 1..<rows {
        let y = gridTop + rh * CGFloat(r) - lw / 2
        ctx.fill(CGRect(x: sheet.minX, y: y, width: sheet.width, height: lw))
    }
    // total row separator (double line feel)
    ctx.setFillColor(color(0x9FBDB6))
    ctx.fill(CGRect(x: gridLeft, y: gridTop + rh * CGFloat(rows - 1) - 3, width: sheet.maxX - gridLeft, height: 6))
    ctx.restoreGState()

    // selected cell: tinted fill, bar, border and fill handle
    let sel = CGRect(x: gridLeft + cw, y: gridTop + rh, width: cw, height: rh)
    ctx.setFillColor(selection.copy(alpha: 0.12)!)
    ctx.fill(sel)
    ctx.setFillColor(selection)
    let selBarW = (cw - 52) * 0.62
    ctx.addPath(roundRect(CGRect(x: sel.maxX - 26 - selBarW, y: sel.midY - 10, width: selBarW, height: 20), 10))
    ctx.fillPath()
    ctx.addPath(roundRect(sel.insetBy(dx: 1, dy: 1), 6))
    ctx.setStrokeColor(selection); ctx.setLineWidth(10); ctx.strokePath()
    let handle = CGRect(x: sel.maxX - 15, y: sel.maxY - 15, width: 30, height: 30)
    ctx.setFillColor(color(0xFFFFFF)); ctx.fill(handle.insetBy(dx: -6, dy: -6))
    ctx.setFillColor(selection); ctx.fill(handle)

    drawBadge(ctx, center: CGPoint(x: 792, y: 790), radius: 118, small: false, u: u)
}

func drawBadge(_ ctx: CGContext, center: CGPoint, radius: CGFloat, small: Bool, u: CGFloat) {
    let r = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    // white ring + shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: small ? u * 0.3 : 10), blur: small ? u * 0.8 : 24, color: color(0x3A0F00, 0.35))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: r.insetBy(dx: small ? -u * 0.8 : -12, dy: small ? -u * 0.8 : -12))
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: r); ctx.clip()
    linearGradient(ctx, badgeTop, badgeBottom, from: CGPoint(x: r.midX, y: r.minY), to: CGPoint(x: r.midX, y: r.maxY))
    ctx.restoreGState()

    // Σ glyph (SF Pro Rounded Heavy), drawn unflipped around the centre.
    var font = NSFont.systemFont(ofSize: radius * (small ? 1.5 : 1.28), weight: small ? .black : .heavy)
    if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: font.pointSize) { font = f }
    let attr = NSAttributedString(string: "Σ", attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(attr)
    let ib = CTLineGetImageBounds(line, ctx)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = CGPoint(x: -ib.midX, y: -ib.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func render(px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let s = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: s, y: -s)
    drawIcon(ctx, px: px)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Output

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Foglio-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

var cache: [Int: Data] = [:]
func png(_ px: Int) -> Data { if let d = cache[px] { return d }; let d = render(px: px); cache[px] = d; return d }

for base in [16, 32, 128, 256, 512] {
    try png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(1024).write(to: assets.appendingPathComponent("icon-1024.png"))

// Optional previews of the small sizes (for eyeballing): FOGLIO_ICON_PREVIEW=1
if ProcessInfo.processInfo.environment["FOGLIO_ICON_PREVIEW"] != nil {
    for px in [16, 32, 64, 128] { try png(px).write(to: assets.appendingPathComponent("preview-\(px).png")) }
}

let icns = assets.appendingPathComponent("Foglio.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard p.terminationStatus == 0 else { fputs("iconutil failed\n", stderr); exit(1) }
print("✓ \(assets.appendingPathComponent("icon-1024.png").path)")
print("✓ \(icns.path)")
