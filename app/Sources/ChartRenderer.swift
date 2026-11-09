import AppKit

/// Draws a chart with CoreGraphics, in the look of Excel's default chart style.
/// Works in the current NSGraphicsContext, which must be flipped (y down), in logical points.
struct ChartRenderer {
    let chart: ChartInfo
    let data: [ChartSeriesData]
    let dark: Bool

    // MARK: Style

    static let palette: [UInt32] = [0x4472C4, 0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47]

    static func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// Excel's accent cycle: after the six accents come darker, then lighter variants.
    static func paletteColor(_ i: Int) -> NSColor {
        let base = color(palette[i % palette.count])
        switch (i / palette.count) % 3 {
        case 0: return base
        case 1: return base.blended(withFraction: 0.4, of: .black) ?? base
        default: return base.blended(withFraction: 0.4, of: .white) ?? base
        }
    }

    func seriesColor(_ i: Int) -> NSColor {
        if let hex = data[safe: i]?.color, let v = UInt32(hex, radix: 16) { return ChartRenderer.color(v) }
        return ChartRenderer.paletteColor(i)
    }

    var background: NSColor { dark ? NSColor(srgbRed: 0.15, green: 0.15, blue: 0.16, alpha: 1) : .white }
    var border: NSColor { dark ? NSColor(white: 1, alpha: 0.16) : ChartRenderer.color(0xD9D9D9) }
    var textColor: NSColor { dark ? NSColor(white: 0.78, alpha: 1) : ChartRenderer.color(0x595959) }
    var titleColor: NSColor { dark ? NSColor(white: 0.88, alpha: 1) : ChartRenderer.color(0x595959) }
    var gridColor: NSColor { dark ? NSColor(white: 1, alpha: 0.12) : ChartRenderer.color(0xD9D9D9) }
    var axisColor: NSColor { dark ? NSColor(white: 1, alpha: 0.28) : ChartRenderer.color(0xBFBFBF) }
    /// Separator between pie slices and around markers.
    var separator: NSColor { background }

    private var labelFont: NSFont { .systemFont(ofSize: 9) }
    private var legendFont: NSFont { .systemFont(ofSize: 9) }
    private var titleFont: NSFont { .systemFont(ofSize: 14) }
    private var axisTitleFont: NSFont { .systemFont(ofSize: 10, weight: .semibold) }

