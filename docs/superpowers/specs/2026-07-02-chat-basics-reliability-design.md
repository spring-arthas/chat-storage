# 聊天基础体验与可靠性第一阶段设计

## 目标

第一阶段用于提升 `chat-storage` 的聊天体验，让它更接近一个正常 macOS 即时通讯客户端，同时不影响现有云盘、好友、缩略图、视频播放和文件传输能力。

本阶段包含：

- 消息基础操作。
- Emoji 与输入体验。
- 剪贴板图片发送。
- 消息发送可靠性。
- 对当前庞大的 `MainChatStorage.swift` 做小范围、目标明确的聊天组件拆分。

## 当前上下文

客户端是 SwiftUI macOS 应用，使用自定义二进制帧协议：

```text
Magic(2 字节: FA CE) + Type(1 字节) + Flags(1 字节) + Length(4 字节) + Data(N 字节)
```

当前聊天和好友相关帧号使用情况：

| 帧号 | 当前含义 |
| --- | --- |
| `0x50` | 发送聊天消息请求 |
| `0x51` | 聊天消息推送 |
| `0x52` | 聊天消息回执 |
| `0x53` | 聊天历史请求 |
| `0x54` | 聊天历史响应 |
| `0x55` | 清除未读请求 |
| `0x56` | 清除未读响应 |
| `0x57` | 修改好友备注请求 |
| `0x58` | 修改好友备注响应 |

`0x57` 和 `0x58` 已经用于好友备注修改。第一阶段不能把它们复用于聊天消息操作。

`MainChatStorage.swift` 当前同时承载云盘主界面和大量聊天 UI，文件已经超过 5000 行。第一阶段必须拆分出聚焦的聊天组件，不能继续把聊天逻辑堆回主文件。

## 功能范围

1. 增加消息上下文操作：
   - 复制文本。
   - 本地删除。
   - 在允许条件下双向撤回。
2. 增加引用回复：
   - 从消息菜单选择一条消息作为引用。
   - 在输入框上方展示引用预览。
   - 发送消息时携带引用元数据。
   - 推送消息和历史消息中可以渲染引用信息。
3. 优化输入体验：
   - Enter 发送。
   - Shift+Enter 或 Option+Enter 换行。
   - 输入框高度随内容增长，到达上限后内部滚动。
4. 增加 Emoji：
   - 输入区表情按钮。
   - Emoji 面板。
   - 点击表情后插入到当前光标位置。
   - 本地持久化最近使用表情。
5. 增加剪贴板图片发送：
   - 在聊天输入框中按 Cmd+V 时捕获图片内容。
   - 展示发送预览。
   - 通过现有文件上传链路上传图片。
   - 上传成功后发送 `msgType = "IMAGE"` 的聊天消息。
6. 增加发送可靠性：
   - 发送消息后立即以 `sending` 状态展示在本地。
   - 收到服务端回执后变为 `success`。
   - 超时或失败后变为 `failed`。
   - 失败消息支持重试。
7. 保持兼容：
   - 现有 TEXT 消息仍正常展示。
   - 现有好友备注帧继续工作。
   - 新增字段全部为可选字段，不破坏旧 payload 解析。

## 非目标

以下内容不属于第一阶段：

- 聊天中的云盘文件卡片。
- 将聊天文件保存到云盘。
- 从聊天文件卡片直接播放视频。
- 会话置顶。
- 免打扰。
- 全局聊天记录搜索。
- 已读回执。
- 完整离线同步引擎。
- 群聊。

## 协议设计

### 复用现有帧

`0x50`、`0x51`、`0x52`、`0x54` 必须通过可选字段扩展，不能替换原协议。

#### 发送聊天消息请求：`0x50`

保留现有字段：

```json
{
  "receiverId": 123,
  "content": "hello",
  "msgType": "TEXT"
}
```

第一阶段新增可选字段：

```json
{
  "clientMsgId": "local-uuid",
  "quoteMsgId": 456,
  "quoteMsgContent": "quoted preview",
  "quoteMsgSenderName": "sender display name"
}
```

规则：

- `clientMsgId` 由客户端在发送前生成，用于本地消息状态和服务端回执匹配。
- `quote*` 字段全部可选。
- Emoji 作为普通 Unicode 文本放在 `content` 中，不新增帧。
- 图片消息使用 `msgType = "IMAGE"`；`content` 必须是现有上传流程产出的稳定文件标识，或紧凑 JSON 字符串。实现计划必须先验证当前后端图片消息支持情况，再启用最终发送链路。

#### 聊天消息推送：`0x51`

保留现有字段：

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

第一阶段新增可选字段：

