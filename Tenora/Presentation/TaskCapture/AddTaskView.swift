import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
    @State private var title = ""
    @State private var notes = ""
    @State private var estimatedDurationMinutes: Int?
    @FocusState private var isTitleFocused: Bool
    @State private var saving = false

    init(initialTitle: String = "") { _title = State(initialValue: initialTitle) }

    var body: some View {
        NavigationStack {
            Form {
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
                if let error = taskStore.errorMessage { Section { Text(error) } }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tenoraSurface)
            .tint(.tenoraBlue)
            .navigationTitle("Add Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isTitleFocused = true }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            if await taskStore.createTask(
                title: title,
                notes: notes,
                estimatedDurationMinutes: estimatedDurationMinutes
            ) {
                dismiss()
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