    private func attrs(_ font: NSFont, _ color: NSColor) -> [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: color] }
    private func size(_ s: String, _ font: NSFont) -> CGSize { (s as NSString).size(withAttributes: [.font: font]) }

    // MARK: Entry point

    func draw(in bounds: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Chart area: fill + hairline border.
        background.setFill()
        bounds.fill()
        border.setStroke()
        let b = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        b.lineWidth = 0.75
        b.stroke()
        NSBezierPath(rect: bounds).setClip()

        var r = bounds.insetBy(dx: 10, dy: 8)
        guard r.width > 20, r.height > 20 else { return }

        if let t = chart.title, !t.isEmpty {
            let font = titleFont
            let s = fit(t, font, r.width)
            let sz = size(s, font)
            (s as NSString).draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.minY), withAttributes: attrs(font, titleColor))
            r.origin.y += sz.height + 6; r.size.height -= sz.height + 6
        }
        let points = data.map { $0.values.count }.max() ?? 0
        guard !data.isEmpty, points > 0 else {
            let msg = L("No data")
            let sz = size(msg, labelFont)
            (msg as NSString).draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2), withAttributes: attrs(labelFont, textColor))
            return
        }
        r = drawLegend(in: r)
        guard r.width > 16, r.height > 16 else { return }
        switch chart.kind {
        case .pie, .doughnut: drawPie(in: r)
        case .scatter: drawScatter(in: r)
        default: drawCategoryChart(in: r)
        }
    }

    // MARK: Legend

    private struct LegendItem { let text: String; let color: NSColor }

    private var legendItems: [LegendItem] {
        if chart.kind == .pie || chart.kind == .doughnut {
            let s = data[0]
            let n = s.values.count
            return (0..<n).map { LegendItem(text: s.categories[safe: $0].flatMap { $0.isEmpty ? nil : $0 } ?? "\($0 + 1)", color: ChartRenderer.paletteColor($0)) }
        }
        return data.enumerated().map { LegendItem(text: $1.name, color: seriesColor($0)) }
    }

    private func drawLegendSwatch(_ item: LegendItem, at p: CGPoint, lineH: CGFloat) {
        let midY = p.y + lineH / 2
        if chart.kind.isLine || chart.kind == .scatter {
            let path = NSBezierPath()
            if chart.kind.isLine {
                path.move(to: CGPoint(x: p.x, y: midY)); path.line(to: CGPoint(x: p.x + 14, y: midY))
                path.lineWidth = 2.25
                item.color.setStroke(); path.stroke()
            }
            if chart.kind == .lineMarkers || chart.kind == .scatter {
                marker(at: CGPoint(x: p.x + 7, y: midY), color: item.color)
            }
        } else {
            item.color.setFill()
            CGRect(x: p.x + 3, y: midY - 3.5, width: 7, height: 7).fill()
        }
    }

    /// Draws the legend and returns what is left for the plot.
    private func drawLegend(in rect: CGRect) -> CGRect {
        guard chart.legend != .none else { return rect }
        let items = legendItems
        guard !items.isEmpty else { return rect }
        let font = legendFont
        let lineH = ceil(font.ascender - font.descender + font.leading) + 2
        let swatchW: CGFloat = 14 + 4
        var r = rect
        switch chart.legend {
        case .bottom, .top:
            // Rows of items, centered.
            let maxW = r.width
            var rows: [[(LegendItem, CGFloat, String)]] = [[]]
            var rowW: CGFloat = 0
            for it in items {
                let text = fit(it.text, font, maxW * 0.6)
                let w = swatchW + size(text, font).width
                if rowW > 0 && rowW + 12 + w > maxW { rows.append([]); rowW = 0 }
                rowW += (rowW > 0 ? 12 : 0) + w
                rows[rows.count - 1].append((it, w, text))
            }
            rows = Array(rows.prefix(max(1, Int(r.height * 0.3 / lineH))))
            let h = CGFloat(rows.count) * lineH
            var y = chart.legend == .bottom ? r.maxY - h : r.minY
            for row in rows {
                let total = row.reduce(0) { $0 + $1.1 } + CGFloat(max(0, row.count - 1)) * 12
                var x = r.midX - total / 2
                for (it, w, text) in row {
                    drawLegendSwatch(it, at: CGPoint(x: x, y: y), lineH: lineH)
                    (text as NSString).draw(at: CGPoint(x: x + swatchW, y: y + 1), withAttributes: attrs(font, textColor))
                    x += w + 12
                }
                y += lineH
            }
            if chart.legend == .bottom { r.size.height -= h + 6 } else { r.origin.y += h + 6; r.size.height -= h + 6 }
        case .left, .right:
            let maxText = r.width * 0.32
            let texts = items.map { fit($0.text, font, maxText) }
            let w = (texts.map { size($0, font).width }.max() ?? 0) + swatchW
            let shown = min(items.count, max(1, Int(r.height / lineH)))
            let h = CGFloat(shown) * lineH
            let x = chart.legend == .right ? r.maxX - w : r.minX
            var y = r.midY - h / 2
            for i in 0..<shown {
                drawLegendSwatch(items[i], at: CGPoint(x: x, y: y), lineH: lineH)
                (texts[i] as NSString).draw(at: CGPoint(x: x + swatchW, y: y + 1), withAttributes: attrs(font, textColor))
                y += lineH
            }
            if chart.legend == .right { r.size.width -= w + 10 } else { r.origin.x += w + 10; r.size.width -= w + 10 }
        case .none: break
        }
        return r
    }

    // MARK: Axes

    struct Scale {
        var lo: Double, hi: Double, step: Double
        func pos(_ v: Double, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
            hi == lo ? a : a + CGFloat((v - lo) / (hi - lo)) * (b - a)
        }
        var ticks: [Double] {
            let span = ((hi - lo) / step).rounded()
            guard step > 0, span.isFinite else { return lo.isFinite ? [lo] : [0] }
            let n = Int(min(span, 1_000))
            return (0...max(0, min(n, 200))).map { lo + Double($0) * step }
        }
    }

    /// Excel-like automatic scale: zero included unless the data sit far from it, round steps.
    static func niceScale(min mn: Double, max mx: Double, maxTicks: Int, includeZero: Bool = true) -> Scale {
        var lo = mn, hi = mx
        if !lo.isFinite || !hi.isFinite { lo = 0; hi = 1 }
        // Keep the span finite (hi - lo would overflow to infinity near ±Double.greatestFiniteMagnitude).
        lo = max(lo, -1e300); hi = min(hi, 1e300)
        if includeZero {
            if lo > 0 && (hi - lo) / hi > 1.0 / 6 { lo = 0 }
            if hi < 0 && (lo - hi) / lo > 1.0 / 6 { hi = 0 }
        }
        if hi == lo {
            if hi == 0 { hi = 1 } else if hi > 0 { lo = includeZero ? 0 : hi - abs(hi) * 0.5; hi += abs(hi) * 0.1 } else { hi = includeZero ? 0 : lo + abs(lo) * 0.5 }
        }
        let raw = (hi - lo) / Double(max(1, maxTicks))
        let mag = pow(10, floor(log10(raw)))
        let norm = raw / mag
        let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag
        var a = floor(lo / step) * step, b = ceil(hi / step) * step
        // Like Excel, keep a little headroom above the largest value.
        if b == hi && hi > 0 && mx == hi && !(includeZero && hi == 0) && (hi - lo) / step < Double(maxTicks) { b += step }
        if a == lo && lo < 0 && mn == lo { a -= step }
        guard step.isFinite, step > 0, a.isFinite, b.isFinite else { return Scale(lo: 0, hi: 1, step: 0.2) }
        return Scale(lo: a, hi: b, step: step)
    }

    private func valueRange(stacked: Bool) -> (Double, Double) {
        var lo = Double.infinity, hi = -Double.infinity
        if stacked {
            let n = data.map { $0.values.count }.max() ?? 0
            for i in 0..<n {
                var pos = 0.0, neg = 0.0
                for s in data { if let v = s.values[safe: i] ?? nil { if v >= 0 { pos += v } else { neg += v } } }
                hi = max(hi, pos); lo = min(lo, neg)
            }
        } else {
            for s in data { for v in s.values.compactMap({ $0 }) { lo = min(lo, v); hi = max(hi, v) } }
        }
        if !lo.isFinite { lo = 0; hi = 1 }
        return (lo, hi)
    }

    private var categories: [String] {
        let n = data.map { $0.values.count }.max() ?? 0
        let source = data.first { !$0.categories.isEmpty && $0.categories.contains { !$0.isEmpty } }?.categories ?? []
        return (0..<n).map { source[safe: $0].flatMap { $0.isEmpty ? nil : $0 } ?? (source.isEmpty ? "\($0 + 1)" : "") }
    }

    private var valueFormat: AxisFormat { AxisFormat(code: data.first?.format ?? "general") }

    private func drawText(_ s: String, font: NSFont, color: NSColor, center: CGPoint, angle: CGFloat = 0) {
        let sz = size(s, font)
        guard angle != 0, let ctx = NSGraphicsContext.current?.cgContext else {
            (s as NSString).draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: attrs(font, color))
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        (s as NSString).draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2), withAttributes: attrs(font, color))
        ctx.restoreGState()
    }

    /// Text shortened with an ellipsis to fit `width`.
    private func fit(_ s: String, _ font: NSFont, _ width: CGFloat) -> String {
        if size(s, font).width <= width || s.count < 2 { return s }
        var t = s
        while t.count > 1 && size(t + "…", font).width > width { t.removeLast() }
        return t + "…"
    }

    /// Room taken by the axis titles: (left, bottom) for column charts.
    private func axisTitles(in r: inout CGRect, horizontalValues: Bool) {
        let font = axisTitleFont
        let h = ceil(font.ascender - font.descender) + 4
        // Value axis title: vertical on the left (column/line/area/scatter Y), below for horizontal bars.
        let valueTitle = chart.valueAxisTitle.flatMap { $0.isEmpty ? nil : $0 }
        let catTitle = chart.categoryAxisTitle.flatMap { $0.isEmpty ? nil : $0 }
        let (leftTitle, bottomTitle) = horizontalValues ? (catTitle, valueTitle) : (valueTitle, catTitle)
        if let t = bottomTitle {
            drawText(fit(t, font, r.width), font: font, color: textColor, center: CGPoint(x: r.midX, y: r.maxY - h / 2))
            r.size.height -= h + 2
        }
        if let t = leftTitle {
            drawText(fit(t, font, r.height), font: font, color: textColor, center: CGPoint(x: r.minX + h / 2, y: r.midY), angle: -.pi / 2)
            r.origin.x += h + 2; r.size.width -= h + 2
        }
    }

    // MARK: Column, bar, line, area

    private func drawCategoryChart(in rect: CGRect) {
        let kind = chart.kind
        let horizontal = kind.isHorizontal
        var r = rect
        axisTitles(in: &r, horizontalValues: horizontal)
        let cats = categories
        let n = max(1, cats.count)
        let font = labelFont
        let lineH = ceil(font.ascender - font.descender)
        let (vmin, vmax) = valueRange(stacked: kind.isStacked)
        let valueLen = horizontal ? r.width : r.height
        let scale = ChartRenderer.niceScale(min: vmin, max: vmax, maxTicks: max(2, min(10, Int(valueLen / (horizontal ? 70 : 34)))))
        let fmt = valueFormat
        let tickLabels = scale.ticks.map { fmt.string($0, step: scale.step) }
        let valueLabelW = (tickLabels.map { size($0, font).width }.max() ?? 0)

        // Plot rectangle.
        var plot = r
        if horizontal {
            let catW = min(r.width * 0.35, (cats.map { size($0, font).width }.max() ?? 0) + 6)
            plot.origin.x += catW; plot.size.width -= catW
            plot.size.height -= lineH + 4
            plot.origin.x += valueLabelW / 2; plot.size.width -= valueLabelW   // half labels stick out on both ends
        } else {
            plot.origin.x += valueLabelW + 6; plot.size.width -= valueLabelW + 6
            plot.origin.y += lineH / 2; plot.size.height -= lineH / 2
        }
        // Category labels: rotate or thin out when they do not fit.
        let slot = (horizontal ? plot.height : plot.width) / CGFloat(n)
        var rotate = false, every = 1
        if !horizontal {
            let widest = cats.map { size($0, font).width }.max() ?? 0
            if widest > slot - 4 {
                rotate = true
                let diag = min(widest, 90) * 0.71 + lineH * 0.71
                plot.size.height -= diag + 4
                every = max(1, Int(ceil((lineH + 2) / max(1, slot))))
            } else {
                plot.size.height -= lineH + 6
            }
        } else {
            every = max(1, Int(ceil((lineH + 1) / max(1, slot))))
        }
        // Area charts put the first and last category on the plot edges: leave room for their labels.
        if kind.isArea && !horizontal && n > 1 && !rotate {
            let l = size(cats.first ?? "", font).width / 2, rr = size(cats.last ?? "", font).width / 2
            let left = max(0, l - (plot.minX - r.minX)), right = max(0, rr - 2)
            plot.origin.x += left; plot.size.width -= left + right
        }
        guard plot.width > 4, plot.height > 4 else { return }
        let ctx = NSGraphicsContext.current!.cgContext

        // Gridlines and value labels.
        for (t, label) in zip(scale.ticks, tickLabels) {
            if horizontal {
                let x = scale.pos(t, plot.minX, plot.maxX).rounded() + 0.5
                gridColor.setFill(); CGRect(x: x - 0.375, y: plot.minY, width: 0.75, height: plot.height).fill()
                drawText(label, font: font, color: textColor, center: CGPoint(x: x, y: plot.maxY + 3 + lineH / 2))
            } else {
                let y = scale.pos(t, plot.maxY, plot.minY).rounded() + 0.5
                gridColor.setFill(); CGRect(x: plot.minX, y: y - 0.375, width: plot.width, height: 0.75).fill()
                let sz = size(label, font)
                (label as NSString).draw(at: CGPoint(x: plot.minX - 6 - sz.width, y: y - sz.height / 2), withAttributes: attrs(font, textColor))
            }
        }
        // Category labels.
        let slotLen = (horizontal ? plot.height : plot.width) / CGFloat(n)
        let areaEdges = kind.isArea && n > 1
        func catCenter(_ i: Int) -> CGFloat {
            if horizontal { return plot.maxY - (CGFloat(i) + 0.5) * slotLen }   // first category at the bottom, like Excel
            if areaEdges { return plot.minX + CGFloat(i) * plot.width / CGFloat(n - 1) }
            return plot.minX + (CGFloat(i) + 0.5) * slotLen
        }
        for (i, c) in cats.enumerated() where i % every == 0 {
            if horizontal {
                let sz = size(c, font)
                let t = fit(c, font, plot.minX - r.minX - 6)
                (t as NSString).draw(at: CGPoint(x: plot.minX - 6 - min(sz.width, size(t, font).width), y: catCenter(i) - sz.height / 2), withAttributes: attrs(font, textColor))
            } else if rotate {
                let t = fit(c, font, 90)
                let sz = size(t, font)
                ctx.saveGState()
                ctx.translateBy(x: catCenter(i), y: plot.maxY + 4)
                ctx.rotate(by: -.pi / 4)
                (t as NSString).draw(at: CGPoint(x: -sz.width, y: -sz.height / 2), withAttributes: attrs(font, textColor))
                ctx.restoreGState()
            } else {
                drawText(c, font: font, color: textColor, center: CGPoint(x: catCenter(i), y: plot.maxY + 4 + lineH / 2))
            }
        }

        // Series.
        let zero = min(max(0, scale.lo), scale.hi)
        func vpos(_ v: Double) -> CGFloat { horizontal ? scale.pos(v, plot.minX, plot.maxX) : scale.pos(v, plot.maxY, plot.minY) }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: plot.insetBy(dx: -6, dy: -6)).setClip()
        if kind.isBar {
            let m = CGFloat(data.count)
            let (gap, overlap): (CGFloat, CGFloat) = kind.isStacked ? (1.5, 1) : (2.19, -0.27)
            let bars = kind.isStacked ? 1 : m
            let barW = slotLen / (bars - (bars - 1) * overlap + gap)
            var posStack = [Double](repeating: 0, count: n), negStack = [Double](repeating: 0, count: n)
            for (si, s) in data.enumerated() {
                seriesColor(si).setFill()
                for i in 0..<n {
                    guard let v = s.values[safe: i] ?? nil else { continue }
                    var a = zero, b = v
                    if kind.isStacked {
                        if v >= 0 { a = posStack[i]; b = a + v; posStack[i] = b } else { a = negStack[i]; b = a + v; negStack[i] = b }
                    }
                    let offset = kind.isStacked ? 0 : (CGFloat(si) * barW * (1 - overlap) - (bars * barW - (bars - 1) * overlap * barW) / 2)
                    let p0 = vpos(a), p1 = vpos(b)
                    let rect: CGRect
                    if horizontal {
                        let y = catCenter(i) + (kind.isStacked ? -barW / 2 : -offset - barW)
                        rect = CGRect(x: min(p0, p1), y: y, width: abs(p1 - p0), height: barW)
                    } else {
                        let x = catCenter(i) + (kind.isStacked ? -barW / 2 : offset)
                        rect = CGRect(x: x, y: min(p0, p1), width: barW, height: abs(p1 - p0))
                    }
                    rect.fill()
                    if kind.isStacked {   // thin separators between stacked segments, like Excel
                        separator.setStroke()
                        let p = NSBezierPath(rect: rect); p.lineWidth = 0.75; p.stroke()
                        seriesColor(si).setFill()
                    }
                }
            }
        } else if kind.isArea {
            var base = [Double](repeating: 0, count: n)
            let order = Array(data.indices)
            var layers: [(Int, NSBezierPath)] = []
            for si in order {
                let s = data[si]
                var top: [CGPoint] = [], bottom: [CGPoint] = []
                for i in 0..<n {
                    let v = (s.values[safe: i] ?? nil) ?? 0
                    let a = kind.isStacked ? base[i] : zero
                    let b = kind.isStacked ? base[i] + v : v
                    if kind.isStacked { base[i] = b }
                    let x = n == 1 ? plot.midX : catCenter(i)
                    top.append(CGPoint(x: x, y: vpos(b)))
                    bottom.append(CGPoint(x: x, y: vpos(a)))
                }
                let path = NSBezierPath()
                path.move(to: top[0])
                top.dropFirst().forEach { path.line(to: $0) }
                bottom.reversed().forEach { path.line(to: $0) }
                path.close()
                layers.append((si, path))
            }
            // Stacked: all visible; standard: first series behind.
            for (si, path) in layers {
                seriesColor(si).setFill()
                path.fill()
            }
        } else {
            // Lines: gaps for empty cells, like Excel's default.
            for (si, s) in data.enumerated() {
                let color = seriesColor(si)
                let path = NSBezierPath()
                path.lineWidth = 2.25
                path.lineJoinStyle = .round
                path.lineCapStyle = .round
                var pts: [CGPoint] = []
                var penDown = false
                for i in 0..<n {
                    guard let v = s.values[safe: i] ?? nil else { penDown = false; continue }
                    let p = CGPoint(x: catCenter(i), y: vpos(v))
                    if penDown { path.line(to: p) } else { path.move(to: p) }
                    penDown = true
                    pts.append(p)
                }
                color.setStroke()
                path.stroke()
                if kind == .lineMarkers || pts.count == 1 { pts.forEach { marker(at: $0, color: color) } }
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // Category axis line at zero.
        axisColor.setFill()
        if horizontal {
            let x = vpos(zero).rounded() + 0.5
            CGRect(x: x - 0.375, y: plot.minY, width: 0.75, height: plot.height).fill()
        } else {
            let y = vpos(zero).rounded() + 0.5
            CGRect(x: plot.minX, y: y - 0.375, width: plot.width, height: 0.75).fill()
        }
    }

    private func marker(at p: CGPoint, color: NSColor) {
        let m = NSBezierPath(ovalIn: CGRect(x: p.x - 2.75, y: p.y - 2.75, width: 5.5, height: 5.5))
        color.setFill(); m.fill()
        color.setStroke(); m.lineWidth = 0.75; m.stroke()
    }

    // MARK: Scatter

    private func drawScatter(in rect: CGRect) {
        var r = rect
        axisTitles(in: &r, horizontalValues: false)
        let font = labelFont
        let lineH = ceil(font.ascender - font.descender)
        // X values: numbers from the categories, else 1, 2, 3...
        let xs: [[Double?]] = data.map { s in
            let numeric = s.categoryNumbers.contains { $0 != nil }
            return (0..<s.values.count).map { numeric ? (s.categoryNumbers[safe: $0] ?? nil) : Double($0 + 1) }
        }
        let allX = xs.flatMap { $0.compactMap { $0 } }
        let allY = data.flatMap { $0.values.compactMap { $0 } }
        let xScale = ChartRenderer.niceScale(min: allX.min() ?? 0, max: allX.max() ?? 1, maxTicks: max(2, min(10, Int(r.width / 60))))
        let yScale = ChartRenderer.niceScale(min: allY.min() ?? 0, max: allY.max() ?? 1, maxTicks: max(2, min(10, Int(r.height / 34))))
        let yFmt = valueFormat, xFmt = AxisFormat(code: "general")
        let yLabels = yScale.ticks.map { yFmt.string($0, step: yScale.step) }
        let xLabels = xScale.ticks.map { xFmt.string($0, step: xScale.step) }
        let yW = yLabels.map { size($0, font).width }.max() ?? 0
        let lastXW = size(xLabels.last ?? "", font).width
        var plot = r
        plot.origin.x += yW + 6; plot.size.width -= yW + 6 + lastXW / 2
        plot.origin.y += lineH / 2; plot.size.height -= lineH / 2 + lineH + 6
        guard plot.width > 4, plot.height > 4 else { return }
        for (t, label) in zip(yScale.ticks, yLabels) {
            let y = yScale.pos(t, plot.maxY, plot.minY).rounded() + 0.5
            gridColor.setFill(); CGRect(x: plot.minX, y: y - 0.375, width: plot.width, height: 0.75).fill()
            let sz = size(label, font)
            (label as NSString).draw(at: CGPoint(x: plot.minX - 6 - sz.width, y: y - sz.height / 2), withAttributes: attrs(font, textColor))
        }
        for (t, label) in zip(xScale.ticks, xLabels) {
            let x = xScale.pos(t, plot.minX, plot.maxX).rounded() + 0.5
            gridColor.setFill(); CGRect(x: x - 0.375, y: plot.minY, width: 0.75, height: plot.height).fill()
            drawText(label, font: font, color: textColor, center: CGPoint(x: x, y: plot.maxY + 4 + lineH / 2))
        }
        axisColor.setFill()
        let y0 = yScale.pos(min(max(0, yScale.lo), yScale.hi), plot.maxY, plot.minY).rounded() + 0.5
        CGRect(x: plot.minX, y: y0 - 0.375, width: plot.width, height: 0.75).fill()
        for (si, s) in data.enumerated() {
            let color = seriesColor(si)
            for i in 0..<s.values.count {
                guard let y = s.values[i], let x = xs[si][i] else { continue }
                marker(at: CGPoint(x: xScale.pos(x, plot.minX, plot.maxX), y: yScale.pos(y, plot.maxY, plot.minY)), color: color)
            }
        }
    }

    // MARK: Pie and doughnut

    private func drawPie(in rect: CGRect) {
        let rings = chart.kind == .doughnut ? data : Array(data.prefix(1))
        let radius = max(4, min(rect.width, rect.height) / 2 - 4)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let hole: CGFloat = chart.kind == .doughnut ? 0.5 : 0
        let ringW = radius * (1 - hole) / CGFloat(max(1, rings.count))
        for (ri, s) in rings.enumerated() {
            let values = s.values.map { max(0, $0 ?? 0) }
            let total = values.reduce(0, +)
            guard total > 0 else { continue }
            let outer = radius - CGFloat(ri) * ringW
            let inner = chart.kind == .doughnut ? outer - ringW : 0
            var angle: CGFloat = -90   // 12 o'clock, clockwise (y is down)
            for (i, v) in values.enumerated() where v > 0 {
                let sweep = CGFloat(v / total) * 360
                let path = NSBezierPath()
                if inner > 0 {
                    path.appendArc(withCenter: center, radius: outer, startAngle: angle, endAngle: angle + sweep, clockwise: false)
                    path.appendArc(withCenter: center, radius: inner, startAngle: angle + sweep, endAngle: angle, clockwise: true)
                } else {
                    path.move(to: center)
                    path.appendArc(withCenter: center, radius: outer, startAngle: angle, endAngle: angle + sweep, clockwise: false)
                }
                path.close()
                ChartRenderer.paletteColor(i).setFill()
                path.fill()
                separator.setStroke()
                path.lineWidth = 1
                path.stroke()
                angle += sweep
            }
        }
    }
}

