import SwiftUI

struct RecordingHUDView: View {
    let state: RecordingState
    let shortcutHint: String
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(titleText, systemImage: iconName)
                    .foregroundStyle(iconColor)
                Spacer()
                statusClock
            }

            Text(descriptionText)
                .foregroundStyle(AppTheme.mutedText)

            Text("Global shortcut: \(shortcutHint)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.accent)

            Button(role: buttonRole, action: onPrimaryAction) {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(buttonTint)
            .controlSize(.large)
        }
        .padding(28)
        .cardStyle()
    }

    @ViewBuilder
    private var statusClock: some View {
        switch state {
        case .idle:
            Text("00:00")
                .font(.system(.body, design: .monospaced))
        case .countdown(let secondsRemaining):
            Text(String(format: "00:%02d", secondsRemaining))
                .font(.system(.body, design: .monospaced))
        case .recording(let startedAt):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsedText(since: startedAt, now: context.date))
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var titleText: String {
        switch state {
        case .idle:
            return "Ready"
        case .countdown(let secondsRemaining):
            return "Starting in \(secondsRemaining)"
        case .recording:
            return "Recording"
        }
    }

    private var iconName: String {
        switch state {
        case .idle:
            return "circle.dashed"
        case .countdown:
            return "timer"
        case .recording:
            return "record.circle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle:
            return AppTheme.mutedText
        case .countdown:
            return .orange
        case .recording:
            return .red
        }
    }

    private var descriptionText: String {
        switch state {
        case .idle:
            return "MouseLens is ready for the next walkthrough."
        case .countdown:
            return "MouseLens will hide its window before capture begins so the control panel does not end up in the recording."
        case .recording:
            return "Pointer activity is being tracked for automatic zoom and smooth camera motion even while the app window stays hidden."
        }
    }

    private var primaryButtonTitle: String {
        switch state {
        case .idle:
            return "Start Recording"
        case .countdown:
            return "Cancel Countdown"
        case .recording:
            return "Stop Recording"
        }
    }

    private var primaryButtonIcon: String {
        switch state {
        case .idle:
            return "play.circle.fill"
        case .countdown:
            return "xmark.circle.fill"
        case .recording:
            return "stop.circle.fill"
        }
    }

    private var buttonTint: Color {
        switch state {
        case .idle:
            return AppTheme.accent
        case .countdown:
            return .orange
        case .recording:
            return .red
        }
    }

    private var buttonRole: ButtonRole? {
        switch state {
        case .recording:
            return .destructive
        case .idle, .countdown:
            return nil
        }
    }

    private func elapsedText(since startedAt: Date, now: Date) -> String {
        let duration = max(0, Int(now.timeIntervalSince(startedAt)))
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
