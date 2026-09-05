# Attention loop implementation

Six independently committed slices:

1. Task detail, editing, scheduling, due dates, priority, and deletion.
2. Local notifications with persisted Done / Later / Tomorrow actions, quiet hours, and daily limits.
3. App Intent capture, Siri / Shortcuts phrases, and deep links for capture and task opening.
4. Small and medium widgets with NOW, next event, and capture links.
5. Optional morning planning and one-at-a-time evening reset.
6. NOW eligibility, recommendation explanations, calendar refresh, and working-hour preferences.

All task data remains local. Calendar availability is a snapshot, not a guarantee of free time. iOS controls delivery of notifications and widget refreshes. Notification copy must not promise an unverified future calendar gap.

## Notifications

Enable notifications from Settings. The planner schedules a rolling seven-day queue with at most 21 pending reminders, three per local day, separated by two hours and constrained to 09:00–20:00. Previously due reservations remain spent when the queue is rebuilt, so editing tasks cannot reset the daily cap. Explicit postponements override a missed deadline. Completing or deleting tasks removes their future reminders on the next synchronization.

Background notification actions save through the repository and rebuild the queue. Failed decisions are retained locally for retry when the app opens. Open a task from a notification to edit it. iOS may delay or suppress delivery through Focus, notification settings, or system policy; a seven-day queue does not imply indefinite background execution.

## Capture

The Add task to Tenora App Intent is available to Shortcuts and through the phrases “Add a task to Tenora” and “Remember something in Tenora.” It opens the app to keep task storage and reminder updates in one process. A Shortcuts workflow can pass text from its Share Sheet input to this intent. Deep links `tenora://add?title=...`, `tenora://today`, and `tenora://task/<UUID>` support widgets and other local workflows. Capture links prefill a draft and require the user to tap Add. Invalid task links never create tasks.

## Widgets

The embedded TenoraWidgets extension provides small and medium Home Screen widgets. Both deep-link to the recommended task; medium also shows the next timed event and a capture link. Tasks remain in the original SwiftData store. Only a Codable snapshot is shared through `group.com.tenora.app`, avoiding a database migration. Timelines recompute around event boundaries and every 15 minutes; snapshots older than six hours show a refresh prompt. iOS decides actual widget reload timing.

For a physical device or distribution archive, choose your Apple development team and enable the same App Group (`group.com.tenora.app`, or your own identifier changed in both entitlements and WidgetSnapshot) for the app and extension. Unsigned builds verify compilation, not provisioning or Home Screen refresh delivery.
