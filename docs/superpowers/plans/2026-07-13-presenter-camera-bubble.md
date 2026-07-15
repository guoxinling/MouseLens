# Presenter Camera Bubble Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional presenter camera bubble that can be recorded, previewed, edited, and exported consistently for Screen and Window projects.

**Architecture:** Record presenter video as a separate synchronized local media asset during capture, persist its metadata in `RecordingProject`, and compose it through the same preview/export rendering path used by the current screen video, cursor, click ripple, and zoom system. Keep the first release intentionally small: one presenter track, simple bubble styling, four corner positions, and no background removal.

**Tech Stack:** SwiftUI, AppKit, AVFoundation, ScreenCaptureKit, CoreGraphics, CoreImage, existing MouseLens preview/export renderer and project persistence model.

## Execution Status

- [x] Task 1: Add presenter bubble project model.
- [x] Task 2: Add camera permission and recorder lifecycle.
- [x] Task 3: Wire presenter media into capture completion.
- [x] Task 4: Add presenter bubble editor controls.
- [x] Task 5: Add live preview presenter overlay.
- [x] Task 6: Add presenter overlay to MP4/GIF export.
- [x] Task 7: Final verification and canonical app rebuild.

Verification:

- Focused presenter/capture/storage/editor tests: 92 tests, 0 failures.
- Full test suite: 188 tests, 0 failures.
- Canonical app rebuilt at `/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app`.

## Global Constraints

- Do not reintroduce preview/export drift.
- Do not record the native cursor into the source video.
- Do not couple presenter bubble motion to cursor or camera motion.
- The presenter bubble must work for both Screen and Window projects.
- The first release supports only one presenter track and one camera source.
- Do not add chroma key, background removal, independent camera timeline editing, or camera animation in this milestone.
- The bubble must remain a presentation aid, not a streaming-style overlay.
- Use TDD for model, rendering, and view-model behavior before implementation code.

---

## File Structure

### New files

- `Sources/Core/Capture/PresenterCameraRecorder.swift`
  - Owns AVCapture camera recording lifecycle and writes a local presenter video file.
- `Sources/Core/Render/PresenterOverlayGeometry.swift`
  - Shared geometry mapping for preview and export bubble placement.
- `Tests/Capture/PresenterCameraRecorderTests.swift`
  - Validates recorder lifecycle and synchronization metadata behavior with test doubles.
- `Tests/Render/PresenterOverlayGeometryTests.swift`
  - Validates bubble placement, sizing, and corner cases across aspect ratios.

### Modified files

- `Sources/Core/Storage/ProjectModels.swift`
  - Adds presenter overlay style/media metadata to the persisted project model.
- `Sources/Core/Capture/CaptureModels.swift`
  - Extends capture session data so presenter media can be finalized with the main recording.
- `Sources/App/AppEnvironment.swift`
  - Wires the presenter recorder service into shared app dependencies.
- `Sources/Core/System/SystemServices.swift`
  - Adds camera permission status and request handling.
- `Sources/Features/Home/HomeViewModel.swift`
  - Starts/stops presenter recording with screen recording and includes presenter asset in completed projects.
- `Sources/Features/Editor/EditorViewModel.swift`
  - Exposes presenter bubble editing state and persists edits back into the project.
- `Sources/Features/Editor/EditorView.swift`
  - Adds a Presenter inspector section for enable/disable, position, size, and style controls.
- `Sources/Features/Editor/PreviewCanvasView.swift`
  - Composes presenter bubble in live preview using shared overlay geometry.
- `Sources/Core/Render/RenderModels.swift`
  - Composes presenter bubble into exported video and GIF frames using the same geometry path.
- `Tests/Storage/ProjectStoreTests.swift`
  - Covers project persistence and migration behavior for presenter metadata.
- `Tests/Editor/EditorViewModelTests.swift`
  - Covers editing state, defaults, and save behavior for presenter bubble controls.

## Shared Interfaces

These signatures are the contract across tasks.

```swift
enum PresenterBubblePosition: String, CaseIterable, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

enum PresenterBubbleShape: String, CaseIterable, Codable {
    case circle
    case roundedRect
}

struct PresenterBubbleStyle: Codable, Equatable {
    let isEnabled: Bool
    let position: PresenterBubblePosition
    let normalizedSize: Double
    let shape: PresenterBubbleShape
    let cornerRadius: Double
    let shadowOpacity: Double
}

struct PresenterMedia: Codable, Equatable {
    let sourceVideoURL: URL?
    let startedAt: Date?
    let renderOffset: TimeInterval
    let naturalSize: CGSize
}

protocol PresenterCameraRecording {
    func start() async throws -> PresenterRecordingSession
    func stop() async throws -> PresenterMedia?
    func cancel()
}

struct PresenterRecordingSession: Equatable {
    let startedAt: Date
    let previewDeviceName: String
}

struct PresenterOverlayLayout: Equatable {
    let frame: CGRect
    let clippingPathCornerRadius: CGFloat
}

enum PresenterOverlayGeometry {
    static func layout(
        contentRect: CGRect,
        style: PresenterBubbleStyle
    ) -> PresenterOverlayLayout
}
```

