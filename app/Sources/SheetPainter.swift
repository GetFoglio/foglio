import AppKit

/// Cells of one region, indexed for neighbour lookups (text overflow).
struct CellData {
    var cells: [VCell] = []
    var byKey: [Int64: Int] = [:]
    var occupied = Set<Int64>()

    init() {}
    init(_ cells: [VCell]) {
        self.cells = cells
        byKey.reserveCapacity(cells.count)
        for (i, c) in cells.enumerated() {
            let k = CellData.key(c.row, c.col)
            byKey[k] = i
            if !c.text.isEmpty { occupied.insert(k) }
        }
    }
    static func key(_ r: Int, _ c: Int) -> Int64 { Int64(r) << 16 | Int64(c) }
    func cell(_ r: Int, _ c: Int) -> VCell? { byKey[CellData.key(r, c)].map { cells[$0] } }
}

/// Draws cells (fills, grid lines, text, borders, merges). Shared by the grid and printing.
final class SheetPainter {
    /// Excel font points -> screen points.
    var fontScale: CGFloat = 12.0 / 11.0
    var printing = false
    private var attrCache: [Int: [NSAttributedString.Key: Any]] = [:]
    private var fontCache: [Int: NSFont] = [:]

    func resetColors() { attrCache.removeAll() }

