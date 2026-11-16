import AppKit
import Foundation
import OpenComputerUseKit

final class MCPAppRuntime: NSObject, NSApplicationDelegate {
    private let server: StdioMCPServer
    private var runtimeError: Error?
    private var turnEndedObserver: NSObjectProtocol?

    private init(server: StdioMCPServer) {
        self.server = server
    }

    @MainActor
    static func run(server: StdioMCPServer) throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let delegate = MCPAppRuntime(server: server)
        application.delegate = delegate
        application.run()

        if let runtimeError = delegate.runtimeError {
            throw runtimeError
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        turnEndedObserver = DistributedNotificationCenter.default().addObserver(
            forName: currentOpenComputerUseTurnEndedNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Tools can synchronously require the main queue while holding the
            // state transaction. Never wait for that transaction on main.
            DispatchQueue.global(qos: .userInitiated).async {
                resetOpenComputerUseBackgroundWindowState()
                Task { @MainActor in resetOpenComputerUseVisualCursor() }
            }
        }
        Thread.detachNewThreadSelector(#selector(processStandardIO), toTarget: self, with: nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // An in-flight AX call can need main while holding the display lock.
        // Never wait for that lock on the AppKit thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let allowed = PhoneHostDisplay.shared.prepareNormalTermination()
            Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: allowed) }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Process-exit hooks restore placement/pins. Do not block main behind
        // an in-flight tool that may still need the main queue.
        if let turnEndedObserver {
            DistributedNotificationCenter.default().removeObserver(turnEndedObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc
    private func processStandardIO() {
        do {
            try server.run()
        } catch {
            runtimeError = error
        }

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
