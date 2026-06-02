import SwiftUI
import SwiftData

struct SkillListView: View {
    private enum ActiveAlert: Identifiable {
        case confirmDelete(Skill)
        case confirmDeleteMultiple([Skill])
        case confirmMakeGlobal(Skill)
        case deleteError(String)
        case makeGlobalError(String)

        var id: String {
            switch self {
            case .confirmDelete(let skill):
                return "confirm-delete-\(skill.filePath)"
            case .confirmDeleteMultiple(let skills):
                return "confirm-delete-multiple-\(skills.map(\.filePath).sorted().joined(separator: "|"))"
            case .confirmMakeGlobal(let skill):
                return "confirm-make-global-\(skill.filePath)"
            case .deleteError(let message):
                return "delete-error-\(message)"
            case .makeGlobalError(let message):
                return "make-global-error-\(message)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \SkillCollection.name) private var allCollections: [SkillCollection]
    @State private var activeAlert: ActiveAlert?

    private var filteredSkills: [Skill] {
        var result = allSkills

        switch appState.sidebarFilter {
        case .allSkills:
            break   // unified list — all item kinds
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .tool(let tool):
            result = result.filter { $0.toolSources.contains(tool) }
            if let kind = appState.toolKindFilter {
                result = result.filter { $0.itemKind == kind }
            }
        case .collection(let collName):
            result = result.filter { skill in
                skill.collections.contains { $0.name == collName }
            }
        case .server(let serverID):
            result = result.filter { $0.remoteServer?.id == serverID }
        }

        if !appState.searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(appState.searchText) ||
                $0.skillDescription.localizedCaseInsensitiveContains(appState.searchText) ||
                $0.content.localizedCaseInsensitiveContains(appState.searchText)
            }
        }

        return result
    }

    private var title: String {
        switch appState.sidebarFilter {
        case .allSkills: "Library"
        case .favorites: "Favorites"
        case .tool(let tool): tool.displayName
        case .collection(let name): name
        case .server(let id):
            allSkills.first(where: { $0.remoteServer?.id == id })?.remoteServer?.label ?? "Remote"
        }
    }

    /// Whether the current filter shows mixed item types (skills and agents together)
    private var showsTypeBadge: Bool {
        switch appState.sidebarFilter {
        case .tool: appState.toolKindFilter == nil
        default: true
        }
    }

    private var availableKinds: [ItemKind] {
        guard case .tool(let tool) = appState.sidebarFilter else { return [] }
        let kinds = Set(allSkills.filter { $0.toolSources.contains(tool) }.map(\.itemKind))
        return ItemKind.allCases.filter { kinds.contains($0) }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if let kind = appState.toolKindFilter {
            ContentUnavailableView(
                "No \(kind.displayName)",
                systemImage: kind.icon,
                description: Text("No \(kind.displayName.lowercased()) match the current filter.")
            )
        } else {
            ContentUnavailableView("No Items", systemImage: "doc.text",
                description: Text("No items match the current filter."))
        }
    }

    @ViewBuilder
    private func contextMenu(for skills: Set<Skill>) -> some View {
        if skills.count == 1, let skill = skills.first {
            singleContextMenu(for: skill)
        } else if skills.count > 1 {
            multiContextMenu(for: skills)
        }
    }

    @ViewBuilder
    private func singleContextMenu(for skill: Skill) -> some View {
        Button(skill.isFavorite ? "Unfavorite" : "Favorite") {
            skill.isFavorite.toggle()
            try? modelContext.save()
        }
        if skill.canMakeGlobal {
            Button("Make Global") {
                activeAlert = .confirmMakeGlobal(skill)
            }
        }
        if !allCollections.isEmpty {
            Menu("Collections") {
                ForEach(allCollections) { collection in
                    let isAssigned = skill.collections.contains(where: { $0.name == collection.name })
                    Button {
                        if isAssigned {
                            skill.collections.removeAll { $0.name == collection.name }
                        } else {
                            skill.collections.append(collection)
                        }
                        try? modelContext.save()
                    } label: {
                        Toggle(isOn: .constant(isAssigned)) {
                            Label(collection.name, systemImage: collection.icon)
                        }
                    }
                }
            }
        }
        if !skill.isRemote {
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(skill.filePath, inFileViewerRootedAtPath: "")
            }
        }
        if !skill.isReadOnly {
            Divider()
            Button("Delete", role: .destructive) {
                activeAlert = .confirmDelete(skill)
            }
        }
    }

    /// Bulk actions for a multi-selection. No "Show in Finder" — that targets a
    /// single file and is meaningless for many.
    @ViewBuilder
    private func multiContextMenu(for skills: Set<Skill>) -> some View {
        let allFavorite = skills.allSatisfy(\.isFavorite)
        Button(allFavorite ? "Unfavorite \(skills.count) Items" : "Favorite \(skills.count) Items") {
            for skill in skills { skill.isFavorite = !allFavorite }
            try? modelContext.save()
        }
        if !allCollections.isEmpty {
            Menu("Collections") {
                ForEach(allCollections) { collection in
                    let allAssigned = skills.allSatisfy { skill in
                        skill.collections.contains { $0.name == collection.name }
                    }
                    Button {
                        for skill in skills {
                            let isAssigned = skill.collections.contains { $0.name == collection.name }
                            if allAssigned {
                                skill.collections.removeAll { $0.name == collection.name }
                            } else if !isAssigned {
                                skill.collections.append(collection)
                            }
                        }
                        try? modelContext.save()
                    } label: {
                        Toggle(isOn: .constant(allAssigned)) {
                            Label(collection.name, systemImage: collection.icon)
                        }
                    }
                }
            }
        }
        let deletable = skills.filter { !$0.isReadOnly }
        if !deletable.isEmpty {
            Divider()
            Button("Delete \(deletable.count) Items", role: .destructive) {
                activeAlert = .confirmDeleteMultiple(Array(deletable))
            }
        }
    }

