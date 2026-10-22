import Foundation
import SwiftData

@MainActor
final class SwiftDataHabitRepository: HabitRepository, HabitCompletionRepository, HabitProgressRepository {
    private let modelContext: ModelContext
    private let profileID: LocalProfileID
    private let outbox: MutationOutbox?
    private let syncMetadata: PersonalSyncMetadataStore

    init(modelContext: ModelContext, profileID: LocalProfileID = .offline, outbox: MutationOutbox? = nil) {
        self.modelContext = modelContext
        self.profileID = profileID
        self.outbox = outbox
        syncMetadata = PersonalSyncMetadataStore(modelContext: modelContext)
    }

    func fetchHabits() throws -> [Habit] {
        try modelContext.fetch(FetchDescriptor<StoredHabit>(sortBy: [SortDescriptor(\.createdAt)])).map(\.domainModel)
    }

    func saveHabit(_ habit: Habit) throws {
        let id = habit.id
        let descriptor = FetchDescriptor<StoredHabit>(predicate: #Predicate { $0.id == id })
        if let stored = try modelContext.fetch(descriptor).first { stored.update(from: habit) }
        else { modelContext.insert(StoredHabit(habit: habit)) }
        try syncMetadata.recordLocalUpsert(entity: .habit, recordID: id.uuidString, profileID: profileID)
        try modelContext.save()
        try enqueue(.habit, id: id.uuidString, operation: .upsert, value: habit)
    }

    func deleteHabit(id: UUID) throws {
        let descriptor = FetchDescriptor<StoredHabit>(predicate: #Predicate { $0.id == id })
        for item in try modelContext.fetch(descriptor) { modelContext.delete(item) }
        try syncMetadata.recordLocalDeletion(entity: .habit, recordID: id.uuidString, profileID: profileID)
        try modelContext.save()
        try enqueue(.habit, id: id.uuidString, operation: .delete, value: Optional<Habit>.none)
    }

    func deleteAllHabits() throws {
        for item in try modelContext.fetch(FetchDescriptor<StoredHabit>()) { modelContext.delete(item) }
        try modelContext.save()
    }

    func fetchHabitCompletions() throws -> [HabitCompletion] {
        try modelContext.fetch(FetchDescriptor<StoredHabitCompletion>(sortBy: [SortDescriptor(\.completionDate)])).map(\.domainModel)
    }

    func saveHabitCompletion(_ completion: HabitCompletion) throws {
        let id = completion.id
        let descriptor = FetchDescriptor<StoredHabitCompletion>(predicate: #Predicate { $0.id == id })
        if try modelContext.fetch(descriptor).isEmpty {
            modelContext.insert(StoredHabitCompletion(completion: completion))
            try syncMetadata.recordLocalUpsert(
                entity: .habitCompletion,
                recordID: id.uuidString,
                profileID: profileID
            )
            try modelContext.save()
            try enqueue(.habitCompletion, id: id.uuidString, operation: .upsert, value: completion)
        }
    }

    func deleteHabitCompletion(id: UUID) throws {
        let descriptor = FetchDescriptor<StoredHabitCompletion>(predicate: #Predicate { $0.id == id })
        for item in try modelContext.fetch(descriptor) { modelContext.delete(item) }
        try syncMetadata.recordLocalDeletion(
            entity: .habitCompletion,
            recordID: id.uuidString,
            profileID: profileID
        )
        try modelContext.save()
        try enqueue(.habitCompletion, id: id.uuidString, operation: .delete, value: Optional<HabitCompletion>.none)
    }

    func deleteHabitCompletions(habitID: UUID) throws {
        let descriptor = FetchDescriptor<StoredHabitCompletion>(predicate: #Predicate { $0.habitID == habitID })
        let matches = try modelContext.fetch(descriptor)
        for item in matches {
            let id = item.id
            modelContext.delete(item)
            try syncMetadata.recordLocalDeletion(
                entity: .habitCompletion,
                recordID: id.uuidString,
                profileID: profileID
            )
            try enqueue(.habitCompletion, id: id.uuidString, operation: .delete, value: Optional<HabitCompletion>.none)
        }
        try modelContext.save()
    }

    func deleteAllHabitCompletions() throws {
        for item in try modelContext.fetch(FetchDescriptor<StoredHabitCompletion>()) { modelContext.delete(item) }
        try modelContext.save()
    }

    func fetchPlayerProgress() throws -> PlayerProgress? {
        guard let stored = try modelContext.fetch(FetchDescriptor<StoredPlayerProgress>()).first else { return nil }
        return PlayerProgress(
            totalXP: stored.totalXP,
            level: stored.level,
            xpIntoLevel: stored.xpIntoLevel,
            xpForNextLevel: stored.xpForNextLevel,
            totalCompletions: stored.totalCompletions,
            currentMomentum: stored.currentMomentum,
            longestMomentum: stored.longestMomentum,
            perfectDays: stored.perfectDays
        )
    }

    func savePlayerProgress(_ progress: PlayerProgress) throws {
        if let stored = try modelContext.fetch(FetchDescriptor<StoredPlayerProgress>()).first {
            stored.update(from: progress)
        } else {
            modelContext.insert(StoredPlayerProgress(progress: progress))
        }
        try syncMetadata.recordLocalUpsert(
            entity: .playerProgress,
            recordID: "local-player",
            profileID: profileID
        )
        try modelContext.save()
    }

    func deleteAllHabitProgress() throws {
        for item in try modelContext.fetch(FetchDescriptor<StoredPlayerProgress>()) { modelContext.delete(item) }
        for item in try modelContext.fetch(FetchDescriptor<StoredGameUnlock>()) { modelContext.delete(item) }
        try modelContext.save()
    }

    private func enqueue<Value: Encodable>(
        _ entity: LocalMutation.Entity,
        id: String,
        operation: LocalMutation.Operation,
        value: Value?
    ) throws {
        guard let outbox else { return }
        let payload = try value.map { try JSONEncoder().encode($0) }
        try outbox.enqueue(LocalMutation(
            profileID: profileID,
            entity: entity,
            recordID: id,
            operation: operation,
            payload: payload
        ))
    }
}
