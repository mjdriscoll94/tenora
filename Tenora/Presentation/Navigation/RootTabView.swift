import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @State private var isAddingTask = false
    @ObservedObject private var reminders = ReminderService.shared
    @State private var openedTask: TenoraTask?

    var body: some View {
        TabView {
            NavigationStack {
                TodayView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }

            NavigationStack {
                InboxView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Inbox", systemImage: "tray") }

            NavigationStack {
                CalendarView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
        }
        .sheet(isPresented: $isAddingTask) {
            AddTaskView()
        }
        .tint(.tenoraBlue)
        .sheet(item: $openedTask) { task in NavigationStack { TaskDetailView(task: task) } }
        .onChange(of: reminders.openedTaskID) { _, id in
            Task {
                await taskStore.load()
                openedTask = taskStore.tasks.first { $0.id == id }
                reminders.openedTaskID = nil
            }
        }
        .task {
            await taskStore.load()
            await calendarStore.refresh()
            await reminders.drainActions()
            if let id = reminders.openedTaskID { openedTask = taskStore.tasks.first { $0.id == id }; reminders.openedTaskID = nil }
        }
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isAddingTask = true
            } label: {
                Label("Add task", systemImage: "plus")
            }
        }
    }
}
