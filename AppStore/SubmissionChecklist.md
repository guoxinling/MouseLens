# MouseLens App Store / TestFlight Checklist

Updated: 2026-07-20

## Current Repository State

- Source project exists.
- Canonical local test app exists at `.LocalTestApp/MouseLens.app`.
- MouseLens 1.1 has been approved and released.
- Active development branch: `codex/1.2-development`.
- App Store metadata drafts now exist under `AppStore/`.
- App icon is included in `Resources/Assets.xcassets`.
- Release uses App Sandbox, Hardened Runtime, and Team `6UYTZXY3H9`.

## 1.2 Blocking Items Before Upload

- [x] Apple Developer Program account available.
- [x] App Store Connect app record created.
- [x] Bundle ID confirmed: `com.guoxl.MouseLens`.
- [x] `DEVELOPMENT_TEAM` configured for distribution signing.
- [x] Signing/capabilities configured for Mac App Store distribution.
- [x] App icon added to `Resources/Assets.xcassets`.
- [ ] Set version to `1.2`.
- [ ] Set build number higher than the latest uploaded 1.1 build.
- [ ] Run full test suite.
- [ ] Fresh canonical app build with `./scripts/prepare_local_test_app.sh`.
- [ ] Screen recording smoke test.
- [ ] Window recording smoke test.
- [ ] Presenter camera smoke test.
- [ ] MP4 export smoke test.
- [ ] GIF export smoke test.
- [ ] Archive and export Mac App Store package.
- [ ] Upload build to App Store Connect.
- [ ] Wait for build processing to complete and select the build.
- [ ] Export compliance answered.
- [ ] App privacy answers reconfirmed.

## Required Metadata

- [x] App name draft
- [x] Subtitle draft
- [x] Description draft
- [x] Keywords draft
- [x] Review notes draft
- [x] Beta test notes draft
- [x] Support URL
- [x] Privacy Policy URL
- [ ] Copyright owner confirmation
- [ ] Contact email/support page
- [x] What's New draft for 1.2
- [x] Promotional text draft for 1.2

## Required Visual Assets

- [x] App icon
- [x] Current Mac screenshot set exists under `AppStore/Screenshots/`
- [ ] Update screenshots for 1.2 if marketing Presenter Camera or GIF export
- [ ] Optional app preview video

Recommended screenshot set for 1.2:

1. Recording toolbar ready state
2. Countdown or floating recording toolbar
3. Editor playback with cursor/zoom visible
4. Zoom Track with Auto/Manual segment
5. Presenter camera bubble controls
6. GIF/MP4 export panel
7. Background/padding/corner radius inspector

## Pre-Upload Validation

- [ ] `xcodebuild test -scheme MouseLens -destination 'platform=macOS'`
- [ ] Fresh canonical app build with `./scripts/prepare_local_test_app.sh`
- [ ] Screen recording smoke test
- [ ] Window recording smoke test
- [ ] Presenter camera smoke test
- [ ] MP4 export smoke test
- [ ] GIF export smoke test
- [ ] Permission prompts verified on a clean install path

## App Store Connect TestFlight Flow

1. Create app record.
2. Upload signed archive/build.
3. Wait for build processing.
4. Fill beta app information and test notes.
5. Add internal tester group.
6. Add build to group.
7. Invite testers.
8. For external testing, submit build for Beta App Review.

## Store Release Items After Beta

- [ ] Final product positioning.
- [ ] Final screenshot set.
- [ ] Final support/privacy pages.
- [ ] Pricing/availability.
- [ ] Review any App Sandbox or entitlement rejection feedback.
- [ ] Decide whether to keep app as local-only or add update/analytics/crash reporting.
