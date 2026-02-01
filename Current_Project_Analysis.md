# Current Project Analysis & Functionality Report

## 1. Project Overview
**Project Name**: chat-storage
**Platform**: macOS (SwiftUI)
**Architecture**: MVVM-like with centralized Service layer.
**Core Functionality**: Secure file storage with custom TCP networking protocol.

## 2. Architecture & Data Flow

### 2.1 Dependency Injection (DI)
The application uses a clean Dependency Injection pattern initialized in `chat_storageApp.swift`:

*   **SocketManager**: Singleton (`.shared`) but injected as an `@EnvironmentObject`.
*   **AuthenticationService**: Created in `chat_storageApp` using the `SocketManager` singleton, and injected as an `@EnvironmentObject`.
*   **PersistenceController**: Core Data stack injected into the environment (though currently less active than the custom socket layer).

**Flow**:
`chat_storageApp` -> `AuthenticationService` -> `SocketManager` -> `TCP Socket`

### 2.2 Navigation Flow
Navigation is controlled by the `AuthenticationService.isAuthenticated` state:
*   **True**: Shows `MainChatStorage` (Main File View).
*   **False**: Shows `LoginView`.

This reactive state management ensures that login/logout events automatically transition the UI without manual view manipulation.

## 3. Key Components Analysis

### 3.1 Networking Layer (`SocketManager.swift`)
*   **Protocol**: Custom binary frame protocol (Header + Payload).
*   **Connection**: Persistent TCP connection using `CFStream` / `InputStream` / `OutputStream`.
*   **Features**:
    *   Heartbeat mechanism (PING/PONG every 30s).
    *   Auto-reconnection logic (up to 5 attempts).
    *   Speed monitoring (upload/download).
    *   Event-driven data reception (`StreamDelegate`).
    *   `CheckedContinuation` based request-response matching (allows `await`ing async responses to specific frame types).

### 3.2 Authentication Layer (`AuthenticationService.swift`)
*   **Role**: Manages user session and login/register logic.
*   **State**: Exposes `currentUser` and `isAuthenticated` as `@Published` properties.
*   **Methods**:
    *   `login()`: Sends `.userLoginReq`, waits for `.userResponse`, parses `UserDO`.
    *   `register()`: Sends `.userRegisterReq`, waits for `.userResponse`.
    *   `logout()`: Clears local state.

### 3.3 UI Components

#### `LoginView.swift`
*   **State**: Manages form inputs (`username`, `password`) and UI state (`isLoading`, `errorMessage`).
*   **Integration**: Uses `@EnvironmentObject var authService` to perform actual network requests.
*   **Feedback**: Displays real-time error messages from the `AuthError` or `SocketError`.

#### `RegisterView.swift`
*   **State**: Manages registration form including password confirmation and email.
*   **Integration**: Calls `authService.register()` and dismisses itself upon success.

#### `MainChatStorage.swift`
*   **Layout**: Split view with Sidebar (Directory Tree) and Main Content (File List + Transfer List).
*   **Features**:
    *   **Directory Management**: Create, Rename, Delete directories (Real network calls via `DirectoryService`).
    *   **File Browser**: Grid/List view of files (Currently uses fake data generation `generateFakeData()`, but wired for real `DirectoryItem` models).
    *   **Transfer Manager**: Visualizes Upload/Download tasks.

## 4. Current Status & Readiness
The project has successfully transitioned from a UI prototype to a connected application.
*   **Verified**:
    *   Socket connection lifecycle.
    *   Authentication flow (Login/Register) is fully wired to the network layer.
    *   UI state reacts correctly to network events.
*   **Pending Feature Development**:
    *   **Real File Listing**: `MainChatStorage` still generates some fake data (`generateFakeData`) on appear. This needs to be replaced with real `DirectoryService` calls.
    *   **File Transfer**: Upload/Download logic is stubbed (UI exists, but underlying byte stream transfer is not implemented).

## 5. Next Steps Recommendation
1.  **Directory Listing**: Replace `generateFakeData()` in `MainChatStorage` with `directoryService.loadDirectoryTree()`.
2.  **File Upload**: Implement the `DataFrame` sending logic in `SocketManager` and connect it to the "Upload" button.
3.  **File Download**: Implement the logic to handle incoming `.dataFrame` streams and write them to disk.
