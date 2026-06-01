# Library: Tools & Supported Directories

How Chops discovers skills, agents, and rules across installed AI coding tools, custom project directories, plugins, and remote servers.

Throughout Chops, skills, agents, and rules are often grouped under the word "skills" in the UI. This document keeps the kinds separate because every tool exposes a different filesystem contract.

Primary source of truth:

- `Chops/Models/ToolSource.swift`: tool cases, display metadata, install checks, global scan paths, and flat-agent behavior.
- `Chops/Services/SkillScanner.swift`: local scan order, project probes, file recognition, plugin scanning, de-duplication, and SwiftData upserts.
- `Chops/Views/Shared/NewSkillSheet.swift`: which tools Chops can create files for and what boilerplate it writes.
- `Chops/Models/AgentTarget.swift`: symlink fan-out targets for Global skills.
- `Chops/Services/SSHService.swift`: remote `SKILL.md` discovery.

Use this page as the implementation contract when adding a new tool or updating support for an existing tool. The registry below is intentionally compact: shared behavior is documented once, while each tool row captures only the facts that vary by tool.

## Add Or Update A Tool

Before changing code, add or update one entry in [Tool Registry](#tool-registry). 

- How Chops detects the tool.
- Which global paths and project probes Chops scans.
- Where Chops can create specific kinds of files.
- Which vendor docs or local app source verified the behavior.
- Which exceptions make the tool different from the shared defaults.

Then update the app in this order:

1. `ToolSource`: case, display metadata, `listable`, install detection, global scan paths, and `usesFlatAgentFiles`.
2. `SkillScanner.projectProbes`: repo-local scan paths.
3. `SkillParser`: only if the tool cannot use the shared parser behavior.
4. `NewSkillSheet`: creatable kinds and boilerplate.
5. `AgentTarget`: only if Global skills should symlink into the tool.
6. `RemoteServer.inferredRemoteToolSource`: only if remote sync should tag the tool.
7. This document: update the registry row and any exception notes.

## Shared Defaults

These defaults apply unless a registry row or exception note says otherwise.

- Install checks gate global scans. If `ToolSource.isInstalled` is false, Chops skips that tool's global paths.
- `cliBinaryExists` probes `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, and every `~/.nvm/versions/node/*/bin`.
- `appBundleExists` probes `/Applications` and `~/Applications`.
- `<configHome>` means `$XDG_CONFIG_HOME` when set and non-empty, otherwise `~/.config`.
- File recognition and parser behavior are shared unless the registry notes a parser exception.
- Creation layouts are shared unless the registry notes a flat-agent or rule-only exception.

Local scan order in `SkillScanner.collectAllSkills` is:

1. Installed `ToolSource` cases, in enum declaration order, excluding `custom`.
2. For each installed tool: global skills, then global agents, then global rules.
3. Optional plugin skills when `ChopsSettings.includePluginSkills` is enabled.
4. Custom scan directories, in the order stored in settings.

## Open Standard Skills Spec

Agent Skills are a lightweight, open format for extending AI agent capabilities with specialized knowledge and workflows.

- overview <https://agentskills.io/>
- full spec <https://agentskills.io/specification/>  (`SKILL.md`, frontmatter, directory layout)

## Vercel `skills` CLI

Open standard single command to install, remove, update skill files

- README / commands <https://github.com/vercel-labs/skills>
- npm `npx skills` <https://www.npmjs.com/package/skills>
- skills registry <https://skills.sh>

## Tool Registry <a name="tool-registry"></a>

### Global Agent Skills

- **Detect:** `~/.agents/skills`
- **SkillScan:** `~/.agents/skills`
- **CreateSkill:** `~/.agents/skills/<name>/SKILL.md`; symlinks to installed targets
- **Docs:** <https://agentskills.io/specification/>

### Claude Code

- **Detect:** `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/plugins/installed_plugins.json`, or `claude`
- **SkillScan:** `~/.claude/skills`, `.claude/skills`
- **AgentScan:**  `~/.claude/agents`, `.claude/agents`
- **CreateSkill** `~/.claude/skills/<name>/SKILL.md`
- **PluginScan:** optional scan from `~/.claude/plugins/installed_plugins.json` → `installPath/skills`
- **Docs:** <https://code.claude.com/docs/en/skills>
- **SupportsOpenStandardDiscovery:** false

### Claude Desktop

- **Detect:** `Claude.app`
- **SkillScan:** plugin manifests only
- **PluginScan:** optional scan from `~/Library/Application Support/Claude/local-agent-mode-sessions`, `cowork_plugins/installed_plugins.json`, `remote_cowork_plugins/manifest.json`
- **Docs:** <https://docs.claude.com>

### Cursor

- **Detect:** `Cursor.app` or `~/.cursor/argv.json`
- **SkillScan:** `~/.cursor/skills`, `.cursor/skills`
- **AgentScan:** `~/.cursor/agents`, `.cursor/agents`
- **RuleScan:** `~/.cursor/rules`, `.cursor/rules`
- **CreateSkill:** `~/.cursor/skills/<name>/SKILL.md`; 
- **CreateAgent:** `~/.cursor/agents/<name>.md`; 
- **CreateRule:** `~/.cursor/rules/<name>.mdc`
- **Docs:** <https://cursor.com/docs/skills>
- **SupportsOpenStandardDiscovery:** true

### Windsurf

- **Detect:** `Windsurf.app` or `~/.codeium/windsurf/argv.json`
- **SkillScan:** `~/.codeium/windsurf/skills/`, `.windsurf/skills/`
- **RuleScan:** `~/.codeium/windsurf/memories`, `~/.windsurf/rules`, `.windsurf/rules`,  
- **CreateSkill:** `~/.codeium/windsurf/skills/<name>/SKILL.md`
- **Docs:** <https://docs.windsurf.com/windsurf/cascade/memories>

### Codex

- **Detect:** `~/.codex/config.toml`, `~/.codex/auth.json`, or `codex`
- **SkillScan:** `~/.codex/skills`, `.codex/skills`
- **AgentScan:** `~/.codex/agents`, `.codex/agents`
- **CreateSkill:** `~/.codex/skills/<name>/SKILL.md`
- **CreateAgent:** `~/.codex/agents/<name>.toml`
- **Docs:** <https://developers.openai.com/codex/skills>
- **SupportsOpenStandardDiscovery:** true

### Factory

- **Detect:** `~/.factory` or `droid`
- **SkillScan:** `~/.factory/skills`, `.factory/skills`, `~/.factory/commands`, `.factory/commands`
- **AgentScan:** `~/.factory/droids`, `.factory/droids`
- **CreateSkill:** `~/.factory/skills/<name>/SKILL.md`
- **CreateAgent:** `~/.factory/droids/<name>.md`
- **Docs:** <https://docs.factory.ai>
- **SupportsOpenStandardDiscovery:** true
- **Note:** Only skill commands are scanned; per Factory docs, only skill creation is supported.

### Copilot

- **Detect:** `~/.copilot` or `copilot`
- **SkillScan:** `~/.copilot/skills`, `.github/skills`
- **AgentScan:** `.github/agents`
- **CreateSkill:** `~/.github/skills`
- **Docs:** <https://docs.github.com/en/copilot>
- **SupportsOpenStandardDiscovery:** true

### Amp

- **Detect:** `<configHome>/amp/config.json`, `<configHome>/amp/settings.json`, or `amp`
- **SkillScan:** `<configHome>/amp/skills`
- **CreateSkill:** `<configHome>/amp/skills/<name>/SKILL.md`
- **Docs:** <https://ampcode.com/manual>
- **SupportsOpenStandardDiscovery:** true

### Auggie

- **Detect:** `Augment.app`, `~/.augment/settings.json`, or `augment`
- **SkillScan:** `~/.augment/skills`, `.augment/skills`
- **AgentScan:** `~/.augment/agents`, `.augment/agents`
- **RuleScan:** `~/.augment/rules`, `.augment/rules`
- **CreateSkill:** `~/.augment/skills/<name>/SKILL.md`
- **CreateAgent:** `~/.augment/agents/<name>.md`
- **Docs:** <https://docs.augmentcode.com/cli/skills>, <https://docs.augmentcode.com/cli/subagents>, <https://docs.augmentcode.com/cli/rules>
- **SupportsOpenStandardDiscovery:** true

### OpenCode

- **Detect:** `OpenCode.app`, `<configHome>/opencode/opencode.json`, `<configHome>/opencode/opencode.jsonc`, `~/.local/share/opencode`, or `opencode`
- **SkillScan:** `<configHome>/opencode/skills`, `.opencode/skills`
- **CreateSkill:** `<configHome>/opencode/skills/<name>/SKILL.md`
- **Docs:** <https://opencode.ai/docs>

### Pi

- **Detect:** `~/.pi` or `pi`
- **SkillScan:** `~/.pi/agent/skills`
- **CreateSkill:** `~/.pi/agent/skills/<name>/SKILL.md`
- **Docs:** <https://pi.dev/docs/latest/skills>
- **SupportsOpenStandardDiscovery:** true

### Antigravity

- **Detect:** `Antigravity.app`, `~/.antigravity`, or `antigravity`
- **SkillScan:** `~/.gemini/antigravity/skills`, `~/.gemini/config/skills`
- **CreateSkill:** `~/.gemini/config/skills/<name>/SKILL.md`
- **Docs:** <https://antigravity.google/docs/skills>

### Hermes

- **Detect:** `~/.hermes` or `hermes`
- **SkillScan:** `~/.hermes/skills`, `.hermes/skills`
- **Docs:** <https://hermes-agent.nousresearch.com/docs/developer-guide/creating-skills>

### OpenClaw

- **Detect:** `~/.openclaw`, `openclaw`, or global NPM install
- **SkillScan:** `~/.openclaw/skills`, `~/.openclaw/<workspace>/skills`, Homebrew NPM install dirs
- **Docs:** <https://docs.openclaw.ai/tools/skills>
- **SupportsOpenStandardDiscovery:** true

### Aider

- **Detect:** `aider`
- **Docs:** <https://aider.chat>

Last verified: 2026-05-31 against app source. Vendor docs should be rechecked before relying on a row for new implementation work.

## Exceptions And Extra Sources

### Plugins

When "Include plugin skills" is enabled in Settings, Chops will scans for plugins 

### Custom Scan Roots

Custom scan roots serve two jobs:

- Direct library entries: immediate child folders containing `SKILL.md`, plus loose `.md`, `.mdc`, or `.toml` files directly inside the custom directory, are imported as `Custom` skills.
- Project probes: each immediate child directory is treated as a project, and Chops probes the registry's project paths.

The project probe set is one level deep. Chops does not recurse into arbitrarily nested projects.

### Remote Servers

Remote servers are synced separately through `SkillScanner.syncAllRemoteServers`. Chops connects over SSH, runs `find <basePath> -name 'SKILL.md' -type f`, reads each match, parses frontmatter, and stores the skill with a `remote://<server-id>/<path>` identity.

*Remote sync only discovers directory-style `SKILL.md` skills. Loose files, agents, and rules are local-only today.*

Remote tool inference:

- paths containing `hermes` are tagged as Hermes.
- paths containing `openclaw` are tagged as OpenClaw.
- all other remote paths default to OpenClaw.

## File Recognition And Parsing

Inside any scanned directory, Chops recognizes:

- A subdirectory containing `SKILL.md`: directory-style skill, named after the folder if frontmatter has no name.
- A subdirectory containing `AGENTS.md`: treated according to the directory's scan kind.
- An agent subdirectory with a single `.md`, `.mdc`, or `.toml` file, or a file whose name matches the folder.
- Loose `.md`, `.mdc`, or `.toml` files.
- For Copilot project skills only, `.github/copilot-instructions.md`.

Loose files with these names are always ignored because they are config or project metadata, not skills:

`README.md`, `README`, `CLAUDE.md`, `AGENTS.md`, `AGENTS.override.md`, `global_rules.md`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `LICENSE.md`, `LICENSE`, `CHANGELOG.md`

Parser selection:

- Claude Code, Claude Desktop, and Cursor: `.mdc` files use `MDCParser`; everything else uses `FrontmatterParser`.
- All other tools, including Global and Custom: `FrontmatterParser` runs first; if no `name` is found, Chops falls back to the first Markdown `# Heading`.

`.toml` files are accepted as loose skill or agent files but still run through the frontmatter/heading parsers. There is no dedicated TOML parser today.

Symlinked directories are resolved and traversed. Skills are de-duplicated by resolved symlink path, so the same skill installed for multiple tools appears once with multiple tool badges.

## Creation Behavior

`NewSkillSheet` sanitizes the entered name by lowercasing it, replacing spaces with hyphens, and keeping only letters, numbers, and hyphens. It then writes one of these layouts:


| Kind       | Layout     | Resulting path                  | Boilerplate                                                                                                                            |
| ---------- | ---------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Skill      | directory  | `<skills-dir>/<name>/SKILL.md`  | `name` and `description` frontmatter; Claude, Cursor, and Global also get `When to Use` and `Instructions`; others get `Instructions`. |
| Agent      | directory  | `<agents-dir>/<name>/<name>.md` | `name` and `description` frontmatter plus `Instructions`.                                                                              |
| Flat agent | loose file | `<agents-dir>/<name>.md`        | Same as agent. Used when `usesFlatAgentFiles` is true.                                                                                 |
| Rule       | loose file | `<rules-dir>/<name>.md`         | Plain `# <name>` heading, no frontmatter.                                                                                              |


The `Created` column in [Tool Registry](#tool-registry) is the current source of truth for which tools appear in the new-item sheet.

Chops creates subdirectory-style agents for Claude Code, Cursor, and Codex, even though the scanner accepts loose agent files too. Factory droids are written flat because `usesFlatAgentFiles` is true.

Creating a Global skill writes `~/.agents/skills/<name>/SKILL.md` and then symlinks that folder into every installed `AgentTarget`: Claude Code, Codex, Amp, OpenCode, Goose, Cursor, Windsurf, and Warp. Goose and Warp are symlink targets only; they are not `ToolSource` cases today.

## Documentation Hygiene

When a vendor changes its spec, update the relevant tool definition rather than adding another comparison table. Keep historical notes only if they explain current implementation behavior.

For each update:

- Link to vendor docs where possible.
- Record whether the entry was verified against vendor docs, app source, or both.
- Prefer concrete paths over prose summaries.
- Call out known gaps explicitly, such as "scanned but not creatable" or "model case exists but no paths are wired".
- Keep shared behavior in the shared sections so every tool entry stays short and comparable.

