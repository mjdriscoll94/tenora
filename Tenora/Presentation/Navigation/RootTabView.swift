import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("workStart") private var workStart = 8
    @AppStorage("workEnd") private var workEnd = 18
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @State private var isAddingTask = false
    @ObservedObject private var reminders = ReminderService.shared
    @State private var openedTask: TenoraTask?
    @State private var captureTitle = ""
    @State private var selectedTab = 0
    @State private var missingTask = false
    @AppStorage("lastLeftTenora") private var lastLeft = 0.0
    @State private var showingResume = false
    @State private var returnSince: Date?

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
            AddTaskView(initialTitle: captureTitle, onResume: { selectedTab = 0 })
        }
        .tint(.tenoraBlue)
        .sheet(isPresented: $showingResume) { ResumeView(since: returnSince, onResume: { selectedTab = 0 }) }
        .onOpenURL { url in
            guard let route = TenoraRoute(url: url) else { return }
            showingResume = false
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
            guard let id else { return }
            showingResume = false
            Task {
                await taskStore.load()
                openedTask = taskStore.tasks.first { $0.id == id }
                reminders.openedTaskID = nil
            }
        }
        .onChange(of: workStart) { _, _ in Task { await calendarStore.refresh() } }
        .onChange(of: workEnd) { _, _ in Task { await calendarStore.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lastLeft = Date().timeIntervalSince1970 }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await taskStore.load()
            if lastLeft > 0, Date().timeIntervalSince1970 - lastLeft >= 15 * 60,
               taskStore.resumeTask != nil, !isAddingTask, openedTask == nil, reminders.openedTaskID == nil {
                returnSince = Date(timeIntervalSince1970: lastLeft)
                showingResume = true
            }
            lastLeft = 0
            repeat {
                await taskStore.load()
                await calendarStore.refresh()
                await reminders.drainActions()
                if let id = reminders.openedTaskID { openedTask = taskStore.tasks.first { $0.id == id }; reminders.openedTaskID = nil }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            } while !Task.isCancelled
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
