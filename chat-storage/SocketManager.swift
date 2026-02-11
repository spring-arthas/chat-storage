//  全局socket连接
//  SocketManager.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation
import Combine

/// 全局 Socket 连接管理器
/// 负责维护与服务器的 TCP Socket 长连接
public class SocketManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    /// 单例实例
    static let shared = SocketManager()
    
    // MARK: - Published Properties (UI 可观察的状态)
    
    /// 当前连接状态
    @Published var connectionState: ConnectionState = .disconnected
    
    /// 最后的错误信息
    @Published var lastError: String?
    
    /// 接收到的消息（用于调试或日志）
    @Published var lastReceivedMessage: String?
    
    /// 上行速率 (UI 显示)
    @Published var uploadSpeedStr: String = "0 KB/s"
    
    /// 下行速率 (UI 显示)
    @Published var downloadSpeedStr: String = "0 KB/s"
    
    /// 待处理好友申请数量 (UI 显示)
    @Published var pendingRequestCount: Int = 0
    
    /// 待处理好友申请列表缓存
    @Published var pendingFriendRequests: [FriendRequestDto] = []
    
    // MARK: - Private Properties
    
    /// 输入流（从服务器接收数据）
    internal var inputStream: InputStream?
    
    /// 输出流（发送数据到服务器）
    internal var outputStream: OutputStream?
    
    /// 心跳定时器
    private var heartbeatTimer: Timer?
    
    /// 重连定时器
    private var reconnectTimer: Timer?
    
    /// 服务器地址（可动态配置）
    private var host: String = "172.21.32.120"  // 默认服务器地址  172.21.32.120 192.168.2.104  192.168.0.103
    
    /// 服务器端口（可动态配置）
    private var port: UInt32 = 10086
    
    // MARK: - Frame Handling Properties
    
    /// 接收数据缓冲区
    internal var receiveBuffer = Data()
    
    /// 响应等待队列（用于同步等待响应）
    /// 响应等待映射 (帧类型 -> 请求ID)
    internal var continuationTypeMap: [FrameTypeEnum: UUID] = [:]
    /// 活动的 Continuation (请求ID -> Continuation)
    internal var activeContinuations: [UUID: CheckedContinuation<Frame, Error>] = [:]
    
    /// 流式处理回调 (帧类型 -> 处理闭包)
    /// 用于处理如下载时的连续数据帧，闭包返回 true 表示继续处理，false 表示结束
    internal var streamHandlers: [FrameTypeEnum: (Frame) -> Bool] = [:]
    
    /// 响应队列锁
    internal let continuationLock = NSLock()
    
    /// 接收循环线程
    internal var receiveThread: Thread?
    
    /// 是否正在接收
    internal var isReceiving = false

    /// 写入流等待 Continuation
    private var writeStreamContinuation: CheckedContinuation<Void, Never>?
    private let writeLock = NSLock()
    
    /// 心跳间隔（秒）
    private let heartbeatInterval: TimeInterval = 30.0
    
    /// 重连间隔（秒）
    private let reconnectInterval: TimeInterval = 3.0
    
    /// 最大重连次数
    private let maxReconnectAttempts: Int = 5
    
    /// 当前重连次数
    private var reconnectAttempts: Int = 0
    
    // MARK: - Speed Statistics
    
    private var totalBytesSent: Int64 = 0
    private var totalBytesReceived: Int64 = 0
    private var lastBytesSent: Int64 = 0
    private var lastBytesReceived: Int64 = 0
    private var speedTimer: Timer?
    private let speedLock = NSLock()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        print("📱 SocketManager 初始化完成")
    }
    
    deinit {
        disconnect(notifyUI: false)
    }
    
    // MARK: - Connection Management
    
    // MARK: - Dynamic Configuration
    
    /// 测试连接到指定服务器
    /// - Parameters:
    ///   - host: 服务器地址
    ///   - port: 服务器端口
    ///   - completion: 完成回调（成功/失败）
    func testConnection(host: String, port: UInt32, completion: @escaping (Bool) -> Void) {
        print("🧪 测试连接: \(host):\(port)")
        
        DispatchQueue.global(qos: .userInitiated).async {
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
                print("❌ 测试连接失败：无法创建 Socket 流")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            let testInputStream = readStreamRef as InputStream
            let testOutputStream = writeStreamRef as OutputStream
            
            // 设置超时
            testInputStream.schedule(in: .current, forMode: .default)
            testOutputStream.schedule(in: .current, forMode: .default)
            
            testInputStream.open()
            testOutputStream.open()
            
            // 等待连接结果（最多3秒）
            var attempts = 0
            let maxAttempts = 30  // 3秒（每次100ms）
            
            while attempts < maxAttempts {
                if testInputStream.streamStatus == .open && testOutputStream.streamStatus == .open {
                    print("✅ 测试连接成功")
                    
                    // 关闭测试连接
                    testInputStream.close()
                    testOutputStream.close()
                    testInputStream.remove(from: .current, forMode: .default)
                    testOutputStream.remove(from: .current, forMode: .default)
                    
                    DispatchQueue.main.async {
                        completion(true)
                    }
                    return
                }
                
                if testInputStream.streamStatus == .error || testOutputStream.streamStatus == .error {
                    print("❌ 测试连接失败：流错误")
                    testInputStream.close()
                    testOutputStream.close()
                    testInputStream.remove(from: .current, forMode: .default)
                    testOutputStream.remove(from: .current, forMode: .default)
                    
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                
                Thread.sleep(forTimeInterval: 0.1)
                attempts += 1
            }
            
            // 超时
            print("❌ 测试连接超时")
            testInputStream.close()
            testOutputStream.close()
            testInputStream.remove(from: .current, forMode: .default)
            testOutputStream.remove(from: .current, forMode: .default)
            
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
    
    /// 切换到新的服务器连接
    /// - Parameters:
    ///   - host: 新服务器地址
    ///   - port: 新服务器端口
    func switchConnection(host: String, port: UInt32) {
        print("🔄 切换服务器: \(host):\(port)")
        
        // 断开旧连接
        disconnect()
        
        // 更新配置
        self.host = host
        self.port = port
        
        // 连接新服务器
        connect()
    }
    
    /// 获取当前服务器配置
    /// - Returns: (host, port)
    func getCurrentServer() -> (host: String, port: UInt32) {
        return (host, port)
    }
    
    // MARK: - Connection Management
    
    /// 连接到服务器
    func connect() {
        // 避免重复连接
        guard connectionState != .connecting && connectionState != .connected else {
            print("⚠️ Socket 已在连接中或已连接，跳过")
            return
        }
        
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
        stopReceiveLoop()  // 停止接收循环
        stopSpeedTimer()   // 停止测速
        
        inputStream?.close()
        outputStream?.close()
        
        inputStream?.remove(from: .current, forMode: .common)
        outputStream?.remove(from: .current, forMode: .common)
        
        inputStream?.delegate = nil
        outputStream?.delegate = nil
        
        inputStream = nil
        outputStream = nil
        
        if notifyUI {
            updateState(.disconnected)
        }
        reconnectAttempts = 0
        
        // 唤醒所有等待写入的任务，避免死锁
        writeLock.lock()
        if let continuation = writeStreamContinuation {
            writeStreamContinuation = nil
            // 恢复以便任务可以继续执行（然后发现连接已断开并报错）
            continuation.resume()
        }
        writeLock.unlock()
    }
    
    // MARK: - Data Transmission
    
    /// 等待输出流变为可写
    func waitForWritable() async {
        guard let outputStream = outputStream else { return }
        
        // 如果当前已经有空间，直接返回
        if outputStream.hasSpaceAvailable {
            return
        }
        
        // 否则挂起等待
        await withCheckedContinuation { continuation in
            writeLock.lock()
            // 双重检查
            if outputStream.hasSpaceAvailable {
                writeLock.unlock()
                continuation.resume()
                return
            }
            
            // 如果已有等待者，唤醒旧的以避免死锁（虽然理想情况不应发生）
            if let existing = writeStreamContinuation {
                existing.resume()
            }
            
            writeStreamContinuation = continuation
            writeLock.unlock()
        }
    }
    
    /// 发送数据到服务器
    /// - Parameter data: 要发送的数据
    /// - Returns: 是否发送成功
    @discardableResult
    func send(data: Data) -> Bool {
        guard connectionState == .connected else {
            print("❌ Socket 未连接，无法发送数据")
            return false
        }
        
        guard let outputStream = outputStream else {
            print("❌ 输出流不可用")
            return false
        }
        
        var totalBytesWritten = 0
        let totalBytes = data.count
        
        // 循环发送直到全部数据发送完毕
        while totalBytesWritten < totalBytes {
            let bytesToWrite = totalBytes - totalBytesWritten
            
            // 使用 withUnsafeBytes 访问数据
            let bytesWritten = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
                guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                // 偏移地址
                let currentAddress = baseAddress.advanced(by: totalBytesWritten)
                return outputStream.write(currentAddress, maxLength: bytesToWrite)
            }
            
            if bytesWritten > 0 {
                totalBytesWritten += bytesWritten
            } else if bytesWritten == 0 {
                // 缓冲区满，无法写入？由于是同步方法，这里其实很尴尬。
                // 但如果外部正确使用了 waitForWritable，这里几率很小。
                // 如果真的遇到0，可能需要稍作等待或返回失败（会断开连接）
                // 简单处理：如果写不进去，认为失败，由上层重试或断开
                print("❌ 发送数据受阻 (写入0字节)")
                return false
            } else {
                print("❌ 发送数据失败 (Stream Error)")
                return false
            }
        }
        
        // 统计流量
        speedLock.lock()
        totalBytesSent += Int64(totalBytesWritten)
        speedLock.unlock()
        
        // print("📤 发送数据成功: \(totalBytesWritten) 字节")
        return true
    }
    
    /// 发送字符串消息
    /// - Parameter message: 要发送的字符串
    /// - Returns: 是否发送成功
    @discardableResult
    func send(message: String) -> Bool {
        guard let data = message.data(using: .utf8) else {
            print("❌ 字符串转换为数据失败")
            return false
        }
        return send(data: data)
    }
    
    // MARK: - Heartbeat
    
    /// 启动心跳
    private func startHeartbeat() {
        stopHeartbeat()
        
        print("💓 启动心跳，间隔: \(heartbeatInterval) 秒")
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }
    
    /// 停止心跳
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    /// 发送心跳包
    private func sendHeartbeat() {
        print("💓 发送心跳包")
        send(message: "PING\n")
    }
    
    // MARK: - Auto Reconnect
    
    /// 启动自动重连
    private func startReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ 达到最大重连次数 (\(maxReconnectAttempts))，停止重连")
            updateState(.failed)
            lastError = "连接失败：达到最大重连次数"
            return
        }
        
        reconnectAttempts += 1
        updateState(.reconnecting)
        
        print("🔄 将在 \(reconnectInterval) 秒后尝试第 \(reconnectAttempts) 次重连...")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectInterval, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
    
    /// 停止自动重连
    private func stopReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // MARK: - State Management
    
    /// 更新连接状态
    /// - Parameter state: 新状态
    private func updateState(_ state: ConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
            print("📊 连接状态更新: \(state)")
        }
    }
    
    /// 处理连接错误
    /// - Parameter message: 错误信息
    private func handleConnectionError(_ message: String) {
        print("❌ 连接错误: \(message)")
        
        DispatchQueue.main.async {
            self.lastError = message
        }
        
        updateState(.disconnected)
        
        // 自动重连
        if reconnectAttempts < maxReconnectAttempts {
            startReconnect()
        }
    }
    
    // MARK: - Data Reception
    
    /// 读取接收到的数据
    private func readAvailableData() {
        guard let inputStream = inputStream else { return }
        
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
            
            if bytesRead > 0 {
                speedLock.lock()
                totalBytesReceived += Int64(bytesRead)
                speedLock.unlock()
                
                let data = Data(bytes: buffer, count: bytesRead)
                
                if let message = String(data: data, encoding: .utf8) {
                    print("📥 接收到数据: \(message)")
                    
                    DispatchQueue.main.async {
                        self.lastReceivedMessage = message
                    }
                    
                    // TODO: 在这里处理接收到的消息
                    handleReceivedMessage(message)
                }
            } else if bytesRead < 0 {
                print("❌ 读取数据时发生错误")
                handleConnectionError("读取数据失败")
                break
            }
        }
    }
    
    /// 处理接收到的消息
    /// - Parameter message: 接收到的消息字符串
    private func handleReceivedMessage(_ message: String) {
        // TODO: 根据您的协议解析消息
        // 例如：JSON 解析、命令分发等
        
        if message.contains("PONG") {
            print("💓 收到心跳响应")
        }
    }
    
    // MARK: - Speed Calculation
    
    private func startSpeedTimer() {
        stopSpeedTimer()
        // 在主线程执行定时器
        DispatchQueue.main.async {
            self.speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.calculateSpeed()
            }
        }
    }
    
    private func stopSpeedTimer() {
        speedTimer?.invalidate()
        speedTimer = nil
    }
    
    private func calculateSpeed() {
        speedLock.lock()
        let currentSent = totalBytesSent
        let currentReceived = totalBytesReceived
        speedLock.unlock()
        
        let sentDelta = currentSent - lastBytesSent
        let receivedDelta = currentReceived - lastBytesReceived
        
        lastBytesSent = currentSent
        lastBytesReceived = currentReceived
        
        DispatchQueue.main.async {
            self.uploadSpeedStr = self.formatSpeed(sentDelta)
            self.downloadSpeedStr = self.formatSpeed(receivedDelta)
        }
    }
    
    private func formatSpeed(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B/s"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB/s", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB/s", Double(bytes) / (1024.0 * 1024.0))
        }
    }
    
    /// 记录接收到的字节数 (供 Extension 使用)
    internal func recordBytesReceived(_ count: Int64) {
        speedLock.lock()
        totalBytesReceived += count
        speedLock.unlock()
    }
    
    // MARK: - User Search
    
    /// 搜索用户
    /// - Parameter userName: 用户名关键词
    /// - Returns: 用户列表
    func searchUser(userName: String) async throws -> [UserDto] {
        // 1. 构建请求模型
        let request = UserSearchRequest(userName: userName)
        let jsonData = try JSONEncoder().encode(request)
        
        // 2. 构建帧 (0x36)
        let frame = Frame(type: .searchUserReq, data: jsonData)
        
        // 3. 发送并等待响应
        // 服务端返回的是 userResponse (0x34) 而不是 searchUserReq (0x36)
        // 错误日志显示: "收到未预期的帧类型: 用户操作响应"
        let responseFrame = try await sendFrameAndWait(frame, expecting: .userResponse, timeout: 10.0)
        
        // 4. 解析响应
        // 先尝试解析为标准响应结构 (code, message, data)
        if let jsonObject = try? JSONSerialization.jsonObject(with: responseFrame.data, options: []) as? [String: Any] {
            // 情况A: 包含 code/data 的标准响应
            if let data = jsonObject["data"] {
                let dataData = try JSONSerialization.data(withJSONObject: data)
                // 尝试解析为列表
                if let users = try? JSONDecoder().decode([UserDto].self, from: dataData) {
                    return users
                }
                // 尝试解析为单个对象
                if let user = try? JSONDecoder().decode(UserDto.self, from: dataData) {
                    return [user]
                }
            }
            
            // 情况B: 直接是列表或对象 (后端可能直接返回了数据)
            // 尝试全量解析为列表
            if let users = try? JSONDecoder().decode([UserDto].self, from: responseFrame.data) {
                return users
            }
            // 尝试全量解析为单个对象 (如截图所示似乎是单个对象)
            if let user = try? JSONDecoder().decode(UserDto.self, from: responseFrame.data) {
                return [user]
            }
        }
        
        // 如果都失败，抛出错误
        throw SocketError.invalidResponse
    }
    
    // MARK: - Friend Request Management
    
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
        
        // 3. 解析响应数据
        let requests: [FriendRequestDto] = try parseDataResponse(responseFrame)
        
        // 4. 更新状态 (MainActor)
        await MainActor.run {
            self.pendingFriendRequests = requests
            self.pendingRequestCount = requests.count
        }
        
        return requests
    }
    
    /// 处理好友申请
    /// - Parameters:
    ///   - requestId: 申请记录ID
    ///   - action: 1=同意, 2=拒绝
    /// - Returns: 是否成功
    func handleFriendRequest(requestId: Int64, action: Int) async throws -> Bool {
        // 1. 构建请求 Payload
        let payload: [String: Any] = [
            "requestId": requestId,
            "action": action
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        
        // 2. 构建帧 (0x39)
        let frame = Frame(type: .handleFriendReq, data: jsonData)
        
        // 3. 发送并等待响应 (0x34)
        let responseFrame = try await sendFrameAndWait(frame, expecting: .userResponse, timeout: 10.0)
        
        // 4. 解析通用响应
        return try parseStandardResponse(responseFrame)
    }
    
    // MARK: - Helper Parsing Methods
    
    /// 解析标准响应 (code/msg)
    private func parseStandardResponse(_ frame: Frame) throws -> Bool {
        guard let jsonResult = try? JSONSerialization.jsonObject(with: frame.data) as? [String: Any] else {
            throw SocketError.invalidResponse
        }
        
        if let code = jsonResult["code"] as? Int {
            if code == 200 { return true }
            let msg = jsonResult["message"] as? String ?? "Unknown error"
            print("❌ 操作失败: \(msg)")
            throw DirectoryError.serverError(code: code, message: msg)
        }
        // Fallback: 假设没有 code 字段就是成功 (视后端实现而定)
        return true
    }
    
    /// 解析带数据的响应 (T)
    private func parseDataResponse<T: Decodable>(_ frame: Frame) throws -> T {
        // 1. 尝试解析为标准结构 {"code": 200, "data": ...}
        if let jsonObject = try? JSONSerialization.jsonObject(with: frame.data, options: []) as? [String: Any],
           let data = jsonObject["data"] {
            let dataData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(T.self, from: dataData)
        }
        
        // 2. 尝试直接解析数据
        return try JSONDecoder().decode(T.self, from: frame.data)
    }

}

