//
//  RegisterView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import SwiftUI

struct RegisterView: View {
    // MARK: - Binding (父视图传入的绑定)
    
    /// 控制是否显示注册视图（由父视图 LoginView 传入）
    @Binding var showRegister: Bool
    
    /// 认证服务
    @StateObject private var authService: AuthenticationService
    
    // MARK: - Initializer
    
    init(showRegister: Binding<Bool>) {
        _showRegister = showRegister
        _authService = StateObject(wrappedValue: AuthenticationService(socketManager: SocketManager.shared))
    }
    
    // MARK: - State Variables (状态变量)
    
    /// 用户名输入（手机号或邮箱）
    @State private var username: String = ""
    
    /// 密码输入
    @State private var password: String = ""
    
    /// 确认密码输入
    @State private var confirmPassword: String = ""
    
    /// 错误提示信息
    @State private var errorMessage: String = ""
    
    /// 是否正在注册（用于显示加载状态）
    @State private var isLoading: Bool = false
    
    // MARK: - Body (界面布局)
    
    var body: some View {
        VStack(spacing: 25) {
            
            Spacer()
            
            // Logo 图标
            Image(systemName: "person.crop.circle.badge.plus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundColor(.green)
            
            // 标题
            Text("创建新账号")
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
                    .onChange(of: username) { _ in
                        // 清除错误信息
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
                
                SecureField("至少6位字符", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onChange(of: password) { _ in
                        if !errorMessage.isEmpty {
                            errorMessage = ""
                        }
                    }
            }
            
            // 确认密码输入框
            VStack(alignment: .leading, spacing: 8) {
                Text("确认密码")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                SecureField("再次输入密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onChange(of: confirmPassword) { _ in
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
            
            // 注册按钮
            Button(action: handleRegister) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 280, height: 40)
                } else {
                    Text("注册")
                        .frame(width: 280, height: 40)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            
            // 返回登录按钮
            Button(action: {
                showRegister = false
            }) {
                Text("已有账号？返回登录")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .frame(minWidth: 400, minHeight: 550)
        .padding()
    }
    
    // MARK: - Event Handlers (事件处理)
    
    /// 处理注册按钮点击事件
    private func handleRegister() {
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
        
        // 验证两次密码是否一致
        guard password == confirmPassword else {
            errorMessage = "两次输入的密码不一致"
            return
        }
        
        // 显示加载状态
        isLoading = true
        
        // 执行注册
        Task {
            do {
                let user = try await authService.register(
                    userName: username,
                    password: password,
                    mail: username  // 使用用户名作为邮箱（如果是邮箱格式）
                )
                
                // 注册成功
                await MainActor.run {
                    isLoading = false
                    print("✅ 注册成功！用户名: \(user.userName)")
                    // 返回登录界面
                    showRegister = false
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
                    errorMessage = "注册失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Preview (预览)

struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        RegisterView(showRegister: .constant(true))
    }
}
