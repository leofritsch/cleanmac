import Foundation

typealias Progress = @Sendable (String) -> Void

enum ScanKit {
    static func sizes(_ urls: [URL]) async -> [String: SizeResult] {
        await withTaskGroup(of: (String, SizeResult).self) { group in
            for url in Set(urls) {
                group.addTask { (url.standardizedFileURL.path, await SizeCache.shared.size(url)) }
            }
            var out: [String: SizeResult] = [:]
            for await (path, result) in group { out[path] = result }
            return out
        }
    }

    /// Measures every item whose size isn't known yet, based on what its action would remove.
    static func fill(_ items: [StorageItem]) async -> [StorageItem] {
        func targets(_ item: StorageItem) -> [URL] {
            switch item.action {
            case .remove(let urls): return urls
            case .removeContents(let dir, _): return [dir]
            case .command(_, _, let fallback): return [fallback ?? item.url].compactMap { $0 }
            case .none: return [item.url].compactMap { $0 }
            }
        }
        let pending = items.filter { $0.bytes == 0 }
        let measured = await sizes(pending.flatMap(targets))
        return items.map { item in
            guard item.bytes == 0 else { return item }
            var copy = item
            copy.bytes = targets(item).reduce(0) { $0 + (measured[$1.standardizedFileURL.path]?.bytes ?? 0) }
            return copy
        }
    }

    static func bySize(_ a: StorageItem, _ b: StorageItem) -> Bool { a.bytes > b.bytes }

    static func existing(_ relativePaths: [String]) -> [URL] {
        relativePaths.map(resolve).filter(Paths.exists)
    }

    /// Absolute paths stay as they are; everything else is relative to home.
    static func resolve(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : Paths.h(path)
    }

    static func versionLess(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}
