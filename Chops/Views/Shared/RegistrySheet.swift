import SwiftUI

struct RegistrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var registry = SkillRegistry()
    @State private var searchText = ""
    @State private var results: [SkillRegistry.RegistrySkill] = []
    @State private var trending: [SkillRegistry.RegistrySkill] = []
    @State private var isLoadingTrending = false
    @State private var trendingError: String?
    @State private var officialOnly = false
    @State private var selectedSkill: SkillRegistry.RegistrySkill?
    @State private var skillContent: String?
    @State private var isSearching = false
    @State private var isFetchingContent = false
    @State private var isInstalling = false
    @State private var error: String?
    @State private var installSuccess = false
    @State private var searchTask: Task<Void, Never>?
    @State private var contentTask: Task<Void, Never>?

    /// What the list renders: trending when idle, locally-filtered trending plus any
    /// long-tail API hits when searching. Local matches come first (they're the popular
    /// ones), API extras fill in skills that aren't in the trending set.
    private var visibleSkills: [SkillRegistry.RegistrySkill] {
        let base: [SkillRegistry.RegistrySkill]
        if searchText.count < 2 {
            base = trending
        } else {
            let local = SkillRegistry.filter(trending, query: searchText)
            let localIDs = Set(local.map(\.id))
            let extra = results.filter { !localIDs.contains($0.id) }
            base = local + extra
        }
        return officialOnly ? base.filter { $0.isOfficial == true } : base
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if selectedSkill != nil {
                    Button {
                        withAnimation {
                            contentTask?.cancel()
                            selectedSkill = nil
                            skillContent = nil
                            error = nil
                            installSuccess = false
                            isFetchingContent = false
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(selectedSkill != nil ? "Install Skill" : "Browse Skills")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if let skill = selectedSkill {
                installView(skill: skill)
            } else {
                searchView
            }
        }
        .frame(width: 560, height: 620)
        .task {
            await loadTrending()
        }
        .onDisappear {
            searchTask?.cancel()
            contentTask?.cancel()
        }
    }

    // MARK: - Search Phase

    private var searchView: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search skills (e.g. react, testing, deploy)...", text: $searchText)
                    .textFieldStyle(.plain)
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onChange(of: searchText) { _, newValue in
                debounceSearch(query: newValue)
            }

            // Browse header: section label + Official filter toggle
            HStack {
                Text(searchText.count < 2 ? "Trending" : "Results")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Official only", isOn: $officialOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Divider()

            // Results
            if isLoadingTrending && trending.isEmpty && searchText.count < 2 {
                Spacer()
                ProgressView("Loading popular skills…")
                Spacer()
            } else if visibleSkills.isEmpty && searchText.count >= 2 && !isSearching {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else if trendingError != nil && trending.isEmpty && searchText.count < 2 {
                ContentUnavailableView {
                    Label("Couldn't load trending skills", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Check your connection, or search the registry directly.")
                } actions: {
                    Button("Retry") {
                        Task { await loadTrending() }
                    }
                }
                .frame(maxHeight: .infinity)
            } else if visibleSkills.isEmpty {
                ContentUnavailableView {
                    Label("Search the Skills Registry", systemImage: "globe")
                } description: {
                    Text("Find and install skills from the open agent skills ecosystem.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(visibleSkills) { skill in
                    Button {
                        selectSkill(skill)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(skill.name)
                                        .fontWeight(.medium)
                                    if skill.isOfficial == true {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(skill.source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(skill.formattedInstalls) installs")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Install Phase

    private func installView(skill: SkillRegistry.RegistrySkill) -> some View {
        VStack(spacing: 0) {
            if isFetchingContent {
                Spacer()
                ProgressView("Loading skill content...")
                Spacer()
            } else if let content = skillContent {
                // Content preview — fills the freed vertical space now that
                // per-agent checkboxes are gone.
                ScrollView {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(maxHeight: .infinity)
                .background(.quaternary.opacity(0.3))

                Divider()

                // Install button — always installs globally; CLI auto-detects
                // which of the user's installed agents to wire up.
                HStack {
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }

                    if installSuccess {
                        Label("Installed!", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Text("npx skills add \(skill.source) -g -s \(skill.skillId) -y")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("npx skills add \(skill.source) -g -s \(skill.skillId) -y")
                        .layoutPriority(-1)

                    Button {
                        performInstall(skill: skill)
                    } label: {
                        if isInstalling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Install")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInstalling || installSuccess)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else if let error {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func loadTrending() async {
        guard trending.isEmpty else { return }
        isLoadingTrending = true
        trendingError = nil
        // Search stays available even if trending fails; surface the failure explicitly.
        do {
            trending = try await registry.fetchTrending()
        } catch {
            trendingError = error.localizedDescription
        }
        isLoadingTrending = false
    }

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        error = nil

        guard query.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                let skills = try await registry.search(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    results = skills
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func selectSkill(_ skill: SkillRegistry.RegistrySkill) {
        contentTask?.cancel()
        selectedSkill = skill
        skillContent = nil
        error = nil
        installSuccess = false
        isFetchingContent = true

        contentTask = Task {
            do {
                let content = try await registry.fetchContent(skill: skill)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard selectedSkill?.id == skill.id else { return }
                    self.skillContent = content
                    self.isFetchingContent = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard selectedSkill?.id == skill.id else { return }
                    self.error = error.localizedDescription
                    self.isFetchingContent = false
                }
            }
        }
    }

    private func performInstall(skill: SkillRegistry.RegistrySkill) {
        isInstalling = true
        error = nil

        Task {
            do {
                try await registry.install(skill: skill)
                installSuccess = true
                isInstalling = false

                // Tell ContentView which skill to select once the rescan
                // surfaces it; canonical path matches the `npx skills add`
                // layout (`~/.agents/skills/<skillId>/SKILL.md`).
                appState.pendingSkillSelectionPath =
                    "\(NSHomeDirectory())/.agents/skills/\(skill.skillId)/SKILL.md"

                // Universal-mode agents (Cursor, Codex, Zed, …) get no
                // per-agent symlink, so the skill's only toolSource is
                // `.agents`. Make sure the active filter actually contains
                // it — otherwise the highlight target is invisible.
                appState.sidebarFilter = .allSkills
                appState.toolKindFilter = nil

                // Trigger re-scan so the new skill appears immediately
                NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)

                try? await Task.sleep(for: .milliseconds(800))
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isInstalling = false
            }
        }
    }
}
