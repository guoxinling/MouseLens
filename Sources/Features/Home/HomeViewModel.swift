import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var selectedCaptureTarget: CaptureTarget = .screen
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

    var menuBarPrimaryActionTitle: String {
        switch recordingState {
        case .idle:
            return "Start Recording"
        case .countdown:
            return "Cancel Countdown"
        case .recording:
            return "Stop Recording"
        }
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

        beginCountdown()
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil

        guard case .countdown = recordingState else { return }
        recordingState = .idle
        statusMessage = "Recording countdown cancelled."
    }

    func stopRecording() async {
        countdownTask?.cancel()
        countdownTask = nil

        guard case .recording = recordingState else { return }

        defer {
            environment.windowController.restoreAfterCapture()
            recordingState = .idle
        }

        do {
            let session = try await environment.screenRecorder.stop()
            let events = environment.eventMonitor.stop()
            let normalizedEvents = normalize(events: events, for: session)
            let fallbackEvents = normalizedEvents.isEmpty ? Self.demoEvents(duration: max(session.duration, 6.0)) : normalizedEvents
            let keyframes = environment.cameraPlanEngine.makePlan(
                from: fallbackEvents,
                baseZoom: 1.0,
                followStrength: 0.72,
                clickRule: ClickEmphasisRule(boost: 0.54, duration: 0.72)
            )

            let style = ProjectStyle(
                aspectRatio: selectedAspectRatio,
                background: .aurora,
                cornerRadius: 26,
                shadowRadius: 30,
                followStrength: 0.72,
                clickEmphasis: 0.54,
                padding: 0.09
            )

            let project = try environment.projectStore.createProject(
                from: session,
                events: fallbackEvents,
                keyframes: keyframes,
                style: style
            )

            loadRecentProjects()
            statusMessage = "Project created. You can fine-tune the motion and export it now."
            completedProject = project
        } catch {
            statusMessage = "Unable to finish recording: \(error.localizedDescription)"
        }
    }

    func consumeCompletedProject() {
        completedProject = nil
    }

    func openRecent(project: RecordingProject) -> RecordingProject {
        statusMessage = "Reopened \(project.name)."
        return project
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

    private func beginCountdown() {
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

        statusMessage = "MouseLens will hide its window and start recording in \(countdownSeconds) seconds. Press \(recordingShortcutHint) to cancel."

        countdownTask = Task { [weak self] in
            guard let self else { return }

            for remaining in stride(from: countdownSeconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                recordingState = .countdown(secondsRemaining: remaining)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            guard !Task.isCancelled else { return }
            await startCaptureNow()
        }
    }

    private func startCaptureNow() async {
        if environment.preferencesStore.hideWindowBeforeCapture {
            await environment.windowController.prepareForCapture()
        }

        do {
            let configuration = ScreenRecorderConfiguration(
                target: selectedCaptureTarget,
                includeMicrophone: includeMicrophone,
                includeSystemAudio: includeSystemAudio
            )
            _ = try await environment.screenRecorder.start(configuration: configuration)
            environment.eventMonitor.start()
            recordingState = .recording(startedAt: Date())
            statusMessage = "Recording started. MouseLens is tracking pointer activity. Press \(recordingShortcutHint) to stop from anywhere."
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

        let viewport = coordinateSpace.viewport.rect
        let screenBounds = coordinateSpace.screenBounds.rect
        guard screenBounds.width > 0, screenBounds.height > 0, viewport.width > 0, viewport.height > 0 else {
            return events
        }

        let filtered = events.compactMap { event -> PointerEvent? in
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

        return filtered.isEmpty ? events : filtered
    }

    private static func demoEvents(duration: TimeInterval) -> [PointerEvent] {
        let points: [NormalizedPoint] = [
            .init(x: 0.18, y: 0.28),
            .init(x: 0.39, y: 0.36),
            .init(x: 0.61, y: 0.41),
            .init(x: 0.72, y: 0.22),
            .init(x: 0.54, y: 0.64),
            .init(x: 0.32, y: 0.74),
            .init(x: 0.78, y: 0.70)
        ]

        return points.enumerated().flatMap { index, point in
            let t = duration * Double(index) / Double(max(points.count - 1, 1))
            let move = PointerEvent(timestamp: t, location: point, type: .move)
            if index.isMultiple(of: 2) {
                return [move, PointerEvent(timestamp: min(t + 0.15, duration), location: point, type: .click)]
            }
            return [move]
        }
    }
}
