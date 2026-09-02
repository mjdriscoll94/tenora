import SwiftData
import SwiftUI

@main
struct TenoraApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var taskStore: TaskStore
    @StateObject private var calendarStore: CalendarStore

    init() {
        do {
            let container = try ModelContainer(for: StoredTask.self)
            modelContainer = container
            let repository = SwiftDataTaskRepository(modelContext: container.mainContext)
            _taskStore = StateObject(wrappedValue: TaskStore(repository: repository))
            let calendarRepository = EventKitCalendarRepository()
            _calendarStore = StateObject(wrappedValue: CalendarStore(repository: calendarRepository))
        } catch {
            fatalError("Unable to initialize Tenora's local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(taskStore)
                .environmentObject(calendarStore)
        }
        .modelContainer(modelContainer)
    }
}