```json
{
  "clientMsgId": "local-uuid-if-known",
  "quoteMsgId": 456,
  "quoteMsgContent": "quoted preview",
  "quoteMsgSenderName": "sender display name"
}
```

#### 聊天消息回执：`0x52`

当前字段：

```json
{
  "messageId": 789,
  "status": "success"
}
```

第一阶段新增：

```json
{
  "clientMsgId": "local-uuid",
  "message": "optional error message"
}
```

客户端优先通过 `clientMsgId` 匹配回执；如果没有 `clientMsgId`，再回退使用 `messageId`。

#### 聊天历史响应：`0x54`

历史消息单条记录必须支持可选引用字段和删除状态字段：

```json
{
  "quoteMsgId": 456,
  "quoteMsgContent": "quoted preview",
  "quoteMsgSenderName": "sender display name",
  "deleted": false,
  "retracted": false
}
```

客户端对缺失字段按默认值处理：布尔字段默认为 `false`，引用字段默认为 `nil`。

### 新增聊天动作帧

不能使用 `0x57` 或 `0x58`。

| 帧号 | 含义 |
| --- | --- |
| `0x59` | `chatMessageActionReq` |
| `0x5A` | `chatMessageActionResp` |
| `0x5B` | `chatMessageActionPush` |

#### 动作请求：`0x59`

本地删除：

```json
{
  "action": "delete_local",
  "messageId": 789,
  "friendId": 123
}
```

双向撤回：

```json
{
  "action": "retract",
  "messageId": 789,
  "friendId": 123
}
```

规则：

- `delete_local` 仅对当前用户隐藏消息。
- `retract` 将消息标记为双方可见的撤回状态。
- 服务端必须校验操作者身份、消息归属和撤回时间窗口。

#### 动作响应：`0x5A`

```json
{
  "code": 200,
  "message": "ok",
  "action": "retract",
  "messageId": 789,
  "friendId": 123
}
```

#### 动作推送：`0x5B`

```json
{
  "action": "retract",
  "messageId": 789,
  "friendId": 123,
  "notifyText": "对方撤回了一条消息"
}
```

接收方收到后，将当前可见消息更新为撤回占位提示。

## 客户端架构

第一阶段必须在 `chat-storage/Views/Chat/` 和 `chat-storage/Services/Chat/` 下引入聚焦的聊天文件，同时保留当前 `SocketManager` 作为网络入口。

建议组件：

| 组件 | 职责 |
| --- | --- |
| `ChatDetailView` | 会话壳层和状态编排。 |
| `ChatMessageListView` | 消息列表、历史分页、滚动到底部。 |
| `ChatMessageRow` | 单条消息行，包括头像、气泡、状态、右键菜单。 |
| `ChatBubbleView` | 文本、emoji、引用块、图片占位展示。 |
| `ChatInputBar` | 文本输入、emoji 按钮、粘贴处理、发送按钮。 |
| `MacChatTextView` | AppKit 封装文本框，用于 Enter 行为、光标插入、粘贴拦截。 |
| `EmojiPickerPanel` | Emoji 分类、最近使用、插入回调。 |
| `ImageSendPreview` | 发送前展示剪贴板图片预览。 |
| `ChatMessageStore` | 本地内存消息变更辅助。 |
| `ChatSendCoordinator` | 发送生命周期：发送中、回执、超时、重试。 |

第一阶段完成后，`MainChatStorage.swift` 必须只保留高层组合逻辑，不能继续拥有消息行或输入框内部实现。

## 客户端数据模型

`ChatMessage` 必须支持：

- `localId`：未确认消息的本地 UUID 字符串。
- `messageId`：服务端消息 ID，可为空。
- `clientMsgId`：随 `0x50` 发送，并由 `0x52` 回执带回。
- `content`：消息内容。
- `type`：`TEXT`、`IMAGE`、`FILE`、`SYSTEM`。
- `sendStatus`：`sending`、`success`、`failed`、`retracted`。
- `quote`：可选引用摘要。
- `createdAt`：创建时间。
- `errorMessage`：可选错误信息。

`TransferModels.swift` 中的 DTO 必须只通过可选字段扩展。解码必须继续保持容错，因为当前后端字段存在整数和字符串混用情况。

## 数据流

### 发送文本或 Emoji

1. 用户输入文本或插入 emoji。
2. 客户端创建 `clientMsgId`。
3. 客户端追加一条 `sending` 状态的本地消息。
4. 客户端发送 `0x50`。
5. 客户端启动回执超时计时。
6. 收到 `0x52 success` 后，通过 `clientMsgId` 匹配本地消息，更新为 `success` 并保存 `messageId`。
7. 超时或错误时，将本地消息更新为 `failed`。
8. 重试时复用消息内容并启动新的发送尝试；只有服务端支持幂等时才复用同一个 `clientMsgId`，否则生成新的 `clientMsgId` 并替换本地追踪关系。

