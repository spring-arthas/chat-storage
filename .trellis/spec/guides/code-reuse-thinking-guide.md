# 代码复用思考指南

> **目的**：在写新代码之前，先确认仓库里是不是已经有相同或相近的实现，避免出现第二套协议处理、第二套状态同步、第二套 UI 行为。

---

## 这个项目里“重复代码”的真实危害

在这个仓库里，重复代码不只是“丑”，它会直接造成行为不一致：

- 一处兼容了 `success` / `code` 双格式响应，另一处没有兼容
- 一处做了 `MainActor` 切换，另一处直接在后台线程改 `@Published`
- 一处恢复了 bookmark，另一处忘了恢复，导致文件权限失效
- 一处重命名文件后刷新列表，另一处只弹成功提示，不刷新 UI
- 一处把逻辑写进 `SocketManager`，另一处在 View 里直接重写一遍

结果就是：

- 修一个 bug，另一个同类流程还坏着
- 相似功能表现不同，用户感知混乱
- 代码越来越难判断“哪份才是权威实现”

---

## 写新代码前先做的事

### 第一步：先搜，不要先写

优先使用 `rg`：

```bash
# 搜函数名或动作名
rg "renameFile|deleteFile|sendFrameAndWait|bookmark" chat-storage .trellis/spec

# 搜相近的日志、状态、错误文案
rg "重命名成功|下载中|已暂停|无法解析响应" chat-storage

# 搜已有状态变量或 UI 流程
rg "showing.*Dialog|isLoading|alertMessage" chat-storage/MainChatStorage.swift
```

### 第二步：问这几个问题

| 问题 | 如果答案是“是” |
|------|----------------|
| 仓库里已经有相似函数吗？ | 优先复用或扩展，不要平行再写一份 |
| 这个模式在别处已经出现 2 次以上吗？ | 应该抽象或统一风格 |
| 这是现有 DTO / 错误处理 / 日志格式的变种吗？ | 沿用现有模式，不要自创格式 |
| 我是不是正在从别的文件复制代码？ | 先停下来，判断能不能抽共享逻辑 |
| 我新增的状态是不是和已有状态源重复？ | 先确认唯一数据源应该放在哪 |

---

## 这个项目里最容易重复的几类代码

### 1. 帧请求发送模式

典型重复点：

- 构造请求结构体
- `JSONEncoder().encode(...)`
- 构造 `Frame`
- `sendFrameAndWait(...)`
- 解析 `success` / `code`

如果你要新增一个请求函数，先看：

- `AuthenticationService.swift`
- `DirectoryService.swift`
- `SocketManager.swift`

要点：

- 同一类功能保持同一种请求组织方式
- 不要一处用 `FrameBuilder`，另一处随手拼 `Data`，再一处直接用字典，除非确有必要
- 同类响应的错误处理要一致

### 2. 响应解析与兼容逻辑

这个项目里服务端响应并不完全统一，常见兼容点包括：

- `success: Bool`
- `code: Int`
- `message` / `msg`
- `Int` / `String` 混合字段

危险写法：

- 每个函数都手写一遍略有差异的响应解析

更稳妥的做法：

- 优先复用已有 `ResponseWrapper`
- 参考 `FileDto`、`UserDO`、`FriendDto` 的容错解码方式
- 如果必须写新兼容逻辑，风格要和现有实现一致

### 3. 状态文案与 UI 行为

高频重复点：

- 任务状态：`上传中`、`下载中`、`暂停`、`已完成`、`失败`
- 弹窗状态：`showing...Dialog`
- 加载态：`isLoading...`
- 操作后刷新：重命名、删除、创建目录、处理好友申请

危险写法：

- 新增一套状态文案或刷新策略，但不和原流程对齐

更稳妥的做法：

- 优先沿用现有状态命名
- 操作成功后的 UI 回刷路径要和同类功能一致
- 颜色、文案、状态映射优先复用已有主题和 helper

### 4. bookmark 与本地路径恢复

这个项目在 macOS 上有明显的文件权限恢复约束。

高风险重复点：

- 生成 bookmark
- 恢复 bookmark
- `startAccessingSecurityScopedResource()`
- 持久化文件路径 / 下载目录

危险写法：

