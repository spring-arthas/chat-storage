# 服务端在线播放拉流（Pull-Range）详细设计方案

## 1. 文档信息
- 项目：`net-server`
- 目标类：`com.alibaba.server.nio.service.file.handler.FileDownloadHandler`
- 版本：`v2.0`
- 日期：`2026-04-07`
- 作者：AI Design Draft

## 2. 背景与现状

当前服务端文件流逻辑在 `FileDownloadHandler.handleClientAck()` 内调用 `transferFile()`，行为是：
1. 客户端发 `META_FRAME` 请求（含 `fileId/taskId/startOffset`）。
2. 服务端 `ACK` 后，进入循环读取文件并持续推送 `DATA_FRAME` 到 EOF。
3. 默认每帧 64KB（`BUFFER_SIZE=65536`）。
4. 发送 `END_FRAME` 后关闭连接。

该模式适合“下载”，不适合“在线播放（Range/seek）”，因为播放器是按字节区间按需拉取，而不是一次性消费到 EOF。

## 3. 问题定义

1. 协议语义错配  
服务端“主动连续推送”与客户端“按段拉取”不一致，导致中间缓存和本地代理压力增大。

2. seek 场景不稳定  
播放器频繁改变 Range 时，旧流仍可能持续推送，造成无效传输和连接重置。

3. 长度一致性风险  
本地 HTTP 代理声明的 `Content-Length` 与实际可发送数据可能不一致，触发客户端 strict content-length 错误。

4. 资源利用低效  
服务端在客户端暂不需要数据时仍可能持续发送，浪费带宽和 CPU。

## 4. 设计目标

1. 服务端改为“按请求窗口返回”的 Pull-Range 模式。
2. 与现有 Frame 通道兼容，不引入 HTTP 服务端重构。
3. 保留旧客户端下载能力，支持灰度切换。
4. 确保 seek/随机访问稳定性和可观测性。
5. 限制内存占用和队列积压，避免写队列失控。

## 5. 非目标

1. 本次不改数据库结构（除非新增可选字段）。
2. 本次不替换 Socket 协议为 HTTP。
3. 本次不改上传逻辑。
4. 本次不引入 CDN。

## 6. 新协议设计（Frame V2）

### 6.1 基本原则
1. 一个 `META_FRAME(op=range_pull)` 对应一个“窗口传输”。
2. 服务端只发送窗口范围内的数据，不越界推送。
3. 窗口结束必须发送 `END_FRAME`，并保持连接可复用。
4. 客户端需要下一段时，再发送下一次 `META_FRAME`。

### 6.2 请求帧（META_FRAME）
```json
{
  "op": "range_pull",
  "taskId": "uuid-task",
  "requestId": "uuid-req",
  "fileId": 7440344008343912448,
  "startOffset": 1048576,
  "length": 1048576,
  "client": "mac-chat-storage",
  "protocolVersion": 2
}
```

字段说明：
- `op`: 固定 `range_pull`。
- `taskId`: 会话标识。
- `requestId`: 单窗口请求唯一 ID，用于幂等。
- `startOffset`: 起始字节。
- `length`: 请求窗口长度。
- `protocolVersion`: 协议版本标识。

### 6.3 确认帧（ACK_FRAME）
```json
{
  "status": "ok",
  "taskId": "uuid-task",
  "requestId": "uuid-req",
  "fileId": 7440344008343912448,
  "fileSize": 4124218656,
  "startOffset": 1048576,
  "length": 1048576,
  "chunkSize": 65536,
  "eof": false
}
```

错误示例：
```json
{
  "status": "error",
  "taskId": "uuid-task",
  "requestId": "uuid-req",
  "code": 41601,
  "message": "range out of bounds"
}
```

### 6.4 数据帧（DATA_FRAME）
当前可保持“纯数据 payload”。  
建议扩展两种策略，二选一：
1. 简单方案：保持现状，不加头，依赖有序发送。
2. 增强方案：在 payload 前增加轻量自定义头（`requestId/seq/offset`），提升诊断能力。

### 6.5 结束帧（END_FRAME）
```json
{
  "status": "success",
  "taskId": "uuid-task",
  "requestId": "uuid-req",
  "sentBytes": 1048576,
  "nextOffset": 2097152,
  "eof": false
}
```

失败示例：
```json
{
  "status": "error",
  "taskId": "uuid-task",
  "requestId": "uuid-req",
  "code": 50031,
  "message": "io read failed"
}
```

## 7. 服务端状态机设计

状态：
1. `IDLE`
2. `READY`
3. `TRANSFERRING_WINDOW`
4. `WINDOW_DONE`
5. `ERROR`
6. `CLOSED`

流转：
1. `META_FRAME(range_pull)` -> 参数校验 -> `ACK(ok)` -> `TRANSFERRING_WINDOW`
2. 窗口发送完成 -> `END(success)` -> `WINDOW_DONE` -> 回到 `READY`
3. 任意异常 -> `END(error)` 或 `ACK(error)` -> `ERROR`
4. 超时或客户端断开 -> `CLOSED`

## 8. 核心实现改造点

### 8.1 FileDownloadHandler 改造
1. 新增方法 `handleRangePullRequest(frame, socketCtx, simpleCtx)`。
2. 在 `handleFrame()` 中根据 `op` 分流：
   - `op=range_pull` 走新逻辑。
   - 无 `op` 或旧格式走老逻辑（兼容）。
3. 将 `transferFile()` 拆分为 `transferWindow(context, startOffset, length, requestId, ...)`。
4. `transferWindow()` 完成后不强制关闭连接，等待下一请求。
5. 增加连接空闲超时关闭逻辑（如 30s 无新请求关闭）。

