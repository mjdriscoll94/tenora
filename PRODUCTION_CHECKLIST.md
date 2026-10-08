# Tenora 1.0 production checklist

Last audited: October 8, 2026

## Automated checks completed

- [x] Full unit and UI suite: 102 tests passed, 0 failures, 0 skips.
- [x] Warning-free unsigned Release archive built with Xcode 26.6 / iOS 26.5 SDK.
- [x] Xcode Release static analysis completed without findings.
- [x] App and widget property lists, entitlements, and privacy manifests pass `plutil` validation.
- [x] App icon is a 1024×1024 RGB PNG without alpha.
- [x] Release bundle is iPhone-only, targets iOS 17.0+, and reports version 1.0.0 (build 1).
- [x] The app and widget contain `PrivacyInfo.xcprivacy` declarations for their `UserDefaults` access.
- [x] Calendar purpose strings are present in the archived app.
- [x] The unfinished ChatGPT agent bridge is disabled in the Release build unless explicitly enabled with `TENORA_AGENT_BRIDGE_ENABLED`.
- [x] No committed private keys, provisioning profiles, environment files, or recognizable production secrets were found.
- [x] Public privacy and support URLs return HTTP 200.
- [x] App Store Connect export succeeded with cloud-managed Apple Distribution signing for both targets after the Habit Tracker implementation.

## Apple Developer account gates

- [x] Set `DEVELOPMENT_TEAM` in `project.yml`, then regenerate the Xcode project.
- [x] Register `com.tenora.app` and `com.tenora.app.widgets` with the selected Apple Developer team.
- [x] Register the `group.com.tenora.app` App Group and enable it for both identifiers.
- [x] Create or refresh distribution signing certificates and provisioning profiles.
- [x] Produce a signed Archive build and App Store Connect export.
- [ ] Run Xcode's Validate App action.
- [ ] Upload the validated build to App Store Connect or TestFlight.

## Physical-device acceptance

- [ ] First launch and local task persistence after force-quit/relaunch.
- [ ] Calendar permission: not determined, allowed, and denied flows.
- [ ] iCloud, Google, or Outlook calendar selection and availability calculations.
- [ ] Meeting buffers, minimum usable gaps, and per-day/overnight working hours.
- [ ] Notification permission, delivery, and Done / Later / Tomorrow actions from a cold launch.
- [ ] Just Start timer notification after locking the phone.
- [ ] Small and medium widgets with the shared App Group.
- [ ] Habit schedules, reminders, historical corrections, and the habits widget after force-quit/relaunch.
- [ ] Siri/App Shortcut discovery and capture deep links.
- [ ] Dynamic Type, VoiceOver actions, dark appearance, and reduced motion.
- [ ] Data export and confirmed deletion of local data.

## App Store Connect

- [ ] Create the app record with bundle ID `com.tenora.app`, version 1.0.0, and a permanent SKU.
- [ ] Add the support URL: `https://github.com/mjdriscoll94/tenora/issues`.
- [ ] Add the privacy policy URL: `https://github.com/mjdriscoll94/tenora/blob/main/PRIVACY.md`.
- [ ] Complete App Privacy responses based on the shipping build. The initial build processes task and calendar data locally and does not enable the hosted agent bridge.
- [ ] Complete the current age-rating questionnaire.
- [ ] Complete export-compliance questions for the app's use of standard Apple networking/security APIs.
- [ ] Add app name, subtitle, description, keywords, category, copyright, review contact, and review notes.
- [ ] Capture required screenshots on supported iPhone display sizes using the shipping UI and representative non-sensitive data.
- [ ] Select the uploaded build and complete TestFlight internal testing before review.

## Release discipline

- [ ] Increment `CURRENT_PROJECT_VERSION` for every subsequent upload.
- [ ] Keep privacy answers and the privacy policy synchronized with any future agent bridge release.
- [ ] Repeat Release archive, static analysis, tests, signed-device checks, and URL validation for every submitted build.
