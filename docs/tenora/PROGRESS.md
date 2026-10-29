# Tenora Family Transition — Progress and Verification

**Last updated:** October 29, 2026
**Current product step:** Step 04 — Household permissions, with the Step 03 signed-device gate pending
**Implementation state:** Steps 01 and 02 are complete. Step 03 now has its database
foundation and iOS create, invite, preview, join, and revoke experience. Private sync
infrastructure remains local-only with cloud reads and writes disabled. No shared
productivity data is enabled. Step 03 still requires a signed-device, two-adult lifecycle
check before it is closed. The first isolated Step 04 slice now supports leaving a
household without exposing or deleting personal data. Historical-data gates were waived
for the initial pre-release rollout because current development data may be discarded.

## Work completed

### Product backlog additions

- Added an unscheduled low-friction text-capture concept: users can eventually text
  Tenora and receive the capture in their private Inbox without opening the app.
- Added an unscheduled companion web interface for capture, review, planning, and
  household coordination.
- Both concepts are explicitly gated behind private sync, production authentication, and
  household authorization. Neither changes the current Step 03–05 delivery order, and
  neither permits personal content to become household-visible by default.

### Step 03 household identity foundation

- Reconciled the repository roadmap to the approved five product steps.
- Designed shared household identity as a separate boundary from all personal tasks,
  habits, schedules, settings, calendar information, and attention state.
- Added a migration for households, adult memberships, server-managed invitation state,
  and immutable security audit events.
- Household creation derives the creator from the authenticated Tenora identity and
  atomically provisions an owner membership.
- Added indexed ownership and membership constraints, including one active household per
  adult for this release.
- Added RLS boundaries so members can read only their household, managers can read only
  their household's invitation state, and unrelated adults cannot observe any of it.
- Direct client writes to memberships, invitations, and audit events are denied; those
  lifecycle changes are reserved for controlled command functions in the next slice.
- Added a transactional pgTAP authorization test covering household provisioning,
  isolation, grants, RLS, and audit behavior.
- Added guarded invitation commands for create, privacy-safe preview, atomic acceptance,
  and revocation. Raw 256-bit invitation tokens are returned only once and only hashes are
  stored.
- Enforced a maximum 30-day invitation lifetime, a 20-pending-invitation household limit,
  owner-only admin invitations, one active household per adult, single-use acceptance,
  and idempotent revocation.
- Added a 27-assertion pgTAP invitation suite covering execution grants, hashing,
  normalization, preview, acceptance, isolation, replay rejection, revocation, and audit
  behavior.
- Added the iOS Household settings experience for creating a household, showing adult
  members, creating and sharing one-time invitations, joining by pasted code or link, and
  revoking pending invitations.
- Added `tenora://household/invite/<token>` deep-link routing. A link opened while signed
  out is retained until the adult signs in, then previewed without exposing household
  details to an anonymous session.
- Kept the main Settings menu concise while moving privacy guidance and invitation details
  into the Household screen.
- Reused the authenticated Supabase session for household requests; the iOS app contains
  only the publishable client key and calls the guarded server commands already covered by
  the database authorization tests.

**Verification:** All three Step 03 foundation migrations are recorded in the linked
development project. Transactional live checks proved owner provisioning and rename
auditing, zero-row visibility for an unrelated authenticated adult, no anonymous household
read access, no client INSERT privilege for memberships/invitations/audit events, and no
client access to the private helper schema. RLS is enabled on all four new tables. The
performance advisor's missing foreign-key index was corrected; only expected unused-index
notices remain before real traffic. The security advisor still reports leaked-password
protection disabled; the current Apple-only authentication path does not accept passwords,
but the setting must be enabled before any password-based provider is offered.

The checked-in pgTAP file covers the same boundary. The remote SQL transport parses an
entire batch before executing its in-transaction `create extension`, so it could not run
that file as a single request without permanently enabling pgTAP. Equivalent transactional
checks ran successfully instead; the pgTAP file remains the repeatable CLI/CI gate. No iOS
source changed in this database-only slice, so the previously passing 126-unit/10-UI app
baseline remains the current client verification.

Invitation verification used three temporary authenticated adults in a rolled-back live
transaction. The owner created a 64-character token; the invitee previewed and accepted it,
received an `adult` membership, and saw both household members; the unrelated adult saw
zero household, membership, invitation, and audit rows. A second acceptance failed with
SQLSTATE `55000`, and revocation produced a visible `revoked` state while a repeated revoke
returned false. Supabase's security advisor intentionally reports four
`authenticated_security_definer_function_executable` warnings for these four public RPCs.
This is a reviewed exception: each RPC is deliberately callable only by `authenticated`,
rejects anonymous-auth sessions, derives the actor from `auth.uid()`, performs its own
current database membership check, uses an empty `search_path`, exposes no service secret,
and is the controlled transaction boundary. The pre-existing Apple-only password-protection
warning also remains; performance findings are expected unused indexes before traffic.

