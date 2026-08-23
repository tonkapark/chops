# Keyboard Navigation

Chops is keyboard-driven. The ⌘K command palette is the fastest way to jump
anywhere or create something; everything it does is also bound to a menu
shortcut.

## ⌘K — Command Palette

Press **⌘K** (also under the **View** menu) to open the palette. Start typing to
fuzzy-filter across command title and category. It is keyboard-first:

| Key | Action |
|-----|--------|
| Type | Filter the command list |
| ↑ / ↓ | Move the selection |
| ↵ | Run the selected command |
| ⎋ | Dismiss the palette |
| Click | Run a command directly (hover highlights, but never moves the keyboard selection) |

The chosen command runs after the palette closes, so it never collides with the
sheet it opens.

### Commands shown

**Navigate** — switches the sidebar selection / list view:
- **Skills**, **Agents**, **Rules** — each library section
- **Favorites** — items marked favorite
- **One row per tool** that currently has items — e.g. Global, Claude Code,
  Cursor, Codex, OpenCode — each jumps to that tool's library. Tools with no
  items are omitted (matching the sidebar).

**Discover**:
- **Browse Registry** — opens the registry sheet to discover skills from
  skills.sh (see [skills-discovery](skills-discovery.md))

**Create** — opens the New Item sheet pre-set to that kind:
- **New Skill**
- **New Agent**
- **New Rule**

## App shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘K | Open the command palette |
| ⌘B | Toggle the sidebar |
| ⌘⇧L | Go to Skills |
| ⌘S | Save the current skill (disabled when nothing is selected) |
| ⌘, | Open Settings |

⌘, opens the standard macOS **Settings** window (a separate window, not a modal
sheet). It is provided automatically by SwiftUI's `Settings` scene and listed as
**Settings…** under the **Chops** app menu — no custom binding is needed. The
window opens with the section tab bar focused, so **← / →** switch sections
(General, Library, AI Assist, Scan Directories, Servers, About) without reaching
for the mouse.

Standard macOS text-editing shortcuts (⌘C/⌘V/⌘Z, etc.) apply in the editor.

## Sheet & panel conventions

Modal sheets and panels follow the usual macOS defaults:

| Shortcut | Action |
|----------|--------|
| ↵ | Confirm the primary button (e.g. **Create**, **Add**) |
| ⌘↵ | Send / accept in the compose and diff-review panels |
| ⎋ or ⌘. | Cancel / dismiss |
