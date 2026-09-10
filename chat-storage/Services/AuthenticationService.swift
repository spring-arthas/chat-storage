//
//  AuthenticationService.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation
import Combine
import Security

struct StoredAuthenticationSession: Codable, Equatable {
    let sessionToken: String
    let user: UserDO
}

protocol SessionCredentialStoring: AnyObject {
    func load(for endpoint: ServerEndpoint) throws -> StoredAuthenticationSession?
    func save(_ session: StoredAuthenticationSession, for endpoint: ServerEndpoint) throws
    func clear(for endpoint: ServerEndpoint) throws
}

enum SessionCredentialStoreError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            // [修改] Keychain 失败向上提供可读状态码，退出提示不再只显示通用系统错误。
            return "Keychain 操作失败，状态码: \(status)"
        case .unexpectedData:
            return "Keychain 登录凭据格式无效"
        }
    }
}

final class KeychainSessionCredentialStore: SessionCredentialStoring {
    private let baseService: String
    private let account = "authentication-session"

    init(baseService: String = "com.duyao.chat-storage.macos") {
        self.baseService = baseService
    }

    func load(for endpoint: ServerEndpoint) throws -> StoredAuthenticationSession? {
        var query = baseQuery(for: endpoint)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SessionCredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw SessionCredentialStoreError.unexpectedData
        }
        return try JSONDecoder().decode(StoredAuthenticationSession.self, from: data)
    }

    func save(_ session: StoredAuthenticationSession, for endpoint: ServerEndpoint) throws {
        let data = try JSONEncoder().encode(session)
        let query = baseQuery(for: endpoint)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SessionCredentialStoreError.unexpectedStatus(updateStatus)
        }
        var addition = query
        addition.merge(values) { _, new in new }
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SessionCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    func clear(for endpoint: ServerEndpoint) throws {
        let status = SecItemDelete(baseQuery(for: endpoint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionCredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for endpoint: ServerEndpoint) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            // [修改] 凭据按服务器隔离，切换服务器不会串用另一个环境的会话。
            kSecAttrService as String: "\(baseService).\(scope(for: endpoint))",
            kSecAttrAccount as String: account,
        ]
    }

    private func scope(for endpoint: ServerEndpoint) -> String {
        let host = endpoint.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        return "\(host):\(endpoint.port)"
    }
}

enum TransferTokenExpiration {
    // [修改] 只读取服务端令牌中的毫秒过期时间用于提前刷新，不在客户端校验身份和签名。
    static func expirationDate(from token: String?) -> Date? {
        guard let token else { return nil }
        let parts = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 5,
              let expiresAtMilliseconds = Int64(parts[2]),
              expiresAtMilliseconds > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(expiresAtMilliseconds) / 1_000)
    }
}

typealias AuthenticationRequestHandler = (
    _ frame: Frame,
    _ responseType: FrameTypeEnum,
    _ timeout: TimeInterval
) async throws -> Frame

typealias AuthenticationConnectionReadyHandler = () async throws -> Void

/// 认证服务（处理登录和注册）
class AuthenticationService: ObservableObject {

    // [修改] 每次恢复都绑定 endpoint、唯一 ID 和失效代数，旧操作不能冒充新的恢复流程。
    private struct SessionResumeOperation {
        let endpoint: ServerEndpoint
        let id: UUID
        let generation: UInt64
        let sendPermit: SocketSendPermit
    }
    
    // MARK: - Singleton
    
    static let shared = AuthenticationService(socketManager: SocketManager.shared)

    // MARK: - Published Properties
    
    /// 当前登录用户
    @Published var currentUser: UserDO?
    
    /// 是否已认证
    @Published var isAuthenticated: Bool = false

    /// 会话恢复失败提示；网络瞬时失败保留 Keychain 凭据等待下次重试。
    @Published private(set) var restorationError: String?
    
    // MARK: - Private Properties
    
