# Tenora Family Transition — Roadmap

**Planning baseline:** October 21, 2026
**Rule:** Do not start household feature UI until Phase 1 data-safety exit criteria pass.

## Delivery principles

- Additive and reversible migrations.
- Personal/offline mode remains functional at every phase.
- Existing data is private by default.
- Server authorization is tested independently of client UI.
- Each phase has a feature flag, migration telemetry, and rollback plan.
- Legacy gamification data is preserved even though the current UI is practical and non-gamified.

## Phase 0 — Audit and architecture

**Status:** Complete in documentation; no product implementation performed.

### Deliverables

- Repository and feature inventory.
- Current and target architecture.
- Backend decision and alternatives.
- Data classification and privacy boundary.
- Migration strategy and technical risk register.
- Build/test baseline.

### Exit criteria

- Product owner reviews [PROJECT_BRIEF.md](PROJECT_BRIEF.md).
- Proposed decisions in [DECISIONS.md](DECISIONS.md) are accepted or amended.
- First household release scope is frozen.

## Phase 1 — Make current data safe to evolve

**User-visible household features:** None.

**Status (October 21, 2026):** Complete for the initial pre-release rollout. The versioned
schema, complete backup/restore, safe startup recovery, legacy-store test, preservation
tests, and full automated suite are green. The product owner explicitly waived historical
fixture capture and a physical-device restore drill because current development data may
be discarded before the first release. The existing inferred
`[String]` tag warning remains intentionally unchanged in V1; changing its transformer
altered the schema hash and failed the old-store compatibility gate. Move that field only
in an explicit V2 migration after the first public release establishes persistent user data.

### Work

1. [x] Define the current models as `TenoraSchemaV1` with an explicit `SchemaMigrationPlan`.
2. [x] Confirm historical fixture requirement. Waived for the first release because development data may be discarded; fixture capture becomes mandatory after public release.
3. Add upgrade tests for empty, typical, large, and legacy-game datasets.
4. [ ] Replace or explicitly migrate the `[String]` tags persistence representation that produces the Core Data warning. Deferred to V2 after a compatibility attempt proved unsafe.
5. [x] Version the export format and include every Tenora-owned data source:
   - all five SwiftData entities;
   - transitions;
   - focus and recovery state;
   - working schedule and all attention/calendar/reminder preferences;
   - legacy player progress and unlocks;
   - migration metadata and checksums.
6. [x] Add import/restore staging in an isolated store, checksum and relationship validation, a pre-restore recovery backup, and a transaction-scoped live replacement.
7. [x] Replace ordinary persistent-store startup failure with a non-destructive recovery screen and temporary in-memory store.
8. [x] Repair the calendar settings UI-test assertion with a stable accessibility identifier and make the full suite green.

### Tests

- Old-store open and migrate.
- Export/import round trip with semantic equality.
- Interrupted migration and retry. *(Mandatory for the first post-release schema change.)*
- Corrupt export rejection without touching live data.
- Orphan completion detection.
- Legacy progression/unlock preservation.

### Exit criteria

- 100% of fixture IDs and required fields survive migration.
- Export/import restores every documented local data source.
- Device build, 96 unit tests, and all 9 UI tests pass. The pre-existing inferred-array warning is accepted only for V1 compatibility and has a mandatory V2 migration task.
- [x] Physical-device historical-data drill waived for the initial release by explicit product decision. A clean-install device smoke test replaces it.

## Phase 2 — Refactor persistence boundaries

**User-visible household features:** None.

**Status (October 21, 2026):** Implemented. The app now uses profile-scoped repository
boundaries for tasks, habits, completions, transitions, settings, focus state, local
stores, notification queues, and widget snapshots. A durable file-backed mutation outbox
is present but deliberately has no network consumer. Legacy offline settings continue to
be copied and mirrored for one compatibility release.

### Work

1. [x] Add repository protocols for habits, completions, settings, transitions, and profile state, matching the existing task repository boundary.
2. [x] Stop allowing presentation stores to know SwiftData details directly.
3. [x] Introduce an account/profile namespace for local records and App Group widget snapshots.
4. [x] Add a durable local outbox type without transmitting data yet.
5. [x] Centralize all Tenora-owned `UserDefaults` keys in a versioned settings repository.
6. [x] Keep compatibility reads for legacy keys through at least one stable release.

### Exit criteria

- [x] Existing UI behavior is unchanged.
- [x] Repository contracts and existing store tests cover each local record family.
- [x] Active-profile widget tests prove that another profile's task/focus snapshot is not read.

## Phase 3 — Cloud and identity foundation

**User-visible household features:** Optional Tenora account only.

### Work

1. Provision separate development/staging/production managed PostgreSQL projects.
2. Add Tenora users and provider identity mappings.
3. Implement Sign in with Apple and email link sign-in; retain offline use.
4. Define normalized tables, constraints, migrations, RLS, audit events, and restricted server roles.
5. Build the command API for sensitive operations instead of exposing service credentials to iOS.
6. Add session revocation, account deletion/export, rate limiting, monitoring, backups, and secret rotation procedures.
7. Update privacy policy, App Store privacy disclosures, and privacy manifests before any cloud collection flag is enabled.
8. Keep Agent Bridge data and scopes separate.

### Security tests

