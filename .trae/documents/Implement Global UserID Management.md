I will implement the global `userId` management as requested.

### Plan

1.  **Enhance `AuthenticationService.swift`**:
    -   Add `static let shared` singleton instance to facilitate global access if needed, though we will primarily use Environment Object injection.

2.  **Update `chat_storageApp.swift`**:
    -   Lift `AuthenticationService` to the App level as a `@StateObject`.
    -   Inject it as an `.environmentObject` into both `LoginView` and `MainChatStorage`. This ensures the `currentUser` (and thus `userId`) persists when switching views.

3.  **Update `LoginView.swift`**:
    -   Remove the local `@StateObject` creation of `authService`.
    -   Use `@EnvironmentObject` to access the global `authService` instance.
    -   Remove the custom `init` method that was creating a new service instance.

4.  **Update `MainChatStorage.swift`**:
    -   In `handleTransferAction`, retrieve the `userId` from the global `authService.currentUser?.userId`.
    -   Pass this `userId` when creating the `TransferTask`.

5.  **Fix `DirectoryService.swift`**:
    -   In `TransferTaskManager.startTask`, fix the undefined `userId` variable by using `task.userId` (which carries the value we retrieved from the global store).
    -   Ensure `FileTransferService` uses this `userId`.

### Verification
-   I will verify that `chat_storageApp.swift` correctly initializes and injects the service.
-   I will verify `LoginView` compiles and uses the environment object.
-   I will verify `DirectoryService.swift` no longer has the undefined `userId` error.
