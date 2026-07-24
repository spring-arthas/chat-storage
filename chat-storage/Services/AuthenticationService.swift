//
//  AuthenticationService.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation
import Combine

/// 认证服务（处理登录和注册）
class AuthenticationService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AuthenticationService(socketManager: SocketManager.shared)

    // MARK: - Published Properties
    
    /// 当前登录用户
    @Published var currentUser: UserDO?
    
    /// 是否已认证
    @Published var isAuthenticated: Bool = false
    
    // MARK: - Private Properties
    
    private let socketManager: SocketManager
    
    // MARK: - Initializer
    
    init(socketManager: SocketManager) {
        self.socketManager = socketManager
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
        
        // 1. 构建请求体
        let request = UserRequest(userName: userName, password: password)
        
        // 2. 构建帧
        let frame = try FrameBuilder.build(
            type: .userLoginReq,
            payload: request
        )
        
        // 3. 发送并等待响应
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .userResponse,
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
        
        // 6. 更新状态（主线程）
        await MainActor.run {
            self.currentUser = user
            self.isAuthenticated = true
            // 记录当前用户 ID，用于后续从历史头像字典中定位自己的 base64 头像
            self.socketManager.currentUserId = user.id
            self.socketManager.myAvatar = user.avatar
        }
        
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
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .userResponse,
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
        
        // 6. 更新状态（主线程）
        await MainActor.run {
            self.currentUser = user
            self.isAuthenticated = true
            // 记录当前用户 ID
            self.socketManager.currentUserId = user.id
        }
        
        print("✅ 注册成功: \(user.username)")
        return user
    }

    /// 更新当前登录用户头像
    func updateAvatar(avatarData: String, avatarName: String = "avatar.jpg") async throws -> UserDO {
        guard isAuthenticated, currentUser != nil else {
            throw AuthError.invalidInput("请先登录后再上传头像")
        }

        struct AvatarUpdateRequest: Codable {
            let avatarData: String
            let avatarName: String
        }

        let frame = try FrameBuilder.build(
            type: .userAvatarUpdateReq,
            payload: AvatarUpdateRequest(avatarData: avatarData, avatarName: avatarName)
        )

        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .userResponse,
            timeout: 12.0
        )

        let response = try FrameParser.decodePayload(
            responseFrame,
            as: ResponseWrapper<UserDO>.self
        )

        guard response.code == 200, let user = response.data else {
            throw AuthError.invalidInput(response.message.isEmpty ? "头像上传失败" : response.message)
        }

        await MainActor.run {
            self.currentUser = user
            self.socketManager.currentUserId = user.id
            self.socketManager.myAvatar = user.avatar
        }

        return user
    }
    
    /// 退出登录。
    ///
    /// 优先通过 0x33 通知服务端解除当前用户与 10086 文本连接的绑定；
    /// 如果连接异常或服务端未确认，则主动断开连接，避免旧在线映射残留。
    func logout() async {
        var shouldDisconnect = !socketManager.isTransportReady

        if !shouldDisconnect {
            do {
                let frame = FrameBuilder.buildEmpty(type: .userLogoutReq)
                let responseFrame = try await socketManager.sendFrameAndWait(
                    frame,
                    expecting: .userResponse,
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

        await MainActor.run {
            if shouldDisconnect {
                let server = socketManager.getCurrentServer()
                socketManager.disconnect(notifyUI: false)
                socketManager.connect(host: server.0, port: server.1)
            }
            currentUser = nil
            isAuthenticated = false
            socketManager.myAvatar = nil
            socketManager.currentUserId = nil
            socketManager.activeChatFriendId = nil
            print("👋 已退出登录")
        }
    }

    /// 服务端地址切换后，旧连接上的认证状态不能继续沿用。
    @MainActor
    func invalidateLocalSession() {
        currentUser = nil
        isAuthenticated = false
        socketManager.myAvatar = nil
        socketManager.currentUserId = nil
        socketManager.activeChatFriendId = nil
        socketManager.friendList = []
        socketManager.pendingFriendRequests = []
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case loginFailed(String)
    case registerFailed(String)
    case logoutFailed(String)
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
        case .connectionError:
            return "网络连接错误，请检查服务器配置"
        case .invalidInput(let message):
            return message
        }
    }
}
