import Foundation
import SwiftData

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
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

    func fetchTasks() async throws -> [TenoraTask] {
        let descriptor = FetchDescriptor<StoredTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func save(_ task: TenoraTask) async throws {
        let taskID = task.id
        let descriptor = FetchDescriptor<StoredTask>(
            predicate: #Predicate { $0.id == taskID }
        )

        if let storedTask = try modelContext.fetch(descriptor).first {
            storedTask.update(from: task)
        } else {
            modelContext.insert(StoredTask(task: task))
        }
        try syncMetadata.recordLocalUpsert(
            entity: .task,
            recordID: task.id.uuidString,
            profileID: profileID
        )
        try outbox?.stage(LocalMutation(
            profileID: profileID,
            entity: .task,
            recordID: task.id.uuidString,
            operation: .upsert,
            payload: try JSONEncoder().encode(task)
        ))
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        let taskID = id
        let descriptor = FetchDescriptor<StoredTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        if let storedTask = try modelContext.fetch(descriptor).first {
            modelContext.delete(storedTask)
            try syncMetadata.recordLocalDeletion(
                entity: .task,
                recordID: id.uuidString,
                profileID: profileID
            )
            try outbox?.stage(LocalMutation(
                profileID: profileID,
                entity: .task,
                recordID: id.uuidString,
                operation: .delete
            ))
            try modelContext.save()
        }
    }

    func deleteAll() async throws {
        let storedTasks = try modelContext.fetch(FetchDescriptor<StoredTask>())
        for task in storedTasks { modelContext.delete(task) }
        try modelContext.save()
    }
}
