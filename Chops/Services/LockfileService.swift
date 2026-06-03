import Foundation

/// Reads `npx skills` CLI lock files and exposes their entries keyed by skill
/// name. The CLI owns these files; Chops only observes them.
///
/// Two formats are read by the same decoder:
/// - Global: `~/.agents/.skill-lock.json` (version 3, full metadata).
/// - Project: `<project>/skills-lock.json` (version 1, no timestamps/URL,
///   stores the folder hash under `computedHash` instead of `skillFolderHash`).
enum LockfileService {
    struct Entry: Decodable {
        let source: String?
        let sourceType: String?
        let sourceUrl: String?
        let skillPath: String?
        let skillFolderHash: String?
        let installedAt: Date?
        let updatedAt: Date?
        let hashKind: HashKind

        /// Which algorithm produced `skillFolderHash`. Global lock files
        /// store the GitHub tree SHA (SHA-1, 40 chars); project lock files
        /// store a locally-computed content SHA-256 (64 chars). They are
        /// incomparable, so the update check has to branch on which one
        /// the entry holds.
        enum HashKind {
            case treeSHA
            case contentSHA
            case none
        }

        enum CodingKeys: String, CodingKey {
            case source, sourceType, sourceUrl, skillPath
            case skillFolderHash, computedHash, installedAt, updatedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            source = try c.decodeIfPresent(String.self, forKey: .source)
            sourceType = try c.decodeIfPresent(String.self, forKey: .sourceType)
            sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
            skillPath = try c.decodeIfPresent(String.self, forKey: .skillPath)
            let folderSHA = try c.decodeIfPresent(String.self, forKey: .skillFolderHash)
            let computedSHA = try c.decodeIfPresent(String.self, forKey: .computedHash)
            skillFolderHash = folderSHA ?? computedSHA
            if folderSHA != nil {
                hashKind = .treeSHA
            } else if computedSHA != nil {
                hashKind = .contentSHA
            } else {
                hashKind = .none
            }
            installedAt = try c.decodeIfPresent(Date.self, forKey: .installedAt)
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
    }

    /// Returns global lock entries keyed by skill name. Empty on missing or
    /// unparseable lock file — the CLI is the enforcement layer, not us.
    static func loadGlobal() -> [String: Entry] {
        loadEntries(at: URL(fileURLWithPath: globalLockPath))
    }

    /// Returns project-scoped lock entries keyed by skill name from
    /// `<projectDir>/skills-lock.json`. Empty when the file is missing.
    static func loadProject(_ projectDir: URL) -> [String: Entry] {
        loadEntries(at: projectDir.appendingPathComponent("skills-lock.json"))
    }

    private static func loadEntries(at url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }

        let decoder = JSONDecoder()
        // The CLI writes timestamps with fractional seconds (e.g.
        // "2026-04-30T16:21:15.162Z"), which Foundation's default `.iso8601`
        // strategy rejects. Custom decoder accepts both.
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let d = isoWithFractional.date(from: raw) { return d }
            if let d = isoPlain.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognised date: \(raw)"
            )
        }

        guard let lock = try? decoder.decode(Lockfile.self, from: data) else {
            return [:]
        }
        return lock.skills
    }

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Path of the global lock file. Exposed for the FileWatcher.
    static var globalLockPath: String {
        "\(NSHomeDirectory())/.agents/.skill-lock.json"
    }

    /// Top-level shape of `.skill-lock.json`. Skill entries decode lossily —
    /// a single corrupt entry (bad date, type mismatch) drops only that one
    /// instead of disabling managed-skill detection across the whole file.
    private struct Lockfile: Decodable {
        let skills: [String: Entry]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let lossy = try container.decode([String: LossyEntry].self, forKey: .skills)
            self.skills = lossy.compactMapValues(\.value)
        }

        enum CodingKeys: String, CodingKey { case skills }
    }

    /// Wraps `Entry` so one bad value doesn't bring down the whole dict
    /// decode. Failure to decode an `Entry` becomes a nil `value`.
    private struct LossyEntry: Decodable {
        let value: Entry?

        init(from decoder: Decoder) throws {
            self.value = try? Entry(from: decoder)
        }
    }
}
