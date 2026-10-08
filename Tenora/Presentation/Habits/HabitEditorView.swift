import SwiftUI

struct HabitPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
}

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: HabitStore
    @State private var draft: Habit
    @State private var reminderEnabled: Bool
    @State private var saving = false
    @State private var showingIconPicker = false
    @FocusState private var nameFocused: Bool

    private let presets: [HabitPreset] = [
        .init(name: "Drink Water", icon: "habit_icon_water"),
        .init(name: "Exercise", icon: "habit_icon_exercise"),
        .init(name: "Read", icon: "habit_icon_book"),
        .init(name: "Medication", icon: "habit_icon_medication"),
        .init(name: "Prayer", icon: "habit_icon_prayer"),
        .init(name: "Bible Reading", icon: "habit_icon_bible"),
        .init(name: "Stretch", icon: "habit_icon_stretch"),
        .init(name: "Walk", icon: "habit_icon_walk"),
        .init(name: "Journal", icon: "habit_icon_journal"),
        .init(name: "Dishes", icon: "habit_icon_dishes"),
        .init(name: "Laundry", icon: "habit_icon_laundry"),
        .init(name: "Practice Instrument", icon: "habit_icon_music"),
        .init(name: "Sleep Routine", icon: "habit_icon_sleep")
    ]

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
                                    HStack(spacing: 7) {
                                        HabitArtworkView(iconName: preset.icon, size: 32)
                                        Text(preset.name)
                                    }
                                        .font(.subheadline.weight(.medium)).padding(.horizontal, 10).frame(minHeight: 42)
                                        .background(Color.tenoraSage.opacity(0.18), in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }.padding(.vertical, 3)
                    }
                }

                Section("Habit") {
                    TextField("Habit name", text: $draft.name).focused($nameFocused)
                    TextField("Optional notes", text: $draft.details, axis: .vertical).lineLimit(2...5)
                    Button { showingIconPicker = true } label: {
                        HStack {
                            Text("Icon").foregroundStyle(.primary)
                            Spacer()
                            Text(HabitIconCatalog.title(for: draft.iconName)).foregroundStyle(.secondary)
                            HabitArtworkView(iconName: draft.iconName, size: 42, tint: HabitTint.color(for: draft.colorIdentifier))
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
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
                  footer: { Text("Choose a rhythm that reflects real life. You can change it whenever your schedule changes.") }

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
            .sheet(isPresented: $showingIconPicker) { iconPicker }
        }
    }

    private var iconPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(HabitIconCatalog.all) { option in
                        Button {
                            draft.iconName = option.id
                            showingIconPicker = false
                        } label: {
                            VStack(spacing: 7) {
                                HabitArtworkView(iconName: option.id, size: 72)
                                Text(option.title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(option.category).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(draft.iconName == option.id ? Color.tenoraSage.opacity(0.30) : Color.tenoraCard, in: RoundedRectangle(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).stroke(draft.iconName == option.id ? Color.tenoraForest : Color.tenoraSage.opacity(0.20), lineWidth: draft.iconName == option.id ? 2 : 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.title), \(option.category)")
                        .accessibilityAddTraits(draft.iconName == option.id ? .isSelected : [])
                    }
                }
                .padding()
            }
            .background(TenoraScreenBackground())
            .navigationTitle("Choose an Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingIconPicker = false } } }
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
                    ForEach(weekdayChoices, id: \.weekday) { choice in
                        Button {
                            if draft.schedule.weekdays.contains(choice.weekday) { draft.schedule.weekdays.remove(choice.weekday) }
                            else { draft.schedule.weekdays.insert(choice.weekday) }
                        } label: {
                            Text(choice.symbol).font(.caption.weight(.bold)).frame(width: 34, height: 34)
                                .background(draft.schedule.weekdays.contains(choice.weekday) ? Color.tenoraForest : Color.tenoraSage.opacity(0.14), in: Circle())
                                .foregroundStyle(draft.schedule.weekdays.contains(choice.weekday) ? .white : .primary)
                        }.buttonStyle(.plain).accessibilityLabel(choice.name)
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

    private var weekdayChoices: [(weekday: Int, symbol: String, name: String)] {
        let calendar = Calendar.current
        return (0..<calendar.weekdaySymbols.count).map { offset in
            let weekday = (offset + calendar.firstWeekday - 1) % calendar.weekdaySymbols.count + 1
            return (weekday, calendar.veryShortWeekdaySymbols[weekday - 1], calendar.weekdaySymbols[weekday - 1])
        }
    }

    private func apply(_ preset: HabitPreset) {
        draft.name = preset.name
        draft.iconName = preset.icon
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
