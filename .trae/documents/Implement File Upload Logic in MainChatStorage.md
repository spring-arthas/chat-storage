I will modify `MainChatStorage.swift` to implement the file upload logic by integrating the `FileTransferService`.

1.  **Read `Services/SocketManager.swift`** to confirm `sendFrameAndWait` exists and is compatible.
2.  **Modify `MainChatStorage.swift`**:
    *   Update the `TransferItem` struct to include a `targetDirId` field, ensuring we know where to upload the file.
    *   Update the `handleSelectFiles` function to populate the `targetDirId` when creating a transfer task.
    *   Implement the `handleTransferAction` function (specifically the `start` case) to call `transferService.uploadFile`, handling progress updates and success/failure states.
    *   This ensures the upload follows the specified protocol (Resume Check -> Meta -> Data -> End) via the service.

No other functional code blocks will be affected.