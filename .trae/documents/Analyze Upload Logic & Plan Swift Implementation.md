# Swift File Upload Logic Analysis & Implementation Plan

Based on the `FileUploadClient.java` reference and the existing project structure, I have designed the Swift implementation for the file upload functionality with "Resume Upload" (Breakpoint Continuation) support.

## 1. Protocol Flow Analysis (Java Reference)

The upload process follows a strict 4-step handshake and data transmission protocol:

| Step | Action | Frame Type | Direction | Payload / Description |
| :--- | :--- | :--- | :--- | :--- |
| **1. Check** | **Resume Check** | `0x05` (Check) | Client -> Server | JSON: MD5, Name, Size, Type, DirID, UserID |
| | | `0x06` (Ack) | Server -> Client | JSON: `status` ("resume"/"new"), `taskId`, `uploadedSize` |
| **2. Handshake** | **Meta Info** | `0x01` (Meta) | Client -> Server | *(Only if status="new")* Same JSON as Check |
| | | `0x04` (Ack) | Server -> Client | JSON: `status` ("ready"), `taskId` |
| **3. Transfer** | **Send Data** | `0x02` (Data) | Client -> Server | Raw Binary Chunks (8KB). No ACK per frame. |
| **4. Finish** | **End Upload** | `0x03` (End) | Client -> Server | JSON: `taskId` |
| | | `0x04` (Ack) | Server -> Client | JSON: `status` ("success") |

## 2. Swift Implementation Logic

I will encapsulate this logic into a new `FileTransferService` class.

### 2.1 Core Components

1.  **MD5 Calculation**: Use `CryptoKit` for efficient, streaming MD5 calculation of large files.
2.  **File Reading**: Use `FileHandle` to seek to specific offsets (for resume) and read chunks without loading the entire file into memory.
3.  **Frame Construction**: Use the existing `Frame` struct and `FrameTypeEnum`.
4.  **Networking**: Use `SocketManager.shared.sendFrameAndWait` for control frames and `sendFrame` for data frames.

### 2.2 Data Structures (Codable)

We need strict structs to match the JSON payloads expected by the server.

```swift
// Request Payloads
struct FileMetaRequest: Codable {
    let md5: String
    let fileName: String
    let fileSize: Int64
    let fileType: String
    let dirId: Int64
    let userId: Int64
}

struct EndUploadRequest: Codable {
    let taskId: String
}

// Response Payloads
struct ResumeAckResponse: Codable {
    let status: String       // "resume", "new"
    let taskId: String?
    let uploadedSize: Int64? // Offset
    let message: String?
}

struct StandardAckResponse: Codable {
    let status: String       // "ready", "success"
    let taskId: String?
    let message: String?
}
```

### 2.3 Upload Workflow (Pseudo-Code)

```swift
func uploadFile(url: URL, targetDirId: Int64) async throws {
    // 1. Pre-computation
    let md5 = calculateMD5(url)
    let fileSize = url.fileSize
    let fileName = url.lastPathComponent
    let fileType = url.pathExtension
    
    // 2. Resume Check (0x05)
    let metaReq = FileMetaRequest(...)
    let checkFrame = Frame(type: .resumeCheck, data: metaReq.jsonData)
    let resumeRespFrame = try await socket.sendFrameAndWait(checkFrame, expecting: .resumeAck)
    let resumeInfo = decode(resumeRespFrame, as: ResumeAckResponse.self)
    
    var offset: Int64 = 0
    var taskId: String = ""
    
    if resumeInfo.status == "resume" {
        // Case A: Resume
        taskId = resumeInfo.taskId!
        offset = resumeInfo.uploadedSize ?? 0
    } else if resumeInfo.status == "new" {
        // Case B: New Upload -> Send Meta (0x01)
        let metaFrame = Frame(type: .metaFrame, data: metaReq.jsonData)
        let ackFrame = try await socket.sendFrameAndWait(metaFrame, expecting: .ackFrame)
        let ack = decode(ackFrame, as: StandardAckResponse.self)
        taskId = ack.taskId!
    }
    
    // 3. Send Data (0x02)
    if offset < fileSize {
        let fileHandle = try FileHandle(forReadingFrom: url)
        try fileHandle.seek(toOffset: UInt64(offset))
        
        while let chunk = try fileHandle.read(upToCount: 8192) {
             let dataFrame = Frame(type: .dataFrame, data: chunk)
             try socket.sendFrame(dataFrame) // No wait
        }
    }
    
    // 4. Send End (0x03)
    let endReq = EndUploadRequest(taskId: taskId)
    let endFrame = Frame(type: .endFrame, data: endReq.jsonData)
    try await socket.sendFrameAndWait(endFrame, expecting: .ackFrame)
}
```

## 3. Next Steps
I will create the `FileTransferService.swift` file and implement the logic described above, then integrate it into `MainChatStorage.swift` to handle the "Start Upload" action.
