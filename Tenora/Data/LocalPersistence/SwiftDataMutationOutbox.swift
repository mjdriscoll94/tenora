import Foundation
import SwiftData

/// The production Phase 4 journal. `stage` participates in the caller's SwiftData save,
/// keeping content, metadata, and its mutation envelope crash-consistent.
@MainActor
final class SwiftDataMutationOutbox: MutationOutbox {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func stage(_ mutation: LocalMutation) throws {
        let id = mutation.id
        let descriptor = FetchDescriptor<StoredLocalMutation>(predicate: #Predicate { $0.id == id })
        guard try modelContext.fetch(descriptor).isEmpty else { return }
        modelContext.insert(StoredLocalMutation(mutation: mutation))
    }

    func enqueue(_ mutation: LocalMutation) throws {
        try stage(mutation)
        try modelContext.save()
    }

    func pending(profileID: LocalProfileID) throws -> [LocalMutation] {
        let profile = profileID.rawValue
        let descriptor = FetchDescriptor<StoredLocalMutation>(
            predicate: #Predicate { $0.profileIDValue == profile },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).compactMap(\.domainModel)
    }

    func recordAttempt(
        ids: Set<UUID>,
        profileID: LocalProfileID,
        attemptedAt: Date,
        outcome: LocalMutationAttemptOutcome
    ) throws {
        let profile = profileID.rawValue
        let records = try modelContext.fetch(FetchDescriptor<StoredLocalMutation>(
            predicate: #Predicate { $0.profileIDValue == profile }
        ))
        for record in records where ids.contains(record.id) {
            record.attemptCount += 1
            record.lastAttemptAt = attemptedAt
            switch outcome {
            case .retryable(let code):
                record.stateValue = LocalMutation.State.retryScheduled.rawValue
                record.nextAttemptAt = MutationRetryPolicy.nextAttemptDate(
                    attemptCount: record.attemptCount,
                    attemptedAt: attemptedAt
                )
                record.lastFailureCode = code
            case .blocked(let code):
                record.stateValue = LocalMutation.State.blocked.rawValue
                record.nextAttemptAt = nil
                record.lastFailureCode = code
            }
        }
        try modelContext.save()
    }

    func remove(ids: Set<UUID>, profileID: LocalProfileID) throws {
        let profile = profileID.rawValue
        let records = try modelContext.fetch(FetchDescriptor<StoredLocalMutation>(
            predicate: #Predicate { $0.profileIDValue == profile }
        ))
        for record in records where ids.contains(record.id) { modelContext.delete(record) }
        try modelContext.save()
    }

    func removeAll(profileID: LocalProfileID) throws {
        let profile = profileID.rawValue
        let records = try modelContext.fetch(FetchDescriptor<StoredLocalMutation>(
            predicate: #Predicate { $0.profileIDValue == profile }
        ))
        records.forEach(modelContext.delete)
        try modelContext.save()
    }
}
