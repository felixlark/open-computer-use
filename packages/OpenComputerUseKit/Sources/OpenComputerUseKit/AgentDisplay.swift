import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OpenComputerUseVirtualDisplayShim

public enum WindowPlacement: String, CaseIterable, Sendable {
    case keep
    case agentDisplay = "agent_display"
    case restore
    case release
}

func parseWindowPlacement(_ rawValue: String?) throws -> WindowPlacement {
    let normalized = rawValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? WindowPlacement.keep.rawValue

    guard let placement = WindowPlacement(rawValue: normalized) else {
        let expected = WindowPlacement.allCases.map(\.rawValue).joined(separator: ", ")
        throw ComputerUseError.message(
            "Invalid window_placement '\(rawValue ?? "")'. Expected one of: \(expected)"
        )
    }

    return placement
}

func validateExactWindowPlacement(_ placement: WindowPlacement, windowID: CGWindowID?) throws {
    if windowID == 0 { throw ComputerUseError.invalidArguments("window_id must be positive") }
    if placement == .release && windowID == nil {
        throw ComputerUseError.invalidArguments("window_placement release requires an explicit window_id")
    }
}

/// Unknown enumeration retains the display; removing it could relocate a live
/// window whose recovery record was deliberately released by its owner.
func agentDisplayHasOccupants(windowFrames: [CGRect]?, displayBounds: CGRect) -> Bool {
    guard let windowFrames else { return true }
    return windowFrames.contains { !$0.isEmpty && $0.intersects(displayBounds) }
}

/// Use the WindowServer's complete non-desktop window list. Floating panels
/// and other nonzero layers are real occupants too; malformed metadata is not
/// evidence that dropping this display is safe.
func agentDisplayHasOccupants(windowInfo: [[String: Any]]?, displayBounds: CGRect) -> Bool {
    guard let windowInfo else { return true }
    var frames: [CGRect] = []
    for info in windowInfo {
        guard let value = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: value) else { return true }
        frames.append(frame)
    }
    return agentDisplayHasOccupants(windowFrames: frames, displayBounds: displayBounds)
}

/// Once a persistent workspace has been requested, keep its display until the
/// owner exits, even after all window records are pruned. Request/session
/// environment restoration must not turn that decision back into auto-destroy.
struct AgentDisplayRetention {
    private(set) var untilOwnerExit = false
    mutating func recordPark(restoreOnSessionEnd: Bool) {
        untilOwnerExit = untilOwnerExit || !restoreOnSessionEnd
    }
}

/// Where a parked window goes on the agent display: inset from the top-left
/// corner, clamped so at least the top-left `minVisible` points stay inside the
/// display when the window is larger than it.
func agentDisplayPlacement(windowSize: CGSize, displayBounds: CGRect, inset: CGFloat = 40, minVisible: CGFloat = 200) -> CGPoint {
    let maxX = max(displayBounds.minX, displayBounds.maxX - max(windowSize.width, minVisible))
    let maxY = max(displayBounds.minY, displayBounds.maxY - max(windowSize.height, minVisible))
    return CGPoint(
        x: min(displayBounds.minX + inset, maxX),
        y: min(displayBounds.minY + inset, maxY)
    )
}

/// Preserve the legacy identity, while namespaced owners use stable distinct
/// serials. WindowServer rejects simultaneous displays with the same identity.
func agentDisplaySerialNumber(namespace: String?) -> UInt32 {
    let file = openComputerUseAppAgentSocketFileName(namespace: namespace)
    guard file != openComputerUseAppAgentSocketFileName(namespace: nil) else { return 1 }
    let digest = file.dropFirst("open-computer-use-agent-".count).prefix(8)
    return max(2, UInt32(digest, radix: 16) ?? 2)
}

