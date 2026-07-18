# 文件上传自适应性能改造实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保持单 TCP 连接、绝对偏移和断点续传可靠性的前提下，实现 32 KB 至 512 KB 动态分块、1 MB 至 8 MB 动态 ACK 窗口、动态超时和服务端背压，并在上传完成前强制校验文件大小与 MD5。

**Architecture:** chat-storage 使用纯算法 `AdaptiveUploadController` 根据 ACK RTT、确认吞吐、Socket 写等待和服务端建议调整下一窗口参数；net-server 使用 `UploadBackpressureController` 将资源压力、写盘耗时和公平带宽预算转换为扩展 ACK。DATA_FRAME 结构、帧类型和单连接顺序写盘保持不变，所有参数只在完整 ACK 边界更新。

**Tech Stack:** Swift 5 / Swift Concurrency / XCTest，Java 8 / Java NIO / Fastjson / JUnit 4 / Maven。

---

## 文件边界

- 新建 `chat-storage/Services/AdaptiveUploadController.swift`：纯算法状态机，不直接访问 Socket、文件或 UI。
- 修改 `chat-storage/Services/DirectoryService.swift`：解析服务端策略，将动态参数接入上传循环。
- 修改 `chat-storage/Services/TransferTaskManager.swift`：接收并展示“等待服务端”“校验中”等状态。
- 修改 `chat-storage.xcodeproj/project.pbxproj`：将新 Swift 文件加入应用 target。
- 修改 `chat-storageTests/chat_storageTests.swift`：覆盖升降档、冷却、超时和 ACK 解码。
- 新建 `net-server/.../adaptive/UploadBackpressureController.java`：将服务端指标转换为状态和建议参数。
- 新建 `net-server/.../adaptive/UploadBackpressureDecision.java`：不可变背压决策值对象。
- 新建 `net-server/.../handler/UploadIntegrityVerifier.java`：校验最终文件大小和 MD5。
- 修改 `net-server/.../config/FileUploadConfig.java`：集中读取自适应范围和带宽上限。
- 修改 `net-server/.../model/file/FileUploadContext.java`：记录最近写盘耗时和 ACK 窗口指标。
- 修改 `net-server/.../handler/UploadAckPayloadBuilder.java`：输出扩展 progress ACK。
- 修改 `net-server/.../handler/FileUploadHandler.java`：接入策略、ACK 和最终完整性校验。
- 修改 `net-server/src/main/resources/server.properties`：配置自适应范围和公平带宽。
- 新建对应 JUnit 测试：覆盖背压映射、ACK 字段和完整性校验。

### Task 1: 固化客户端自适应算法

**Files:**
- Create: `chat-storage/Services/AdaptiveUploadController.swift`
- Modify: `chat-storageTests/chat_storageTests.swift`
- Modify: `chat-storage.xcodeproj/project.pbxproj`

- [x] **Step 1: 写失败测试**

测试初始参数 `64 KB / 1 MB / 30s`，连续两个健康窗口升档，`slow_down` 立即减半，降档后三个健康窗口冷却，参数不越过 `32 KB...512 KB` 和 `1 MB...8 MB`。

```swift
func testAdaptiveUploadControllerRaisesAfterTwoHealthyWindows() {
    var controller = AdaptiveUploadController()
    let first = controller.record(.healthy(rtt: 0.1, bytes: 1_048_576, elapsed: 0.4))
    let second = controller.record(.healthy(rtt: 0.1, bytes: 1_048_576, elapsed: 0.4))
    XCTAssertEqual(first.chunkSize, 65_536)
    XCTAssertEqual(second.chunkSize, 131_072)
    XCTAssertEqual(second.ackWindowBytes, 2_097_152)
}
```

- [x] **Step 2: 运行测试并确认因类型不存在而失败**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testAdaptiveUploadControllerRaisesAfterTwoHealthyWindows`

Expected: FAIL，提示找不到 `AdaptiveUploadController`。

- [x] **Step 3: 实现纯算法控制器**

控制器保存 `smoothedRTT`、`smoothedGoodput`、连续健康窗口和冷却计数；动态超时使用：

```swift
let transfer = Double(ackWindowBytes) / max(smoothedGoodput, 65_536)
ackTimeout = min(60, max(10, 4 * smoothedRTT + 2 * transfer))
```

服务端推荐值通过 `min(local, recommended)` 生效；`pause` 不改变确认偏移，只返回等待时间。

- [x] **Step 4: 运行控制器测试**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests`

