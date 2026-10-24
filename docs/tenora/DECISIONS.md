# Tenora Family Transition — Architecture Decisions

**Status:** Proposed decisions from the October 21, 2026 audit.
Implementation should not begin until the product owner accepts or amends these decisions.

## D-001 — Use a hybrid local-first architecture

**Decision:** Keep an on-device database for responsive offline behavior and add an authoritative cloud collaboration store for authenticated data.

**Why:** Tenora's personal attention loop must work without a network. Household members nevertheless need a common source of truth, authorization, revocation, auditability, and cross-device reconciliation.

**Consequences:**

- SwiftData remains a local materialized store, not the sole source of truth for shared records.
- A sync engine needs an outbox, cursor-based inbound changes, tombstones, retries, idempotency, and conflict rules.
- Personal-only mode remains supported.

## D-002 — Use PostgreSQL as the household system of record

**Decision:** Model identities, households, memberships, records, assignments, completions, invites, and audit events relationally in PostgreSQL.

**Recommended managed implementation:** Supabase Postgres + Auth + Realtime/Edge Functions for the first household platform, while keeping an application-owned service/repository layer so the app is not coupled directly to vendor-specific types.

**Why:** Household membership and future financial records are relational and permission-heavy. PostgreSQL provides constraints, transactions, row-level security, mature backup tooling, and an appropriate future home for ledger-like data. Supabase currently provides a maintained Swift client, authentication, Postgres row-level security, and realtime primitives in one managed surface. Its documentation explicitly requires RLS on exposed tables and supports private realtime channels; those controls match the household boundary when implemented and tested carefully.

**Alternatives considered:**

| Option | Assessment |
|---|---|
| SwiftData + CloudKit sharing | Lower initial Apple-only effort, but a poor fit for server-side financial webhooks, non-Apple access, explicit household roles, SQL constraints, and centralized audit/control. |
| Existing Auth0 + Render + Neon | Technically viable and reuses the prototype, but Tenora would own more custom session, sync, API, realtime, operations, and authorization code. Prefer this only if retaining Auth0 is a hard business requirement. |
| Firebase | Strong mobile/offline tooling, but household permissions and future finance are more naturally modeled and audited relationally; complex security rules would duplicate relational logic. |
| Agent Bridge snapshot table | Reject. It stores one replaceable JSON snapshot per user and has no household or mutation protocol. |

