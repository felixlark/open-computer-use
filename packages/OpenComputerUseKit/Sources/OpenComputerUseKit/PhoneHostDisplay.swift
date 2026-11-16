import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Security
import OpenComputerUseVirtualDisplayShim

/// Only the explicitly bound phone window may enter this separate display.
/// No generic placement or automatic physical-screen restoration is enabled.
public final class PhoneHostDisplay: @unchecked Sendable {
    public static let shared = PhoneHostDisplay()
    private let lock = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private var displayID: CGDirectDisplayID = 0
    private var binding: PhoneHostDisplayBinding?
    private var claimURL: URL?
    private var admission: PhoneHostDisplayBinding?
    private var recoveredClaim = false
    private var recoveryUnknown = false
    private var terminating = false
    private let serial: UInt32 = 0x50484F4E
    private var settleSeconds: Double = 0
    private var lastFailure: String?
    private var topologyPhase: PhoneHostDisplayTopology.Phase = .unattempted
    private var priorTopology: PhoneHostDisplayTopology.Snapshot?
    private var lastTopology: [String: Any]?

    private func recordTopology() {
        lastTopology = ["owned_id": displayID, "main_id": CGMainDisplayID(),
            "online": displayID != 0 && CGDisplayIsOnline(displayID) != 0,
            "active": displayID != 0 && CGDisplayIsActive(displayID) != 0,
            "mirror_of": displayID == 0 ? 0 : CGDisplayMirrorsDisplay(displayID),
            "mirrored": displayID != 0 && CGDisplayIsInMirrorSet(displayID) != 0]
    }
    private func currentTopologyReady() -> Bool {
        guard topologyPhase.mayPark else { return false }
        let area = bounds()
        let originalPreserved = priorTopology.flatMap { before in
            (try? PhoneHostDisplayTopology.Snapshot.read()).map { $0.preserving(before, owned: displayID) }
        } ?? false
        let valid = area.map { PhoneHostDisplayPolicy.fitsPhone(width: $0.width, height: $0.height) } ?? false
        let ready = topologyPhase.validate(valid && originalPreserved && CGDisplayIsActive(displayID) != 0
            && CGMainDisplayID() != displayID && CGDisplayIsInMirrorSet(displayID) == 0)
        if !ready {
            lastFailure = "phone or original display topology changed after verification"
            recordTopology()
        }
        return ready
    }