Expected: 新增算法测试 PASS。

### Task 2: 扩展客户端协议模型并接入上传循环

**Files:**
- Modify: `chat-storage/Services/DirectoryService.swift`
- Modify: `chat-storageTests/chat_storageTests.swift`

- [x] **Step 1: 写失败测试**

验证 progress ACK 可以解码：

```swift
let json = #"{"status":"progress","uploadedSize":1048576,"serverState":"slow_down","recommendedChunkSize":65536,"recommendedAckWindow":1048576,"serverWriteMillis":42,"retryAfterMs":120}"#.data(using: .utf8)!
let ack = try JSONDecoder().decode(StandardAckResponse.self, from: json)
XCTAssertEqual(ack.serverState, "slow_down")
XCTAssertEqual(ack.retryAfterMs, 120)
```

- [x] **Step 2: 运行测试确认缺少字段**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testUploadProgressAckDecodesAdaptiveFields`

Expected: FAIL，`StandardAckResponse` 没有自适应字段。

- [x] **Step 3: 扩展 DTO 和上传循环**

`ResumeInfo` 增加初始/最小/最大 chunk 与 ACK 窗口字段；`StandardAckResponse` 增加 `serverState`、建议值、`serverWriteMillis`、`retryAfterMs`。`sendFileData` 每个窗口读取一次控制器快照，窗口内保持 chunk 固定，ACK 返回后再更新下一窗口。

- [x] **Step 4: 接入动态 ACK timeout 和状态回调**

`waitForUploadProgressAck` 返回完整 ACK 与 RTT；收到 `pause` 时先回调“等待服务端”，挂起 `retryAfterMs`，恢复后继续同一确认偏移；收到 `slow_down` 时不报错，立即降档。

- [x] **Step 5: 运行客户端测试**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'`

Expected: 全部 XCTest PASS。

### Task 3: 服务端配置和背压决策

**Files:**
- Create: `src/main/java/com/alibaba/server/nio/service/file/adaptive/UploadBackpressureDecision.java`
- Create: `src/main/java/com/alibaba/server/nio/service/file/adaptive/UploadBackpressureController.java`
- Create: `src/test/java/com/alibaba/server/nio/service/file/adaptive/UploadBackpressureControllerTest.java`
- Modify: `src/main/java/com/alibaba/server/nio/service/file/config/FileUploadConfig.java`
- Modify: `src/main/resources/server.properties`

- [x] **Step 1: 写失败测试**

```java
@Test
public void shouldPauseWhenResourcePressureIsCritical() {
    UploadBackpressureDecision decision = controller.decide(
            ResourcePressureLevel.CRITICAL, 10L, 3, 30, 0.9D);
    assertEquals("pause", decision.getServerState());
    assertTrue(decision.getRetryAfterMs() > 0L);
}
```

同时覆盖 NORMAL -> `normal`，MODERATE/HIGH -> `slow_down`，建议参数始终落在配置边界。

- [x] **Step 2: 用 Zulu JDK8 运行并确认测试失败**

Run: `JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn -Dtest=UploadBackpressureControllerTest test`

Expected: FAIL，背压类不存在。

- [x] **Step 3: 实现配置和决策类**

配置默认值：单连接最大 `50 MB/s`、全局 `100 MB/s`、chunk `32/64/512 KB`、ACK `1/8 MB`。公平预算按 `min(perConnectionMaxRate, globalRate / activeUploads)` 计算，服务端建议只作为客户端上限。

- [x] **Step 4: 运行背压测试**

Run: `JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn -Dtest=UploadBackpressureControllerTest test`

Expected: PASS。

### Task 4: 记录写盘指标并扩展 ACK

**Files:**
- Modify: `src/main/java/com/alibaba/server/nio/model/file/FileUploadContext.java`
- Modify: `src/main/java/com/alibaba/server/nio/service/file/handler/UploadAckPayloadBuilder.java`
- Modify: `src/main/java/com/alibaba/server/nio/service/file/handler/FileUploadHandler.java`
- Modify: `src/test/java/com/alibaba/server/nio/service/file/handler/FileUploadHandlerResponseTaskIdTest.java`

- [x] **Step 1: 写失败测试**

