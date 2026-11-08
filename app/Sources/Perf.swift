import AppKit
import Darwin

/// Measurement hooks, active only when FOGLIO_PERF is set. Prints KEY=value lines on stdout.
final class Perf {
    static let shared = Perf()
    let enabled = ProcessInfo.processInfo.environment["FOGLIO_PERF"] != nil
    var onFirstFrame: (() -> Void)?

    private var firstFrameDone = false
    private var recording = false
    private var drawTimes: [Double] = []

    private func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }

    func emit(_ key: String, _ value: String) {
        guard enabled else { return }
        print("\(key)=\(value)")
        fflush(stdout)
    }

    func frameDrawn(ms: Double) {
        if !firstFrameDone {
            firstFrameDone = true
            if enabled, let start = processStart() {
                emit("FIRST_FRAME_MS", String(format: "%.1f", Date().timeIntervalSince(start) * 1000))
            }
            // Let the frame reach the screen before running any benchmark.
            DispatchQueue.main.async { self.onFirstFrame?() }
        }
        if recording { drawTimes.append(ms) }
    }

    func beginRecording() { drawTimes.removeAll(); recording = true }

    func endRecording(frameStamps: [CFTimeInterval], refresh: Double) {
        recording = false
        let d = drawTimes.sorted()
        func pct(_ p: Double) -> Double { d.isEmpty ? 0 : d[min(d.count - 1, Int(Double(d.count) * p))] }
        emit("SCROLL_FRAMES", "\(frameStamps.count)")
        emit("DRAW_MS_P50", String(format: "%.2f", pct(0.5)))
        emit("DRAW_MS_P99", String(format: "%.2f", pct(0.99)))
        emit("DRAW_MS_MAX", String(format: "%.2f", d.last ?? 0))
        let budget = 1 / refresh
        var late = 0
        for i in 1..<max(1, frameStamps.count) where frameStamps[i] - frameStamps[i - 1] > budget * 1.5 { late += 1 }
        emit("DISPLAY_HZ", String(format: "%.0f", refresh))
        emit("DROPPED_FRAMES", "\(late)")
        NotificationCenter.default.post(name: .foglioBenchmarkDone, object: nil)
    }
}

extension Notification.Name {
    static let foglioBenchmarkDone = Notification.Name("foglioBenchmarkDone")
}
