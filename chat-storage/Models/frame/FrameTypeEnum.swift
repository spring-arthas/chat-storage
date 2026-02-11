//
//  FrameTypeEnum.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

/// 帧类型枚举
enum FrameTypeEnum: UInt8, CaseIterable {
    // ========== 基础帧 (0x01-0x0F) ==========
    /// 元数据帧：包含文件名、大小、类型等信息
    case metaFrame = 0x01
    /// 数据帧：包含文件字节流数据
    case dataFrame = 0x02
    /// 结束帧：标识文件传输结束
    case endFrame = 0x03
    /// 确认帧：服务端发送给客户端的确认响应
    case ackFrame = 0x04
    /// 断点检查帧：客户端请求检查文件上传断点
    case resumeCheck = 0x05
    /// 断点应答帧：服务端返回已上传大小和续传信息
    case resumeAck = 0x06
    
    // ========== 目录操作帧 (0x10-0x1F) ==========
    /// 目录新建请求
    case dirCreateReq = 0x10
    /// 目录删除请求
    case dirDeleteReq = 0x11
    /// 目录更新请求
    case dirUpdateReq = 0x12
    /// 目录移动请求
    case dirMoveReq = 0x13
    /// 目录操作响应
    case dirResponse = 0x14
    /// 目录列表请求
    case dirListReq = 0x15
    
    // ========== 目录文件上传帧 (0x20-0x2F) ==========
    /// 目录文件元数据帧
    case dirFileMeta = 0x20
    /// 目录文件数据帧
    case dirFileData = 0x21
    /// 目录文件结束帧
    case dirFileEnd = 0x22
    /// 目录文件确认帧
    case dirFileAck = 0x23
    
    // ========== 用户认证帧 (0x30-0x3F) ==========
    /// 用户注册请求
    case userRegisterReq = 0x30
    /// 用户登录请求
    case userLoginReq = 0x31
    /// 用户修改密码请求
    case userChangePwdReq = 0x32
    /// 用户退出登录请求
    case userLogoutReq = 0x33
    /// 用户操作响应
    case userResponse = 0x34
    
    /// 搜索用户请求 (0x36)
    case searchUserReq = 0x36
    /// 添加好友请求 (0x37)
    case addFriendReq = 0x37
    /// 获取未处理好友申请请求 (0x38)
    case pendingRequestsReq = 0x38
    /// 处理好友申请请求 (0x39)
    case handleFriendReq = 0x39
    
    // ========== 文件操作帧 (0x40-0x4F) ==========
    /// 文件列表分页请求
    case fileListReq = 0x40
    /// 文件删除请求 (0x41)
    case fileDeleteReq = 0x41
    /// 文件详情请求 (0x42)
    case fileDetailReq = 0x42
    /// 文件操作响应
    case fileResponse = 0x43
    
    /// 帧类型描述
    var description: String {
        switch self {
        case .metaFrame: return "元数据帧"
        case .dataFrame: return "数据帧"
        case .endFrame: return "结束帧"
        case .ackFrame: return "确认帧"
        case .resumeCheck: return "断点检查帧"
        case .resumeAck: return "断点应答帧"
            
        case .dirCreateReq: return "目录新建请求"
        case .dirDeleteReq: return "目录删除请求"
        case .dirUpdateReq: return "目录更新请求"
        case .dirMoveReq: return "目录移动请求"
        case .dirResponse: return "目录操作响应"
        case .dirListReq: return "目录列表请求"
            
        case .dirFileMeta: return "目录文件元数据"
        case .dirFileData: return "目录文件数据"
        case .dirFileEnd: return "目录文件结束"
        case .dirFileAck: return "目录文件确认"
            
        case .userRegisterReq: return "用户注册请求"
        case .userLoginReq: return "用户登录请求"
        case .userChangePwdReq: return "用户修改密码请求"
        case .userLogoutReq: return "用户退出登录请求"
        case .userResponse: return "用户操作响应"
        case .searchUserReq: return "搜索用户请求"
        case .addFriendReq: return "添加好友请求"
        case .pendingRequestsReq: return "获取好友申请列表"
        case .handleFriendReq: return "处理好友申请"
            
        case .fileListReq: return "文件列表请求"
        case .fileDetailReq: return "文件详情请求"
        case .fileDeleteReq: return "文件删除请求"
        case .fileResponse: return "文件操作响应"
        }
    }
    
    /// 从原始值创建枚举
    static func from(rawValue: UInt8) -> FrameTypeEnum? {
        return FrameTypeEnum(rawValue: rawValue)
    }
}
