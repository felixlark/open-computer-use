import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

/// These tests use only in-memory geometry and callbacks, never AX/GUI tools.
final class AgentWindowGeometryTests: XCTestCase {
    let original = CGRect(x: -2000, y: 70, width: 2304, height: 1266)
    let screen = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    func testOversizedFrameFitsCompletelyAndKeepsNonOversizedDimensions() {
        let fitted = AgentWindowGeometry.fittedFrame(original: original, display: screen)
        XCTAssertTrue(screen.contains(fitted))
        XCTAssertEqual(fitted.size, CGSize(width: 1840, height: 1000))
        let wide = AgentWindowGeometry.fittedFrame(original: CGRect(x: 0, y: 0, width: 2304, height: 600), display: screen)
        XCTAssertEqual(wide.height, 600)
        XCTAssertTrue(screen.contains(wide))
        let ordinary = CGRect(x: 0, y: 0, width: 900, height: 700)
        XCTAssertEqual(AgentWindowGeometry.fittedFrame(original: ordinary, display: screen).size, ordinary.size)
    }

    func testPartlyOffscreenOriginStillBelongsToItsCenterDisplay() {
        let physical = CGRect(x: 0, y: 0, width: 1920, height: 1200)
        let partial = CGRect(x: -100, y: -80, width: 2048, height: 1122)
        XCTAssertTrue(AgentWindowGeometry.displayContainsCenter(physical, frame: partial))
        XCTAssertFalse(physical.contains(CGPoint(x: partial.minX + 20, y: partial.minY + 20)))
        XCTAssertEqual(AgentWindowGeometry.restoredFrame(original: partial, originalDisplay: physical, targetDisplay: physical), partial)
    }

    func testUnchangedOriginalDisplayRestoresExactFrameEvenIfPartlyOutside() {
        let physical = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(AgentWindowGeometry.restoredFrame(original: original, originalDisplay: physical, targetDisplay: physical), original)
    }

    func testScreenSizedAndNearScreenSizedWindowsFitBelowMenuBarConstraints() {
        for height in [1080, 1060, 1001] as [CGFloat] {
            let fitted = AgentWindowGeometry.fittedFrame(original: CGRect(x: 0, y: 0, width: 1920, height: height), display: screen)
            XCTAssertEqual(fitted, CGRect(x: screen.minX + 40, y: 40, width: 1840, height: 1000))
            XCTAssertTrue(screen.contains(fitted))
        }
        let offsetScreen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let fitted = AgentWindowGeometry.fittedFrame(original: original, display: offsetScreen)
        XCTAssertEqual(fitted.origin, CGPoint(x: -1880, y: -160))
        XCTAssertTrue(offsetScreen.contains(fitted))
    }

    func testChangedDisplayRebasesPositionWhilePreservingOriginalSize() {
        let physical = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let moved = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let restored = AgentWindowGeometry.restoredFrame(original: original, originalDisplay: physical, targetDisplay: moved)
        XCTAssertEqual(restored.origin, CGPoint(x: 216, y: 70))
        XCTAssertEqual(restored.size, original.size)
        XCTAssertEqual(AgentWindowGeometry.restoredFrame(original: original, originalDisplay: nil, targetDisplay: nil), original)
    }

    func testFallbackPrefersARealScreenThatCanKeepOriginalSize() {
        let screens: [UInt32: CGRect] = [1: CGRect(x: 0, y: 0, width: 1512, height: 908),
            2: CGRect(x: -392, y: -1296, width: 2304, height: 1296),
            3: CGRect(x: 1912, y: -1152, width: 2048, height: 1152)]
        XCTAssertEqual(AgentWindowGeometry.fallbackDisplayID(displays: screens, main: 1, windowSize: CGSize(width: 1920, height: 1050)), 2)
        XCTAssertEqual(AgentWindowGeometry.fallbackDisplayID(displays: screens, main: 1, windowSize: CGSize(width: 2048, height: 1122)), 2)
        XCTAssertEqual(AgentWindowGeometry.fallbackDisplayID(displays: screens, main: 1, windowSize: CGSize(width: 900, height: 700)), 1)
        XCTAssertEqual(AgentWindowGeometry.fallbackDisplayID(displays: screens, main: 1, windowSize: nil), 1)
        XCTAssertEqual(AgentWindowGeometry.fallbackDisplayID(displays: screens, main: 1, windowSize: CGSize(width: 4000, height: 3000)), 2)
        XCTAssertNil(AgentWindowGeometry.fallbackDisplayID(displays: [:], main: 1, windowSize: CGSize(width: 1920, height: 1050)))
    }

