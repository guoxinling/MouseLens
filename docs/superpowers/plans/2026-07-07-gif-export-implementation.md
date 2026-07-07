# GIF Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class GIF export to MouseLens with a default `720p / 15 fps` preset, optional `1080p / 15 fps`, and visual parity with the existing preview and MP4 export paths.

**Architecture:** Keep a single visual composition pipeline. `EditorViewModel` and `ExportPanelView` will expose GIF as a real export format, while `ExportCoordinator` and `VideoRenderer` branch only at the final encoding step. MP4 keeps the current AVFoundation path; GIF renders the same composed frames and writes them through ImageIO.

**Tech Stack:** Swift 5, SwiftUI, AppKit, AVFoundation, CoreImage, ImageIO, UniformTypeIdentifiers, XCTest, XcodeGen, `xcodebuild`.

---

## File Structure

- Modify `Sources/Core/Render/RenderModels.swift`: enable GIF format, GIF-safe export configuration helpers, approximate size estimation, filename/content-type branching, ImageIO GIF encoding, and renderer branching.
- Modify `Sources/Features/Editor/EditorViewModel.swift`: format switching, GIF-specific configuration coercion, save-panel suffix/content-type handling, GIF warning state, and export label/caption behavior.
- Modify `Sources/Features/Editor/ExportPanelView.swift`: make GIF selectable, show only GIF-relevant controls, surface the long-duration warning, and keep MP4 behavior unchanged.
- Modify `Tests/Render/ExportConfigurationTests.swift`: recommended GIF settings, GIF availability, allowed settings, and GIF estimate coverage.
- Modify `Tests/Render/ExportFilenameTests.swift`: `.gif` filename coverage.
- Create `Tests/Render/GIFEncodingTests.swift`: deterministic ImageIO GIF encoding tests.
- Modify `Tests/Editor/EditorViewModelTests.swift`: export format switching, GIF button label, GIF warning state, and configuration coercion tests.
- Modify `NEXT_VERSION_DEVELOPMENT_PLAN.md`: narrow the documented GIF scope to the approved 1.1 behavior.
- Regenerate `MouseLens.xcodeproj/project.pbxproj` with XcodeGen so any new test file is tracked.

### Task 1: Enable GIF in the Export Configuration Model

**Files:**
- Modify: `Sources/Core/Render/RenderModels.swift:8-182`
- Modify: `Tests/Render/ExportConfigurationTests.swift`
- Regenerate: `MouseLens.xcodeproj/project.pbxproj`

- [ ] **Step 1: Extend render tests with failing GIF expectations**

Add these tests to `Tests/Render/ExportConfigurationTests.swift`:

```swift
func testGIFIsAvailableAndUsesApprovedDefaults() {
    let configuration = ExportConfiguration.recommended(
        for: .landscape,
        format: .gif
    )

    XCTAssertTrue(ExportFormat.gif.isAvailable)
    XCTAssertEqual(configuration.format, .gif)
    XCTAssertEqual(configuration.resolution, .p720)
    XCTAssertEqual(configuration.frameRate, .fps15)
    XCTAssertEqual(configuration.quality, .balanced)
    XCTAssertTrue(configuration.includesCursor)
    XCTAssertTrue(configuration.includesClickFeedback)
}

func testGIFAllowedResolutionsMatchReleaseScope() {
    XCTAssertEqual(
        ExportConfiguration.allowedResolutions(for: .gif),
        [.p720, .p1080]
    )
}

func testGIFFixedFrameRateIsFifteenFPS() {
    XCTAssertEqual(
        ExportConfiguration.allowedFrameRates(for: .gif),
        [.fps15]
    )
}

func testGIFEstimateIncreasesWithResolution() {
    let low = ExportConfiguration.recommended(for: .landscape, format: .gif)
    var high = low
    high.resolution = .p1080

    XCTAssertGreaterThan(
        ExportSizeEstimator.estimatedByteCount(for: high, aspectRatio: .landscape, duration: 8),
        ExportSizeEstimator.estimatedByteCount(for: low, aspectRatio: .landscape, duration: 8)
    )
}
```

