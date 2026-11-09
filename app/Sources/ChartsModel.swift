import Foundation

// Charts: Swift side of core/include/foglio_charts.h. Rows/columns here are 0-based like the rest of the app.

enum ChartKind: String, CaseIterable {
    case column, columnStacked = "column_stacked", bar, barStacked = "bar_stacked", line, lineMarkers = "line_markers"
    case pie, doughnut, area, areaStacked = "area_stacked", scatter

    var title: String {
        switch self {
        case .column: return L("Clustered Column")
        case .columnStacked: return L("Stacked Column")
        case .bar: return L("Clustered Bar")
        case .barStacked: return L("Stacked Bar")
        case .line: return L("Line")
        case .lineMarkers: return L("Line with Markers")
        case .pie: return L("Pie")
        case .doughnut: return L("Doughnut")
        case .area: return L("Area")
        case .areaStacked: return L("Stacked Area")
        case .scatter: return L("Scatter")
        }
    }
    var symbol: String {
        switch self {
        case .column, .columnStacked: return "chart.bar"
        case .bar, .barStacked: return "chart.bar.xaxis"
        case .line, .lineMarkers: return "chart.line.uptrend.xyaxis"
        case .pie: return "chart.pie"
        case .doughnut: return "circle.circle"
        case .area, .areaStacked: return "chart.line.uptrend.xyaxis.circle"
        case .scatter: return "chart.dots.scatter"
        }
    }
    var hasAxes: Bool { self != .pie && self != .doughnut }
    var isHorizontal: Bool { self == .bar || self == .barStacked }
    var isStacked: Bool { self == .columnStacked || self == .barStacked || self == .areaStacked }
    var isBar: Bool { self == .column || self == .columnStacked || self == .bar || self == .barStacked }
    var isLine: Bool { self == .line || self == .lineMarkers }
    var isArea: Bool { self == .area || self == .areaStacked }
}

enum ChartLegend: String, CaseIterable {
    case none, right, top, bottom, left
    var title: String {
        switch self {
        case .none: return L("None")
        case .right: return L("At Right")
        case .top: return L("At Top")
        case .bottom: return L("At Bottom")
        case .left: return L("At Left")
        }
    }
}

/// A corner of the chart: a cell (0-based) plus a fraction of its height (fy) and width (fx).
struct ChartCorner: Equatable {
    var row: Int, col: Int
    var fy: Double, fx: Double
}

struct ChartSeriesRef: Codable, Equatable {
    var nameRef: String?
    var name: String?
    var categoriesRef: String?
    var valuesRef: String
    var color: String?
}

/// One chart of a sheet, as listed by the engine.
struct ChartInfo: Equatable {
    var index: Int
    var name: String
    var kind: ChartKind
    var title: String?
    var legend: ChartLegend
    var categoryAxisTitle: String?
    var valueAxisTitle: String?
    var series: [ChartSeriesRef]
    var from: ChartCorner
    var to: ChartCorner
    var dataRange: String?
}

/// Evaluated series, ready to draw.
struct ChartSeriesData: Decodable, Equatable {
    var name: String
    var color: String?
    var categories: [String]
    var categoryNumbers: [Double?]
    var values: [Double?]
    var format: String
}

private struct RawCorner: Decodable { let row: Int; let col: Int; let fy: Double; let fx: Double }
private struct RawAnchor: Decodable { let from: RawCorner; let to: RawCorner }
private struct RawChart: Decodable {
    let index: Int
    let name: String
    let kind: String
    let title: String?
    let legend: String
    let categoryAxisTitle: String?
    let valueAxisTitle: String?
    let series: [ChartSeriesRef]
    let anchor: RawAnchor
    let dataRange: String?
}

private let snakeDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()
private let snakeEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.keyEncodingStrategy = .convertToSnakeCase
    return e
}()

extension Workbook {
    /// The engine handle. `Workbook.ptr` is private to Engine.swift, so it is read by reflection
    /// (cheap: one stored property). If Engine.swift ever exposes it, use that instead.
    fileprivate var enginePtr: OpaquePointer? { rawPtr }

