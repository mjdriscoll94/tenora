import SwiftData
import SwiftUI

@main
struct TenoraApp: App {
    @UIApplicationDelegateAdaptor(TenoraAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @StateObject private var taskStore: TaskStore
    @StateObject private var calendarStore: CalendarStore
    @StateObject private var transitionStore: TransitionStore

    init() {
        let runtime = AppRuntime.shared
        modelContainer = runtime.container
        _taskStore = StateObject(wrappedValue: runtime.tasks)
        _calendarStore = StateObject(wrappedValue: runtime.calendar)
        _transitionStore = StateObject(wrappedValue: runtime.transitions)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(taskStore)
                .environmentObject(calendarStore)
                .environmentObject(transitionStore)
        }
        .modelContainer(modelContainer)
    }
}