- [ ] **Step 2: Run targeted render tests and confirm the API is missing**

Run:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/ExportConfigurationTests
```

Expected: test compilation fails because `recommended(for:format:)`, `allowedResolutions(for:)`, and `allowedFrameRates(for:)` do not exist, and `ExportFormat.gif.isAvailable` is still `false`.

- [ ] **Step 3: Add GIF-aware configuration helpers**

Update `Sources/Core/Render/RenderModels.swift` so the export model has an explicit GIF branch:

```swift
enum ExportFormat: String, CaseIterable, Equatable {
    case mp4
    case gif

    var label: String {
        switch self {
        case .mp4: "MP4"
        case .gif: "GIF"
        }
    }

    var isAvailable: Bool { true }
}

struct ExportConfiguration: Equatable {
    var format: ExportFormat
    var resolution: ExportResolution
    var frameRate: ExportFrameRate
    var quality: ExportQuality
    var includesCursor: Bool
    var includesClickFeedback: Bool

    static func recommended(
        for aspectRatio: ProjectAspectRatio,
        format: ExportFormat = .mp4
    ) -> ExportConfiguration {
        switch format {
        case .mp4:
            ExportConfiguration(
                format: .mp4,
                resolution: .p1080,
                frameRate: .fps30,
                quality: .high,
                includesCursor: true,
                includesClickFeedback: true
            )
        case .gif:
            ExportConfiguration(
                format: .gif,
                resolution: .p720,
                frameRate: .fps15,
                quality: .balanced,
                includesCursor: true,
                includesClickFeedback: true
            )
        }
    }

    static func allowedResolutions(for format: ExportFormat) -> [ExportResolution] {
        switch format {
        case .mp4: [.p720, .p1080, .p1440, .p2160, .p480]
        case .gif: [.p720, .p1080]
        }
    }

    static func allowedFrameRates(for format: ExportFormat) -> [ExportFrameRate] {
        switch format {
        case .mp4: ExportFrameRate.allCases.reversed()
        case .gif: [.fps15]
        }
    }
}
```

Keep `quality` in the model so the type stays stable across formats, but GIF should always normalize back to `.balanced`.

- [ ] **Step 4: Add GIF approximate size estimation**

Branch `ExportSizeEstimator.estimatedByteCount(...)` by format:

```swift
switch configuration.format {
case .mp4:
    // existing bitrate-based estimate
case .gif:
    let renderSize = configuration.renderSize(for: aspectRatio)
    let frameCount = max(Int((duration * Double(configuration.frameRate.rawValue)).rounded(.up)), 1)
    let bytesPerPixelFrame = renderSize.width >= 1920 ? 0.095 : 0.072
    return max(
        Int64((renderSize.width * renderSize.height * CGFloat(frameCount) * bytesPerPixelFrame).rounded()),
        0
    )
}
```

This is intentionally approximate. The UI will label it as an estimate rather than an exact value.

- [ ] **Step 5: Regenerate and rerun render tests**

Run:

```bash
xcodegen generate
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/ExportConfigurationTests
```

Expected: `ExportConfigurationTests` passes with GIF now available and constrained to the approved resolutions/frame rate.

- [ ] **Step 6: Commit the model changes**

```bash
git add Sources/Core/Render/RenderModels.swift Tests/Render/ExportConfigurationTests.swift MouseLens.xcodeproj/project.pbxproj
git commit -m "Add GIF export configuration model"
```

### Task 2: Wire GIF Format Selection into the Editor

**Files:**
- Modify: `Sources/Features/Editor/EditorViewModel.swift:17-209`
- Modify: `Sources/Features/Editor/ExportPanelView.swift:1-220`
- Modify: `Tests/Editor/EditorViewModelTests.swift:30-95`

- [ ] **Step 1: Add failing editor tests for GIF behavior**

Add these tests to `Tests/Editor/EditorViewModelTests.swift`:

```swift
func testSwitchingToGIFUsesApprovedDefaults() {
    let viewModel = makeViewModel()
    viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))

    viewModel.updateExportFormat(.gif)

    XCTAssertEqual(viewModel.exportConfiguration.format, .gif)
    XCTAssertEqual(viewModel.exportConfiguration.resolution, .p720)
    XCTAssertEqual(viewModel.exportConfiguration.frameRate, .fps15)
    XCTAssertEqual(viewModel.exportConfiguration.quality, .balanced)
    XCTAssertEqual(viewModel.exportButtonLabel, "Export GIF")
}

