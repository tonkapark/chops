import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var skills: [Skill]
    @State private var scanner: SkillScanner?
    @State private var fileWatcher: FileWatcher?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var searchFocused: Bool
    // SwiftUI doesn't reliably back-bind the `.searchable` field losing focus,
    // so `searchFocused` reads `true` forever after the first press. Bumping
    // an Int on every shortcut press forces the false→true cycle below to
    // re-fire, which makes the shortcut idempotent.
    @State private var searchFocusBump: Int = 0

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
        .searchFocused($searchFocused)
        .onChange(of: searchFocusBump) { _, _ in
            searchFocused = false
            DispatchQueue.main.async { searchFocused = true }
        }
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
            // Fires before the scan finishes, but if the pending skill is
            // already in the query (reinstall of a row that was never removed)
            // the selection happens immediately. New installs still get caught
            // by the count-change observer below once the scan inserts them.
            applyPendingSkillSelection(in: skills)
            // Pick up upstream hashes for any skill the scan adds — without
            // this, in-session installs would never get an upstreamHash and
            // their Update badge would never light up until next launch. The
            // 6-hour staleness window inside checkAll keeps already-checked
            // skills from re-burning API quota.
            Task { await UpdateChecker.checkAll(in: modelContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            columnVisibility = columnVisibility == .doubleColumn ? .all : .doubleColumn
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterSkills)) { _ in
            searchFocusBump &+= 1
        }
        .onChange(of: skills.count) { _, _ in
            applyPendingSkillSelection(in: skills)
        }
    }

    /// When the user installs from the registry, the sheet records the
    /// canonical path of the new skill in `pendingSkillSelectionPath`. We try
    /// to resolve it both on scan-trigger (for reinstalls where the row
    /// already exists) and on `skills.count` change (for genuinely new rows).
    /// SwiftData's @Query updates model instances in place without changing
    /// array identity, so a plain `.onChange(of: skills)` would miss in-place
    /// updates — count works for inserts, and the notification path covers
    /// the no-insert case.
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
        // The `npx skills` global lock file lives at `~/.agents/.skill-lock.json`,
        // a sibling of `~/.agents/skills/` (which we already watch). Watch the
        // parent `~/.agents/` so lock-file create / edit / delete events
        // trigger a rescan even if the file didn't exist when Chops launched.
        allPaths.append("\(home)/.agents")
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

        // Check whether any managed skills have upstream updates. Throttled
        // inside UpdateChecker — skills checked within the staleness window
        // are skipped, so this is cheap on subsequent launches.
        Task {
            await UpdateChecker.checkAll(in: modelContext)
        }
    }
}
