import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TenoraTask
    @State private var saving = false
    @State private var confirmingDelete = false
    @State private var holding = false
    @State private var justStarting = false
    @State private var choosingReturn = false

    init(task: TenoraTask) { _draft = State(initialValue: task) }

    var body: some View {
        Form {
            Section("What needs your attention?") {
                TextField("Title", text: $draft.title, axis: .vertical)
                TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
            }
            Section("Timing") {
                optionalDate("Schedule", date: $draft.scheduledDate)
                optionalDate("Due", date: $draft.dueDate)
                optionalDate("Bring back", date: $draft.nextSurfaceAt)
                Picker("Duration", selection: $draft.estimatedDurationMinutes) {
                    Text("No estimate").tag(Int?.none)
                    ForEach([5, 15, 30, 45, 60, 120], id: \.self) { Text("\($0) min").tag(Optional($0)) }
                }
                Picker("Priority", selection: $draft.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button(draft.returnTrigger == nil ? "Bring back contextually" : draft.returnTrigger!.summary) {
                    choosingReturn = true
                }
            }
            Section("Make this easier") {
                TextField("Smallest next step", text: Binding(get: { draft.nextStep ?? "" }, set: { draft.nextStep = $0 }), axis: .vertical)
                Text("What's the smallest physical thing you could do next?").font(.footnote).foregroundStyle(.secondary)
            }
            if let error = store.errorMessage { Section { Text(error).foregroundStyle(.secondary) } }
            Section {
                Button(draft.justStartEndsAt == nil ? "Just Start" : "Continue short start") {
                    saving = true
                    Task {
                        if await store.update(draft) { justStarting = true }
                        saving = false
                    }
                }.disabled(saving || draft.status == .completed)
                Button("Hold my place") {
                    saving = true
                    Task {
                        if await store.update(draft) { holding = true }
                        saving = false
                    }
                }.disabled(saving || draft.status == .completed)
                Button("Resume task") { Task { if await store.start(draft) { dismiss() } } }
                    .disabled(saving || draft.status == .completed)
                Button("Complete task") {
                    Task { if await store.complete(draft) { dismiss() } }
                }.disabled(saving || draft.status == .completed)
                Button("Delete task", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle("Task")
        .sheet(isPresented: $holding, onDismiss: {
            if let latest = store.tasks.first(where: { $0.id == draft.id }) { draft = latest }
        }) { HoldPlaceView(task: draft) }
        .sheet(isPresented: $justStarting, onDismiss: {
            if let latest = store.tasks.first(where: { $0.id == draft.id }) { draft = latest }
        }) { JustStartView(task: draft) }
        .sheet(isPresented: $choosingReturn, onDismiss: {
            if let latest = store.tasks.first(where: { $0.id == draft.id }) { draft = latest }
        }) { ReturnTriggerView(task: draft) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saving = true
                    Task {
                        if await store.update(draft) { dismiss() }
                        saving = false
                    }
                }.disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .confirmationDialog("Delete this task? This cannot be undone.", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                Task { if await store.delete(draft.id) { dismiss() } }
            }
        }
    }

    private func optionalDate(_ title: String, date: Binding<Date?>) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(get: { date.wrappedValue != nil }, set: { date.wrappedValue = $0 ? Date() : nil }))
            if date.wrappedValue != nil {
                DatePicker(title, selection: Binding(get: { date.wrappedValue ?? Date() }, set: { date.wrappedValue = $0 }))
            }
        }
    }
}