    private let socketManager: SocketManager
    private let credentialStore: SessionCredentialStoring
    private let endpointProvider: () -> ServerEndpoint
    private let requestHandler: AuthenticationRequestHandler?
    private let connectionReadyHandler: AuthenticationConnectionReadyHandler
    private let transferTokenRefreshLeadTime: TimeInterval
    private let refreshRetryDelay: TimeInterval
    private let refreshLock = NSLock()
    private var tokenRefreshTask: Task<Void, Never>?
    // [修改] 恢复中的状态按 endpoint 隔离，同一 endpoint 只保留一个唯一操作。
    private let sessionResumeLock = NSLock()
    private var activeSessionResumeOperations: [ServerEndpoint: SessionResumeOperation] = [:]
    private var sessionResumeGeneration: UInt64 = 0
    
    // MARK: - Initializer
    
    init(
        socketManager: SocketManager,
        credentialStore: SessionCredentialStoring = KeychainSessionCredentialStore(),
        endpointProvider: (() -> ServerEndpoint)? = nil,
        requestHandler: AuthenticationRequestHandler? = nil,
        connectionReadyHandler: AuthenticationConnectionReadyHandler? = nil,
        transferTokenRefreshLeadTime: TimeInterval = 5 * 60,
        refreshRetryDelay: TimeInterval = 60
    ) {
        self.socketManager = socketManager
        self.credentialStore = credentialStore
        self.endpointProvider = endpointProvider ?? {
            let current = socketManager.getCurrentServer()
            return ServerEndpoint(host: current.0, port: current.1)
        }
        self.requestHandler = requestHandler
        self.connectionReadyHandler = connectionReadyHandler ?? {
            try await Self.waitUntilTransportReady(socketManager)
        }
        self.transferTokenRefreshLeadTime = max(0, transferTokenRefreshLeadTime)
        self.refreshRetryDelay = max(0.05, refreshRetryDelay)
    }

    deinit {
        tokenRefreshTask?.cancel()
    }
    
    // MARK: - Authentication Methods
    
    /// 用户登录
    /// - Parameters:
    ///   - userName: 用户名
    ///   - password: 密码
    /// - Returns: 用户信息
    /// - Throws: AuthError
    func login(userName: String, password: String) async throws -> UserDO {
        print("🔐 开始登录: \(userName)")
        try await connectionReadyHandler()
        
        // 1. 构建请求体
        let request = UserRequest(userName: userName, password: password)
        
        // 2. 构建帧
        let frame = try FrameBuilder.build(
            type: .userLoginReq,
            payload: request
        )
        
        // 3. 发送并等待响应
        let responseFrame = try await sendAuthenticationRequest(
            frame,
            responseType: .userResponse,
            timeout: 10.0
        )
        
        // 4. 解析响应
        let response = try FrameParser.decodePayload(
            responseFrame,
            as: ResponseWrapper<UserDO>.self
        )
        
        // 5. 检查响应码
        guard response.code == 200, let user = response.data else {
            print("❌ 登录失败: \(response.message)")
            throw AuthError.loginFailed(response.message)
        }
        
        // [修改] 登录成功必须同时持久化 sessionToken，网盘 transferToken 才能自动续期。
        try await acceptAuthenticatedUser(user, endpoint: endpointProvider())
        
        print("✅ 登录成功: \(user.username)")
        return user
    }
    
