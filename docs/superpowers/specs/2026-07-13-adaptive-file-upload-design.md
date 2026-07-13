# 文件上传自适应性能改造设计

## 1. 背景

当前 chat-storage 使用固定 8 KB 文件分块上传，客户端每累计发送 4 MB 数据请求一次进度 ACK。
该实现具备绝对偏移校验和断点续传能力，但在大文件和高速网络中会产生大量帧、系统调用和解析开销。

net-server 当前还配置了固定单连接 2 MB/s、全局 20 MB/s 的上传限速。仅增大客户端分块不能突破该上限，
也无法根据公网高延迟、Wi-Fi 抖动、弱网或服务端磁盘压力主动降速。

本次改造统一升级 chat-storage 和 net-server，不支持新旧上传协议混合运行。

## 2. 目标

- 同时适配局域网、高延迟公网、Wi-Fi 和弱网环境。
- 降低大文件上传过程中的帧数量、系统调用和协议解析开销。
- 根据网络质量和服务端负载动态调整分块大小与 ACK 窗口。
- 保持单文件单 TCP 连接，避免多连接争抢带宽和随机写盘。
- 保留任务暂停、网络中断、客户端重启和服务端重启后的断点续传。
- 服务端繁忙时通过背压引导客户端降速，不将正常拥塞直接当作上传失败。
- 上传完成后校验文件大小和 MD5，禁止不完整或损坏文件进入正式 file 表。
- 不影响登录、聊天、下载、缩略图和视频在线播放协议。

## 3. 非目标

- 本阶段不实现单文件多连接并行上传。
- 本阶段不实现跨服务端节点的分布式分片合并。
- 不保留旧版上传协议兼容分支。
- 不根据文件扩展名决定上传可靠性，所有文件使用同一套完整性规则。

## 4. 总体架构

```text
本地文件
  -> AdaptiveUploadController
  -> DATA_FRAME(offset + data)
  -> 单条 TCP 连接
  -> net-server 上传 Worker
  -> 偏移校验与顺序写盘
  -> progress/backpressure ACK
  -> 客户端升档、降档、暂停或偏移回退
```

TCP 继续负责丢包重传、拥塞窗口和链路层流控。应用层不重新实现 TCP 拥塞算法，只根据以下信号调整每次读取量和
未确认数据量：

- ACK 往返时间。
- 实际确认吞吐量。
- 客户端 Socket 写入等待时间。
- 服务端文件写入耗时。
- 服务端 Worker 队列负载。
- 服务端活跃上传数和全局带宽预算。
- 偏移回退、超时和重连次数。

## 5. 客户端组件

### 5.1 AdaptiveUploadController

新增独立的自适应控制器，不将算法继续堆入 FileTransferService。

控制器输入：

- 最近一次发送窗口的字节数和耗时。
- ACK 中的 uploadedSize。
- ACK 往返时间。
- 客户端 Socket 写入等待时间。
- 服务端 serverState 和推荐参数。
- 本次是否发生偏移回退、超时或重连。

控制器输出：

- 下一阶段 chunkSize。
- 下一阶段 ackWindowBytes。
- 动态 ACK timeout。
- 是否进入冷却期。
- 是否根据服务端要求短暂暂停。

### 5.2 参数边界

| 参数 | 初始值 | 最小值 | 最大值 |
|---|---:|---:|---:|
| chunkSize | 64 KB | 32 KB | 512 KB |
| ackWindowBytes | 1 MB | 1 MB | 8 MB |
| ACK timeout | 动态计算 | 10 秒 | 60 秒 |
| 客户端并发上传数 | 3 | 1 | 5 |

单连接只保留一个正在编码或发送的数据块，因此单任务主要额外内存不超过 512 KB。

### 5.3 指标平滑

客户端使用指数加权移动平均保存网络指标：

```text
smoothedRTT = 0.8 * oldRTT + 0.2 * latestRTT
smoothedGoodput = 0.75 * oldGoodput + 0.25 * latestGoodput
```

动态超时按以下方式计算：

```text
estimatedTransferTime = ackWindowBytes / max(smoothedGoodput, 64 KB/s)
ackTimeout = clamp(4 * smoothedRTT + 2 * estimatedTransferTime, 10 秒, 60 秒)
```

首次没有历史指标时使用 30 秒。

## 6. 自适应算法

### 6.1 健康窗口

一个 ACK 窗口同时满足以下条件时视为健康：

- ACK status 为 progress。
- uploadedSize 等于客户端预期位置。
- serverState 为 normal。
- 未发生 ACK 超时、偏移回退或重连。
- ACK RTT 未超过 max(2 * smoothedRTT, 800 ms)。
- 服务端没有返回 retryAfterMs。

### 6.2 升档

启动阶段使用保守参数：

```text
64 KB / 1 MB
```

连续两个健康窗口后进入升档：

