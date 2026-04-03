# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Debug build (Xcode)
xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug build

# Release archive
xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Release archive -archivePath build/release/chat-storage.xcarchive

# Run tests
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'

# Run a single test (replace TestClassName/testMethodName)
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/TestClassName/testMethodName

# Package as DMG (ad-hoc, for local testing)
bash package_dmg.sh

# Package DMG with notarization (for distribution to other machines)
DEVELOPER_TEAM_ID="<TEAM_ID>" \
DEVELOPER_ID_APPLICATION="Developer ID Application: <Name> (<TEAM_ID>)" \
NOTARY_KEYCHAIN_PROFILE="chat-storage-notary" \
bash chat-storage/scripts/build_release_dmg.sh
```

## Architecture Overview

This is a macOS SwiftUI app that acts as a client for a remote personal cloud storage and chat service. All communication with the server happens over a **custom binary frame protocol** via TCP.

### Custom Frame Protocol

The core of the app is a binary protocol defined in `chat-storage/Models/frame/`:

- **`Frame.swift`**: Wire format — `[Magic: 2B][Type: 1B][Flags: 1B][Length: 4B][Data: NB]`. Magic bytes are `0xFACE`. Data is JSON-encoded payload.
- **`FrameTypeEnum.swift`**: All protocol message types (0x01–0x5F), covering file transfer, directory ops, auth, and chat.
- **`FrameBuilder.swift`**: Encodes a `Codable` payload into a `Frame`.
- **`FrameParser.swift`**: Decodes raw bytes into `Frame` structs, handles buffer accumulation.

### Core Services (all singletons)

- **`SocketManager.swift`**: Manages the TCP connection using Apple's `Network` framework. Exposes `sendFrameAndWait(_:expecting:timeout:)` — a send-and-await-response method using a pending-response map keyed by frame type. Frame handling logic lives here (merged from `SocketManager+FrameHandling.swift`).
- **`AuthenticationService.swift`**: Login/register/logout by sending auth frames through `SocketManager`. Stores the current `UserDO` and `isAuthenticated` flag.
- **`DirectoryService.swift`** (`@MainActor`): Directory tree loading, file listing, upload/download initiation. Uses `CommonCrypto` for MD5 calculation (not `CryptoKit`).
- **`TransferTaskManager.swift`**: Manages concurrent file transfers (max 5). Uses `ManagedCriticalState` (a custom actor-safe wrapper) for thread-safe queue access. Persists incomplete tasks to Core Data via `PersistenceManager` and restores them on launch. Download tasks are identified by a `DOWNLOAD_FILE_ID_<id>` marker in the MD5 field.
- **`LocalMediaServer.swift`**: Local HTTP server on `127.0.0.1` that proxies range requests from `AVPlayer` to the custom frame protocol — bridges `AVPlayer` video playback to the socket backend.

### View Layer

- **`chat_storageApp.swift`**: App entry point. Initializes `SocketManager` and `AuthenticationService` as `@StateObject` singletons injected as `@EnvironmentObject`.
- **`LoginView.swift` / `RegisterView.swift`**: Auth screens.
- **`ConfigServerView.swift`**: Server address/port configuration.
- **`MainChatStorage.swift`**: Primary view after login — file browser with directory tree, file list, pagination, upload/download controls, and a transfer task list. Tabs include friend list and file storage.
- **`NewFriendView.swift`**: Friend search, pending requests, and friend list management.

### Video Streaming

`LocalMediaServer` + `VideoStreamLoaderDelegate` + `VideoStreamingService` + `VideoWindowManager` + `StreamingVideoPlayer` (in `Views/`) form the video playback pipeline. `AVPlayer` talks to the local HTTP server; the server translates HTTP Range requests into the frame protocol.

### Data Persistence

Core Data (`Persistence.swift`, `NSPersistentCloudKitContainer`) is used **only** to persist `TransferTaskEntity` records (the in-progress/pending upload-download queue). It is not used for the main file data, which lives on the remote server.

### Key Architectural Notes

- `FileTransferService.swift` is a commented-out stub; its logic was merged into `DirectoryService.swift`.
- `SocketManager+FrameHandling.swift` is an empty stub; its logic was merged into `SocketManager.swift`. Both files remain to avoid missing Xcode reference errors.
- The `build/` directory contains Xcode's derived data and should not be modified manually.
