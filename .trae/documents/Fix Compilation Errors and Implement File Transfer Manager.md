I will fix the persistent "undefined variable" and visibility errors by consolidating the file transfer logic into `DirectoryService.swift` (ensuring it's compiled) and updating `MainChatStorage.swift` to correctly integrate with the new `TransferTaskManager`.

### Step 1: Refactor `DirectoryService.swift`
I will merge `FileTransferService`, `TransferTaskManager`, and `DirectoryService` into this single file to resolve Xcode target membership issues.
- **Fix Imports**: Ensure `import CommonCrypto` is present for MD5 hashing.
- **Implement `TransferTaskManager`**: A singleton (`shared`) actor-isolated class that manages the thread pool (limit 10) and dedicated upload tasks.
- **Fix MD5 Calculation**: Use `CC_MD5` (C-based) to avoid `CryptoKit` scope issues.
- **Fix Socket Logic**: Ensure `TransferTaskManager` creates a **new** `SocketManager` instance for each upload task, connects to port **10087**, and executes the upload.

### Step 2: Update `MainChatStorage.swift`
I will update the main view to use the singleton manager and ensure the UI reflects the transfer progress.
- **Remove Legacy Code**: Delete all references to the removed `transferService` variable.
- **Integrate Manager**: Use `@StateObject private var transferManager = TransferTaskManager.shared`.
- **Sync UI Progress**: Add `.onReceive(transferManager.$taskUpdates)` to listen for progress updates and synchronize them with the local `transferList` so the progress bars update in real-time.
- **Fix Definitions**: Ensure `TransferTask` and other models are correctly instantiated using `AuthenticationService` data.

This approach addresses the "Cannot find definition" errors by ensuring all related classes are in a known-good file and removes the "undefined variable" errors by cleaning up the View code.