import Foundation

enum CleanMode: String {
    case trash, delete
}

enum CleanError: LocalizedError {
    case protected(String)
    case outside(String)
    case command(String)
    case partial(failed: Int, total: Int, reason: String)
    case notCleanable

    var errorDescription: String? {
        switch self {
        case .protected(let p): "\(Paths.tilde(URL(fileURLWithPath: p))) is a system or personal folder Clean Mac never removes."
        case .outside(let p): "\(p) is outside the folders Clean Mac is allowed to clean."
        case .command(let msg): msg.isEmpty ? "The command failed." : msg
        case .partial(let failed, let total, let reason): "\(failed) of \(total) items couldn't be removed. \(reason)"
        case .notCleanable: "This item can't be removed from Clean Mac."
        }
    }
}

/// Last line of defense: refuses to touch folders that hold the system or a person's life.
enum PathGuard {
    private static let home = Paths.home.path

    /// Lowercased, because APFS is case-insensitive by default: "~/documents" is "~/Documents".
    private static let protectedPaths: Set<String> = {
        var set: Set<String> = [
            "/", "/Applications", "/Applications/Utilities", "/Library", "/System", "/Users",
            "/Users/Shared", "/private", "/usr", "/bin", "/sbin", "/opt", "/Volumes", home,
        ]
        let rel = [
            "Library", "Library/Application Support", "Library/Caches", "Library/Containers",
            "Library/Group Containers", "Library/Preferences", "Library/Keychains", "Library/Developer",
            "Library/Developer/Xcode", "Library/Developer/CoreSimulator", "Library/Mobile Documents",
            "Library/CloudStorage", "Library/Mail", "Library/Messages", "Library/Logs",
            "Library/Application Support/MobileSync", "Library/Application Support/MobileSync/Backup",
            "Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications",
            ".Trash", ".ssh", ".gnupg", ".config", ".local", "Code", "Developer", "Projects",
            "Library/Mobile Documents/com~apple~CloudDocs",
        ]
        for r in rel { set.insert(home + "/" + r) }
        return Set(set.map { $0.lowercased() })
    }()
    private static let cloudStorage = (home + "/Library/CloudStorage").lowercased()
    /// Folders Clean Mac empties on purpose, though it never removes them.
    private static let emptiable = Set([home + "/.Trash", home + "/Library/Logs"].map { $0.lowercased() })

    static func check(_ url: URL) throws {
        // Judge where the item really is: resolve symlinked parents, but not the item, since removing a link removes the link.
        let given = url.standardizedFileURL
        let real = given.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(given.lastPathComponent)
        for p in [given.path, real.path] {
            let lower = p.lowercased()
            if protectedPaths.contains(lower) || lower.contains("/library/keychains") || lower.hasSuffix("/.git")
                || lower.hasSuffix("/.ssh") || lower.hasSuffix(".photoslibrary")
                || (lower as NSString).deletingLastPathComponent == cloudStorage {
                throw CleanError.protected(p)
            }
            let allowedRoots = [home + "/", "/Applications/"].map { $0.lowercased() }
            guard allowedRoots.contains(where: { lower.hasPrefix($0) }) else { throw CleanError.outside(p) }
        }
    }

    /// Emptying keeps the folder, but the folder itself must still be one Clean Mac may clean.
    static func checkEmptying(_ dir: URL) throws {
        if emptiable.contains(dir.standardizedFileURL.path.lowercased()) { return }
        try check(dir)
    }
}

struct CleanFailure: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let reason: String
}

struct CleanOutcome {
    var freed: Int64 = 0
    var cleaned = 0
    var failures: [CleanFailure] = []
    var usedTrash = false
}

enum Cleaner {
    static func perform(
        _ items: [StorageItem],
        mode: CleanMode,
        progress: @escaping @Sendable (Int, Int, String) async -> Void
    ) async -> CleanOutcome {
        var outcome = CleanOutcome(usedTrash: mode == .trash && items.contains { $0.action.touchesFiles })
        // Empty the Trash before moving anything into it, so files trashed by this clean can still be put back.
        let ordered = items.filter { !$0.action.touchesFiles } + items.filter(\.action.touchesFiles)
        for (i, item) in ordered.enumerated() {
            await progress(i, items.count, item.title)
            do {
                try await run(item.action, mode: mode)
                outcome.freed += item.bytes
                outcome.cleaned += 1
            } catch {
                outcome.failures.append(CleanFailure(title: item.title, reason: error.localizedDescription))
            }
        }
        await progress(items.count, items.count, "")
        return outcome
    }

    static func run(_ action: CleanAction, mode: CleanMode) async throws {
        switch action {
        case .remove(let urls):
            for url in urls { try await remove(url, mode: mode) }

        case .removeContents(let dir, let permanent):
            try PathGuard.checkEmptying(dir)
            let kids = Paths.children(dir)
            var failed = 0
            var reason = ""
            for kid in kids {
                do { try await remove(kid, mode: permanent ? .delete : mode) } catch {
                    failed += 1
                    if reason.isEmpty { reason = error.localizedDescription }
                }
            }
            if failed > 0 { throw CleanError.partial(failed: failed, total: kids.count, reason: reason) }

        case .command(let tool, let args, let fallback):
            let result = await Shell.run(tool, args)
            if !result.ok {
                if let fallback {
                    try await run(.removeContents(fallback, permanent: false), mode: mode)
                } else {
                    throw CleanError.command(result.error)
                }
            }

        case .none:
            throw CleanError.notCleanable
        }
    }

    static func remove(_ url: URL, mode: CleanMode) async throws {
        let fm = FileManager.default
        let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        guard fm.fileExists(atPath: url.path) || isLink else { return }   // already gone
        try PathGuard.check(url)

        switch mode {
        case .trash:
            try fm.trashItem(at: url, resultingItemURL: nil)
        case .delete:
            do {
                try fm.removeItem(at: url)
            } catch {
                // Some tools (Go, Nix) write read-only trees. Make them writable and retry once.
                _ = await Shell.run("/bin/chmod", ["-R", "u+w", url.path])
                try fm.removeItem(at: url)
            }
        }
    }
}
