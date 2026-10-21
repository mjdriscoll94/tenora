import Foundation

@MainActor
protocol MutationOutbox: AnyObject {
    func enqueue(_ mutation: LocalMutation) throws
    func pending(profileID: LocalProfileID) throws -> [LocalMutation]
    func remove(ids: Set<UUID>, profileID: LocalProfileID) throws
    func removeAll(profileID: LocalProfileID) throws
}
