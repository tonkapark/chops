# skills.sh-Managed Skills Progress

## Status: Phase 2 - Completed | Next: Phase 3 (Remove via CLI)

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

### Phase 3: Remove via CLI
**Status:** Not Started

#### Tasks
- [ ] Branch `Skill.deleteFromDisk` on `lockSource != nil` — dispatch to `removeViaCLI()`
- [ ] `removeViaCLI()` maps `toolSources` → CLI agent IDs; falls back to `-a "*"` if all unmapped
- [ ] Promote `deleteFromDisk` to `async throws`; update ~2 call sites
- [ ] Manual verify: install via Phase 2 → delete via UI → lock entry gone, symlinks cleaned
- [ ] Manual verify: unmanaged skill still deletes via the existing FileManager path

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 4: Update Detection + Update Button
**Status:** Not Started

#### Tasks
- [ ] Inspect `vercel-labs/skills` source for the `skillFolderHash` algorithm — decide eager (Path B) vs lazy (Path A) detection
- [ ] **Path B (preferred):** add `upstreamHash` + `lastCheckedAt` fields; new `UpdateChecker` service that fetches upstream and computes the matching hash
- [ ] **Path A (fallback):** ship "Check Updates" menu command that runs `npx skills update -g` and parses output
- [ ] `SkillRow`: orange `arrow.up.circle.fill` after favorite star, gated on `skill.hasUpdateAvailable`
- [ ] `SkillHeaderPanel`: Update button shown only when `skill.hasUpdateAvailable`
- [ ] "Check Updates" menu item in `ChopsApp.swift`
- [ ] Manual verify: hand-edit lock hash → badge appears → click Update → badge clears

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

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

## Architectural Decisions

- **Two branch points only.** `SkillRegistry.install` and `Skill.deleteFromDisk` are the only places that distinguish managed vs unmanaged skills. Anywhere else in the code, both kinds of skills look identical.
- **One service per concern.** `LockfileService` is the only thing that reads `.skill-lock.json`; `SkillsCLI` is the only thing that shells out to `npx skills`. No leakage.
- **Additive schema.** All seven new fields land on `SchemaV1` as nullable additions. No `SchemaV2` until something non-additive forces it.
- **No fallbacks.** Phase 2 deletes the direct-write install code entirely — no feature flag, no "old behaviour" toggle.
- **Lock file is read-only from Chops.** The CLI owns writes; Chops observes.
- **Managed status surfaces only in the detail header** (per user direction during planning). No sidebar badges or list-row indicators for managed-ness — those are reserved for the update-available signal in Phase 4, which is a different concern.

## Lessons Learned
(What worked, what didn't, what to do differently)
