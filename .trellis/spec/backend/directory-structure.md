# Directory Structure

> How backend (service/model) code is organized in this project.

---

## Overview

This is a macOS SwiftUI app. "Backend" refers to the service layer, models, and protocol layer — everything that is NOT a SwiftUI View.

---

## Directory Layout

```
chat-storage/
├── Models/
│   ├── frame/                  # Custom binary protocol definitions
│   │   ├── Frame.swift         # Wire format struct
│   │   ├── FrameTypeEnum.swift # All protocol message type codes (0x01–0x5F)
│   │   ├── FrameBuilder.swift  # Encodes Codable payload → Frame
│   │   └── FrameParser.swift   # Decodes raw bytes → Frame, handles buffer accumulation
│   ├── do/                     # Data Objects (server-side entities)
│   │   ├── UserDO.swift        # User entity, CodingKeys map server field names
│   │   └── FileDto.swift       # File entity from server
│   ├── business/               # Business-specific models
│   │   └── UserSearchModels.swift
│   └── DirectoryItem.swift     # Directory tree node
├── Services/
│   ├── AuthenticationService.swift   # Login/register/logout via frame protocol
│   ├── DirectoryService.swift        # Directory CRUD, file listing, upload/download
│   ├── TransferTaskManager.swift     # Concurrent transfer queue (max 5)
│   ├── StorageTransferTask.swift     # Transfer task model (upload/download)
│   ├── TransferModels.swift          # Supporting transfer types
│   ├── ManagedCriticalState.swift    # NSLock-based actor-safe state wrapper
│   ├── LocalMediaServer.swift        # Local HTTP server for AVPlayer video proxy
│   ├── VideoStreamingService.swift   # Video streaming coordination
│   ├── VideoStreamLoaderDelegate.swift
│   ├── VideoWindowManager.swift
│   ├── FileTransferService.swift     # STUB — logic merged into DirectoryService
│   └── RecursiveDirectoryView.swift  # Helper for directory traversal
├── SocketManager.swift               # TCP connection, sendFrameAndWait
├── SocketManager+FrameHandling.swift # STUB — logic merged into SocketManager
├── Persistence.swift                 # Core Data stack + PersistenceManager
└── InputValidator.swift              # Phone/email/password format validation
```

---

## Module Organization

**Frame Protocol** (`Models/frame/`): Self-contained. All protocol message types, encoding and decoding live here. Never bypass this layer — always use `FrameBuilder.build()` and `FrameParser.decodePayload()`.

**Services** (`Services/`): Business logic singletons. Each service depends on `SocketManager.shared` for transport.

**SocketManager** (root): The single source of truth for the TCP connection. All communication goes through `sendFrameAndWait(_:expecting:timeout:)`.

---

## Naming Conventions

| Pattern | Convention | Example |
|---------|-----------|---------|
| Data Objects | `*DO` suffix | `UserDO` |
| Request structs | `*Request` suffix | `UserRequest`, `FileListRequest` |
| Response wrapper | `ResponseWrapper<T>` | `ResponseWrapper<UserDO>` |
| Frame type codes | `*Req` / `*Response` / `*Ack` | `.dirCreateReq`, `.dirResponse` |
| Singletons | `static let shared` | `SocketManager.shared` |
| Errors | `*Error` enum conforming `LocalizedError` | `SocketError`, `FrameError`, `AuthError`, `DirectoryError` |

---

## Stub Files — Do Not Delete

Two files are intentional empty stubs kept to avoid breaking Xcode project references:
- `FileTransferService.swift` — logic merged into `DirectoryService.swift`
- `SocketManager+FrameHandling.swift` — logic merged into `SocketManager.swift`

**Never delete these files. Never add logic back into them.**

---

## Examples

- Well-organized service: `Services/AuthenticationService.swift`
- Well-organized protocol layer: `Models/frame/FrameBuilder.swift`
- Data object with CodingKeys mapping: `Models/do/UserDO.swift`
