import Foundation

/// A client disconnect can race another client's snapshot/park sequence.
/// Serialize the complete tool operation with placement + occlusion cleanup,
/// not only the individual registries. Recursive for nested service cleanup.
public enum BackgroundWindowStateTransaction {
    private static let lock = NSRecursiveLock()

    public static func perform<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
