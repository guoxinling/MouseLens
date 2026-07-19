# Background Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current eight hard-coded gradient-only backgrounds with the approved mixed library of four gradients and four wallpaper-style assets, while keeping project migration safe and preview/export visually aligned.

**Architecture:** Introduce a preset catalog layer that becomes the single source of truth for background identity, preview metadata, and render configuration. Keep legacy `ProjectBackgroundStyle` decoding alive only as a migration bridge. Move gradient and wallpaper resolution behind shared helpers consumed by both the editor preview and export renderer so UI and rendered files cannot drift.

**Tech Stack:** Swift, SwiftUI, AppKit, Core Image, XCTest, Xcode asset catalogs

---

## File Structure

### New files

- `Sources/Core/Storage/BackgroundPresetCatalog.swift`
  - Defines the new preset model, preset kind, gradient definition, wallpaper definition, legacy mapping, and the approved eight-preset catalog.
- `Sources/DesignSystem/BackgroundPreviewStyle.swift`
  - Builds SwiftUI gradients/images for the editor and swatches from catalog data.
- `Tests/Storage/BackgroundPresetCatalogTests.swift`
  - Covers catalog count, IDs, legacy mapping, and migration decoding.
- `Tests/Render/BackgroundRenderResolverTests.swift`
  - Covers gradient resolution, wallpaper lookup, and render input parity.

### Modified files

- `Sources/Core/Storage/ProjectModels.swift`
  - Replaces `ProjectBackgroundStyle` usage in `ProjectStyle` with a preset ID-backed value while preserving legacy decoding.
- `Sources/DesignSystem/AppTheme.swift`
  - Removes the giant `ProjectBackgroundStyle.gradient` switch in favor of catalog-driven preview helpers.
- `Sources/Features/Editor/EditorViewModel.swift`
  - Stores the selected preset ID, maps legacy projects, and saves the new style field.
- `Sources/Features/Editor/EditorView.swift`
  - Renders the mixed eight-item picker and swatches from the new catalog.
- `Sources/Core/Render/RenderModels.swift`
  - Replaces the hard-coded export gradient switch with catalog-driven background resolution shared with preview behavior.
- `Tests/Editor/EditorViewModelTests.swift`
  - Updates editor expectations and adds background-specific tests.
- `Tests/Storage/ProjectStoreTests.swift`
  - Updates fixture creation for the new style field and adds legacy JSON migration coverage.
- `MouseLens.xcodeproj/project.pbxproj`
  - Adds new source files, tests, and wallpaper assets.
- `Resources/Assets.xcassets/*`
  - Adds four wallpaper images as catalog-backed image sets.

## Task 1: Introduce the Background Preset Catalog and Migration Bridge

**Files:**
- Create: `Sources/Core/Storage/BackgroundPresetCatalog.swift`
- Modify: `Sources/Core/Storage/ProjectModels.swift`
- Test: `Tests/Storage/BackgroundPresetCatalogTests.swift`

- [ ] **Step 1: Write the failing catalog tests**

```swift
import XCTest
@testable import MouseLens

final class BackgroundPresetCatalogTests: XCTestCase {
    func testCatalogContainsApprovedEightPresetsInDisplayOrder() {
        XCTAssertEqual(BackgroundPresetCatalog.all.map(\.id), [
            "aurora-air",
            "sunset-bloom",
            "midnight-pulse",
            "silver-mist",
            "soft-glass",
            "tidal-glow",
            "luminous-drift",
            "horizon-glow"
        ])
    }

    func testLegacyStyleMapsToNewPresetIDs() {
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .aurora), "aurora-air")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .graphite), "midnight-pulse")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .sunrise), "sunset-bloom")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .ocean), "aurora-air")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .plum), "sunset-bloom")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .moss), "tidal-glow")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .paper), "silver-mist")
        XCTAssertEqual(BackgroundPresetCatalog.legacyPresetID(for: .midnight), "midnight-pulse")
    }

    func testProjectStyleDecodesLegacyBackgroundEnumIntoPresetID() throws {
        let data = """
        {
          "aspectRatio": "landscape",
          "background": "aurora",
          "cornerRadius": 10.35,
          "shadowRadius": 0,
          "followStrength": 0.72,
          "clickEmphasis": 0.54,
          "padding": 0.04
        }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(ProjectStyle.self, from: data)

        XCTAssertEqual(style.backgroundPresetID, "aurora-air")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS' \
  -only-testing:MouseLensTests/BackgroundPresetCatalogTests
```