func testGIFResolutionCanSwitchTo1080p() {
    let viewModel = makeViewModel()
    viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))
    viewModel.updateExportFormat(.gif)

    viewModel.updateExportResolution(.p1080)

    XCTAssertEqual(viewModel.exportConfiguration.resolution, .p1080)
}

func testGIFExportShowsApproximateSizeCaption() {
    let viewModel = makeViewModel()
    viewModel.configure(for: makeProject(followStrength: 0.65, aspectRatio: .landscape))

    viewModel.updateExportFormat(.gif)

    XCTAssertEqual(viewModel.estimatedExportSizeCaption, "Approx. size")
}
```

Also extend the local helper signature near the bottom of the test file:

```swift
private func makeProject(
    followStrength: Double,
    aspectRatio: ProjectAspectRatio,
    backgroundPresetID: String = "aurora-air",
    manualZoomSegments: [ManualZoomSegment] = [],
    zoomTrackEdited: Bool = true,
    duration: TimeInterval = 1.0
) -> RecordingProject
```

and pass `duration` through the `RecordingProject(...)` initializer.

- [ ] **Step 2: Run editor tests and verify the format switcher is missing**

Run:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: compilation fails because `updateExportFormat(_:)` does not exist and the caption/button label logic is MP4-only.

- [ ] **Step 3: Add GIF state management to `EditorViewModel`**

Implement a format switcher and GIF coercion logic:

```swift
private let gifWarningDurationThreshold = 12.0

func updateExportFormat(_ format: ExportFormat) {
    exportConfiguration = .recommended(for: selectedAspectRatio, format: format)
    isExportConfigurationModified = false
    exportState = .idle
}

var showsGIFDurationWarning: Bool {
    exportConfiguration.format == .gif && (project?.trimmedDuration ?? 0) > gifWarningDurationThreshold
}

var gifDurationWarningText: String {
    "Long GIFs can become large. Trim the clip if you want a smaller file."
}

var estimatedExportSizeCaption: String {
    exportConfiguration.format == .gif ? "Approx. size" : "Estimated size"
}
```

Clamp GIF-only values inside the existing mutators:

```swift
func updateExportResolution(_ value: ExportResolution) {
    updateExportConfiguration {
        $0.resolution = ExportConfiguration.allowedResolutions(for: $0.format).contains(value) ? value : $0.resolution
    }
}

