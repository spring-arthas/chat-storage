
import SwiftUI

struct RecursiveDirectoryView: View {
    let nodes: [DirectoryItem]
    @Binding var selectedId: Int64?
    @Binding var expandedIds: Set<Int64>
    var level: Int = 0

    var onCreate: (DirectoryItem) -> Void
    var onMove: (DirectoryItem) -> Void
    var onRename: (DirectoryItem) -> Void
    var onDelete: (DirectoryItem) -> Void
    var onUpload: (DirectoryItem) -> Void
    var onExpand: (DirectoryItem) -> Void = { _ in }

    var body: some View {
        ForEach(nodes) { item in
            DirectoryNodeView(
                item: item,
                selectedId: $selectedId,
                expandedIds: $expandedIds,
                level: level,
                onCreate: onCreate,
                onMove: onMove,
                onRename: onRename,
                onDelete: onDelete,
                onUpload: onUpload,
                onExpand: onExpand
            )
        }
    }
}

struct DirectoryNodeView: View {
    let item: DirectoryItem
    @Binding var selectedId: Int64?
    @Binding var expandedIds: Set<Int64>
    let level: Int

    var onCreate: (DirectoryItem) -> Void
    var onMove: (DirectoryItem) -> Void
    var onRename: (DirectoryItem) -> Void
    var onDelete: (DirectoryItem) -> Void
    var onUpload: (DirectoryItem) -> Void
    var onExpand: (DirectoryItem) -> Void

    @State private var isHovering = false

    var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedIds.contains(item.id) },
            set: { isExp in
                if isExp {
                    onExpand(item)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isExp { expandedIds.insert(item.id) }
                    else { expandedIds.remove(item.id) }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            nodeContent(hasChildren: item.hasChild)

            if item.hasChild,
               isExpanded.wrappedValue,
               let children = item.childFileList,
               !children.isEmpty {
                RecursiveDirectoryView(
                    nodes: children,
                    selectedId: $selectedId,
                    expandedIds: $expandedIds,
                    level: level + 1,
                    onCreate: onCreate,
                    onMove: onMove,
                    onRename: onRename,
                    onDelete: onDelete,
                    onUpload: onUpload,
                    onExpand: onExpand
                )
            }
        }
    }

    private func nodeContent(hasChildren: Bool) -> some View {
        HStack(spacing: 7) {
            if level > 0 {
                Color.clear
                    .frame(width: CGFloat(level * 14))
            }

            Group {
                if hasChildren {
                    Button {
                        isExpanded.wrappedValue.toggle()
                    } label: {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(TelegramTheme.textSecondary.opacity(0.72))
                            .frame(width: 12, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded.wrappedValue ? "收起目录" : "展开目录")
                } else {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4, weight: .bold))
                        .foregroundStyle(TelegramTheme.textSecondary.opacity(0.35))
                        .frame(width: 12)
                }
            }

            Image(systemName: "folder")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    selectedId == item.id
                    ? TelegramTheme.success
                    : TelegramTheme.textSecondary.opacity(0.62)
                )
                .frame(width: 17)

            Text(item.fileName)
                .font(.system(size: 13, weight: selectedId == item.id ? .bold : .semibold))
                .foregroundColor(selectedId == item.id ? TelegramTheme.success : TelegramTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(
                    selectedId == item.id
                    ? TelegramTheme.success.opacity(0.12)
                    : isHovering
                        ? TelegramTheme.elevatedBackground.opacity(0.55)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(
                    selectedId == item.id ? TelegramTheme.success.opacity(0.42) : Color.clear,
                    lineWidth: 1
                )
        )
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
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard item.hasChild else { return }
                isExpanded.wrappedValue.toggle()
            }
        )
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
