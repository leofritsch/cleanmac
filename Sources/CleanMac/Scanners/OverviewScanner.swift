import Foundation

enum LayerID: String, CaseIterable, Codable, Hashable, Identifiable {
    case system, sharedLibrary, apps, xcode, devtools, projects, appdata, caches, mail, icloud
    case documents, downloads, media, otherLibrary, otherHome, hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "macOS & system data"
        case .sharedLibrary: "Shared /Library"
        case .apps: "Applications"
        case .xcode: "Xcode & simulators"
        case .devtools: "Developer tools"
        case .projects: "Code & projects"
        case .appdata: "App data"
        case .caches: "App caches"
        case .mail: "Mail & Messages"
        case .icloud: "iCloud & cloud drives"
        case .documents: "Documents & Desktop"
        case .downloads: "Downloads"
        case .media: "Photos, music & movies"
        case .otherLibrary: "Rest of ~/Library"
        case .otherHome: "Other files in home"
        case .hidden: "Hidden folders"
        }
    }

    var note: String {
        switch self {
        case .system: "macOS, swap, snapshots, other users and anything Clean Mac can't read"
        case .sharedLibrary: "Plug-ins, sound libraries and support files for every user"
        case .apps: "Everything in /Applications"
        case .xcode: "~/Library/Developer and simulator runtimes"
        case .devtools: "Package caches, toolchains, models, Docker"
        case .projects: "Your code folders, dependencies included"
        case .appdata: "Application Support and app containers"
        case .caches: "~/Library/Caches"
        case .mail: "Mailboxes and message attachments"
        case .icloud: "Files downloaded from iCloud Drive and others"
        case .documents: "Documents and Desktop"
        case .downloads: "Your Downloads folder"
        case .media: "Pictures, Music and Movies"
        case .otherLibrary: "Logs, preferences, keychains, saved state"
        case .otherHome: "Other folders and loose files in your home"
        case .hidden: "Dot-folders Finder doesn't show"
        }
    }

    var destination: Destination {
        switch self {
        case .system: .section(.hidden)
        case .sharedLibrary: .folder(URL(fileURLWithPath: "/Library"))
        case .apps: .folder(URL(fileURLWithPath: "/Applications"))
        case .xcode: .section(.xcode)
        case .devtools: .section(.developer)
        case .projects: .section(.projects)
        case .appdata, .caches: .section(.apps)
        case .mail: .section(.hidden)
        case .icloud: .folder(Paths.lib("Mobile Documents"))
        case .documents: .folder(Paths.h("Documents"))
        case .downloads: .folder(Paths.h("Downloads"))
        case .media: .folder(Paths.home)
        case .otherLibrary: .folder(Paths.library)
        case .otherHome: .folder(Paths.home)
        case .hidden: .section(.hidden)
        }
    }
}

enum Destination: Hashable {
    case section(SectionID)
    case folder(URL)
}

struct MeasuredFolder: Hashable, Identifiable {
    var id: String { path }
    let path: String
    let title: String
    let layer: LayerID
    let bytes: Int64
    let denied: Int
}

struct Layer: Identifiable, Hashable {
    var id: LayerID { kind }
    let kind: LayerID
    let bytes: Int64
}

struct OverviewReport {
    var date = Date()
    var volume = VolumeInfo.current()
    var folders: [MeasuredFolder] = []
    var runtimeBytes: Int64 = 0
    var complete = false

    static let runtimePath = "simctl://runtimes"

    var measured: Int64 { folders.reduce(0) { $0 + $1.bytes } }
    var denied: Int { folders.reduce(0) { $0 + $1.denied } }

