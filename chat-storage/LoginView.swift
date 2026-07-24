//
//  LoginView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import SwiftUI

struct LoginView: View {
    // MARK: - Environment Objects

    @EnvironmentObject var socketManager: SocketManager
    @EnvironmentObject var authService: AuthenticationService

    // MARK: - Bindings

    @Binding var isLoggedIn: Bool

    // MARK: - State Variables

    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var showRegister = false
    @State private var isLoading = false
    @State private var showConfigServer = false
    @State private var isPasswordVisible = false
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.migratedDefaultRawValue
    @FocusState private var focusedField: LoginField?

    private let loginContentTopInset: CGFloat = 38

    private enum LoginField: Hashable {
        case username
        case password
    }

    // MARK: - Initializer

    init(isLoggedIn: Binding<Bool>) {
        _isLoggedIn = isLoggedIn
#if DEBUG
        _username = State(initialValue: "18806504525")
        _password = State(initialValue: "spring")
#endif
    }

    // MARK: - Body

    var body: some View {
        if showRegister {
            RegisterView(showRegister: $showRegister)
        } else {
            loginContent
                .sheet(isPresented: $showConfigServer) {
                    ConfigServerView()
                        .environmentObject(socketManager)
                }
        }
    }

    // MARK: - Login Content

    private var loginContent: some View {
        ZStack {
            loginBackground

            HStack(spacing: 18) {
                workspacePreview
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)

                signInPanel
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.top, loginContentTopInset)
            .padding(.bottom, 18)
        }
        .preferredColorScheme(AppAppearanceMode(rawValue: appearanceModeRaw)?.colorScheme)
        .frame(
            width: AppWindowLayout.loginWidth,
            height: AppWindowLayout.loginHeight
        )
    }

    private var loginBackground: some View {
        TelegramTheme.appBackground
    }

    private var workspacePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewHeader

            Text("继续处理聊天与文件")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(TelegramTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)

            Text("登录页只保留功能入口说明，进入后继续使用完整工作台。")
                .font(.system(size: 12))
                .foregroundColor(TelegramTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            featureOverview
                .padding(.top, 18)

            Spacer(minLength: 16)

            connectionStatus
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TelegramTheme.panelBackground.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TelegramTheme.textSecondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var previewHeader: some View {
        HStack(spacing: 11) {
            appMark

            VStack(alignment: .leading, spacing: 3) {
                Text("桌面工作台")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TelegramTheme.textPrimary)

                Text("聊天、文件与传输状态集中处理")
                    .font(.system(size: 12))
                    .foregroundColor(TelegramTheme.textSecondary)
            }
            .lineLimit(1)
        }
    }

    private var appMark: some View {
        Text("D")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(TelegramTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: TelegramTheme.accent.opacity(0.22), radius: 10, y: 6)
    }

    private var featureOverview: some View {
        VStack(spacing: 10) {
            featurePillRow(
                icon: "message.circle",
                title: "聊天协作",
                detail: "继续处理消息、图片与文件。"
            )

            featurePillRow(
                icon: "externaldrive",
                title: "云盘管理",
                detail: "上传、下载和文件预览。"
            )

            featurePillRow(
                icon: "arrow.up.arrow.down.circle",
                title: "传输状态",
                detail: "查看任务、连接和失败提示。"
            )
        }
    }

    private func featurePillRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TelegramTheme.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(TelegramTheme.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TelegramTheme.elevatedBackground.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TelegramTheme.textSecondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 8, height: 8)
                .shadow(color: connectionStatusColor.opacity(0.32), radius: 4)

            Text(connectionStatusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TelegramTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var connectionStatusColor: Color {
        socketManager.connectionState == .connected ? TelegramTheme.success : TelegramTheme.textSecondary.opacity(0.42)
    }

    private var connectionStatusText: String {
        socketManager.connectionState == .connected ? "服务器连接正常" : socketManager.connectionState.description
    }

    private var signInPanel: some View {
        VStack {
            loginForm
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TelegramTheme.panelBackground.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TelegramTheme.textSecondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("欢迎回来")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(TelegramTheme.textPrimary)

            Text("输入账号信息继续使用聊天与云盘")
                .font(.system(size: 13))
                .foregroundColor(TelegramTheme.textSecondary)
                .padding(.top, 8)
                .padding(.bottom, 26)

            fieldLabel("账号")
            usernameField

            fieldLabel("密码")
                .padding(.top, 16)
            passwordField

            errorArea
                .padding(.top, 12)

            loginButton
                .padding(.top, 10)

            formFooter
                .padding(.top, 16)
        }
        .frame(width: 360)
        .padding(.horizontal, 28)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(TelegramTheme.textSecondary)
            .padding(.bottom, 8)
    }

    private var usernameField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(TelegramTheme.textSecondary)
                .frame(width: 18)

            TextField("手机号或用户名", text: $username)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .username)
                .disabled(isLoading)
                .onSubmit {
                    if password.isEmpty {
                        focusedField = .password
                    } else {
                        handleLogin()
                    }
                }
                .onChange(of: username) { _ in
                    clearErrorMessage()
                }
        }
        .modifier(LoginInputModifier(isFocused: focusedField == .username))
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(TelegramTheme.textSecondary)
                .frame(width: 18)

            Group {
                if isPasswordVisible {
                    TextField("输入登录密码", text: $password)
                        .textFieldStyle(.plain)
                } else {
                    SecureField("输入登录密码", text: $password)
                        .textFieldStyle(.plain)
                }
            }
            .focused($focusedField, equals: .password)
            .disabled(isLoading)
            .onSubmit {
                handleLogin()
            }
            .onChange(of: password) { _ in
                clearErrorMessage()
            }

            Button {
                isPasswordVisible.toggle()
                focusedField = .password
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help(isPasswordVisible ? "隐藏密码" : "显示密码")
            .accessibilityLabel(isPasswordVisible ? "隐藏密码" : "显示密码")
        }
        .modifier(LoginInputModifier(isFocused: focusedField == .password))
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
        .frame(height: 28, alignment: .topLeading)
    }

    private var loginButton: some View {
        Button(action: handleLogin) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(isLoading ? "正在登录…" : "登录")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TelegramTheme.accent.opacity(isLoginDisabled ? 0.48 : 1))
            )
            .shadow(
                color: isLoginDisabled ? .clear : TelegramTheme.accent.opacity(0.2),
                radius: 10,
                y: 6
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoginDisabled)
        .keyboardShortcut(.defaultAction)
    }

    private var formFooter: some View {
        HStack(spacing: 12) {
            serverConfigButton

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text("还没有账号？")
                    .foregroundColor(TelegramTheme.textSecondary)

                Button("创建账号") {
                    showRegister = true
                }
                .buttonStyle(.plain)
                .foregroundColor(TelegramTheme.accent)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }

    private var serverConfigButton: some View {
        Button {
            showConfigServer = true
        } label: {
            Label {
                Text("服务器设置")
                    .lineLimit(1)
            } icon: {
                Image(systemName: "gearshape")
            }
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .foregroundColor(TelegramTheme.textSecondary)
        .help("配置服务端地址")
    }

    private var isLoginDisabled: Bool {
        isLoading || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
    }

    // MARK: - Event Handlers

    private func clearErrorMessage() {
        if !errorMessage.isEmpty {
            errorMessage = ""
        }
    }

    private func handleLogin() {
        guard !isLoading else { return }

        errorMessage = ""

        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
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

        username = normalizedUsername
        isLoading = true

        Task {
            do {
                let user = try await authService.login(
                    userName: normalizedUsername,
                    password: password
                )

                await MainActor.run {
                    isLoading = false
                    print("✅ 登录成功！用户名: \(user.username)")
                    withAnimation {
                        isLoggedIn = true
                    }
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
                    errorMessage = "登录失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct LoginInputModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TelegramTheme.appBackground.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isFocused ? TelegramTheme.accent : TelegramTheme.textSecondary.opacity(0.18),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(color: isFocused ? TelegramTheme.accent.opacity(0.12) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

// MARK: - Preview

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LoginView(isLoggedIn: .constant(false))
                .preferredColorScheme(.light)

            LoginView(isLoggedIn: .constant(false))
                .preferredColorScheme(.dark)
        }
        .environmentObject(SocketManager.shared)
        .environmentObject(AuthenticationService.shared)
        .frame(width: AppWindowLayout.loginWidth, height: AppWindowLayout.loginHeight)
    }
}
