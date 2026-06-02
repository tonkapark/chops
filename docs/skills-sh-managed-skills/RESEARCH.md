# skills.sh-Managed Skills Research

## Overview

Add first-class support in Chops for skills installed via the `npx skills` CLI (skills.sh / `vercel-labs/skills`). Detect them via the `skills-lock.json` lock file, surface their source provenance in the UI, route install / remove / update through the CLI instead of direct filesystem operations, and badge skills with newer upstream versions.

## Problem Statement

Today, Chops manages skills purely by reading and writing files in `~/.agents/skills/` and the per-tool skill directories. The community is converging on `npx skills` as the canonical way to install / update / remove skills from GitHub-backed packages, with a lock file that tracks provenance and an update mechanism that knows when upstream has moved.

If Chops keeps treating these files as anonymous markdown, three things break:

1. Users lose provenance — they can't see where a skill came from or visit its source.
2. Direct filesystem deletion silently corrupts the lock file, leaving "phantom" entries that the CLI then tries to manage.
3. Chops has no way to tell the user "this skill has an update available."

We need Chops to recognise managed skills, defer to the CLI for lifecycle operations, and present the new metadata clearly.

## User Stories / Use Cases

- **Browse → install**: User opens the registry sheet, picks a skill, ticks the agents to install for, hits Install. Chops runs `npx skills add` in the background; once it finishes the new skill shows up in the library.
- **Source visibility**: A user opens a managed skill's detail view. Below the Location row they see "Source: https://github.com/imbue-ai/blueprint" — clickable, opens in browser.
- **Update available**: A skill in the list shows an orange up-arrow badge. The detail header shows "Update available — installed 2026-04-30, upstream is newer." Clicking "Update" runs `npx skills update <name>`.
- **Remove**: User right-clicks a managed skill → Remove. Chops runs `npx skills remove <name>`, the lock file and symlinks are cleaned up correctly, the skill disappears from the library.
- **Hand-edited skill is unaffected**: A user-authored skill (no lock entry) continues to use the existing direct-delete and direct-write paths, unchanged.

## Technical Research

### How skills.sh actually works (verified locally)

The `npx skills` CLI is installed and operational on this machine. Verified behaviour:

**Lock file location and shape** (verified by reading `/Users/mando/.agents/.skill-lock.json`):

