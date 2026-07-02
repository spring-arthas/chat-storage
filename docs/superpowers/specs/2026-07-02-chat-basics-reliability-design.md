# Chat Basics And Reliability Phase 1 Design

## Purpose

Phase 1 improves the chat experience in `chat-storage` so it feels like a normal macOS IM client while keeping the existing cloud-drive, friend, thumbnail, video, and file-transfer behavior intact.

The phase combines:

- Basic message operations.
- Emoji and input ergonomics.
- Clipboard image sending.
- Message send reliability.
- Small, targeted component extraction from the current large `MainChatStorage.swift`.

## Current Context

The client is a SwiftUI macOS app using a custom binary frame protocol:

```text
Magic(2 bytes: FA CE) + Type(1 byte) + Flags(1 byte) + Length(4 bytes) + Data(N bytes)
```

Important current chat and friend frame usage:

| Frame | Current meaning |
| --- | --- |
| `0x50` | Chat send request |
| `0x51` | Chat push |
| `0x52` | Chat receipt |
| `0x53` | Chat history request |
| `0x54` | Chat history response |
| `0x55` | Clear unread request |
| `0x56` | Clear unread response |
| `0x57` | Friend alias update request |
| `0x58` | Friend alias update response |

`0x57` and `0x58` are already implemented for friend alias updates. Phase 1 must not reuse them for chat message actions.

`MainChatStorage.swift` currently contains the main cloud-drive UI and much of the chat UI. It is over 5000 lines, so Phase 1 must extract focused chat components instead of adding more chat logic to the main file.

## Goals

1. Add message context actions:
   - Copy text.
   - Delete locally.
   - Retract for both sides when permitted.
2. Add quote reply:
   - Select a message to quote.
   - Show a quote preview above the input.
   - Send quote metadata with the message.
   - Render quote metadata in push and history messages.
3. Improve input:
   - Enter sends.
   - Shift+Enter or Option+Enter inserts a newline.
   - Input height grows up to a capped height, then scrolls.
4. Add emoji:
   - Emoji button in the input toolbar.
   - Emoji picker panel.
   - Click inserts emoji at the current caret position.
   - Recent emoji list is persisted locally.
5. Add clipboard image sending:
   - Cmd+V in the chat input captures image content.
   - Show a send preview.
   - Upload the image through the existing file upload path.
   - Send a chat message with `msgType = "IMAGE"` after upload succeeds.
6. Add send reliability:
   - Outgoing messages appear immediately as `sending`.
   - Server receipt turns them into `success`.
   - Timeout or error turns them into `failed`.
   - Failed messages can retry.
7. Preserve compatibility:
   - Existing TEXT messages still display.
   - Existing friend alias frames keep working.
   - Optional new fields do not break older payloads.

## Non-Goals

These are not part of Phase 1:

- Cloud-drive file cards in chat.
- Save chat files to cloud-drive.
- Chat video playback from file cards.
- Conversation pinning.
- Do-not-disturb.
- Global chat history search.
- Read receipts.
- Full offline sync engine.
- Group chat.

## Protocol Design

### Reused Frames

`0x50`, `0x51`, `0x52`, and `0x54` must be extended with optional fields instead of replaced.

#### Chat Send Request: `0x50`

Existing fields remain:

```json
{
  "receiverId": 123,
  "content": "hello",
  "msgType": "TEXT"
}
```

Phase 1 optional fields:

```json
{
  "clientMsgId": "local-uuid",
  "quoteMsgId": 456,
  "quoteMsgContent": "quoted preview",
  "quoteMsgSenderName": "sender display name"
}
```

Rules:

- `clientMsgId` is generated on the client before sending and is required for reliable local state matching.
- `quote*` fields are optional.
- Emoji stays plain Unicode text in `content`.
- For images, `msgType` is `IMAGE`; `content` must be a compact JSON string or stable file identifier produced by the existing upload flow. The implementation plan must verify current backend image-message support before enabling the final send path.

#### Chat Push: `0x51`

Existing fields remain:

