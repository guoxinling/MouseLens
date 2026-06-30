# Export Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the editor's compact Export card with the approved full-height single-panel export workflow and make every enabled MP4 setting affect the generated file.

**Architecture:** Add an export configuration value model beside the existing render presets, then pass that configuration through `EditorViewModel`, `ExportCoordinator`, and `VideoRenderer`. Keep preview rendering on the existing aspect-based preset path. Isolate the new SwiftUI surface in `ExportPanelView`, while `EditorView` only switches between normal inspector and export inspector modes.

**Tech Stack:** Swift 5, SwiftUI, AppKit, AVFoundation/AVAssetWriter, XCTest, XcodeGen, `xcodebuild`.

---

## File Structure

- Modify `Sources/Core/Render/RenderModels.swift`: export configuration types, render-size/bitrate calculation, renderer/coordinator configuration plumbing.
- Modify `Sources/Features/Editor/EditorViewModel.swift`: recommended export state, modification/reset methods, size estimate, and configured export action.
- Create `Sources/Features/Editor/ExportPanelView.swift`: dedicated single-panel SwiftUI export surface.
- Modify `Sources/Features/Editor/EditorView.swift`: inspector-mode switching, header Export entry, and failure-only preview retry.
- Create `Tests/Render/ExportConfigurationTests.swift`: deterministic configuration and bitrate tests.
- Modify `Tests/Editor/EditorViewModelTests.swift`: recommended/modified/reset and aspect-ratio behavior tests.
- Modify `NEXT_VERSION_DEVELOPMENT_PLAN.md`: replace obsolete Presets/Custom wording with the approved single-panel structure.
- Regenerate `MouseLens.xcodeproj/project.pbxproj` with XcodeGen so the new source and test files are included.

### Task 1: Export Configuration Value Model

**Files:**
- Modify: `Sources/Core/Render/RenderModels.swift:8-48`
- Create: `Tests/Render/ExportConfigurationTests.swift`
- Regenerate: `MouseLens.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing configuration tests**

```swift
import XCTest
@testable import MouseLens

final class ExportConfigurationTests: XCTestCase {
    func testRecommendedMP4Uses1080pThirtyFPSAndHighQuality() {
        let configuration = ExportConfiguration.recommended(for: .landscape)

        XCTAssertEqual(configuration.format, .mp4)
        XCTAssertEqual(configuration.resolution, .p1080)
        XCTAssertEqual(configuration.frameRate, .fps30)
        XCTAssertEqual(configuration.quality, .high)
        XCTAssertTrue(configuration.includesCursor)
        XCTAssertTrue(configuration.includesClickFeedback)
    }

    func testResolutionPreservesProjectAspect() {
        XCTAssertEqual(ExportResolution.p720.renderSize(for: .landscape), CGSize(width: 1280, height: 720))
        XCTAssertEqual(ExportResolution.p720.renderSize(for: .portrait), CGSize(width: 720, height: 1280))
        XCTAssertEqual(ExportResolution.p720.renderSize(for: .square), CGSize(width: 720, height: 720))
    }

    func testBitrateScalesDownForSmallerAndLowerQualityExports() {
        let high1080 = ExportQuality.high.averageBitRate(
            renderSize: CGSize(width: 1920, height: 1080),
            frameRate: .fps30
        )
        let small720 = ExportQuality.small.averageBitRate(
            renderSize: CGSize(width: 1280, height: 720),
            frameRate: .fps15
        )

        XCTAssertGreaterThan(high1080, small720)
        XCTAssertGreaterThan(small720, 0)
    }

    func testGIFIsVisibleButUnavailableUntilEncoderLands() {
        XCTAssertFalse(ExportFormat.gif.isAvailable)
        XCTAssertTrue(ExportFormat.mp4.isAvailable)
    }
}
```

- [ ] **Step 2: Regenerate the test target**

```bash
xcodegen generate
```

Expected: `ExportConfigurationTests.swift` is included in the MouseLensTests target.

- [ ] **Step 3: Run the new test and verify it fails**

Run:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/ExportConfigurationTests
```

Expected: compilation fails because `ExportConfiguration` and related types do not exist.

- [ ] **Step 4: Add the configuration model**

Add these public-to-module types near `ExportPreset`:

