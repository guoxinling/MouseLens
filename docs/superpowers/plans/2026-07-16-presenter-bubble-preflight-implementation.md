# Presenter Bubble Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a draggable pre-recording presenter bubble whose position, corner radius, and mirrored camera appearance match recording, editor preview, and export.

**Architecture:** Extend presenter style from fixed corners and shape enum to free normalized center plus corner radius ratio, while preserving legacy decoding. Use `PresenterOverlayGeometry` as the single layout source across preflight, recording, preview, and export. Add a non-activating floating panel for the preflight bubble, driven by the same camera preview session as recording.

**Tech Stack:** SwiftUI, AppKit `NSPanel`, AVFoundation `AVCaptureSession`/`AVPlayer`, CoreGraphics, XCTest, existing MouseLens local canonical app build scripts.

## Global Constraints

- Raw screen/window video must remain clean; presenter is recorded separately and post-composed.
- Presenter video is mirrored in preflight, recording, editor preview, MP4 export, and GIF export.
- Existing projects with `PresenterBubblePosition` and `PresenterBubbleShape` must keep rendering.
- Virtual avatar implementation is excluded; only reserve `PresenterSource.avatarImage`.
- Only test canonical app after rebuild: `/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app`.
- Do not revert unrelated uncommitted changes.

---

### Task 1: Presenter Style Model Migration

**Files:**
- Modify: `Sources/Core/Storage/ProjectModels.swift`
- Test: `Tests/Storage/ProjectStoreTests.swift`

**Interfaces:**
- Produces: `PresenterSource`, `PresenterBubbleStyle.normalizedCenter`, `PresenterBubbleStyle.cornerRadiusRatio`, migration from legacy `position`/`shape`.
- Consumes: existing `NormalizedPoint`, `PresenterBubblePosition`, `PresenterBubbleShape`.

- [ ] **Step 1: Write failing migration tests**

Add tests covering:

```swift
func testPresenterBubbleStyleDecodesLegacyBottomRightCircleIntoFreePosition() throws
func testPresenterBubbleStylePersistsReservedPresenterSource() throws
```

Expected assertions:

