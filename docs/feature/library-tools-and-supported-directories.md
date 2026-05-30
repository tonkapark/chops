# Library: Tools & Supported Directories

How Chops discovers skills, agents, and rules across the AI coding tools installed on your machine, in any custom project directories you add, and on remote servers.

> Throughout Chops, **skills**, **agents**, and **rules** are all referred to as "skills" unless an agents or rules folder is specifically called out. This doc keeps them distinct because each tool exposes them in different folders.

Source of truth: `Chops/Models/ToolSource.swift` (paths) and `Chops/Services/SkillScanner.swift` (scan logic). Remote scanning lives in `Chops/Services/SSHService.swift`.

---

## Supported tools

Every tool below is gated by an install check (`ToolSource.isInstalled`) — Chops only scans a tool's directories if it finds that tool's app bundle, CLI binary, or config files. A tool with no detected install is skipped entirely.

| Tool | Skills | Agents | Rules |
|------|--------|--------|-------|
| **Global** (`~/.agents`) | `~/.agents/skills/` | — | — |
| **Claude Code** | `~/.claude/skills/` | `~/.claude/agents/` | — |
| **Cursor** | `~/.cursor/skills/` | `~/.cursor/agents/` | `~/.cursor/rules/` |
| **Windsurf** | — | — | `~/.codeium/windsurf/memories/`, `~/.windsurf/rules/` |
| **Codex** | `~/.codex/skills/` | `~/.codex/agents/` | — |
| **Factory** (Droid CLI) | `~/.factory/skills/` | `~/.factory/droids/` | — |
| **Copilot** | `~/.copilot/skills/` | — | — |
| **Amp** | `$XDG_CONFIG_HOME/amp/skills/` (default `~/.config/amp/skills/`) | — | — |
| **Auggie** (Augment) | `~/.augment/skills/` | — | — |
| **OpenCode** | `$XDG_CONFIG_HOME/opencode/skills/` (default `~/.config/opencode/skills/`) | — | — |
| **Pi** | `~/.pi/agent/skills/` | — | — |
| **Antigravity** | `~/.gemini/antigravity/skills/` | — | — |
| **Hermes** | `~/.hermes/skills/` *(only if it exists; nested `<category>/<skill>/SKILL.md` layout is walked recursively)* | — | — |
| **OpenClaw** | `~/.openclaw/skills/`, `~/.openclaw/<workspace>/skills/`, `/opt/homebrew/lib/node_modules/openclaw/skills/`, `/usr/local/lib/node_modules/openclaw/skills/` | — | — |
| **Claude Desktop** | via plugin manifests only *(see Plugins below)* | — | — |
| **Aider** | — *(no global paths and no project probes — currently discovers nothing)* | — | — |

Notes:

