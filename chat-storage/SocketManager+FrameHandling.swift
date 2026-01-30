//
//  SocketManager+FrameHandling.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

// MARK: - Frame Handling Extension

extension SocketManager {
    
    /// 发送帧
    /// - Parameter frame: 要发送的帧
    /// - Throws: 发送失败时抛出错误
    func sendFrame(_ frame: Frame) throws {
        guard connectionState == .connected else {
            throw SocketError.notConnected
        }
        
        let bytes = frame.toBytes()
        let success = send(data: bytes)
        
        if !success {
            throw SocketError.sendFailed
        }
        
        print("📤 发送帧: \(frame.type.description), 长度: \(bytes.count) 字节")
    }
    
    /// 发送帧并等待响应
    /// - Parameters:
    ///   - frame: 要发送的帧
    ///   - responseType: 期望的响应帧类型
    ///   - timeout: 超时时间（秒，默认10秒）
    /// - Returns: 响应帧
    /// - Throws: 超时或其他错误
    func sendFrameAndWait(
        _ frame: Frame,
        expecting responseType: FrameTypeEnum,
        timeout: TimeInterval = 10.0
    ) async throws -> Frame {
        // 发送帧
        try sendFrame(frame)
        
        // 等待响应
        return try await withCheckedThrowingContinuation { continuation in
            // 存储 continuation
            continuationLock.lock()
            responseContinuations[responseType] = continuation
            continuationLock.unlock()
            
            // 设置超时
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                // 超时处理
                continuationLock.lock()
                if let storedContinuation = responseContinuations.removeValue(forKey: responseType) {
                    continuationLock.unlock()
                    storedContinuation.resume(throwing: SocketError.timeout)
                } else {
                    continuationLock.unlock()
                }
            }
        }
    }
    
    /// 启动接收循环
    func startReceiveLoop() {
        guard !isReceiving else { return }
        
        isReceiving = true
        receiveBuffer.removeAll()
        
        receiveThread = Thread { [weak self] in
            guard let self = self else { return }
            
            print("🔄 接收循环已启动")
            
            while self.isReceiving && self.connectionState == .connected {
                autoreleasepool {
                    self.receiveAndProcessFrames()
                }
                
                // 短暂休眠，避免 CPU 占用过高
                Thread.sleep(forTimeInterval: 0.01)
            }
            
            print("⏹️ 接收循环已停止")
        }
        
        receiveThread?.start()
    }
    
    /// 停止接收循环
    func stopReceiveLoop() {
        isReceiving = false
        receiveThread?.cancel()
        receiveThread = nil
        receiveBuffer.removeAll()
        
        // 清理所有等待中的 continuation
        continuationLock.lock()
        for (_, continuation) in responseContinuations {
            continuation.resume(throwing: SocketError.connectionClosed)
        }
        responseContinuations.removeAll()
        continuationLock.unlock()
    }
    
    /// 接收并处理帧
    private func receiveAndProcessFrames() {
        guard let inputStream = inputStream, inputStream.hasBytesAvailable else {
            return
        }
        
        // 读取数据到缓冲区
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
        
        if bytesRead > 0 {
            receiveBuffer.append(Data(bytes: buffer, count: bytesRead))
            
            // 尝试提取完整的帧
            while let (frame, remaining) = FrameParser.extractFrame(from: receiveBuffer) {
                receiveBuffer = remaining
                handleReceivedFrame(frame)
            }
        }
    }
    
    /// 处理接收到的帧
    private func handleReceivedFrame(_ frame: Frame) {
        print("📥 接收到帧: \(frame.type.description), 长度: \(frame.length) 字节")
        
        // 在主线程处理响应
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 查找对应的 continuation
            self.continuationLock.lock()
            if let continuation = self.responseContinuations.removeValue(forKey: frame.type) {
                self.continuationLock.unlock()
                continuation.resume(returning: frame)
            } else {
                self.continuationLock.unlock()
                // 未找到对应的等待者，可能是主动推送的消息
                print("⚠️ 收到未预期的帧类型: \(frame.type.description)")
            }
        }
    }
}

// MARK: - Socket Errors

enum SocketError: LocalizedError {
    case notConnected
    case sendFailed
    case timeout
    case connectionClosed
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Socket 未连接"
        case .sendFailed:
            return "发送数据失败"
        case .timeout:
            return "等待响应超时"
        case .connectionClosed:
            return "连接已关闭"
        case .invalidResponse:
            return "响应数据无效"
        }
    }
}
