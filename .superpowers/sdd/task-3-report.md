# Task 3 Report

Initial implementation landed in commit 82cd1f1.
Follow-up fixes pending from review:
- replace mismatched save-panel extension instead of appending (avoid .mp4.gif)
- tighten the save-panel test seam so tests exercise configuration/normalization logic
- add direct coverage for save-panel branching/URL normalization and keep availability semantics coherent for the current pre-Task-4 state

## Task 3 fix wave - 2026-07-08

### Root cause
- `presentExportSavePanel` normalized by blindly calling `appendingPathExtension`, so a user-entered mismatched suffix like `.mp4` became `.mp4.gif`.
- The injected test seam returned a final destination URL directly, which let tests skip the save-panel configuration and normalization logic entirely.
- GIF export is intentionally selectable before Task 4, but the behavioral proof needed to show "reachable export path, renderer still rejects it" without leaning on brittle string matching.

### Changes made
- Added `EditorViewModel.ExportSavePanelConfiguration` plus `exportSavePanelConfiguration(for:configuration:)` so save-panel branching is expressed as testable data.
- Narrowed the seam from "inject the final normalized URL" to "inject the raw save-panel selection after configuration," keeping panel branching and URL normalization inside `presentExportSavePanel`.
- Added `normalizedExportDestinationURL(_:requiredPathExtension:)` and changed normalization to replace a mismatched extension via `deletingPathExtension()` before appending the required suffix.
- Added focused editor tests for MP4/GIF save-panel metadata, mismatched-extension replacement, missing-extension appending, and the current GIF export state (`canExportSelectedFormat == true` while export still fails in the renderer path before Task 4).
- Added a focused render test for `ExportFormat.fileExtension` to keep filename/path-extension expectations explicit.

### Verification
1. Not applicable:
   - `swift test --filter 'EditorViewModelTests/(testMP4SavePanelConfigurationUsesVideoMetadata|testGIFSavePanelConfigurationUsesGIFMetadata|testSavePanelNormalizationReplacesMismatchedExtension|testSavePanelNormalizationAppendsMissingExtension|testGIFExportUsesRendererPathWhenSelected)'`
   - Output: `error: Could not find Package.swift in this directory or any of its parent directories.`

2. Red run:
   - `xcodebuild test -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj -scheme MouseLens -destination 'platform=macOS' -derivedDataPath /Users/guoxl/Documents/Playground/MouseLens/.DerivedDataReview -only-testing:MouseLensTests/EditorViewModelTests/testMP4SavePanelConfigurationUsesVideoMetadata -only-testing:MouseLensTests/EditorViewModelTests/testGIFSavePanelConfigurationUsesGIFMetadata -only-testing:MouseLensTests/EditorViewModelTests/testSavePanelNormalizationReplacesMismatchedExtension -only-testing:MouseLensTests/EditorViewModelTests/testSavePanelNormalizationAppendsMissingExtension -only-testing:MouseLensTests/EditorViewModelTests/testGIFExportUsesRendererPathWhenSelected -only-testing:MouseLensTests/ExportFilenameTests/testExportFormatUsesMatchingFileExtension -only-testing:MouseLensTests/ExportFilenameTests/testGIFExportFilenameUsesGIFExtension`
   - First failure: build error in `EditorViewModel.exportSavePanelConfiguration` (`missing return in static method expected to return 'EditorViewModel.ExportSavePanelConfiguration'`).
   - Second red signal after fixing returns: `EditorViewModelTests.testGIFExportUsesRendererPathWhenSelected` failed because the assertion compared localized error strings too literally.

3. Green run:
   - `xcodebuild test -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj -scheme MouseLens -destination 'platform=macOS' -derivedDataPath /Users/guoxl/Documents/Playground/MouseLens/.DerivedDataReview -only-testing:MouseLensTests/EditorViewModelTests/testMP4SavePanelConfigurationUsesVideoMetadata -only-testing:MouseLensTests/EditorViewModelTests/testGIFSavePanelConfigurationUsesGIFMetadata -only-testing:MouseLensTests/EditorViewModelTests/testSavePanelNormalizationReplacesMismatchedExtension -only-testing:MouseLensTests/EditorViewModelTests/testSavePanelNormalizationAppendsMissingExtension -only-testing:MouseLensTests/EditorViewModelTests/testGIFExportUsesRendererPathWhenSelected -only-testing:MouseLensTests/ExportFilenameTests/testExportFormatUsesMatchingFileExtension -only-testing:MouseLensTests/ExportFilenameTests/testGIFExportFilenameUsesGIFExtension`
   - Result: `Executed 7 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.

### Notes
- No Task 4 GIF rendering work was added. GIF remains selectable, save-panel plumbing is now format-aware, and renderer failure remains the explicit pre-Task-4 behavior.
- I left the unrelated untracked file `docs/superpowers/plans/2026-07-02-background-library-implementation.md` alone.
