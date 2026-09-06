import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
    @State private var title = ""
    @State private var notes = ""
    @State private var estimatedDurationMinutes: Int?
    @FocusState private var isTitleFocused: Bool
    @State private var saving = false
    @State private var capturedReturnID: UUID?
    @State private var captured = false
    var onResume: () -> Void = {}

    init(initialTitle: String = "", onResume: @escaping () -> Void = {}) {
        _title = State(initialValue: initialTitle)
        self.onResume = onResume
    }

    var body: some View {
        NavigationStack {
            Form {
                if captured {
                    Section {
                        Text("Captured.").font(.title.bold())
                        if let task = taskStore.tasks.first(where: { $0.id == capturedReturnID && ![.completed, .archived].contains($0.status) }) {
                            Text("Back to: \(task.title)").font(.headline)
                            if let step = task.nextStep, !step.isEmpty { Text("Next: \(step)") }
                            Button("Resume") {
                                saving = true
                                Task {
                                    if await taskStore.start(task) { onResume(); dismiss() }
                                    saving = false
                                }
                            }.disabled(saving)
                        }
                        Button("Close") { dismiss() }.disabled(saving)
                    }
                } else {
                Section {
                    TextField("What do you need to remember?", text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }

                Section("Optional") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)

                    Picker("Duration", selection: $estimatedDurationMinutes) {
                        Text("None").tag(Int?.none)
                        ForEach([5, 15, 30, 45, 60, 120], id: \.self) { minutes in
                            Text(durationLabel(for: minutes)).tag(Optional(minutes))
                        }
                    }
                }
                }
                if let error = taskStore.errorMessage { Section { Text(error) } }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tenoraSurface)
            .tint(.tenoraBlue)
            .navigationTitle(captured ? "Your place is held" : "Hold this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !captured { Button("Cancel") { dismiss() }.disabled(saving) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !captured { Button("Add", action: save)
                        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { isTitleFocused = true }
            .interactiveDismissDisabled(saving)
        }
    }

    private func save() {
        guard !saving, !captured else { return }
        saving = true
        capturedReturnID = taskStore.currentTask?.id
        Task {
            if await taskStore.createTask(
                title: title,
                notes: notes,
                estimatedDurationMinutes: estimatedDurationMinutes
            ) {
                if capturedReturnID != nil { isTitleFocused = false; captured = true }
                else { dismiss() }
            }
            saving = false
        }
    }

    private func durationLabel(for minutes: Int) -> String {
        switch minutes {
        case 60: return "1 hour"
        case 120: return "2 hours"
        default: return "\(minutes) min"
        }
    }
}