```json
{
  "messageId": 789,
  "senderId": 123,
  "content": "hello",
  "msgType": "TEXT",
  "avatar": "...",
  "gmtCreated": 1234567890
}
```

Phase 1 optional fields:

```json
{
  "clientMsgId": "local-uuid-if-known",
  "quoteMsgId": 456,
  "quoteMsgContent": "quoted preview",
  "quoteMsgSenderName": "sender display name"
}
```

#### Chat Receipt: `0x52`

Current field:

```json
{
  "messageId": 789,
  "status": "success"
}
```

Phase 1 adds:

```json
{
  "clientMsgId": "local-uuid",
  "message": "optional error message"
}
```

The client matches receipt by `clientMsgId` first, then by `messageId` as fallback.

#### Chat History Response: `0x54`

Each history item must accept optional quote and deletion-state fields:

```json
{
  "quoteMsgId": 456,
  "quoteMsgContent": "quoted preview",
  "quoteMsgSenderName": "sender display name",
  "deleted": false,
  "retracted": false
}
```

The client treats absent fields as default false or nil.

### New Chat Action Frames

Do not use `0x57` or `0x58`.

| Frame | Meaning |
| --- | --- |
| `0x59` | `chatMessageActionReq` |
| `0x5A` | `chatMessageActionResp` |
| `0x5B` | `chatMessageActionPush` |

#### Action Request: `0x59`

```json
{
  "action": "delete_local",
  "messageId": 789,
  "friendId": 123
}
```

```json
{
  "action": "retract",
  "messageId": 789,
  "friendId": 123
}
```

Rules:

- `delete_local` hides the message for the current user only.
- `retract` marks the message retracted for both sides.
- The server must validate ownership and the retract time window.

#### Action Response: `0x5A`

```json
{
  "code": 200,
  "message": "ok",
  "action": "retract",
  "messageId": 789,
  "friendId": 123
}
```

#### Action Push: `0x5B`

```json
{
  "action": "retract",
  "messageId": 789,
  "friendId": 123,
  "notifyText": "对方撤回了一条消息"
}
```

The receiver updates the visible message into a retracted placeholder.

## Client Architecture

Phase 1 must introduce focused chat files under `chat-storage/Views/Chat/` and `chat-storage/Services/Chat/` while preserving the current `SocketManager` entry points.

Suggested components:

| Component | Responsibility |
| --- | --- |
| `ChatDetailView` | Conversation shell and state orchestration. |
| `ChatMessageListView` | Scrollable message list, pagination, scroll-to-bottom behavior. |
| `ChatMessageRow` | One message row, including avatar, bubble, status, context menu. |
| `ChatBubbleView` | Text, emoji, quote block, image placeholder rendering. |
| `ChatInputBar` | Text input, emoji button, paste handling, send button. |
| `MacChatTextView` | AppKit-backed text view for Enter behavior, caret insertion, paste interception. |
| `EmojiPickerPanel` | Emoji categories, recent emoji, insertion callback. |
| `ImageSendPreview` | Preview captured image before upload/send. |
| `ChatMessageStore` | Local in-memory message mutation helpers. |
| `ChatSendCoordinator` | Outgoing message lifecycle: sending, receipt, timeout, retry. |

`MainChatStorage.swift` must keep only high-level composition and must not own message-row or input internals after this phase.

## Client Data Model

`ChatMessage` must support:

- `localId`: UUID string for messages not yet confirmed.
- `messageId`: server ID when available.
- `clientMsgId`: sent with `0x50`, echoed by `0x52`.
- `content`.
- `type`: `TEXT`, `IMAGE`, `FILE`, `SYSTEM`.
- `sendStatus`: `sending`, `success`, `failed`, `retracted`.
- `quote`: optional quote summary.
- `createdAt`.
- `errorMessage`: optional.

DTOs in `TransferModels.swift` must be extended with optional fields only. Decoding must stay tolerant because current backend fields have mixed integer/string behavior.

## Data Flow

### Send Text Or Emoji

