import AppKit
import Foundation

struct InstalledApp: Hashable {
    let name: String
    let bundleID: String?
    let url: URL
}

/// Who a folder in ~/Library belongs to.
struct Owner: Hashable {
    let name: String
    let app: InstalledApp?
    /// Folder is named like a bundle identifier (com.vendor.app).
    let isBundleStyle: Bool
    let isApple: Bool

    /// Confident the app that wrote this folder is gone.
    var isLeftover: Bool { isBundleStyle && app == nil && !isApple }
}

/// Index of installed apps used to put names and icons on ~/Library folders.
final class AppIndex: @unchecked Sendable {
    static let shared = AppIndex()

    private let lock = NSLock()
    private var built = false
    private var byID: [String: InstalledApp] = [:]
    private var byName: [String: InstalledApp] = [:]
    private var lsCache: [String: InstalledApp?] = [:]

    private func buildIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !built else { return }
        built = true
        let roots = [
            "/Applications", "/Applications/Utilities", "/System/Applications",
            "/System/Applications/Utilities", "/System/Library/CoreServices",
            Paths.h("Applications").path, "/Applications/Setapp",
        ]
        for root in roots {
            for url in Paths.children(URL(fileURLWithPath: root)) where url.pathExtension == "app" {
                index(url)
            }
        }
    }

    private func index(_ url: URL) {
        let info = Paths.plist(url.appendingPathComponent("Contents/Info.plist")) ?? [:]
        let id = info["CFBundleIdentifier"] as? String
        let display = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let app = InstalledApp(name: display, bundleID: id, url: url)
        if let id { byID[id.lowercased()] = app }
        for key in [display, info["CFBundleName"] as? String].compactMap({ $0 }) {
            let n = Self.normalize(key)
            if !n.isEmpty, byName[n] == nil { byName[n] = app }
        }
    }

    func app(bundleID: String) -> InstalledApp? {
        buildIfNeeded()
        let key = bundleID.lowercased()
        lock.lock()
        if let a = byID[key] { lock.unlock(); return a }
        if let cached = lsCache[key] { lock.unlock(); return cached }
        lock.unlock()

        var found: InstalledApp?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           !url.path.contains("/.Trash/") {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            found = InstalledApp(name: name, bundleID: bundleID, url: url)
        }
        lock.withLock { lsCache[key] = found }
        return found
    }

    /// An installed app whose bundle ID starts with the same two parts (com.vendor).
    func app(vendorOf id: String) -> InstalledApp? {
        buildIfNeeded()
        let parts = id.lowercased().split(separator: ".").prefix(2)
        guard parts.count == 2 else { return nil }
        let vendor = parts.joined(separator: ".") + "."
        return lock.withLock { byID.first { $0.key.hasPrefix(vendor) }?.value }
    }

    func app(named name: String) -> InstalledApp? {
        buildIfNeeded()
        return lock.withLock { byName[Self.normalize(name)] }
    }

    func owner(ofFolderNamed raw: String) -> Owner {
        let id = Self.stripContainerPrefix(raw)
        let bundleStyle = Self.looksLikeBundleID(id)
        let lower = id.lowercased()
        // Shortcuts and the Developer app keep group containers outside com.apple
        let apple = ["com.apple.", "apple", "is.workflow.", "developer.apple."].contains { lower.hasPrefix($0) }

        if bundleStyle {
            var parts = id.split(separator: ".").map(String.init)
            while parts.count >= 2 {
                if let app = app(bundleID: parts.joined(separator: ".")) {
                    return Owner(name: app.name, app: app, isBundleStyle: true, isApple: apple)
                }
                parts.removeLast()
                if parts.count < 3 { break }
            }
            // Apps share folders under IDs that don't match their own (com.microsoft.teams vs com.microsoft.teams2,
            // group.com.2stable.shared vs com.2stable.2fa), so any installed app from the same vendor keeps it
            return Owner(name: Self.prettyName(fromBundleID: id), app: app(vendorOf: id), isBundleStyle: true, isApple: apple)
        }
        if let app = app(named: raw) {
            return Owner(name: app.name, app: app, isBundleStyle: false, isApple: apple)
        }
        return Owner(name: raw, app: nil, isBundleStyle: false, isApple: apple)
    }

    // MARK: helpers

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count >= 3, !s.contains(" ") else { return false }
        return parts.allSatisfy { !$0.isEmpty }
    }

    /// Group containers look like "UBF8T346G9.com.microsoft.teams" or "group.com.vendor.app".
    static func stripContainerPrefix(_ s: String) -> String {
        if s.hasPrefix("group.") { return String(s.dropFirst(6)) }
        let parts = s.split(separator: ".", maxSplits: 1)
        if parts.count == 2, parts[0].count == 10,
           parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            let rest = String(parts[1])
            return rest.hasPrefix("group.") ? String(rest.dropFirst(6)) : rest
        }
        return s
    }

    static func prettyName(fromBundleID id: String) -> String {
        let generic: Set<String> = ["mac", "macos", "osx", "app", "desktop", "helper", "agent", "client"]
        let parts = id.split(separator: ".").map(String.init)
        let meaningful = parts.dropFirst(min(2, parts.count - 1)).filter { !generic.contains($0.lowercased()) }
        let base = meaningful.first ?? parts.last ?? id
        return base.prefix(1).uppercased() + base.dropFirst()
    }
}
