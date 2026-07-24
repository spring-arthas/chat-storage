//
//  ConfigServerView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import SwiftUI
import Network

struct ServerEndpoint: Equatable {
    let host: String
    let port: UInt32
}

enum ServerConnectionProbe {
    static func test(
        endpoint: ServerEndpoint,
        timeout: TimeInterval = 5,
        completion: @escaping (Bool) -> Void
    ) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(endpoint.port)) else {
            completion(false)
            return
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: port,
            using: .tcp
        )
        let queue = DispatchQueue(label: "duyao.chat-storage.server-probe")
        let completionState = ManagedCriticalState(false)

        let finish: (Bool) -> Void = { success in
            let shouldComplete = completionState.withCriticalRegion { hasCompleted in
                guard !hasCompleted else { return false }
                hasCompleted = true
                return true
            }
            guard shouldComplete else { return }

            connection.cancel()
            DispatchQueue.main.async {
                completion(success)
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) {
            finish(false)
        }
    }
}

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
    
    /// 最近一次独立探测成功的服务端地址
    @State private var testedEndpoint: ServerEndpoint?
    
    /// 是否需要自动关闭窗体（点击确定后）
    @State private var shouldAutoDismiss: Bool = false
    
    /// 旋转角度（用于加载图标动画）
    @State private var rotationAngle: Double = 0

    private let onServerChanged: (() -> Void)?

    init(onServerChanged: (() -> Void)? = nil) {
        self.onServerChanged = onServerChanged
    }
    
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
                            let (host, port) = currentServer
                            Text("\(host):\(port)")
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
                            testedEndpoint = nil
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
            if isTesting {
                return
            }
            let (host, port) = socketManager.getCurrentServer()
            self.serverAddress = "\(host):\(port)"
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
        case .disconnected:
            return "xmark.circle.fill"
        case .error:
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
        case .disconnected:
            return .gray
        case .error:
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
        case .disconnected:
            return "未连接"
        case .error(let msg):
            return "连接失败: \(msg)"
        }
    }
    
    /// 连接状态徽章
    private var connectionStatusBadge: String {
        switch socketManager.connectionState {
        case .connected:
            return "正常"
        case .connecting:
            return "连接中"
        case .disconnected:
            return "断开"
        case .error:
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
        let endpoint = ServerEndpoint(host: host, port: port)
        
        // 禁用按钮，开始测试
        statusMessage = "正在测试连接..."
        statusColor = .blue
        isTesting = true
        isNewConnectionReady = false
        
        // 启动旋转动画
        startRotationAnimation()
        
        ServerConnectionProbe.test(endpoint: endpoint) { success in
            isTesting = false
            stopRotationAnimation()

            if success {
                testedEndpoint = endpoint
                isNewConnectionReady = true
                statusMessage = "远程服务端连接成功"
                statusColor = .green

                if shouldAutoDismiss {
                    applyServerChange(endpoint)
                }
            } else {
                testedEndpoint = nil
                isNewConnectionReady = false
                shouldAutoDismiss = false
                statusMessage = "连接失败或超时，请检查地址和网络"
                statusColor = .red
            }
        }
    }
    
    /// 处理确定按钮
    private func handleConfirm() {
        guard let (host, port) = validateServerAddress(serverAddress) else {
            statusMessage = "地址格式错误，请使用 IP:Port 格式"
            statusColor = .red
            return
        }
        let endpoint = ServerEndpoint(host: host, port: port)

        if testedEndpoint == endpoint {
            applyServerChange(endpoint)
            return
        }

        shouldAutoDismiss = true
        handleTestConnection()
    }

    private func applyServerChange(_ endpoint: ServerEndpoint) {
        let current = socketManager.getCurrentServer()
        let currentEndpoint = ServerEndpoint(host: current.0, port: current.1)
        guard endpoint != currentEndpoint else {
            dismiss()
            return
        }

        socketManager.switchConnection(host: endpoint.host, port: endpoint.port)
        onServerChanged?()
        dismiss()
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
