import SwiftUI

@Observable
final class AppState {
    var selectedTool: ToolSource?
    var selectedSkill: Skill?
    var searchText: String = ""
    var showingNewSkillSheet: Bool = false
    var showingRegistrySheet: Bool = false
    var showingCommandPalette: Bool = false
    /// Action chosen in the command palette, run after the palette sheet dismisses
    /// (so we never present two sheets at once).
    var pendingPaletteAction: PaletteAction?
    var newItemKind: ItemKind = .skill
    var sidebarFilter: SidebarFilter = .allSkills
    /// Filter by item kind within a tool view (nil = show all)
    var toolKindFilter: ItemKind?
}

enum PaletteAction: Equatable {
    case navigate(SidebarFilter)
    case openDiscovery
    case newItem(ItemKind)
}

enum SidebarFilter: Hashable {
    case allSkills
    case allAgents
    case allRules
    case favorites
    case tool(ToolSource)
    case collection(String)
    case server(String)
}
