# skills.sh-Managed Skills Progress

## Status: Phase 4 - In Progress (awaiting manual verify) | Feature near-complete

## Quick Reference
- Research: `docs/skills-sh-managed-skills/RESEARCH.md`
- Implementation: `docs/skills-sh-managed-skills/IMPLEMENTATION.md`

---

## Phase Progress

### Phase 1: Detect + Display Managed Skills
**Status:** Completed

#### Tasks
- [x] Add nullable fields to `SchemaV1.Skill` (`lockSource`, `sourceURL`, `lockInstalledAt`, `lockUpdatedAt`, `lockHash`)
- [x] Create `Chops/Services/LockfileService.swift` — `loadGlobal()` reading `~/.agents/.skill-lock.json`
- [x] `SkillScanner.applyResults()` attaches lock fields to upserted skills (and clears them when removed from lock)
- [x] Add `~/.agents/.skill-lock.json` to `ContentView` watch paths
- [x] `SkillHeaderPanel.swift`: added `sourceRow` directly under `locationRow` (only place managed status is visible)
- [x] Manual verify (user confirmed 2026-06-02): lock-file skill shows Source row; unmanaged skill does not; nothing else in UI differs

#### Decisions Made
- LockfileService is a typed `enum` namespace (not an instance), since it holds no state and the lock file path is fixed.
- The CLI writes timestamps with fractional seconds, which Foundation's `.iso8601` strategy rejects. Added a custom decoder that accepts both formats — silent failure to parse a lock entry would have caused the whole file to skip silently and looked like "no managed skills found".
- Source row hides scheme and trailing `.git` for display (`github.com/imbue-ai/blueprint`), opens the cleaned URL in a browser, full URL shown on hover via `.help`.
- Lock entries match Chops skills by **canonical path** (`~/.agents/skills/<name>/SKILL.md`), not by name — robust against any future skill that happens to share a name with a lock entry but live elsewhere.

#### Blockers
- (none)

---

### Phase 2: Install via CLI
**Status:** Completed

#### Tasks
- [x] Create `Chops/Services/SkillsCLI.swift` with `add` / `remove` / `run` (resolves `npx` via asdf shims + `cliBinaryURL`, runs `-g -y`, returns combined stdout/stderr, strips ANSI, throws on non-zero exit)
- [x] Skip the `ToolSource.agentIdForSkillsCLI` mapping — `AgentTarget.id` already uses skills.sh CLI identifiers
- [x] Rewrite `SkillRegistry.install` as `async throws` delegating to `SkillsCLI.add` — old canonical-write + symlink loop deleted
- [x] Update `RegistrySheet.performInstall` call site to `await` the new install
- [x] Add `npx`-missing typed error with actionable message in the sheet
- [x] Strip agent-detection env vars (`AI_AGENT`, `CLAUDECODE`, `CURSOR_*`, etc.) before spawning so `-y` doesn't silently route to the calling agent
- [x] Highlight newly-installed skill in library (`pendingSkillSelectionPath` in AppState, resolved by `.onChange(of: skills.count)` in ContentView, force-switches sidebar filter to `.allSkills`)
- [x] Remove agent checkboxes from RegistrySheet; install always runs globally and lets the CLI auto-detect target agents
- [x] Enlarge skill content preview to fill freed vertical space; sheet now 620pt tall
- [x] ~~Stream CLI output if install > 5s~~ deferred — error states + spinner cover the install UX without adding a conditional view path
- [x] Manual verify (user confirmed): install from registry → new skill appears + auto-selected with Source row populated → lock file shows new entry

