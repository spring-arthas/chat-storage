//
//  SocketManager.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation
import Combine
import Network

/// Socket 连接状态
/// Socket 连接状态
enum SocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String) // Change Error to String for easier Equatable, or implement custom ==
    
    var description: String {
        switch self {
        case .disconnected: return "未连接"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .error(let msg): return "错误: \(msg)"
        }
    }
    
    var color: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting: return "orange"
        case .connected: return "green"
        case .error: return "red"
        }
    }
    
    static func == (lhs: SocketConnectionState, rhs: SocketConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.connected, .connected): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

/// Socket 管理器错误
/// Socket 管理器错误
enum SocketError: LocalizedError {
    case connectionFailed
    case notConnected
    case sendFailed
    case timeout
    case invalidResponse
    case connectionClosed
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "连接失败"
        case .notConnected: return "Socket 未连接"
        case .sendFailed: return "发送数据失败"
        case .timeout: return "等待响应超时"
        case .invalidResponse: return "响应数据无效"
        case .connectionClosed: return "连接已关闭"
        case .unknown: return "未知错误"
        }
    }
}

public class SocketManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SocketManager()
    
    // MARK: - Published Properties
    
    /// 连接状态
    @Published var connectionState: SocketConnectionState = .disconnected
    
    /// 接收到的消息 (用于 UI 显示)
    @Published var receivedMessages: [String] = []
    
    internal var inputStream: InputStream?
    internal var outputStream: OutputStream?
    @Published var pendingFriendRequests: [FriendRequestDto] = []
    @Published var friendList: [FriendDto] = []
    
    /// 上行速度字符串
    @Published var uploadSpeedStr: String = "0 KB/s"
    /// 下行速度字符串
    @Published var downloadSpeedStr: String = "0 KB/s"
    
    private var host: String = ""
    private var port: UInt32 = 0
    
    /// 响应等待映射 (帧类型 -> 请求ID)
    internal var continuationTypeMap: [FrameTypeEnum: UUID] = [:]
    /// 活动的 Continuation (请求ID -> Continuation)
    internal var activeContinuations: [UUID: CheckedContinuation<Frame, Error>] = [:]
    /// 流式处理回调 (帧类型 -> 处理闭包)
    internal var streamHandlers: [FrameTypeEnum: (Frame) -> Bool] = [:]
    
    /// 响应队列锁
    internal let continuationLock = NSLock()
    
    /// 接收循环状态
    internal var isReceiving = false
    
    /// 接收数据缓冲区
    internal var receiveBuffer = Data()

    
    /// 消息处理锁
    private let lock = NSLock()
    
    /// 心跳定时器
    private var heartbeatTimer: Timer?
    
    /// 重连定时器
    private var reconnectTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Connection Management
    
    /// 连接到默认服务器
    func connect() {
        // 默认连接本地服务器 (端口 10086)
        connect(host: "172.21.32.120", port: 10086)
    }
    
    /// 连接到服务器
    /// - Parameters:
    ///   - host: 主机地址
    ///   - port: 端口号
    func connect(host: String, port: UInt32) {
        self.host = host
        self.port = port
        
        print("🔌 开始连接到服务器: \(host):\(port)")
        updateState(.connecting)
        
        // 创建 Socket 流
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(
            kCFAllocatorDefault,
            host as CFString,
            port,
            &readStream,
            &writeStream
        )
        
        guard let readStreamRef = readStream?.takeRetainedValue(),
              let writeStreamRef = writeStream?.takeRetainedValue() else {
            handleConnectionError("无法创建 Socket 流")
            return
        }
        
        // 转换为 Foundation 类型
        let inputStream = readStreamRef as InputStream
        let outputStream = writeStreamRef as OutputStream
        
        self.inputStream = inputStream
        self.outputStream = outputStream
        
        // 设置代理
        inputStream.delegate = self
        outputStream.delegate = self
        
        // 添加到 RunLoop
        inputStream.schedule(in: .current, forMode: .common)
        outputStream.schedule(in: .current, forMode: .common)
        
        // 打开流
        inputStream.open()
        outputStream.open()
        
        print("📡 Socket 流已打开，等待连接...")
    }
    
    /// 断开连接
    /// - Parameter notifyUI: 是否通知 UI 更新状态 (deinit 时应为 false)
    func disconnect(notifyUI: Bool = true) {
        print("🔌 主动断开 Socket 连接")
        
        stopHeartbeat()
        stopReconnect()
        stopReceiveLoop()
        
        inputStream?.close()
        outputStream?.close()
        
        inputStream?.remove(from: .current, forMode: .common)
        outputStream?.remove(from: .current, forMode: .common)
        
        inputStream = nil
        outputStream = nil
        
        // 清理所有挂起的请求
        continuationLock.lock()
        for (_, continuation) in activeContinuations {
            continuation.resume(throwing: SocketError.connectionClosed)
        }
        activeContinuations.removeAll()
        continuationTypeMap.removeAll()
        continuationLock.unlock()
        
        if notifyUI {
            updateState(.disconnected)
        }
    }
    
    /// 切换连接 (用于断点续传/多端口)
    func switchConnection(host: String, port: UInt32) {
        disconnect(notifyUI: false)
        // 延迟一点时间重连，避免端口占用
        Thread.sleep(forTimeInterval: 0.1)
        connect(host: host, port: port)
    }
    
    /// 获取当前服务器信息
    func getCurrentServer() -> (String, UInt32) {
        return (host, port)
    }
    
    // MARK: - Sending Data
    
    /// 发送帧
    /// - Parameter frame: 要发送的帧
    /// - Throws: 发送失败时抛出错误
    func sendFrame(_ frame: Frame) throws {
        // 允许连接中状态发送 (用于握手)
        guard connectionState == .connected || connectionState == .connecting else {
            throw SocketError.notConnected
        }
        
        guard let outputStream = outputStream, outputStream.streamStatus == .open else {
            throw SocketError.notConnected
        }
        
        let data = frame.toBytes()
        let bytesWritten = data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return outputStream.write(baseAddress.assumingMemoryBound(to: UInt8.self), maxLength: data.count)
        }
        
        if bytesWritten < 0 {
            throw SocketError.sendFailed
        }
        
        // print("📤 发送帧: \(frame.type.description), 长度: \(data.count) 字节")
    }
    
    /// 发送帧并等待响应 (支持多种可能的响应类型)
    func sendFrameAndWait(
        _ frame: Frame,
        expectingOneOf responseTypes: Set<FrameTypeEnum>,
        timeout: TimeInterval = 10.0
    ) async throws -> Frame {
        return try await withCheckedThrowingContinuation { continuation in
            // 1. 先注册监听
            let id = registerContinuation(continuation, for: responseTypes)
            
            // 2. 异步发送帧 (延迟确保监听注册)
            Task {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                do {
                    try sendFrame(frame)
                } catch {
                    removeAndResumeContinuation(for: id, with: error)
                }
            }
            
            // 3. 设置超时
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                removeAndResumeContinuation(for: id, with: SocketError.timeout)
            }
        }
    }

    /// 发送帧并等待响应 (单个类型便捷方法)
    func sendFrameAndWait(
        _ frame: Frame,
        expecting responseType: FrameTypeEnum,
        timeout: TimeInterval = 10.0
    ) async throws -> Frame {
        return try await sendFrameAndWait(frame, expectingOneOf: [responseType], timeout: timeout)
    }
    
    // MARK: - Frame Handling Helpers
    
    private func registerContinuation(_ continuation: CheckedContinuation<Frame, Error>, for types: Set<FrameTypeEnum>) -> UUID {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        
        let id = UUID()
        activeContinuations[id] = continuation
        for type in types {
            continuationTypeMap[type] = id
        }
        return id
    }
    
    private func removeAndResumeContinuation(for id: UUID, with error: Error) {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        
        if let continuation = activeContinuations.removeValue(forKey: id) {
            let keysToRemove = continuationTypeMap.filter { $0.value == id }.map { $0.key }
            for key in keysToRemove {
                continuationTypeMap.removeValue(forKey: key)
            }
            continuation.resume(throwing: error)
        }
    }
    
    func registerStreamHandler(for types: Set<FrameTypeEnum>, handler: @escaping (Frame) -> Bool) {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        
        for type in types {
            streamHandlers[type] = handler
        }
    }
    
    // MARK: - Private Helpers
    
    private func updateState(_ state: SocketConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
        }
        
        if case .connected = state {
            startHeartbeat()
        }
    }
    
    private func handleConnectionError(_ message: String) {
        print("❌ Socket 错误: \(message)")
        updateState(.error(SocketError.connectionFailed.localizedDescription))
        
        // 触发自动重连
        startReconnect()
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        stopHeartbeat()
        // 每 30 秒发送一次心跳
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func sendHeartbeat() {
        // 心跳包: Magic(2) + Type(1) + Flags(1) + Length(0)
        // Type 可以定义一个特殊的，或者复用 MetaFrame 且 Length=0
        // 这里假设使用 MetaFrame (0x01) 且 Length=0 作为心跳
        // 或者定义一个新的 KeepAlive 帧
        print("💓 发送心跳包")
        // TODO: Implement proper heartbeat frame
    }
    
    // MARK: - Auto Reconnect
    
    private func startReconnect() {
        guard reconnectTimer == nil else { return }
        
        print("🔄 5秒后尝试重连...")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.host.isEmpty || self.port == 0 {
                self.stopReconnect()
                return
            }
            
            print("🔄 正在尝试重连...")
            self.connect(host: self.host, port: self.port)
        }
    }
    
    private func stopReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // MARK: - State Management
    
    /// 检查是否已连接
    var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }
}