```swift
enum ExportFormat: String, CaseIterable, Equatable {
    case mp4
    case gif

    var label: String { self == .mp4 ? "MP4" : "GIF" }
    var isAvailable: Bool { self == .mp4 }
}

enum ExportResolution: String, CaseIterable, Equatable {
    case p1080, p720, p480

    var label: String {
        switch self {
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }

    func renderSize(for aspectRatio: ProjectAspectRatio) -> CGSize {
        let longSide: CGFloat
        let shortSide: CGFloat
        switch self {
        case .p1080: (longSide, shortSide) = (1920, 1080)
        case .p720: (longSide, shortSide) = (1280, 720)
        case .p480: (longSide, shortSide) = (854, 480)
        }
        switch aspectRatio {
        case .landscape: CGSize(width: longSide, height: shortSide)
        case .portrait: CGSize(width: shortSide, height: longSide)
        case .square: CGSize(width: shortSide, height: shortSide)
        }
    }
}

enum ExportFrameRate: Int32, CaseIterable, Equatable {
    case fps15 = 15
    case fps24 = 24
    case fps30 = 30
    var label: String { "\(rawValue) fps" }
}

enum ExportQuality: String, CaseIterable, Equatable {
    case high, balanced, small

    var label: String { rawValue.capitalized }

    func averageBitRate(renderSize: CGSize, frameRate: ExportFrameRate) -> Int {
        let base: Double
        switch self {
        case .high: base = 8_000_000
        case .balanced: base = 5_000_000
        case .small: base = 3_000_000
        }
        let pixelScale = (renderSize.width * renderSize.height) / (1920 * 1080)
        let frameScale = Double(frameRate.rawValue) / 30
        return max(Int(base * pixelScale * frameScale), 750_000)
    }
}

struct ExportConfiguration: Equatable {
    var format: ExportFormat
    var resolution: ExportResolution
    var frameRate: ExportFrameRate
    var quality: ExportQuality
    var includesCursor: Bool
    var includesClickFeedback: Bool

    static func recommended(for aspectRatio: ProjectAspectRatio) -> ExportConfiguration {
        ExportConfiguration(
            format: .mp4,
            resolution: .p1080,
            frameRate: .fps30,
            quality: .high,
            includesCursor: true,
            includesClickFeedback: true
        )
    }
}
```

- [ ] **Step 5: Run configuration tests**

Run the command from Step 3.

Expected: `ExportConfigurationTests` passes.

- [ ] **Step 6: Commit the model**

```bash
git add Sources/Core/Render/RenderModels.swift Tests/Render/ExportConfigurationTests.swift MouseLens.xcodeproj/project.pbxproj
git commit -m "Add MP4 export configuration model"
```

### Task 2: Apply Configuration in the MP4 Renderer

**Files:**
- Modify: `Sources/Core/Render/RenderModels.swift:577-1055`
- Modify: `Tests/Render/ExportFilenameTests.swift`

- [ ] **Step 1: Add failing filename and option tests**

Add coverage proving configured exports keep the `.mp4` suffix and that the chosen render size, frame rate, bitrate, and overlay flags are exposed through deterministic helpers. The core assertions are:

```swift
let configuration = ExportConfiguration(
    format: .mp4,
    resolution: .p720,
    frameRate: .fps15,
    quality: .small,
    includesCursor: false,
    includesClickFeedback: false
)
XCTAssertEqual(configuration.renderSize(for: .portrait), CGSize(width: 720, height: 1280))
XCTAssertTrue(ExportCoordinator.exportFilename(for: project, configuration: configuration).hasSuffix(".mp4"))
```

- [ ] **Step 2: Run render tests and verify the new API is missing**

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/ExportConfigurationTests \
  -only-testing:MouseLensTests/ExportFilenameTests
```

Expected: compilation fails on the new configuration API.

- [ ] **Step 3: Thread configuration through renderer and coordinator**

Add `ExportConfiguration.renderSize(for:)`, then introduce configuration overloads:

```swift
func renderVideo(
    for project: RecordingProject,
    configuration: ExportConfiguration,
    destinationURL: URL
) async throws -> URL

