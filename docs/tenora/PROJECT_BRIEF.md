# Tenora Family Transition — Project Brief

**Status:** Planning only
**Audit date:** October 21, 2026
**Current release baseline:** iOS 17+, app version 1.0.0 (build 1)

## Purpose

Tenora is evolving from a single-person, ADHD-friendly productivity app into a family-first household management app. The transition must add collaboration without weakening the features that make Tenora useful to an individual or exposing one adult's private attention, health-adjacent, calendar, or financial information to another household member.

This brief defines the desired outcome and guardrails. It does not authorize implementation of household features.

## Current product

The shipped code is a local-first iPhone app with four tabs: Today, Inbox, Calendar, and Habits. It uses SwiftUI, SwiftData, EventKit, UserNotifications, WidgetKit, and App Intents. It has no required sign-in and remains fully usable offline.

The product's strongest differentiator is not generic task storage. It is continuity support for executive-function failure points:

- Decide what to do now using deadlines, priority, available calendar time, working hours, and the user's current capacity.
- Keep an important task in front for today without converting it into a rigid schedule.
- Preserve the next physical step and the reason work stopped.
- Offer a short “Just Start” session and contextual “I'm stuck” paths.
- Recover the user's previous thread after an interruption or absence.
- Bring work back after another task, a calendar event, or a usable free window.
- Resurface postponed work without treating postponement as failure.
- Support practical habit check-ins, including corrections for previous days.

Those behaviors should remain personal by default even after household collaboration exists.

## Product objective

Create a shared household layer in which authenticated adults can coordinate household work while each adult keeps a private Tenora space.

The first household release should let adults:

1. Create or join one household.
2. Invite another adult safely.
3. Create, assign, schedule, complete, and discuss shared household tasks and routines.
4. See who owns or completed shared work.
5. Choose what moves from personal to household visibility.
6. Keep personal tasks, habits, working hours, capacity, focus state, notes, and calendar details private unless explicitly shared.
7. Continue working offline and reconcile changes later.

## Non-goals for the first household release

- No automatic sharing of existing local data.
- No child accounts, parental controls, or custody-sensitive access model until separately designed and reviewed.
- No banking credential collection, transaction aggregation, bill payment, money movement, or financial advice.
- No replacement of the current ADHD support flows.
- No requirement that a user sign in before using personal/offline Tenora.
- No revival or deletion of the legacy gamification data during the household migration.
- No use of the unfinished Agent Bridge snapshot as the household synchronization protocol.

## Users and privacy expectations

### Adult with a personal Tenora space

Owns private tasks, habits, settings, focus state, working hours, calendar selections, and attention preferences. Joining a household must not change their default visibility.

### Adult household member

Can see and act on records explicitly created in or moved into the household. They must not be able to infer another adult's private record titles, notes, capacity, calendar event titles, habits, or financial connections.

### Household owner/admin

Can manage membership and household-level configuration. Administrative status does not grant access to another adult's private personal data.

## Privacy principles

1. **Private by default.** Existing and newly captured personal records remain private unless the user deliberately chooses the household.
2. **The household is a scope, not an account.** A person owns an identity; a household is a collaboration boundary with membership and roles.
3. **Administrative access is not personal-data access.** Household owners manage membership, not other adults' private spaces.
4. **Share the minimum.** Calendar availability can be shared as busy/free blocks without event titles. Capacity and recovery state should not be shared.
5. **Make visibility obvious.** Every shared item should show its scope, creator, assignee, and relevant members.
6. **Preserve offline use.** Network or account problems must not make personal data unavailable.
7. **Make deletion complete and understandable.** Local deletion, cloud-account deletion, leaving a household, and deleting shared content are separate actions with explicit consequences.
8. **Treat finance as a separate security domain.** Provider tokens and webhook secrets never belong in the iOS app or general household tables.

## Audit outcome at a glance

| Area | Current state | Household readiness |
|---|---|---|
| SwiftUI app and navigation | Implemented | Good presentation foundation; no account/household navigation |
| Tasks and ADHD workflows | Implemented | Preserve; add ownership/scope without changing behavior |
| Habits | Implemented | Personal-only data model; legacy game columns remain |
| Gamification | Retired from the current UI; legacy persistence remains | Preserve stored progress/unlocks during all migrations |
| SwiftData persistence | Implemented, local only | Needs an explicit versioned schema and migration plan before model changes |
| Preferences and transitions | Implemented across `UserDefaults` | Needs inventory, versioning, and an account-aware settings boundary |
| Calendar | Implemented as on-device EventKit read access | Add privacy-safe availability sharing; do not upload event detail by default |
| Notifications | Implemented locally | Shared assignment notifications and server push are missing |
| Widgets and App Intents | Implemented | Need account/scope-safe snapshots and shared-record deep links later |
| Authentication | Implemented only inside a disabled Agent Bridge build path | No production account lifecycle for the normal app |
| Backend | Read-only Agent Bridge prototype with one snapshot per Auth0 subject | Not a collaboration backend |
| Household model and sync | Missing | Core new platform work |
| Financial integrations | Missing | Deliberately defer behind a hardened server boundary |

The detailed evidence is in [ARCHITECTURE.md](ARCHITECTURE.md). Decisions are in [DECISIONS.md](DECISIONS.md), sequencing is in [ROADMAP.md](ROADMAP.md), and verified results are in [PROGRESS.md](PROGRESS.md).

## Success criteria for architecture implementation

- An existing user upgrades without losing or duplicating any task, habit, completion, setting, transition plan, focus state, game progression record, or unlock.
- All pre-household records become personal/private unless the user explicitly shares them.
- Two adults can make offline edits to different shared items and converge after reconnecting.
- Authorization tests prove that a household member cannot read or mutate another member's private records or a different household's records.
- Revoked members lose access promptly and cannot continue through stale sessions on sensitive operations.
- Calendar titles and notes never leave the device without an explicit, separate opt-in.
- Export and account deletion cover both local and cloud data with documented exceptions for legally required financial records, if those are introduced later.
- Existing unit and UI behavior remains at least as well tested as the audited baseline.

## Constraints

- Preserve the existing bundle identifiers, App Group, local store, and stable UUIDs.
- Keep iOS 17 as the current deployment target unless a separate product decision changes it.
- Keep the app usable without an account during the migration period.
- Do not place service-role credentials, bank-provider tokens, or webhook secrets in the app.
- Do not couple domain record identifiers to an authentication vendor's user identifier.
- Ship migrations behind feature flags with backup, verification, telemetry, and rollback paths.
