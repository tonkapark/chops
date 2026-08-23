import Foundation

@Observable
final class SkillRegistry {
    /// One instance for the app so the trending and GitHub caches last the session,
    /// not just a single sheet presentation.
    static let shared = SkillRegistry()

    var isSearching = false
    var searchError: String?

    // Cache repo metadata to avoid repeated GitHub API calls
    private var treeCache: [String: [String]] = [:] // source@branch -> [SKILL.md paths]
    private var branchCache: [String: String] = [:] // source -> default branch

    // Popular/trending skills, scraped from skills.sh. Cached in memory for the session.
    private var trendingCache: [RegistrySkill]?

    // MARK: - Search

    struct SearchResponse: Codable {
        let skills: [RegistrySkill]
        let count: Int
    }

    struct RegistrySkill: Identifiable, Codable {
        let skillId: String
        let name: String
        let installs: Int
        let source: String
        let isOfficial: Bool?

        // Derived rather than decoded: the search API sends an `id` field equal to
        // "<source>/<skillId>", but the trending payload omits it. Computing it keeps
        // both sources Identifiable without a fragile optional.
        var id: String { "\(source)/\(skillId)" }

        var formattedInstalls: String {
            if installs >= 1_000_000 {
                return "\(String(format: "%.1f", Double(installs) / 1_000_000).replacingOccurrences(of: ".0", with: ""))M"
            } else if installs >= 1_000 {
                return "\(String(format: "%.1f", Double(installs) / 1_000).replacingOccurrences(of: ".0", with: ""))K"
            }
            return "\(installs)"
        }
    }

    func search(query: String) async throws -> [RegistrySkill] {
        guard query.count >= 2 else { return [] }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://skills.sh/api/search?q=\(encoded)&limit=30")!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RegistryError.searchFailed
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.skills
    }

    // MARK: - Trending / Browse

    /// Fetches the most-installed skills by scraping skills.sh's server-rendered
    /// trending page (no public JSON API exists for this). The result — ~600 skills
    /// ranked by install count — is cached for the session and powers instant local
    /// browse + filtering, which is both faster and broader than the fuzzy search API.
    func fetchTrending() async throws -> [RegistrySkill] {
        if let cached = trendingCache { return cached }

        var request = URLRequest(url: URL(string: "https://www.skills.sh/trending")!)
        // Identify ourselves honestly since we're reading their HTML rather than a JSON API.
        request.setValue(
            "Chops/macOS (+https://github.com/Shpigford/chops)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw RegistryError.trendingFailed
        }

        let skills = Self.parseTrending(html: html)
        guard !skills.isEmpty else { throw RegistryError.trendingFailed }
        trendingCache = skills
        return skills
    }

    /// Extracts skill objects from the Next.js RSC payload embedded in the trending HTML.
    /// The payload lives inside JS string literals, so JSON quotes arrive as `\"`; we
    /// unescape, then pull out every flat `{…"skillId":…}` object and hand it to
    /// JSONDecoder, which tolerates extra keys and any key order. Page order is
    /// install-count descending, which we preserve.
    static func parseTrending(html: String) -> [RegistrySkill] {
        let unescaped = html.replacingOccurrences(of: "\\\"", with: "\"")
        let pattern = #/\{[^{}]*"skillId":[^{}]*\}/#

        let decoder = JSONDecoder()
        var seen = Set<String>()
        var result: [RegistrySkill] = []
        for match in unescaped.matches(of: pattern) {
            let json = String(match.output)
            guard let skill = try? decoder.decode(RegistrySkill.self, from: Data(json.utf8)) else { continue }
            if seen.insert(skill.id).inserted {
                result.append(skill)
            }
        }
        return result
    }

