# Attention loop implementation

Six independently committed slices:

1. Task detail, editing, scheduling, due dates, priority, and deletion.
2. Local notifications with persisted Done / Later / Tomorrow actions, quiet hours, and daily limits.
3. App Intent capture, Siri / Shortcuts phrases, and deep links for capture and task opening.
4. Small and medium widgets with NOW, next event, and capture links.
5. Optional morning planning and one-at-a-time evening reset.
6. NOW eligibility, recommendation explanations, calendar refresh, and working-hour preferences.

All task data remains local. Calendar availability is a snapshot, not a guarantee of free time. iOS controls delivery of notifications and widget refreshes. Notification copy must not promise an unverified future calendar gap.
