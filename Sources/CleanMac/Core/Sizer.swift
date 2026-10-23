import Foundation
import Darwin

struct SizeResult: Sendable, Hashable {
    var bytes: Int64 = 0
    var files: Int = 0
    var newest: Date? = nil
    /// Folders or files we weren't allowed to read (usually needs Full Disk Access).
    var denied: Int = 0
}

/// Walks a tree with fts(3) and adds up allocated blocks, like `du`.
enum Sizer {
    static func measureSync(_ path: String, shouldCancel: () -> Bool = { false }) -> SizeResult {
        var result = SizeResult()
        var newest: Int = 0
        var seenLinks = Set<UInt64>()

        guard let cpath = strdup(path) else { return result }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return result }
        defer { fts_close(fts) }

        var visited = 0
        while let entry = fts_read(fts) {
            visited += 1
            if visited & 0x7FF == 0, shouldCancel() { break }

            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_D:
                if let st = entry.pointee.fts_statp {
                    result.bytes += Int64(st.pointee.st_blocks) * 512
                }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let st = entry.pointee.fts_statp?.pointee else { continue }
                if st.st_nlink > 1, (st.st_mode & S_IFMT) == S_IFREG {
                    if !seenLinks.insert(UInt64(st.st_ino)).inserted { continue }
                }
                result.bytes += Int64(st.st_blocks) * 512
                result.files += 1
                if st.st_mtimespec.tv_sec > newest { newest = st.st_mtimespec.tv_sec }
            case FTS_DNR, FTS_ERR, FTS_NS:
                result.denied += 1
            default:
                break
            }
        }
        if newest > 0 { result.newest = Date(timeIntervalSince1970: TimeInterval(newest)) }
        return result
    }

    private static let queue = DispatchQueue(label: "cleanmac.sizer", qos: .userInitiated, attributes: .concurrent)

    static func measure(_ path: String, cancel: CancelFlag? = nil) async -> SizeResult {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: measureSync(path, shouldCancel: { cancel?.isSet ?? false }))
            }
        }
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Caps how many tree walks run at once so the disk isn't thrashed.
actor Gate {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ slots: Int) { available = slots }

    func acquire() async {
        if available > 0 { available -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { available += 1 } else { waiters.removeFirst().resume() }
    }
}

/// Shared, de-duplicated sizes so the overview and sections never walk the same folder twice.
actor SizeCache {
    static let shared = SizeCache()

    private var finished: [String: SizeResult] = [:]
    private var inFlight: [String: Task<SizeResult, Never>] = [:]
    private var generation = 0
    private let gate = Gate(8)
    private let interactiveGate = Gate(6)

    func size(_ url: URL) async -> SizeResult {
        let key = url.standardizedFileURL.path
        if let r = finished[key] { return r }
        if let t = inFlight[key] { return await t.value }

        let gate = self.gate
        let task = Task.detached(priority: .userInitiated) { () -> SizeResult in
            await gate.acquire()
            let r = await Sizer.measure(key)
            await gate.release()
            return r
        }
        inFlight[key] = task
        let gen = generation
        let result = await task.value
        if gen == generation {
            finished[key] = result
            inFlight[key] = nil
        }
        return result
    }

    /// For Explore: cancellable, uses its own slots so browsing stays responsive during scans.
    func interactiveSize(_ url: URL, cancel: CancelFlag) async -> SizeResult? {
        let key = url.standardizedFileURL.path
        if let r = finished[key] { return r }
        await interactiveGate.acquire()
        if cancel.isSet { await interactiveGate.release(); return nil }
        let gen = generation
        let r = await Sizer.measure(key, cancel: cancel)
        await interactiveGate.release()
        if cancel.isSet { return nil }
        if gen == generation { finished[key] = r }
        return r
    }

    func cached(_ url: URL) -> SizeResult? { finished[url.standardizedFileURL.path] }

    func reset() {
        generation += 1
        finished = [:]
        inFlight = [:]
    }
}
