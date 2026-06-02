import Foundation

/// Reads the `npx skills` CLI global lock file at `~/.agents/.skill-lock.json`
/// and exposes its entries keyed by skill name. The CLI owns this file; Chops
/// only observes it.
enum LockfileService {
    struct Entry: Decodable {
        let source: String?
        let sourceType: String?
        let sourceUrl: String?
        let skillPath: String?
        let skillFolderHash: String?
        let installedAt: Date?
        let updatedAt: Date?
    }

    /// Returns lock entries keyed by skill name. Empty on missing or
    /// unparseable lock file — the CLI is the enforcement layer, not us.
    static func loadGlobal() -> [String: Entry] {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".agents/.skill-lock.json")

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

    private struct Lockfile: Decodable {
        let skills: [String: Entry]
    }
}
