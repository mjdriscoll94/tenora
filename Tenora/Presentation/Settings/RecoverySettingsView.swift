import SwiftUI

struct RecoverySettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Offer help when I return", isOn: $settings.recoveryEnabled)
                if settings.recoveryEnabled {
                    Picker("Offer recovery", selection: $settings.recoveryDelayRaw) {
                        ForEach(RecoveryPromptDelay.allCases) { delay in
                            Text(delay.title).tag(delay.rawValue)
                        }
                    }
                }
            } header: {
                Text("Return assistance")
            } footer: {
                Text("When Tenora has been in the background long enough, it can restore your last intentional task and smallest next step. The permanent What was I doing? button remains available even when this is off.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle("Recovery")
    }
}
