---
name: tool-registry-audit
description: Audit the tool registry doc against the code — compare documented detect/scan/create paths to ToolSource and SkillScanner, list divergences, and ask how to resolve each.
---

Validate that `docs/feature/library-tools-and-supported-directories.md` (the tool registry, the stated implementation contract) matches the actual code. Find every place the doc and code disagree, then resolve each with the user.

## Step 1: Read the tool registry

Read the **entire** file `docs/feature/library-tools-and-supported-directories.md` with one clean read (not snippets). For each tool row, note the documented:

- **Detect** — install markers (app bundle, CLI binary, config files)
- **SkillScan / AgentScan / RuleScan** — global (`~/...`) and project-relative (no `~`) paths
- **CreateSkill / CreateAgent / CreateRule** — where the new-item sheet writes
- **Notes** — flat-agent, rule-only, or "scanned but not creatable" exceptions

Tilde convention: a leading `~/` means a home/global path; no leading `~` means a project-relative probe (e.g. `.cursor/skills`).

## Step 2: Compare to the code

Read these and diff each doc claim against what the code actually does:

- `Chops/Models/ToolSource.swift`
  - `isInstalled` ← Detect
  - `globalPaths` ← global SkillScan
  - `globalAgentPaths` ← global AgentScan
  - `globalRulePaths` ← global RuleScan
  - `usesFlatAgentFiles` ← flat vs subdirectory agent creation
- `Chops/Services/SkillScanner.swift`
  - `projectProbes` ← all project-relative scan rows
  - any tool-specific special cases (e.g. the `.github` → `copilot-instructions.md` branch)
- `Chops/Views/Shared/NewSkillSheet.swift`
  - `creatableTools` (per kind) ← which tools appear in the new-item sheet
  - the create-path logic ← CreateSkill/CreateAgent/CreateRule resolve to `globalPaths.first` / `globalAgentPaths.first` / `globalRulePaths.first`

Note common divergence shapes: documented path not scanned; code scans a path the doc omits; create-path points at the wrong dir (`.first` mismatch); tool listed as creatable but absent from `creatableTools`; phantom doc fields with no code backing.

When a doc row cites a vendor's behavior, confirm against the vendor's public docs before treating the doc or the code as correct — don't assume either side is right.

## Step 3: Report findings and resolve one at a time

Print findings as a **numbered list**, each with: the doc claim (with line number), the code reality (with `file:line`), and whether they match.

Then go through the open ones **one at a time**. For each, state the two resolution paths and ask the user which they want:

- **Fix the doc** — when the code is the intended behavior.
- **Fix the code** — when the doc is the contract.

Do not batch-apply fixes. Wait for the user's choice on each finding.

## When fixing code

- After any code change, build (`xcodebuild -scheme Chops -configuration Debug build`) and **manually verify** the behavior in the running app — per the project's "always manually test" rule. Seeing "build succeeded" is not enough.
- To exercise scan paths, create a temporary fixture skill/agent/rule at the path in question (and a detect marker if the tool isn't installed), relaunch, confirm it appears tagged to the right tool, then **delete the fixture**.
- To test custom-directory project probes, set the `customScanPaths` UserDefaults key on `com.joshpigford.Chops` — **read its prior value first** so you can restore it; never blind-overwrite shared prefs.
- Keep edits direct, no fallbacks (per CLAUDE.md).
