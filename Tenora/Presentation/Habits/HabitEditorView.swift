import SwiftUI

struct HabitPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let difficulty: HabitDifficulty
}

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: HabitStore
    @State private var draft: Habit
    @State private var reminderEnabled: Bool
    @State private var saving = false
    @FocusState private var nameFocused: Bool

    private let presets: [HabitPreset] = [
        .init(name: "Drink Water", icon: "drop.fill", difficulty: .easy),
        .init(name: "Exercise", icon: "figure.run", difficulty: .challenging),
        .init(name: "Read", icon: "book.fill", difficulty: .standard),
        .init(name: "Medication", icon: "pills.fill", difficulty: .easy),
        .init(name: "Prayer", icon: "hands.sparkles.fill", difficulty: .standard),
        .init(name: "Bible Reading", icon: "book.closed.fill", difficulty: .standard),
        .init(name: "Stretch", icon: "figure.flexibility", difficulty: .easy),
        .init(name: "Walk", icon: "figure.walk", difficulty: .standard),
        .init(name: "Journal", icon: "pencil.and.scribble", difficulty: .standard),
        .init(name: "Practice", icon: "music.note", difficulty: .standard),
        .init(name: "Sleep Routine", icon: "moon.stars.fill", difficulty: .standard)
    ]

    private let icons = ["sparkles", "drop.fill", "figure.run", "book.fill", "pills.fill", "hands.sparkles.fill", "book.closed.fill", "figure.flexibility", "figure.walk", "pencil.and.scribble", "music.note", "moon.stars.fill", "leaf.fill", "heart.fill", "sun.max.fill"]

    init(habit: Habit? = nil) {
        let value = habit ?? Habit(name: "")
        _draft = State(initialValue: value)
        _reminderEnabled = State(initialValue: value.reminderMinute != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick start") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(presets) { preset in
                                Button { apply(preset) } label: {
                                    Label(preset.name, systemImage: preset.icon)
                                        .font(.subheadline.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 38)
                                        .background(Color.tenoraSage.opacity(0.18), in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }.padding(.vertical, 3)
                    }
                }

                Section("Habit") {
                    TextField("Habit name", text: $draft.name).focused($nameFocused)
                    TextField("Optional notes", text: $draft.details, axis: .vertical).lineLimit(2...5)
                    Picker("Icon", selection: $draft.iconName) {
                        ForEach(icons, id: \.self) { Label($0.replacingOccurrences(of: ".fill", with: "").capitalized, systemImage: $0).tag($0) }
                    }
                    Picker("Color", selection: $draft.colorIdentifier) {
                        ForEach(HabitTint.choices, id: \.id) { choice in
                            Label(choice.name, systemImage: "circle.fill").foregroundStyle(choice.color).tag(choice.id)
                        }
                    }
                }

                Section {
                    Picker("Frequency", selection: $draft.schedule.type) {
                        ForEach(HabitScheduleType.allCases) { Text($0.title).tag($0) }
                    }
                    scheduleControls
                } header: { Text("Schedule") }
                  footer: { Text("Choose a rhythm that makes the habit easy to find without requiring a perfect week.") }

                Section {
                    Picker("Difficulty", selection: $draft.difficulty) {
                        ForEach(HabitDifficulty.allCases) { difficulty in
                            Text("\(difficulty.title) · \(HabitGameEngine().xpAward(for: difficulty)) XP").tag(difficulty)
                        }
                    }
                } header: { Text("Quest reward") }
                  footer: { Text("Difficulty only changes XP. It is not a judgment about the habit or your effort.") }

                Section {
                    Toggle("Remind me", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: reminderBinding, displayedComponents: .hourAndMinute)
                    }
                } header: { Text("Reminder") }
                  footer: { Text("Reminders are optional and use Tenora's existing notification permission.") }

                if let error = store.errorMessage { Section { Text(error).foregroundStyle(.secondary) } }
            }
            .scrollContentBackground(.hidden).background(TenoraScreenBackground()).tint(.tenoraForest)
            .navigationTitle(draft.name.isEmpty ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(saving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { if draft.name.isEmpty { nameFocused = true } }
            .onChange(of: reminderEnabled) { _, enabled in
                if enabled {
                    if draft.reminderMinute == nil { draft.reminderMinute = 9 * 60 }
                    Task { await ReminderService.shared.requestAccess() }
                } else { draft.reminderMinute = nil }
            }
        }
    }

    @ViewBuilder
    private var scheduleControls: some View {
        switch draft.schedule.type {
        case .everyDay:
            EmptyView()
        case .specificWeekdays:
            VStack(alignment: .leading, spacing: 10) {
                Text("Days").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                        let weekday = index + 1
                        Button {
                            if draft.schedule.weekdays.contains(weekday) { draft.schedule.weekdays.remove(weekday) }
                            else { draft.schedule.weekdays.insert(weekday) }
                        } label: {
                            Text(symbol).font(.caption.weight(.bold)).frame(width: 34, height: 34)
                                .background(draft.schedule.weekdays.contains(weekday) ? Color.tenoraForest : Color.tenoraSage.opacity(0.14), in: Circle())
                                .foregroundStyle(draft.schedule.weekdays.contains(weekday) ? .white : .primary)
                        }.buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[index])
                    }
                }
            }
        case .timesPerWeek:
            Stepper("\(draft.schedule.weeklyTarget) times each week", value: $draft.schedule.weeklyTarget, in: 1...7)
        case .custom:
            Stepper("Every \(draft.schedule.intervalDays) days", value: $draft.schedule.intervalDays, in: 2...30)
        }
    }

    private var reminderBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = draft.reminderMinute ?? 9 * 60
                return Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: minutes / 60, minute: minutes % 60)) ?? Date()
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                draft.reminderMinute = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func apply(_ preset: HabitPreset) {
        draft.name = preset.name
        draft.iconName = preset.icon
        draft.difficulty = preset.difficulty
    }

    private func save() {
        guard !saving else { return }
        saving = true
        if !reminderEnabled { draft.reminderMinute = nil }
        Task {
            if await store.save(draft) { dismiss() }
            saving = false
        }
    }
}
