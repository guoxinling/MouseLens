# Task 4 Report

## 2026-07-08

### Scope completed

- Implemented `GIFFrameEncoder` in `Sources/Core/Render/RenderModels.swift` using ImageIO + `UTType.gif`.
- Branched `VideoRenderer.renderVideo(for:configuration:destinationURL:)` at the encoding edge so `.mp4` keeps the AVAssetWriter path and `.gif` renders composed frames into an ImageIO destination.
- Reused the existing composition pipeline for source-backed GIF export and added a debug-frame GIF fallback for projects without a source video.
- Added deterministic encoder coverage in `Tests/Render/GIFEncodingTests.swift`.
- Regenerated `MouseLens.xcodeproj/project.pbxproj` with `xcodegen generate` so the new test file is included.

### TDD evidence

#### RED

Command:

```bash
xcodegen generate
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/GIFEncodingTests
```

Observed failure:

```text
Tests/Render/GIFEncodingTests.swift:18:13: error: cannot find 'GIFFrameEncoder' in scope
```

This was the expected missing-encoder failure.

#### GREEN

Command:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/GIFEncodingTests \
  -only-testing:MouseLensTests/ExportConfigurationTests \
  -only-testing:MouseLensTests/ExportFilenameTests
```

Observed result:

```text
Test Suite 'MouseLensTests.xctest' passed
Executed 23 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

### Implementation notes

- The GIF encoder writes loop count `0` for infinite looping and sets both clamped and unclamped frame delay properties.
- `GIFEncodingTests` now asserts the persisted frame delay at GIF centisecond precision, since ImageIO quantizes `1/15` to `0.07` when reading the file back.
- Debug GIF rendering now converts the generated CI background to `CGImage` before drawing into the bitmap context, which avoids the Core Image draw warnings seen during fallback export.

### Additional verification

I also ran the stale editor expectation test to understand full-suite fallout:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/EditorViewModelTests/testGIFExportUsesRendererPathWhenSelected
```

Result:

```text
EditorViewModelTests.testGIFExportUsesRendererPathWhenSelected failed
Expected GIF export to fail in the renderer until Task 4 lands.
```

This failure is expected after Task 4 because the test still asserts the old pre-implementation behavior. The file is outside this task's ownership, so I did not update it here.

### Workspace notes

- Left the unrelated untracked file `docs/superpowers/plans/2026-07-02-background-library-implementation.md` untouched.
- `xcodegen generate` rewrote `MouseLens.xcodeproj/project.pbxproj` and preserved other in-flight project-file changes instead of reverting them.

## Review follow-up required
- Restore the intended architecture: one shared frame-production path, branch only at the final encoding edge.
- Apply the same normalizedRenderError behavior to GIF source export as MP4.
- Update the stale editor integration expectation now that GIF rendering is implemented.
- Add loop-count assertion to GIFEncodingTests.

## 2026-07-08 Review fix wave

### Scope completed

- Restored the source-backed export architecture so MP4 and GIF now share one composed-frame production path in `VideoRenderer`, with format-specific branching only at the final encoding step.
- Applied `normalizedRenderError(_:for:)` to source GIF export so legacy MP4 decode failures are normalized the same way as MP4 export.
- Updated `EditorViewModelTests.testGIFExportUsesRendererPathWhenSelected` to assert the shipped behavior instead of the pre-Task-4 failure expectation.
- Expanded `GIFEncodingTests` to assert the file-level GIF loop count is `0` in addition to frame count and delay.
- Kept project generation stable; no `project.pbxproj` changes were required for this fix wave.

### Root-cause notes

- The Task 4 renderer landed with two source-export loops: one path composed `CIImage` frames into `AVAssetWriter` buffers for MP4, while a second path independently regenerated timestamps, source frames, camera snapshots, and pointer snapshots for GIF.
- That duplication created the architectural drift called out in review and also left GIF source export outside the existing `normalizedRenderError` catch that protects MP4 export from raw legacy-decode errors.
- The stale editor test was still asserting the old “GIF export should fail” expectation even though the renderer path now succeeds for debug/no-source projects.

### Implementation notes

- Added `renderSourceFrames(...)` to centralize source timing, frame extraction, snapshot generation, pointer sampling, and `composeFrame(...)` work.
- Added `forEachRenderFrameTiming(...)` so the shared source path derives timestamps from one helper instead of re-implementing frame math per format.
- Replaced the old GIF-only source render loop with a `CGImage` collection closure fed by `renderSourceFrames(...)`.
- Replaced the MP4 source render loop body with the same shared producer, rendering the composed `CIImage` directly into pixel buffers before append.
- Wrapped `AVAssetWriter` in `AssetWriterBox` to remove the `@Sendable` capture warnings from the focused build output.

### TDD / verification evidence

#### Baseline red

Command:

```bash
xcodegen generate
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/GIFEncodingTests \
  -only-testing:MouseLensTests/ExportConfigurationTests \
  -only-testing:MouseLensTests/ExportFilenameTests \
  -only-testing:MouseLensTests/EditorViewModelTests/testGIFExportUsesRendererPathWhenSelected
```

Observed failure:

```text
EditorViewModelTests.testGIFExportUsesRendererPathWhenSelected failed
Expected GIF export to fail in the renderer until Task 4 lands.
```

This confirmed the known stale integration expectation before the fix wave.

#### Green after test update

Command:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/GIFEncodingTests \
  -only-testing:MouseLensTests/ExportConfigurationTests \
  -only-testing:MouseLensTests/ExportFilenameTests \
  -only-testing:MouseLensTests/EditorViewModelTests/testGIFExportUsesRendererPathWhenSelected
```

Observed result:

```text
Test Suite 'Selected tests' passed
Executed 24 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

#### Green after renderer refactor and warning cleanup

Command:

```bash
xcodebuild -project MouseLens.xcodeproj -scheme MouseLens -configuration Debug \
  -derivedDataPath .DerivedDataTests test \
  -only-testing:MouseLensTests/GIFEncodingTests \
  -only-testing:MouseLensTests/ExportConfigurationTests \
  -only-testing:MouseLensTests/ExportFilenameTests \
  -only-testing:MouseLensTests/EditorViewModelTests/testGIFExportUsesRendererPathWhenSelected
```

Observed result:

```text
Test Suite 'Selected tests' passed
Executed 24 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

### Notes

- `xcodebuild` was reliable in this wave, so no additional workaround command was needed.
- The standard destination-selection warning from `xcodebuild` and App Intents metadata “skipped” warning still appear, but the renderer-specific sendability warnings from `RenderModels.swift` are gone.
