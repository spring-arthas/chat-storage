# Journal - veneno (Part 1)

> AI development session journal
> Started: 2026-04-03

---



## Session 1: 视频暂停继续拉流 + 磁盘缓存快速 seek

**Date**: 2026-04-05
**Task**: 视频暂停继续拉流 + 磁盘缓存快速 seek

### Summary

(Add summary)

### Main Changes

| 模块 | 变更内容 |
|------|---------|
| 新增 `VideoStreamCache.swift` | `VideoStreamCache`：后台独立拉流，顺序写入临时磁盘文件；`CacheWriterDelegate`：实现 `VideoStreamLoaderDelegate`，将 dataFrame 追加写盘；`VideoStreamCacheManager`：单例管理所有活跃缓存生命周期 |
| `LocalMediaServer.swift` | `streamVideoData()` 开头增加缓存命中检查；新增 `serveFromCache()` 用 `pread()` 原子读取磁盘数据返回给 AVPlayer |
| `StreamingVideoPlayer.swift` | `setupPlayer()` 时启动后台缓存；`stopPlaying()` 时停止并清理临时文件 |
| `project.pbxproj` | 将 `VideoStreamCache.swift` 注册到 Xcode 编译目标 |

**核心设计**:
- 后台拉流与 AVPlayer HTTP 连接完全解耦，暂停不中断下载
- 所有文件 I/O 在专属串行 DispatchQueue 上执行，保证线程安全和写后可见性
- `isRangeAvailable` 用高水位线（writtenBytes > range.upperBound）判断，适配顺序写入场景
- crash 残留处理：init 时先删除同名旧临时文件
- 写入失败时不递增 writtenBytes，缓存标记 invalid，自动回退实时拉流


### Git Commits

| Hash | Message |
|------|---------|
| `b325145` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
