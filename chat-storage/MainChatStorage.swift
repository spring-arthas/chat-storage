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
    @State private var itemsPerPage: Int = 10
    
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
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 顶部工具栏
                topToolbar
                
                Divider()
                
                // TabView 内容区域
                TabView(selection: $selectedTab) {
                    // 第一个标签页：好友列表
                    friendsListView
                        .tabItem {
                            Label("好友列表", systemImage: "person.2.fill")
                        }
                        .tag(0)
                    
                    // 第二个标签页：网盘存储
                    storageView
                        .tabItem {
                            Label("网盘存储", systemImage: "externaldrive.fill")
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
            // 恢复挂起的任务 (Persistent Resumable Transfer)
            directoryService?.resumePendingTasks()
            
            // 延迟加载恢复的任务到 UI (等待 restore 完成)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("🔄 Syncing restored tasks to UI...")
                loadRestoredTasks()
            }
        }
        .onChange(of: selectedTab) { newTab in
            // 当切换到网盘存储标签页时，加载目录
            // 使用 DispatchQueue 延迟执行，避免在视图初始化时立即创建 Task
            if newTab == 1 {
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
        // 监听传输任务更新
        .onReceive(TransferTaskManager.shared.$taskUpdates) { updates in
            var needReload = false
            
            for (id, info) in updates {
                if let index = self.transferList.firstIndex(where: { $0.id == id }) {
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 刷新按钮
                Button(action: {
                    Task {
                        await loadDirectoryFromServer()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("刷新目录")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 树形列表
            // 树形列表 (使用自定义递归视图以支持展开控制)
            List {
                RecursiveDirectoryView(
                    nodes: directoryTree,
                    selectedId: $selectedDirectoryId,
                    expandedIds: $expandedDirectoryIds,
                    onCreate: { item in
                        addLog("在 [\(item.fileName)] 下新建目录")
                        self.createDirParentId = item.id
                        self.newDirName = ""
                        self.showingCreateDirDialog = true
                    },
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
            }
            .listStyle(SidebarListStyle())
            .alert("确认删除目录", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    handleDeleteDirectory()
                }
            } message: {
                Text("确定要删除目录 [\(deleteTargetName)] 吗？此操作无法撤销。")
            }
        }
    }
    
    // MARK: - Main Content (主内容区域)
    

    
    private var mainContent: some View {
        VSplitView {
            // 上半部分：文件浏览区
            VStack(spacing: 0) {
                // 上传控制栏
                uploadControlBar
                
                Divider()
                
                // 文件列表
                fileListView
            }
            .frame(minHeight: 300)
            
            // 下半部分：文件传输区
            transferListView
                .frame(minHeight: 150)
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
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .disabled(selectedFiles.isEmpty)
            
            Button(action: {
                handleBatchDownload()
            }) {
                Label("批量下载", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.blue)
            .disabled(selectedFiles.isEmpty)


            
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
            // 表头
            HStack(spacing: 0) {
                //复选框列 (全选)
                Toggle("", isOn: Binding(
                    get: { isAllSelected },
                    set: { _ in toggleAllSelection() }
                ))
                .toggleStyle(.checkbox)
                .frame(width: 30, alignment: .center)
                
                Label("文件名称", systemImage: "doc")
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                
                Label("文件大小", systemImage: "externaldrive")
                    .frame(width: 80, alignment: .leading)
                
                Label("所属目录", systemImage: "folder")
                    .frame(width: 100, alignment: .leading)
                
                Label("上传时间", systemImage: "clock")
                    .frame(width: 140, alignment: .leading)
                
                Text("操作")
                    .frame(width: 80, alignment: .center)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
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
        HStack(spacing: 0) {
            // 复选框 (单选)
            Toggle("", isOn: Binding(
                get: { selectedFiles.contains(file.id) },
                set: { _ in toggleSelection(file.id) }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 30, alignment: .center)
            
            // 文件名
            HStack(spacing: 6) {
                Image(systemName: !file.isFile ? "folder.fill" : "doc.fill")
                    .foregroundColor(!file.isFile ? .blue : .gray)
                Text(file.fileName)
                    .font(.system(size: 11))
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            
            // 文件大小
            Text(file.sizeString)
                .font(.system(size: 11))
                .frame(width: 80, alignment: .leading)
            
            // 所属目录
            Text(file.directoryName ?? "-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            // 上传时间
            Text(file.uploadTimeString)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            
            // 操作按钮
            HStack(spacing: 4) {
                Button(action: {
                    handleFileAction(file, action: 1) // 1: 删除
                }) {
                    Image(systemName: "trash")
                    .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("删除")
                
                Button(action: {
                    handleFileAction(file, action: 2) // 2: 下载
                }) {
                    Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("下载")
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selectedFiles.contains(file.id) ? Color.accentColor.opacity(0.1) : Color.clear)
        .onTapGesture {
            toggleSelection(file.id)
        }
    }
    
    // MARK: - Transfer List View (文件传输区)
    
    private var transferListView: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Label("传输列表", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .bold))
                
                Spacer()
                
                // 批量启动按钮 (原批量上传)
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
                    // 清除已完成的任务
                    let completedTasks = transferList.filter { $0.status == "已完成" }
                    for task in completedTasks {
                        PersistenceManager.shared.deleteTask(taskId: task.id.uuidString)
                    }
                    
                    transferList.removeAll { $0.status == "已完成" }
                    // 重新排序剩余任务 (保持规则一致)
                    sortTransferList()
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
            
            // 表头
            HStack(spacing: 0) {
                Label("文件名称", systemImage: "doc")
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                
                Label("文件大小", systemImage: "externaldrive")
                    .frame(width: 80, alignment: .leading)
                
                Label("所属目录", systemImage: "folder")
                    .frame(width: 100, alignment: .leading)
                
                Label("传输类型", systemImage: "arrow.up.arrow.down") // New Column
                    .frame(width: 80, alignment: .leading)
                
                Label("状态", systemImage: "waveform.path.ecg")
                    .frame(width: 80, alignment: .leading)
                
                Label("传输进度", systemImage: "timer")
                    .frame(width: 200, alignment: .leading)
                
                Text("操作")
                    .frame(width: 80, alignment: .center)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
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
    
    private func transferRow(_ item: TransferItem) -> some View {
        HStack(spacing: 0) {
            // 文件名
            HStack(spacing: 6) {
                Image(systemName: "doc.fill")
                    .foregroundColor(.blue)
                Text(item.name)
                    .font(.system(size: 11))
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            
            // 文件大小
            Text(item.sizeString)
                .font(.system(size: 11))
                .frame(width: 80, alignment: .leading)
            
            // 所属目录
            Text(item.directoryName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            // 传输类型
            HStack(spacing: 4) {
                Image(systemName: item.taskType == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(item.taskType == .upload ? .blue : .green)
                Text(item.taskType.rawValue)
            }
            .font(.system(size: 11))
            .frame(width: 80, alignment: .leading)
            
            // 状态
            Text(item.status)
                .font(.system(size: 11))
                .foregroundColor(statusColorForTransfer(item.status))
                .frame(width: 80, alignment: .leading)
            
            // 传输进度
            HStack(spacing: 8) {
                ProgressView(value: item.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 0.8, anchor: .center)
                
                VStack(alignment: .trailing, spacing: 0) {
                    Text(item.progressPercent)
                        .font(.system(size: 10))
                    
                    if item.status == "上传中" || item.status == "下载中" {
                        Text(item.speed)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 50, alignment: .trailing)
            }
            .frame(width: 200, alignment: .leading)
            
            // 操作按钮
            HStack(spacing: 4) {
                if item.status == "等待上传" || item.status == "暂停" || item.status == "已暂停" || item.status == "失败" {
                    // Start/Resume Button
                    Button(action: { handleTransferAction(id: item.id, action: "start") }) {
                        Image(systemName: "arrow.up.circle") // Upload icon for start
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("开始上传")
                } else if item.status == "上传中" {
                    // Pause Button
                    Button(action: { handleTransferAction(id: item.id, action: "pause") }) {
                        Image(systemName: "pause.circle")
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help("暂停")
                }
                
                // Cancel Button (Always visible)
                Button(action: { handleTransferAction(id: item.id, action: "cancel") }) {
                    Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("取消")
            }
            .controlSize(.small)
            .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func statusColorForTransfer(_ status: String) -> Color {
        switch status {
        case "已完成": return .green
        case "上传中": return .blue
        case "等待上传": return .gray
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
        let server = socketManager.getCurrentServer()
        serverAddress = "\(server.host):\(server.port)"
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
            // TODO: 调用下载逻辑 (如果已有 downloadFile 方法)
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
    
    private func handleBatchDelete() {
        let count = selectedFiles.count
        print("批量删除: \(count) 个文件")
        
        // 获取选中的行号 (index + 1)
        let selectedIndices = fileList.enumerated()
            .filter { selectedFiles.contains($0.element.id) }
            .map { String($0.offset + 1) }
            .joined(separator: ", ")
            
        alertMessage = "选择了以下行进行删除：\(selectedIndices)"
        showingAlert = true
        
        addLog("批量删除 \(count) 个文件")
    }
    
    private func handleBatchDownload() {
        let count = selectedFiles.count
        print("批量下载: \(count) 个文件")
        
        // 获取选中的行号 (index + 1)
        let selectedIndices = fileList.enumerated()
            .filter { selectedFiles.contains($0.element.id) }
            .map { String($0.offset + 1) }
            .joined(separator: ", ")
            
        alertMessage = "选择了以下行进行下载：\(selectedIndices)"
        showingAlert = true
        
        addLog("批量下载 \(count) 个文件")
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
        GeometryReader { geometry in
            HSplitView {
                // 左侧边栏 (18%)
                sidebar
                    .frame(minWidth: 150, maxWidth: .infinity)
                    .frame(width: geometry.size.width * 0.18)
                
                // 右侧主内容 (75%)
                mainContent
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
        }
    }

    
    // MARK: - Helper Views
    
    private func statusView(status: String) -> some View {
        HStack(spacing: 4) {
            switch status {
            case "已完成":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case "失败":
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            case "上传中":
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.blue)
            case "等待上传":
                Image(systemName: "clock.fill")
                    .foregroundColor(.gray)
            default:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
            }
            Text(status)
                .font(.system(size: 11))
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
        let currentUserId = Int64(authService.currentUser?.userId ?? 0)
        
        for item in transferList {
            // 只处理非“上传中”和非“已完成”的任务
            if item.status != "上传中" && item.status != "下载中" && item.status != "已完成" {
                
                // 确保有文件路径
                if let fileUrl = item.fileUrl {
                    let task = StorageTransferTask(
                        id: item.id, // 使用 TransferItem 现有的 ID
                        name: item.name,
                        fileUrl: fileUrl,
                        targetDirId: item.targetDirId,
                        userId: currentUserId,
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
            if item.status == "暂停" {
                addLog("▶️ 恢复任务: \(item.name)")
                transferManager.resume(id: id)
            } else {
                addLog("🚀 提交任务至队列: \(item.name)")
                transferList[index].status = "等待上传" // 立即更新UI响应
                
                guard let fileUrl = item.fileUrl else {
                    addLog("❌ 文件路径丢失: \(item.name)")
                    transferList[index].status = "失败"
                    return
                }
                
                // 获取当前用户ID (从全局认证服务)
                let currentUserId = Int64(authService.currentUser?.userId ?? 0)
                
                
                // 构建 TransferTask
                // 构建 TransferTask
                let task = StorageTransferTask(
                    id: item.id,
                    name: item.name,
                    fileUrl: fileUrl,
                    targetDirId: item.targetDirId,
                    userId: currentUserId,
                    fileSize: item.size,
                    directoryName: item.directoryName,
                    progress: 0.0
                )
                
                transferManager.submit(task: task)
            }
            
        case "pause":
            addLog("⏸️ 暂停任务: \(item.name)")
            transferManager.pause(id: id)
            
        case "cancel":
            addLog("❌ 取消任务: \(item.name)")
            transferManager.cancel(id: id)
            transferList.remove(at: index)
            
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
        
        print("📥 Loading \(tasks.count) tasks from service to UI")
        
        for task in tasks {
            // Check if already exists in UI
            if !transferList.contains(where: { $0.id == task.id }) {
                // Get current status and progress from manager updates
                // If update is missing, use task.progress (restored value) instead of 0.0
                let (status, progress, speed) = TransferTaskManager.shared.taskUpdates[task.id] ?? ("已暂停", task.progress, "")
                
                let newItem = TransferItem(
                    id: task.id, // Explicitly set restored ID
                    name: task.name,
                    size: task.fileSize,
                    directoryName: task.directoryName,
                    fileUrl: task.fileUrl,
                    targetDirId: task.targetDirId,
                    taskType: .upload, // Defaulting to upload
                    status: status,
                    progress: progress,
                    speed: speed
                )
                transferList.append(newItem)
            }
        }
        
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

struct RecursiveDirectoryView: View {
    let nodes: [DirectoryItem]
    @Binding var selectedId: Int64?
    @Binding var expandedIds: Set<Int64>
    
    // Actions
    var onCreate: (DirectoryItem) -> Void
    var onRename: (DirectoryItem) -> Void
    var onDelete: (DirectoryItem) -> Void
    var onUpload: (DirectoryItem) -> Void
    
    var body: some View {
        ForEach(nodes) { item in
            DirectoryNodeView(
                item: item,
                selectedId: $selectedId,
                expandedIds: $expandedIds,
                onCreate: onCreate,
                onRename: onRename,
                onDelete: onDelete,
                onUpload: onUpload
            )
        }
    }
}

struct DirectoryNodeView: View {
    let item: DirectoryItem
    @Binding var selectedId: Int64?
    @Binding var expandedIds: Set<Int64>
    
    // Actions
    var onCreate: (DirectoryItem) -> Void
    var onRename: (DirectoryItem) -> Void
    var onDelete: (DirectoryItem) -> Void
    var onUpload: (DirectoryItem) -> Void
    
    var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedIds.contains(item.id) },
            set: { isExp in
                if isExp { expandedIds.insert(item.id) }
                else { expandedIds.remove(item.id) }
            }
        )
    }
    
    var body: some View {
        Group {
            if let children = item.childFileList, !children.isEmpty {
                DisclosureGroup(isExpanded: isExpanded) {
                    RecursiveDirectoryView(
                        nodes: children,
                        selectedId: $selectedId,
                        expandedIds: $expandedIds,
                        onCreate: onCreate,
                        onRename: onRename,
                        onDelete: onDelete,
                        onUpload: onUpload
                    )
                } label: {
                    nodeContent
                }
            } else {
                nodeContent
            }
        }
    }
    
    private var nodeContent: some View {
        HStack {
            Image(systemName: item.childFileList == nil && item.isFile ? "doc" : (item.childFileList == nil ? "folder" : "folder.fill"))
                .foregroundColor(item.isFile ? .gray : .blue)
                .font(.system(size: 14))
            
            Text(item.fileName)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle()) // Make entire row tappable
        .padding(.vertical, 4)
        .background(selectedId == item.id ? Color.accentColor.opacity(0.2) : Color.clear) // Custom Selection Highlight
        .cornerRadius(4)
        .onTapGesture {
            selectedId = item.id
        }
        .contextMenu {
            if !item.isFile {
                 Button("选择文件") { onUpload(item) }
                 Button("新建") { onCreate(item) }
            }
            Button("重命名") { onRename(item) }
            Divider()
            Button("删除") { onDelete(item) }
        }
    }
}

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
