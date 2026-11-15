import AppKit

// Manual installed-app acceptance only; never run this through XCTest.
@MainActor
final class PreviewFixture: NSObject, NSApplicationDelegate {
    let stateURL = URL(fileURLWithPath: CommandLine.arguments.last!)
    var window: NSWindow!
    var label: NSTextField!
    var presses = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 560, height: 260),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "OCU Preview Acceptance Fixture"
        let root = window.contentView!
        label = NSTextField(labelWithString: "PREVIEW A · presses 0")
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.frame = NSRect(x: 20, y: 150, width: 520, height: 70)
        root.addSubview(label)
        let button = NSButton(title: "Change preview marker", target: self, action: #selector(change))
        button.frame = NSRect(x: 20, y: 50, width: 260, height: 40)
        root.addSubview(button)
        window.orderFrontRegardless()
        record()
    }
    @objc func change() {
        presses += 1; label.stringValue = "PREVIEW B · presses \(presses)"; record()
    }
    func record() {
        let state: [String: Any] = ["pid": getpid(), "window_id": window.windowNumber,
                                  "presses": presses, "marker": label.stringValue]
        if let data = try? JSONSerialization.data(withJSONObject: state) { try? data.write(to: stateURL) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = PreviewFixture(); app.delegate = delegate; app.run()
}