// MARK: - StreamDelegate

extension SocketManager: StreamDelegate {
    
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            print("✅ Stream 打开完成")
            
            // 两个流都打开后才算连接成功
            if inputStream?.streamStatus == .open && outputStream?.streamStatus == .open {
                updateState(.connected)
                reconnectAttempts = 0  // 重置重连次数
                startHeartbeat()
                startReceiveLoop()  // 启动接收循环
                startSpeedTimer()   // 启动测速
                print("🎉 Socket 连接成功！")
            }
            
        case .hasBytesAvailable:
            if aStream == inputStream {
                // 调用帧处理方法（在 SocketManager+FrameHandling.swift 中定义）
                receiveAndProcessFrames()
                
                // 也要尝试读取普通数据（如果不是用 Frame 处理的话）
                // readAvailableData() 
                // 注意：如果使用了 receiveAndProcessFrames (FrameHandling)，就不应该同时调用 readAvailableData，除非它们处理不同的协议或者有分发机制。
                // 之前的代码中似乎是 readAvailableData 被删掉了调用，或者混用了。
                // 这里我们保留 readAvailableData 作为备用，或者让 receiveAndProcessFrames 负责统计流量?
                // FrameHandling extension 中应该也有读取数据的逻辑。让我们确保那里也做了统计。
            }
            