1. User enters text or inserts emoji.
2. Client creates `clientMsgId`.
3. Client appends local message with `sending`.
4. Client sends `0x50`.
5. Client starts a receipt timeout.
6. On `0x52 success`, update matching local message to `success` and store `messageId`.
7. On timeout or error, mark local message `failed`.
8. Retry reuses message content but sends a new attempt with a new timeout; it may reuse the same `clientMsgId` only if the server supports idempotency. Otherwise use a new `clientMsgId` and replace local tracking.

### Quote Reply

1. User chooses quote from a message context menu.
2. Input bar shows quote preview.
3. Send request includes quote fields.
4. Push/history render quote block if fields exist.
5. If the quoted message later retracts, the quote block can stay as a historical summary.

### Delete Local

1. User chooses delete locally.
2. Client hides the message optimistically.
3. Client sends `0x59 action=delete_local`.
4. If server fails, client restores message and shows error.

### Retract

1. User chooses retract.
2. Client replaces message with a retracted placeholder optimistically.
3. Client sends `0x59 action=retract`.
4. Server validates ownership and time window.
5. Server replies `0x5A`.
6. Server pushes `0x5B` to the peer if online.
7. History returns the message as retracted or excludes content.

### Paste Image

1. User presses Cmd+V in `MacChatTextView`.
2. Text view detects an image on the pasteboard and prevents normal text paste.
3. Client shows `ImageSendPreview`.
4. On confirm, upload image through existing file transfer service.
5. After upload returns `fileId`, send `0x50` with `msgType=IMAGE` and content containing the image reference.
6. If upload fails, no chat message is sent.

## Error Handling

- Socket disconnected: new outgoing messages are blocked or marked failed with a clear retry option.
- Receipt timeout: mark outgoing message failed without removing it.
- Duplicate receipt: ignore if already success.
- Unknown action push: log and ignore.
- Unsupported image backend: show a user-facing failure and keep the image preview available for retry.
- Retract denied: restore original content if it was optimistically hidden.
- Local delete denied: restore original message.
- Emoji insertion failures must not affect text input; fall back to appending at the end.

## Testing And Verification

### Client Unit/Debug Checks

- `FrameTypeEnum` contains `0x59`, `0x5A`, `0x5B` and keeps existing `0x57`, `0x58`.
- Optional DTO fields decode when present and absent.
- `ChatSendCoordinator` transitions:
  - sending -> success
  - sending -> failed on timeout
  - failed -> sending on retry
- Emoji insertion updates text at caret.
- Shift/Option+Enter inserts newline; Enter sends.
- Paste image path does not paste binary noise into the text field.

### Backend Verification

- JDK 8 only for `net-server`.
- `mvn test` or focused compile must pass with Zulu JDK 8.
- Existing login, friend list, alias update, file list, upload, thumbnail, and video playback must remain unaffected.
- New frames must not collide with `0x57/0x58`.

### Manual End-To-End

1. Login as `18806504525`.
2. Open one friend chat.
3. Send text with emoji.
4. Verify sending -> success.
5. Simulate server timeout or disconnect and verify failed + retry.
6. Quote reply and reload history.
7. Copy message text.
8. Delete locally and reload history.
9. Retract a sent message and verify peer push if a second client is available.
10. Paste an image, confirm preview, upload, and send as `IMAGE` after backend support is verified. If backend support is not ready, keep the preview and return a clear failure without sending an invalid chat message.

## Rollout Plan

1. Implement protocol constants and DTO optional fields.
2. Extract chat UI components without changing behavior.
3. Add reliable send coordinator and receipt matching.
4. Add emoji/input improvements.
5. Add message context menu with copy and quote.
6. Add delete/retract protocol handlers.
7. Add paste image flow behind a readiness check.
8. Run regression tests for login, friends, cloud files, thumbnails, upload, and video playback.

## Compatibility Constraints

- Do not reuse `0x57` or `0x58`.
- Do not remove existing friend alias behavior.
- Do not change file upload/download frame values.
- Do not change video streaming HTTP Range behavior.
- Do not require DB schema changes for pure client features.
- Any DB schema additions for quote, client message ID, or deletion state must be additive and nullable.
- Old chat records without new fields must still display.
