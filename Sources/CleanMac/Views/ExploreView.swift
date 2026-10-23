import AppKit
import SwiftUI

struct ExploreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let explore = model.explore
        VStack(alignment: .leading, spacing: 0) {
            header(explore)
                .padding(.horizontal, 40)
                .padding(.top, 30)
                .padding(.bottom, 16)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            list(explore)
        }
        .onAppear { explore.loadIfNeeded() }
    }

    private func header(_ explore: ExploreModel) -> some View {
        @Bindable var explore = explore
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Explore")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.5)
                Spacer()
                Toggle("Hidden files", isOn: $explore.showHidden)
                    .toggleStyle(.checkbox)
                    .tint(Theme.accent)
                    .font(.system(size: 12))
                Picker("", selection: Binding(
                    get: { rootMatch(explore.path) },
                    set: { explore.open($0) }
                )) {
                    Text("Home").tag(Paths.home)
                    Text("Library").tag(Paths.library)
                    Text("Applications").tag(URL(fileURLWithPath: "/Applications"))
                    Text("Macintosh HD").tag(URL(fileURLWithPath: "/"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(Theme.accent)
                .fixedSize()
            }
            HStack(spacing: 8) {
                Button {
                    explore.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.glass)
                .disabled(explore.back.isEmpty)
                .keyboardShortcut("[", modifiers: .command)
                Breadcrumb(url: explore.path) { explore.open($0) }
                Spacer()
                if explore.loading { ProgressView().controlSize(.small) }
                Text("\(Fmt.bytes(explore.total)) in \(explore.visible.count) items")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rootMatch(_ path: URL) -> URL {
        let roots = [Paths.home, Paths.library, URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/")]
        return roots.first { $0.standardizedFileURL.path == path.standardizedFileURL.path } ?? path
    }

    private func list(_ explore: ExploreModel) -> some View {
        let entries = explore.visible
        let largest = entries.compactMap(\.bytes).max() ?? 1
        let total = max(1, explore.total)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    ExploreRow(entry: entry, largest: largest, total: total)
                }
                if entries.isEmpty && !explore.loading {
                    Text("This folder is empty, or Clean Mac isn't allowed to read it.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 10)
            .padding(.bottom, 100)
        }
    }
}

private struct Breadcrumb: View {
    let url: URL
    let open: (URL) -> Void

    var body: some View {
        let parts = url.standardizedFileURL.pathComponents
        HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                if i > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Button(i == 0 ? "Macintosh HD" : part) {
                    open(URL(fileURLWithPath: NSString.path(withComponents: Array(parts.prefix(i + 1)))))
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: i == parts.count - 1 ? .semibold : .regular))
                .foregroundStyle(i == parts.count - 1 ? .primary : .secondary)
                .lineLimit(1)
            }
        }
    }
}

private struct ExploreRow: View {
    let entry: ExploreEntry
    let largest: Int64
    let total: Int64
    @Environment(AppModel.self) private var model
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.icon(for: entry.url))
                .resizable()
                .frame(width: 20, height: 20)
            Text(entry.name)
                .font(.system(size: 13))
                .foregroundStyle(entry.name.hasPrefix(".") ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: 16)
            if let files = entry.files, entry.isDirectory {
                Text("\(files.formatted()) files")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            if let modified = entry.modified {
                Text(Fmt.ago(modified))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(width: 110, alignment: .trailing)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: entry.bytes.map { max(2, geo.size.width * CGFloat($0) / CGFloat(max(1, largest))) } ?? 0, height: 4)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 120, height: 10)
            Group {
                if let bytes = entry.bytes {
                    Text(Fmt.bytes(bytes))
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .frame(width: 80, alignment: .trailing)
            Text(entry.bytes.map { percent($0) } ?? "")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .opacity(entry.isDirectory ? 1 : 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if entry.isDirectory { model.explore.open(entry.url) } }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Button("Open") { NSWorkspace.shared.open(entry.url) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url.path, forType: .string)
            }
            Divider()
            Button("Move to Trash…") {
                model.reviewClean(items: [StorageItem(
                    id: entry.id, title: entry.name, subtitle: Paths.tilde(entry.url), url: entry.url,
                    bytes: entry.bytes ?? 0, safety: .personal, action: .remove([entry.url]))], from: .explore)
            }
        }
    }

    private func percent(_ bytes: Int64) -> String {
        let p = Double(bytes) / Double(total) * 100
        return p < 1 ? "" : "\(Int(p.rounded()))%"
    }
}
