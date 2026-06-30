# MouseLens Export Panel Design

## Purpose

Replace the editor's compact Export inspector section with a dedicated export mode that is easier to scan and prepares the UI for GIF export without changing the current MP4 rendering pipeline.

## Interaction

- Clicking the editor header's `Export` button replaces the right inspector contents.
- The preview, playback controls, timeline, and editor window dimensions do not move or resize.
- A back control returns to the normal Video, Motion, Zoom, and Export inspector.
- Export uses the existing save-panel and completion behavior.

## Panel Structure

The panel keeps the current inspector width.

1. Header
   - Back control and `Export` title.
   - Export readiness state.
2. Mode control
   - `Presets` selected by default.
   - `Custom` for detailed settings.
3. Preset cards
   - `MP4` with `H.264` and output resolution summary.
   - `GIF` with short-clip guidance; disabled in the first UI-only iteration if encoding is not implemented.
4. Common controls
   - Resolution.
   - Frame rate.
   - Quality.
   - Include Cursor.
   - Include Click Feedback.
5. Fixed footer
   - Estimated output size when available.
   - Primary button whose label matches the selected format.

## Visual Rules

- Match the existing dark MouseLens editor and 8px-or-less control radius.
- Use compact format cards, restrained borders, and a single blue selection state.
- Keep the primary export button visually dominant.
- Do not show a permanent Refresh control.
- Show `Retry Preview` only when preview rendering has failed.
- Avoid nested cards; the export inspector is one full-height panel with individually framed preset options.

## States

- Ready: controls enabled and primary action available.
- Exporting: controls disabled with progress in the primary action area.
- Failed: inline error and retry export action.
- Preview failed: separate `Retry Preview` action in the header status area.
- GIF unavailable: GIF preset remains visible but clearly disabled until the encoder lands.

## Mockup Scope

The HTML mockup will show the complete editor with the Export inspector open. It will support switching between Presets and Custom, selecting MP4 or GIF, and changing representative controls. It is a visual prototype only and will not export media.

## Implementation Boundary

The first production implementation wires the new panel to the existing MP4 H.264 export path. GIF encoding and expanded background presets remain separate milestones.
