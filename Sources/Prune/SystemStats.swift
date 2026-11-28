import SwiftUI
import Darwin

/// CPU and memory load for the menu bar rings. Sampled every 2 s while the panel is on screen.
@MainActor @Observable
final class SystemStats {
    static let shared = SystemStats()

    private(set) var cpu: Double = 0
    private(set) var memoryUsed: Int64 = 0
    let memoryTotal = Int64(ProcessInfo.processInfo.physicalMemory)
    var memoryFraction: Double { memoryTotal > 0 ? min(1, Double(memoryUsed) / Double(memoryTotal)) : 0 }

    private var previousTicks: (busy: UInt64, total: UInt64)?
    private var timer: Timer?
    private var watchers = 0

    func startWatching() {
        watchers += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in SystemStats.shared.sample() }
        }
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func sample() {
        if let ticks = Self.cpuTicks() {
            if let prev = previousTicks, ticks.total > prev.total {
                cpu = Double(ticks.busy - prev.busy) / Double(ticks.total - prev.total)
            }
            previousTicks = ticks
        }
        if let used = Self.memoryInUse() { memoryUsed = used }
    }

    /// Busy and total CPU ticks summed over all cores since boot.
    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Free memory (free + speculative pages). `purge` raises this by dropping the file cache.
    nonisolated static func memoryFree() -> Int64? {
        guard let stats = vmStats() else { return nil }
        return (Int64(stats.free_count) + Int64(stats.speculative_count)) * Int64(vm_kernel_page_size)
    }

    nonisolated private static func vmStats() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return r == KERN_SUCCESS ? stats : nil
    }

    /// "Memory Used" as Activity Monitor counts it: app memory + wired + compressed.
    private static func memoryInUse() -> Int64? {
        guard let stats = vmStats() else { return nil }
        let page = Int64(vm_kernel_page_size)
        let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        let pages = max(0, app) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
        return pages * page
    }
}

extension Fmt {
    /// Memory sizes in binary units (1 GB = 1024³ bytes), the way Activity Monitor and "About This Mac" show RAM.
    static func memory(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        let s = i == 0 ? "\(Int(v))" : (v < 100 ? String(format: "%.1f", v) : String(format: "%.0f", v))
        return "\(s) \(tr(units[i]))"
    }
}

/// A small usage ring with an icon inside and the value under it.
struct UsageRing: View {
    let symbol: String
    let label: String
    let fraction: Double
    let color: Color
    var value: String? = nil

    private var tint: Color { fraction >= 0.9 ? Theme.red : (fraction >= 0.75 ? Theme.amber : color) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Theme.text.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(Theme.sans(12.5, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 58, height: 58)
            VStack(spacing: 0) {
                Text(tr(label)).font(Theme.sans(11, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                if let value {
                    Text(value).font(Theme.sans(10)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: fraction)
    }
}
