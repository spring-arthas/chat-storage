I have analyzed the request and the codebase. Here is the plan to implement the thread pool and optimized upload logic:

1.  **Refactor SocketManager**:
    *   Currently, `SocketManager` is a singleton (`shared`) with a `private init`. I need to change `private override init()` to `override init()` (internal access) to allow creating separate instances for each file transfer task.
    *   This is crucial because the requirement specifies "Establish a new connection... on port 10087" for each task.

2.  **Create `TransferTaskManager.swift`**:
    *   This class will manage the "thread pool".
    *   I will use Swift's `Task` and structured concurrency or an Actor to manage the active tasks.
    *   Since the user specifically asked for a "Thread Pool" and "Max concurrent 10", I will implement a `TransferTaskManager` actor that maintains:
        *   `activeTasks`: A dictionary of running tasks.
        *   `pendingTasks`: A queue of tasks waiting to run.
        *   `maxConcurrentTasks = 10`.
    *   It will have methods: `addTask`, `cancelTask`, `pauseTask`, `resumeTask`.

3.  **Refactor `FileTransferService` (in `DirectoryService.swift`)**:
    *   I will extract `FileTransferService` out of `DirectoryService.swift` into a new file `Services/TransferService.swift` (since I can't easily re-add the old one to Xcode, I'll create a new file or just keep it in `DirectoryService.swift` but modify it to accept a *specific* `SocketManager` instance instead of using the shared one).
    *   Actually, to keep it clean and avoid the "file not in target" issue again, I will keep the code in `DirectoryService.swift` for now but rename the class to `TransferWorker` or similar, and instantiate it per task.
    *   **Crucial Change**: The `uploadFile` method needs to take a `host` and `port` (10087) and create its *own* `SocketManager` instance, connect, perform the handshake, and then upload.

4.  **Implement `TransferTask` Logic**:
    *   This will be a wrapper struct/class that holds the state (`TransferItem`), the `Task` handle, and the `SocketManager` instance.
    *   It will handle the Pause/Resume logic. Pause = Cancel the task/Close socket but keep state. Resume = Start new task with offset.

5.  **Update `MainChatStorage.swift`**:
    *   Inject `TransferTaskManager` as an `@EnvironmentObject`.
    *   Update `handleTransferAction` to call `manager.start()` / `manager.pause()`.
    *   Update the UI to reflect the status changes driven by the manager.

**Implementation Steps:**

1.  **Modify `SocketManager.swift`**: Change `private override init()` to `override init()` to allow instantiation.
2.  **Create `TransferTaskManager`**: Implement the actor/class to manage the queue and concurrency.
3.  **Update `FileTransferService` (in `DirectoryService.swift`)**:
    *   Modify `uploadFile` to create a *new* `SocketManager` connected to port 10087.
    *   Implement the connection handshake logic (standard TCP connect).
    *   Ensure it reports progress back to the manager.
4.  **Update `MainChatStorage.swift`**: Connect the UI actions to the `TransferTaskManager`.

I will start by modifying `SocketManager.swift` to allow multiple instances. Then I will implement the Manager and update the Service.