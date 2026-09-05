import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @State private var isAddingTask = false
    @ObservedObject private var reminders = ReminderService.shared
    @State private var openedTask: TenoraTask?
    @State private var captureTitle = ""
    @State private var selectedTab = 0
    @State private var missingTask = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                InboxView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .tag(1)

            NavigationStack {
                CalendarView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(2)
        }
        .sheet(isPresented: $isAddingTask) {
            AddTaskView(initialTitle: captureTitle)
        }
        .tint(.tenoraBlue)
        .onOpenURL { url in
            guard let route = TenoraRoute(url: url) else { return }
            Task {
                await taskStore.load()
                switch route {
                case .capture(let title):
                    openedTask = nil
                    captureTitle = title
                    isAddingTask = true
                case .task(let id):
                    isAddingTask = false
                    openedTask = taskStore.tasks.first { $0.id == id }
                    missingTask = openedTask == nil
                case .today: selectedTab = 0
                }
            }
        }
        .alert("This task is no longer available", isPresented: $missingTask) { Button("OK", role: .cancel) {} }
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
                captureTitle = ""
                isAddingTask = true
            } label: {
                Label("Add task", systemImage: "plus")
            }
        }
    }
}
