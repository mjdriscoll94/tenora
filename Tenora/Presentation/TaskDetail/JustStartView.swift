import SwiftUI

struct JustStartView: View {
    let task: TenoraTask
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var nextStep: String
    @State private var durationMinutes = 3
    @State private var saving = false
    @FocusState private var editingStep: Bool

    init(task: TenoraTask) {
        self.task = task
        _nextStep = State(initialValue: task.nextStep ?? "")
    }

    private var current: TenoraTask {
        store.tasks.first(where: { $0.id == task.id }) ?? task
    }

    var body: some View {
        NavigationStack {
            Group {
                if let end = current.justStartEndsAt {
                    session(end: end)
                } else {
                    setup
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.tenoraSurface.ignoresSafeArea())
            .navigationTitle("Just Start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
        }
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(current.title).font(.title.bold())
                Text("For a few minutes, just:").font(.headline).foregroundStyle(.secondary)
                TextField("Smallest next step", text: $nextStep, axis: .vertical)
                    .focused($editingStep)
                    .font(.title3)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("just-start-next-step")
                Text("Choose one physical action, such as opening the document or finding the phone number.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Short session", selection: $durationMinutes) {
                    Text("3 min").tag(3)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                }.pickerStyle(.segmented).accessibilityIdentifier("just-start-duration")
                Button("Start \(durationMinutes) minutes") {
                    saving = true
                    Task {
                        _ = await store.beginJustStart(current.id, nextStep: nextStep, durationSeconds: durationMinutes * 60)
                        saving = false
                    }
                }
                .buttonStyle(TenoraPrimaryButtonStyle())
                .disabled(saving || nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Stopping when the timer ends still counts. There is no penalty for doing only this much.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let error = store.errorMessage { Text(error).foregroundStyle(.secondary) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { editingStep = nextStep.isEmpty }
    }

    private func session(end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(end.timeIntervalSince(context.date))))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(seconds == 0 ? "That was enough to count." : "For now, just:")
                        .font(.title.bold())
                    Text(current.nextStep ?? current.title).font(.title2)
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel(seconds == 0 ? "Session complete" : "\(seconds) seconds remaining")
                        .accessibilityIdentifier("just-start-countdown")
                    if seconds == 0 {
                        Text("Want to keep the momentum, or stop here for now?").foregroundStyle(.secondary)
                    }
                    Button(seconds == 0 ? "Keep going" : "Keep working without the timer") { finish(keepGoing: true) }
                        .buttonStyle(TenoraPrimaryButtonStyle()).disabled(saving)
                    Button("I'm done for now") { finish(keepGoing: false) }
                        .buttonStyle(.bordered).disabled(saving)
                    Button("Complete task") {
                        saving = true
                        Task { if await store.complete(current) { dismiss() }; saving = false }
                    }.buttonStyle(.bordered).disabled(saving)
                    if let error = store.errorMessage { Text(error).foregroundStyle(.secondary) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func finish(keepGoing: Bool) {
        saving = true
        Task {
            if await store.finishJustStart(current.id, keepGoing: keepGoing) { dismiss() }
            saving = false
        }
    }
}
