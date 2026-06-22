# MouseLens App Store / TestFlight Checklist

Updated: 2026-06-21

## Current Repository State

- Source project exists.
- Canonical local test app exists at `.LocalTestApp/MouseLens.app`.
- Full local tests last passed with 92 tests.
- App Store metadata drafts now exist under `AppStore/`.
- App icon is included in `Resources/Assets.xcassets`.
- Release uses App Sandbox, Hardened Runtime, and Team `6UYTZXY3H9`.
- Archive created at `.Archives/MouseLens-0.1.0-1.xcarchive`.

## Blocking Items Before TestFlight Upload

- [ ] Apple Developer Program account available.
- [ ] App Store Connect app record created for `MouseLens`.
- [ ] Bundle ID confirmed: `com.guoxl.MouseLens`.
- [x] `DEVELOPMENT_TEAM` configured for distribution signing.
- [x] Signing/capabilities configured for Mac App Store distribution.
- [x] App icon added to `Resources/Assets.xcassets`.
- [ ] Version/build numbers updated if needed.
- [x] Archive created with Xcode.
- [x] Sign in to the Apple Developer account again in Xcode.
- [x] Account Holder accepts the current Apple Developer Program License Agreement.
- [x] Create/download a `Mac Installer Distribution` certificate.
- [x] Create/download a Mac App Store provisioning profile for `com.guoxl.MouseLens`.
- [x] App Store Connect app record created.
- [x] Build `0.1.0 (1)` uploaded to App Store Connect on 2026-06-21.
- [ ] Wait for App Store Connect build processing to complete and select the build.
- [ ] Export compliance answered.
- [ ] App privacy answers completed.
- [ ] Privacy policy hosted at a public HTTPS URL.
- [ ] TestFlight internal tester group created.

## Required Metadata

- [x] App name draft
- [x] Subtitle draft
- [x] Description draft
- [x] Keywords draft
- [x] Review notes draft
- [x] Beta test notes draft
- [ ] Support URL
- [ ] Privacy Policy URL
- [ ] Copyright owner confirmation
- [ ] Contact email/support page

## Required Visual Assets

- [x] App icon
- [ ] 1 to 10 Mac screenshots
- [ ] Optional app preview video

Recommended screenshot set for first beta/store prep:

1. Recording toolbar ready state
2. Countdown or floating recording toolbar
3. Editor playback with cursor/zoom visible
4. Zoom Track with Auto/Manual segment
5. Background/padding/corner radius inspector
6. Export sheet or exported-result moment

## Pre-Upload Validation

- [x] `xcodebuild test -scheme MouseLens -destination 'platform=macOS'` (92 passed)
- [x] Fresh canonical app build with `./scripts/prepare_local_test_app.sh`
- [ ] Screen recording smoke test
- [ ] Window recording smoke test
- [ ] Export smoke test
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
