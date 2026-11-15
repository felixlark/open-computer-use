import Foundation

/// Virtual displays change the system display arrangement, so creating one
/// requires an explicit host setting in addition to the tool argument.
struct VirtualDisplayConfig: Equatable {
    static let environmentKey = "OPEN_COMPUTER_USE_VIRTUAL_DISPLAY_ENABLED"
    static let restoreEnvironmentKey = "OPEN_COMPUTER_USE_VIRTUAL_DISPLAY_RESTORE_ON_SESSION_END"
    var enabled = false
    var restoreOnSessionEnd = true

    static var current: VirtualDisplayConfig {
        let environment = OCUConfiguration.environment
        var document: [String: Any] = [:]
        do {
            let url = try OCUConfiguration.fileURL(environment: environment)
            if FileManager.default.fileExists(atPath: url.path) {
                guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                document = root
            }
        } catch {
            warn("Cannot read virtual display config: \(error). Using environment/defaults.")
        }
        return resolve(document: document, environment: environment, warning: warn)
    }

    static func resolve(document: [String: Any], environment: [String: String], warning: (String) -> Void = { _ in }) -> VirtualDisplayConfig {
        let section = document["virtualDisplay"] as? [String: Any] ?? [:]
        if document["virtualDisplay"] != nil && document["virtualDisplay"] as? [String: Any] == nil {
            warning("Invalid virtualDisplay config; using defaults")
        }
        func boolean(_ key: String, environmentKey: String, default fallback: Bool) -> Bool {
            if let value = environment[environmentKey] {
                if value == "true" || value == "false" { return value == "true" }
                warning("Invalid \(environmentKey); using default \(fallback)")
                return fallback
            }
            guard let value = section[key] else { return fallback }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                warning("Invalid virtualDisplay.\(key); using default \(fallback)")
                return fallback
            }
            return number.boolValue
        }
        return VirtualDisplayConfig(
            enabled: boolean("enabled", environmentKey: environmentKey, default: false),
            restoreOnSessionEnd: boolean("restoreOnSessionEnd", environmentKey: restoreEnvironmentKey, default: true)
        )
    }

    func requireEnabled() throws {
        // The virtual-display route has been retired. Old MCP processes can
        // retain enabled=true in their environment; that is not an opt-in.
        throw ComputerUseError.message("OCU virtual displays are retired; use exact window_placement=right_display on the rightmost physical display")
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("ocu config: \(message)\n".utf8))
    }
}
