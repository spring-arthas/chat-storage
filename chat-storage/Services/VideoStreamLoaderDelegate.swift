//
//  VideoStreamLoaderDelegate.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/7.
//

import Foundation

/// 流式数加载器代理协议
public protocol VideoStreamLoaderDelegate: AnyObject {
    /// 收到文件元数据
    func didReceiveContentInfo(totalSize: Int64, mimeType: String)
    /// 收到视频数据片段
    func didReceiveVideoData(_ data: Data, range: Range<Int64>)
    /// 下载完成
    func didFinishLoading()
    /// 发生错误
    func didFail(with error: Error)
}