func agentDisplayRestoredPosition(original: CGPoint, originalDisplay: CGRect?, targetDisplay: CGRect, windowSize: CGSize) -> CGPoint {
    let offset = CGPoint(x: original.x - (originalDisplay?.minX ?? targetDisplay.minX),
                         y: original.y - (originalDisplay?.minY ?? targetDisplay.minY))
    let maxX = max(targetDisplay.minX, targetDisplay.maxX - min(max(windowSize.width, 1), targetDisplay.width))
    let maxY = max(targetDisplay.minY, targetDisplay.maxY - min(max(windowSize.height, 1), targetDisplay.height))
    return CGPoint(x: min(max(targetDisplay.minX + offset.x, targetDisplay.minX), maxX),
                   y: min(max(targetDisplay.minY + offset.y, targetDisplay.minY), maxY))
}

/// Geometry belongs to the placement owner, never to a consumer that would
/// otherwise overwrite the original frame before OCU can capture it.
enum AgentWindowGeometry {
    static func valid(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    static func samePosition(_ frame: CGRect, _ target: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(frame.minX - target.minX) < tolerance && abs(frame.minY - target.minY) < tolerance
    }

    static func sameSize(_ frame: CGRect, _ target: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(frame.width - target.width) < tolerance && abs(frame.height - target.height) < tolerance
    }

    static func sameFrame(_ frame: CGRect, _ target: CGRect) -> Bool {
        valid(frame) && valid(target) && samePosition(frame, target) && sameSize(frame, target)
    }

    static func displayContainsCenter(_ bounds: CGRect, frame: CGRect) -> Bool {
        bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    static func fittedFrame(original: CGRect, display: CGRect, inset: CGFloat = 40) -> CGRect {
        // Fit the inset area, including exact-screen-size windows. A full-bounds
        // target at y=0 can be clamped below the menu bar by WindowServer.
        let size = CGSize(width: min(original.width, max(1, display.width - 2 * inset)),
                          height: min(original.height, max(1, display.height - 2 * inset)))
        return CGRect(origin: agentDisplayPlacement(windowSize: size, displayBounds: display, inset: inset), size: size)
    }

    /// Only fallback selection uses fitting. An unchanged original display
    /// retains its exact frame, including intentional partial offscreen edges.
    static func fallbackDisplayID(displays: [UInt32: CGRect], main: UInt32, windowSize: CGSize?) -> UInt32? {
        func largest(_ candidates: [UInt32: CGRect]) -> UInt32? {
            candidates.max { a, b in
                let left = a.value.width * a.value.height, right = b.value.width * b.value.height
                return left == right ? a.key > b.key : left < right
            }?.key
        }
        guard let size = windowSize else { return displays[main] == nil ? largest(displays) : main }
        // The same existing40pt margin avoids WindowServer menu/edge clamps.
        // This never shrinks the original restoration target.
        let fitting = displays.filter { canRestore(size, on: $0.value) }
        if fitting.isEmpty { return largest(displays) }
        return fitting[main] == nil ? largest(fitting) : main
    }

    static func canRestore(_ size: CGSize, on bounds: CGRect) -> Bool {
        size.width <= max(1, bounds.width - 80) && size.height <= max(1, bounds.height - 80)
    }

    static func restorationDisplayID(displays: [UInt32: CGRect], main: UInt32,
        originalID: UInt32?, originalBounds: CGRect?, windowSize: CGSize) -> UInt32? {
        if let id = originalID, let current = displays[id],
           current == originalBounds || canRestore(windowSize, on: current) { return id }
        return fallbackDisplayID(displays: displays, main: main, windowSize: windowSize)
    }

    static func restoredFrame(original: CGRect, originalDisplay: CGRect?, targetDisplay: CGRect?) -> CGRect {
        guard let targetDisplay, targetDisplay != originalDisplay else { return original }
        let rebased = agentDisplayRestoredPosition(original: original.origin, originalDisplay: originalDisplay,
            targetDisplay: targetDisplay, windowSize: original.size)
        let area = targetDisplay.insetBy(dx: min(40, max(0, (targetDisplay.width - 1) / 2)),
            dy: min(40, max(0, (targetDisplay.height - 1) / 2)))
        let origin = agentDisplayRestoredPosition(original: rebased, originalDisplay: nil, targetDisplay: area, windowSize: original.size)
        return CGRect(origin: origin, size: original.size)
    }
}

/// A single ordered geometry transaction. Injectable reads/writes also let
/// non-GUI tests exercise uncertain AX acknowledgements and identity loss.
struct AgentWindowGeometryWriter {
    let readFrame: () -> CGRect?
    let setPosition: (CGPoint) throws -> Void
    let setSize: (CGSize) throws -> Void
    let settle: (() -> Bool) -> Bool

    func apply(_ target: CGRect, restoring: Bool) throws {
        guard AgentWindowGeometry.valid(target) else {
            throw ComputerUseError.stateUnavailable("window_placement has invalid target geometry")
        }
        // Restore on the physical display before expanding: expanding while
        // still on the smaller invisible screen can be clamped by the OS.
        if restoring { try position(target) }
        try size(target)
        try position(target)
        guard settle({ readFrame().map { AgentWindowGeometry.sameFrame($0, target) } ?? false }) else {
            throw ComputerUseError.stateUnavailable("window_placement could not confirm the complete window frame")
        }
    }

    private func position(_ target: CGRect) throws {
        try write(target, matches: AgentWindowGeometry.samePosition, action: { try setPosition(target.origin) })
    }

    private func size(_ target: CGRect) throws {
        try write(target, matches: AgentWindowGeometry.sameSize, action: { try setSize(target.size) })
    }

    private func write(_ target: CGRect, matches: (CGRect, CGRect, CGFloat) -> Bool, action: () throws -> Void) throws {
        // readFrame includes the exact identity check immediately before every
        // write and on every observation. Unknown/replaced identities stop here.
        guard let current = readFrame(), AgentWindowGeometry.valid(current) else {
            throw ComputerUseError.stateUnavailable("window_placement could not verify the target identity and frame")
        }
        if matches(current, target, 1) { return }
        var failure: Error?
        do { try action() } catch { failure = error }
        // An AX error can follow delivery. Observe the requested attribute;
        // never replay an unconfirmed write, even when the call returned success.
        guard settle({ readFrame().map { matches($0, target, 1) } ?? false }) else {
            throw failure ?? ComputerUseError.stateUnavailable("window_placement geometry write remains unconfirmed")
        }
    }
}

/// The agent's own display: a virtual display (the mechanism behind Screen
/// Sharing's headless sessions) that the user never sees. A window parked on it
/// is genuinely on screen for WindowServer, so its app renders it, exposes its
/// full accessibility tree and accepts input, while the user's Space, foreground
/// app and pointer are untouched. Parking moves the window's frame (AX
/// position/size, no activation); the original frame is restored on `restore`
/// and at process exit, and the display is removed once nothing is parked.
final class AgentDisplay: @unchecked Sendable {
    static let shared = AgentDisplay()

    static let displaySize = CGSize(width: 1920, height: 1080)
    // Upper bounds for the polls; the observed values are far lower and are
    // logged with OPEN_COMPUTER_USE_DEBUG_TIMING=1.
    static let displaySettle: TimeInterval = 3.0
    static let moveSettle: TimeInterval = 2.0
    // Fallback sleeps when the observation SPIs are unavailable.
    static let displayFallbackSettle: TimeInterval = 0.5

    struct ParkedWindow {
        let pid: pid_t
        let element: AXUIElement
        let originalFrame: CGRect
        let originalDisplayID: CGDirectDisplayID?
        let originalDisplayBounds: CGRect?
        let processLaunchDate: Date
        var restoreOnSessionEnd: Bool
    }

    private let lock = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private(set) var displayID: CGDirectDisplayID = 0
    private(set) var displaySpaceIDs: Set<UInt64> = []
    private var parked: [CGWindowID: ParkedWindow] = [:]
    private var exitHookInstalled = false
    private var retention = AgentDisplayRetention()

    var isSupported: Bool {
        ocu_virtual_display_is_supported() != 0
    }

    var displayBounds: CGRect? {
        displayID == 0 ? nil : CGDisplayBounds(displayID)
    }

    func isParked(windowID: CGWindowID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return parked[windowID] != nil
    }

    func parkedWindowIDs(pid: pid_t) -> [CGWindowID] {
        lock.lock()
        defer { lock.unlock() }
        return parked.filter { $0.value.pid == pid }.map(\.key)
    }

    /// Explicit login bootstrap; configuration is sampled under the lifecycle lock.
    func ensureForHost() throws -> PersistentDisplayReadiness {
        lock.lock()
        defer { lock.unlock() }
        let config = VirtualDisplayConfig.current
        try PersistentDisplayBootstrap.requireConfiguration(config)
        let bounds = try ensureDisplay(configuration: config)
        retention.recordPark(restoreOnSessionEnd: config.restoreOnSessionEnd)
        installExitHookIfNeeded()
        let namespace = getenv(openComputerUseAppAgentSocketNamespaceEnvironmentKey)
            .map { String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return PersistentDisplayReadiness(id: displayID, bounds: bounds, namespace: namespace)
    }

    /// Move `window` onto the agent display. Returns the display bounds.
    @discardableResult
    func park(windowID: CGWindowID, pid: pid_t, window: AXUIElement) throws -> CGRect {
        lock.lock()
        defer { lock.unlock() }

        let config = VirtualDisplayConfig.current
        try config.requireEnabled()
        guard let launchDate = NSRunningApplication(processIdentifier: pid)?.launchDate,
              SkyLightSPI.shared.windowID(for: window) == windowID else {
            throw ComputerUseError.stateUnavailable("window_placement 'agent_display' could not verify the target window identity")
        }
        if var existing = parked[windowID] {
            if existing.pid == pid, existing.processLaunchDate == launchDate, CFEqual(existing.element, window) {
                let bounds = try ensureDisplay()
                guard let frame = Self.windowFrame(windowID), bounds.contains(frame) else {
                    throw ComputerUseError.stateUnavailable("Existing placement is not on the agent display; inspect this exact window, then restore or release before parking again")
                }
                existing.restoreOnSessionEnd = config.restoreOnSessionEnd
                parked[windowID] = existing
                retention.recordPark(restoreOnSessionEnd: config.restoreOnSessionEnd)
                return bounds
            }
            parked.removeValue(forKey: windowID)
            WindowOcclusionKeepAlive.shared.forget(windowIDs: [windowID])
        }

        guard let position = axPoint(window, kAXPositionAttribute as String), let size = axSize(window),
              AgentWindowGeometry.valid(CGRect(origin: position, size: size)) else {
            throw ComputerUseError.stateUnavailable("window_placement 'agent_display' could not read the complete window frame")
        }
        let originalDisplay = Self.activeDisplays().first { AgentWindowGeometry.displayContainsCenter($0.bounds, frame: CGRect(origin: position, size: size)) }
        // Capture before creation: WindowServer can change the global origin
        // when a display is added or the previous main display goes offline.
        let start = TimingLog.now()
        let entry = ParkedWindow(pid: pid, element: window, originalFrame: CGRect(origin: position, size: size),
                                      originalDisplayID: originalDisplay?.id, originalDisplayBounds: originalDisplay?.bounds,
                                      processLaunchDate: launchDate, restoreOnSessionEnd: config.restoreOnSessionEnd)
        // Own recovery before display creation and every uncertain AX effect.
        parked[windowID] = entry
        retention.recordPark(restoreOnSessionEnd: config.restoreOnSessionEnd)
        installExitHookIfNeeded()
        let bounds = try ensureDisplay()
        let target = AgentWindowGeometry.fittedFrame(original: entry.originalFrame, display: bounds)
        try geometryWriter(for: entry, windowID: windowID).apply(target, restoring: false)
        try waitForWindow(windowID, entry: entry, toLandOn: displaySpaceIDs, or: bounds)
        TimingLog.log("agent_display.park", since: start)
        return bounds
    }

    /// Wait until the window's frame sits inside the display and, when the
    /// Space SPI is available, WindowServer also reports it on one of the
    /// display's Spaces. Space membership alone precedes the frame update.
    private func waitForWindow(_ windowID: CGWindowID, entry: ParkedWindow, toLandOn spaceIDs: Set<UInt64>, or bounds: CGRect) throws {
        let spi = SkyLightSPI.shared
        let landed = waitUntil(timeout: Self.moveSettle) {
            guard self.identity(of: entry, windowID: windowID) == .live,
                  let frame = Self.windowFrame(windowID), bounds.contains(frame)
            else { return false }
            if !spaceIDs.isEmpty, let spaces = spi.spaces(forWindow: windowID) {
                return spaces.contains(where: spaceIDs.contains)
            }
            return true
        }
        if landed == nil {
            throw ComputerUseError.stateUnavailable("window_placement could not confirm the complete frame on the agent display")
        }
    }

    private static func windowFrame(_ windowID: CGWindowID) -> CGRect? {
        let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in infoList {
            guard let number = info[kCGWindowNumber as String] as? NSNumber, number.uint32Value == windowID,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { continue }
            return bounds
        }
        return nil
    }

    static func isRestored(frame: CGRect, to originalFrame: CGRect) -> Bool {
        AgentWindowGeometry.sameFrame(frame, originalFrame)
    }

    private func geometryWriter(for entry: ParkedWindow, windowID: CGWindowID) -> AgentWindowGeometryWriter {
        AgentWindowGeometryWriter(readFrame: {
            guard self.identity(of: entry, windowID: windowID) == .live else { return nil }
            return Self.windowFrame(windowID)
        }, setPosition: { try self.setAXPosition(entry.element, $0) },
           setSize: { try self.setAXSize(entry.element, $0) },
           settle: { waitUntil(timeout: Self.moveSettle, $0) != nil })
    }

    private enum WindowIdentity { case live, gone, unknown }

    private func identity(of entry: ParkedWindow, windowID: CGWindowID) -> WindowIdentity {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return .unknown }
        guard let info = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }) else { return .gone }
        guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber else { return .unknown }
        guard owner.int32Value == entry.pid else { return .gone }
        guard let launchDate = NSRunningApplication(processIdentifier: entry.pid)?.launchDate else { return .unknown }
        guard launchDate == entry.processLaunchDate else { return .gone }
        guard let liveID = SkyLightSPI.shared.windowID(for: entry.element) else { return .unknown }
        return liveID == windowID ? .live : .gone
    }

