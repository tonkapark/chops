import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var skills: [Skill]
    @State private var scanner: SkillScanner?
    @State private var fileWatcher: FileWatcher?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            SkillListView()
        } detail: {
            if let skill = appState.selectedSkill {
                SkillDetailView(skill: skill)
            } else if appState.selectedSkills.count > 1 {
                ContentUnavailableView(
                    "\(appState.selectedSkills.count) Items Selected",
                    systemImage: "checklist",
                    description: Text("Right-click the selection to favorite, add to a collection, or delete.")
                )
            } else {
                ContentUnavailableView(
                    "Select a Skill",
                    systemImage: "doc.text",
                    description: Text("Choose a skill from the sidebar to view and edit it.")
                )
            }
        }
        .searchable(text: $appState.searchText, prompt: "Search skills...")
        .onAppear {
            startScanning()
        }
        .sheet(isPresented: $appState.showingNewSkillSheet) {
            NewSkillSheet()
        }
        .sheet(isPresented: $appState.showingRegistrySheet) {
            RegistrySheet()
        }
        .sheet(isPresented: $appState.showingCommandPalette, onDismiss: runPaletteAction) {
            CommandPaletteView()
        }
        .onChange(of: appState.sidebarFilter) {
            appState.toolKindFilter = nil
        }
        .frame(minWidth: 900, minHeight: 500)
        .onReceive(NotificationCenter.default.publisher(for: .customScanPathsChanged)) { _ in
            scanner?.scanAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            columnVisibility = columnVisibility == .doubleColumn ? .all : .doubleColumn
        }
        .onChange(of: skills.count) { _, _ in
            applyPendingSkillSelection(in: skills)
        }
    }

    /// When the user installs from the registry, the sheet records the
    /// canonical path of the new skill in `pendingSkillSelectionPath`. The
    /// scan that follows surfaces the SwiftData row asynchronously — once it
    /// appears here, we select it and clear the pending state. Observed via
    /// `skills.count` rather than the array itself because SwiftData's @Query
    /// can update model instances in place without changing array identity.
    private func applyPendingSkillSelection(in skills: [Skill]) {
        guard let path = appState.pendingSkillSelectionPath,
              let match = skills.first(where: { $0.resolvedPath == path })
        else { return }
        appState.selectedSkill = match
        appState.pendingSkillSelectionPath = nil
    }

    /// Runs the action chosen in the command palette, after that sheet has
    /// fully dismissed — avoids presenting two sheets simultaneously.
    private func runPaletteAction() {
        guard let action = appState.pendingPaletteAction else { return }
        appState.pendingPaletteAction = nil
        switch action {
        case .navigate(let filter):
            appState.sidebarFilter = filter
        case .openDiscovery:
            appState.showingRegistrySheet = true
        case .newItem(let kind):
            appState.newItemKind = kind
            appState.showingNewSkillSheet = true
        }
    }

    private func startScanning() {
        AppLogger.ui.notice("App started, beginning initial scan")
        let scanner = SkillScanner(modelContext: modelContext)
        self.scanner = scanner
        scanner.removeDeletedSkills()
        scanner.scanAll()

        var allPaths: [String] = []
        for tool in ToolSource.allCases {
            allPaths.append(contentsOf: tool.globalPaths)
            allPaths.append(contentsOf: tool.globalAgentPaths)
            allPaths.append(contentsOf: tool.globalRulePaths)
        }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let claudePlugins = "\(home)/.claude/plugins"
        let claudePluginCache = "\(claudePlugins)/cache"
        let claudePluginManifest = "\(claudePlugins)/installed_plugins.json"
        for path in [claudePlugins, claudePluginCache, claudePluginManifest] where fm.fileExists(atPath: path) {
            allPaths.append(path)
        }
        let claudeDesktopSessions = "\(home)/Library/Application Support/Claude/local-agent-mode-sessions"
        if fm.fileExists(atPath: claudeDesktopSessions) {
            allPaths.append(claudeDesktopSessions)
        }
        // The `npx skills` global lock file lives next to the skills directory,
        // not inside it, so the per-tool watches above miss its edits.
        if fm.fileExists(atPath: LockfileService.globalLockPath) {
            allPaths.append(LockfileService.globalLockPath)
        }
        allPaths = Array(Set(allPaths)).sorted()

        let watcher = FileWatcher { _ in
            scanner.scanAll()
            scanner.removeDeletedSkills()
        }
        watcher.watchDirectories(allPaths)
        self.fileWatcher = watcher
        AppLogger.ui.notice("File watchers active on \(allPaths.count) directories")

        // Sync remote servers in the background
        Task {
            await scanner.syncAllRemoteServers()
        }
    }
}
