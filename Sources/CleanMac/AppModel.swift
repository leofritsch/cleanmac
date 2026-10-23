import AppKit
import Observation
import SwiftUI

struct CleanSession: Identifiable {
    enum Phase {
        case confirm
        case running(title: String, fraction: Double)
        case done(CleanOutcome)
    }

    let id = UUID()
    let section: SectionID?
    let items: [StorageItem]
    var phase: Phase = .confirm

    var bytes: Int64 { items.reduce(0) { $0 + max(0, $1.bytes) } }
}

@MainActor
@Observable
final class AppModel {
    var section: SectionID? = .overview
    var volume = VolumeInfo.current()
    var overview: OverviewReport?
    var overviewStatus: String?
    var reports: [SectionID: SectionReport] = [:]
    var status: [SectionID: String] = [:]
    var selections: [SectionID: Set<String>] = [:]
    var hasFullDiskAccess = Permissions.hasFullDiskAccess()
    var history: [Snapshot] = HistoryStore.load()
    var cleanSession: CleanSession?
    var projectRoots: [URL] = ProjectScanner.storedRoots()
    var freedAllTime = Int64(UserDefaults.standard.integer(forKey: "freedAllTime"))
    var cleanMode = CleanMode(rawValue: UserDefaults.standard.string(forKey: "cleanMode") ?? "") ?? .trash {
        didSet { UserDefaults.standard.set(cleanMode.rawValue, forKey: "cleanMode") }
    }
    let explore = ExploreModel()

    @ObservationIgnored private var tasks: [SectionID: Task<Void, Never>] = [:]
    @ObservationIgnored private var started = false

    var isBusy: Bool { overviewStatus != nil || !status.isEmpty }

    /// The snapshot the current overview is compared against.
    var baseline: Snapshot? {
        guard let overview, overview.complete else { return nil }
        return HistoryStore.baseline(in: history, before: overview.date)
    }

    func start() {
        guard !started else { return }
        started = true
        scanAll()
    }

    func refreshPermissions() {
        let had = hasFullDiskAccess
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
        volume = .current()
        if !had && hasFullDiskAccess { scanAll() }
    }

    // MARK: Scanning

    func scanAll() {
        Task {
            await SizeCache.shared.reset()
            scanOverview()
            for s in SectionID.scannable { scan(s) }
        }
    }

    func scanOverview() {
        tasks[.overview]?.cancel()
        overviewStatus = "Measuring your disk…"
        volume = .current()
        let roots = projectRoots
        tasks[.overview] = Task {
            let report = await OverviewScanner.scan(projectRoots: roots) { partial in
                await MainActor.run { self.overview = partial }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.5)) { self.overview = report }
            self.overviewStatus = nil
            self.volume = report.volume
            // Capture runs come from a shell without folder permissions; their numbers aren't history.
            if !Capture.isActive {
                self.history = HistoryStore.record(report.snapshot, into: self.history)
            }
        }
    }

    func scan(_ s: SectionID) {
        guard SectionID.scannable.contains(s) else { return }
        tasks[s]?.cancel()
        status[s] = "Scanning…"
        let roots = projectRoots
        let progress: Progress = { [weak self] message in
            Task { @MainActor in
                if self?.status[s] != nil { self?.status[s] = message }
            }
        }
        tasks[s] = Task {
            let groups: [StorageGroup]
            switch s {
            case .xcode: groups = await XcodeScanner.scan(progress: progress)
            case .developer: groups = await DeveloperScanner.scan(progress: progress)
            case .projects: groups = await ProjectScanner.scan(roots: roots, progress: progress)
            case .apps: groups = await AppsScanner.scan(progress: progress)
            case .hidden: groups = await HiddenScanner.scan(progress: progress)
            default: groups = []
            }
            guard !Task.isCancelled else { return }
            let report = SectionReport(groups: groups, date: Date())
            self.reports[s] = report
            self.status[s] = nil
            let valid = Set(report.allItems.map(\.id))
            self.selections[s] = self.selections[s, default: []].intersection(valid)
        }
    }

    func setProjectRoots(_ roots: [URL]) {
        projectRoots = roots
        ProjectScanner.save(roots)
        scan(.projects)
    }

    // MARK: Selection

    func isSelected(_ id: String, in s: SectionID) -> Bool { selections[s]?.contains(id) ?? false }

    func toggle(_ id: String, in s: SectionID) {
        if selections[s, default: []].contains(id) { selections[s]?.remove(id) } else { selections[s, default: []].insert(id) }
    }

    func setSelection(_ ids: [String], selected: Bool, in s: SectionID) {
        if selected { selections[s, default: []].formUnion(ids) } else { selections[s, default: []].subtract(ids) }
    }

    func selectRecommended(in s: SectionID) {
        guard let report = reports[s] else { return }
        let ids = report.groups.filter { !$0.overlapsOthers }.flatMap(\.items).filter { $0.recommended && $0.isCleanable }.map(\.id)
        selections[s] = Set(ids)
    }

    func selectedItems(in s: SectionID) -> [StorageItem] {
        guard let report = reports[s], let ids = selections[s] else { return [] }
        var seen = Set<String>()
        return report.allItems.filter { ids.contains($0.id) && seen.insert($0.id).inserted }
    }

    // MARK: Cleaning

    func reviewClean(in s: SectionID) {
        let items = selectedItems(in: s)
        guard !items.isEmpty else { return }
        cleanSession = CleanSession(section: s, items: items)
    }

    func reviewClean(items: [StorageItem], from s: SectionID?) {
        cleanSession = CleanSession(section: s, items: items)
    }

    func runClean() {
        guard var session = cleanSession else { return }
        session.phase = .running(title: session.items.first?.title ?? "", fraction: 0)
        cleanSession = session
        let mode = cleanMode
        Task {
            let outcome = await Cleaner.perform(session.items, mode: mode) { done, total, title in
                await MainActor.run {
                    guard self.cleanSession?.id == session.id else { return }
                    self.cleanSession?.phase = .running(title: title, fraction: total > 0 ? Double(done) / Double(total) : 1)
                }
            }
            self.cleanSession?.phase = .done(outcome)
            self.freedAllTime += outcome.freed
            UserDefaults.standard.set(Int(self.freedAllTime), forKey: "freedAllTime")
            if let s = session.section { self.selections[s] = [] }
            await SizeCache.shared.reset()
            self.volume = .current()
            if let s = session.section, SectionID.scannable.contains(s) { self.scan(s) }
            if session.section == .explore { self.explore.reload() }
        }
    }

    // MARK: Navigation

    func go(_ destination: Destination) {
        switch destination {
        case .section(let s):
            section = s
        case .folder(let url):
            explore.open(url)
            section = .explore
        }
    }
}

