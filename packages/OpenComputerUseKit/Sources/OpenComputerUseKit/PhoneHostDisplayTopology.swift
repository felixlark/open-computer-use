import CoreGraphics
import Foundation

/// Pure planning for the one newly owned phone screen. Never enables a display
/// or changes modes; an unrelated hotplug/layout edit invalidates the plan.
struct PhoneHostDisplayTopology {
    struct Screen: Equatable {
        let id: CGDirectDisplayID
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32
        let bounds: CGRect
        let mirror: CGDirectDisplayID
        let mirrored: Bool
        let mode: [Double]
    }
    struct Snapshot: Equatable {
        let main: CGDirectDisplayID
        let screens: [CGDirectDisplayID: Screen]
        static func read() throws -> Snapshot {
            let mainBefore = CGMainDisplayID()
            var count: UInt32 = 0
            guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
                throw ComputerUseError.stateUnavailable("phone display inventory unavailable")
            }
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
                throw ComputerUseError.stateUnavailable("phone display inventory changed")
            }
            var screens: [CGDirectDisplayID: Screen] = [:]
            for id in ids.prefix(Int(count)) {
                guard let mode = CGDisplayCopyDisplayMode(id) else {
                    throw ComputerUseError.stateUnavailable("phone display mode unavailable")
                }
                screens[id] = Screen(id: id, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                    serial: CGDisplaySerialNumber(id), bounds: CGDisplayBounds(id),
                    mirror: CGDisplayMirrorsDisplay(id), mirrored: CGDisplayIsInMirrorSet(id) != 0,
                    mode: [Double(mode.width), Double(mode.height), Double(mode.pixelWidth), Double(mode.pixelHeight), mode.refreshRate])
            }
            let result = Snapshot(main: CGMainDisplayID(), screens: screens)
            var verifyCount: UInt32 = 0
            guard CGGetOnlineDisplayList(0, nil, &verifyCount) == .success, verifyCount == count,
                  result.main == mainBefore, result.usable else {
                throw ComputerUseError.stateUnavailable("phone display snapshot is incomplete or unstable")
            }
            var verifyIDs = [CGDirectDisplayID](repeating: 0, count: Int(verifyCount))
            guard CGGetOnlineDisplayList(verifyCount, &verifyIDs, &verifyCount) == .success,
                  Set(verifyIDs.prefix(Int(verifyCount))) == Set(screens.keys), CGMainDisplayID() == mainBefore else {
                throw ComputerUseError.stateUnavailable("phone display inventory changed during snapshot")
            }
            return result
        }
        var usable: Bool {
            guard let mainScreen = screens[main], mainScreen.bounds.origin == .zero else { return false }
            return screens.values.allSatisfy { s in
                s.id != 0 && s.bounds.minX.isFinite && s.bounds.minY.isFinite
                    && s.bounds.width.isFinite && s.bounds.height.isFinite && s.bounds.width > 0 && s.bounds.height > 0
                    && s.mode.count == 5 && s.mode.allSatisfy(\.isFinite) && s.mode.prefix(4).allSatisfy { $0 > 0 }
                    && (s.mirror == 0 || screens[s.mirror] != nil)
            }
        }
        var diagnostic: [String: Any] {
            ["main_id": main, "screens": screens.keys.sorted().map { id -> [String: Any] in
                let s = screens[id]!
                return ["id": id, "vendor": s.vendor, "model": s.model, "serial": s.serial,
                    "bounds": [s.bounds.minX, s.bounds.minY, s.bounds.width, s.bounds.height],
                    "mirror_of": s.mirror, "mirrored": s.mirrored, "mode": s.mode]
            }]
        }
        func preserving(_ before: Snapshot, owned: CGDirectDisplayID) -> Bool {
            main == before.main && Set(screens.keys) == Set(before.screens.keys).union([owned])
                && before.screens.allSatisfy { screens[$0.key] == $0.value }
        }
    }
    struct Plan {
        let mirrors: [(CGDirectDisplayID, CGDirectDisplayID)]
        let origins: [(CGDirectDisplayID, CGPoint)]
    }
    enum Phase: String {
        case unattempted, verifying, verified, failedUnknown
        var mayBegin: Bool { self == .unattempted }
        var mayPark: Bool { self == .verified }
        mutating func validate(_ valid: Bool) -> Bool {
            guard self == .verified else { return false }
            if !valid { self = .failedUnknown }
            return self == .verified
        }
    }
    static func plan(before: Snapshot, after: Snapshot, owned: CGDirectDisplayID) throws -> Plan {
        func reject() -> ComputerUseError { .stateUnavailable("phone display topology changed outside owned screen") }
        guard before.usable, after.usable, before.screens[owned] == nil, let priorMain = before.screens[before.main],
              priorMain.bounds.origin == .zero,
              Set(after.screens.keys) == Set(before.screens.keys).union([owned]),
              let phone = after.screens[owned], phone.vendor == 0x0CAC, phone.model == 0x0CAC,
              phone.serial == 0x50484F4E, after.main == before.main || after.main == owned else { throw reject() }
        let shift = after.main == owned ? after.screens[before.main]!.bounds.origin : .zero
        var mirrors: [(CGDirectDisplayID, CGDirectDisplayID)] = []
        var origins: [(CGDirectDisplayID, CGPoint)] = []
        for id in before.screens.keys.sorted() {
            let original = before.screens[id]!, current = after.screens[id]!
            guard current.vendor == original.vendor, current.model == original.model, current.serial == original.serial else { throw reject() }
            let joinedOwnedMirror = current.mirror == owned
            if joinedOwnedMirror {
                mirrors.append((id, original.mirror))
            } else {
                let expected = original.bounds.offsetBy(dx: shift.x, dy: shift.y)
                guard current.mirror == original.mirror, current.mirrored == original.mirrored,
                      current.mode == original.mode, current.bounds == expected else { throw reject() }
            }
            // A mirrored slave inherits its master's origin. Configuring its
            // origin would detach it from the original mirror relationship.
            if original.mirror == 0 && (current.bounds.origin != original.bounds.origin || joinedOwnedMirror || after.main == owned) {
                origins.append((id, original.bounds.origin))
            }
        }
        if phone.mirrored { mirrors.insert((owned, 0), at: 0) }
        guard let right = before.screens.values.max(by: { a, b in
            a.bounds.maxX == b.bounds.maxX ? a.id < b.id : a.bounds.maxX < b.bounds.maxX
        }) else { throw reject() }
        let target = CGPoint(x: right.bounds.maxX, y: right.bounds.minY)
        // The owned origin is configured before the original main at (0,0).
        origins.removeAll { $0.0 == before.main }
        origins.append((owned, target))
        if after.main == owned || after.screens[before.main] != priorMain { origins.append((before.main, .zero)) }
        let moved = Set(origins.map { $0.0 })
        for original in before.screens.values where original.mirror != 0 && moved.contains(original.mirror) {
            if !mirrors.contains(where: { $0.0 == original.id }) { mirrors.append((original.id, original.mirror)) }
        }
        // Restore master/unmirrored states before their original slaves.
        mirrors.sort { a, b in a.1 == 0 && b.1 != 0 || (a.1 == 0) == (b.1 == 0) && a.0 < b.0 }
        for (_, point) in origins {
            guard point.x.isFinite, point.y.isFinite,
                  point.x >= Double(Int32.min), point.x <= Double(Int32.max), point.x.rounded() == point.x,
                  point.y >= Double(Int32.min), point.y <= Double(Int32.max), point.y.rounded() == point.y else { throw reject() }
        }
        return Plan(mirrors: mirrors, origins: origins)
    }
    static func apply(_ plan: Plan) throws {
        var ref: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&ref) == .success, let ref else {
            throw ComputerUseError.stateUnavailable("phone topology transaction unavailable")
        }
        // CGConfigureDisplayOrigin can remove a display from a mirror set;
        // original mirror relationships must be the final queued operations.
        for (id, point) in plan.origins {
            guard CGConfigureDisplayOrigin(ref, id, Int32(point.x), Int32(point.y)) == .success else {
                CGCancelDisplayConfiguration(ref)
                throw ComputerUseError.stateUnavailable("phone topology origin configuration failed")
            }
        }
        for (id, master) in plan.mirrors {
            guard CGConfigureDisplayMirrorOfDisplay(ref, id, master) == .success else {
                CGCancelDisplayConfiguration(ref)
                throw ComputerUseError.stateUnavailable("phone topology mirror configuration failed")
            }
        }
        guard CGCompleteDisplayConfiguration(ref, .forSession) == .success else {
            throw ComputerUseError.stateUnavailable("phone topology commit unconfirmed")
        }
    }
}
