import Foundation

private struct SimDevice: Decodable {
    let name: String
    let udid: String
    let state: String?
    let isAvailable: Bool?
    let dataPathSize: Int64?
    let logPathSize: Int64?
    let lastBootedAt: String?
}

private struct SimDeviceList: Decodable {
    let devices: [String: [SimDevice]]
}

private struct SimRuntime: Decodable {
    let identifier: String
    let version: String?
    let build: String?
    let sizeBytes: Int64?
    let lastUsedAt: String?
    let state: String?
    let deletable: Bool?
    let platformIdentifier: String?
    let runtimeIdentifier: String?
}

enum XcodeScanner {
    static let xcrun = "/usr/bin/xcrun"

    /// simctl ships with Xcode. Without developer tools, /usr/bin/xcrun opens Apple's
    /// "install command line developer tools" dialog instead of running, so look for simctl first.
    static func simctl(_ args: [String]) async -> ShellResult {
        let developerDir = await Shell.run("/usr/bin/xcode-select", ["-p"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !developerDir.isEmpty, Paths.exists(URL(fileURLWithPath: developerDir + "/usr/bin/simctl")) else {
            return ShellResult(status: -1, output: Data(), error: "Xcode isn't installed.")
        }
        return await Shell.run(xcrun, ["simctl"] + args)
    }

    /// Paths this section owns, so other sections don't list them twice.
    static let claimedPaths: Set<String> = Set(cacheCatalog.map { ScanKit.resolve($0.path).path })

    static func scan(progress: @escaping Progress) async -> [StorageGroup] {
        progress("Asking simctl about simulators…")
        async let sims = simulators()
        async let derived = derivedData()
        async let support = deviceSupport()
        async let archives = archives()
        async let previews = previewsAndTests()
        async let caches = cachesAndLogs()
        async let installs = installations()

        let s = await sims
        progress("Measuring Xcode folders…")
        let groups = [await derived, s.runtimes, s.devices, await support, await previews, await caches, await archives, await installs]
        return groups.filter { !$0.items.isEmpty }.sorted { $0.total > $1.total }
    }

    /// Total of simulator runtimes, used by the overview.
    static func runtimeBytes() async -> Int64 {
        let r = await simctl(["runtime", "list", "-j"])
        let runtimes = (try? JSONDecoder().decode([String: SimRuntime].self, from: r.output)) ?? [:]
        return runtimes.values.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    // MARK: Derived data

    static func derivedData() async -> StorageGroup {
        let root = Paths.lib("Developer/Xcode/DerivedData")
        let shared = [
            "ModuleCache.noindex": "Module cache",
            "CompilationCache.noindex": "Compilation cache",
            "SymbolCache.noindex": "Symbol cache",
            "SDKStatCaches.noindex": "SDK stat cache",
        ]
        var items: [StorageItem] = []
        for dir in Paths.subdirectories(root) {
            let name = dir.lastPathComponent
            if let title = shared[name] {
                items.append(StorageItem(
                    id: dir.path, title: title, subtitle: "Shared by every project", url: dir,
                    safety: .safe, action: .remove([dir]), icon: .symbol("cube"),
                    date: Paths.modified(dir), recommended: true))
                continue
            }
            let info = Paths.plist(dir.appendingPathComponent("info.plist")) ?? [:]
            let workspace = (info["WorkspacePath"] as? String).map { URL(fileURLWithPath: $0) }
            let lastBuilt = (info["LastAccessedDate"] as? Date) ?? Paths.modified(dir)
            let parts = name.split(separator: "-")
            let project = parts.count > 1 ? parts.dropLast().joined(separator: "-") : name

            var badges: [Badge] = []
            var recommended = false
            let projectExists = workspace.map(Paths.exists) ?? true
            if !projectExists {
                badges.append(Badge(text: "Project is gone", tone: .alert))
                recommended = true
            }
            let idle = lastBuilt.map { Fmt.days(since: $0) > 30 } ?? false
            if idle { recommended = true }
            items.append(StorageItem(
                id: dir.path, title: project,
                subtitle: workspace.map(Paths.tilde) ?? Paths.tilde(dir), url: dir,
                safety: .safe, action: .remove([dir]),
                icon: (workspace.flatMap { projectExists ? $0 : nil }).map { .file($0) } ?? .symbol("hammer"),
                date: lastBuilt, dateLabel: "Built", staleDate: idle, badges: badges, recommended: recommended))
        }
        items = await ScanKit.fill(items).sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "xcode.derived", title: "Derived Data",
            note: "Build intermediates and indexes, one folder per project. Xcode recreates them on the next build, which is slower the first time.",
            symbol: "hammer", items: items)
    }

    // MARK: Simulators

    static func simulators() async -> (runtimes: StorageGroup, devices: StorageGroup) {
        async let devOut = simctl(["list", "devices", "-j"])
        async let rtOut = simctl(["runtime", "list", "-j"])
        let (d, r) = await (devOut, rtOut)
        let deviceList = (try? JSONDecoder().decode(SimDeviceList.self, from: d.output))?.devices ?? [:]
        let runtimes = (try? JSONDecoder().decode([String: SimRuntime].self, from: r.output)) ?? [:]

        // Devices
        var deviceItems: [StorageItem] = []
        var unavailableBytes: Int64 = 0
        var unavailableCount = 0
        for (runtimeKey, devices) in deviceList {
            let runtimeName = displayName(forRuntime: runtimeKey)
            for dev in devices {
                let dir = Paths.lib("Developer/CoreSimulator/Devices/\(dev.udid)")
                let opened = Date.iso(dev.lastBootedAt)
                let available = dev.isAvailable ?? true
                let running = dev.state == "Booted"
                var badges: [Badge] = []
                var recommended = false
                if !available {
                    badges.append(Badge(text: "Unavailable", tone: .alert))
                    recommended = true
                }
                if running { badges.append(Badge(text: "Running", tone: .good)) }
                let unused = available && (opened.map { Fmt.days(since: $0) > 180 } ?? false)
                if unused { recommended = true }
                let bytes = (dev.dataPathSize ?? 0) + (dev.logPathSize ?? 0)
                if !available { unavailableBytes += bytes; unavailableCount += 1 }
                deviceItems.append(StorageItem(
                    id: "sim:\(dev.udid)", title: dev.name,
                    subtitle: available ? runtimeName : "\(runtimeName), runtime no longer installed",
                    url: dir, bytes: bytes,
                    safety: available ? .review : .safe,
                    action: .command(tool: xcrun, args: ["simctl", "delete", dev.udid], fallback: nil),
                    icon: .symbol(deviceSymbol(dev.name)),
                    date: opened, dateLabel: "Opened", staleDate: unused, badges: badges,
                    recommended: recommended && !running))
            }
        }
        deviceItems = await ScanKit.fill(deviceItems).sorted(by: ScanKit.bySize)

        var bulk: [BulkAction] = []
        if unavailableCount > 0 {
            bulk.append(BulkAction(
                id: "sim.unavailable", title: "Delete unavailable",
                detail: "Delete \(unavailableCount) unavailable simulator\(unavailableCount == 1 ? "" : "s")",
                bytes: unavailableBytes,
                action: .command(tool: xcrun, args: ["simctl", "delete", "unavailable"], fallback: nil)))
        }
        let devicesGroup = StorageGroup(
            id: "xcode.devices", title: "Simulators",
            note: "Each simulator keeps its own installed apps, photos and data. Deleting one removes it from Xcode's device list; you can add it back in Devices and Simulators.",
            symbol: "iphone", items: deviceItems, bulk: bulk)

        // Runtimes
        let deviceCount = deviceList.mapValues(\.count)
        let platforms = [
            "com.apple.platform.iphonesimulator": "iOS",
            "com.apple.platform.appletvsimulator": "tvOS",
            "com.apple.platform.watchsimulator": "watchOS",
            "com.apple.platform.xrsimulator": "visionOS",
        ]
        let sameVersion = Dictionary(grouping: runtimes.values) { "\($0.platformIdentifier ?? "")|\($0.version ?? "")" }
        var runtimeItems: [StorageItem] = []
        for rt in runtimes.values {
            let platform = platforms[rt.platformIdentifier ?? ""] ?? "Simulator"
            let lastUsed = Date.iso(rt.lastUsedAt)
            let devices = deviceCount[rt.runtimeIdentifier ?? ""] ?? 0
            var badges: [Badge] = []
            var recommended = false

            let siblings = sameVersion["\(rt.platformIdentifier ?? "")|\(rt.version ?? "")"] ?? []
            if siblings.count > 1 {
                let keep = siblings.max { (Date.iso($0.lastUsedAt) ?? .distantPast) < (Date.iso($1.lastUsedAt) ?? .distantPast) }
                if keep?.identifier != rt.identifier {
                    badges.append(Badge(text: "Duplicate of a newer copy", tone: .alert))
                    recommended = true
                }
            }
            if let state = rt.state, state != "Ready" {
                badges.append(Badge(text: state, tone: .alert))
                recommended = true
            }
            let unused = lastUsed.map { Fmt.days(since: $0) > 180 } ?? false
            if unused { recommended = true }
            let deletable = rt.deletable ?? true
            if !deletable { badges.append(Badge(text: "Managed by macOS")) }

            runtimeItems.append(StorageItem(
                id: "runtime:\(rt.identifier)",
                title: "\(platform) \(rt.version ?? "")",
                subtitle: "Build \(rt.build ?? "?"), \(devices) simulator\(devices == 1 ? "" : "s")",
                bytes: rt.sizeBytes ?? 0,
                safety: deletable ? .review : .info,
                action: deletable ? .command(tool: xcrun, args: ["simctl", "runtime", "delete", rt.identifier], fallback: nil) : .none,
                icon: .symbol("square.stack.3d.up"),
                date: lastUsed, dateLabel: "Used", staleDate: unused, badges: badges,
                recommended: recommended && deletable))
        }
        runtimeItems.sort(by: ScanKit.bySize)
        let runtimesGroup = StorageGroup(
            id: "xcode.runtimes", title: "Simulator runtimes",
            note: "A full copy of each OS version you've downloaded for the simulator. Xcode › Settings › Components downloads any of them again.",
            symbol: "square.stack.3d.up", items: runtimeItems)

        return (runtimesGroup, devicesGroup)
    }

    static func displayName(forRuntime key: String) -> String {
        guard let tail = key.components(separatedBy: "SimRuntime.").last else { return key }
        let parts = tail.split(separator: "-")
        guard let first = parts.first else { return tail }
        return "\(first) \(parts.dropFirst().joined(separator: "."))"
    }

    static func deviceSymbol(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("ipad") { return "ipad" }
        if n.contains("watch") { return "applewatch" }
        if n.contains("tv") { return "appletv" }
        if n.contains("vision") { return "visionpro" }
        return "iphone"
    }

    // MARK: Device support

    static func deviceSupport() async -> StorageGroup {
        let base = Paths.lib("Developer/Xcode")
        let platforms = ["iOS", "watchOS", "tvOS", "visionOS", "macOS"]
        let pattern = try? NSRegularExpression(pattern: #"^(?:(\S+) )?(\d+(?:\.\d+)*)(?: \((\w+)\))?"#)
        var items: [StorageItem] = []

        for platform in platforms {
            let dirs = Paths.subdirectories(base.appendingPathComponent("\(platform) DeviceSupport"))
            let parsed: [(dir: URL, model: String?, version: String?, build: String?)] = dirs.map { dir in
                let name = dir.lastPathComponent
                let ns = name as NSString
                guard let m = pattern?.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else {
                    return (dir, nil, nil, nil)
                }
                func group(_ i: Int) -> String? {
                    let r = m.range(at: i)
                    return r.location == NSNotFound ? nil : ns.substring(with: r)
                }
                return (dir, group(1), group(2), group(3))
            }
            let newest = parsed.compactMap(\.version).max(by: ScanKit.versionLess)

            for p in parsed {
                let added = Paths.modified(p.dir)
                var badges: [Badge] = []
                var recommended = false
                if let v = p.version, let newest, ScanKit.versionLess(v, newest) {
                    badges.append(Badge(text: "Newer \(platform) present", tone: .warn))
                    if let added, Fmt.days(since: added) > 30 { recommended = true }
                }
                let old = added.map { Fmt.days(since: $0) > 180 } ?? false
                if old { recommended = true }
                let title = p.version.map { "\(platform) \($0)" + (p.build.map { " (\($0))" } ?? "") } ?? p.dir.lastPathComponent
                items.append(StorageItem(
                    id: p.dir.path, title: title,
                    subtitle: p.model ?? "\(platform) DeviceSupport", url: p.dir,
                    safety: .review, action: .remove([p.dir]), icon: .symbol(platform == "watchOS" ? "applewatch" : "iphone.gen3"),
                    date: added, dateLabel: "Added", staleDate: old, badges: badges, recommended: recommended))
            }
        }
        items = await ScanKit.fill(items).sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "xcode.support", title: "Device support",
            note: "Debug symbols Xcode copies from a real device the first time you run on it, one copy per OS version. Xcode copies them again if you plug that device in.",
            symbol: "cable.connector", items: items)
    }

    // MARK: Archives

    static func archives() async -> StorageGroup {
        let root = Paths.lib("Developer/Xcode/Archives")
        var items: [StorageItem] = []
        for day in Paths.subdirectories(root) {
            for archive in Paths.children(day) where archive.pathExtension == "xcarchive" {
                let info = Paths.plist(archive.appendingPathComponent("Info.plist")) ?? [:]
                let props = info["ApplicationProperties"] as? [String: Any] ?? [:]
                let name = info["Name"] as? String ?? archive.deletingPathExtension().lastPathComponent
                let version = props["CFBundleShortVersionString"] as? String
                let build = props["CFBundleVersion"] as? String
                let created = info["CreationDate"] as? Date ?? Paths.modified(archive)
                var title = name
                if let version { title += " \(version)" }
                if let build { title += " (\(build))" }
                items.append(StorageItem(
                    id: archive.path, title: title,
                    subtitle: props["CFBundleIdentifier"] as? String ?? Paths.tilde(archive), url: archive,
                    safety: .review, action: .remove([archive]), icon: .symbol("archivebox"),
                    date: created, dateLabel: "Archived",
                    staleDate: created.map { Fmt.days(since: $0) > 365 } ?? false))
            }
        }
        items = await ScanKit.fill(items).sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "xcode.archives", title: "Archives",
            note: "Builds you archived for distribution. Keep the ones you shipped: they hold the symbols that make crash reports readable.",
            symbol: "archivebox", items: items)
    }

    // MARK: Previews, playgrounds, tests

    static func previewsAndTests() async -> StorageGroup {
        let previews = Paths.lib("Developer/Xcode/UserData/Previews")
        let playgrounds = Paths.lib("Developer/XCPGDevices")
        let tests = Paths.lib("Developer/XCTestDevices")
        var items: [StorageItem] = []
        if Paths.exists(previews) {
            items.append(StorageItem(
                id: previews.path, title: "SwiftUI previews", subtitle: "Simulators Xcode boots to render #Preview",
                url: previews, safety: .safe,
                action: .command(tool: xcrun, args: ["simctl", "--set", "previews", "delete", "all"], fallback: previews),
                icon: .symbol("eye"), date: Paths.modified(previews), recommended: true))
        }
        if Paths.exists(playgrounds) {
            items.append(StorageItem(
                id: playgrounds.path, title: "Playground simulators", subtitle: "Devices Xcode creates to run playgrounds",
                url: playgrounds, safety: .safe,
                action: .command(tool: xcrun, args: ["simctl", "--set", playgrounds.path, "delete", "all"], fallback: playgrounds),
                icon: .symbol("play.square"), date: Paths.modified(playgrounds), recommended: true))
        }
        if Paths.exists(tests) {
            items.append(StorageItem(
                id: tests.path, title: "Test clones", subtitle: "Simulator copies made for parallel testing",
                url: tests, safety: .safe,
                action: .command(tool: xcrun, args: ["simctl", "--set", "testing", "delete", "all"], fallback: tests),
                icon: .symbol("checkmark.diamond"), date: Paths.modified(tests), recommended: true))
        }
        items = await ScanKit.fill(items).filter { $0.bytes > 1_000_000 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "xcode.previews", title: "Previews, playgrounds & tests",
            note: "Throwaway simulators Xcode creates behind the scenes. Removed with simctl; Xcode makes fresh ones when it needs them.",
            symbol: "eye", items: items)
    }

    // MARK: Caches & logs

    struct CacheEntry {
        let path: String
        let title: String
        let subtitle: String
        var safety: Safety = .safe
        var recommended = true
    }

    static let cacheCatalog: [CacheEntry] = [
        CacheEntry(path: "Library/Caches/com.apple.dt.Xcode", title: "Xcode cache", subtitle: "Downloads and temporary data"),
        CacheEntry(path: "Library/Developer/Xcode/DocumentationCache", title: "Documentation cache", subtitle: "Downloaded developer documentation"),
        CacheEntry(path: "Library/Developer/Xcode/DocumentationIndex", title: "Documentation index", subtitle: "Search index for documentation"),
        CacheEntry(path: "Library/Developer/CoreSimulator/Caches", title: "Simulator caches", subtitle: "Shared dyld caches for simulators"),
        CacheEntry(path: "Library/Logs/CoreSimulator", title: "Simulator logs", subtitle: "Logs written by every simulator"),
        CacheEntry(path: "Library/Developer/Xcode/iOS Device Logs", title: "Device logs", subtitle: "Logs and crash reports pulled from devices", safety: .review, recommended: false),
        CacheEntry(path: "Library/Developer/Xcode/DeviceLogs", title: "Device logs (new)", subtitle: "Logs pulled from devices", safety: .review, recommended: false),
        CacheEntry(path: "Library/Developer/Xcode/Products", title: "Build products", subtitle: "Products built for previews and testing"),
        CacheEntry(path: "Library/Caches/org.swift.swiftpm", title: "Swift Package cache", subtitle: "Downloaded package sources"),
        CacheEntry(path: "Library/Caches/com.apple.dt.instruments", title: "Instruments cache", subtitle: "Symbol caches for profiling"),
        CacheEntry(path: "Library/Developer/DVTDownloads", title: "Component downloads", subtitle: "Installers Xcode already used"),
        CacheEntry(path: "Library/Developer/DeveloperDiskImages", title: "Developer disk images", subtitle: "Images mounted on devices for debugging", safety: .review, recommended: false),
        CacheEntry(path: "Library/Developer/Xcode/UserData/IB Support", title: "Interface Builder support", subtitle: "Rendering helpers for storyboards"),
    ]

    static func cachesAndLogs() async -> StorageGroup {
        var items: [StorageItem] = []
        for entry in cacheCatalog {
            let url = ScanKit.resolve(entry.path)
            guard Paths.exists(url) else { continue }
            items.append(StorageItem(
                id: url.path, title: entry.title, subtitle: entry.subtitle, url: url,
                safety: entry.safety, action: .remove([url]), icon: .symbol("internaldrive"),
                date: Paths.modified(url), recommended: entry.recommended))
        }
        items = await ScanKit.fill(items).filter { $0.bytes > 1_000_000 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "xcode.caches", title: "Caches & logs",
            note: "Downloads, indexes and logs Xcode and the simulator write as they run.",
            symbol: "internaldrive", items: items)
    }

    // MARK: Installations

    static func installations() async -> StorageGroup {
        let active = await Shell.run("/usr/bin/xcode-select", ["-p"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [StorageItem] = []
        for app in Paths.children(URL(fileURLWithPath: "/Applications"))
        where app.pathExtension == "app" && app.lastPathComponent.hasPrefix("Xcode") {
            let info = Paths.plist(app.appendingPathComponent("Contents/Info.plist")) ?? [:]
            guard (info["CFBundleIdentifier"] as? String) == "com.apple.dt.Xcode" else { continue }
            let version = info["CFBundleShortVersionString"] as? String ?? ""
            let build = Paths.plist(app.appendingPathComponent("Contents/version.plist"))?["ProductBuildVersion"] as? String
            let isActive = !active.isEmpty
                && URL(fileURLWithPath: active).resolvingSymlinksInPath().path.hasPrefix(app.resolvingSymlinksInPath().path + "/")
            items.append(StorageItem(
                id: app.path, title: "Xcode \(version)" + (build.map { " (\($0))" } ?? ""),
                subtitle: app.path, url: app,
                safety: isActive ? .info : .review,
                action: isActive ? .none : .remove([app]), icon: .file(app),
                badges: [isActive ? Badge(text: "Selected with xcode-select", tone: .good) : Badge(text: "Not selected", tone: .warn)]))
        }
        items = await ScanKit.fill(items).sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "xcode.installs", title: "Xcode installations",
            note: "Every copy of Xcode in Applications. Older betas often stay behind after an update.",
            symbol: "app.badge", items: items)
    }
}
