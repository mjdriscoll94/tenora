import SwiftUI

struct ReviewView: View {
    let kind: ReviewKind
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [UUID] = []
    @State private var started = false
    @State private var busy = false
    @State private var showSchedule = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var confirmDelete = false

    private var current: TenoraTask? {
        ids.compactMap { id in store.tasks.first { $0.id == id && ![.completed, .archived].contains($0.status) } }.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !started {
                        Text(kind == .morning ? "What matters most today?" : "Let's make room for tomorrow.")
                            .font(.largeTitle.bold())
                        if kind == .morning {
                            if calendarStore.authorization == .fullAccess {
                                Text("\(calendarStore.upcomingEvents.count) calendar events ahead.")
                            }
                            Text("Choose a few things to keep in front of you. Everything else can wait.")
                        } else {
                            Text("Give each unfinished task a next step. You can stop whenever you need to.")
                        }
                        Button("Begin") { ids = store.reviewTasks.map(\.id); started = true }
                            .buttonStyle(TenoraPrimaryButtonStyle())
                    } else if let task = current {
                        Text(task.title).font(.title.bold())
                        if !task.notes.isEmpty { Text(task.notes).foregroundStyle(.secondary) }
                        if let date = task.dueDate {
                            Text("Due \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            if kind == .morning {
                                decision("Make room today", .today, task.id)
                            }
                            decision("Tomorrow", .tomorrow, task.id)
                            Button("Schedule") { showSchedule = true }.buttonStyle(.bordered)
                            decision("Keep reminding me", .keep, task.id)
                            decision("Done", .complete, task.id)
                            Button("Delete", role: .destructive) { confirmDelete = true }.buttonStyle(.bordered)
                        }.disabled(busy)
                        if let error = store.errorMessage { Text(error).foregroundStyle(.secondary) }
                    } else {
                        Text("Your place is held.").font(.largeTitle.bold())
                        Text("Your decisions are saved. You can return whenever you need to.")
                        Button("Finish") { dismiss() }.buttonStyle(TenoraPrimaryButtonStyle())
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.tenoraSurface)
            .navigationTitle(kind == .morning ? "Morning review" : "Evening reset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showSchedule) {
                NavigationStack {
                    Form {
                        DatePicker("When", selection: $scheduleDate, in: Date()...)
                        if let error = store.errorMessage { Text(error) }
                    }.navigationTitle("Schedule")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showSchedule = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                guard let task = current else { return }
                                busy = true
                                Task {
                                    if await store.review(task.id, decision: .schedule(scheduleDate)) {
                                        ids.removeAll { $0 == task.id }
                                        showSchedule = false
                                    }
                                    busy = false
                                }
                            }.disabled(busy)
                        }
                    }
                }.presentationDetents([.medium])
            }
            .confirmationDialog("Delete this task? This cannot be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let task = current else { return }
                    busy = true
                    Task {
                        if await store.delete(task.id) { ids.removeAll { $0 == task.id } }
                        busy = false
                    }
                }
            }
        }
    }

    private func decision(_ title: String, _ decision: ReviewDecision, _ id: UUID) -> some View {
        Button(title) {
            busy = true
            Task {
                if await store.review(id, decision: decision) { ids.removeAll { $0 == id } }
                busy = false
            }
        }.buttonStyle(.bordered).frame(minHeight: 44)
    }
}