Expected: build fails because `BackgroundPresetCatalogTests.swift` is not in the target and `BackgroundPresetCatalog` / `backgroundPresetID` do not exist.

- [ ] **Step 3: Add the catalog model and legacy migration bridge**

Create `Sources/Core/Storage/BackgroundPresetCatalog.swift`:

```swift
import Foundation

struct BackgroundGradientDefinition: Equatable, Codable {
    let colors: [RGBAColor]
    let startPoint: UnitPointDefinition
    let endPoint: UnitPointDefinition
}

struct BackgroundWallpaperDefinition: Equatable, Codable {
    let assetName: String
}

struct BackgroundPreset: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case gradient
        case wallpaper
    }

    let id: String
    let name: String
    let kind: Kind
    let gradient: BackgroundGradientDefinition?
    let wallpaper: BackgroundWallpaperDefinition?
}

struct RGBAColor: Equatable, Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct UnitPointDefinition: Equatable, Codable {
    let x: Double
    let y: Double
}

enum BackgroundPresetCatalog {
    static let all: [BackgroundPreset] = [
        .init(
            id: "aurora-air",
            name: "Aurora Air",
            kind: .gradient,
            gradient: .init(
                colors: [
                    .init(red: 0.91, green: 0.97, blue: 1.0, alpha: 1),
                    .init(red: 0.85, green: 0.95, blue: 0.92, alpha: 1),
                    .init(red: 0.84, green: 0.89, blue: 1.0, alpha: 1)
                ],
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            ),
            wallpaper: nil
        ),
        .init(
            id: "sunset-bloom",
            name: "Sunset Bloom",
            kind: .gradient,
            gradient: .init(
                colors: [
                    .init(red: 1.0, green: 0.93, blue: 0.82, alpha: 1),
                    .init(red: 1.0, green: 0.83, blue: 0.78, alpha: 1),
                    .init(red: 0.99, green: 0.88, blue: 0.95, alpha: 1)
                ],
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            ),
            wallpaper: nil
        ),
        .init(
            id: "midnight-pulse",
            name: "Midnight Pulse",
            kind: .gradient,
            gradient: .init(
                colors: [
                    .init(red: 0.05, green: 0.06, blue: 0.10, alpha: 1),
                    .init(red: 0.09, green: 0.12, blue: 0.22, alpha: 1),
                    .init(red: 0.14, green: 0.20, blue: 0.35, alpha: 1)
                ],
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            ),
            wallpaper: nil
        ),
        .init(
            id: "silver-mist",
            name: "Silver Mist",
            kind: .gradient,
            gradient: .init(
                colors: [
                    .init(red: 0.98, green: 0.97, blue: 0.94, alpha: 1),
                    .init(red: 0.90, green: 0.91, blue: 0.92, alpha: 1),
                    .init(red: 0.78, green: 0.84, blue: 0.88, alpha: 1)
                ],
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            ),
            wallpaper: nil
        ),
        .init(id: "soft-glass", name: "Soft Glass", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundSoftGlass")),
        .init(id: "tidal-glow", name: "Tidal Glow", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundTidalGlow")),
        .init(id: "luminous-drift", name: "Luminous Drift", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundLuminousDrift")),
        .init(id: "horizon-glow", name: "Horizon Glow", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundHorizonGlow"))
    ]

    static let defaultPresetID = "aurora-air"

    static func preset(id: String) -> BackgroundPreset {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    static func legacyPresetID(for style: ProjectBackgroundStyle) -> String {
        switch style {
        case .aurora, .ocean:
            return "aurora-air"
        case .sunrise, .plum:
            return "sunset-bloom"
        case .graphite, .midnight:
            return "midnight-pulse"
        case .paper:
            return "silver-mist"
        case .moss:
            return "tidal-glow"
        }
    }
}
```

