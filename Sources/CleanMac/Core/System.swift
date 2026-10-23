import AppKit
import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    static let library = home.appendingPathComponent("Library")

    static func h(_ relative: String) -> URL { home.appendingPathComponent(relative) }
    static func lib(_ relative: String) -> URL { library.appendingPathComponent(relative) }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    static func children(_ url: URL, keys: [URLResourceKey] = []) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])) ?? []
    }

    static func subdirectories(_ url: URL) -> [URL] {
        children(url, keys: [.isDirectoryKey, .isSymbolicLinkKey]).filter {
            let v = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return v?.isDirectory == true && v?.isSymbolicLink != true
        }
    }

    static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func plist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// "~/Library/Caches" instead of "/Users/me/Library/Caches".
    static func tilde(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        return p.hasPrefix(home.path) ? "~" + p.dropFirst(home.path.count) : p
    }
}

struct ShellResult {
    let status: Int32
    let output: Data
    let error: String
    var ok: Bool { status == 0 }
    var text: String { String(decoding: output, as: UTF8.self) }
}

enum Shell {
    static func run(_ tool: String, _ args: [String]) async -> ShellResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = args
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    cont.resume(returning: ShellResult(status: -1, output: Data(), error: error.localizedDescription))
                    return
                }
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                cont.resume(returning: ShellResult(
                    status: process.terminationStatus,
                    output: outData,
                    error: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
    }
}

struct VolumeInfo: Hashable {
    var total: Int64 = 0
    var available: Int64 = 0
    var important: Int64 = 0

    /// What Finder and System Settings call "used".
    var used: Int64 { max(0, total - important) }
    /// Space macOS can reclaim on its own when it needs it.
    var purgeable: Int64 { max(0, important - available) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> VolumeInfo {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return VolumeInfo() }
        let available = Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeInfo(
            total: Int64(v.volumeTotalCapacity ?? 0),
            available: available,
            important: max(available, v.volumeAvailableCapacityForImportantUsage ?? 0)
        )
    }
}

enum Permissions {
    /// Full Disk Access can't be queried directly; probe files only it unlocks.
    static func hasFullDiskAccess() -> Bool {
        let probes = [
            "Library/Application Support/com.apple.TCC/TCC.db",
            "Library/Safari/Bookmarks.plist",
            "Library/Mail",
        ]
        for rel in probes {
            let fd = open(Paths.h(rel).path, O_RDONLY)
            if fd >= 0 { close(fd); return true }
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum Fmt {
    /// Decimal units like Finder, with fewer digits as numbers grow: 8.35 GB, 45.7 GB, 840.8 GB.
    static func bytes(_ b: Int64) -> String {
        if b <= 0 { return "0 KB" }
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        let value = Double(b)
        for (size, unit) in units where value >= size {
            let n = value / size
            let digits = unit == "KB" || (unit == "MB" && n >= 10) ? 0 : (n < 10 ? 2 : 1)
            return n.formatted(.number.precision(.fractionLength(digits))) + " " + unit
        }
        return "\(b) bytes"
    }

    static func signedBytes(_ b: Int64) -> String {
        (b >= 0 ? "+" : "−") + bytes(abs(b))
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func ago(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return "just now" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func days(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) / 86_400)
    }
}

extension Date {
    static func iso(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string)
    }
}
