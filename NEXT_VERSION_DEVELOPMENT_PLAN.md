# MouseLens Next Version Development Plan

Updated: 2026-06-29

This document defines the development plan after the first App Store submission of MouseLens 1.0.

The goal is to improve the product's visual quality and workflow completeness without destabilizing the core recording architecture.

## Current Baseline

MouseLens 1.0 has been submitted to App Review.

Release state:

- App Store version: `1.0`.
- Binary: `1.0 (1)`.
- Review state at the start of 1.1 development: `Waiting for Review`.
- Git baseline: tag `v1.0.0` on the submitted release commit.
- Active development branch: `codex/1.1-development`.

Stable foundations:

- Screen and Window recording.
- Raw video recorded without the native cursor.
- Pointer events recorded separately.
- Cursor, click feedback, and camera motion reconstructed in preview/export.
- Unified Zoom Track for Auto and Manual zoom segments.
- MP4 export.
- Built-in editor with trim, background, padding, corner radius, zoom, and export controls.
- App Store support/privacy pages and submission screenshots are archived in the repo.

Do not regress the core architecture:

- Do not record the native cursor into the source video.
- Do not couple cursor motion directly to camera motion.
- Do not reintroduce preview/export divergence.

## Version Strategy

### Branching and Review Isolation

- Keep `main` and tag `v1.0.0` as the submitted 1.0 baseline until review completes.
- Develop all planned 1.1 work on `codex/1.1-development`.
- Do not upload a 1.1 build while App Store version 1.0 is under review.
- If Apple requests a correction, create `release/1.0.1` from `v1.0.0`, apply only the review fix, and submit it as version `1.0`, build `2`.
- Do not merge unfinished 1.1 features into a 1.0 review-fix build.

### MouseLens 1.1

Focus:

- UI polish.
- More recording backgrounds.
- GIF export.
- Export workflow improvements.

This is the recommended next release because it improves perceived product quality with manageable technical risk.

### MouseLens 1.2

Focus:

- Presenter camera bubble.
- Camera overlay editing.
- Camera video export composition.

This should be separated because camera recording adds new permission, synchronization, privacy, and rendering risks.

## 1.1 Product Goals

MouseLens 1.1 should feel more polished before, during, and after recording.

Primary outcomes:

- The recording toolbar should feel like a professional capture utility.
- The editor should have a cleaner export workflow.
- Users should have more attractive built-in backgrounds.
- Users should be able to export short clips as GIFs.
- Preview and export should remain visually consistent.

## 1.1 Scope

### P0: UI System Refresh

#### Full-Screen Capture Entry

Support recording while another application occupies a native macOS Full Screen Space.

Required behavior:

- A user can start recording the currently selected Screen target from the menu bar or global shortcut without opening the normal MouseLens app window.
- Starting capture must not switch away from the full-screen application.
- The recording countdown and active recording toolbar may appear over the full-screen Space.
- MouseLens setup/countdown/recording controls must remain excluded from the recorded source.
- The normal setup window remains available for changing target, audio, aspect ratio, and settings outside the quick-start flow.

Implementation direction:

- Treat the regular SwiftUI setup window as configuration UI, not as the only recording entry point.
- Use the existing menu-bar item and global shortcut as the primary full-screen-safe entry path.
- Reuse the last valid Screen capture configuration for quick start.
- If a setup surface must appear over a full-screen application, host it in a non-activating `NSPanel` configured with `.canJoinAllSpaces` and `.fullScreenAuxiliary`; do not activate MouseLens or switch Spaces when showing it.
- Keep the recording control panel as a stable overlay sibling, never part of the captured content.

Acceptance criteria:

- Safari/Chrome in native macOS full screen can be recorded without leaving that Space.
- Menu-bar and shortcut quick start use the expected screen, microphone, system-audio, and aspect settings.
- Countdown and recording controls remain operable above the full-screen application.
- Screen and Window capture behavior outside full screen does not regress.

#### Recording Setup Toolbar

Replace the current pre-recording surface with a more compact horizontal toolbar.

Required controls:

- Screen mode.
- Window mode.
- Microphone toggle.
- System audio toggle.
- Aspect ratio selector.
- Record button.
- Settings entry.
- Close/minimize controls.

Design requirements:

- Preserve clear target selection.
- Avoid wide empty gaps.
- Prevent long screen/window names from pushing the Record button out of view.
- Use short labels in the toolbar and full names in menus/tooltips.
- Keep the first screen functional, not a marketing-style landing page.

Implementation notes:

- Treat the toolbar as a fixed capture command surface.
- Put long target names inside popovers or menus.
- Do not show recent projects or product notes on the recording entry screen.

#### Floating Recording Toolbar

Polish the existing recording overlay into a compact fixed control bar.

Required states:

- Countdown.
- Recording.
- Paused.
- Finishing.