Modify `ProjectStyle` in `Sources/Core/Storage/ProjectModels.swift`:

```swift
struct ProjectStyle: Codable, Equatable {
    let aspectRatio: ProjectAspectRatio
    let backgroundPresetID: String
    let cornerRadius: Double
    let shadowRadius: Double
    let followStrength: Double
    let clickEmphasis: Double
    let padding: Double

    var backgroundPreset: BackgroundPreset {
        BackgroundPresetCatalog.preset(id: backgroundPresetID)
    }

    enum CodingKeys: String, CodingKey {
        case aspectRatio
        case backgroundPresetID
        case background
        case cornerRadius
        case shadowRadius
        case followStrength
        case clickEmphasis
        case padding
    }

    init(
        aspectRatio: ProjectAspectRatio,
        backgroundPresetID: String,
        cornerRadius: Double,
        shadowRadius: Double,
        followStrength: Double,
        clickEmphasis: Double,
        padding: Double
    ) {
        self.aspectRatio = aspectRatio
        self.backgroundPresetID = backgroundPresetID
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.followStrength = followStrength
        self.clickEmphasis = clickEmphasis
        self.padding = padding
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let aspectRatio = try container.decode(ProjectAspectRatio.self, forKey: .aspectRatio)
        let backgroundPresetID: String
        if let presetID = try container.decodeIfPresent(String.self, forKey: .backgroundPresetID) {
            backgroundPresetID = presetID
        } else {
            let legacy = try container.decode(ProjectBackgroundStyle.self, forKey: .background)
            backgroundPresetID = BackgroundPresetCatalog.legacyPresetID(for: legacy)
        }

        self.init(
            aspectRatio: aspectRatio,
            backgroundPresetID: backgroundPresetID,
            cornerRadius: try container.decode(Double.self, forKey: .cornerRadius),
            shadowRadius: try container.decode(Double.self, forKey: .shadowRadius),
            followStrength: try container.decode(Double.self, forKey: .followStrength),
            clickEmphasis: try container.decode(Double.self, forKey: .clickEmphasis),
            padding: try container.decode(Double.self, forKey: .padding)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(backgroundPresetID, forKey: .backgroundPresetID)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(shadowRadius, forKey: .shadowRadius)
        try container.encode(followStrength, forKey: .followStrength)
        try container.encode(clickEmphasis, forKey: .clickEmphasis)
        try container.encode(padding, forKey: .padding)
    }
}
```

Keep `ProjectBackgroundStyle` in the file temporarily as a legacy decode bridge only. Do not remove it in this task.

- [ ] **Step 4: Add the new test file to the Xcode project**

Update `MouseLens.xcodeproj/project.pbxproj` to include `BackgroundPresetCatalogTests.swift` in the `MouseLensTests` target and `BackgroundPresetCatalog.swift` in the main app target.

- [ ] **Step 5: Run the catalog tests to verify they pass**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS' \
  -only-testing:MouseLensTests/BackgroundPresetCatalogTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C /Users/guoxl/Documents/Playground/MouseLens add \
  Sources/Core/Storage/BackgroundPresetCatalog.swift \
  Sources/Core/Storage/ProjectModels.swift \
  Tests/Storage/BackgroundPresetCatalogTests.swift \
  MouseLens.xcodeproj/project.pbxproj
