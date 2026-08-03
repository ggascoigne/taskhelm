import Foundation
import os

struct QuickCaptureLatencyMeasurement: Equatable, Sendable {
    var selectionLookup: Duration?
    var invocationToFocusedPanel: Duration

    var isWithinBudget: Bool {
        (selectionLookup == nil || selectionLookup! <= QuickCaptureLatencyBudget.selectionLookup)
            && invocationToFocusedPanel <= QuickCaptureLatencyBudget.invocationToFocusedPanel
    }
}

enum QuickCaptureLatencyBudget {
    static let selectionLookup = Duration.milliseconds(100)
    static let invocationToFocusedPanel = Duration.milliseconds(150)
    static let selectionTimeoutNanoseconds: UInt64 = 70_000_000
}

struct QuickCaptureLatencyTrace: Sendable {
    let startedAt: ContinuousClock.Instant
    let signpostID: OSSignpostID
}

enum QuickCaptureLatency {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.ggp.tw-mac",
        category: "QuickCaptureLatency"
    )

    @MainActor
    static func begin() -> QuickCaptureLatencyTrace {
        let trace = QuickCaptureLatencyTrace(
            startedAt: .now,
            signpostID: OSSignpostID(log: log)
        )
        os_signpost(
            .begin,
            log: log,
            name: "InvocationToFocusedPanel",
            signpostID: trace.signpostID
        )
        return trace
    }

    @MainActor
    static func recordSelectionLookup(for trace: QuickCaptureLatencyTrace) -> Duration {
        let duration = trace.startedAt.duration(to: .now)
        os_signpost(
            .event,
            log: log,
            name: "SelectionLookup",
            signpostID: trace.signpostID,
            "duration_ms=%{public}.2f within_budget=%{public}d",
            duration.milliseconds,
            duration <= QuickCaptureLatencyBudget.selectionLookup
        )
        return duration
    }

    @MainActor
    static func finish(
        _ trace: QuickCaptureLatencyTrace,
        selectionLookup: Duration?
    ) -> QuickCaptureLatencyMeasurement {
        let duration = trace.startedAt.duration(to: .now)
        let measurement = QuickCaptureLatencyMeasurement(
            selectionLookup: selectionLookup,
            invocationToFocusedPanel: duration
        )
        os_signpost(
            .end,
            log: log,
            name: "InvocationToFocusedPanel",
            signpostID: trace.signpostID,
            "duration_ms=%{public}.2f within_budget=%{public}d",
            duration.milliseconds,
            measurement.isWithinBudget
        )
        return measurement
    }
}

private extension Duration {
    var milliseconds: Double {
        let value = components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1_000_000_000_000_000
    }
}
