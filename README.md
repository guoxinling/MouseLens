# MouseLens

MouseLens is a local-first macOS screen demo tool focused on one job: record an interaction and quickly turn it into a polished walkthrough with cursor-follow camera motion, click emphasis, and clean framing.

This first cut ships as an MVP scaffold with:

- a SwiftUI macOS app
- a permission-aware recording flow
- pointer event capture
- a camera-planning engine with tests
- a debug export pipeline that renders an MP4 preview from the generated motion plan

## Stack

- SwiftUI
- ScreenCaptureKit-ready recording service scaffold
- AVFoundation export pipeline
- XcodeGen project generation

## Generate the Xcode project

```bash
cd MouseLens
xcodegen generate
open MouseLens.xcodeproj
```

## Run tests

```bash
xcodebuild test \
  -project MouseLens.xcodeproj \
  -scheme MouseLens \
  -destination 'platform=macOS'
```