        case .hasSpaceAvailable:
            // print("📝 输出流有可用空间")
            
            // 唤醒等待写入的任务
            writeLock.lock()
            if let continuation = writeStreamContinuation {
                writeStreamContinuation = nil
                writeLock.unlock()
                continuation.resume()
            } else {
                writeLock.unlock()
            }
            
        case .errorOccurred:
            if let error = aStream.streamError {
                handleConnectionError("Stream 错误: \(error.localizedDescription)")
            }
            
        case .endEncountered:
            print("🔌 连接已关闭")
            disconnect()
            
            // 断线后自动重连
            if reconnectAttempts < maxReconnectAttempts {
                startReconnect()
            }
            
        default:
            print("⚠️ 未处理的 Stream 事件: \(eventCode)")
        }
    }
}

// MARK: - ConnectionState Enum

extension SocketManager {
    
    /// 连接状态枚举
    enum ConnectionState {
        case disconnected   // 未连接
        case connecting     // 连接中
        case connected      // 已连接
        case reconnecting   // 重连中
        case failed         // 连接失败
        
        var description: String {
            switch self {
            case .disconnected: return "未连接"
            case .connecting: return "连接中..."
            case .connected: return "已连接"
            case .reconnecting: return "重连中..."
            case .failed: return "连接失败"
            }
        }
        
        var color: String {
            switch self {
            case .disconnected: return "gray"
            case .connecting: return "blue"
            case .connected: return "green"
            case .reconnecting: return "orange"
            case .failed: return "red"
            }
        }
    }
}
