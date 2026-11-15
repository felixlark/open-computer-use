import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Physical placement for caller-confirmed Agent windows. No display creation,
/// app launch, activation, focus change or global pointer operation.
enum RightDisplayPlacement {
    static func rightmost(_ displays: [UInt32: CGRect]) -> UInt32? {
        displays.keys.max {
            let a = displays[$0]!, b = displays[$1]!
            return a.midX == b.midX ? $0 < $1 : a.midX < b.midX
        }
    }

    static func fittedFrame(original: CGRect, display: CGRect) -> CGRect {
        let area = display.insetBy(dx: min(40, display.width / 10),
                                  dy: min(40, display.height / 10))
        let size = CGSize(width: min(original.width, area.width),
                          height: min(original.height, area.height))
        if area.contains(original) { return original }
        return CGRect(origin: area.origin, size: size)
    }

    static func move(windowID: CGWindowID, pid: pid_t, window: AXUIElement) throws {
        var role: CFTypeRef?
        let roleRead = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role)
        guard let launch = NSRunningApplication(processIdentifier: pid)?.launchDate,
              SkyLightSPI.shared.windowID(for: window) == windowID,
              roleRead == .success, role as? String == kAXWindowRole as String else {
            throw ComputerUseError.stateUnavailable("right_display requires the exact live AXWindow")
        }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            throw ComputerUseError.stateUnavailable("Could not enumerate physical displays")
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            throw ComputerUseError.stateUnavailable("Could not enumerate physical displays")
        }
        let displays = Dictionary(uniqueKeysWithValues: ids.prefix(Int(count)).filter {
            !(CGDisplayVendorNumber($0) == 0x0CAC && CGDisplayModelNumber($0) == 0x0CAC)
                && CGDisplayIsInMirrorSet($0) == 0
        }.map { ($0, CGDisplayBounds($0)) })
        guard let id = rightmost(displays), let bounds = displays[id],
              AgentWindowGeometry.valid(bounds) else {
            throw ComputerUseError.stateUnavailable("No rightmost physical display is available")
        }
        func readFrame() -> CGRect? {
            guard NSRunningApplication(processIdentifier: pid)?.launchDate == launch,
                  SkyLightSPI.shared.windowID(for: window) == windowID,
                  let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
                  let info = list.first(where: {
                      ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
                        && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                  }), let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: dict)
        }
        guard let original = readFrame(), AgentWindowGeometry.valid(original) else {
            throw ComputerUseError.stateUnavailable("right_display could not read the exact window frame")
        }
        if bounds.contains(original) { return }
        let target = fittedFrame(original: original, display: bounds)
        func contained() -> Bool { readFrame().map { bounds.contains($0) } ?? false }
        func settle(_ predicate: () -> Bool) -> Bool {
            let until = Date().addingTimeInterval(2)
            repeat {
                if predicate() { return true }
                Thread.sleep(forTimeInterval: 0.025)
            } while Date() < until
            return predicate()
        }
        func write(_ attribute: String, _ value: AXValue?, matches: () -> Bool) throws {
            guard readFrame() != nil, let value else {
                throw ComputerUseError.stateUnavailable("right_display lost exact window identity")
            }
            let result = AXUIElementSetAttributeValue(window, attribute as CFString, value)
            // Some apps adjust their own outer frame on a display change (for
            // example Device Hub). The contract is the complete live frame on
            // the right screen, not equality with an app-rejected size/origin.
            guard settle({ contained() || matches() }) else {
                throw ComputerUseError.stateUnavailable("right_display geometry remains unconfirmed (AX \(result.rawValue)); observe before retrying")
            }
        }
        // Shrink an oversized frame before moving it. Otherwise an app can
        // clamp the requested origin to the old size and prevent the resize.
        if !AgentWindowGeometry.sameSize(original, target, tolerance: 1) {
            var size = target.size
            try write(kAXSizeAttribute as String, AXValueCreate(.cgSize, &size), matches: {
                readFrame().map { AgentWindowGeometry.sameSize($0, target, tolerance: 1) } ?? false
            })
            if contained() { return }
        }
        // Only a confirmed resize can lead to this new position write.
        var point = target.origin
        try write(kAXPositionAttribute as String, AXValueCreate(.cgPoint, &point), matches: contained)
        guard contained() else {
            throw ComputerUseError.stateUnavailable("right_display could not confirm the complete frame")
        }
    }
}
