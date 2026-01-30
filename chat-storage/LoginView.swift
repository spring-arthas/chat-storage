//
//  LoginView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import SwiftUI

struct LoginView: View {
    // MARK: - State Variables (状态变量)
    
    /// 用户名输入（手机号或邮箱）
    @State private var username: String = ""
    
    /// 密码输入
    @State private var password: String = ""
    
    /// 错误提示信息
    @State private var errorMessage: String = ""
    
    /// 是否显示注册视图
    @State private var showRegister: Bool = false
    
    /// 是否正在登录（用于显示加载状态）
    @State private var isLoading: Bool = false
    
    // MARK: - Body (界面布局)
    
    var body: some View {
        if showRegister {
            // 显示注册界面
            RegisterView(showRegister: $showRegister)
        } else {
            // 显示登录界面
            loginContent
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
            Text("欢迎使用 Chat Storage")
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
        
        // ============ 伪代码：登录逻辑 ============
        // TODO: 替换为真实的 API 调用
        
        // 模拟网络请求延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // 伪代码：调用登录 API
            let success = performLogin(username: username, password: password)
            
            isLoading = false
            
            if success {
                // 登录成功：跳转到主界面
                print("✅ 登录成功！用户名: \(username)")
                // TODO: 导航到 ContentView（主界面）
                // 实现方式：在 App 级别管理登录状态，或使用 NavigationStack
            } else {
                // 登录失败：显示错误
                errorMessage = "用户名或密码错误"
            }
        }
        // ============ 伪代码结束 ============
    }
    
    /// 伪代码：执行登录请求
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    /// - Returns: 是否登录成功
    private func performLogin(username: String, password: String) -> Bool {
        // ============ 伪代码 ============
        // 这里应该调用真实的登录 API
        // 示例代码：
        /*
         let url = URL(string: "https://api.example.com/login")!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         
         let body = ["username": username, "password": password]
         request.httpBody = try? JSONSerialization.data(withJSONObject: body)
         
         URLSession.shared.dataTask(with: request) { data, response, error in
             // 处理响应
         }.resume()
         */
        
        // 模拟登录验证（仅供测试）
        // 测试账号：phone: 13800138000, email: test@example.com, password: 123456
        let isValidAccount = (username == "13800138000" || username == "test@example.com") 
                             && password == "123456"
        
        return isValidAccount
        // ============ 伪代码结束 ============
    }
}

// MARK: - Preview (预览)

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
