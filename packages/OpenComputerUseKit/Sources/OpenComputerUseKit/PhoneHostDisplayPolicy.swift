import Foundation
import CoreFoundation

struct PhoneHostDisplayBinding: Codable, Equatable {
    let instanceID: String
    let pid: Int32
    let processStartTime: Double
    var windowID: UInt32?
}

struct PhoneHostDisplayPolicy {
    static let namespace = "smart-shadow-phone-host"
    static func validate(_ raw: [String: Any]) throws -> (String, PhoneHostDisplayBinding) {
        let keys: Set<String> = ["action", "instance_id", "pid", "process_start_time", "window_id"]
        guard Set(raw.keys).isSubset(of: keys),
              let action = raw["action"] as? String, ["ensure", "status", "park", "release"].contains(action),
              let instance = raw["instance_id"] as? String, UUID(uuidString: instance) != nil,
              let pid = raw["pid"] as? NSNumber, CFGetTypeID(pid) != CFBooleanGetTypeID(),
              pid.doubleValue > 0, pid.doubleValue <= Double(Int32.max), pid.doubleValue.rounded() == pid.doubleValue,
              let start = raw["process_start_time"] as? NSNumber, CFGetTypeID(start) != CFBooleanGetTypeID(),
              start.doubleValue.isFinite, start.doubleValue > 0 else {
            throw ComputerUseError.invalidArguments("phone_host_display requires action, instance UUID, exact positive pid and process_start_time")
        }
        var window: UInt32?
        if let value = raw["window_id"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue > 0, number.doubleValue <= Double(UInt32.max), number.doubleValue.rounded() == number.doubleValue else {
                throw ComputerUseError.invalidArguments("phone_host_display requires an exact positive window_id")
            }
            window = number.uint32Value
        }
        guard !["park", "release"].contains(action) || window != nil else {
            throw ComputerUseError.invalidArguments("phone_host_display park/release requires window_id")
        }
        return (action, PhoneHostDisplayBinding(instanceID: instance.lowercased(), pid: pid.int32Value,
                                                processStartTime: start.doubleValue, windowID: window))
    }
    static func sameHost(_ a: PhoneHostDisplayBinding, _ b: PhoneHostDisplayBinding) -> Bool {
        a.instanceID == b.instanceID && a.pid == b.pid && a.processStartTime == b.processStartTime
    }
    static func processGone(exists: Bool, observedStart: Double?, expectedStart: Double) -> Bool {
        guard exists else { return true }
        guard let observedStart else { return false }
        return abs(observedStart - expectedStart) >= 0.0001
    }
    static func admitted(_ request: PhoneHostDisplayBinding, by admission: PhoneHostDisplayBinding) -> Bool {
        sameHost(request, admission) && (request.windowID == nil || request.windowID == admission.windowID)
    }
    static func enabled(document: [String: Any], namespace: String) -> Bool {
        guard namespace == self.namespace, let section = document["phoneHostDisplay"] as? [String: Any],
              let value = section["enabled"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return value.boolValue
    }
}

