import SwiftUI
import UniformTypeIdentifiers

struct DataPrivacySettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var transitionStore: TransitionStore
    @EnvironmentObject private var habitStore: HabitStore
    @State private var showingExporter = false
    @State private var exportDocument = TenoraExportDocument(data: Data())
    @State private var showingDeleteConfirmation = false
    @State private var deleting = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Tasks", value: "\(store.tasks.count)")
                LabeledContent("Habits", value: "\(habitStore.habits.count)")
                LabeledContent("Habit completions", value: "\(habitStore.completions.count)")
                LabeledContent("Location", value: "On this device")
            } header: {
                Text("Storage")
            } footer: {
                Text("Tasks, habits, progress, working hours, attention preferences, and calendar-derived availability remain local to this device. Calendar events are read from Apple Calendar and are not copied into Tenora's database.")
            }

            Section {
                Button("Export Tenora data") { prepareExport() }
            } header: {
                Text("Export")
            } footer: {
                Text("Creates a JSON file containing your tasks, habits, habit completions, progression, transition plans, and saved preference values. Calendar events are not exported.")
            }

            Section {
                Button("Delete all Tenora data", role: .destructive) { showingDeleteConfirmation = true }
                    .disabled(deleting)
            } header: {
                Text("Delete")
            } footer: {
                Text("This removes tasks, habits, progress, transition plans, reminder reservations, and Tenora preferences from this device. It does not change calendar or notification permissions in iOS Settings.")
            }

            if let statusMessage {
                Section { Text(statusMessage).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle("Data & Privacy")
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Tenora Export"
        ) { result in
            if case .failure = result { statusMessage = "The export was not saved." }
        }
        .confirmationDialog(
            "Delete all Tenora data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all data", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Export first if you want a copy.")
        }
    }

    private func prepareExport() {
        let payload = TenoraExportPayload(
            exportedAt: Date(),
            tasks: store.tasks,
            habits: habitStore.habits,
            habitCompletions: habitStore.completions,
            playerProgress: habitStore.progress,
            achievementIDs: habitStore.achievementIDs.sorted(),
            rewardIDs: habitStore.rewardIDs.sorted(),
            transitionPlans: transitionStore.plans,
            workingSchedule: AttentionPreferences.schedule,
            reminderLevel: AttentionPreferences.reminderLevel.rawValue,
            reminderStartMinute: AttentionPreferences.reminderStartMinute,
            reminderEndMinute: AttentionPreferences.reminderEndMinute,
            recoveryDelay: AttentionPreferences.recoveryDelay.rawValue
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else {
            statusMessage = "Tenora couldn't prepare the export."
            return
        }
        exportDocument = TenoraExportDocument(data: data)
        showingExporter = true
    }

    private func deleteAllData() {
        deleting = true
        Task {
            guard await store.deleteAll() else {
                deleting = false
                statusMessage = store.errorMessage
                return
            }
            guard await habitStore.deleteAll() else {
                deleting = false
                statusMessage = habitStore.errorMessage
                return
            }
            await transitionStore.removeAll()
            await ReminderService.shared.removeAllTenoraNotifications()
            AttentionPreferences.resetLocalPreferences()
            statusMessage = "All local Tenora data was deleted."
            deleting = false
        }
    }
}

private struct TenoraExportPayload: Codable {
    let exportedAt: Date
    let tasks: [TenoraTask]
    let habits: [Habit]
    let habitCompletions: [HabitCompletion]
    let playerProgress: PlayerProgress
    let achievementIDs: [String]
    let rewardIDs: [String]
    let transitionPlans: [TransitionPlan]
    let workingSchedule: WorkingSchedule
    let reminderLevel: String
    let reminderStartMinute: Int
    let reminderEndMinute: Int
    let recoveryDelay: String
}

private struct TenoraExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
