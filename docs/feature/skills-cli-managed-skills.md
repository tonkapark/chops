# skills.sh-Managed Skills

Chops delegates the full lifecycle of skills installed from the registry —
install, remove, update, version detection — to the **`npx skills` CLI**
(skills.sh). The CLI owns the lock file and the per-agent file layout; Chops
observes the result and surfaces it. Driven by the
[Discover / Browse Registry](skills-discovery.md) sheet.

## Setup

- **Node + npm** must be installed. Chops resolves `npx` via the same probe as
  other CLI tools, including `~/.asdf/shims/npx` for asdf-managed Node. Missing
  `npx` surfaces as an actionable error in the install sheet — no silent
  failure.
- Optional opt-out: **Settings → General → Disable npx skills telemetry**
  injects `DISABLE_TELEMETRY=1` into every CLI subprocess. Default off; the
  toggle is read per-call so flipping it takes effect on the next action
  without relaunching.

## Lifecycle

| Action | Command | UI entry point |
|---|---|---|
| Install | `npx skills add <source> -g -s <skillId> -y` | Registry sheet → **Install** |
| Remove | `npx skills remove <name> -g -y` | Library context menu or detail-view **Delete** (for managed skills only) |
| Update | `npx skills update <name> -g -y` | Detail-header **Update** button (only when badge is showing) |
| Check upstream | GitHub Trees API | App menu → **Check for Skill Updates** |

Every subprocess runs with a **sanitised environment**: `AI_AGENT`,
`CLAUDECODE`, `CURSOR_*`, `CODEX_*`, `WINDSURF_*`, `OPENCODE_*`, `CLINE`, `ZED`,
`AMP` are stripped so the CLI's "auto-detected calling agent" cannot override
the `-a` flags Chops passes (or doesn't).

## What users see

- **Source row** in the detail header, directly under Location. Shows
  `github.com/owner/repo`; clicking opens the upstream URL. Visible only for
  managed skills — the only UI surface for "this came from the registry".
- **Orange up-arrow badge** in the library row (and matching **Update** button
  in the header) when the upstream tree SHA differs from the installed
  `skillFolderHash`.
- **`npx skills add …` preview** alongside the Install button in the registry
  sheet — the exact command Chops will run.

## Design decisions

**One source of truth: the CLI.** Chops never writes to `.skill-lock.json`;
it reads it on every scan and on every upstream check. Every state-changing
action is a CLI invocation. This keeps Chops in lockstep with whatever the
user does outside the app.

**Branch at one boundary per operation.** `SkillRegistry.install`,
`Skill.deleteFromDisk`, and `SkillHeaderPanel.runUpdate` are the only places
that distinguish managed vs unmanaged skills. The rest of the UI treats both
the same.

**No per-agent install picker.** The CLI splits target agents into
*universal-mode* (Cursor, Codex, Zed, …) which all read directly from
`~/.agents/skills/`, and *symlinked-mode* (Claude Code, OpenCode, …) which get
a per-agent dir symlink. Asking the user to pick agents wasn't honest UX —
universal agents share the canonical location regardless. Chops installs
globally with auto-agent detection and lets the CLI decide.

**Update detection: GitHub Trees API.** Chops fetches
`/repos/<source>/git/trees/<main|master>?recursive=1` once per source repo
per check (batched by source), then looks up the tree entry whose `path`
matches the skill's folder. The entry's `sha` is the upstream
`skillFolderHash` — same algorithm the CLI itself uses in
`getSkillFolderHashFromTree`. **No bespoke hashing.**

**Throttled checks.** The on-launch upstream check skips skills with a
`lastUpstreamCheckedAt` newer than 6 hours. The menu command forces a fresh
check. The 60-call/hour unauthenticated GitHub rate limit then covers 60
distinct source repos per hour — plenty for any realistic skill collection.

**Two-tier lock watching.** `FileWatcher` watches both `~/.agents/` (catches
file creation, rename, delete) and `~/.agents/.skill-lock.json` itself
(catches in-place truncate-and-write edits that the parent-dir watch misses).
A forced `UpdateChecker` run also re-reads the lock from disk, so manual
edits land in SwiftData even if FileWatcher debounce timing falls badly.

**Additive schema.** Seven nullable fields live on `SchemaV1.Skill`
(`lockSource`, `sourceURL`, `lockInstalledAt`, `lockUpdatedAt`, `lockHash`,
`upstreamHash`, `lastUpstreamCheckedAt`). No `SchemaV2`; SwiftData handles
the lightweight migration automatically.

## Where things live

| Concern | File |
|---|---|
| Lock file read | `Chops/Services/LockfileService.swift` |
| CLI wrapper | `Chops/Services/SkillsCLI.swift` |
| Upstream check | `Chops/Services/UpdateChecker.swift` |
| Install call site | `Chops/Views/Shared/RegistrySheet.swift` |
| Delete branch | `Chops/Models/Skill.swift` (`deleteFromDisk`) |
| Source row + Update button | `Chops/Views/Detail/SkillHeaderPanel.swift` |
| Update badge | `Chops/Views/Sidebar/SkillListView.swift` (`SkillRow`) |
| "Check for Skill Updates" menu | `Chops/App/ChopsApp.swift` |
| Telemetry toggle | `Chops/Views/Settings/SettingsView.swift` |
