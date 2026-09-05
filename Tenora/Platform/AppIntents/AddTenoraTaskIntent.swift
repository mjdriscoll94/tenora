import AppIntents
import Foundation

struct AddTenoraTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add task to Tenora"
    static var description = IntentDescription("Capture something you want Tenora to remember.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task title", requestValueDialog: "What do you need to remember?")
    var title: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$title) to Tenora") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let saved = await AppRuntime.shared.tasks.createTask(title: title, source: .shortcut)
        guard saved else { throw CaptureError.couldNotSave }
        return .result(dialog: "Saved to Tenora.")
    }

    enum CaptureError: LocalizedError {
        case couldNotSave
        var errorDescription: String? { "Tenora couldn't save this task. Check the title and try again." }
    }
}

struct TenoraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTenoraTaskIntent(), phrases: [
            "Add a task to \(.applicationName)",
            "Remember something in \(.applicationName)"
        ], shortTitle: "Remember something", systemImageName: "plus.circle")
    }
}
