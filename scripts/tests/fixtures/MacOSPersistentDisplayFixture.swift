import AppKit
import WebKit
import Foundation
import CoreGraphics

// A real, nonactivating AppKit/WebKit receiver. Input is supplied only through
// the installed OCU/Agent Desktop tools; this fixture does not synthesize input.
@MainActor
final class DisplayProbe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var editor: NSTextField!
    var web: WKWebView?
    var commits = 0
    let webMode = CommandLine.arguments.contains("--web")
    let stateFile = URL(fileURLWithPath: CommandLine.arguments.last!)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = webMode ? NSSize(width: 800, height: 600) : NSSize(width: 1100, height: 800)
        let screen = NSScreen.screens.first!
        window = NSWindow(contentRect: NSRect(x: screen.frame.minX + 50, y: screen.frame.maxY - size.height - 80,
                                              width: size.width, height: size.height),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = webMode ? "OCU Persistent Web Probe" : "OCU Persistent Native Probe"
        let content = window.contentView!
        editor = NSTextField(string: "ready")
        editor.frame = NSRect(x: 20, y: 20, width: 480, height: 28)
        editor.setAccessibilityIdentifier("persistent-marker")
        editor.setAccessibilityLabel("Probe marker")
        content.addSubview(editor)
        let button = NSButton(title: "Commit marker", target: self, action: #selector(commit))
        button.frame = NSRect(x: 520, y: 20, width: 180, height: 28)
        content.addSubview(button)
        if webMode {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let web = WKWebView(frame: NSRect(x: 10, y: 70, width: size.width - 20, height: size.height - 80), configuration: config)
            self.web = web
            content.addSubview(web)
            web.load(URLRequest(url: URL(string: "https://example.com")!))
        } else {
            let label = NSTextField(labelWithString: "Native receiver covers the web receiver on the virtual display.")
            label.frame = NSRect(x: 20, y: size.height - 70, width: size.width - 40, height: 30)
            content.addSubview(label)
        }
        window.orderBack(nil)
        window.makeFirstResponder(editor)
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.record() }
        }
        record()
    }

    @objc func commit() { commits += 1; record() }

    func record() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let physical = ids.prefix(Int(count)).filter { !(CGDisplayVendorNumber($0) == 0x0CAC && CGDisplayModelNumber($0) == 0x0CAC) }
        let item: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "window_id": window.windowNumber, "marker": editor.stringValue, "commits": commits,
            "active": NSApp.isActive, "web_loading": web?.isLoading ?? false,
            "front_pid": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
            "clipboard_change_count": NSPasteboard.general.changeCount,
            "physical_displays": physical, "main_display": CGMainDisplayID()]
        if let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]) {
            try? data.write(to: stateFile, options: .atomic)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let receiver = DisplayProbe()
    app.delegate = receiver
    app.run()
}