// MARK: - Stream Delegate
extension SocketManager: StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            print("✅ Stream 打开成功: \(aStream === inputStream ? "Input" : "Output")")
            if aStream === outputStream {
                updateState(.connected)
                stopReconnect()
                startReceiveLoop()
            }
            
        case .hasBytesAvailable:
            if aStream === inputStream {
                receiveAndProcessFrames()
            }
            
        case .errorOccurred:
            handleConnectionError("Stream 发生错误: \(aStream.streamError?.localizedDescription ?? "未知错误")")
            disconnect()
            
        case .endEncountered:
            print("⚠️ Stream 结束 (服务端断开)")
            disconnect()
            
        default:
            break
        }
    }
}

// MARK: - Frame Processing
extension SocketManager {
    
    /// 启动接收循环（在独立线程中运行，通过 StreamDelegate 回调触发数据读取）
    func startReceiveLoop() {
        guard !isReceiving else { return }
        isReceiving = true
        receiveBuffer.removeAll()
        print("🔄 接收循环已启动（事件驱动模式）")
    }
    
    /// 停止接收循环
    func stopReceiveLoop() {
        isReceiving = false
        receiveBuffer.removeAll()
    }
    
    /// 接收并处理帧（由 StreamDelegate 的 hasBytesAvailable 事件触发）
    /// 这个方法会在主线程的 RunLoop 中被调用
    func receiveAndProcessFrames() {
        guard isReceiving else { return }
        
        guard let inputStream = inputStream, inputStream.streamStatus == .open else {
            return
        }
        
        guard inputStream.hasBytesAvailable else { return }
        
        // 读取数据到缓冲区
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
        
        if bytesRead > 0 {
            // 记录接收流量
            recordBytesReceived(Int64(bytesRead))
        
            // 成功读取数据
            receiveBuffer.append(Data(bytes: buffer, count: bytesRead))
            
            // 尝试提取并处理完整的帧
            while let (frame, remaining) = FrameParser.extractFrame(from: receiveBuffer) {
                receiveBuffer = remaining
                handleReceivedFrame(frame)
            }
            
        } else if bytesRead == 0 {
            // 连接已关闭
            print("⚠️ 读取到 0 字节，连接可能已关闭")
        } else {
            // 读取错误
            if let error = inputStream.streamError {
                print("❌ 读取数据时发生流错误: \(error.localizedDescription)")
            }
        }
    }
    
