import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var units: UnitSystem = .localeDefault
    @State private var apiKey = KeychainStore.loadAPIKey() ?? ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(saved ? "Saved" : "Save key") {
                        saved = KeychainStore.saveAPIKey(apiKey)
                    }
                    .disabled(saved)
                } header: {
                    Text("Claude API key")
                } footer: {
                    Text("Used for the AI weather summary. Stored in this device's Keychain and sent only to api.anthropic.com. Get a key at console.anthropic.com.")
                }
                .onChange(of: apiKey) { saved = false }

                Section("Units") {
                    Picker("Units", selection: $units) {
                        ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("About") {
                    LabeledContent("Weather data", value: "Open-Meteo")
                    LabeledContent("AI model", value: ClaudeService.model)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !saved { KeychainStore.saveAPIKey(apiKey) }
                        dismiss()
                    }
                }
            }
        }
    }
}
