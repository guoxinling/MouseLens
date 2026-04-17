import Combine
import Foundation

@MainActor
final class AppPreferencesStore: ObservableObject {
    private enum Keys {
        static let countdownSeconds = "preferences.countdownSeconds"
        static let hideWindowBeforeCapture = "preferences.hideWindowBeforeCapture"
        static let defaultMicrophoneEnabled = "preferences.defaultMicrophoneEnabled"
        static let defaultSystemAudioEnabled = "preferences.defaultSystemAudioEnabled"
        static let defaultAspectRatio = "preferences.defaultAspectRatio"
        static let autoRevealExportInFinder = "preferences.autoRevealExportInFinder"
    }

    @Published var countdownSeconds: Int {
        didSet {
            let clamped = countdownSeconds.clamped(to: 0...5)
            guard clamped == countdownSeconds else {
                countdownSeconds = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.countdownSeconds)
        }
    }

    @Published var hideWindowBeforeCapture: Bool {
        didSet { defaults.set(hideWindowBeforeCapture, forKey: Keys.hideWindowBeforeCapture) }
    }

    @Published var defaultMicrophoneEnabled: Bool {
        didSet { defaults.set(defaultMicrophoneEnabled, forKey: Keys.defaultMicrophoneEnabled) }
    }

    @Published var defaultSystemAudioEnabled: Bool {
        didSet { defaults.set(defaultSystemAudioEnabled, forKey: Keys.defaultSystemAudioEnabled) }
    }

    @Published var defaultAspectRatio: ProjectAspectRatio {
        didSet { defaults.set(defaultAspectRatio.rawValue, forKey: Keys.defaultAspectRatio) }
    }

    @Published var autoRevealExportInFinder: Bool {
        didSet { defaults.set(autoRevealExportInFinder, forKey: Keys.autoRevealExportInFinder) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedCountdown = defaults.object(forKey: Keys.countdownSeconds) as? Int
        countdownSeconds = (savedCountdown ?? 3).clamped(to: 0...5)
        hideWindowBeforeCapture = defaults.object(forKey: Keys.hideWindowBeforeCapture) as? Bool ?? true
        defaultMicrophoneEnabled = defaults.object(forKey: Keys.defaultMicrophoneEnabled) as? Bool ?? true
        defaultSystemAudioEnabled = defaults.object(forKey: Keys.defaultSystemAudioEnabled) as? Bool ?? false

        if
            let rawAspectRatio = defaults.string(forKey: Keys.defaultAspectRatio),
            let aspectRatio = ProjectAspectRatio(rawValue: rawAspectRatio)
        {
            defaultAspectRatio = aspectRatio
        } else {
            defaultAspectRatio = .landscape
        }

        autoRevealExportInFinder = defaults.object(forKey: Keys.autoRevealExportInFinder) as? Bool ?? false
    }
}
