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
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 25) {
            
            // 标题
            Text("配置服务端地址")
                .font(.title)
                .fontWeight(.bold)
            
            // 当前服务器显示
            VStack(alignment: .leading, spacing: 8) {
                Text("当前服务器")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                let currentServer = socketManager.getCurrentServer()
                Text("\(currentServer.host):\(currentServer.port)")
                    .font(.body)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
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
                    if isTesting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 160, height: 40)
                    } else {
                        Text("测试连接")
                            .frame(width: 160, height: 40)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isTesting)
                
                // 确定按钮
                Button(action: handleConfirm) {
                    Text("确定")
                        .frame(width: 160, height: 40)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isTesting)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 450, height: 400)
        .onAppear {
            // 初始化为当前服务器地址
            let current = socketManager.getCurrentServer()
            serverAddress = "\(current.host):\(current.port)"
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
        
        // 清除之前的状态
        statusMessage = "正在测试连接..."
        statusColor = .blue
        isTesting = true
        isNewConnectionReady = false
        
        // 测试连接
        socketManager.testConnection(host: host, port: port) { success in
            isTesting = false
            
            if success {
                // 测试成功
                statusMessage = "远程服务端连接成功"
                statusColor = .green
                isNewConnectionReady = true
                
                // 保存新配置
                newHost = host
                newPort = port
                
                // 自动切换连接
                socketManager.switchConnection(host: host, port: port)
            } else {
                // 测试失败
                statusMessage = "连接失败，请检查地址和网络"
                statusColor = .red
                isNewConnectionReady = false
            }
        }
    }
    
    /// 处理确定按钮
    private func handleConfirm() {
        if isNewConnectionReady {
            // 新连接已就绪，直接关闭
            dismiss()
        } else {
            // 执行测试连接逻辑
            handleTestConnection()
            
            // 等待连接结果
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                if isNewConnectionReady {
                    dismiss()
                }
            }
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
}

// MARK: - Preview

struct ConfigServerView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigServerView()
            .environmentObject(SocketManager.shared)
    }
}
