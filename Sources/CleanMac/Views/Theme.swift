import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}

extension Color {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

enum Theme {
    /// Azurite: actions and selection.
    static let accent = Color.adaptive(light: 0x4C68D8, dark: 0x8399F4)
    static let safe = Color.adaptive(light: 0x4E9A63, dark: 0x7CC490)
    static let review = Color.adaptive(light: 0xB98128, dark: 0xE4B663)
    static let personal = Color.adaptive(light: 0xBF5F4D, dark: 0xE88E7C)
    static let canvas = Color.adaptive(light: 0xFBFBFC, dark: 0x1C1D21)
    static let hairline = Color.primary.opacity(0.08)

    static func color(_ safety: Safety) -> Color {
        switch safety {
        case .safe: safe
        case .review: review
        case .personal: personal
        case .info: Color.secondary.opacity(0.6)
        }
    }

    /// Mineral tones, one per stratum.
    static func layer(_ id: LayerID) -> Color {
        switch id {
        case .system: .adaptive(light: 0x5D6372, dark: 0x515767)
        case .sharedLibrary: .adaptive(light: 0x9097A4, dark: 0x737A88)
        case .apps: .adaptive(light: 0x7C8DB5, dark: 0x8698C4)
        case .xcode: .adaptive(light: 0x5B7BE0, dark: 0x7892F2)
        case .devtools: .adaptive(light: 0x8B7FD4, dark: 0xA096E6)
        case .projects: .adaptive(light: 0x98B064, dark: 0xA9C27A)
        case .appdata: .adaptive(light: 0xCF8B73, dark: 0xDD9A82)
        case .caches: .adaptive(light: 0xD9A94E, dark: 0xE6BD6B)
        case .mail: .adaptive(light: 0xD39AB2, dark: 0xE2AAC1)
        case .icloud: .adaptive(light: 0x7FB9CD, dark: 0x8FCADC)
        case .documents: .adaptive(light: 0xD8BB92, dark: 0xD9BF99)
        case .downloads: .adaptive(light: 0xC2845A, dark: 0xD29569)
        case .media: .adaptive(light: 0x72A584, dark: 0x83B694)
        case .otherLibrary: .adaptive(light: 0xA7ADB9, dark: 0x8B919E)
        case .otherHome: .adaptive(light: 0xC6BEB0, dark: 0xADA699)
        case .hidden: .adaptive(light: 0x726A8C, dark: 0x8A82A6)
        }
    }
}

// MARK: - Small components

struct SafetyDot: View {
    let safety: Safety
    var body: some View {
        Circle()
            .fill(Theme.color(safety))
            .frame(width: 6, height: 6)
            .help(safety.label)
            .accessibilityLabel(safety.label)
    }
}

struct BadgeView: View {
    let badge: Badge
    var body: some View {
        Text(badge.text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    private var tint: Color {
        switch badge.tone {
        case .neutral: .secondary
        case .good: Theme.safe
        case .warn: Theme.review
        case .alert: Theme.personal
        }
    }
}

struct CheckCircle: View {
    let on: Bool
    var mixed = false
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(on || mixed ? Color.clear : Color.secondary.opacity(0.45), lineWidth: 1.2)
                .background(Circle().fill(on || mixed ? Theme.accent : Color.clear))
            if on || mixed {
                Image(systemName: mixed && !on ? "minus" : "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 16, height: 16)
        .animation(.snappy(duration: 0.18), value: on)
    }
}

/// App and file icons are cached; NSWorkspace lookups are slow enough to stutter a list.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let hit = cache[url.path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = image
        return image
    }
}

struct ItemIconView: View {
    let icon: ItemIcon
    var size: CGFloat = 22

    var body: some View {
        switch icon {
        case .file(let url):
            Image(nsImage: IconCache.icon(for: url))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.58, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

struct RevealButton: View {
    let url: URL?
    var body: some View {
        Button {
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } label: {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
        .disabled(url == nil)
    }
}

struct AccessBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.open")
                .font(.system(size: 15))
                .foregroundStyle(Theme.review)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Some folders are closed to Clean Mac")
                    .font(.system(size: 13, weight: .semibold))
                Text("Mail, Messages, Safari, device backups, the Trash and other apps' containers need Full Disk Access. Without it, their space shows up as system data.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open Privacy Settings") { Permissions.openFullDiskAccessSettings() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(16)
        .glassEffect(.regular.tint(Theme.review.opacity(0.12)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SafetyLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach([Safety.safe, .review, .personal], id: \.self) { s in
                HStack(spacing: 6) {
                    SafetyDot(safety: s)
                    Text(s.label)
                }
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
    }
}