    /// Placement and occlusion pins may belong to the app agent rather than a
    /// client. Return surviving IDs so session cleanup keeps their content live.
    func endSession() -> Set<CGWindowID> {
        lock.lock()
        let closed = Set(parked.compactMap { identity(of: $0.value, windowID: $0.key) == .gone ? $0.key : nil })
        for windowID in closed { parked.removeValue(forKey: windowID) }
        let transient = parked.filter { $0.value.restoreOnSessionEnd }.map(\.key)
        destroyDisplayIfIdle()
        lock.unlock()
        WindowOcclusionKeepAlive.shared.forget(windowIDs: closed)
        for windowID in transient { try? restore(windowID: windowID) }
        lock.lock()
        defer { lock.unlock() }
        return Set(parked.keys)
    }

    /// Put a parked window back where it was.
    func restore(windowID: CGWindowID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = parked[windowID] else {
            return
        }
        switch identity(of: entry, windowID: windowID) {
        case .gone:
            parked.removeValue(forKey: windowID)
            WindowOcclusionKeepAlive.shared.forget(windowIDs: [windowID])
            destroyDisplayIfIdle()
            return
        case .unknown:
            throw ComputerUseError.stateUnavailable("window_placement 'restore' could not verify the parked window identity")
        case .live:
            break
        }
        let start = TimingLog.now()
        let displays = Self.activeDisplays()
        let physical = displays.filter { !Self.isAgentDisplay($0.id) }
        let targetID = AgentWindowGeometry.restorationDisplayID(
            displays: Dictionary(uniqueKeysWithValues: physical.map { ($0.id, $0.bounds) }), main: CGMainDisplayID(),
            originalID: entry.originalDisplayID, originalBounds: entry.originalDisplayBounds, windowSize: entry.originalFrame.size)
        guard let target = physical.first(where: { $0.id == targetID }) else {
            throw ComputerUseError.stateUnavailable("No physical display is available for window restoration")
        }
        let targetFrame = AgentWindowGeometry.restoredFrame(original: entry.originalFrame,
            originalDisplay: entry.originalDisplayBounds, targetDisplay: target.bounds)
        do {
            try geometryWriter(for: entry, windowID: windowID).apply(targetFrame, restoring: true)
        } catch {
            // A failed frame read is not evidence of closure. Unknown identity
            // and all partial writes retain both recovery and visibility pin.
            if identity(of: entry, windowID: windowID) == .gone {
                parked.removeValue(forKey: windowID)
                WindowOcclusionKeepAlive.shared.forget(windowIDs: [windowID])
                destroyDisplayIfIdle()
                return
            }
            throw error
        }
        _ = WindowOcclusionKeepAlive.shared.release(windowID: windowID)
        parked.removeValue(forKey: windowID)
        TimingLog.log("agent_display.restore", since: start)
        destroyDisplayIfIdle()
    }

