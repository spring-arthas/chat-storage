//
//  NewFriendView.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/11.
//  UI Layout for New Friend Requests
//

import SwiftUI

struct NewFriendView: View {
    @EnvironmentObject var socketManager: SocketManager
    // Remove local state, use SocketManager's published property
    // @State private var requests: [FriendRequestDto] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Modal state
    @State private var showingAliasAlert = false
    @State private var aliasInput = ""
    @State private var selectedRequestId: Int64? = nil
    @State private var selectedRequestAvatar: String? = nil
    @State private var selectedRequestNickName: String? = nil
    @State private var isProcessingAlias = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("新的朋友")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                
                Button(action: loadRequests) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新")
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // List
            if isLoading && socketManager.pendingFriendRequests.isEmpty {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("重试", action: loadRequests)
                }
                Spacer()
            } else if socketManager.pendingFriendRequests.isEmpty {
                Spacer()
                Text("暂无好友申请")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(socketManager.pendingFriendRequests) { request in
                            FriendRequestRow(request: request) { reqId, act, alias in
                                if act == 1 && alias == nil {
                                    // Show alias modal
                                    selectedRequestId = reqId
                                    selectedRequestAvatar = request.senderAvatar
                                    selectedRequestNickName = request.senderNickName
                                    aliasInput = request.senderNickName
                                    withAnimation {
                                        showingAliasAlert = true
                                    }
                                } else {
                                    handleAction(requestId: reqId, action: act, alias: alias)
                                }
                            }
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Refresh on appear to ensure latest data
            loadRequests()
        }
        .overlay(
            Group {
                if showingAliasAlert, let reqId = selectedRequestId, let nickName = selectedRequestNickName {
                    ZStack {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                            .onTapGesture {
                                // Optional: dismiss on tap
                            }
                        
                        VStack(spacing: 16) {
                            // Large Avatar
                            let cleanAvatar = selectedRequestAvatar?.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let avatarStr = cleanAvatar, !avatarStr.isEmpty,
                               let avatarData = Data(base64Encoded: avatarStr, options: .ignoreUnknownCharacters),
                               let nsImage = NSImage(data: avatarData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.3), lineWidth: 1))
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 80, height: 80)
                                    .overlay(Text(nickName.prefix(1)).foregroundColor(.white).font(.system(size: 32, weight: .bold)))
                            }
                            
                            Text("【快来为好友添加一个爱称吧】")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            
                            TextField("输入备注名", text: $aliasInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 260)
                            
                            HStack(spacing: 16) {
                                Button(action: {
                                    withAnimation {
                                        showingAliasAlert = false
                                    }
                                }) {
                                    Text("取消")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                
                                Button(action: {
                                    isProcessingAlias = true
                                    Task {
                                        do {
                                            let success = try await socketManager.handleFriendRequest(requestId: reqId, action: 1, alias: aliasInput)
                                            if success {
                                                await MainActor.run {
                                                    withAnimation { showingAliasAlert = false }
                                                    loadRequests()
                                                }
                                                // 延迟500ms防止服务端DB事务尚未完全提交
                                                try? await Task.sleep(nanoseconds: 500_000_000)
                                                // 此时调用0x35帧类型请求来刷新最新的好友列表
                                                let friends = try await socketManager.getFriendList()
                                                await MainActor.run {
                                                    socketManager.friendList = friends
                                                    isProcessingAlias = false
                                                }
                                            } else {
                                                await MainActor.run { isProcessingAlias = false }
                                            }
                                        } catch {
                                            await MainActor.run { isProcessingAlias = false }
                                            print("Failed to handle request: \(error)")
                                        }
                                    }
                                }) {
                                    if isProcessingAlias {
                                        ProgressView().scaleEffect(0.5).frame(height: 16)
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Text("确定")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .disabled(isProcessingAlias)
                            }
                            .frame(width: 260)
                        }
                        .padding(24)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(12)
                        .shadow(radius: 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(100)
                }
            }
        )
    }
    
    private func loadRequests() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // This updates socketManager.pendingFriendRequests automatically
                let _ = try await socketManager.getPendingRequests()
                await MainActor.run {
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func handleAction(requestId: Int64, action: Int, alias: String? = nil) {
        Task {
            do {
                let success = try await socketManager.handleFriendRequest(requestId: requestId, action: action, alias: alias)
                if success {
                    await MainActor.run {
                        // Refresh list to update status
                        loadRequests()
                    }
                }
            } catch {
                print("Failed to handle request: \(error)")
            }
        }
    }
}

private struct FriendRequestRow: View {
    let request: FriendRequestDto
    let onAction: (Int64, Int, String?) -> Void
    @State private var isHovering = false
    @State private var isProcessing = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            let cleanAvatar = request.senderAvatar?.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let avatarStr = cleanAvatar, !avatarStr.isEmpty,
               let avatarData = Data(base64Encoded: avatarStr, options: .ignoreUnknownCharacters),
               let nsImage = NSImage(data: avatarData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(Text(request.senderNickName.prefix(1)).foregroundColor(.white).font(.headline))
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(request.senderNickName)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(request.requestMsg)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action Buttons or Status
            if request.status == 0 {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(height: 20)
                    } else {
                        Button(action: {
                            isProcessing = true
                            onAction(request.id, 2, nil) // Reject
                        }) {
                            Text("拒绝")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: {
                            onAction(request.id, 1, nil)
                        }) {
                            Text("同意")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            } else {
                Text(request.status == 1 ? "已添加" : "已拒绝")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)
            }
        }
        .padding(12)
        .background(isHovering ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// Preview Provider (Optional, requires wrapping in #if DEBUG)
#if DEBUG
struct NewFriendView_Previews: PreviewProvider {
    static var previews: some View {
        NewFriendView()
            .frame(width: 400, height: 500)
    }
}
#endif
