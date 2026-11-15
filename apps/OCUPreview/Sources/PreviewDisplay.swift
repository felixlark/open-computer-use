import CoreGraphics
import Foundation

/// Serial identity survives reconnects; a WindowServer display ID does not.
struct PreviewDisplay: Equatable, Sendable {
    let id: CGDirectDisplayID
    let serial: UInt32

    static func accepts(vendor: UInt32, model: UInt32, serial: UInt32,
                        isMain: Bool, isMirrored: Bool) -> Bool {
        vendor == 0x0CAC && model == 0x0CAC && serial != 0 && !isMain && !isMirrored
    }

    static func discover() -> [PreviewDisplay] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).compactMap { id in
            let serial = CGDisplaySerialNumber(id)
            guard accepts(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                          serial: serial, isMain: CGDisplayIsMain(id) != 0,
                          isMirrored: CGDisplayIsInMirrorSet(id) != 0) else { return nil }
            return PreviewDisplay(id: id, serial: serial)
        }.sorted { $0.serial < $1.serial }
    }

    /// Once selected, wait for that identity instead of switching to another screen.
    static func selected(in displays: [PreviewDisplay], serial: UInt32?) -> PreviewDisplay? {
        guard let serial else { return displays.first }
        return displays.first { $0.serial == serial }
    }
}

/// Single-slot handoff: never enqueue an unbounded backlog of full-screen images.
final class PreviewLatestFrame: @unchecked Sendable {
    private let lock = NSLock()
    private var image: CGImage?
    func put(_ image: CGImage) { lock.lock(); self.image = image; lock.unlock() }
    func take() -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        let frame = image; image = nil; return frame
    }
    func clear() { lock.lock(); image = nil; lock.unlock() }
}