#### Decisions Made
- **Universal vs symlinked agents**: skills.sh distinguishes "universal" agents (Cursor, Codex, Zed — read directly from `~/.agents/skills/`) from "symlinked" agents (Claude Code, OpenCode — get a per-agent dir symlink). `-a cursor` does not create a per-agent dir, by design. Per-agent install UI was therefore misleading — replaced with one Install button that defers entirely to the CLI's auto-detection.
- **Env sanitization is mandatory.** The CLI reads `AI_AGENT`, `CLAUDECODE`, `CURSOR_*`, `CODEX_*`, `OPENCODE_*` etc. as "auto-detected calling agent" and silently overrides `-a` flags when set. Chops inherits these from whichever shell launched it, so we strip them before every subprocess.
- **`AgentTarget.id` already matches the CLI's agent IDs** (`claude-code`, `codex`, `cursor`, …) — no ToolSource mapping table needed.
- **Highlight uses `skills.count`**, not `skills` itself, because SwiftData `@Query` updates model instances in place without changing array identity. Count is monotonic enough to detect inserts.
- **Sheet auto-switches to `.allSkills` filter on install** so the highlight target is always in the visible filter.

#### Blockers
- (none)

---

### Phase 2a: Disable CLI Telemetry (opt-in)
**Status:** In Progress (awaiting manual verify)

#### Tasks
- [x] Add `disableSkillsCLITelemetry` UserDefaults-backed accessor on `ChopsSettings`
- [x] Add "Disable npx skills telemetry" Toggle to `SettingsView.generalSettings`, backed by `@AppStorage("disableSkillsCLITelemetry")`
- [x] Inject `DISABLE_TELEMETRY=1` in `SkillsCLI.sanitizedEnvironment()` when the setting is true
- [ ] Manual verify: toggle on → install a skill → confirm setting persists across relaunches

#### Decisions Made
- Toggle is **opt-in** (default false) — Chops does not silently disable a documented CLI default. Mirrors the CLI's own behaviour when the flag is unset.
- The flag is read **at subprocess time** (not cached), so flipping it takes effect on the very next install/remove/update — no relaunch needed.
- The env variable is only set when enabled. When disabled we don't pass `DISABLE_TELEMETRY=0` either, so the CLI's default kicks in unmodified.

#### Blockers
- (none)

---

### Phase 3: Remove via CLI
**Status:** In Progress (awaiting manual verify)

#### Tasks
- [x] Branch `Skill.deleteFromDisk` on `lockSource != nil` — dispatch to `SkillsCLI.remove`
- [x] Pass empty `agentIds` (no `-a`) — verified that `npx skills remove <name> -g -y` cleanly removes from every detected agent and the lock entry
- [x] Promote `deleteFromDisk` to `async throws`
- [x] Wrap the three call sites (`SkillListView.deleteSkill`, `SkillListView.deleteSkills`, `SkillDetailView.deleteSkill`) in `Task { @MainActor in ... }`
- [ ] Manual verify: install a managed skill → delete via UI → lock entry gone, symlinks cleaned
- [ ] Manual verify: unmanaged skill still deletes via existing FileManager path

#### Decisions Made
- **Lock key from `resolvedPath`**, not `skill.name`. The canonical path is `~/.agents/skills/<key>/SKILL.md`, so the parent dir name is authoritative. `skill.name` is sourced from frontmatter and could drift from the lock key over time.
- **Empty `agentIds` for remove** — `npx skills remove <name> -g -y` (no `-a`) cleanly removes from every detected agent. Tested: "Targeting 56 potential agent(s)" → "Successfully removed". Pre-Phase-3 the code had a `-a "*"` fallback (already deleted in Phase 2 since the CLI rejects `*` for remove).
- **`Task { @MainActor in ... }` at every call site** rather than `await MainActor.run` inside an unstructured Task. The view methods are already MainActor-isolated, so explicit `@MainActor` on the new Task closure keeps the body in the same context — no actor hops, model context stays valid across the await.

#### Blockers
- (none)

---

### Phase 4: Update Detection + Update Button
**Status:** In Progress (awaiting manual verify)