    func testRestoreKeepsUnchangedOriginalScreenButFallsBackAfterItShrinks() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 600)
        let original = CGRect(x: 0, y: 0, width: 2048, height: 1152)
        let large = CGRect(x: -2304, y: 0, width: 2304, height: 1296)
        let size = CGSize(width: 2048, height: 1122)
        XCTAssertEqual(AgentWindowGeometry.restorationDisplayID(displays: [1: original, 2: large], main: 1, originalID: 1, originalBounds: original, windowSize: size), 1)
        XCTAssertEqual(AgentWindowGeometry.restorationDisplayID(displays: [1: small, 2: large], main: 1, originalID: 1, originalBounds: original, windowSize: size), 2)
        XCTAssertEqual(AgentWindowGeometry.restorationDisplayID(displays: [2: large], main: 1, originalID: 1, originalBounds: original, windowSize: size), 2)
        XCTAssertEqual(AgentWindowGeometry.restorationDisplayID(displays: [2: large], main: 2, originalID: 99, originalBounds: small, windowSize: size), 2)
    }

    func testFallbackFromHiddenTopClearsPhysicalMenuBarWithoutShrinking() {
        let hidden = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let physical = CGRect(x: -392, y: -1296, width: 2304, height: 1296)
        for y in [0, 30] as [CGFloat] {
            let original = CGRect(x: 1512, y: y, width: 1920, height: 1050)
            let target = AgentWindowGeometry.restoredFrame(original: original, originalDisplay: hidden, targetDisplay: physical)
            XCTAssertEqual(target, CGRect(x: -352, y: -1256, width: 1920, height: 1050))
        }
    }

    func testParkThenRestoreUsesFullOriginalFrameAndCorrectWriteOrder() throws {
        let fake = FakeWindow(original)
        let fitted = AgentWindowGeometry.fittedFrame(original: original, display: screen)
        try fake.writer.apply(fitted, restoring: false)
        XCTAssertEqual(fake.operations, ["size", "position"])
        XCTAssertEqual(fake.frame, fitted)
        fake.operations = []
        try fake.writer.apply(original, restoring: true)
        XCTAssertEqual(fake.operations, ["position", "size"])
        XCTAssertEqual(fake.frame, original)
    }

    func testErrorAfterDeliveryIsReadBackWithoutDuplicateWrite() throws {
        let fake = FakeWindow(original)
        fake.throwAfterDelivery = true
        let fitted = AgentWindowGeometry.fittedFrame(original: original, display: screen)
        try fake.writer.apply(fitted, restoring: false)
        XCTAssertEqual(fake.frame, fitted)
        XCTAssertEqual(fake.operations, ["size", "position"])
    }

    func testSizeDeliveredButPositionNotDeliveredStopsAndCanExplicitlyRestore() throws {
        let fake = FakeWindow(original)
        fake.failPosition = true
        let fitted = AgentWindowGeometry.fittedFrame(original: original, display: screen)
        XCTAssertThrowsError(try fake.writer.apply(fitted, restoring: false))
        XCTAssertEqual(fake.operations, ["size", "position"])
        XCTAssertEqual(fake.frame.origin, original.origin)
        XCTAssertEqual(fake.frame.size, fitted.size)
        fake.failPosition = false
        fake.operations = []
        try fake.writer.apply(original, restoring: true)
        XCTAssertEqual(fake.frame, original)
        XCTAssertEqual(fake.operations, ["size"])
    }

    func testRestorePositionDeliveredButSizeClampedDoesNotReportComplete() throws {
        let fitted = AgentWindowGeometry.fittedFrame(original: original, display: screen)
        let fake = FakeWindow(fitted)
        fake.clampSize = true
        XCTAssertThrowsError(try fake.writer.apply(original, restoring: true))
        XCTAssertEqual(fake.operations, ["position", "size"])
        XCTAssertEqual(fake.frame.origin, original.origin)
        XCTAssertFalse(AgentWindowGeometry.sameFrame(fake.frame, original))
        // An explicit later restore uses the retained original target and the
        // observed partial state; it does not repeat the already-applied move.
        fake.clampSize = false
        fake.operations = []
        try fake.writer.apply(original, restoring: true)
        XCTAssertEqual(fake.operations, ["size"])
        XCTAssertEqual(fake.frame, original)
    }

    func testUnavailableOrReplacedIdentityStopsBeforeNextWrite() {
        let fake = FakeWindow(original)
        fake.readable = false
        XCTAssertThrowsError(try fake.writer.apply(CGRect(x: 0, y: 0, width: 600, height: 400), restoring: false))
        XCTAssertTrue(fake.operations.isEmpty)
        fake.readable = true
        fake.loseIdentityAfterSize = true
        XCTAssertThrowsError(try fake.writer.apply(CGRect(x: 0, y: 0, width: 600, height: 400), restoring: false))
        XCTAssertEqual(fake.operations, ["size"])
    }

    func testRestoreCorrectsObservedPositionAdjustmentAfterExpanding() throws {
        let fake = FakeWindow(CGRect(x: 1512, y: 40, width: 900, height: 700))
        fake.adjustPositionAfterSize = true
        try fake.writer.apply(original, restoring: true)
        XCTAssertEqual(fake.operations, ["position", "size", "position"])
        XCTAssertEqual(fake.frame, original)
    }

    func testSuccessWithoutDeliveryIsNotRetriedOrReportedComplete() {
        let fake = FakeWindow(original)
        fake.ignoreSize = true
        XCTAssertThrowsError(try fake.writer.apply(CGRect(x: 1512, y: 40, width: 900, height: 700), restoring: false))
        XCTAssertEqual(fake.operations, ["size"])
        XCTAssertEqual(fake.frame, original)
    }

    func testAutomaticResizeDuringMoveFailsFinalFullFrameConfirmation() {
        let fake = FakeWindow(original)
        fake.adjustSizeAfterPosition = true
        XCTAssertThrowsError(try fake.writer.apply(CGRect(x: 1512, y: 40, width: 900, height: 700), restoring: false))
        XCTAssertEqual(fake.operations, ["size", "position"])
    }

    func testInvalidTargetDoesNotWrite() {
        let fake = FakeWindow(original)
        XCTAssertThrowsError(try fake.writer.apply(CGRect(x: 0, y: 0, width: CGFloat.nan, height: 100), restoring: false))
        XCTAssertTrue(fake.operations.isEmpty)
    }

    private final class FakeWindow {
        enum Failure: Error { case uncertain }
        var frame: CGRect
        var operations: [String] = []
        var readable = true
        var throwAfterDelivery = false
        var failPosition = false
        var clampSize = false
        var ignoreSize = false
        var loseIdentityAfterSize = false
        var adjustPositionAfterSize = false
        var adjustSizeAfterPosition = false
        init(_ frame: CGRect) { self.frame = frame }
        var writer: AgentWindowGeometryWriter {
            AgentWindowGeometryWriter(readFrame: { self.readable ? self.frame : nil }, setPosition: {
                self.operations.append("position")
                if self.failPosition { throw Failure.uncertain }
                self.frame.origin = $0
                if self.adjustSizeAfterPosition { self.frame.size.height -= 20 }
                if self.throwAfterDelivery { throw Failure.uncertain }
            }, setSize: {
                self.operations.append("size")
                if !self.ignoreSize { self.frame.size = $0 }
                if self.clampSize { self.frame.size.height -= 20 }
                if self.adjustPositionAfterSize { self.frame.origin.x += 50 }
                if self.loseIdentityAfterSize { self.readable = false }
                if self.throwAfterDelivery { throw Failure.uncertain }
            }, settle: { $0() })
        }
    }
}