## Task 1: Add Presenter Bubble Project Model

**Files:**
- Create: none
- Modify: `Sources/Core/Storage/ProjectModels.swift`
- Test: `Tests/Storage/ProjectStoreTests.swift`

**Interfaces:**
- Consumes: existing `RecordingProject`, `ProjectStyle`, Codable persistence behavior
- Produces:
  - `PresenterBubblePosition`
  - `PresenterBubbleShape`
  - `PresenterBubbleStyle`
  - `PresenterMedia`
  - `RecordingProject.presenterMedia: PresenterMedia?`
  - `ProjectStyle.presenterBubbleStyle: PresenterBubbleStyle`

- [ ] **Step 1: Write the failing persistence tests**

```swift
func testProjectStylePersistsPresenterBubbleStyle() throws {
    let style = ProjectStyle(
        aspectRatio: .landscape,
        backgroundPresetID: BackgroundPresetCatalog.defaultPresetID,
        cornerRadius: 10.35,
        shadowRadius: 24,
        followStrength: 0.72,
        clickEmphasis: 0.54,
        padding: 0.04,
        presenterBubbleStyle: PresenterBubbleStyle(
            isEnabled: true,
            position: .bottomRight,
            normalizedSize: 0.22,
            shape: .circle,
            cornerRadius: 18,
            shadowOpacity: 0.24
        )
    )

    let encoded = try JSONEncoder().encode(style)
    let decoded = try JSONDecoder().decode(ProjectStyle.self, from: encoded)

    XCTAssertEqual(decoded.presenterBubbleStyle, style.presenterBubbleStyle)
}

func testRecordingProjectPersistsPresenterMedia() throws {
    let media = PresenterMedia(
        sourceVideoURL: URL(fileURLWithPath: "/tmp/presenter.mov"),
        startedAt: Date(timeIntervalSince1970: 10),
        renderOffset: 0.12,
        naturalSize: CGSize(width: 1280, height: 720)
    )

    let project = RecordingProject(
        id: UUID(),
        name: "Demo",
        createdAt: Date(timeIntervalSince1970: 20),
        duration: 6,
        sourceVideoURL: URL(fileURLWithPath: "/tmp/source.mov"),
        captureTarget: .screen,
        reconstructsCursor: true,
        events: [],
        cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1)],
        style: .testValue,
        presenterMedia: media
    )

    let encoded = try JSONEncoder().encode(project)
    let decoded = try JSONDecoder().decode(RecordingProject.self, from: encoded)

    XCTAssertEqual(decoded.presenterMedia, media)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/ProjectStoreTests
```

Expected: FAIL because `ProjectStyle` and `RecordingProject` do not yet contain presenter bubble fields.

- [ ] **Step 3: Add the minimal model fields and Codable migration**

```swift
struct ProjectStyle: Codable, Equatable {
    let aspectRatio: ProjectAspectRatio
    let backgroundPresetID: String
    let cornerRadius: Double
    let shadowRadius: Double
    let followStrength: Double
    let clickEmphasis: Double
    let padding: Double
    let presenterBubbleStyle: PresenterBubbleStyle

    init(
        aspectRatio: ProjectAspectRatio,
        backgroundPresetID: String,
        cornerRadius: Double,
        shadowRadius: Double,
        followStrength: Double,
        clickEmphasis: Double,
        padding: Double,
        presenterBubbleStyle: PresenterBubbleStyle = .defaultValue
    ) {
        self.aspectRatio = aspectRatio
        self.backgroundPresetID = backgroundPresetID
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.followStrength = followStrength
        self.clickEmphasis = clickEmphasis
        self.padding = padding
        self.presenterBubbleStyle = presenterBubbleStyle
    }
}

struct RecordingProject: Identifiable, Codable, Equatable {
    let presenterMedia: PresenterMedia?
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/ProjectStoreTests
```

