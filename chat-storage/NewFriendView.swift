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
                            FriendRequestRow(request: request, onAction: handleAction)
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
    
    private func handleAction(requestId: Int64, action: Int) {
        Task {
            do {
                let success = try await socketManager.handleFriendRequest(requestId: requestId, action: action)
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
    let onAction: (Int64, Int) -> Void
    @State private var isHovering = false
    @State private var isProcessing = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            if let avatarStr = request.senderAvatar,
               let avatarData = Data(base64Encoded: avatarStr),
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
                            onAction(request.id, 2) // Reject
                        }) {
                            Text("拒绝")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: {
                            isProcessing = true
                            onAction(request.id, 1) // Accept
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
