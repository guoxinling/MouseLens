# MouseLens Current Product Status

Updated: 2026-05-25

This document records the current checkpoint state. It is meant to prevent drift between source code, test app builds, and product decisions.

## Current Architecture

- Raw screen/window video is recorded without the cursor.
- Pointer events are recorded separately.
- The cursor is reconstructed later in preview/export.
- Camera motion and cursor motion remain decoupled.
- The editor uses a unified Zoom Track: Auto and Manual zoom segments share one lane.

Do not return to the older approach of recording the native cursor directly into the source video.

## Canonical Test App

Only test this app:

```text
/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app
```

Build it with:

```bash
./scripts/prepare_local_test_app.sh
```

Build and open it with:

```bash
./scripts/prepare_local_test_app.sh --open
```

Do not test old `Build/`, `BuildRelease/`, or random Xcode DerivedData app bundles.

## Implemented

- Screen recording.
- Window recording path.
- Countdown before recording.
- Floating recording toolbar with pause/resume/finish controls.
- Canonical local test app build script.
- Stable local signing identity for repeated permission testing.
- Pointer event capture.
- Cursor reconstruction overlay.
- Click ripple feedback.
- Per-shot camera motion.
- Idle/transitioning/holding shot state.
- Eased shot transitions.
- First-click activation: opening segment stays full view until a meaningful click.
- Editor preview with playback controls.
- Trim timeline with playhead and in/out handles.
- Background swatches.
- Padding and corner radius controls.
- Motion Zoom Level control.
- Unified Zoom Track:
  - Auto segments generated from camera motion.
  - Manual segments added by user.
  - Auto and Manual displayed in the same lane.
  - Manual/user-edited segments override Auto.
  - Auto segment visualization no longer double-applies camera zoom.
- MP4 export path.
- Tests for camera planning, trim behavior, pointer normalization, preview composition, and zoom track behavior.

## Recently Stabilized

- Canonical app workflow is the only supported local test path.
- Editor no longer waits on styled preview MP4 for basic playback.
- Preview controls are separated from zoomed video content.
- Auto Zoom segments are now timeline controls/visual markers instead of an additional zoom layer.
- Window pointer normalization no longer falls back to full-screen coordinates when the window viewport does not match.

## Known Risks

- Window mode still needs repeated real recordings across different apps and display layouts.
- Multi-display window coordinates remain the highest-risk part of pointer alignment.
- Auto Zoom generation is useful but still needs product tuning around segment duration and threshold.
- Visual verification is still partly manual; screenshots/video inspection remain necessary.
- Distribution/notarization/update flow is not implemented.

## Current Test Baseline

Latest checkpoint:

- Full `xcodebuild test` passed.
- Canonical app rebuilt successfully.

Expected verification flow:

1. Run full tests.
2. Rebuild canonical app.
3. Screen mode recording:
   - first segment starts full view,
   - first click activates zoom,
   - Auto segment stays visible without corrupting motion,
   - cursor follows clicks.
4. Window mode recording:
   - cursor aligns with obvious click targets,
   - zoom activates after meaningful interaction,
   - no full-screen coordinate fallback drift.
5. Editor:
   - playhead, trim handles, Auto/Manual Zoom segments are independently draggable,
   - Manual segment overrides Auto,
   - Convert to Manual enables Set Area and per-segment zoom editing.

## Recommended Next Work

1. Run another real Window-mode test pass on simple windows first, then complex apps.
2. Tune Auto Zoom segment generation thresholds and durations.
3. Add stronger diagnostics for captured pointer events and chosen window viewport.
4. Polish Zoom Track UI labels and hit targets after behavior is stable.