git -C /Users/guoxl/Documents/Playground/MouseLens commit -m "Add background preset catalog"
```

## Task 2: Add Shared Preview/Render Background Resolution and Wallpaper Assets

**Files:**
- Create: `Sources/DesignSystem/BackgroundPreviewStyle.swift`
- Modify: `Sources/DesignSystem/AppTheme.swift`
- Modify: `Sources/Core/Render/RenderModels.swift`
- Modify: `MouseLens.xcodeproj/project.pbxproj`
- Create: `Resources/Assets.xcassets/BackgroundSoftGlass.imageset/Contents.json`
- Create: `Resources/Assets.xcassets/BackgroundTidalGlow.imageset/Contents.json`
- Create: `Resources/Assets.xcassets/BackgroundLuminousDrift.imageset/Contents.json`
- Create: `Resources/Assets.xcassets/BackgroundHorizonGlow.imageset/Contents.json`
- Add image files: the four approved wallpaper PNGs into those image sets
- Test: `Tests/Render/BackgroundRenderResolverTests.swift`

- [ ] **Step 1: Write failing render resolver tests**

```swift
import XCTest
@testable import MouseLens

final class BackgroundRenderResolverTests: XCTestCase {
    func testGradientPresetBuildsSwiftUIPreviewGradient() {
        let preset = BackgroundPresetCatalog.preset(id: "aurora-air")
        let preview = BackgroundPreviewStyle.makeGradient(for: preset)

        XCTAssertNotNil(preview)
    }

    func testWallpaperPresetLooksUpAssetName() {
        let preset = BackgroundPresetCatalog.preset(id: "soft-glass")

        XCTAssertEqual(BackgroundRenderResolver.wallpaperAssetName(for: preset), "BackgroundSoftGlass")
    }

