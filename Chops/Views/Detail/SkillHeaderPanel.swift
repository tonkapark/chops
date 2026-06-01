import SwiftUI
import SwiftData
import Foundation

/// Panel above the editor/preview showing the skill's identity (title, slug,
/// version), the tools it's installed in, and quick-access chips for sibling
/// resource folders (templates/, references/, scripts/, …).
struct SkillHeaderPanel: View {
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
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

    private var toolSourcesSummary: String {
        skill.toolSources.map(\.displayName).joined(separator: ", ")
    }

    private var siblingFolders: [String] {
        guard !skill.isRemote else { return [] }
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
