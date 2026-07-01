# MouseLens Background Library Design

Updated: 2026-07-01

## Summary

MouseLens 1.1 replaces the current weak background set with a curated library of eight premium presets:

- 4 gradient backgrounds
- 4 wallpaper-style image backgrounds

The goal is not broad customization. The goal is a smaller library with a high hit rate for real screen recordings.

The library should feel more visually assertive than the current set. It should lean toward showcase-quality output while still respecting the recorded window as the primary visual subject.

## Product Direction

This library intentionally leans toward a stronger visual identity than the 1.0 background set.

The chosen direction is:

- More visual than the current muted library
- More hero-oriented than a purely safe utility set
- Still constrained by recording readability and export stability

This means:

- Some presets may be noticeably bold
- The library may include 2-3 clearly showcase-oriented options
- No preset may become more visually important than the recorded content

The difference from Screen Studio should not be a different category taxonomy. The difference should be that MouseLens backgrounds are selected and tuned as part of a recording composition system, not just as a wallpaper browser.

## Scope

This spec covers:

- The 1.1 built-in background preset library
- Visual rules for each preset
- Data model direction
- Editor presentation
- Preview and export rendering consistency
- Migration from the current enum-based background set

This spec does not cover:

- User-uploaded custom images
- Background packs or downloads
- Seasonal or branded background collections
- Background animation
- Image editing controls such as crop, scale, pan, blur amount, or overlays

## Final Library Composition

MouseLens 1.1 ships with eight built-in presets.

### Gradient Presets

1. `Aurora Air`
   - Light cool blue-cyan gradient
   - Serves as the best default general-purpose preset

2. `Sunset Bloom`
   - Warm coral, soft orange, and light violet blend
   - Serves as the most socially expressive gradient preset

3. `Midnight Pulse`
   - Deep navy-to-black gradient with subtle edge glow
   - Serves dark-mode recordings and code-heavy scenes

4. `Silver Mist`
   - Very light grey-blue, low-contrast premium surface
   - Serves documentation-style and minimal presentations

### Wallpaper-Style Image Presets

1. `Soft Glass`
   - Abstract glass-like highlights with restrained layered reflections
   - Serves as the strongest product-hero wallpaper

2. `Tidal Glow`
   - Bright blue-green abstract light depth with a small warm light accent
   - Serves as the brighter premium wallpaper that adds energy without obvious texture

3. `Luminous Drift`
   - Clean abstract luminous flow with soft atmosphere and minimal visible texture
   - Serves visually richer showcase exports without distracting material detail

4. `Horizon Glow`
   - Abstract spatial light depth with distant horizon-like staging
   - Serves cinematic but non-literal presentation scenes

## Role Allocation

Each preset should earn a specific role in the library.

### Default High-Frequency Presets

- `Aurora Air`
- `Silver Mist`

These should be the safest and most reusable options.

### Hero / Showcase Presets

- `Soft Glass`
- `Sunset Bloom`

These should create the strongest first impression in social and store-facing visuals.

### Dark Recording Presets

- `Midnight Pulse`
- `Horizon Glow`

These should remain stable for dark windows, code editors, and terminal-heavy recordings.

### Atmospheric Accent Presets

- `Tidal Glow`
- `Luminous Drift`

These add variety, motion, and visual lift without becoming novelty backgrounds.

## Visual Rules

The presets must differ by more than color alone. Composition, lighting, and material impression must also differ.

### `Aurora Air`

Should include:

- Light cool tones
- Soft transparency feeling
- Clean highlight flow
- Large calm areas

Should avoid:

- Strong purple dominance
- Rainbow or neon behavior
- Looking like a generic system wallpaper

### `Sunset Bloom`

Should include:

- Warm coral and orange energy
- Some soft pink or light violet transition
- A memorable visual signature

Should avoid:

- Candy color treatment
- Over-saturation
- Youthful or decorative “cute” styling

### `Midnight Pulse`

Should include:

- Dense deep navy and black structure
- Subtle low-key glow
- Controlled depth

Should avoid:

- Cyberpunk neon
- Gaming aesthetics
- Fluorescent blue-purple glow

### `Silver Mist`

Should include:

- Very light cool neutrals
- Soft premium paper or photography backdrop feeling
- Low contrast

Should avoid:

- Dirty greys
- Warm yellow cast
- Generic office-template blandness

### `Soft Glass`

Should include:

- Abstract reflective softness
- Light glass layering
- Controlled highlight structure
- Premium product-render feeling

Should avoid:

- Literal glass objects
- Hard refraction complexity
- Bright hotspots that compete with the recording window

### `Tidal Glow`

Should include:

- Blue-green luminous depth
- A small amount of warm accent light
- Clean abstract spatial layering
- Bright but premium energy

Should avoid:

- Grey-dominant mood
- Visible material texture
- Scenic or photographic interpretation
- Busy light noise

### `Luminous Drift`

Should include:

- Soft continuous light flow
- Airy abstract atmosphere
- Slightly expressive but still clean composition
- Very low visible texture

Should avoid:

- Literal fabric texture
- Patterning
- Tactile realism
- Any surface detail that pulls attention from the recording window

### `Horizon Glow`

Should include:

- Spatial depth
- Soft distant light boundary
- A suggestion of perspective without literal scenery

Should avoid:

- Real sky
- Real sea
- Mountains
- Cities
- Any identifiable landscape subject

## Global Prohibitions

All eight presets must avoid:

- Recognizable subject matter
- Repeating patterns
- High-frequency texture
- Material or photographic detail that competes with the content frame
- Strong purple-led palettes
- Heavy black corner vignettes
- Local highlight noise that makes cursor or click feedback hard to read
- Color contrast that causes the recorded window to lose edge definition

