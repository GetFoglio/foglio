#!/usr/bin/env swift
// Generates the Foglio app icon programmatically (CoreGraphics only, no external assets).
//
// Usage:  swift scripts/make_icon.swift
// Output: assets/icon-1024.png   master PNG (1024×1024)
//         assets/Foglio.icns     all iconset sizes (16–1024), built with iconutil
//
// Optional: FOGLIO_ICON_PREVIEW=<dir> also writes every size plus a contact sheet
// (light/dark backgrounds, small sizes magnified) into <dir> for eyeballing.
//
// Design — one idea: a sheet with one selected cell.
//   • macOS icon grid: 1024 canvas, 824 continuous-corner squircle, soft drop shadow
//   • green-teal body gradient (one hue), a white sheet card with a tinted header row,
//     a 3 × 4 grid of hairlines and one cell filled with the body gradient
//   • three colours in total: green-teal (light → deep), white, and a neutral grid grey
// The geometry is laid out on a 64-unit lattice (16 canvas units) so every line lands on
// whole pixels from 64 px up; 32 px and 16 px use hand-tuned pixel layouts of the same design.

import AppKit
import CoreGraphics
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
let accentTop = color(0x2FD382), accentBottom = color(0x0B8C62)   // body + selected cell
let headerTint = color(0x1DB57A, 0.20)                              // accent at low alpha
let gridLine = color(0xD3DFD9), gridLineSmall = color(0xBACBC3), gridLine16 = color(0xCAD8D1)
let sheetTop = color(0xFFFFFF), sheetBottom = color(0xF0F4F2)
let shadowTint = color(0x00402C)

// MARK: - Geometry helpers

