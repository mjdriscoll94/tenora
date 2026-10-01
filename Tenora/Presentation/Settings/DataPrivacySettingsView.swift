import SwiftUI
import UniformTypeIdentifiers

struct DataPrivacySettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var transitionStore: TransitionStore
    @State private var showingExporter = false
    @State private var exportDocument = TenoraExportDocument(data: Data())
    @State private var showingDeleteConfirmation = false
    @State private var deleting = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Tasks", value: "\(store.tasks.count)")
                LabeledContent("Location", value: "On this device")
            } header: {
                Text("Storage")
            } footer: {
                Text("Tasks, working hours, attention preferences, and calendar-derived availability remain local to this device. Calendar events are read from Apple Calendar and are not copied into Tenora's task database.")
            }

            Section {
                Button("Export Tenora data") { prepareExport() }
            } header: {
                Text("Export")
            } footer: {
                Text("Creates a JSON file containing your tasks, transition plans, and saved preference values. Calendar events are not exported.")
            }

            Section {
                Button("Delete all Tenora data", role: .destructive) { showingDeleteConfirmation = true }
                    .disabled(deleting)
            } header: {
                Text("Delete")
            } footer: {
                Text("This removes tasks, transition plans, reminder reservations, and Tenora preferences from this device. It does not change calendar or notification permissions in iOS Settings.")
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
