import Foundation
import SwiftData

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        let taskID = id
        let descriptor = FetchDescriptor<StoredTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        if let storedTask = try modelContext.fetch(descriptor).first {
            modelContext.delete(storedTask)
            try modelContext.save()
        }
    }
}

