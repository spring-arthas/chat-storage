# 视频流优化：暂停后继续拉流 + 本地缓存快速 seek

## Goal

当用户播放视频并点击暂停后，后台应继续从服务端拉取视频数据并缓存到本地；等全部数据拉取完成后，拖动进度条可以无延迟快速跳转，不再重新发起网络请求。

## What I already know

* AVPlayer 通过 HTTP Range Request 向 `LocalMediaServer`（本地 127.0.0.1）请求视频片段
* `LocalMediaServer` 每次请求都创建新的 `VideoStreamingService`（独立 SocketManager 连接），实时转发帧数据
* AVPlayer **暂停**后会关闭 HTTP 连接，触发 `NWConnectionVideoStreamDelegate.cancel()` → `VideoStreamingService.cancel()` → 拉流终止
* AVPlayer **seek** 后会发起新的 Range Request，重新从服务端拉取目标区间数据（慢）
* 当前架构：完全按需拉流，无任何本地缓存层

## Assumptions (temporary)

* 服务端支持从任意 offset 开始的流请求（`startOffset` 参数），已验证
* 文件大小通过 `fileSize` 参数预先已知
* 视频文件大小适合写入本地临时目录（macOS tmp 通常几十 GB 可用）

## Open Questions

* 视频文件是否有大小上限（超大文件是否仍需完整缓存）？还是 MVP 先不限制，超大文件同样缓存？

## Requirements (evolving)

* 视频开始播放时，立即在后台发起从头（offset=0）的完整拉流任务，写入本地临时文件
* AVPlayer 发起 Range Request 时：
  * 若请求区间已缓存 → 直接从临时文件读取返回，无需网络请求
  * 若请求区间尚未缓存 → 等待后台拉流追上，或仍走实时拉流（fallback）
* 暂停不中断后台拉流；关闭播放窗口时才停止拉流并清理临时文件
* 全部数据拉取完成后，所有 Range Request 均从本地文件服务，seek 无延迟

## Acceptance Criteria (evolving)

* [ ] 点击暂停，后台继续拉流（日志可见 dataFrame 持续到达）
* [ ] 全量拉取完成后，拖动进度条不触发新的网络请求
* [ ] 关闭播放窗口，临时文件被清理
* [ ] 已缓存区间的 seek 响应时间 < 200ms（相比当前数秒的重新拉流）

## Definition of Done

* 功能在 macOS Debug build 验证通过
* 无内存泄漏（deinit 正常触发，临时文件被清理）
* 不影响现有上传/下载功能

## Out of Scope (explicit)

* 跨会话持久化缓存（重启 App 后缓存不保留，MVP）
* 多视频同时后台预加载
* 弱网降级（网络中断时自动重连继续拉流，暂不做）

## Technical Notes

### 核心文件

| 文件 | 职责 | 改动方向 |
|------|------|---------|
| `LocalMediaServer.swift` | HTTP 代理，分发 Range 请求 | 加入缓存查询层 |
| `VideoStreamingService.swift` | 单次流请求逻辑 | 支持全量后台拉流（不依赖 HTTP 连接存活） |
| `StreamingVideoPlayer.swift` | 播放 UI + ViewModel | 触发后台拉流 task |

### Research Notes

#### 类似方案参考

* **VLC / FFmpeg**: 先下载到本地 temp，再用 local file URL 播放
* **AVAssetResourceLoader**: Apple 官方方案，可拦截 AVPlayer 的每一个 Range 请求并自定义数据源，支持写缓冲
* **当前架构 (LocalMediaServer + NWListener)**: 自定义 HTTP 代理，已经有 Range 解析，只缺缓存层

#### 可行方案

**方案 A：磁盘缓存 + 独立后台拉流（推荐）**

* 播放启动时创建 `VideoStreamCache`，管理一个临时文件（FileHandle 写入）和一个"已写入字节数"计数器
* 后台 Task 持续从 offset=0 拉流，每收到 dataFrame 就追加写入临时文件
* `LocalMediaServer` 处理 Range Request 时先查 cache：若区间已写入 → 从文件读取返回；否则阻塞等待（短轮询或 async/await 通知）
* AVPlayer 暂停 → HTTP 连接断，后台拉流任务不受影响，继续写文件
* 优点：架构清晰，文件 I/O 高效，seek 服务简单
* 缺点：磁盘写入有延迟（可接受，顺序写极快）

**方案 B：内存缓冲**

* 数据写入 `[Data]` 或连续 `Data` 对象
* 优点：读取更快（无磁盘 I/O）
* 缺点：大文件会耗尽内存，macOS 会触发内存压缩甚至 OOM

**方案 C：切换为 AVAssetResourceLoader**

* 完全替换 `LocalMediaServer`，改用 Apple 的资源加载拦截 API
* 优点：更接近 Apple 官方推荐
* 缺点：改动量大，需重构整个视频播放链路，风险高

## Decision (ADR-lite)

**Context**: 需要在不大幅重构现有 LocalMediaServer 架构的前提下，增加后台持续拉流 + 磁盘缓存能力

**Decision**: 待用户确认

**Consequences**: TBD