    private func configure() throws {
        let env = OCUConfiguration.environment
        let namespace = getenv(openComputerUseAppAgentSocketNamespaceEnvironmentKey).map { String(cString: $0) } ?? ""
        let url = try OCUConfiguration.fileURL(environment: env)
        guard url.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SmartShadow/phone-host-ocu/config.json") else { throw ComputerUseError.message("phone host requires its fixed runtime configuration") }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o022 == 0,
              let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              PhoneHostDisplayPolicy.enabled(document: document, namespace: namespace) else {
            throw ComputerUseError.message("phone host display requires dedicated namespace and phoneHostDisplay.enabled=true")
        }
        guard let raw = document["phoneHostDisplay"] as? [String: Any],
              let data = raw["admission"] as? [String: Any] else { throw ComputerUseError.stateUnavailable("phone window admission required") }
        guard let timeout = raw["requestTimeoutSeconds"] as? NSNumber,
              CFGetTypeID(timeout) != CFBooleanGetTypeID(), timeout.doubleValue.isFinite, timeout.doubleValue > 0 else {
            throw ComputerUseError.stateUnavailable("phone topology deadline is not configured")
        }
        settleSeconds = timeout.doubleValue
        var args = data; args["action"] = "park"
        admission = try PhoneHostDisplayPolicy.validate(args).1
        let journal = url.deletingLastPathComponent().appendingPathComponent("phone-host-claim.json")
        if claimURL == nil {
            var restored: PhoneHostDisplayBinding?
            if FileManager.default.fileExists(atPath: journal.path) {
                restored = try JSONDecoder().decode(PhoneHostDisplayBinding.self, from: Data(contentsOf: journal))
            }
            binding = restored; recoveredClaim = restored != nil
            claimURL = journal
        }
        guard claimURL == journal else { throw ComputerUseError.stateUnavailable("phone host configuration changed") }
    }
    private func save() throws {
        guard let claimURL else { throw ComputerUseError.stateUnavailable("phone host journal unavailable") }
        if let binding { try JSONEncoder().encode(binding).write(to: claimURL, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claimURL.path) }
        else if FileManager.default.fileExists(atPath: claimURL.path) { try FileManager.default.removeItem(at: claimURL) }
    }
    private func host(_ b: PhoneHostDisplayBinding) throws -> RunningAppDescriptor {
        let app = try AppDiscovery.resolveRunning(String(b.pid))
        guard app.bundleIdentifier == "com.openai.codex",
              let started = app.runningApplication.launchDate?.timeIntervalSince1970,
              abs(started - b.processStartTime) < 0.0001 else {
            throw ComputerUseError.stateUnavailable("phone host process identity changed")
        }
        var guest: SecCode?; var requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: b.pid] as CFDictionary, [], &guest) == errSecSuccess,
              let guest,
              SecRequirementCreateWithString("anchor apple generic and identifier \"com.openai.codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\"" as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(guest, [], requirement) == errSecSuccess else {
            throw ComputerUseError.stateUnavailable("phone host vendor signature changed")
        }
        return app
    }
    private func windowFrame(_ b: PhoneHostDisplayBinding) -> CGRect? {
        guard let id = b.windowID, let rows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
              let row = rows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == b.pid }),
              let dict = row[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }
    private func claimedWindowGone(_ b: PhoneHostDisplayBinding) -> Bool {
        guard let id = b.windowID else { return true }
        let app = NSRunningApplication(processIdentifier: b.pid)
        if PhoneHostDisplayPolicy.processGone(exists: app != nil, observedStart: app?.launchDate?.timeIntervalSince1970, expectedStart: b.processStartTime) { return true }
        guard app?.launchDate != nil else { return false }
        guard let rows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return false }
        return !rows.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == b.pid }
    }
    public func prepareDedicatedOwner() {
        lock.lock(); defer { lock.unlock() }
        let journal = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SmartShadow/phone-host-ocu/phone-host-claim.json")
        if FileManager.default.fileExists(atPath: journal.path) {
            do { binding = try JSONDecoder().decode(PhoneHostDisplayBinding.self, from: Data(contentsOf: journal)); recoveredClaim = true }
            catch { recoveryUnknown = true }
        }
    }
    public func prepareNormalTermination() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !recoveryUnknown, binding.map(claimedWindowGone) ?? true else { return false }
        terminating = true
        return true
    }
    func retainedWindows() -> Set<CGWindowID> {
        lock.lock(); defer { lock.unlock() }
        guard let binding, !claimedWindowGone(binding), let id = binding.windowID else { return [] }
        return [id]
    }
    private func bounds() -> CGRect? {
        guard handle != nil, displayID != 0, CGDisplayIsOnline(displayID) != 0,
              CGDisplayVendorNumber(displayID) == 0x0CAC, CGDisplaySerialNumber(displayID) == serial else { return nil }
        let result = CGDisplayBounds(displayID)
        return AgentWindowGeometry.valid(result) ? result : nil
    }
    private func ensure() throws {
        if topologyPhase.mayPark {
            guard currentTopologyReady() else { throw ComputerUseError.stateUnavailable("verified phone topology was lost") }
            return
        }
        guard topologyPhase.mayBegin, handle == nil else {
            throw ComputerUseError.stateUnavailable("phone topology attempt ended; close exact phone window before explicit provider recovery")
        }
        topologyPhase = .verifying
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + settleSeconds
            let before = try PhoneHostDisplayTopology.Snapshot.read()
            priorTopology = before
            var next: UnsafeMutableRawPointer?
            let id = ocu_virtual_display_create_with_serial("SmartShadow Phone Host", 1920, 1440, 60, serial, &next)
            guard id != 0, let next else {
                throw ComputerUseError.stateUnavailable("phone display creation failed: " + String(cString: ocu_virtual_display_creation_diagnostic()))
            }
            handle = next; displayID = id
            var configured = false
            repeat {
                recordTopology()
                if CGDisplayIsOnline(id) != 0,
                   CGDisplayVendorNumber(id) == 0x0CAC, CGDisplaySerialNumber(id) == serial {
                    let current = try PhoneHostDisplayTopology.Snapshot.read()
                    if !configured {
                        let plan = try PhoneHostDisplayTopology.plan(before: before, after: current, owned: id)
                        configured = true // A failed/unknown transaction is never retried.
                        try PhoneHostDisplayTopology.apply(plan)
                    } else if current.preserving(before, owned: id), let area = bounds(),
                              CGDisplayIsActive(id) != 0, CGMainDisplayID() != id,
                              CGDisplayIsInMirrorSet(id) == 0,
                              PhoneHostDisplayPolicy.fitsPhone(width: area.width, height: area.height) {
                        topologyPhase = .verified; lastFailure = nil
                        recordTopology()
                        return
                    }
                }
                Thread.sleep(forTimeInterval: 0.025)
            } while ProcessInfo.processInfo.systemUptime < deadline
            throw ComputerUseError.stateUnavailable("phone display topology unconfirmed")
        } catch {
            topologyPhase = .failedUnknown
            lastFailure = String(describing: error)
            recordTopology()
            // Retain the owned handle and claim. Only normal provider termination,
            // after exact phone-window absence, may release this uncertain screen.
            throw error
        }
    }
    public func call(_ raw: [String: Any]) throws -> ToolCallResult {
        let (action, request) = try PhoneHostDisplayPolicy.validate(raw)
        lock.lock(); defer { lock.unlock() }
        guard !terminating || action == "status" else { throw ComputerUseError.stateUnavailable("phone provider is terminating") }
        guard !recoveryUnknown else { throw ComputerUseError.stateUnavailable("phone claim journal corrupt; preserve it for explicit reconciliation") }
        try configure()
        guard let admission, PhoneHostDisplayPolicy.admitted(request, by: admission) else {
            throw ComputerUseError.stateUnavailable("phone window is not admitted by the runtime controller")
        }
        if let current = binding, !PhoneHostDisplayPolicy.sameHost(current, request) {
            guard claimedWindowGone(current) else { throw ComputerUseError.stateUnavailable("another phone window is still claimed") }
            guard action == "ensure" else { throw ComputerUseError.stateUnavailable("phone host binding mismatch") }
            binding = nil; recoveredClaim = false; try save()
        }
        if action == "release" {
            let current = binding ?? admission
            guard PhoneHostDisplayPolicy.sameHost(current, request), current.windowID == request.windowID,
                  claimedWindowGone(current) else { throw ComputerUseError.stateUnavailable("close the exact phone window before releasing its claim") }
            binding = nil; recoveredClaim = false; try save()
        } else if action != "status" {
            let app = try host(request)
            if action == "ensure" {
                if recoveredClaim, let current = binding, !claimedWindowGone(current) { throw ComputerUseError.stateUnavailable("provider restarted with prior live phone window; close/release before ensure") }
                recoveredClaim = false
                if binding == nil { binding = admission; try save() }
                try ensure()
            } else {
                guard let current = binding, PhoneHostDisplayPolicy.sameHost(current, request) else {
                    throw ComputerUseError.stateUnavailable("phone host was not ensured")
                }
                if action == "park" {
                    // Also validate when an AX write or frame read throws/returns
                    // unknown; short-circuit guards must not bypass the latch.
                    defer { _ = currentTopologyReady() }
                    let topologyConfirmed = currentTopologyReady()
                    guard current.windowID == nil || current.windowID == request.windowID,
                          let id = request.windowID, let area = bounds(), topologyConfirmed else { throw ComputerUseError.stateUnavailable("phone display or window binding changed") }
                    let context = try SnapshotBuilder.resolveTargetWindow(for: app, windowID: id)
                    guard let original = context.windowBounds else { throw ComputerUseError.stateUnavailable("phone window bounds unavailable") }
                    var claim = current; claim.windowID = id
                    binding = claim; try save() // Preserve identity before uncertain AX writes.
                    let target = CGRect(x: area.minX + 40, y: area.minY + 40, width: 480, height: 600)
                    func read() -> CGRect? {
                        guard (try? host(claim)) != nil, SkyLightSPI.shared.windowID(for: context.windowElement) == id else { return nil }
                        return windowFrame(claim)
                    }
                    func set(_ attribute: String, _ value: CFTypeRef?) throws {
                        guard let value, AXUIElementSetAttributeValue(context.windowElement, attribute as CFString, value) == .success else { throw ComputerUseError.stateUnavailable("phone window move unconfirmed") }
                    }
                    let writer = AgentWindowGeometryWriter(readFrame: read,
                        setPosition: { p in var p = p; try set(kAXPositionAttribute as String, AXValueCreate(.cgPoint, &p)) },
                        setSize: { s in var s = s; try set(kAXSizeAttribute as String, AXValueCreate(.cgSize, &s)) },
                        settle: { predicate in let end = Date().addingTimeInterval(2); repeat { if predicate() { return true }; Thread.sleep(forTimeInterval: 0.025) } while Date() < end; return false })
                    try writer.apply(target, restoring: false)
                    let topologyAfterWrite = currentTopologyReady()
                    guard let frame = windowFrame(claim), let observed = bounds(), topologyAfterWrite, observed.contains(frame) else { throw ComputerUseError.stateUnavailable("phone window residency unconfirmed") }
                    guard WindowOcclusionKeepAlive.shared.keepVisible(windowID: id, bounds: frame) else {
                        throw ComputerUseError.stateUnavailable("phone window render keep-alive unconfirmed")
                    }
                }
            }
        }
        let area = bounds(), frame = binding.flatMap(windowFrame)
        let hostCurrent = (try? host(request)) != nil
        let topologyConfirmed = currentTopologyReady()
        let contained = hostCurrent && area != nil && topologyConfirmed && frame != nil && area!.contains(frame!)
        let renderPinned = binding?.windowID.map { WindowOcclusionKeepAlive.shared.isPinned(windowID: $0) } ?? false
        let ready = PhoneHostDisplayPolicy.ready(contained: contained, renderPinned: renderPinned)
        func geometry(_ r: CGRect?) -> Any { guard let r else { return NSNull() }; return ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
        let value: [String: Any] = ["schema": "ocu.phone-host-display/v1", "action": action, "scope": "phone_host", "instance_id": request.instanceID,
            "pid": request.pid, "process_start_time": request.processStartTime, "window_id": (binding?.windowID ?? admission.windowID).map { $0 as Any } ?? NSNull(),
            "claim_present": binding != nil, "released": binding == nil && claimedWindowGone(admission),
            "provider_pid": getpid(), "namespace": PhoneHostDisplayPolicy.namespace, "display_id": area == nil ? 0 : displayID, "display_serial": serial,
            "bounds": geometry(area), "window_bounds": geometry(frame), "contained": contained, "render_pinned": renderPinned, "ready": ready, "persistent": true]
        var observed = value
        observed["allocated_display_id"] = displayID
        observed["display_online"] = displayID != 0 && CGDisplayIsOnline(displayID) != 0
        observed["display_active"] = displayID != 0 && CGDisplayIsActive(displayID) != 0
        observed["main_display_id"] = CGMainDisplayID()
        observed["display_mirrored"] = displayID != 0 && CGDisplayIsInMirrorSet(displayID) != 0
        observed["observed_vendor"] = displayID == 0 ? 0 : CGDisplayVendorNumber(displayID)
        observed["observed_serial"] = displayID == 0 ? 0 : CGDisplaySerialNumber(displayID)
        observed["prior_topology"] = priorTopology?.diagnostic as Any? ?? NSNull()
        observed["current_topology"] = (try? PhoneHostDisplayTopology.Snapshot.read())?.diagnostic as Any? ?? NSNull()
        observed["topology_phase"] = topologyPhase.rawValue
        observed["last_topology"] = lastTopology as Any? ?? NSNull()
        observed["last_failure"] = lastFailure as Any? ?? NSNull()
        observed["virtual_display_supported"] = ocu_virtual_display_is_supported() != 0
        observed["terminating"] = terminating
        return .text(String(decoding: try JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys]), as: UTF8.self))
    }
    static let definition = ToolDefinition(name: "phone_host_display", description: "Manage only the explicitly bound SmartShadow phone host display. Requires dedicated provider configuration. No physical fallback.",
        annotations: ["readOnlyHint": false, "idempotentHint": true, "destructiveHint": false, "openWorldHint": false],
        inputSchema: ["type": "object", "properties": ["action": ["type": "string", "enum": ["ensure", "status", "park", "release"]], "instance_id": ["type": "string"], "pid": ["type": "integer"], "process_start_time": ["type": "number"], "window_id": ["type": "integer"]], "required": ["action", "instance_id", "pid", "process_start_time"], "additionalProperties": false])
}
