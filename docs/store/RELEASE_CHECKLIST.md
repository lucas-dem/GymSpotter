# GymSpotter store release checklist

This checklist is operational guidance, not legal advice.

## Required for every release

1. Commit all source and release metadata. Do not build a store binary from a
   dirty working tree.
2. Publish that exact revision in a repository reachable through HTTPS without
   payment or authentication. Keep it available for as long as the binary is
   distributed.
3. Include `LICENSE`, `NOTICE.md`, `CREDITS.md`, `MODIFICATIONS.md`,
   `PRIVACY.md`, the dependency lockfile, build scripts and every source or
   asset needed to rebuild the application.
4. Mark the release with an immutable tag and place the source URL next to the
   binary/store listing. The URL should resolve to the exact tag or revision,
   not merely the repository default branch.
5. Build with `SOURCE_CODE_URL`, `SOURCE_REVISION` and `BUILD_DATE`. The app
   displays these values in its legal screen.
6. Preserve the GPL-3.0 license for the complete derivative application. Do not
   add terms that prohibit copying, modification or redistribution.
7. Preserve the CC BY-SA 4.0 attribution for exercise art and the SIL OFL 1.1
   notice for Nunito.
8. Review the generated dependency-license screen after dependency upgrades.
9. Verify the privacy declaration against the actual binary and complete each
   store's privacy/data-safety questionnaire accurately.

## Google Play

- Create and protect the release keystore. `android/key.properties` and the
  keystore must never be committed.
- Build an Android App Bundle with `scripts/build_android_store.ps1`.
- Put the exact source URL in the Play listing or an easily discoverable legal
  page linked by the listing.
- Complete Data safety, content rating, target audience, ads and app-access
  forms based on the release binary.

## Apple App Store

- An iOS build must be produced and signed on macOS with Xcode and an Apple
  Developer account. It cannot be built or validated on Windows.
- Provide the same exact source URL and GPL notices used by Android.
- Review the final App Store agreement and EULA with qualified counsel before
  submission. Apple permits a custom EULA and its standard EULA contains an
  open-source carve-out, but only counsel or explicit additional permission
  from all relevant copyright holders can remove the remaining GPL/App Store
  contractual risk.
- Build with a current stable Flutter/Xcode toolchain and inspect Xcode's
  generated privacy report. Confirm that every listed SDK (including Flutter,
  file_picker, image_picker_ios, flutter_local_notifications, path_provider,
  share_plus, shared_preferences, url_launcher and video_player_avfoundation)
  contributes the privacy manifest/signature required by Apple.
- Do not claim that the App Store build is closed source or impose restrictions
  inconsistent with GPL-3.0.

## Release metadata example

```text
SOURCE_CODE_URL=https://example.org/owner/gymspotter/tree/v1.3.0
SOURCE_REVISION=<full commit SHA>
BUILD_DATE=2026-09-22T15:00:00Z
```

Replace the example URL. Never ship it as written.
