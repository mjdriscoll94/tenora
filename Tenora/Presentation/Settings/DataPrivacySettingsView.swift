import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataPrivacySettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var transitionStore: TransitionStore
    @EnvironmentObject private var habitStore: HabitStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.modelContext) private var modelContext
    @State private var showingExporter = false
    @State private var exportDocument = TenoraExportDocument(data: Data())
    @State private var showingImporter = false
    @State private var pendingRestore: TenoraBackupPayload?
    @State private var showingRestoreConfirmation = false
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
                Text("Tasks, habits, check-in history, working hours, attention preferences, and calendar-derived availability remain local to this device. Calendar events are read from Apple Calendar and are not copied into Tenora's database.")
            }

            Section {
                Button("Export Tenora backup") { prepareExport() }
                Button("Restore Tenora backup") { showingImporter = true }
            } header: {
                Text("Backup & Restore")
            } footer: {
                Text("Backups include tasks, habits, check-ins, transition plans, saved settings, and preserved game progress. Restoring validates the file and saves a local recovery copy first. Calendar events and sign-in tokens are never included.")
            }

            Section {
                Button("Delete all Tenora data", role: .destructive) { showingDeleteConfirmation = true }
                    .disabled(deleting)
            } header: {
                Text("Delete")
            } footer: {
                Text("This removes tasks, habits, check-in history, transition plans, reminder reservations, and Tenora preferences from this device. It does not change calendar or notification permissions in iOS Settings.")
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
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmationDialog(
            "Replace current Tenora data with this backup?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore backup", role: .destructive) { restorePendingBackup() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Tenora will first preserve a recovery copy of the current data. Calendar events and account tokens are not changed.")
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
        do {
            let data = try TenoraDataArchive.make(context: modelContext, transitionPlans: transitionStore.plans)
            exportDocument = TenoraExportDocument(data: data)
            showingExporter = true
        } catch {
            statusMessage = "Tenora couldn't prepare the export."
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            pendingRestore = try TenoraDataArchive.decode(Data(contentsOf: url))
            showingRestoreConfirmation = true
            statusMessage = nil
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? "Tenora couldn't read that backup."
        }
    }

    private func restorePendingBackup() {
        guard let payload = pendingRestore else { return }
        pendingRestore = nil
        deleting = true
        Task {
            do {
                let current = try TenoraDataArchive.make(context: modelContext, transitionPlans: transitionStore.plans)
                try TenoraDataArchive.savePreRestoreCopy(current)
                try TenoraDataArchive.restore(
                    payload,
                    context: modelContext,
                    profileID: AppRuntime.shared.profileID
                )
                settings.repository.refreshFromLegacyStore()
                settings.reload()
                await transitionStore.replaceAll(payload.transitionPlans)
                await store.load()
                await habitStore.load()
                store.restoreFocusedTaskID(payload.preferences.focusedTaskID)
                statusMessage = "Your Tenora backup was restored."
            } catch {
                statusMessage = (error as? LocalizedError)?.errorDescription ?? "Tenora couldn't restore that backup."
            }
            deleting = false
        }
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
            try? AppRuntime.shared.outbox?.removeAll(profileID: AppRuntime.shared.profileID)
            try? PersonalSyncMetadataStore(modelContext: modelContext).removeAll()
            settings.reset()
            statusMessage = "All local Tenora data was deleted."
            deleting = false
        }
    }
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