- Anonymous, cross-user, and cross-household reads/writes fail.
- Owners/admins cannot read another adult's personal records.
- UPDATE cannot change owner/scope/household outside policy.
- Revoked memberships fail with fresh and stale sessions on sensitive routes.
- No server secret exists in app artifacts or logs.
- Database backup and point-in-time recovery drill.

### Exit criteria

- Threat model reviewed.
- RLS and API integration tests run in CI against an ephemeral/staging database.
- Production is not enabled until security advisors/checks are clean or exceptions documented.

## Phase 4 — Private personal sync pilot

**User-visible household features:** Multi-device private backup/sync for opted-in accounts.

### Work

1. Add additive sync metadata to SwiftData V2.
2. Backfill all existing records as personal/private.
3. Implement local outbox, batch mutations, idempotency, server versions, tombstones, cursor download, and retry/backoff.
4. Add a pre-upload backup and a visible migration report.
5. Reconcile counts, IDs, and hashes before changing cloud/local source-of-truth behavior.
6. Implement account-linking decisions when a signed-in cloud account and device both contain data.
7. Keep notes/calendar upload behind separate explicit controls.

### Tests

- First upload, retry, interrupted upload, duplicate mutation, and reinstallation restore.
- Two devices create/update/delete different records and converge.
- Simultaneous edit conflict and deletion/edit conflict.
- Account switch with no cross-profile data or widget leakage.
- Offline personal use for extended periods.

### Exit criteria

- No silent loss or duplication in automated and beta reconciliation reports.
- Cloud kill switch returns users to usable local state.
- Support can diagnose sync state without reading private content.

## Phase 5 — Household identity and membership

**User-visible household features:** Create/join a household and manage adult members.

### Work

1. Household creation.
2. Expiring, single-use adult invitations.
3. Owner/admin/adult roles.
4. Membership acceptance, revocation, leaving, and ownership transfer.
5. Clear household/privacy onboarding.
6. Audit trail for membership and role changes.
7. Recovery paths for expired/revoked invites and last-owner departure.

### Exit criteria

- Membership lifecycle and authorization tests pass.
- A household admin cannot access another adult's private data.
- Revocation removes realtime, API, and subsequent sync access.

## Phase 6 — Shared household tasks and routines

**User-visible household features:** First collaborative value release.

### Work

1. Explicit personal/household scope picker with plain-language visibility.
2. Shared task/list/routine creation.
3. Assignee, creator, completion actor, and activity history.
4. Remote change reconciliation and APNs notifications.
5. Per-member attention state for shared tasks so one adult's “keep in front” or focus does not affect another.
6. Intentional personal-to-household move/copy flow.
7. Household-aware widgets and deep links with redaction and account namespace.
8. Conflict UI and recovery for deleted/edited shared work.

### Exit criteria

- Two adults can work offline, reconnect, and converge without losing completed work.
- Visibility is clear on every create/edit/detail surface.
- Existing ADHD workflows operate on both personal and shared tasks without sharing private attention state.

## Phase 7 — Privacy-safe household scheduling

**User-visible household features:** Find workable household time without exposing calendar contents.

### Work

1. Opt-in derived busy/free blocks with expiration.
2. Per-member availability sharing controls.
3. Household availability view and shared task placement suggestions.
4. No event title, notes, attendees, calendar name, or source identifier by default.
5. Clear revocation and deletion when availability sharing is disabled.

### Exit criteria

- Turning off sharing removes server availability within the documented window.
- Other members cannot recover source event details.
- Time-zone, DST, overnight work, and travel cases are tested.

## Phase 8 — Hardening and staged rollout

### Work

1. Internal, small beta, expanded beta, then staged production gates.
2. Migration success, reconciliation, authorization denial, crash, and sync-latency metrics without private content.
3. Accessibility and localization audit.
4. Restore, region outage, auth outage, push failure, and database recovery drills.
5. Support/admin tools with audited, least-privilege access.
6. Data retention and account/household deletion verification.
7. Independent security review before broad rollout.

### Exit criteria

- Release checklist and incident runbooks approved.
- Migration rollback drill completed.
- Full tests green across oldest supported iOS, current iOS, and representative devices.

## Phase 9 — Financial discovery and gated implementation

**Do not begin until Phases 3–8 meet their security/reliability gates.**

### Discovery

- Define whether Tenora needs bill reminders, shared budgets, account aggregation, or money movement; these have very different obligations.
- Complete legal, privacy, security, support, and provider reviews.
- Define adult consent and visibility rules for joint versus individual accounts.
- Decide retention, deletion, export, dispute, and incident procedures.

### Technical foundation

- Separate restricted database schema/service and roles.
- Server-created short-lived provider link tokens.
- Encrypted provider access tokens in a managed secret/KMS boundary.
- Signed webhook verification and idempotent event processing.
- Append-only ledger/audit events where appropriate.
- Step-up authentication for sensitive actions.
- No raw credentials or service secrets on device.

## Cross-phase quality gates

Every implementation phase must include:

- a migration/rollback note;
- data classification review;
- unit, integration, UI, and authorization tests appropriate to the change;
- privacy disclosure review;
- accessibility labels for new UI;
- telemetry that excludes titles, notes, calendar content, and financial content;
- documented support behavior for offline, expired session, revoked membership, and partial failure.
