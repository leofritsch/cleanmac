import AppKit
import SwiftUI

/// Captures happen while another app is frontmost; draw controls as if the window were active.
struct CaptureAppearsActive: ViewModifier {
    func body(content: Content) -> some View {
        if Capture.isActive {
            content.environment(\.appearsActive, true)
        } else {
            content
        }
    }
}

/// Development aid: with CLEANMAC_CAPTURE=<folder>, waits for the scan, saves a PNG of every
/// section, opens the clean sheet (without cleaning) and quits.
@MainActor
enum Capture {
    nonisolated static var isActive: Bool { ProcessInfo.processInfo.environment["CLEANMAC_CAPTURE"] != nil }

    static func runIfRequested(_ model: AppModel) async {
        guard let path = ProcessInfo.processInfo.environment["CLEANMAC_CAPTURE"] else { return }
        let dir = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let started = Date()
        log(dir, "cleanMode at launch: \(model.cleanMode.rawValue), stored: \(UserDefaults.standard.string(forKey: "cleanMode") ?? "nil")")

        try? await Task.sleep(for: .seconds(1.5))
        snap(model, dir, "00-scanning")
        while model.isBusy, Date().timeIntervalSince(started) < 600 {
            try? await Task.sleep(for: .milliseconds(500))
        }
        log(dir, "scan finished in \(Int(Date().timeIntervalSince(started)))s")
        for s in SectionID.scannable {
            let r = model.reports[s]
            log(dir, "\(s.rawValue): \(Fmt.bytes(r?.total ?? 0)) found, \(Fmt.bytes(r?.recommendedBytes ?? 0)) recommended, \(r?.groups.count ?? 0) groups")
            for g in r?.groups ?? [] {
                log(dir, "  \(g.title): \(Fmt.bytes(g.total)) (\(g.items.count) items)")
            }
        }
        if let o = model.overview {
            for l in o.layers { log(dir, "layer \(l.kind.rawValue): \(Fmt.bytes(l.bytes))") }
            log(dir, "denied entries: \(o.denied)")
        }

        let window = NSApp.windows.first { $0.isVisible && !$0.isSheet }
        let normal = window?.frame ?? .zero
        for (i, s) in SectionID.allCases.enumerated() {
            if s == .explore { model.go(.folder(Paths.library)) } else { model.section = s }
            // The overview is long; grow the window so one image shows all of it.
            if s == .overview { window?.setFrame(NSRect(x: normal.minX, y: 0, width: normal.width, height: 2300), display: true) }
            try? await Task.sleep(for: .seconds(s == .explore ? 8 : 1.5))
            snap(model, dir, String(format: "%02d-%@", i + 1, s.rawValue))
            if s == .overview { window?.setFrame(normal, display: true) }
        }

        let target = SectionID.scannable.first { (model.reports[$0]?.recommendedBytes ?? 0) > 0 } ?? .xcode
        model.section = target
        model.selectRecommended(in: target)
        try? await Task.sleep(for: .seconds(1.2))
        snap(model, dir, "10-\(target.rawValue)-selected")
        model.reviewClean(in: target)
        try? await Task.sleep(for: .seconds(1.2))
        log(dir, "cleanMode with sheet open: \(model.cleanMode.rawValue)")
        if let sheet = NSApp.windows.first(where: { $0.isSheet && $0.isVisible }) {
            write(sheet, to: dir.appendingPathComponent("11-clean-sheet.png"))
        }
        model.cleanSession = nil
        try? await Task.sleep(for: .seconds(0.5))
        NSApp.terminate(nil)
    }

    private static func snap(_ model: AppModel, _ dir: URL, _ name: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet && $0.contentView != nil }) else { return }
        write(window, to: dir.appendingPathComponent("\(name).png"))
    }

    private typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// An app may image its own windows without Screen Recording permission. The CoreGraphics
    /// call is hidden from the current SDK, so it's looked up at runtime.
    private static func write(_ window: NSWindow, to url: URL) {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(symbol, to: WindowImageFn.self)
        // optionIncludingWindow, boundsIgnoreFraming | bestResolution
        guard let image = create(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func log(_ dir: URL, _ line: String) {
        let url = dir.appendingPathComponent("report.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
