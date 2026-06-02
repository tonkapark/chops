import SwiftUI
import SwiftData
import Foundation

/// Panel above the editor/preview showing the skill's identity (title, slug,
/// version), the tools it's installed in, and quick-access chips for sibling
/// resource folders (templates/, references/, scripts/, …).
struct SkillHeaderPanel: View {
    let skill: Skill
    @State private var copiedPath = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            locationRow
            if displaySourceURL != nil {
                sourceRow
            }
            if !siblingFolders.isEmpty {
                contentsRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(skill.name)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .truncationMode(.tail)

            KindPill(kind: skill.itemKind)

            if let version = versionLabel {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(skill.toolSources) { tool in
                    ToolIcon(tool: tool, size: 14, title: tool.displayName)
                }
            }
        }
    }

    // MARK: - Location

    private var locationRow: some View {
        HStack(spacing: 6) {
            Text("Location:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                copyPath()
            } label: {
                HStack(spacing: 4) {
                    Text(displayLocation)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: copiedPath ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(copiedPath ? "Copied!" : "Click to copy path")

            Spacer(minLength: 0)
        }
    }

    private var displayLocation: String {
        let path = locationPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: home, with: "~")
    }

    private var locationPath: String {
        if skill.isRemote {
            return skill.remotePath ?? ""
        }
        return URL(fileURLWithPath: skill.filePath)
            .deletingLastPathComponent()
            .path
    }

    private func copyPath() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(locationPath, forType: .string)
        copiedPath = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedPath = false
        }
    }

    // MARK: - Source

    private var sourceRow: some View {
        HStack(spacing: 6) {
            Text("Source:")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let url = sourceLinkURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack(spacing: 4) {
                        Text(displaySourceURL ?? "")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(skill.sourceURL ?? "")
            } else {
                // Lock entry stored a non-URL source (e.g. a local path or a
                // malformed string). Render plain text so the row still shows
                // provenance — clicking it just wouldn't do anything useful.
                Text(displaySourceURL ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(skill.sourceURL ?? "")
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
    }

    /// The URL that opens when the user clicks the Source row. Falls back to
    /// the GitHub HTTPS form when the lock file stored an `https://…/foo.git`
    /// URL, since browsers don't render `.git` URLs.
    private var sourceLinkURL: URL? {
        guard let raw = skill.sourceURL, !raw.isEmpty else { return nil }
        let trimmed = raw.hasSuffix(".git") ? String(raw.dropLast(4)) : raw
        return URL(string: trimmed)
    }

    /// Compact display form: drops the scheme and trailing `.git`. e.g.
    /// `https://github.com/imbue-ai/blueprint.git` → `github.com/imbue-ai/blueprint`.
    private var displaySourceURL: String? {
        guard let raw = skill.sourceURL, !raw.isEmpty else { return nil }
        var s = raw
        if s.hasPrefix("https://") { s.removeFirst("https://".count) }
        else if s.hasPrefix("http://") { s.removeFirst("http://".count) }
        if s.hasSuffix(".git") { s.removeLast(4) }
        return s
    }

    // MARK: - Contents

    private var contentsRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("CONTENTS")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(siblingFolders, id: \.self) { folder in
                    FolderChip(name: folder)
                }
            }
        }
    }

    // MARK: - Derived

    private var versionLabel: String? {
        let candidates = [
            skill.frontmatter["version"],
            skill.frontmatter["metadata.version"]
        ].compactMap { $0?.trimmingCharacters(in: .whitespaces) }

        guard let raw = candidates.first(where: { !$0.isEmpty }) else { return nil }
        let cleaned = raw.replacingOccurrences(of: "\"", with: "")
        return cleaned.lowercased().hasPrefix("v") ? cleaned : "v\(cleaned)"
    }

    private var siblingFolders: [String] {
        guard !skill.isRemote else { return [] }
        guard skill.isDirectory else { return [] }
        let fm = FileManager.default
        let parent = URL(fileURLWithPath: skill.filePath).deletingLastPathComponent()

        guard let entries = try? fm.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map(\.lastPathComponent)
            .sorted()
    }
}

// MARK: - Kind pill

private struct KindPill: View {
    let kind: ItemKind

    var body: some View {
        Text(kind.rawValue)
            .font(.system(size: 10, weight: .medium, design: .default))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )
    }
}

// MARK: - Folder chip

private struct FolderChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(name) /")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
