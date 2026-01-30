//
//  ConfigServerView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import SwiftUI

struct ConfigServerView: View {
    // MARK: - Environment
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var socketManager: SocketManager
    
    // MARK: - State Variables
    
    /// 服务器地址输入（格式：IP:Port）
    @State private var serverAddress: String = ""
    
    /// 状态提示信息
    @State private var statusMessage: String = ""
    
    /// 状态提示颜色
    @State private var statusColor: Color = .gray
    
    /// 是否正在测试连接
    @State private var isTesting: Bool = false
    
    /// 新连接是否已就绪
    @State private var isNewConnectionReady: Bool = false
    
    /// 新连接的配置（测试成功后保存）
    @State private var newHost: String = ""
    @State private var newPort: UInt32 = 0
    
    /// 是否需要自动关闭窗体（点击确定后）
    @State private var shouldAutoDismiss: Bool = false
    
    /// 旋转角度（用于加载图标动画）
    @State private var rotationAngle: Double = 0
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 25) {
            
            // 标题
            Text("配置服务端地址")
                .font(.title)
                .fontWeight(.bold)
            
            // 当前服务器显示（美化版）
            VStack(alignment: .leading, spacing: 8) {
                Text("当前服务器")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                let currentServer = socketManager.getCurrentServer()
                
                // 卡片式展示
                VStack(spacing: 12) {
                    // 服务器地址行
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("服务器地址")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(currentServer.host):\(currentServer.port)")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                    }
                    
                    Divider()
                    
                    // 连接状态行
                    HStack {
                        Image(systemName: connectionStatusIcon)
                            .foregroundColor(connectionStatusColor)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("连接状态")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(connectionStatusColor)
                                    .frame(width: 8, height: 8)
                                
                                Text(connectionStatusText)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(connectionStatusColor)
                            }
                        }
                        
                        Spacer()
                        
                        // 连接状态徽章
                        Text(connectionStatusBadge)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(connectionStatusColor.opacity(0.15))
                            .foregroundColor(connectionStatusColor)
                            .cornerRadius(12)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(connectionStatusColor.opacity(0.3), lineWidth: 1.5)
                        )
                )
            }
            .frame(width: 350)
            
            // 服务器地址输入
            VStack(alignment: .leading, spacing: 8) {
                Text("新服务器地址")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("格式: IP:Port 或 域名:Port", text: $serverAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 350)
                    .onChange(of: serverAddress) { _ in
                        // 用户修改地址时，清除状态
                        if isNewConnectionReady {
                            isNewConnectionReady = false
                            statusMessage = ""
                        }
                    }
                
                Text("例如: 192.168.1.100:8080")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 状态提示
            if !statusMessage.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    
                    Text(statusMessage)
                        .foregroundColor(statusColor)
                        .font(.body)
                }
                .frame(width: 350, alignment: .leading)
            }
            
            // 按钮区域
            HStack(spacing: 20) {
                // 测试连接按钮
                Button(action: handleTestConnection) {
                    HStack(spacing: 8) {
                        if isTesting {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .rotationEffect(.degrees(rotationAngle))
                        }
                        Text(isTesting ? "连接中..." : "测试连接")
                    }
                    .frame(width: 160, height: 40)
                    .background(isTesting ? Color.orange.opacity(0.7) : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isTesting)
                
                // 确定按钮
                Button(action: handleConfirm) {
                    HStack(spacing: 8) {
                        if isTesting {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .rotationEffect(.degrees(rotationAngle))
                        }
                        Text(isTesting ? "连接中..." : "确定")
                    }
                    .frame(width: 160, height: 40)
                    .background(isTesting ? Color.blue.opacity(0.7) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isTesting)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 450, height: 480)  // 增加高度，避免内容被遮挡
        .onAppear {
            // 初始化为当前服务器地址
            let current = socketManager.getCurrentServer()
            serverAddress = "\(current.host):\(current.port)"
        }
    }
    
    // MARK: - Computed Properties (连接状态展示)
    
    /// 连接状态图标
    private var connectionStatusIcon: String {
        switch socketManager.connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "arrow.clockwise.circle.fill"
        case .reconnecting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .disconnected:
            return "xmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    /// 连接状态颜色
    private var connectionStatusColor: Color {
        switch socketManager.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .reconnecting:
            return .orange
        case .disconnected:
            return .gray
        case .failed:
            return .red
        }
    }
    
    /// 连接状态文字
    private var connectionStatusText: String {
        switch socketManager.connectionState {
        case .connected:
            return "连接正常"
        case .connecting:
            return "连接中..."
        case .reconnecting:
            return "重连中..."
        case .disconnected:
            return "未连接"
        case .failed:
            return "连接失败"
        }
    }
    
    /// 连接状态徽章
    private var connectionStatusBadge: String {
        switch socketManager.connectionState {
        case .connected:
            return "正常"
        case .connecting:
            return "连接中"
        case .reconnecting:
            return "重连中"
        case .disconnected:
            return "断开"
        case .failed:
            return "异常"
        }
    }
    
    // MARK: - Event Handlers
    
    /// 处理测试连接
    private func handleTestConnection() {
        // 验证地址格式
        guard let (host, port) = validateServerAddress(serverAddress) else {
            statusMessage = "地址格式错误，请使用 IP:Port 格式"
            statusColor = .red
            return
        }
        
        // 禁用按钮，开始测试
        statusMessage = "正在断开旧连接..."
        statusColor = .blue
        isTesting = true
        isNewConnectionReady = false
        
        // 启动旋转动画
        startRotationAnimation()
        
        // 如果是直接点击测试按钮，不自动关闭窗体
        // 只有点击确定按钮才自动关闭
        
        // 步骤 1: 先断开现有连接
        socketManager.disconnect()
        
        // 等待断开完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // 步骤 2: 更新状态提示
            statusMessage = "正在连接新服务器..."
            statusColor = .blue
            
            // 步骤 3: 切换到新服务器（会自动连接）
            socketManager.switchConnection(host: host, port: port)
            
            // 步骤 4: 等待连接结果（最多5秒）
            var checkCount = 0
            let maxChecks = 50  // 5秒 = 50 * 100ms
            
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                checkCount += 1
                
                // 检查连接状态
                if socketManager.connectionState == .connected {
                    // 连接成功
                    timer.invalidate()
                    isTesting = false
                    isNewConnectionReady = true
                    statusMessage = "远程服务端连接成功"
                    statusColor = .green
                    
                    // 停止旋转动画
                    stopRotationAnimation()
                    
                    // 保存新配置
                    newHost = host
                    newPort = port
                    
                    // 如果是点击确定按钮触发的，自动关闭窗体
                    if shouldAutoDismiss {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    }
                    
                } else if socketManager.connectionState == .failed || checkCount >= maxChecks {
                    // 连接失败或超时
                    timer.invalidate()
                    isTesting = false
                    isNewConnectionReady = false
                    
                    // 停止旋转动画
                    stopRotationAnimation()
                    
                    if checkCount >= maxChecks {
                        statusMessage = "连接超时，请检查地址和网络"
                    } else {
                        statusMessage = "连接失败，请检查地址和网络"
                    }
                    statusColor = .red
                }
            }
        }
    }
    
    /// 处理确定按钮
    private func handleConfirm() {
        if isNewConnectionReady {
            // 新连接已就绪，直接关闭
            dismiss()
        } else {
            // 设置自动关闭标志
            shouldAutoDismiss = true
            
            // 执行测试连接逻辑（连接成功后会自动关闭）
            handleTestConnection()
        }
    }
    
    /// 验证服务器地址格式
    /// - Parameter address: 地址字符串（格式：host:port）
    /// - Returns: (host, port) 或 nil
    private func validateServerAddress(_ address: String) -> (host: String, port: UInt32)? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        
        guard parts.count == 2 else {
            return nil
        }
        
        let host = String(parts[0]).trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            return nil
        }
        
        guard let port = UInt32(parts[1]),
              port > 0 && port <= 65535 else {
            return nil
        }
        
        return (host, port)
    }
    
    // MARK: - Animation Helpers
    
    /// 启动旋转动画
    private func startRotationAnimation() {
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
    
    /// 停止旋转动画
    private func stopRotationAnimation() {
        withAnimation {
            rotationAngle = 0
        }
    }
}

// MARK: - Preview

struct ConfigServerView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigServerView()
            .environmentObject(SocketManager.shared)
    }
}