```text
chunkSize:      64 KB -> 128 KB -> 256 KB -> 512 KB
ackWindowBytes: 1 MB  -> 2 MB   -> 4 MB   -> 8 MB
```

达到最大值后保持，不继续扩大内存和在途数据。

### 6.3 降档

出现以下任一信号时立即降档：

- serverState 为 slow_down。
- 服务端确认位置落后于客户端预期位置。
- ACK RTT 超过 max(2 * smoothedRTT, 800 ms)。
- Socket 写入等待时间超过本窗口总耗时的 40%。
- 发生 ACK 超时或连接中断。

降档规则：

```text
chunkSize = max(32 KB, chunkSize / 2)
ackWindowBytes = max(1 MB, ackWindowBytes / 2)
```

降档后进入三个健康 ACK 窗口的冷却期，冷却期内不允许升档。

ACK 超时或重连后，新连接从 max(32 KB, previousChunkSize / 2) 和 1 MB 窗口重新开始。

### 6.4 服务端暂停

serverState 为 pause 时，客户端：

- 不关闭连接。
- 不继续读取源文件。
- 按 retryAfterMs 挂起当前任务。
- 暂停期间保持 UI 为“等待服务端”。
- 恢复后沿用当前确认偏移，不重复发送已确认数据。

## 7. 上传协议

### 7.1 DATA_FRAME

数据帧保持现有二进制结构：

```text
8 字节协议帧头
+ 8 字节 UInt64 大端序文件绝对偏移
+ N 字节文件内容
```

使用以下标志：

- FLAG_HAS_OFFSET 0x04：载荷前 8 字节为文件偏移。
- FLAG_NEED_ACK 0x02：该帧写盘后必须返回进度 ACK。

offset 已经能够唯一确定顺序和重复区间，因此不再增加独立 sequence 字段。

### 7.2 RESUME_ACK

断点响应继续返回服务端确认的安全偏移，并增加初始上传策略：

```json
{
  "taskId": "client-task-id",
  "status": "resume",
  "uploadedSize": 8396800,
  "initialChunkSize": 65536,
  "minChunkSize": 32768,
  "maxChunkSize": 524288,
  "initialAckWindow": 1048576,
  "maxAckWindow": 8388608
}
```

status 仍支持 new、resume、complete 和 error。

### 7.3 Progress ACK

```json
{
  "taskId": "client-task-id",
  "status": "progress",
  "uploadedSize": 12591104,
  "serverState": "normal",
  "recommendedChunkSize": 262144,
  "recommendedAckWindow": 4194304,
  "serverWriteMillis": 18,
  "retryAfterMs": 0
}
```

serverState 取值：

- normal：服务端可继续接收。
- slow_down：客户端立即降低分块和 ACK 窗口。
- pause：客户端按 retryAfterMs 暂停发送。
- error：终止当前连接并保留已确认断点。

客户端最终参数始终取本地算法值与服务端建议值的较小者。

## 8. 服务端背压与公平限速

### 8.1 服务端指标

每个上传上下文记录：

- 最近数据块写盘耗时。
- 最近 ACK 窗口平均写入速率。
- Worker 队列占用率。
- 活跃上传连接数。
- 全局令牌桶剩余预算。
- 当前 JVM 可用内存比例。

### 8.2 serverState 判定

normal：

- Worker 队列占用率低于 60%。
- 最近写盘耗时未连续异常上升。
- JVM 可用内存高于安全下限。

slow_down：

- Worker 队列占用率达到 60% 至 85%。
- 写盘延迟连续三个窗口高于其平滑值两倍。
- 全局速率预算持续不足。

pause：

- Worker 队列占用率超过 85%。
- JVM 可用内存低于配置的安全下限。
- 磁盘写入出现短期不可用但连接仍然有效。

### 8.3 动态公平带宽

移除固定单连接 2 MB/s 的硬编码行为，改为配置最大值和动态公平预算：

```text
connectionBudget = min(perConnectionMaxRate, globalRate / activeUploadCount)
```

建议默认配置：

```properties
FILE.UPLOAD.PER.CONNECTION.MAX.RATE.BPS=52428800
FILE.UPLOAD.GLOBAL.RATE.BPS=104857600
FILE.UPLOAD.ADAPTIVE.CHUNK.MIN.BYTES=32768
FILE.UPLOAD.ADAPTIVE.CHUNK.INITIAL.BYTES=65536
FILE.UPLOAD.ADAPTIVE.CHUNK.MAX.BYTES=524288
FILE.UPLOAD.ADAPTIVE.ACK.INITIAL.BYTES=1048576
FILE.UPLOAD.ADAPTIVE.ACK.MAX.BYTES=8388608
```

配置值是上限，不保证实际网络一定达到该速率。

## 9. 断点续传

上传中断时服务端执行：