Required controls:

- Recording indicator.
- Elapsed time.
- Pause/resume.
- Finish.

Design requirements:

- Finish is visually dominant and clearly destructive to the active recording.
- Pause/resume is secondary.
- Toolbar stays above other MouseLens UI.
- Toolbar does not appear in the recorded source video.
- Toolbar does not conflict with future camera bubble placement.

#### Editor Export Panel

Rework the right-side export area into a dedicated export panel.

Recommended structure:

- Header:
  - Live Preview.
  - Export.
- Recovery state:
  - Show `Retry Preview` only when live preview fails or becomes unavailable.
  - Do not show a normal `Refresh` button in the steady state.
- Format cards:
  - MP4, H.264.
  - GIF, disabled until the GIF encoder milestone.
- Selecting a format loads recommended values.
- Recommended values remain editable in one settings section:
  - Resolution.
  - Frame rate.
  - Quality.
  - Include cursor.
  - Include click feedback.
- Modified settings show a quiet `Modified` state and can be reset to recommended values.
- Footer:
  - Primary export button.
  - Estimated size.

Export scope for 1.1 is intentionally narrow:

- MP4 uses H.264 only.
- GIF is the only alternate format.
- Do not add H.265 in 1.1.
- Do not add WebM in 1.1.

Reasoning:

- H.264 has the best compatibility across QuickTime, browsers, chat apps, documentation tools, and social platforms.
- GIF covers short looping clips and lightweight sharing.
- H.265 and WebM add complexity without improving the core first-run export workflow.
- Live preview should update immediately; a permanent refresh control would imply that edits require manual rebuilds.

### P1: Background Wallpaper System

Add more built-in backgrounds suitable for screen recordings.

#### Background Types

Support these types:

- Gradient.
- Solid color.
- Image, optional for later.

Initial 1.1 implementation should prioritize gradients and solids because they are small, deterministic, and easy to render consistently.

#### Suggested Presets

Soft gradients:

- Aurora.
- Ocean.
- Moss.
- Sunrise.
- Plum.
- Sky.
- Coral.
- Mint.

Studio dark:

- Graphite.
- Midnight.
- Slate.
- Charcoal.

Clean light:

- Paper.
- Cloud.
- Mist.
- Porcelain.

Product colors:

- Blue.
- Green.
- Purple.
- Warm.

#### UI Requirements

- Backgrounds are selected through visual swatches, not text-only dropdowns.
- Swatches should preview the actual background.
- Selected background is clearly marked.
- Background changes apply instantly in the preview.
- Background rendering in export must match preview.

#### Model Direction

Use a model similar to:

```swift
struct BackgroundPreset: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case solid
        case gradient
        case image
    }

    var id: String
    var name: String
    var kind: Kind
    var colors: [String]
    var imageName: String?
}
```

Exact fields can follow existing project patterns.

#### Rendering Rule

Preview and export must share the same background rendering logic.

Avoid separate preview-only gradients or export-only Core Image fallbacks that can drift visually.

### P1: GIF Export

Add GIF export for short clips.

#### First Release Scope

Supported presets:

- GIF 720p, 15 fps, balanced quality by default.
- GIF 1080p, 15 fps, balanced quality as the only higher-resolution option.

#### Product Rules

- GIF export uses the active trim range.
- GIF export includes current background, padding, rounded corners, cursor, click feedback, and zoom.
- GIF export does not include audio.
- If the selected range is longer than 30 seconds, show a size/performance warning.
- Default GIF export should favor reasonable file size over maximum quality.

#### Technical Direction

Pipeline:

1. Reuse current composition path to render frames.
2. Downscale to the selected GIF resolution.
3. Encode GIF from frames.

Possible implementation options:

- Native ImageIO GIF encoding for the first version.
- Later evaluate `gifski` or a palette optimization path if quality/file size is not acceptable.

Do not block 1.1 on advanced GIF compression.

#### Export Panel Integration

The export panel should treat GIF as a first-class preset:

- Preset card: `GIF`.
- Description: `720p / 15 fps default` with optional `1080p / 15 fps`.
- Button text: `Export GIF`.
- Estimated size shown when feasible.

### P2: Presenter Camera Bubble

This is tentatively planned for 1.2, not 1.1.

#### Product Scope

Recording setup:

- Camera toggle in the setup toolbar.
- Camera device selector, if multiple cameras exist.
- Camera permission prompt path.

Editor:

- Show/hide presenter bubble.
- Position: four corners.
- Size.
- Shape: circle or rounded rectangle.
- Border.
- Shadow.

Export:

- Camera bubble appears exactly where preview shows it.
- Camera can be excluded from export if disabled.

#### Architecture Rule

Do not bake the camera bubble into the raw screen/window video.

Use separate tracks:

