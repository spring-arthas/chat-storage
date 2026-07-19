//
//  MainChatStorage.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/31.
//

import SwiftUI
import Combine
import AVKit
import Foundation
import AppKit
import UniformTypeIdentifiers

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static var migratedDefaultRawValue: String {
        if UserDefaults.standard.object(forKey: "appearanceMode") != nil {
            return UserDefaults.standard.string(forKey: "appearanceMode") ?? system.rawValue
        }
        return UserDefaults.standard.object(forKey: "isDarkMode") == nil
            ? system.rawValue
            : (UserDefaults.standard.bool(forKey: "isDarkMode") ? dark.rawValue : light.rawValue)
    }
}

private enum MainWorkspaceLayout {
    static let sidebarWidth: CGFloat = 244
    static let panelSpacing: CGFloat = 14
    static let contentPadding: CGFloat = 14
    static let detailMinWidth: CGFloat = 292
    static let detailIdealWidth: CGFloat = 320
    static let detailMaxWidth: CGFloat = 360
}

struct AppSettingsView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var socketManager: SocketManager
    @StateObject private var downloadDirectoryManager = DownloadDirectoryManager.shared
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.migratedDefaultRawValue
    @State private var selectedCategory: AppSettingsCategory? = .appearance
    @State private var showingServerConfig = false

    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        ZStack {
            MeshGradientBackground()

            HStack(alignment: .top, spacing: MainWorkspaceLayout.panelSpacing) {
                VStack(spacing: 0) {
                    HStack {
                        Text("设置")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(TelegramTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58)

                    Divider().overlay(TelegramTheme.textSecondary.opacity(0.12))

                    VStack(spacing: 6) {
                        ForEach(AppSettingsCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(width: 22)

                                    Text(category.title)
                                        .font(.system(size: 13, weight: .semibold))

                                    Spacer()
                                }
                                .foregroundColor(
                                    selectedCategory == category
                                        ? TelegramTheme.accent
                                        : TelegramTheme.textPrimary
                                )
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 11)
                                        .fill(
                                            selectedCategory == category
                                                ? TelegramTheme.accent.opacity(0.12)
                                                : Color.clear
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)

                    Spacer()

                    TelegramSidebarTabBar(
                        selectedTab: $selectedTab,
                        unreadCount: socketManager.unreadCounts.values.reduce(0, +)
                    )
                }
                .frame(width: MainWorkspaceLayout.sidebarWidth)
                .cloudGlassPanel()

                Group {
                    switch selectedCategory ?? .appearance {
                    case .appearance:
                        appearanceSettings
                    case .transfer:
                        transferSettings
                    case .connection:
                        connectionSettings
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(34)
                .cloudGlassPanel()
            }
            .padding(MainWorkspaceLayout.contentPadding)
        }
        .preferredColorScheme(appearanceMode.wrappedValue.colorScheme)
        .sheet(isPresented: $showingServerConfig) {
            ConfigServerView()
                .environmentObject(socketManager)
        }
    }

    private var appearanceSettings: some View {
        settingsPage(title: "外观", subtitle: "选择应用界面的显示方式") {
            Picker("主题模式", selection: appearanceMode) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            settingsStatusRow(
                icon: appearanceMode.wrappedValue.icon,
                title: "当前模式",
                detail: appearanceMode.wrappedValue.title
            )
            .padding(.top, 22)
        }
    }

    private var transferSettings: some View {
        settingsPage(title: "文件传输", subtitle: "管理文件下载后的默认保存位置") {
            Text("默认下载位置")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundColor(TelegramTheme.warning)

                Text(downloadDirectoryManager.currentDownloadPath)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(downloadDirectoryManager.currentDownloadPath)

                Spacer()

                Button("选择") {
                    downloadDirectoryManager.selectDirectory()
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))

            HStack(spacing: 16) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([downloadDirectoryManager.getDownloadDirectory()])
                } label: {
                    Label("在 Finder 中显示", systemImage: "finder")
                }

                Button {
                    downloadDirectoryManager.resetToDefaultDirectory()
                } label: {
                    Label("恢复默认位置", systemImage: "arrow.counterclockwise")
                }
            }
            .buttonStyle(.link)
            .padding(.top, 12)
        }
    }

    private var connectionSettings: some View {
        settingsPage(title: "网络连接", subtitle: "查看连接状态或切换 net-server 地址") {
            let server = socketManager.getCurrentServer()

            settingsStatusRow(
                icon: "server.rack",
                title: "当前服务器",
                detail: "\(server.0):\(server.1)"
            )

            settingsStatusRow(
                icon: socketManager.connectionState == .connected ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                title: "连接状态",
                detail: socketManager.connectionState.description
            )
            .padding(.top, 12)

            Button {
                showingServerConfig = true
            } label: {
                Label("配置服务器", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 22)
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 24, weight: .bold))

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 5)

            Divider()
                .padding(.vertical, 22)

            content()
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func settingsStatusRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(TelegramTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

enum AppSettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case transfer
    case connection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "外观"
        case .transfer: return "文件传输"
        case .connection: return "网络连接"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .transfer: return "arrow.up.arrow.down"
        case .connection: return "network"
        }
    }
}

enum TelegramTheme {
    static let appBackgroundHex = "#17212B"
    static let panelBackgroundHex = "#1F2936"
    static let elevatedBackgroundHex = "#253142"
    static let textPrimaryHex = "#EAF3FF"
    static let textSecondaryHex = "#9DB0C8"
    static let accentHex = "#2AABEE"
    static let successHex = "#4BCB8A"
    static let dangerHex = "#FF5C5C"
    static let warningHex = "#F3B15E"

    static let lightAppBackgroundHex = "#EEF3F8"
    static let lightPanelBackgroundHex = "#F7FAFD"
    static let lightElevatedBackgroundHex = "#E3EBF4"
    static let lightTextPrimaryHex = "#132338"
    static let lightTextSecondaryHex = "#51657F"
    static let lightWarningHex = "#C88A1A"

    static var appBackground: Color { Color(lightHex: lightAppBackgroundHex, darkHex: appBackgroundHex) }
    static var panelBackground: Color { Color(lightHex: lightPanelBackgroundHex, darkHex: panelBackgroundHex) }
    static var elevatedBackground: Color { Color(lightHex: lightElevatedBackgroundHex, darkHex: elevatedBackgroundHex) }
    static var textPrimary: Color { Color(lightHex: lightTextPrimaryHex, darkHex: textPrimaryHex) }
    static var textSecondary: Color { Color(lightHex: lightTextSecondaryHex, darkHex: textSecondaryHex) }
    static var accent: Color { Color(lightHex: accentHex, darkHex: accentHex) }
    static var success: Color { Color(lightHex: successHex, darkHex: successHex) }
    static var danger: Color { Color(lightHex: dangerHex, darkHex: dangerHex) }
    static var warning: Color { Color(lightHex: lightWarningHex, darkHex: warningHex) }
    static var transferHeaderText: Color { Color(lightHex: transferHeaderTextHex(isDark: false), darkHex: transferHeaderTextHex(isDark: true)) }

    static func transferHeaderTextHex(isDark: Bool = true) -> String {
        isDark ? textPrimaryHex : lightTextPrimaryHex
    }

    static func statusColorHex(for status: String, isDark: Bool = true) -> String {
        switch status {
        case "已完成":
            return successHex
        case "上传中", "下载中":
            return accentHex
        case "失败":
            return dangerHex
        case "暂停", "已暂停":
            return isDark ? warningHex : lightWarningHex
        default:
            return isDark ? textSecondaryHex : lightTextSecondaryHex
        }
    }

    static func statusColor(for status: String) -> Color {
        switch status {
        case "已完成":
            return success
        case "上传中", "下载中":
            return accent
        case "失败":
            return danger
        case "暂停", "已暂停":
            return warning
        default:
            return textSecondary
        }
    }
}

/// 云盘页面专用表面颜色。浅色模式统一使用白色，深色模式沿用现有深色层级。
private enum CloudStorageSurface {
    static var page: Color {
        Color(lightHex: "#FFFFFF", darkHex: TelegramTheme.appBackgroundHex)
    }

    static var panel: Color {
        Color(lightHex: "#FFFFFF", darkHex: TelegramTheme.panelBackgroundHex)
    }

    static var field: Color {
        Color(lightHex: "#F7F9FC", darkHex: TelegramTheme.appBackgroundHex)
    }

    static var hover: Color {
        Color(lightHex: "#F5F8FC", darkHex: TelegramTheme.elevatedBackgroundHex)
    }
}

private struct TelegramToolbarButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .imageScale(.small)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(configuration.isPressed ? 0.26 : 0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.7), lineWidth: 1)
            )
            .foregroundColor(tint)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private struct CloudPrimaryButtonStyle: ButtonStyle {
    let tint: Color
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .imageScale(.small)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(filled ? tint.opacity(configuration.isPressed ? 0.82 : 1) : TelegramTheme.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(filled ? Color.clear : TelegramTheme.textSecondary.opacity(0.18), lineWidth: 1)
            )
            .foregroundColor(filled ? .white : TelegramTheme.textPrimary)
            .shadow(color: filled ? tint.opacity(0.18) : .clear, radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private struct CloudIconButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(TelegramTheme.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(TelegramTheme.textSecondary.opacity(0.18), lineWidth: 1)
            )
            .foregroundColor(tint)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
    }
}

private struct CloudDockButton: View {
    let icon: String
    let tint: Color
    let badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(tint)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())

                if let badge, badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(TelegramTheme.danger))
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Telegram 风格的侧边栏贴底导航：无悬浮外框，三个入口等分，当前项使用底部细线强调。
private struct TelegramSidebarTabBar: View {
    @Binding var selectedTab: Int
    let unreadCount: Int

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(TelegramTheme.textSecondary.opacity(0.12))

            HStack(spacing: 0) {
                tabButton(
                    icon: "bubble.left.and.bubble.right",
                    tint: TelegramTheme.accent,
                    isSelected: selectedTab == 0,
                    badge: unreadCount,
                    help: "会话"
                ) {
                    selectedTab = 0
                }

                tabButton(
                    icon: "externaldrive",
                    tint: TelegramTheme.success,
                    isSelected: selectedTab == 1,
                    badge: 0,
                    help: "云盘"
                ) {
                    selectedTab = 1
                }

                tabButton(
                    icon: "gearshape",
                    tint: TelegramTheme.accent,
                    isSelected: selectedTab == 2,
                    badge: 0,
                    help: "设置"
                ) {
                    selectedTab = 2
                }
            }
            .frame(height: 45)
        }
        .background(TelegramTheme.panelBackground.opacity(0.96))
    }

    private func tabButton(
        icon: String,
        tint: Color,
        isSelected: Bool,
        badge: Int,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(isSelected ? tint : TelegramTheme.textSecondary.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(TelegramTheme.danger))
                        .offset(x: -18, y: 3)
                }

                if isSelected {
                    Capsule()
                        .fill(tint)
                        .frame(width: 25, height: 2.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CloudGlassPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(TelegramTheme.textSecondary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

/// 云盘主工作区使用纯色卡片，避免磨砂材质在浅色模式下形成大面积灰底。
private struct CloudStoragePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(CloudStorageSurface.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(TelegramTheme.textSecondary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.055), radius: 15, x: 0, y: 6)
    }
}

private extension View {
    func cloudGlassPanel() -> some View {
        modifier(CloudGlassPanelModifier())
    }

    func cloudStoragePanel() -> some View {
        modifier(CloudStoragePanelModifier())
    }
}

private enum TransferDisplayFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case upload = "上传"
    case download = "下载"
    case active = "进行中"
    case failed = "失败"
    case completed = "已完成"

    var id: String { rawValue }
}

