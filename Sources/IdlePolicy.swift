import Foundation

enum BlackoutDelay: Int, CaseIterable {
    case oneMinute = 1
    case twoMinutes = 2
    case threeMinutes = 3
    case fiveMinutes = 5

    init(savedMinutes: Int) {
        self = Self(rawValue: savedMinutes) ?? .twoMinutes
    }

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    var title: String { "\(rawValue) \(rawValue == 1 ? "minute" : "minutes")" }
}

/// Pure state machine; input timestamps are derived from the system idle counter.
struct IdlePolicy {
    enum Change: Equatable { case none, show, hide }

    private(set) var timeout: TimeInterval
    private(set) var enabled = true
    private(set) var suspended = false
    private(set) var isBlack = false
    private var armedAt: TimeInterval
    private var inputAtBlackout: TimeInterval = 0

    init(timeout: TimeInterval = 120, now: TimeInterval) {
        self.timeout = timeout
        armedAt = now
    }

    mutating func configure(enabled: Bool, suspended: Bool, now: TimeInterval) -> Change {
        self.enabled = enabled
        self.suspended = suspended
        armedAt = now
        return clear()
    }

    mutating func setTimeout(_ timeout: TimeInterval, now: TimeInterval) -> Change {
        guard timeout.isFinite, timeout > 0 else { return .none }
        self.timeout = timeout
        armedAt = now
        return clear()
    }

    mutating func sample(now: TimeInterval, idle: TimeInterval) -> Change {
        guard enabled, !suspended else { return clear() }
        guard now.isFinite, idle.isFinite, idle >= 0 else {
            armedAt = now
            return clear()
        }

        let lastInput = now - idle
        if isBlack {
            // Allow 5 ms of clock/query jitter, without reading or intercepting input.
            if lastInput > inputAtBlackout + 0.005 {
                armedAt = now
                return clear()
            }
            return .none
        }

        if idle >= timeout, now - armedAt >= timeout {
            return blackOut(now: now, idle: idle)
        }
        return .none
    }

    mutating func blackOut(now: TimeInterval, idle: TimeInterval) -> Change {
        guard enabled, !suspended, !isBlack, now.isFinite, idle.isFinite, idle >= 0 else {
            return .none
        }
        inputAtBlackout = now - idle
        isBlack = true
        return .show
    }

    private mutating func clear() -> Change {
        guard isBlack else { return .none }
        isBlack = false
        return .hide
    }
}
