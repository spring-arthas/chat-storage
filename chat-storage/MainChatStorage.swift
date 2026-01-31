//
//  MainChatStorage.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/31.
//

import SwiftUI

/// 主文件管理界面
struct MainChatStorage: View {
    
    // MARK: - Environment Objects
    
    @EnvironmentObject var socketManager: SocketManager
    
    // MARK: - Bindings
    
    @Binding var isLoggedIn: Bool
    
    // MARK: - State Variables
    
    /// 服务地址
    @State private var serverAddress: String = ""
    
    /// 当前目录路径
    @State private var currentPath: String = "个人网盘" 
    
    /// 下载路径
    @State private var downloadPath: String = ""
    
    /// 文件列表
    @State private var fileList: [FileItem] = []
    
    /// 选中的文件
    @State private var selectedFiles: Set<UUID> = []
    
    /// 当前页码 (从 1 开始)
    @State private var currentPage: Int = 1
    
    /// 每页显示数量
    @State private var itemsPerPage: Int = 20
    

    /// 当前时间
    @State private var currentTime: String = ""
    
    /// 定时器
    @State private var timer: Timer?
    
    /// 当前选中的标签页 (默认进入好友列表: 0)
    @State private var selectedTab: Int = 0
    
    /// 目录树数据
    @State private var directoryTree: [DirectoryItem] = []
    
    /// 展开的目录节点 ID
    @State private var expandedDirectoryIds: Set<UUID> = []
    
    /// 当前选中的目录 ID
    @State private var selectedDirectoryId: FileItem.ID?
    
    /// 是否显示弹窗
    @State private var showingAlert = false
    
    /// 弹窗消息
    @State private var alertMessage = ""
    
    /// 是否正在加载目录
    @State private var isLoadingDirectory = false
    
    /// 目录服务
    @State private var directoryService: DirectoryService?
    
    // MARK: - Body
    
    var body: some View {
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
        .onAppear {
            startTimer()
            loadServerAddress()
            generateFakeData()
            // 初始化目录服务
            directoryService = DirectoryService(socketManager: socketManager)
        }
        .onChange(of: selectedTab) { newTab in
            // 当切换到网盘存储标签页时，加载目录
            if newTab == 1 && directoryTree.isEmpty {
                Task {
                    await loadDirectoryFromServer()
                }
            }
        }
        .onDisappear {
            stopTimer()
        }
        .alert("批量操作", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
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
            List(directoryTree, children: \.children, selection: $selectedDirectoryId) { item in
                HStack {
                    Image(systemName: item.children == nil ? "folder" : "folder.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    
                    Text(item.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.vertical, 2)
                .tag(item.id)
                .contextMenu {
                    Button("新建") {
                        addLog("在 [\(item.name)] 下新建")
                    }
                    Button("移动") {
                        addLog("移动目录 [\(item.name)]")
                    }
                    Button("重命名") {
                        addLog("重命名 [\(item.name)]")
                    }
                    Divider()
                    Button("删除") {
                        addLog("删除目录 [\(item.name)]")
                    }
                }
            }
            .listStyle(SidebarListStyle())
        }
    }
    
    // MARK: - Main Content (主内容区域)
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            // 上传控制栏
            uploadControlBar
            
            Divider()
            
            // 文件列表
            fileListView
        }
    }
    
    // MARK: - Upload Control Bar (工具栏：批量操作)
    
    private var uploadControlBar: some View {
        HStack(spacing: 12) {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - File List View (文件列表)
    
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
                
                Label("上传状态", systemImage: "icloud.and.arrow.up")
                    .frame(width: 80, alignment: .leading)
                
                Label("文件大小", systemImage: "externaldrive")
                    .frame(width: 80, alignment: .leading)
                
                Label("状态", systemImage: "waveform.path.ecg")
                    .frame(width: 60, alignment: .leading)
                
                Label("传输进度", systemImage: "timer")
                    .frame(width: 160, alignment: .leading)
                
                Text("操作")
                    .frame(width: 120, alignment: .center)
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
            
            // 分页栏
            paginationBar
        }
        .frame(minHeight: 300)
    }
    
    // MARK: - Pagination Bar (分页栏)
    
