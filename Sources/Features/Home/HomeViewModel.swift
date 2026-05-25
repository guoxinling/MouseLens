import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var selectedCaptureTarget: CaptureTarget = .screen {
        didSet {
            guard selectedCaptureTarget == .window else { return }
            Task { [weak self] in
                await self?.refreshWindowTargets()
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
    private var isApplyingDefaults = false
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
            return "Start Recording"
        case .countdown:
            return "Cancel Countdown"
        case .recording(let session):
            if session.isPaused {
                return "Stop Recording (Paused)"
            }
            return "Stop Recording"
        }
    }

    var selectedWindowTarget: CaptureWindowOption? {
        availableWindowTargets.first { $0.id == selectedWindowTargetID }
    }

    var selectedWindowTargetLabel: String {
        if isRefreshingWindowTargets {
            return "Loading Windows"
        }

        return selectedWindowTarget?.compactLabel ?? "Choose Window"
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        applyPreferences()
        bindPreferences()
        refreshPermissions()
        loadRecentProjects()

        environment.hotkeyManager.setToggleHandler { [weak self] in
            guard let self else { return }
            Task { await self.handleRecordingToggleHotkey() }
        }
    }

    deinit {
        countdownTask?.cancel()
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
            includeAccessibility: false
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
            if selectedWindowTargetID == nil || selectedWindowTarget == nil {
                await refreshWindowTargets(preservingCurrentSelection: selectedWindowTargetID != nil)
            }
            guard selectedWindowTargetID != nil else {
                statusMessage = "No recordable window is selected. Open a window, refresh Window mode, then record again."
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
            let events = environment.eventMonitor.stop()
            let normalizedEvents = normalize(events: events, for: session)
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
                padding: 0.04
            )

            let project = try environment.projectStore.createProject(
                from: session,
                events: normalizedEvents,
                keyframes: keyframes,
                style: style
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
            recordingState = .idle
            environment.windowController.restoreAfterCapture()
            statusMessage = "Unable to finish recording: \(error.localizedDescription)"
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

    func refreshWindowTargets(preservingCurrentSelection: Bool = false) async {
        guard recordingState == .idle, selectedCaptureTarget == .window else { return }

        isRefreshingWindowTargets = true
        defer { isRefreshingWindowTargets = false }

        let previousTargets = availableWindowTargets
        let previousTargetID = selectedWindowTargetID

        do {
            let targets = try await environment.screenRecorder.availableWindowTargets()
            availableWindowTargets = targets

            if let selectedWindowTargetID,
               targets.contains(where: { $0.id == selectedWindowTargetID }) {
                statusMessage = "Window target: \(selectedWindowTarget?.displayLabel ?? "Selected window")."
            } else if preservingCurrentSelection, previousTargetID != nil {
                availableWindowTargets = targets.isEmpty ? previousTargets : targets
                selectedWindowTargetID = previousTargetID
                statusMessage = "Window target preserved for recording."
            } else {
                selectedWindowTargetID = targets.first?.id
                if let selectedWindowTarget {
                    statusMessage = "Window target: \(selectedWindowTarget.displayLabel)."
                } else {
                    statusMessage = "No recordable windows found. Open a window, then refresh Window mode."
                }
            }
        } catch {
            if preservingCurrentSelection, previousTargetID != nil {
                availableWindowTargets = previousTargets
                selectedWindowTargetID = previousTargetID
            } else {
                availableWindowTargets = []
                selectedWindowTargetID = nil
            }
            statusMessage = "Unable to list windows: \(error.localizedDescription)"
        }
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
        permissions.recordingReady(requiresMicrophone: includeMicrophone)
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
            let session = try await environment.screenRecorder.start(configuration: configuration)
            environment.eventMonitor.start()
            recordingState = .recording(RecordingSessionState(startedAt: session.startedAt))
            statusMessage = "Recording started. Use the floating toolbar to pause or finish."
        } catch {
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

    private func applyPreferences() {
        isApplyingDefaults = true
        includeMicrophone = environment.preferencesStore.defaultMicrophoneEnabled
        includeSystemAudio = environment.preferencesStore.defaultSystemAudioEnabled
        selectedAspectRatio = environment.preferencesStore.defaultAspectRatio
        isApplyingDefaults = false
    }

    private func bindPreferences() {
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

        environment.preferencesStore.$defaultAspectRatio
            .dropFirst()
            .sink { [weak self] (_: ProjectAspectRatio) in
                guard let self, self.recordingState == .idle else { return }
                self.applyPreferences()
            }
            .store(in: &cancellables)
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
            let normalizedEvents = normalizedPointerEvents(events, screenBounds: screenBounds, viewport: viewport)
            return normalizedEvents.isEmpty ? events : normalizedEvents
        case .window:
            return normalizedWindowPointerEvents(events, screenBounds: screenBounds, viewport: viewport)
        }
    }

    private static func normalizedPointerEvents(
        _ events: [PointerEvent],
        screenBounds: CGRect,
        viewport: CGRect
    ) -> [PointerEvent] {
        events.compactMap { event -> PointerEvent? in
            let globalX = screenBounds.minX + (event.location.x * screenBounds.width)
            let globalY = screenBounds.minY + ((1 - event.location.y) * screenBounds.height)
            let globalPoint = CGPoint(x: globalX, y: globalY)

            guard viewport.contains(globalPoint) else { return nil }

            let localX = ((globalPoint.x - viewport.minX) / viewport.width).clamped(to: 0...1)
            let localY = (1 - ((globalPoint.y - viewport.minY) / viewport.height)).clamped(to: 0...1)

            return PointerEvent(
                id: event.id,
                timestamp: event.timestamp,
                location: NormalizedPoint(x: localX, y: localY),
                type: event.type
            )
        }
    }

    private static func normalizedWindowPointerEvents(
        _ events: [PointerEvent],
        screenBounds: CGRect,
        viewport: CGRect
    ) -> [PointerEvent] {
        let alternateViewport = flippedViewport(viewport, in: screenBounds)
        let candidates = [viewport, alternateViewport]
        let scoredCandidates = candidates.map { candidate in
            (
                viewport: candidate,
                events: normalizedPointerEvents(events, screenBounds: screenBounds, viewport: candidate)
            )
        }

        let best = scoredCandidates.max { lhs, rhs in
            if lhs.events.count != rhs.events.count {
                return lhs.events.count < rhs.events.count
            }
            return averageDistanceFromCenter(lhs.events) > averageDistanceFromCenter(rhs.events)
        }

        return best?.events ?? []
    }

    private static func flippedViewport(_ viewport: CGRect, in screenBounds: CGRect) -> CGRect {
        CGRect(
            x: viewport.minX,
            y: screenBounds.minY + screenBounds.height - (viewport.minY - screenBounds.minY) - viewport.height,
            width: viewport.width,
            height: viewport.height
        )
    }

    private static func averageDistanceFromCenter(_ events: [PointerEvent]) -> Double {
        guard !events.isEmpty else { return .greatestFiniteMagnitude }
        let total = events.reduce(0.0) { partialResult, event in
            let dx = event.location.x - 0.5
            let dy = event.location.y - 0.5
            return partialResult + sqrt((dx * dx) + (dy * dy))
        }
        return total / Double(events.count)
    }
}
