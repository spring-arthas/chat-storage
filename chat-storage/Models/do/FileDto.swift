
//
//  FileDto.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/31.
//

import Foundation

/// 文件/目录数据传输对象 (对应服务端 FileDto)
struct FileDto: Codable {
    /// 文件/目录ID
    let id: Int64
    
    /// 父ID
    let pId: Int64
    
    /// 文件/目录名称
    let fileName: String
    
    /// 文件路径
    let filePath: String
    
    /// 文件大小 (可能为空，目录没有大小)
    let fileSize: Int64?
    
    /// 文件类型
    let fileType: String
    
    /// 是否是文件 ("Y" 或 "N")
    let isFile: String
    
    /// 是否存在 ("Y" 或 "N")
    let isExist: String
    
    /// 是否有子节点 ("Y" 或 "N")
    let hasChild: String
    
    /// 用户名
    let userName: String?
    
    /// 创建时间 (时间戳)
    let gmtCreated: Int64?
    
    /// 修改时间 (时间戳)
    let gmtModified: Int64?
    
    /// 删除标记 ("Y" 或 "N")
    let del: String?
    
    /// 删除时间 (时间戳)
    let delTime: Int64?
    
    /// 子文件列表 (如果是目录且有子项，可能为空数组)
    let childFileList: [FileDto]?
    
    /// 是否是文件 (布尔值)
    var isFileBoolean: Bool {
        return isFile.uppercased() == "Y"
    }
    
    /// 是否存在 (布尔值)
    var isExistBoolean: Bool {
        return isExist.uppercased() == "Y"
    }
    
    /// 是否有子节点 (布尔值)
    var hasChildBoolean: Bool {
        return hasChild.uppercased() == "Y"
    }
    
    /// 是否已删除 (布尔值)
    var isDeleted: Bool {
        return del?.uppercased() == "Y"
    }
    
    /// 转换为 DirectoryItem (用于 UI 显示)
    func toDirectoryItem() -> DirectoryItem {
        let children = childFileList?.map { $0.toDirectoryItem() }
        
        return DirectoryItem(
            id: id,
            pId: pId,
            fileName: fileName,
            childFileList: children,
            fileSize: fileSize,
            isFile: isFileBoolean,
            uploadTime: gmtCreated,
            directoryName: nil // 可以在 UI 层根据 pId 查找或忽略
        )
    }
}

// MARK: - DirectoryItem (Moved here to ensure visibility)

struct DirectoryItem: Identifiable, CustomDebugStringConvertible, Codable, Hashable {
    let id: Int64
    let pId: Int64
    let fileName: String
    let childFileList: [DirectoryItem]?
    
    // New fields for file metadata
    let fileSize: Int64?
    let isFile: Bool
    let uploadTime: Int64? // Timestamp in milliseconds
    let directoryName: String? // Display purpose

    // Helper for UI
    var sizeString: String {
        guard let size = fileSize else { return "-" }
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

    var uploadTimeString: String {
        guard let time = uploadTime else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(time / 1000))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    var debugDescription: String {
        return "DirectoryItem(id: \(id), fileName: '\(fileName)', isFile: \(isFile), children: \(childFileList?.count ?? 0))"
    }

    // Default Init
    init(id: Int64, pId: Int64, fileName: String, childFileList: [DirectoryItem]?, fileSize: Int64? = nil, isFile: Bool = false, uploadTime: Int64? = nil, directoryName: String? = nil) {
        self.id = id
        self.pId = pId
        self.fileName = fileName
        self.childFileList = childFileList
        self.fileSize = fileSize
        self.isFile = isFile
        self.uploadTime = uploadTime
        self.directoryName = directoryName
    }
}
