import AppKit
import AVFoundation
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum PermissionStatus: String {
    case granted
    case requiresRelaunch
    case denied
    case unknown

    var isGranted: Bool {
        self == .granted
    }
}

struct AppPermissions: Equatable {
    let screenRecording: PermissionStatus
    let microphone: PermissionStatus
    let accessibility: PermissionStatus

    static let unknown = AppPermissions(
        screenRecording: .unknown,
        microphone: .unknown,
        accessibility: .unknown
    )

    func recordingReady(requiresMicrophone: Bool) -> Bool {
        screenRecording == .granted && (!requiresMicrophone || microphone == .granted)
    }

    var needsScreenRecordingRelaunch: Bool {
        screenRecording == .requiresRelaunch
    }
}

@MainActor
final class PermissionManager {
    private var screenRecordingPromptedThisLaunch = false
    private var screenRecordingCaptureAttemptedThisLaunch = false

    func currentPermissions() -> AppPermissions {
        AppPermissions(
            screenRecording: screenRecordingStatus(),
            microphone: microphoneStatus(),
            accessibility: AXIsProcessTrusted() ? .granted : .unknown
        )
    }

    func requestMissingPermissions(includeMicrophone: Bool, includeAccessibility: Bool) async {
        if !CGPreflightScreenCaptureAccess() {
            screenRecordingPromptedThisLaunch = true
            _ = CGRequestScreenCaptureAccess()
        }

        if includeMicrophone && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        if includeAccessibility && !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    func markScreenRecordingCaptureAttempt() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        screenRecordingCaptureAttemptedThisLaunch = true
    }

    private func screenRecordingStatus() -> PermissionStatus {
        if CGPreflightScreenCaptureAccess() {
            screenRecordingPromptedThisLaunch = false
            screenRecordingCaptureAttemptedThisLaunch = false
            return .granted
        }

        if screenRecordingPromptedThisLaunch || screenRecordingCaptureAttemptedThisLaunch {
            return .requiresRelaunch
        }

        return .unknown
    }

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .granted
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .unknown
        @unknown default:
            .unknown
        }
    }
}

struct Logger {
    func log(_ message: String) {
        print("[MouseLens] \(message)")
    }
}

@MainActor
final class AppWindowController {
    private var hiddenForCapture = false

    func prepareForCapture() async {
        guard !hiddenForCapture else { return }
        hiddenForCapture = true

        let app = NSApplication.shared
        app.windows.forEach { $0.orderOut(nil) }
        app.hide(nil)

        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    func restoreAfterCapture() {
        guard hiddenForCapture else { return }
        hiddenForCapture = false

        let app = NSApplication.shared
        app.unhide(nil)
        app.activate(ignoringOtherApps: true)
        app.windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }

    func activateAppWindow() {
        let app = NSApplication.shared
        app.unhide(nil)
        app.activate(ignoringOtherApps: true)
        app.windows.forEach { window in
            guard window.canBecomeKey else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }
}

final class HotkeyManager {
    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32
        let displayLabel: String
    }

    let toggleShortcut = Shortcut(
        keyCode: UInt32(kVK_ANSI_2),
        modifiers: UInt32(cmdKey) | UInt32(shiftKey),
        displayLabel: "⌘⇧2"
    )

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var onToggleRecording: (() -> Void)?

    init() {
        registerDefaults()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func registerDefaults() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyCallback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        var hotKeyID = EventHotKeyID(signature: OSType(0x4D4C4854), id: 1)
        RegisterEventHotKey(
            toggleShortcut.keyCode,
            toggleShortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func setToggleHandler(_ handler: (() -> Void)?) {
        onToggleRecording = handler
    }

    private nonisolated func handleHotKeyPressed(_ event: EventRef?) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.id == 1 else {
            return noErr
        }

        Task { @MainActor [weak self] in
            self?.onToggleRecording?()
        }
        return noErr
    }

    private static let hotKeyCallback: EventHandlerUPP = { _, event, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleHotKeyPressed(event)
    }
}
