# Infyter store declarations

Use this as the source of truth when completing Play Console and App Store
Connect. Re-check it against the final signed binaries before submission.

## Product identity

- App name: Infyter
- Android application ID: `com.infyter.app`
- Apple bundle ID: `com.infyter.app`
- Version: `1.3.0` (`1`)
- Ads: no
- Account or login: no
- Paid subscription or in-app purchase: no
- Health Connect: read only, Steps (`android.permission.health.READ_STEPS`), Android 14+, foreground only. HealthKit: not used
- Step counting: on-device (Android step counter sensor / Core Motion)

## Privacy and data safety

- Data collected by the developer: none.
- Data shared with third parties: none.
- Tracking: none.
- Analytics, advertising or crash-reporting SDKs: none.
- Network access in the Android release binary: none (no `INTERNET`
  permission). To check for updates, the app asks the on-device Google Play
  Store app through Google's Play In-App Updates library (an inter-process
  call, not a connection made by the app) and reads whether the device is
  online (`ACCESS_NETWORK_STATE`).
- Network access in the iOS binary: one HTTPS request to Apple's public lookup
  (`https://itunes.apple.com/lookup?bundleId=com.infyter.app&country=<region>`)
  when the app opens, and again when it returns after at least an hour, to
  compare versions. It sends no user data; Apple receives the device's IP
  address as with any request. Nothing reaches the developer or a third party.
- Workout history, body measurements, steps, notes and attached media remain
  on the device. They leave it only when the user explicitly exports or shares
  them (backup, workouts CSV, or "Share progress" as text, PDF, Excel, CSV or
  JSON).
- QR recognition runs locally on the device; QR plan payloads are not sent to
  a server.
- Data deletion: the app has a delete-all-data action; uninstalling also
  removes app-private data when the operating system performs its normal
  cleanup. Android cloud backup is excluded; a device-to-device transfer can
  still carry app data, except the step anchor file. On iPhone, iCloud and
  computer backups include app data.

For Google Play Data safety, data processed only on-device and never sent off
the device is not declared as collected. Answer **No** to collection and
sharing only if the final signed bundle still matches this document.

For Apple App Privacy, select **Data Not Collected** and **No tracking** only
if Xcode's privacy report for the final archive confirms the same result.

The version check does not change these answers: nothing it sends reaches the
developer or a third party. For Google Play Data safety, re-check Google's
guidance for the Play In-App Updates library when filling the form.

## Permissions and purpose

- Camera: local QR plan scanning and photos/videos the user chooses to add.
- Photos/files: import, export, backup, restore and user-selected media.
- Microphone (iOS): audio in a video the user chooses to record.
- Physical activity (Android `ACTIVITY_RECOGNITION`, iOS Motion & Fitness /
  `NSMotionUsageDescription`): daily step count and estimated active calories,
  only after the user enables step counting. Read and stored on the device;
  nothing is sent anywhere. No Google Play services and no foreground service.
- Health Connect steps (Android 14+, `android.permission.health.READ_STEPS`):
  reads daily steps from Health Connect, only after the user enables step
  counting, to show them with estimated active calories and to include them in
  a progress summary the user chooses to share. Read only; nothing is written
  to Health Connect, and the app sends nothing by itself.
- Notifications: rest-timer and training reminders.
- Schedule exact alarms (Android): optional precision for short rest timers;
  the app falls back to an inexact notification if access is unavailable.
- Vibration and wake lock (Android): alert for an active rest timer while the
  display is off.
- Network state (Android, `ACCESS_NETWORK_STATE`): checks that the device is
  online before requiring an update, so the app never blocks without a
  connection. It does not give internet access.

The step feature does not add `INTERNET`. The app does not request `INTERNET`, `USE_EXACT_ALARM`,
`USE_FULL_SCREEN_INTENT` or promoted-notification permission in release.

## Content and review notes

- Play Console, App content: mark the health apps declaration "Activity and
  fitness / activity tracking". Complete the Health Connect declaration:
  Steps, read only, foreground, to show daily steps and estimated active
  calories and to include them in progress exports the user starts.
- App Store review note: "Step count is read with Core Motion only after the
  user enables it; it stays on the device; calories are labelled as
  estimates."
- Infyter is a workout log, not a medical device, diagnosis tool or treatment.
- It contains no social feed, chat, gambling, ads or user-generated public
  content.
- A reviewer can access every feature without credentials.
- Exercise and progress-photo features may show stylized anatomy or media the
  user adds locally; no such media is uploaded by Infyter.

## Required owner-supplied values

Do not submit until the release owner has supplied and verified:

- a permanent public HTTPS URL for `PRIVACY.md`;
- a monitored support email or support URL shown in both listings;
- the exact public source-code URL and immutable revision for GPL compliance;
- Android release-keystore credentials in untracked `android/key.properties`;
- Apple signing team, certificates and provisioning profiles;
- the final custom-EULA/GPL decision reviewed by qualified counsel or backed
  by explicit additional permission from all relevant copyright holders.
