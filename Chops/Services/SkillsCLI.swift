import Foundation

/// Thin wrapper around `npx skills <command>`. The CLI owns lock-file truth;
/// Chops just shells out and surfaces the result.
enum SkillsCLI {
    enum CLIError: LocalizedError {
        case npxMissing
        case nonZeroExit(code: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case .npxMissing:
                return "Couldn't find `npx`. Install Node.js (nodejs.org) to install skills via the registry."
            case .nonZeroExit(_, let message):
                return message.isEmpty ? "Skills CLI failed" : message
            }
        }
    }

    /// `npx skills add <source> -g -s <skillId> -y`. Omitting `-a` lets the
    /// CLI install for all detected agents.
    @discardableResult
    static func add(source: String, skillId: String) async throws -> String {
        try await run(args: ["skills", "add", source, "-g", "-s", skillId, "-y"])
    }

    /// `npx skills remove <name> -g -y -a <agent>...`. Empty `agentIds` lets
    /// the CLI default to removing from every detected agent — passing `*`
    /// here is rejected by the CLI as "Invalid agents".
    @discardableResult
    static func remove(name: String, agentIds: [String]) async throws -> String {
        var args = ["skills", "remove", name, "-g", "-y"]
        for id in agentIds {
            args.append(contentsOf: ["-a", id])
        }
        return try await run(args: args)
    }

    /// `npx skills update <name>... -g -y`. With no names, the CLI updates
    /// every managed skill in scope. With names, only those listed.
    @discardableResult
    static func update(names: [String]) async throws -> String {
        var args = ["skills", "update"]
        args.append(contentsOf: names)
        args.append(contentsOf: ["-g", "-y"])
        return try await run(args: args)
    }

    // MARK: - Process

    private static func run(args: [String]) async throws -> String {
        guard let npx = locateNpx() else { throw CLIError.npxMissing }

        let env = sanitizedEnvironment()

        return try await Task.detached(priority: .userInitiated) { () -> String in
            let proc = Process()
            proc.executableURL = npx
            proc.arguments = args
            proc.environment = env
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            try proc.run()
            proc.waitUntilExit()

            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            try? pipe.fileHandleForReading.close()
            let output = stripANSI(String(data: data, encoding: .utf8) ?? "")

            if proc.terminationStatus != 0 {
                throw CLIError.nonZeroExit(code: proc.terminationStatus, message: output)
            }
            return output
        }.value
    }

    /// The shared `cliBinaryURL` probe doesn't cover asdf shims, which is where
    /// the user's `npx` lives when Node is managed by asdf. Extend it here.
    private static func locateNpx() -> URL? {
        let home = NSHomeDirectory()
        return ToolSource.cliBinaryURL("npx", extraPaths: [
            "\(home)/.asdf/shims/npx",
        ])
    }

    /// Strip ANSI color/escape codes so error messages render cleanly in
    /// SwiftUI Text views.
    private static func stripANSI(_ s: String) -> String {
        let pattern = #/\u{001B}\[[0-9;]*[mGKHF]/#
        return s.replacing(pattern, with: "")
    }

    /// `npx skills` auto-detects the calling agent from env vars (AI_AGENT,
    /// CLAUDECODE, CURSOR_TRACE_ID, etc.) and silently overrides any `-a`
    /// flags we pass when one is set. Chops inherits whatever shell launched
    /// it — so when Chops is launched from a Claude Code or Cursor session,
    /// every install would route to that agent regardless of user selection.
    /// Strip the well-known auto-detection vars before spawning. Also injects
    /// `DISABLE_TELEMETRY=1` when the user opts out of CLI telemetry.
    private static func sanitizedEnvironment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        let prefixes = ["CLAUDE_CODE", "CURSOR", "CODEX", "WINDSURF", "OPENCODE"]
        let exact: Set<String> = ["AI_AGENT", "CLAUDECODE", "CLINE", "ZED", "AMP"]
        var sanitized = env.filter { key, _ in
            !exact.contains(key) && !prefixes.contains(where: { key.hasPrefix($0) })
        }
        if ChopsSettings.disableSkillsCLITelemetry {
            sanitized["DISABLE_TELEMETRY"] = "1"
        }
        return sanitized
    }
}