The iOS household build passes with the pinned Supabase client. All 133 unit tests pass on
iPhone 16 Pro / iOS 18.3.1, including six household-store tests and household deep-link
coverage. The focused Settings UI test also passes and confirms the Household destination
is present without adding explanatory paragraphs to the root menu. Result bundles:
`/tmp/TenoraHouseholdBuild/Logs/Test/Test-Tenora-2026.10.27_12-58-16--0500.xcresult`
and `/tmp/TenoraHouseholdBuild/Logs/Test/Test-Tenora-2026.10.27_12-58-43--0500.xcresult`.

**Remaining Step 03 gate:** On two signed devices or two separate Apple test accounts,
create a household as the first adult, share the generated invitation, open it as the
second adult, join, confirm both adults appear, revoke a second unused invitation, and
confirm both adults' personal tasks, habits, schedules, calendar details, focus state, and
settings remain absent from the other account. Only after this passes should Step 04 begin
granting or testing access to shared productivity records.

### Step 04 household permissions — leaving a household

- Added an authenticated `leave_household()` command that derives the adult from the
  active session, locks the current membership, and accepts no user or household ID from
  the client.
- Adults and administrators can leave. Their membership is retained as `left`, its end
  time is recorded, and an immutable `member_left` audit event preserves household
  history.
- Leaving immediately removes access to household records while preserving the household,
  remaining memberships, and all private local tasks, habits, schedules, calendar details,
  attention state, and settings.
- Owners cannot leave yet. The database and app require ownership transfer first so one
  adult cannot erase or strand the shared household for everyone else.
- Added a destructive confirmation flow in Household settings and clear owner guidance.
  The app clears the departed household and invitation state after the command succeeds.
- Added a 13-assertion transactional pgTAP suite covering grants, owner protection,
  immediate access removal, idempotency, retained history, and unrelated-adult behavior.

**Verification:** Migration `20261029200942_leave_household_command` is applied to the
linked development project. All 13 database assertions passed in a rolled-back live
transaction. The complete iOS unit suite passed on iPhone 16 Pro / iOS 18.3.1 with 135
tests and zero failures; the focused household store suite passed all eight tests. Result
bundle: `/tmp/TenoraLeaveHouseholdDerivedData/Logs/Test/Test-Tenora-2026.10.29_15-11-38--0500.xcresult`.

Supabase's security advisor now reports the expected reviewed warning for this public
security-definer command, alongside the four invitation commands. It is intentionally
authenticated-only, rejects anonymous sessions, derives the actor from `auth.uid()`,
checks current membership in the database, accepts no identity parameters, and uses an
empty `search_path`.

### Phase 4 local-only sync foundation

- Added additive `TenoraSchemaV2` with a generic sync-metadata sidecar; V1 content models remain unchanged.
- Added idempotent startup inventory for tasks, habits, completions, retained player progress, and retained game unlocks.
- Backfilled records as personal, local-only, owned by the active local profile, with no cloud owner or household assignment.
- Local task and habit repositories now maintain metadata for changes and deletion tombstones in SwiftData.
- Added content-free inventory reporting, explicit optimistic-concurrency/deletion conflict rules, and separate disabled read/write feature gates.
- Added focused tests for private defaults, idempotent backfill, tombstones, conflict behavior, and legacy-store opening.
- Replaced the production file outbox with a SwiftData mutation journal that commits in the
  same save as task/habit content and metadata.
- Added stable idempotency keys, base-version fields, bounded retry scheduling, blocked
  conflict state, and content-free failure codes.
- Added retry-safe, idempotent import of pending Phase 2 file mutations into the journal.
- No Supabase productivity-data schema or upload code was added.

**Verification:** Simulator build passed. The complete unit suite passed with 126 tests,
including an explicit V1-to-V2 store migration and retry-safe legacy-queue import.
Nine unchanged UI flows passed in the full run; the one stale account-configuration test
was updated for the now-configured development project and passed separately, covering all
10 current UI flows. `git diff --check` passed.

### Phase 3 optional-account foundation

