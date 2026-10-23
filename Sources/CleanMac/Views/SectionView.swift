import AppKit
import SwiftUI

struct SectionView: View {
    let section: SectionID
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 30)
                if section == .projects {
                    ProjectRootsBar().padding(.bottom, 26)
                }
                if !model.hasFullDiskAccess && (section == .apps || section == .hidden) {
                    AccessBanner().padding(.bottom, 26)
                }
                if let report = model.reports[section] {
                    if report.groups.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 40) {
                            ForEach(report.groups) { group in
                                GroupView(group: group, section: section)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.status[section] ?? "Waiting to scan…")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13))
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .padding(.bottom, 130)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .id(section)
    }

    private var header: some View {
        let report = model.reports[section]
        return VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.5)
            Text(section.blurb)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                if let report {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.bytes(report.total))
                            .font(.system(size: 20, weight: .semibold))
                            .monospacedDigit()
                        Text("found")
                            .foregroundStyle(.secondary)
                    }
                    if report.recommendedBytes > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Fmt.bytes(report.recommendedBytes))
                                .font(.system(size: 20, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.safe)
                            Text("recommended")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if let status = model.status[section], report != nil {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(status).foregroundStyle(.secondary)
                    }
                }
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        if let report, report.recommendedBytes > 0 {
                            Button("Select recommended") { model.selectRecommended(in: section) }
                                .buttonStyle(.glass)
                        }
                        Button {
                            model.scan(section)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .help("Scan this section again")
                        .disabled(model.status[section] != nil)
                    }
                }
            }
            .font(.system(size: 13))
            .padding(.top, 8)
            SafetyLegend().padding(.top, 2)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing here")
                .font(.system(size: 15, weight: .semibold))
            Text(section == .projects
                 ? "No build folders found in the folders above. Add the folder where you keep your code."
                 : "Clean Mac didn't find anything worth listing in this section.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }
}

// MARK: - Group

struct GroupView: View {
    let group: StorageGroup
    let section: SectionID
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    private let collapsedCount = 8

    var body: some View {
        let cleanable = group.items.filter(\.isCleanable)
        let selectedCount = cleanable.filter { model.isSelected($0.id, in: section) }.count
        let shown = expanded ? group.items : Array(group.items.prefix(collapsedCount))

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if !cleanable.isEmpty {
                    Button {
                        model.setSelection(cleanable.map(\.id), selected: selectedCount < cleanable.count, in: section)
                    } label: {
                        CheckCircle(on: selectedCount == cleanable.count, mixed: selectedCount > 0)
                    }
                    .buttonStyle(.plain)
                    .help(selectedCount == cleanable.count ? "Deselect all" : "Select all")
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                }
                Text(group.title)
                    .font(.system(size: 17, weight: .semibold))
                Text("\(group.items.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(group.items.allSatisfy { $0.bytes < 0 } ? "—" : Fmt.bytes(group.total))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)

            Text(group.note)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 640, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.leading, cleanable.isEmpty ? 0 : 26)
                .padding(.top, 5)

            if !group.bulk.isEmpty {
                HStack(spacing: 10) {
                    ForEach(group.bulk) { bulk in
                        Button {
                            model.reviewClean(items: [bulk.asItem], from: section)
                        } label: {
                            Label("\(bulk.title) (\(Fmt.bytes(bulk.bytes)))", systemImage: "sparkles")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.leading, cleanable.isEmpty ? 0 : 26)
                .padding(.top, 10)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(shown) { item in
                ItemRow(item: item, section: section)
            }

            if group.items.count > collapsedCount {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show fewer" : "Show all \(group.items.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.leading, 26)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Row

struct ItemRow: View {
    let item: StorageItem
    let section: SectionID
    @Environment(AppModel.self) private var model
    @State private var hover = false

    var body: some View {
        let selected = model.isSelected(item.id, in: section)
        HStack(spacing: 10) {
            Group {
                if item.isCleanable {
                    CheckCircle(on: selected)
                } else {
                    Color.clear
                }
            }
            .frame(width: 16)

            ItemIconView(icon: item.icon)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if item.recommended {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.safe)
                            .help("Recommended")
                    }
                    ForEach(item.badges.prefix(2), id: \.self) { BadgeView(badge: $0) }
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            if let date = item.date {
                Text("\(item.dateLabel) \(Fmt.ago(date))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(item.staleDate ? AnyShapeStyle(Theme.review) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
                    .fixedSize()
            }
            SafetyDot(safety: item.safety)
            Text(item.bytes < 0 ? "—" : Fmt.bytes(item.bytes))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
                .foregroundStyle(item.bytes < 0 ? .tertiary : .primary)
            RevealButton(url: item.url)
                .opacity(hover && item.url != nil ? 1 : 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.11) : hover ? Color.primary.opacity(0.045) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if item.isCleanable { model.toggle(item.id, in: section) }
        }
        .contextMenu {
            if let url = item.url {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
                Button("Explore Contents") { model.go(.folder(url)) }
            }
            if item.isCleanable {
                Divider()
                Button("Clean This…") { model.reviewClean(items: [item], from: section) }
            }
        }
        .help(item.isCleanable ? item.safety.label : item.subtitle ?? "")
    }
}

// MARK: - Project roots

struct ProjectRootsBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 8) { roots }
    }

    private var roots: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Searching")
                .foregroundStyle(.secondary)
            ForEach(model.projectRoots, id: \.self) { root in
                HStack(spacing: 5) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(Paths.tilde(root))
                    Button {
                        model.setProjectRoots(model.projectRoots.filter { $0 != root })
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Stop searching this folder")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
            }
            Button("Add Folder…") { addFolder() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .font(.system(size: 12))
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = Paths.home
        panel.prompt = "Search for Builds"
        if panel.runModal() == .OK {
            let added = panel.urls.filter { !model.projectRoots.contains($0) }
            model.setProjectRoots(model.projectRoots + added)
        }
    }
}
