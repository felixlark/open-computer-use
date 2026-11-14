import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// A pin is owned by one process instance and AX window, not by a reusable
/// WindowServer number. nil means observation is inconclusive, never live.
struct WindowOcclusionIdentity {
    let isCurrent: () -> Bool?

    init(validate: @escaping () -> Bool?) { isCurrent = validate }

    init(windowID: CGWindowID, pid: pid_t, launchDate: Date?, element: AXUIElement) {
        isCurrent = {
            guard let launchDate else { return nil }
            guard let records = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
            guard let row = records.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }) else { return false }
            guard let owner = row[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            guard owner.int32Value == pid, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            guard let currentLaunch = app.launchDate else { return nil }
            guard currentLaunch == launchDate else { return false }
            guard let currentID = SkyLightSPI.shared.windowID(for: element) else { return nil }
            return currentID == windowID
        }
    }

    /// Compatibility for internal callers that have only a native window ID.
    /// Failure to bind its AX identity simply declines the optional pin.
    static func capture(windowID: CGWindowID) -> WindowOcclusionIdentity? {
        guard let rows = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let owner = rows.first?[kCGWindowOwnerPID as String] as? NSNumber,
              let app = AppDiscovery.runningApps().first(where: { $0.pid == owner.int32Value }),
              let target = try? SnapshotBuilder.resolveTargetWindow(for: app, windowID: windowID) else { return nil }
        return WindowOcclusionIdentity(windowID: windowID, pid: app.pid,
            launchDate: app.runningApplication.launchDate, element: target.windowElement)
    }
}
