# App Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增独立应用设置窗口并从主界面移除下载路径和主题快捷配置。

**Architecture:** 使用 `WindowGroup(id:)` 提供独立设置窗口，`AppStorage` 保存三态外观，现有 `DownloadDirectoryManager` 和 `ConfigServerView` 继续负责目录与网络配置。

**Tech Stack:** Swift 5、SwiftUI、AppKit、XCTest

---

### Task 1: 设置模型和测试
- [ ] 定义三态外观模式和三个设置分类。
- [ ] 验证三态到 `ColorScheme?` 的映射。

### Task 2: 设置窗口
- [ ] 实现侧边栏与外观、下载、网络三个页面。
- [ ] 增加选择目录、Finder 展示、恢复默认和服务器配置入口。

### Task 3: 主界面接入
- [ ] 增加齿轮按钮打开设置窗口。
- [ ] 删除主界面主题按钮和下载目录工具栏。
- [ ] 使用三态外观配置驱动主界面主题。

### Task 4: 验证
- [ ] 运行客户端单元测试和 Debug 构建。
