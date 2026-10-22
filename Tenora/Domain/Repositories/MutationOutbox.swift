import Foundation

@MainActor
protocol MutationOutbox: AnyObject {
    func enqueue(_ mutation: LocalMutation) throws
    /// Stages a mutation for a surrounding local transaction when supported.
    func stage(_ mutation: LocalMutation) throws
    func pending(profileID: LocalProfileID) throws -> [LocalMutation]
    func ready(profileID: LocalProfileID, now: Date, limit: Int) throws -> [LocalMutation]
    func recordAttempt(
        ids: Set<UUID>,
        profileID: LocalProfileID,
        attemptedAt: Date,
        outcome: LocalMutationAttemptOutcome
    ) throws
    func remove(ids: Set<UUID>, profileID: LocalProfileID) throws
    func removeAll(profileID: LocalProfileID) throws
}

extension MutationOutbox {
    func stage(_ mutation: LocalMutation) throws { try enqueue(mutation) }

    func ready(profileID: LocalProfileID, now: Date, limit: Int) throws -> [LocalMutation] {
        Array(try pending(profileID: profileID).filter {
            $0.state != .blocked && ($0.nextAttemptAt == nil || $0.nextAttemptAt! <= now)
        }.prefix(max(0, limit)))
    }
}
