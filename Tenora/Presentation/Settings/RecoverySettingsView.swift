import SwiftUI

struct RecoverySettingsView: View {
    @AppStorage(AttentionPreferences.recoveryEnabledKey) private var recoveryEnabled = true
    @AppStorage(AttentionPreferences.recoveryDelayKey) private var recoveryDelayRaw = RecoveryPromptDelay.fifteenMinutes.rawValue

    var body: some View {
        Form {
            Section {
                Toggle("Offer help when I return", isOn: $recoveryEnabled)
                if recoveryEnabled {
                    Picker("Offer recovery", selection: $recoveryDelayRaw) {
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
