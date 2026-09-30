//
//  ConfigServerView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import SwiftUI
import Network

struct ServerEndpoint: Codable, Equatable, Hashable, Sendable {
    // [修改] 本机测试统一连接当前局域网服务端地址。
    static let defaultHost = "172.21.32.120"

    let host: String
    let port: UInt32
}

struct ServerConfiguration: Codable, Equatable, Sendable {
    static let defaultControlPort: UInt32 = 10_086
    static let defaultUploadPort: UInt32 = 10_087
    static let defaultDownloadPort: UInt32 = 10_088
    static let defaultMediaPort: UInt32 = 10_188

    let host: String
    let controlPort: UInt32
    let uploadPort: UInt32
    let downloadPort: UInt32
    let mediaPort: UInt32

    init(
        host: String = ServerEndpoint.defaultHost,
        controlPort: UInt32 = defaultControlPort,
        uploadPort: UInt32 = defaultUploadPort,
        downloadPort: UInt32 = defaultDownloadPort,
        mediaPort: UInt32 = defaultMediaPort
    ) {
        self.host = host
        self.controlPort = controlPort
        self.uploadPort = uploadPort
        self.downloadPort = downloadPort
        self.mediaPort = mediaPort
    }

    var controlEndpoint: ServerEndpoint {
        ServerEndpoint(host: host, port: controlPort)
    }

    func validated() throws -> ServerConfiguration {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw ServerConfigurationError.emptyHost
        }
        try Self.validate(port: controlPort, name: "控制")
        try Self.validate(port: uploadPort, name: "上传")
        try Self.validate(port: downloadPort, name: "下载")
        try Self.validate(port: mediaPort, name: "媒体")
        return ServerConfiguration(
            host: normalizedHost,
            controlPort: controlPort,
            uploadPort: uploadPort,
            downloadPort: downloadPort,
            mediaPort: mediaPort
        )
    }

    private static func validate(port: UInt32, name: String) throws {
        guard port > 0, port <= UInt32(UInt16.max) else {
            throw ServerConfigurationError.invalidPort(name)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case host
        case controlPort
        case uploadPort
        case downloadPort
        case mediaPort
        case port
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        controlPort = try container.decodeIfPresent(UInt32.self, forKey: .controlPort)
            ?? container.decodeIfPresent(UInt32.self, forKey: .port)
            ?? Self.defaultControlPort
        uploadPort = try container.decodeIfPresent(UInt32.self, forKey: .uploadPort)
            ?? Self.defaultUploadPort
        downloadPort = try container.decodeIfPresent(UInt32.self, forKey: .downloadPort)
            ?? Self.defaultDownloadPort
        mediaPort = try container.decodeIfPresent(UInt32.self, forKey: .mediaPort)
            ?? Self.defaultMediaPort
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(controlPort, forKey: .controlPort)
        try container.encode(uploadPort, forKey: .uploadPort)
        try container.encode(downloadPort, forKey: .downloadPort)
        try container.encode(mediaPort, forKey: .mediaPort)
    }
}

enum ServerConfigurationError: LocalizedError, Equatable {
    case emptyHost
    case invalidPort(String)

    var errorDescription: String? {
        switch self {
        case .emptyHost:
            return "服务器地址不能为空"
        case .invalidPort(let name):
            return "\(name)端口必须在 1 到 65535 之间"
        }
    }
}

enum ServerEndpointStore {
    private static let key = "chat-storage.server-endpoint"
    private static let previousLocalHosts: Set<String> = [
        "localhost",
        "127.0.0.1",
        "::1",
        "172.21.32.64"
    ]

    static func load(defaults: UserDefaults = .standard) -> ServerEndpoint? {
        loadConfiguration(defaults: defaults)?.controlEndpoint
    }

    static func loadConfiguration(defaults: UserDefaults = .standard) -> ServerConfiguration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let stored = try? JSONDecoder().decode(ServerConfiguration.self, from: data) else {
            return nil
        }
        let normalizedHost = stored.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard previousLocalHosts.contains(normalizedHost) else { return stored }

