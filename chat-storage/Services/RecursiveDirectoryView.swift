
import SwiftUI

struct RecursiveDirectoryView: View {
    let nodes: [DirectoryItem]
    @Binding var selectedId: Int64?
    @Binding var expandedIds: Set<Int64>

    var onCreate: (DirectoryItem) -> Void
    var onMove: (DirectoryItem) -> Void
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
                onMove: onMove,
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

    var onCreate: (DirectoryItem) -> Void
    var onMove: (DirectoryItem) -> Void
    var onRename: (DirectoryItem) -> Void
    var onDelete: (DirectoryItem) -> Void
    var onUpload: (DirectoryItem) -> Void

    @State private var isHovering = false

    var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedIds.contains(item.id) },
            set: { isExp in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isExp { expandedIds.insert(item.id) }
                    else { expandedIds.remove(item.id) }
                }
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
                        onMove: onMove,
                        onRename: onRename,
                        onDelete: onDelete,
                        onUpload: onUpload
                    )
                } label: {
                    nodeContent(hasChildren: true)
                }
            } else {
                nodeContent(hasChildren: false)
            }
        }
    }

    private func nodeContent(hasChildren: Bool) -> some View {
        HStack(spacing: 8) {
            // 文件夹图标 - 选中时 accentColor，否则 orange
            Image(systemName: hasChildren ? (isExpanded.wrappedValue ? "folder.fill" : "folder") : "folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    selectedId == item.id
                    ? TelegramTheme.accent
                    : TelegramTheme.warning.opacity(0.9)
                )
                .frame(width: 20)

            Text(item.fileName)
                .font(.system(size: 13, weight: selectedId == item.id ? .semibold : .regular))
                .foregroundColor(selectedId == item.id ? TelegramTheme.textPrimary : TelegramTheme.textSecondary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    selectedId == item.id
                    ? TelegramTheme.accent.opacity(0.2)
                    : isHovering
                        ? TelegramTheme.elevatedBackground.opacity(0.75)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    selectedId == item.id ? TelegramTheme.accent.opacity(0.52) : Color.clear,
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: selectedId)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedId = item.id
            }
        }
        .contextMenu {
            Button("新建") { onCreate(item) }
            Button("选择") { selectedId = item.id }
            Button("重命名") { onRename(item) }
            Button("上传") { onUpload(item) }
            Divider()
            Button("删除", role: .destructive) { onDelete(item) }
        }
    }
}
