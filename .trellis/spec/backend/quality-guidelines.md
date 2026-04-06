# 质量规范

> 当前项目在服务层、协议层、持久化层开发时应遵守的现实质量边界。

---

## 目标

后端层代码的质量重点不在“看起来多优雅”，而在：

- 协议调用正确
- 状态更新一致
- 并发读写安全
- 恢复链路完整
- 不引入新的结构性混乱

---

## 当前项目中的主要实现模式

### 1. 服务组织不是完全统一的

当前代码里同时存在几类服务：

- 典型单例：`SocketManager`、`TransferTaskManager`、`PersistenceManager`、`LocalMediaServer`
- 单页内服务：`DirectoryService`
- 有共享实例也存在局部实例的服务：`AuthenticationService`

因此不要写成“所有服务都必须是私有初始化单例”。这不符合当前现状。

更准确的理解是：

- 核心基础设施大多是单例
- 业务服务不完全统一，需要按已有上下文接入

### 2. 协议请求构造方式不止一种

当前仓库里真实存在三类方式：

- `FrameBuilder.build(type:payload:)`
- 直接 `Frame(type:data:flags:)`
- `JSONSerialization` + `Frame`

因此不能写成“所有请求都必须统一走 `FrameBuilder`”。

更真实的规则是：

- 对结构稳定、可 `Codable` 的请求，优先用 `FrameBuilder`
- 对空 body 请求，直接构造 `Frame`
- 对动态字典或历史接口，允许 `JSONSerialization` 兜底

### 3. 响应解析同样不止一种

当前项目里同时存在：

- `FrameParser.decodePayload(...)`
- `ResponseWrapper<T>`
- `FrameParser.decodeAsDictionary(...)`
- `JSONSerialization`

新增实现时要先看对应链路的既有模式，不要强行统一成文档里想象的单一路径。

---

## 并发与线程安全要求

### `SocketManager`

当前依赖：

- `NSLock` 保护 continuation 映射
- 主 RunLoop 上的流事件

任何修改：

- `activeContinuations`
- `continuationTypeMap`
- `streamHandlers`

相关逻辑时，都必须明确线程边界。

### `TransferTaskManager`

当前依赖：

- `ManagedCriticalState`
- Swift `Task`
- 最大并发数控制

不要绕开 `ManagedCriticalState` 直接改共享任务容器。

### `DirectoryService`

当前标注了 `@MainActor`，说明它很多面向 UI 的状态和调用默认运行在主线程上下文。

### `PersistenceManager`

当前通过：

- `context.perform`
- `context.performAndWait`

来保证 Core Data 访问安全。

---

## 当前项目中的重要现实约束

### 1. 不要误删历史占位文件

当前这些文件仍应保留：

- `SocketManager+FrameHandling.swift`
- `Services/FileTransferService.swift`
- `Models/DirectoryItem.swift`
- `Models/FileDto.swift`

它们可能承担：

- Xcode 引用兼容
- 迁移过渡
- 历史占位说明

### 2. 不要引入新的阻塞式等待

当前代码里已经存在少量 `Thread.sleep(...)`，例如：

- `SocketManager.switchConnection`
- 某些历史下载 / 流控链路

这并不是值得扩散的模式。新增实现应尽量避免进一步增加阻塞调用。

### 3. 不要继续扩大职责已经过重的文件

当前最明显的高复杂度文件包括：

- `SocketManager.swift`
- `DirectoryService.swift`
- `TransferTaskManager.swift`

新增功能时优先判断能否在现有边界下局部提取，而不是继续堆进去。

---

## 类型与协议质量要求

### 1. 服务端边界优先强类型，但接受受控降级

优先顺序应是：

1. `Codable`
2. 容错解码
3. 字典解析兜底

### 2. 不要把动态字典向上层扩散

字典解析应尽量停留在协议边界或服务边界。

### 3. 不要忽略当前接口返回格式不统一的事实

例如：

- `success`
- `code`
- `msg`
- `message`

这类兼容必须写在边界，不要交给 View 层猜。

---

## 持久化质量要求

- 所有任务实体读写优先走 `PersistenceManager`
- 文件权限相关逻辑必须考虑 bookmark
- 下载目录和任务文件 bookmark 不是同一条持久化路径
- 状态值中英混用现状必须兼容

---

## 当前项目中的常见反模式

### 1. 在新服务里重新复制一套请求 / 响应框架

会制造第二套近似协议接入逻辑。

### 2. 用 `try?` 吞掉关键错误

尤其是帧协议和持久化边界。

### 3. 在错误线程直接改共享状态

容易造成 UI 状态不同步或隐藏问题。

### 4. 绕开 `PersistenceManager`

会让数据库访问散落，后续更难维护。

### 5. 只做当前会话可用，不考虑恢复链路

上传 / 下载 / 本地权限 / 目录恢复都要考虑重启后行为。

---

## 测试与验证现状

当前自动化测试覆盖较轻，因此后端层修改后通常需要额外做：

- 手动协议链路验证
- 真实登录 / 文件操作验证
- 任务恢复验证
- 视频流播放与拖动验证

不能因为“编译过了”就判断逻辑可靠。

---

## 代码审查检查单

- [ ] 新增协议调用是否沿用了该链路已有模式
- [ ] continuation / stream handler 是否保证收尾
- [ ] 共享可变状态是否通过现有线程安全机制访问
- [ ] 没有把业务逻辑继续无边界塞进超大文件
- [ ] Core Data 和 bookmark 路径是否处理完整
- [ ] 没有误删或误用历史占位文件
- [ ] 日志、错误、状态刷新是否构成闭环

---

**核心原则**：这个项目后端层最重要的质量，不是“形式统一”，而是“链路正确、状态一致、异常可恢复”。