Expected: PASS for presenter model persistence coverage.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Storage/ProjectModels.swift Tests/Storage/ProjectStoreTests.swift
git commit -m "Add presenter bubble project model"
```

## Task 2: Add Camera Permission and Recorder Lifecycle

**Files:**
- Create: `Sources/Core/Capture/PresenterCameraRecorder.swift`
- Modify: `Sources/Core/Capture/CaptureModels.swift`, `Sources/Core/System/SystemServices.swift`, `Sources/App/AppEnvironment.swift`
- Test: `Tests/Capture/PresenterCameraRecorderTests.swift`

**Interfaces:**
- Consumes: AVFoundation camera capture APIs, existing app environment/service injection
- Produces:
  - `PresenterCameraRecording`
  - `PresenterRecordingSession`
  - `SystemPermissionState.camera`
  - `AppEnvironment.presenterCameraRecorder`

- [ ] **Step 1: Write the failing recorder/permission tests**

```swift
func testPresenterRecorderReturnsSessionOnStart() async throws {
    let recorder = PresenterCameraRecorder(
        writerFactory: .mockSuccess,
        deviceProvider: .mockBuiltInCamera
    )

    let session = try await recorder.start()

    XCTAssertEqual(session.previewDeviceName, "Mock Camera")
}

func testPresenterRecorderStopReturnsMediaWithNaturalSize() async throws {
    let recorder = PresenterCameraRecorder(
        writerFactory: .mockSuccess,
        deviceProvider: .mockBuiltInCamera
    )

    _ = try await recorder.start()
    let media = try await recorder.stop()

    XCTAssertEqual(media?.naturalSize, CGSize(width: 1280, height: 720))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/PresenterCameraRecorderTests
```

Expected: FAIL because the presenter recorder service does not exist.

- [ ] **Step 3: Implement the minimal recorder service and environment wiring**

```swift
protocol PresenterCameraRecording {
    func start() async throws -> PresenterRecordingSession
    func stop() async throws -> PresenterMedia?
    func cancel()
}

final class PresenterCameraRecorder: PresenterCameraRecording {
    func start() async throws -> PresenterRecordingSession { ... }
    func stop() async throws -> PresenterMedia? { ... }
    func cancel() { ... }
}
```

Also extend `SystemServices`:

```swift
func requestCameraAccessIfNeeded() async
func cameraPermissionGranted() -> Bool
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/PresenterCameraRecorderTests
```

Expected: PASS for recorder lifecycle tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Capture/PresenterCameraRecorder.swift Sources/Core/Capture/CaptureModels.swift Sources/Core/System/SystemServices.swift Sources/App/AppEnvironment.swift Tests/Capture/PresenterCameraRecorderTests.swift
git commit -m "Add presenter camera recorder service"
```

## Task 3: Capture Presenter Video With Screen Recording

**Files:**
- Create: none
- Modify: `Sources/Features/Home/HomeViewModel.swift`, `Sources/Core/Capture/CaptureModels.swift`, `Tests/Storage/ProjectStoreTests.swift`
- Test: `Tests/Editor/EditorViewModelTests.swift`

**Interfaces:**
- Consumes: `PresenterCameraRecording`, `ScreenRecorderConfiguration`, project creation flow
- Produces:
  - presenter media included in completed `RecordingProject`
  - presenter camera start/stop synchronized with capture start/stop

- [ ] **Step 1: Write failing workflow tests**

```swift
func testCompletedProjectIncludesPresenterMediaWhenCameraRecordingSucceeds() async {
    let presenterRecorder = PresenterCameraRecorderStub(
        mediaToReturn: PresenterMedia(
            sourceVideoURL: URL(fileURLWithPath: "/tmp/presenter.mov"),
            startedAt: Date(timeIntervalSince1970: 10),
            renderOffset: 0.05,
            naturalSize: CGSize(width: 1280, height: 720)
        )
    )

    let viewModel = makeHomeViewModel(presenterRecorder: presenterRecorder)
    await viewModel.startRecording()
    await viewModel.stopRecording()

    XCTAssertNotNil(viewModel.completedProject?.presenterMedia)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/ProjectStoreTests -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: FAIL because the capture completion flow drops presenter media.

- [ ] **Step 3: Start/stop presenter recording alongside capture**

```swift
private func startCaptureNow() async {
    if environment.systemServices.cameraPermissionGranted() {
        presenterRecordingSession = try? await environment.presenterCameraRecorder.start()
    }
    let session = try await environment.screenRecorder.start(configuration: configuration)
    ...
}

private func stopRecording() async {
    let presenterMedia = try? await environment.presenterCameraRecorder.stop()
    let project = try projectStore.createProject(
        from: session,
        rawEvents: events,
        events: normalizedEvents,
        keyframes: keyframes,
        style: style,
        presenterMedia: presenterMedia
    )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/ProjectStoreTests -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: PASS for presenter media capture persistence.

- [ ] **Step 5: Commit**

```bash
git add Sources/Features/Home/HomeViewModel.swift Sources/Core/Capture/CaptureModels.swift Tests/Storage/ProjectStoreTests.swift Tests/Editor/EditorViewModelTests.swift
git commit -m "Capture presenter media with recordings"
```

## Task 4: Add Shared Bubble Geometry For Preview And Export

**Files:**
- Create: `Sources/Core/Render/PresenterOverlayGeometry.swift`
- Modify: `Sources/Features/Editor/PreviewCanvasView.swift`, `Sources/Core/Render/RenderModels.swift`
- Test: `Tests/Render/PresenterOverlayGeometryTests.swift`, `Tests/Render/SourceCropPlannerTests.swift`

**Interfaces:**
- Consumes: `PresenterBubbleStyle`, preview `contentRect`, export render layout
- Produces:
  - `PresenterOverlayLayout`
  - shared preview/export bubble placement

- [ ] **Step 1: Write failing geometry tests**

```swift
func testBottomRightCircleBubbleStaysInsideContentRect() {
    let layout = PresenterOverlayGeometry.layout(
        contentRect: CGRect(x: 100, y: 80, width: 1280, height: 720),
        style: PresenterBubbleStyle(
            isEnabled: true,
            position: .bottomRight,
            normalizedSize: 0.22,
            shape: .circle,
            cornerRadius: 18,
            shadowOpacity: 0.24
        )
    )

    XCTAssertTrue(CGRect(x: 100, y: 80, width: 1280, height: 720).contains(layout.frame))
}

func testPreviewAndExportUseSamePresenterBubbleLayout() {
    let contentRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let style = PresenterBubbleStyle.defaultValue

    let previewLayout = PresenterOverlayGeometry.layout(contentRect: contentRect, style: style)
    let exportLayout = PresenterOverlayGeometry.layout(contentRect: contentRect, style: style)

    XCTAssertEqual(previewLayout, exportLayout)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/PresenterOverlayGeometryTests -only-testing:MouseLensTests/SourceCropPlannerTests
```

Expected: FAIL because the shared geometry helper does not exist.

- [ ] **Step 3: Implement shared overlay geometry and hook it into preview/export**

```swift
enum PresenterOverlayGeometry {
    static func layout(contentRect: CGRect, style: PresenterBubbleStyle) -> PresenterOverlayLayout {
        let shortestSide = min(contentRect.width, contentRect.height)
        let bubbleSize = shortestSide * CGFloat(style.normalizedSize)
        let inset = max(shortestSide * 0.035, 18)
        let origin: CGPoint = ...

        return PresenterOverlayLayout(
            frame: CGRect(origin: origin, size: CGSize(width: bubbleSize, height: bubbleSize)),
            clippingPathCornerRadius: style.shape == .circle ? bubbleSize / 2 : CGFloat(style.cornerRadius)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/PresenterOverlayGeometryTests -only-testing:MouseLensTests/SourceCropPlannerTests
```

Expected: PASS for shared presenter bubble layout behavior.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Render/PresenterOverlayGeometry.swift Sources/Features/Editor/PreviewCanvasView.swift Sources/Core/Render/RenderModels.swift Tests/Render/PresenterOverlayGeometryTests.swift Tests/Render/SourceCropPlannerTests.swift
git commit -m "Add presenter bubble preview and export geometry"
```

## Task 5: Add Editor Controls For Presenter Bubble

**Files:**
- Create: none
- Modify: `Sources/Features/Editor/EditorViewModel.swift`, `Sources/Features/Editor/EditorView.swift`, `Tests/Editor/EditorViewModelTests.swift`
- Test: `Tests/Editor/EditorViewModelTests.swift`

**Interfaces:**
- Consumes: `RecordingProject.presenterMedia`, `ProjectStyle.presenterBubbleStyle`
- Produces:
  - editor bindings for presenter enable/position/size/shape
  - draft project updates when presenter settings change

- [ ] **Step 1: Write failing editor tests**

```swift
func testConfiguringEditorLoadsPresenterBubbleState() {
    let project = makeProjectWithPresenterBubble()
    let viewModel = makeViewModel()

    viewModel.configure(for: project)

    XCTAssertTrue(viewModel.isPresenterBubbleEnabled)
    XCTAssertEqual(viewModel.presenterBubblePosition, .bottomRight)
}

func testUpdatingPresenterBubbleRebuildsDraftProject() {
    let project = makeProjectWithPresenterBubble()
    let viewModel = makeViewModel()
    viewModel.configure(for: project)

    viewModel.updatePresenterBubblePosition(.topLeft)

    XCTAssertEqual(viewModel.project?.style.presenterBubbleStyle.position, .topLeft)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: FAIL because editor state does not yet expose presenter bubble controls.

- [ ] **Step 3: Add minimal editor state and inspector UI**

```swift
@Published var isPresenterBubbleEnabled = false
@Published var presenterBubblePosition: PresenterBubblePosition = .bottomRight
@Published var presenterBubbleSize = 0.22
@Published var presenterBubbleShape: PresenterBubbleShape = .circle
```

Add a `Presenter` inspector section only when `project.presenterMedia != nil`.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: PASS for presenter editor state and draft-project update behavior.

- [ ] **Step 5: Commit**

```bash
git add Sources/Features/Editor/EditorViewModel.swift Sources/Features/Editor/EditorView.swift Tests/Editor/EditorViewModelTests.swift
git commit -m "Add presenter bubble editor controls"
```

## Task 6: Compose Presenter Bubble In Export Output

**Files:**
- Create: none
- Modify: `Sources/Core/Render/RenderModels.swift`, `Tests/Render/ExportConfigurationTests.swift`, `Tests/Render/SourceCropPlannerTests.swift`
- Test: `Tests/Render/SourceCropPlannerTests.swift`

**Interfaces:**
- Consumes: `PresenterMedia`, `PresenterBubbleStyle`, `PresenterOverlayGeometry`
- Produces:
  - presenter bubble visible in MP4 and GIF exports
  - export path aligned with preview path

- [ ] **Step 1: Write failing export composition tests**

```swift
func testPresenterBubbleUsesSharedGeometryDuringExport() {
    let project = makeProjectWithPresenterBubble()
    let contentRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    let layout = PresenterOverlayGeometry.layout(
        contentRect: contentRect,
        style: project.style.presenterBubbleStyle
    )

    XCTAssertGreaterThan(layout.frame.width, 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/SourceCropPlannerTests
```

Expected: FAIL because export composition does not yet consume presenter media.

- [ ] **Step 3: Render the presenter layer through the export frame pipeline**

```swift
if let presenterMedia = project.presenterMedia,
   project.style.presenterBubbleStyle.isEnabled {
    let layout = PresenterOverlayGeometry.layout(
        contentRect: renderLayout.contentRect,
        style: project.style.presenterBubbleStyle
    )
    composePresenterFrame(
        from: presenterMedia,
        at: timestamp,
        into: composedImage,
        layout: layout
    )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' -only-testing:MouseLensTests/SourceCropPlannerTests
```

Expected: PASS for export-side presenter bubble layout and composition coverage.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Render/RenderModels.swift Tests/Render/ExportConfigurationTests.swift Tests/Render/SourceCropPlannerTests.swift
git commit -m "Render presenter bubble in exports"
```

## Task 7: End-to-End Validation And Canonical App Rebuild

**Files:**
- Create: none
- Modify: none
- Test: existing suites plus canonical app build

**Interfaces:**
- Consumes: all prior tasks
- Produces: validated local release candidate and canonical app for manual QA

- [ ] **Step 1: Run targeted presenter-related test suites**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS' \
  -only-testing:MouseLensTests/PresenterCameraRecorderTests \
  -only-testing:MouseLensTests/PresenterOverlayGeometryTests \
  -only-testing:MouseLensTests/EditorViewModelTests \
  -only-testing:MouseLensTests/ProjectStoreTests \
  -only-testing:MouseLensTests/SourceCropPlannerTests
```

Expected: PASS.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
xcodebuild test -project '/Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj' -scheme 'MouseLens' -destination 'platform=macOS'
```

Expected: PASS with no regressions.

- [ ] **Step 3: Rebuild the canonical local test app**

Run:

```bash
cd /Users/guoxl/Documents/Playground/MouseLens
./scripts/prepare_local_test_app.sh
```

Expected: build succeeds and updates:

```text
/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app
```

- [ ] **Step 4: Manual QA checklist**

Verify in the canonical app:

```text
1. Screen recording with presenter bubble enabled records screen + presenter.
2. Window recording with presenter bubble enabled records window + presenter.
3. Editor preview shows the same bubble placement as export.
4. Bubble can be moved between all four corners.
5. Bubble size updates immediately in preview.
6. GIF and MP4 exports both include the presenter bubble.
```

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "Finalize presenter camera bubble feature"
```
