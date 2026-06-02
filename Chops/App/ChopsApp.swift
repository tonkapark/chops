import SwiftUI
import SwiftData
import Sparkle
import AppKit

@main
struct ChopsApp: App {
    @State private var appState = AppState()
    @AppStorage("AgentDebugLogging") private var debugLoggingEnabled = false
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)

        do {
            let config = try StoreBootstrap.makeConfiguration(schema: schema)
            return try ModelContainer(
                for: schema,
                migrationPlan: ChopsMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            TextEditingCommands()
            // Chops is a single-window app — drop the "New Window" command.
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Go to Library") {
                    appState.sidebarFilter = .allSkills
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Command Palette") {
                    appState.showingCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()
            }
            // Replacing (not after) .saveItem drops SwiftUI's default Close/Close All
            // from the File menu; Close lives in the Window menu instead (below).
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveCurrentSkill, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.selectedSkill == nil)
            }
            // Close Window in the Window menu, next to "Remove Window from Set".
            CommandGroup(after: .windowSize) {
                Button {
                    NSApp.keyWindow?.performClose(nil)
                } label: {
                    Label("Close Window", systemImage: "xmark")
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
                Button("Check for Skill Updates") {
                    Task {
                        await UpdateChecker.checkAll(
                            in: sharedModelContainer.mainContext,
                            force: true
                        )
                    }
                }
            }
            CommandGroup(after: .help) {
                Toggle("Enable Debug Logging", isOn: $debugLoggingEnabled)
                Divider()
                Button("Export Diagnostic Log…") {
                    let context = sharedModelContainer.mainContext
                    DiagnosticExporter.export(modelContext: context)
                }
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(appState)
                .modelContainer(sharedModelContainer)
        }
    }
}

// MARK: - Sparkle Check for Updates menu item

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var observation: Any?

    init(updater: SPUUpdater) {
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, change in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }
}
