I will fix the `EXC_BAD_ACCESS` error in `SocketManager.swift` which occurs during object deallocation.

### Issue Analysis
The crash happens because:
1. `SocketManager.deinit` calls `disconnect()`.
2. `disconnect()` calls `updateState(.disconnected)`.
3. `updateState` dispatches a closure to the main queue: `DispatchQueue.main.async { self.connectionState = state }`.
4. This closure captures `self` strongly, but `self` is already in the deallocation phase (`deinit`). When the closure executes on the main thread, `self` is invalid or being destroyed, causing `EXC_BAD_ACCESS`.

### Solution Plan
I will modify `SocketManager.swift` to ensure `disconnect()` does not trigger async UI updates when called from `deinit`.

1.  **Refactor `disconnect`**: Add a parameter `notifyUI: Bool = true`.
2.  **Update `deinit`**: Call `disconnect(notifyUI: false)` to perform cleanup without scheduling async updates.
3.  **Implement Cleanup**: Ensure stream closing and timer invalidation happens synchronously in `disconnect`.

This change prevents the zombie object access while maintaining correct resource cleanup.