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
    
    /// 邮箱输入
    @State private var email: String = ""
    
    /// 错误提示信息
    @State private var errorMessage: String = ""
    
    /// 是否正在注册（用于显示加载状态）
    @State private var isLoading: Bool = false
    
    // MARK: - Avatar Selection State
    
    /// 选中的头像图片
    @State private var selectedAvatar: NSImage?
    
    /// 是否正在悬停头像区域
    @State private var isHoveringAvatar: Bool = false
    
    // MARK: - Body (界面布局)
    
    var body: some View {
        VStack(spacing: 25) {
            
            Spacer()
            
            // 头像选择区域
            Button(action: selectAvatar) {
                ZStack {
                    if let avatar = selectedAvatar {
                        Image(nsImage: avatar)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    } else {
                        // 默认状态：灰色背景 + 相机图标 (明显的 UI 变化)
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(.secondary)
                                    Text("上传头像")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            )
                            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    }
                    
                    // 悬停效果 (仅在有图片时显示遮罩，或者是默认状态下的高亮)
                    if isHoveringAvatar && selectedAvatar != nil {
                         Circle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "pencil")
                                    .foregroundColor(.white)
                                    .font(.title)
                            )
                    }
                }
            }
            .buttonStyle(.plain) // 无边框按钮
            .onHover { hovering in
                withAnimation {
                    isHoveringAvatar = hovering
                }
            }
            .help("点击选择头像")
            
            // 标题
            Text("创建新账号 (UI v2.0)")
                .font(.title)
                .fontWeight(.bold)
            
            // 输入区域组
            Group {
                // 用户名输入框
                VStack(alignment: .leading, spacing: 8) {
                    Text("用户名")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("手机号或邮箱", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .onSubmit {
                            // 按回车跳转到下一个输入框或注册
                            if !password.isEmpty && !confirmPassword.isEmpty && !email.isEmpty {
                                handleRegister()
                            }
                        }
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
                        .onSubmit {
                            // 按回车跳转到下一个输入框或注册
                            if !confirmPassword.isEmpty && !email.isEmpty {
                                handleRegister()
                            }
                        }
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
                        .onSubmit {
                            // 按回车跳转到邮箱输入框或注册
                            if !email.isEmpty {
                                handleRegister()
                            }
                        }
                        .onChange(of: confirmPassword) { _ in
                            if !errorMessage.isEmpty {
                                errorMessage = ""
                            }
                        }
                }
                
                // 邮箱输入框
                VStack(alignment: .leading, spacing: 8) {
                    Text("邮箱")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("请输入邮箱地址", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .onSubmit {
                            // 按回车触发注册
                            handleRegister()
                        }
                        .onChange(of: email) { _ in
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
        .frame(minWidth: 400, minHeight: 600)
        .padding()
    }
    
    // MARK: - Event Handlers (事件处理)
    
    /// 选择头像文件
    private func selectAvatar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image] // 仅允许图片
        panel.prompt = "选择头像"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let image = NSImage(contentsOf: url) {
                    // 优化图片：调整大小并裁剪为正方形，适配 Retina 显示 (2x)
                    // 目标尺寸 100pt * 2 = 200px
                    let targetSize = NSSize(width: 200, height: 200)
                    let processedImage = image.resizeAndCrop(to: targetSize)
                    
                    self.selectedAvatar = processedImage ?? image
                    print("📸 已选择并处理头像: \(url.lastPathComponent)")
                } else {
                    print("❌ 无法加载图片: \(url.path)")
                }
            }
        }
    }
    
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
        
        // 验证邮箱格式
        guard InputValidator.isValidEmail(email) else {
            errorMessage = InputValidator.getEmailErrorMessage(email)
            return
        }
        
        // 处理头像数据
        var avatarData: String? = nil
        var avatarName: String? = nil
        
        if let avatar = selectedAvatar {
            // 将 NSImage 转为 Data (JPEG 格式，压缩质量 0.7)
            if let tiffData = avatar.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                
                // 检查大小是否超过限制 (例如 100KB)
                if jpegData.count > 100 * 1024 {
                    print("⚠️ 头像过大 (\(jpegData.count / 1024)KB)，建议使用更小的图片")
                    // 这里可以选择进一步压缩或者提示用户，目前仅打印警告
                }
                
                // 转为 Base64 字符串
                avatarData = jpegData.base64EncodedString()
                avatarName = "avatar.jpg" // 默认文件名，或者保留原始文件名如果能获取到
                print("📸 头像已编码，大小: \(jpegData.count) bytes")
            } else {
                print("❌ 头像编码失败")
            }
        }
        
        // 显示加载状态
        isLoading = true
        
        // 执行注册
        Task {
            do {
                let user = try await authService.register(
                    userName: username,
                    password: password,
                    mail: email,
                    avatarData: avatarData,
                    avatarName: avatarName
                )
                
                // 注册成功
                await MainActor.run {
                    isLoading = false
                    print("✅ 注册成功！用户名: \(user.username)")
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

// MARK: - Image Processing Extension

extension NSImage {
    /// 调整图片大小并居中裁剪
    func resizeAndCrop(to targetSize: NSSize) -> NSImage? {
        let originalSize = self.size
        let widthRatio = targetSize.width / originalSize.width
        let heightRatio = targetSize.height / originalSize.height
        
        // 使用较大的比例以填满目标区域 (Aspect Fill)
        let scale = max(widthRatio, heightRatio)
        
        let newSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let x = (targetSize.width - newSize.width) / 2
        let y = (targetSize.height - newSize.height) / 2
        
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        // 设置高质量重采样
        NSGraphicsContext.current?.imageInterpolation = .high
        
        self.draw(in: NSRect(origin: CGPoint(x: x, y: y), size: newSize),
                  from: NSRect(origin: .zero, size: originalSize),
                  operation: .copy,
                  fraction: 1.0)
        
        newImage.unlockFocus()
        return newImage
    }
}