1. 停止接收该通道的新数据。
2. force 并关闭 FileChannel。
3. 读取临时文件真实大小。
4. 将真实大小写入 file_task.current_offset。
5. 将任务状态改为 PAUSED。
6. 保存内存 checkpoint，随后释放上传上下文。

恢复时服务端执行：

1. 使用 transferToken 校验用户身份。
2. 按用户和 MD5 查询暂停任务。
3. 比较数据库断点与临时文件真实大小。
4. 磁盘小于断点时以磁盘大小为准。
5. 磁盘大于可信断点时截断到可信断点。
6. 将 FileChannel 定位到最终偏移。
7. 通过 RESUME_ACK 返回最终偏移。

客户端始终以服务端 RESUME_ACK.uploadedSize 为准，并定位本地源文件后继续发送。

动态分块参数不持久化。重连后网络条件可能变化，因此从保守值重新探测。

## 10. 完整性校验

客户端发送 END_FRAME 前必须满足：

```text
currentOffset == declaredFileSize
```

服务端收到 END_FRAME 后必须依次执行：

1. force 并关闭临时文件。
2. 验证磁盘文件大小严格等于声明大小。
3. 在独立的 UploadFinalizeExecutor 中计算文件 MD5。
4. 验证服务端 MD5 与客户端声明 MD5 一致。
5. 校验通过后更新 file_task 为 UPLOAD_SUCCESS。
6. 创建正式 file 记录并返回 fileId。

大小或 MD5 不一致时：

- 不创建 file 记录。
- 将任务标记为校验失败。
- 删除损坏的临时文件和 checkpoint。
- 客户端收到明确错误后从零重新上传。

## 11. 错误处理

- ACK确认偏移小于客户端预期：客户端回退文件指针并重发，最多 12 次。
- ACK确认偏移大于客户端预期：协议状态异常，断开并重新执行断点检查。
- ACK超时：断开连接，由服务端落盘并保存断点，然后重连恢复。
- 服务端 slow_down：降档，不计为失败。
- 服务端 pause：等待 retryAfterMs，不断开连接。
- 本地文件 bookmark 失效：任务标记失败并要求重新选择源文件。
- 用户登录状态失效：停止任务并提示重新登录，不使用持久化任务中的旧用户身份。

## 12. UI行为

传输列表继续使用现有任务行，不展示底层分块参数。

状态补充：

- 上传中：正常传输。
- 等待服务端：收到 pause 背压。
- 网络恢复中：连接中断后正在重新建立断点会话。
- 校验中：数据发送完成，服务端正在校验大小和 MD5。
- 失败：不可自动恢复的错误。

暂停、取消、清除任务和缩略图映射行为保持不变。

## 13. 测试与验收

### 13.1 单元测试

- 不同指标序列下的升档、降档和冷却期。
- chunkSize 与 ackWindow 的最小值和最大值。
- 动态 timeout 计算边界。
- DATA_FRAME 偏移头编码与解码。
- progress ACK 新字段编解码。
- serverState 对客户端状态机的影响。
- 最终文件大小与 MD5 校验。

### 13.2 集成测试

- 小于 32 KB、正好 64 KB、跨多个分块和大于 3 GB 的文件。
- 上传过程中暂停、断网、退出客户端和重启服务端。
- 服务端确认偏移落后时客户端回退重发。
- 五个大文件并发上传时的公平带宽和内存占用。
- 服务端 Worker 队列压力下 slow_down 和 pause 行为。
- 上传完成后的源文件和服务端文件 MD5 一致。

### 13.3 网络环境验收

- 局域网：参数可稳定升到 512 KB / 8 MB，并接近配置带宽上限。
- 高延迟公网：不会因正常 RTT 提升频繁超时，吞吐保持稳定。
- Wi-Fi 抖动：发生拥塞后能够降档，并在恢复后逐步升档。
- 弱网：最小分块和窗口下可持续推进，不出现无限重试。
- 网络中断：恢复后从服务端确认偏移继续，最终 MD5 一致。

## 14. 实施边界

chat-storage 主要改动：

- FileTransferService：接入动态分块、窗口和 ACK timeout。
- AdaptiveUploadController：新增纯算法组件。
- 上传响应 DTO：增加服务端背压字段。
- TransferTaskManager：补充网络恢复中和等待服务端状态。
- 单元测试：覆盖算法、协议和断点恢复。

net-server 主要改动：

- FileUploadHandler：生成扩展 ACK，并执行结束校验。
- FileUploadContext：记录窗口写入指标。
- UploadBackpressureController：新增服务端建议参数计算。
- 上传限速配置：固定速率改为最大速率和公平预算。
- UploadFinalizeExecutor：独立执行最终大小和 MD5 校验。
- 单元测试和集成测试：覆盖协议、背压、断点和完整性。

整个改造不修改聊天帧类型、下载帧类型、媒体流端口和缩略图生命周期。