    /// 用户注册
    /// - Parameters:
    ///   - userName: 用户名
    ///   - password: 密码
    ///   - mail: 邮箱
    ///   - avatarData: 头像数据 (Base64)
    ///   - avatarName: 头像文件名
    /// - Returns: 用户信息
    /// - Throws: AuthError
    func register(userName: String, password: String, mail: String, avatarData: String? = nil, avatarName: String? = nil) async throws -> UserDO {
        print("📝 开始注册: \(userName)")
        try await connectionReadyHandler()
        
        // 1. 构建请求体
        let request = UserRequest(
            userName: userName,
            password: password,
            mail: mail,
            avatarData: avatarData,
            avatarName: avatarName
        )
        
        // 2. 构建帧
        let frame = try FrameBuilder.build(
            type: .userRegisterReq,
            payload: request
        )
        
        // 3. 发送并等待响应
        let responseFrame = try await sendAuthenticationRequest(
            frame,
            responseType: .userResponse,
            timeout: 10.0
        )
        
        // 4. 解析响应
        let response = try FrameParser.decodePayload(
            responseFrame,
            as: ResponseWrapper<UserDO>.self
        )
        
        // 5. 检查响应码
        guard response.code == 200, let user = response.data else {
            print("❌ 注册失败: \(response.message)")
            throw AuthError.registerFailed(response.message)
        }
        
        // [修改] 注册响应没有登录令牌，注册完成后仍回到登录页，不能伪造已登录状态。
        print("✅ 注册成功: \(user.username)")
        return user
    }

    /// 更新当前登录用户头像
    func updateAvatar(avatarData: String, avatarName: String = "avatar.jpg") async throws -> UserDO {
        guard isAuthenticated, currentUser != nil else {
            throw AuthError.invalidInput("请先登录后再上传头像")
        }

        try await connectionReadyHandler()

        struct AvatarUpdateRequest: Codable {
            let avatarData: String
            let avatarName: String
        }

        let frame = try FrameBuilder.build(
            type: .userAvatarUpdateReq,
            payload: AvatarUpdateRequest(avatarData: avatarData, avatarName: avatarName)
        )

        let responseFrame = try await sendAuthenticationRequest(
            frame,
            responseType: .userResponse,
            timeout: 12.0
        )

        let response = try FrameParser.decodePayload(
            responseFrame,
            as: ResponseWrapper<UserDO>.self
        )

        guard response.code == 200, let user = response.data else {
            throw AuthError.invalidInput(response.message.isEmpty ? "头像上传失败" : response.message)
        }

        // [修改] 头像更新响应会换发新令牌，必须覆盖 Keychain 中的旧会话。
        try await acceptAuthenticatedUser(user, endpoint: endpointProvider())

        return user
    }

    /// 应用启动后尝试恢复当前服务器对应的会话。
    @discardableResult
    func restoreSession() async -> Bool {
        await resumeStoredSession(for: endpointProvider(), schedulesRetry: true)
    }

    /// 应用回到前台时刷新会话和 transferToken；瞬时网络失败保留当前登录态并自动重试。
    @discardableResult
    func resumeForForeground() async -> Bool {
        let resumed = await resumeStoredSession(for: endpointProvider(), schedulesRetry: true)
        if resumed { return true }
        return await MainActor.run { self.isAuthenticated }
    }
    
    /// 退出登录。
    ///
    /// 先删除本地凭据并作废旧恢复操作，再通过 0x33 通知服务端解除当前用户绑定；
    /// 如果连接异常或服务端未确认，则主动断开连接，避免旧在线映射残留。
    func logout() async throws {
        let endpoint = endpointProvider()
        // [修改] Keychain 删除与旧恢复 operation 作废共用同一原子边界；失败时不动刷新、认证和连接状态。
        try clearStoredSessionAndInvalidateResumeOperations(for: endpoint)
        cancelTokenRefresh()
        var shouldDisconnect = !socketManager.isTransportReady

        if !shouldDisconnect {
            do {
                let frame = FrameBuilder.buildEmpty(type: .userLogoutReq)
                let responseFrame = try await sendAuthenticationRequest(
                    frame,
                    responseType: .userResponse,
                    timeout: 3.0
                )
                let response = try FrameParser.decodePayload(
                    responseFrame,
                    as: ResponseWrapper<EmptyResponse>.self
                )
                guard response.isSuccess else {
                    throw AuthError.logoutFailed(response.message)
                }
            } catch {
                shouldDisconnect = true
                print("⚠️ 服务端退出确认失败，将断开文本连接清理登录映射: \(error.localizedDescription)")
            }
        }

        let disconnectAfterLogout = shouldDisconnect
        await MainActor.run {
            if disconnectAfterLogout {
                let server = socketManager.getCurrentServer()
                socketManager.disconnect(notifyUI: false)
                socketManager.connect(host: server.0, port: server.1)
            }
            clearLocalAuthenticationState()
            print("👋 已退出登录")
        }
    }

