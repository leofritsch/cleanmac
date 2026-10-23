import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        // `CleanMac --measure <path>…` prints sizes, for checking the sizer against du.
        if let i = args.firstIndex(of: "--measure") {
            for path in args.dropFirst(i + 1) {
                let r = Sizer.measureSync(path)
                print("\(r.bytes / 1024)\t\(r.files) files\t\(r.denied) denied\t\(path)")
            }
            exit(0)
        }
        CleanMacApp.main()
    }
}

struct CleanMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Clean Mac", id: "main") {
            RootView()
                .environment(model)
                .modifier(CaptureAppearsActive())
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    model.start()
                    await Capture.runIfRequested(model)
                }
        }
        .defaultSize(width: 1200, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Rescan") { model.scanAll() }
                    .keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appearance = ProcessInfo.processInfo.environment["CLEANMAC_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
