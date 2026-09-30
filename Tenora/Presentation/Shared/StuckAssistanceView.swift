import SwiftUI

enum StuckReason: String, CaseIterable, Identifiable {
    case unsureWhereToStart
    case feelsTooBig
    case doNotWantTo
    case distracted
    case tooTired
    case waitingOnSomeone
    case unsureWhatMatters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unsureWhereToStart: "I don't know where to start"
        case .feelsTooBig: "It feels too big"
        case .doNotWantTo: "I don't want to do it"
        case .distracted: "I got distracted"
        case .tooTired: "I'm too tired"
        case .waitingOnSomeone: "I need something from someone"
        case .unsureWhatMatters: "I'm not sure what matters"
        }
    }

    var icon: String {
        switch self {
        case .unsureWhereToStart: "signpost.right"
        case .feelsTooBig: "square.3.layers.3d"
        case .doNotWantTo: "hand.raised"
        case .distracted: "arrow.uturn.backward"
        case .tooTired: "battery.25percent"
        case .waitingOnSomeone: "person.crop.circle.badge.clock"
        case .unsureWhatMatters: "scope"
        }
    }
}

struct StuckAssistanceView: View {
    let task: TenoraTask
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: StuckReason?
    @State private var nextStep: String
    @State private var busy = false
    @State private var showingHold = false
    @State private var showingReturn = false
    @State private var showingJustStart = false

    init(task: TenoraTask) {
        self.task = task
        _nextStep = State(initialValue: task.nextStep ?? "")
    }