    func testRenderResolverUsesCatalogColorsForGradientPreset() {
        let preset = BackgroundPresetCatalog.preset(id: "midnight-pulse")
        let colors = BackgroundRenderResolver.gradientColors(for: preset)

        XCTAssertEqual(colors.count, 3)
        XCTAssertEqual(colors[0].red, 0.05, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the resolver tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS' \
  -only-testing:MouseLensTests/BackgroundRenderResolverTests
```

Expected: build fails because `BackgroundPreviewStyle` and `BackgroundRenderResolver` do not exist.

- [ ] **Step 3: Create shared preview helpers**

Create `Sources/DesignSystem/BackgroundPreviewStyle.swift`:

```swift
import SwiftUI

enum BackgroundPreviewStyle {
    static func makeGradient(for preset: BackgroundPreset) -> LinearGradient? {
        guard let definition = preset.gradient else { return nil }
        return LinearGradient(
            colors: definition.colors.map {
                Color(red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
            },
            startPoint: UnitPoint(x: definition.startPoint.x, y: definition.startPoint.y),
            endPoint: UnitPoint(x: definition.endPoint.x, y: definition.endPoint.y)
        )
    }
}
```

Replace the switch in `Sources/DesignSystem/AppTheme.swift` with:

```swift
extension BackgroundPreset {
    var previewGradient: LinearGradient? {
        BackgroundPreviewStyle.makeGradient(for: self)
    }
}
```

- [ ] **Step 4: Create the shared render resolver**

Add near the background rendering helpers in `Sources/Core/Render/RenderModels.swift`:

```swift
enum BackgroundRenderResolver {
    static func gradientColors(for preset: BackgroundPreset) -> [CGColor] {
        preset.gradient?.colors.map {
            CGColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
        } ?? []
    }

    static func wallpaperAssetName(for preset: BackgroundPreset) -> String? {
        preset.wallpaper?.assetName
    }
}
```

Then replace the hard-coded `switch style` in `makeBackgroundImage(...)` with:

```swift
let preset = style.backgroundPreset

if let assetName = BackgroundRenderResolver.wallpaperAssetName(for: preset),
   let image = NSImage(named: assetName),
   let tiff = image.tiffRepresentation,
   let ciImage = CIImage(data: tiff) {
    return ciImage
        .transformed(by: wallpaperTransform(for: ciImage.extent.size, canvasSize: size))
        .cropped(to: CGRect(origin: .zero, size: size))
}

let colors = BackgroundRenderResolver.gradientColors(for: preset)
```

Add a helper stub in the same file:

```swift
private func wallpaperTransform(for sourceSize: CGSize, canvasSize: CGSize) -> CGAffineTransform {
    let scale = max(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
    let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let origin = CGPoint(
        x: (canvasSize.width - scaledSize.width) / 2,
        y: (canvasSize.height - scaledSize.height) / 2
    )

    return CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
}
```

- [ ] **Step 5: Add the wallpaper assets**

Create four image sets under `Resources/Assets.xcassets`:

```text
Resources/Assets.xcassets/BackgroundSoftGlass.imageset
Resources/Assets.xcassets/BackgroundTidalGlow.imageset
Resources/Assets.xcassets/BackgroundLuminousDrift.imageset
Resources/Assets.xcassets/BackgroundHorizonGlow.imageset
```

Each `Contents.json` should be:

```json
{
  "images" : [
    {
      "filename" : "background.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Use the approved wallpaper PNGs as `background.png` in each image set.

- [ ] **Step 6: Add files to the Xcode project**

Update `MouseLens.xcodeproj/project.pbxproj` to include:

- `BackgroundPreviewStyle.swift` in Sources
- `BackgroundRenderResolverTests.swift` in Tests
- the four `.imageset` directories under `Assets.xcassets`

- [ ] **Step 7: Run the render resolver tests**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS' \
  -only-testing:MouseLensTests/BackgroundRenderResolverTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git -C /Users/guoxl/Documents/Playground/MouseLens add \
  Sources/DesignSystem/BackgroundPreviewStyle.swift \
  Sources/DesignSystem/AppTheme.swift \
  Sources/Core/Render/RenderModels.swift \
  Tests/Render/BackgroundRenderResolverTests.swift \
  Resources/Assets.xcassets \
  MouseLens.xcodeproj/project.pbxproj
git -C /Users/guoxl/Documents/Playground/MouseLens commit -m "Add shared background preview and render resolution"
```

## Task 3: Move the Editor Picker and View Model to Preset IDs

**Files:**
- Modify: `Sources/Features/Editor/EditorViewModel.swift`
- Modify: `Sources/Features/Editor/EditorView.swift`
- Test: `Tests/Editor/EditorViewModelTests.swift`

- [ ] **Step 1: Write failing editor tests for preset-backed selection**

Add to `Tests/Editor/EditorViewModelTests.swift`:

```swift
func testEditorDefaultsToAuroraAirPresetID() {
    let viewModel = makeViewModel()

    XCTAssertEqual(viewModel.selectedBackgroundPresetID, "aurora-air")
}

func testConfiguringProjectUsesPresetIDFromStyle() {
    let viewModel = makeViewModel()
    let project = makeProject(backgroundPresetID: "tidal-glow")

    viewModel.configure(for: project)

    XCTAssertEqual(viewModel.selectedBackgroundPresetID, "tidal-glow")
}

func testChangingSelectedBackgroundPresetUpdatesDraftProject() {
    let viewModel = makeViewModel()
    let project = makeProject(backgroundPresetID: "aurora-air")

    viewModel.configure(for: project)
    viewModel.selectedBackgroundPresetID = "soft-glass"

    XCTAssertEqual(viewModel.project?.style.backgroundPresetID, "soft-glass")
}
```

- [ ] **Step 2: Run the editor tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS' \
  -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: FAIL because `selectedBackgroundPresetID` and the new `makeProject(backgroundPresetID:)` helper do not exist.

- [ ] **Step 3: Update the view model to store preset IDs**

In `Sources/Features/Editor/EditorViewModel.swift`, replace:

```swift
@Published var selectedBackground: ProjectBackgroundStyle = .ocean {
    didSet { handleStyleChange(updateExportPreset: false) }
}
```

with:

```swift
@Published var selectedBackgroundPresetID: String = BackgroundPresetCatalog.defaultPresetID {
    didSet { handleStyleChange(updateExportPreset: false) }
}
```

Update `configure(for:)`:

```swift
selectedBackgroundPresetID = project.style.backgroundPresetID
```

Update `handleStyleChange(...)` style creation:

```swift
let style = ProjectStyle(
    aspectRatio: selectedAspectRatio,
    backgroundPresetID: selectedBackgroundPresetID,
    cornerRadius: cornerRadius,
    shadowRadius: 0,
    followStrength: motionSettings.followStrength,
    clickEmphasis: motionSettings.clickEmphasis,
    padding: padding
)
```

- [ ] **Step 4: Update the editor picker and swatch to use presets**

In `Sources/Features/Editor/EditorView.swift`, replace the `ForEach(ProjectBackgroundStyle.allCases...)` grid with:

```swift
ForEach(BackgroundPresetCatalog.all) { preset in
    Button {
        viewModel.selectedBackgroundPresetID = preset.id
    } label: {
        BackgroundSwatch(
            preset: preset,
            isSelected: viewModel.selectedBackgroundPresetID == preset.id
        )
    }
    .buttonStyle(.plain)
}
```

Replace `BackgroundSwatch` with:

```swift
private struct BackgroundSwatch: View {
    let preset: BackgroundPreset
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Group {
                    if let gradient = preset.previewGradient {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(gradient)
                    } else if let assetName = preset.wallpaper?.assetName {
                        Image(assetName)
                            .resizable()
                            .scaledToFill()
                    }
                }

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                    .frame(width: 54, height: 31)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white, AppTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(7)
                }
            }
            .frame(height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent : Color.white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            )

            Text(preset.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white : AppTheme.mutedText)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isSelected ? AppTheme.accent.opacity(0.18) : Color.white.opacity(0.04))
        )
    }
}
```

- [ ] **Step 5: Update test helpers**

Adjust `makeProject(...)` in `Tests/Editor/EditorViewModelTests.swift` and any local helpers to build `ProjectStyle(backgroundPresetID: ...)` instead of `background:`.

Use:

```swift
backgroundPresetID: backgroundPresetID
```

with a default helper argument:

```swift
backgroundPresetID: String = "aurora-air"
```

- [ ] **Step 6: Run the editor tests to verify they pass**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS' \
  -only-testing:MouseLensTests/EditorViewModelTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git -C /Users/guoxl/Documents/Playground/MouseLens add \
  Sources/Features/Editor/EditorView.swift \
  Sources/Features/Editor/EditorViewModel.swift \
  Tests/Editor/EditorViewModelTests.swift
git -C /Users/guoxl/Documents/Playground/MouseLens commit -m "Switch editor to background preset catalog"
```

## Task 4: Update Storage Fixtures and Run Full Background Regression Verification

**Files:**
- Modify: `Tests/Storage/ProjectStoreTests.swift`
- Modify: `Tests/Render/ExportFilenameTests.swift`
- Modify: any remaining `ProjectStyle(background:)` call sites found by search

- [ ] **Step 1: Write one explicit legacy storage migration assertion**

Add to `Tests/Storage/ProjectStoreTests.swift`:

```swift
func testLegacyStoredBackgroundEnumMigratesToPresetID() throws {
    let data = """
    {
      "id": "\(UUID())",
      "name": "LegacyProject",
      "createdAt": 0,
      "duration": 1,
      "sourceVideoURL": null,
      "captureTarget": "screen",
      "reconstructsCursor": false,
      "events": [],
      "cameraKeyframes": [{"timestamp":0,"focus":{"x":0.5,"y":0.5},"zoom":1}],
      "style": {
        "aspectRatio": "landscape",
        "background": "paper",
        "cornerRadius": 10.35,
        "shadowRadius": 0,
        "followStrength": 0.72,
        "clickEmphasis": 0.54,
        "padding": 0.04
      },
      "trimRange": {"start":0,"end":1},
      "clipSegments": [{"start":0,"end":1}],
      "manualZoomSegments": [],
      "zoomTrackEdited": false
    }
    """.data(using: .utf8)!

    let project = try JSONDecoder().decode(RecordingProject.self, from: data)

    XCTAssertEqual(project.style.backgroundPresetID, "silver-mist")
}
```

- [ ] **Step 2: Run the storage test to verify it fails if fixtures are not updated**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS' \
  -only-testing:MouseLensTests/ProjectStoreTests
```

Expected: initial failures from outdated `ProjectStyle(background:)` fixture calls.

- [ ] **Step 3: Update fixture call sites**

Replace old fixture construction across tests with the new style initializer:

```swift
ProjectStyle(
    aspectRatio: .landscape,
    backgroundPresetID: "aurora-air",
    cornerRadius: 24,
    shadowRadius: 16,
    followStrength: 0.5,
    clickEmphasis: 0.4,
    padding: 0.08
)
```

Apply the same update to:

- `Tests/Storage/ProjectStoreTests.swift`
- `Tests/Render/ExportFilenameTests.swift`
- any other test or helper still using `background:`

- [ ] **Step 4: Run focused test suites**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS' \
  -only-testing:MouseLensTests/BackgroundPresetCatalogTests \
  -only-testing:MouseLensTests/BackgroundRenderResolverTests \
  -only-testing:MouseLensTests/EditorViewModelTests \
  -only-testing:MouseLensTests/ProjectStoreTests \
  -only-testing:MouseLensTests/ExportFilenameTests
```

Expected: PASS.

- [ ] **Step 5: Run the full test suite**

Run:

```bash
xcodebuild test \
  -project /Users/guoxl/Documents/Playground/MouseLens/MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS'
```

Expected: full suite passes.

- [ ] **Step 6: Rebuild the canonical app for manual verification**

Run:

```bash
cd /Users/guoxl/Documents/Playground/MouseLens
./scripts/build_local_test_app.sh
```

Expected: refreshed canonical app at:

```text
/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app
```

- [ ] **Step 7: Manual verification checklist**

Verify in `/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app`:

- Editor shows exactly eight presets
- The first four are gradients and the last four are wallpapers
- Switching presets updates immediately
- `5 Soft Glass` keeps a little glass layering
- `6 Tidal Glow` is bright blue-green with slight warm accent and no visible texture
- `7 Luminous Drift` is clean, airy, and low-texture
- Preview and exported MP4 show the same background choice
- Old projects open with a valid mapped preset

- [ ] **Step 8: Commit**

```bash
git -C /Users/guoxl/Documents/Playground/MouseLens add \
  Tests/Storage/ProjectStoreTests.swift \
  Tests/Render/ExportFilenameTests.swift
git -C /Users/guoxl/Documents/Playground/MouseLens commit -m "Update background preset fixtures and regressions"
```

## Self-Review

### Spec Coverage

- Eight-preset library: covered in Task 1 catalog data.
- Four gradients + four wallpapers: covered in Task 1 IDs and Task 2 assets.
- Mixed editor grid: covered in Task 3.
- Preview/export shared rendering: covered in Task 2.
- Migration from legacy enum backgrounds: covered in Task 1 and Task 4.
- Immediate background switching: covered in Task 3 and Task 4 manual verification.

No spec gaps remain.

### Placeholder Scan

- No `TBD`, `TODO`, or “implement later” placeholders remain.
- Each task has explicit files, code, commands, and expected outcomes.

### Type Consistency

- `backgroundPresetID` is used consistently across model, view model, and tests.
- Approved wallpaper IDs are consistent across the catalog, tests, and assets:
  - `soft-glass`
  - `tidal-glow`
  - `luminous-drift`
  - `horizon-glow`

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-02-background-library-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