func exportVideo(
    for project: RecordingProject,
    configuration: ExportConfiguration,
    destinationURL: URL
) async throws -> URL
```

The renderer must use:

```swift
let renderSize = configuration.renderSize(for: project.style.aspectRatio)
let fps = configuration.frameRate.rawValue
let averageBitRate = configuration.quality.averageBitRate(
    renderSize: renderSize,
    frameRate: configuration.frameRate
)
```

Pass `fps` into frame count, frame duration, and output timestamp calculations instead of the fixed `exportFPS`. Pass `averageBitRate` into `AVVideoAverageBitRateKey`.

Extend `composeFrame` with explicit export overlay options:

```swift
private func composeFrame(
    from sourceImage: CIImage,
    snapshot: FrameSnapshot,
    pointerSnapshot: PointerSnapshot?,
    project: RecordingProject,
    preparedAssets: PreparedRenderAssets,
    includesCursor: Bool = true,
    includesClickFeedback: Bool = true
) -> CIImage
```

Use `includesClickFeedback` to suppress the ripple and `includesCursor` to suppress only the cursor image. Keep preview calls on both defaults so preview behavior does not regress. Preserve the existing `preset:` overloads by delegating to recommended MP4 configuration, because preview and existing tests still use `ExportPreset`.

- [ ] **Step 4: Run render tests**

Run the command from Step 2.

Expected: both suites pass.

- [ ] **Step 5: Commit renderer plumbing**

```bash
git add Sources/Core/Render/RenderModels.swift Tests/Render/ExportFilenameTests.swift Tests/Render/ExportConfigurationTests.swift
git commit -m "Apply export settings to MP4 rendering"
```

### Task 3: Add Export State to EditorViewModel

**Files:**
- Modify: `Sources/Features/Editor/EditorViewModel.swift:1-190`
- Modify: `Tests/Editor/EditorViewModelTests.swift:1-60`

- [ ] **Step 1: Write failing ViewModel tests**

```swift
func testEditorStartsWithRecommendedExportConfiguration() {
    let viewModel = makeViewModel()
    viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))

    XCTAssertEqual(viewModel.exportConfiguration, .recommended(for: .landscape))
    XCTAssertFalse(viewModel.isExportConfigurationModified)
}

func testEditingAndResettingExportConfiguration() {
    let viewModel = makeViewModel()
    viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))

    viewModel.updateExportResolution(.p720)
    XCTAssertTrue(viewModel.isExportConfigurationModified)
    XCTAssertEqual(viewModel.exportConfiguration.resolution, .p720)

    viewModel.resetExportConfiguration()
    XCTAssertFalse(viewModel.isExportConfigurationModified)
    XCTAssertEqual(viewModel.exportConfiguration, .recommended(for: .landscape))
}

func testAspectChangeResetsRecommendedExportGeometry() {
    let viewModel = makeViewModel()
    viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))
    viewModel.selectedAspectRatio = .portrait

    XCTAssertEqual(
        viewModel.exportConfiguration.renderSize(for: .portrait),
        CGSize(width: 1080, height: 1920)
    )
}
```

- [ ] **Step 2: Run ViewModel tests and verify failure**

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: compilation fails because export configuration state and methods are missing.

- [ ] **Step 3: Implement ViewModel state and actions**

Add:

```swift
@Published private(set) var exportConfiguration = ExportConfiguration.recommended(for: .landscape)
@Published private(set) var isExportConfigurationModified = false

func updateExportResolution(_ value: ExportResolution) { updateExportConfiguration { $0.resolution = value } }
func updateExportFrameRate(_ value: ExportFrameRate) { updateExportConfiguration { $0.frameRate = value } }
func updateExportQuality(_ value: ExportQuality) { updateExportConfiguration { $0.quality = value } }
func updateExportIncludesCursor(_ value: Bool) { updateExportConfiguration { $0.includesCursor = value } }
func updateExportIncludesClickFeedback(_ value: Bool) { updateExportConfiguration { $0.includesClickFeedback = value } }

func resetExportConfiguration() {
    exportConfiguration = .recommended(for: selectedAspectRatio)
    isExportConfigurationModified = false
}

