import Foundation

enum HiddenScanner {
    static func scan(progress: @escaping Progress) async -> [StorageGroup] {
        progress("Checking backups, installers and snapshots…")
        async let mobile = mobileDevices()
        async let installers = installers()
        async let trash = trash()
        async let large = largeFiles()
        async let cloud = cloudDrives()
        async let media = mediaLibraries()
        async let mail = mailAndMessages()
        async let vms = virtualMachines()
        async let logs = logs()
        async let snapshots = snapshots()
        async let system = systemFiles()
        async let dots = dotFolders()

        var groups = [await mobile, await installers, await trash, await large, await cloud, await media,
                      await mail, await vms, await logs, await snapshots, await system]
        groups = groups.filter { !$0.items.isEmpty }
        let dotGroup = await dots
        if !dotGroup.items.isEmpty { groups.append(dotGroup) }
        return groups
    }

    // MARK: iPhone & iPad

    static func mobileDevices() async -> StorageGroup {
        var items: [StorageItem] = []
        let backups = Paths.lib("Application Support/MobileSync/Backup")
        if Paths.exists(backups) {
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) != nil
            if readable {
                for b in Paths.subdirectories(backups) {
                    let info = Paths.plist(b.appendingPathComponent("Info.plist")) ?? [:]
                    let device = info["Device Name"] as? String ?? "Device backup"
                    let product = info["Product Name"] as? String ?? info["Product Type"] as? String
                    let ios = info["Product Version"] as? String
                    items.append(StorageItem(
                        id: b.path, title: device,
                        subtitle: [product, ios.map { "iOS \($0)" }].compactMap { $0 }.joined(separator: ", "),
                        url: b, safety: .personal, action: .remove([b]), icon: .symbol("iphone"),
                        date: info["Last Backup Date"] as? Date ?? Paths.modified(b), dateLabel: "Backed up"))
                }
            } else {
                items.append(StorageItem(
                    id: backups.path, title: "Device backups",
                    subtitle: "Clean Mac needs Full Disk Access to look inside", url: backups,
                    bytes: -1, safety: .info, action: .none, icon: .symbol("lock")))
            }
        }
        for (folder, title) in [("iPhone Software Updates", "iPhone software updates"), ("iPad Software Updates", "iPad software updates")] {
            let dir = Paths.lib("iTunes/\(folder)")
            guard Paths.exists(dir) else { continue }
            items.append(StorageItem(
                id: dir.path, title: title, subtitle: "Firmware Finder downloaded to update or restore a device",
                url: dir, safety: .safe, action: .removeContents(dir, permanent: false),
                icon: .symbol("arrow.down.circle"), date: Paths.modified(dir), recommended: true))
        }
        items = await ScanKit.fill(items).filter { $0.bytes != 0 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "hidden.mobile", title: "iPhone & iPad",
            note: "Local backups made by Finder can be tens of gigabytes each, and old ones stay after you replace a phone.",
            symbol: "iphone", items: items)
    }

    // MARK: Installers

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "ipsw"]
    static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "7z", "rar", "bz2", "xz"]

    static func installers() async -> StorageGroup {
        let items = await Task.detached(priority: .userInitiated) { () -> [StorageItem] in
            var out: [StorageItem] = []
            for (root, depth) in [(Paths.h("Downloads"), 3), (Paths.h("Desktop"), 1), (Paths.home, 0)] {
                for file in files(in: root, maxDepth: depth, minBytes: 20_000_000) {
                    let ext = file.url.pathExtension.lowercased()
                    let isInstaller = installerExtensions.contains(ext)
                    guard isInstaller || archiveExtensions.contains(ext) else { continue }
                    let added = file.added ?? file.modified
                    let old = added.map { Fmt.days(since: $0) > 14 } ?? false
                    // A disk image you made yourself (an encrypted or folder image) has no quarantine flag
                    let downloaded = isInstaller && wasDownloaded(file.url)
                    out.append(StorageItem(
                        id: file.url.path, title: file.url.lastPathComponent,
                        subtitle: Paths.tilde(file.url.deletingLastPathComponent()),
                        url: file.url, bytes: file.bytes, safety: .review, action: .remove([file.url]),
                        icon: .file(file.url), date: added, dateLabel: "Added",
                        staleDate: isInstaller && old, recommended: downloaded && old))
                }
            }
            return out
        }.value
        return StorageGroup(
            id: "hidden.installers", title: "Installers & archives",
            note: "Disk images, packages and archives you already opened. Installers are usually safe to drop once the app is installed.",
            symbol: "shippingbox.and.arrow.backward", items: items.sorted(by: ScanKit.bySize))
    }

    /// Files from a browser, Mail or AirDrop carry a quarantine flag.
    static func wasDownloaded(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    // MARK: Trash

    static func trash() async -> StorageGroup {
        let dir = Paths.h(".Trash")
        var items: [StorageItem] = []
        if let kids = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            let visible = kids.filter { $0 != ".DS_Store" }
            if !visible.isEmpty {
                let size = await SizeCache.shared.size(dir)
                items.append(StorageItem(
                    id: dir.path, title: "Trash", subtitle: "\(visible.count) item\(visible.count == 1 ? "" : "s") waiting to be deleted",
                    url: dir, bytes: size.bytes, safety: .review, action: .removeContents(dir, permanent: true),
                    icon: .symbol("trash")))
            }
        } else {
            items.append(StorageItem(
                id: dir.path, title: "Trash", subtitle: "Clean Mac needs Full Disk Access to read the Trash",
                url: dir, bytes: -1, safety: .info, action: .none, icon: .symbol("trash")))
        }
        return StorageGroup(
            id: "hidden.trash", title: "Trash",
            note: "Files in the Trash still take up space until it's emptied. Emptying here deletes them for good.",
            symbol: "trash", items: items)
    }

    // MARK: Large files

    static func largeFiles() async -> StorageGroup {
        let items = await Task.detached(priority: .utility) { () -> [StorageItem] in
            let skipTop: Set<String> = ["Library", "Downloads"]
            var out: [StorageItem] = []
            for top in Paths.children(Paths.home) {
                let name = top.lastPathComponent
                guard !name.hasPrefix("."), !skipTop.contains(name), Paths.isDirectory(top) else { continue }
                for file in files(in: top, maxDepth: 12, minBytes: 1_000_000_000) {
                    out.append(StorageItem(
                        id: file.url.path, title: file.url.lastPathComponent,
                        subtitle: Paths.tilde(file.url.deletingLastPathComponent()),
                        url: file.url, bytes: file.bytes, safety: .personal, action: .remove([file.url]),
                        icon: .file(file.url), date: file.modified, dateLabel: "Modified"))
                }
            }
            for file in files(in: Paths.h("Downloads"), maxDepth: 6, minBytes: 1_000_000_000)
            where !installerExtensions.union(archiveExtensions).contains(file.url.pathExtension.lowercased()) {
                out.append(StorageItem(
                    id: file.url.path, title: file.url.lastPathComponent,
                    subtitle: Paths.tilde(file.url.deletingLastPathComponent()),
                    url: file.url, bytes: file.bytes, safety: .personal, action: .remove([file.url]),
                    icon: .file(file.url), date: file.modified, dateLabel: "Modified"))
            }
            return Array(out.sorted(by: ScanKit.bySize).prefix(40))
        }.value
        return StorageGroup(
            id: "hidden.large", title: "Files over 1 GB",
            note: "Single large files in your folders: videos, disk images, exports. App libraries like Photos aren't opened.",
            symbol: "doc", items: items)
    }

    struct FoundFile {
        let url: URL
        let bytes: Int64
        let modified: Date?
        let added: Date?
    }

    static func files(in root: URL, maxDepth: Int, minBytes: Int64) -> [FoundFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else { return [] }
        let skip: Set<String> = ["node_modules", ".git", "Pods", "DerivedData", ".build", "target", ".venv"]
        var out: [FoundFile] = []
        for case let url as URL in walker {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                if walker.level >= maxDepth || skip.contains(url.lastPathComponent) { walker.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true else { continue }
            if maxDepth == 0, walker.level > 1 { continue }
            let size = Int64(v.totalFileAllocatedSize ?? 0)
            if size >= minBytes {
                out.append(FoundFile(url: url, bytes: size, modified: v.contentModificationDate, added: v.addedToDirectoryDate))
            }
        }
        return out
    }

    // MARK: Cloud drives

    static func cloudDrives() async -> StorageGroup {
        var items: [StorageItem] = []
        let icloud = Paths.lib("Mobile Documents")
        if Paths.exists(icloud) {
            items.append(StorageItem(
                id: icloud.path, title: "iCloud Drive", subtitle: "Downloaded copies. Turn on Optimize Mac Storage in System Settings › iCloud › iCloud Drive",
                url: icloud, safety: .info, action: .none, icon: .symbol("icloud")))
        }
        for drive in Paths.subdirectories(Paths.lib("CloudStorage")) {
            let name = drive.lastPathComponent.split(separator: "-").first.map(String.init) ?? drive.lastPathComponent
            items.append(StorageItem(
                id: drive.path, title: name, subtitle: "Downloaded copies. In Finder, right-click a folder and choose Remove Download",
                url: drive, safety: .info, action: .none, icon: .symbol("externaldrive.badge.icloud")))
        }
        items = await ScanKit.fill(items).filter { $0.bytes > 10_000_000 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "hidden.cloud", title: "Cloud drives kept on this Mac",
            note: "Files synced from iCloud, Dropbox, Google Drive or OneDrive take local space while they're downloaded.",
            symbol: "icloud", items: items)
    }

    // MARK: Media

    static func mediaLibraries() async -> StorageGroup {
        var items: [StorageItem] = []
        for lib in Paths.children(Paths.h("Pictures")) where lib.pathExtension == "photoslibrary" {
            items.append(StorageItem(
                id: lib.path, title: lib.deletingPathExtension().lastPathComponent,
                subtitle: "Photos library. Photos › Settings › iCloud › Optimize Mac Storage keeps originals in iCloud",
                url: lib, safety: .info, action: .none, icon: .file(lib)))
        }
        let movies = Paths.h("Movies")
        for lib in Paths.children(movies) where ["fcpbundle", "imovielibrary"].contains(lib.pathExtension) {
            items.append(StorageItem(
                id: lib.path, title: lib.deletingPathExtension().lastPathComponent,
                subtitle: "Video library. Delete generated render files from inside the app",
                url: lib, safety: .info, action: .none, icon: .file(lib)))
        }
        let fixed: [(String, String, String, String)] = [
            ("Music/Music/Media.localized", "Music library", "Songs downloaded or imported into Music", "music.note"),
            ("Music/iTunes", "iTunes library", "Older iTunes media", "music.note"),
            ("Movies/TV/Media.localized", "TV app downloads", "Movies and shows downloaded in the TV app", "tv"),
            ("Music/Audio Music Apps", "GarageBand & Logic projects", "Projects and patches", "pianokeys"),
            ("/Library/Application Support/GarageBand", "GarageBand sound library", "Remove from GarageBand › Sound Library", "pianokeys"),
            ("/Library/Application Support/Logic", "Logic sound library", "Remove from Logic Pro › Sound Library", "pianokeys"),
            ("/Library/Audio/Apple Loops", "Apple Loops", "Loops for GarageBand and Logic", "waveform"),
            ("Library/Application Support/Steam/steamapps", "Steam games", "Uninstall games from Steam", "gamecontroller"),
        ]
        for (path, title, subtitle, symbol) in fixed {
            let url = ScanKit.resolve(path)
            guard Paths.exists(url) else { continue }
            items.append(StorageItem(id: url.path, title: title, subtitle: subtitle, url: url, safety: .info, action: .none, icon: .symbol(symbol)))
        }
        items = await ScanKit.fill(items).filter { $0.bytes > 50_000_000 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "hidden.media", title: "Media libraries",
            note: "Libraries are packages Finder shows as a single file. Manage them from their own app so nothing breaks.",
            symbol: "photo.on.rectangle", items: items)
    }

    // MARK: Mail & Messages

    static func mailAndMessages() async -> StorageGroup {
        var items: [StorageItem] = []
        let downloads = Paths.lib("Containers/com.apple.mail/Data/Library/Mail Downloads")
        if Paths.exists(downloads) {
            items.append(StorageItem(
                id: downloads.path, title: "Mail downloads",
                subtitle: "Attachments you opened from Mail. The originals stay in your mailbox, but edits to an opened attachment are saved only here",
                url: downloads, safety: .review, action: .removeContents(downloads, permanent: false),
                icon: .symbol("paperclip")))
        }
        let fixed: [(String, String, String, String)] = [
            ("Library/Mail", "Mail", "Your messages and attachments. Mail › Settings › Accounts can download fewer attachments", "envelope"),
            ("Library/Messages/Attachments", "Messages attachments", "Photos and files from conversations. Review them in System Settings › General › Storage › Messages", "message"),
        ]
        for (path, title, subtitle, symbol) in fixed {
            let url = ScanKit.resolve(path)
            guard Paths.exists(url) else { continue }
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            items.append(StorageItem(
                id: url.path, title: title,
                subtitle: readable ? subtitle : "Clean Mac needs Full Disk Access to measure this",
                url: url, bytes: readable ? 0 : -1, safety: .info, action: .none, icon: .symbol(readable ? symbol : "lock")))
        }
        items = await ScanKit.fill(items).filter { $0.bytes != 0 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "hidden.mail", title: "Mail & Messages",
            note: "Attachments pile up for years. Let the apps manage them so conversations stay intact.",
            symbol: "envelope", items: items)
    }

    // MARK: Virtual machines

    static func virtualMachines() async -> StorageGroup {
        let places: [(String, Set<String>, String)] = [
            ("Parallels", ["pvm"], "Parallels"),
            ("Library/Containers/com.utmapp.UTM/Data/Documents", ["utm"], "UTM"),
            ("Virtual Machines.localized", ["vmwarevm"], "VMware Fusion"),
            ("Documents/Virtual Machines.localized", ["vmwarevm"], "VMware Fusion"),
            ("VirtualBox VMs", [], "VirtualBox"),
        ]
        var items: [StorageItem] = []
        for (path, exts, app) in places {
            let dir = ScanKit.resolve(path)
            guard Paths.exists(dir) else { continue }
            for vm in Paths.children(dir) where exts.isEmpty ? Paths.isDirectory(vm) : exts.contains(vm.pathExtension) {
                items.append(StorageItem(
                    id: vm.path, title: vm.deletingPathExtension().lastPathComponent, subtitle: "\(app) virtual machine",
                    url: vm, safety: .personal, action: .remove([vm]), icon: .symbol("desktopcomputer"),
                    date: Paths.modified(vm), dateLabel: "Used"))
            }
        }
        items = await ScanKit.fill(items).filter { $0.bytes > 10_000_000 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "hidden.vms", title: "Virtual machines",
            note: "Each VM is a whole computer's disk. Old test machines are easy to forget.",
            symbol: "desktopcomputer", items: items)
    }

    // MARK: Logs

    static func logs() async -> StorageGroup {
        var items: [StorageItem] = []
        let mine = Paths.lib("Logs")
        if Paths.exists(mine) {
            items.append(StorageItem(
                id: mine.path, title: "Your logs & crash reports", subtitle: "~/Library/Logs",
                url: mine, safety: .safe, action: .removeContents(mine, permanent: false),
                icon: .symbol("doc.text"), recommended: true))
        }
        let system = URL(fileURLWithPath: "/Library/Logs")
        if Paths.exists(system) {
            items.append(StorageItem(
                id: system.path, title: "System logs", subtitle: "/Library/Logs. macOS rotates these on its own",
                url: system, safety: .info, action: .none, icon: .symbol("doc.text")))
        }
        items = await ScanKit.fill(items).map { item in
            var item = item
            if item.bytes < 100_000_000 { item.recommended = false }
            return item
        }.filter { $0.bytes > 5_000_000 }
        return StorageGroup(
            id: "hidden.logs", title: "Logs",
            note: "Diagnostic text apps write as they run. Nothing depends on old logs.",
            symbol: "doc.text", items: items)
    }

    // MARK: Snapshots

    static func snapshots() async -> StorageGroup {
        let volume = VolumeInfo.current()
        var items: [StorageItem] = []
        if volume.purgeable > 0 {
            items.append(StorageItem(
                id: "purgeable", title: "Purgeable space",
                subtitle: "Caches and snapshots macOS frees by itself when an app needs room",
                bytes: volume.purgeable, safety: .info, action: .none, icon: .symbol("wind")))
        }
        let result = await Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        for line in result.text.split(separator: "\n").map(String.init) where line.hasPrefix("com.apple.") {
            if line.hasPrefix("com.apple.TimeMachine.") {
                let stamp = line.replacingOccurrences(of: "com.apple.TimeMachine.", with: "").replacingOccurrences(of: ".local", with: "")
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd-HHmmss"
                items.append(StorageItem(
                    id: "snapshot:\(line)", title: "Time Machine snapshot",
                    subtitle: "Size isn't reported by macOS; it's part of purgeable space",
                    bytes: -1, safety: .review,
                    action: .command(tool: "/usr/bin/tmutil", args: ["deletelocalsnapshots", stamp], fallback: nil),
                    icon: .symbol("clock.arrow.circlepath"), date: f.date(from: stamp), dateLabel: "Taken"))
            } else {
                items.append(StorageItem(
                    id: "snapshot:\(line)", title: "macOS update snapshot",
                    subtitle: "Kept while an update is prepared or rolled back; macOS removes it",
                    bytes: -1, safety: .info, action: .none, icon: .symbol("arrow.triangle.2.circlepath")))
            }
        }
        return StorageGroup(
            id: "hidden.snapshots", title: "Snapshots & purgeable space",
            note: "APFS snapshots freeze old copies of files, so deleting a file doesn't free its space until the snapshot goes.",
            symbol: "clock.arrow.circlepath", items: items)
    }

    // MARK: System

    static func systemFiles() async -> StorageGroup {
        let fixed: [(String, String, String, String)] = [
            ("/private/var/vm", "Swap & sleep image", "Virtual memory. Restarting your Mac shrinks it", "memorychip"),
            ("/Library/Caches", "System caches", "Shared caches macOS manages", "gearshape"),
            ("/Library/Updates", "Downloaded macOS updates", "Installed or waiting to install", "arrow.down.circle"),
            ("/Library/Application Support", "Shared app support", "Data apps install for every user, such as plug-ins and sound libraries", "square.grid.2x2"),
            ("/Users/Shared", "Shared folder", "Files available to every user on this Mac", "person.2"),
        ]
        var items: [StorageItem] = []
        for (path, title, subtitle, symbol) in fixed {
            let url = URL(fileURLWithPath: path)
            guard Paths.exists(url) else { continue }
            items.append(StorageItem(id: url.path, title: title, subtitle: subtitle, url: url, safety: .info, action: .none, icon: .symbol(symbol)))
        }
        items = await ScanKit.fill(items).filter { $0.bytes > 50_000_000 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "hidden.system", title: "System",
            note: "Space macOS manages for you. Shown so you know what part of \"System Data\" is.",
            symbol: "gearshape", items: items)
    }

    // MARK: Dot folders

    static let dotNotes: [String: String] = [
        ".npm": "npm cache and logs", ".cache": "Caches from command-line tools", ".docker": "Docker CLI settings",
        ".ollama": "Ollama models", ".vscode": "VS Code extensions", ".cursor": "Cursor extensions",
        ".rustup": "Rust toolchains", ".cargo": "Rust crates and tools", ".gradle": "Gradle caches",
        ".m2": "Maven repository", ".nvm": "Node versions", ".pyenv": "Python versions", ".conda": "Conda",
        ".android": "Android emulators and settings", ".expo": "Expo CLI state", ".bun": "Bun runtime and cache",
        ".claude": "Claude Code settings and history", ".codex": "Codex CLI settings and history",
        ".local": "Tools installed per user", ".config": "App and tool settings", ".orbstack": "OrbStack",
        ".swiftpm": "Swift Package Manager settings", ".lmstudio": "LM Studio models", ".keras": "Keras datasets",
        ".pub-cache": "Dart packages", ".gem": "Ruby gems", ".rbenv": "Ruby versions", ".volta": "Volta tools",
    ]

    static func dotFolders() async -> StorageGroup {
        var items: [StorageItem] = []
        for url in Paths.children(Paths.home) {
            let name = url.lastPathComponent
            guard name.hasPrefix("."), name != ".Trash", name != ".DS_Store" else { continue }
            items.append(StorageItem(
                id: "dot:\(url.path)", title: name, subtitle: dotNotes[name] ?? Paths.tilde(url),
                url: url, safety: .personal, action: .remove([url]), icon: .symbol("eye.slash"),
                date: Paths.modified(url), dateLabel: "Updated"))
        }
        items = await ScanKit.fill(items).filter { $0.bytes > 10_000_000 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "hidden.dot", title: "Hidden folders in your home",
            note: "Finder hides anything starting with a dot. Tools keep settings, caches and downloads here; parts of these are also listed under Developer tools.",
            symbol: "eye.slash", items: items, overlapsOthers: true)
    }
}
