import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct ExactAXRead<Value> {
    let value: Value?
    let status: Int32
}

enum ExactCGOwner: Equatable {
    case owned, absent, other(pid_t), unavailable
}

/// Read-only identity binding. Retries observations only; never selects a title,
/// activates a window, or converts failed AX reads into evidence of closure.
enum ExactAXWindowBinding {
    static func resolve<Element>(
        windowID: CGWindowID,
        sameProcess: () -> Bool,
        owner: () -> ExactCGOwner,
        windows: (Float) -> ExactAXRead<[Element]>,
        focused: (Float) -> ExactAXRead<Element>,
        id: (Element, Float) -> ExactAXRead<CGWindowID>,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        pause: () -> Void = { Thread.sleep(forTimeInterval: 0.05) }
    ) throws -> Element {
        let deadline = now() + 2
        var evidence: [String] = []
        var unavailable = false
        func fail(_ code: String) -> ComputerUseError {
            .stateUnavailable("Exact window_id \(windowID) binding \(code); \(evidence.joined(separator: "; ")). No other window was selected.")
        }
        func verify() throws {
            guard sameProcess() else { throw fail("process_changed") }
            switch owner() {
            case .owned: return
            case .absent: throw fail("cg_window_absent")
            case .other(let pid): throw fail("cg_owner_mismatch(\(pid))")
            case .unavailable: throw fail("cg_inventory_unavailable")
            }
        }
        func budget() -> Float { Float(max(0.001, min(0.5, deadline - now()))) }
        for attempt in 1...2 {
            try verify()
            guard now() < deadline else { break }
            let listed = windows(budget())
            evidence.append("attempt\(attempt).AXWindows=\(listed.status)/count=\(listed.value.map { String($0.count) } ?? "nil")")
            if listed.status != 0 || listed.value == nil { unavailable = true }
            let candidates = listed.value ?? []
            // Sheets may be omitted from AXWindows. The focused attribute is
            // accepted only when its AX-to-CG ID is the exact requested ID.
            func match(_ candidate: Element) throws -> Element? {
                guard now() < deadline else { return nil }
                let result = id(candidate, budget())
                if result.status != 0 || result.value == nil {
                    unavailable = true
                    if evidence.count < 16 { evidence.append("AXWindowID=\(result.status)/\(result.value.map(String.init) ?? "nil")") }
                    return nil
                }
                guard result.value == windowID else { return nil }
                try verify()
                return candidate
            }
            if listed.status == 0 {
                for candidate in candidates {
                    if let result = try match(candidate) { return result }
                }
            }
            if now() < deadline {
                let current = focused(budget())
                evidence.append("attempt\(attempt).AXFocusedWindow=\(current.status)")
                if current.status != 0 && current.status != AXError.noValue.rawValue && current.status != AXError.attributeUnsupported.rawValue { unavailable = true }
                if current.status == 0, let candidate = current.value,
                   let result = try match(candidate) { return result }
            }
            if attempt == 1, now() < deadline { pause() }
        }
        try verify()
        throw fail(now() >= deadline ? "ax_budget_exhausted(CG_owner_confirmed)" : "\(unavailable ? "ax_lookup_unavailable" : "ax_not_enumerated")(CG_owner_confirmed)")
    }

    static func resolve(app: RunningAppDescriptor, appElement: AXUIElement, windowID: CGWindowID) throws -> AXUIElement {
        guard let launch = app.runningApplication.launchDate else {
            throw ComputerUseError.stateUnavailable("Exact window_id \(windowID) process identity is unavailable")
        }
        func read<T>(_ element: AXUIElement, attribute: String, timeout: Float, cast: (CFTypeRef) -> T?) -> ExactAXRead<T> {
            let set = AXUIElementSetMessagingTimeout(element, timeout)
            guard set == .success else { return ExactAXRead(value: nil, status: set.rawValue) }
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return ExactAXRead(value: status == .success ? value.flatMap(cast) : nil, status: status.rawValue)
        }
        return try resolve(windowID: windowID, sameProcess: {
            NSRunningApplication(processIdentifier: app.pid)?.launchDate == launch
        }, owner: {
            guard let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return .unavailable }
            guard let row = rows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }) else { return .absent }
            guard let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return .unavailable }
            return pid == app.pid ? .owned : .other(pid)
        }, windows: { timeout in
            read(appElement, attribute: kAXWindowsAttribute as String, timeout: timeout) { $0 as? [AXUIElement] }
        }, focused: { timeout in
            read(appElement, attribute: kAXFocusedWindowAttribute as String, timeout: timeout) {
                CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
            }
        }, id: { element, timeout in
            let set = AXUIElementSetMessagingTimeout(element, timeout)
            guard set == .success else { return ExactAXRead(value: nil, status: set.rawValue) }
            var pid: pid_t = 0
            let result = AXUIElementGetPid(element, &pid)
            guard result == .success, pid == app.pid else {
                return ExactAXRead(value: nil, status: result == .success ? AXError.invalidUIElement.rawValue : result.rawValue)
            }
            return SkyLightSPI.shared.windowIDRead(for: element)
        })
    }
}
