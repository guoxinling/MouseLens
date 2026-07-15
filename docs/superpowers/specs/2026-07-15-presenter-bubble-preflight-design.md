# Presenter Bubble Preflight Design

## Goal

MouseLens 1.2 should let users position their presenter camera before recording starts. When the user enables the camera from the Home toolbar, MouseLens shows an independent floating presenter bubble in the current Space. The bubble can be dragged to the final on-video position before Record is pressed.

The preview before recording, recording-time display, editor preview, MP4 export, and GIF export must use the same presenter bubble placement, size, corner radius, and mirror behavior.

## Scope

Included:

- Show a standalone floating presenter bubble as soon as presenter camera is enabled before recording.
- Allow direct drag positioning of that bubble before recording starts.
- Keep bubble position, size, corner radius, and mirror behavior consistent across preflight, recording, editor preview, and export.
- Make presenter video mirrored everywhere.
- Replace the current shape selector with a continuous corner radius slider.
- Add model extensibility for a future `presenterSource = camera/avatarImage`.

Excluded from this version:

- Virtual avatar generation.
- Background removal.
- Multiple presenter tracks.
- Real-time face tracking or auto-framing.
- Per-project camera device picker.

## User Journey

1. User opens MouseLens Home toolbar.
2. User toggles presenter camera on.
3. MouseLens requests camera permission if needed.
4. After permission is granted, an independent floating presenter bubble appears near the default bottom-right recording content position.
5. User drags the bubble to the desired location.
6. User starts recording.
7. The preflight bubble hides or transitions into the recording-time overlay without changing its visual position.
8. Recording ends and editor opens.
9. Editor preview shows the same bubble position, size, corner radius, and mirrored camera orientation.
10. Export produces the same result as editor preview.

## Product Rules

### Bubble Placement

Presenter bubble placement is stored as normalized coordinates relative to the styled video content rect, not raw screen coordinates.

This keeps the placement stable across:

- Screen capture and Window capture.
- Different export resolutions.
- Different aspect ratios.
- Padding changes.
- Preview and export render paths.

The existing corner-position enum should be migrated toward a free-position model. Existing projects with `topLeft`, `topRight`, `bottomLeft`, or `bottomRight` positions should decode into equivalent normalized anchor positions.

### Drag Behavior

The floating bubble should drag only within the expected video content safe area.

Drag behavior:

- Dragging moves the bubble center.
- The bubble remains fully visible inside the content rect.
- Drag updates are reflected immediately in Home state.
- The final position is saved into project style when recording completes.

The floating bubble should not capture keyboard focus or block typing in other apps.

### Mirroring

Presenter camera is always mirrored:

- Preflight floating bubble: mirrored.
- Recording-time bubble: mirrored.
- Editor preview bubble: mirrored.
- MP4 export bubble: mirrored.
- GIF export bubble: mirrored.

The implementation should not encode a separate mirrored source file. It should apply a horizontal transform in all composition surfaces so the stored source media stays neutral and render policy remains explicit.

### Corner Radius

The current `PresenterBubbleShape` control should be replaced in the UI by a continuous corner radius slider.

Recommended model:

- Store `cornerRadiusRatio: Double` in `0...0.5`, relative to bubble size.
- `0` means square.
- `0.5` means circle.
- Existing `circle` decodes to `0.5`.
- Existing `roundedRect` decodes from its saved radius into the nearest ratio.

The editor may keep quick actions later, but the primary control is the slider.

## Architecture

### Model

Extend `PresenterBubbleStyle` with:

- `normalizedCenter: NormalizedPoint`
- `cornerRadiusRatio: Double`
- `source: PresenterSource`

Add:

```swift
enum PresenterSource: String, Codable, Equatable {
    case camera
    case avatarImage
}
```

For 1.2, only `.camera` is active. `.avatarImage` is a reserved model value for future work and should not appear in UI yet.

Compatibility:

- Preserve decoding of existing `position` and `shape`.
- Save using the new normalized center and corner radius ratio.
- Keep migration deterministic so old projects render the same visual placement.

### Geometry

`PresenterOverlayGeometry.layout(...)` should become the single source of truth for:

- Bubble frame.
- Bubble clipping radius.
- Constraining bubble inside content rect.

Inputs:

- content rect
- normalized center
- normalized size
- corner radius ratio

Outputs:

- frame
- clipping radius

All surfaces must use this shared geometry:

- Home preflight floating bubble
- Recording floating toolbar or recording overlay
- Editor preview
- MP4 export
- GIF export

### Preflight Bubble Window

Add a lightweight floating panel for the standalone presenter bubble.

Rules:

- Appears only when Home toolbar is visible, capture state is idle, and presenter camera is enabled.
- Uses the active camera preview session.
- Floats across Spaces like the Home toolbar.
- Does not steal focus.
- Uses the same Space behavior as the Home toolbar.
- Hides before actual capture begins so it is not recorded into the raw screen video.

This panel is a control surface only. The final exported bubble is still composed from the separately recorded presenter media.

### Recording-Time Bubble

The recording-time bubble should use the same style and position. The current implementation places camera preview inside the recording toolbar; this should change to match preflight placement or use the same standalone bubble panel while recording.

If keeping it inside the recording toolbar temporarily, it must not change the persisted placement. The persisted placement comes from the preflight floating bubble.

### Preview and Export

Editor preview and export already compose presenter media as a separate overlay. Update those paths to:

- Use the new free-position geometry.
- Apply horizontal mirroring.
- Use corner radius ratio.
- Keep presenter bubble synchronized with source video time as currently implemented.

## Error Handling

- If camera permission is denied, keep the camera toggle off and show the existing permission guidance.
- If camera starts but produces no frames, do not save presenter media.
- If preflight preview fails, recording should still be possible without presenter media after clearly disabling the camera toggle.
- If the bubble would be outside the content rect after aspect or padding changes, clamp it back inside.

## Testing

Unit tests:

- Decode legacy `PresenterBubblePosition` into normalized centers.
- Decode legacy `PresenterBubbleShape` into corner radius ratio.
- Clamp dragged presenter center so the bubble remains inside content rect.
- `PresenterOverlayGeometry` returns the same frame for preview/export inputs.
- Mirroring flag is applied to preview/export presenter render surfaces.
- `PresenterSource.avatarImage` decodes but remains inactive in 1.2 UI.

App tests:

- Enable camera before recording and verify floating bubble appears.
- Drag bubble before recording and verify editor preview uses that position.
- Record with presenter enabled and verify preflight/recording/editor/export are mirrored consistently.
- Adjust corner radius slider and verify square, rounded, and circular results.
- Verify the bubble does not get captured into the raw screen video.
- Verify existing projects with old shape/position still open and render correctly.

## Acceptance Criteria

- Users can position their presenter camera before recording starts.
- The bubble position seen before recording matches editor preview and export.
- Presenter video is mirrored in every visible and exported surface.
- Shape selection is replaced by a continuous corner radius control.
- Existing presenter projects remain compatible.
- No virtual avatar UI appears in 1.2.
