# Infyter pre-store audit — 2026-10-07

Status: code and Android release validation passed locally. The exact source
revision is prepared for publication; no store binary has been uploaded.

## Resolved in the workspace

- Removed the cloud-backed ML Kit scanner and replaced it with local ZXing QR
  recognition on Android and native AVFoundation recognition on iOS.
- Removed Android `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT` and
  `POST_PROMOTED_NOTIFICATIONS`. Rest timers use user-controlled
  `SCHEDULE_EXACT_ALARM` with an inexact fallback.
- Renamed Android namespaces, source packages, channels, widget identifiers,
  notification resources and current export markers to Infyter.
- Kept old GymMane identifiers only where required for license attribution or
  backwards-compatible import/storage.
- Localized the trainer and QR flows across all 16 shipped languages.
- Added a CocoaPods integration file, removed the duplicated iOS camera key,
  and localized iOS permission explanations in English and Spanish.
- Bundled GPL modification notices and the Nunito OFL license in the app.
- Synchronized first-release metadata with version `1.3.0+1` and added
  changelog 1.
- Replaced the obsolete Play icon, feature graphic and 12 phone screenshots
  with Infyter-branded material captured from the current app.
- Made the in-app widget buttons request the Android launcher immediately and
  report unsupported launchers instead of appearing unresponsive. Settings now
  show each widget's real installed state, confirm additions and guide removal
  through the Android home screen.
- Localized the widget-management feedback across all 16 shipped languages.
- Replaced the legacy runner notification glyph with a monochrome Infyter
  mark for rest timers and live workouts.
- Added store privacy/data declarations and updated the public privacy text.

## Verification

- `flutter analyze`: no issues.
- `flutter test`: 497 passed; 3 optional fixture suites skipped because their
  private fixtures are intentionally not distributed; 0 failed.
- Android debug build: passed and installed on `emulator-5554`.
- Android local release build: passed.
- Android local app bundle build: passed; bundle structure and signature were
  verified locally.
- Package/version: `com.infyter.app`, `1.3.0` (`1`), target SDK 36.
- Release dependency review: QR support resolves only local ZXing libraries;
  no Firebase, Analytics, ML Kit or Google Play Services dependency was found.
- Emulator QR smoke test: Android displayed the camera permission under the
  Infyter name, the scanner opened and rendered its capture frame, and no
  fatal Android error was logged.
- Release APK permissions: camera, notifications, schedule-exact-alarm,
  vibration, legacy storage through Android 9, boot-completed, wake-lock and
  foreground-service. It has no Internet permission.
- Bundled notices: `LICENSE`, `NOTICE.md`, `CREDITS.md`, `MODIFICATIONS.md`,
  `PRIVACY.md` and `assets/fonts/Nunito-OFL.txt`.

The generated APK and AAB are local validation artifacts signed with the debug
key. They must not be uploaded to a store.

## Submission blockers owned outside the repository

1. Create/provide the protected Android release keystore and untracked
   `android/key.properties`.
2. Publish `PRIVACY.md` and `docs/public/support.html` at permanent HTTPS URLs,
   and enter a monitored contact email privately in each store console.
3. Build store binaries from the immutable `v1.3.0` source tag using the
   release metadata defines.
4. On macOS, install pods, build/archive with Xcode 26 and the iOS 26 SDK,
   inspect Apple's generated privacy report, sign and validate the IPA.
5. Resolve the GPL/App Store contractual question with qualified counsel or
   explicit additional permission from every relevant copyright holder.

See `RELEASE_CHECKLIST.md` and `STORE_DECLARATIONS.md` before submission.
