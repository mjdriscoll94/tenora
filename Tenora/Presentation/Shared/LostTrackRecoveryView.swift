import SwiftUI

struct LostTrackRecoveryView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    var since: Date? = nil
    var availableMinutes: Int? = nil
    var capacityMode: TaskCapacityMode = .balanced
    var onRecover: () -> Void = {}

    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    recoveryHeader

                    if let task = store.recoveryTask {
                        thread(task)
                    } else if let task = store.recommendation(
                        availableMinutes: availableMinutes,
                        capacityMode: capacityMode
                    ) {
                        freshStart(task)
                    } else {
                        clearState
                    }

                    if let since {
                        absenceContext(since: since)
                    }

                    Button("Show me today") { finish() }
                        .buttonStyle(TenoraSecondaryButtonStyle())

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(TenoraScreenBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(saving)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private var recoveryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.tenoraCopper)
            Text(since == nil ? "Let's find your place." : "Welcome back.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("You don't need to reconstruct everything. Tenora will give you one clear thread.")
                .foregroundStyle(.secondary)
        }
    }

    private func thread(_ task: TenoraTask) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("YOU WERE DOING")
                Text(task.title)
                    .font(.title2.weight(.bold))

                if let step = task.nextStep, !step.isEmpty {
                    Divider().padding(.vertical, 2)
                    sectionLabel("YOU STOPPED AT")
                    Text(step).font(.title3.weight(.medium))
                }

                if let reason = task.holdReason, !reason.isEmpty,
                   let heldAt = task.heldAt,
                   heldAt >= (task.lastWorkedAt ?? .distantPast) {
                    Label("You paused because: \(reason)", systemImage: "pause.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tenoraCard()

            Button("Resume") { recover(task) }
                .buttonStyle(TenoraPrimaryButtonStyle())
                .disabled(saving)
        }
    }

    private func freshStart(_ task: TenoraTask) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("There isn't an earlier thread to recover. Here's one place to begin now.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("START HERE")
                Text(task.title).font(.title2.weight(.bold))
                if let step = task.nextStep, !step.isEmpty {
                    Text("Next: \(step)").foregroundStyle(.secondary)
                }
                Text(store.reason(for: task, availableMinutes: availableMinutes, capacityMode: capacityMode))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tenoraCard()

            Button("Start here") { recover(task) }
                .buttonStyle(TenoraPrimaryButtonStyle())
                .disabled(saving)
        }
    }

    private var clearState: some View {
        ContentUnavailableView(
            "Your place is clear",
            systemImage: "checkmark.circle",
            description: Text("There is no unfinished thread that needs reconstructing right now.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func absenceContext(since: Date) -> some View {
        let count = store.relevantItemCount(since: since)
        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("WHILE YOU WERE AWAY")
            Text(count == 0
                 ? "Nothing new reached a deadline or return time."
                 : "\(count) unfinished \(count == 1 ? "item reached" : "items reached") a deadline or return time. You can review \(count == 1 ? "it" : "them") later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tenoraSage.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(Color.tenoraCopper)
    }

    private func recover(_ task: TenoraTask) {
        saving = true
        Task {
            if await store.start(task) { finish() }
            saving = false
        }
    }

    private func finish() {
        onRecover()
        dismiss()
    }
}