- Added a normal-app adult account state machine independent from the disabled Agent Bridge.
- Added native Sign in with Apple with a cryptographic nonce and pinned Supabase Swift 2.55.4.
- Uses the supported Supabase Apple default Keychain session store; no service credential is embedded.
- Added explicit, two-step local-profile association with interruption recovery and reverse uniqueness.
- Added a privacy gate for incomplete and cross-profile account transitions, with widget blanking before profile activation.
- Added concise Account settings and clear local-only/no-upload language.
- Added and applied additive Supabase identity migrations with stable Tenora UUIDs, provider mappings, minimal account profiles, RLS, grants, and private trigger-based provisioning.
- Added local account lifecycle tests and a database authorization test file.
- Documented setup, lifecycle, recovery, rollback, and deferred cloud work in `ACCOUNT_LIFECYCLE.md`.

**Disposition:** COMPLETE for the Phase 3 development-foundation scope. The development
Supabase environment, client configuration, migrations, RLS checks, advisor checks, and
signed-device Sign in with Apple lifecycle are verified. No productivity data is uploaded.
Staging, production operations, deletion/export, and public-release disclosures remain
release gates rather than blockers to closing this implementation phase.

### Phase 3 verification

- Unsigned generic-device Debug build with Supabase Swift 2.55.4: passed.
- Unit suite on iPhone 16 Pro / iOS 18.3.1: 117 executed, 117 passed, 0 failed or skipped.
- UI regression suite on iPhone 16 Pro / iOS 18.3.1: 10 executed, 10 passed, 0 failed or skipped.
- Combined current iOS coverage: 127 tests.
- Post-live-migration full suite on iPhone 16 Pro / iOS 18.3.1: 127 executed, 127 passed, 0 failed or skipped.
- Post-live-migration result bundle: `/tmp/TenoraPhase3LiveGateDerivedData/Logs/Test/Test-Tenora-2026.10.22_13-45-06--0500.xcresult`.
- Unit result bundle: `/tmp/TenoraAuthTestsVerified/Logs/Test/Test-Tenora-2026.10.21_14-48-43--0500.xcresult`.
- UI result bundle: `/tmp/TenoraAuthUITestsFinal/Logs/Test/Test-Tenora-2026.10.21_14-43-24--0500.xcresult`.
- `git diff --check`: passed.
- Supabase development project `hcwtsntljmpbkgzclnxs` is linked and both identity migrations are recorded remotely.
- Live schema verification confirmed RLS on all three account tables, four authenticated ownership policies, no anonymous identity-table access, and no app-role execution privilege on the private provisioning function.
- The transactional pgTAP authorization file completed against the linked database through the Docker-free SQL runner. The CLI's dedicated `test db --linked` wrapper could not run because it unnecessarily required a local Docker/Podman executable on this machine.
- Post-migration advisors report no security warnings. The only performance notice is that the newly created foreign-key index is unused before production traffic, which is expected.
- Signed-device gate reported complete by the product owner on October 22, 2026: Apple sign-in succeeded, the current local profile was connected, the session survived force-quit/relaunch, sign-out succeeded, and local tasks, habits, and settings remained intact.
- Live database verification after the device sign-in confirmed exactly one Apple identity, one Supabase Auth user, one Tenora user, one identity mapping, and one account profile.

- Audited SwiftUI startup, dependency ownership, tabs, navigation, sheets, and deep links.
- Audited all SwiftData entities and other local persistence locations.
- Audited task, habit, legacy gamification, ADHD support, widgets, App Intents, notifications, and EventKit integration.
- Audited Agent Bridge iOS client, OAuth/Keychain flow, Express service, PostgreSQL RLS migration, MCP tools, deployment files, and backend tests.
- Audited assets, privacy manifests, entitlements, XcodeGen configuration, tests, dependencies, and CI.
- Classified features as implemented, partial, or missing.
- Designed the target household privacy boundary and backend approach.
- Designed a staged, rollback-capable migration that preserves local records, settings, and legacy game data.
- Created the five planning documents under `docs/tenora/`.
- Froze the existing five-model SwiftData graph as `TenoraSchemaV1` behind an explicit `TenoraMigrationPlan` and one container factory.
- Added a versioned, checksummed backup containing tasks, habits, completions, preserved player progress/unlocks, transitions, focus/recovery state, working schedule, and attention/calendar/reminder preferences.
- Added restore with checksum and relationship validation, isolated-store staging, a pre-restore recovery copy, and transaction-scoped replacement.
- Added compatibility decoding for the previous incomplete JSON export.
- Replaced ordinary persistent-store startup failure with a non-destructive recovery screen and temporary store; the original store is not deleted.
- Prevented the practical habit tracker from overwriting preserved XP, level, and unlock-era progress values.
- Repaired the calendar settings UI test with a stable accessibility identifier.
- Added regression tests for full backup/restore, altered-file rejection, orphan-record rejection without live-data mutation, unversioned-store reopening, and legacy game-progress preservation.
- Added repository protocols and concrete local repositories for habits, completions, retained progress, transitions, settings, profiles, and a mutation outbox.
- Removed SwiftData knowledge from `HabitStore`; presentation stores now depend on domain repository contracts.
- Added profile-specific SwiftData locations while preserving the original offline store URL.
- Moved active settings UI and calendar/reminder behavior to a versioned, profile-scoped settings repository with compatibility reads for existing keys.
- Namespaced task/habit widget snapshots and pending habit actions by active profile.
- Added a durable, profile-separated JSON mutation outbox without enabling any upload or cloud behavior.
- Added Phase 2 contract tests for settings isolation, outbox persistence, habit persistence/mutations, transition mutations, and widget/focus isolation.