        // [修改] 旧安装保存的本机地址迁移到当前局域网 IP，端口配置原样保留。
        let migrated = ServerConfiguration(
            host: ServerEndpoint.defaultHost,
            controlPort: stored.controlPort,
            uploadPort: stored.uploadPort,
            downloadPort: stored.downloadPort,
            mediaPort: stored.mediaPort
        )
        if let migratedData = try? JSONEncoder().encode(migrated) {
            defaults.set(migratedData, forKey: key)
        }
        return migrated
    }

    // [修改] 服务端地址必须跨启动保存，才能从对应服务器的 Keychain 会话恢复。
    static func save(_ endpoint: ServerEndpoint, defaults: UserDefaults = .standard) throws {
        let existing = loadConfiguration(defaults: defaults)
        let configuration = ServerConfiguration(
            host: endpoint.host,
            controlPort: endpoint.port,
            uploadPort: existing?.uploadPort ?? ServerConfiguration.defaultUploadPort,
            downloadPort: existing?.downloadPort ?? ServerConfiguration.defaultDownloadPort,
            mediaPort: existing?.mediaPort ?? ServerConfiguration.defaultMediaPort
        )
        try save(configuration, defaults: defaults)
    }

    static func save(_ configuration: ServerConfiguration, defaults: UserDefaults = .standard) throws {
        let validated = try configuration.validated()
        defaults.set(try JSONEncoder().encode(validated), forKey: key)
    }

    static func resolvedConfiguration(
        for endpoint: ServerEndpoint,
        defaults: UserDefaults = .standard
    ) -> ServerConfiguration {
        guard let stored = loadConfiguration(defaults: defaults),
              stored.host == endpoint.host,
              stored.controlPort == endpoint.port else {
            return ServerConfiguration(host: endpoint.host, controlPort: endpoint.port)
        }
        return stored
    }
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
            // [修改] 服务端当前为明文自定义帧端口，探测成功以 TCP 连接就绪为准。
            using: SocketTransportParameters.makePlainTCP()
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
    @State private var uploadPort: String = ""
    @State private var downloadPort: String = ""
    @State private var mediaPort: String = ""
    
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
    @State private var testedConfiguration: ServerConfiguration?
    
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

                    let configuredPorts = ServerEndpointStore.resolvedConfiguration(
                        for: ServerEndpoint(host: currentServer.0, port: currentServer.1)
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("传输端口")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("上传 \(configuredPorts.uploadPort) · 下载 \(configuredPorts.downloadPort) · 媒体 \(configuredPorts.mediaPort)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                        resetTestState()
                    }
                
                Text("例如: 192.168.1.100:8080")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    portField(title: "上传", text: $uploadPort)
                    portField(title: "下载", text: $downloadPort)
                    portField(title: "媒体", text: $mediaPort)
                }
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
        .frame(width: 450, height: 570)  // 增加高度，展示独立传输端口
        .onAppear {
            // 初始化为当前服务器地址
            if isTesting {
                return
            }
            let (host, port) = socketManager.getCurrentServer()
            let configuration = ServerEndpointStore.resolvedConfiguration(
                for: ServerEndpoint(host: host, port: port)
            )
            self.serverAddress = "\(host):\(port)"
            self.uploadPort = "\(configuration.uploadPort)"
            self.downloadPort = "\(configuration.downloadPort)"
            self.mediaPort = "\(configuration.mediaPort)"
        }
    }

    @ViewBuilder
    private func portField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            TextField("端口", text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _ in
                    resetTestState()
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func resetTestState() {
        isNewConnectionReady = false
        testedEndpoint = nil
        testedConfiguration = nil
        statusMessage = ""
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
        guard let configuration = validateConfiguration() else {
            statusMessage = "地址或传输端口格式错误，请检查输入"
            statusColor = .red
            return
        }
        let endpoint = configuration.controlEndpoint
        
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
                testedConfiguration = configuration
                isNewConnectionReady = true
                statusMessage = "远程服务端连接成功"
                statusColor = .green

                if shouldAutoDismiss {
                    applyServerChange(configuration)
                }
            } else {
                testedEndpoint = nil
                testedConfiguration = nil
                isNewConnectionReady = false
                shouldAutoDismiss = false
                statusMessage = "连接失败或超时，请检查地址和网络"
                statusColor = .red
            }
        }
    }
    
    /// 处理确定按钮
    private func handleConfirm() {
        guard let configuration = validateConfiguration() else {
            statusMessage = "地址或传输端口格式错误，请检查输入"
            statusColor = .red
            return
        }
        let endpoint = configuration.controlEndpoint

        if testedEndpoint == endpoint, testedConfiguration == configuration {
            applyServerChange(configuration)
            return
        }

        shouldAutoDismiss = true
        handleTestConnection()
    }

    private func applyServerChange(_ configuration: ServerConfiguration) {
        let endpoint = configuration.controlEndpoint
        let current = socketManager.getCurrentServer()
        let currentEndpoint = ServerEndpoint(host: current.0, port: current.1)
        guard endpoint != currentEndpoint || ServerEndpointStore.loadConfiguration()?.uploadPort != configuration.uploadPort
            || ServerEndpointStore.loadConfiguration()?.downloadPort != configuration.downloadPort
            || ServerEndpointStore.loadConfiguration()?.mediaPort != configuration.mediaPort else {
            dismiss()
            return
        }

        do {
            try ServerEndpointStore.save(configuration)
        } catch {
            statusMessage = "保存服务器地址失败"
            statusColor = .red
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

    private func validateConfiguration() -> ServerConfiguration? {
        guard let (host, controlPort) = validateServerAddress(serverAddress),
              let uploadPort = UInt32(uploadPort),
              let downloadPort = UInt32(downloadPort),
              let mediaPort = UInt32(mediaPort) else {
            return nil
        }
        let configuration = ServerConfiguration(
            host: host,
            controlPort: controlPort,
            uploadPort: uploadPort,
            downloadPort: downloadPort,
            mediaPort: mediaPort
        )
        return try? configuration.validated()
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
