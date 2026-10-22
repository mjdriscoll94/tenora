# Tenora Optional Account Lifecycle

**Implementation status:** Client and development Supabase foundation verified; signed-device Apple lifecycle verification remains.

## Boundaries

An authenticated adult, a local data profile, a future household membership, and a
future managed child profile are separate concepts. Phase 3 only creates the first two.
Signing in does not create a household, share records, enable synchronization, or upload
tasks, habits, settings, calendar information, focus state, or working hours.

The app remains fully usable without an account. Account failures never block the
`offline` profile.

## Client lifecycle

1. On launch, an unconfigured build enters local-only mode.
2. A configured build asks the supported Supabase client to restore its Keychain-backed
   session and refresh it when necessary.
3. No session shows signed-out status. An expired, revoked, or unreachable session shows
   a recoverable state while local data remains available.
4. Native Sign in with Apple creates or restores the Supabase Auth identity. A random
   nonce and SHA-256 digest protect the exchange.
5. A private database trigger creates the provider-independent Tenora UUID as part of
   the trusted Supabase Auth user insertion. The client reads its own identity mapping
   through RLS; there is no privileged account-creation RPC exposed to the app.
6. The adult explicitly connects that UUID to either the current local profile or a new,
   separate local profile. This association is written as `pending` and then `complete`
   so an interrupted operation can be retried or removed without copying data.
7. If the associated profile differs from the profile loaded in memory, Tenora hides all
   productivity content, clears the destination widget snapshots, changes the active
   profile marker, and asks the user to reopen the app.
8. Sign-out uses local scope, removes the device session, and retains local data and the
   account/profile association.

One completed local profile cannot be associated with two Tenora accounts. There is no
automatic merging, duplication, upload, or deletion.

## Provider and app configuration

Use separate Supabase projects for development, staging, and production. Apply both
identity migrations under `supabase/migrations/` in order and run the database tests
before enabling a build. The development project completed this gate on October 22, 2026.

Required iOS build settings:

- `TENORA_SUPABASE_URL`: the HTTPS project URL.
- `TENORA_SUPABASE_PUBLISHABLE_KEY`: the project's publishable/anon client key.
- Never place a Supabase `service_role` or other server secret in the app.

Required Apple/Supabase setup:

1. In Apple Developer, enable Sign in with Apple for the existing App ID
   `com.tenora.app` and regenerate the provisioning profile.
2. In Supabase Auth providers, enable Apple and register `com.tenora.app` as an allowed
   native client ID. Follow the current Supabase Apple-provider instructions for any
   server-side credential fields shown by that environment.
3. Native ID-token sign-in does not add an iOS redirect URL or custom callback handler.
   Web OAuth or email-link support, if added later, needs separately reviewed redirect
   URLs and associated-domain handling.
4. Build with the checked-in Sign in with Apple entitlement and confirm the capability is
   present in the signed archive.

The app validates that configuration is nonempty and HTTPS before showing sign-in.
Missing values safely disable account sign-in.

## Backend identity and authorization

The additive migration creates only:

- `tenora_users`: stable provider-independent adult IDs;
- `user_identities`: trusted Supabase Auth subject mappings;
- `account_profiles`: minimal optional account metadata.

RLS is enabled on all three tables. Anonymous access is revoked. Authenticated clients
receive read access only to their own rows and may update only their own display name.
Creation goes through a security-definer trigger in an unexposed `private` schema. It
accepts no client input, is not executable by app roles, and never authorizes from
user-editable metadata. The client can only read its own mapping through RLS.

No household, child, task, habit, calendar, or sync table is introduced by this phase.

## Failure and recovery behavior

- Network unavailable: local use continues; retry account actions later.
- Session expired: sign in again; no local data changes.
- Session revoked or account removed: sign in again or continue locally.
- Apple sheet canceled: no error banner and no state change.
- Interrupted profile association: finish or remove the pending association explicitly.
- Account belongs to another local profile: content remains privacy-locked until the
  protected switch and app reopen complete.
- Provider outage: no local mutation is queued for network transmission.

## Disconnect and deletion preparation

There is no destructive "disconnect profile" or "delete cloud account" action in this
phase. Removing an interrupted `pending` association is safe because it never moved or
copied data. A future completed-association disconnect must require confirmation and must
remove only the mapping; it must not delete the local SwiftData store, settings, habits,
history, legacy game data, widgets, or outbox. If private sync exists by then, disconnect
must first explain unsent and cloud-only data and provide export/recovery choices.

Future account deletion should require recent authentication, offer a cloud export where
applicable, revoke sessions, and run as an audited server operation. It should remove the
auth identity and private cloud account profile according to the published retention
policy while leaving device-local productivity data unless the user separately confirms a
local reset. Future household memberships must reference `tenora_users.id`, not the auth
provider subject; deletion will therefore need explicit ownership transfer, leave, or
household-deletion rules before the user row can be removed.

## Rollback

Removing the two Supabase build values returns the client to local-only mode without
touching local records or associations. The database migration is additive; do not drop
identity rows as an application rollback. Disable the client gate, preserve data, and
investigate before writing a compensating migration.

## Deferred lifecycle work

Cloud account deletion/export, verified email-link sign-in, multi-device private sync,
households, invitations, child profiles, and collaboration remain later phases. Before
production cloud collection is enabled, update the privacy policy, App Store privacy
answers, retention/deletion procedure, monitoring, backup drills, and support runbooks.