- **Global (`~/.agents`)** is the tool-agnostic location for any tool that follows the [Agent Skills specification](https://agentskills.io/specification). Skills installed here are shared across spec-compliant tools rather than belonging to one vendor.
- **`$XDG_CONFIG_HOME`** is honored for Amp and OpenCode; when unset or empty it falls back to `~/.config`.
- **OpenClaw** probes its NPM global install locations (Apple-silicon and Intel Homebrew prefixes) in addition to the user dotfiles, and discovers per-workspace skill folders under `~/.openclaw/`.
- **Hermes** is only added to the scan set when `~/.hermes/skills` already exists on disk.
- **Factory** is Factory.ai's Droid CLI. Its custom droids (`~/.factory/droids/`, loose `<name>.md` files) are surfaced as **agents**. Factory's slash **commands** (`.factory/commands`) are intentionally not scanned — Factory's own docs steer users toward skills instead. Detected when `~/.factory` exists or the `droid` CLI is on `PATH`.
- **Aider** appears in the tool model but has no discovery paths wired up — it neither has global paths nor a project-level probe. It is effectively a no-op until paths are added.

### Plugins (optional)

When **Include plugin skills** is enabled in settings (`ChopsSettings.includePluginSkills`), two additional sources are scanned after the global tool paths:

- **Claude CLI plugins** — read from `~/.claude/plugins/installed_plugins.json`; each plugin's `installPath/skills/` directory is scanned.
- **Claude Desktop / Cowork plugins** — read from `~/Library/Application Support/Claude/local-agent-mode-sessions/`. Local cowork plugins use `cowork_plugins/installed_plugins.json`; remote cowork plugins use `remote_cowork_plugins/manifest.json` as the source of truth. Anthropic's built-in `skills-plugin/` is intentionally skipped.

---

## What counts as a skill file

Inside any scanned directory, Chops recognizes:

- A **subdirectory containing `SKILL.md`** → a directory-style skill (named after the folder if frontmatter has no name).
- A **subdirectory containing `AGENTS.md`** → treated according to the directory's kind (skill/agent/rule).
- An **agent subdirectory** with a single `.md`/`.mdc`/`.toml` file, or a file whose name matches the folder name → that agent file.
- **Loose `.md`, `.mdc`, or `.toml` files** → a single-file skill/agent/rule.
- For **Copilot project skills** specifically, only `.github/copilot-instructions.md` is picked up.

Loose files with these names are always ignored (they're config/meta, not skills):

`README.md`, `README`, `CLAUDE.md`, `AGENTS.md`, `AGENTS.override.md`, `global_rules.md`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `LICENSE.md`, `LICENSE`, `CHANGELOG.md`

Symlinked directories are resolved and traversed, and skills are de-duplicated by their resolved symlink path so the same skill installed for multiple tools shows up once with multiple tool badges.

---

## Local scan order

`SkillScanner.collectAllSkills` runs a full local scan in this fixed order:

1. **Global tool directories** — for every installed tool (in the order they're declared: Global, Auggie, Claude Code, Cursor, Windsurf, Codex, Copilot, Aider, Amp, Hermes, OpenClaw, OpenCode, Pi, Antigravity, Claude Desktop), Chops scans, in this sub-order:
   1. the tool's **skill** paths (`globalPaths`)
   2. the tool's **agent** paths (`globalAgentPaths`)
   3. the tool's **rule** paths (`globalRulePaths`)
2. **Plugins** (if the setting is enabled) — Claude CLI plugins, then Claude Desktop / Cowork plugins.
3. **Custom scan directories** — each path you've added, in the order it appears in your settings list.

Remote servers are scanned separately (see below) and are not part of this local pass.

---

## Custom project directories

Add a parent directory (e.g. `~/Development`) in **Settings → Custom Scan Directories** and Chops scans it two ways:

1. **Direct library entries** — any immediate child that is a folder containing `SKILL.md`, or any loose `.md`/`.mdc`/`.toml` file directly in the directory, is imported as a skill tagged **Custom**. (Only direct entries are imported this way, so adding a generic project parent doesn't turn every repo's `AGENTS.md` into a bogus skill.)

2. **Per-project tool folders** — for each immediate subdirectory (treated as a "project"), Chops probes for these tool-specific paths and tags any finds with the matching tool:

   | Probe path (within each project) | Tool | Kind |
   |----------------------------------|------|------|
   | `.claude/skills` | Claude Code | skill |
   | `.claude/agents` | Claude Code | agent |
   | `.cursor/skills` | Cursor | skill |
   | `.cursor/rules` | Cursor | rule |
   | `.cursor/agents` | Cursor | agent |
   | `.codex/skills` | Codex | skill |
   | `.codex/agents` | Codex | agent |
   | `.windsurf/rules` | Windsurf | rule |
   | `.github` | Copilot | skill *(`copilot-instructions.md`)* |
   | `.github/agents` | Copilot | agent |
   | `.config/amp/skills` | Amp | skill |
   | `.opencode/skills` | OpenCode | skill |
   | `.hermes/skills` | Hermes | skill |
   | `.factory/skills` | Factory | skill |
   | `.factory/droids` | Factory | agent |

The probe set is one level deep: Chops looks at the directory's immediate children for these `.tool/...` folders. It does not recurse into arbitrarily nested projects.

---

## Remote servers

Add a server in **Settings → Remote Servers** (label, host, username, base path, optional SSH key path). Chops connects over SSH and discovers skills like this:

1. Runs `find <basePath> -name 'SKILL.md' -type f` under the server's **Base Path**.
2. `cat`s each match and parses its frontmatter.
3. Skills are stored with a `remote://<server-id>/<path>` identity and tagged with a tool inferred from the base path:
   - path contains `hermes` → **Hermes**
   - otherwise (including paths containing `openclaw`) → **OpenClaw**

Only directory-style `SKILL.md` skills are discovered remotely (the loose-file and agent/rule probes used locally do not apply over SSH). Typical base paths, per the in-app prompt, are `~/.hermes/skills`, `~/.openclaw`, or `~/skills`. Skills that disappear from the server on a later sync are removed locally; sync errors are surfaced per-server in settings.
