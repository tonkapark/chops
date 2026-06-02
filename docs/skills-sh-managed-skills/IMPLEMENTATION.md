# skills.sh-Managed Skills Implementation Plan

## Overview

Wire Chops to recognise skills installed by the `npx skills` CLI and route their lifecycle (install / remove / update) through that CLI instead of direct filesystem operations. Each phase ends with something a user can open the app and *see* working — no dead infrastructure phases.

The design hinges on one principle from the user's brief: **avoid creating too many paths through the code.** The pattern throughout is "branch at one boundary, share the call site." Specifically:

- A single `LockfileService` is the only thing that knows about `skill-lock.json`.
- A single `SkillsCLI` is the only thing that shells out to `npx skills`.
- `SkillRegistry.install` and `Skill.deleteFromDisk` become the single branch points; the UI calling them doesn't change.
- One additive schema bump (nullable fields on `SchemaV1`) — no `SchemaV2` unless something non-additive forces it later.

## Prerequisites

- `npx` resolvable on the user's machine (already true for the developer; we'll add a friendly error path in Phase 2 for users without it).
- `xcodegen` installed (already noted in CLAUDE.md).
- Lock file present at `~/.agents/.skill-lock.json` for manual verification (already present on this machine — 14 entries).

## Phase Summary

1. **Detect + display** — Parse the lock file, attach metadata during the scan, show a Source row in the detail header. *User sees: source URL appears under Location for managed skills. Nowhere else in the UI changes.*
2. **Install via CLI** — Replace `SkillRegistry.install` with `SkillsCLI.add`. *User sees: installing from the registry sheet runs `npx skills add` in the background; the new skill appears with its source URL filled in.*
3. **Remove via CLI** — Branch `Skill.deleteFromDisk` so managed skills route to `npx skills remove`. *User sees: deleting a managed skill from the UI cleans up the lock file too — verifiable with `cat ~/.agents/.skill-lock.json`.*
4. **Update detection + Update button** — Compare lock-file hash to upstream, badge stale skills, add an Update button that runs `npx skills update`. *User sees: an orange up-arrow on skills with newer upstream; clicking Update refreshes them.*

---

## Phase 1: Detect + Display Managed Skills

### Objective

Surface "this skill was installed via `npx skills`" everywhere it matters: a Source row in the detail header (clickable to open the upstream URL) and a subtle "Managed by skills.sh" hint. No CLI invocation yet — purely read-side.

### Rationale

This is the smallest end-to-end slice that proves the data model + scanner integration is right. Once the user can open a skill and see its source, every later phase has a verifiable feedback loop ("the source still shows after I update"). It also de-risks the schema decision before we touch any code that writes.

### Tasks

- [ ] Add nullable fields to `Skill` in `SchemaV1` (`SchemaVersions.swift`): `lockSource: String?`, `sourceURL: String?`, `lockInstalledAt: Date?`, `lockUpdatedAt: Date?`, `lockHash: String?`. Confirm SwiftData handles the additive migration automatically against the live store at `~/Library/Application Support/Chops/Chops.store`.
- [ ] Create `Chops/Services/LockfileService.swift` — one type with one method: `load() -> [String: LockEntry]` keyed by skill name. Reads `~/.agents/.skill-lock.json`, decodes the `skills` dict, returns the entries. Silent empty-map on missing file or parse error (we are not the enforcement layer — the CLI is).
- [ ] In `SkillScanner.applyResults()` (line ~488), call `LockfileService.load()` once at the top of the upsert loop. For each scanned skill, if its canonical name matches a lock key AND its canonical path is `~/.agents/skills/<name>/SKILL.md`, copy the five lock fields onto the SwiftData row. Clear the fields if the lock entry has disappeared (so demoting from managed → unmanaged works).
- [ ] Add `~/.agents/.skill-lock.json` to the watch list in `ContentView.swift` (where `allPaths` is assembled around line ~84) so external CLI runs trigger a rescan.
- [ ] In `Chops/Views/Detail/SkillHeaderPanel.swift`, add a `sourceRow` directly under `locationRow` (~line 83). Visual treatment mirrors Location: caption "Source:" label, monospaced URL truncated like Location, click opens in browser via `NSWorkspace.shared.open(url)`. Render only when `skill.sourceURL != nil`. This is the **only** place the managed-skill distinction surfaces — no badges, no labels, no indicators anywhere else in the UI.
- [ ] Manual verify: build, launch, open a skill known to be in the lock file (e.g. `blueprint`, `ai-seo`) → Source row appears with clickable URL. Open an unmanaged skill → no Source row. Confirm nothing else in the UI (sidebar rows, list, etc.) changes appearance based on managed status.

