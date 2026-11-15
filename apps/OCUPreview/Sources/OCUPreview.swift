import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@main
@MainActor
enum OCUPreviewMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let controller = PreviewController()
        application.delegate = controller
        application.run()
        withExtendedLifetime(controller) {}
    }
}

@MainActor
final class PreviewController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private let imageView = NSImageView()
    private let status = NSTextField(labelWithString: "正在寻找 OCU 虚拟屏…")
    private let selector = NSPopUpButton()
    private var allowButton: NSButton!
    private var settingsButton: NSButton!
    private var displays: [PreviewDisplay] = []
    private var selectedSerial: UInt32?
    private var activeDisplay: PreviewDisplay?
    private var generation: UInt64 = 0
    private var stream: SCStream?
    private var capture: PreviewCapture?
    private var startTask: Task<Void, Never>?
    private var timer: Timer?
    private var frameTimer: Timer?
    private var failed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "OCU"
        statusItem.button?.toolTip = "OCU 虚拟屏只读预览"
        let menu = NSMenu()
        for (title, action) in [("显示虚拟屏预览", #selector(showPreview)),
                                ("关闭预览", #selector(closePreview)),
                                ("退出预览", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        statusItem.menu = menu
        createWindow()
        showPreview()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreview(); return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { stopCapture() }

    private func createWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "OCU 虚拟屏 · 只读实时预览"
        window.identifier = NSUserInterfaceItemIdentifier("ocu-read-only-preview")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 480, height: 320)
        window.setFrameAutosaveName("OCUReadOnlyPreview")
        // Ordinary user-owned window: never park it or restore automation windows.
        if !window.setFrameUsingName("OCUReadOnlyPreview") { window.center() }
        guard let root = window.contentView else { return }
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor.black.cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setAccessibilityLabel("虚拟屏画面（只读，不转发鼠标键盘）")
        selector.target = self; selector.action = #selector(changeDisplay)
        selector.setAccessibilityLabel("选择 OCU 虚拟屏")
        let allow = button("允许屏幕录制", #selector(requestPermission))
        let settings = button("打开权限设置", #selector(openSettings))
        allowButton = allow; settingsButton = settings
        let retry = button("重试", #selector(retry))
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [selector, allow, settings, retry])
        controls.orientation = .horizontal; controls.spacing = 8
        let footer = NSStackView(views: [status, controls])
        footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 6
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)
        footer.wantsLayer = true; footer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        for view in [imageView, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: root.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 76),
        ])
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    @objc private func showPreview() {
        window.orderFrontRegardless()
        // No NSApp.activate: merely observing never steals the current app's focus.
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.reconcile() }
            }
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.renderLatest() }
            }
            reconcile()
        }
    }
    @objc private func closePreview() { window.close() }
    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        frameTimer?.invalidate(); frameTimer = nil
        stopCapture()
    }
    @objc private func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
        retry()
    }
    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func retry() { stopCapture(); failed = false; reconcile() }
    @objc private func changeDisplay() {
        guard displays.indices.contains(selector.indexOfSelectedItem) else { return }
        selectedSerial = displays[selector.indexOfSelectedItem].serial
        retry()
    }

    private func stopCapture() {
        generation &+= 1
        startTask?.cancel(); startTask = nil
        let prior = stream
        stream = nil; activeDisplay = nil
        capture?.frames.clear(); capture = nil; imageView.image = nil
        // The pending start task retains its own stream and also stops it after
        // startCapture returns if superseded, covering close during async start.
        if let prior { Task { try? await prior.stopCapture() } }
    }

    private func reconcile() {
        guard timer != nil else { return }
        let permissionGranted = CGPreflightScreenCaptureAccess()
        allowButton.isHidden = permissionGranted
        settingsButton.isHidden = permissionGranted
        let current = PreviewDisplay.discover()
        if current != displays {
            displays = current
            selector.removeAllItems()
            selector.addItems(withTitles: current.enumerated().map { "虚拟屏 \($0.offset + 1) · \($0.element.serial)" })
            if let index = current.firstIndex(where: { $0.serial == selectedSerial }) { selector.selectItem(at: index) }
            selector.isEnabled = current.count > 1
        }
        guard let target = PreviewDisplay.selected(in: current, serial: selectedSerial) else {
            if activeDisplay != nil || startTask != nil { stopCapture() }
            status.stringValue = "等待 OCU 虚拟屏连接 · 只读预览"
            return
        }
        if activeDisplay != target {
            stopCapture(); failed = false
        }
        guard permissionGranted else {
            stopCapture()
            status.stringValue = "请允许本预览应用使用屏幕录制，然后点击“重试”"
            return
        }
        guard stream == nil, startTask == nil, !failed else { return }
        selectedSerial = target.serial; activeDisplay = target
        let token = generation
        status.stringValue = "正在连接虚拟屏…"
        startTask = Task { [weak self] in
            guard let self else { return }
            var pending: SCStream?
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard self.generation == token, !Task.isCancelled,
                      PreviewDisplay.discover().contains(target),
                      let display = content.displays.first(where: { $0.displayID == target.id }) else {
                    if self.generation == token { self.startTask = nil; self.activeDisplay = nil }
                    return
                }
                let capture = PreviewCapture { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.stopCapture(); self.failed = true
                        self.activeDisplay = target
                        self.status.stringValue = "预览已停止：\(message) · 点击重试"
                    }
                }
                let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
                let newStream = try capture.makeStream(display: display, excluding: ownWindows)
                pending = newStream
                self.capture = capture; self.stream = newStream
                try await newStream.startCapture()
                guard self.generation == token, !Task.isCancelled else {
                    try? await newStream.stopCapture(); capture.frames.clear(); return
                }
                self.startTask = nil
                self.status.stringValue = "只读 · 实时 · \(display.width) × \(display.height) · 鼠标键盘不会传入虚拟屏"
            } catch {
                if let pending { try? await pending.stopCapture() }
                guard self.generation == token else { return }
                self.stopCapture(); self.failed = true
                self.activeDisplay = target
                self.status.stringValue = "无法预览：\(error.localizedDescription) · 点击重试"
            }
        }
    }

    private func renderLatest() {
        guard let activeDisplay, PreviewDisplay.discover().contains(activeDisplay) else {
            imageView.image = nil; return
        }
        if let image = capture?.frames.take() {
            imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }
}
