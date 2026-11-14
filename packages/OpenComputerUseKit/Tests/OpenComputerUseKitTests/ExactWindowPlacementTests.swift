import AppKit
import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class ExactWindowPlacementTests: XCTestCase {
    func testExactPlacementSchemaAndScopedReleasePreconditions() throws {
        let tool = try XCTUnwrap(ToolDefinitions.configured(virtualDisplayEnabled: true).first { $0.name == "get_app_state" })
        let properties = try XCTUnwrap(tool.inputSchema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["window_id"])
        XCTAssertEqual((properties["window_placement"] as? [String: Any])?["enum"] as? [String], ["keep", "agent_display", "restore", "release"])
        for mode in WindowPlacement.allCases { XCTAssertNoThrow(try validateExactWindowPlacement(mode, windowID: 42)) }
        XCTAssertThrowsError(try validateExactWindowPlacement(.release, windowID: nil))
        XCTAssertThrowsError(try validateExactWindowPlacement(.restore, windowID: 0))
        let dispatcher = ComputerUseToolDispatcher()
        for bad in [0, -1, 1.5, true, "42", 4_294_967_296] as [Any] {
            XCTAssertThrowsError(try dispatcher.callTool(name: "get_app_state", arguments: ["app": "not-running-test-app", "window_id": bad]))
        }
        XCTAssertThrowsError(try dispatcher.callTool(name: "get_app_state", arguments: ["app": "not-running-test-app", "window_placement": "release"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit window_id"))
        }
    }

    func testExplicitPIDResolutionNeverChoosesAnotherProcessOrLaunches() throws {
        let a = RunningAppDescriptor(name: "Twin", bundleIdentifier: "local.test.twin", pid: 123,
                                     runningApplication: NSRunningApplication.current)
        let b = RunningAppDescriptor(name: "Twin", bundleIdentifier: "local.test.twin", pid: 456,
                                     runningApplication: NSRunningApplication.current)
        XCTAssertEqual(try AppDiscovery.resolveRunning("456", applications: [a, b]).pid, 456)
        XCTAssertThrowsError(try AppDiscovery.resolveRunning("789", applications: [a, b]))
        XCTAssertThrowsError(try AppDiscovery.resolveRunning("0", applications: [a, b]))
        let blocked = RunningAppDescriptor(name: "Vault", bundleIdentifier: "com.1password.1password", pid: 789,
                                           runningApplication: NSRunningApplication.current)
        XCTAssertThrowsError(try AppDiscovery.resolveRunning("789", applications: [blocked])) { error in
            XCTAssertTrue(error.localizedDescription.contains("not allowed"))
        }
    }

    func testPersistentWorkspaceSurvivesEmptyRecordsAndLaterTransientClients() {
        var retention = AgentDisplayRetention()
        XCTAssertFalse(retention.untilOwnerExit)
        retention.recordPark(restoreOnSessionEnd: true)
        XCTAssertFalse(retention.untilOwnerExit)
        retention.recordPark(restoreOnSessionEnd: false)
        XCTAssertTrue(retention.untilOwnerExit)
        // Disconnect prunes closed window records and restores request env.
        // A later client's transient preference cannot delete that workspace.
        retention.recordPark(restoreOnSessionEnd: true)
        XCTAssertTrue(retention.untilOwnerExit)
    }

    func testReleasedAndUnknownDisplayOccupancyKeepsScreenAlive() {
        let screen = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(agentDisplayHasOccupants(windowFrames: nil, displayBounds: screen))
        XCTAssertTrue(agentDisplayHasOccupants(windowFrames: [CGRect(x: 1600, y: 40, width: 200, height: 100)], displayBounds: screen))
        XCTAssertFalse(agentDisplayHasOccupants(windowFrames: [], displayBounds: screen))
        let floating: [String: Any] = [kCGWindowLayer as String: 3,
            kCGWindowBounds as String: CGRect(x: 1600, y: 40, width: 200, height: 100).dictionaryRepresentation]
        XCTAssertTrue(agentDisplayHasOccupants(windowInfo: [floating], displayBounds: screen))
        XCTAssertTrue(agentDisplayHasOccupants(windowInfo: [[kCGWindowLayer as String: 3]], displayBounds: screen))
        XCTAssertFalse(agentDisplayHasOccupants(windowFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)], displayBounds: screen))
    }

    func testExplicitPinReleaseIsScopedAndHasNoLateWriteAfterFailure() {
        let pins = WindowOcclusionKeepAlive(), spi = FakeSPI()
        let frame = CGRect(x: -20000, y: -20000, width: 10, height: 10)
        XCTAssertTrue(pins.keepVisible(windowID: 1001, bounds: frame, identity: WindowOcclusionIdentity(validate: { true }), spi: spi))
        XCTAssertTrue(pins.keepVisible(windowID: 1002, bounds: frame, identity: WindowOcclusionIdentity(validate: { true }), spi: spi))
        spi.fail = true
        XCTAssertFalse(pins.release(windowID: 1001, spi: spi))
        XCTAssertFalse(pins.isPinned(windowID: 1001))
        XCTAssertTrue(pins.isPinned(windowID: 1002))
        let calls = spi.calls
        spi.fail = false
        pins.releaseAll(excluding: [1002], spi: spi)
        XCTAssertEqual(spi.calls, calls, "release failure must not leave a delayed reset onto a user-owned window")
        XCTAssertTrue(pins.release(windowID: 1002, spi: spi))
    }

    func testClosedReplacedOrUnknownPinIdentityNeverWritesReplacement() {
        let pins = WindowOcclusionKeepAlive(), spi = FakeSPI()
        let frame = CGRect(x: -20000, y: -20000, width: 10, height: 10)
        var live: Bool? = true
        XCTAssertTrue(pins.keepVisible(windowID: 1003, bounds: frame, identity: WindowOcclusionIdentity(validate: { live }), spi: spi))
        let count = spi.calls
        live = nil
        pins.releaseAll(spi: spi)
        XCTAssertEqual(spi.calls, count)
        live = false
        pins.releaseAll(spi: spi)
        XCTAssertEqual(spi.calls, count)
        XCTAssertFalse(pins.isPinned(windowID: 1003))
    }

    private final class FakeSPI: WindowOcclusionControlling {
        let occlusionCapability = SkyLightSPICapability(missingSymbols: [], feature: "occlusion")
        var calls = 0
        var fail = false
        func setWindowOcclusionNotificationsEnabled(_ enabled: Bool, windowID: CGWindowID) throws -> Bool {
            calls += 1
            if fail { throw NSError(domain: "FakeSPI", code: 1) }
            return !enabled
        }
    }
}
