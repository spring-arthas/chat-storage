# 类型安全

> 当前项目前端侧在 DTO、输入校验、响应解析边界上的真实类型约定。

---

## 概述

这个项目使用 Swift 强类型体系和 `Codable` 作为主要数据模型基础，但并不是所有服务端返回都能直接靠“理想的强类型模型”一次解完。

当前实际情况是：

- 能稳定建模的响应，优先用 `Codable`
- 字段名和 Swift 命名不一致时，使用 `CodingKeys`
- 字段类型不稳定时，在 `init(from:)` 中做容错解码
- 结构不稳定的返回，当前仍会退回字典解析

因此，本项目的类型安全不是“绝不碰字典”，而是“优先强类型，在边界处对不稳定响应做受控降级”。

---

## 当前主要类型组织方式

| 类别 | 位置 | 说明 |
|------|------|------|
| 帧协议类型 | `chat-storage/Models/frame/` | `Frame`、`FrameParser`、`FrameTypeEnum` 等 |
| 服务端实体 / DTO | `chat-storage/Models/do/` | `UserDO`、`FileDto` |
| 请求体 | `chat-storage/Models/request/` 或函数内联 | 如 `UserRequest`，或 `DirectoryService` 内联请求结构体 |
| 好友 / 聊天 / 传输 DTO | `chat-storage/Services/TransferModels.swift` | 当前这类模型集中在这里 |
| 输入校验工具 | `chat-storage/InputValidator.swift` | 用户输入合法性判断 |

### 需要特别注意的历史现状

- `chat-storage/Models/DirectoryItem.swift` 是废弃占位文件
- `chat-storage/Models/FileDto.swift` 也是废弃占位文件
- 实际使用的 `DirectoryItem` 类型定义在 `chat-storage/Models/do/FileDto.swift`

不要只看文件名判断真实类型位置。

---

## `CodingKeys` 映射

服务端字段名和 Swift 命名不一致时，当前项目主流使用 `CodingKeys` 映射。

典型例子：

```swift
enum CodingKeys: String, CodingKey {
    case id = "userId"
    case username = "userName"
    case nickname = "nickName"
    case email = "mail"
}
```

这在 `UserDO` 中很典型，也适用于后续新增的稳定 DTO。

### 建议

- 只要服务端字段名和 Swift 命名不同，就显式写 `CodingKeys`
- 不要靠“字段刚好同名”赌后端永远不变

---

## 容错解码

当前服务端某些字段存在不稳定情况，例如：

- `Int64` / `String` 混用
- `message` / `msg` 混用
- `success` / `code` 混用

因此项目里已经有多处容错解码逻辑。

### `FileDto`

`FileDto` 会对以下字段做容错：

- `id`
- `pId`
- `fileSize`

### `FriendDto`

`FriendDto` 会对：

- `latestUnreadMsg`
- 各种后备字段名

进行兼容读取。

### `ResponseWrapper<T>`

当前项目中的通用响应包装器位于 `UserDO.swift` 底部，主要处理：

- `success`
- `code`
- `msg`

但要注意：**并不是所有服务都统一用 `ResponseWrapper<T>`**。

对于结构不稳定的返回，当前代码里仍有不少地方直接走：

- `FrameParser.decodeAsDictionary(...)`
- `JSONSerialization`

这属于现状，不应在文档里被抹掉。

---

## 请求体建模现状

### 一次性请求体

在 `DirectoryService.swift` 中，很多请求体会直接在函数内部定义：

```swift
struct RenameDirRequest: Codable {
    let id: Int64
    let dirName: String
}
```

这是当前项目中很常见的方式，适合只在单处使用的请求体。

### 重复使用或语义明确的请求体

项目中也存在顶层请求体类型，例如：

- `UserRequest`
- `FileMetaRequest`
- `EndUploadRequest`

因此规则不是“一律内联”，而是：

- 单点使用时内联
- 复用或语义明确时顶层定义

---

## 输入校验

前端用户输入校验当前主要依赖 `InputValidator.swift`。

已覆盖内容包括：

- 中国大陆手机号
- 邮箱格式
- 用户名（手机号或邮箱）
- 密码长度
- 错误提示文本生成

典型使用位置：

- `LoginView`
- `RegisterView`

### 规则

- 视图层负责基础输入合法性校验
- 服务层负责协议和响应边界
- 不要把简单输入校验塞进协议层或 DTO 解码层

---

## 何时允许使用字典解析

当前项目允许在以下场景使用字典解析：

- 服务端返回结构不稳定
- 某些字段只有运行时才能判断结构
- 需要兼容旧格式和新格式混杂

常见形式：

```swift
guard let dict = try? FrameParser.decodeAsDictionary(responseFrame) else {
    throw DirectoryError.invalidResponse("无法解析响应为字典")
}
```

### 但要注意

- 只有在边界处才允许这样做
- 一旦结构稳定，应尽量回归 `Codable`
- 不要把 `[String: Any]` 继续传到视图层

---

## 当前项目中的类型安全风险点

### 1. 文件名相同但真实类型位置不同

例如 `DirectoryItem`、`FileDto` 的真实实现并不在看起来最直观的文件里。

### 2. 服务端格式兼容不统一

同一类接口未必都返回完全统一的 JSON 结构。

### 3. 过早假设所有返回都能强类型一次解完

这会导致你写出一份“理想 DTO”，但一接真实返回就失败。

### 4. 用 `Any` 继续向上层扩散

字典解析只是协议边界兜底，不应该扩散到整个视图层。

---

## 检查单

- [ ] 服务端字段名不一致时已显式写 `CodingKeys`
- [ ] 类型不稳定字段已做容错解码
- [ ] 输入校验仍留在前端入口层
- [ ] `[String: Any]` 没有向视图层扩散
- [ ] 没有误用废弃占位文件中的类型定义

---

**核心原则**：优先强类型，但承认服务端边界并不总是稳定；类型安全应建立在真实响应现状之上。
