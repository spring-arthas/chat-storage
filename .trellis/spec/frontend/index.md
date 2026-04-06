# 前端开发规范

> 基于当前 `chat-storage` 项目的 SwiftUI 代码现状整理的前端开发说明。

---

## 概述

这里的“前端”指的是所有直接参与 macOS 界面渲染和交互的 SwiftUI 代码，以及少量与视图强绑定的展示型辅助类型。

这个项目的前端现状有几个关键特点：

- 主要 UI 框架是 SwiftUI，少量能力通过 AppKit 桥接
- 登录后主界面高度集中在 `MainChatStorage.swift`
- 全局共享状态主要来自 `SocketManager` 和 `AuthenticationService`
- 复杂功能没有引入额外状态管理框架，主要依赖 SwiftUI 自带属性包装器
- 视频播放是一个独立子链路，使用 `AVPlayer` + 本地 HTTP 代理

这组文档的目标不是描述理想架构，而是帮助后续开发者和 AI 助手理解**当前仓库真实的前端组织方式**。

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [目录结构](./directory-structure.md) | 当前前端代码分布、文件职责和历史遗留位置 |
| [组件规范](./component-guidelines.md) | SwiftUI 视图的组织方式、注入方式和常见拆分模式 |
| [属性包装器与状态接入](./hook-guidelines.md) | `@State`、`@StateObject`、`@EnvironmentObject`、`@ObservedObject` 等的实际使用方式 |
| [状态管理](./state-management.md) | 全局状态、局部状态、服务状态、任务恢复状态如何分工 |
| [质量规范](./quality-guidelines.md) | 当前项目在视图层应遵守的实现边界和常见反模式 |
| [类型安全](./type-safety.md) | 前端常见 DTO、解码模式、输入校验和类型边界 |

---

## 使用方式

阅读顺序建议如下：

1. 先看 [目录结构](./directory-structure.md)，建立文件级认识。
2. 再看 [组件规范](./component-guidelines.md) 和 [状态管理](./state-management.md)，理解 View 和 Service 的边界。
3. 如果要新增页面、弹窗、列表、播放器或复杂交互，再看 [属性包装器与状态接入](./hook-guidelines.md)。
4. 如果要改 DTO、用户输入、服务端字段映射，再看 [类型安全](./type-safety.md)。
5. 开始改代码前，最后过一遍 [质量规范](./quality-guidelines.md)。

---

## 这套规范特别关注什么

相较于通用 SwiftUI 规范，这个项目更需要关注下面这些现实问题：

- 不要把更多业务逻辑继续堆进 `body`
- 不要在 View 中复制第二套协议调用或状态同步
- 不要误把模板文件或历史占位文件当成真实入口
- 不要让同一份事实在 View、本地状态、共享状态里同时出现多份版本
- 不要忽略视频流、传输队列、好友聊天这些已经存在但组织较分散的能力

---

**核心原则**：尊重当前项目结构，在现有组织基础上做清晰、可维护的增量改动。