## Repository changes in Phase 1

- New local persistence boundary: `TenoraDataSchema.swift`.
- New backup and restore implementation: `TenoraDataArchive.swift`.
- Data & Privacy now offers both export and confirmed restore.
- App startup now has a recovery state instead of deleting or silently replacing a failed persistent store.
- Habit progress refresh preserves retired game fields.
- Task focus and transitions can be safely reloaded after restore.
- Xcode project regenerated from `project.yml` to include the new source and tests.
- Planning documents updated with verified implementation status and remaining gates.

## Verified baseline

### Phase 2 verification

- Unsigned generic-device Debug build: passed.
- Final unit suite: 105 executed, 105 passed, 0 failed or skipped on iPhone 16 Pro / iOS 18.3.1.
- UI suite: 9 executed, 9 passed, 0 failed in the post-refactor full run.
- Combined current coverage: 114 tests (105 unit + 9 UI).
- Final unit result bundle: `/tmp/TenoraPhase2FinalUnitTests3/Logs/Test/Test-Tenora-2026.10.21_14-15-14--0500.xcresult`.
- The full post-refactor run passed before the final collision-proof profile-path encoding test was added; that last change does not alter offline UI behavior and is covered by the final unit run.

The new Phase 2 tests prove legacy preference adoption only by the offline profile,
cross-profile settings isolation, collision-free provider-subject storage paths, durable
and profile-separated outbox recovery, repository persistence/mutation contracts, and
active-profile widget/focus isolation.

### iOS build

**Command shape:** `xcodebuild` for the `Tenora` scheme, generic iOS device, Debug, unsigned, isolated Derived Data.
**Result:** Passed (`exit 0`) after Phase 1 changes.
**Coverage:** Compiled the Tenora app and its explicit TenoraWidgets dependency using the installed iOS 26.5 SDK with deployment target iOS 17.

### iOS unit tests

**Environment:** iPhone 16 Pro simulator, iOS 18.3.
**Result:** 96 executed, 96 passed, 0 failures.

Tested areas include:

- SwiftData task repository behavior and backward Codable compatibility;
- priority, capacity, availability, buffers, working hours, overnight shifts, and DST;
- resurfacing, reminders, reviews, return triggers, and day horizon;
- task store persistence, focus, Hold My Place, Just Start, notification actions, and recovery;
- habit schedules, prior-day completion, correction, and practical progress;
- calendar store access/filter behavior and transition persistence;
- widgets, routes, and Agent Bridge snapshot privacy/scopes.

New Phase 1 coverage includes complete backup/restore semantic equality, checksum
tampering, orphan completion rejection, old unversioned store reopening with task tags,
and preservation of retired XP/level fields.

### iOS UI tests

**Environment:** iPhone 16 Pro simulator, iOS 18.3.
**Result:** 9 executed, 9 passed, 0 failures.

Passing flows:

- capture, schedule, complete, and open review;
- practical habit dashboard and prior-day check-in;
- Inbox swipe-to-complete;
- Just Start using the smallest next step;
- Lost Track Recovery;
- capture interruption and Hold My Place continuity;
- “I'm stuck” to short start;
- setting one weekday as off and persisting it across relaunch.

Test result bundle:

`/tmp/TenoraPhase1FullTests/Logs/Test/Test-Tenora-2026.10.21_12-13-44--0500.xcresult`

Combined result: 105 tests passed (96 unit + 9 UI), 0 failed, 0 skipped.

### Agent Bridge build and tests

