//
//  FileDto.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/31.
//

import Foundation

/// 文件/目录数据传输对象 (对应服务端 FileDto)
struct FileDto: Codable {
    /// 父ID
    let pId: Int64
    
    /// 子文件列表 (如果是目录且有子项)
    let childFileList: [FileDto]?
    
    /// 文件/目录名称
    let fileName: String
    
    /// 文件路径
    let filePath: String
    
    /// 文件大小
    let fileSize: Int64
    
    /// 文件类型
    let fileType: String
    
    /// 是否是文件 ("true" 或 "false")
    let isFile: String
    
    /// 是否存在 ("true" 或 "false")
    let isExist: String
    
    /// 是否是文件 (布尔值)
    var isFileBoolean: Bool {
        return isFile.lowercased() == "true"
    }
    
    /// 是否存在 (布尔值)
    var isExistBoolean: Bool {
        return isExist.lowercased() == "true"
    }
    
    /// 转换为 DirectoryItem (用于 UI 显示)
    func toDirectoryItem() -> DirectoryItem {
        let children: [DirectoryItem]? = childFileList?.map { $0.toDirectoryItem() }
        return DirectoryItem(name: fileName, children: children)
    }
}