private extension Color {
    init(lightHex: String, darkHex: String) {
        self.init(nsColor: NSColor.dynamicHex(light: lightHex, dark: darkHex))
    }

    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    static func dynamicHex(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

struct FileDetailLayoutMetrics {
    let previewHeight: CGFloat
    let sectionSpacing: CGFloat
    let contentPadding: CGFloat
    let actionButtonHeight: CGFloat
    let titleFontSize: CGFloat

    init(availableHeight: CGFloat, availableWidth: CGFloat) {
        let compactHeight = availableHeight < 720
        let compactWidth = availableWidth < 340
        let compact = compactHeight || compactWidth
        previewHeight = compact ? 112 : min(176, availableHeight * 0.22)
        sectionSpacing = compact ? 9 : 14
        contentPadding = compact ? 10 : 14
        actionButtonHeight = compact ? 34 : 38
        titleFontSize = compact ? 14 : 16
    }
}

private struct FileDetailPresentation {
    let item: DirectoryItem
    let fileName: String
    let size: String
    let fileType: String
    let uploadTime: String
    let directoryName: String
    let iconName: String

    init(item: DirectoryItem, detail: FileDto?) {
        let resolvedDetail = detail?.id == item.id ? detail : nil
        let resolvedItem = resolvedDetail?.toDirectoryItem() ?? item
        let fileExtension = (resolvedItem.fileName as NSString).pathExtension.uppercased()

        self.item = resolvedItem
        self.fileName = resolvedDetail?.fileName ?? resolvedItem.fileName
        self.size = resolvedDetail?.sizeString ?? resolvedItem.sizeString
        if let detailType = resolvedDetail?.fileType, !detailType.isEmpty {
            self.fileType = detailType.uppercased()
        } else {
            self.fileType = fileExtension.isEmpty ? "-" : fileExtension
        }
        self.uploadTime = resolvedDetail?.uploadTime ?? resolvedItem.uploadTimeString
        self.directoryName = resolvedDetail?.directoryName
            ?? resolvedItem.directoryName
            ?? "-"
        self.iconName = resolvedDetail?.iconName ?? resolvedItem.iconName
    }
}

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

    /// 合并短时间内连续上传完成事件的延迟刷新任务
    @State private var uploadCompletionRefreshTask: Task<Void, Never>?
    
    /// 传输任务列表 (上传/下载)
    @State private var transferList: [TransferItem] = []
    @State private var isTransferCenterExpanded = false
    @State private var transferDisplayFilter: TransferDisplayFilter = .all
    @State private var transferSearchText = ""
    
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

    /// 是否正在执行目录树与文件列表的联合刷新
    @State private var isRefreshingCloudData = false
    
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

    // MARK: - Rename File State

    /// 是否显示文件重命名弹窗
    @State private var showingFileRenameDialog = false
    @State private var fileRenameTargetId: Int64?
    @State private var fileRenameValue = ""
    @State private var isFileRenaming = false

    // Video Playing State
    // @State private var playingVideoFile: DirectoryItem? // Removed, now using VideoWindowManager
    
    /// 是否显示删除确认弹窗
    @State private var showingDeleteAlert = false
    @State private var deleteTargetId: Int64?
    @State private var deleteTargetName = ""
    @State private var isDeleting = false

    /// 批量上传选择器状态
    @State private var showingBatchUpload = false

    /// 是否开启自动排序
    @State private var isAutoSortEnabled = true
    
    /// 传输列表面板高度：收起时只显示摘要，展开后显示完整任务中心
    private let collapsedTransferPanelHeight: CGFloat = 58
    private let expandedTransferPanelHeight: CGFloat = 360

    /// 主题模式状态 (持久化)
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.migratedDefaultRawValue
    
    // MARK: - Detail View State
    @State private var selectedFileId: Int64?
    @State private var fileDetail: FileDto?
    @State private var isLoadingDetail = false
    @State private var selectedDetailItem: DirectoryItem?
    @State private var detailPreviewImage: NSImage?
    @State private var isLoadingDetailPreview = false
    @State private var detailLoadTask: Task<Void, Never>?
    @State private var detailPreviewTask: Task<Void, Never>?
    
    // MARK: - Cloud Storage UI Innovation & Theme
    /// 视图模式: 0 = 列表, 1 = 网格 (Cloud Hub Grid)
    @State private var storageViewMode: Int = 0
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
                topToolbar

                Divider()
                    .overlay(TelegramTheme.textSecondary.opacity(0.12))

                Group {
                    switch selectedTab {
                    case 0:
                        FriendChatSplitView(selectedTab: $selectedTab)
                    case 1:
                        storageView
                    default:
                        AppSettingsView(selectedTab: $selectedTab)
                            .environmentObject(socketManager)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(TelegramTheme.appBackground)
            .tint(TelegramTheme.accent)
            .disabled(showingCreateDirDialog || showingRenameDialog || isDeleting) // 弹窗或删除时禁用主界面交互
            
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

            // 重命名文件弹窗
            if showingFileRenameDialog {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {}

                renameFileUiDialog
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
        .onReceive(NotificationCenter.default.publisher(for: .uploadTaskDidComplete)) { _ in
            scheduleFileListRefreshAfterUpload()
        }
        .onDisappear {
            uploadCompletionRefreshTask?.cancel()
            uploadCompletionRefreshTask = nil
            detailLoadTask?.cancel()
            detailPreviewTask?.cancel()
            stopTimer()
        }
        .alert("提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("删除目录", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {
                deleteTargetId = nil
                deleteTargetName = ""
            }
            Button("删除", role: .destructive) {
                handleDeleteDirectory()
            }
        } message: {
            Text("确定删除目录“\(deleteTargetName)”吗？如果该目录或子目录中存在有效文件，系统将拒绝删除。")
        }
        // 应用主题设置
        .preferredColorScheme(AppAppearanceMode(rawValue: appearanceModeRaw)?.colorScheme)
        .transaction { tx in
            tx.animation = nil
        }
    }


    
    // MARK: - Top Toolbar (顶部工具栏)

    private var toolbarAvatar: String? {
        if let avatar = socketManager.myAvatar, !avatar.isEmpty {
            return avatar
        }
        return authService.currentUser?.avatar
    }
    
    private var topToolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Group {
                    if let avatar = toolbarAvatar, !avatar.isEmpty {
                        AvatarDecodeView(
                            base64: avatar,
                            fallbacName: String(authService.currentUser?.username.prefix(1) ?? "用"),
                            fallbackColor: TelegramTheme.success,
                            cache: ChatAvatarCache.shared,
                            customSize: 34
                        )
                    } else {
                        Text(String(authService.currentUser?.username.prefix(1) ?? "用"))
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(TelegramTheme.success.opacity(0.95)))
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())

                Text("下午好，\(authService.currentUser?.username ?? "朋友")")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(TelegramTheme.textPrimary)
            }

            Spacer()
            
            // 当前时间
            Label(currentTime, systemImage: "clock")
                .font(.system(size: 12))
                .foregroundColor(TelegramTheme.textSecondary)

            // 退出按钮 (移到最右侧)
            Button(action: {
                handleLogout()
            }) {
                Image(systemName: "power.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(TelegramTheme.danger)
            }
            .buttonStyle(.borderless)
            .help("退出登录")
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
        .background(TelegramTheme.panelBackground)
    }

    // MARK: - Sidebar (左侧边栏)
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Text("目录")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TelegramTheme.textPrimary)

                    Spacer()