#### Tasks
- [x] Inspect `vercel-labs/skills` source for the `skillFolderHash` algorithm — decided **Path B (eager hash compare)**
- [x] Add `upstreamHash` + `lastUpstreamCheckedAt` fields to `SchemaV1.Skill`; `hasUpdateAvailable` computed property
- [x] New `UpdateChecker` service: fetches GitHub Trees API per source (batched), looks up folder SHA, stores in `upstreamHash`. `main` branch with `master` fallback
- [x] `SkillsCLI.update(names:)`
- [x] `SkillRow`: orange `arrow.up.circle.fill` after favorite star, gated on `skill.hasUpdateAvailable`
- [x] `SkillHeaderPanel`: Update button shown only when `hasUpdateAvailable`. Runs `SkillsCLI.update`, clears `upstreamHash` on success, triggers rescan
- [x] "Check for Skill Updates" menu command in `ChopsApp.swift` (separate from Sparkle's own "Check for Updates…")
- [x] On-launch check via `UpdateChecker.checkAll(in:)` in `ContentView.startScanning`, throttled by 4-hour staleness window
- [ ] Manual verify: hand-edit lock hash → trigger Check Updates → badge appears → click Update → badge clears

#### Decisions Made
- **Path B (eager hash compare) wins.** Source inspection of `vercel-labs/skills/src/blob.ts:getSkillFolderHashFromTree` shows the hash is just the GitHub tree SHA for the skill's folder. No bespoke hash algorithm to reimplement — one Trees API call per source repo, plus a lookup in the recursive tree response.
- **Per-source batching.** Skills grouped by `lockSource` so each repo's tree is fetched exactly once per check, even if 12 skills come from the same repo. Default GitHub unauthenticated quota (60 req/h) then covers 60 distinct upstream repos per hour, which is plenty.
- **6-hour staleness window on launch checks.** Avoids burning rate quota on every relaunch; Force-trigger via "Check for Skill Updates" menu bypasses the window.
- **Update name uses the canonical directory name, not `skill.name`.** Same robustness argument as Phase 3's remove: frontmatter `name:` can drift; the lock key is the truth.
- **Post-update we clear `upstreamHash`, not set it equal to lockHash.** The badge clears immediately (hasUpdateAvailable = false when upstreamHash nil), and the next check re-populates with current truth. Cleaner than reasoning about cached vs newly-pulled state.

#### Blockers
- (none)

---

## Session Log

### 2026-06-02
- Wrote RESEARCH.md (lock file location + schema verified from live `~/.agents/.skill-lock.json`; CLI behaviour verified via `npx skills --help` and `npx skills list -g`)
- Wrote IMPLEMENTATION.md with 4 medium phases
- User edit: Phase 1 scope tightened — managed-skill metadata appears **only** in the detail header Source row; no badges, labels, or sidebar indicators
- Phase 4's hash-vs-lazy decision deferred to start of phase (needs upstream source inspection)
- **Phase 1 completed.** Lock metadata wired through scan → schema → header. User confirmed visually in dev build.
- **Phase 2 completed.** Install path rewritten via `SkillsCLI`. Initial test surfaced two problems: the CLI's universal-vs-symlinked agent model made per-agent checkboxes misleading, and the inherited shell's `AI_AGENT` env var was silently forcing every install to claude-code. Fixed by stripping the env, removing the checkboxes entirely, defaulting to global install, enlarging the preview, and switching to `.allSkills` filter post-install so the auto-highlight is always visible.
- **Phase 2a in progress.** Added opt-in "Disable npx skills telemetry" toggle under Settings → General. When on, `DISABLE_TELEMETRY=1` is injected into every `npx skills` subprocess via the existing `sanitizedEnvironment` path. Awaiting visual verification.

---

## Files Changed

**Phase 1:**
- `Chops/Models/SchemaVersions.swift` — added 5 nullable lock fields to `SchemaV1.Skill`
- `Chops/Services/LockfileService.swift` — **new**, ~55 lines
- `Chops/Services/SkillScanner.swift` — `applyResults` now loads + applies lock metadata per-skill (`lockEntriesByCanonicalPath`, `applyLockMetadata`)
- `Chops/App/ContentView.swift` — `~/.agents/.skill-lock.json` added to `FileWatcher` paths
- `Chops/Views/Detail/SkillHeaderPanel.swift` — new `sourceRow`, `sourceLinkURL`, `displaySourceURL`

**Phase 2:**
- `Chops/Services/SkillsCLI.swift` — **new**, ~90 lines. `add` / `remove` / `run`, env sanitization, ANSI stripping, asdf-shim probe
- `Chops/Services/SkillRegistry.swift` — `install(skill:)` rewritten as `async throws`, old canonical-write code deleted, two unused `RegistryError` cases removed
- `Chops/Views/Shared/RegistrySheet.swift` — agent checkboxes removed, preview enlarged, install awaits CLI, sets `pendingSkillSelectionPath`, forces `.allSkills` filter, sheet height 500→620
- `Chops/App/AppState.swift` — added `pendingSkillSelectionPath`
- `Chops/App/ContentView.swift` — `.onChange(of: skills.count)` resolves pending selection

**Phase 2a:**
- `Chops/Models/ChopsSettings.swift` — added `disableSkillsCLITelemetry` UserDefaults accessor
- `Chops/Views/Settings/SettingsView.swift` — Toggle in General tab, bound via `@AppStorage`
- `Chops/Services/SkillsCLI.swift` — `sanitizedEnvironment` injects `DISABLE_TELEMETRY=1` when the setting is true

**Phase 3:**
- `Chops/Models/Skill.swift` — `deleteFromDisk` is now `async throws`; managed skills dispatch to `SkillsCLI.remove`
- `Chops/Views/Sidebar/SkillListView.swift` — `deleteSkill` and `deleteSkills` wrap in `Task { @MainActor in ... }`
- `Chops/Views/Detail/SkillDetailView.swift` — `deleteSkill` wraps in `Task { @MainActor in ... }`

**Phase 4:**
- `Chops/Models/SchemaVersions.swift` — added `upstreamHash`, `lastUpstreamCheckedAt`
- `Chops/Models/Skill.swift` — `hasUpdateAvailable` computed
- `Chops/Services/UpdateChecker.swift` — **new**, ~140 lines: GitHub Trees fetch, per-source batching, main→master fallback
- `Chops/Services/SkillsCLI.swift` — `update(names:)` wrapper
- `Chops/Views/Sidebar/SkillListView.swift` — orange update badge after favorite star
- `Chops/Views/Detail/SkillHeaderPanel.swift` — Update button + alert; clears `upstreamHash` on success
- `Chops/App/ChopsApp.swift` — "Check for Skill Updates" command alongside Sparkle's
- `Chops/App/ContentView.swift` — on-launch `UpdateChecker.checkAll` (throttled inside)

## Architectural Decisions

- **Two branch points only.** `SkillRegistry.install` and `Skill.deleteFromDisk` are the only places that distinguish managed vs unmanaged skills. Anywhere else in the code, both kinds of skills look identical.
- **One service per concern.** `LockfileService` is the only thing that reads `.skill-lock.json`; `SkillsCLI` is the only thing that shells out to `npx skills`. No leakage.
- **Additive schema.** All seven new fields land on `SchemaV1` as nullable additions. No `SchemaV2` until something non-additive forces it.
- **No fallbacks.** Phase 2 deletes the direct-write install code entirely — no feature flag, no "old behaviour" toggle.
- **Lock file is read-only from Chops.** The CLI owns writes; Chops observes.
- **Managed status surfaces only in the detail header** (per user direction during planning). No sidebar badges or list-row indicators for managed-ness — those are reserved for the update-available signal in Phase 4, which is a different concern.

## Lessons Learned
(What worked, what didn't, what to do differently)