### Success Criteria

- A skill listed in `~/.agents/.skill-lock.json` shows its `sourceUrl` in the detail header, click opens the GitHub repo.
- A skill not in the lock file shows no Source row.
- Editing the lock file by hand (e.g. removing an entry) and saving triggers a rescan within ~0.5s (the existing FileWatcher debounce) and the Source row disappears.
- No crashes on missing lock file (e.g. fresh user who's never run `npx skills`).

### Files Likely Affected

- `Chops/Models/SchemaVersions.swift` — add fields to `SchemaV1.Skill`.
- `Chops/Services/LockfileService.swift` — **new**, ~50 lines.
- `Chops/Services/SkillScanner.swift` — annotate upsert path.
- `Chops/App/ContentView.swift` — extend watch paths.
- `Chops/Views/Detail/SkillHeaderPanel.swift` — `sourceRow` view only.

---

## Phase 2: Install via CLI

### Objective

Replace `SkillRegistry.install`'s direct file write with a `npx skills add` invocation. The user-facing install flow in the registry sheet doesn't change — same agent multi-select, same loading state — but under the hood, lock-file truth is established by the CLI itself.

### Rationale

This is the highest-value swap: every new install from this point forward becomes properly managed, so users naturally accumulate metadata that Phase 1 surfaces. Doing it after Phase 1 means the result is visible the moment install finishes — the new skill shows up with its Source row already populated. Order matters here.

### Tasks

- [ ] Create `Chops/Services/SkillsCLI.swift`. One actor (or `@MainActor` class) with the subprocess pattern lifted from `SSHService.swift:130–165`. Public surface:
  - `func add(source: String, skillId: String, agents: [String]) async throws -> String`
  - `func remove(name: String, agents: [String]) async throws -> String`
  - Internal `func run(args: [String]) async throws -> String` that resolves `npx` via the same probe pattern as `ToolSource.cliBinaryURL()`, runs with `-g -y` always set, streams stdout/stderr to one combined buffer, throws on non-zero exit with the buffer as the error message.
- [ ] Add `static let agentIdForSkillsCLI: [ToolSource: String]` to `ToolSource.swift` covering the cases the skills CLI knows about (`.claude → "claude-code"`, `.codex → "codex"`, `.cursor → "cursor"`, `.opencode → "opencode"`, `.windsurf → "windsurf"`, `.factory → "droid"`, `.pi → "pi"`, `.amp → "amp"`, `.antigravity → "antigravity"`, plus `.zed` if/when added). Any tool not in the map is filtered out before passing `-a` flags.
- [ ] Rewrite `SkillRegistry.install` (line 311) as `func install(source: String, skillId: String, agents: [AgentTarget]) async throws` that delegates entirely to `SkillsCLI.add`. **Delete** the canonical-write + symlink loop — the CLI owns that now. Map `AgentTarget` to CLI agent IDs via the new table; throw if no targets are recognised.
- [ ] Update the install call site in `Chops/Views/Shared/RegistrySheet.swift:415` (`performInstall`) to `try await registry.install(...)`. Pass `source` and `skillId` from the `RegistrySkill` (already on the model). Keep the existing `isInstalling` spinner + `.customScanPathsChanged` post.
- [ ] Add `npx`-missing detection: if `SkillsCLI.run` can't find a binary, throw a typed error that the sheet renders as "Install Node / npm to use this feature" (link to nodejs.org).
- [ ] If install takes > 5 seconds, surface the CLI output in the sheet (single scrolling text region). Below the threshold, keep the existing minimal spinner. (Implementation: collect stdout into a `@Published` string, show conditionally.)
- [ ] Manual verify: open registry sheet → install a skill (e.g. one from `vercel-labs/agent-skills` you don't already have) → after install completes, the skill appears in the library with Source row populated (proves Phase 1 + Phase 2 wire together). Run `cat ~/.agents/.skill-lock.json` → new entry present.

### Success Criteria

- Installing a skill from the registry creates a lock-file entry and a populated Source row in the detail view.
- Installing while only `.claude` agent is selected results in a symlink only in `~/.claude/skills/`, mirroring `npx skills add` behaviour.
- Missing `npx` is surfaced as a clear error in the sheet, not a silent failure.
- The old direct-write code path is gone — no fallback, no toggle.

### Files Likely Affected

- `Chops/Services/SkillsCLI.swift` — **new**, ~120 lines.
- `Chops/Models/ToolSource.swift` — agent-ID map.
- `Chops/Services/SkillRegistry.swift` — `install` rewritten, old code deleted.
- `Chops/Views/Shared/RegistrySheet.swift` — `await` call site, error rendering, optional output streaming.

---

## Phase 3: Remove via CLI

### Objective

When the user deletes a managed skill from Chops, route through `npx skills remove` so the lock file and all symlinks update correctly. Unmanaged skills continue down the existing FileManager path.

### Rationale

Closes the symmetry of Phase 2 — managed skills now have a fully managed lifecycle. Deferring this past Phase 2 would let users accumulate orphan lock entries (delete from Chops, but lock still references the deleted name). Doing it now keeps the system consistent end-to-end.

### Tasks

- [ ] In `Chops/Models/Skill.swift:253` (`deleteFromDisk`), branch at the top: if `lockSource != nil`, dispatch to a new `removeViaCLI()` path; otherwise run the existing FileManager logic. The UI calling `deleteFromDisk` doesn't change.
- [ ] `removeViaCLI()` builds the agent list from `self.toolSources` (mapped through `ToolSource.agentIdForSkillsCLI`), calls `SkillsCLI.remove(name: self.name, agents: ...)`, then awaits a single rescan tick. If `toolSources` is empty or all unmapped, fall back to `-a "*"` — the CLI will figure it out.
- [ ] `Skill.deleteFromDisk` is currently synchronous; make `removeViaCLI` synchronous wrapper around `SkillsCLI.remove` by hopping through a semaphore-backed `Task` **only if necessary**. Preferred: promote `deleteFromDisk` to `async throws` and update the ~2 call sites. Cleaner code, no semaphore hack.
- [ ] Manual verify: install a skill via the registry sheet (Phase 2 proven), then delete it via the context menu → confirm the entry vanishes from `~/.agents/.skill-lock.json` and the symlinks in tool dirs are gone.
- [ ] Also verify: an unmanaged skill (one without a `lockSource`) still deletes via the old path, untouched.

### Success Criteria

- Deleting a managed skill removes its lock entry and all installed symlinks. `npx skills list -g` no longer reports it.
- Deleting an unmanaged skill works exactly as it did before.
- Error from the CLI (e.g. skill name disagreement) surfaces as an alert in the UI; the SwiftData row is not deleted if the CLI failed.

### Files Likely Affected

- `Chops/Models/Skill.swift` — branch in `deleteFromDisk`, possibly making it `async`.
- `Chops/Services/SkillsCLI.swift` — exercise the `remove` method added in Phase 2.
- Any view calling `deleteFromDisk` — likely `Chops/Views/Sidebar/SkillListView.swift` around line 152.

---

## Phase 4: Update Detection + Update Button

### Objective

Show an "update available" badge on managed skills whose upstream has moved, plus a one-click Update button in the detail header that runs `npx skills update <name>`.

### Rationale

This is the part the user explicitly asked for ("if skill-lock detected for a skill, support highlighting update available"). It comes last because it depends on the schema (Phase 1) and the CLI helper (Phase 2). It's also the only phase with a real research question — see Tasks.

### Tasks

- [ ] **Inspect `vercel-labs/skills` source first.** Find the function that computes `skillFolderHash`. We need to know: which files are included, hash algorithm (SHA-1? SHA-256?), whether folder structure or just file contents are hashed. If it's straightforward, reproduce it locally. If it's nontrivial, pivot to the lazy approach below.
- [ ] **Path B (preferred — eager hash compare):**
  - Add `upstreamHash: String?` and `lastCheckedAt: Date?` to `Skill` (same SchemaV1, additive).
  - New `UpdateChecker` service. Periodic + on-demand: for each managed skill, fetch the upstream `SKILL.md` (or whatever the hash algorithm includes) via existing GitHub raw fetch in `SkillRegistry`, compute the matching hash, write to `upstreamHash`. Default check interval: once on launch, then on a manual "Check Updates" command.
  - Computed `var hasUpdateAvailable: Bool { upstreamHash != nil && lockHash != nil && upstreamHash != lockHash }`.
- [ ] **Path A (fallback — lazy CLI call):** if reproducing the hash is messy, ship a manual "Check Updates" menu command that runs `npx skills update -g` and parses the `Found N update(s)` line to mark skills with an `availableUpdate: Bool` flag. Updates happen as part of the check — no separate "Update" button needed. Worse UX, simpler code.
- [ ] In `Chops/Views/Sidebar/SkillListView.swift:373` (`SkillRow`), add a single `Image(systemName: "arrow.up.circle.fill")` in orange after the favorite star, gated on `skill.hasUpdateAvailable`. Tooltip: "Update available".
- [ ] In `Chops/Views/Detail/SkillHeaderPanel.swift`, add an "Update" button in the header action row (where existing actions live), shown only when `skill.hasUpdateAvailable`. Click runs `SkillsCLI.update(names: [skill.name])`; spinner while running; rescan after.
- [ ] Add a "Check Updates" menu item under the existing menu structure (likely in `ChopsApp.swift` commands) that triggers a global `UpdateChecker.checkAll()` pass.
- [ ] Manual verify: edit the lock file by hand to set `skillFolderHash` to an obviously-wrong value for one skill, trigger a rescan + check → orange badge appears on the SkillRow, Update button appears in detail header, click → skill updates, badge clears.

### Success Criteria

- Skills with a newer upstream than what the lock file records are visually flagged in both the list and the detail view.
- Clicking Update successfully runs `npx skills update <name>` and the badge clears on next scan.
- "Check Updates" command surfaces results without freezing the UI (background task).
- No badge / button on unmanaged skills.

### Files Likely Affected

- `Chops/Models/SchemaVersions.swift` — `upstreamHash`, `lastCheckedAt` additive fields.
- `Chops/Services/UpdateChecker.swift` — **new**, ~80 lines (Path B) or ~30 lines (Path A).
- `Chops/Services/SkillsCLI.swift` — `update` method.
- `Chops/Views/Sidebar/SkillListView.swift` — badge.
- `Chops/Views/Detail/SkillHeaderPanel.swift` — Update button.
- `Chops/App/ChopsApp.swift` — "Check Updates" command.

---

## Post-Implementation

- [ ] Update `CLAUDE.md` with the new `LockfileService` / `SkillsCLI` services and how install/remove now work.
- [ ] Manual test matrix: install → detect badge after edit → remove → verify lock file at each step.
- [ ] If Path A was chosen in Phase 4 due to hash complexity, note the deferred work in `docs/notes.md` so a future pass can revisit eager detection.

## Notes

- **One branch point per operation.** The whole plan rests on `SkillRegistry.install` and `Skill.deleteFromDisk` being the only places that know about the managed/unmanaged distinction. If you find yourself adding the same `if lockSource != nil` check at a third site, stop and refactor — the abstraction is leaking.
- **Lock file is read-only from Chops.** We never write to `~/.agents/.skill-lock.json` directly. The CLI owns it; we observe it. If something we want needs us to write, that's a sign we're working against the grain.
- **Schema strategy.** All five Phase-1 fields and the two Phase-4 fields go onto `SchemaV1` as nullable additions. SwiftData handles the lightweight migration; no `SchemaV2` until something non-additive forces it. If we add anything stricter later (non-nullable, renamed, type-changed), promote to V2 *then*, with a proper migration stage.
- **Per CLAUDE.md, no tests** — every phase ends with a manual verify step. Don't skip it.
- **Per CLAUDE.md, no fallbacks** — the rewrite in Phase 2 deletes the direct-write code path entirely. No feature flag, no `if oldBehavior {...}`. If we need the old behaviour back, we revert the commit.
