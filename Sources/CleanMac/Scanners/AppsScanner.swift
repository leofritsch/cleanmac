import Foundation

enum AppsScanner {
    /// Folder names Chromium, Electron and friends use for disposable caches inside app data.
    static let innerCacheNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GrShaderCache", "GraphiteDawnCache", "ShaderCache", "CacheStorage", "ScriptCache",
        "component_crx_cache", "Crashpad",
    ]

    /// Application Support folders that belong to macOS itself.
    static let systemSupportNames: Set<String> = [
        "AddressBook", "CallHistoryDB", "CallHistoryTransactions", "CloudDocs", "CrashReporter", "Dock",
        "FileProvider", "Knowledge", "MobileSync", "Clean Mac", "SyncServices", "iCloud", "icdd", "networkserviceproxy",
        "AppleMediaServices", "Animoji", "DifferentialPrivacy", "FaceTime", "Accounts", "CallServices",
        "ControlCenter", "DiskImages", "AppStore", "Photos", "ContextStoreAgent", "Siri", "SESStorage",
        "AppleMediaServicesUI", "identityservicesd", "Wallet", "TrustedPeersHelper", "Tips",
    ]

    static func scan(progress: @escaping Progress) async -> [StorageGroup] {
        let claimed = XcodeScanner.claimedPaths.union(DeveloperScanner.claimedPaths)
        func isClaimed(_ url: URL) -> Bool {
            let p = url.standardizedFileURL.path
            return claimed.contains(p) || claimed.contains { $0.hasPrefix(p + "/") }
        }

        progress("Reading ~/Library/Caches…")
        // 1. Regular caches
        var cacheCandidates: [(URL, Owner, sandboxed: Bool)] = []
        for dir in Paths.children(Paths.lib("Caches")) where !isClaimed(dir) {
            cacheCandidates.append((dir, AppIndex.shared.owner(ofFolderNamed: dir.lastPathComponent), false))
        }
        let containers = Paths.subdirectories(Paths.lib("Containers"))
        for c in containers {
            let caches = c.appendingPathComponent("Data/Library/Caches")
            guard Paths.isDirectory(caches), !isClaimed(c) else { continue }
            cacheCandidates.append((caches, AppIndex.shared.owner(ofFolderNamed: c.lastPathComponent), true))
        }

        // 2. Chromium/Electron caches hiding inside Application Support
        progress("Looking inside app data for hidden caches…")
        let support = Paths.lib("Application Support")
        let innerCaches = await Task.detached(priority: .userInitiated) {
            findInnerCaches(in: support).filter { !isClaimed($0) }
        }.value

        progress("Measuring app caches…")
        let cacheSizes = await ScanKit.sizes(cacheCandidates.map(\.0) + innerCaches)

        var cacheItems: [StorageItem] = []
        for (url, owner, sandboxed) in cacheCandidates {
            let bytes = cacheSizes[url.standardizedFileURL.path]?.bytes ?? 0
            guard bytes >= 1_000_000 else { continue }
            var badges: [Badge] = []
            if owner.isLeftover { badges.append(Badge(text: "App not installed", tone: .warn)) }
            cacheItems.append(StorageItem(
                id: url.path, title: owner.name,
                subtitle: sandboxed ? "Sandboxed cache. \(Paths.tilde(url))" : Paths.tilde(url),
                url: url, bytes: bytes, safety: .safe,
                action: sandboxed ? .removeContents(url, permanent: false) : .remove([url]),
                icon: owner.app.map { .file($0.url) } ?? .symbol("archivebox"),
                date: Paths.modified(url), dateLabel: "Updated", badges: badges,
                recommended: bytes >= 50_000_000 && !owner.isApple))
        }

        var innerItems: [StorageItem] = []
        for url in innerCaches {
            let bytes = cacheSizes[url.standardizedFileURL.path]?.bytes ?? 0
            guard bytes >= 5_000_000 else { continue }
            let relative = url.path.dropFirst(support.path.count + 1).split(separator: "/").map(String.init)
            let owner = ownerOfSupportPath(relative)
            innerItems.append(StorageItem(
                id: url.path, title: owner.name,
                subtitle: relative.dropFirst().joined(separator: " › "),
                url: url, bytes: bytes, safety: .safe, action: .removeContents(url, permanent: false),
                icon: owner.app.map { .file($0.url) } ?? .symbol("archivebox"),
                date: Paths.modified(url), dateLabel: "Updated",
                recommended: bytes >= 100_000_000))
        }

        // 3. App data, with the caches above subtracted so nothing is counted twice
        progress("Measuring app data…")
        var dataCandidates: [(URL, Owner, kind: String)] = []
        for dir in Paths.subdirectories(support) where !isClaimed(dir) {
            let name = dir.lastPathComponent
            var owner = AppIndex.shared.owner(ofFolderNamed: name)
            if systemSupportNames.contains(name) || name.hasPrefix("com.apple.") {
                owner = Owner(name: owner.name, app: owner.app, isBundleStyle: owner.isBundleStyle, isApple: true)
            }
            dataCandidates.append((dir, owner, "Application Support"))
        }
        for c in containers where !isClaimed(c) {
            dataCandidates.append((c, AppIndex.shared.owner(ofFolderNamed: c.lastPathComponent), "Container"))
        }
        for g in Paths.subdirectories(Paths.lib("Group Containers")) where !isClaimed(g) {
            let name = g.lastPathComponent
            var owner = AppIndex.shared.owner(ofFolderNamed: name)
            if name.contains("com.apple.") || name.hasPrefix("group.com.apple") {
                owner = Owner(name: owner.name, app: owner.app, isBundleStyle: owner.isBundleStyle, isApple: true)
            }
            dataCandidates.append((g, owner, "Group container"))
        }
        let dataSizes = await ScanKit.sizes(dataCandidates.map(\.0))

        let allCaches = cacheItems + innerItems
        var dataItems: [StorageItem] = []
        var leftoverItems: [StorageItem] = []
        for (url, owner, kind) in dataCandidates {
            let prefix = url.path + "/"
            let cached = allCaches.filter { $0.id.hasPrefix(prefix) }.reduce(0) { $0 + $1.bytes }
            let bytes = (dataSizes[url.standardizedFileURL.path]?.bytes ?? 0) - cached
            guard bytes >= 1_000_000 else { continue }

            var item = StorageItem(
                id: "data:\(url.path)", title: owner.name,
                subtitle: "\(kind). \(Paths.tilde(url))", url: url, bytes: bytes,
                safety: owner.isApple ? .info : .personal,
                action: owner.isApple ? .none : .remove([url]),
                icon: owner.app.map { .file($0.url) } ?? .symbol(owner.isApple ? "applelogo" : "folder"),
                date: Paths.modified(url), dateLabel: "Updated")
            if owner.isLeftover {
                item.badges = [Badge(text: "App not installed", tone: .warn)]
                leftoverItems.append(item)
            } else {
                dataItems.append(item)
            }
        }

        return [
            StorageGroup(
                id: "apps.caches", title: "App caches",
                note: "Files apps keep to load faster. Apps rebuild them as needed; quit an app before clearing its cache.",
                symbol: "archivebox", items: cacheItems.sorted(by: ScanKit.bySize)),
            StorageGroup(
                id: "apps.inner", title: "Caches inside app data",
                note: "Chrome, Slack, Discord, Spotify and other Chromium or Electron apps tuck web and GPU caches inside Application Support, where cleaners usually don't look.",
                symbol: "square.stack.3d.forward.dottedline", items: innerItems.sorted(by: ScanKit.bySize)),
            StorageGroup(
                id: "apps.leftovers", title: "Left behind by removed apps",
                note: "Data for apps that are no longer installed. Clean Mac matches folders to apps by bundle ID, so check anything you don't recognize.",
                symbol: "questionmark.folder", items: leftoverItems.sorted(by: ScanKit.bySize)),
            StorageGroup(
                id: "apps.data", title: "App data",
                note: "Settings, accounts, offline files and history. Removing a folder resets that app. Caches listed above are subtracted.",
                symbol: "folder", items: dataItems.sorted(by: ScanKit.bySize)),
        ].filter { !$0.items.isEmpty }
    }

    private static func ownerOfSupportPath(_ components: [String]) -> Owner {
        guard let first = components.first else { return Owner(name: "Unknown", app: nil, isBundleStyle: false, isApple: false) }
        let owner = AppIndex.shared.owner(ofFolderNamed: first)
        if owner.app == nil, components.count > 1 {
            // "Google/Chrome", "Microsoft/Teams": the vendor folder holds the app folder.
            let inner = AppIndex.shared.owner(ofFolderNamed: components[1])
            if inner.app != nil { return inner }
            return Owner(name: "\(first) \(components[1])", app: nil, isBundleStyle: false, isApple: false)
        }
        return owner
    }

    static func findInnerCaches(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isDirectory == true, v.isSymbolicLink != true else { continue }
            if walker.level > 6 { walker.skipDescendants(); continue }
            if walker.level >= 2, innerCacheNames.contains(url.lastPathComponent) {
                found.append(url)
                walker.skipDescendants()
            }
        }
        return found
    }
}