/// Formats axis values following the number format of the data (percent, currency, thousands, decimals).
struct AxisFormat {
    let percent: Bool
    let decimals: Int?
    let thousands: Bool
    let prefix: String
    let suffix: String

    init(code: String) {
        let c = code.split(separator: ";").first.map(String.init) ?? code
        percent = c.contains("%")
        thousands = c.contains("#,##") || c.contains("#.##0")
        if c.lowercased() == "general" || !(c.contains("0") || c.contains("#")) {
            decimals = nil
        } else if let dot = c.range(of: ".") {
            decimals = c[dot.upperBound...].prefix { $0 == "0" }.count
        } else {
            decimals = 0
        }
        // Currency: [$€-410], "€", $ € £ ¥ outside quotes.
        var symbol = ""
        if let m = c.range(of: #"\[\$([^\]-]+)"#, options: .regularExpression) {
            symbol = String(c[m].dropFirst(2))
        } else if let ch = c.first(where: { "€$£¥".contains($0) }) {
            symbol = String(ch)
        }
        if !symbol.isEmpty, let pos = c.range(of: symbol), let zero = c.firstIndex(where: { $0 == "0" || $0 == "#" }) {
            if pos.lowerBound < zero { prefix = symbol; suffix = "" } else { prefix = ""; suffix = " " + symbol }
        } else { prefix = ""; suffix = "" }
    }

    func string(_ v: Double, step: Double) -> String {
        let value = percent ? v * 100 : v
        let stepDecimals = max(0, Int(ceil(-log10(max(1e-12, (percent ? step * 100 : step)) - 1e-9))))
        let d = decimals ?? min(10, stepDecimals)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = d
        f.maximumFractionDigits = d
        f.usesGroupingSeparator = thousands || (decimals == nil && abs(value) >= 10000)
        let en = FormulaLocale.current.locale.hasPrefix("en")
        f.decimalSeparator = en ? "." : ","
        f.groupingSeparator = en ? "," : "."
        let s = f.string(from: NSNumber(value: abs(value) < 1e-12 ? 0 : value)) ?? "\(value)"
        return prefix + s + (percent ? "%" : "") + suffix
    }
}

