## Sidebar

The left column of the three-pane `NavigationSplitView`. It is the primary navigation surface —
selecting a row filters the middle list (`SkillListView`) and, in turn, the detail pane.

**Source:** `Chops/Views/Sidebar/SidebarView.swift` (plus `CollectionListView.swift`).
**State:** selection is bound to `appState.sidebarFilter` via `List(selection:)`; each selectable
row carries a `.tag(SidebarFilter…)`. The `SidebarFilter` cases are `allSkills`, `favorites`,
`tool(ToolSource)`, `collection(String)`, and `server(String)` (`Chops/App/AppState.swift`).

### Layout (top to bottom)

```
 Library            27      ← all items, every kind
 Favorites
 
 Global            23
 Claude Code       25
 Cursor            11
 …                         ← one row per tool with skills
Servers (if any)
Collections
─────────────            ← faint divider
Discovery                 ← opens the Browse Registry sheet (not a selection)
```



### Library — Skills & Favorites

- **Library** (`doc.text`, tag `.allSkills`) — the unified library. Lists every discovered item
  regardless of kind (skill, agent, rule); the badge is the total item count (`allSkills.count`).
  Because the list mixes kinds, each row in `SkillListView` shows a type badge.
- **Favorites** (`star`, tag `.favorites`) — items where `isFavorite == true`; badge is that count.

#### Tools / Agent Harnesses

One row per tool source that is **listable** and currently has at least one skill
(`activeSources` in `SidebarView`). Each row shows the tool's icon — a custom logo asset when one
exists (`ToolIcon`), otherwise the tool's SF Symbol — its display name, and a badge counting the
skills installed for that tool. Selecting a row (tag `.tool(tool)`) filters the list to that tool
and exposes a per-tool item-kind filter in `SkillListView`.

- **Global** is `ToolSource.agents` — the shared `~/.agents` location, not a specific editor.
- Tools without a listable surface never appear here (`.custom`, `.claudeDesktop`, `.aider`).
- A tool drops out of the sidebar automatically when its last skill is removed.

#### Servers

Shown only when at least one `RemoteServer` exists (`Section("Servers")`). Each row shows the
server label, a `server.rack` icon, and a badge of how many skills came from it (tag
`.server(id)`). Per row:

- **Sync button** — re-scans the server (`SkillScanner.scanRemoteServer`); shows a spinner while
  in flight.
- **Error indicator** — a red triangle appears if the last sync failed; tapping it shows the error
  message in a popover.

#### Collections

User-created groupings (`SkillCollection`), rendered by `CollectionListView` under
`Section("Collections")`. Collections are pure user data, not filesystem-backed.

- Each collection shows its chosen icon and a badge of its skill count (tag `.collection(name)`).
- **Drag and drop** a skill from the list onto a collection to add it (deduped by resolved path).
- **Context menu** — Rename (inline text field) or Delete. Renaming updates the active filter if
  that collection is selected.
- **New Collection** — a button opening a popover with a name field and an 18-icon picker;
  duplicate names (case-insensitive) are rejected.

### Discovery

A single action row at the bottom. It is **not** a navigation destination — it has no
`SidebarFilter` tag and does not participate in list selection. Clicking it sets
`appState.showingRegistrySheet = true`, which presents the Browse Registry sheet from
`ContentView` (see [skills-discovery](skills-discovery.md)). Icon: SF Symbol `safari`
(compass-needle glyph).

### Selection → list behavior

Whatever is selected sets `appState.sidebarFilter`, which `SkillListView.filteredSkills` switches
on to filter the middle column (search text and, for tools, the kind filter are applied on top).
The list pane's title mirrors the selection (e.g. "Skills", "Favorites", the tool name, the
collection name, or the server label).
