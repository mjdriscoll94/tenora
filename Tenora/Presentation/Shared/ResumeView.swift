import SwiftUI

struct ResumeView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    var since: Date? = nil
    var onResume: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Where were we?").font(.largeTitle.bold())
                    if let task = store.resumeTask {
                        Text("You left off here").font(.subheadline).foregroundStyle(.secondary)
                        Text(task.title).font(.title2.bold())
                        if let step = task.nextStep, !step.isEmpty {
                            Text("Next step").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(step).font(.title3)
                        } else {
                            NavigationLink("Choose a smallest next step") { TaskDetailView(task: task) }
                        }
                        if let reason = task.holdReason, !reason.isEmpty,
                           let held = task.heldAt, held >= (task.lastWorkedAt ?? .distantPast) {
                            Text("You paused because: \(reason)").foregroundStyle(.secondary)
                        }
                        Button("Resume") {
                            saving = true
                            Task {
                                if await store.start(task) { onResume(); dismiss() }
                                saving = false
                            }
                        }.buttonStyle(TenoraPrimaryButtonStyle()).disabled(saving)
                        if let since {
                            let relevant = store.inboxTasks.filter { item in
                                [item.dueDate, item.scheduledDate, item.nextSurfaceAt].compactMap { $0 }
                                    .contains { $0 > since && $0 <= Date() }
                            }.count
                            if relevant > 0 { Text("\(relevant) unfinished items reached a deadline or return time while you were away.").font(.subheadline) }
                        }
                        if let error = store.errorMessage { Text(error) }
                    } else {
                        Text("Your place is clear. Choose your next step in Today.")
                    }
                    Button("Show me today") { onResume(); dismiss() }.buttonStyle(.bordered)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.tenoraSurface)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
        }
    }
}