    private var paginationBar: some View {
        HStack(spacing: 16) {
            Text("共 \(fileList.count) 个文件")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    if currentPage > 1 { currentPage -= 1 }
                }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(currentPage <= 1)
                
                Text("\(currentPage) / \(max(1, (fileList.count + itemsPerPage - 1) / itemsPerPage))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Button(action: {
                    let totalPages = (fileList.count + itemsPerPage - 1) / itemsPerPage
                    if currentPage < totalPages { currentPage += 1 }
                }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(currentPage >= (fileList.count + itemsPerPage - 1) / itemsPerPage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - File Row (文件行)
    
    private func fileRow(_ file: FileItem) -> some View {
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
                Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundColor(file.isDirectory ? .blue : .gray)
                Text(file.name)
                    .font(.system(size: 11))
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            
            // 上传状态
            statusView(status: file.uploadStatus)
                .frame(width: 80, alignment: .leading)
            
            // 文件大小
            Text(file.sizeString)
                .font(.system(size: 11))
                .frame(width: 80, alignment: .leading)
            
            // 状态
            Text(file.status)
                .font(.system(size: 11))
                .foregroundColor(file.status == "正常" ? .green : .red)
                .frame(width: 60, alignment: .leading)
            
            // 传输进度 (进度条 + 速度)
            HStack(spacing: 6) {
                // 进度条
                ProgressView(value: file.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 0.8, anchor: .center)
                
                // 速度文本
                Text(file.uploadSpeed)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
            .frame(width: 160, alignment: .leading)
            
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
            .frame(width: 120, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selectedFiles.contains(file.id) ? Color.accentColor.opacity(0.1) : Color.clear)
        .onTapGesture {
            toggleSelection(file.id)
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
    
    private func toggleSelection(_ id: UUID) {
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
        // TODO: 实现刷新逻辑
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                addLog("准备上传: \(url.lastPathComponent)")
                // TODO: 实现文件上传
            }
        }
    }
    
    private func handleVoiceUpload() {
        print("语音上传")
        addLog("语音上传功能暂未实现")
        // TODO: 实现语音上传
    }
    
    private func handleFileAction(_ file: FileItem, action: Int) {
        print("文件操作: \(file.name), 操作\(action)")
        addLog("对文件 \(file.name) 执行操作\(action)")
        // TODO: 实现文件操作
    }
    
    // MARK: - Batch Operations
    
    /// 当前页显示的文件列表
    private var currentFiles: [FileItem] {
        let startIndex = (currentPage - 1) * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, fileList.count)
        if startIndex >= fileList.count { return [] }
        return Array(fileList[startIndex..<endIndex])
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
        // 如果列表已有数据，则不生成（防止刷新时覆盖，除非显式指明）
        if !fileList.isEmpty { return }
        
        let statuses = ["等待上传", "上传中", "已完成", "失败"]
        let fileTypes = ["doc", "pdf", "jpg", "mp4", "zip"]
        
        var newFiles: [FileItem] = []
        // 生成 55 条数据以测试分页
        for i in 1...55 {
            let isDir = Bool.random()
            let name = isDir ? "文件夹 \(i)" : "文件 \(i).\(fileTypes.randomElement()!)"
            let item = FileItem(
                name: name,
                isDirectory: isDir,
                size: Int64.random(in: 1024...1024*1024*500),
                uploadStatus: statuses.randomElement()!,
                status: Bool.random() ? "正常" : "异常",
                uploadSpeed: "\(Int.random(in: 0...5)) MB/s",
                progress: statuses.randomElement()! == "已完成" ? 1.0 : Double.random(in: 0.1...0.9)
            )
            // 修正进度逻辑
            var fakeProgress = 0.0
            if item.uploadStatus == "已完成" { fakeProgress = 1.0 }
            else if item.uploadStatus == "等待上传" { fakeProgress = 0.0 }
            else if item.uploadStatus == "失败" { fakeProgress = Double.random(in: 0.0...0.5) }
            else { fakeProgress = Double.random(in: 0.1...0.9) }
            
            let finalItem = FileItem(
                name: item.name,
                isDirectory: item.isDirectory,
                size: item.size,
                uploadStatus: item.uploadStatus,
                status: item.status,
                uploadSpeed: item.uploadSpeed,
                progress: fakeProgress
            )
            newFiles.append(finalItem)
        }
        fileList = newFiles
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
        HSplitView {
            // 左侧边栏
            sidebar
                .frame(minWidth: 150, idealWidth: 200)
            
            // 右侧主内容
            mainContent
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
}

// MARK: - File Item Model

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let size: Int64
    let uploadStatus: String
    let status: String
    let uploadSpeed: String
    let progress: Double // 0.0 - 1.0
    
    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Directory Item Model

struct DirectoryItem: Identifiable {
    let id = UUID()
    let name: String
    let children: [DirectoryItem]?
}