func updateExportFrameRate(_ value: ExportFrameRate) {
    updateExportConfiguration {
        $0.frameRate = ExportConfiguration.allowedFrameRates(for: $0.format).contains(value) ? value : $0.frameRate
    }
}
```

When the active format is `.gif`, force `quality = .balanced`, `includesCursor = true`, and `includesClickFeedback = true` in `updateExportConfiguration(_:)` so hidden controls cannot drift the state.

- [ ] **Step 4: Make the export panel format-aware**

Update `Sources/Features/Editor/ExportPanelView.swift` so the format cards are driven by `viewModel.exportConfiguration.format`:

```swift
formatCard(
    title: "MP4",
    subtitle: "H.264 · Recommended",
    iconText: "H.264",
    isSelected: viewModel.exportConfiguration.format == .mp4,
    isEnabled: true,
    action: { viewModel.updateExportFormat(.mp4) }
)
formatCard(
    title: "GIF",
    subtitle: "720p / 15 fps default",
    iconText: "GIF",
    isSelected: viewModel.exportConfiguration.format == .gif,
    isEnabled: true,
    action: { viewModel.updateExportFormat(.gif) }
)
```

For GIF, render only:

```swift
settingsRow("Resolution") { ...allowed GIF resolutions... }
settingsRow("Frame Rate") {
    Text("15 fps")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(AppTheme.mutedText)
}
```

Hide `Quality`, `Include Cursor`, and `Click Feedback` rows when `format == .gif`. Show the warning block when `showsGIFDurationWarning` is `true`.

- [ ] **Step 5: Rerun editor tests**

Run:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: GIF-related editor tests pass and existing MP4 export tests remain green.

- [ ] **Step 6: Commit the editor changes**

```bash
git add Sources/Features/Editor/EditorViewModel.swift Sources/Features/Editor/ExportPanelView.swift Tests/Editor/EditorViewModelTests.swift
git commit -m "Add GIF export UI state"
```

### Task 3: Add GIF Filenames, Save-Panel Behavior, and Coordinator Branching

**Files:**
- Modify: `Sources/Features/Editor/EditorViewModel.swift:114-168`
- Modify: `Sources/Core/Render/RenderModels.swift:2003-2120`
- Modify: `Tests/Render/ExportFilenameTests.swift`

- [ ] **Step 1: Add failing filename coverage for GIF**

Append this test to `Tests/Render/ExportFilenameTests.swift`:

```swift
func testGIFExportFilenameUsesGIFExtension() {
    let project = RecordingProject(
        id: UUID(),
        name: "Product Tour",
        createdAt: Date(timeIntervalSince1970: 1_776_368_400),
        duration: 10,
        sourceVideoURL: nil,
        events: [],
        cameraKeyframes: [CameraKeyframe(timestamp: 0, focus: .center, zoom: 1.0)],
        style: ProjectStyle(
            aspectRatio: .landscape,
            background: .aurora,
            cornerRadius: 26,
            shadowRadius: 30,
            followStrength: 0.7,
            clickEmphasis: 0.5,
            padding: 0.08
        )
    )
    let configuration = ExportConfiguration.recommended(for: .landscape, format: .gif)

    XCTAssertTrue(
        ExportCoordinator.exportFilename(for: project, configuration: configuration).hasSuffix("-gif-p720.gif")
    )
}
```

- [ ] **Step 2: Run filename tests and confirm GIF still ends in `.mp4`**

Run:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/ExportFilenameTests
```

Expected: the new GIF filename assertion fails because `exportFilename(for:configuration:)` still appends `.mp4`.

- [ ] **Step 3: Fix filename and save-panel branching**

In `ExportCoordinator.exportFilename(for:configuration:)`, switch on `configuration.format`:

```swift
static func exportFilename(for project: RecordingProject, configuration: ExportConfiguration) -> String {
    let stem = exportFilenameStem(for: project)
    switch configuration.format {
    case .mp4:
        return "\(stem)-mp4-\(configuration.resolution.rawValue).mp4"
    case .gif:
        return "\(stem)-gif-\(configuration.resolution.rawValue).gif"
    }
}
```

In `EditorViewModel.presentExportSavePanel(...)`, branch by format:

```swift
switch configuration.format {
case .mp4:
    panel.title = "Export MP4"
    panel.message = "Choose where MouseLens should save the exported video."
    panel.allowedContentTypes = [.mpeg4Movie]
case .gif:
    panel.title = "Export GIF"
    panel.message = "Choose where MouseLens should save the exported GIF."
    panel.allowedContentTypes = [.gif]
}
```

Normalize the final URL extension to match the format before returning it.

- [ ] **Step 4: Keep coordinator API stable while allowing GIF**

Leave the public `exportVideo(for:configuration:)` API in place, but ensure the coordinator no longer assumes MP4-only output when moving the rendered file:

```swift
let renderedURL = try await renderer.renderVideo(
    for: project,
    configuration: configuration,
    destinationURL: workingURL
)
return try moveExportedVideo(from: renderedURL, to: destinationURL)
```

The renderer will choose the actual file contents in Task 4. The coordinator only needs to stop assuming `.mp4`.

- [ ] **Step 5: Rerun filename tests**

