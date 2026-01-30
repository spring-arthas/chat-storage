//
//  LoginView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import SwiftUI

struct LoginView: View {
    // MARK: - Environment Objects (环境对象)
    
    /// 全局 Socket 连接管理器
    @EnvironmentObject var socketManager: SocketManager
    
    /// 认证服务
    @StateObject private var authService: AuthenticationService
    
    // MARK: - State Variables (状态变量)
    
    /// 用户名输入（手机号或邮箱）
    @State private var username: String = "18806504525"
    
    /// 密码输入
    @State private var password: String = "spring"
    
    /// 错误提示信息
    @State private var errorMessage: String = ""
    
    /// 是否显示注册视图
    @State private var showRegister: Bool = false
    
    /// 是否正在登录（用于显示加载状态）
    @State private var isLoading: Bool = false
    
    /// 是否显示配置服务器窗口
    @State private var showConfigServer: Bool = false
    
    // MARK: - Initializer
    
    init() {
        _authService = StateObject(wrappedValue: AuthenticationService(socketManager: SocketManager.shared))
    }
    
    // MARK: - Body (界面布局)
    
    var body: some View {
        if showRegister {
            // 显示注册界面
            RegisterView(showRegister: $showRegister)
        } else {
            // 显示登录界面，带配置按钮
            ZStack(alignment: .bottomTrailing) {
                loginContent
                
                // 配置服务端地址按钮（右下角）
                Button("配置服务端地址") {
                    showConfigServer = true
                }
                .foregroundColor(.black)
                .font(.subheadline)
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .sheet(isPresented: $showConfigServer) {
                ConfigServerView()
                    .environmentObject(socketManager)
            }
        }
    }
    
    // MARK: - Login Content (登录界面内容)
    
    private var loginContent: some View {
        VStack(spacing: 25) {
            
            Spacer()
            
            // Logo 图标
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundColor(.accentColor)
            
            // 标题
            Text("毒药网盘，您的信赖之举")
                .font(.title)
                .fontWeight(.bold)
            
            // 用户名输入框
            VStack(alignment: .leading, spacing: 8) {
                Text("用户名")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("手机号或邮箱", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit {
                        // 按下回车键时，如果密码已填写则登录，否则跳转到密码框
                        if !password.isEmpty {
                            handleLogin()
                        }
                    }
                    .onChange(of: username) { _ in
                        // 清除错误信息（用户重新输入时）
                        if !errorMessage.isEmpty {
                            errorMessage = ""
                        }
                    }
            }
            
            // 密码输入框
            VStack(alignment: .leading, spacing: 8) {
                Text("密码")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                SecureField("请输入密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit {
                        // 按下回车键时触发登录
                        handleLogin()
                    }
                    .onChange(of: password) { _ in
                        // 清除错误信息（用户重新输入时）
                        if !errorMessage.isEmpty {
                            errorMessage = ""
                        }
                    }
            }
            
            // 错误提示
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .frame(width: 300, alignment: .leading)
            }
            
            // 登录按钮
            Button(action: handleLogin) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 280, height: 40)
                } else {
                    Text("登录")
                        .frame(width: 280, height: 40)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            
            // 注册按钮
            Button(action: {
                showRegister = true
            }) {
                Text("还没有账号？立即注册")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Socket 连接状态显示
            HStack(spacing: 8) {
                Circle()
                    .fill(socketManager.connectionState == .connected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                // 显示服务器地址和连接状态
                let server = socketManager.getCurrentServer()
                Text("服务器: \(server.host):\(server.port) \(socketManager.connectionState.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 10)
        }
        .frame(minWidth: 400, minHeight: 500)
        .padding()
    }
    
    // MARK: - Event Handlers (事件处理)
    
    /// 处理登录按钮点击事件
    private func handleLogin() {
        // 清除之前的错误信息
        errorMessage = ""
        
        // 验证用户名格式
        guard InputValidator.isValidUsername(username) else {
            errorMessage = InputValidator.getUsernameErrorMessage(username)
            return
        }
        
        // 验证密码
        guard InputValidator.isValidPassword(password) else {
            errorMessage = InputValidator.getPasswordErrorMessage(password)
            return
        }
        
        // 显示加载状态
        isLoading = true
        
        // 执行登录
        Task {
            do {
                let user = try await authService.login(
                    userName: username,
                    password: password
                )
                
                // 登录成功
                await MainActor.run {
                    isLoading = false
                    print("✅ 登录成功！用户名: \(user.userName)")
                    // TODO: 导航到主界面
                }
                
            } catch let error as AuthError {
                // 认证错误
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
                
            } catch let error as SocketError {
                // Socket 错误
                await MainActor.run {
                    isLoading = false
                    errorMessage = "连接错误: \(error.localizedDescription)"
                }
                
            } catch {
                // 其他错误
                await MainActor.run {
                    isLoading = false
                    errorMessage = "登录失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Preview (预览)

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(SocketManager.shared)
    }
}
