import Foundation

enum SectionID: String, CaseIterable, Identifiable, Hashable {
    case overview, xcode, developer, projects, apps, hidden, explore

    var id: String { rawValue }

    static let scannable: [SectionID] = [.xcode, .developer, .projects, .apps, .hidden]

    var title: String {
        switch self {
        case .overview: "Overview"
        case .xcode: "Xcode"
        case .developer: "Developer tools"
        case .projects: "Project builds"
        case .apps: "App caches & data"
        case .hidden: "Hidden storage"
        case .explore: "Explore"
        }
    }

    var sidebarTitle: String {
        self == .apps ? "Apps" : title
    }

    var symbol: String {
        switch self {
        case .overview: "square.3.layers.3d.down.right"
        case .xcode: "hammer"
        case .developer: "terminal"
        case .projects: "shippingbox"
        case .apps: "square.grid.2x2"
        case .hidden: "eye.slash"
        case .explore: "folder"
        }
    }

    var blurb: String {
        switch self {
        case .overview:
            "Where your disk went."
        case .xcode:
            "Build products, simulators and device symbols pile up with every Xcode release. Simulators and runtimes are removed through simctl, the same way Xcode removes them."
        case .developer:
            "Package caches, toolchains, AI models and container disks that command-line tools keep, mostly in folders Finder hides."
        case .projects:
            "Dependencies and build output inside your projects. All of it comes back with an install or a build."
        case .apps:
            "What your apps keep in ~/Library. Caches rebuild themselves. App data holds settings, accounts and offline files."
        case .hidden:
            "Storage Finder doesn't show you: device backups, installers, snapshots, hidden folders and system files."
        case .explore:
            "Browse any folder by size."
        }
    }
}

enum Safety: Int, Comparable, Hashable {
    case safe, review, personal, info

    static func < (a: Safety, b: Safety) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe: "Rebuilds itself"
        case .review: "Check before removing"
        case .personal: "Contains your data"
        case .info: "Shown for reference"
        }
    }
}

enum CleanAction: Hashable {
    /// Move to Trash or delete, depending on the mode the person picks.
    case remove([URL])
    /// Empty a folder but keep the folder itself.
    case removeContents(URL, permanent: Bool)
    /// Run a tool (simctl, tmutil). `fallback` is emptied if the tool fails.
    case command(tool: String, args: [String], fallback: URL?)
    case none

    var isActionable: Bool {
        if case .none = self { return false }
        return true
    }

    var touchesFiles: Bool {
        switch self {
        case .remove: true
        case .removeContents(_, let permanent): !permanent
        case .command, .none: false
        }
    }

    var describe: String {
        switch self {
        case .remove: "Removes the folder"
        case .removeContents(_, let permanent): permanent ? "Deletes the contents permanently" : "Empties the folder"
        case .command(let tool, let args, _):
            "Runs \((tool as NSString).lastPathComponent) \(args.joined(separator: " "))"
        case .none: "Not removable here"
        }
    }
}

enum ItemIcon: Hashable {
    case symbol(String)
    case file(URL)
}

struct Badge: Hashable {
    enum Tone { case neutral, good, warn, alert }
    let text: String
    var tone: Tone = .neutral
}

struct StorageItem: Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String? = nil
    var url: URL? = nil
    /// -1 when macOS doesn't report a size (snapshots, folders we can't read).
    var bytes: Int64 = 0
    var safety: Safety
    var action: CleanAction
    var icon: ItemIcon = .symbol("folder")
    var date: Date? = nil
    var dateLabel: String = "Modified"
    /// The date is the reason this is recommended (idle project, unused runtime…).
    var staleDate = false
    var badges: [Badge] = []
    var recommended: Bool = false

    var isCleanable: Bool { action.isActionable && safety != .info }
}

struct BulkAction: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let bytes: Int64
    let action: CleanAction

    var asItem: StorageItem {
        StorageItem(id: "bulk:\(id)", title: detail, bytes: bytes, safety: .safe, action: action, icon: .symbol("sparkles"))
    }
}

struct StorageGroup: Identifiable, Hashable {
    let id: String
    var title: String
    var note: String
    var symbol: String
    var items: [StorageItem]
    var bulk: [BulkAction] = []
    /// Groups that re-list space other groups already count (e.g. hidden dot-folders).
    var overlapsOthers = false

    var total: Int64 { items.reduce(0) { $0 + max(0, $1.bytes) } }
    var recommendedBytes: Int64 { items.filter(\.recommended).reduce(0) { $0 + max(0, $1.bytes) } }
}

struct SectionReport {
    var groups: [StorageGroup]
    var date: Date

    var allItems: [StorageItem] { groups.flatMap(\.items) }

    var total: Int64 {
        groups.filter { !$0.overlapsOthers }.reduce(0) { $0 + $1.total }
    }

    var recommendedBytes: Int64 {
        groups.filter { !$0.overlapsOthers }.reduce(0) { $0 + $1.recommendedBytes }
    }

    func item(_ id: String) -> StorageItem? {
        for g in groups { if let i = g.items.first(where: { $0.id == id }) { return i } }
        return nil
    }
}