Run:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/ExportFilenameTests \
  -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: GIF filenames and save-panel format logic now pass.

- [ ] **Step 6: Commit the coordinator/save-panel changes**

```bash
git add Sources/Core/Render/RenderModels.swift Sources/Features/Editor/EditorViewModel.swift Tests/Render/ExportFilenameTests.swift
git commit -m "Add GIF export file handling"
```

### Task 4: Implement ImageIO GIF Encoding in `VideoRenderer`

**Files:**
- Modify: `Sources/Core/Render/RenderModels.swift:849-2063`
- Create: `Tests/Render/GIFEncodingTests.swift`
- Regenerate: `MouseLens.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing GIF encoding tests**

Create `Tests/Render/GIFEncodingTests.swift` with deterministic encoder coverage that does not require a real recording fixture:

```swift
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MouseLens

final class GIFEncodingTests: XCTestCase {
    func testEncodeGIFWritesRequestedFrameCountAndDelay() throws {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")

        let frames = [
            makeSolidFrame(color: .red, size: CGSize(width: 32, height: 18)),
            makeSolidFrame(color: .blue, size: CGSize(width: 32, height: 18))
        ]

        try GIFFrameEncoder.encode(
            frames: frames,
            frameDelay: 1.0 / 15.0,
            destinationURL: destinationURL
        )

        guard let source = CGImageSourceCreateWithURL(destinationURL as CFURL, nil) else {
            return XCTFail("Failed to read GIF")
        }

        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        XCTAssertEqual(delay, 1.0 / 15.0, accuracy: 0.0001)
    }
}
```

Add the local helper at the bottom of the test file:

```swift
private func makeSolidFrame(color: CGColor, size: CGSize) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(color)
    context.fill(CGRect(origin: .zero, size: size))
    return context.makeImage()!
}
```

- [ ] **Step 2: Run the new GIF test and confirm the encoder is missing**

Run:

```bash
xcodegen generate
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/GIFEncodingTests
```

Expected: compilation fails because `GIFFrameEncoder` does not exist.

- [ ] **Step 3: Add a reusable GIF encoder helper**

Inside `Sources/Core/Render/RenderModels.swift`, add:

```swift
import ImageIO

enum GIFFrameEncoder {
    static func encode(
        frames: [CGImage],
        frameDelay: Double,
        destinationURL: URL
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw VideoRendererError.exportFailed
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]

        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw VideoRendererError.exportFailed
        }
    }
}
```

- [ ] **Step 4: Branch `VideoRenderer` into MP4 vs GIF at the encoding edge**

Update `renderVideo(for:configuration:destinationURL:)`:

```swift
func renderVideo(
    for project: RecordingProject,
    configuration: ExportConfiguration,
    destinationURL: URL
) async throws -> URL {
    switch configuration.format {
    case .mp4:
        return try await renderMP4(for: project, configuration: configuration, destinationURL: destinationURL)
    case .gif:
        return try await renderGIF(for: project, configuration: configuration, destinationURL: destinationURL)
    }
}
```

Move the existing MP4 body into `renderMP4(...)`. Then add `renderGIF(...)` that reuses the same prepared assets, crop planning, and `composeFrame(...)` output:

```swift
private func renderGIF(
    for project: RecordingProject,
    configuration: ExportConfiguration,
    destinationURL: URL
) async throws -> URL {
    let renderSize = configuration.renderSize(for: project.style.aspectRatio)
    let fps = Double(configuration.frameRate.rawValue)
    let frameDelay = 1.0 / fps
    let duration = project.trimmedDuration
    let frameCount = max(Int((duration * fps).rounded(.up)), 1)

    let preparedAssets = try prepareCompositionAssets(
        for: project,
        renderSize: renderSize,
        includeCursor: configuration.includesCursor,
        includeClickFeedback: configuration.includesClickFeedback
    )

    var frames: [CGImage] = []
    frames.reserveCapacity(frameCount)

    for frameIndex in 0..<frameCount {
        let timestamp = min(project.trimRange.start + (Double(frameIndex) / fps), project.trimRange.end)
        let image = try makeGIFFrame(
            at: timestamp,
            project: project,
            renderSize: renderSize,
            preparedAssets: preparedAssets
        )
        frames.append(image)
    }

    try GIFFrameEncoder.encode(frames: frames, frameDelay: frameDelay, destinationURL: destinationURL)
    return destinationURL
}
```

Add `makeGIFFrame(...)` as a thin wrapper around the existing `composeFrame(...)` result:

```swift
private func makeGIFFrame(
    at timestamp: Double,
    project: RecordingProject,
    renderSize: CGSize,
    preparedAssets: PreparedCompositionAssets
) throws -> CGImage {
    let frameImage = composeFrame(
        at: timestamp,
        project: project,
        preparedAssets: preparedAssets,
        renderSize: renderSize,
        includeCursor: true,
        includeClickFeedback: true
    )

    guard let cgImage = ciContext.createCGImage(frameImage, from: CGRect(origin: .zero, size: renderSize)) else {
        throw VideoRendererError.exportFailed
    }
    return cgImage
}
```

Keep loop count at `0` so exported GIFs loop indefinitely by default.

- [ ] **Step 5: Run GIF encoder tests**

Run:

```bash
xcodegen generate
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/GIFEncodingTests \
  -only-testing:MouseLensTests/ExportConfigurationTests \
  -only-testing:MouseLensTests/ExportFilenameTests
