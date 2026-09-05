import SwiftData
import SwiftUI

@main
struct TenoraApp: App {
    @UIApplicationDelegateAdaptor(TenoraAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @StateObject private var taskStore: TaskStore
    @StateObject private var calendarStore: CalendarStore

    init() {
        do {
            let container = try ModelContainer(for: StoredTask.self)
            modelContainer = container
            let repository = SwiftDataTaskRepository(modelContext: container.mainContext)
            let store = TaskStore(repository: repository)
            store.didChange = { tasks in await ReminderService.shared.synchronize(tasks: tasks) }
            ReminderService.shared.handleAction = { [weak store] id, action in
                await store?.notificationAction(id: id, action: action) ?? false
            }
            _taskStore = StateObject(wrappedValue: store)
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
