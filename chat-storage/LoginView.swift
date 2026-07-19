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
    @FocusState private var focusedField: LoginField?

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
        HStack(spacing: 0) {
            brandPanel
                .frame(width: AppWindowLayout.loginWidth * 0.4)

            loginForm
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            width: AppWindowLayout.loginWidth,
            height: AppWindowLayout.loginHeight
        )
    }

    private var brandPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 23 / 255, green: 40 / 255, blue: 58 / 255)

            brandDecoration

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

    private var brandDecoration: some View {
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

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("欢迎回来")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(.primary)

            Text("请输入账号信息继续使用")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.bottom, 22)

            fieldLabel("账号")
            usernameField

            fieldLabel("密码")
                .padding(.top, 14)
            passwordField

            errorArea
                .padding(.top, 10)

            loginButton
                .padding(.top, 8)

            formFooter
                .padding(.top, 17)
        }
        .frame(width: 310)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 7)
    }

    private var usernameField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(TelegramTheme.accent.opacity(isLoginDisabled ? 0.48 : 1))
            )
            .shadow(
                color: isLoginDisabled ? .clear : TelegramTheme.accent.opacity(0.2),
                radius: 7,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoginDisabled)
        .keyboardShortcut(.defaultAction)
    }

    private var formFooter: some View {
        HStack(spacing: 12) {
            Button {
                showConfigServer = true
            } label: {
                Label("服务器设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("配置服务端地址")

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text("还没有账号？")
                    .foregroundStyle(.secondary)

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
