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
    
    /// 注册响应等待
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
    
    /// 移除并触发响应等待 (用于超时或错误)
    private func removeAndResumeContinuation(for id: UUID, with error: Error) {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        
        if let continuation = activeContinuations.removeValue(forKey: id) {
            // 清理类型映射
            let keysToRemove = continuationTypeMap.filter { $0.value == id }.map { $0.key }
            for key in keysToRemove {
                continuationTypeMap.removeValue(forKey: key)
            }
            continuation.resume(throwing: error)
        }
    }
    
    /// 发送帧并等待响应 (支持多种可能的响应类型)
    /// - Parameters:
    ///   - frame: 要发送的帧
    ///   - responseTypes: 期望的响应帧类型集合
    ///   - timeout: 超时时间（秒，默认10秒）
    /// - Returns: 响应帧
    func sendFrameAndWait(
        _ frame: Frame,
        expectingOneOf responseTypes: Set<FrameTypeEnum>,
        timeout: TimeInterval = 10.0
    ) async throws -> Frame {
        // 发送帧
        try sendFrame(frame)
        
        // 等待响应
        return try await withCheckedThrowingContinuation { continuation in
            // 注册 continuation
            let id = registerContinuation(continuation, for: responseTypes)
            
            // 设置超时
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                // 超时处理
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
    
    /// 启动接收循环（在独立线程中运行，通过 StreamDelegate 回调触发数据读取）
    func startReceiveLoop() {
        guard !isReceiving else { 
            print("⚠️ 接收循环已在运行中")
            return 
        }
        
        isReceiving = true
        receiveBuffer.removeAll()
        
        print("🔄 接收循环已启动（事件驱动模式）")
        print("📌 注意：数据接收由 StreamDelegate 的 hasBytesAvailable 事件触发")
    }
    
    /// 停止接收循环
    func stopReceiveLoop() {
        print("🛑 正在停止接收循环...")
        
        isReceiving = false
        receiveBuffer.removeAll()
        
        // 清理所有等待中的 continuation
        continuationLock.lock()
        for (_, continuation) in activeContinuations {
            continuation.resume(throwing: SocketError.connectionClosed)
        }
        activeContinuations.removeAll()
        continuationTypeMap.removeAll()
        continuationLock.unlock()
        
        print("✅ 接收循环已完全停止")
    }
    
    /// 接收并处理帧（由 StreamDelegate 的 hasBytesAvailable 事件触发）
    /// 这个方法会在主线程的 RunLoop 中被调用
    func receiveAndProcessFrames() {
        guard isReceiving else {
            print("⚠️ 接收循环未启动，跳过数据处理")
            return
        }
        
        guard let inputStream = inputStream else {
            print("❌ 输入流不可用")
            return
        }
        
        // 检查流状态
        guard inputStream.streamStatus == .open else {
            print("⚠️ 输入流状态异常: \(inputStream.streamStatus.rawValue)")
            return
        }
        
        // 只有在有数据可读时才读取
        guard inputStream.hasBytesAvailable else {
            return
        }
        
        // 读取数据到缓冲区
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
        
        if bytesRead > 0 {
            // 记录接收流量
            self.recordBytesReceived(Int64(bytesRead))
        
            // 成功读取数据
            receiveBuffer.append(Data(bytes: buffer, count: bytesRead))
            print("📥 读取到 \(bytesRead) 字节数据，缓冲区总大小: \(receiveBuffer.count) 字节")
            
            // 尝试提取并处理完整的帧
            var frameCount = 0
            while let (frame, remaining) = FrameParser.extractFrame(from: receiveBuffer) {
                receiveBuffer = remaining
                frameCount += 1
                
                // 处理帧 (handleReceivedFrame 不抛出错误，无需 do-catch)
                handleReceivedFrame(frame)
            }
            
            if frameCount > 0 {
                print("✅ 本次共处理 \(frameCount) 个完整帧，剩余缓冲区: \(receiveBuffer.count) 字节")
            }
            
        } else if bytesRead == 0 {
            // 连接已关闭
            print("⚠️ 读取到 0 字节，连接可能已关闭")
            
        } else {
            // 读取错误
            if let error = inputStream.streamError {
                print("❌ 读取数据时发生流错误: \(error.localizedDescription)")
            } else {
                print("❌ 读取数据时发生未知错误")
            }
        }
    }
    
    /// 处理接收到的帧
    private func handleReceivedFrame(_ frame: Frame) {
        print("📥 接收到帧: \(frame.type.description), 长度: \(frame.length) 字节")
        
        // 打印可视化的帧数据
        printFrameVisualization(frame)
        
        // 在主线程处理响应
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.resumeContinuation(for: frame)
        }
    }
    
    /// 恢复等待的 continuation
    private func resumeContinuation(for frame: Frame) {
        self.continuationLock.lock()
        defer { self.continuationLock.unlock() }
        
        if let id = self.continuationTypeMap[frame.type],
           let continuation = self.activeContinuations.removeValue(forKey: id) {
            
            // 清理该 ID 对应的所有类型映射
            let keysToRemove = self.continuationTypeMap.filter { $0.value == id }.map { $0.key }
            for key in keysToRemove {
                self.continuationTypeMap.removeValue(forKey: key)
            }
            
            continuation.resume(returning: frame)
        } else {
            // 未找到对应的等待者，可能是主动推送的消息
            print("⚠️ 收到未预期的帧类型: \(frame.type.description) (No waiter found)")
            // 这里可以添加对未预期帧的全局处理逻辑
        }
    }
    
    /// 打印帧的可视化数据（用于调试）
    /// - Parameter frame: 要打印的帧
    private func printFrameVisualization(_ frame: Frame) {
        print("┌─────────────────────────────────────────────────────────────")
        print("│ 📦 帧数据详情")
        print("├─────────────────────────────────────────────────────────────")
        print("│ 类型: \(frame.type.description) (0x\(String(format: "%02X", frame.type.rawValue)))")
        print("│ 标志位: 0x\(String(format: "%02X", frame.flags))")
        print("│ 数据长度: \(frame.length) 字节")
        print("├─────────────────────────────────────────────────────────────")
        
        // 打印十六进制数据（仅前256字节，避免过长）
        let hexDataLimit = min(256, frame.data.count)
        if hexDataLimit > 0 {
            print("│ 📋 十六进制数据 (前 \(hexDataLimit) 字节):")
            let hexData = frame.data.prefix(hexDataLimit)
            let hexString = hexData.map { String(format: "%02X", $0) }.joined(separator: " ")
            
            // 每行显示32字节
            let bytesPerLine = 32
            var offset = 0
            while offset < hexString.count {
                let endIndex = min(offset + bytesPerLine * 3 - 1, hexString.count - 1)
                let line = String(hexString[hexString.index(hexString.startIndex, offsetBy: offset)...hexString.index(hexString.startIndex, offsetBy: endIndex)])
                print("│   \(line)")
                offset += bytesPerLine * 3
            }
            
            if frame.data.count > hexDataLimit {
                print("│   ... (还有 \(frame.data.count - hexDataLimit) 字节未显示)")
            }
            print("├─────────────────────────────────────────────────────────────")
        }
        
        // 尝试解析并打印 JSON 数据
        if let jsonString = String(data: frame.data, encoding: .utf8) {
            print("│ 📄 JSON 数据:")
            
            // 尝试格式化 JSON
            if let jsonData = jsonString.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []),
               let prettyJsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let prettyJsonString = String(data: prettyJsonData, encoding: .utf8) {
                
                // 为每行添加前缀
                let lines = prettyJsonString.components(separatedBy: "\n")
                for line in lines {
                    print("│   \(line)")
                }
            } else {
                // 如果格式化失败，直接打印原始字符串
                print("│   \(jsonString)")
            }
        } else {
            print("│ ⚠️  数据不是有效的 UTF-8 字符串")
        }
        
        print("└─────────────────────────────────────────────────────────────")
        
        // 针对特定帧类型的额外处理
        printFrameTypeSpecificInfo(frame)
    }
    
    /// 打印特定帧类型的额外信息
    /// - Parameter frame: 帧对象
    private func printFrameTypeSpecificInfo(_ frame: Frame) {
        switch frame.type {
        case .userResponse:
            print("🔐 用户操作响应帧详情:")
            if let dict = try? FrameParser.decodeAsDictionary(frame) {
                if let code = dict["code"] as? Int {
                    print("  ├─ 响应码: \(code) \(getResponseCodeDescription(code))")
                }
                if let message = dict["message"] as? String {
                    print("  ├─ 消息: \(message)")
                }
                if let data = dict["data"] {
                    print("  └─ 数据: \(data)")
                }
            }
            
        case .dirResponse:
            print("📁 目录操作响应帧详情:")
            if let dict = try? FrameParser.decodeAsDictionary(frame) {
                if let code = dict["code"] as? Int {
                    print("  ├─ 响应码: \(code) \(getResponseCodeDescription(code))")
                }
                if let message = dict["message"] as? String {
                    print("  └─ 消息: \(message)")
                }
            }
            
        case .fileResponse:
            print("📄 文件操作响应帧详情:")
            if let dict = try? FrameParser.decodeAsDictionary(frame) {
                if let code = dict["code"] as? Int {
                    print("  ├─ 响应码: \(code) \(getResponseCodeDescription(code))")
                }
                if let message = dict["message"] as? String {
                    print("  └─ 消息: \(message)")
                }
            }
            
        case .ackFrame:
            print("✅ 确认帧详情:")
            if let dict = try? FrameParser.decodeAsDictionary(frame) {
                print("  └─ 确认数据: \(dict)")
            }
            
        case .resumeAck:
            print("⏸️ 断点续传应答帧详情:")
            if let dict = try? FrameParser.decodeAsDictionary(frame) {
                if let uploadedSize = dict["uploadedSize"] as? Int {
                    print("  ├─ 已上传大小: \(uploadedSize) 字节")
                }
                if let canResume = dict["canResume"] as? Bool {
                    print("  └─ 可续传: \(canResume ? "是" : "否")")
                }
            }
            
        default:
            break
        }
    }
    
    /// 获取响应码的描述
    /// - Parameter code: 响应码
    /// - Returns: 描述文本
    private func getResponseCodeDescription(_ code: Int) -> String {
        switch code {
        case 200: return "✅ 成功"
        case 400: return "❌ 请求错误"
        case 401: return "🔒 未授权"
        case 403: return "🚫 禁止访问"
        case 404: return "🔍 未找到"
        case 500: return "💥 服务器错误"
        default: return ""
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