- 新建本地文件访问流程时，直接保存路径字符串，不走 bookmark

更稳妥的做法：

- 先复用 `PersistenceManager` 与下载目录相关现有流程
- 如果新增本地文件能力，优先接入已有 bookmark 模式

### 5. 视图里直接访问 `.shared`

仓库中已经形成了一部分状态注入约定：

- `SocketManager` / `AuthenticationService` 通过 `@EnvironmentObject`
- 部分局部单例在 `MainChatStorage` 中以 `@StateObject` 持有

危险写法：

- 在某个新 View 里直接 `SocketManager.shared` 再来一套读取和更新

更稳妥的做法：

- 先看现有注入方式
- 能通过环境对象拿的，不要自己重新抓单例

---

## 什么时候应该抽象

适合抽象的情况：

- 同一段逻辑已经出现 3 次以上
- 这段逻辑一旦出错，影响面很广
- 这段逻辑本身就包含响应兼容、错误处理、状态切换等复杂细节
- 多个功能必须共享同一规则，不能接受轻微行为漂移

不适合急着抽象的情况：

- 只用一次
- 逻辑非常短，而且上下文强绑定
- 抽象后反而会隐藏协议细节，降低可读性

这个项目里要特别注意：**不要为了“看起来更优雅”而做过度抽象。**

比起抽一个很大的通用层，更重要的是：

- 找到真正重复的部分
- 抽到正确的位置
- 不要破坏现有调用链

---

## 这个项目里“先复用”的优先检查清单

写新逻辑前，先看看这些地方是不是已经有现成模式：

- 协议请求 / 响应：`chat-storage/SocketManager.swift`
- 文件 / 目录操作：`chat-storage/Services/DirectoryService.swift`
- 传输任务状态：`chat-storage/Services/TransferTaskManager.swift`
- DTO 容错解码：`chat-storage/Models/do/FileDto.swift`、`chat-storage/Models/do/UserDO.swift`、`chat-storage/Services/TransferModels.swift`
- 视图状态组织：`chat-storage/MainChatStorage.swift`
- 主题与状态色：`chat-storage/MainChatStorage.swift`
- bookmark / 持久化：`chat-storage/Persistence.swift`、`chat-storage/Services/DirectoryService.swift`

---

## 批量修改后的自检

如果你一次改了多个文件，提交前至少做这几件事：

1. 搜索同类关键词，确认没有漏改。
2. 检查同类流程是否仍保持一致。
3. 判断这次改动是否暴露了一个应该抽出的共享模式。
4. 如果你复制过代码，再问一遍：这份复制是不是还能消掉。

建议命令：

```bash
rg "关键词" chat-storage .trellis/spec
```

---

## 本项目特有的高风险提示

### 看起来“相似”，其实不能随便复用

有些流程长得很像，但不能盲目抽成一个函数：

- 普通文件下载 vs 视频流下载
- 单次请求响应 vs 持续流式处理
- 云盘文件列表刷新 vs 好友列表刷新
- 本地目录路径记录 vs 安全书签恢复

判断标准不是“代码像不像”，而是：

- 生命周期是否一致
- 错误处理是否一致
- 状态更新是否一致
- 调用方是否需要知道不同语义

### 遗留兼容文件不要误判成“可删除重复代码”

下面这类文件虽然是壳或兼容层，但不要看到“重复”就直接删：

- `SocketManager+FrameHandling.swift`
- `Services/FileTransferService.swift`
- `Models/DirectoryItem.swift`
- `Models/FileDto.swift`
- `ContentView.swift`

它们可能仍承担 Xcode 引用兼容、历史占位或迁移过渡作用。

---

## 提交前检查单

- [ ] 先搜索过现有实现，而不是直接开写
- [ ] 没有复制出第二套近似协议 / 状态 / 解析逻辑
- [ ] 同类请求的错误处理和响应解析保持一致
- [ ] 状态文案、刷新行为、主题映射没有偷偷分叉
- [ ] 新增本地文件访问逻辑时，确认是否需要 bookmark 支持
- [ ] 没有在 View 中无必要地直接抓 `.shared`

---

**核心原则**：这个项目最危险的不是“没有实现”，而是“已经有一份实现，你又写了半套新的”。