**Security caveat:** Supabase is not secure by default merely because it supports RLS. Every exposed table needs explicit grants and least-privilege RLS policies. Authorization must use immutable membership records or trusted app metadata, never user-editable metadata. Secret/service credentials remain server-only. See the current [Supabase RLS guide](https://supabase.com/docs/guides/database/postgres/row-level-security), [security guidance](https://supabase.com/docs/guides/security/product-security), and [Realtime authorization guide](https://supabase.com/docs/guides/realtime/authorization).

## D-003 — Separate identity from domain ownership

**Decision:** Use application UUIDs for `users`, `households`, and records. Store authentication identities in a mapping table such as `user_identities(provider, provider_subject, user_id)`.

**Why:** Auth providers can change. Records and household memberships must survive provider migration, account linking, or the addition of Sign in with Apple.

**Consequences:** Never use an Auth0 `sub` or Supabase Auth UUID as the only domain identifier on tasks, habits, or households.

## D-004 — Make every collaborative record's scope explicit

**Decision:** Records use an explicit scope:

- `personal`: visible only to the owner.
- `household`: visible to authorized members of one household.
- `selected_members`: deferred until product need justifies its complexity.

Every scoped record also carries `owner_user_id`, nullable `household_id`, `created_by`, `updated_by`, `version`, timestamps, and a deletion tombstone.

**Why:** Inferring privacy from a nullable owner or screen location is unsafe. Explicit scope enables consistent UI and database policy.

## D-005 — Existing records migrate as personal/private

**Decision:** All records that predate household support remain personal. No migration may automatically share tasks, notes, habits, calendar details, working hours, focus state, or game history.

**Why:** Consent cannot be inferred from joining a household.

## D-006 — Preserve personal attention state outside the household model

**Decision:** Keep these per-user and private by default:

- capacity mode and selection time;
- focused task and recovery/last-left state;
- working schedule;
- task notes and “why I stopped” context;
- private habits and habit history;
- calendar selection and event titles;
- reminder/recovery preferences;
- Agent Bridge sharing preferences and tokens.

Shared tasks may still have per-member presentation state, such as “keep this in front for me,” stored separately from the shared task.

**Why:** One adult's executive-function support should not become household surveillance or cause another adult's preferences to overwrite theirs.

## D-007 — Introduce explicit SwiftData schema versioning before adding fields

**Decision:** The first implementation phase creates a `VersionedSchema` and `SchemaMigrationPlan` representing the exact audited models before any household fields or sync metadata are added.

**Why:** The current `ModelContainer` lists model types directly and relies on inferred migration. Adding ownership and sync fields without a frozen baseline creates an avoidable data-loss risk.

**Consequences:** After the first public release, migration tests must open fixture stores created by the prior app version. The non-failing Core Data warning for `StoredTask.tags: [String]` must be resolved or explicitly transformed in a versioned migration before changing that field.

## D-008 — Use an incremental, idempotent sync protocol

**Decision:** Do not upload whole app snapshots for collaboration. Sync operations should carry stable record UUIDs, client mutation IDs, base/server versions, and deletion tombstones. The server returns a monotonic cursor/revision for incremental downloads.

**Conflict defaults:**

- Independent records merge independently.
- Scalar fields use server-validated optimistic concurrency; simple non-overlapping changes can merge.
- Completion/activity events are append-only and idempotent.
- Deletes are tombstones retained through a defined synchronization window.
- Irreconcilable simultaneous edits create a visible conflict instead of silently discarding data.

## D-009 — Keep the Agent Bridge isolated

**Decision:** The disabled Agent Bridge remains a separate, opt-in, read-only integration experiment. Its `tenora_snapshots` table and `tasks:read`/`tasks:sync` scopes are not extended into household storage.

**Why:** It has useful OAuth and RLS lessons, but its replace-one-snapshot design cannot provide collaborative mutations, conflict handling, invites, membership revocation, or record-level privacy.

**Future:** After the household API is secure, a new agent integration can query permitted records through the same authorization service. It must never receive more access than the connected user.

## D-010 — Share calendar availability, not calendar content, by default

**Decision:** EventKit remains device-local. If household scheduling needs availability, upload coarse busy/free intervals with expiration and no title, notes, attendee, calendar name, or external identifier unless the user separately opts in.

**Why:** A calendar often reveals medical, work, school, religious, or relationship information. A household usually needs availability, not event content.

## D-011 — Treat finance as an isolated later phase

**Decision:** Financial provider access is server-mediated and separated into a restricted schema/service. The iOS app never stores provider secrets or raw banking credentials.

**Required controls before finance work:** explicit consent, short-lived link tokens, encrypted provider tokens in a managed secret/KMS boundary, webhook signature verification, idempotent ingestion, least-privilege service roles, audit logs, retention/deletion rules, incident response, and legal/compliance review.

**Why:** Household productivity data and financial data have different risk, retention, and support requirements. The first household release should not inherit financial blast radius.

## D-012 — Preserve legacy gamification data without reviving it

**Decision:** Keep `StoredPlayerProgress`, `StoredGameUnlock`, `HabitCompletion.xpAwarded`, and `Habit.difficulty` through local and cloud migrations. Do not display, reset, or delete them as part of household work.

**Why:** The current habit UI is intentionally practical rather than gamified, but prior user data may exist. Preservation is cheaper and safer than an irreversible cleanup.

## D-013 — Use feature flags and staged rollout

**Decision:** Account creation, cloud backup, household creation, invites, and shared mutations ship behind independent server-controlled gates. The local-only path remains available until import and rollback metrics are proven.

**Why:** Authentication, migration, and synchronization fail differently. Independent gates reduce the recovery surface.

## D-014 — Make authorization verifiable at the database boundary

**Decision:** RLS policies use membership tables and record scope, with both read predicates and mutation checks. Service-only webhook operations use a non-exposed schema and a narrowly scoped role. Tests attempt cross-user, cross-household, revoked-member, stale-token, and ownership-transfer attacks.

**Why:** UI hiding and API route checks are insufficient against broken object-level authorization.

## D-015 — Keep secrets and private tokens out of shared storage

**Decision:** OAuth access/refresh tokens remain in the iOS Keychain or a server-side encrypted secret store according to their use. They are never synchronized as ordinary user data, written to logs, or copied into household records.

## D-016 — Freeze the released local representation as schema V1

**Decision:** `TenoraSchemaV1` uses the exact model representation already present in
existing stores, including the inferred `[String]` representation for task tags. The
Core Data materialization warning is documented but the field is not silently changed
inside V1.

**Why:** A trial replacement with a custom transformer changed the schema signature and
caused an existing simulator store to fail during startup. Preserving readable user data
has higher priority than suppressing a non-failing warning.

**Consequence:** A future V2 must move tags to an explicitly supported representation
through a tested migration. That migration cannot ship until fixtures from the last
distributed app pass empty, typical, large, and legacy-game upgrade tests.

## D-017 — Initial release may start with a clean local store

**Decision:** The product owner confirmed on October 21, 2026 that current development
data does not need to survive the first public rollout. Existing simulator and test-device
installations may be removed before installing the release candidate.

**Why:** Tenora has not established a production-data preservation requirement for the
current local datasets. Requiring physical-device recovery drills and historical fixture
capture would delay the initial release without protecting user data that must be retained.

**Guardrail:** This is a one-time pre-release decision, not permission for future builds
to delete user data automatically. The versioned schema, backup/restore, safe startup,
and preservation-first migration rules remain in the codebase for all post-release data.

## D-018 — Namespace local state before introducing identity

**Decision:** Every local persistence surface now accepts a `LocalProfileID`. The existing
installation is the stable `offline` profile; future authenticated profiles use separate
SwiftData files, versioned settings keys, outbox files, widget snapshots, focus state, and
pending action queues.

**Why:** Authentication must not be allowed to arrive before local isolation. Otherwise,
sign-out or account switching could expose one adult's focused task, habits, schedule, or
widget content to another adult using the same device.

**Compatibility:** Only the `offline` profile may read and mirror the pre-namespace
UserDefaults keys. Authenticated profiles never fall back to those keys. This bridge stays
for at least one stable release and must be removed through an explicit later migration.

**Consequence:** Phase 2 creates local profiles and an outbox but does not create accounts,
send mutations, or change the source of truth. Phase 3 owns identity/session lifecycle;
Phase 4 must make local-record and outbox writes transactionally consistent before sync is enabled.

## D-019 — Optional adult identity does not imply cloud storage

**Decision:** Phase 3 uses native Sign in with Apple through Supabase Auth, but creates only
a stable Tenora adult identity and an explicit local-profile association. Signing in does
not upload productivity data, enable the mutation outbox, create a household, or change
the local source of truth.

**Why:** Identity and synchronization fail differently and require different consent.
Separating them keeps local Tenora useful during outages and prevents a sign-in button
from making a misleading privacy promise.

**Consequence:** The account UI states that data remains on-device. Supabase configuration
may be omitted to ship a local-only build. Production account status remains blocked until
the external project, Apple capability, migration, and RLS tests are verified.

## D-020 — Local profile association is explicit and interruption-safe

**Decision:** A signed-in adult must choose which local profile to associate. The mapping
is persisted as `pending` then `complete`, one completed profile may belong to only one
account, and a cross-profile session privacy-locks content until restart completes.

**Why:** Silently binding the active store risks data duplication and cross-account
exposure. A two-step local marker supports retry without moving or deleting records.

**Consequence:** Live in-memory profile replacement is deferred. The protected switch is
completed through a normal app reopen after widgets are blanked and the active namespace
is changed.

## D-021 — Add sync metadata as a private sidecar

**Decision:** SwiftData V2 adds one `StoredSyncMetadata` sidecar keyed by entity type and
stable record ID. The V1 task, habit, completion, player-progress, and unlock models remain
unchanged. Startup idempotently inventories those records as `personal` and `localOnly`.

**Why:** This keeps the first Phase 4 migration additive and reversible. It also avoids
putting cloud ownership onto a record merely because a user signed in. Cloud owner IDs,
household IDs, server versions, and acknowledgements remain empty until a separate,
explicit sync consent flow succeeds.

**Guardrail:** Sync reads and writes are independently disabled. Local repositories may
maintain sidecar state and tombstones, but no code may transmit content until the outbox
and local-record write are transactional, reconciliation is proven, and the user opts in.

## D-022 — Keep sync mutations in the local database transaction

**Decision:** Phase 4 stores mutation envelopes in SwiftData V2. Task and habit repositories
stage the content edit, metadata update or tombstone, and mutation before one `ModelContext`
save. The Phase 2 file queue is imported idempotently and cleared only after all destination
inserts succeed.

**Why:** Saving content and then writing a separate file can lose the intent to sync after a
crash, while writing the file first can upload a change the local database rejected. One
transaction eliminates that split-brain window for the initial personal-sync entities.

**Consequence:** Transition plans still use their existing local preference store and are
not in the initial personal-sync entity set. They need an explicit storage migration before
they can receive the same transaction guarantee.

## D-023 — Use narrowly exposed transactional RPCs for household invitations

**Decision:** Invitation creation, preview, acceptance, and revocation are authenticated
Postgres RPCs rather than direct table writes. They use `SECURITY DEFINER` intentionally so
each command can lock and mutate invitation, membership, and audit rows atomically while
clients retain no table mutation privileges.

**Why:** RLS alone cannot safely return a one-time raw token, consume it once, update a
membership, and append an audit event as one indivisible operation without granting broad
direct-write access. The RPCs derive the actor from `auth.uid()`, reject anonymous-auth
sessions, re-read current membership state, use an empty `search_path`, and are executable
only by the authenticated role.

**Advisor exception:** Supabase intentionally reports these commands under
`authenticated_security_definer_function_executable`. This warning is accepted only for
the four named invitation RPCs and must be re-reviewed whenever their bodies, grants, or
parameters change. All other privileged helpers remain in the unexposed `private` schema.

**Token handling:** Creation returns 32 random bytes encoded as hexadecimal. Only a SHA-256
hash is stored. Tokens expire within 30 days, are single-use, and never grant access without
a separately authenticated adult account.