- Global lock: `~/.agents/.skill-lock.json` (note the **leading dot** — it's hidden).
- Project lock: `<project>/skills-lock.json` (no leading dot; verified at `/Users/mando/dev/agent-scripts/skills-lock.json`).
- Schema (`"version": 3` for global, `"version": 1` for the older local-source project file):

```json
{
  "version": 3,
  "skills": {
    "blueprint": {
      "source": "imbue-ai/blueprint",
      "sourceType": "github",
      "sourceUrl": "https://github.com/imbue-ai/blueprint.git",
      "skillPath": "skills/blueprint/SKILL.md",
      "skillFolderHash": "f1c1e286...",
      "installedAt": "2026-04-30T16:21:15.162Z",
      "updatedAt": "2026-04-30T16:21:15.162Z"
    }
  },
  "dismissed": { "findSkillsPrompt": true },
  "lastSelectedAgents": ["claude-code", "codex", "cursor", "..."]
}
```

The `skillFolderHash` is the CLI's identity for the installed copy. When the source updates, the CLI computes a fresh hash for the upstream and compares — if different, an update is available.

**Lock keys are skill names** (e.g. `blueprint`), not paths. A skill's canonical location is `~/.agents/skills/<key>/SKILL.md`, and the CLI symlinks from each selected agent's directory back to that canonical location. (Optionally `--copy` makes the agent copies real files.)

**CLI commands and flags** (verified via `npx skills --help`):

```bash
npx skills add <source>  -g  -a <agent>  -s <skillName>  -y
npx skills remove <name> -g  -a <agent>                  -y
npx skills update [<name>...]
npx skills list -g
```

- `-g` / `--global` installs to `~/.agents/skills/` (the location Chops already scans). Project scope is `<cwd>/.agents/skills/` plus a project-root lock file.
- `-a` / `--agent` is **repeatable** (`-a claude-code -a cursor`) and also accepts `*` for all detected agents.
- `-s` / `--skill` selects skills inside a multi-skill package; for single-skill registry entries we pass `-s <skillId>`.
- `-y` skips confirmation prompts — required for non-interactive use from Chops.
- `update` with no args checks every installed skill against its source repo. Output: `Found N global update(s)` followed by per-skill `✓ Updated <name>`. There is **no `--dry-run`** — see "Update detection" below.

**Agent identifiers** are kebab-case strings: `claude-code`, `codex`, `cursor`, `opencode`, `windsurf`, `zed`, `cline`, `continue`, `github-copilot`, `amp`, `antigravity`, `gemini-cli`, `factory` / `droid`, `pi`, `kimi-cli`, `warp`, `deepagents`, `dexto`, `firebender`, `openhands`, etc. These do **not** match Chops's `ToolSource.id` strings exactly (Chops uses e.g. `claude`, not `claude-code`). We need a small mapping table.

### Chops integration points

The codebase is well-positioned for this — every touch point already exists:

- **`Chops/Models/ToolSource.swift`** — defines the 21 tool cases and their scan paths. Need a static `agentIdForSkillsCLI` map (e.g. `.claude → "claude-code"`) for translating Chops tool selection into CLI flags.
- **`Chops/Services/SkillScanner.swift:488`** — `applyResults()` upserts skills keyed by resolved symlink path. This is the natural place to attach lock-file metadata: after collecting filesystem skills, load the lock file once, and for each skill whose canonical path matches a lock entry, copy the `source`, `sourceUrl`, `installedAt`, `updatedAt`, `skillFolderHash` into the SwiftData row.
- **`Chops/Models/SchemaVersions.swift`** — currently `SchemaV1` only, no migrations registered. Adding nullable fields (`sourceURL: String?`, `lockSource: String?`, `lockUpdatedAt: Date?`, `upstreamHash: String?`) is the cheapest path; SwiftData handles the lightweight migration automatically. Only break out a `SchemaV2` if we need a non-additive change later.
- **`Chops/Services/SkillRegistry.swift:311` (`install`)** — currently writes file + symlinks. Replace with one call to a new `SkillsCLI.add(source:skillId:agents:)` helper. Same call site, same UI flow.
- **`Chops/Views/Shared/RegistrySheet.swift:415` (`performInstall`)** — already collects the user's agent picks (`selectedAgents`). The user wants this to invoke the CLI in the background; the existing UI already shows `isInstalling` + success state, so we keep that UI and swap the underlying call.
- **`Chops/Views/Detail/SkillHeaderPanel.swift:58` (`locationRow`)** — add a `sourceRow` directly beneath, identical visual treatment to Location but rendering the source URL as a button that opens in browser. Shown only when `skill.sourceURL != nil`.
- **`Chops/Views/Sidebar/SkillListView.swift:373` (`SkillRow`)** — add a single `Image(systemName: "arrow.up.circle.fill")` after the favorite star, shown only when `skill.upstreamHash != nil && skill.upstreamHash != skill.skillFolderHash`.
- **`Chops/Models/Skill.swift:253` (`deleteFromDisk`)** — branch at this single boundary: if `lockSource != nil`, call `SkillsCLI.remove(name:)` instead of `FileManager.removeItem`. The UI calling `deleteFromDisk` doesn't need to know which path was taken.
- **`Chops/Services/FileWatcher.swift`** — already watches `~/.agents/skills` (verified — that's where the symlinks point). Changes to `~/.agents/.skill-lock.json` won't trigger via the directory watcher because it's at `~/.agents/`, not inside `skills/`. **Add `~/.agents/.skill-lock.json` (and project lock files when present) to the watched paths** so the lock file's updates trigger a rescan and update-badge refresh.

### Subprocess helper

No shared subprocess helper exists today. `SSHService.swift:130–165` has the idiomatic Process-pipe pattern; the existing `ClaudeCLIAgent` / `CodexCLIAgent` follow the same shape. We'll create one focused service:

```swift
@MainActor
final class SkillsCLI {
    func add(source: String, skillId: String, agents: [String]) async throws -> String
    func remove(name: String, agents: [String]) async throws -> String
    func update(names: [String]) async throws -> [String] // returns updated skill names
    func list(global: Bool) async throws -> [LockEntry]   // optional; lock file is authoritative
}
```

All four shell out to `npx skills <cmd> -g -y` with `-a` flags repeated per agent. They run on a background queue and return when the process exits. The registry-install UI already supports an async loading state, so the only surface change is `try registry.install(...)` becoming `try await skillsCLI.add(...)`.

`npx` resolution uses the same probe pattern as `ToolSource.cliBinaryURL()` — `/opt/homebrew/bin/npx`, `/usr/local/bin/npx`, then asdf/nvm fallbacks. On this machine it's at `/Users/mando/.asdf/shims/npx`.

### Update detection — the only non-obvious design call

There is no `npx skills update --dry-run`. We have two options:

- **A. Lazy / on-demand**: a per-skill "Check for update" or a global "Check updates" command runs `npx skills update <name>` (or `update` with no args). Output is parsed for `Found N update(s)` and `✓ Updated <name>` lines. **Cost:** running the check *is* the update. There's no "you have updates, want to install them?" intermediate state.
- **B. Eager / hash-compare** (recommended): on scan, for each managed skill, fetch the upstream `SKILL.md` (cheap GitHub raw fetch — Chops already does this in `SkillRegistry.fetchContent`), compute the same folder hash the CLI uses, compare to `skillFolderHash` from the lock. If different → badge "update available" without touching disk. Clicking "Update" runs the CLI.

Recommendation: **B** — it matches the user's request to "highlight update available" (which implies a passive indicator, not an action), and it gives them an explicit Update button. Risk: we have to reproduce the CLI's hashing algorithm. Mitigation: check the `vercel-labs/skills` source for the hashing logic before Phase 4; if it's nontrivial, fall back to A.

### Data Requirements

New fields on `Skill` (all nullable, added in place to `SchemaV1`):

- `lockSource: String?` — e.g. `"imbue-ai/blueprint"`. Truthy ⇔ managed by `npx skills`.
- `sourceURL: String?` — full URL for display + click-to-open.
- `lockInstalledAt: Date?`
- `lockUpdatedAt: Date?`
- `lockHash: String?` — installed folder hash from lock file.
- `upstreamHash: String?` — most-recently-fetched upstream hash; populated by the update check (Phase 4). When `upstreamHash != lockHash`, an update is available.

No new SwiftData model. No `SchemaV2`. If migration becomes necessary later, we can promote to V2 then.

## UI/UX Considerations

- **Source row** sits directly under Location in `SkillHeaderPanel`, same visual treatment: caption-style "Source:" label, monospaced URL, click to open in browser, no copy button (Location already covers that pattern; a second copy button is noise).
- **Update badge in list**: small filled up-arrow in orange after the favorite star. Tooltip "Update available". Same icon (`arrow.up.circle.fill`) used everywhere.
- **Update affordance in detail**: a single "Update" button in the header next to the existing actions, shown only when an update is available. Disabled / spinner while the CLI runs.
- **Install flow stays as it is**: the existing `RegistrySheet` already has agent multi-select; the CLI call replaces the file write. User-visible difference: progress spinner runs slightly longer (npx + git clone), so we keep the existing `isInstalling` state and add output streaming only if the install takes > 5 seconds (otherwise it's noise).
- **Remove**: no UI change. Right-click → Delete still works; it just calls a different code path internally for managed skills. A separate "Managed by skills.sh" passive badge in the header makes the distinction visible without adding a second menu item.

## Integration Points

- **Existing scan trigger** (`FileWatcher` → `SkillScanner.scanAll`) — lock file lives at `~/.agents/.skill-lock.json`; add that one file to the watch list so lock-file edits (CLI run from outside Chops) refresh state.
- **Existing registry install UI** — same sheet, same agent picker; only the install call swaps.
- **Existing scan dedup by resolved path** — already correct for the CLI's symlink layout (canonical file under `~/.agents/skills/<name>`, symlinks from each agent dir).
- **Existing delete UX** — unchanged at the call site; branched at `Skill.deleteFromDisk`.

## Risks and Challenges

1. **Hashing algorithm reproduction.** If we go with proactive update detection (option B above), we need the same hash the CLI computes. Inspecting `vercel-labs/skills` source before Phase 4 will tell us if this is one obvious choice (e.g. SHA-1 over file contents) or a multi-step recipe. Fall back to lazy detection if it's gnarly.
2. **`npx` availability and slowness.** First-time `npx skills add` may take 10+ seconds while npm fetches the CLI. Mitigation: detect the binary location once at startup; if missing, show an actionable "Install Node / npm" prompt in the install sheet instead of failing silently.
3. **Mixed-mode users.** Skills installed by Chops's current direct-write path won't have lock entries. They'll continue to work via the existing direct-delete path. The `lockSource != nil` check is the single boundary; no skill needs to be retroactively migrated.
4. **Agent ID mapping drift.** The `vercel-labs/skills` agent list may add new entries over time. Keep the mapping table in `ToolSource.swift` and treat unknown agents as "skip" (don't pass an unrecognised `-a` flag to the CLI).
5. **Project-scoped lock files.** Chops scans global paths today, so the global lock file is the priority. The same parser handles project lock files (identical schema) — defer scanning per-project lock files until users ask for it. Noted as out of scope for v1.
6. **No tests.** Per CLAUDE.md, validation is manual. Each phase ends with a concrete "run this and observe X" checklist.

## Open Questions

- **CLI hash algorithm** — needs source inspection at the start of Phase 4 to commit to eager-vs-lazy update detection.
- **Project lock files** — surface in v1, or defer? Recommendation: defer; the data model is identical so adding it later is cheap.
- **"Managed by skills.sh" badge** — useful or noisy? Recommendation: include it (small subtle text under Source), so users learn which skills they can't safely delete by `rm -rf`.

## References

- Lock file (live on this machine): `/Users/mando/.agents/.skill-lock.json`
- `npx skills --help` output captured in research session
- skills.sh docs: https://www.skills.sh/docs (sparse — most behaviour learned from CLI + lock file)
- CLI source: https://github.com/vercel-labs/skills
- Chops code references:
  - `Chops/Models/ToolSource.swift` (tool enum + paths)
  - `Chops/Services/SkillScanner.swift:488` (upsert point)
  - `Chops/Models/SchemaVersions.swift` (schema versioning)
  - `Chops/Services/FileWatcher.swift` (watch paths)
  - `Chops/Services/SkillRegistry.swift:311` (current `install` to replace)
  - `Chops/Views/Shared/RegistrySheet.swift:415` (install UI call site)
  - `Chops/Views/Detail/SkillHeaderPanel.swift:58` (Location row — anchor for new Source row)
  - `Chops/Views/Sidebar/SkillListView.swift:373` (`SkillRow` — anchor for update badge)
  - `Chops/Models/Skill.swift:253` (`deleteFromDisk` — branch point)