    /// 服务端地址切换后，旧连接上的认证状态不能继续沿用。
    @MainActor
    func invalidateLocalSession() {
        // [修改] 切换服务器先作废全部旧恢复操作，再清内存和刷新任务，保留各服务器独立凭据。
        invalidateSessionResumeOperations()
        cancelTokenRefresh()
        clearLocalAuthenticationState()
    }

    // MARK: - Session Persistence and Refresh

    private func sendAuthenticationRequest(
        _ frame: Frame,
        responseType: FrameTypeEnum,
        timeout: TimeInterval,
        expectedEndpoint: ServerEndpoint? = nil,
        sendPermit: SocketSendPermit? = nil
    ) async throws -> Frame {
        if let requestHandler {
            return try await requestHandler(frame, responseType, timeout)
        }
        // [修改] 默认恢复链把目标 endpoint 交给传输层，测试注入 handler 仍保留原签名。
        return try await socketManager.sendFrameAndWait(
            frame,
            expecting: responseType,
            timeout: timeout,
            expectedEndpoint: expectedEndpoint,
            sendPermit: sendPermit
        )
    }

    private func acceptAuthenticatedUser(
        _ user: UserDO,
        endpoint: ServerEndpoint,
        operation: SessionResumeOperation? = nil
    ) async throws {
        guard isAuthenticationContextValid(endpoint: endpoint, operation: operation) else {
            throw AuthError.connectionError
        }
        guard let sessionToken = normalizedSessionToken(user.sessionToken) else {
            throw AuthError.invalidInput("服务端未返回有效的会话凭据")
        }

        let storedSession = StoredAuthenticationSession(sessionToken: sessionToken, user: user)
        // [修改] 响应返回后到 Keychain 持久化前再次复核，失效操作不能覆盖目标服务器会话。
        guard try saveAuthenticatedSessionIfCurrent(
            storedSession,
            for: endpoint,
            operation: operation
        ) else {
            throw AuthError.connectionError
        }

        // [修改] MainActor 真正写认证状态前再复核，旧响应不能覆盖新 endpoint 的唯一状态源。
        let accepted = await MainActor.run { () -> Bool in
            guard self.isAuthenticationContextValid(endpoint: endpoint, operation: operation) else {
                return false
            }
            self.currentUser = user
            self.isAuthenticated = true
            self.restorationError = nil
            self.socketManager.currentUserId = user.id
            self.socketManager.myAvatar = user.avatar
            return true
        }
        guard accepted,
              scheduleTokenRefresh(for: user, endpoint: endpoint, operation: operation) else {
            throw AuthError.connectionError
        }
    }

