import SwiftUI

@main
struct MeetingTranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MainWindowScene(appState: appState)
            .commands {
                CommandMenu("Transcription") {
                    Button("Import Audio…") {
                        appState.presentImportDraft()
                    }
                    .keyboardShortcut("o")

                    Button(appState.stopMenuTitle) {
                        appState.cancelActiveRun()
                    }
                    .keyboardShortcut(".")
                    .disabled(!appState.canStopActiveRun || appState.isCancellingActiveRun)
                }
            }

        Settings {
            SettingsContentView(appState: appState)
                .frame(width: 460)
        }
    }
}

private struct SettingsContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("Storage") {
                settingsPathRow("Models", path: appState.modelsDirectoryPath)
                settingsPathRow("Run Manifest", path: appState.runsDirectoryPath)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func settingsPathRow(_ title: LocalizedStringKey, path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }
}
