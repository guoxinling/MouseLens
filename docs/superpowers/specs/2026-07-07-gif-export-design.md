# MouseLens GIF Export Design

## Purpose

Add first-class GIF export to MouseLens without introducing a second visual rendering path. The GIF output must preserve the same edited result users already see in preview and MP4 export, while keeping the first release scope intentionally narrow and stable.

## Product Scope

GIF export is positioned as a high-quality demo format, not a lightweight meme or sticker format.

Supported settings for 1.1:

- Default: `720p / 15 fps`
- Optional: `1080p / 15 fps`
- Audio: not supported

GIF export must preserve the active project state:

- Trim range
- Background preset
- Padding
- Corner radius
- Rebuilt cursor
- Click feedback
- Auto zoom
- Manual zoom

The export experience should remain simple. Users choose `MP4` or `GIF` in the export panel, then adjust only the settings that matter for the selected format.

## Interaction

- `GIF` appears as a first-class format next to `MP4` in the export panel.
- Selecting `GIF` loads the recommended GIF configuration automatically.
- The primary action label changes to `Export GIF`.
- Resolution is selectable between `720p` and `1080p`.
- Frame rate is fixed at `15 fps` for the first release. It can be shown as read-only text or as a disabled single-value control.
- A warning appears when the selected trim range is long enough that the exported GIF is likely to be large or slow to encode.

The save workflow should match the existing export behavior:

- Use the current save-panel flow.
- Export completion behavior remains unchanged.
- Finder reveal remains controlled by the existing preference.

## Rendering Rule

GIF export must not introduce a preview/export drift problem.

The visual composition for GIF must come from the same source-of-truth used by MP4 export:

- source crop geometry
- background rendering
- content layout
- cursor placement
- click ripple placement
- zoom and camera framing

The only difference between MP4 and GIF should be the final encoding step.

MouseLens should not maintain:

- one preview composition path
- one MP4 composition path
- a separate GIF-only composition path

Instead, MP4 and GIF should both consume the same composed frame definition so that a timestamp renders identically across formats.

## Technical Direction

The first GIF implementation should use the existing frame composition pipeline and add a GIF encoder at the end.

Pipeline:

1. Resolve the active export configuration for GIF.
2. Resolve the active trim range.
3. Render each output timestamp through the existing composition path.
4. Downscale the composed frame to the selected GIF resolution.
5. Encode frames with native ImageIO GIF APIs.

This first release should prefer:

- correctness
- visual consistency
- maintainability

over:

- smallest possible file size
- advanced palette optimization
- maximum encoding speed

Do not block 1.1 on external encoders such as `gifski`.

## Export Panel Behavior

The export panel should adapt to the selected format.

For `MP4`, keep the current controls and recommended/default behavior.

For `GIF`, simplify the controls to the GIF-safe subset:

- Resolution: `720p`, `1080p`
- Frame rate: fixed `15 fps`

Controls that do not apply to GIF should be hidden or locked rather than shown as misleading editable inputs.

If the export panel shows estimated size, the estimate for GIF should be clearly labeled as approximate rather than exact.

## Warning and Guardrail Rules

GIF can become expensive quickly, so the first release needs explicit guardrails.

- If the trimmed duration exceeds a threshold, show a warning before export.
- The warning should recommend shortening the trim range rather than blocking export outright.
- The threshold should be product-driven and conservative enough to catch obviously large exports.

The first release does not need adaptive recommendation logic beyond this warning.

## Non-Goals for 1.1

Do not include these in the first GIF release:

- `30 fps` GIF
- arbitrary custom resolution
- WebP, APNG, or WebM export
- advanced palette tuning
- dithering controls
- quality presets specific to GIF
- audio support

These are expansion areas, not launch requirements.

## Validation

The implementation is complete only when these cases hold:

1. Export panel can switch between `MP4` and `GIF`.
2. Default GIF configuration is `720p / 15 fps`.
3. Users can switch GIF resolution to `1080p`.
4. Exported GIF uses the active trim range.
5. Exported GIF preserves background, padding, corner radius, cursor, click feedback, and zoom.
6. Exported GIF is visually aligned with the editor preview at the same timestamps.
7. Existing MP4 export behavior does not regress.

## Risks

### Preview/Export Drift

If GIF rendering forks from the current composition logic, the product will reintroduce one of its most expensive failure modes: preview looks correct, but export differs. The implementation should be rejected if it creates a format-specific composition path.

### File Size

High-quality GIFs can become large. This is acceptable for 1.1 as long as users receive a warning for longer clips and the default configuration remains `720p / 15 fps`.

### Performance

GIF encoding may be slower than MP4 export. This is acceptable for the first release, provided the UI exposes exporting state clearly and does not freeze unpredictably.
