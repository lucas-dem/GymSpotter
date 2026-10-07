# Infyter — first store release handoff

This source package is prepared for Infyter's first publication on Google Play
and the Apple App Store. Store credentials and signing keys are intentionally
not included.

## Fixed product identity

- Name: Infyter
- Public version: `1.3.0`
- Android first version code: `1`
- iOS first build number: `1`
- Android application ID: `com.infyter.app`
- Apple bundle ID: `com.infyter.app`

Register both identifiers exactly as written. Do not create either store record
with a different identifier without first updating and rebuilding the project.

## Values the owner must provide

1. A monitored contact email entered privately in each store console. It does
   not need to be embedded in the app or source package.
2. Public HTTPS URLs for the hosted `support.html` and `privacy.html` pages.
3. The public source tag containing the exact source used for the
   binaries. This is required by the GPL notices shown inside the app.

## Google Play uploader

1. Create the Play Console record for `com.infyter.app` and enable Play App
   Signing.
2. Create and securely back up an upload key. Copy
   `android/key.properties.example` to `android/key.properties` and replace all
   four placeholder values. Never commit or share either secret file.
3. Commit the exact release source and publish an immutable `v1.3.0` tag.
4. From a clean checkout, run:

   ```powershell
   ./scripts/build_android_store.ps1 -SourceCodeUrl "https://github.com/lucas-dem/GymSpotter/tree/v1.3.0"
   ```

5. Upload `build/app/outputs/bundle/release/app-release.aab`.
6. Copy the listing material from `fastlane/metadata/android` and complete the
   forms from `docs/store/STORE_DECLARATIONS.md`.
7. Use the hosted privacy URL, a monitored support email, and the hosted
   support page where requested.

## Apple App Store uploader

1. On a Mac, create the App Store Connect record and App ID for
   `com.infyter.app`, select the correct Apple Developer team and configure
   automatic signing in Xcode.
2. Replace the support-email placeholder, commit the exact source and publish
   the same immutable `v1.3.0` source tag.
3. Install the current stable Flutter toolchain, Xcode and CocoaPods, then run:

   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ./scripts/build_ios_store.sh "https://github.com/lucas-dem/GymSpotter/tree/v1.3.0"
   ```

4. Validate and upload the resulting archive with Xcode/Transporter.
5. Complete App Privacy from `docs/store/STORE_DECLARATIONS.md`, set the hosted
   privacy and support URLs, and attach the prepared screenshots.

## Do not upload

- Any APK or AAB described as a local validation/debug-signed artifact.
- `.dart_tool`, `build`, `.gradle`, the bundled local Flutter SDK backup or
  `.codex-apk-share`.
- `android/key.properties`, `.jks`, `.keystore`, passwords, Apple certificates
  or provisioning credentials.

Read `RELEASE_CHECKLIST.md` before submission, especially the GPL/App Store
contractual note. This checklist is operational guidance, not legal advice.
