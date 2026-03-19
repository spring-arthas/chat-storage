import Foundation

/// A tiny backport used to guard mutable state from concurrent access.
final class ManagedCriticalState<State> {
    private let lock = NSLock()
    private var state: State

    init(_ initialState: State) {
        self.state = initialState
    }

    @discardableResult
    func withCriticalRegion<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
