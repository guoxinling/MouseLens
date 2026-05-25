import Foundation

struct RecordingSessionState: Equatable {
    let startedAt: Date
    var pausedAt: Date?
    var accumulatedPausedDuration: TimeInterval

    init(startedAt: Date, pausedAt: Date? = nil, accumulatedPausedDuration: TimeInterval = 0) {
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.accumulatedPausedDuration = accumulatedPausedDuration
    }

    var isPaused: Bool {
        pausedAt != nil
    }

    func pausing(at date: Date = Date()) -> RecordingSessionState {
        guard pausedAt == nil else { return self }

        var updated = self
        updated.pausedAt = date
        return updated
    }

    func resuming(at date: Date = Date()) -> RecordingSessionState {
        guard let pausedAt else { return self }

        var updated = self
        updated.accumulatedPausedDuration += max(0, date.timeIntervalSince(pausedAt))
        updated.pausedAt = nil
        return updated
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        let effectiveEnd = pausedAt ?? date
        return max(0, effectiveEnd.timeIntervalSince(startedAt) - accumulatedPausedDuration)
    }
}

enum RecordingState: Equatable {
    case idle
    case countdown(secondsRemaining: Int)
    case recording(RecordingSessionState)
}
