import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 300)
        } detail: {
            Group {
                switch model.section ?? .overview {
                case .overview: OverviewView()
                case .explore: ExploreView()
                case let s: SectionView(section: s)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // A real bar: lists inset above it and blur softly where they pass underneath.
            .safeAreaBar(edge: .bottom) { CleanBar() }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .background(Theme.canvas)
            .navigationTitle(model.section?.title ?? "Clean Mac")
        }
        .sheet(item: $model.cleanSession) { _ in CleanSheet() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.section) {
            Section {
                row(.overview)
            }
            Section("Find space") {
                ForEach(SectionID.scannable) { row($0) }
            }
            Section("Browse") {
                row(.explore)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { DiskMeter().padding(16) }
    }

    private func row(_ s: SectionID) -> some View {
        HStack(spacing: 8) {
            Label(s.sidebarTitle, systemImage: s.symbol)
            Spacer(minLength: 4)
            if model.status[s] != nil || (s == .overview && model.overviewStatus != nil) {
                ProgressView().controlSize(.mini)
            } else if let total = model.reports[s]?.total, total > 0 {
                Text(Fmt.bytes(total))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .tag(s)
    }
}

struct DiskMeter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let v = model.volume
        let critical = v.total > 0 && Double(v.important) / Double(v.total) < 0.05
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Macintosh HD")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((v.fraction * 100).rounded()))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(critical ? Theme.personal : Theme.accent)
                        .frame(width: max(4, geo.size.width * v.fraction))
                }
            }
            .frame(height: 5)
            Text("\(Fmt.bytes(v.important)) free of \(Fmt.bytes(v.total))")
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(critical ? Theme.personal : .primary)
            if model.freedAllTime > 0 {
                Text("Clean Mac has freed \(Fmt.bytes(model.freedAllTime))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CleanBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let section = model.section ?? .overview
        let items = model.selectedItems(in: section)
        let bytes = items.reduce(Int64(0)) { $0 + max(0, $1.bytes) }

        ZStack {
            if !items.isEmpty {
                GlassEffectContainer(spacing: 14) {
                    HStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Text("\(items.count) selected")
                                .foregroundStyle(.secondary)
                            Text(Fmt.bytes(bytes))
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Button {
                                model.selections[section] = []
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 18, height: 18)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Clear selection")
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 12)
                        .frame(height: 44)
                        .glassEffect(.regular, in: .capsule)

                        Button {
                            model.reviewClean(in: section)
                        } label: {
                            Text("Review & clean")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .font(.system(size: 13))
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.12), value: items.isEmpty)
        .animation(.snappy(duration: 0.2), value: bytes)
    }
}
