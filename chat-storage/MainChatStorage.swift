//
//  MainChatStorage.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/31.
//

import SwiftUI
import Combine

/// 主文件管理界面
struct MainChatStorage: View {
    
    // MARK: - Environment Objects
    
    @EnvironmentObject var socketManager: SocketManager
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var transferManager = TransferTaskManager.shared
    @StateObject private var downloadDirectoryManager = DownloadDirectoryManager.shared
    
    // MARK: - Bindings
    
    @Binding var isLoggedIn: Bool
    
    // MARK: - State Variables
    
    /// 服务地址
    @State private var serverAddress: String = ""
    
    /// 当前目录路径
    @State private var currentPath: String = "个人网盘" 
    
    /// 下载路径
    @State private var downloadPath: String = ""
    
    /// 文件列表 (浏览)
    @State private var fileList: [DirectoryItem] = []
    
    /// 传输任务列表 (上传/下载)
    @State private var transferList: [TransferItem] = []
    
    /// 选中的文件
    @State private var selectedFiles: Set<Int64> = []
    
    /// 当前页码 (从 1 开始)
    @State private var currentPage: Int = 1
    
    /// 每页显示数量
    @State private var itemsPerPage: Int = 13
    
    /// 总页数
    @State private var totalPages: Int = 1
    
    /// 总记录数
    @State private var totalCount: Int64 = 0
    
    /// 当前时间
    @State private var currentTime: String = ""
    
    /// 定时器
    @State private var timer: Timer?
    
    /// 当前选中的标签页 (默认进入好友列表: 0)
    @State private var selectedTab: Int = 0
    
    /// 目录树数据
    @State private var directoryTree: [DirectoryItem] = []
    
    /// 展开的目录节点 ID
    @State private var expandedDirectoryIds: Set<Int64> = []
    
    /// 当前选中的目录 ID
    @State private var selectedDirectoryId: Int64?
    
    // MARK: - Search State
    
    /// 搜索关键字
    @State private var searchKeyword: String = ""
    
    /// 搜索选中的目录 ID (nil 表示全部)
    @State private var searchDirectoryId: Int64? = nil
    
    /// 是否显示弹窗
    @State private var showingAlert = false
    
    /// 弹窗消息
    @State private var alertMessage = ""
    
    /// 是否正在加载目录
    @State private var isLoadingDirectory = false
    
    /// 目录服务
    @State private var directoryService: DirectoryService?
    
    // MARK: - Create Directory State
    
    /// 是否显示新建目录弹窗
    @State private var showingCreateDirDialog = false
    
    /// 新建目录名称
    @State private var newDirName = ""
    
    /// 新建目录的父ID
    @State private var createDirParentId: Int64 = -1
    
    /// 是否正在创建目录
    @State private var isCreatingDirectory = false
    
    // MARK: - Rename & Delete Directory State
    
    /// 是否显示重命名弹窗
    @State private var showingRenameDialog = false
    @State private var renameTargetId: Int64?
    @State private var renameValue = ""
    @State private var isRenaming = false
    
    /// 是否显示删除确认弹窗
    @State private var showingDeleteAlert = false
    @State private var deleteTargetId: Int64?
    @State private var deleteTargetName = ""
    @State private var isDeleting = false

    /// 批量上传选择器状态
    @State private var showingBatchUpload = false

    /// 是否开启自动排序
    @State private var isAutoSortEnabled = true

    /// 主题模式状态 (持久化)
    @AppStorage("isDarkMode") private var isDarkMode = true
    
    // MARK: - Detail View State
    @State private var selectedFileId: Int64?
    @State private var fileDetail: FileDto?
    @State private var isLoadingDetail = false
    
    // MARK: - Cloud Storage UI Innovation & Theme
    /// 视图模式: 0 = 列表, 1 = 网格 (Cloud Hub Grid)
    @State private var storageViewMode: Int = 1 
    /// 网格项悬停状态，Key 为文件 ID
    @State private var gridHoverStates: [Int64: Bool] = [:]
    /// 是否开启网格背景网格动画
    @State private var isMeshAnimating = true
    
    // MARK: - New Friend State
    @State public var showingNewFriendView = false
    @State private var newFriendBadgeCount = 3 // Mock count

    // MARK: - Body
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 顶部工具栏
                topToolbar
                
                Divider()
                
                // TabView 内容区域
                TabView(selection: $selectedTab) {
                    // 第一个标签页：好友列表与聊天
                    FriendChatSplitView()
                        .tabItem {
                            Label("会话", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                        .tag(0)
                    
                    // 第二个标签页：网盘存储
                    storageView
                        .tabItem {
                            Label("云盘", systemImage: "externaldrive.fill")
                        }
                        .tag(1)
                }
            }
            .disabled(showingCreateDirDialog || showingRenameDialog) // 弹窗时禁用主界面交互
            
            // 新建目录弹窗
            if showingCreateDirDialog {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {}
                
                createDirectoryDialog
            }
            
            // 重命名目录弹窗
            if showingRenameDialog {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {}
                
                renameDirectoryUiDialog
            }
        }
        .onAppear {
            startTimer()
            loadServerAddress()
            // generateFakeData() // Removed demo data generation
            // 初始化目录服务
            directoryService = DirectoryService(socketManager: socketManager)
            
            // 不在登录时恢复或启动任何任务，完全移除自动恢复逻辑
            // 等待用户切换到网盘标签时再手动处理
            // directoryService?.resumePendingTasks()
            
            // 不在登录时立即恢复任务，等待用户切换到网盘存储标签时再恢复
            // 这样可以避免在登录界面就建立大量连接，提升用户体验
            // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            //     print("🔄 Syncing restored tasks to UI...")
            //     loadRestoredTasks()
            // }
        }
        .onChange(of: selectedTab) { newTab in
            // 当切换到网盘存储标签页时，恢复传输任务和加载目录
            if newTab == 1 {
                // 只在第一次切换到网盘标签时恢复任务
                if transferList.isEmpty {
                    loadRestoredTasks()
                }
                
                // 加载目录树（如果还未加载）
                if directoryTree.isEmpty {
                    DispatchQueue.main.async {
                        Task {
                            await loadDirectoryFromServer()
                        }
                    }
                }
                // 刷新文件列表
                Task { loadCurrentFiles() }
            }
        }
        // 监听目录选中变化，加载对应文件
        .onChange(of: selectedDirectoryId) { newId in
            if let id = newId {
                printNodeInfo(id: id)
                // 重置搜索和页码
                self.searchKeyword = ""
                self.currentPage = 1
                loadCurrentFiles()
            }
        }
        // 监听来自桌面通知的自动跳转事件
        .onReceive(NotificationCenter.default.publisher(for: .switchToChat)) { notification in
            if let userInfo = notification.userInfo, let senderId = userInfo["senderId"] as? Int64 {
                print("🔄 接收到跳转会话事件，目标好友ID: \(senderId)")
                // 1. 切换到“会话” Tab页
                self.selectedTab = 0
                // 2. 选中对应的好友聊天面板
                self.socketManager.activeChatFriendId = senderId
            }
        }
        // 监听传输任务更新
        .onReceive(TransferTaskManager.shared.$taskUpdates) { updates in
            var needReload = false
            
            for (id, info) in updates {
                if let index = self.transferList.firstIndex(where: { $0.id.uuidString == id }) {
                    let oldStatus = self.transferList[index].status
                    // 更新状态
                    self.transferList[index].status = info.0
                    // 更新进度
                    self.transferList[index].progress = info.1
                    // 更新速度
                    self.transferList[index].speed = info.2
                    
                    // 如果开启了自动排序且状态变为已完成，触发排序
                    if self.isAutoSortEnabled && info.0 == "已完成" && oldStatus != "已完成" {
                        DispatchQueue.main.async {
                            self.sortTransferList()
                        }
                    }
                } else {
                    // 发现未知任务ID (可能是恢复的任务)，标记需要重载
                    needReload = true
                }
            }
            
            if needReload {
                // 有新任务，加载它们
                self.loadRestoredTasks()
            }
        }
        .onDisappear {
            stopTimer()
        }
        .alert("提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        // 应用主题设置
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }


    
    // MARK: - Top Toolbar (顶部工具栏)
    