构造 `UploadBackpressureDecision` 后验证 ACK JSON 包含 `serverState`、`recommendedChunkSize`、`recommendedAckWindow`、`serverWriteMillis` 和 `retryAfterMs`，且原有 `taskId/fileId/status/uploadedSize` 不变。

- [x] **Step 2: 运行测试确认 ACK 字段缺失**

Run: `JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn -Dtest=FileUploadHandlerResponseTaskIdTest test`

Expected: FAIL，扩展字段不存在。

- [x] **Step 3: 实现窗口指标和扩展 ACK**

`writeData` 外围用 `System.nanoTime()` 记录本块写盘耗时；上下文累计 ACK 窗口字节、写盘毫秒和窗口起始时间。仅在 `FLAG_NEED_ACK` 时生成决策和扩展 ACK，并在 ACK 构建后重置窗口指标。

- [x] **Step 4: 运行 ACK 和协议测试**

Run: `JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn -Dtest=FileUploadHandlerResponseTaskIdTest,UploadDataFrameProtocolTest test`

Expected: PASS。

### Task 5: 上传完成前完整性校验

**Files:**
- Create: `src/main/java/com/alibaba/server/nio/service/file/handler/UploadIntegrityVerifier.java`
- Create: `src/test/java/com/alibaba/server/nio/service/file/handler/UploadIntegrityVerifierTest.java`
- Modify: `src/main/java/com/alibaba/server/nio/service/file/handler/FileUploadHandler.java`

- [x] **Step 1: 写失败测试**

测试正确大小和 MD5 通过；大小不符、MD5 不符明确失败；MD5 比较忽略大小写。

```java
@Test
public void shouldRejectMismatchedMd5() throws Exception {
    UploadIntegrityResult result = verifier.verify(file, file.length(), "00000000000000000000000000000000");
    assertFalse(result.isValid());
    assertEquals("MD5_MISMATCH", result.getCode());
}
```

- [x] **Step 2: 运行测试确认校验器不存在**

Run: `JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn -Dtest=UploadIntegrityVerifierTest test`

Expected: FAIL。

- [x] **Step 3: 实现校验器并接入 END_FRAME**

END_FRAME 首先 force/close 文件，校验 `Files.size == declaredFileSize`，随后流式计算 MD5。校验通过后才更新 `UPLOAD_SUCCESS` 和创建 `file` 记录；失败时返回 error ACK、标记失败、删除临时文件和 checkpoint，不创建 file 记录。

- [x] **Step 4: 运行完整性测试**

Run: `JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn -Dtest=UploadIntegrityVerifierTest test`

Expected: PASS。

### Task 6: 全链路验证

**Files:**
- Modify: `docs/superpowers/specs/2026-07-13-adaptive-file-upload-design.md` only if implementation requires clarified wording

- [x] **Step 1: 运行 net-server 全量测试和打包**

Run: `JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn clean package`

Expected: 所有测试 PASS，生成 `target/net-server-1.0-SNAPSHOT.jar`。

- [x] **Step 2: 运行 chat-storage 全量测试和 Debug 编译**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'`

Run: `xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug build`

Expected: 测试和构建均返回 0。

- [x] **Step 3: 静态协议核对**

确认两端保持 `FLAG_HAS_OFFSET=0x04`、`FLAG_NEED_ACK=0x02`、`ACK_FRAME=0x04`；确认聊天、下载、缩略图和媒体流帧类型未修改。

- [x] **Step 4: 交付人工验收清单**

由用户在已启动的服务上验证局域网升档、Wi-Fi 抖动降档、pause UI、断线续传以及最终文件 MD5。自动化阶段不代替用户操作 Xcode UI 上传。

## 实施结果（2026-07-13）

- net-server 使用 Zulu JDK 8.0.382 执行 `mvn clean package` 成功，60 项测试全部通过。
- 已生成带 `Main-Class: com.alibaba.server.NetServer` 的 `target/net-server-1.0-SNAPSHOT.jar`。
- chat-storage 单元测试全部通过，Debug 构建成功。
- 上传网络异常支持最多三次自动断点重连；重连后重新执行 RESUME_CHECK，以服务端磁盘安全偏移继续。
- ACK_FRAME、FLAG_NEED_ACK 和 FLAG_HAS_OFFSET 两端值一致，未修改聊天、下载、缩略图及媒体流帧类型。