    /// Relinquish only this recovery entry. Never move a user-taken-over window,
    /// and never perform a snapshot here (it would immediately pin it again).
    func release(windowID: CGWindowID, pid: pid_t) throws -> (registered: Bool, occlusionRestored: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let entry = parked[windowID], entry.pid != pid, identity(of: entry, windowID: windowID) != .gone {
            throw ComputerUseError.stateUnavailable("window_id belongs to another parked process")
        }
        let registered = parked.removeValue(forKey: windowID) != nil
        let restored = WindowOcclusionKeepAlive.shared.release(windowID: windowID)
        destroyDisplayIfIdle()
        return (registered, restored)
    }

    func restoreAll() {
        lock.lock()
        let windowIDs = Array(parked.keys)
        lock.unlock()
        for windowID in windowIDs {
            try? restore(windowID: windowID)
        }
    }

    /// Restore every window parked for one application. Unlike process-exit
    /// cleanup, an explicit restore reports a live failure to the caller after
    /// attempting the remaining windows.
    func restoreAll(pid: pid_t) throws {
        let windowIDs = parkedWindowIDs(pid: pid)
        var firstError: Error?
        for windowID in windowIDs {
            do {
                try restore(windowID: windowID)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    // MARK: - Display lifecycle (call with lock held)

    private func ensureDisplay(configuration: VirtualDisplayConfig? = nil) throws -> CGRect {
        try (configuration ?? .current).requireEnabled()
        if displayID != 0, let bounds = displayBounds, !bounds.isEmpty {
            return bounds
        }
        guard isSupported else {
            throw ComputerUseError.message("window_placement 'agent_display' is unavailable: CGVirtualDisplay is not present on this macOS")
        }
        let spi = SkyLightSPI.shared
        let priorMain = CGMainDisplayID()
        let spacesBefore = Set((spi.managedDisplaySpaces() ?? [:]).values.flatMap { $0 })
        let start = TimingLog.now()
        var newHandle: UnsafeMutableRawPointer?
        let namespace = getenv(openComputerUseAppAgentSocketNamespaceEnvironmentKey).map { String(cString: $0) }
        let id = ocu_virtual_display_create_with_serial("Open Computer Use", UInt32(Self.displaySize.width), UInt32(Self.displaySize.height), 60, agentDisplaySerialNumber(namespace: namespace), &newHandle)
        guard id != 0, let newHandle else {
            throw ComputerUseError.message("window_placement 'agent_display' could not create the agent display")
        }
        handle = newHandle
        displayID = id
        TimingLog.log("agent_display.create", since: start)

        // Ready means WindowServer reports the display's bounds and has given
        // it a Space; without the Space SPI, fall back to a fixed settle.
        var newSpaces: Set<UInt64> = []
        let ready = waitUntil(timeout: Self.displaySettle) {
            guard let bounds = self.displayBounds, !bounds.isEmpty else { return false }
            guard let displays = spi.managedDisplaySpaces() else { return true }
            newSpaces = Set(displays.values.flatMap { $0 }).subtracting(spacesBefore)
            return !newSpaces.isEmpty
        }
        if ready == nil, displayBounds?.isEmpty != false {
            destroyDisplay()
            throw ComputerUseError.message("window_placement 'agent_display' timed out waiting for the agent display")
        }
        if newSpaces.isEmpty {
            Thread.sleep(forTimeInterval: Self.displayFallbackSettle)
        }
        displaySpaceIDs = newSpaces
        try preserveUserMainDisplay(priorMain: priorMain)
        TimingLog.log("agent_display.ready", since: start)
        return displayBounds ?? .zero
    }

    private struct Display { let id: CGDirectDisplayID; let bounds: CGRect }

    private static func activeDisplays() -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { Display(id: $0, bounds: CGDisplayBounds($0)) }
    }

    private static func isAgentDisplay(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == 0x0CAC && CGDisplayModelNumber(id) == 0x0CAC
    }

    private static func preferredUserDisplay(in displays: [Display]) -> Display? {
        let physical = displays.filter { !isAgentDisplay($0.id) }
        let id = AgentWindowGeometry.fallbackDisplayID(displays: Dictionary(uniqueKeysWithValues: physical.map { ($0.id, $0.bounds) }),
            main: CGMainDisplayID(), windowSize: nil)
        return physical.first { $0.id == id }
    }

    /// A newly created invisible screen must not take the user's main screen.
    /// Translate the existing arrangement for this login session only; never
    /// enable/disable physical screens or change their modes.
    private func preserveUserMainDisplay(priorMain: CGDirectDisplayID) throws {
        guard Self.isAgentDisplay(CGMainDisplayID()) else { return }
        let displays = Self.activeDisplays()
        guard let target = displays.first(where: { $0.id == priorMain && !Self.isAgentDisplay($0.id) })
                ?? Self.preferredUserDisplay(in: displays) else { return }
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else {
            destroyDisplay()
            throw ComputerUseError.stateUnavailable("agent display could not preserve the user's main display")
        }
        for display in displays {
            guard CGConfigureDisplayOrigin(configuration, display.id,
                  Int32((display.bounds.minX - target.bounds.minX).rounded()),
                  Int32((display.bounds.minY - target.bounds.minY).rounded())) == .success else {
                CGCancelDisplayConfiguration(configuration)
                destroyDisplay()
                throw ComputerUseError.stateUnavailable("agent display could not preserve the display arrangement")
            }
        }
        guard CGCompleteDisplayConfiguration(configuration, .forSession) == .success else {
            destroyDisplay()
            throw ComputerUseError.stateUnavailable("agent display could not preserve the user's main display")
        }
    }

    private func destroyDisplayIfIdle() {
        guard !retention.untilOwnerExit, parked.isEmpty, let bounds = displayBounds else { return }
        let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        guard !agentDisplayHasOccupants(windowInfo: rows, displayBounds: bounds) else { return }
        destroyDisplay()
    }

    private func destroyDisplay() {
        if let handle {
            ocu_virtual_display_destroy(handle)
        }
        handle = nil
        displayID = 0
        displaySpaceIDs = []
    }

    private func installExitHookIfNeeded() {
        guard !exitHookInstalled else { return }
        exitHookInstalled = true
        atexit {
            AgentDisplay.shared.restoreAll()
        }
    }

    // MARK: - AX helpers

    private func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func axSize(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success, let value else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func setAXPosition(_ element: AXUIElement, _ point: CGPoint) throws {
        var mutable = point
        guard let value = AXValueCreate(.cgPoint, &mutable) else {
            throw ComputerUseError.message("could not encode the window position")
        }
        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        guard result == .success else {
            throw ComputerUseError.stateUnavailable("window_placement could not move the window (AXError \(result.rawValue))")
        }
    }

    private func setAXSize(_ element: AXUIElement, _ size: CGSize) throws {
        var mutable = size
        guard let value = AXValueCreate(.cgSize, &mutable) else {
            throw ComputerUseError.message("could not encode the window size")
        }
        let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        guard result == .success else {
            throw ComputerUseError.stateUnavailable("window_placement could not resize the window (AXError \(result.rawValue))")
        }
    }
}
