import AppKit
import AVFoundation
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import SwiftUI

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
    private weak var appWindow: NSWindow?
    private var recordingControlPanel: NSPanel?
    private var showsZoomButtonForAppWindow = false
    private var allowsBackgroundDraggingForAppWindow = true

    func attachAppWindow(_ window: NSWindow) {
        appWindow = window
        configureStandardWindowButtons(
            for: window,
            allowsBackgroundDragging: allowsBackgroundDraggingForAppWindow,
            showsZoomButton: showsZoomButtonForAppWindow
        )
    }

    func applyHomeToolbarWindowLayout() {
        showsZoomButtonForAppWindow = false
        allowsBackgroundDraggingForAppWindow = true
        configureAppWindows(
            contentSize: NSSize(width: 1120, height: 96),
            minContentSize: NSSize(width: 1120, height: 96),
            maxContentSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: 96),
            allowsBackgroundDragging: true,
            showsZoomButton: false,
            preservesLargerContentSize: false,
            exitsZoomedState: true
        )
    }

    func applyEditorWindowLayout() {
        showsZoomButtonForAppWindow = true
        allowsBackgroundDraggingForAppWindow = false
        configureAppWindows(
            contentSize: NSSize(width: 1120, height: 720),
            minContentSize: NSSize(width: 1120, height: 720),
            maxContentSize: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            allowsBackgroundDragging: false,
            showsZoomButton: true,
            preservesLargerContentSize: true,
            exitsZoomedState: false
        )
    }

    func prepareForCapture() async {
        guard !hiddenForCapture else { return }
        hiddenForCapture = true

        let app = NSApplication.shared
        app.windows.forEach { window in
            guard !isRecordingControlPanel(window) else { return }
            window.orderOut(nil)
        }
        app.hide(nil)

        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    func restoreAfterCapture() {
        hideRecordingControlPanel()

        guard hiddenForCapture else { return }
        hiddenForCapture = false

        let app = NSApplication.shared
        app.unhide(nil)
        app.activate(ignoringOtherApps: true)
        activateAppWindow()
    }

    func activateAppWindow() {
        let app = NSApplication.shared
        app.unhide(nil)
        app.activate(ignoringOtherApps: true)

        if let appWindow, appWindow.canBecomeKey {
            appWindow.makeKeyAndOrderFront(nil)
            return
        }

        app.windows.forEach { window in
            guard !isRecordingControlPanel(window) else { return }
            guard window.canBecomeKey else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showRecordingControlPanel<Content: View>(@ViewBuilder content: () -> Content) {
        let panel = recordingControlPanel ?? makeRecordingControlPanel()
        panel.contentViewController = NSHostingController(rootView: content())
        recordingControlPanel = panel

        positionRecordingControlPanel(panel)
        if !hiddenForCapture {
            NSApplication.shared.unhide(nil)
        }
        panel.orderFrontRegardless()
    }

    func hideRecordingControlPanel() {
        recordingControlPanel?.orderOut(nil)
    }

    private func configureAppWindows(
        contentSize: NSSize,
        minContentSize: NSSize,
        maxContentSize: NSSize,
        allowsBackgroundDragging: Bool,
        showsZoomButton: Bool,
        preservesLargerContentSize: Bool,
        exitsZoomedState: Bool
    ) {
        controlledWindows.forEach { window in
            configureStandardWindowButtons(
                for: window,
                allowsBackgroundDragging: allowsBackgroundDragging,
                showsZoomButton: showsZoomButton
            )
            window.contentMinSize = minContentSize
            window.contentMaxSize = maxContentSize

            if exitsZoomedState, window.isZoomed {
                window.zoom(nil)
            }

            let currentContentSize = window.contentLayoutRect.size
            let proposedWidth = preservesLargerContentSize
                ? max(currentContentSize.width, contentSize.width)
                : contentSize.width
            let proposedHeight = preservesLargerContentSize
                ? max(currentContentSize.height, contentSize.height)
                : contentSize.height
            let targetWidth = min(max(proposedWidth, minContentSize.width), maxContentSize.width)
            let targetHeight = min(max(proposedHeight, minContentSize.height), maxContentSize.height)
            setContentSizePreservingTopLeft(
                NSSize(width: targetWidth, height: targetHeight),
                for: window
            )
        }
    }

    private var controlledWindows: [NSWindow] {
        if let appWindow {
            return [appWindow]
        }

        return NSApplication.shared.windows.filter { window in
            !isRecordingControlPanel(window) && window.canBecomeKey && !window.isSheet
        }
    }

    private func setContentSizePreservingTopLeft(_ contentSize: NSSize, for window: NSWindow) {
        let currentFrame = window.frame
        let currentContentSize = window.contentLayoutRect.size
        var adjustedFrame = currentFrame

        if abs(currentContentSize.width - contentSize.width) > 0.5 ||
            abs(currentContentSize.height - contentSize.height) > 0.5 {
            let topY = currentFrame.maxY
            let targetFrame = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: contentSize)
            )
            adjustedFrame.size = targetFrame.size
            adjustedFrame.origin.y = topY - targetFrame.height
        }

        adjustedFrame = constrainedFrame(adjustedFrame, for: window)
        guard !NSEqualRects(adjustedFrame, currentFrame) else { return }

        window.setFrame(adjustedFrame, display: true, animate: true)
    }

    private func constrainedFrame(_ frame: NSRect, for window: NSWindow) -> NSRect {
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var constrained = frame
        constrained.size.width = min(constrained.width, visibleFrame.width)
        constrained.size.height = min(constrained.height, visibleFrame.height)

        if constrained.maxX > visibleFrame.maxX {
            constrained.origin.x = visibleFrame.maxX - constrained.width
        }
        if constrained.minX < visibleFrame.minX {
            constrained.origin.x = visibleFrame.minX
        }
        if constrained.maxY > visibleFrame.maxY {
            constrained.origin.y = visibleFrame.maxY - constrained.height
        }
        if constrained.minY < visibleFrame.minY {
            constrained.origin.y = visibleFrame.minY
        }

        return constrained
    }

    private func makeRecordingControlPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.canHide = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.level = .statusBar
        panel.sharingType = .none
        return panel
    }

    private func positionRecordingControlPanel(_ panel: NSPanel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = NSSize(width: 360, height: 58)
        let origin = NSPoint(
            x: screenFrame.midX - (panelSize.width / 2),
            y: screenFrame.maxY - panelSize.height - 18
        )

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func configureStandardWindowButtons(
        for window: NSWindow,
        allowsBackgroundDragging: Bool,
        showsZoomButton: Bool
    ) {
        window.standardWindowButton(.zoomButton)?.isHidden = !showsZoomButton
        window.standardWindowButton(.zoomButton)?.isEnabled = showsZoomButton
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.isMovableByWindowBackground = allowsBackgroundDragging
        window.collectionBehavior.remove(.fullScreenPrimary)
    }

    private func isRecordingControlPanel(_ window: NSWindow) -> Bool {
        guard let recordingControlPanel else { return false }
        return window === recordingControlPanel
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

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4C4854), id: 1)
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
