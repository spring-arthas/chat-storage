I have successfully refactored the file upload logic to support a thread pool, dedicated connection port (10087), and pause/resume functionality.

Here is the summary of changes:
1.  **Refactored `MainChatStorage.swift`**:
    -   Integrated `TransferTaskManager` to manage upload tasks.
    -   Updated `handleTransferAction` to delegate Start/Pause/Cancel operations to the manager.
    -   Added real-time UI updates by subscribing to `transferManager.taskUpdates`.
    -   Removed the deprecated direct usage of `FileTransferService`.

2.  **Updated `DirectoryService.swift`**:
    -   Added `try Task.checkCancellation()` in the file upload loop to support immediate task pausing/cancellation.
    -   Ensured `FileTransferService` (merged inside) is correctly implemented with `CommonCrypto` for MD5 hashing.

3.  **Cleaned up `FileTransferService.swift`**:
    -   Commented out the content of the standalone `FileTransferService.swift` to avoid "Redefinition of class" errors, as the valid code is now in `DirectoryService.swift`.

4.  **Verified `TransferTaskManager.swift`**:
    -   Confirms it implements the thread pool (max 10 concurrent tasks).
    -   Creates a dedicated `SocketManager` for each task on port 10087.
    -   Handles the Pause/Resume logic by cancelling tasks and re-queueing them with server-side breakpoint checks.

The code is now ready for testing. Please ensure `TransferTaskManager.swift` is included in your Xcode project target.