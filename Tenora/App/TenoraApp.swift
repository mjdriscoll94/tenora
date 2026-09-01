import SwiftData
import SwiftUI

@main
struct TenoraApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var taskStore: TaskStore

    init() {
        do {
            let container = try ModelContainer(for: StoredTask.self)
            modelContainer = container
            let repository = SwiftDataTaskRepository(modelContext: container.mainContext)
            _taskStore = StateObject(wrappedValue: TaskStore(repository: repository))
        } catch {
            fatalError("Unable to initialize Tenora's local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(taskStore)
        }
        .modelContainer(modelContainer)
    }
}