    private func resumeStoredSession(
        for endpoint: ServerEndpoint,
        schedulesRetry: Bool
    ) async -> Bool {
        guard let operation = beginSessionResume(for: endpoint) else {
            return await MainActor.run { self.isAuthenticated }
        }
        // [修改] defer 只结束自己的 UUID，旧操作绝不会清掉同 endpoint 的较新操作。
        defer { endSessionResume(operation) }

        let loadedSession: StoredAuthenticationSession?
        do {
            loadedSession = try credentialStore.load(for: endpoint)
        } catch {
            guard isSessionResumeOperationValid(operation) else { return false }
            await setRestorationError(
                "读取登录凭据失败: \(error.localizedDescription)",
                operation: operation
            )
            if schedulesRetry { scheduleRefreshRetry(for: endpoint, operation: operation) }
            return false
        }

        // [修改] 凭据读取后立即复核 endpoint 和 operation，切服期间读到的旧凭据到此为止。
        guard isSessionResumeOperationValid(operation) else { return false }
        guard let storedSession = loadedSession else {
            await setRestorationError(nil, operation: operation)
            return false
        }

        do {
            try await connectionReadyHandler()
            // [修改] 等待连接期间可能切服，恢复操作必须在继续组帧前仍然有效。
            guard isSessionResumeOperationValid(operation) else { return false }

            struct SessionResumeRequest: Codable {
                let sessionToken: String
            }

            let frame = try FrameBuilder.build(
                type: .userSessionResumeReq,
                payload: SessionResumeRequest(sessionToken: storedSession.sessionToken)
            )
            // [修改] 发送帧前最后复核，禁止把旧 endpoint 的 sessionToken 交给当前新连接。
            guard isSessionResumeOperationValid(operation) else { return false }
            let responseFrame = try await sendAuthenticationRequest(
                frame,
                responseType: .userResponse,
                timeout: 10.0,
                expectedEndpoint: endpoint,
                sendPermit: operation.sendPermit
            )
            // [修改] 请求已发出后仍可能切服，处理响应前必须再次确认 operation 未失效。
            guard isSessionResumeOperationValid(operation) else { return false }
            let response = try FrameParser.decodePayload(
                responseFrame,
                as: ResponseWrapper<UserDO>.self
            )

            guard response.code == 200, let user = response.data else {
                if Self.isExpiredSessionResponse(response) {
                    await clearStoredAndLocalSession(for: endpoint, operation: operation)
                } else {
                    await setRestorationError(
                        response.message.isEmpty ? "登录状态恢复失败" : response.message,
                        operation: operation
                    )
                    if schedulesRetry { scheduleRefreshRetry(for: endpoint, operation: operation) }
                }
                return false
            }

            try await acceptAuthenticatedUser(user, endpoint: endpoint, operation: operation)
            return true
        } catch {
            // [修改] 已失效操作的异常静默结束，不能写错误、清凭据或安排重试。
            guard isSessionResumeOperationValid(operation) else { return false }
            await setRestorationError(
                "登录状态恢复失败: \(error.localizedDescription)",
                operation: operation
            )
            if schedulesRetry { scheduleRefreshRetry(for: endpoint, operation: operation) }
            return false
        }
    }

    private static func isExpiredSessionResponse(_ response: ResponseWrapper<UserDO>) -> Bool {
        let code = response.errorCode?.uppercased()
        return code == "SESSION_EXPIRED"
            || code == "SESSION_INVALID"
            || code == "NOT_LOGGED_IN"
    }

    private func normalizedSessionToken(_ token: String?) -> String? {
        guard let value = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    @discardableResult
    private func scheduleTokenRefresh(
        for user: UserDO,
        endpoint: ServerEndpoint,
        operation: SessionResumeOperation? = nil
    ) -> Bool {
        guard let expirationDate = TransferTokenExpiration.expirationDate(from: user.transferToken) else {
            return replaceTokenRefreshTask(with: nil, validFor: operation)
        }

        let delay = max(0.05, expirationDate.timeIntervalSinceNow - transferTokenRefreshLeadTime)
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            _ = await self.resumeStoredSession(for: endpoint, schedulesRetry: true)
        }
        return replaceTokenRefreshTask(with: task, validFor: operation)
    }

