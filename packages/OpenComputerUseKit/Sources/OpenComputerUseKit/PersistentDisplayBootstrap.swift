import CoreGraphics
import Foundation

/// Host bootstrap creates no fixture or window and shares the normal OCU owner.
enum PersistentDisplayBootstrap {
    static func requireConfiguration(_ config: VirtualDisplayConfig) throws {
        try config.requireEnabled()
        guard !config.restoreOnSessionEnd else {
            throw ComputerUseError.message("ensure_agent_display requires virtualDisplay.restoreOnSessionEnd=false")
        }
    }

    static let definition = ToolDefinition(
        name: "ensure_agent_display",
        description: "Create or reuse this owner's persistent virtual display without opening or moving any window. Requires virtualDisplay.enabled=true and restoreOnSessionEnd=false. Returns protocol 1 display identity and geometry; session disconnect keeps the empty screen until owner exit.",
        annotations: ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
        inputSchema: ["type": "object", "properties": [String: Any](), "additionalProperties": false]
    )
}

struct PersistentDisplayReadiness {
    let id: CGDirectDisplayID
    let bounds: CGRect
    let namespace: String

    func rendered() throws -> String {
        let value: [String: Any] = ["protocol": 1, "display_id": id, "namespace": namespace, "persistent": true,
            "bounds": ["x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height]]
        return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
}

extension ComputerUseService {
    public func ensureAgentDisplay() throws -> ToolCallResult {
        .text(try AgentDisplay.shared.ensureForHost().rendered())
    }
}