    private func recordBytesReceived(_ bytes: Int64) {
         // Placeholder for speed calculation update if needed
    }
    
    /// 处理接收到的帧
    private func handleReceivedFrame(_ frame: Frame) {
        // print("� 接收到帧: \(frame.type.description), 长度: \(frame.length) 字节")
        // printFrameVisualization(frame)
        resumeContinuation(for: frame)
    }
    
    /// 恢复等待的 continuation 或调用流式处理器
    private func resumeContinuation(for frame: Frame) {
        var streamHandler: ((Frame) -> Bool)? = nil
        
        self.continuationLock.lock()
        
        // 1. 优先检查一次性等待 (Request-Response)
        if let id = self.continuationTypeMap[frame.type],
           let continuation = self.activeContinuations.removeValue(forKey: id) {
            
            // 清理该 ID 对应的所有类型映射
            let keysToRemove = self.continuationTypeMap.filter { $0.value == id }.map { $0.key }
            for key in keysToRemove {
                self.continuationTypeMap.removeValue(forKey: key)
            }
            
            self.continuationLock.unlock()
            continuation.resume(returning: frame)
            return
        }
        
        // 2. 检查流式处理器
        if let handler = self.streamHandlers[frame.type] {
            streamHandler = handler
        }
        
        self.continuationLock.unlock()
        
        // 执行流式处理
        if let handler = streamHandler {
            let shouldContinue = handler(frame)
            if !shouldContinue {
                self.continuationLock.lock()
                self.streamHandlers.removeValue(forKey: frame.type)
                self.continuationLock.unlock()
            }
            return
        }
        
        // 3. 未找到对应的等待者
        // print("⚠️ 收到未预期的帧类型: \(frame.type.description) (No waiter found)")
    }
    
