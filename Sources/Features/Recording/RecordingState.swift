import Foundation

enum RecordingState: Equatable {
    case idle
    case countdown(secondsRemaining: Int)
    case recording(startedAt: Date)
}
