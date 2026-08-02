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
    let camera: PermissionStatus

    static let unknown = AppPermissions(
        screenRecording: .unknown,
        microphone: .unknown,
        accessibility: .unknown,
        camera: .unknown
    )

    func recordingReady(requiresMicrophone: Bool) -> Bool {
        recordingReady(requiresMicrophone: requiresMicrophone, requiresPresenterCamera: false)
    }

    func recordingReady(requiresMicrophone: Bool, requiresPresenterCamera: Bool) -> Bool {
        screenRecording == .granted
            && (!requiresMicrophone || microphone == .granted)
            && (!requiresPresenterCamera || camera == .granted)
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
            accessibility: AXIsProcessTrusted() ? .granted : .unknown,
            camera: cameraStatus()
        )
    }

    func requestMissingPermissions(
        includeMicrophone: Bool,
        includeAccessibility: Bool,
        includeCamera: Bool = false
    ) async {
        if !CGPreflightScreenCaptureAccess() {
            screenRecordingPromptedThisLaunch = true
            _ = CGRequestScreenCaptureAccess()
        }

        if includeMicrophone && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        if includeCamera && AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }

        if includeAccessibility && !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    func requestCameraAccessIfNeeded() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    func cameraPermissionGranted() -> Bool {
        cameraStatus() == .granted
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

    private func cameraStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
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
final class AppWindowController: NSObject {
    static let captureSetupContentSize = NSSize(width: 1120, height: 96)
    static let captureToolbarCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary
    ]

    private var hiddenForCapture = false
    private weak var appWindow: NSWindow?
    private var captureSetupPanel: NSPanel?
    private var recordingControlPanel: NSPanel?
    private var presenterBubblePanel: NSPanel?
    private var recordingNotesPanel: NSPanel?
    private var presenterBubbleTrackingFrame: NSRect?
    private var presenterBubblePanelStyle: PresenterBubbleStyle?
    private var presenterBubbleMoveHandler: ((NormalizedPoint) -> Void)?
    private var appWindowResizeObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var activeApplicationObserver: NSObjectProtocol?
    private var showsZoomButtonForAppWindow = false
    private var allowsBackgroundDraggingForAppWindow = true
    var onCaptureSetupPanelDismissed: (() -> Void)?

    override init() {
        super.init()
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        activeSpaceObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshOverlayWindowsForCurrentSpace()
            }
        }
        activeApplicationObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshOverlayWindowsForCurrentSpace()
            }
        }
    }

    deinit {
        if let appWindowResizeObserver {
            NotificationCenter.default.removeObserver(appWindowResizeObserver)
        }
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
        if let activeApplicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeApplicationObserver)
        }
    }

    func attachAppWindow(_ window: NSWindow) {
        if appWindow !== window {
            observeAppWindowResize(window)
        }
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
            exitsZoomedState: true,
            animatesResize: false
        )
        controlledWindows.forEach { window in
            configureCaptureToolbarSpaceBehavior(window)
            positionCaptureToolbarOnActiveScreen(window)
        }
    }

    func applyEditorWindowLayout() {
        showsZoomButtonForAppWindow = true
        allowsBackgroundDraggingForAppWindow = false
        controlledWindows.forEach(configureStandardSpaceBehavior)
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
            exitsZoomedState: false,
            animatesResize: true
        )
    }

    func maximizeEditorWindowOnActiveScreen() {
        controlledWindows.forEach { window in
            configureStandardSpaceBehavior(window)
            let visibleFrame = window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let targetFrame = Self.editorPresentationFrame(visibleFrame: visibleFrame)
            guard !NSEqualRects(window.frame, targetFrame) else { return }
            window.setFrame(targetFrame, display: true, animate: true)
        }
    }

    static func editorPresentationFrame(visibleFrame: NSRect) -> NSRect {
        visibleFrame
    }

    func prepareForCapture() async {
        guard !hiddenForCapture else { return }
        hiddenForCapture = true

        let app = NSApplication.shared
        app.windows.forEach { window in
            guard !isRecordingControlPanel(window) else { return }
            guard !isPresenterBubblePanel(window) else { return }
            guard !isRecordingNotesPanel(window) else { return }
            window.orderOut(nil)
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    func restoreAfterCapture(activate: Bool = true) {
        hideRecordingControlPanel()
        hideRecordingNotesPanel()

        guard hiddenForCapture else { return }
        hiddenForCapture = false

        let app = NSApplication.shared
        app.unhide(nil)
        guard activate else { return }
        activateAppWindow(forceAppActivation: true)
    }

    func activateAppWindow(forceAppActivation: Bool = false) {
        hideCaptureSetupPanel()
        let app = NSApplication.shared
        app.unhide(nil)

        if let appWindow, appWindow.canBecomeKey {
            if isCaptureToolbarWindow(appWindow) {
                configureCaptureToolbarSpaceBehavior(appWindow)
                positionCaptureToolbarOnActiveScreen(appWindow)
                appWindow.orderFrontRegardless()
            } else {
                appWindow.makeKeyAndOrderFront(nil)
            }
            if forceAppActivation {
                app.activate(ignoringOtherApps: true)
            }
            return
        }

        if forceAppActivation {
            app.activate(ignoringOtherApps: true)
        }
        app.windows.forEach { window in
            guard !isRecordingControlPanel(window) else { return }
            guard !isRecordingNotesPanel(window) else { return }
            guard window.canBecomeKey else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showCaptureSetupPanel<Content: View>(@ViewBuilder content: () -> Content) {
        let panel = captureSetupPanel ?? makeCaptureSetupPanel()
        panel.contentViewController = NSHostingController(
            rootView: content()
                .frame(
                    width: Self.captureSetupContentSize.width,
                    height: Self.captureSetupContentSize.height
                )
                .background(AppTheme.windowBackground)
        )
        captureSetupPanel = panel

        if appWindow?.isMiniaturized == true {
            appWindow?.deminiaturize(nil)
        }
        appWindow?.orderOut(nil)
        Self.prepareCaptureSetupPanelForDisplay(panel)
        configureCaptureToolbarSpaceBehavior(panel)
        positionCaptureToolbarOnActiveScreen(panel)
        NSApplication.shared.unhide(nil)
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else { return }
            self.positionCaptureToolbarOnActiveScreen(panel)
        }
    }

    func hideCaptureSetupPanel() {
        captureSetupPanel?.orderOut(nil)
    }

    var isCaptureSetupPanelVisible: Bool {
        captureSetupPanel?.isVisible == true
    }

    func dismissFloatingCaptureToolbar() {
        captureSetupPanel?.orderOut(nil)
        if let appWindow, isCaptureToolbarWindow(appWindow) {
            appWindow.orderOut(nil)
        }
        onCaptureSetupPanelDismissed?()
        NSApplication.shared.hide(nil)
    }

    func hidePrimaryWindowForFloatingHomeToolbar() {
        guard let appWindow else { return }
        configureStandardSpaceBehavior(appWindow)
        appWindow.orderOut(nil)
    }

    func showRecordingControlPanel<Content: View>(
        contentSize: NSSize = NSSize(width: 360, height: 58),
        @ViewBuilder content: () -> Content
    ) {
        let panel = recordingControlPanel ?? makeRecordingControlPanel()
        panel.contentViewController = NSHostingController(
            rootView: content()
                .frame(width: contentSize.width, height: contentSize.height)
        )
        recordingControlPanel = panel

        positionRecordingControlPanel(panel, panelSize: contentSize)
        if !hiddenForCapture {
            NSApplication.shared.unhide(nil)
        }
        panel.orderFrontRegardless()
    }

    func hideRecordingControlPanel() {
        recordingControlPanel?.orderOut(nil)
    }

    func showRecordingNotesPanel<Content: View>(
        contentSize: NSSize = NSSize(width: 420, height: 132),
        @ViewBuilder content: () -> Content
    ) {
        let panel = recordingNotesPanel ?? makeRecordingNotesPanel()
        panel.contentViewController = NSHostingController(
            rootView: content()
                .frame(width: contentSize.width, height: contentSize.height)
        )
        panel.setContentSize(contentSize)
        recordingNotesPanel = panel

        configureCaptureToolbarSpaceBehavior(panel)
        positionRecordingNotesPanel(panel, panelSize: contentSize)
        if !hiddenForCapture {
            NSApplication.shared.unhide(nil)
        }
        panel.orderFrontRegardless()
    }

    func hideRecordingNotesPanel() {
        recordingNotesPanel?.orderOut(nil)
    }

    func showPresenterBubblePanel<Content: View>(
        style: PresenterBubbleStyle,
        trackingFrame: NSRect? = nil,
        @ViewBuilder content: () -> Content,
        onMove: @escaping (NormalizedPoint) -> Void
    ) {
        let panel = presenterBubblePanel ?? makePresenterBubblePanel()
        let hadVisiblePanel = panel.isVisible
        let previousTrackingFrame = presenterBubbleTrackingFrame
        let size = presenterBubblePanelSize(for: style)
        let shouldReuseContent = Self.shouldReusePresenterBubblePanelContent(
            isVisible: hadVisiblePanel,
            previousStyle: presenterBubblePanelStyle,
            newStyle: style,
            previousTrackingFrame: previousTrackingFrame,
            newTrackingFrame: trackingFrame
        )
        if !shouldReuseContent {
            panel.contentViewController = NSHostingController(
                rootView: content()
                    .frame(width: size.width, height: size.height)
            )
            panel.setContentSize(size)
        }
        presenterBubbleTrackingFrame = trackingFrame
        presenterBubblePanelStyle = style
        presenterBubbleMoveHandler = onMove
        presenterBubblePanel = panel
        configureCaptureToolbarSpaceBehavior(panel)
        if hadVisiblePanel, previousTrackingFrame != trackingFrame {
            notifyPresenterBubblePanelMoved(panel)
        } else if !hadVisiblePanel || !shouldReuseContent {
            positionPresenterBubblePanel(panel, style: style)
        }
        if !hadVisiblePanel {
            panel.orderFrontRegardless()
        }
    }

    func hidePresenterBubblePanel() {
        presenterBubblePanel?.orderOut(nil)
        presenterBubbleTrackingFrame = nil
        presenterBubblePanelStyle = nil
    }

    private func configureAppWindows(
        contentSize: NSSize,
        minContentSize: NSSize,
        maxContentSize: NSSize,
        allowsBackgroundDragging: Bool,
        showsZoomButton: Bool,
        preservesLargerContentSize: Bool,
        exitsZoomedState: Bool,
        animatesResize: Bool
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
                for: window,
                animate: animatesResize
            )
        }
    }

    private var controlledWindows: [NSWindow] {
        if let appWindow {
            return [appWindow]
        }

        return NSApplication.shared.windows.filter { window in
            !isRecordingControlPanel(window) &&
                !isCaptureSetupPanel(window) &&
                !isPresenterBubblePanel(window) &&
                !isRecordingNotesPanel(window) &&
                window.canBecomeKey &&
                !window.isSheet
        }
    }

    private func setContentSizePreservingTopLeft(
        _ contentSize: NSSize,
        for window: NSWindow,
        animate: Bool
    ) {
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

        window.setFrame(adjustedFrame, display: true, animate: animate)
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
        panel.collectionBehavior = Self.captureToolbarCollectionBehavior
        panel.canHide = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.level = .statusBar
        panel.sharingType = .none
        return panel
    }

    private func makePresenterBubblePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 164, height: 164),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = Self.captureToolbarCollectionBehavior
        panel.canHide = false
        panel.delegate = self
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.sharingType = .none
        return panel
    }

    private func makeRecordingNotesPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 132),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = Self.captureToolbarCollectionBehavior
        panel.canHide = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.sharingType = .none
        return panel
    }

    private func makeCaptureSetupPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.captureSetupContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = Self.captureToolbarCollectionBehavior
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.sharingType = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.delegate = self
        panel.standardWindowButton(.closeButton)?.target = self
        panel.standardWindowButton(.closeButton)?.action = #selector(handleCaptureSetupPanelCloseButton(_:))
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        return panel
    }

    static func prepareCaptureSetupPanelForDisplay(_ panel: NSPanel) {
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        panel.setContentSize(captureSetupContentSize)
    }

    private func positionRecordingControlPanel(
        _ panel: NSPanel,
        panelSize: NSSize = NSSize(width: 360, height: 58)
    ) {
        let screenFrame = preferredOverlayVisibleFrame()
        let origin = NSPoint(
            x: screenFrame.midX - (panelSize.width / 2),
            y: screenFrame.maxY - panelSize.height - 18
        )

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func positionRecordingNotesPanel(
        _ panel: NSPanel,
        panelSize: NSSize = NSSize(width: 420, height: 132)
    ) {
        let screenFrame = preferredOverlayVisibleFrame()
        let origin = NSPoint(
            x: screenFrame.midX - (panelSize.width / 2),
            y: screenFrame.maxY - panelSize.height - 94
        )

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func presenterBubblePanelSize(for style: PresenterBubbleStyle) -> NSSize {
        let visibleFrame = preferredOverlayVisibleFrame()
        let shortestSide = min(visibleFrame.width, visibleFrame.height)
        let side = (shortestSide * CGFloat(style.normalizedSize)).clamped(to: 96...260)
        return NSSize(width: side, height: side)
    }

    private func positionPresenterBubblePanel(_ panel: NSPanel, style: PresenterBubbleStyle) {
        let visibleFrame = presenterBubbleReferenceFrame()
        let size = panel.frame.size
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let center = NSPoint(
            x: (visibleFrame.minX + visibleFrame.width * CGFloat(style.normalizedCenter.x))
                .clamped(to: (visibleFrame.minX + halfWidth)...(visibleFrame.maxX - halfWidth)),
            y: (visibleFrame.minY + visibleFrame.height * (1 - CGFloat(style.normalizedCenter.y)))
                .clamped(to: (visibleFrame.minY + halfHeight)...(visibleFrame.maxY - halfHeight))
        )
        panel.setFrameOrigin(NSPoint(x: center.x - halfWidth, y: center.y - halfHeight))
    }

    private func configureCaptureToolbarSpaceBehavior(_ window: NSWindow) {
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.collectionBehavior.formUnion(Self.captureToolbarCollectionBehavior)
        window.level = .statusBar
        window.sharingType = .none
        window.hidesOnDeactivate = false
    }

    private func configureStandardSpaceBehavior(_ window: NSWindow) {
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.remove(.stationary)
        window.collectionBehavior.remove(.canJoinAllSpaces)
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.level = .normal
    }

    private func positionCaptureToolbarOnActiveScreen(_ window: NSWindow) {
        let visibleFrame = preferredOverlayVisibleFrame()
        let origin = Self.captureToolbarOrigin(
            toolbarSize: window.frame.size,
            visibleFrame: visibleFrame
        )
        window.setFrameOrigin(origin)
    }

    private func preferredOverlayVisibleFrame() -> NSRect {
        activeScreen.visibleFrame
    }

    private func refreshOverlayWindowsForCurrentSpace() {
        if let panel = recordingControlPanel, panel.isVisible {
            positionRecordingControlPanel(panel, panelSize: panel.contentLayoutRect.size)
        }

        if let panel = recordingNotesPanel, panel.isVisible {
            positionRecordingNotesPanel(panel, panelSize: panel.contentLayoutRect.size)
        }

        if let panel = captureSetupPanel, panel.isVisible {
            positionCaptureToolbarOnActiveScreen(panel)
        }

        if let panel = presenterBubblePanel, panel.isVisible {
            notifyPresenterBubblePanelMoved(panel)
        }

        guard
            !hiddenForCapture,
            let appWindow,
            appWindow.isVisible,
            isCaptureToolbarWindow(appWindow)
        else {
            return
        }

        configureCaptureToolbarSpaceBehavior(appWindow)
        positionCaptureToolbarOnActiveScreen(appWindow)
    }

    static func captureToolbarOrigin(
        toolbarSize: NSSize,
        visibleFrame: NSRect,
        bottomMargin: CGFloat = 45
    ) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - (toolbarSize.width / 2),
            y: visibleFrame.minY + bottomMargin
        )
    }

    static func presenterBubbleNormalizedCenter(
        panelFrame: NSRect,
        visibleFrame: NSRect,
        edgeTolerance: CGFloat? = nil
    ) -> NormalizedPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }

        let edgeSnapTolerance = edgeTolerance ?? presenterBubbleEdgeSnapTolerance(for: panelFrame.size)
        let normalizedX: Double
        if panelFrame.minX <= visibleFrame.minX + edgeSnapTolerance {
            normalizedX = 0
        } else if panelFrame.maxX >= visibleFrame.maxX - edgeSnapTolerance {
            normalizedX = 1
        } else {
            normalizedX = Double(((panelFrame.midX - visibleFrame.minX) / visibleFrame.width).clamped(to: 0...1))
        }

        let normalizedY: Double
        if panelFrame.maxY >= visibleFrame.maxY - edgeSnapTolerance {
            normalizedY = 0
        } else if panelFrame.minY <= visibleFrame.minY + edgeSnapTolerance {
            normalizedY = 1
        } else {
            normalizedY = Double((1 - ((panelFrame.midY - visibleFrame.minY) / visibleFrame.height)).clamped(to: 0...1))
        }

        return NormalizedPoint(x: normalizedX, y: normalizedY)
    }

    private static func presenterBubbleEdgeSnapTolerance(for panelSize: NSSize) -> CGFloat {
        let shortestSide = min(panelSize.width, panelSize.height)
        return max(24, min(shortestSide * 1.15, 220))
    }

    static func shouldReusePresenterBubblePanelContent(
        isVisible: Bool,
        previousStyle: PresenterBubbleStyle?,
        newStyle: PresenterBubbleStyle,
        previousTrackingFrame: NSRect?,
        newTrackingFrame: NSRect?
    ) -> Bool {
        isVisible
            && previousStyle == newStyle
            && previousTrackingFrame == newTrackingFrame
    }

    private func observeAppWindowResize(_ window: NSWindow) {
        if let appWindowResizeObserver {
            NotificationCenter.default.removeObserver(appWindowResizeObserver)
        }

        appWindowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, let window, self.appWindow === window else { return }
                guard self.isCaptureToolbarWindow(window) else { return }
                self.positionCaptureToolbarOnActiveScreen(window)
            }
        }
    }

    private var activeScreen: NSScreen {
        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointerLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func isCaptureToolbarWindow(_ window: NSWindow) -> Bool {
        !showsZoomButtonForAppWindow && window.contentLayoutRect.height <= 120
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

    private func isCaptureSetupPanel(_ window: NSWindow) -> Bool {
        guard let captureSetupPanel else { return false }
        return window === captureSetupPanel
    }

    private func isPresenterBubblePanel(_ window: NSWindow) -> Bool {
        guard let presenterBubblePanel else { return false }
        return window === presenterBubblePanel
    }

    private func isRecordingNotesPanel(_ window: NSWindow) -> Bool {
        guard let recordingNotesPanel else { return false }
        return window === recordingNotesPanel
    }

    private func notifyPresenterBubblePanelMoved(_ panel: NSWindow) {
        let visibleFrame = presenterBubbleReferenceFrame()
        presenterBubbleMoveHandler?(
            Self.presenterBubbleNormalizedCenter(
                panelFrame: panel.frame,
                visibleFrame: visibleFrame
            )
        )
    }

    private func presenterBubbleReferenceFrame() -> NSRect {
        guard
            let trackingFrame = presenterBubbleTrackingFrame,
            trackingFrame.width > 0,
            trackingFrame.height > 0
        else {
            return preferredOverlayVisibleFrame()
        }

        return trackingFrame
    }

    @objc private func handleCaptureSetupPanelCloseButton(_ sender: Any?) {
        dismissFloatingCaptureToolbar()
    }
}

extension AppWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === captureSetupPanel else { return true }
        dismissFloatingCaptureToolbar()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === presenterBubblePanel else { return }
        notifyPresenterBubblePanelMoved(panel)
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