    static func rgb(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func luminance(_ v: UInt32) -> CGFloat {
        let r = CGFloat((v >> 16) & 0xFF) / 255, g = CGFloat((v >> 8) & 0xFF) / 255, b = CGFloat(v & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private var textColor: NSColor { printing ? .black : .textColor }
    var background: NSColor { printing ? .white : .textBackgroundColor }

    func font(size: Int, bold: Bool, italic: Bool) -> NSFont {
        let key = size << 2 | (bold ? 1 : 0) | (italic ? 2 : 0)
        if let f = fontCache[key] { return f }
        var f = NSFont.monospacedDigitSystemFont(ofSize: max(4, CGFloat(size) * fontScale), weight: bold ? .semibold : .regular)
        if italic { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
        fontCache[key] = f
        return f
    }

    func attrs(_ c: VCell) -> [NSAttributedString.Key: Any] {
        let size = Int(c.fontSize == 0 ? 11 : c.fontSize)
        var k = size
        k = k << 1 | (c.bold ? 1 : 0)
        k = k << 1 | (c.italic ? 1 : 0)
        k = k << 1 | (c.underline ? 1 : 0)
        k = k << 1 | (c.strike ? 1 : 0)
        k = k << 1 | (c.kind == 3 ? 1 : 0)
        k = k << 1 | (c.wrap ? 1 : 0)
        // Automatic text colour on a filled cell follows the fill's brightness (readable in dark mode too).
        let onFill: Int = c.fg != VCell.noColor || c.bg == VCell.noColor ? 0 : (SheetPainter.luminance(c.bg) > 0.5 ? 1 : 2)
        k = k << 2 | onFill
        k = k << 25 | Int(c.fg == VCell.noColor ? 0x1FFFFFF : c.fg)
        if let a = attrCache[k] { return a }
        let auto: NSColor = onFill == 1 ? .black : (onFill == 2 ? .white : textColor)
        let color: NSColor = c.fg == VCell.noColor ? (c.kind == 3 ? .systemRed : auto) : SheetPainter.rgb(c.fg)
        var a: [NSAttributedString.Key: Any] = [.font: font(size: size, bold: c.bold, italic: c.italic), .foregroundColor: color]
        if c.underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if c.strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if c.wrap {
            let p = NSMutableParagraphStyle()
            p.lineBreakMode = .byWordWrapping
            p.alignment = [.natural, .left, .center, .right][Int(min(c.align, 3))]
            a[.paragraphStyle] = p
        }
        attrCache[k] = a
        return a
    }

    /// Paints `rows` x `cols`. `rect` maps a cell to its rectangle in the current coordinate space.
    func paint(rows: ClosedRange<Int>, cols: ClosedRange<Int>, data: CellData, merges: [GridRange],
               showGrid: Bool, hair: CGFloat, clip: CGRect, gridColor: NSColor,
               rect: (Int, Int) -> CGRect, colWidth: (Int) -> CGFloat, rowHeight: (Int) -> CGFloat) {
        let bg = background
        let visible = GridRange(r0: rows.lowerBound, c0: cols.lowerBound, r1: rows.upperBound, c1: cols.upperBound)
        let visibleMerges = merges.filter { $0.intersects(visible) }

        // 1. fills
        for c in data.cells where c.bg != VCell.noColor && rows.contains(c.row) && cols.contains(c.col) {
            SheetPainter.rgb(c.bg).setFill()
            rect(c.row, c.col).fill()
        }

        // 2. grid lines
        if showGrid {
            gridColor.setFill()
            var lines: [CGRect] = []
            lines.reserveCapacity(rows.count + cols.count)
            for r in rows where rowHeight(r) > 0 {
                let y = rect(r, cols.lowerBound).maxY - hair
                lines.append(CGRect(x: clip.minX, y: y, width: clip.width, height: hair))
            }
            for c in cols where colWidth(c) > 0 {
                let x = rect(rows.lowerBound, c).maxX - hair
                lines.append(CGRect(x: x, y: clip.minY, width: hair, height: clip.height))
            }
            for l in lines { l.fill() }
        }

        // 3. merged areas: cover inner grid lines with the anchor's fill
        for m in visibleMerges {
            let r = rect(m.r0, m.c0).union(rect(m.r1, m.c1))
            let fill = data.cell(m.r0, m.c0).map { $0.bg } ?? VCell.noColor
            (fill == VCell.noColor ? bg : SheetPainter.rgb(fill)).setFill()
            CGRect(x: r.minX, y: r.minY, width: r.width - hair, height: r.height - hair).fill()
        }

        // 4. text
        for c in data.cells where !c.text.isEmpty && rows.contains(c.row) && cols.contains(c.col) {
            if visibleMerges.contains(where: { $0.contains(CellRef(row: c.row, col: c.col)) && !($0.r0 == c.row && $0.c0 == c.col) }) {
                continue
            }
            let merge = visibleMerges.first { $0.r0 == c.row && $0.c0 == c.col }
            let cellRect = merge.map { rect($0.r0, $0.c0).union(rect($0.r1, $0.c1)) } ?? rect(c.row, c.col)
            guard cellRect.width > 0, cellRect.height > 0 else { continue }
            drawText(c, in: cellRect, data: data, cols: cols, rect: rect, hair: hair, merged: merge != nil)
        }
        // Merge anchors scrolled out of view still own the visible part of the merge.
        for m in visibleMerges where !(rows.contains(m.r0) && cols.contains(m.c0)) {
            if let c = data.cell(m.r0, m.c0), !c.text.isEmpty {
                drawText(c, in: rect(m.r0, m.c0).union(rect(m.r1, m.c1)), data: data, cols: cols, rect: rect, hair: hair, merged: true)
            }
        }

        // 5. borders
        for c in data.cells where c.borderMask != 0 && rows.contains(c.row) && cols.contains(c.col) {
            let r = rect(c.row, c.col)
            let w: CGFloat = [1, 1, 2, 3, 3][Int(min(c.borderWeight, 4))]
            (c.borderColor == VCell.noColor ? textColor : SheetPainter.rgb(c.borderColor)).setFill()
            let m = c.borderMask
            if m & 1 != 0 { CGRect(x: r.minX - hair, y: r.minY - hair, width: r.width + hair, height: w).fill() }
            if m & 4 != 0 { CGRect(x: r.minX - hair, y: r.maxY - w + (w > 1 ? hair : 0) - hair, width: r.width + hair, height: w).fill() }
            if m & 8 != 0 { CGRect(x: r.minX - hair, y: r.minY - hair, width: w, height: r.height + hair).fill() }
            if m & 2 != 0 { CGRect(x: r.maxX - w + (w > 1 ? hair : 0) - hair, y: r.minY - hair, width: w, height: r.height + hair).fill() }
        }
    }

    private func drawText(_ c: VCell, in rect: CGRect, data: CellData, cols: ClosedRange<Int>,
                          rect cellRect: (Int, Int) -> CGRect, hair: CGFloat, merged: Bool) {
        var text = c.text
        let a = attrs(c)
        let pad: CGFloat = 3
        let effAlign: UInt8 = c.align != 0 ? c.align : (c.kind == 1 ? 3 : (c.kind >= 2 ? 2 : 1))

        if c.wrap {
            let r = rect.insetBy(dx: pad, dy: 1)
            let bounds = (text as NSString).boundingRect(with: CGSize(width: r.width, height: .greatestFiniteMagnitude),
                                                         options: [.usesLineFragmentOrigin], attributes: a)
            var y = r.minY
            switch c.valign {
            case 1: y = r.midY - bounds.height / 2
            case 2: y = r.minY
            default: y = max(r.minY, r.maxY - bounds.height)
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            (text as NSString).draw(with: CGRect(x: r.minX, y: y, width: r.width, height: r.maxY - y),
                                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: a)
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        var size = (text as NSString).size(withAttributes: a)
        var clip = rect
        var needsClip = false
        if size.width > rect.width - 2 * pad {
            if c.kind == 1 && !merged {
                // Numbers never overflow: Excel shows ####.
                let hash = ("#" as NSString).size(withAttributes: a).width
                text = String(repeating: "#", count: max(1, Int((rect.width - 2 * pad) / max(hash, 1))))
                size = (text as NSString).size(withAttributes: a)
            } else if !merged && (effAlign == 1 || effAlign == 3 || effAlign == 2) {
                // Overflow into empty neighbours (to the right for left-aligned text, etc.).
                var lo = c.col, hi = c.col
                var width = rect.width
                let empty = { (col: Int) -> Bool in !data.occupied.contains(CellData.key(c.row, col)) }
                while width < size.width + 2 * pad {
                    var grew = false
                    if effAlign != 3, hi + 1 < Sheet.maxCols, hi + 1 <= cols.upperBound + 8, empty(hi + 1) {
                        hi += 1; width += cellRect(c.row, hi).width; grew = true
                    }
                    if effAlign != 1, width < size.width + 2 * pad, lo - 1 >= 0, lo - 1 >= cols.lowerBound - 8, empty(lo - 1) {
                        lo -= 1; width += cellRect(c.row, lo).width; grew = true
                    }
                    if !grew { break }
                }
                if lo != c.col || hi != c.col {
                    clip = cellRect(c.row, lo).union(cellRect(c.row, hi))
                    background.setFill()
                    CGRect(x: clip.minX, y: clip.minY, width: clip.width - hair, height: clip.height - hair).fill()
                    let own = cellRect(c.row, c.col)
                    if c.bg != VCell.noColor { SheetPainter.rgb(c.bg).setFill(); own.fill() }
                }
                needsClip = size.width > clip.width - 2 * pad
            } else {
                needsClip = true
            }
        }
        let x: CGFloat
        switch effAlign {
        case 3: x = (effAlign == 3 && clip != rect ? clip.maxX : rect.maxX) - pad - size.width
        case 2: x = (clip != rect ? clip.midX : rect.midX) - size.width / 2
        default: x = (clip != rect ? clip.minX : rect.minX) + pad
        }
        let y: CGFloat
        switch c.valign {
        case 1: y = rect.midY - size.height / 2
        case 2: y = rect.minY + 1
        default: y = rect.maxY - size.height - 1
        }
        if needsClip || size.height > rect.height {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: clip.insetBy(dx: 1, dy: 0)).addClip()
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: a)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: a)
        }
    }
}