- Screen/window source video.
- Pointer event timeline.
- Camera source video.
- Camera overlay style.

This preserves editability and matches MouseLens' existing post-composition approach.

#### Risks

- Camera permission flow.
- Screen + camera + audio synchronization.
- CPU and memory pressure during recording.
- Privacy policy updates.
- App Review explanation for camera permission.

Because of these risks, camera is intentionally separated from the 1.1 UI/background/GIF work.

## Suggested Milestones

### Milestone 1: UI Foundation

Deliverables:

- New recording setup toolbar.
- New floating recording toolbar.
- Export panel shell with current MP4 export path wired in.
- Full-screen-safe quick start from the menu bar and global shortcut.

Acceptance criteria:

- Screen and Window recording still work.
- Pause/resume/finish behavior is unchanged functionally.
- Toolbar does not overflow at narrow widths.
- Export MP4 works from the new panel.
- A native full-screen browser can be recorded without switching Spaces.

### Milestone 2: Background System

Deliverables:

- Background preset model.
- Visual swatch picker.
- 12-20 built-in backgrounds.
- Shared preview/export renderer.

Acceptance criteria:

- Changing background updates preview instantly.
- Export matches preview.
- Existing saved projects still load.
- Existing background settings migrate or fall back safely.

### Milestone 3: GIF Export

Deliverables:

- GIF preset in export panel.
- GIF encoding path.
- Basic size warning for long clips.

Acceptance criteria:

- GIF exports from current trim range.
- GIF includes current visual styling and cursor/click effects.
- Short GIF exports can be opened in Finder/Preview/Browser.
- Long clip warning appears before expensive export.

### Milestone 4: Polish and Release Prep

Deliverables:

- UI fit checks on small and large windows.
- Updated screenshots if the UI changes materially.
- Updated metadata if GIF export is marketed.
- Full test pass.
- Canonical app rebuild.

Acceptance criteria:

- `xcodebuild test -scheme MouseLens -destination 'platform=macOS'` passes.
- Canonical app runs:

```bash
./scripts/prepare_local_test_app.sh --open
```

- Screen recording smoke test passes.
- Window recording smoke test passes.
- MP4 export smoke test passes.
- GIF export smoke test passes.

## Test Plan

### Unit Tests

Add or update tests for:

- Background preset encoding/decoding.
- Background fallback for legacy projects.
- Preview/export background geometry consistency.
- Export preset selection.
- GIF output size and frame count.
- Toolbar state transitions, where testable through view model logic.

### Integration / Manual Tests

Use only the canonical local app:

```text
/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app
```

Required flows:

1. Screen recording:
   - Record.
   - Pause/resume.
   - Finish.
   - Preview.
   - Export MP4.
   - Export GIF.

2. Window recording:
   - Select a target window.
   - Record.
   - Finish.
   - Verify cursor and zoom alignment.
   - Export MP4.
   - Export GIF.

3. Editor visual controls:
   - Change background.
   - Change padding.
   - Change corner radius.
   - Add/delete Zoom segment.
   - Confirm preview/export match.

4. Layout:
   - Narrow window.
   - Wide window.
   - Long window title or screen name.
   - Dark mode.
   - Light mode if supported.

5. Native macOS full screen:
   - Put Safari or Chrome in native full screen.
   - Start Screen recording from the menu bar.
   - Repeat using the global shortcut.
   - Confirm MouseLens does not switch Spaces.
   - Confirm countdown and recording controls remain visible but are not captured.

## Out of Scope for 1.1

- Presenter camera bubble, unless explicitly pulled forward.
- WebM export.
- Cloud upload or sharing.
- AI subtitles.
- AI noise reduction.
- Keyboard keystroke overlay.
- Paid subscription or Pro gating.
- App update framework.

## Product Risks

### UI Scope Creep

The export panel can easily become too complex.

Mitigation:

- Keep Presets first.
- Hide advanced controls under Custom.
- Do not add unsupported formats just because they appear in mockups.

### Preview/Export Drift

MouseLens has already had issues where preview and export diverged.

Mitigation:

- Reuse rendering models.
- Add tests for geometry and visual style mapping.
- Avoid separate code paths for similar concepts.

### GIF Performance

GIF encoding can become slow or produce huge files.

Mitigation:

- Start with 480p/15fps.
- Warn on long durations.
- Keep advanced compression for a later iteration.

### Camera Complexity

Camera looks simple in UI but is a multi-track recording feature.

Mitigation:

- Keep camera in 1.2.
- Preserve separate camera source and overlay style.
- Do not compromise raw video / post-composition architecture.

## Recommended Next Step

Start with Milestone 1:

1. Refactor the recording setup toolbar.
2. Refactor the floating recording toolbar.
3. Introduce the export panel shell while keeping MP4 export behavior unchanged.

Only after the UI shell is stable should the background system and GIF export be added.