    private var currentTask: TenoraTask {
        store.tasks.first(where: { $0.id == task.id }) ?? task
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let selectedReason {
                        assistance(for: selectedReason)
                    } else {
                        reasonPicker
                    }

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(TenoraScreenBackground())
            .navigationTitle("I'm stuck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedReason == nil ? "Close" : "Back") {
                        if selectedReason == nil { dismiss() }
                        else { selectedReason = nil }
                    }
                    .disabled(busy)
                }
            }
            .sheet(isPresented: $showingHold, onDismiss: {
                if currentTask.heldAt != task.heldAt { dismiss() }
            }) { HoldPlaceView(task: currentTask) }
            .sheet(isPresented: $showingReturn, onDismiss: {
                if currentTask.returnTrigger != task.returnTrigger { dismiss() }
            }) { ReturnTriggerView(task: currentTask) }
            .sheet(isPresented: $showingJustStart, onDismiss: { dismiss() }) {
                JustStartView(task: currentTask)
            }
            .interactiveDismissDisabled(busy)
        }
    }

    private var reasonPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's stopping you?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Pick the closest answer. You only need one next move.")
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(StuckReason.allCases) { reason in
                    Button {
                        selectedReason = reason
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: reason.icon)
                                .font(.title3)
                                .foregroundStyle(Color.tenoraCopper)
                                .frame(width: 28)
                            Text(reason.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tenoraCard(cornerRadius: 16)
                }
            }
        }
    }

    @ViewBuilder
    private func assistance(for reason: StuckReason) -> some View {
        switch reason {
        case .unsureWhereToStart:
            nextStepHelp(
                title: "Let's find the first visible action.",
                message: "Choose something physical and specific—open the file, find the number, or put one item away.",
                placeholder: "The first small thing I can do",
                minutes: 3
            )
        case .feelsTooBig:
            nextStepHelp(
                title: "You don't have to do the whole task.",
                message: "Shrink it until the next action feels almost too small to count.",
                placeholder: "A much smaller next step",
                minutes: 3
            )
        case .doNotWantTo:
            nextStepHelp(
                title: "You don't have to feel motivated first.",
                message: "Try five minutes with permission to stop, or let Tenora bring you something else.",
                placeholder: "What could you tolerate for five minutes?",
                minutes: 5,
                offersAnotherTask: true
            )
        case .distracted:
            reorientationHelp
        case .tooTired:
            lowEnergyHelp
        case .waitingOnSomeone:
            waitingHelp
        case .unsureWhatMatters:
            priorityHelp
        }
    }

    private func nextStepHelp(
        title: String,
        message: String,
        placeholder: String,
        minutes: Int,
        offersAnotherTask: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            responseHeader(title, message: message, icon: "figure.step.training")
            taskContext(currentTask)
            TextField(placeholder, text: $nextStep, axis: .vertical)
                .lineLimit(2...4)
                .padding(16)
                .background(Color.tenoraCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.tenoraSage.opacity(0.4))
                }
                .accessibilityIdentifier("stuck-next-step")

            Button("Start with \(minutes) minutes") { beginShortStart(minutes: minutes) }
                .buttonStyle(TenoraPrimaryButtonStyle())
                .disabled(busy || cleanNextStep.isEmpty)

            Button("Save this next step") { saveNextStep() }
                .buttonStyle(TenoraSecondaryButtonStyle())
                .disabled(busy || cleanNextStep.isEmpty)

            if offersAnotherTask {
                Button("Show me something else") { chooseSomethingElse() }
                    .disabled(busy)
            }
        }
    }

    private var reorientationHelp: some View {
        VStack(alignment: .leading, spacing: 18) {
            responseHeader("Here is the thread again.", message: "No cleanup or replanning required. Just return to the next visible step.", icon: "arrow.uturn.backward")
            taskContext(currentTask)
            if let step = currentTask.nextStep, !step.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NEXT STEP").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Color.tenoraCopper)
                    Text(step).font(.title3.weight(.semibold))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tenoraCard()
            }
            Button("Return to this") { resumeTask() }
                .buttonStyle(TenoraPrimaryButtonStyle())
                .disabled(busy)
            Button("Hold my place instead") { showingHold = true }
                .buttonStyle(TenoraSecondaryButtonStyle())
                .disabled(busy)
        }
    }

    private var lowEnergyHelp: some View {
        VStack(alignment: .leading, spacing: 18) {
            responseHeader("Let's lower the demand.", message: "A tiny start counts. Resting with a clear return path also counts.", icon: "battery.25percent")
            taskContext(currentTask)
            TextField("One low-energy next step", text: $nextStep, axis: .vertical)
                .lineLimit(2...4)
                .padding(16)
                .background(Color.tenoraCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("stuck-next-step")
            Button("Try 3 minutes") { beginShortStart(minutes: 3) }
                .buttonStyle(TenoraPrimaryButtonStyle())
                .disabled(busy || cleanNextStep.isEmpty)
            Button("Hold this for later") { holdForLowEnergy() }
                .buttonStyle(TenoraSecondaryButtonStyle())
                .disabled(busy)
            Button("Show me something else") { chooseSomethingElse() }
                .disabled(busy)
        }
    }

    private var waitingHelp: some View {
        VStack(alignment: .leading, spacing: 18) {
            responseHeader("You don't need to keep carrying this.", message: "Choose what should make the task relevant again, and Tenora will hold it until then.", icon: "person.crop.circle.badge.clock")
            taskContext(currentTask)
            Button("Choose when this should return") { showingReturn = true }
                .buttonStyle(TenoraPrimaryButtonStyle())
            Button("Keep it in front today") { keepInFront() }
                .buttonStyle(TenoraSecondaryButtonStyle())
                .disabled(busy)
        }
    }

    @ViewBuilder
    private var priorityHelp: some View {
        let recommendation = store.recommendation(
            availableMinutes: calendarStore.availability?.availableMinutes,
            capacityMode: currentCapacityMode
        )
        VStack(alignment: .leading, spacing: 18) {
            responseHeader("Let Tenora narrow it down.", message: "You do not need to compare your whole list.", icon: "scope")
            if let recommendation {
                taskContext(recommendation)
                Text(store.reason(
                    for: recommendation,
                    availableMinutes: calendarStore.availability?.availableMinutes,
                    capacityMode: currentCapacityMode
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Start this") { start(recommendation) }
                    .buttonStyle(TenoraPrimaryButtonStyle())
                    .disabled(busy)
            } else {
                Text("Nothing needs you in this moment. Your calendar or working hours may be protecting this time.")
                    .foregroundStyle(.secondary)
                Button("Keep this task in front today") { keepInFront() }
                    .buttonStyle(TenoraSecondaryButtonStyle())
                    .disabled(busy)
            }
        }
    }

    private func responseHeader(_ title: String, message: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.tenoraCopper)
            Text(title)
                .font(.system(.title, design: .rounded, weight: .bold))
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func taskContext(_ task: TenoraTask) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("YOU WERE WORKING ON").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Color.tenoraCopper)
            Text(task.title).font(.headline)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tenoraCard()
    }

    private var cleanNextStep: String {
        nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentCapacityMode: TaskCapacityMode {
        let defaults = UserDefaults.standard
        return AttentionPreferences.capacityMode(
            rawValue: defaults.string(forKey: AttentionPreferences.capacityModeKey) ?? TaskCapacityMode.balanced.rawValue,
            selectedAt: defaults.double(forKey: AttentionPreferences.capacitySelectedAtKey),
            now: calendarStore.currentDate
        )
    }

    private func beginShortStart(minutes: Int) {
        busy = true
        Task {
            if await store.beginJustStart(currentTask.id, nextStep: cleanNextStep, durationSeconds: minutes * 60) {
                showingJustStart = true
            }
            busy = false
        }
    }

    private func saveNextStep() {
        busy = true
        Task {
            var draft = currentTask
            draft.nextStep = cleanNextStep
            if await store.update(draft) { dismiss() }
            busy = false
        }
    }

    private func resumeTask() {
        start(currentTask)
    }

    private func start(_ task: TenoraTask) {
        busy = true
        Task {
            if await store.start(task) { dismiss() }
            busy = false
        }
    }

    private func chooseSomethingElse() {
        busy = true
        Task {
            await store.postpone(currentTask)
            if store.errorMessage == nil { dismiss() }
            busy = false
        }
    }

    private func holdForLowEnergy() {
        busy = true
        Task {
            if await store.hold(currentTask.id, nextStep: cleanNextStep, reason: "Low energy", returnAt: nil) {
                dismiss()
            }
            busy = false
        }
    }

    private func keepInFront() {
        busy = true
        Task {
            if await store.setKeepInFrontToday(true, for: currentTask.id) { dismiss() }
            busy = false
        }
    }
}
