import XCTest
@testable import MouseLens

@MainActor
final class AppPreferencesStoreTests: XCTestCase {
    func testPreferencesPersistAcrossInstances() {
        let suiteName = "MouseLensTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let firstStore = AppPreferencesStore(defaults: defaults)
        firstStore.countdownSeconds = 1
        firstStore.hideWindowBeforeCapture = false
        firstStore.defaultMicrophoneEnabled = false
        firstStore.defaultSystemAudioEnabled = true
        firstStore.defaultAspectRatio = .portrait
        firstStore.autoRevealExportInFinder = true

        let secondStore = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(secondStore.countdownSeconds, 1)
        XCTAssertFalse(secondStore.hideWindowBeforeCapture)
        XCTAssertFalse(secondStore.defaultMicrophoneEnabled)
        XCTAssertTrue(secondStore.defaultSystemAudioEnabled)
        XCTAssertEqual(secondStore.defaultAspectRatio, .portrait)
        XCTAssertTrue(secondStore.autoRevealExportInFinder)
    }
}
