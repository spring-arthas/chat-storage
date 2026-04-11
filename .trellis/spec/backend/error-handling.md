# 错误处理

> 当前项目中服务层和协议层的错误类型、传播路径与常见处理方式。

---

## 概述

本项目整体上使用 Swift 的 `throws` / `async throws` 传递错误，并让上层决定如何展示。

但要注意，当前项目的错误处理并不是“绝对统一”的：

- 有些页面用 `alert`
- 有些页面用页面内错误文本
- 有些局部链路只打印日志再通过状态回传
- 流式处理部分还会用 continuation / handler 收尾

因此理解错误处理时，必须按**链路类型**来区分，而不是假设全仓库都一个模式。

---

## 当前主要错误类型

### `SocketError`

定义于 `SocketManager.swift`，用于传输层错误，例如：

- 连接失败
- 未连接
- 发送失败
- 超时
- 响应无效
- 连接关闭

它对应的是：

- TCP 层
- 请求等待层
- continuation 收尾层

### `FrameError`

定义于 `Models/frame/Frame.swift`，用于协议帧级错误，例如：

- 魔数错误
- 帧类型未知
- 长度不合法
- 数据不完整
- 编码 / 解码失败

### `AuthError`

定义于 `AuthenticationService.swift`，当前包括：

- `loginFailed(String)`
- `registerFailed(String)`
- `connectionError`
- `invalidInput(String)`

### `DirectoryError`

定义于 `DirectoryService.swift`，当前包括：

- `invalidResponse(String)`
- `serverError(code: Int, message: String)`
- `invalidData`

这是目录 / 文件相关业务的主要错误类型。

### `FileTransferError`

也定义在 `DirectoryService.swift` 合并区域中，主要用于上传链路，例如：

- 文件不存在
- 连接丢失
- 服务端错误
- 响应无效

---

## 当前错误传播主路径

### 1. 单次请求响应链路

典型流程：

```text
View
→ Service async throws
→ SocketManager.sendFrameAndWait(...)
→ 解析响应
→ throw 具体错误
→ View catch
```

这类链路常见于：

- 登录
- 注册
- 目录加载
- 文件重命名
- 文件详情查询

### 2. 流式处理链路

典型流程：

```text
Service
→ 注册 stream handler
→ 持续接收帧
→ 中途根据状态决定 resume success / failure
```

这类链路常见于：

- 下载
- 视频流
- 部分聊天或长流处理

它的风险比单次请求更高，因为必须处理：

- 取消
- 超时
- 半路断连
- handler 收尾

---

## 当前项目中的响应错误判断现状

本项目服务端返回格式并不完全统一，当前常见判断方式有：

- `ResponseWrapper<T>.code`
- 字典里的 `success`
- 字典里的 `code`

因此，错误处理的现实规则是：

- 不要假设所有响应都统一
- 先判断当前接口实际使用哪种返回格式
- 对不稳定返回保留兼容分支

### 典型字典解析方式

```swift
guard let dict = try? FrameParser.decodeAsDictionary(responseFrame) else {
    throw DirectoryError.invalidResponse("无法解析响应为字典")
}

if let success = dict["success"] as? Bool, !success {
    let message = dict["message"] as? String ?? "未知错误"
    throw DirectoryError.serverError(code: 500, message: message)
}

if let code = dict["code"] as? Int, code != 200 {
    let message = dict["message"] as? String ?? "未知错误"
    throw DirectoryError.serverError(code: code, message: message)
}
```

---

## View 层当前如何处理错误

### `LoginView` / `RegisterView`

更偏向页面内错误文本，不一定用 alert。

### `MainChatStorage`

大量场景会把错误放进：

- `alertMessage`
- `showingAlert`

然后用 `.alert(...)` 展示。

### `NewFriendView`

会保留本地 `errorMessage` 进行界面内提示。

### 结论

不要写成“顶层 catch 一律弹 alert”，这不符合当前现状。

更准确的说法是：

- 错误通常在 View 层被最终消费
- 但具体展示形式按页面不同而不同

---

## Continuation 与断连收尾

这是当前错误处理里最不能出错的部分之一。

`SocketManager.disconnect()` 当前会在断连时：

- 遍历所有 `activeContinuations`
- 用 `SocketError.connectionClosed` 统一 `resume`
- 清空 continuation 映射

如果遗漏 `resume`，就会造成：

- 调用方永远挂起
- 内存泄漏
- 请求无法结束

因此任何改动 continuation 相关逻辑时，都必须保证所有路径最终都有收尾。

---

## 当前项目中最常见的错误处理失误

### 1. 用 `try?` 吞掉关键错误

在协议和传输层，这通常会让真正失败被静默掩盖。

### 2. 只打印日志，不向上反馈

用户看到“没反应”，但实际底层已经失败。

### 3. 成功路径完整，失败路径不收尾

特别容易出现在：

- continuation
- stream handler
- 下载 / 视频流

### 4. 假设所有接口都只看 `code == 200`

当前仓库里并不成立。

---

## 错误处理建议

新增功能时，至少明确：

1. 这条链路抛什么类型的错误最合适？
2. 出错后由哪一层负责提示用户？
3. 如果是流式处理，中途失败如何收尾？
4. 如果断连，等待中的请求是否都会结束？

---

## 检查单

- [ ] 错误类型是否符合当前链路层级
- [ ] 是否兼容当前接口实际使用的响应格式
- [ ] View 层是否真正消费了错误，而不是只打印日志
- [ ] continuation / stream handler 在失败时一定能结束
- [ ] 没有用 `try?` 把关键协议错误悄悄吞掉

---

**核心原则**：在这个项目里，错误处理最重要的不是“抛错”，而是“所有失败路径都能被看见、被收尾、被反馈”。


## Java Rules Overlay - Exception Strategy

- 领域异常优先使用自定义 `RuntimeException`（带关键业务上下文），避免到处传播通用异常。
- 禁止宽泛 `catch (Exception e)`（除顶层兜底）；禁止吞异常或只记录“失败”而不带主键上下文。
- 对外错误响应禁止泄漏堆栈、SQL 细节、内部路径；内部日志保留完整异常堆栈用于排查。
- 需要返回可空结果时优先 `Optional.orElseThrow(...)` 或显式分支，避免“空值继续流转”。