## Technical Composition Model

The editor may continue to support multiple background technologies internally, but the user-facing experience should present a single curated mixed library.

### Rendering Types

The 1.1 library should use:

- `gradient`
- `wallpaper`

It should not introduce `solid color` or `custom image upload` in this milestone.

### Gradient Implementation

Gradient presets should remain code-defined, not stored as bitmaps.

Each gradient preset should support a render definition that can express:

- Base colors
- Gradient direction
- Optional secondary highlight layer
- Optional vignette or light falloff layer

The exact structure can follow project conventions, but it should be flexible enough to represent the four approved gradients without duplicating rendering logic.

### Wallpaper Implementation

Wallpaper presets should be shipped as bundled controlled assets.

Constraints:

- No user editing controls in 1.1
- No free repositioning or scaling UI
- Preset selection only

Wallpaper assets should be prepared at sufficiently high resolution for export use and should support aspect adaptation through shared composition rules rather than per-screen ad hoc handling.

## Data Model Direction

The current enum-only background model is too rigid for the approved library.

1.1 should evolve the model from a hard-coded style enum into a preset-based model that still remains simple.

The model should be able to represent:

- Stable preset `id`
- Display `name`
- Preset `kind`
- Render definition
- Preview definition when needed

A model in this family is sufficient:

```swift
struct BackgroundPreset: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case gradient
        case wallpaper
    }

    var id: String
    var name: String
    var kind: Kind
    var gradient: GradientDefinition?
    var assetName: String?
}
```

The exact fields may differ, but the architecture should support future growth without requiring a UI rewrite.

## Editor Presentation

The editor should present the eight presets in one curated mixed grid.

Rules:

- Do not make the primary picker feel like a technical category browser
- Do not require the user to first choose `Gradient` or `Wallpaper`
- Show all eight presets together as first-class choices
- Each swatch must preview the actual visual character of the preset
- Selection must be visually obvious

Optional future filtering can be added later, but 1.1 should default to a single mixed presentation because the library is intentionally small.

## Preview and Export Consistency

Preview and export must use the same background resolution path.

Required rule:

- A selected background preset resolves into one shared background render layer
- That shared layer then enters the same composition pipeline for padding, corner radius, cursor, click feedback, and zoom

This avoids:

- Preview-only gradients that do not match export
- Export-only image treatment that shifts tone or brightness
- Separate implementations that drift visually over time

Consistency is especially important because 1.1 also targets GIF export and stronger showcase presets, both of which amplify drift if composition paths diverge.

## Geometry and Aspect Rules

The background system must remain stable under:

- `16:9`
- `9:16`
- `1:1`

Rules:

- Gradient presets must remain visually balanced across all three aspect ratios
- Wallpaper presets must avoid destructive cropping that breaks their composition
- Background composition must stay subordinate to the content frame and padding system
- Rounded corners and padding must visually read the same way in preview and export

For wallpapers, the adaptation rule should prioritize preserving the intended focal composition rather than filling aggressively at any cost.

## Performance and Interaction Requirements

Switching backgrounds should feel immediate.

Required behaviors:

- Selecting a background updates preview instantly
- No blocking “rebuilding preview” loop for normal background changes
- Cursor, click feedback, and playback controls remain unaffected by background selection changes

If a wallpaper asset requires decoding or caching, that work must be handled in a way that preserves the perception of instant editing.

## Migration Strategy

Existing projects using the current background enum must not lose visual intent.

Migration rules:

- Any current preset that has a direct replacement maps to its closest new equivalent
- If a direct replacement does not exist, map to the nearest approved fallback
- Projects must always open with a valid background
- Migration must not break saved projects or exported output

This should be treated as a compatibility migration, not a destructive reset.

## Testing Requirements

The implementation plan should include both model tests and real-app verification.

### Model / Rendering Tests

- Preset decoding and encoding
- Migration from legacy enum backgrounds
- Gradient render determinism
- Wallpaper preset lookup safety
- Preview/export background resolution using the same input preset

### Geometry Tests

- Background stability across `16:9`, `9:16`, and `1:1`
- Wallpaper composition remains visually sane under non-landscape export
- Padding and corner radius behavior remain consistent after background changes

### Real App Verification

Verify in the canonical app:

- All eight presets appear in the editor grid
- Selecting any preset updates preview immediately
- The most vivid presets still preserve window readability
- Dark presets keep cursor and click ripple visible
- Exported MP4 matches preview
- Exported GIF matches preview closely enough for 1.1 quality expectations

## Risks

### Risk: Hero presets overpower content

Mitigation:

- Strictly enforce the global prohibitions
- Keep readable window contrast as a hard acceptance criterion

### Risk: Wallpaper presets feel too close to Screen Studio

Mitigation:

- Favor abstract material and light compositions over literal wallpaper imagery
- Keep the library smaller and more composition-driven

### Risk: Preview/export drift

Mitigation:

- Single background resolution path
- Shared composition pipeline
- Explicit preview/export verification for every preset

### Risk: Wallpaper aspect adaptation looks broken in portrait or square

Mitigation:

- Prepare wallpaper assets with composition-aware cropping tolerance
- Verify all presets across all supported aspect ratios before release

## Acceptance Criteria

The background library work is complete when:

- MouseLens ships with exactly eight approved built-in presets for 1.1
- The library contains four gradients and four wallpaper-style image backgrounds
- The picker presents them as one curated mixed library
- The presets are visually differentiated by composition and light, not just color
- Background switching is immediate in the editor
- Preview and export match
- Legacy projects migrate safely
- The resulting library feels stronger, more premium, and less washed out than the current set
