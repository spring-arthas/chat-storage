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
        
        // ============ 伪代码：注册逻辑 ============
        // TODO: 替换为真实的 API 调用
        
        // 模拟网络请求延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // 伪代码：调用注册 API
            let success = performRegister(username: username, password: password)
            
            isLoading = false
            
            if success {
                // 注册成功：返回登录界面或直接登录
                print("✅ 注册成功！用户名: \(username)")
                // 方案1: 返回登录界面，让用户重新登录
                showRegister = false
                // 方案2: 自动登录并跳转到主界面（需要实现状态管理）
                // TODO: 在实际项目中，可以保存注册返回的 Token，然后直接进入主界面
            } else {
                // 注册失败：显示错误
                errorMessage = "注册失败，该账号可能已存在"
            }
        }
        // ============ 伪代码结束 ============
    }
    
    /// 伪代码：执行注册请求
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    /// - Returns: 是否注册成功
    private func performRegister(username: String, password: String) -> Bool {
        // ============ 伪代码 ============
        // 这里应该调用真实的注册 API
        // 示例代码：
        /*
         let url = URL(string: "https://api.example.com/register")!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         
         let body = ["username": username, "password": password]
         request.httpBody = try? JSONSerialization.data(withJSONObject: body)
         
         URLSession.shared.dataTask(with: request) { data, response, error in
             // 处理响应
             if let data = data {
                 // 解析返回的 JSON
                 // 保存 Token 到 UserDefaults 或 Keychain
             }
         }.resume()
         */
        
        // 模拟注册验证（仅供测试）
        // 这里简单返回 true，表示注册成功
        print("📝 伪代码：正在注册账号...")
        print("   用户名: \(username)")
        print("   密码: \(password)")
        
        // 实际项目中，这里需要：
        // 1. 发送 POST 请求到服务器
        // 2. 检查服务器返回的状态码
        // 3. 如果成功，保存返回的 Token
        // 4. 如果失败，解析错误信息（如"用户已存在"）
        
        return true // 模拟注册成功
        // ============ 伪代码结束 ============
    }
}

// MARK: - Preview (预览)

struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        RegisterView(showRegister: .constant(true))
    }
}