    private var topToolbar: some View {
        HStack(spacing: 16) {
            // 服务地址 (只读 + 状态灯)
            HStack(spacing: 6) {
                Label("服务地址:", systemImage: "server.rack")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                
                Text(serverAddress)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                
                // 连接状态指示灯
                Circle()
                    .fill(statusColor(socketManager.connectionState.color))
                    .frame(width: 8, height: 8)
                    .help(socketManager.connectionState.description)
            }
            .padding(4)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            
            // 主题切换按钮
            Button(action: {
                withAnimation {
                    isDarkMode.toggle()
                }
            }) {
                Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(isDarkMode ? .yellow : .orange)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help(isDarkMode ? "切换到浅色模式" : "切换到深色模式")
            .padding(.horizontal, 4)
            
            Spacer()
            
            // 网速显示
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 10))
                    Text("上行: \(socketManager.uploadSpeedStr)")
                        .font(.system(size: 11, design: .monospaced))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 10))
                    Text("下行: \(socketManager.downloadSpeedStr)")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            // 分隔线
            Divider()
                .frame(height: 16)
            
            // 当前时间
            Label(currentTime, systemImage: "clock")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            // 退出按钮 (移到最右侧)
            Button(action: {
                handleLogout()
            }) {
                Image(systemName: "power.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("退出登录")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Sidebar (左侧边栏)
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("目录导航")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    Task { await loadDirectoryFromServer() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("刷新目录")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            // 树形列表
            List {
                RecursiveDirectoryView(
                    nodes: directoryTree,
                    selectedId: $selectedDirectoryId,
                    expandedIds: $expandedDirectoryIds,
                    onCreate: { item in
                        self.createDirParentId = item.id
                        self.newDirName = ""
                        self.showingCreateDirDialog = true
                    },
                    onMove: { _ in },
                    onRename: { item in 
                        self.renameTargetId = item.id
                        self.renameValue = item.fileName
                        self.showingRenameDialog = true
                    },
                    onDelete: { item in 
                        self.deleteTargetId = item.id
                        self.deleteTargetName = item.fileName
                        self.showingDeleteAlert = true
                    },
                    onUpload: { item in
                        handleSelectFiles(targetDirectory: item)
                    }
                )
                .listRowBackground(Color.clear)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }
    
    // MARK: - Main Content (主内容区域)
    

    
    private var mainContent: some View {
        VSplitView {
            // 上半部分：文件浏览区
            VStack(spacing: 0) {
                // 上传控制栏 (Floating style)
                uploadControlBar
                    .background(.ultraThinMaterial)
                
                Divider()
                
                // 文件列表 / 网格视图切换
                ZStack {
                    if storageViewMode == 0 {
                        fileListView
                            .transition(.opacity)
                    } else {
                        CloudGridView(
                            items: currentFiles,
                            selectedFiles: $selectedFiles,
                            selectedFileId: $selectedFileId,
                            onFileTapped: { file in
                                self.selectedFileId = file.id
                                loadFileDetail(fileId: file.id)
                            },
                            onFileDoubleTapped: { file in
                                if !file.isFile {
                                    handleEnterDirectory(file)
                                }
                            },
                            onAction: { file, action in
                                handleFileAction(file, action: action)
                            }
                        )
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                }
                .animation(.spring(), value: storageViewMode)
            }
            .frame(minWidth: 300, minHeight: 300)
            
            // 下半部分：文件传输区
            transferListView
                .frame(minHeight: 150)
                .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - Upload Control Bar (工具栏：批量操作)
    
    // MARK: - Upload Control Bar (工具栏：批量操作 + 搜索)
    
    private var uploadControlBar: some View {
        HStack(spacing: 12) {
            // 左侧：批量操作按钮
            Button(action: {
                handleBatchDelete()
            }) {
                Label("批量删除", systemImage: "trash")
                    .foregroundColor(selectedFiles.isEmpty ? .secondary : .red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedFiles.isEmpty)
            
            Button(action: {
                handleBatchDownload()
            }) {
                Label("批量下载", systemImage: "arrow.down.circle")
                    .foregroundColor(selectedFiles.isEmpty ? .secondary : .blue)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedFiles.isEmpty)


            
            // 下载目录配置 (移到工具栏)
            HStack(spacing: 8) {
                Text("下载至:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(downloadDirectoryManager.currentDownloadPath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150)
                    .help(downloadDirectoryManager.currentDownloadPath)
                
                Button("更改") {
                    downloadDirectoryManager.selectDirectory()
                }
                .font(.caption)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(4)
            
            Spacer()
            
            // 右侧：搜索区
            HStack(spacing: 8) {
                
                // 搜索输入框
                TextField("搜索文件名称", text: $searchKeyword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .controlSize(.small)
                
                // 搜索按钮
                Button(action: {
                    handleSearch()
                }) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - File List View (文件列表 - 浏览)
    
    private var fileListView: some View {
        VStack(spacing: 0) {
            // 表头 (现代优化版)
            HStack(spacing: 0) {
                Toggle("", isOn: Binding(
                    get: { isAllSelected },
                    set: { _ in toggleAllSelection() }
                ))
                .toggleStyle(.checkbox)
                .frame(width: 30, alignment: .center)
                .padding(.leading, 14)
                
                FileTableHeaderView(items: [
                    HeaderItem(title: "文件名称", icon: "doc", isSpacer: true),
                    HeaderItem(title: "文件大小", icon: "externaldrive", width: 80),
                    HeaderItem(title: "所属目录", icon: "folder", width: 100),
                    HeaderItem(title: "上传时间", icon: "clock", width: 140),
                    HeaderItem(title: "操作", width: 80, alignment: .center)
                ], leadingPadding: 8)
            }
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

            
            // 文件列表内容区域
            ScrollView {
                if fileList.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                        
                        Text("暂无文件")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(currentFiles) { file in
                            fileRow(file)
                            Divider()
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
            
            Divider()
            
            // 分页栏 (绑定在文件浏览区)
            paginationBar
        }
    }
    
    // MARK: - Pagination Bar (分页栏)
    
    private var paginationBar: some View {
        HStack(spacing: 16) {
            Text("共 \(totalCount) 个文件")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    if currentPage > 1 {
                        currentPage -= 1
                        loadCurrentFiles()
                    }
                }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(currentPage <= 1)
                
                Text("\(currentPage) / \(max(1, totalPages))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Button(action: {
                    if currentPage < totalPages {
                        currentPage += 1
                        loadCurrentFiles()
                    }
                }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(currentPage >= totalPages)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - File Row (文件行 - 浏览)
    
    private func fileRow(_ file: DirectoryItem) -> some View {
        FileListRowView(
            file: file,
            isSelected: selectedFileId == file.id,
            isChecked: selectedFiles.contains(file.id),
            onToggle: { toggleSelection(file.id) },
            onTap: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.selectedFileId = file.id
                    loadFileDetail(fileId: file.id)
                }
            },
            onDownload: { handleFileAction(file, action: 2) },
            onDelete: { handleFileAction(file, action: 1) }
        )
    }

    
    // MARK: - Transfer List View (文件传输区) 传输列表UI以及相关逻辑
    private var transferListView: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Label("传输列表", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .bold))
                
                Spacer()
                
                // 批量启动按钮，开启相关文件上传或是下载任务
                Button(action: {
                    handleBatchStart()
                }) {
                    Label("批量启动", systemImage: "play.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("启动列表中所有待处理任务")
                
                // 清除已完成按钮
                Button(action: {
                    // 1. 调用管理器清除 (内存 + 数据库)
                    transferManager.clearCompletedTasks()
                    
                    // 2. 从UI列表移除
                    let beforeCount = transferList.count
                    transferList.removeAll { $0.status == "已完成" || $0.status == "Completed" }
                    let removedCount = beforeCount - transferList.count
                    
                    print("✅ [UI] 已移除 \(removedCount) 个已完成任务")
                    
                    // 3. 重新排序
                    if isAutoSortEnabled {
                        sortTransferList()
                    }
                }) {
                    Label("清除已完成", systemImage: "trash.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("清除所有已完成的任务记录")
                
                // 自动排序开关
                Toggle("自动排序", isOn: $isAutoSortEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("开启后，进行中的任务将自动排在前面")
                    .onChange(of: isAutoSortEnabled) { enabled in
                        if enabled { sortTransferList() }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 表头 (现代优化版)
            FileTableHeaderView(items: [
                HeaderItem(title: "文件名称", icon: "doc", isSpacer: true),
                HeaderItem(title: "文件大小", icon: "externaldrive", width: 80),
                HeaderItem(title: "所属目录", icon: "folder", width: 100),
                HeaderItem(title: "传输类型", icon: "arrow.up.arrow.down", width: 100),
                HeaderItem(title: "状态", icon: "waveform.path.ecg", width: 80),
                HeaderItem(title: "传输进度", icon: "timer", width: 200),
                HeaderItem(title: "操作", width: 80, alignment: .center)
            ], leadingPadding: 0)

            
            // 列表内容
            ScrollView {
                if transferList.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.up.arrow.down.square")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                        
                        Text("无传输任务")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(transferList) { item in
                            transferRow(item)
                            Divider()
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
        }
    }
    // 文件传输列表一行记录的状态
    private func transferRow(_ item: TransferItem) -> some View {
        TransferListRowView(
            item: item,
            onStart:  { handleTransferAction(id: item.id, action: "start") },
            onPause:  { handleTransferAction(id: item.id, action: "pause") },
            onCancel: { handleTransferAction(id: item.id, action: "cancel") }
        )
    }

    
    private func statusColorForTransfer(_ status: String) -> Color {
        switch status {
        case "已完成": return .green
        case "上传中": return .blue
        case "下载中": return .green
        case "等待上传": return .gray
        case "等待下载": return .gray
        case "失败": return .red
        case "暂停", "已暂停": return .orange
        default: return .primary
        }
    }
    

    
    // MARK: - Helper Methods
    
    private func startTimer() {
        updateTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTime()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        currentTime = formatter.string(from: Date())
    }
    
    private func statusColor(_ colorName: String) -> Color {
        switch colorName {
        case "green": return .green
        case "blue": return .blue
        case "red": return .red
        case "orange": return .orange
        default: return .gray
        }
    }
    
    private func loadServerAddress() {
        let (host, port) = socketManager.getCurrentServer()
        serverAddress = "\(host):\(port)"
    }
    
    private func toggleSelection(_ id: Int64) {
        if selectedFiles.contains(id) {
            selectedFiles.remove(id)
        } else {
            selectedFiles.insert(id)
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleLogout() {
        print("退出登录")
        isLoggedIn = false
    }
    
    private func handleDirectory() {
        print("打开目录")
        // TODO: 实现目录选择
    }
    
    private func handleEnterDirectory(_ directory: DirectoryItem) {
        self.selectedDirectoryId = directory.id
        self.expandedDirectoryIds.insert(directory.id)
        addLog("进入目录: \(directory.fileName)")
    }
    
    private func handleRefresh() {
        print("刷新文件列表")
        addLog("刷新文件列表...")
        Task {
            // 重置加载状态以强制刷新
            isLoadingDirectory = false
            await loadDirectoryFromServer()
        }
    }
    
    private func selectDownloadPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                downloadPath = url.path
                addLog("下载路径已设置: \(downloadPath)")
            }
        }
    }
    
    private func handleStartUpload() {
        // Not used, using handleSelectFiles via UI context
    }
    
    private func handleSelectFiles(targetDirectory: DirectoryItem? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "确定选择"
        
        if let target = targetDirectory {
            panel.message = "选择文件上传到目录: \(target.fileName)"
        }
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            
            // Generate transfer items from selected files
            var newItems: [TransferItem] = []
            for url in urls {
                // Get file attributes
                let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = Int64(resources?.fileSize ?? 0)
                let name = url.lastPathComponent
                
                // Determine target directory name
                let targetName = targetDirectory?.fileName ?? "根目录"
                
                let item = TransferItem(
                    name: name,
                    size: fileSize,
                    directoryName: targetName,
                    fileUrl: url, // 保存 URL
                    targetDirId: targetDirectory?.id ?? 0,
                    taskType: .upload, // Set as Upload
                    status: "等待上传",
                    progress: 0.0,
                    speed: "-"
                )
                newItems.append(item)
            }
            
            // Add to transfer list (UI update)
            self.transferList.append(contentsOf: newItems)
            
            let dirInfo = targetDirectory != nil ? " -> [\(targetDirectory!.fileName)]" : ""
            addLog("用户选择了 \(urls.count) 个文件\(dirInfo)，已添加到传输列表")
        }
    }
    
    private func handleVoiceUpload() {
        print("语音上传")
        addLog("语音上传功能暂未实现")
        // TODO: 实现语音上传
    }
    
    private func handleFileAction(_ file: DirectoryItem, action: Int) {
        if action == 1 {
            // 删除操作
            Task {
                do {
                    addLog("🗑️ 正在删除文件: \(file.fileName)")
                    try await directoryService?.deleteFile(fileId: file.id)
                    
                    await MainActor.run {
                        addLog("✅ 文件删除成功: \(file.fileName)")
                        loadCurrentFiles() // 刷新列表
                    }
                } catch {
                    await MainActor.run {
                        addLog("❌ 文件删除失败: \(error.localizedDescription)")
                        alertMessage = "删除失败: \(error.localizedDescription)"
                        showingAlert = true
                    }
                }
            }
        } else if action == 2 {
            // 下载操作
            print("📥 准备下载文件: \(file.fileName)")
            // 修正属性访问: isFolder -> !isFile
            if !file.isFile {
                addLog("⚠️ 暂不支持文件夹下载")
            } else {
                submitDownloadTask(for: file)
            }
        }
    }
    
    // MARK: - Batch Operations
    
    /// 当前页显示的文件列表 (经过搜索过滤)
    private var currentFiles: [DirectoryItem] {
        // 由于采用了服务端分页，fileList 已经是当前页的数据，且已经经过了关键字过滤
        return fileList
    }
    
    private func flattenDirectories(nodes: [DirectoryItem]) -> [DirectoryItem] {
        var result: [DirectoryItem] = []
        for node in nodes {
            result.append(node)
            if let children = node.childFileList {
                result.append(contentsOf: flattenDirectories(nodes: children))
            }
        }
        return result
    }
    
    private func findDirectoryName(id: Int64, nodes: [DirectoryItem]?) -> String? {
        guard let nodes = nodes else { return nil }
        for node in nodes {
            if node.id == id { return node.fileName }
            if let found = findDirectoryName(id: id, nodes: node.childFileList) {
                return found
            }
        }
        return nil
    }
    
    private var isAllSelected: Bool {
        !currentFiles.isEmpty && currentFiles.allSatisfy { selectedFiles.contains($0.id) }
    }
    
    private func toggleAllSelection() {
        if isAllSelected {
            // 取消当前页的全选
            currentFiles.forEach { selectedFiles.remove($0.id) }
        } else {
            // 全选当前页
            currentFiles.forEach { selectedFiles.insert($0.id) }
        }
    }
    
    // 批量循环下载
    private func handleBatchDelete() {
        // 1. 如果没有选中的文件，直接返回，不做任何事情
        if selectedFiles.isEmpty {
            return
        }
        
        // 获取实际的对象列表
        let filesToDelete = fileList.filter { selectedFiles.contains($0.id) }
        let count = filesToDelete.count
        if count == 0 { return }
        
        let service = directoryService
        
        Task {
            await MainActor.run {
                addLog("🗑️ 开始批量删除 \(count) 个文件...")
            }
            
            var successCount = 0
            var failCount = 0
            
            // 2. 循环单个删除
            for file in filesToDelete {
                do {
                    // 调用单个文件删除接口 (Frame Type 0x41)
                    try await service?.deleteFile(fileId: file.id)
                    successCount += 1
                } catch {
                    failCount += 1
                    let errorMsg = error.localizedDescription
                    await MainActor.run {
                        addLog("❌ 删除失败 [\(file.fileName)]: \(errorMsg)")
                    }
                }
            }
            
            // 3. 完成后更新 UI
            await MainActor.run {
                addLog("✅ 批量删除结束: 成功 \(successCount), 失败 \(failCount)")
                
                // 清空选中状态
                selectedFiles.removeAll()
                
                // 刷新列表
                loadCurrentFiles()
                
                // 提示结果
                //alertMessage = "批量删除完成\n成功: \(successCount) 个\n失败: \(failCount) 个"
                //showingAlert = true
            }
        }
    }
    
    // 批量循环下载
    private func handleBatchDownload() {
        guard !selectedFiles.isEmpty else { return }
        
        var count = 0
        for id in selectedFiles {
            // 优先在当前文件列表中查找 (最常用场景)
            if let item = currentFiles.first(where: { $0.id == id }) {
                if !item.isFile {
                    addLog("⚠️ 暂不支持文件夹下载: \(item.fileName)")
                    continue
                }
                submitDownloadTask(for: item)
                count += 1
            } 
            // 如果没找到，再尝试在目录树中递归查找 (防御性)
            else if let item = findDirectoryItem(id: id, nodes: directoryTree) {
                if !item.isFile {
                    addLog("⚠️ 暂不支持文件夹下载: \(item.fileName)")
                    continue
                }
                submitDownloadTask(for: item)
                count += 1
            } else {
                print("❌ 未在当前列表或目录树中找到文件 ID: \(id)")
            }
        }
        
        if count > 0 {
            // 批量添加完成后，取消选择
            selectedFiles.removeAll()
            addLog("✅ 批量添加了 \(count) 个下载任务")
        }
    }
    
    /// 提交单个下载任务
    private func submitDownloadTask(for item: DirectoryItem) {
        let downloadDir = downloadDirectoryManager.getDownloadDirectory()
        try? FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true, attributes: nil)
        
        // 🔹 使用唯一路径生成逻辑 (处理重名)
        let targetUrl = getUniqueFileURL(in: downloadDir, fileName: item.fileName)
        let finalFileName = targetUrl.lastPathComponent
        
        // 获取当前用户ID
        let currentUserId = Int64(authService.currentUser?.id ?? 0)
        let currentUserName = String(authService.currentUser?.username ?? "default")
        
        let task = StorageTransferTask(
            id: UUID(), // Explicitly provide ID
            taskType: .download,
            name: finalFileName, // 🔹 使用最终文件名 (包含序号)
            fileUrl: targetUrl,
            targetDirId: 0,
            userId: currentUserId,
            userName: currentUserName,
            fileSize: item.fileSize ?? 0, // 修正属性访问: size -> fileSize
            directoryName: "",
            remoteFileId: item.id,
            progress: 0.0,
            status: "等待下载"
        )
        
        transferManager.submit(task: task)
        addLog("📥 已添加下载任务: \(finalFileName)")
    }
    
    /// 获取唯一的文件保存路径 (处理重名自动重命名)
    /// - Parameters:
    ///   - directory: 目标目录
    ///   - fileName: 原始文件名
    /// - Returns: 不冲突的文件路径
    private func getUniqueFileURL(in directory: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        var destinationURL = directory.appendingPathComponent(fileName)
        
        // 如果文件不存在，直接返回
        if !fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        
        // 分离文件名和扩展名
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        let extensionString = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        
        var counter = 1
        
        // 循环查找可用文件名
        while true {
            let newName = "\(nameWithoutExtension)（\(counter)）\(extensionString)" // 使用中文括号
            destinationURL = directory.appendingPathComponent(newName)
            
            if !fileManager.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
            
            counter += 1
        }
    }
    
    private func generateFakeData() {
        // Disabled demo data generation
    }
    
    /// 从服务器加载目录树
    @MainActor
    private func loadDirectoryFromServer() async {
        guard let service = directoryService else {
            print("⚠️ DirectoryService 未初始化")
            return
        }
        
        guard !isLoadingDirectory else {
            print("⚠️ 目录正在加载中，跳过重复请求")
            return
        }
        
        isLoadingDirectory = true
        addLog("开始加载目录树...")
        
        do {
            let items = try await service.loadDirectoryTree()
            
            // 在主线程更新 UI
            await MainActor.run {
                self.directoryTree = items
                self.isLoadingDirectory = false
                self.directoryTree = items
                self.isLoadingDirectory = false
                
                // 仅在首次加载（无展开项）时执行默认展开，否则保留用户当前的展开状态
                if self.expandedDirectoryIds.isEmpty {
                   self.expandDefaultLevels(items: items) // 默认展开两层
                }
                addLog("目录树加载成功，共 \(items.count) 个顶级项")
            }
        } catch {
            // 在主线程更新 UI
            await MainActor.run {
                self.isLoadingDirectory = false
                addLog("目录树加载失败: \(error.localizedDescription)")
                print("❌ 加载目录失败: \(error)")
            }
        }
    }
    
    /// 默认展开顶层和下一层 (共两层)
    private func expandDefaultLevels(items: [DirectoryItem]) {
        var ids: Set<Int64> = []
        for root in items {
            ids.insert(root.id) // 展开顶层
            if let children = root.childFileList {
                for child in children {
                    // 如果第二层还有子节点，则展开第二层 (即展示第三层)
                    // 用户要求：展示两个层级的目录数据。
                    // 展开顶层 -> 可见第二层。
                    // 展开第二层 -> 可见第三层。
                    // 这里的理解是：默认看到 Root 和 Root 的 children。
                    // 只要展开 Root 就可以看到 Root 的 children。
                    // 用户说：默认展开最顶层和下一层级。
                    // 意思是：Root 展开，Child 展开。
                    if let grandChildren = child.childFileList, !grandChildren.isEmpty {
                        ids.insert(child.id)
                    }
                }
            }
        }
        self.expandedDirectoryIds = ids
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] \(message)")
    }
    
    // MARK: - Tab Views (标签页视图)
    
    /// 好友列表视图
    private var friendsListView: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索好友", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                
                Button("添加好友") {
                    print("添加好友")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 好友列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 示例好友项
                    ForEach(0..<5) { index in
                        friendRow(name: "好友 \(index + 1)", status: "在线")
                        Divider()
                    }
                }
            }
        }
    }
    
    /// 好友行视图
    private func friendRow(name: String, status: String) -> some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
            .fill(Color.blue.opacity(0.3))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "person.fill")
                .foregroundColor(.blue)
            )
            
            // 好友信息
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(status == "在线" ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 操作按钮
            Button(action: {
                print("聊天: \(name)")
            }) {
                Image(systemName: "message.fill")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .onTapGesture {
            print("选中好友: \(name)")
        }
    }
    
    /// 网盘存储视图
    private var storageView: some View {
        ZStack {
            // New Dynamic Background
            MeshGradientBackground()
            
            GeometryReader { geometry in
                HSplitView {
                    // 左侧边栏 (18%) - Added glassmorphism effect
                    sidebar
                        .frame(minWidth: 150, maxWidth: .infinity)
                        .frame(width: geometry.size.width * 0.18)
                        .background(.ultraThinMaterial)
                    
                    // 右侧主内容 (52%)
                    mainContent
                        .frame(minWidth: 300, maxWidth: .infinity)
                    
                    // 详情侧边栏 (30%) - Added glassmorphism effect
                    detailSidebar
                        .frame(minWidth: 200, maxWidth: .infinity)
                        .frame(width: geometry.size.width * 0.3)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }
    
    // MARK: - File Detail Sidebar
    
    private var detailSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("文件详情")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                if isLoadingDetail {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(16)
            
            Divider().opacity(0.1)
            
            if let detail = fileDetail {
                ScrollView {
                    VStack(alignment: .center, spacing: 24) {
                        // Large File Icon
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color.accentColor.opacity(0.05))
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: detail.iconName)
                                    .font(.system(size: 64))
                                    .foregroundColor(.accentColor)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            
                            Text(detail.fileName)
                                .font(.system(size: 18, weight: .bold))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        .padding(.top, 24)
                        
                        // Properties Group
                        VStack(alignment: .leading, spacing: 16) {
                            DetailRow(label: "文件大小", value: detail.sizeString)
                            DetailRow(label: "文件类型", value: detail.fileType.uppercased())
                            DetailRow(label: "上传时间", value: detail.uploadTime)
                            DetailRow(label: "存储目录", value: detail.directoryName)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(16)
                        
                        Spacer(minLength: 20)
                        
                        // Actions
                        VStack(spacing: 12) {
                            Button(action: {
                                if let item = directoryTree.first(where: { $0.id == detail.id }) ?? findDirectoryItem(id: detail.id, nodes: directoryTree) {
                                     submitDownloadTask(for: item)
                                } else {
                                     submitDownloadTask(for: detail.toDirectoryItem())
                                }
                            }) {
                                Label("立即下载", systemImage: "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
                            Button(action: {
                                handleFileAction(detail.toDirectoryItem(), action: 1)
                            }) {
                                Label("删除文件", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .foregroundColor(.red)
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("选择文件查看详情")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // Helper View for Detail
    private struct DetailRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }

    
    // MARK: - Helper Views
    
    private func statusView(status: String) -> some View {
        HStack(spacing: 6) {
            Group {
                switch status {
                case "已完成":
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                case "失败":
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                case "上传中", "下载中":
                    Image(systemName: "arrow.up.circle.fill").foregroundColor(.blue)
                case "等待中":
                    Image(systemName: "clock.fill").foregroundColor(.secondary)
                default:
                    Image(systemName: "circle").foregroundColor(.secondary)
                }
            }
            .font(.system(size: 11))
            
            Text(status)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor(for: status).opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(statusColor(for: status).opacity(0.24), lineWidth: 0.5)
        )
    }
    
    private func statusColor(for status: String) -> Color {
        switch status {
        case "已完成": return .green
        case "失败": return .red
        case "上传中", "下载中": return .blue
        case "等待中": return .secondary
        default: return .secondary
        }
    }
    
    // MARK: - Create Directory Dialog
    
    private var createDirectoryDialog: some View {
        VStack(spacing: 20) {
            Text("新建目录")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("目录名称:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("请输入目录名称 (最多10字)", text: $newDirName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: newDirName) { newValue in
                        if newValue.count > 10 {
                            newDirName = String(newValue.prefix(10))
                        }
                    }
            }
            
            HStack(spacing: 20) {
                Button("取消") {
                    showingCreateDirDialog = false
                    newDirName = ""
                }
                .keyboardShortcut(.cancelAction)
                
                Button("保存") {
                    handleCreateDirectory()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newDirName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingDirectory)
                .keyboardShortcut(.defaultAction)
            }
            
            if isCreatingDirectory {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
    
    private func handleCreateDirectory() {
        guard let service = directoryService else { return }
        let name = newDirName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return }
        
        isCreatingDirectory = true
        
        Task {
            do {
                try await service.createDirectory(pId: createDirParentId, name: name)
                
                await MainActor.run {
                    addLog("目录 [\(name)] 创建成功")
                    isCreatingDirectory = false
                    showingCreateDirDialog = false
                    
                    // 自动刷新目录
                    addLog("自动刷新目录...")
                    Task {
                        await loadDirectoryFromServer()
                    }
                }
            } catch {
                await MainActor.run {
                    addLog("目录创建失败: \(error.localizedDescription)")
                    isCreatingDirectory = false
                    // 失败时不关闭弹窗，允许重试
                    print("❌ 创建目录失败: \(error)")
                    
                    showingAlert = true
                    if let dirError = error as? DirectoryError, case .serverError(_, let msg) = dirError {
                         alertMessage = msg
                    } else {
                         alertMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Rename Directory Dialog
    
    private var renameDirectoryUiDialog: some View {
        VStack(spacing: 20) {
            Text("重命名目录")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("目录名称:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("请输入新名称", text: $renameValue)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack(spacing: 20) {
                Button("取消") {
                    showingRenameDialog = false
                    renameValue = ""
                    renameTargetId = nil
                }
                .keyboardShortcut(.cancelAction)
                
                Button("保存") {
                    handleRenameDirectory()
                }
                .buttonStyle(.borderedProminent)
                .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRenaming)
                .keyboardShortcut(.defaultAction)
            }
            
            if isRenaming {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
    
    private func handleRenameDirectory() {
        guard let service = directoryService, let id = renameTargetId else { return }
        let name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return }
        
        isRenaming = true
        
        Task {
            do {
                try await service.renameDirectory(id: id, name: name)
                
                await MainActor.run {
                    addLog("目录 [\(id)] 重命名为 [\(name)] 成功")
                    isRenaming = false
                    showingRenameDialog = false
                    
                    // 自动刷新目录
                    addLog("自动刷新目录...")
                    Task {
                        await loadDirectoryFromServer()
                    }
                }
            } catch {
                await MainActor.run {
                    addLog("重命名失败: \(error.localizedDescription)")
                    isRenaming = false
                    showingAlert = true
                    
                    // 提取更简洁的错误信息
                    if let dirError = error as? DirectoryError, case .serverError(_, let msg) = dirError {
                         alertMessage = msg
                    } else {
                         alertMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Delete Directory
    
    private func handleDeleteDirectory() {
        guard let service = directoryService, let id = deleteTargetId else { return }
        
        isDeleting = true
        
        Task {
            do {
                try await service.deleteDirectory(id: id)
                
                await MainActor.run {
                    addLog("目录 [\(id)] 删除成功")
                    isDeleting = false
                    
                    // 自动刷新目录
                    addLog("自动刷新目录...")
                    Task {
                        await loadDirectoryFromServer()
                    }
                }
            } catch {
                await MainActor.run {
                    addLog("删除失败: \(error.localizedDescription)")
                    isDeleting = false
                    showingAlert = true
                    
                    // 提取更简洁的错误信息
                    if let dirError = error as? DirectoryError, case .serverError(_, let msg) = dirError {
                         alertMessage = msg
                    } else {
                         alertMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Batch Upload Logic  批量启动传输列表中的任务
    
    // MARK: - Batch Logic
    
    private func handleBatchStart() {
        // 1. 检查列表是否为空
        if transferList.isEmpty {
            self.alertMessage = "请选择要上传或是下载的文件"
            self.showingAlert = true
            return
        }
        
        // 打印 transferList 数据用于调试
        print("📋 [DEBUG] handleBatchStart - transferList count: \(transferList.count)")
        for item in transferList {
            print("   👉 Task: \(item.name), ID: \(item.id), Status: \(item.status), URL: \(String(describing: item.fileUrl))")
        }
        
        // 2. 遍历列表，提交待处理任务
        var count = 0
        let currentUserId = Int64(authService.currentUser?.id ?? 0)
        let currentUserName = String(authService.currentUser?.username ?? "default")
        
        for item in transferList {
            // 只处理非“上传中”和非“已完成”的任务
            if item.status != "上传中" && item.status != "下载中" && item.status != "已完成" {
                
                // 确保有文件路径
                if let fileUrl = item.fileUrl {
                    let task = StorageTransferTask(
                        id: item.id, // 使用 TransferItem 现有的 ID
                        taskType: .upload,
                        name: item.name,
                        fileUrl: fileUrl,
                        targetDirId: item.targetDirId,
                        userId: currentUserId,
                        userName: currentUserName,
                        fileSize: item.size,
                        directoryName: item.directoryName,
                        progress: 0.0
                    )
                    
                    // 提交任务 (submit 会自动处理：存在则resume，不存在则add)
                    transferManager.submit(task: task)
                    count += 1
                }
            }
        }
        
        if count > 0 {
            addLog("批量提交了 \(count) 个任务到传输队列")
        } else {
            addLog("没有需要启动的任务")
        }
    }
    
    // MARK: - Transfer Logic
    
    private func handleTransferAction(id: UUID, action: String) {
        guard let index = transferList.firstIndex(where: { $0.id == id }) else { return }
        let item = transferList[index]
        
        switch action {
        case "start":
            // 检查当前状态，决定是 submit 还是 resume
            if item.status == "暂停" || item.status == "已暂停" || item.status == "失败" {
                addLog("▶️ 恢复任务: \(item.name)")
                
                // 立即更新UI状态为"上传中"（如果是上传任务）
                if item.taskType == .upload {
                    transferList[index].status = "上传中"
                } else {
                    transferList[index].status = "下载中"
                }
                
                // 后台执行恢复操作
                DispatchQueue.global(qos: .userInitiated).async {
                    transferManager.resume(id: id)
                }
            } else {
                addLog("🚀 提交任务至队列: \(item.name)")
                
                // 根据任务类型设置初始状态
                if item.taskType == .upload {
                    transferList[index].status = "等待上传"
                } else {
                    transferList[index].status = "等待下载"
                }
                
                guard let fileUrl = item.fileUrl else {
                    addLog("❌ 文件路径丢失: \(item.name)")
                    transferList[index].status = "失败"
                    return
                }
                
                // 获取当前用户ID (从全局认证服务)
                let currentUserId = Int64(authService.currentUser?.id ?? 0)
                let currentUserName = String(authService.currentUser?.username ?? "default")
                
                
                // 构建 TransferTaskd
                // 构建 TransferTask
                let task = StorageTransferTask(
                    id: item.id,
                    taskType: .upload,
                    name: item.name,
                    fileUrl: fileUrl,
                    targetDirId: item.targetDirId,
                    userId: currentUserId,
                    userName: currentUserName,
                    fileSize: item.size,
                    directoryName: item.directoryName,
                    progress: 0.0
                )
                
                transferManager.submit(task: task)
            }
            
        case "pause":
            addLog("⏸️ 暂停任务: \(item.name)")
            
            // 立即更新UI状态为"已暂停"
            transferList[index].status = "已暂停"
            transferList[index].speed = ""
            
            // 在后台线程执行暂停操作，避免阻塞主线程UI
            DispatchQueue.global(qos: .userInitiated).async {
                transferManager.pause(id: id)
            }
            
        case "cancel":
            addLog("❌ 取消任务: \(item.name)")
            
            // 🔹 从管理器移除 (会自动删除数据库)
            transferManager.cancel(id: id)
            
            // 🔹 从UI列表移除
            transferList.remove(at: index)
            
            // 🔹 如果是已完成任务,额外记录日志
            if item.status == "已完成" {
                print("🗑️ 已删除已完成任务: \(item.name) (ID: \(id.uuidString))")
            }
            
        default:
            break
        }
    }
    
    private func printNodeInfo(id: Int64) {
        if let item = findDirectoryItem(id: id, nodes: directoryTree) {
            print("📂 [选中节点详情] --------------------------------")
            print("   ID       : \(item.id)")
            print("   名称     : \(item.fileName)")
            print("   子节点数 : \(item.childFileList?.count ?? 0)")
            print("   完整信息 : \(item.debugDescription)")
            print("------------------------------------------------")
        }
    }
    
    private func findDirectoryItem(id: Int64, nodes: [DirectoryItem]?) -> DirectoryItem? {
        guard let nodes = nodes else { return nil }
        for node in nodes {
            if node.id == id {
                return node
            }
            if let found = findDirectoryItem(id: id, nodes: node.childFileList) {
                return found
            }
        }
        return nil
    }
    
    // MARK: - File List Pagination Helpers
    
    /// 加载当前条件下的文件列表
    private func loadCurrentFiles() {
        Task {
            guard let service = directoryService else { return }
            
            // 确定查询参数
            // 如果选中了目录，使用 selectedDirectoryId，否则默认为 0 (根目录)
            let dirId = selectedDirectoryId ?? 0
            
            let currentKeyword = searchKeyword
            
            do {
                let result = try await service.fetchFileList(
                    dirId: dirId,
                    fileName: currentKeyword,
                    pageNum: currentPage,
                    pageSize: itemsPerPage
                )
                
                // 更新 UI 状态
                await MainActor.run {
                    self.fileList = result.recordList.map { $0.toDirectoryItem() }
                    self.totalPages = Int(result.totalPage)
                    self.totalCount = result.totalCount
                    // 如果当前页大于总页数（可能是删除后），且总页数不为0，重置为最后一页
                    if self.currentPage > self.totalPages && self.totalPages > 0 {
                        self.currentPage = self.totalPages
                        // 简单重置，不再递归调用，下次交互会正常
                    }
                }
            } catch {
                print("❌ 加载文件列表失败: \(error)")
                await MainActor.run {
                    // 发生错误时清空列表，避免误导用户
                    self.fileList = []
                    self.totalCount = 0
                    self.totalPages = 1
                    
                    self.alertMessage = "加载文件列表失败: \(error.localizedDescription)"
                    self.showingAlert = true
                }
            }
        }
    }
    
    private func handleSearch() {
        // 重置页码并加载
        self.currentPage = 1
        loadCurrentFiles()
    }
    
    // MARK: - Sorting Logic
    
    private func sortTransferList() {
        self.transferList.sort { (item1, item2) -> Bool in
            let score1 = statusScore(item1.status)
            let score2 = statusScore(item2.status)
            if score1 != score2 {
                return score1 > score2 // 分数高的排前面
            }
            return item1.name < item2.name // 同状态按名称排
        }
    }
    
    // MARK: - Recovery Logic
    
    // MARK: - Recovery Logic
    
    private func loadRestoredTasks() {
        let tasks = TransferTaskManager.shared.getAllTasks()
        if tasks.isEmpty { return }
        
        print("📥 从本地恢复 \(tasks.count) 个传输任务")
        
        for task in tasks {
            // Check if already exists in UI
            if !transferList.contains(where: { $0.id == task.id }) {
                // 所有恢复的任务都设置为"已暂停"状态，由用户手动决定是否启动
                let status = "已暂停"
                
                let newItem = TransferItem(
                    id: task.id,
                    name: task.name,
                    size: task.fileSize,
                    directoryName: task.directoryName,
                    fileUrl: task.fileUrl,
                    targetDirId: task.targetDirId,
                    taskType: task.taskType == .upload ? .upload : .download,
                    status: status,
                    progress: task.progress,
                    speed: ""
                )
                transferList.append(newItem)
                
                // 在 TransferTaskManager 中也更新为暂停状态
                TransferTaskManager.shared.taskUpdates[task.id.uuidString] = (status, task.progress, "")
            }
        }
        
        print("✅ 任务恢复完成，所有任务均为暂停状态，请手动启动需要的任务")
        
        // Trigger sort
        if isAutoSortEnabled {
            sortTransferList()
        }
    }
        
    private func statusScore(_ status: String) -> Int {
        switch status {
        case "上传中", "下载中": return 100
        case "等待上传", "等待下载": return 80
        case "暂停", "已暂停", "失败": return 60
        case "已完成": return 10
        default: return 0
        }
    }
    
    /// 加载文件详情
    private func loadFileDetail(fileId: Int64) {
        guard !isLoadingDetail else { return }
        
        isLoadingDetail = true
        // 先使用本地缓存的列表作为临时展示 (如果需要)
        // fileDetail = fileList.first { $0.id == fileId }?.toFileDto() 
        
        Task {
            do {
                // Determine which service to use
                // If directoryService is available, use it (it has fetchFileDetail)
                if let service = directoryService {
                    let detail = try await service.fetchFileDetail(fileId: fileId)
                    await MainActor.run {
                        self.fileDetail = detail
                        self.isLoadingDetail = false
                    }
                } else {
                     print("❌ directoryService is nil")
                     await MainActor.run { self.isLoadingDetail = false }
                }
            } catch {
                print("❌ 加载文件详情失败: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoadingDetail = false
                    // 可选: 显示错误提示
                    // alertMessage = "无法加载详情: \(error.localizedDescription)"
                    // showingAlert = true
                }
            }
        }
    }
}

// MARK: - Extensions

extension DirectoryItem {
    static func formatBytes(_ size: Int64?) -> String {
        guard let size = size else { return "-" }
        if size < 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        }
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var index = 0
        var value = Double(size)
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f %@", value, units[index])
    }
}

extension FileDto {
    // toDirectoryItem is already defined in Models/do/FileDto.swift
    
    /// 格式化大小
    var sizeString: String {
        return DirectoryItem.formatBytes(fileSize)
    }
    
    /// 格式化上传时间
    var uploadTime: String {
        guard let time = gmtCreated else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(time / 1000))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    /// 获取所属目录名称
    var directoryName: String {
        // 简化处理，如果有 filePath 则显示，否则显示 "-"
        return filePath.isEmpty ? "-" : filePath
    }
    
    /// 获取图标名称
    var iconName: String {
        let type = fileType.lowercased()
        switch type {
        case "jpg", "jpeg", "png", "gif", "bmp": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "aac": return "music.note"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "chart.bar.doc.horizontal"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "pdf": return "doc.text.fill"
        case "zip", "rar", "7z": return "doc.zipper"
        case "txt", "md", "json", "xml": return "doc.text"
        default: return "doc"
        }
    }
}

// MARK: - Transfer Item Model

struct TransferItem: Identifiable {
    let id: UUID
    
    init(id: UUID = UUID(), name: String, size: Int64, directoryName: String, fileUrl: URL?, targetDirId: Int64, taskType: TaskType, status: String, progress: Double, speed: String) {
        self.id = id
        self.name = name
        self.size = size
        self.directoryName = directoryName
        self.fileUrl = fileUrl
        self.targetDirId = targetDirId
        self.taskType = taskType
        self.status = status
        self.progress = progress
        self.speed = speed
    }
    let name: String
    let size: Int64
    let directoryName: String
    let fileUrl: URL? // 新增：保存文件路径用于上传
    let targetDirId: Int64 // 新增：目标目录ID
    enum TaskType: String {
        case upload = "上传"
        case download = "下载"
    }
    let taskType: TaskType // New field
    var status: String // 等待上传, 上传中, 已完成, 失败, 暂停
    var progress: Double // 0.0 - 1.0
    var speed: String
    
    var sizeString: String {
        if size < 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        }
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var index = 0
        var value = Double(size)
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f %@", value, units[index])
    }
    
    var progressPercent: String {
        String(format: "%.1f%%", progress * 100)
    }
}

// MARK: - Recursive Directory View Support



// MARK: - Directory Tree Selector (用于筛选的树形组件)

struct DirectoryTreeSelector: View {
    let nodes: [DirectoryItem]
    @Binding var selectedId: Int64?
    let onSelect: () -> Void
    @State private var collapsedIds: Set<Int64> = []
    var level: Int = 0
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(nodes) { node in
                // Node Row
                HStack(spacing: 4) {
                    // Indentation
                    if level > 0 {
                        Spacer()
                            .frame(width: CGFloat(level * 16))
                    }
                    
                    // Expand/Collapse Button
                    if let children = node.childFileList, !children.isEmpty {
                        Image(systemName: collapsedIds.contains(node.id) ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9))
                            .frame(width: 12, height: 12)
                            .onTapGesture {
                                toggleExpand(node.id)
                            }
                    } else {
                        Spacer().frame(width: 12)
                    }
                    
                    // Folder icon
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    
                    Text(node.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    // Checkmark
                    if selectedId == node.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                            .font(.system(size: 10))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selectedId == node.id ? Color.secondary.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedId = node.id
                    onSelect()
                }
                
                // Children (Show if NOT collapsed)
                if let children = node.childFileList, !collapsedIds.contains(node.id) {
                    DirectoryTreeSelector(
                        nodes: children,
                        selectedId: $selectedId,
                        onSelect: onSelect,
                        level: level + 1
                    )
                }
            }
        }
    }
    
    private func toggleExpand(_ id: Int64) {
        if collapsedIds.contains(id) {
            collapsedIds.remove(id)
        } else {
            collapsedIds.insert(id)
        }
    }
}

// MARK: - Friend List & Chat Module

// 1. Data Models (Mock)
struct Friend: Identifiable, Hashable {
    let id: Int64
    let friendshipId: Int64
    let name: String
    let status: String // "在线", "离线"
    let avatarColor: Color
    let avatarBase64: String?
    let serverUnreadCount: Int32?
    let serverLatestMsg: String?
}

struct ChatMessage: Identifiable, Equatable {
    var id: String {
        if let mid = messageId {
            return "msg-\(mid)"
        }
        return localId.uuidString
    }
    let localId = UUID()
    var messageId: Int32? // 服务端分配的实际ID
    let content: String
    let isMe: Bool // true = 我发的, false = 对方发的
    let timestamp: Date
    let type: String // "TEXT", "IMAGE", "FILE"
    var sendStatus: SendStatus
    
    var groupTime: String?
    var msgTimeStr: String?
    var avatar: String?
    
    enum SendStatus: Equatable {
        case sending
        case success
        case failed
    }
}


// 2. Chat Detail View (右侧聊天窗口)
private struct ChatDetailView: View {
    let friend: Friend
    @State private var messageText = ""
    @EnvironmentObject var socketManager: SocketManager
    @EnvironmentObject var authService: AuthenticationService
    
    // Pagination states
    @State private var currentOffset: Int32 = 0
    let pageSize: Int32 = 20
    @State private var hasMore: Bool = true
    @State private var isLoadingHistory: Bool = false
    @State private var topMessageIdBeforeLoad: String? = nil
    @State private var shouldScrollToBottom: Bool = false
    @State private var isInitialProcessing: Bool = true 
    
    // Emoji Picker State
    @State private var showEmojiPicker: Bool = false
    
    // Alias Update State
    @State private var showingAliasPopover: Bool = false
    @State private var newAliasInput: String = ""
    @State private var isUpdatingAlias: Bool = false
    
    // Nudge/Reaction States
    @State private var nudgeOffset: CGFloat = 0
    @State private var reactionOpacity: Double = 0
    @State private var reactionScale: CGFloat = 0.5
    
    var messages: [ChatMessage] {
        socketManager.chatHistory[friend.id] ?? []
    }
    
    var groupedMessages: [(String, [ChatMessage])] {
        var result: [(String, [ChatMessage])] = []
        for msg in messages {
            let group = msg.groupTime ?? "未知时间"
            if let last = result.last, last.0 == group {
                result[result.count - 1].1.append(msg)
            } else {
                result.append((group, [msg]))
            }
        }
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(friend.name)
                    .font(.system(size: 16, weight: .bold))
                
                if friend.status == "在线" {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
                
                Spacer()
                
                Menu {
                    Button("修改好友别名") {
                        newAliasInput = friend.name
                        showingAliasPopover = true
                    }
                    Button("更改聊天背景") {
                        // TODO: Implement background change
                    }
                    Button("清空聊天记录") {
                        // TODO: Implement clear history
                        socketManager.chatHistory[friend.id]?.removeAll()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.leading, 8)
                .popover(isPresented: $showingAliasPopover, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("修改好友备注")
                            .font(.headline)
                        
                        TextField("备注姓名", text: $newAliasInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        HStack {
                            Spacer()
                            Button("取消") {
                                showingAliasPopover = false
                            }
                            Button("确定") {
                                handleUpdateAlias()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isUpdatingAlias)
                        }
                    }
                    .padding()
                    .frame(width: 240)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Messages Area
            ScrollViewReader { proxy in
                ZStack {
                    // Mesh Gradient Placeholder Background
                    LinearGradient(colors: [.clear, .blue.opacity(0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .ignoresSafeArea()
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if isLoadingHistory {
                                ProgressView()
                                    .padding(.top, 8)
                            } else if !hasMore && messages.count > 0 {
                                Text("没有更多历史消息了")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                            } else {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        if !isLoadingHistory && hasMore && !shouldScrollToBottom && !isInitialProcessing {
                                            Task {
                                                try? await Task.sleep(nanoseconds: 300_000_000)
                                                if !isLoadingHistory && hasMore && !shouldScrollToBottom && !isInitialProcessing {
                                                    await loadMoreHistory()
                                                }
                                            }
                                        }
                                    }
                            }
                            
                            ForEach(groupedMessages, id: \.0) { groupInfo in
                                let (groupTime, msgs) = groupInfo
                                if !groupTime.isEmpty {
                                    Text(groupTime)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(8)
                                        .padding(.top, 8)
                                }
                                
                                ForEach(msgs) { msg in
                                    messageBubble(msg)
                                }
                            }
                            
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 30)
                                .id("BOTTOM_ANCHOR")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: messages.count) { newCount in
                        if newCount > 0 {
                            if let topId = topMessageIdBeforeLoad {
                                topMessageIdBeforeLoad = nil
                                DispatchQueue.main.async { proxy.scrollTo(topId, anchor: .top) }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onChange(of: shouldScrollToBottom) { act in
                        if act {
                            shouldScrollToBottom = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                            }
                        }
                    }
                    
                    // Floating Reaction Overlay
                    if reactionOpacity > 0 {
                        Text("❤️")
                            .font(.system(size: 60))
                            .scaleEffect(reactionScale)
                            .opacity(reactionOpacity)
                            .shadow(radius: 10)
                    }
                }
                .offset(x: nudgeOffset)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.8))
            
            Divider()
            
            // Input Area
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { showEmojiPicker.toggle() }
                    }) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 18))
                            .foregroundColor(showEmojiPicker ? .accentColor : .secondary)
                    }
                    Button(action: {}) { Image(systemName: "folder").font(.system(size: 18)) }
                    Button(action: {}) { Image(systemName: "scissors").font(.system(size: 18)) }
                    Button(action: {}) { Image(systemName: "mic").font(.system(size: 18)) }
                    Spacer()
                    Button(action: { sendNudge() }) { Image(systemName: "hand.tap").font(.system(size: 18)).help("抖一抖") }
                    Button(action: {}) { Image(systemName: "phone").font(.system(size: 18)) }
                    Button(action: {}) { Image(systemName: "video").font(.system(size: 18)) }
                }
                .foregroundColor(.secondary).buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
                
                if showEmojiPicker {
                    EmojiPickerPanel { emoji in
                        showEmojiPicker = false
                        shouldScrollToBottom = true
                        socketManager.sendChatMessage(receiverId: friend.id, content: emoji, msgType: "TEXT", avatar: authService.currentUser?.avatar)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                ZStack(alignment: .topLeading) {
                    if messageText.isEmpty {
                        Text("请输入消息...").foregroundColor(.secondary).padding(.leading, 8).padding(.top, 4).font(.system(size: 14)).allowsHitTesting(false)
                    }
                    MacResponsiveTextView(text: $messageText) { Task { await sendMessage() } }
                    .frame(minHeight: 36, maxHeight: 150)
                }
                .background(Color.clear).padding(.horizontal, 12).padding(.bottom, 16)
            }
            .background(Color(NSColor.textBackgroundColor)).frame(minHeight: 150)
        }
        .onAppear {
            isInitialProcessing = true
            Task {
                await loadInitialHistory()
                try? await Task.sleep(nanoseconds: 600_000_000)
                isInitialProcessing = false
            }
        }
    }
    
    private func sendNudge() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.2, blendDuration: 0)) { nudgeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.2, blendDuration: 0)) { nudgeOffset = -10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.2, blendDuration: 0)) { nudgeOffset = 0 }
            }
        }
        socketManager.sendChatMessage(receiverId: friend.id, content: "【抖了你一下】", msgType: "NUDGE", avatar: authService.currentUser?.avatar)
    }
    
    private func handleUpdateAlias() {
        let trimmedAlias = newAliasInput.trimmingCharacters(in: .whitespaces)
        guard !trimmedAlias.isEmpty else { return }
        isUpdatingAlias = true
        Task {
            do {
                _ = try await socketManager.updateFriendAlias(friendshipId: friend.friendshipId, newAlias: trimmedAlias)
                await MainActor.run { isUpdatingAlias = false; showingAliasPopover = false }
            } catch {
                await MainActor.run { isUpdatingAlias = false; print("❌ 修改备注失败: \(error.localizedDescription)") }
            }
        }
    }
    
    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.isMe {
                Spacer(minLength: 60)
                HStack(alignment: .bottom, spacing: 4) {
                    Text(msg.content)
                        .font(.system(size: 14)).padding(10)
                        .background(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .foregroundColor(.white).clipShape(TailChatBubbleShape(isMe: true)).textSelection(.enabled).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                renderAvatar(base64String: msg.avatar, fallbacName: "我", fallbackColor: .gray)
            } else {
                renderAvatar(base64String: msg.avatar ?? friend.avatarBase64, fallbacName: String(friend.name.prefix(1)), fallbackColor: friend.avatarColor)
                HStack(alignment: .bottom, spacing: 4) {
                    Text(msg.content)
                        .font(.system(size: 14)).padding(10).background(Color(NSColor.controlBackgroundColor)).foregroundColor(.primary)
                        .clipShape(TailChatBubbleShape(isMe: false)).textSelection(.enabled).overlay(TailChatBubbleShape(isMe: false).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                Spacer(minLength: 60)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: msg.isMe ? .trailing : .leading)),
            removal: .opacity
        ))
        .padding(.vertical, 2).id(msg.id).onTapGesture(count: 2) { triggerReaction() }
    }
    
    private func triggerReaction() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { reactionScale = 1.2; reactionOpacity = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.4)) {
                reactionScale = 1.5
                reactionOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                reactionScale = 0.5
            }
        }
    }
    
    // 全局头像缓存，避免滚动时主线程频繁且重复解析长 Base64 字符串导致的掉帧卡顿
    fileprivate static let globalAvatarCache = NSCache<NSString, NSImage>()
    
    // Abstracted avatar renderer to support URL/Base64 strings flexibly
    @ViewBuilder
    private func renderAvatar(base64String: String?, fallbacName: String, fallbackColor: Color) -> some View {
        InteractiveAvatarView(
            base64String: base64String,
            fallbacName: fallbacName,
            fallbackColor: fallbackColor,
            cache: Self.globalAvatarCache
        )
    }
    
    private func sendMessage() async {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let contentToSend = messageText
        messageText = ""
        
        // 发送前预声明滚动到最底
        shouldScrollToBottom = true
        
        let avatar = authService.currentUser?.avatar
        socketManager.sendChatMessage(receiverId: friend.id, content: contentToSend, msgType: "TEXT", avatar: avatar)
    }
    
    private func loadInitialHistory() async {
        var currentUnreadCount: Int32 = 0
        
        await MainActor.run {
            currentUnreadCount = Int32(socketManager.unreadCounts[friend.id] ?? 0)
            
            // 切换好友时先清空记录，保证 UI 界面是一个干净的状态接收新数据
            var history = socketManager.chatHistory
            history[friend.id] = []
            socketManager.chatHistory = history
            
            currentOffset = 0
            hasMore = true
            isLoadingHistory = false
        }
        
        await fetchHistory(offset: 0, limit: pageSize, isInitial: true)
        
        // 按照需求，如果加载完历史且未读数量大于0，发起0x55帧请求
        print("🔍 [loadInitialHistory] friend.id=\\(friend.id), currentUnreadCount=\\(currentUnreadCount)")
        if currentUnreadCount > 0 {
            do {
                print("📨 发起清除红点请求 0x55...")
                let success = try await socketManager.clearUnreadCount(friendId: Int32(friend.id))
                print("✅ 0x55 请求响应成功标识: \\(success)")
                
                if success {
                    await MainActor.run {
                        print("🔄 正在更新本地 UI unreadCounts 字典...")
                        var counts = socketManager.unreadCounts
                        counts[friend.id] = 0
                        // 强制赋值全新的字典以触发 @Published
                        socketManager.unreadCounts = counts
                        print("✨ unreadCounts 本地更新完成: \\(socketManager.unreadCounts[friend.id] ?? -1)")
                    }
                } else {
                    print("❌ 服务端返回清除红点失败 (业务失败，非抛错)")
                }
            } catch {
                print("❌ 发送清除红点请求 0x55 失败(抛出异常): \\(error)")
            }
        }
    }
    
    private func loadMoreHistory() async {
        guard hasMore, !isLoadingHistory else { return }
        await MainActor.run {
            currentOffset += pageSize
        }
        await fetchHistory(offset: currentOffset, limit: pageSize, isInitial: false)
    }
    
    private func fetchHistory(offset: Int32, limit: Int32, isInitial: Bool) async {
        if !isInitial {
            await MainActor.run {
                topMessageIdBeforeLoad = messages.first?.id
            }
        }
        await MainActor.run { isLoadingHistory = true }
        defer { Task { @MainActor in isLoadingHistory = false } }
        
        do {
            let historyDtos = try await socketManager.getChatHistory(friendId: Int32(friend.id), offset: offset, limit: limit)
            
            await MainActor.run {
                if historyDtos.count < limit {
                    hasMore = false
                }
                
                let newMessages = historyDtos.map { dto in
                    let amIMe = (dto.senderId != Int32(friend.id))
                    
                    return ChatMessage(
                        messageId: Int32(dto.id),
                        content: dto.content,
                        isMe: amIMe,
                        timestamp: Date(),
                        type: "TEXT",
                        sendStatus: .success,
                        groupTime: dto.groupTime,
                        msgTimeStr: dto.msgTimeStr,
                        avatar: dto.avatar
                    )
                }
                
                var history = socketManager.chatHistory
                let currentList = history[friend.id] ?? []
                
                // ────────────────────────────────────────────────────────────
                // 直接从历史消息中提取当前用户自己的 base64 头像（无条件覆盖）
                // 服务端 avatars 字典里的是 base64，比登录响应的文件路径更可靠
                // ────────────────────────────────────────────────────────────
                if let myMsg = newMessages.first(where: { $0.isMe && $0.avatar != nil && !($0.avatar!.isEmpty) }) {
                    socketManager.myAvatar = myMsg.avatar
                    print("✅ [fetchHistory] myAvatar 已从历史 base64 头像更新")
                }
                
                // 把头像补充给还在等待中的本地乐观消息（发出去但还没回执的）
                let effectiveMyAvatar = socketManager.myAvatar
                let localSendingMessages = currentList.filter { $0.messageId == nil }.map { msg -> ChatMessage in
                    guard msg.isMe, msg.avatar == nil, let av = effectiveMyAvatar else { return msg }
                    var updated = msg
                    updated.avatar = av          // ChatMessage.avatar 需要 var
                    return updated
                }
                
                var finalMessages: [ChatMessage]
                
                if isInitial {
                    finalMessages = newMessages + localSendingMessages
                    shouldScrollToBottom = true
                } else {
                    let existingServerMessages = currentList.filter { $0.messageId != nil }
                    // 假设服务端依然按时间正序返回（最早的在前面，或者根据 offset 拼接在最前面最合适）
                    finalMessages = newMessages + existingServerMessages + localSendingMessages
                }
                
                history[friend.id] = finalMessages
                socketManager.chatHistory = history

            }
        } catch {
            print("❌ 获取历史消息失败: \(error)")
            // To prevent infinite loop of onAppear trying to reload indefinitely if the server crashes
            await MainActor.run {
                hasMore = false
            }
        }
    }
}

// MARK: - Emoji Picker Panel

/// 表情选择面板 - 分类展示常用 emoji，点击后触发回调
private struct EmojiPickerPanel: View {
    let onEmojiSelected: (String) -> Void

    private let categories: [(String, String, [String])] = [
        ("笑脸", "face.smiling", [
            "😀","😁","😂","🤣","😃","😄","😅","😆","😉","😊",
            "😋","😎","😍","🥰","😘","😗","😙","😚","🙂","🤗",
            "🤩","🤔","🤨","😐","😑","😶","🙄","😏","😣","😥",
            "😮","🤐","😯","😪","😫","🥱","😴","😌","😛","😜",
            "😝","🤤","😒","😓","😔","😕","🙃","🤑","😲","☹️",
            "🙁","😖","😞","😟","😤","😢","😭","😦","😧","😨",
            "😩","🤯","😬","😰","😱","🥵","🥶","😳","🤪","😠"
        ]),
        ("手势", "hand.raised", [
            "👋","🤚","🖐","✋","🖖","👌","🤏","✌️","🤞","🤟",
            "🤘","🤙","👈","👉","👆","🖕","👇","☝️","👍","👎",
            "✊","👊","🤛","🤜","👏","🙌","👐","🤲","🤝","🙏",
            "✍️","💪","🦾","🦿","🦵","🦶","👂","🦻"
        ]),
        ("人物", "person", [
            "👶","🧒","👦","👧","🧑","👱","👨","🧔","👩","🧓",
            "👴","👵","🙍","🙎","🙅","🙆","💁","🙋","🧏","🙇",
            "🤦","🤷","👮","💂","👷","🤴","👸","🦸","🦹"
        ]),
        ("动物", "pawprint", [
            "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯",
            "🦁","🐮","🐷","🐸","🐵","🙈","🙉","🙊","🐔","🐧",
            "🐦","🐤","🦆","🦅","🦉","🦇","🐺","🐴","🦄","🐢",
            "🐍","🦎","🐊","🦕","🦖","🦈","🐋","🐬","🦭","🐘"
        ]),
        ("食物", "fork.knife", [
            "🍎","🍊","🍋","🍇","🍓","🍈","🍒","🍑","🥭","🍍",
            "🥥","🥝","🍅","🍆","🥑","🥦","🌽","🥕","🧄","🧅",
            "🍔","🍟","🍕","🌮","🌯","🥪","🥙","🧆","🥚","🍳",
            "🍿","🧂","🥞","🧇","🧈","🍱","🍜","🍣","🍦","☕️"
        ]),
        ("活动", "sportscourt", [
            "⚽️","🏀","🏈","⚾️","🎾","🏐","🏉","🎱","🏓","🏸",
            "🥊","🥋","🎽","🛹","🛷","⛸","🏂","🏋️","🤸","🤺",
            "🏊","🚴","🧘","🎯","🎳","🎲","🎮","🎸","🎺","🎻"
        ]),
        ("旅行", "car", [
            "🚗","🚕","🚙","🚌","🏎","🚓","🚒","🚐","🚚","✈️",
            "🚀","🛸","🚁","🛶","⛵️","🚢","🚂","🏠","🏢","🗼",
            "🗽","⛩","🎡","🎢","🎠","🌍","🌏","🌙","☀️","🌈"
        ]),
        ("符号", "heart", [
            "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔",
            "❣️","💕","💞","💓","💗","💖","💘","💝","💯","✅",
            "❎","🔴","🟠","🟡","🟢","🔵","🟣","⚫️","⚪️","🟤",
            "🔶","🔷","🔸","🔹","🔺","🔻","💠","🔘","🔲","🔳"
        ]),
        ("物品", "star", [
            "🎁","🎈","🎉","🎊","🎀","🏆","🥇","🥈","🥉","🎖",
            "🔑","🗝","🔒","🔓","🔔","🔕","🎵","🎶","💡","🔦",
            "📱","💻","⌨️","🖥","🖨","📷","📸","📹","🎥","📺",
            "📚","📖","✏️","🖊","📝","💼","🎒","🌂","☂️","🧲"
        ])
    ]

    @State private var selectedCategoryIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // 分类标签栏 —— 均匀分布，无需滚动
            HStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.offset) { index, cat in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategoryIndex = index
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: cat.1)
                                .font(.system(size: 13))
                            Text(cat.0)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            selectedCategoryIndex == index
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .foregroundColor(selectedCategoryIndex == index ? .accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Emoji 网格 —— adaptive 列宽，自动铺满
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 0)],
                    spacing: 0
                ) {
                    ForEach(categories[selectedCategoryIndex].2, id: \.self) { emoji in
                        EmojiCell(emoji: emoji, onTap: onEmojiSelected)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .frame(height: 160)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: -3)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }
}

/// 单个 Emoji 格子，带 hover 高亮
private struct EmojiCell: View {
    let emoji: String
    let onTap: (String) -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: { onTap(emoji) }) {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.secondary.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
    }
}


private struct InteractiveAvatarView: View {
    let base64String: String?
    let fallbacName: String
    let fallbackColor: Color
    let cache: NSCache<NSString, NSImage>
    
    @State private var showingPopover = false
    
    private var cachedImage: NSImage? {
        guard let base64 = base64String, !base64.isEmpty else { return nil }
        return cache.object(forKey: base64 as NSString)
    }
    
    var body: some View {
        Group {
            if let image = cachedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else if let base64 = base64String, !base64.isEmpty {
                AvatarDecodeView(base64: base64, fallbacName: fallbacName, fallbackColor: fallbackColor, cache: cache)
            } else {
                Circle()
                    .fill(fallbackColor)
                    .frame(width: 32, height: 32)
                    .overlay(Text(fallbacName).font(.caption).foregroundColor(.white))
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            showingPopover = true
        }
        .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
            VStack {
                if let image = cachedImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 256, height: 256)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else if let base64 = base64String, !base64.isEmpty {
                    // 如果缓存没命中（可能还没解码完），回退到基础解码显示
                    AvatarDecodeView(base64: base64, fallbacName: fallbacName, fallbackColor: fallbackColor, cache: cache, customSize: 256)
                } else {
                    Circle()
                        .fill(fallbackColor)
                        .frame(width: 256, height: 256)
                        .overlay(
                            Text(fallbacName)
                                .font(.system(size: 80, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
            }
            .padding(12)
        }
    }
}

private struct AvatarDecodeView: View {
    let base64: String
    let fallbacName: String
    let fallbackColor: Color
    let cache: NSCache<NSString, NSImage>
    var customSize: CGFloat = 32
    
    @State private var decodedImage: NSImage?
    
    var body: some View {
        Group {
            if let nsImage = decodedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: customSize, height: customSize)
                    .clipShape(RoundedRectangle(cornerRadius: customSize > 32 ? 8 : customSize / 2))
            } else {
                Circle()
                    .fill(fallbackColor)
                    .frame(width: customSize, height: customSize)
                    .overlay(Text(fallbacName).font(customSize > 32 ? .system(size: 80) : .caption).foregroundColor(.white))
            }
        }
        .task {
            // Asynchronous decoding off the main thread
            await decodeImageAsync()
        }
    }
    
    private func decodeImageAsync() async {
        // 先检查是否已经被其他 Cell 缓存
        if let cached = cache.object(forKey: base64 as NSString) {
            await MainActor.run { self.decodedImage = cached }
            return
        }
        
        // 提取并去除头
        let pureBase64 = base64.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pureBase64.isEmpty else { return }
        
        // 在后台线程执行沉重的 base64 和图片解码工作
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            if let avatarData = Data(base64Encoded: pureBase64, options: .ignoreUnknownCharacters),
               let nsImage = NSImage(data: avatarData) {
                return nsImage
            }
            return nil
        }.value
        
        if let validImage = image {
            cache.setObject(validImage, forKey: base64 as NSString)
            await MainActor.run {
                self.decodedImage = validImage
            }
        }
    }
}

// 3. Friend Sidebar View (左侧列表)
// 3. Friend Sidebar View (左侧列表)
// 3. Friend Sidebar View (左侧列表)
private struct OptimizedFriendSidebarView: View {
    @Binding var selectedFriendId: Int64?
    let friends: [Friend]
    @State private var searchText = ""
    @State private var showingAddFriendSheet = false
    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject var socketManager: SocketManager
    
    var filteredFriends: [Friend] {
        if searchText.isEmpty {
            return friends
        } else {
            return friends.filter { $0.name.contains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Combined Header: Search Bar + Add Button
            HStack(spacing: 8) {
                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    
                    TextField("搜索好友", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isSearchFocused)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSearchFocused ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1)
                )
                
                // Add Button
                Button(action: {
                    showingAddFriendSheet = true
                }) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("添加好友")
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial) // Added vibrancy to header as well
            
            Divider()
            
            // List
            ScrollView {
                LazyVStack(spacing: 0) {
                    // New Friend Item
                    Button(action: {
                        selectedFriendId = -1 // Special ID for New Friend
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.orange)
                                .clipShape(Circle())
                            
                            Text("新的朋友")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Badge with dynamic count
                            if socketManager.pendingFriendRequests.count > 0 {
                                Text("\(socketManager.pendingFriendRequests.count)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle()) // Make entire area clickable
                        .background(selectedFriendId == -1 ? Color.blue : Color.clear)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 64)
                    
                    ForEach(filteredFriends) { friend in
                        FriendRow(friend: friend, isSelected: selectedFriendId == friend.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedFriendId = friend.id
                            }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingAddFriendSheet) {
            MacAddFriendSheet(isPresented: $showingAddFriendSheet)
        }
    }
}

// 3.1. Add Friend View (添加好友弹窗 - macOS Style)
private struct MacAddFriendSheet: View {
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var searchResults: [UserDto] = []
    @State private var isSearching = false
    @State private var requestSent = false
    @State private var lastErrorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Window Header (Visual Title Bar)
            ZStack {
                Text("添加好友")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(VisualEffectBlur(material: .headerView, blendingMode: .withinWindow).ignoresSafeArea(edges: .top))
            
            Divider()
            
            // Main Content
            VStack(spacing: 24) {
                // Search Input Group
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("输入用户 ID 或昵称", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .onSubmit { performSearch() }
                        
                        if !searchText.isEmpty {
                            Button(action: { performSearch() }) {
                                Text("搜索")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isSearching)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    
                    Text("通过精确匹配用户 ID 或昵称来查找好友")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
                
                // Result Area
                ZStack {
                    if isSearching {
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在查找...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = lastErrorMessage {
                         VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.red.opacity(0.8))
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !searchResults.isEmpty {
                        // User Response List
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(searchResults) { user in
                                    UserResultRow(user: user, requestSent: $requestSent)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    } else if !searchText.isEmpty {
                        // Empty State for Search
                        VStack(spacing: 12) {
                            Image(systemName: "person.slash.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("未找到该用户")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("请检查输入的 ID 或昵称是否正确")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Initial Empty State
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                                .opacity(0.5)
                            Text("寻找新朋友")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 160) // Increased height to accommodate list
            }
            .padding(24)
        }
        .frame(width: 600, height: 450) // Increased size for better text display
        .background(VisualEffectBlur(material: .windowBackground, blendingMode: .behindWindow))
    }
    // 用户名搜索
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        lastErrorMessage = nil
        requestSent = false
        
        Task {
            do {
                let users = try await SocketManager.shared.searchUser(userName: searchText)
                await MainActor.run {
                    self.searchResults = users
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }
}

// Subview for User Result Row 用户搜索结果行视图
private struct UserResultRow: View {
    let user: UserDto
    @Binding var requestSent: Bool
    @State private var isHovering = false
    
    @EnvironmentObject var socketManager: SocketManager
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            let cleanAvatar = user.avatar?.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let avatarStr = cleanAvatar, !avatarStr.isEmpty,
               let avatarData = Data(base64Encoded: avatarStr, options: .ignoreUnknownCharacters),
               let nsImage = NSImage(data: avatarData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                    .overlay(Text((user.nickName ?? user.userName).prefix(1)).foregroundColor(.white).font(.headline))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.nickName ?? user.userName)
                    .font(.headline)
                    .foregroundColor(.primary)
                HStack(spacing: 6) {
                    Text("@\(user.userName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 按钮逻辑状态机
            Group {
                let status = user.friendStatus ?? -1
                let statusDesc = user.friendStatusDesc ?? "添加"
                
                switch status {
                    case 0: // 已投递申请 (对应后端可能返回 0:申请中)
                        Button(statusDesc) {}
                            .disabled(true)
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                    case 1: // 已是好友
                        Button(statusDesc) {}
                            .disabled(true)
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                    case 2: // 对方拒绝 或 陌生人 (允许申请)
                        Button(action: sendFriendRequest) {
                            Text(requestSent ? "已发送" : statusDesc)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(requestSent)
                    default: // 默认情况/陌生人
                        Button(action: sendFriendRequest) {
                            Text(requestSent ? "已发送" : statusDesc)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(requestSent)
                }
            }
            }

        .padding(12)
        .background(isHovering ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .contentShape(Rectangle()) // Ensure hover works on the whole row
        .alert("添加好友", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func statusColor(for status: Int?) -> Color {
        switch status {
        case 0: return .orange
        case 1: return .green
        case 2: return .red
        default: return .secondary
        }
    }
    
    private func sendFriendRequest() {
        Task {
            do {
                // 1. 构建默认验证消息
                let displayName = (user.nickName?.isEmpty ?? true) ? user.userName : user.nickName!
                let msg = "\(displayName)申请添加你为好友"
                
                // 2. 发送好友请求
                print("📨 Sending friend request to \(user.userName) (ID: \(user.id)) with msg: \(msg)")
                let success = try await socketManager.addFriend(remoteUserId: user.id, requestMsg: msg)
                
                await MainActor.run {
                    if success {
                        withAnimation {
                            requestSent = true
                        }
                    } else {
                        alertMessage = "请求发送失败"
                        showingAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = "发送失败: \(error.localizedDescription)"
                    showingAlert = true
                    print("❌ Friend request failed: \(error)")
                }
            }
        }
    }
}


// Helper for padding
extension View {
    func paddingStreamlined() -> some View {
        self.padding(16)
    }
}

// Blur Effect Helper
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}


private struct FriendRow: View {
    let friend: Friend
    let isSelected: Bool
    @EnvironmentObject var socketManager: SocketManager
    
    var unreadCount: Int {
        // 优先使用 SocketManager 中的实时未读数
        if let realTime = socketManager.unreadCounts[friend.id] {
            return realTime // 实时数值哪怕是 0 也应该应用
        }
        return Int(friend.serverUnreadCount ?? 0)
    }
    
    var lastMessageText: String {
        // 优先使用实时的最新一条记录文本，如果没有再降级到服务端下发的 lastUnreadMsg
        if let msg = socketManager.chatHistory[friend.id]?.last {
            return msg.content
        } else if let serverMsg = friend.serverLatestMsg, !serverMsg.isEmpty {
            return serverMsg
        }
        return "点击开始聊天"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar with Unread Badge
            ZStack(alignment: .topTrailing) {
                Group {
                    let cleanAvatar = friend.avatarBase64?.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let avatarStr = cleanAvatar, !avatarStr.isEmpty {
                        if let cachedImage = ChatDetailView.globalAvatarCache.object(forKey: avatarStr as NSString) {
                            Image(nsImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } else {
                            AvatarDecodeView(
                                base64: avatarStr,
                                fallbacName: String(friend.name.prefix(1)),
                                fallbackColor: friend.avatarColor,
                                cache: ChatDetailView.globalAvatarCache
                            )
                            .frame(width: 40, height: 40)
                        }
                    } else {
                        Circle()
                            .fill(friend.avatarColor)
                            .frame(width: 40, height: 40)
                            .overlay(Text(String(friend.name.prefix(1))).foregroundColor(.white))
                    }
                }
                .overlay(
                    Circle()
                        .stroke(
                            friend.status == "在线" ? 
                            LinearGradient(colors: [.green, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing) : 
                            LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                            lineWidth: 2
                        )
                        .padding(-2)
                )
                .shadow(color: friend.status == "在线" ? .green.opacity(0.4) : .clear, radius: 4)
                
                // Unread Badge
                if unreadCount > 0 {
                    Text("\(unreadCount > 99 ? "99+" : "\(unreadCount)")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(friend.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    Spacer()
                    if let lastMsg = socketManager.chatHistory[friend.id]?.last {
                        Text(formatTime(lastMsg.timestamp))
                            .font(.caption)
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
                
                Text(lastMessageText)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue : Color.clear)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MM-dd"
        }
        return formatter.string(from: date)
    }
}


// 4. Friend Chat Split View (主容器)
private struct FriendChatSplitView: View {
    @State private var selectedFriendId: Int64?
    @State private var friends: [Friend] = []
    @EnvironmentObject var socketManager: SocketManager
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            OptimizedFriendSidebarView(selectedFriendId: $selectedFriendId, friends: friends)
                .frame(width: 260)
            
            Divider()
            
            // Right Detail
            if let selectedId = selectedFriendId {
                if selectedId == -1 {
                    NewFriendView()
                } else if let friend = friends.first(where: { $0.id == selectedId }) {
                    ChatDetailView(friend: friend)
                        .id(friend.id) // 确保切换好友时重建 View，清空所有的 @State (如 currentOffset 等)
                } else {
                    // Placeholder
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("选择一个好友开始聊天")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("选择一个好友开始聊天")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .onAppear {
            loadMockFriends()
        }
        .onChange(of: selectedFriendId) { newValue in
            // 通知 SocketManager 当前活跃聊天窗口，以消除红点累加
            socketManager.activeChatFriendId = newValue
            
            // 下面的点击直接清除本地状态去掉了，交给 loadInitialHistory 去做真正的 0x55 清除
        }
        .onChange(of: socketManager.friendList) { newFriendDtos in
            // 当 socketManager.friendList 被更新（如同意好友后 0x35 刷新），同步更新本地 UI friends
            self.friends = newFriendDtos.map { dto in
                let displayName = dto.alias ?? (dto.nickName.isEmpty ? dto.userName : dto.nickName)
                let color = self.colorFor(name: displayName)
                
                // 同步未读数到全局状态，以便 ChatDetailView 判断是否需要触发 0x55
                if let unreadCount = dto.unreadCount {
                    self.socketManager.unreadCounts[dto.friendId] = Int(unreadCount)
                }
                
                return Friend(
                    id: dto.friendId,
                    friendshipId: dto.id,
                    name: displayName,
                    status: "在线",
                    avatarColor: color,
                    avatarBase64: dto.avatar,
                    serverUnreadCount: dto.unreadCount,
                    serverLatestMsg: dto.latestUnreadMsg
                )
            }
        }
    }
    
    private func loadMockFriends() {
        // Load real friends from server
        Task {
            do {
                let friendDtos = try await socketManager.getFriendList()
                await MainActor.run {
                    self.socketManager.friendList = friendDtos // 确保全局状态也能记录下拉取到的最新值
                    self.friends = friendDtos.map { dto in
                        // Convert FriendDto to UI Model (Friend)
                        // Use nickName if available, otherwise userName or alias
                        let displayName = dto.alias ?? (dto.nickName.isEmpty ? dto.userName : dto.nickName)
                        
                        // Parse avatar color from name or id hash if needed, or use default
                        let color = self.colorFor(name: displayName)
                        
                        // 同步未读数到全局状态
                        if let unreadCount = dto.unreadCount {
                            self.socketManager.unreadCounts[dto.friendId] = Int(unreadCount)
                        }
                        
                        return Friend(
                            id: dto.friendId,
                            friendshipId: dto.id,
                            name: displayName,
                            status: "在线", // Default status, real status needs another mechanism
                            avatarColor: color,
                            avatarBase64: dto.avatar,
                            serverUnreadCount: dto.unreadCount,
                            serverLatestMsg: dto.latestUnreadMsg
                        )
                    }
                }
            } catch {
                print("❌ Failed to load friend list: \(error)")
            }
            
            // Fetch pending requests count on load
            try? await socketManager.getPendingRequests()
        }
    }
    
    private func colorFor(name: String) -> Color {
        let colors: [Color] = [.blue, .orange, .purple, .green, .red, .pink, .teal]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Mac Responsive Text View (Custom NSTextView Integration)
/// 封装 AppKit 的 NSTextView，以支持：1. 真正的换行拦截与回车发送；2. 内容自适应高度。
struct MacResponsiveTextView: NSViewRepresentable {
    @Binding var text: String
    var onSendTriggered: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        
        // 替换为自定义的 CustomNSTextView
        let customTextView = CustomNSTextView()
        customTextView.delegate = context.coordinator
        customTextView.drawsBackground = false
        customTextView.isRichText = false
        customTextView.font = NSFont.systemFont(ofSize: 14)
        customTextView.autoresizingMask = [.width]
        customTextView.isHorizontallyResizable = false
        customTextView.isVerticallyResizable = true
        customTextView.textContainerInset = NSSize(width: 8, height: 8)
        
        scrollView.documentView = customTextView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CustomNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacResponsiveTextView
        
        init(_ parent: MacResponsiveTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                let flags = event?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) || flags.contains(.control) {
                    // 修饰键+Enter，允许换行
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    // 单击回车，触发发送逻辑
                    self.parent.onSendTriggered()
                    return true
                }
            }
            return false
        }
    }
}

class CustomNSTextView: NSTextView {
    // 留出扩展接口供日后处理剪贴板图片等
}

// MARK: - Chat Bubble Tail Shape
struct TailChatBubbleShape: Shape {
    var isMe: Bool
    var cornerRadius: CGFloat = 8
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.width
        let h = rect.height
        let r = cornerRadius
        
        if isMe {
            // Tail at bottom right
            path.move(to: CGPoint(x: 0, y: r))
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            
            // Draw tail
            path.addLine(to: CGPoint(x: w, y: h)) // Sharp bottom right corner
            path.addLine(to: CGPoint(x: w - r, y: h)) // Go left
            
            path.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.closeSubpath()
        } else {
            // Tail at bottom left
            path.move(to: CGPoint(x: w, y: h - r))
            path.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: r, y: h)) // Go left
            path.addLine(to: CGPoint(x: 0, y: h)) // Sharp bottom left corner
            path.addLine(to: CGPoint(x: 0, y: r)) // Go up
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            path.closeSubpath()
        }
        
        return path
    }
}

// MARK: - Cloud Storage Components

/// 动态背景：磨砂渐变效果
private struct MeshGradientBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // 基础渐变
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.1),
                    Color.cyan.opacity(0.1)
                ],
                startPoint: animate ? .topLeading : .bottomTrailing,
                endPoint: animate ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                    animate.toggle()
                }
            }
            
            // 模糊层
            VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                .ignoresSafeArea()
        }
    }
}

/// 网格视图：卡片式文件展示
private struct CloudGridView: View {
    let items: [DirectoryItem]
    @Binding var selectedFiles: Set<Int64>
    @Binding var selectedFileId: Int64?
    var onFileTapped: (DirectoryItem) -> Void
    var onFileDoubleTapped: (DirectoryItem) -> Void
    var onAction: (DirectoryItem, Int) -> Void
    
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(items) { item in
                    FileCard(
                        item: item,
                        isSelected: selectedFiles.contains(item.id) || selectedFileId == item.id,
                        onTap: { onFileTapped(item) },
                        onDoubleTap: { onFileDoubleTapped(item) },
                        onAction: { action in onAction(item, action) }
                    )
                }
            }
            .padding(24)
        }
    }
}

/// 文件卡片：生动形象的单个文件/文件夹展示
private struct FileCard: View {
    let item: DirectoryItem
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onAction: (Int) -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 12) {
            // 图标区域
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.05))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
                
                Image(systemName: item.isFile ? item.iconName : "folder.fill")
                    .font(.system(size: 44))
                    .foregroundColor(item.isFile ? .blue : .orange)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(isHovering ? 1.1 : 1.0)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .background(Circle().fill(Color.white))
                        .offset(x: 6, y: -6)
                }
            }
            .shadow(color: .black.opacity(isHovering ? 0.2 : 0.05), radius: isHovering ? 10 : 4, y: isHovering ? 5 : 2)
            
            // 文字区域
            VStack(spacing: 4) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                Text(item.isFile ? item.sizeString : "\(item.childFileList?.count ?? 0) 项")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture(count: 1, perform: onTap)
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { isHovering = h } }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .opacity
        ))
        .contextMenu {
            Button { onAction(2) } label: { Label("下载", systemImage: "arrow.down.circle") }
            Button { onAction(1) } label: { Label("删除", systemImage: "trash") }
        }
    }
}

// MARK: - View Extensions
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/// 系统视觉效果视图包装器
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - FileListRowView (商业级文件行组件)
/// 带悬停动画、卡片背景、微缩放效果的文件行视图
private struct FileListRowView: View {
    let file: DirectoryItem
    let isSelected: Bool
    let isChecked: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isDownloadHovering = false
    @State private var isDeleteHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // 复选框
            Toggle("", isOn: Binding(get: { isChecked }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .frame(width: 24)

            // 文件图标（颜色渐变，按类型区分）
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(file.isFile
                          ? Color.blue.opacity(0.08)
                          : Color.orange.opacity(0.08))
                    .frame(width: 32, height: 32)
                Image(systemName: file.isFile ? file.iconName : "folder.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(file.isFile
                                     ? Color.blue.gradient
                                     : Color.orange.gradient)
            }

            // 文件名
            Text(file.fileName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)

            // 文件大小
            Text(file.sizeString)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            // 上传时间
            Text(file.uploadTimeString)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            // 操作按钮（悬停时渐显）
            HStack(spacing: 10) {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isDownloadHovering
                                         ? Color.accentColor
                                         : Color.secondary.opacity(0.6))
                        .scaleEffect(isDownloadHovering ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: isDownloadHovering)
                }
                .buttonStyle(.plain)
                .help("下载")
                .onHover { isDownloadHovering = $0 }

                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(isDeleteHovering
                                         ? Color.red
                                         : Color.secondary.opacity(0.5))
                        .scaleEffect(isDeleteHovering ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: isDeleteHovering)
                }
                .buttonStyle(.plain)
                .help("删除")
                .onHover { isDeleteHovering = $0 }
            }
            .opacity(isHovering || isSelected ? 1 : 0.4)
            .frame(width: 72, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected
                    ? Color.accentColor.opacity(0.13)
                    : isHovering
                        ? Color.primary.opacity(0.05)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected
                    ? Color.accentColor.opacity(0.4)
                    : Color.clear,
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovering ? 1.005 : 1.0)
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
            radius: 4, x: 0, y: 2
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovering = hovering }
        }
        .onTapGesture { onTap() }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

// MARK: - HeaderItem & FileTableHeaderView (现代表头组件)
/// 表头项定义
struct HeaderItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String?
    let width: CGFloat?
    let alignment: Alignment
    let isSpacer: Bool // 为其分配 maxWidth: .infinity
    
    init(title: String, icon: String? = nil, width: CGFloat? = nil, alignment: Alignment = .leading, isSpacer: Bool = false) {
        self.title = title
        self.icon = icon
        self.width = width
        self.alignment = alignment
        self.isSpacer = isSpacer
    }
}

/// 具有现代感（玻璃材质、精致图标）的表头视图
struct FileTableHeaderView: View {
    let items: [HeaderItem]
    let leadingPadding: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            // 前置填充（用于对齐复选框等）
            if leadingPadding > 0 {
                Spacer()
                    .frame(width: leadingPadding)
            }
            
            ForEach(items) { item in
                HStack(spacing: 4) {
                    if let icon = item.icon {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor.gradient)
                            .opacity(0.8)
                    }
                    
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(width: item.isSpacer ? nil : item.width, alignment: item.alignment)
                .frame(maxWidth: item.isSpacer ? .infinity : nil, alignment: item.alignment)
            }
        }
        .padding(.horizontal, 14)
        .background(
            ZStack {
                // 玻璃材质底色
                VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                
                // 细微的边框或底部分割线
                VStack {
                    Spacer()
                    Divider().opacity(0.1)
                }
            }
        )
    }
}


// MARK: - TransferListRowView (商业级传输行组件)
/// 带渐变进度条、状态徽章、悬停按钮的传输任务行
private struct TransferListRowView: View {
    let item: TransferItem
    let onStart:  () -> Void
    let onPause:  () -> Void
    let onCancel: () -> Void

    @State private var isHovering = false

    private var isActive: Bool {
        item.status == "上传中" || item.status == "下载中" || item.status == "等待下载"
    }
    private var canResume: Bool {
        item.status == "等待上传" || item.status == "暂停" || item.status == "已暂停" || item.status == "失败"
    }

    private var statusColor: Color {
        switch item.status {
        case "已完成":        return .green
        case "上传中":        return .blue
        case "下载中":        return .teal
        case "等待上传", "等待下载": return .gray
        case "失败":          return .red
        case "暂停", "已暂停": return .orange
        default:             return .primary
        }
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: item.taskType == .upload
                ? [Color.blue, Color.indigo]
                : [Color.teal, Color.green]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶部行：图标 + 文件名 + 右侧操作按钮
            HStack(spacing: 10) {
                // 传输类型图标
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(item.taskType == .upload
                              ? Color.blue.opacity(0.1)
                              : Color.teal.opacity(0.1))
                        .frame(width: 30, height: 30)
                    Image(systemName: item.taskType == .upload
                          ? "arrow.up.circle.fill"
                          : "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.taskType == .upload
                                         ? Color.blue.gradient
                                         : Color.teal.gradient)
                }

                // 文件名 + 目录
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(item.directoryName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(item.sizeString)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 状态徽章
                Text(item.status)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .clipShape(Capsule())

                // 操作按钮（悬停时渐显）
                HStack(spacing: 6) {
                    if canResume {
                        Button(action: onStart) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.blue.gradient)
                        }
                        .buttonStyle(.plain)
                        .help(item.taskType == .upload ? "开始上传" : "开始下载")
                        .transition(.opacity)
                    } else if isActive {
                        Button(action: onPause) {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.orange.gradient)
                        }
                        .buttonStyle(.plain)
                        .help("暂停")
                        .transition(.opacity)
                    }

                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.red.opacity(0.8).gradient)
                    }
                    .buttonStyle(.plain)
                    .help("取消")
                }
                .opacity(isHovering ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
            }

            // 进度条（渐变样式）
            if item.progress > 0 || isActive {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 5)
                        Capsule()
                            .fill(progressGradient)
                            .frame(width: max(geo.size.width * CGFloat(item.progress), 0), height: 5)
                            .animation(.easeInOut(duration: 0.4), value: item.progress)
                    }
                }
                .frame(height: 5)

                // 进度百分比 + 速度
                HStack {
                    Text(item.progressPercent)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(statusColor)
                    Spacer()
                    if isActive, !item.speed.isEmpty {
                        Text(item.speed)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering
                      ? Color.primary.opacity(0.04)
                      : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.07 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }
}
import Foundation
import UserNotifications
import AppKit

/// NotificationCenter custom events
extension Notification.Name {
    static let switchToChat = Notification.Name("switchToChat")
}

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// Request authorization to show desktop notifications
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ [NotificationManager] 桌面通知权限已授予")
            } else if let error = error {
                print("❌ [NotificationManager] 桌面通知权限获取失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// Show a notification for an incoming chat message
    /// - Parameters:
    ///   - senderId: ID of the friend who sent the message
    ///   - senderName: Display name of the friend (username or nickname)
    ///   - message: The message content
    func showChatMessageNotification(senderId: Int64, senderName: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = message
        content.sound = UNNotificationSound.default
        content.userInfo = ["senderId": senderId]
        
        let request = UNNotificationRequest(
            identifier: "ChatMessage_\(senderId)_\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [NotificationManager] 发送通知失败: \(error.localizedDescription)")
            } else {
                print("🔔 [NotificationManager] 发送横幅通知成功: '\(senderName): \(message)'")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    /// Called when the app is in the foreground and a notification arrives.
    /// We can choose whether to still show the banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // Show banner and play sound even if app is in foreground (but not focused on this specific chat)
        completionHandler([.banner, .sound])
    }
    
    /// Called when the user clicks on the desktop notification banner
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // Extract senderId from notification userInfo
        if let senderId = response.notification.request.content.userInfo["senderId"] as? Int64 {
            print("🖱️ [NotificationManager] 用户点击了来自 \(senderId) 的消息通知")
            
            // Bring application to front
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            // Post local notification to trigger UI update in SwiftUI
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .switchToChat,
                    object: nil,
                    userInfo: ["senderId": senderId]
                )
            }
        }
        
        completionHandler()
    }
}
