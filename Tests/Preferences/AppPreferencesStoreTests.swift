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
        firstStore.defaultPresenterCameraEnabled = true
        firstStore.defaultCaptureTarget = .window
        firstStore.defaultAspectRatio = .portrait
        firstStore.appLanguage = .simplifiedChinese
        firstStore.autoRevealExportInFinder = true

        let secondStore = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(secondStore.countdownSeconds, 1)
        XCTAssertFalse(secondStore.hideWindowBeforeCapture)
        XCTAssertFalse(secondStore.defaultMicrophoneEnabled)
        XCTAssertTrue(secondStore.defaultSystemAudioEnabled)
        XCTAssertTrue(secondStore.defaultPresenterCameraEnabled)
        XCTAssertEqual(secondStore.defaultCaptureTarget, .window)
        XCTAssertEqual(secondStore.defaultAspectRatio, .portrait)
        XCTAssertEqual(secondStore.appLanguage, .simplifiedChinese)
        XCTAssertTrue(secondStore.autoRevealExportInFinder)
    }

    func testAppLanguageDefaultsToSystem() {
        let suiteName = "MouseLensTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.appLanguage, .system)
        XCTAssertNil(store.appLanguage.localeIdentifier)
    }
}