- `npm run build`: passed (`tsc -p tsconfig.json`, exit 0).
- `npm test`: 6 executed, 6 passed, 0 failures.
- The first sandboxed backend test attempt failed because `tsx` could not create a local IPC socket (`EPERM`). The same test command passed when rerun with the required local permission. This is an execution-environment constraint, not a backend test failure.

The six tests cover OAuth challenge scopes, read-only MCP tool advertisement/structured results, per-user in-memory lookup behavior, search, current context, and the no-snapshot empty state.

They do **not** exercise a real PostgreSQL instance, database role, forced RLS policy, migrations, backup/restore, rate limiting, or Render deployment.

## Warnings and blockers

### Phase 1 release disposition

1. **Historical fixtures and physical restore drill:** explicitly waived for the first release because existing development data may be discarded.
2. **Required release check:** uninstall the development build from the test device, install the release candidate into a clean container, and complete the core-flow smoke test.
3. **Task tag warning remains in frozen V1.** Passing tests can emit: `Could not materialize Objective-C class named "Array" from declared attribute value type "Array<String>" of attribute named tags`. A custom-transformer attempt changed the schema signature, so the representation remains unchanged for V1.
4. **Future obligation:** fixture-based, preservation-first migration testing becomes mandatory after the first public release. This waiver must not be reused for production user data.

### P1 before cloud beta

1. The normal-app account client, development Supabase schema, and signed-device lifecycle are verified; deletion/export, administrative revocation operations, and staging/production setup remain before cloud beta.
2. No incremental or bidirectional sync, tombstones, conflict behavior, or durable outbox.
3. No database integration/RLS adversarial test suite.
4. Local state is fragmented across SwiftData, standard defaults, App Group defaults, Keychain, and EventKit.
5. Widget snapshots are local-profile namespaced and blanked before a profile switch; household-scoped widget behavior does not exist yet.
6. Privacy manifests and App Store disclosures describe the current local-only default and must be reassessed before cloud data collection.
7. iOS build/test does not currently run in repository CI.

### P2 before finance

1. No financial threat model, provider, consent model, retention/deletion policy, or compliance review.
2. No restricted finance schema/service, KMS-backed token storage, webhook verification, audit log, or step-up authentication.
3. Household privacy/authorization and recovery must be proven first.

## Feature status checklist

### Implemented

- [x] SwiftUI four-tab app and settings/detail navigation
- [x] Local SwiftData task and habit persistence
- [x] Task capture/edit/complete/delete and Inbox actions
- [x] NOW priority and capacity recommendation
- [x] Per-day/overnight working schedule
- [x] Keep in front, smallest next step, Hold My Place, Just Start
- [x] “I'm stuck” and Lost Track Recovery
- [x] Resurfacing, return triggers, reviews, and transition plans
- [x] Practical habit schedules, history, prior-day correction, and reminders
- [x] EventKit calendar read/filter/availability integration
- [x] Local actionable notifications
- [x] NOW and Habits widgets
- [x] Add Task App Intent and deep links
- [x] Versioned, checksummed local backup; validated restore; destructive reset
- [x] Disabled, opt-in, read-only Agent Bridge prototype

### Partial

- [x] Authentication foundation: normal-app Apple/Supabase client, live development schema, authorization checks, and signed-device lifecycle are verified
- [~] Backend: secure prototype patterns, not a collaboration service
- [~] Cloud data: one-way replaceable task snapshot only
- [~] Data portability: comprehensive local backup/restore is implemented; cloud lifecycle remains, while the pre-release physical-device history drill was waived
- [~] Gamification: legacy data retained, current UI intentionally removed
- [~] CI: backend workflow only; no iOS CI
- [x] Automated test gate: 96 unit and 9 UI tests green

### Missing

- [ ] Production verification, deletion/export, and operations for Tenora accounts
- [ ] Household/membership/invitation/role model
- [ ] Personal versus household record scope
- [ ] Shared assignments/activity/comments/routines
- [ ] Bidirectional offline collaboration sync
- [ ] Server push for remote changes
- [ ] Multi-device restore/account switching
- [ ] Privacy-safe household availability
- [ ] RLS integration and adversarial authorization tests
- [ ] Financial integration platform and controls

## Next decision point

Continue Phase 4 without enabling uploads: replace the Phase 2 file queue with a versioned
retry/idempotency envelope and make the local content change plus mutation journal crash-safe.
Then add a pre-upload backup and content-free reconciliation report before designing the
server change-feed schema. Provision staging/production and finish deletion/export,
monitoring, backup, and disclosure gates before any public cloud beta.
