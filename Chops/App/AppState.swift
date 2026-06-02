import SwiftUI

@Observable
final class AppState {
    var selectedTool: ToolSource?
    /// Source of truth for list selection — supports shift/⌘-click multi-select.
    var selectedSkills: Set<Skill> = []
    /// Single-selection bridge for the detail pane and Save command: non-nil only
    /// when exactly one skill is selected.
    var selectedSkill: Skill? {
        get { selectedSkills.count == 1 ? selectedSkills.first : nil }
        set { selectedSkills = newValue.map { [$0] } ?? [] }
    }
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
    /// Resolved-path of a skill the user just installed via the registry.
    /// ContentView watches its skills query and auto-selects the matching
    /// skill the moment scanning surfaces it, then clears this.
    var pendingSkillSelectionPath: String?
}

enum PaletteAction: Equatable {
    case navigate(SidebarFilter)
    case openDiscovery
    case newItem(ItemKind)
}

enum SidebarFilter: Hashable {
    case allSkills
    case favorites
    case tool(ToolSource)
    case collection(String)
    case server(String)
}

/// SwiftUI-focusable panes for keyboard navigation. The editor is an AppKit
/// `NSTextView` and tracks its own first-responder state, so it is not a case
/// here — `ContentView` drives the full Sidebar → List → Search → Editor cycle.
enum FocusPane: Hashable {
    case sidebar
    case list
}