/// Apple-style continuous-corner rounded square (the "squircle" used by iOS/macOS icons).
/// Built from one corner (the widely reproduced UIBezierPath continuous-corner curve, which
/// extends 1.5287 × radius along each edge) rotated four times about the centre.
func squirclePath(_ r: CGRect, radius: CGFloat) -> CGPath {
    precondition(r.width == r.height, "squircle expects a square")
    let h = r.width / 2, k = radius
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

/// Shadows are specified in base (device, y-up) space, so scale them to the output size and
/// flip the offset to keep them falling downward.
func setShadow(_ ctx: CGContext, px: Int, dy: CGFloat, blur: CGFloat, _ c: CGColor) {
    let s = CGFloat(px) / 1024
    ctx.setShadow(offset: CGSize(width: 0, height: -dy * s), blur: blur * s, color: c)
}

// MARK: - Layout

/// The sheet layout in canvas units (1024 canvas). Columns/rows are the cell sizes; the
/// first row is the header. Lines sit on the boundaries between cells.
struct Layout {
    var sheet: CGRect
    var radius: CGFloat
    var cols: [CGFloat]
    var rows: [CGFloat]
    var line: CGFloat
    var lineColor: CGColor
    var selected: (col: Int, row: Int)
    var selectedRadius: CGFloat
    var selectedOutset: CGFloat
    var shadow: Bool
}

func layout(px: Int) -> Layout {
    let u = 1024 / CGFloat(px)        // canvas units per output pixel
    switch px {
    case ...16:
        // 16 px: 10 × 10 sheet at (3,3); rows header 2 | 3 | 3, columns 2 | 4 | 2 (+1 px lines)
        return Layout(sheet: CGRect(x: 3 * u, y: 3 * u, width: 10 * u, height: 10 * u), radius: 1.2 * u,
                      cols: [2 * u, 4 * u, 2 * u], rows: [2 * u, 3 * u, 3 * u], line: u,
                      lineColor: gridLine16, selected: (1, 1), selectedRadius: 0, selectedOutset: 0, shadow: false)
    case ...32:
        // 32 px: 18 × 18 sheet at (7,7); header 3 | 4 | 4 | 4 rows, 5 | 6 | 5 columns (+1 px lines)
        return Layout(sheet: CGRect(x: 7 * u, y: 7 * u, width: 18 * u, height: 18 * u), radius: 1.8 * u,
                      cols: [5 * u, 6 * u, 5 * u], rows: [3 * u, 4 * u, 4 * u, 4 * u], line: u,
                      lineColor: gridLineSmall, selected: (1, 2), selectedRadius: 1.2 * u, selectedOutset: u, shadow: true)
    default:
        // 576 × 576 sheet: 3 columns of 192, 4 rows of 144 (header + 3) — all multiples of 16.
        let lw: CGFloat = px >= 512 ? 10 : px >= 256 ? 12 : 16   // 64 px: 1 px, 128 px: 2 px, 256 px: 3 px
        return Layout(sheet: CGRect(x: 224, y: 224, width: 576, height: 576), radius: 64,
                      cols: [192, 192, 192], rows: [144, 144, 144, 144], line: lw,
                      lineColor: px <= 128 ? gridLineSmall : gridLine, selected: (1, 2),
                      selectedRadius: 22, selectedOutset: 8, shadow: true)
    }
}

// MARK: - Drawing

/// Draws the icon into `ctx`, whose user space is a 1024×1024 canvas with a top-left origin.
func drawIcon(_ ctx: CGContext, px: Int) {
    let small = px <= 32
    let u = 1024 / CGFloat(px)
    func snap(_ v: CGFloat) -> CGFloat { (v / u).rounded() * u }     // to whole output pixels

    // ── Body (824 squircle centred on the 1024 grid) ────────────────────────────────────────
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = squirclePath(body, radius: 185.4)

    ctx.saveGState()
    setShadow(ctx, px: px, dy: small ? max(10, u * 0.5) : 10, blur: small ? max(22, u) : 22, color(0x000000, 0.28))
    ctx.addPath(bodyPath); ctx.setFillColor(accentBottom); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    linearGradient(ctx, accentTop, accentBottom, from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    let sheen = CGGradient(colorsSpace: sRGB, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 512, y: 100), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 100), endRadius: 560, options: [])
    if !small {
        // hairline rim light along the top edge, fading out towards the bottom (subtle depth)
        ctx.addPath(bodyPath); ctx.setLineWidth(8); ctx.replacePathWithStrokedPath(); ctx.clip()
        linearGradient(ctx, color(0xFFFFFF, 0.35), color(0xFFFFFF, 0), from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 420))
    }
    ctx.restoreGState()

    // ── Sheet ───────────────────────────────────────────────────────────────────────────────
    let L = layout(px: px)
    let sheet = L.sheet
    let sheetPath = small ? roundRect(sheet, L.radius) : squirclePath(sheet, radius: L.radius)

    ctx.saveGState()
    if L.shadow { setShadow(ctx, px: px, dy: small ? u * 0.5 : 16, blur: small ? u : 34, shadowTint.copy(alpha: 0.32)!) }
    ctx.addPath(sheetPath); ctx.setFillColor(sheetTop); ctx.fillPath()
    ctx.restoreGState()

    // cell boundaries
    var xs: [CGFloat] = [sheet.minX], ys: [CGFloat] = [sheet.minY]
    let lineInCell = small            // small sizes: lines take their own pixel between cells
    for w in L.cols { xs.append(xs.last! + w + (lineInCell ? L.line : 0)) }
    for h in L.rows { ys.append(ys.last! + h + (lineInCell ? L.line : 0)) }

    ctx.saveGState()
    ctx.addPath(sheetPath); ctx.clip()
    linearGradient(ctx, sheetTop, sheetBottom, from: CGPoint(x: 0, y: sheet.minY), to: CGPoint(x: 0, y: sheet.maxY))
    ctx.setFillColor(headerTint)
    ctx.fill(CGRect(x: sheet.minX, y: sheet.minY, width: sheet.width, height: L.rows[0]))
    ctx.setFillColor(L.lineColor)
    for i in 1..<L.cols.count {
        let x = lineInCell ? xs[i] - L.line : snap(xs[i] - L.line / 2)
        ctx.fill(CGRect(x: x, y: sheet.minY, width: L.line, height: sheet.height))
    }
    for i in 1..<L.rows.count {
        let y = lineInCell ? ys[i] - L.line : snap(ys[i] - L.line / 2)
        ctx.fill(CGRect(x: sheet.minX, y: y, width: sheet.width, height: L.line))
    }
    ctx.restoreGState()

    // selected cell, filled with the body gradient
    let (c, r) = L.selected
    let cell0 = CGRect(x: xs[c], y: ys[r], width: L.cols[c], height: L.rows[r])
    let o = cell0.insetBy(dx: -L.selectedOutset, dy: -L.selectedOutset)
    let cell = CGRect(x: snap(o.minX), y: snap(o.minY), width: snap(o.maxX) - snap(o.minX), height: snap(o.maxY) - snap(o.minY))
    ctx.saveGState()
    if !small { setShadow(ctx, px: px, dy: 6, blur: 14, shadowTint.copy(alpha: 0.30)!) }
    ctx.addPath(roundRect(cell, L.selectedRadius)); ctx.setFillColor(accentBottom); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(roundRect(cell, L.selectedRadius)); ctx.clip()
    linearGradient(ctx, accentTop, accentBottom, from: CGPoint(x: 0, y: cell.minY - 40), to: CGPoint(x: 0, y: cell.maxY + 40))
    if !small {
        // soft inner rim light on the top edge of the selected cell
        ctx.addPath(roundRect(cell, L.selectedRadius)); ctx.setLineWidth(6); ctx.replacePathWithStrokedPath(); ctx.clip()
        linearGradient(ctx, color(0xFFFFFF, 0.35), color(0xFFFFFF, 0), from: CGPoint(x: 0, y: cell.minY), to: CGPoint(x: 0, y: cell.minY + 24))
    }
    ctx.restoreGState()
}