```

Expected: the GIF encoder tests pass and the configuration/filename tests remain green.

- [ ] **Step 6: Commit the renderer changes**

```bash
git add Sources/Core/Render/RenderModels.swift Tests/Render/GIFEncodingTests.swift MouseLens.xcodeproj/project.pbxproj
git commit -m "Implement GIF export renderer"
```

### Task 5: Final GIF UX Regression Pass and Documentation Update

**Files:**
- Modify: `NEXT_VERSION_DEVELOPMENT_PLAN.md:292-336`
- Modify: `Tests/Editor/EditorViewModelTests.swift`
- Modify: `Tests/Render/ExportConfigurationTests.swift`

- [ ] **Step 1: Update the next-version plan to the approved GIF scope**

Replace the old GIF section in `NEXT_VERSION_DEVELOPMENT_PLAN.md` so it documents:

```md
- Default: GIF 720p, 15 fps
- Optional: GIF 1080p, 15 fps
- Audio is not supported
- GIF preserves trim, background, padding, rounded corners, cursor, click feedback, and zoom
```

Remove references to 480p, 10 fps, 24 fps, or other optional presets from the 1.1 plan text.

- [ ] **Step 2: Add one last regression test for GIF warning state**

Append this editor test:

```swift
func testLongTrimmedGIFShowsWarning() {
    let viewModel = makeViewModel()
    let project = makeProject(
        followStrength: 0.65,
        aspectRatio: .landscape,
        duration: 14.0
    )

    viewModel.configure(for: project)
    viewModel.updateExportFormat(.gif)

    XCTAssertTrue(viewModel.showsGIFDurationWarning)
}
```

- [ ] **Step 3: Run the relevant suite**

Run:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/ExportConfigurationTests \
  -only-testing:MouseLensTests/ExportFilenameTests \
  -only-testing:MouseLensTests/GIFEncodingTests \
  -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: all targeted GIF and editor export tests pass.

- [ ] **Step 4: Run the full macOS test suite**

Run:

```bash
xcodebuild test -project MouseLens.xcodeproj -scheme MouseLens -destination 'platform=macOS' -quiet
```

Expected: full suite passes with no regressions in MP4 export, preview mapping, or editor behavior.

- [ ] **Step 5: Commit the documentation and regression updates**

```bash
git add NEXT_VERSION_DEVELOPMENT_PLAN.md Tests/Editor/EditorViewModelTests.swift Tests/Render/ExportConfigurationTests.swift Tests/Render/ExportFilenameTests.swift Tests/Render/GIFEncodingTests.swift
git commit -m "Finalize GIF export release scope"
```
