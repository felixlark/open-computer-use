import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class PersistentDisplayBootstrapTests: XCTestCase {
    func testBootstrapIsAdvertisedOnlyWithExplicitDisplayConfiguration() {
        XCTAssertFalse(ToolDefinitions.configured(virtualDisplayEnabled: false).contains { $0.name == "ensure_agent_display" })
        let tool = ToolDefinitions.configured(virtualDisplayEnabled: true).first { $0.name == "ensure_agent_display" }
        XCTAssertNotNil(tool)
        XCTAssertEqual(tool?.annotations["idempotentHint"] as? Bool, true)
        XCTAssertEqual(tool?.annotations["readOnlyHint"] as? Bool, false)
        XCTAssertEqual(tool?.inputSchema["additionalProperties"] as? Bool, false)
    }
    func testDisabledOrTransientConfigurationCannotBootstrap() {
        for config in [VirtualDisplayConfig(enabled: false, restoreOnSessionEnd: false),
                       VirtualDisplayConfig(enabled: true, restoreOnSessionEnd: true)] {
            XCTAssertThrowsError(try PersistentDisplayBootstrap.requireConfiguration(config))
        }
        XCTAssertNoThrow(try PersistentDisplayBootstrap.requireConfiguration(.init(enabled: true, restoreOnSessionEnd: false)))
    }
    func testWindowArgumentsAreRejectedBeforeAnyDisplayOperation() {
        XCTAssertThrowsError(try ComputerUseToolDispatcher().callTool(name: "ensure_agent_display", arguments: ["window_id": 10]))
    }
    func testReceiptIdentifiesTheLiveNamespaceScreen() throws {
        let receipt = PersistentDisplayReadiness(id: 42, bounds: CGRect(x: 5000, y: 0, width: 1920, height: 1080), namespace: "persistent-display")
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(receipt.rendered().utf8)) as? [String: Any])
        XCTAssertEqual(value["protocol"] as? Int, 2)
        XCTAssertEqual(value["geometry"] as? String, "fit_restore_v1")
        XCTAssertEqual(value["display_id"] as? Int, 42)
        XCTAssertEqual(value["namespace"] as? String, "persistent-display")
        XCTAssertEqual(value["persistent"] as? Bool, true)
        XCTAssertEqual((value["bounds"] as? [String: Int])?["width"], 1920)
    }
}
