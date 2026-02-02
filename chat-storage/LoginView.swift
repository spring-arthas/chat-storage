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
    @EnvironmentObject var authService: AuthenticationService
    
    // MARK: - Bindings
    
    @Binding var isLoggedIn: Bool
    
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
    
    init(isLoggedIn: Binding<Bool>) {
        _isLoggedIn = isLoggedIn
    }
    
    // MARK: - Body (界面布局)
    
    var body: some View {
        if showRegister {
            // 显示注册界面
            RegisterView(showRegister: $showRegister)
        } else {
            // 显示登录界面
            loginContent
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
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(radius: 5)
            
            Text("毒药网盘，您的信赖之举")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black.opacity(0.8))
            
            // 输入区域组
            Group {
                // 用户名输入框
                VStack(alignment: .leading, spacing: 8) {
                    Text("用户名")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("请输入用户名", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .onSubmit {
                            // 如果密码和邮箱不为空，则尝试登录
                            if !password.isEmpty {
                                handleLogin()
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
                            handleLogin()
                        }
                }
                
                // 错误提示
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .frame(width: 300, alignment: .leading)
                }
            }
            
            // 登录按钮
            Button(action: handleLogin) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                } else {
                    Text("登录")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(width: 300)
            .disabled(isLoading || username.isEmpty || password.isEmpty)
            
            // 注册链接
            Button("还没有账号？立即注册") {
                showRegister = true
            }
            .buttonStyle(.link)
            .font(.footnote)
            
            // 错误信息
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Spacer()
            
            // 底部状态栏：连接状态 + 配置按钮
            HStack(spacing: 8) {
                // 左侧：Socket 连接状态显示
                Circle()
                    .fill(socketManager.connectionState == .connected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                // 显示服务器地址和连接状态
                let server = socketManager.getCurrentServer()
                Text("服务器: \(server.host):\(server.port) \(socketManager.connectionState.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()  // 将右侧按钮推到最右边
                
                // 右侧：配置服务端地址按钮
                Button("配置服务端地址") {
                    showConfigServer = true
                }
                .foregroundColor(.black)
                .font(.caption)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)
        }
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
                    // 导航到主界面
                    withAnimation {
                        isLoggedIn = true
                    }
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
        LoginView(isLoggedIn: .constant(false))
            .environmentObject(SocketManager.shared)
            .environmentObject(AuthenticationService.shared)
    }
}
