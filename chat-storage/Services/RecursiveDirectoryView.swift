
import SwiftUI

struct RecursiveDirectoryView: View {
    let nodes: [DirectoryItem]
    @Binding var selectedId: Int64?
    @Binding var expandedIds: Set<Int64>
    
    // Actions
    var onCreate: (DirectoryItem) -> Void
    var onMove: (DirectoryItem) -> Void
    var onRename: (DirectoryItem) -> Void
    var onDelete: (DirectoryItem) -> Void
    
    var body: some View {
        ForEach(nodes) { item in
            DirectoryNodeView(
                item: item,
                selectedId: $selectedId,
                expandedIds: $expandedIds,
                onCreate: onCreate,
                onMove: onMove,
                onRename: onRename,
                onDelete: onDelete
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
    var onMove: (DirectoryItem) -> Void
    var onRename: (DirectoryItem) -> Void
    var onDelete: (DirectoryItem) -> Void
    
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
                        onMove: onMove,
                        onRename: onRename,
                        onDelete: onDelete
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
            Image(systemName: item.childFileList == nil ? "folder" : "folder.fill")
                .foregroundColor(.blue)
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
            Button("新建") { onCreate(item) }
            Button("移动") { onMove(item) }
            Button("重命名") { onRename(item) }
            Divider()
            Button("删除") { onDelete(item) }
        }
    }
}
