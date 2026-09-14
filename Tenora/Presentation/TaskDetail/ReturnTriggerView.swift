import SwiftUI

struct ReturnTriggerView: View {
    let task: TenoraTask
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let trigger = taskStore.tasks.first(where: { $0.id == task.id })?.returnTrigger ?? task.returnTrigger {
                    Section("Current return") {
                        Label(trigger.summary, systemImage: "arrow.uturn.forward.circle")
                        Button("Clear return condition", role: .destructive) { apply(nil) }
                    }
                }
                Section("After another task") {
                    ForEach(otherTasks) { other in
                        Button(other.title) { apply(.taskCompleted(taskID: other.id, title: other.title)) }
                    }
                    if otherTasks.isEmpty { Text("No other open tasks").foregroundStyle(.secondary) }
                }
                Section("After a calendar event") {
                    ForEach(calendarStore.upcomingEvents.filter { !$0.isAllDay }) { event in
                        Button {
                            apply(.calendarEventEnded(eventID: event.externalIdentifier, title: event.title, endDate: event.endDate))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(event.title)
                                Text("Ends \(event.endDate.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if calendarStore.authorization != .fullAccess {
                        Text("Connect Calendar to use event-based returns.").foregroundStyle(.secondary)
                    }
                }
                Section("When time opens up") {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button("At least \(minutes) minutes") {
                            apply(.freeWindow(minimumMinutes: minutes, candidateDate: nil))
                        }
                    }
                    Text("Tenora checks your working hours and busy calendar events.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bring Back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var otherTasks: [TenoraTask] {
        taskStore.tasks.filter { $0.id != task.id && ![.completed, .archived].contains($0.status) }
    }

    private func apply(_ trigger: ReturnTrigger?) {
        Task {
            if await taskStore.setReturnTrigger(trigger, for: task.id, availability: calendarStore.availability) { dismiss() }
        }
    }
}
