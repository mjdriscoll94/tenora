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
