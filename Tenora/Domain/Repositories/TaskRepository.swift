import Foundation

@MainActor
protocol TaskRepository {
    func fetchTasks() async throws -> [TenoraTask]
    func save(_ task: TenoraTask) async throws
    func delete(id: UUID) async throws
}