    func charts(sheet: Int) -> [ChartInfo] {
        guard let p = enginePtr, let json = Workbook.take(foglio_charts_json(p, UInt32(sheet))),
              let raw = try? snakeDecoder.decode([RawChart].self, from: Data(json.utf8)) else { return [] }
        return raw.map { r in
            ChartInfo(index: r.index, name: r.name, kind: ChartKind(rawValue: r.kind) ?? .column, title: r.title,
                      legend: ChartLegend(rawValue: r.legend) ?? .bottom,
                      categoryAxisTitle: r.categoryAxisTitle, valueAxisTitle: r.valueAxisTitle, series: r.series,
                      from: ChartCorner(row: r.anchor.from.row - 1, col: r.anchor.from.col - 1, fy: r.anchor.from.fy, fx: r.anchor.from.fx),
                      to: ChartCorner(row: r.anchor.to.row - 1, col: r.anchor.to.col - 1, fy: r.anchor.to.fy, fx: r.anchor.to.fx),
                      dataRange: r.dataRange)
        }
    }

    func chartData(sheet: Int, index: Int) -> [ChartSeriesData] {
        guard let p = enginePtr, let json = Workbook.take(foglio_chart_data_json(p, UInt32(sheet), UInt32(index))) else { return [] }
        return (try? snakeDecoder.decode([ChartSeriesData].self, from: Data(json.utf8))) ?? []
    }

    /// Adds a chart for `range`; placed at `at` or right of the data. Returns the new index.
    @discardableResult
    func addChart(sheet: Int, kind: ChartKind, range r: GridRange, at: CellRef? = nil) -> Int? {
        guard let p = enginePtr else { return nil }
        let i = foglio_chart_add(p, UInt32(sheet), kind.rawValue, Int32(r.r0 + 1), Int32(r.c0 + 1), Int32(r.r1 + 1), Int32(r.c1 + 1),
                                 Int32((at?.row ?? -1) + 1), Int32((at?.col ?? -1) + 1))
        return i >= 0 ? Int(i) : nil
    }

    /// Changes kind/title/legend/axis titles/series. `nil` leaves a field alone; an empty title removes it.
    @discardableResult
    func updateChart(sheet: Int, index: Int, kind: ChartKind? = nil, title: String? = nil, legend: ChartLegend? = nil,
                     categoryAxisTitle: String? = nil, valueAxisTitle: String? = nil, series: [ChartSeriesRef]? = nil) -> Bool {
        guard let p = enginePtr else { return false }
        var patch: [String: Any] = [:]
        if let kind { patch["kind"] = kind.rawValue }
        if let title { patch["title"] = title }
        if let legend { patch["legend"] = legend.rawValue }
        if let categoryAxisTitle { patch["category_axis_title"] = categoryAxisTitle }
        if let valueAxisTitle { patch["value_axis_title"] = valueAxisTitle }
        if let series, let d = try? snakeEncoder.encode(series), let v = try? JSONSerialization.jsonObject(with: d) { patch["series"] = v }
        guard let data = try? JSONSerialization.data(withJSONObject: patch), let json = String(data: data, encoding: .utf8) else { return false }
        return foglio_chart_update(p, UInt32(sheet), UInt32(index), json) == 0
    }

    @discardableResult
    func setChartAnchor(sheet: Int, index: Int, from a: ChartCorner, to b: ChartCorner) -> Bool {
        guard let p = enginePtr else { return false }
        return foglio_chart_set_anchor(p, UInt32(sheet), UInt32(index), Int32(a.row + 1), Int32(a.col + 1), a.fy, a.fx,
                                       Int32(b.row + 1), Int32(b.col + 1), b.fy, b.fx) == 0
    }

    @discardableResult
    func setChartRange(sheet: Int, index: Int, _ range: String) -> Bool {
        guard let p = enginePtr else { return false }
        return foglio_chart_set_range(p, UInt32(sheet), UInt32(index), range) == 0
    }

    @discardableResult
    func deleteChart(sheet: Int, index: Int) -> Bool {
        guard let p = enginePtr else { return false }
        return foglio_chart_delete(p, UInt32(sheet), UInt32(index)) == 0
    }
}
