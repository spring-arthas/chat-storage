# 聊天媒体消息与可靠性第二阶段设计

## 目标

第二阶段用于闭环第一阶段留下的图片消息链路，并补强聊天发送可靠性。实现后，用户可以在聊天输入框粘贴图片、上传到现有文件存储、发送 `IMAGE` 消息、在聊天记录中看到图片缩略图，并在历史消息中恢复展示。

本阶段必须继续保护现有功能：

- 不改变云盘文件列表、上传、下载、缩略图、视频在线播放主链路。
- 不复用好友备注帧 `0x57/0x58`。
- net-server 继续使用本地 Zulu JDK 8 编译测试。
- 数据库新增字段只能作为可空兼容字段；缺字段时不得影响 TEXT 消息、登录、好友列表和云盘能力。

## 范围

### 必做

1. 图片消息端到端：
   - Cmd+V 捕获图片。
   - 展示发送前预览。
   - 点击发送后通过独立上传连接上传图片。
   - 上传成功后发送 `msgType = "IMAGE"` 聊天消息。
   - 聊天气泡中显示图片缩略图。
   - 历史消息恢复后仍能显示图片缩略图。

2. 附件元数据：
   - `IMAGE` 消息的 `content` 使用紧凑 JSON。
   - JSON 至少包含 `fileId`、`fileName`、`fileSize`、`mimeType`。
   - 客户端解析失败时显示 `[图片]` 占位，不让整条聊天记录解析失败。

3. 可靠性：
   - 图片上传失败时不发送聊天消息，并显示明确失败原因。
   - 图片消息发送后继续使用第一阶段的 `clientMsgId` 回执匹配。
   - 服务端在存在 `client_msg_id` 字段时按 `sender_id + client_msg_id` 幂等保存，避免重试重复消息。
   - 服务端在存在引用字段时保存并返回引用字段；缺字段时降级为只保存正文。

4. 撤回和本地删除：
   - 撤回继续校验操作者必须是发送者。
   - 本地删除如数据库没有按用户隐藏字段，则保持现有兼容降级，不做破坏性表结构假设。

### 非目标

- 聊天文件卡片完整发送。
- 离线同步引擎。
- 群聊、已读回执、会话置顶、免打扰、全局搜索。
- 视频聊天消息直接在线播放。

## 客户端设计

### 附件模型

新增 `ChatImageAttachment`，负责把聊天图片附件编码到 `content`：

```json
{
  "kind": "image",
  "fileId": 123,
  "fileName": "chat-image-uuid.png",
  "fileSize": 45678,
  "mimeType": "image/png"
}
```

该模型放在 `chat-storage/Services/Chat/`，只负责编码、解码、构建 `DirectoryItem`。解码失败返回 `nil`，UI 降级显示占位。

### 图片上传

新增聊天附件上传服务：

- 将 `NSImage` 写入临时 PNG 文件。
- 创建独立 `SocketManager` 连接当前服务主机的上传端口 `10087`。
- 调用现有 `FileTransferService.uploadFile`。
- 上传完成后调用 `FileThumbnailService.remapToFileId(taskId:fileId:)`，保持缩略图逻辑和云盘上传一致。
- 上传连接完成后断开，不影响主聊天连接 `10086`。

上传目标目录先使用根目录 `dirId = 0`。如果后续需要隐藏聊天附件目录，再单独设计目录策略。

### 聊天气泡展示

`ChatMessageRow` 对 `msgType == "IMAGE"` 的消息：

- 解析 `ChatImageAttachment`。
- 通过 `FileThumbnailService.thumbnail(for:)` 加载缩略图。
- 显示固定尺寸图片气泡，加载中显示进度占位，失败显示 `[图片]`。
- 点击缩略图打开系统图片预览窗口。

TEXT 消息保持原逻辑。

### 发送流程

1. 用户粘贴图片，输入区展示图片预览。
2. 用户点击发送图片。
3. 客户端进入上传中状态。
4. 上传成功拿到 `fileId`。
5. 构造 `ChatImageAttachment` JSON。
6. 调用现有 `SocketManager.sendChatMessage(..., msgType: "IMAGE")`。
7. 清空图片预览。
8. 等待 `0x52` 回执更新发送状态。

## 服务端设计

### 幂等保存

扩展 `ChatMessageService.sendClientMessage` 参数：

- `clientMsgId`
- `quoteMsgId`
- `quoteMsgContent`
- `quoteMsgSenderName`

服务端启动时或首次使用时探测 `user_friend_message` 是否存在以下列：

- `client_msg_id`
- `quote_msg_id`
- `quote_msg_content`
- `quote_msg_sender_name`

存在时写入并查询；不存在时跳过这些字段，保证旧表可运行。

幂等规则：

- 当 `clientMsgId` 非空且表存在 `client_msg_id` 列时，先按 `sender_id + client_msg_id + del='N'` 查询。
- 如果已存在，直接返回已有消息，不重复插入。
- 如果不存在，再插入新消息。

### 历史消息

`0x54` 历史响应继续保留原字段，并在列存在时补充：

- `clientMsgId`
- `quoteMsgId`
- `quoteMsgContent`
- `quoteMsgSenderName`

缺列时返回空值，不影响客户端解析。

## 测试

客户端：

- 测试 `ChatImageAttachment` JSON 编解码。
- 测试 IMAGE 消息可以构建 `DirectoryItem`。
- 测试 TEXT 渲染逻辑不被 IMAGE 解析影响。
- 跑完整 `xcodebuild test`。

服务端：

- 测试聊天动作帧仍不占用 `0x57/0x58`。
- 测试 `clientMsgId` 幂等查询 SQL 或服务逻辑。
- 测试缺少可选列时 TEXT 消息保存不失败。
- 使用 Zulu JDK 8 跑 `mvn test`。