### 引用回复

1. 用户从消息右键菜单选择引用。
2. 输入区展示引用预览。
3. 发送请求携带引用字段。
4. 推送消息和历史消息中如存在引用字段，则渲染引用块。
5. 如果被引用消息后续被撤回，引用块可以保留为历史摘要。

### 本地删除

1. 用户选择本地删除。
2. 客户端乐观隐藏消息。
3. 客户端发送 `0x59 action=delete_local`。
4. 如果服务端失败，客户端恢复消息并展示错误。

### 双向撤回

1. 用户选择撤回。
2. 客户端乐观地将消息替换为撤回占位提示。
3. 客户端发送 `0x59 action=retract`。
4. 服务端校验归属和时间窗口。
5. 服务端返回 `0x5A`。
6. 如果对方在线，服务端向对方推送 `0x5B`。
7. 后续历史消息返回时，该消息必须表现为已撤回，或不再返回原始内容。

### 粘贴图片

1. 用户在 `MacChatTextView` 中按 Cmd+V。
2. 文本框检测剪贴板中存在图片，并阻止默认文本粘贴行为。
3. 客户端展示 `ImageSendPreview`。
4. 用户确认后，通过现有文件传输服务上传图片。
5. 上传返回 `fileId` 后，发送 `0x50`，`msgType=IMAGE`，`content` 中携带图片引用。
6. 如果上传失败，不发送聊天消息。

## 错误处理

- Socket 断开：阻止新消息发送，或将消息标记为失败并提供明确重试入口。
- 回执超时：消息标记为失败，但不移除。
- 重复回执：如果消息已经成功，则忽略。
- 未知动作推送：记录日志并忽略。
- 图片消息后端未支持：展示明确失败信息，保留图片预览供用户重试。
- 撤回被拒绝：如果客户端已乐观隐藏原消息，需要恢复原内容。
- 本地删除被拒绝：恢复原消息。
- Emoji 插入失败不能影响文本输入；失败时回退为追加到文本末尾。

## 测试与验证

### 客户端单元或调试检查

- `FrameTypeEnum` 包含 `0x59`、`0x5A`、`0x5B`，并保留既有 `0x57`、`0x58`。
- DTO 新增可选字段在存在和缺失时都能正常解码。
- `ChatSendCoordinator` 状态流转：
  - `sending -> success`
  - `sending -> failed`，超时时触发
  - `failed -> sending`，重试时触发
- Emoji 能插入到当前光标位置。
- Shift/Option+Enter 换行；Enter 发送。
- 粘贴图片时不会把二进制内容或无意义文本塞进输入框。

### 后端验证

- `net-server` 只能使用 Zulu JDK 8。
- 必须使用 Zulu JDK 8 完成 `mvn test` 或聚焦编译验证。
- 现有登录、好友列表、好友备注、文件列表、上传、缩略图、视频播放不能受影响。
- 新增聊天帧不能与 `0x57/0x58` 冲突。

### 手工端到端验证

1. 使用 `18806504525` 登录。
2. 打开一个好友聊天。
3. 发送带 emoji 的文本。
4. 验证消息从 `sending` 变为 `success`。
5. 模拟服务端超时或断连，验证消息变为 `failed` 且可重试。
6. 发送引用回复并重新加载历史记录。
7. 复制消息文本。
8. 本地删除消息并重新加载历史记录。
9. 撤回一条已发送消息；如果有第二客户端，验证对方收到推送。
10. 粘贴图片、确认预览、上传，并在后端图片消息能力验证通过后发送为 `IMAGE`。如果后端暂未支持，保留预览并返回明确失败，不发送非法聊天消息。

## 发布步骤

1. 实现协议常量和 DTO 可选字段。
2. 抽取聊天 UI 组件，保持原行为不变。
3. 增加可靠发送协调器和回执匹配。
4. 增加 emoji 和输入体验优化。
5. 增加消息右键菜单，先支持复制和引用。
6. 增加删除和撤回协议处理。
7. 在后端能力检查通过后启用粘贴图片发送流程。
8. 回归验证登录、好友、云盘文件、缩略图、上传和视频在线播放。

## 兼容性约束

- 不能复用 `0x57` 或 `0x58`。
- 不能移除现有好友备注行为。
- 不能修改文件上传和下载帧值。
- 不能修改视频在线播放 HTTP Range 行为。
- 纯客户端功能不能要求数据库结构变更。
- 如需为引用、`clientMsgId` 或删除状态增加数据库字段，必须是增量且允许为空。
- 没有新字段的旧聊天记录必须继续正常展示。
