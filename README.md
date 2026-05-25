# MouseLens

MouseLens is a local-first macOS screen demo tool focused on one job: record an interaction and quickly turn it into a polished walkthrough with cursor-follow camera motion, click emphasis, and clean framing.

The current product prototype already includes:

- a SwiftUI macOS app
- a permission-aware recording flow
- countdown recording with optional auto-hide before capture
- menu bar controls and a global stop shortcut
- pointer event capture and automatic camera planning
- a real MP4 export pipeline with editor controls and presets

## Local testing: one app path only

To avoid permission drift between `Build`, `BuildRelease`, and temporary Xcode outputs, MouseLens now uses **one canonical local test app path**:

`/Users/guoxl/Documents/Playground/MouseLens/.LocalTestApp/MouseLens.app`

Build and open that app with:

```bash
cd /Users/guoxl/Documents/Playground/MouseLens
./scripts/prepare_local_test_app.sh --open
```

If the local macOS recording permissions have become confused, reset them and rebuild with:

```bash
cd /Users/guoxl/Documents/Playground/MouseLens
./scripts/prepare_local_test_app.sh --clean --reset-permissions --open
```

After this change, local testing should only use:

- `.LocalTestApp/MouseLens.app`

Do not use:

- `Build/MouseLens.app`
- `BuildRelease/MouseLens.app`
- random apps opened directly from Xcode DerivedData

## Stack

- SwiftUI
- ScreenCaptureKit capture pipeline
- AVFoundation export pipeline
- XcodeGen project generation

## Generate the Xcode project

```bash
cd MouseLens
xcodegen generate
open MouseLens.xcodeproj
```

## Prepare the canonical local test app

```bash
cd /Users/guoxl/Documents/Playground/MouseLens
./scripts/prepare_local_test_app.sh
```

## Run tests

```bash
xcodebuild test \
  -project MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS'
```
