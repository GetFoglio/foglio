import AppKit

struct CellRef: Equatable, Hashable {
    var row: Int
    var col: Int
}

struct GridRange: Equatable {
    var r0: Int, c0: Int, r1: Int, c1: Int
    init(_ a: CellRef, _ b: CellRef) {
        r0 = min(a.row, b.row); r1 = max(a.row, b.row)
        c0 = min(a.col, b.col); c1 = max(a.col, b.col)
    }
    init(r0: Int, c0: Int, r1: Int, c1: Int) {
        self.r0 = min(r0, r1); self.r1 = max(r0, r1)
        self.c0 = min(c0, c1); self.c1 = max(c0, c1)
    }
    var isSingle: Bool { r0 == r1 && c0 == c1 }
    var rows: Int { r1 - r0 + 1 }
    var cols: Int { c1 - c0 + 1 }
    var cellCount: Int { rows * cols }
    var isFullColumns: Bool { r0 == 0 && r1 == Sheet.maxRows - 1 }
    var isFullRows: Bool { c0 == 0 && c1 == Sheet.maxCols - 1 }
    func contains(_ c: CellRef) -> Bool { c.row >= r0 && c.row <= r1 && c.col >= c0 && c.col <= c1 }
    func intersects(_ o: GridRange) -> Bool { !(o.r1 < r0 || o.r0 > r1 || o.c1 < c0 || o.c0 > c1) }
    func union(_ o: GridRange) -> GridRange { GridRange(r0: min(r0, o.r0), c0: min(c0, o.c0), r1: max(r1, o.r1), c1: max(c1, o.c1)) }
    var a1: String {
        if isFullColumns { return "\(columnName(c0)):\(columnName(c1))" }
        if isFullRows { return "\(r0 + 1):\(r1 + 1)" }
        let a = "\(columnName(c0))\(r0 + 1)"
        return isSingle ? a : "\(a):\(columnName(c1))\(r1 + 1)"
    }
}

enum Sheet {
    static let maxRows = 1_048_576
    static let maxCols = 16_384
}

func columnName(_ c: Int) -> String {
    var n = c + 1
    var s = ""
    while n > 0 {
        let m = (n - 1) % 26
        s = String(UnicodeScalar(UInt8(65 + m))) + s
        n = (n - 1) / 26
    }
    return s
}

/// Parses "B12", "$B$12", "B12:C20" (0-based).
func parseA1Range(_ s: String) -> GridRange? {
    let parts = s.replacingOccurrences(of: "$", with: "").split(separator: ":")
    guard let a = parts.first.flatMap({ parseA1(String($0)) }) else { return nil }
    if parts.count == 2, let b = parseA1(String(parts[1])) { return GridRange(a, b) }
    return parts.count == 1 ? GridRange(a, a) : nil
}

func parseA1(_ s: String) -> CellRef? {
    let u = s.uppercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
    var col = 0, i = u.startIndex
    while i < u.endIndex, let a = u[i].asciiValue, a >= 65, a <= 90 { col = col * 26 + Int(a - 64); i = u.index(after: i) }
    guard col > 0, col <= Sheet.maxCols, i < u.endIndex, let r = Int(u[i...]), r > 0, r <= Sheet.maxRows else { return nil }
    return CellRef(row: r - 1, col: col - 1)
}

/// Sizes along one axis: a default size plus sparse overrides (hidden = 0). O(log n) lookups.
struct Axis {
    let defaultSize: CGFloat
    let count: Int
    private var idx: [Int] = []
    private var sizes: [CGFloat] = []
    private var prefix: [CGFloat] = []   // cumulative (size - default) through entry k, inclusive

    init(defaultSize: CGFloat, count: Int, overrides: [(Int, CGFloat)] = []) {
        self.defaultSize = defaultSize
        self.count = count
        let sorted = overrides.filter { $0.0 >= 0 && $0.0 < count }.sorted { $0.0 < $1.0 }
        var acc: CGFloat = 0
        for (i, s) in sorted where idx.last != i {
            idx.append(i); sizes.append(s)
            acc += s - defaultSize
            prefix.append(acc)
        }
    }

    /// Index of the last override with idx < i, or -1.
    private func lastBefore(_ i: Int) -> Int {
        var lo = 0, hi = idx.count
        while lo < hi { let m = (lo + hi) / 2; if idx[m] < i { lo = m + 1 } else { hi = m } }
        return lo - 1
    }

    func size(_ i: Int) -> CGFloat {
        let k = lastBefore(i + 1)
        return k >= 0 && idx[k] == i ? sizes[k] : defaultSize
    }

    func pos(_ i: Int) -> CGFloat {
        let k = lastBefore(i)
        return CGFloat(i) * defaultSize + (k >= 0 ? prefix[k] : 0)
    }

    var total: CGFloat { pos(count) }

    /// The index whose span contains p (clamped to valid indices).
    func index(at p: CGFloat) -> Int {
        if p <= 0 { return firstVisible(from: 0) }
        // Largest override k whose start <= p.
        var lo = 0, hi = idx.count
        while lo < hi {
            let m = (lo + hi) / 2
            let start = CGFloat(idx[m]) * defaultSize + (m > 0 ? prefix[m - 1] : 0)
            if start <= p { lo = m + 1 } else { hi = m }
        }
        let k = lo - 1
        var i: Int
        if k < 0 {
            i = Int(p / defaultSize)
        } else {
            let start = CGFloat(idx[k]) * defaultSize + (k > 0 ? prefix[k - 1] : 0)
            if p < start + sizes[k] {
                i = idx[k]
            } else {
                i = idx[k] + 1 + Int((p - start - sizes[k]) / defaultSize)
                if k + 1 < idx.count { i = min(i, idx[k + 1]) }
            }
        }
        return min(max(0, i), count - 1)
    }

    func firstVisible(from i: Int) -> Int {
        var j = i
        while j < count - 1 && size(j) == 0 { j += 1 }
        return j
    }

    func isHidden(_ i: Int) -> Bool { size(i) == 0 }

    /// Moves `steps` visible indices from i (skipping hidden ones).
    func step(_ i: Int, by steps: Int) -> Int {
        guard steps != 0 else { return i }
        var j = i, left = abs(steps)
        let d = steps > 0 ? 1 : -1
        while left > 0 {
            let n = j + d
            if n < 0 || n >= count { break }
            j = n
            if size(j) > 0 { left -= 1 }
        }
        return size(j) > 0 ? j : i
    }
}