- legacy bottom-right decodes to `normalizedCenter == NormalizedPoint(x: 0.86, y: 0.86)` within tolerance.
- legacy circle decodes to `cornerRadiusRatio == 0.5`.
- encoded/decoded style preserves `source == .avatarImage`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -scheme MouseLens -destination 'platform=macOS' -only-testing:MouseLensTests/ProjectStoreTests
```

Expected: FAIL because the new properties and source enum do not exist.

- [ ] **Step 3: Implement model fields and legacy decoding**

Add:

```swift
enum PresenterSource: String, Codable, Equatable {
    case camera
    case avatarImage
}
```

Extend `PresenterBubbleStyle` with `normalizedCenter`, `cornerRadiusRatio`, and `source`, while retaining legacy fields for decoding compatibility.

- [ ] **Step 4: Run model tests**

Run the same ProjectStoreTests command.

Expected: PASS.

### Task 2: Shared Free-Position Presenter Geometry

**Files:**
- Modify: `Sources/Core/Render/PresenterOverlayGeometry.swift`
- Test: `Tests/Render/PresenterOverlayGeometryTests.swift`

**Interfaces:**
- Consumes: `PresenterBubbleStyle.normalizedCenter`, `normalizedSize`, `cornerRadiusRatio`.
- Produces: shared `PresenterOverlayLayout(frame:clippingPathCornerRadius:)`.

- [ ] **Step 1: Write failing geometry tests**

Add tests:

```swift
func testFreePositionPresenterBubbleCentersOnNormalizedPoint()
func testPresenterBubbleCenterIsClampedInsideContentRect()
func testCornerRadiusRatioControlsSquareRoundedAndCircle()
```

Expected:

- center `0.5,0.5` places bubble at content center.
- edge center clamps so full bubble remains visible.
- ratio `0` -> radius `0`; ratio `0.5` -> radius half bubble size.

- [ ] **Step 2: Run geometry tests to verify failure**

Run:

```bash
xcodebuild test -scheme MouseLens -destination 'platform=macOS' -only-testing:MouseLensTests/PresenterOverlayGeometryTests
```

Expected: FAIL until geometry reads new fields.

- [ ] **Step 3: Implement geometry**

Update `PresenterOverlayGeometry.layout` to compute frame from normalized center and clamp inside `contentRect`. Use `cornerRadiusRatio * bubbleSize` for clipping radius.

- [ ] **Step 4: Run geometry tests**

Run the same PresenterOverlayGeometryTests command.

Expected: PASS.

### Task 3: Preflight Floating Bubble Panel

**Files:**
- Modify: `Sources/App/AppCoordinator.swift`
- Modify: `Sources/App/MouseLensApp.swift`
- Modify: `Sources/Core/System/SystemServices.swift`
- Modify: `Sources/Features/Home/HomeViewModel.swift`
- Modify: `Sources/Features/Recording/RecordingHUDView.swift`
- Test: `Tests/AppWindowControllerTests.swift` or `Tests/HomeViewModelWindowTargetTests.swift`

**Interfaces:**
- Consumes: `HomeViewModel.presenterCameraPreviewSession`, `HomeViewModel.presenterBubbleStyle`.
- Produces: a non-activating floating panel showing a draggable mirrored `AVCaptureSession` bubble before recording.

- [ ] **Step 1: Write failing state tests**

Add tests proving:

- enabling presenter camera in idle makes preflight bubble eligible to show.
- starting recording hides preflight bubble.
- drag updates persist `presenterBubbleStyle.normalizedCenter`.

- [ ] **Step 2: Run tests to verify failure**

Run targeted home/window controller tests.

Expected: FAIL because preflight bubble state and drag API do not exist.

- [ ] **Step 3: Implement state and panel plumbing**

Add published style state to `HomeViewModel`. Add an app/window-controller path to show a floating `PresenterCameraPreviewView` panel when idle, camera enabled, and preview session exists.

- [ ] **Step 4: Add drag handling**

Convert panel drag location to normalized content center and update `HomeViewModel.presenterBubbleStyle`.

- [ ] **Step 5: Run targeted tests**

Expected: PASS.

### Task 4: Editor UI Corner Radius Slider

**Files:**
- Modify: `Sources/Features/Editor/EditorView.swift`
- Modify: `Sources/Features/Editor/EditorViewModel.swift`
- Test: `Tests/Editor/EditorViewModelTests.swift`

**Interfaces:**
- Consumes: `PresenterBubbleStyle.cornerRadiusRatio`.
- Produces: `updatePresenterBubbleCornerRadiusRatio(_:)`.

- [ ] **Step 1: Write failing view model test**

Add:

```swift
func testUpdatingPresenterBubbleCornerRadiusRatioRebuildsDraftProject()
```

Expected: style ratio changes and clamps to `0...0.5`.

- [ ] **Step 2: Run EditorViewModelTests to verify failure**

Expected: FAIL because update method does not exist.

- [ ] **Step 3: Implement view model and UI slider**

Replace shape picker UI with a metric slider over `0...0.5`. Optionally keep display labels `Square` and `Circle` at the ends.

- [ ] **Step 4: Run EditorViewModelTests**

Expected: PASS.

### Task 5: Mirroring Consistency Across Preview and Export

**Files:**
- Modify: `Sources/Features/Recording/RecordingHUDView.swift`
- Modify: `Sources/Features/Editor/PreviewCanvasView.swift`
- Modify: `Sources/Core/Render/RenderModels.swift`
- Test: `Tests/Render/SourceCropPlannerTests.swift`
- Test: `Tests/Render/PresenterOverlayGeometryTests.swift`

**Interfaces:**
- Consumes: shared presenter geometry and presenter source media.
- Produces: mirrored presenter rendering in preflight, recording, editor preview, MP4 export, and GIF export.

- [ ] **Step 1: Write failing render tests**

Add or adjust tests so a deliberately asymmetric presenter frame renders mirrored in MP4/GIF composition.

- [ ] **Step 2: Run targeted render tests to verify failure**

Run:

```bash
xcodebuild test -scheme MouseLens -destination 'platform=macOS' -only-testing:MouseLensTests/SourceCropPlannerTests
```

Expected: FAIL until render paths apply horizontal flip.

- [ ] **Step 3: Implement mirroring transforms**

Apply horizontal flip in:

- `PresenterCameraPreviewNSView` preview layer.
- `PresenterBubblePlayerView` editor player layer.
- export compositor drawing path.

- [ ] **Step 4: Run targeted render tests**

Expected: PASS.

### Task 6: Full Verification and Canonical App

**Files:**
- No source ownership; verification task.

- [ ] **Step 1: Run full tests**

```bash
xcodebuild test -scheme MouseLens -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 2: Rebuild canonical app**

```bash
./scripts/prepare_local_test_app.sh --clean
```

Expected: `/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app` is ready.

- [ ] **Step 3: Manual acceptance flow**

```bash
open /Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app
```

Verify:

- Toggle Presenter before recording shows floating bubble.
- Dragging bubble changes final position.
- Recording/editor/export match the same position.
- Presenter is mirrored in every surface.
- Corner radius slider reaches square and circle.
