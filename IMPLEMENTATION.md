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

## Reviews

Today offers optional Morning review and Evening reset. Both present one unresolved item at a time, exclude tasks scheduled for future days, and persist each decision before advancing. Morning adds Make room today. Both offer Tomorrow, Schedule, Keep reminding me, Done, and confirmed deletion. Closing the flow preserves completed decisions; the next session recomputes the queue from persisted tasks. Tomorrow means 9 AM on the next local calendar day, including daylight-saving transitions, and does not change a task's actual deadline.

## NOW

Recommendations respect a personal weekly work schedule, future schedules, snooze return dates, active meetings, and estimated duration versus the available gap. Each weekday can use different minute-level start and end times, be marked as a day off, or run overnight into the following day. The schedule repeats in local wall-clock time across time-zone and daylight-saving changes. Existing single-range settings initialize all seven days until the weekly schedule is edited. Without calendar access, Tenora cannot check meetings or gap size. Start persists a focused task; completing, postponing, scheduling, or deleting it releases focus. Focused tasks are excluded from reminder scheduling. The card explains its recommendation, and resurfacing is limited to two additional eligible items.

The foreground app refreshes every minute and on activation; EventKit changes refresh calendar data. Failed calendar reads discard stale availability. Overnight calendar reads continue through the end of the active shift. Widgets share the weekly schedule and focus and add work, schedule, and return boundaries to their timelines. Unchanged minute refreshes do not repeatedly move pending notification delivery times.

## Device acceptance checks

Validation: 62 unit tests and four isolated simulator UI tests cover the domain/store rules, contextual return triggers, transition-plan persistence, the day horizon, per-day schedule persistence, Just Start, capture → schedule → complete → review navigation, and resume → interruption capture → hold context. The UI tests use an in-memory task store. An unsigned iOS device build checks compilation of the app and widget.

Before release, verify notification permission, delivery and cold-launch actions; Siri phrase discovery; Share Sheet capture through a configured Shortcut; and small/medium widgets on a signed physical device with the App Group enabled. No native Share extension is included. Automated domain/store tests and unsigned builds do not replace those device checks.

## Preserving your place

Tasks can store a smallest next step, the time they were held, an optional reason for stopping, and the last time work intentionally resumed. These are optional persisted fields; older widget snapshots without them still decode.

Hold my place is available from NOW and task details. It preserves the next step and releases active focus. Choose a return time, or let Tenora resurface the task after four hours under the existing reminder limits. Resume deliberately clears scheduling and snooze dates while preserving the actual deadline.

Today keeps “What was I doing?” available even outside working hours. After at least 15 minutes in the background, returning to the app presents the Resume screen when an unresolved current or held task exists. It shows the next step, pause reason, and the number of unfinished items whose deadline or return time passed while away. Explicit task/capture links take precedence. Completed and deleted tasks are excluded.

Capturing while a task is current shows “Captured. Back to…” and a Resume action. It saves the new intention without replacing focus. Siri capture also names the current task in its confirmation; the medium widget shows the next step when present.

This phase implements next steps, Hold My Place, Resume, and interruption capture. Location integration, Lock Screen controls, and Live Activities remain future phases.

## Just Start

Just Start turns a task's smallest next step into a three, five, or ten-minute commitment. A session stores its absolute start and end time with the task, so locking the phone, leaving Tenora, or relaunching the app cannot reset the countdown. An active session remains available from Today even outside normal recommendation conditions.

When time expires, Keep going removes the timer and leaves the task focused. I'm done for now releases focus, preserves the next step and deadline, adds no snooze penalty, and returns the task after four hours. Complete task resolves it normally. Holding, postponing, scheduling, reviewing, or completing a task clears any active short session.

When notification access is enabled, Tenora schedules one session-end notification with Keep going, Done for now, and Complete task actions. Resolving the session removes its pending or delivered prompt. In-app and notification decisions share the same persisted actions.

## Contextual returns and day transitions

Each unresolved task can return after another task is completed, after a selected calendar event ends, or when a free calendar window meets a chosen 15–60 minute minimum. The condition is stored with the task. Task dependencies resolve immediately when the preceding task completes; calendar and free-window conditions are reevaluated on calendar changes, app activation, and the foreground minute refresh. Without calendar access, Tenora preserves free-window conditions but cannot claim that a gap is available.

Today combines future task times, timed events, and transition cues into Soon (the next three hours) and Later (the following 21 hours). NOW remains a single recommendation. A task appears only once in the horizon even when it has several relevant dates, using its earliest upcoming time.

Calendar event details can enable a leave reminder and an earlier wrap-up reminder. Transition plans stay on-device, follow event title/time changes while the event remains in the loaded calendar window, and are removed one day after their event. Notification permission and iOS delivery policy still govern whether alerts appear.

## ChatGPT Agent Bridge

Phase 4A adds an opt-in, one-way snapshot bridge and a read-only MCP server. The iOS app continues to own task state and work offline. A configured release build can authenticate through an OAuth 2.1/OIDC provider and upload the newest complete snapshot; older uploads cannot replace newer ones. Access tokens are stored in the device Keychain.

Task notes and calendar context are disabled independently by default. The base task snapshot contains titles, status, dates, priorities, tags, next steps, and contextual-return summaries. The user can delete the hosted snapshot before disconnecting, or disconnect only the current device while leaving data available to another authorized client.

The TypeScript service in `AgentBridge/` exposes `list_tasks`, `get_task`, `get_now_context`, `get_today_schedule`, `search`, and `fetch`. All tools are read-only. JWT signature, issuer, audience, expiry, and scope are checked before the authenticated subject reaches the repository. PostgreSQL queries include the subject and run under forced row-level security.

Bridge validation includes TypeScript compilation, four service/MCP protocol tests, the 62-test iOS unit suite, four simulator UI acceptance flows, and an unsigned iOS device build. Live OAuth, PostgreSQL, HTTPS deployment, and ChatGPT connection checks require the production issuer, database, and host values documented in `AgentBridge/README.md`.
