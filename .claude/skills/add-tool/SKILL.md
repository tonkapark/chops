---
name: add-tool
description: Add a new AI coding tool to the Chops tool registry. Takes the tool's documentation URL, derives its skill/subagent/command/rule paths from the docs following existing registry patterns, confirms the proposed registry row with the user, then wires the doc and code.
---

Add support for a new tool to Chops by deriving its filesystem contract from the vendor's docs and wiring it into the registry and code — following the patterns already in `docs/feature/library-tools-and-supported-directories.md`.

## Step 1: Gather inputs

Ask the user for:

1. **Tool name** (display name, e.g. "Auggie").
2. **Documentation URL(s)** — the vendor docs for the tool's skills / subagents / commands / rules.

If a docs URL has an `llms.txt` index (e.g. `<host>/llms.txt`), fetch it first to find the specific skills / subagents / rules pages, then fetch those.

## Step 2: Read the existing registry for the pattern

Read `docs/feature/library-tools-and-supported-directories.md` in full so the new row matches the established format exactly:

- **Shared Defaults** (`cliBinaryExists`, `appBundleExists`, `<configHome>`) — reuse these in Detect rather than restating paths.
- A registry row's fields and order: `Detect`, `SkillScan`, `AgentScan`, `RuleScan`, `CreateSkill`, `CreateAgent`, `CreateRule`, `Docs`, `SupportsOpenStandardDiscovery`, optional `Note`.
- Tilde convention: `~/...` = global/home path; no leading `~` = project-relative probe (e.g. `.cursor/skills`).

## Step 3: Scan the docs for the four kinds

From the fetched docs, extract concrete paths for each kind the tool supports. Look for both a **global** (home-dir) and a **project** (repo-relative) location for each:

- **Skills** — directory of `SKILL.md` subfolders (e.g. `~/.tool/skills`, `.tool/skills`).
- **Subagents / agents** — note whether they are **flat** single `.md` files (e.g. `agents/<name>.md`) or **subdirectory** style. Flat → `usesFlatAgentFiles`.
- **Commands** — slash-command dirs, if the tool has them (map to SkillScan like Factory's `commands`, only if the vendor treats them as skill-like).
- **Rules** — rule/memory `.md` dirs (e.g. `~/.tool/rules`, `.tool/rules`).

Also derive:

- **Detect** — app bundle name, CLI binary name, and/or config files that prove the tool is installed.
- **Create paths** — where the new-item sheet should write each kind (usually the global path's `…/skills`, `…/agents`, `…/rules`).
- **SupportsOpenStandardDiscovery** — true if the tool reads the open-standard `~/.agents/skills` location (informational only; see the doc's Open Standard section).

Quote the exact vendor path for each claim. If the docs don't define a kind, omit that row — do not invent paths (e.g. Codex has no standalone agent-file format, so it has no CreateAgent row).

## Step 4: Draft the registry row and confirm

Produce the proposed `### <Tool>` registry row in the exact doc format, plus a short bullet list of the code changes it implies (which `ToolSource` paths, which `projectProbes`, whether it's creatable, flat-agent or not). **Show this to the user and wait for confirmation or edits before writing anything.**

## Step 5: Wire it in (after confirmation)

Follow the registry's own "Add Or Update A Tool" order:

1. `Chops/Models/ToolSource.swift` — add the enum case (in declaration order) and fill `displayName`, `iconName`, `color`, `logoAssetName` (nil if no asset), `listable`, `isInstalled`, `globalPaths`, `globalAgentPaths`, `globalRulePaths`, and `usesFlatAgentFiles`.
2. `Chops/Services/SkillScanner.swift` — add project-relative entries to `projectProbes`.
3. `Chops/Services/SkillParser.swift` — only if the tool needs non-standard parsing.
4. `Chops/Views/Shared/NewSkillSheet.swift` — add the case to the `creatableTools` list for each creatable kind.
5. `Chops/Models/AgentTarget.swift` — only if Global skills should symlink into the tool.
6. `Chops/Services/RemoteServer.swift` — only if remote sync should tag the tool.
7. `docs/feature/library-tools-and-supported-directories.md` — insert the confirmed registry row and bump the `Last verified` date.

## Step 6: Build and verify

- Build: `xcodebuild -scheme Chops -configuration Debug build`.
- Manually verify in the app (per CLAUDE.md "always manually test"): create a temporary fixture skill/agent/rule at each new path (plus a detect marker if the tool isn't installed), relaunch, confirm it appears tagged to the new tool, then **delete the fixture**. To exercise project probes, set the `customScanPaths` UserDefaults key on `com.joshpigford.Chops` — read its prior value first and restore it.
- No fallbacks; keep edits direct (per CLAUDE.md).

See `tool-registry-audit` for the inverse skill: validating the registry against the code after the fact.