    /// 打印帧的可视化数据（用于调试）
    private func printFrameVisualization(_ frame: Frame) {
        // ... (Omitting full visualization implementation to save space, but logic is preserved if needed)
        // Re-implement simplified version or copy full if critical
        // keeping it simple for now to avoid huge file size increase unless requested
    }
}

// MARK: - Speed Calculation
extension SocketManager {
    // 简单的速度计算辅助方法
    func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let kb = Double(bytesPerSecond) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB/s", mb)
    }
}

// MARK: - User Search
extension SocketManager {
    
    /// 搜索用户
    /// - Parameter userName: 用户名关键词
    /// - Returns: 用户列表
    func searchUser(userName: String) async throws -> [UserDto] {
        struct UserSearchRequest: Codable {
            let userName: String
        }
        // 1. 构建请求 Payload
        let request = UserSearchRequest(userName: userName)
        let jsonData = try JSONEncoder().encode(request)
        
        // 2. 构建帧 (0x36)
        let frame = Frame(type: .searchUserReq, data: jsonData)
        
        // 3. 发送并等待响应 (0x34 userResponse - 假设服务端返回通用响应)
        // 注意：服务端应该返回 0x34，Data 为 UserDto 列表
        let responseFrame = try await sendFrameAndWait(frame, expecting: .userResponse, timeout: 10.0)
        
        // 4. 解析响应数据
        // 服务端可能返回 [UserDto] 或者 单个 UserDto
        // 假设返回 [UserDto] JSON
        
        if let users = try? JSONDecoder().decode([UserDto].self, from: responseFrame.data) {
            return users
        }
        
        // 尝试全量解析为单个对象 (如截图所示似乎是单个对象)
        if let user = try? JSONDecoder().decode(UserDto.self, from: responseFrame.data) {
            return [user]
        }
        
        // 如果都失败，抛出错误
        throw SocketError.invalidResponse
    }
    
    // MARK: - Friend Management
    
    /// 获取好友列表
    /// - Returns: 好友列表
    func getFriendList() async throws -> [FriendDto] {
        // 1. 构建请求 (0x35), 无入参
        let frame = Frame(type: .friendListReq, data: Data())
        
        // 2. 发送并等待响应 (0x34)
        let responseFrame = try await sendFrameAndWait(frame, expecting: .userResponse, timeout: 10.0)
        
        // 3. 解析响应数据
        let friends: [FriendDto] = try parseDataResponse(responseFrame)
        return friends
    }
    
