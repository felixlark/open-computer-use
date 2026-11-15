import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class RightDisplayPlacementTests: XCTestCase {
    func testRightmostUsesCurrentPhysicalGeometry() {
        XCTAssertEqual(RightDisplayPlacement.rightmost([
            1: CGRect(x: 0, y: 0, width: 1512, height: 982),
            2: CGRect(x: 1912, y: -1152, width: 2048, height: 1152),
            3: CGRect(x: -392, y: -1296, width: 2304, height: 1296)
        ]), 2)
        XCTAssertNil(RightDisplayPlacement.rightmost([:]))
    }
    func testOversizedWindowFitsAndAlreadyPlacedWindowStays() {
        let screen = CGRect(x: 1912, y: -1152, width: 2048, height: 1152)
        let target = RightDisplayPlacement.fittedFrame(
            original: CGRect(x: 0, y: 0, width: 2500, height: 1600), display: screen)
        XCTAssertTrue(screen.contains(target))
        XCTAssertEqual(target.size, CGSize(width: 1968, height: 1072))
        XCTAssertEqual(RightDisplayPlacement.fittedFrame(original: target, display: screen), target)
    }
    func testRightPlacementRequiresExactWindowAndVirtualProducerAlwaysRejects() {
        XCTAssertThrowsError(try validateExactWindowPlacement(.rightDisplay, windowID: nil))
        XCTAssertNoThrow(try validateExactWindowPlacement(.rightDisplay, windowID: 123))
        XCTAssertThrowsError(try VirtualDisplayConfig(enabled: true, restoreOnSessionEnd: false).requireEnabled())
        for enabled in [true, false] {
            let tools = ToolDefinitions.configured(virtualDisplayEnabled: enabled)
            XCTAssertFalse(tools.contains { $0.name == "ensure_agent_display" })
            let state = tools.first { $0.name == "get_app_state" }!
            let properties = state.inputSchema["properties"] as! [String: Any]
            let placement = properties["window_placement"] as! [String: Any]
            let values = placement["enum"] as! [String]
            XCTAssertTrue(values.contains("right_display"))
            XCTAssertFalse(values.contains("agent_display"))
        }
    }
}