// MARK: - Explore

struct ExploreEntry: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let isDirectory: Bool
    var bytes: Int64?
    var files: Int?
    let modified: Date?
}

@MainActor
@Observable
final class ExploreModel {
    var path: URL = Paths.home
    var entries: [ExploreEntry] = []
    var loading = false
    var showHidden = true
    var back: [URL] = []

    @ObservationIgnored private var cancel: CancelFlag?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var loaded = false

    var visible: [ExploreEntry] {
        showHidden ? entries : entries.filter { !$0.name.hasPrefix(".") }
    }

    var total: Int64 { visible.reduce(0) { $0 + ($1.bytes ?? 0) } }

    func loadIfNeeded() {
        if !loaded { load(path) }
    }

    func open(_ url: URL) {
        if url != path { back.append(path) }
        load(url)
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        load(previous)
    }

    func reload() { load(path) }

    private func load(_ url: URL) {
        loaded = true
        cancel?.set()
        task?.cancel()
        path = url
        entries = []
        loading = true
        let flag = CancelFlag()
        cancel = flag

        task = Task {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .totalFileAllocatedSizeKey]
            var list = await Task.detached(priority: .userInitiated) { () -> [ExploreEntry] in
                Paths.children(url, keys: keys).map { u in
                    let v = try? u.resourceValues(forKeys: Set(keys))
                    let isDir = v?.isDirectory == true && v?.isSymbolicLink != true
                    return ExploreEntry(
                        url: u, name: u.lastPathComponent, isDirectory: isDir,
                        bytes: isDir ? nil : Int64(v?.totalFileAllocatedSize ?? 0),
                        files: isDir ? nil : 1, modified: v?.contentModificationDate)
                }
            }.value
            for i in list.indices where list[i].bytes == nil {
                if let r = await SizeCache.shared.cached(list[i].url) {
                    list[i].bytes = r.bytes
                    list[i].files = r.files
                }
            }
            guard !flag.isSet else { return }
            entries = Self.sorted(list)

            let pending = list.filter { $0.bytes == nil }
            await withTaskGroup(of: (String, SizeResult?).self) { group in
                for e in pending {
                    group.addTask { (e.id, await SizeCache.shared.interactiveSize(e.url, cancel: flag)) }
                }
                for await (id, result) in group {
                    guard let result, !flag.isSet, let i = entries.firstIndex(where: { $0.id == id }) else { continue }
                    entries[i].bytes = result.bytes
                    entries[i].files = result.files
                    withAnimation(.snappy(duration: 0.25)) { entries = Self.sorted(entries) }
                }
            }
            if !flag.isSet { loading = false }
        }
    }

    private static func sorted(_ list: [ExploreEntry]) -> [ExploreEntry] {
        list.sorted {
            switch ($0.bytes, $1.bytes) {
            case let (a?, b?): a == b ? $0.name < $1.name : a > b
            case (nil, _?): false
            case (_?, nil): true
            default: $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
}
