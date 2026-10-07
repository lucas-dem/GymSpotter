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
- Health Connect / HealthKit: not used

## Privacy and data safety

- Data collected by the developer: none.
- Data shared with third parties: none.
- Tracking: none.
- Analytics, advertising or crash-reporting SDKs: none.
- Network access in the Android release binary: none.
- Workout history, body measurements, notes and attached media remain on the
  device. They leave it only when the user explicitly exports or shares them.
- QR recognition runs locally on the device; QR plan payloads are not sent to
  a server.
- Data deletion: the app has a delete-all-data action; uninstalling also
  removes app-private data when the operating system performs its normal
  cleanup. Android backup is disabled.

For Google Play Data safety, data processed only on-device and never sent off
the device is not declared as collected. Answer **No** to collection and
sharing only if the final signed bundle still matches this document.

For Apple App Privacy, select **Data Not Collected** and **No tracking** only
if Xcode's privacy report for the final archive confirms the same result.

## Permissions and purpose

- Camera: local QR plan scanning and photos/videos the user chooses to add.
- Photos/files: import, export, backup, restore and user-selected media.
- Microphone (iOS): audio in a video the user chooses to record.
- Notifications: rest-timer and training reminders.
- Schedule exact alarms (Android): optional precision for short rest timers;
  the app falls back to an inexact notification if access is unavailable.
- Vibration and wake lock (Android): alert for an active rest timer while the
  display is off.

The app does not request `INTERNET`, `USE_EXACT_ALARM`,
`USE_FULL_SCREEN_INTENT` or promoted-notification permission in release.

## Content and review notes

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