    private func makeSkillGlobal(_ skill: Skill) {
        do {
            try skill.makeGlobal()
            try? modelContext.save()
        } catch {
            activeAlert = .makeGlobalError(error.localizedDescription)
        }
    }

    private func deleteSkill(_ skill: Skill) {
        guard !skill.isReadOnly else { return }
        Task { @MainActor in
            do {
                try await skill.deleteFromDisk()
                appState.selectedSkills.remove(skill)
                modelContext.delete(skill)
                try modelContext.save()
            } catch {
                activeAlert = .deleteError(error.localizedDescription)
            }
        }
    }

    private func deleteSkills(_ skills: [Skill]) {
        Task { @MainActor in
            var firstError: String?
            for skill in skills where !skill.isReadOnly {
                do {
                    try await skill.deleteFromDisk()
                    appState.selectedSkills.remove(skill)
                    modelContext.delete(skill)
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                }
            }
            try? modelContext.save()
            if let firstError {
                activeAlert = .deleteError(firstError)
            }
        }
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSkills) {
            ForEach(filteredSkills) { skill in
                SkillRow(skill: skill, showTypeBadge: showsTypeBadge)
                    .tag(skill)
                    .draggable(skill.resolvedPath)
            }
        }
        .contextMenu(forSelectionType: Skill.self) { skills in
            contextMenu(for: skills)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    if case .tool = appState.sidebarFilter, availableKinds.count > 1 {
                        Menu {
                            Button {
                                appState.toolKindFilter = nil
                            } label: {
                                if appState.toolKindFilter == nil {
                                    Label("All", systemImage: "checkmark")
                                } else {
                                    Text("All")
                                }
                            }
                            Divider()
                            ForEach(availableKinds, id: \.self) { kind in
                                Button {
                                    appState.toolKindFilter = kind
                                } label: {
                                    if appState.toolKindFilter == kind {
                                        Label(kind.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(kind.displayName)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: appState.toolKindFilter != nil ? "ellipsis.circle.fill" : "ellipsis.circle")
                        }
                    }
                    Menu {
                        Button {
                            appState.newItemKind = .skill
                            appState.showingNewSkillSheet = true
                        } label: {
                            Label("New Skill", systemImage: "doc.text")
                        }
                        Button {
                            appState.newItemKind = .agent
                            appState.showingNewSkillSheet = true
                        } label: {
                            Label("New Agent", systemImage: "person.crop.rectangle")
                        }
                        Button {
                            appState.newItemKind = .rule
                            appState.showingNewSkillSheet = true
                        } label: {
                            Label("New Rule", systemImage: "list.bullet.rectangle")
                        }
                        Divider()
                        Button {
                            appState.showingRegistrySheet = true
                        } label: {
                            Label("Browse Registry", systemImage: "globe")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuIndicator(.hidden)
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmMakeGlobal(let skill):
                return Alert(
                    title: Text("Make \"\(skill.name)\" Global?"),
                    message: Text("This will move the skill to ~/.agents/skills/ and symlink it to all installed agents."),
                    primaryButton: .default(Text("Make Global")) {
                        makeSkillGlobal(skill)
                    },
                    secondaryButton: .cancel()
                )
            case .confirmDelete(let skill):
                return Alert(
                    title: Text("Delete \(skill.displayTypeName)?"),
                    message: Text("This will permanently delete \"\(skill.name)\" from disk."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteSkill(skill)
                    },
                    secondaryButton: .cancel()
                )
            case .confirmDeleteMultiple(let skills):
                return Alert(
                    title: Text("Delete \(skills.count) Items?"),
                    message: Text("This will permanently delete \(skills.count) items from disk."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteSkills(skills)
                    },
                    secondaryButton: .cancel()
                )
            case .deleteError(let message):
                return Alert(
                    title: Text("Delete Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .makeGlobalError(let message):
                return Alert(
                    title: Text("Make Global Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .overlay {
            if filteredSkills.isEmpty { emptyStateView }
        }
        .onChange(of: appState.sidebarFilter) {
            // Drop any selection that isn't in the new filter; if nothing valid
            // survives, fall back to the first row.
            let surviving = appState.selectedSkills.filter { filteredSkills.contains($0) }
            if surviving.isEmpty {
                appState.selectedSkill = filteredSkills.first
            } else if surviving != appState.selectedSkills {
                appState.selectedSkills = surviving
            }
        }
    }
}

struct SkillRow: View {
    let skill: Skill
    var showTypeBadge: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showTypeBadge {
                let kindIcon: String = switch skill.itemKind {
                case .agent: "person.crop.rectangle"
                case .rule: "list.bullet.rectangle"
                case .skill: "doc.text"
                }
                Image(systemName: kindIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(skill.name)
                .lineLimit(1)

            if skill.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            if skill.hasUpdateAvailable {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Update available")
            }

            Spacer()

            if skill.isRemote, let serverLabel = skill.remoteServer?.label {
                Text(serverLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if let project = skill.projectName {
                Text(project)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 3) {
                ForEach(skill.toolSources, id: \.self) { tool in
                    ToolIcon(tool: tool, size: 14)
                        .help(tool.displayName)
                        .opacity(0.6)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
