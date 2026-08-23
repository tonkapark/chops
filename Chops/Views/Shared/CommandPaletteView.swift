import SwiftUI
import SwiftData

/// A ⌘K command palette: fuzzy-search and run quick actions — jump to a tool's
/// library, open the registry, or create a new skill/agent/rule. Keyboard-first
/// (↑/↓ to move, ↵ to run, ⎋ to dismiss); mouse hover/click also work.
struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Skill.name) private var allSkills: [Skill]

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var hoveredID: String?
    @FocusState private var searchFocused: Bool

    private var activeTools: [ToolSource] {
        ToolSource.allCases.filter { tool in
            tool.listable && allSkills.contains { $0.toolSources.contains(tool) }
        }
    }

    private var commands: [PaletteCommand] {
        var result: [PaletteCommand] = [
            PaletteCommand(title: "Skills", subtitle: nil, systemImage: "doc.text",
                           tool: nil, category: "Navigate", action: .navigate(.allSkills)),
            PaletteCommand(title: "Agents", subtitle: nil, systemImage: "person.crop.rectangle",
                           tool: nil, category: "Navigate", action: .navigate(.allAgents)),
            PaletteCommand(title: "Rules", subtitle: nil, systemImage: "list.bullet.rectangle",
                           tool: nil, category: "Navigate", action: .navigate(.allRules)),
            PaletteCommand(title: "Favorites", subtitle: nil, systemImage: "star",
                           tool: nil, category: "Navigate", action: .navigate(.favorites)),
        ]
        for tool in activeTools {
            result.append(PaletteCommand(title: tool.displayName, subtitle: nil,
                                         systemImage: tool.iconName, tool: tool,
                                         category: "Navigate", action: .navigate(.tool(tool))))
        }
        result.append(PaletteCommand(title: "Browse Registry",
                                     subtitle: nil, systemImage: "safari",
                                     tool: nil, category: "Discover", action: .openDiscovery))
        for kind in ItemKind.allCases {
            result.append(PaletteCommand(title: "New \(kind.singularName)", subtitle: nil,
                                         systemImage: "plus", tool: nil,
                                    
                                         category: "Create", action: .newItem(kind)))
        }
        return result
    }

    private var filtered: [PaletteCommand] {
        guard !query.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false) ||
            $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit(runSelected)
                    .onChange(of: query) { selectedIndex = 0 }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if filtered.isEmpty {
                Text("No matching commands")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                resultsList
            }
        }
        .frame(width: 560)
        .background(.thickMaterial)
        .onAppear { searchFocused = true }
        .onExitCommand { dismiss() }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                        VStack(alignment: .leading, spacing: 1) {
                            if index == 0 || filtered[index - 1].category != command.category {
                                Text(command.category.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                    .padding(.top, index == 0 ? 10 : 14)
                                    .padding(.bottom, 2)
                            }
                            CommandRow(command: command,
                                       selected: index == selectedIndex,
                                       hovered: command.id == hoveredID)
                                .contentShape(Rectangle())
                                .onTapGesture { run(command) }
                                .onHover { hovering in
                                    if hovering { hoveredID = command.id }
                                    else if hoveredID == command.id { hoveredID = nil }
                                }
                        }
                        .id(command.id)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 360)
            .onChange(of: selectedIndex) {
                guard filtered.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(filtered[selectedIndex].id, anchor: .center)
            }
        }
    }

    private func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), filtered.count - 1)
    }

    private func runSelected() {
        guard filtered.indices.contains(selectedIndex) else { return }
        run(filtered[selectedIndex])
    }

    private func run(_ command: PaletteCommand) {
        appState.pendingPaletteAction = command.action
        dismiss()
    }
}

private struct PaletteCommand: Identifiable {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tool: ToolSource?
    let category: String
    let action: PaletteAction

    var id: String { "\(category)/\(title)" }
}

private struct CommandRow: View {
    let command: PaletteCommand
    let selected: Bool
    let hovered: Bool

    private var background: Color {
        if selected { return .accentColor }
        if hovered { return .primary.opacity(0.08) }
        return .clear
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let tool = command.tool {
                    ToolIcon(tool: tool, size: 16)
                } else {
                    Image(systemName: command.systemImage)
                }
            }
            .frame(width: 20, height: 18)
            .foregroundStyle(selected ? .white : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .foregroundStyle(selected ? .white : .primary)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
    }
}
