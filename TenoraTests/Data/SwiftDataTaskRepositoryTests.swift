import SwiftData
import XCTest
@testable import Tenora

@MainActor
final class SwiftDataTaskRepositoryTests: XCTestCase {
    private func makeRepository() throws -> SwiftDataTaskRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StoredTask.self,
            configurations: configuration
        )
        return SwiftDataTaskRepository(modelContext: container.mainContext)
    }

    func testSaveAndFetchTask() async throws {
        let repository = try makeRepository()
        let task = TenoraTask(title: "Call insurance", notes: "Ask about coverage")

        try await repository.save(task)
        let fetched = try await repository.fetchTasks()

        XCTAssertEqual(fetched, [task])
    }

    func testSavingExistingTaskUpdatesInsteadOfDuplicating() async throws {
        let repository = try makeRepository()
        var task = TenoraTask(title: "Draft email")
        try await repository.save(task)

        task.complete(at: Date(timeIntervalSince1970: 1_700_000_000))
        try await repository.save(task)
        let fetched = try await repository.fetchTasks()

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.status, .completed)
        XCTAssertNotNil(fetched.first?.completedAt)
    }

    func testDeleteRemovesTask() async throws {
        let repository = try makeRepository()
        let task = TenoraTask(title: "Temporary task")
        try await repository.save(task)

        try await repository.delete(id: task.id)

        let fetched = try await repository.fetchTasks()
        XCTAssertTrue(fetched.isEmpty)
    }
}
