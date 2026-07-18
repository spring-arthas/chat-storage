# 上传完成自动刷新文件列表设计

## 目标

每个上传任务收到服务端最终成功响应后刷新当前文件列表；下载任务完成不刷新。多个上传任务在极短时间内连续完成时合并为一次刷新，避免重复请求和列表闪动。

## 数据流

1. `TransferTaskManager` 完成上传并取得 `fileId`。
2. 切换到 `MainActor` 发布 `uploadTaskDidComplete` 通知，附带 `taskId`、`fileId` 和 `targetDirId`。
3. `MainChatStorage` 在主线程接收通知，取消尚未执行的刷新任务。
4. 重新启动 300 毫秒延迟任务，延迟结束后调用 `loadCurrentFiles()`。
5. 下载完成、上传失败、暂停和取消不发布通知。

## 线程约束

- 文件传输继续在后台任务执行。
- NotificationCenter 通知在 `MainActor` 发布。
- SwiftUI 的 `@State` 和文件列表刷新只在主线程触发。

## 验证

- 上传类型允许发布刷新事件，下载类型禁止。
- 通知名称保持独立，不复用聊天通知。
- chat-storage 单元测试和 Debug 编译通过。