    private func scheduleRefreshRetry(
        for endpoint: ServerEndpoint,
        operation: SessionResumeOperation
    ) {
        let delay = refreshRetryDelay
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            _ = await self.resumeStoredSession(for: endpoint, schedulesRetry: true)
        }
        // [修改] 重试任务和 operation 原子绑定，invalidate 后不会重新挂回旧 endpoint 的任务。
        _ = replaceTokenRefreshTask(with: task, validFor: operation)
    }

    @discardableResult
    private func replaceTokenRefreshTask(
        with task: Task<Void, Never>?,
        validFor operation: SessionResumeOperation?
    ) -> Bool {
        guard let operation else {
            replaceTokenRefreshTask(with: task)
            return true
        }
        guard endpointProvider() == operation.endpoint else {
            task?.cancel()
            return false
        }

        // [修改] 与 invalidate 共用恢复锁，保证“校验有效”和“安装任务”之间没有失效窗口。
        sessionResumeLock.lock()
        let isValid = isSessionResumeOperationCurrentLocked(operation)
            && endpointProvider() == operation.endpoint
        if isValid {
            replaceTokenRefreshTask(with: task)
        }
        sessionResumeLock.unlock()

        if !isValid { task?.cancel() }
        return isValid
    }

    private func replaceTokenRefreshTask(with task: Task<Void, Never>?) {
        refreshLock.lock()
        let previous = tokenRefreshTask
        tokenRefreshTask = task
        refreshLock.unlock()
        previous?.cancel()
    }

    private func cancelTokenRefresh() {
        replaceTokenRefreshTask(with: nil)
    }

    private func beginSessionResume(for endpoint: ServerEndpoint) -> SessionResumeOperation? {
        guard endpointProvider() == endpoint else { return nil }

        sessionResumeLock.lock()
        guard activeSessionResumeOperations[endpoint] == nil else {
            sessionResumeLock.unlock()
            return nil
        }
        let operation = SessionResumeOperation(
            endpoint: endpoint,
            id: UUID(),
            generation: sessionResumeGeneration,
            sendPermit: SocketSendPermit()
        )
        activeSessionResumeOperations[endpoint] = operation
        sessionResumeLock.unlock()

        guard endpointProvider() == endpoint else {
            endSessionResume(operation)
            return nil
        }
        return operation
    }

    private func endSessionResume(_ operation: SessionResumeOperation) {
        sessionResumeLock.lock()
        if isSessionResumeOperationCurrentLocked(operation) {
            operation.sendPermit.invalidate()
            activeSessionResumeOperations.removeValue(forKey: operation.endpoint)
        }
        sessionResumeLock.unlock()
    }

    private func invalidateSessionResumeOperations() {
        sessionResumeLock.lock()
        invalidateSessionResumeOperationsLocked()
        sessionResumeLock.unlock()
    }

    private func clearStoredSessionAndInvalidateResumeOperations(
        for endpoint: ServerEndpoint
    ) throws {
        sessionResumeLock.lock()
        defer { sessionResumeLock.unlock() }

        do {
            // [修改] 删除成功后才推进代数；删除失败时旧 operation 和刷新链保持原样。
            try credentialStore.clear(for: endpoint)
        } catch {
            throw AuthError.logoutCredentialCleanupFailed(error.localizedDescription)
        }
        invalidateSessionResumeOperationsLocked()
    }

    private func invalidateSessionResumeOperationsLocked() {
        // [修改] 在恢复操作移除前作废全部 permit，已注册但未真正发送的延迟任务会被传输层拒绝。
        activeSessionResumeOperations.values.forEach { $0.sendPermit.invalidate() }
        sessionResumeGeneration &+= 1
        activeSessionResumeOperations.removeAll()
    }

    private func isSessionResumeOperationValid(_ operation: SessionResumeOperation) -> Bool {
        guard endpointProvider() == operation.endpoint else { return false }

        sessionResumeLock.lock()
        let isCurrent = isSessionResumeOperationCurrentLocked(operation)
        sessionResumeLock.unlock()

        return isCurrent && endpointProvider() == operation.endpoint
    }

    private func isSessionResumeOperationCurrentLocked(
        _ operation: SessionResumeOperation
    ) -> Bool {
        sessionResumeGeneration == operation.generation
            && activeSessionResumeOperations[operation.endpoint]?.id == operation.id
    }

    private func isAuthenticationContextValid(
        endpoint: ServerEndpoint,
        operation: SessionResumeOperation?
    ) -> Bool {
        guard endpointProvider() == endpoint else { return false }
        guard let operation else { return true }
        return operation.endpoint == endpoint && isSessionResumeOperationValid(operation)
    }

    private func saveAuthenticatedSessionIfCurrent(
        _ session: StoredAuthenticationSession,
        for endpoint: ServerEndpoint,
        operation: SessionResumeOperation?
    ) throws -> Bool {
        guard let operation else {
            guard endpointProvider() == endpoint else { return false }
            try credentialStore.save(session, for: endpoint)
            return endpointProvider() == endpoint
        }
        guard endpointProvider() == endpoint else { return false }

        sessionResumeLock.lock()
        defer { sessionResumeLock.unlock() }
        guard operation.endpoint == endpoint,
              isSessionResumeOperationCurrentLocked(operation),
              endpointProvider() == endpoint else {
            return false
        }
        try credentialStore.save(session, for: endpoint)
        return true
    }

    private func clearStoredAndLocalSession(
        for endpoint: ServerEndpoint,
        operation: SessionResumeOperation
    ) async {
        guard clearStoredSessionIfCurrent(for: endpoint, operation: operation) else { return }
        _ = replaceTokenRefreshTask(with: nil, validFor: operation)
        await MainActor.run {
            guard self.isSessionResumeOperationValid(operation) else { return }
            self.clearLocalAuthenticationState()
        }
    }

    private func clearStoredSessionIfCurrent(
        for endpoint: ServerEndpoint,
        operation: SessionResumeOperation
    ) -> Bool {
        guard endpointProvider() == endpoint else { return false }

        // [修改] 失效响应清凭据也和 operation 原子绑定，旧响应不能删掉目标服务器的新会话。
        sessionResumeLock.lock()
        defer { sessionResumeLock.unlock() }
        guard operation.endpoint == endpoint,
              isSessionResumeOperationCurrentLocked(operation),
              endpointProvider() == endpoint else {
            return false
        }
        do {
            try credentialStore.clear(for: endpoint)
        } catch {
            print("⚠️ 清理失效会话失败: \(error.localizedDescription)")
        }
        return true
    }

    @MainActor
    private func clearLocalAuthenticationState() {
        currentUser = nil
        isAuthenticated = false
        restorationError = nil
        socketManager.myAvatar = nil
        socketManager.currentUserId = nil
        socketManager.activeChatFriendId = nil
        socketManager.friendList = []
        socketManager.pendingFriendRequests = []
    }

    private func setRestorationError(
        _ message: String?,
        operation: SessionResumeOperation
    ) async {
        await MainActor.run {
            guard self.isSessionResumeOperationValid(operation) else { return }
            self.restorationError = message
        }
    }

    private static func waitUntilTransportReady(
        _ socketManager: SocketManager,
        timeout: TimeInterval = 10.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if socketManager.isTransportReady { return }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw SocketError.connectionFailed
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case loginFailed(String)
    case registerFailed(String)
    case logoutFailed(String)
    case logoutCredentialCleanupFailed(String)
    case connectionError
    case invalidInput(String)
    
    var errorDescription: String? {
        switch self {
        case .loginFailed(let message):
            return "登录失败: \(message)"
        case .registerFailed(let message):
            return "注册失败: \(message)"
        case .logoutFailed(let message):
            return "退出登录失败: \(message)"
        case .logoutCredentialCleanupFailed(let message):
            // [修改] UI 能明确区分本地凭据未删除，不能宣告退出成功。
            return "退出登录失败: 无法删除本地登录凭据（\(message)）"
        case .connectionError:
            return "网络连接错误，请检查服务器配置"
        case .invalidInput(let message):
            return message
        }
    }
}