                    Button(action: {
                        self.createDirParentId = selectedDirectoryId ?? directoryTree.first?.id ?? 0
                        self.newDirName = ""
                        self.showingCreateDirDialog = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.success))
                    .help("新建目录")
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(TelegramTheme.textSecondary.opacity(0.72))
                    Text("搜索目录")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TelegramTheme.textSecondary.opacity(0.72))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(CloudStorageSurface.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TelegramTheme.textSecondary.opacity(0.16), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)

            directoryTreeContent

            TelegramSidebarTabBar(
                selectedTab: $selectedTab,
                unreadCount: socketManager.unreadCounts.values.reduce(0, +)
            )
        }
        .background(CloudStorageSurface.panel)
    }

    private var directoryTreeContent: some View {
        Group {
            if isLoadingDirectory {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                        .tint(TelegramTheme.success)
                    Text("加载中...")
                        .font(.system(size: 12))
                        .foregroundColor(TelegramTheme.textSecondary)
                    Spacer()
                }
            } else if directoryTree.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 30))
                        .foregroundColor(TelegramTheme.textSecondary.opacity(0.45))
                    Text("暂无目录")
                        .font(.system(size: 12))
                        .foregroundColor(TelegramTheme.textSecondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
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
                            },
                            onExpand: { item in
                                Task { await loadDirectoryChildrenIfNeeded(item) }
                            }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Main Content (主内容区域)
    

    
    private var mainContent: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    cloudHeaderBar

                    VStack(spacing: 0) {
                        uploadControlBar
                            .background(CloudStorageSurface.panel)

                        Divider()
                            .overlay(TelegramTheme.textSecondary.opacity(0.12))

                        ZStack {
                            if storageViewMode == 0 {
                                fileListView
                            } else {
                                CloudGridView(
                                    items: currentFiles,
                                    selectedFiles: $selectedFiles,
                                    selectedFileId: $selectedFileId,
                                    onFileTapped: { file in
                                        self.selectedFileId = file.id
                                        loadFileDetail(fileId: file.id, item: file)
                                    },
                                    onFileDoubleTapped: { file in
                                        if !file.isFile {
                                            handleEnterDirectory(file)
                                        } else if file.isPlayableVideoFile {
                                            VideoWindowManager.shared.show(fileId: file.id, fileName: file.fileName, fileSize: file.fileSize ?? 0)
                                        }
                                    },
                                    onAction: { file, action in
                                        handleFileAction(file, action: action)
                                    },
                                    onPlay: { file in
                                        VideoWindowManager.shared.show(fileId: file.id, fileName: file.fileName, fileSize: file.fileSize ?? 0)
                                    }
                                )
                            }
                        }

                        Divider()
                            .overlay(TelegramTheme.textSecondary.opacity(0.12))

                        paginationBar
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    transferListView
                        .frame(maxWidth: .infinity)
                        .frame(height: isTransferCenterExpanded ? expandedTransferPanelHeight : collapsedTransferPanelHeight)
                        .background(CloudStorageSurface.panel)
                        .transaction { tx in
                            tx.animation = nil
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CloudStorageSurface.panel)
                .transaction { tx in
                    // 云盘区禁用隐式动画，避免登录后状态刷新导致上下抖动
                    tx.animation = nil
                }
            }
            .clipped()
        }
    }

    private var currentDirectoryTitle: String {
        if let selectedDirectoryId,
           let item = findDirectoryItem(id: selectedDirectoryId, nodes: directoryTree) {
            return item.fileName
        }
        return directoryTree.first?.fileName ?? "全部文件"
    }

    private var currentBreadcrumb: String {
        let rootName = directoryTree.first?.fileName ?? authService.currentUser?.username ?? "个人网盘"
        if currentDirectoryTitle == rootName {
            return rootName
        }
        return "\(rootName) / \(currentDirectoryTitle)"
    }

    private var cloudHeaderBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                cloudHeaderIdentity
                Spacer(minLength: 16)
                cloudHeaderActions
            }

            VStack(alignment: .leading, spacing: 10) {
                cloudHeaderIdentity
                cloudHeaderActions
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 78)
        .background(CloudStorageSurface.panel)
        .overlay(alignment: .bottom) {
            Divider().overlay(TelegramTheme.textSecondary.opacity(0.12))
        }
    }

    private var cloudHeaderIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(currentBreadcrumb)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TelegramTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 10) {
                Text(currentDirectoryTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(totalCount) 个文件")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 25)
                    .background(Capsule().fill(TelegramTheme.elevatedBackground.opacity(0.62)))
            }
        }
    }

    private var cloudHeaderActions: some View {
        HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TelegramTheme.textSecondary.opacity(0.72))
                    TextField("搜索文件名称", text: $searchKeyword)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit { handleSearch() }
                }
                .padding(.horizontal, 12)
                .frame(minWidth: 150, idealWidth: 220, maxWidth: 260, minHeight: 36, maxHeight: 36)
                .background(CloudStorageSurface.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TelegramTheme.textSecondary.opacity(0.16), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(action: {
                    handleSelectFiles(targetDirectory: selectedDirectoryId.flatMap { findDirectoryItem(id: $0, nodes: directoryTree) })
                }) {
                    Image(systemName: "icloud.and.arrow.up")
                        .accessibilityHidden(true)
                }
                .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.success))
                .help("上传文件到当前目录")
                .accessibilityLabel("上传文件")
                .accessibilityHint("选择文件并上传到当前目录")

                Button(action: {
                    self.createDirParentId = selectedDirectoryId ?? directoryTree.first?.id ?? 0
                    self.newDirName = ""
                    self.showingCreateDirDialog = true
                }) {
                    Image(systemName: "folder.badge.plus")
                        .accessibilityHidden(true)
                }
                .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.success))
                .help("在当前目录中新建文件夹")
                .accessibilityLabel("新建目录")
                .accessibilityHint("在当前选中的目录中新建文件夹")

                Button(action: {
                    handleRefresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                }
                .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.textSecondary))
                .help("刷新目录和文件列表")
                .accessibilityLabel("刷新云盘")
                .accessibilityHint("依次刷新目录树和当前目录的文件列表")
                .disabled(isRefreshingCloudData || isLoadingDirectory)
        }
    }
    
    // MARK: - Upload Control Bar (工具栏：批量操作)
    
    // MARK: - Upload Control Bar (工具栏：批量操作 + 搜索)
    
    private var uploadControlBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                handleBatchDelete()
            }) {
                Label("批量删除", systemImage: "trash")
            }
            .buttonStyle(CloudPrimaryButtonStyle(tint: selectedFiles.isEmpty ? TelegramTheme.textSecondary : TelegramTheme.danger))
            .disabled(selectedFiles.isEmpty)

            Button(action: {
                handleBatchDownload()
            }) {
                Label("批量下载", systemImage: "arrow.down.circle")
            }
            .buttonStyle(CloudPrimaryButtonStyle(tint: selectedFiles.isEmpty ? TelegramTheme.textSecondary : TelegramTheme.accent))
            .disabled(selectedFiles.isEmpty)

            Button(action: {
                handleRefresh()
            }) {
                Image(systemName: "arrow.clockwise")
                    .accessibilityHidden(true)
            }
            .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.textSecondary))
            .help("刷新目录和文件列表")
            .accessibilityLabel("刷新云盘")
            .accessibilityHint("依次刷新目录树和当前目录的文件列表")
            .disabled(isRefreshingCloudData || isLoadingDirectory)

            Spacer()

            HStack(spacing: 4) {
                Button(action: { storageViewMode = 0 }) {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(CloudIconButtonStyle(tint: storageViewMode == 0 ? TelegramTheme.success : TelegramTheme.textSecondary))

                Button(action: { storageViewMode = 1 }) {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(CloudIconButtonStyle(tint: storageViewMode == 1 ? TelegramTheme.success : TelegramTheme.textSecondary))
            }
            .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(CloudStorageSurface.panel)
    }

    // MARK: - File List View (文件列表 - 浏览)
    
    private var fileListView: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 620
            let showDirectory = proxy.size.width >= 560
            let showUploadTime = proxy.size.width >= 620

            VStack(spacing: 0) {
                if currentFiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(TelegramTheme.textSecondary.opacity(0.55))

                        Text("暂无文件")
                            .font(.system(size: 14))
                            .foregroundColor(TelegramTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                    .background(CloudStorageSurface.panel)
                } else {
                    // 紧凑宽度隐藏低优先级列，优先保证文件名和操作按钮完整可见。
                    HStack(spacing: isCompact ? 8 : FileListColumnLayout.spacing) {
                        Toggle("", isOn: Binding(
                            get: { isAllSelected },
                            set: { _ in toggleAllSelection() }
                        ))
                        .toggleStyle(.checkbox)
                        .frame(width: FileListColumnLayout.checkboxWidth, alignment: .center)

                        Color.clear
                            .frame(width: FileListColumnLayout.iconWidth, height: 1)

                        fileListHeaderLabel("文件名称", icon: "doc")
                            .frame(
                                minWidth: FileListColumnLayout.nameMinWidth,
                                maxWidth: .infinity,
                                alignment: .leading
                            )

                        fileListHeaderLabel("文件大小", icon: "externaldrive")
                            .frame(width: FileListColumnLayout.sizeWidth, alignment: .leading)

                        if showDirectory {
                            fileListHeaderLabel("所属目录", icon: "folder")
                                .frame(width: FileListColumnLayout.directoryWidth, alignment: .leading)
                        }

                        if showUploadTime {
                            fileListHeaderLabel("上传时间", icon: "clock")
                                .frame(width: FileListColumnLayout.timeWidth, alignment: .leading)
                        }

                        fileListHeaderLabel("操作", icon: nil)
                            .frame(width: FileListColumnLayout.actionWidth, alignment: .center)
                    }
                    .padding(.horizontal, isCompact ? 10 : FileListColumnLayout.horizontalPadding)
                    .padding(.vertical, 8)
                    .background(CloudStorageSurface.panel)
                    .overlay(
                        VStack(spacing: 0) {
                            Color.clear
                            Divider().opacity(0.45)
                        }
                        .allowsHitTesting(false)
                    )

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(currentFiles) { file in
                                fileRow(
                                    file,
                                    isCompact: isCompact,
                                    showDirectory: showDirectory,
                                    showUploadTime: showUploadTime
                                )
                                Divider()
                            }
                        }
                    }
                    .background(CloudStorageSurface.panel)
                }
            }
        }
    }

    private func fileListHeaderLabel(_ title: String, icon: String?) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TelegramTheme.transferHeaderText)
            }

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(TelegramTheme.textPrimary)
                .lineLimit(1)
        }
    }
    
    // MARK: - Pagination Bar (分页栏)
    
    private var paginationBar: some View {
        HStack(spacing: 16) {
            Text("共 \(totalCount) 个文件")
                .font(.system(size: 11))
                .foregroundColor(TelegramTheme.textSecondary)
            
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
                    .foregroundColor(TelegramTheme.textSecondary)
                
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
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 32)
        .background(CloudStorageSurface.panel)
    }

    // MARK: - File Row (文件行 - 浏览)
    
    private func fileRow(
        _ file: DirectoryItem,
        isCompact: Bool,
        showDirectory: Bool,
        showUploadTime: Bool
    ) -> some View {
        FileListRowView(
            file: file,
            isCompact: isCompact,
            showDirectory: showDirectory,
            showUploadTime: showUploadTime,
            isSelected: selectedFileId == file.id,
            isChecked: selectedFiles.contains(file.id),
            onToggle: { toggleSelection(file.id) },
            onTap: {
                self.selectedFileId = file.id
                loadFileDetail(fileId: file.id, item: file)
            },
            onPlay: {
                VideoWindowManager.shared.show(fileId: file.id, fileName: file.fileName, fileSize: file.fileSize ?? 0)
            },
            onRename: {
                fileRenameTargetId = file.id
                fileRenameValue = file.fileName
                showingFileRenameDialog = true
            },
            onDownload: { handleFileAction(file, action: 2) },
            onDelete: { handleFileAction(file, action: 1) }
        )
    }

    
    // MARK: - Transfer List View (文件传输区) 传输列表UI以及相关逻辑
    private var transferListView: some View {
        VStack(spacing: 0) {
            transferHeaderBar

            if isTransferCenterExpanded {
                Divider().overlay(TelegramTheme.textSecondary.opacity(0.12))
                transferFilterBar
                Divider().overlay(TelegramTheme.textSecondary.opacity(0.12))
                transferExpandedContent
            }
        }
        .overlay(alignment: .top) {
            Divider().overlay(TelegramTheme.textSecondary.opacity(0.12))
        }
    }

    private var transferHeaderBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                transferHeaderIdentity
                    .layoutPriority(1)

                Spacer(minLength: 12)

                if !isTransferCenterExpanded {
                    ProgressView(value: activeTransferProgress)
                        .progressViewStyle(.linear)
                        .tint(TelegramTheme.success)
                        .frame(width: 180)
                }

                transferExpandButton
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)

            HStack(spacing: 10) {
                transferHeaderIdentity
                    .layoutPriority(1)
                Spacer(minLength: 8)
                transferExpandButton
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
        }
        .background(CloudStorageSurface.panel)
    }

    private var transferHeaderIdentity: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(TelegramTheme.success)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(TelegramTheme.success.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("传输中心")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TelegramTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text("\(transferList.count) 个任务")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(TelegramTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(TelegramTheme.elevatedBackground.opacity(0.72)))
                }

                Text(transferSummaryText)
                    .font(.system(size: 12))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var transferBatchControls: some View {
        HStack(spacing: 8) {
            Button(action: handleBatchCancel) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.danger))
            .disabled(!hasCancellableTransferItems)
            .opacity(hasCancellableTransferItems ? 1 : 0.42)
            .help("全部取消")
            .accessibilityLabel("全部取消")

            Button(action: clearCompletedTransferItems) {
                Image(systemName: "trash.fill")
            }
            .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.textSecondary))
            .disabled(!hasCompletedTransferItems)
            .opacity(hasCompletedTransferItems ? 1 : 0.42)
            .help("清除已完成")
            .accessibilityLabel("清除已完成")

            Toggle("自动排序", isOn: $isAutoSortEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .lineLimit(1)
                .fixedSize()
                .onChange(of: isAutoSortEnabled) { enabled in
                    if enabled { sortTransferList() }
                }
        }
    }

    private var transferExpandButton: some View {
        Button(action: {
            isTransferCenterExpanded.toggle()
        }) {
            HStack(spacing: 6) {
                Text(isTransferCenterExpanded ? "收起" : "展开")
                Image(systemName: isTransferCenterExpanded ? "chevron.down" : "chevron.up")
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(CloudPrimaryButtonStyle(tint: TelegramTheme.textSecondary))
    }

    private var transferFilterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    transferFilterButtons(horizontalPadding: 9, spacing: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                transferBatchControls
                    .fixedSize(horizontal: true, vertical: false)
            }

            transferSearchField
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CloudStorageSurface.panel)
    }

    private func transferFilterButtons(horizontalPadding: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(TransferDisplayFilter.allCases) { filter in
                Button(action: { transferDisplayFilter = filter }) {
                    Text("\(filter.rawValue) \(transferCount(for: filter))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(transferDisplayFilter == filter ? TelegramTheme.success : TelegramTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, horizontalPadding)
                        .frame(height: 32)
                        .background(
                            Capsule()
                                .fill(transferDisplayFilter == filter ? TelegramTheme.success.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(TelegramTheme.textSecondary.opacity(0.16), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var transferSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(TelegramTheme.textSecondary.opacity(0.72))
            TextField("搜索任务", text: $transferSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(CloudStorageSurface.field)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(TelegramTheme.textSecondary.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var transferExpandedContent: some View {
        GeometryReader { geometry in
            let metrics = TransferColumnMetrics(availableWidth: geometry.size.width)

            VStack(spacing: 0) {
                TransferTableHeaderView(metrics: metrics)

                if filteredTransferItems.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "arrow.up.arrow.down.square")
                            .font(.system(size: 34))
                            .foregroundColor(TelegramTheme.textSecondary.opacity(0.45))
                        Text("无传输任务")
                            .font(.system(size: 13))
                            .foregroundColor(TelegramTheme.textSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CloudStorageSurface.panel)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredTransferItems.enumerated()), id: \.element.id) { index, item in
                                transferRow(item, index: index + 1, metrics: metrics)
                                Divider()
                                    .padding(.horizontal, metrics.horizontalPadding)
                                    .overlay(TelegramTheme.textSecondary.opacity(0.08))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(CloudStorageSurface.panel)
                }
            }
        }
    }

    private var filteredTransferItems: [TransferItem] {
        let keyword = transferSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return transferList.filter { item in
            let matchesFilter: Bool
            switch transferDisplayFilter {
            case .all:
                matchesFilter = true
            case .upload:
                matchesFilter = item.taskType == .upload
            case .download:
                matchesFilter = item.taskType == .download
            case .active:
                matchesFilter = item.status == "上传中" || item.status == "下载中" || item.status == "等待上传" || item.status == "等待下载"
            case .failed:
                matchesFilter = item.status == "失败"
            case .completed:
                matchesFilter = item.status == "已完成" || item.status == "Completed"
            }

            guard matchesFilter else { return false }
            guard !keyword.isEmpty else { return true }
            return item.name.lowercased().contains(keyword)
                || item.directoryName.lowercased().contains(keyword)
                || item.status.lowercased().contains(keyword)
        }
    }

    private var transferSummaryText: String {
        guard !transferList.isEmpty else { return "暂无传输任务" }
        if let active = transferList.first(where: { $0.status == "上传中" || $0.status == "下载中" }) {
            return "\(active.name) \(active.status) · \(active.progressPercent)"
        }
        let failedCount = transferList.filter { $0.status == "失败" }.count
        if failedCount > 0 {
            return "\(failedCount) 个任务失败，可展开处理"
        }
        let completedCount = transferList.filter { $0.status == "已完成" || $0.status == "Completed" }.count
        return "已完成 \(completedCount) 个，剩余 \(max(transferList.count - completedCount, 0)) 个"
    }

    private var activeTransferProgress: Double {
        guard let active = transferList.first(where: { $0.status == "上传中" || $0.status == "下载中" }) else {
            return transferList.isEmpty ? 0 : 1
        }
        return active.progress
    }

    private func transferCount(for filter: TransferDisplayFilter) -> Int {
        switch filter {
        case .all:
            return transferList.count
        case .upload:
            return transferList.filter { $0.taskType == .upload }.count
        case .download:
            return transferList.filter { $0.taskType == .download }.count
        case .active:
            return transferList.filter { $0.status == "上传中" || $0.status == "下载中" || $0.status == "等待上传" || $0.status == "等待下载" }.count
        case .failed:
            return transferList.filter { $0.status == "失败" }.count
        case .completed:
            return transferList.filter { $0.status == "已完成" || $0.status == "Completed" }.count
        }
    }

    private var hasCancellableTransferItems: Bool {
        transferList.contains { item in
            item.status != "已完成" && item.status != "Completed"
        }
    }

    private var hasCompletedTransferItems: Bool {
        transferList.contains { item in
            item.status == "已完成" || item.status == "Completed"
        }
    }

    private func handleBatchCancel() {
        let itemsToCancel = transferList.filter { item in
            item.status != "已完成" && item.status != "Completed"
        }
        guard !itemsToCancel.isEmpty else { return }

        let cancelledIds = Set(itemsToCancel.map(\.id))
        for item in itemsToCancel {
            transferManager.cancel(id: item.id)
        }
        transferList.removeAll { cancelledIds.contains($0.id) }
        addLog("已取消 \(itemsToCancel.count) 个未完成传输任务")
    }

    private func clearCompletedTransferItems() {
        transferManager.clearCompletedTasks()
        let beforeCount = transferList.count
        transferList.removeAll { $0.status == "已完成" || $0.status == "Completed" }
        let removedCount = beforeCount - transferList.count
        print("✅ [UI] 已移除 \(removedCount) 个已完成任务")
        if isAutoSortEnabled {
            sortTransferList()
        }
    }
    // 文件传输列表一行记录的状态
    private func transferRow(_ item: TransferItem, index: Int, metrics: TransferColumnMetrics) -> some View {
        TransferListRowView(
            item: item,
            index: index,
            metrics: metrics,
            onStart:  { handleTransferAction(id: item.id, action: "start") },
            onPause:  { handleTransferAction(id: item.id, action: "pause") },
            onCancel: { handleTransferAction(id: item.id, action: "cancel") }
        )
    }

    
    private func statusColorForTransfer(_ status: String) -> Color {
        TelegramTheme.statusColor(for: status)
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
        guard !isRefreshingCloudData else { return }
        Task { @MainActor in
            await refreshCloudDriveData()
        }
    }

    @MainActor
    private func refreshCloudDriveData() async {
        guard !isRefreshingCloudData else { return }
        isRefreshingCloudData = true
        defer { isRefreshingCloudData = false }

        print("刷新目录树和文件列表")
        addLog("开始刷新目录树和文件列表...")
        await loadDirectoryFromServer()
        await loadCurrentFilesFromServer()
        addLog("目录树和文件列表刷新完成")
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

            let currentUserId = Int64(authService.currentUser?.id ?? 0)
            let currentUserName = String(authService.currentUser?.username ?? "default")
            for item in newItems {
                guard let fileUrl = item.fileUrl else { continue }
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
                print("🛠️ [UI] Auto submitting upload task: \(task.name) - ID: \(task.id)")
                transferManager.submit(task: task)
            }
            
            let dirInfo = targetDirectory != nil ? " -> [\(targetDirectory!.fileName)]" : ""
            addLog("用户选择了 \(urls.count) 个文件\(dirInfo)，已提交到传输队列")
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
                        selectedFiles.remove(file.id)
                        if selectedFileId == file.id {
                            clearFileDetailSelection()
                        }
                        fileList.removeAll { $0.id == file.id }
                        totalCount = max(0, totalCount - 1)
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
        } else if action == 3 {
            // 重命名操作
            fileRenameTargetId = file.id
            fileRenameValue = file.fileName
            showingFileRenameDialog = true
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
                let deletedIds = Set(filesToDelete.map { $0.id })
                fileList.removeAll { deletedIds.contains($0.id) }
                if let selectedId = selectedFileId, deletedIds.contains(selectedId) {
                    clearFileDetailSelection()
                }
                totalCount = max(0, totalCount - Int64(successCount))
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
        defer { isLoadingDirectory = false }
        addLog("开始加载目录树...")
        
        do {
            let items = try await service.loadDirectoryTree()

            self.directoryTree = items
            // 仅在首次加载（无展开项）时执行默认展开，否则保留用户当前的展开状态
            if self.expandedDirectoryIds.isEmpty {
               self.expandDefaultLevels(items: items) // 默认展开两层
            }
            addLog("目录树加载成功，共 \(items.count) 个顶级项")
        } catch {
            addLog("目录树加载失败: \(error.localizedDescription)")
            print("❌ 加载目录失败: \(error)")
        }
    }

    @MainActor
    private func loadDirectoryChildrenIfNeeded(_ item: DirectoryItem) async {
        guard item.hasChild, item.childFileList?.isEmpty ?? true else { return }
        guard let service = directoryService else {
            print("⚠️ DirectoryService 未初始化")
            return
        }

        do {
            let children = try await service.loadDirectoryChildren(dirId: item.id)
            self.directoryTree = updateDirectoryChildren(nodes: self.directoryTree, id: item.id, children: children)
            self.expandedDirectoryIds.insert(item.id)
            addLog("子目录加载成功: \(item.fileName)，共 \(children.count) 项")
        } catch {
            addLog("子目录加载失败: \(item.fileName) - \(error.localizedDescription)")
            print("❌ 加载子目录失败: id=\(item.id), name=\(item.fileName), error=\(error)")
        }
    }

    private func updateDirectoryChildren(nodes: [DirectoryItem], id: Int64, children: [DirectoryItem]) -> [DirectoryItem] {
        nodes.map { node in
            if node.id == id {
                return DirectoryItem(
                    id: node.id,
                    pId: node.pId,
                    fileName: node.fileName,
                    childFileList: children,
                    hasChild: !children.isEmpty || node.hasChild,
                    fileSize: node.fileSize,
                    isFile: node.isFile,
                    uploadTime: node.uploadTime,
                    directoryName: node.directoryName
                )
            }

            guard let nodeChildren = node.childFileList else {
                return node
            }

            return DirectoryItem(
                id: node.id,
                pId: node.pId,
                fileName: node.fileName,
                childFileList: updateDirectoryChildren(nodes: nodeChildren, id: id, children: children),
                hasChild: node.hasChild,
                fileSize: node.fileSize,
                isFile: node.isFile,
                uploadTime: node.uploadTime,
                directoryName: node.directoryName
            )
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
        GeometryReader { proxy in
            let detailWidth = min(
                MainWorkspaceLayout.detailMaxWidth,
                max(MainWorkspaceLayout.detailMinWidth, proxy.size.width * 0.25)
            )

            ZStack {
                CloudStorageSurface.page
                    .ignoresSafeArea()

                HStack(alignment: .top, spacing: MainWorkspaceLayout.panelSpacing) {
                    sidebar
                        .frame(width: MainWorkspaceLayout.sidebarWidth)
                        .frame(maxHeight: .infinity)
                        .cloudStoragePanel()

                    mainContent
                        .frame(
                            minWidth: 540,
                            idealWidth: 760,
                            maxWidth: .infinity
                        )
                        .frame(maxHeight: .infinity)
                        .cloudStoragePanel()
                        .layoutPriority(1)

                    detailSidebar
                        .frame(width: detailWidth)
                        .frame(maxHeight: .infinity)
                        .cloudStoragePanel()
                }
                .padding(MainWorkspaceLayout.contentPadding)
            }
        }
        .transaction { tx in
            tx.animation = nil
        }
    }
    
    // MARK: - File Detail Sidebar

    private var activeDetailPresentation: FileDetailPresentation? {
        guard let selectedFileId else { return nil }
        let item = selectedDetailItem?.id == selectedFileId
            ? selectedDetailItem
            : fileDetail?.id == selectedFileId ? fileDetail?.toDirectoryItem() : nil
        guard let item else { return nil }
        return FileDetailPresentation(item: item, detail: fileDetail)
    }
    
    private var detailSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("文件详情")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(TelegramTheme.textPrimary)
                Spacer()
                if isLoadingDetail {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Divider().opacity(0.1)
            
            if let presentation = activeDetailPresentation {
                GeometryReader { proxy in
                    let metrics = FileDetailLayoutMetrics(
                        availableHeight: proxy.size.height,
                        availableWidth: proxy.size.width
                    )
                    detailContent(
                        presentation: presentation,
                        metrics: metrics,
                        availableWidth: proxy.size.width
                    )
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(TelegramTheme.textSecondary.opacity(0.35))
                    Text("选择文件查看详情")
                        .font(.system(size: 14))
                        .foregroundColor(TelegramTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.clear)
    }

    private func detailContent(
        presentation: FileDetailPresentation,
        metrics: FileDetailLayoutMetrics,
        availableWidth: CGFloat
    ) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: metrics.sectionSpacing) {
                detailPreview(presentation: presentation, metrics: metrics)

                Text(presentation.fileName)
                    .font(.system(size: metrics.titleFontSize, weight: .bold))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(availableWidth < 340 ? 3 : 2)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(presentation.fileName)

                VStack(spacing: 0) {
                    DetailRow(label: "文件大小", value: presentation.size)
                    Divider().opacity(0.08)
                    DetailRow(label: "文件类型", value: presentation.fileType)
                    Divider().opacity(0.08)
                    DetailRow(label: "上传时间", value: presentation.uploadTime)
                    Divider().opacity(0.08)
                    DetailRow(label: "存储目录", value: presentation.directoryName)
                }
                .padding(.horizontal, 12)
                .background(CloudStorageSurface.field)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                detailActions(
                    presentation: presentation,
                    metrics: metrics,
                    availableWidth: availableWidth
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(metrics.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func detailPreview(
        presentation: FileDetailPresentation,
        metrics: FileDetailLayoutMetrics
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(CloudStorageSurface.field)

            if let detailPreviewImage {
                Image(nsImage: detailPreviewImage)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Image(systemName: presentation.iconName)
                    .font(.system(size: metrics.previewHeight * 0.38))
                    .foregroundColor(TelegramTheme.accent)
                    .symbolRenderingMode(.hierarchical)
            }

            if isLoadingDetailPreview {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }

            if presentation.item.isVideoFile, detailPreviewImage != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.45), radius: 3)
                            .padding(10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minWidth: 0)
        .frame(height: metrics.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailActions(
        presentation: FileDetailPresentation,
        metrics: FileDetailLayoutMetrics,
        availableWidth: CGFloat
    ) -> some View {
        LazyVGrid(
            columns: availableWidth < 350
                ? [GridItem(.flexible(minimum: 0))]
                : [GridItem(.flexible(minimum: 0), spacing: 10), GridItem(.flexible(minimum: 0))],
            spacing: 10
        ) {
            if presentation.item.isPlayableVideoFile {
                Button {
                    VideoWindowManager.shared.show(
                        fileId: presentation.item.id,
                        fileName: presentation.item.fileName,
                        fileSize: presentation.item.fileSize ?? 0
                    )
                } label: {
                    Label("在线播放", systemImage: "play.circle.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.actionButtonHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(TelegramTheme.success)
            }

            Button {
                submitDownloadTask(for: presentation.item)
            } label: {
                Label("立即下载", systemImage: "arrow.down.circle.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.actionButtonHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(TelegramTheme.accent)

            Button {
                fileRenameTargetId = presentation.item.id
                fileRenameValue = presentation.fileName
                showingFileRenameDialog = true
            } label: {
                Label("重命名", systemImage: "pencil")
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.actionButtonHeight)
            }
            .buttonStyle(.bordered)

            Button {
                handleFileAction(presentation.item, action: 1)
            } label: {
                Label("删除文件", systemImage: "trash")
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.actionButtonHeight)
            }
            .buttonStyle(.bordered)
            .tint(TelegramTheme.danger)
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
                    .foregroundColor(TelegramTheme.textSecondary)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(value)
            }
            .frame(height: 30)
            .frame(minWidth: 0, maxWidth: .infinity)
        }
    }

    
    // MARK: - Helper Views
    
    private func statusView(status: String) -> some View {
        HStack(spacing: 6) {
            Group {
                switch status {
                case "已完成":
                    Image(systemName: "checkmark.circle.fill").foregroundColor(TelegramTheme.success)
                case "失败":
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(TelegramTheme.danger)
                case "上传中", "下载中":
                    Image(systemName: "arrow.up.circle.fill").foregroundColor(TelegramTheme.accent)
                case "等待中":
                    Image(systemName: "clock.fill").foregroundColor(TelegramTheme.textSecondary)
                default:
                    Image(systemName: "circle").foregroundColor(TelegramTheme.textSecondary)
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
        TelegramTheme.statusColor(for: status)
    }
    
    // MARK: - Create Directory Dialog
    
    private var createDirectoryDialog: some View {
        VStack(spacing: 20) {
            Text("新建目录")
                .font(.headline)
                .foregroundColor(TelegramTheme.textPrimary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("目录名称:")
                    .font(.caption)
                    .foregroundColor(TelegramTheme.textSecondary)
                
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
        .background(TelegramTheme.panelBackground)
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
                .foregroundColor(TelegramTheme.textPrimary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("目录名称:")
                    .font(.caption)
                    .foregroundColor(TelegramTheme.textSecondary)
                
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
        .background(TelegramTheme.panelBackground)
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
    
    // MARK: - Rename File Dialog

    private var renameFileUiDialog: some View {
        VStack(spacing: 20) {
            Text("重命名文件")
                .font(.headline)
                .foregroundColor(TelegramTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("文件名称:")
                    .font(.caption)
                    .foregroundColor(TelegramTheme.textSecondary)

                TextField("请输入新文件名", text: $fileRenameValue)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 20) {
                Button("取消") {
                    showingFileRenameDialog = false
                    fileRenameValue = ""
                    fileRenameTargetId = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    handleRenameFile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(fileRenameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFileRenaming)
                .keyboardShortcut(.defaultAction)
            }

            if isFileRenaming {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(TelegramTheme.panelBackground)
        .cornerRadius(12)
        .shadow(radius: 10)
    }

    private func handleRenameFile() {
        guard let service = directoryService, let id = fileRenameTargetId else { return }
        let name = fileRenameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return }

        isFileRenaming = true

        Task {
            do {
                try await service.renameFile(fileId: id, newFileName: name)

                await MainActor.run {
                    addLog("文件 [\(id)] 重命名为 [\(name)] 成功")
                    isFileRenaming = false
                    showingFileRenameDialog = false
                    fileRenameValue = ""
                    fileRenameTargetId = nil

                    // 刷新文件列表
                    loadCurrentFiles()

                    // 刷新右侧详情面板
                    if selectedFileId == id {
                        loadFileDetail(fileId: id)
                    }
                }
            } catch {
                await MainActor.run {
                    addLog("文件重命名失败: \(error.localizedDescription)")
                    isFileRenaming = false
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

    // MARK: - Delete Directory
    
    private func handleDeleteDirectory() {
        guard let service = directoryService, let id = deleteTargetId else { return }
        let target = findDirectoryItem(id: id, nodes: directoryTree)
        let fallbackDirectoryId = target?.pId
        let deletedDirectoryIds = target.map { collectDirectoryIds(from: $0) } ?? Set([id])
        
        isDeleting = true
        
        Task {
            do {
                try await service.deleteDirectory(id: id)
                
                await MainActor.run {
                    addLog("目录 [\(id)] 删除成功")
                    isDeleting = false
                    deleteTargetId = nil
                    deleteTargetName = ""
                    expandedDirectoryIds.subtract(deletedDirectoryIds)
                    if let selectedId = selectedDirectoryId, deletedDirectoryIds.contains(selectedId) {
                        selectedDirectoryId = fallbackDirectoryId
                        fileList = []
                        selectedFiles.removeAll()
                        selectedFileId = nil
                        selectedDetailItem = nil
                        fileDetail = nil
                    }
                    
                    // 自动刷新目录
                    addLog("自动刷新目录...")
                    Task {
                        await loadDirectoryFromServer()
                        if self.selectedDirectoryId == nil {
                            self.selectedDirectoryId = self.directoryTree.first?.id
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    addLog("删除失败: \(error.localizedDescription)")
                    isDeleting = false
                    deleteTargetId = nil
                    deleteTargetName = ""
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

    private func collectDirectoryIds(from item: DirectoryItem) -> Set<Int64> {
        var ids: Set<Int64> = [item.id]
        for child in item.childFileList ?? [] where !child.isFile {
            ids.formUnion(collectDirectoryIds(from: child))
        }
        return ids
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
                
                print("🛠️ [UI] Single upload task submitted: \(task.name) - ID: \(task.id)")
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
        Task { @MainActor in
            await loadCurrentFilesFromServer()
        }
    }

    @MainActor
    private func loadCurrentFilesFromServer() async {
        guard let service = directoryService else { return }

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

            self.fileList = result.recordList.map { fileDto in
                let item = fileDto.toDirectoryItem()
                let parentDirectoryName = fileDto.parentDirName ?? self.findDirectoryName(
                    id: item.pId,
                    nodes: self.directoryTree
                )

                return DirectoryItem(
                    id: item.id,
                    pId: item.pId,
                    fileName: item.fileName,
                    childFileList: item.childFileList,
                    hasChild: item.hasChild,
                    fileSize: item.fileSize,
                    isFile: item.isFile,
                    uploadTime: item.uploadTime,
                    directoryName: parentDirectoryName ?? "未知目录"
                )
            }
            self.totalPages = Int(result.totalPage)
            self.totalCount = result.totalCount
            // 如果当前页大于总页数（可能是删除后），且总页数不为0，重置为最后一页
            if self.currentPage > self.totalPages && self.totalPages > 0 {
                self.currentPage = self.totalPages
            }

            // 文件列表加载完成后，后台预加载图片/视频缩略图
            await FileThumbnailService.shared.prefetch(items: self.fileList)
        } catch {
            print("❌ 加载文件列表失败: \(error)")
            // 发生错误时清空列表，避免误导用户
            self.fileList = []
            self.totalCount = 0
            self.totalPages = 1

            self.alertMessage = "加载文件列表失败: \(error.localizedDescription)"
            self.showingAlert = true
        }
    }

    private func scheduleFileListRefreshAfterUpload() {
        uploadCompletionRefreshTask?.cancel()
        uploadCompletionRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            loadCurrentFiles()
            uploadCompletionRefreshTask = nil
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
    
    /// 加载文件详情，并使用列表项作为网络请求失败时的降级数据。
    private func loadFileDetail(fileId: Int64, item: DirectoryItem? = nil) {
        let localItem = item
            ?? currentFiles.first(where: { $0.id == fileId })
            ?? (selectedDetailItem?.id == fileId ? selectedDetailItem : nil)
            ?? (fileDetail?.id == fileId ? fileDetail?.toDirectoryItem() : nil)

        selectedDetailItem = localItem
        fileDetail = fileDetail?.id == fileId ? fileDetail : nil
        loadDetailPreview(for: localItem)

        detailLoadTask?.cancel()
        isLoadingDetail = true
        detailLoadTask = Task { [service = directoryService] in
            guard let service else {
                await MainActor.run {
                    guard selectedFileId == fileId else { return }
                    isLoadingDetail = false
                }
                return
            }

            do {
                let detail = try await service.fetchFileDetail(fileId: fileId)
                try Task.checkCancellation()
                await MainActor.run {
                    guard selectedFileId == fileId else { return }
                    fileDetail = detail
                    selectedDetailItem = detail.toDirectoryItem()
                    isLoadingDetail = false
                }
            } catch is CancellationError {
                // 快速切换文件时取消旧请求，避免旧详情覆盖当前选择。
            } catch {
                print("❌ 加载文件详情失败: \(error.localizedDescription)")
                await MainActor.run {
                    guard selectedFileId == fileId else { return }
                    isLoadingDetail = false
                }
            }
        }
    }

    private func loadDetailPreview(for item: DirectoryItem?) {
        detailPreviewTask?.cancel()
        detailPreviewTask = nil
        detailPreviewImage = nil

        guard let item, item.isImageFile || item.isVideoFile else {
            isLoadingDetailPreview = false
            return
        }

        isLoadingDetailPreview = true
        detailPreviewTask = Task {
            let image: NSImage?
            if item.isImageFile {
                image = await FileThumbnailService.shared.previewImage(for: item)
            } else {
                image = await FileThumbnailService.shared.thumbnail(for: item)
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard selectedFileId == item.id else { return }
                detailPreviewImage = image
                isLoadingDetailPreview = false
            }
        }
    }

    private func clearFileDetailSelection() {
        detailLoadTask?.cancel()
        detailPreviewTask?.cancel()
        detailLoadTask = nil
        detailPreviewTask = nil
        selectedFileId = nil
        fileDetail = nil
        selectedDetailItem = nil
        detailPreviewImage = nil
        isLoadingDetail = false
        isLoadingDetailPreview = false
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
        if let parentDirName, !parentDirName.isEmpty {
            return parentDirName
        }
        guard !filePath.isEmpty else { return "-" }
        let parentName = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .lastPathComponent
        return parentName.isEmpty ? "-" : parentName
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
    @State private var pendingInsertToken: String? = nil
    @State private var quotedMessage: ChatMessage? = nil
    @State private var pendingImages: [PendingChatImage] = []
    @State private var pendingImageError: String? = nil
    @State private var isUploadingImage: Bool = false
    @State private var pendingMediaMessages: [String: [PendingChatImage]] = [:]
    @State private var imagePreviewContext: ChatImagePreviewContext?
    
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
        ZStack {
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

            GeometryReader { contentProxy in
                let inputHeight = max(150, contentProxy.size.height * 0.20)
                let messageHeight = max(0, contentProxy.size.height - inputHeight)

                VStack(spacing: 0) {
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
                                    ChatMessageRow(
                                        message: msg,
                                        friendName: friend.name,
                                        friendAvatarBase64: friend.avatarBase64,
                                        friendAvatarColor: friend.avatarColor,
                                        onCopy: copyMessage,
                                        onQuote: { quotedMessage = $0 },
                                        onDeleteLocal: deleteLocalMessage,
                                        onRetract: retractMessage,
                                        onRetry: retryMessage,
                                        onDoubleTap: triggerReaction,
                                        onPreviewImage: openImagePreview
                                    )
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
            .frame(height: messageHeight)
            .background(Color(NSColor.textBackgroundColor).opacity(0.8))

                    ChatInputBar(
                        friendName: friend.name,
                        messageText: $messageText,
                        showEmojiPicker: $showEmojiPicker,
                        pendingInsertToken: $pendingInsertToken,
                        quotedMessage: $quotedMessage,
                        pendingImages: $pendingImages,
                        pendingImageError: $pendingImageError,
                        isSending: $isUploadingImage,
                        onSendNudge: sendNudge,
                        onPickImages: pickImages,
                        onPasteImage: handlePastedImage,
                        onRemovePendingImage: removePendingImage,
                        onSendMessage: {
                            Task { await sendMessage() }
                        }
                    )
                    .frame(height: inputHeight)
                    .clipped()
                }
            }
        }
        .onAppear {
            isInitialProcessing = true
            Task {
                await loadInitialHistory()
                try? await Task.sleep(nanoseconds: 600_000_000)
                isInitialProcessing = false
            }
        }

            if let imagePreviewContext {
                ChatImagePreviewOverlay(
                    context: imagePreviewContext,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            self.imagePreviewContext = nil
                        }
                    }
                )
                .zIndex(50)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: imagePreviewContext?.id)
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

    private func openImagePreview(_ attachment: ChatImageAttachment, _ attachments: [ChatImageAttachment]) {
        withAnimation(.easeInOut(duration: 0.16)) {
            imagePreviewContext = ChatImagePreviewContext(
                selectedAttachment: attachment,
                attachments: attachments
            )
        }
    }

    private func copyMessage(_ msg: ChatMessage) {
        guard !msg.content.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(msg.displayText, forType: .string)
    }

    private func deleteLocalMessage(_ msg: ChatMessage) {
        guard let index = socketManager.chatHistory[friend.id]?.firstIndex(where: { $0.id == msg.id }) else { return }
        let snapshot = socketManager.chatHistory[friend.id] ?? []
        socketManager.chatHistory[friend.id]?.remove(at: index)

        guard let messageId = msg.messageId else { return }
        Task {
            do {
                _ = try await socketManager.sendChatMessageAction(action: "delete_local", messageId: messageId, friendId: friend.id)
            } catch {
                await MainActor.run {
                    socketManager.chatHistory[friend.id] = snapshot
                    print("❌ 本地删除消息失败: \(error)")
                }
            }
        }
    }

    private func retractMessage(_ msg: ChatMessage) {
        guard let messageId = msg.messageId else { return }
        let snapshot = socketManager.chatHistory[friend.id] ?? []
        updateMessage(msg) { message in
            message.retracted = true
            message.sendStatus = .retracted
        }

        Task {
            do {
                _ = try await socketManager.sendChatMessageAction(action: "retract", messageId: messageId, friendId: friend.id)
            } catch {
                await MainActor.run {
                    socketManager.chatHistory[friend.id] = snapshot
                    print("❌ 撤回消息失败: \(error)")
                }
            }
        }
    }

    private func retryMessage(_ msg: ChatMessage) {
        guard msg.isMe else { return }
        if let clientMsgId = msg.clientMsgId,
           let pendingImages = pendingMediaMessages[clientMsgId] {
            Task {
                await retryPendingMediaMessage(msg, imagesToSend: pendingImages)
            }
            return
        }

        socketManager.chatHistory[friend.id]?.removeAll(where: { $0.id == msg.id })
        socketManager.sendChatMessage(
            receiverId: friend.id,
            content: msg.content,
            msgType: msg.type,
            avatar: authService.currentUser?.avatar,
            quoteMsgId: msg.quoteMsgId,
            quoteMsgContent: msg.quoteMsgContent,
            quoteMsgSenderName: msg.quoteMsgSenderName,
            clientMsgId: msg.clientMsgId
        )
        shouldScrollToBottom = true
    }

    private func updateMessage(_ msg: ChatMessage, transform: (inout ChatMessage) -> Void) {
        guard var history = socketManager.chatHistory[friend.id],
              let index = history.firstIndex(where: { $0.id == msg.id }) else {
            return
        }
        transform(&history[index])
        socketManager.chatHistory[friend.id] = history
    }

    private func handlePastedImage(_ image: NSImage) {
        guard pendingImages.count < ChatMixedMessageContent.maxImageCount else {
            pendingImageError = "单条消息最多发送\(ChatMixedMessageContent.maxImageCount)张图片"
            return
        }
        pendingImages.append(PendingChatImage.pasted(image))
        pendingImageError = nil
    }

    private func pickImages() {
        guard !isUploadingImage else { return }
        let remaining = ChatMixedMessageContent.maxImageCount - pendingImages.count
        guard remaining > 0 else {
            pendingImageError = "单条消息最多发送\(ChatMixedMessageContent.maxImageCount)张图片"
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "选择"

        guard panel.runModal() == .OK else { return }

        var newItems: [PendingChatImage] = []
        for url in panel.urls.prefix(remaining) {
            do {
                newItems.append(try PendingChatImage.file(url: url))
            } catch {
                pendingImageError = error.localizedDescription
            }
        }
        if panel.urls.count > remaining {
            pendingImageError = "已达到\(ChatMixedMessageContent.maxImageCount)张上限，超出的图片未加入"
        } else if !newItems.isEmpty {
            pendingImageError = nil
        }
        pendingImages.append(contentsOf: newItems)
    }

    private func removePendingImage(_ id: UUID) {
        pendingImages.removeAll { $0.id == id }
        if pendingImages.isEmpty {
            pendingImageError = nil
        }
    }

    private func sendMessage() async {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagesToSend = pendingImages
        guard !trimmedText.isEmpty || !imagesToSend.isEmpty else { return }

        let contentToSend = messageText
        let quote = quotedMessage
        let avatar = authService.currentUser?.avatar

        if imagesToSend.isEmpty {
            messageText = ""
            quotedMessage = nil
            shouldScrollToBottom = true

            socketManager.sendChatMessage(
                receiverId: friend.id,
                content: contentToSend,
                msgType: "TEXT",
                avatar: avatar,
                quoteMsgId: quote?.messageId.map { Int64($0) },
                quoteMsgContent: quote.map { ChatMessagePayload.parse(content: $0.content, msgType: $0.type).displayText },
                quoteMsgSenderName: quote.map { $0.isMe ? "我" : friend.name }
            )
            return
        }

        pendingImageError = nil

        do {
            guard let currentUser = authService.currentUser else {
                pendingImageError = "请先登录"
                return
            }
            guard currentUser.id >= Int64(Int32.min), currentUser.id <= Int64(Int32.max) else {
                pendingImageError = "当前用户ID超出上传协议范围"
                return
            }

            let clientMsgId = UUID().uuidString
            let localAttachments = imagesToSend.map { $0.localAttachment() }
            let localPayload = try ChatMixedMessageContent(text: contentToSend, attachments: localAttachments)
            let localContent = try localPayload.contentString()

            messageText = ""
            pendingImages.removeAll()
            pendingImageError = nil
            quotedMessage = nil
            shouldScrollToBottom = true

            ChatPendingImageStore.shared.store(imagesToSend)
            pendingMediaMessages[clientMsgId] = imagesToSend
            socketManager.appendLocalChatMessage(
                receiverId: friend.id,
                content: localContent,
                msgType: "MIXED",
                avatar: avatar,
                quoteMsgId: quote?.messageId.map { Int64($0) },
                quoteMsgContent: quote.map { ChatMessagePayload.parse(content: $0.content, msgType: $0.type).displayText },
                quoteMsgSenderName: quote.map { $0.isMe ? "我" : friend.name },
                clientMsgId: clientMsgId,
                sendStatus: .uploadingMedia
            )

            await uploadAndSendPendingMediaMessage(
                clientMsgId: clientMsgId,
                contentToSend: contentToSend,
                imagesToSend: imagesToSend,
                quoteMsgId: quote?.messageId.map { Int64($0) },
                quoteMsgContent: quote.map { ChatMessagePayload.parse(content: $0.content, msgType: $0.type).displayText },
                quoteMsgSenderName: quote.map { $0.isMe ? "我" : friend.name },
                avatar: avatar,
                currentUser: currentUser,
                localAttachmentIds: localAttachments.map { $0.fileId }
            )
        } catch {
            pendingImageError = error.localizedDescription
        }
    }

    private func retryPendingMediaMessage(_ msg: ChatMessage, imagesToSend: [PendingChatImage]) async {
        guard let clientMsgId = msg.clientMsgId else { return }
        guard let currentUser = authService.currentUser else {
            socketManager.updateLocalChatMessage(
                receiverId: friend.id,
                clientMsgId: clientMsgId,
                status: .failed,
                errorMessage: "请先登录"
            )
            return
        }
        guard currentUser.id >= Int64(Int32.min), currentUser.id <= Int64(Int32.max) else {
            socketManager.updateLocalChatMessage(
                receiverId: friend.id,
                clientMsgId: clientMsgId,
                status: .failed,
                errorMessage: "当前用户ID超出上传协议范围"
            )
            return
        }

        let payload = ChatMessagePayload.parse(content: msg.content, msgType: msg.type)
        let localAttachmentIds = payload.images
            .filter { $0.isLocalPending }
            .map { $0.fileId }

        socketManager.updateLocalChatMessage(
            receiverId: friend.id,
            clientMsgId: clientMsgId,
            status: .uploadingMedia,
            errorMessage: nil
        )
        shouldScrollToBottom = true

        await uploadAndSendPendingMediaMessage(
            clientMsgId: clientMsgId,
            contentToSend: payload.text,
            imagesToSend: imagesToSend,
            quoteMsgId: msg.quoteMsgId,
            quoteMsgContent: msg.quoteMsgContent,
            quoteMsgSenderName: msg.quoteMsgSenderName,
            avatar: authService.currentUser?.avatar,
            currentUser: currentUser,
            localAttachmentIds: localAttachmentIds
        )
    }

    private func uploadAndSendPendingMediaMessage(
        clientMsgId: String,
        contentToSend: String,
        imagesToSend: [PendingChatImage],
        quoteMsgId: Int64?,
        quoteMsgContent: String?,
        quoteMsgSenderName: String?,
        avatar: String?,
        currentUser: UserDO,
        localAttachmentIds: [Int64]
    ) async {
        do {
            let uploadService = ChatAttachmentUploadService()
            var attachments: [ChatImageAttachment] = []
            for item in imagesToSend {
                attachments.append(
                    try await uploadService.uploadPendingImage(
                        item,
                        userId: Int32(currentUser.id),
                        userName: currentUser.username
                    )
                )
            }

            let payload = try ChatMixedMessageContent(text: contentToSend, attachments: attachments)
            let content = try payload.contentString()

            pendingMediaMessages.removeValue(forKey: clientMsgId)
            ChatPendingImageStore.shared.remove(localAttachmentIds: localAttachmentIds)
            socketManager.updateLocalChatMessage(
                receiverId: friend.id,
                clientMsgId: clientMsgId,
                content: content,
                msgType: "MIXED",
                status: .sending,
                errorMessage: nil
            )
            socketManager.sendChatMessage(
                receiverId: friend.id,
                content: content,
                msgType: "MIXED",
                avatar: avatar,
                quoteMsgId: quoteMsgId,
                quoteMsgContent: quoteMsgContent,
                quoteMsgSenderName: quoteMsgSenderName,
                clientMsgId: clientMsgId,
                appendLocalMessage: false
            )
        } catch {
            socketManager.updateLocalChatMessage(
                receiverId: friend.id,
                clientMsgId: clientMsgId,
                status: .failed,
                errorMessage: error.localizedDescription
            )
        }
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
                    let status: ChatMessage.SendStatus = dto.retracted ? .retracted : .success
                    
                    return ChatMessage(
                        messageId: Int32(dto.id),
                        clientMsgId: dto.clientMsgId,
                        content: dto.content,
                        isMe: amIMe,
                        timestamp: Date(),
                        type: dto.msgType.isEmpty ? "TEXT" : dto.msgType,
                        sendStatus: status,
                        quoteMsgId: dto.quoteMsgId,
                        quoteMsgContent: dto.quoteMsgContent,
                        quoteMsgSenderName: dto.quoteMsgSenderName,
                        retracted: dto.retracted,
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
                        VStack(spacing: 0) {
                            FriendRow(friend: friend, isSelected: selectedFriendId == friend.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedFriendId = friend.id
                                }

                            Divider()
                                .padding(.leading, 64)
                                .opacity(0.35)
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingAddFriendSheet) {
            MacAddFriendSheet(
                isPresented: $showingAddFriendSheet,
                onOpenRequests: {
                    selectedFriendId = -1
                }
            )
                .environmentObject(socketManager)
        }
    }
}

// 3.1. Add Friend View (添加好友弹窗 - macOS Style)
private struct MacAddFriendSheet: View {
    @Binding var isPresented: Bool
    var onOpenRequests: (() -> Void)? = nil
    @EnvironmentObject var socketManager: SocketManager
    @State private var searchText = ""
    @State private var requestMessage = "请求添加你为好友"
    @State private var searchResults: [UserDto] = []
    @State private var isSearching = false
    @State private var lastErrorMessage: String?
    @State private var hasSearched = false
    
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
                        
                        TextField("输入用户名或昵称", text: $searchText)
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
                    
                    Text("支持按用户名或昵称搜索好友")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)

                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .foregroundColor(.secondary)

                        TextField("好友验证消息", text: $requestMessage)
                            .textFieldStyle(.plain)
                            .onChange(of: requestMessage) { value in
                                if value.count > 255 {
                                    requestMessage = String(value.prefix(255))
                                }
                            }

                        Text("\(requestMessage.count)/255")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
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
                                    UserResultRow(
                                        user: user,
                                        requestMessage: requestMessage,
                                        onOpenIncomingRequest: {
                                            isPresented = false
                                            onOpenRequests?()
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    } else if hasSearched {
                        // Empty State for Search
                        VStack(spacing: 12) {
                            Image(systemName: "person.slash.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("未找到该用户")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("请检查输入的用户名或昵称是否正确")
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
                .frame(height: 180)
            }
            .padding(24)
        }
        .frame(width: 600, height: 500)
        .background(VisualEffectBlur(material: .windowBackground, blendingMode: .behindWindow))
    }
    // 用户名搜索
    private func performSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !isSearching else { return }
        
        isSearching = true
        searchResults = []
        lastErrorMessage = nil
        hasSearched = true
        
        Task {
            do {
                let users = try await socketManager.searchUser(userName: keyword)
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
    let requestMessage: String
    let onOpenIncomingRequest: () -> Void
    @State private var isHovering = false
    @State private var isSending = false
    @State private var requestSent = false
    
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
                
                if status == 5 || statusDesc == "你自己" {
                    Button("你自己") { }
                        .disabled(true)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                } else if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 58)
                } else if requestSent {
                    Button("已发送") { }
                        .disabled(true)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                } else {
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
                            Text("重新申请")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    case 4: // 对方已向当前用户发出申请
                        Button(action: onOpenIncomingRequest) {
                            Text("去处理")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    default: // 默认情况/陌生人
                        Button(action: sendFriendRequest) {
                            Text(statusDesc)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
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
        guard !isSending && !requestSent else { return }
        isSending = true
        Task {
            do {
                let normalizedMessage = requestMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                let msg = normalizedMessage.isEmpty ? "请求添加你为好友" : normalizedMessage
                print("📨 Sending friend request to \(user.userName) (ID: \(user.id)) with msg: \(msg)")
                let success = try await socketManager.addFriend(remoteUserId: user.id, requestMsg: msg)
                
                await MainActor.run {
                    isSending = false
                    if success {
                        withAnimation {
                            requestSent = true
                        }
                        alertMessage = "好友申请已发送"
                        showingAlert = true
                    } else {
                        alertMessage = "请求发送失败"
                        showingAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSending = false
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
            return msg.displayText
        } else if let serverMsg = friend.serverLatestMsg, !serverMsg.isEmpty {
            return ChatMessagePayload.parse(content: serverMsg, msgType: "").displayText
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
                        if let cachedImage = ChatAvatarCache.shared.object(forKey: avatarStr as NSString) {
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
                                cache: ChatAvatarCache.shared
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
    @Binding var selectedTab: Int
    @State private var selectedFriendId: Int64?
    @State private var friends: [Friend] = []
    @State private var showingAddFriendSheet = false
    @EnvironmentObject var socketManager: SocketManager

    private var unreadCount: Int {
        friends.reduce(0) { result, friend in
            result + (socketManager.unreadCounts[friend.id] ?? Int(friend.serverUnreadCount ?? 0))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: MainWorkspaceLayout.panelSpacing) {
                if proxy.size.width >= 820 {
                    recentConversationsCard
                        .frame(width: MainWorkspaceLayout.sidebarWidth)
                }

                VStack(spacing: MainWorkspaceLayout.panelSpacing) {
                    if proxy.size.width < 820 {
                        compactChatActions
                    }

                    activeConversationCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, MainWorkspaceLayout.contentPadding)
            .padding(.top, MainWorkspaceLayout.contentPadding)
            .padding(.bottom, 14)
            .background(TelegramTheme.appBackground)
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
        .sheet(isPresented: $showingAddFriendSheet) {
            MacAddFriendSheet(
                isPresented: $showingAddFriendSheet,
                onOpenRequests: {
                    selectedFriendId = -1
                }
            )
                .environmentObject(socketManager)
        }
    }

    private var compactChatActions: some View {
        HStack {
            Text("聊天")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(TelegramTheme.textPrimary)

            Spacer()

            Button {
                showingAddFriendSheet = true
            } label: {
                Image(systemName: "person.badge.plus")
            }
            .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.accent))
            .help("添加好友")
            .accessibilityLabel("添加好友")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(TelegramTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(TelegramTheme.textSecondary.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var activeConversationCard: some View {
        Group {
            if let selectedId = selectedFriendId {
                if selectedId == -1 {
                    NewFriendView {
                        showingAddFriendSheet = true
                    }
                } else if let friend = friends.first(where: { $0.id == selectedId }) {
                    ChatDetailView(friend: friend)
                        .id(friend.id)
                } else {
                    ChatWorkspaceEmptyState()
                }
            } else {
                ChatWorkspaceEmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TelegramTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(TelegramTheme.textSecondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var recentConversationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近会话")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(TelegramTheme.textPrimary)

                Spacer()

                Button {
                    showingAddFriendSheet = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .buttonStyle(CloudIconButtonStyle(tint: TelegramTheme.accent))
                .help("添加好友")
                .accessibilityLabel("添加好友")
                .accessibilityHint("搜索用户并发送好友申请")

                Text("\(friends.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TelegramTheme.accent)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(TelegramTheme.accent.opacity(0.12)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)

            Divider().overlay(TelegramTheme.textSecondary.opacity(0.12))

            ScrollView {
                LazyVStack(spacing: 6) {
                    Button {
                        selectedFriendId = -1
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(TelegramTheme.warning)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 5) {
                                Text("新的朋友")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(TelegramTheme.textPrimary)

                                Text("添加好友与处理申请")
                                    .font(.system(size: 11))
                                    .foregroundColor(TelegramTheme.textSecondary)
                            }

                            Spacer(minLength: 4)

                            if !socketManager.pendingFriendRequests.isEmpty {
                                Text("\(min(socketManager.pendingFriendRequests.count, 99))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Capsule().fill(TelegramTheme.danger))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(selectedFriendId == -1 ? TelegramTheme.accent.opacity(0.13) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(TelegramTheme.textSecondary.opacity(0.10))
                        .padding(.horizontal, 8)

                    ForEach(friends) { friend in
                        ChatWorkspaceRecentRow(
                            friend: friend,
                            isSelected: selectedFriendId == friend.id
                        ) {
                            selectedFriendId = friend.id
                        }
                    }
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("云盘协作", systemImage: "externaldrive.badge.icloud")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TelegramTheme.textPrimary)

                Text("聊天图片与文件可直接保存到私人云盘，重要内容始终在一处。")
                    .font(.system(size: 11))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TelegramTheme.elevatedBackground.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(12)

            TelegramSidebarTabBar(
                selectedTab: $selectedTab,
                unreadCount: unreadCount
            )
        }
        .background(TelegramTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(TelegramTheme.textSecondary.opacity(0.14), lineWidth: 1)
        )
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

                    if self.selectedFriendId == nil {
                        self.selectedFriendId = self.friends.first?.id
                    }
                }
            } catch {
                print("❌ Failed to load friend list: \(error)")
            }
            
            // Fetch pending requests count on load
            _ = try? await socketManager.getPendingRequests()
        }
    }
    
    private func colorFor(name: String) -> Color {
        let colors: [Color] = [.blue, .orange, .purple, .green, .red, .pink, .teal]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

private struct ChatWorkspaceRecentRow: View {
    let friend: Friend
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var socketManager: SocketManager

    private var unreadCount: Int {
        socketManager.unreadCounts[friend.id] ?? Int(friend.serverUnreadCount ?? 0)
    }

    private var lastMessage: String {
        if let message = socketManager.chatHistory[friend.id]?.last {
            return message.displayText
        }
        if let serverMessage = friend.serverLatestMsg, !serverMessage.isEmpty {
            return ChatMessagePayload.parse(content: serverMessage, msgType: "").displayText
        }
        return "点击开始聊天"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ChatWorkspaceAvatar(friend: friend, size: 38)

                VStack(alignment: .leading, spacing: 5) {
                    Text(friend.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TelegramTheme.textPrimary)
                        .lineLimit(1)

                    Text(lastMessage)
                        .font(.system(size: 11))
                        .foregroundColor(TelegramTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(TelegramTheme.accent))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isSelected ? TelegramTheme.accent.opacity(0.13) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ChatWorkspaceAvatar: View {
    let friend: Friend
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                let avatar = friend.avatarBase64?.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let avatar, !avatar.isEmpty {
                    AvatarDecodeView(
                        base64: avatar,
                        fallbacName: String(friend.name.prefix(1)),
                        fallbackColor: friend.avatarColor,
                        cache: ChatAvatarCache.shared
                    )
                } else {
                    Circle()
                        .fill(friend.avatarColor)
                        .overlay(
                            Text(String(friend.name.prefix(1)))
                                .font(.system(size: size * 0.38, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if friend.status == "在线" {
                Circle()
                    .fill(TelegramTheme.success)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(TelegramTheme.panelBackground, lineWidth: 2))
            }
        }
    }
}

private struct ChatWorkspaceEmptyState: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(TelegramTheme.accent.opacity(0.72))

            Text("选择一个好友开始聊天")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(TelegramTheme.textPrimary)

            Text("消息、图片和云盘文件都可以在这里发送")
                .font(.system(size: 12))
                .foregroundColor(TelegramTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cloud Storage Components

/// 动态背景：磨砂渐变效果
private struct MeshGradientBackground: View {
    var body: some View {
        ZStack {
            // 基础渐变
            LinearGradient(
                colors: [
                    TelegramTheme.appBackground,
                    TelegramTheme.panelBackground,
                    TelegramTheme.elevatedBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 模糊层
            VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(TelegramTheme.appBackground.opacity(0.5))
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
    var onPlay: (DirectoryItem) -> Void
    
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
                        onAction: { action in onAction(item, action) },
                        onPlay: { onPlay(item) }
                    )
                }
            }
            .padding(24)
        }
        .background(CloudStorageSurface.panel)
    }
}

/// 文件卡片：生动形象的单个文件/文件夹展示
private struct FileCard: View {
    let item: DirectoryItem
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onAction: (Int) -> Void
    let onPlay: () -> Void
    
    @State private var isHovering = false
    @State private var thumbnail: NSImage? = nil

    var body: some View {
        VStack(spacing: 12) {
            // 图标区域
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? TelegramTheme.accent.opacity(0.18) : CloudStorageSurface.field)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? TelegramTheme.accent : TelegramTheme.textSecondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if thumbnail == nil {
                    Image(systemName: item.isFile ? item.iconName : "folder.fill")
                        .font(.system(size: 44))
                        .foregroundColor(item.isFile ? TelegramTheme.accent : TelegramTheme.warning)
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(isHovering ? 1.1 : 1.0)
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(TelegramTheme.accent)
                        .background(Circle().fill(Color.white))
                        .offset(x: 6, y: -6)
                }
                
                if item.isPlayableVideoFile && isHovering {
                    ZStack {
                        Color.black.opacity(0.3).cornerRadius(16)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }
                    .frame(width: .infinity, height: 100)
                    .onTapGesture {
                        onPlay()
                    }
                }
            }
            .shadow(color: .black.opacity(isHovering ? 0.2 : 0.05), radius: isHovering ? 10 : 4, y: isHovering ? 5 : 2)
            
            // 文字区域
            VStack(spacing: 4) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? TelegramTheme.accent : TelegramTheme.textPrimary)
                
                Text(item.isFile ? item.sizeString : "\(item.childFileList?.count ?? 0) 项")
                    .font(.system(size: 11))
                    .foregroundColor(TelegramTheme.textSecondary)
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture(count: 1, perform: onTap)
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onHover { h in isHovering = h }
        .task {
            guard item.isImageFile || item.isVideoFile else { return }
            let img = await FileThumbnailService.shared.thumbnail(for: item)
            await MainActor.run { self.thumbnail = img }
        }
        .contextMenu {
            if item.isPlayableVideoFile {
                Button { onPlay() } label: { Label("播放", systemImage: "play.circle") }
            }
            Button { onAction(3) } label: { Label("重命名", systemImage: "pencil") }
            Button { onAction(2) } label: { Label("下载", systemImage: "arrow.down.circle") }
            Divider()
            Button(role: .destructive) { onAction(1) } label: { Label("删除", systemImage: "trash") }
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

private enum FileListColumnLayout {
    static let spacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let checkboxWidth: CGFloat = 22
    static let iconWidth: CGFloat = 30
    static let nameMinWidth: CGFloat = 140
    static let sizeWidth: CGFloat = 72
    static let directoryWidth: CGFloat = 78
    static let timeWidth: CGFloat = 112
    static let actionWidth: CGFloat = 100
}

// MARK: - FileListRowView (商业级文件行组件)
/// 带悬停动画、卡片背景、微缩放效果的文件行视图
private struct FileListRowView: View {
    let file: DirectoryItem
    let isCompact: Bool
    let showDirectory: Bool
    let showUploadTime: Bool
    let isSelected: Bool
    let isChecked: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    let onPlay: () -> Void
    let onRename: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var isHovering = false
    @State private var isPlayHovering = false
    @State private var isRenameHovering = false
    @State private var isDownloadHovering = false
    @State private var isDeleteHovering = false

    var body: some View {
        HStack(spacing: isCompact ? 8 : FileListColumnLayout.spacing) {
            // 复选框
            Toggle("", isOn: Binding(get: { isChecked }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .frame(width: FileListColumnLayout.checkboxWidth)

            // 文件图标（图片/视频显示缩略图，其他保持 SF Symbol）
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(file.isFile
                          ? TelegramTheme.accent.opacity(0.12)
                          : TelegramTheme.warning.opacity(0.14))
                    .frame(width: FileListColumnLayout.iconWidth, height: FileListColumnLayout.iconWidth)
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(width: FileListColumnLayout.iconWidth, height: FileListColumnLayout.iconWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: file.isFile ? file.iconName : "folder.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(file.isFile
                                         ? TelegramTheme.accent.gradient
                                         : TelegramTheme.warning.gradient)
                }
            }
            .task {
                guard file.isImageFile || file.isVideoFile else { return }
                let img = await FileThumbnailService.shared.thumbnail(for: file)
                await MainActor.run { self.thumbnail = img }
            }

            // 文件名
            Text(file.fileName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(TelegramTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: FileListColumnLayout.nameMinWidth, maxWidth: .infinity, alignment: .leading)

            // 文件大小
            Text(file.sizeString)
                .font(.system(size: 12))
                .foregroundColor(TelegramTheme.textSecondary)
                .frame(width: FileListColumnLayout.sizeWidth, alignment: .leading)

            // 所属目录（仅显示直接父目录名称）
            if showDirectory {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TelegramTheme.warning.opacity(0.9))

                    Text(file.directoryName ?? "未知目录")
                        .font(.system(size: 12))
                        .foregroundColor(TelegramTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: FileListColumnLayout.directoryWidth, alignment: .leading)
            }

            // 上传时间
            if showUploadTime {
                Text(file.uploadTimeString)
                    .font(.system(size: 12))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .frame(width: FileListColumnLayout.timeWidth, alignment: .leading)
            }

            // 操作按钮（悬停时渐显）
            HStack(spacing: 0) {
                if file.isPlayableVideoFile {
                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(isPlayHovering
                                             ? TelegramTheme.success
                                             : TelegramTheme.textSecondary.opacity(0.65))
                            .scaleEffect(isPlayHovering ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .help("播放")
                    .onHover { isPlayHovering = $0 }
                    .frame(width: 24, alignment: .center)
                }

                Button(action: onRename) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isRenameHovering
                                         ? TelegramTheme.accent
                                         : TelegramTheme.textSecondary.opacity(0.65))
                        .scaleEffect(isRenameHovering ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .help("重命名")
                .onHover { isRenameHovering = $0 }
                .frame(width: 24, alignment: .center)

                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isDownloadHovering
                                         ? TelegramTheme.accent
                                         : TelegramTheme.textSecondary.opacity(0.65))
                        .scaleEffect(isDownloadHovering ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .help("下载")
                .onHover { isDownloadHovering = $0 }
                .frame(width: 24, alignment: .center)

                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(isDeleteHovering
                                         ? TelegramTheme.danger
                                         : TelegramTheme.textSecondary.opacity(0.55))
                        .scaleEffect(isDeleteHovering ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .help("删除")
                .onHover { isDeleteHovering = $0 }
                .frame(width: 24, alignment: .center)
            }
            .opacity(isHovering || isSelected ? 1 : 0.4)
            .frame(width: FileListColumnLayout.actionWidth, alignment: .center)
        }
        .padding(.horizontal, isCompact ? 10 : FileListColumnLayout.horizontalPadding)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected
                    ? TelegramTheme.accent.opacity(0.18)
                    : isHovering
                        ? CloudStorageSurface.hover
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected
                    ? TelegramTheme.accent.opacity(0.5)
                    : Color.clear,
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovering ? 1.005 : 1.0)
        .shadow(
            color: isSelected ? TelegramTheme.accent.opacity(0.14) : Color.clear,
            radius: 4, x: 0, y: 2
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovering = hovering }
        .onTapGesture { onTap() }
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
    let titleColor: Color
    let titleWeight: Font.Weight
    let titleFontSize: CGFloat
    let iconColor: Color
    let iconOpacity: Double

    init(
        items: [HeaderItem],
        leadingPadding: CGFloat,
        titleColor: Color = TelegramTheme.textSecondary.opacity(0.98),
        titleWeight: Font.Weight = .semibold,
        titleFontSize: CGFloat = 11,
        iconColor: Color = TelegramTheme.accent,
        iconOpacity: Double = 0.95
    ) {
        self.items = items
        self.leadingPadding = leadingPadding
        self.titleColor = titleColor
        self.titleWeight = titleWeight
        self.titleFontSize = titleFontSize
        self.iconColor = iconColor
        self.iconOpacity = iconOpacity
    }
    
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
                            .foregroundStyle(iconColor)
                            .opacity(iconOpacity)
                    }
                    
                    Text(item.title)
                        .font(.system(size: titleFontSize, weight: titleWeight))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
        .overlay(TelegramTheme.panelBackground.opacity(0.18))
    }
}


// MARK: - Responsive Transfer Table Layout
/// 传输中心按照可用宽度逐级隐藏低优先级列，文件名和操作列始终保留。
private struct TransferColumnMetrics {
    let showType: Bool
    let showSpeed: Bool
    let typeWidth: CGFloat
    let statusWidth: CGFloat
    let speedWidth: CGFloat
    let progressWidth: CGFloat
    let actionWidth: CGFloat
    let columnSpacing: CGFloat
    let horizontalPadding: CGFloat
    let badgeSize: CGFloat
    let rowHeight: CGFloat

    init(availableWidth: CGFloat) {
        if availableWidth >= 980 {
            showType = true
            showSpeed = true
            typeWidth = 72
            statusWidth = 100
            speedWidth = 88
            progressWidth = 168
            actionWidth = 72
            columnSpacing = 10
            horizontalPadding = 16
            badgeSize = 42
            rowHeight = 74
        } else if availableWidth >= 720 {
            showType = false
            showSpeed = true
            typeWidth = 0
            statusWidth = 92
            speedWidth = 76
            progressWidth = 136
            actionWidth = 64
            columnSpacing = 8
            horizontalPadding = 14
            badgeSize = 40
            rowHeight = 72
        } else {
            showType = false
            showSpeed = false
            typeWidth = 0
            statusWidth = 82
            speedWidth = 0
            progressWidth = availableWidth < 560 ? 104 : 124
            actionWidth = 58
            columnSpacing = 8
            horizontalPadding = 12
            badgeSize = 36
            rowHeight = 70
        }
    }
}

/// 与传输行共用同一份列宽数据，避免表头与内容错位。
private struct TransferTableHeaderView: View {
    let metrics: TransferColumnMetrics

    var body: some View {
        HStack(spacing: metrics.columnSpacing) {
            headerLabel("文件", icon: "doc")
                .frame(maxWidth: .infinity, alignment: .leading)

            if metrics.showType {
                headerLabel("类型")
                    .frame(width: metrics.typeWidth, alignment: .leading)
            }

            headerLabel("状态")
                .frame(width: metrics.statusWidth, alignment: .leading)

            if metrics.showSpeed {
                headerLabel("速度")
                    .frame(width: metrics.speedWidth, alignment: .leading)
            }

            headerLabel("进度")
                .frame(width: metrics.progressWidth, alignment: .leading)

            headerLabel("操作")
                .frame(width: metrics.actionWidth, alignment: .center)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, 8)
        .background(
            ZStack(alignment: .bottom) {
                CloudStorageSurface.panel
                Divider().opacity(0.1)
            }
        )
    }

    private func headerLabel(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .opacity(0.8)
            }

            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(TelegramTheme.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}


// MARK: - TransferListRowView (商业级传输行组件)
/// 带渐变进度条、状态徽章、悬停按钮的传输任务行
private struct TransferListRowView: View {
    let item: TransferItem
    let index: Int
    let metrics: TransferColumnMetrics
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
        TelegramTheme.statusColor(for: item.status)
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: item.taskType == .upload
                ? [TelegramTheme.accent, TelegramTheme.accent.opacity(0.65)]
                : [TelegramTheme.success, TelegramTheme.accent.opacity(0.75)]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        HStack(spacing: metrics.columnSpacing) {
            HStack(spacing: metrics.badgeSize <= 36 ? 8 : 10) {
                Text(fileTypeBadge)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(item.taskType == .upload ? TelegramTheme.accent : TelegramTheme.success)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: metrics.badgeSize, height: metrics.badgeSize)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill((item.taskType == .upload ? TelegramTheme.accent : TelegramTheme.success).opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TelegramTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(2)

                    Text(fileMetadataText)
                        .font(.system(size: 12))
                        .foregroundColor(TelegramTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(2)

            if metrics.showType {
                Text(item.taskType.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: metrics.typeWidth, alignment: .leading)
            }

            Text(item.status)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: metrics.statusWidth - 8)
                .frame(height: 26)
                .background(Capsule().fill(statusColor.opacity(0.12)))
                .frame(width: metrics.statusWidth, alignment: .leading)

            if metrics.showSpeed {
                Text(isActive && !item.speed.isEmpty ? item.speed : "-")
                    .font(.system(size: 13))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: metrics.speedWidth, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(TelegramTheme.elevatedBackground)
                            .frame(height: 6)
                        Capsule()
                            .fill(progressGradient)
                            .frame(width: max(geo.size.width * CGFloat(item.progress), 0), height: 6)
                    }
                }
                .frame(height: 6)

                Text(item.progressPercent)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TelegramTheme.textSecondary)
            }
            .frame(width: metrics.progressWidth)

            HStack(spacing: 6) {
                if canResume {
                    Button(action: onStart) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(TelegramTheme.accent)
                    .help(item.taskType == .upload ? "开始上传" : "开始下载")
                } else if isActive {
                    Button(action: onPause) {
                        Image(systemName: "pause.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(TelegramTheme.warning)
                    .help("暂停")
                }

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundColor(TelegramTheme.danger.opacity(0.88))
                    .help("取消")
            }
            .frame(width: metrics.actionWidth, alignment: .center)
            .opacity(isHovering ? 1 : 0.78)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(height: metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovering
                      ? TelegramTheme.elevatedBackground.opacity(0.5)
                      : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(TelegramTheme.textSecondary.opacity(isHovering ? 0.16 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var fileTypeBadge: String {
        let ext = (item.name as NSString).pathExtension.uppercased()
        if !ext.isEmpty {
            return String(ext.prefix(3))
        }
        return item.taskType == .upload ? "UP" : "DN"
    }

    private var fileMetadataText: String {
        let locationAndSize = "\(item.directoryName) / \(item.sizeString)"
        if metrics.showType {
            return locationAndSize
        }
        return "\(item.taskType.rawValue) · \(locationAndSize)"
    }
}
import Foundation
import UserNotifications
import AppKit

/// NotificationCenter custom events
extension Notification.Name {
    static let switchToChat = Notification.Name("switchToChat")
    static let uploadTaskDidComplete = Notification.Name("uploadTaskDidComplete")
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
