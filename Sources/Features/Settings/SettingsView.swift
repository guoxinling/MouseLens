import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferencesStore
    let shortcutLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Form {
                Section("Recording") {
                    Stepper(
                        value: $preferences.countdownSeconds,
                        in: 0...5
                    ) {
                        HStack {
                            Text("Countdown")
                            Spacer()
                            Text(countdownLabel)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Hide MouseLens before capture starts", isOn: $preferences.hideWindowBeforeCapture)
                    Toggle("Enable microphone by default", isOn: $preferences.defaultMicrophoneEnabled)
                    Toggle("Enable system audio by default", isOn: $preferences.defaultSystemAudioEnabled)
                }

                Section("Output") {
                    Picker("Default aspect ratio", selection: $preferences.defaultAspectRatio) {
                        ForEach(ProjectAspectRatio.allCases, id: \.self) { ratio in
                            Text(ratio.label).tag(ratio)
                        }
                    }

                    Toggle("Reveal export in Finder automatically", isOn: $preferences.autoRevealExportInFinder)
                }

                Section("Shortcut") {
                    HStack {
                        Text("Global toggle")
                        Spacer()
                        Text(shortcutLabel)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.panelBorder.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text("Use the global shortcut to start recording, cancel the countdown, or stop from anywhere.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .formStyle(.grouped)

            Text("Preferences are saved locally and applied to the next recording session.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(24)
        .frame(width: 520, height: 420, alignment: .topLeading)
    }

    private var countdownLabel: String {
        preferences.countdownSeconds == 0 ? "Off" : "\(preferences.countdownSeconds)s"
    }
}
