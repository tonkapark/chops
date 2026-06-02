import Foundation
import SwiftData

/// Polls GitHub Trees API to determine whether a managed skill's upstream
/// folder has moved past its installed `skillFolderHash`. Matches the CLI's
/// own check (see `vercel-labs/skills/src/blob.ts:getSkillFolderHashFromTree`).
///
/// Per-source repo trees are fetched once per `checkAll` invocation; a single
/// 60-call/h unauthenticated rate-limit budget then covers up to 60 distinct
/// upstream repos regardless of how many skills are installed from each.
@MainActor
enum UpdateChecker {
    /// Lock entries refresh frequently; the upstream tree SHA only changes
    /// when the source repo receives a relevant commit. Skip skills checked
    /// more recently than this unless `force` is set.
    static let stalenessWindow: TimeInterval = 60 * 60 * 6 // 6 hours

    /// Refresh `upstreamHash` for every managed skill in the store. Groups
    /// skills by `source` so each repo's tree is fetched exactly once.
    static func checkAll(in modelContext: ModelContext, force: Bool = false) async {
        let descriptor = FetchDescriptor<Skill>()
        guard let skills = try? modelContext.fetch(descriptor) else { return }
        let managed = skills.filter { skill in
            guard let source = skill.lockSource, !source.isEmpty else { return false }
            guard !force, let last = skill.lastUpstreamCheckedAt else { return true }
            return Date().timeIntervalSince(last) >= stalenessWindow
        }
        guard !managed.isEmpty else { return }

        let bySource = Dictionary(grouping: managed, by: { $0.lockSource ?? "" })
        for (source, skillsForSource) in bySource {
            await refresh(source: source, skills: skillsForSource)
        }

        try? modelContext.save()
    }

    /// Refresh `upstreamHash` for one skill, ignoring the staleness window.
    static func check(_ skill: Skill) async {
        guard let source = skill.lockSource, !source.isEmpty else { return }
        await refresh(source: source, skills: [skill])
    }

    // MARK: - Per-source fetch

    /// Fetches the repo's recursive tree once and applies the matching
    /// folder SHA to each skill from that source. Also re-reads the lock
    /// file and refreshes `lockHash`, so external lock edits (manual or by
    /// another `npx skills` run while Chops was unfocused) are visible at
    /// check time without depending on FileWatcher debounce timing.
    private static func refresh(source: String, skills: [Skill]) async {
        let lockEntries = LockfileService.loadGlobal()
        guard let tree = await fetchTree(ownerRepo: source) else {
            stamp(skills: skills, hash: nil)
            return
        }
        for skill in skills {
            let lockKey = URL(fileURLWithPath: skill.resolvedPath)
                .deletingLastPathComponent()
                .lastPathComponent
            guard let entry = lockEntries[lockKey],
                  let path = entry.skillPath
            else { continue }
            skill.lockHash = entry.skillFolderHash
            skill.upstreamHash = folderSHA(in: tree, for: path)
            skill.lastUpstreamCheckedAt = Date()
        }
    }

    private static func stamp(skills: [Skill], hash: String?) {
        let now = Date()
        for skill in skills {
            // Only record the timestamp on a successful fetch — leaving it
            // untouched means a transient 404/rate-limit doesn't suppress
            // the next check by burning the staleness window.
            if hash != nil { skill.lastUpstreamCheckedAt = now }
        }
    }

    // MARK: - GitHub Trees API

    private struct RepoTree: Decodable {
        let sha: String
        let tree: [TreeEntry]
    }

    private struct TreeEntry: Decodable {
        let path: String
        let type: String
        let sha: String
    }

    /// Fetches the recursive tree for `<owner>/<repo>`. Tries `main` first,
    /// falls back to `master`. Returns nil on network error, rate limit,
    /// invalid JSON, or both branches missing.
    private static func fetchTree(ownerRepo: String) async -> RepoTree? {
        for branch in ["main", "master"] {
            if let tree = await fetchTreeBranch(ownerRepo: ownerRepo, branch: branch) {
                return tree
            }
        }
        return nil
    }

    private static func fetchTreeBranch(ownerRepo: String, branch: String) async -> RepoTree? {
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        guard let url = URL(string: "https://api.github.com/repos/\(ownerRepo)/git/trees/\(encodedBranch)?recursive=1")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("chops", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else { return nil }

        return try? JSONDecoder().decode(RepoTree.self, from: data)
    }

    /// Extract the folder SHA for a skill given its repo-relative path.
    /// Mirrors `getSkillFolderHashFromTree` in the CLI: strip a trailing
    /// `/SKILL.md`, then find the matching `tree` entry. Root-level skills
    /// resolve to the repo's tree SHA.
    private static func folderSHA(in tree: RepoTree, for skillPath: String) -> String? {
        var folder = skillPath.replacingOccurrences(of: "\\", with: "/")
        let lower = folder.lowercased()
        if lower.hasSuffix("/skill.md") {
            folder = String(folder.dropLast("/skill.md".count))
        } else if lower.hasSuffix("skill.md") {
            folder = String(folder.dropLast("skill.md".count))
        }
        if folder.hasSuffix("/") { folder.removeLast() }

        if folder.isEmpty { return tree.sha }
        return tree.tree.first(where: { $0.type == "tree" && $0.path == folder })?.sha
    }
}

private extension Skill {
    /// Repo-relative path to the skill's SKILL.md, recovered from the lock
    /// entry. We store the `skillPath` field on the Skill via `LockfileService`
    /// — but historically it was dropped in favour of just the source URL.
    /// Re-read the lock here on demand; lock-file decode is already cached
    /// and these calls happen at most a handful of times per check.
    func lockSourceSkillPath() -> String? {
        let lockKey = URL(fileURLWithPath: resolvedPath)
            .deletingLastPathComponent()
            .lastPathComponent
        return LockfileService.loadGlobal()[lockKey]?.skillPath
    }
}
