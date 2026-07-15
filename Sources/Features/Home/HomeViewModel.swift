import AppKit
import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    enum WindowTargetSelectionPolicy {
        case preserveSelection
        case preferCurrentWindow
    }

    @Published var selectedCaptureTarget: CaptureTarget = .screen {
        didSet {
            if !isApplyingDefaults {
                environment.preferencesStore.defaultCaptureTarget = selectedCaptureTarget
            }
            if selectedCaptureTarget == .window {
                scheduleWindowTargetRefresh(delayNanoseconds: 0)
            } else {
                cancelScheduledWindowTargetRefresh(invalidateRequests: true)
            }
        }
    }
    @Published var includeMicrophone = true {
        didSet {
            guard !isApplyingDefaults else { return }
            environment.preferencesStore.defaultMicrophoneEnabled = includeMicrophone
        }
    }
    @Published var includeSystemAudio = false {
        didSet {
            guard !isApplyingDefaults else { return }
            environment.preferencesStore.defaultSystemAudioEnabled = includeSystemAudio
        }
    }
    @Published var includePresenterCamera = false {
        didSet {
            guard !isApplyingDefaults else { return }
            environment.preferencesStore.defaultPresenterCameraEnabled = includePresenterCamera
        }
    }
    @Published var selectedAspectRatio: ProjectAspectRatio = .landscape {
        didSet {
            guard !isApplyingDefaults else { return }
            environment.preferencesStore.defaultAspectRatio = selectedAspectRatio
        }
    }
    @Published var permissions = AppPermissions.unknown
    @Published var recentProjects: [RecordingProject] = []
    @Published var recordingState: RecordingState = .idle
    @Published var showingPermissions = false
    @Published var statusMessage = "Record a screen demo and let MouseLens build the camera motion."
    @Published var selectedWindowTargetID: UInt32?
    @Published private(set) var availableWindowTargets: [CaptureWindowOption] = []
    @Published private(set) var isRefreshingWindowTargets = false
    @Published private(set) var completedProject: RecordingProject?

    private let environment: AppEnvironment
    private var countdownTask: Task<Void, Never>?
    private var windowTargetRefreshTask: Task<Void, Never>?
    private var windowTargetRefreshGeneration = 0
    private var loadingWindowTargetRefreshGeneration: Int?
    private var isApplyingDefaults = false
    private var presenterCameraRecordingStarted = false
    private var cancellables: Set<AnyCancellable> = []

    var permissionManager: PermissionManager {
        environment.permissionManager
    }

    var recordingShortcutHint: String {
        environment.hotkeyManager.toggleShortcut.displayLabel
    }

    var isCanonicalLocalTestApp: Bool {
        environment.runtimeInfo.isCanonicalLocalTestApp
    }

    var runtimeBundlePath: String {
        environment.runtimeInfo.displayBundlePath
    }

    var menuBarPrimaryActionTitle: String {
        switch recordingState {
        case .idle:
            return selectedCaptureTarget == .screen ? "Record Screen" : "Record Window"
        case .countdown:
            return "Cancel Countdown"
        case .recording(let session):
            return session.isPaused ? "Finish Recording (Paused)" : "Finish Recording"
        }
    }

    var isRecordingActionDisabled: Bool {
        guard case .idle = recordingState else { return false }
        return permissions.needsScreenRecordingRelaunch || Self.isWindowRecordingUnavailable(
            captureTarget: selectedCaptureTarget,
            selectedWindowTargetID: selectedWindowTargetID
        )
    }

    var captureConfigurationSummary: String {
        let audioParts = [
            includeMicrophone ? "Mic" : nil,
            includeSystemAudio ? "System Audio" : nil
        ].compactMap { $0 }
        let audioSummary = audioParts.isEmpty ? "No Audio" : audioParts.joined(separator: " + ")
        return "\(selectedCaptureTarget.label) · \(selectedAspectRatio.label) · \(audioSummary)"
    }

    var selectedWindowTarget: CaptureWindowOption? {
        availableWindowTargets.first { $0.id == selectedWindowTargetID }
    }

    var selectedWindowTargetLabel: String {
        if isRefreshingWindowTargets {
            return "Loading Windows"
        }

        return selectedWindowTarget?.compactLabel ?? "No Window in This Space"
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        applyPreferences()
        bindPreferences()
        bindWorkspaceNotifications()
        refreshPermissions()
        loadRecentProjects()

        environment.hotkeyManager.setToggleHandler { [weak self] in
            guard let self else { return }
            Task { await self.handleRecordingToggleHotkey() }
        }
    }

    deinit {
        countdownTask?.cancel()
        windowTargetRefreshTask?.cancel()
        environment.hotkeyManager.setToggleHandler(nil)
    }

    func refreshPermissions() {
        permissions = environment.permissionManager.currentPermissions()
    }

    func loadRecentProjects() {
        recentProjects = (try? environment.projectStore.loadRecentProjects(limit: 6)) ?? []
    }

    func requestPermissions() async {
        await environment.permissionManager.requestMissingPermissions(
            includeMicrophone: includeMicrophone,
            includeAccessibility: false,
            includeCamera: includePresenterCamera
        )
        refreshPermissions()
    }

    func startRecording() async {
        guard recordingState == .idle else { return }

        refreshPermissions()
        guard canStartRecording else {
            if permissions.needsScreenRecordingRelaunch {
                statusMessage = "Screen Recording is enabled, but MouseLens must be quit and reopened before macOS will allow capture."
            }
            showingPermissions = true
            return
        }

        if selectedCaptureTarget == .window {
            cancelScheduledWindowTargetRefresh(invalidateRequests: false)
            await refreshWindowTargets(
                policy: Self.windowTargetRefreshPolicyForRecording(
                    selectedWindowTargetID: selectedWindowTargetID
                ),
                showsLoadingState: false
            )
            guard selectedWindowTargetID != nil else {
                statusMessage = "No Window in This Space. Switch to a Space with a recordable window, then try again."
                return
            }
        }

        await beginCountdown()
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil

        guard case .countdown = recordingState else { return }
        recordingState = .idle
        environment.windowController.restoreAfterCapture()
        statusMessage = "Recording countdown cancelled."
    }

    func stopRecording() async {
        countdownTask?.cancel()
        countdownTask = nil

        guard case .recording = recordingState else { return }

        do {
            let session = try await environment.screenRecorder.stop()
            let presenterMedia = await stopPresenterCameraIfNeeded()
            let events = environment.eventMonitor.stop()
            let timeAlignedEvents = alignEventTimeline(events, with: session)
            let normalizedEvents = normalize(events: timeAlignedEvents, for: session)
            let keyframes = environment.cameraPlanEngine.makePlan(
                from: normalizedEvents,
                baseZoom: 1.0,
                followStrength: 0.72,
                clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
            )

            let style = ProjectStyle(
                aspectRatio: selectedAspectRatio,
                background: .ocean,
                cornerRadius: 10.35,
                shadowRadius: 0,
                followStrength: 0.72,
                clickEmphasis: 0.54,
                padding: 0.04,
                presenterBubbleStyle: Self.defaultPresenterBubbleStyle(
                    isEnabled: presenterMedia?.sourceVideoURL != nil
                )
            )

            let project = try environment.projectStore.createProject(
                from: session,
                rawEvents: events,
                events: normalizedEvents,
                keyframes: keyframes,
                style: style,
                presenterMedia: presenterMedia
            )

            loadRecentProjects()
            if normalizedEvents.isEmpty {
                statusMessage = "Project created, but MouseLens did not capture pointer events for this take. Reconstructed cursor motion may be unavailable."
            } else {
                statusMessage = "Project created. You can fine-tune the motion and export it now."
            }
            recordingState = .idle
            completedProject = project
        } catch {
            _ = await stopPresenterCameraIfNeeded()
            recordingState = .idle
            environment.windowController.restoreAfterCapture()
            statusMessage = "Unable to finish recording: \(error.localizedDescription)"
        }
    }

    private func alignEventTimeline(_ events: [PointerEvent], with session: CaptureSession) -> [PointerEvent] {
        guard let mediaStartedAt = session.mediaStartedAt else {
            return events
        }

        let offset = mediaStartedAt.timeIntervalSince(session.startedAt)
        guard offset > 0.0001 else {
            return events
        }

        return events.map { event in
            PointerEvent(
                id: event.id,
                timestamp: max(0, event.timestamp - offset),
                location: event.location,
                globalLocation: event.globalLocation,
                type: event.type
            )
        }
    }

    func toggleRecordingPause() {
        guard case .recording(let session) = recordingState else { return }

        if session.isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    func pauseRecording() {
        guard case .recording(let session) = recordingState, !session.isPaused else { return }

        environment.screenRecorder.pause()
        environment.eventMonitor.pause()
        recordingState = .recording(session.pausing())
        statusMessage = "Recording paused. Use the floating toolbar to resume or finish."
    }

    func resumeRecording() {
        guard case .recording(let session) = recordingState, session.isPaused else { return }

        environment.screenRecorder.resume()
        environment.eventMonitor.resume()
        recordingState = .recording(session.resuming())
        statusMessage = "Recording resumed. MouseLens is tracking pointer activity."
    }

    func consumeCompletedProject() {
        completedProject = nil
    }

    func openRecent(project: RecordingProject) -> RecordingProject {
        statusMessage = "Reopened \(project.name)."
        return project
    }

    func refreshWindowTargets(
        policy: WindowTargetSelectionPolicy = .preferCurrentWindow,
        showsLoadingState: Bool = true
    ) async {
        guard recordingState == .idle, selectedCaptureTarget == .window else { return }

        windowTargetRefreshGeneration += 1
        let generation = windowTargetRefreshGeneration
        if showsLoadingState {
            loadingWindowTargetRefreshGeneration = generation
            isRefreshingWindowTargets = true
        }
        defer {
            if loadingWindowTargetRefreshGeneration == generation {
                loadingWindowTargetRefreshGeneration = nil
                isRefreshingWindowTargets = false
            }
        }

        let previousTargets = availableWindowTargets
        let previousTargetID = selectedWindowTargetID

        do {
            let targets = try await environment.screenRecorder.availableWindowTargets()
            guard generation == windowTargetRefreshGeneration,
                  Self.shouldAutoRefreshWindowTargets(
                    captureTarget: selectedCaptureTarget,
                    recordingState: recordingState
                  ) else { return }

            availableWindowTargets = targets
            selectedWindowTargetID = Self.resolveWindowTargetID(
                from: targets,
                previousID: previousTargetID,
                policy: policy
            )

            if let selectedWindowTarget, showsLoadingState {
                statusMessage = "Window target: \(selectedWindowTarget.displayLabel)."
            } else if selectedWindowTarget == nil {
                statusMessage = "No Window in This Space. Switch to a Space with a recordable window."
            }
        } catch {
            guard generation == windowTargetRefreshGeneration,
                  Self.shouldAutoRefreshWindowTargets(
                    captureTarget: selectedCaptureTarget,
                    recordingState: recordingState
                  ) else { return }

            if policy == .preserveSelection, previousTargetID != nil {
                availableWindowTargets = previousTargets
                selectedWindowTargetID = previousTargetID
            } else {
                availableWindowTargets = []
                selectedWindowTargetID = nil
            }
            statusMessage = "Unable to list windows: \(error.localizedDescription)"
        }
    }

    func captureToolbarDidAppear() {
        scheduleWindowTargetRefresh(delayNanoseconds: 0)
    }

    func selectWindowTarget(_ target: CaptureWindowOption) {
        selectedWindowTargetID = target.id
        statusMessage = "Window target: \(target.displayLabel)."
    }

    func handleRecordingToggleHotkey() async {
        switch recordingState {
        case .idle:
            await startRecording()
        case .countdown:
            cancelCountdown()
        case .recording:
            await stopRecording()
        }
    }

    private var canStartRecording: Bool {
        permissions.recordingReady(
            requiresMicrophone: includeMicrophone,
            requiresPresenterCamera: includePresenterCamera
        )
    }

    private func beginCountdown() async {
        countdownTask?.cancel()
        completedProject = nil
        showingPermissions = false
        let countdownSeconds = environment.preferencesStore.countdownSeconds
        if countdownSeconds == 0 {
            statusMessage = "MouseLens will start recording immediately. Press \(recordingShortcutHint) to stop from anywhere."
            countdownTask = Task { [weak self] in
                await self?.startCaptureNow()
            }
            return
        }

        recordingState = .countdown(secondsRemaining: countdownSeconds)
        statusMessage = countdownStatusMessage(for: countdownSeconds)

        countdownTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            if countdownSeconds > 1 {
                for remaining in stride(from: countdownSeconds - 1, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    recordingState = .countdown(secondsRemaining: remaining)
                    statusMessage = countdownStatusMessage(for: remaining)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            guard !Task.isCancelled else { return }
            await startCaptureNow()
        }

        await Task.yield()
        await environment.windowController.prepareForCapture()
    }

    private func countdownStatusMessage(for secondsRemaining: Int) -> String {
        "Recording starts in \(secondsRemaining) second\(secondsRemaining == 1 ? "" : "s"). Press \(recordingShortcutHint) to cancel."
    }

    private func startCaptureNow() async {
        await environment.windowController.prepareForCapture()

        do {
            let configuration = ScreenRecorderConfiguration(
                target: selectedCaptureTarget,
                includeMicrophone: includeMicrophone,
                includeSystemAudio: includeSystemAudio,
                preferredWindowID: selectedCaptureTarget == .window ? selectedWindowTargetID : nil
            )
            let presenterSession = await startPresenterCameraIfAllowed()
            let session = try await environment.screenRecorder.start(configuration: configuration)
            updatePresenterCameraOffsetIfNeeded(sourceStartedAt: session.startedAt, presenterStartedAt: presenterSession?.startedAt)
            environment.eventMonitor.start(origin: session.startedAt)
            recordingState = .recording(RecordingSessionState(startedAt: session.startedAt))
            statusMessage = "Recording started. Use the floating toolbar to pause or finish."
        } catch {
            cancelPresenterCameraIfNeeded()
            environment.windowController.restoreAfterCapture()
            environment.permissionManager.markScreenRecordingCaptureAttempt()
            refreshPermissions()
            recordingState = .idle
            if permissions.needsScreenRecordingRelaunch {
                showingPermissions = true
                statusMessage = "Screen Recording was enabled, but macOS still needs MouseLens to be reopened before capture will start."
            } else {
                statusMessage = "Unable to start recording: \(error.localizedDescription)"
            }
        }
    }

    private func startPresenterCameraIfAllowed() async -> PresenterRecordingSession? {
        guard includePresenterCamera, !presenterCameraRecordingStarted, permissions.camera == .granted else { return nil }

        do {
            let session = try await environment.presenterCameraRecorder.start()
            presenterCameraRecordingStarted = true
            return session
        } catch {
            presenterCameraRecordingStarted = false
            return nil
        }
    }

    private func updatePresenterCameraOffsetIfNeeded(sourceStartedAt: Date, presenterStartedAt: Date?) {
        guard includePresenterCamera, let presenterStartedAt else { return }
        environment.presenterCameraRecorder.updateRenderOffset(sourceStartedAt.timeIntervalSince(presenterStartedAt))
    }

    static func defaultPresenterBubbleStyle(isEnabled: Bool) -> PresenterBubbleStyle {
        PresenterBubbleStyle(
            isEnabled: isEnabled,
            position: .bottomRight,
            normalizedSize: PresenterBubbleStyle.defaultValue.normalizedSize,
            shape: PresenterBubbleStyle.defaultValue.shape,
            cornerRadius: PresenterBubbleStyle.defaultValue.cornerRadius,
            shadowOpacity: PresenterBubbleStyle.defaultValue.shadowOpacity
        )
    }

    private func stopPresenterCameraIfNeeded() async -> PresenterMedia? {
        guard presenterCameraRecordingStarted else { return nil }
        presenterCameraRecordingStarted = false

        do {
            return try await environment.presenterCameraRecorder.stop()
        } catch {
            return nil
        }
    }

    private func cancelPresenterCameraIfNeeded() {
        guard presenterCameraRecordingStarted else { return }
        presenterCameraRecordingStarted = false
        environment.presenterCameraRecorder.cancel()
    }

    private func applyPreferences() {
        isApplyingDefaults = true
        selectedCaptureTarget = environment.preferencesStore.defaultCaptureTarget
        includeMicrophone = environment.preferencesStore.defaultMicrophoneEnabled
        includeSystemAudio = environment.preferencesStore.defaultSystemAudioEnabled
        includePresenterCamera = environment.preferencesStore.defaultPresenterCameraEnabled
        selectedAspectRatio = environment.preferencesStore.defaultAspectRatio
        isApplyingDefaults = false
    }

    private func bindPreferences() {
        environment.preferencesStore.$defaultCaptureTarget
            .dropFirst()
            .sink { [weak self] (_: CaptureTarget) in
                guard let self, self.recordingState == .idle else { return }
                self.applyPreferences()
            }
            .store(in: &cancellables)

        environment.preferencesStore.$defaultMicrophoneEnabled
            .dropFirst()
            .sink { [weak self] (_: Bool) in
                guard let self, self.recordingState == .idle else { return }
                self.applyPreferences()
            }
            .store(in: &cancellables)

        environment.preferencesStore.$defaultSystemAudioEnabled
            .dropFirst()
            .sink { [weak self] (_: Bool) in
                guard let self, self.recordingState == .idle else { return }
                self.applyPreferences()
            }
            .store(in: &cancellables)

        environment.preferencesStore.$defaultPresenterCameraEnabled
            .dropFirst()
            .sink { [weak self] (_: Bool) in
                guard let self, self.recordingState == .idle else { return }
                self.applyPreferences()
            }
            .store(in: &cancellables)

        environment.preferencesStore.$defaultAspectRatio
            .dropFirst()
            .sink { [weak self] (_: ProjectAspectRatio) in
                guard let self, self.recordingState == .idle else { return }
                self.applyPreferences()
            }
            .store(in: &cancellables)
    }

    private func bindWorkspaceNotifications() {
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .merge(with: workspaceNotifications.publisher(for: NSWorkspace.didActivateApplicationNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleWindowTargetRefresh(delayNanoseconds: 300_000_000)
            }
            .store(in: &cancellables)
    }

    private func scheduleWindowTargetRefresh(delayNanoseconds: UInt64) {
        guard Self.shouldAutoRefreshWindowTargets(
            captureTarget: selectedCaptureTarget,
            recordingState: recordingState
        ) else { return }

        windowTargetRefreshTask?.cancel()
        windowTargetRefreshTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, let self else { return }
            await self.refreshWindowTargets(
                policy: .preferCurrentWindow,
                showsLoadingState: false
            )
        }
    }

    private func cancelScheduledWindowTargetRefresh(invalidateRequests: Bool) {
        windowTargetRefreshTask?.cancel()
        windowTargetRefreshTask = nil
        if invalidateRequests {
            windowTargetRefreshGeneration += 1
        }
    }

    static func resolveWindowTargetID(
        from targets: [CaptureWindowOption],
        previousID: UInt32?,
        policy: WindowTargetSelectionPolicy
    ) -> UInt32? {
        guard !targets.isEmpty else { return nil }
        if policy == .preserveSelection,
           let previousID,
           targets.contains(where: { $0.id == previousID }) {
            return previousID
        }
        return targets.first?.id
    }

    static func shouldAutoRefreshWindowTargets(
        captureTarget: CaptureTarget,
        recordingState: RecordingState
    ) -> Bool {
        guard captureTarget == .window else { return false }
        if case .idle = recordingState {
            return true
        }
        return false
    }

    static func isWindowRecordingUnavailable(
        captureTarget: CaptureTarget,
        selectedWindowTargetID: UInt32?
    ) -> Bool {
        captureTarget == .window && selectedWindowTargetID == nil
    }

    static func windowTargetRefreshPolicyForRecording(
        selectedWindowTargetID: UInt32?
    ) -> WindowTargetSelectionPolicy {
        .preferCurrentWindow
    }

    private func normalize(events: [PointerEvent], for session: CaptureSession) -> [PointerEvent] {
        guard let coordinateSpace = session.coordinateSpace else {
            return events
        }

        return Self.normalizedPointerEvents(
            events,
            coordinateSpace: coordinateSpace,
            target: session.configuration.target
        )
    }

    static func normalizedPointerEvents(
        _ events: [PointerEvent],
        coordinateSpace: CaptureCoordinateSpace,
        target: CaptureTarget
    ) -> [PointerEvent] {
        let viewport = coordinateSpace.viewport.rect
        let screenBounds = coordinateSpace.screenBounds.rect
        guard screenBounds.width > 0, screenBounds.height > 0, viewport.width > 0, viewport.height > 0 else {
            return events
        }

        switch target {
        case .screen:
            return normalizedPointerEvents(events, screenBounds: screenBounds, viewport: viewport)
        case .window:
            return normalizedPointerEvents(events, screenBounds: screenBounds, viewport: viewport, outsideTolerance: 10)
        }
    }

    private static func normalizedPointerEvents(
        _ events: [PointerEvent],
        screenBounds: CGRect,
        viewport: CGRect,
        outsideTolerance: CGFloat = 0
    ) -> [PointerEvent] {
        let acceptedViewport = viewport.insetBy(dx: -outsideTolerance, dy: -outsideTolerance)
        return events.compactMap { event -> PointerEvent? in
            let globalPoint: CGPoint
            if let storedGlobalPoint = event.globalLocation?.cgPoint {
                globalPoint = storedGlobalPoint
            } else {
                let globalX = screenBounds.minX + (event.location.x * screenBounds.width)
                let globalY = screenBounds.minY + ((1 - event.location.y) * screenBounds.height)
                globalPoint = CGPoint(x: globalX, y: globalY)
            }

            guard acceptedViewport.contains(globalPoint) else { return nil }

            let localX = ((globalPoint.x - viewport.minX) / viewport.width).clamped(to: 0...1)
            let localY = (1 - ((globalPoint.y - viewport.minY) / viewport.height)).clamped(to: 0...1)

            return PointerEvent(
                id: event.id,
                timestamp: event.timestamp,
                location: NormalizedPoint(x: localX, y: localY),
                globalLocation: event.globalLocation,
                type: event.type
            )
        }
    }

}
