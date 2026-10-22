import Foundation
import SwiftData

@MainActor
final class PersonalSyncMetadataStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Inventories existing content as private, local-only data. This method is idempotent
    /// and deliberately does not associate a cloud user or enqueue an upload.
    func backfill(profileID: LocalProfileID, now: Date = Date()) throws -> PersonalSyncInventoryReport {
        let existing = try modelContext.fetch(FetchDescriptor<StoredSyncMetadata>())
        var existingKeys = Set(existing.map(\.key))
        var report = PersonalSyncInventoryReport()

        func add(_ entity: SyncEntity, id: String, updatedAt: Date) {
            let key = StoredSyncMetadata.key(entity: entity, recordID: id)
            guard !existingKeys.contains(key) else {
                report.metadataAlreadyPresentCount += 1
                return
            }
            modelContext.insert(StoredSyncMetadata(
                entity: entity,
                recordID: id,
                localOwnerProfileID: profileID,
                updatedAt: updatedAt
            ))
            existingKeys.insert(key)
            report.metadataCreatedCount += 1
        }

        let tasks = try modelContext.fetch(FetchDescriptor<StoredTask>())
        report.taskCount = tasks.count
        tasks.forEach { add(.task, id: $0.id.uuidString, updatedAt: $0.createdAt) }

        let habits = try modelContext.fetch(FetchDescriptor<StoredHabit>())
        report.habitCount = habits.count
        habits.forEach { add(.habit, id: $0.id.uuidString, updatedAt: $0.createdAt) }

        let completions = try modelContext.fetch(FetchDescriptor<StoredHabitCompletion>())
        report.habitCompletionCount = completions.count
        completions.forEach { add(.habitCompletion, id: $0.id.uuidString, updatedAt: $0.createdAt) }

        let progress = try modelContext.fetch(FetchDescriptor<StoredPlayerProgress>())
        report.playerProgressCount = progress.count
        progress.forEach { add(.playerProgress, id: $0.recordID, updatedAt: now) }

        let unlocks = try modelContext.fetch(FetchDescriptor<StoredGameUnlock>())
        report.gameUnlockCount = unlocks.count
        unlocks.forEach { add(.gameUnlock, id: $0.id, updatedAt: $0.unlockedAt) }

        if report.metadataCreatedCount > 0 {
            try modelContext.save()
        }
        return report
    }

    func allMetadata() throws -> [PersonalSyncMetadata] {
        try modelContext.fetch(FetchDescriptor<StoredSyncMetadata>())
            .compactMap(\.domainModel)
    }

    func removeAll() throws {
        for metadata in try modelContext.fetch(FetchDescriptor<StoredSyncMetadata>()) {
            modelContext.delete(metadata)
        }
        try modelContext.save()
    }

    func recordLocalUpsert(
        entity: SyncEntity,
        recordID: String,
        profileID: LocalProfileID,
        updatedAt: Date = Date()
    ) throws {
        let key = StoredSyncMetadata.key(entity: entity, recordID: recordID)
        let descriptor = FetchDescriptor<StoredSyncMetadata>(predicate: #Predicate { $0.key == key })
        if let metadata = try modelContext.fetch(descriptor).first {
            metadata.updatedAt = updatedAt
            metadata.deletedAt = nil
            metadata.stateValue = SyncRecordState.localOnly.rawValue
        } else {
            modelContext.insert(StoredSyncMetadata(
                entity: entity,
                recordID: recordID,
                localOwnerProfileID: profileID,
                updatedAt: updatedAt
            ))
        }
    }

    func recordLocalDeletion(
        entity: SyncEntity,
        recordID: String,
        profileID: LocalProfileID,
        deletedAt: Date = Date()
    ) throws {
        try recordLocalUpsert(
            entity: entity,
            recordID: recordID,
            profileID: profileID,
            updatedAt: deletedAt
        )
        let key = StoredSyncMetadata.key(entity: entity, recordID: recordID)
        let descriptor = FetchDescriptor<StoredSyncMetadata>(predicate: #Predicate { $0.key == key })
        guard let metadata = try modelContext.fetch(descriptor).first else { return }
        metadata.deletedAt = deletedAt
    }
}