func render(px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let s = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: s, y: -s)
    drawIcon(ctx, px: px)
    return ctx.makeImage()!
}

func pngData(_ img: CGImage) -> Data { NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])! }

// MARK: - Output

var cache: [Int: CGImage] = [:]
func image(_ px: Int) -> CGImage { if let i = cache[px] { return i }; let i = render(px: px); cache[px] = i; return i }

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Foglio-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try pngData(image(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try pngData(image(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try pngData(image(1024)).write(to: assets.appendingPathComponent("icon-1024.png"))

if let dir = ProcessInfo.processInfo.environment["FOGLIO_ICON_PREVIEW"], !dir.isEmpty {
    let out = URL(fileURLWithPath: dir)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for px in [16, 32, 64, 128, 256, 1024] { try pngData(image(px)).write(to: out.appendingPathComponent("icon-\(px).png")) }
    // Contact sheet: actual sizes 256…16 on light and dark, plus 32 ×4, 16 ×8 and 64 ×2 magnified.
    let W = 900, H = 640
    let sheet = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    sheet.interpolationQuality = .none
    for (row, bg) in [(0, color(0xF2F2F2)), (1, color(0x1E1E1E))] {
        let y0 = H - (row + 1) * 320
        sheet.setFillColor(bg); sheet.fill(CGRect(x: 0, y: y0, width: W, height: 320))
        var x = 16
        for s in [256, 128, 64, 32, 16] { sheet.draw(image(s), in: CGRect(x: x, y: y0 + 32, width: s, height: s)); x += s + 16 }
        sheet.draw(image(32), in: CGRect(x: x, y: y0 + 160, width: 128, height: 128))
        sheet.draw(image(16), in: CGRect(x: x, y: y0 + 16, width: 128, height: 128)); x += 144
        sheet.draw(image(64), in: CGRect(x: x, y: y0 + 160, width: 128, height: 128))
    }
    try pngData(sheet.makeImage()!).write(to: out.appendingPathComponent("contact-sheet.png"))
    // Pixel zoom: 16 ×16, 32 ×8, 64 ×4 (nearest neighbour) on light and dark.
    let zoom = CGContext(data: nil, width: 832, height: 560, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    zoom.interpolationQuality = .none
    for (row, bg) in [(0, color(0xF2F2F2)), (1, color(0x1E1E1E))] {
        let y0 = 560 - (row + 1) * 280
        zoom.setFillColor(bg); zoom.fill(CGRect(x: 0, y: y0, width: 832, height: 280))
        for (i, s) in [16, 32, 64].enumerated() {
            zoom.draw(image(s), in: CGRect(x: 16 + i * 272, y: y0 + 12, width: 256, height: 256))
        }
    }
    try pngData(zoom.makeImage()!).write(to: out.appendingPathComponent("small-zoom.png"))
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
