//
//  RegisterView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RegisterView: View {
    // MARK: - Environment Objects

    @EnvironmentObject private var socketManager: SocketManager

    // MARK: - Bindings

    @Binding var showRegister: Bool

    // MARK: - Services

    @StateObject private var authService: AuthenticationService

    // MARK: - Form State

    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var email = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var currentStep: RegisterStep = .profile
    @FocusState private var focusedField: RegisterField?

    // MARK: - Avatar State

    @State private var selectedAvatar: NSImage?
    @State private var isHoveringAvatar = false

    private enum RegisterField: Hashable {
        case username
        case password
        case confirmPassword
        case email
    }

    private enum RegisterStep: Int, CaseIterable {
        case profile = 1
        case security = 2

        var title: String {
            switch self {
            case .profile: return "基础资料"
            case .security: return "安全设置"
            }
        }

        var subtitle: String {
            switch self {
            case .profile: return "设置头像和账号信息"
            case .security: return "设置登录密码完成注册"
            }
        }
    }

    // MARK: - Initializer

    init(showRegister: Binding<Bool>) {
        _showRegister = showRegister
        _authService = StateObject(wrappedValue: AuthenticationService(socketManager: SocketManager.shared))
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(width: AppWindowLayout.loginWidth * 0.4)

            registerForm
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            width: AppWindowLayout.loginWidth,
            height: AppWindowLayout.loginHeight
        )
    }

    // MARK: - Brand Panel

    private var brandPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 23 / 255, green: 40 / 255, blue: 58 / 255)

            panelDecoration

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("D")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(TelegramTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: TelegramTheme.accent.opacity(0.25), radius: 8, y: 5)

                    Text("云境")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer(minLength: 34)

                Text("让聊天与文件，\n始终触手可及。")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Text("连接好友、即时消息和你的私人云盘，\n所有重要内容都在一处。")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.66))
                    .lineSpacing(5)
                    .padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                connectionStatus
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .clipped()
    }

    private var panelDecoration: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: 210, height: 210)

            Circle()
                .stroke(Color.white.opacity(0.045), lineWidth: 32)
                .frame(width: 280, height: 280)
        }
        .offset(x: 112, y: 118)
        .allowsHitTesting(false)
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 7, height: 7)
                .shadow(color: connectionStatusColor.opacity(0.3), radius: 3)

            Text(connectionStatusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(0.68))
                .lineLimit(1)
        }
    }

    private var connectionStatusColor: Color {
        socketManager.connectionState == .connected ? TelegramTheme.success : Color.white.opacity(0.42)
    }

    private var connectionStatusText: String {
        socketManager.connectionState == .connected ? "服务器连接正常" : socketManager.connectionState.description
    }

    private var avatarSelector: some View {
        Button(action: selectAvatar) {
            HStack(spacing: 12) {
                ZStack {
                    if let avatar = selectedAvatar {
                        Image(nsImage: avatar)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(TelegramTheme.accent.opacity(0.08))
                            .frame(width: 52, height: 52)

                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(TelegramTheme.accent)
                    }

                    Circle()
                        .stroke(
                            isHoveringAvatar ? TelegramTheme.accent : Color(nsColor: .separatorColor).opacity(0.8),
                            lineWidth: isHoveringAvatar ? 1.5 : 1
                        )
                        .frame(width: 52, height: 52)

                    if isHoveringAvatar {
                        Circle()
                            .fill(Color.black.opacity(selectedAvatar == nil ? 0.05 : 0.34))
                            .frame(width: 52, height: 52)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedAvatar == nil ? TelegramTheme.accent : .white)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedAvatar == nil ? "添加头像" : "更换头像")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("选填，支持常见图片格式")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHoveringAvatar = hovering
            }
        }
        .help("点击选择头像")
        .accessibilityLabel(selectedAvatar == nil ? "添加头像" : "更换头像")
    }

    // MARK: - Register Form

    private var registerForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepIndicator

            Text(currentStep.title)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 12)

            Text(currentStep.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 12)

            Group {
                switch currentStep {
                case .profile:
                    profileStep
                case .security:
                    securityStep
                }
            }
            .id(currentStep)
            .transition(.opacity)

            formFooter
                .padding(.top, 10)
        }
        .frame(width: 310)
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
        .animation(.easeInOut(duration: 0.18), value: currentStep)
    }

    private var stepIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("步骤 \(currentStep.rawValue) / \(RegisterStep.allCases.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TelegramTheme.accent)

                Spacer()

                Text(currentStep == .profile ? "下一步：安全设置" : "最后一步")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(RegisterStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? TelegramTheme.accent : Color(nsColor: .separatorColor).opacity(0.7))
                        .frame(height: 4)
                }
            }
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            avatarSelector

            fieldLabel("账号")
                .padding(.top, 10)
            usernameField

            fieldLabel("邮箱")
                .padding(.top, 10)
            emailField

            errorArea
                .padding(.top, 6)

            nextButton
                .padding(.top, 6)
        }
    }

    private var securityStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("密码")
            passwordField

            fieldLabel("确认密码")
                .padding(.top, 12)
            confirmPasswordField

            securityHint
                .padding(.top, 10)

            errorArea
                .padding(.top, 6)

            HStack(spacing: 10) {
                previousButton
                    .frame(width: 96)

                registerButton
            }
            .padding(.top, 6)
        }
    }

    private var securityHint: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TelegramTheme.accent)

            Text("密码至少 6 位，两次输入需保持一致")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var formFooter: some View {
        HStack(spacing: 4) {
            Spacer()

            Text("已有账号？")
                .foregroundStyle(.secondary)

            Button("返回登录") {
                guard !isLoading else { return }
                showRegister = false
            }
            .buttonStyle(.plain)
            .foregroundColor(TelegramTheme.accent)
            .disabled(isLoading)
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 7)
    }

    private var usernameField: some View {
        HStack(spacing: 9) {
            registerFieldIcon("person")

            TextField("手机号或用户名", text: $username)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .username)
                .disabled(isLoading)
                .onSubmit {
                    focusedField = .email
                }
                .onChange(of: username) { _ in
                    clearErrorMessage()
                }
        }
        .modifier(RegisterInputModifier(isFocused: focusedField == .username))
    }

    private var passwordField: some View {
        HStack(spacing: 9) {
            registerFieldIcon("lock")

            Group {
                if isPasswordVisible {
                    TextField("至少 6 位字符", text: $password)
                        .textFieldStyle(.plain)
                } else {
                    SecureField("至少 6 位字符", text: $password)
                        .textFieldStyle(.plain)
                }
            }
            .focused($focusedField, equals: .password)
            .disabled(isLoading)
            .onSubmit {
                focusedField = .confirmPassword
            }
            .onChange(of: password) { _ in
                clearErrorMessage()
            }

            passwordVisibilityButton(
                isVisible: $isPasswordVisible,
                accessibilityLabel: isPasswordVisible ? "隐藏密码" : "显示密码"
            )
        }
        .modifier(RegisterInputModifier(isFocused: focusedField == .password))
    }

    private var confirmPasswordField: some View {
        HStack(spacing: 9) {
            registerFieldIcon("lock.rotation")

            Group {
                if isConfirmPasswordVisible {
                    TextField("再次输入密码", text: $confirmPassword)
                        .textFieldStyle(.plain)
                } else {
                    SecureField("再次输入密码", text: $confirmPassword)
                        .textFieldStyle(.plain)
                }
            }
            .focused($focusedField, equals: .confirmPassword)
            .disabled(isLoading)
            .onSubmit {
                handleRegister()
            }
            .onChange(of: confirmPassword) { _ in
                clearErrorMessage()
            }

            passwordVisibilityButton(
                isVisible: $isConfirmPasswordVisible,
                accessibilityLabel: isConfirmPasswordVisible ? "隐藏确认密码" : "显示确认密码"
            )
        }
        .modifier(RegisterInputModifier(isFocused: focusedField == .confirmPassword))
    }

    private var emailField: some View {
        HStack(spacing: 9) {
            registerFieldIcon("envelope")

            TextField("请输入邮箱地址", text: $email)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .email)
                .disabled(isLoading)
                .onSubmit {
                    advanceToSecurityStep()
                }
                .onChange(of: email) { _ in
                    clearErrorMessage()
                }
        }
        .modifier(RegisterInputModifier(isFocused: focusedField == .email))
    }

    private func registerFieldIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 17)
    }

    private func passwordVisibilityButton(
        isVisible: Binding<Bool>,
        accessibilityLabel: String
    ) -> some View {
        Button {
            isVisible.wrappedValue.toggle()
        } label: {
            Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 21, height: 21)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }

    private var errorArea: some View {
        Group {
            if errorMessage.isEmpty {
                Color.clear
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(TelegramTheme.danger)
                        .padding(.top, 1)

                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(TelegramTheme.danger)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 24, alignment: .topLeading)
    }

    private var nextButton: some View {
        Button(action: advanceToSecurityStep) {
            HStack(spacing: 8) {
                Text("下一步")
                    .font(.system(size: 13, weight: .semibold))

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(TelegramTheme.accent.opacity(isNextDisabled ? 0.48 : 1))
            )
            .shadow(
                color: isNextDisabled ? .clear : TelegramTheme.accent.opacity(0.2),
                radius: 7,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(isNextDisabled)
        .keyboardShortcut(.defaultAction)
    }

    private var previousButton: some View {
        Button(action: returnToProfileStep) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 11, weight: .semibold))

                Text("上一步")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var registerButton: some View {
        Button(action: handleRegister) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(isLoading ? "正在注册…" : "创建账号")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(TelegramTheme.accent.opacity(isRegisterDisabled ? 0.48 : 1))
            )
            .shadow(
                color: isRegisterDisabled ? .clear : TelegramTheme.accent.opacity(0.2),
                radius: 7,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(isRegisterDisabled)
        .keyboardShortcut(.defaultAction)
    }

    private var isNextDisabled: Bool {
        isLoading ||
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isRegisterDisabled: Bool {
        isLoading ||
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Event Handlers

    private func clearErrorMessage() {
        if !errorMessage.isEmpty {
            errorMessage = ""
        }
    }

    private func advanceToSecurityStep() {
        guard !isLoading else { return }

        errorMessage = ""

        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard InputValidator.isValidUsername(normalizedUsername) else {
            errorMessage = InputValidator.getUsernameErrorMessage(normalizedUsername)
            focusedField = .username
            return
        }

        guard InputValidator.isValidEmail(normalizedEmail) else {
            errorMessage = InputValidator.getEmailErrorMessage(normalizedEmail)
            focusedField = .email
            return
        }

        username = normalizedUsername
        email = normalizedEmail
        focusedField = nil

        withAnimation(.easeInOut(duration: 0.18)) {
            currentStep = .security
        }

        DispatchQueue.main.async {
            focusedField = .password
        }
    }

    private func returnToProfileStep() {
        guard !isLoading else { return }

        errorMessage = ""
        focusedField = nil

        withAnimation(.easeInOut(duration: 0.18)) {
            currentStep = .profile
        }

        DispatchQueue.main.async {
            focusedField = .username
        }
    }

    private func selectAvatar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "选择头像"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let image = NSImage(contentsOf: url) {
                    let targetSize = NSSize(width: 200, height: 200)
                    let processedImage = image.resizeAndCrop(to: targetSize)

                    selectedAvatar = processedImage ?? image
                    print("📸 已选择并处理头像: \(url.lastPathComponent)")
                } else {
                    print("❌ 无法加载图片: \(url.path)")
                }
            }
        }
    }

    private func handleRegister() {
        guard !isLoading else { return }

        guard currentStep == .security else {
            advanceToSecurityStep()
            return
        }

        errorMessage = ""

        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard InputValidator.isValidUsername(normalizedUsername) else {
            errorMessage = InputValidator.getUsernameErrorMessage(normalizedUsername)
            focusedField = .username
            return
        }

        guard InputValidator.isValidPassword(password) else {
            errorMessage = InputValidator.getPasswordErrorMessage(password)
            focusedField = .password
            return
        }

        guard password == confirmPassword else {
            errorMessage = "两次输入的密码不一致"
            focusedField = .confirmPassword
            return
        }

        guard InputValidator.isValidEmail(normalizedEmail) else {
            errorMessage = InputValidator.getEmailErrorMessage(normalizedEmail)
            focusedField = .email
            return
        }

        username = normalizedUsername
        email = normalizedEmail

        var avatarData: String?
        var avatarName: String?

        if let avatar = selectedAvatar {
            if let tiffData = avatar.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                if jpegData.count > 100 * 1024 {
                    print("⚠️ 头像过大 (\(jpegData.count / 1024)KB)，建议使用更小的图片")
                }

                avatarData = jpegData.base64EncodedString()
                avatarName = "avatar.jpg"
                print("📸 头像已编码，大小: \(jpegData.count) bytes")
            } else {
                print("❌ 头像编码失败")
            }
        }

        isLoading = true

        Task {
            do {
                let user = try await authService.register(
                    userName: normalizedUsername,
                    password: password,
                    mail: normalizedEmail,
                    avatarData: avatarData,
                    avatarName: avatarName
                )

                await MainActor.run {
                    isLoading = false
                    print("✅ 注册成功！用户名: \(user.username)")
                    showRegister = false
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            } catch let error as SocketError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "连接错误: \(error.localizedDescription)"
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "注册失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct RegisterInputModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isFocused ? TelegramTheme.accent : Color(nsColor: .separatorColor).opacity(0.8),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(color: isFocused ? TelegramTheme.accent.opacity(0.12) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

// MARK: - Preview

struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RegisterView(showRegister: .constant(true))
                .preferredColorScheme(.light)

            RegisterView(showRegister: .constant(true))
                .preferredColorScheme(.dark)
        }
        .environmentObject(SocketManager.shared)
        .frame(width: AppWindowLayout.loginWidth, height: AppWindowLayout.loginHeight)
    }
}

// MARK: - Image Processing

extension NSImage {
    func resizeAndCrop(to targetSize: NSSize) -> NSImage? {
        let originalSize = size
        let widthRatio = targetSize.width / originalSize.width
        let heightRatio = targetSize.height / originalSize.height
        let scale = max(widthRatio, heightRatio)

        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
        let x = (targetSize.width - newSize.width) / 2
        let y = (targetSize.height - newSize.height) / 2

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        draw(
            in: NSRect(origin: CGPoint(x: x, y: y), size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }
}
