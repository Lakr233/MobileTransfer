import Foundation

/// All access to the stored value is synchronous and protected by the lock.
package final class LockedState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    package init(_ value: Value) {
        self.value = value
    }

    package func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
