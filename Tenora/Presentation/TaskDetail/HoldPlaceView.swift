import SwiftUI

struct HoldPlaceView: View {
    let task: TenoraTask
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var nextStep: String
    @State private var reason = ""
    @State private var chooseReturn = false
    @State private var returnAt = Date().addingTimeInterval(3600)
    @State private var saving = false

    init(task: TenoraTask) {
        self.task = task
        _nextStep = State(initialValue: task.nextStep ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(task.title).font(.headline)
                    TextField("Next step when you return", text: $nextStep, axis: .vertical)
                    Text("Leave yourself one small, concrete action.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Optional") {
                    TextField("Why are you stopping?", text: $reason)
                    Toggle("Choose a return time", isOn: $chooseReturn)
                    if chooseReturn { DatePicker("Bring back", selection: $returnAt, in: Date()...) }
                    else { Text("Tenora will bring this back later. You can resume anytime.").font(.footnote) }
                }
                if let error = store.errorMessage { Text(error) }
            }
            .navigationTitle("Hold my place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hold") {
                        saving = true
                        Task {
                            if await store.hold(task.id, nextStep: nextStep, reason: reason, returnAt: chooseReturn ? returnAt : nil) { dismiss() }
                            saving = false
                        }
                    }.disabled(saving)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }
}
