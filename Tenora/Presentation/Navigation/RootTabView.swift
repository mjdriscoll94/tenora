import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @State private var isAddingTask = false

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
        .task {
            await taskStore.load()
        }
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isAddingTask = true
            } label: {
                Label("Add task", systemImage: "plus")
            }
        }
    }
}