private func updateExportConfiguration(_ change: (inout ExportConfiguration) -> Void) {
    change(&exportConfiguration)
    isExportConfigurationModified = exportConfiguration != .recommended(for: selectedAspectRatio)
}
```

Initialize the configuration during `configure(for:)`. Update `export()` and the save panel to use `exportConfiguration`; reject unavailable `.gif` without opening a save panel. Add an estimated-size label derived from trimmed duration, configured video bitrate, and a small audio allowance.

- [ ] **Step 4: Run ViewModel tests**

Run the command from Step 2.

Expected: `EditorViewModelTests` passes.

- [ ] **Step 5: Commit ViewModel support**

```bash
git add Sources/Features/Editor/EditorViewModel.swift Tests/Editor/EditorViewModelTests.swift
git commit -m "Add editable export settings state"
```

### Task 4: Build the Dedicated Single Export Panel

**Files:**
- Create: `Sources/Features/Editor/ExportPanelView.swift`
- Modify: `Sources/Features/Editor/EditorView.swift:1-255`
- Modify: `project.yml`
- Regenerate: `MouseLens.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the export inspector view**

`ExportPanelView` receives `EditorViewModel`, an optional fixed width, and an `onBack` closure. Its structure must be:

```swift
struct ExportPanelView: View {
    @ObservedObject var viewModel: EditorViewModel
    let fixedWidth: CGFloat?
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView { content.padding(.horizontal, 18).padding(.bottom, 16) }
            footer
        }
        .frame(width: fixedWidth)
        .frame(maxWidth: fixedWidth == nil ? .infinity : fixedWidth)
        .background(Color.white.opacity(0.04))
    }
}
```

Use two compact format cards. MP4 is enabled and selected. GIF is visible with a `Coming soon` secondary label and disabled. Settings use menu pickers for resolution, frame rate, and quality, plus toggles for cursor and click feedback. Show `Recommended` or `Modified`; enable `Reset to Recommended` only when modified. The footer shows the estimated size and a prominent `Export MP4` button.

- [ ] **Step 2: Switch EditorView between inspector modes**

Add:

```swift
private enum InspectorMode { case editing, export }
@State private var inspectorMode: InspectorMode = .editing
```

The top-bar Export button sets `.export`; it must no longer start exporting immediately. In desktop and compact layouts, render `ExportPanelView` when `.export` and the existing inspector when `.editing`. The export panel back button restores `.editing` without changing preview/timeline geometry.

Remove the old Export inspector section. Replace the permanent preview refresh icon with `Retry Preview` only for `.failed` preview state.

- [ ] **Step 3: Regenerate the Xcode project**

```bash
xcodegen generate
```

Expected: `ExportPanelView.swift` is included in the MouseLens target.

- [ ] **Step 4: Build the app**

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit the export UI**

```bash
git add Sources/Features/Editor/ExportPanelView.swift Sources/Features/Editor/EditorView.swift project.yml MouseLens.xcodeproj/project.pbxproj
git commit -m "Add dedicated editor export panel"
```

### Task 5: Documentation, Full Verification, and Canonical App

**Files:**
- Modify: `NEXT_VERSION_DEVELOPMENT_PLAN.md:167-194`

- [ ] **Step 1: Update the 1.1 plan wording**

Replace Presets/Custom with the approved single-panel behavior:

```markdown
- Format cards: MP4 H.264 and GIF.
- Selecting a format loads recommended values.
- Recommended values are directly editable in one settings section.
- Modified settings show a quiet Modified state and can be reset.
- GIF remains unavailable until the GIF encoder milestone.
```

- [ ] **Step 2: Run the full test suite**

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Rebuild only the canonical test app**

```bash
./scripts/prepare_local_test_app.sh
```

Expected canonical path:

```text
/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app
```

- [ ] **Step 4: Run the real-app workflow**

Verify in the canonical app:

1. Record a short Screen clip and finish into the editor.
2. Click Export; preview and timeline remain the same size and position.
3. Change MP4 resolution, frame rate, quality, cursor, and click feedback; the state changes to Modified.
4. Reset; settings return to 1080p, 30 fps, High, cursor on, click feedback on.
5. GIF is visible but cannot be selected.
6. Export MP4; open it and verify its dimensions/frame rate and overlay choices.
7. Trigger a preview failure only if practical; confirm Retry Preview is not present during normal operation.

- [ ] **Step 5: Commit verification documentation**

```bash
git add NEXT_VERSION_DEVELOPMENT_PLAN.md
git commit -m "Update export panel milestone"
```
