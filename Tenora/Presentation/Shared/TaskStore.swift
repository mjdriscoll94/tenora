import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TenoraTask] = []
    @Published private(set) var errorMessage: String?

    private let repository: any TaskRepository

    init(repository: any TaskRepository) {
        self.repository = repository
    }

    var inboxTasks: [TenoraTask] {
        tasks.filter { $0.status == .inbox }
    }

    func load() async {
        do {
            tasks = try await repository.fetchTasks()
            errorMessage = nil
        } catch {
            errorMessage = "Tenora couldn't load your tasks."
        }
    }

    func createTask(title: String, notes: String = "") async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }

        do {
            try await repository.save(TenoraTask(title: cleanTitle, notes: notes))
            tasks = try await repository.fetchTasks()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Tenora couldn't save that task."
            return false
        }
    }

    func complete(_ task: TenoraTask) async {
        var completedTask = task
        completedTask.complete()
        do {
            try await repository.save(completedTask)
            tasks = try await repository.fetchTasks()
            errorMessage = nil
        } catch {
            errorMessage = "Tenora couldn't complete that task."
        }
    }
}