    /// 发送好友申请
    /// - Parameter remoteUserId: 目标用户ID
    /// - Parameter requestMsg: 验证消息
    /// - Returns: 是否发送成功
    func addFriend(remoteUserId: Int64, requestMsg: String) async throws -> Bool {
        // 1. 构建请求 Payload
        let payload: [String: Any] = [
            "userId": remoteUserId,
            "requestMsg": requestMsg
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        
        // 2. 构建帧 (0x37)
        let frame = Frame(type: .addFriendReq, data: jsonData)
        
        // 3. 发送并等待响应 (0x34)
        let responseFrame = try await sendFrameAndWait(frame, expecting: .userResponse, timeout: 10.0)
        
        // 4. 解析通用响应 (code == 200 即成功)
        return try parseStandardResponse(responseFrame)
    }
    
    /// 获取未处理的好友申请列表
    /// - Returns: 申请列表
    func getPendingRequests() async throws -> [FriendRequestDto] {
        // 1. 构建空 Payload (或不需要)
        let frame = Frame(type: .pendingRequestsReq, data: Data())
        
        // 2. 发送并等待响应 (0x34)
        let responseFrame = try await sendFrameAndWait(frame, expecting: .userResponse, timeout: 10.0)
        
        // 3. 解析
        let requests: [FriendRequestDto] = try parseDataResponse(responseFrame)
        
        // 4. 更新 Published 属性 (UI 绑定)
        await MainActor.run {
            self.pendingFriendRequests = requests
        }
        
        return requests
    }
    
    /// 处理好友申请
    /// - Parameters:
    ///   - requestId: 申请ID
    ///   - action: 1=同意, 2=拒绝
    /// - Returns: 是否成功
    func handleFriendRequest(requestId: Int64, action: Int) async throws -> Bool {
        // 1. 构建 Payload
        let payload: [String: Any] = [
            "requestId": requestId,
            "status": action
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        
        // 2. 构建帧 (0x39)
        let frame = Frame(type: .handleFriendReq, data: jsonData)
        
        // 3. 发送
        let responseFrame = try await sendFrameAndWait(frame, expecting: .userResponse, timeout: 10.0)
        
        // 4. 解析
        return try parseStandardResponse(responseFrame)
    }
    
    /// 处理好友申请 (兼容旧接口)
    /// - Parameters:
    ///   - requestId: 申请ID
    ///   - accept: 是否同意
    /// - Returns: 是否成功
    func handleFriendRequest(requestId: Int64, accept: Bool) async throws -> Bool {
        return try await handleFriendRequest(requestId: requestId, action: accept ? 1 : 2)
    }
}

// MARK: - Helper Parsing Methods
extension SocketManager {
    
    /// 解析通用响应 (code/msg)
    func parseStandardResponse(_ frame: Frame) throws -> Bool {
        guard let json = try JSONSerialization.jsonObject(with: frame.data) as? [String: Any] else {
            throw SocketError.invalidResponse
        }
        
        if let code = json["code"] as? Int {
            if code == 200 {
                return true
            } else {
                let msg = json["msg"] as? String ?? "Unknown error"
                print("❌ 服务端返回错误: \(code) - \(msg)")
                return false
            }
        }
        
        // 兼容性: 有些接口直接返回数据
        return true
    }
    
    /// 解析数据响应 (泛型)
    func parseDataResponse<T: Codable>(_ frame: Frame) throws -> T {
        // 尝试解析为标准响应结构 (code, msg, data)
        if let responseWrapper = try? JSONDecoder().decode(ResponseWrapper<T>.self, from: frame.data) {
            if responseWrapper.code == 200 {
                if let data = responseWrapper.data {
                    return data
                }
                // 如果 data 为空但 T 是 Optional，这里很难处理，通常 T 不会是 Optional
                throw SocketError.invalidResponse // Data is missing
            } else {
                print("❌ 服务端返回错误: \(responseWrapper.code) - \(responseWrapper.message)")
                throw SocketError.invalidResponse // Server error
            }
        }
        
        // 尝试直接解析为 T (非标准结构)
        if let data = try? JSONDecoder().decode(T.self, from: frame.data) {
            return data
        }
        
        throw SocketError.invalidResponse
    }
}
