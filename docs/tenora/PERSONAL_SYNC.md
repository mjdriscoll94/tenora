# Tenora Private Personal Sync

**Status:** Local foundation only. Cloud reads and writes are disabled.

## What exists now

- SwiftData V2 adds a sidecar record for sync metadata without changing the V1 content models.
- Existing tasks, habits, completions, retained progress, and retained unlocks are inventoried idempotently.
- Every inventoried record begins as personal and local-only.
- Cloud owner, household, server-version, and acknowledgement fields begin empty.
- Local task/habit changes refresh metadata; local deletes retain a tombstone.
- Support-facing inventory contains counts and states, never titles, notes, or habit names.
- Mutable version mismatches and edits after a remote deletion are explicit conflicts. Habit completions are immutable events deduplicated by UUID.

## Safety gates

`personalSyncReadEnabled` and `personalSyncWriteEnabled` are both hard-disabled. Signing in
does not change them. No Phase 4 code currently creates a cloud content table, calls a sync
endpoint, uploads an outbox, or treats Supabase as the source of truth.

## Required before the write gate can open

1. Replace the current compatibility outbox with versioned mutation envelopes containing an idempotency key, base server version, attempt state, and timestamps.
2. Make content writes and mutation journaling crash-safe as one local operation.
3. Create a complete pre-upload backup and show a content-free migration/reconciliation report.
4. Add an explicit user choice for device-only data versus an existing cloud dataset.
5. Add and adversarially test personal-record RLS in a non-production Supabase environment.
6. Prove first upload, retries, interruption, duplicate delivery, conflicts, reinstall restore, account switching, and two-device convergence.
7. Keep notes and all calendar content outside default consent.

## Rollback

Turning both gates off leaves the app fully local. The metadata sidecar is reconstructible
from the content models and does not alter them. Local content is not deleted after an
upload or during the release that first introduces sync.