### 8.2 上下文模型改造（FileDownloadContext）
建议新增字段：
- `protocolVersion`
- `lastRequestId`
- `currentWindowStart`
- `currentWindowLength`
- `windowSentBytes`
- `lastActiveTime`（已有可复用）
- `connectionKeepAlive`（可选）

### 8.3 幂等与重复请求
策略：
1. 若 `requestId` 与最近完成窗口一致，直接返回缓存结果（ACK/END）或忽略重放。
2. 若 `requestId` 新但参数重复，允许重传窗口。

### 8.4 Range 校验
校验规则：
1. `startOffset >= 0`
2. `length > 0`
3. `startOffset < fileSize`
4. `startOffset + length <= fileSize`（或裁剪到 EOF 并回执实际长度）
5. 超限返回 `41601`

### 8.5 传输循环
`transferWindow()` 伪代码：

```java
long endExclusive = min(startOffset + length, fileSize);
channel.position(startOffset);
long sent = 0;
while (startOffset + sent < endExclusive) {
    int toRead = (int) min(BUFFER_SIZE, endExclusive - (startOffset + sent));
    ByteBuffer buf = ByteBuffer.allocate(toRead);
    int n = channel.read(buf);
    if (n < 0) break;
    if (n == 0) continue;
    buf.flip();
    sendDataFrame(socketCtx, copyBytes(buf));
    sent += n;
    applyBackpressure(socketCtx);
}
sendEndFrame(success, sent, nextOffset, eof);
```

## 9. 背压与并发控制

1. 保留 `DOWNLOAD_SEMAPHORE`，建议区分：
   - `maxConcurrentDownloads`（下载）
   - `maxConcurrentStreams`（播放）  
2. 保留 `MAX_PENDING_BUFFERS` 阈值。
3. 增加“窗口级超时”：
   - 单窗口发送超过阈值（如 15s）则 `END(error: timeout)`。
4. 增加“无进展超时”：
   - 队列长时间不下降则中断本窗口。

## 10. 错误码规范建议

1. `40010`: invalid request json
2. `40011`: missing taskId/requestId
3. `40410`: file not found
4. `40910`: session expired
5. `41601`: range out of bounds
6. `42910`: server busy
7. `50031`: io read failed
8. `50032`: queue drain timeout
9. `50033`: channel closed unexpectedly

## 11. 兼容策略与灰度发布

1. 开关：
- `stream.range.pull.enabled=true/false`
- `stream.range.pull.defaultVersion=2`
- `stream.range.pull.fallbackV1=true/false`

2. 兼容逻辑：
- 若客户端 `protocolVersion>=2 && op=range_pull`，走 V2。
- 否则走现有 V1 全量推送。

3. 灰度步骤：
1. 内部环境开启 V2，V1 保底。
2. 指定客户端白名单启用 V2。
3. 观测稳定后扩大比例。
4. 最终将 V2 设为默认，V1 仅兜底。

## 12. 测试方案

### 12.1 单元测试
1. Range 校验边界测试：
   - `start=0,length=1`
   - `start=fileSize-1,length=1`
   - 越界参数
2. requestId 幂等测试。
3. EOF 裁剪测试。

### 12.2 集成测试
1. 连续窗口拉取：0-1MB，1-2MB，2-3MB。
2. seek 跳转：50MB -> 5MB -> 300MB。
3. 并发播放 5 路。
4. 异常中断后重连恢复。
5. 大文件（>4GB）窗口拉取稳定性。

### 12.3 回归测试
1. 旧客户端下载（V1）不受影响。
2. 普通下载任务不受影响。
3. 上传链路不受影响。

## 13. 可观测性与日志

必须打点：
1. `taskId/requestId/fileId/start/length/sentBytes/costMs`
2. `pendingQueuePeak/waitCount`
3. `errorCode/errorMessage`
4. `connectionClosedReason`
5. `semaphoreAcquireCostMs`

建议指标：
- 窗口成功率
- 首帧耗时（TTFB）
- 每窗口平均吞吐
- 重试率
- 416 比例
- 500xx 比例

## 14. 风险与应对

1. 风险：协议分支复杂化  
应对：保留清晰 V1/V2 分流函数，避免逻辑交织。

2. 风险：客户端未带 requestId  
应对：服务端兜底生成但记录 warning，逐步强制。

3. 风险：窗口太小导致 RTT 开销高  
应对：动态建议窗口大小（1MB 默认，可配）。

4. 风险：窗口太大导致内存和队列压力  
应对：服务端限制 `maxWindowLength`（建议 4MB）。

## 15. 实施清单（服务端）

1. `FileDownloadHandler`
   - 增加 `op=range_pull` 解析分支
   - 新增 `handleRangePullRequest()`
   - 新增 `transferWindow()`
   - 增加 `sendEndFrame()` 支持 requestId

2. `FileDownloadContext`
   - 增加窗口与幂等字段

3. `FrameDownloadParser`
   - 确认可透传 `op/requestId/protocolVersion`

4. 配置项
   - 新增 V2 开关与窗口大小、超时参数

5. 监控日志
   - 增加 requestId 维度日志和指标

## 16. 验收标准

1. V2 客户端在随机 seek 场景下不再出现持续推送到 EOF。
2. 窗口传输模型下，服务端每次只发送请求范围数据。
3. `network connection lost (-1005)` 比例显著下降。
4. `strict content length check failed` 归零或接近零。
5. V1 客户端与下载链路兼容不回归。