    /// Case-insensitive substring match across name, skillId, and source.
    static func filter(_ skills: [RegistrySkill], query: String) -> [RegistrySkill] {
        guard !query.isEmpty else { return skills }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.skillId.localizedCaseInsensitiveContains(query)
                || $0.source.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Content Resolution

    func fetchContent(skill: RegistrySkill) async throws -> String {
        let branch = try await getDefaultBranch(source: skill.source)

        if let content = try await fetchContentAtConventionalPaths(skill: skill, branch: branch) {
            return content
        }

        return try await fetchContentViaTreeAPI(skill: skill, branch: branch)
    }

    private func fetchContentAtConventionalPaths(skill: RegistrySkill, branch: String) async throws -> String? {
        let pathPatterns = [
            "skills/\(skill.skillId)/SKILL.md",
            "skills/.curated/\(skill.skillId)/SKILL.md",
            "skills/.experimental/\(skill.skillId)/SKILL.md",
            "\(skill.skillId)/SKILL.md",
            "SKILL.md",
        ]

        for path in pathPatterns {
            let rawURL = URL(string: "https://raw.githubusercontent.com/\(skill.source)/\(branch)/\(path)")!
            guard let (data, response) = try? await URLSession.shared.data(from: rawURL),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            if path == "SKILL.md" {
                let name = parseFrontmatterName(from: content)
                if name != skill.skillId && name != skill.name { continue }
            }

            return content
        }

        return nil
    }

    private func fetchContentViaTreeAPI(skill: RegistrySkill, branch: String) async throws -> String {
        let paths = try await getSkillPaths(source: skill.source, branch: branch)

        for path in paths {
            let rawURL = URL(string: "https://raw.githubusercontent.com/\(skill.source)/\(branch)/\(path)")!
            guard let (data, response) = try? await URLSession.shared.data(from: rawURL),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            let frontmatterName = parseFrontmatterName(from: content)
            if frontmatterName == skill.skillId || frontmatterName == skill.name {
                return content
            }
        }

        throw RegistryError.skillNotFound
    }

    private func getDefaultBranch(source: String) async throws -> String {
        if let cached = branchCache[source] {
            return cached
        }

        let url = URL(string: "https://api.github.com/repos/\(source)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw RegistryError.treeFetchFailed
        }
        if http.statusCode == 403 {
            throw RegistryError.rateLimited
        }
        guard http.statusCode == 200 else {
            throw RegistryError.treeFetchFailed
        }

        struct RepoResponse: Codable {
            let default_branch: String
        }

        let repo = try JSONDecoder().decode(RepoResponse.self, from: data)
        branchCache[source] = repo.default_branch
        return repo.default_branch
    }

    private func getSkillPaths(source: String, branch: String) async throws -> [String] {
        let cacheKey = "\(source)@\(branch)"
        if let cached = treeCache[cacheKey] {
            return cached
        }

        let url = URL(string: "https://api.github.com/repos/\(source)/git/trees/\(branch)?recursive=1")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw RegistryError.treeFetchFailed
        }
        if http.statusCode == 403 {
            throw RegistryError.rateLimited
        }
        guard http.statusCode == 200 else {
            throw RegistryError.treeFetchFailed
        }

        struct TreeResponse: Codable {
            struct TreeEntry: Codable {
                let path: String
                let type: String
            }
            let tree: [TreeEntry]
        }

        let tree = try JSONDecoder().decode(TreeResponse.self, from: data)
        let skillPaths = tree.tree
            .filter { $0.type == "blob" && ($0.path == "SKILL.md" || $0.path.hasSuffix("/SKILL.md")) }
            .map(\.path)

        treeCache[cacheKey] = skillPaths
        return skillPaths
    }

    private func parseFrontmatterName(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.hasPrefix("name:") {
                return trimmed
                    .dropFirst(5)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    // MARK: - Install

    func install(content: String, skillName: String, agents: [AgentTarget]) throws {
        let sanitized = skillName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_" }
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))

        guard !sanitized.isEmpty else {
            throw RegistryError.invalidSkillName
        }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Canonical location — matches the official skills CLI behavior
        let canonicalDir = "\(home)/.agents/skills/\(sanitized)"
        let canonicalFile = "\(canonicalDir)/SKILL.md"
        let canonicalAlreadyExisted = fm.fileExists(atPath: canonicalFile)

        // Write real file to canonical location if not already there
        if !canonicalAlreadyExisted {
            try fm.createDirectory(atPath: canonicalDir, withIntermediateDirectories: true)
            try content.write(toFile: canonicalFile, atomically: true, encoding: .utf8)
        }

        // Symlink from each agent's skills dir to the canonical location
        var newLinks = 0
        for agent in agents {
            let agentDir = "\(agent.expandedSkillsDir)/\(sanitized)"

            // Skip if already installed (real file or symlink)
            if fm.fileExists(atPath: agentDir) { continue }

            // Create parent dir if needed
            try fm.createDirectory(atPath: agent.expandedSkillsDir, withIntermediateDirectories: true)

            // Create symlink to canonical dir
            try fm.createSymbolicLink(atPath: agentDir, withDestinationPath: canonicalDir)
            newLinks += 1
        }

        if newLinks == 0 && canonicalAlreadyExisted {
            throw RegistryError.skillAlreadyExists
        }
    }

    // MARK: - Errors

    enum RegistryError: LocalizedError {
        case searchFailed
        case trendingFailed
        case treeFetchFailed
        case rateLimited
        case skillNotFound
        case invalidSkillName
        case skillAlreadyExists

        var errorDescription: String? {
            switch self {
            case .searchFailed: "Search request failed"
            case .trendingFailed: "Could not load trending skills from skills.sh"
            case .treeFetchFailed: "Could not fetch repository contents"
            case .rateLimited: "GitHub API rate limit reached — try again in a few minutes"
            case .skillNotFound: "File not found in repository"
            case .invalidSkillName: "Invalid name"
            case .skillAlreadyExists: "Already installed for all selected targets"
            }
        }
    }
}
