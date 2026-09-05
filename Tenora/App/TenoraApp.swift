import SwiftData
import SwiftUI

@main
struct TenoraApp: App {
    @UIApplicationDelegateAdaptor(TenoraAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @StateObject private var taskStore: TaskStore
    @StateObject private var calendarStore: CalendarStore

    init() {
        let runtime = AppRuntime.shared
        modelContainer = runtime.container
        _taskStore = StateObject(wrappedValue: runtime.tasks)
        _calendarStore = StateObject(wrappedValue: runtime.calendar)
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