    /// Largest first. The system layer is whatever's used but not accounted for.
    var layers: [Layer] {
        var sums: [LayerID: Int64] = [:]
        for f in folders { sums[f.layer, default: 0] += f.bytes }
        if complete { sums[.system] = max(0, volume.used - measured) }
        return sums.filter { $0.value > 0 }
            .map { Layer(kind: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    var snapshot: Snapshot {
        Snapshot(
            date: date, used: volume.used, total: volume.total,
            layers: Dictionary(uniqueKeysWithValues: layers.map { ($0.kind.rawValue, $0.bytes) }),
            folders: Dictionary(folders.map { ($0.path, $0.bytes) }, uniquingKeysWith: { a, _ in a }))
    }
}

enum OverviewScanner {
    private struct Target {
        let url: URL
        let title: String
        let layer: LayerID
    }

    static let devHomeFolders: Set<String> = [
        ".npm", ".cache", ".gradle", ".cargo", ".rustup", ".bun", ".m2", ".android", ".pyenv", ".nvm",
        ".conda", ".orbstack", ".docker", ".ollama", ".lmstudio", ".expo", ".pub-cache", ".gem", ".rbenv",
        ".volta", ".pnpm-store", ".yarn", ".node-gyp", ".colima", ".lima", ".vscode", ".cursor", ".swiftpm",
        ".keras", ".diffusionbee", ".nuget", ".composer", ".deno", ".rvm", ".fnm",
        "go", "miniconda3", "anaconda3", "miniforge3", "mambaforge", "flutter",
    ]

    private static func targets(projectRoots: [URL]) -> [Target] {
        var out: [Target] = []
        let rootPaths = Set(projectRoots.map(\.standardizedFileURL.path))
        let devClaims = DeveloperScanner.claimedPaths
        let xcodeClaims = XcodeScanner.claimedPaths

        for child in Paths.children(Paths.home) {
            let name = child.lastPathComponent
            if name == "Library" || name == ".DS_Store" { continue }
            let layer: LayerID
            if rootPaths.contains(child.standardizedFileURL.path) { layer = .projects }
            else {
                switch name {
                case "Documents", "Desktop": layer = .documents
                case "Downloads": layer = .downloads
                case "Movies", "Music", "Pictures": layer = .media
                case "Applications": layer = .apps
                default:
                    if devHomeFolders.contains(name) { layer = .devtools }
                    else if name.hasPrefix(".") { layer = .hidden }
                    else { layer = .otherHome }
                }
            }
            out.append(Target(url: child, title: name == ".Trash" ? "Trash" : "~/\(name)", layer: layer))
        }

        let perChild: [String: LayerID] = [
            "Application Support": .appdata, "Containers": .appdata, "Group Containers": .appdata, "Caches": .caches,
        ]
        for child in Paths.children(Paths.library) {
            let name = child.lastPathComponent
            if let layer = perChild[name] {
                for inner in Paths.children(child) where inner.lastPathComponent != ".DS_Store" {
                    let path = inner.standardizedFileURL.path
                    var innerLayer = layer
                    if xcodeClaims.contains(path) { innerLayer = .xcode }
                    else if devClaims.contains(path) || devClaims.contains(where: { $0.hasPrefix(path + "/") }) { innerLayer = .devtools }
                    let label = name == "Containers" || name == "Group Containers"
                        ? AppIndex.shared.owner(ofFolderNamed: inner.lastPathComponent).name
                        : inner.lastPathComponent
                    out.append(Target(url: inner, title: "\(name) › \(label)", layer: innerLayer))
                }
                continue
            }
            let layer: LayerID
            switch name {
            case "Developer": layer = .xcode
            case "Android", "pnpm": layer = .devtools
            case "Mail", "Messages": layer = .mail
            case "Mobile Documents", "CloudStorage": layer = .icloud
            default: layer = .otherLibrary
            }
            out.append(Target(url: child, title: "~/Library/\(name)", layer: layer))
        }

        for app in Paths.children(URL(fileURLWithPath: "/Applications")) where app.lastPathComponent != ".DS_Store" {
            let isXcode = app.lastPathComponent.hasPrefix("Xcode") && app.pathExtension == "app"
            out.append(Target(url: app, title: app.deletingPathExtension().lastPathComponent, layer: isXcode ? .xcode : .apps))
        }
        for child in Paths.children(URL(fileURLWithPath: "/Library")) where child.lastPathComponent != "Developer" {
            out.append(Target(url: child, title: "/Library/\(child.lastPathComponent)", layer: .sharedLibrary))
        }
        for child in Paths.children(URL(fileURLWithPath: "/Library/Developer")) where child.lastPathComponent != "CoreSimulator" {
            out.append(Target(url: child, title: "/Library/Developer/\(child.lastPathComponent)", layer: .devtools))
        }
        for path in ["/opt/homebrew", "/usr/local"] where Paths.exists(URL(fileURLWithPath: path)) {
            out.append(Target(url: URL(fileURLWithPath: path), title: path, layer: .devtools))
        }
        if Paths.exists(URL(fileURLWithPath: "/Users/Shared")) {
            out.append(Target(url: URL(fileURLWithPath: "/Users/Shared"), title: "/Users/Shared", layer: .otherHome))
        }
        return out
    }

    static func scan(projectRoots: [URL], update: @escaping @Sendable (OverviewReport) async -> Void) async -> OverviewReport {
        var report = OverviewReport()
        let list = targets(projectRoots: projectRoots)

        await withTaskGroup(of: MeasuredFolder?.self) { group in
            group.addTask {
                let bytes = await XcodeScanner.runtimeBytes()
                guard bytes > 0 else { return nil }
                return MeasuredFolder(path: OverviewReport.runtimePath, title: "Simulator runtimes", layer: .xcode, bytes: bytes, denied: 0)
            }
            for t in list {
                group.addTask {
                    let r = await SizeCache.shared.size(t.url)
                    return MeasuredFolder(path: t.url.standardizedFileURL.path, title: t.title, layer: t.layer, bytes: r.bytes, denied: r.denied)
                }
            }
            var lastPush = Date.distantPast
            for await folder in group {
                if let folder { report.folders.append(folder) }
                if Date().timeIntervalSince(lastPush) > 0.25 {
                    lastPush = Date()
                    await update(report)
                }
            }
        }
        report.volume = .current()
        report.complete = true
        return report
    }
}
