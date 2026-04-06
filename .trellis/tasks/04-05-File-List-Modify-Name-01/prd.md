文件重命名功能实现计划                                                                                                                                              
                                                                                                                                                                     
 Context                                                                                                                                                             
                                                                                                                                                                     
 云盘文件列表中的文件名带有流水号前缀（如 20240101_abc123_report.pdf），用户难以识别。本次新增文件重命名功能，允许用户为文件设置自定义名称。                         
                                                                                                                                                                  
 涉及：
 - 服务端（Java）：新增 FILE_RENAME_REQ(0x44) 帧处理逻辑
 - 客户端协议文档（Swift/macOS）：输出请求/响应规范，供客户端团队实现

 ---
 一、二进制帧协议（Wire Protocol）

 帧结构（8字节头 + payload）

 [0xFA][0xCE][frameType:1B][flags:1B][dataLen:4B(big-endian)][data:N B(UTF-8 JSON)]

 ┌───────────┬──────┬──────────────────────────────┐
 │   字段    │ 大小 │             说明             │
 ├───────────┼──────┼──────────────────────────────┤
 │ Magic     │ 2B   │ 固定 0xFA 0xCE               │
 ├───────────┼──────┼──────────────────────────────┤
 │ frameType │ 1B   │ 帧类型编码                   │
 ├───────────┼──────┼──────────────────────────────┤
 │ flags     │ 1B   │ 固定 0x00                    │
 ├───────────┼──────┼──────────────────────────────┤
 │ dataLen   │ 4B   │ payload 字节数（big-endian） │
 ├───────────┼──────┼──────────────────────────────┤
 │ data      │ N B  │ UTF-8 编码 JSON              │
 └───────────┴──────┴──────────────────────────────┘

 相关帧类型

 ┌─────────────────┬──────┬─────────────────┬────────────────────────────┐
 │      帧名       │ Code │      方向       │            说明            │
 ├─────────────────┼──────┼─────────────────┼────────────────────────────┤
 │ FILE_RENAME_REQ │ 0x44 │ Client → Server │ 文件重命名请求（新增）     │
 ├─────────────────┼──────┼─────────────────┼────────────────────────────┤
 │ FILE_RESPONSE   │ 0x43 │ Server → Client │ 文件操作响应（已有，复用） │
 └─────────────────┴──────┴─────────────────┴────────────────────────────┘

 ---
 二、服务端实现（Java）

 改动文件

 ┌────────────────────────────────────────────────────────────────────────────────────────┬───────────────────────────────────────┐
 │                                          文件                                          │                 改动                  │
 ├────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────┤
 │ src/main/java/com/alibaba/server/nio/model/file/FileUploadFrame.java                   │ 新增枚举项 FILE_RENAME_REQ(0x44)      │
 ├────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────┤
 │ src/main/java/com/alibaba/server/nio/repository/file/service/FileService.java          │ 新增接口方法 renameFile()             │
 ├────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────┤
 │ src/main/java/com/alibaba/server/nio/repository/file/service/impl/FileServiceImpl.java │ 实现 renameFile()                     │
 ├────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────┤
 │ src/main/java/com/alibaba/server/nio/service/file/handler/TextTransmissionHandler.java │ switch 新增 case + handleFileRename() │
 └────────────────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────┘

 2.1 FileUploadFrame.java — 新增枚举项

 在 FILE_RESPONSE(0x43) 之后插入：

 /**
  * 文件重命名请求
  */
 FILE_RENAME_REQ(0x44, "文件重命名请求"),

 2.2 FileService.java — 新增接口方法

 /**
  * 重命名文件（DB + 文件系统）
  *
  * @param fileId      文件ID
  * @param newFileName 新文件名（含扩展名）
  * @return 更新后的文件信息
  * @throws IllegalArgumentException 参数非法或文件不存在
  * @throws RuntimeException         文件系统重命名失败
  */
 FileDto renameFile(Long fileId, String newFileName);

 2.3 FileServiceImpl.java — 实现 renameFile()

 参考已有的 deleteFileWithFs() 和 updateDirectory() 模式：

 @Override
 public FileDto renameFile(Long fileId, String newFileName) {
     // 1. 参数校验
     if (fileId == null) {
         throw new IllegalArgumentException("文件ID不能为空");
     }
     if (StringUtils.isBlank(newFileName)) {
         throw new IllegalArgumentException("新文件名不能为空");
     }

     // 2. 查询文件记录
     FileDo fileDo = fileRepository.get(fileId);
     if (fileDo == null) {
         throw new IllegalArgumentException("文件不存在");
     }
     if (!YesOrNoEnum.Y.name().equals(fileDo.getIsFile())) {
         throw new IllegalArgumentException("只能对文件进行重命名，不支持目录");
     }

     // 3. 文件系统重命名（先于DB操作）
     String oldFilePath = fileDo.getFilePath();
     String newFilePath = oldFilePath; // 若filePath为空则只更新DB
     if (StringUtils.isNotBlank(oldFilePath)) {
         File oldFile = new File(oldFilePath);
         if (oldFile.exists() && oldFile.isFile()) {
             String parentPath = oldFile.getParent();
             File newFile = new File(parentPath + File.separator + newFileName);
             if (!oldFile.renameTo(newFile)) {
                 throw new RuntimeException("文件系统重命名失败: " + oldFilePath);
             }
             newFilePath = newFile.getAbsolutePath();
         }
     }

     // 4. 更新DB（fileName + filePath + gmtModified）
     FileDo updateDo = new FileDo();
     updateDo.setId(fileId);
     updateDo.setFileName(newFileName);
     updateDo.setFilePath(newFilePath);
     updateDo.setGmtModified(new Date());
     fileRepository.updateSelective(updateDo);

     log.info("文件重命名成功: fileId={}, oldName={}, newName={}", fileId, fileDo.getFileName(), newFileName);

     // 5. 返回最新文件详情
     return getFileDetail(fileId);
 }

 关键依赖：
 - fileRepository.get(fileId) — 已有，直接复用
 - fileRepository.updateSelective(fileDo) — 已有，直接复用（参考 updateDirectory 第652行）
 - getFileDetail(fileId) — 已有，直接复用

 2.4 TextTransmissionHandler.java — 分发与处理

 switch 新增 case（在 FILE_DETAIL_REQ case 后插入）：

 case FILE_RENAME_REQ:
     handleFileRename(frame, context);
     break;

 新增 handleFileRename 方法（与 handleFileDelete 同区块）：

 private void handleFileRename(FileUploadFrame frame, SocketChannelContext context) {
     try {
         // 1. 登录校验
         if (context.getUserDTO() == null) {
             sendErrorResponse(context, FrameType.FILE_RESPONSE, "未登录，无法修改文件名", "NOT_LOGGED_IN");
             return;
         }

         // 2. 解析请求
         JSONObject request = JSON.parseObject(frame.getDataAsString());
         Long fileId = request.getLong("fileId");
         String newFileName = request.getString("newFileName");

         // 3. 参数前置校验
         if (fileId == null || org.apache.commons.lang.StringUtils.isBlank(newFileName)) {
             sendErrorResponse(context, FrameType.FILE_RESPONSE, "fileId 和 newFileName 不能为空", "INVALID_REQUEST");
             return;
         }

         // 4. 调用 Service
         FileDto result = getFileService().renameFile(fileId, newFileName);
         sendSuccessResponse(context, FrameType.FILE_RESPONSE, "文件重命名成功", result);
         log.info("文件重命名成功: fileId={}, newFileName={}", fileId, newFileName);

     } catch (IllegalArgumentException e) {
         sendErrorResponse(context, FrameType.FILE_RESPONSE, e.getMessage(), "FILE_NOT_FOUND");
     } catch (RuntimeException e) {
         log.error("文件重命名文件系统异常", e);
         sendErrorResponse(context, FrameType.FILE_RESPONSE, "文件重命名失败，请稍后重试", "FS_ERROR");
     } catch (Exception e) {
         log.error("文件重命名系统异常", e);
         sendErrorResponse(context, FrameType.FILE_RESPONSE, "文件重命名失败，请稍后重试", "DB_ERROR");
     }
 }

 错误处理矩阵（全部使用 FILE_RESPONSE = 0x43）

 ┌───────────────────────────┬─────────┬──────────────────────┐
 │           场景            │ success │      errorCode       │
 ├───────────────────────────┼─────────┼──────────────────────┤
 │ 未登录                    │ false   │ NOT_LOGGED_IN        │
 ├───────────────────────────┼─────────┼──────────────────────┤
 │ fileId / newFileName 为空 │ false   │ INVALID_REQUEST      │
 ├───────────────────────────┼─────────┼──────────────────────┤
 │ 文件不存在 / 目标为目录   │ false   │ FILE_NOT_FOUND       │
 ├───────────────────────────┼─────────┼──────────────────────┤
 │ 文件系统重命名失败        │ false   │ FS_ERROR             │
 ├───────────────────────────┼─────────┼──────────────────────┤
 │ DB / 系统异常             │ false   │ DB_ERROR             │
 ├───────────────────────────┼─────────┼──────────────────────┤
 │ 成功                      │ true    │ —（data 含 FileDto） │
 └───────────────────────────┴─────────┴──────────────────────┘

 ---
 三、客户端协议设计（Swift / macOS）

 ▎ 以下为客户端实现规范，服务端不包含任何客户端逻辑。

 3.1 连接端口

 文件重命名请求走 文本/聊天通道（port 10086），与文件列表、删除等操作共用同一长连接。

 3.2 请求帧构造

 帧类型: 0x44（FILE_RENAME_REQ）

 请求 JSON payload:
 {
   "fileId": 7408085068658278401,
   "newFileName": "季报2024.pdf"
 }

 Swift 帧构造示例:
 func buildRenameFrame(fileId: Int64, newFileName: String) -> Data {
     let magic: [UInt8] = [0xFA, 0xCE]
     let frameType: UInt8 = 0x44          // FILE_RENAME_REQ
     let flags: UInt8 = 0x00

     let payload: [String: Any] = [
         "fileId": fileId,
         "newFileName": newFileName
     ]
     let jsonData = try! JSONSerialization.data(withJSONObject: payload)
     let dataLen = Int32(jsonData.count).bigEndian

     var frame = Data()
     frame.append(contentsOf: magic)
     frame.append(frameType)
     frame.append(flags)
     withUnsafeBytes(of: dataLen) { frame.append(contentsOf: $0) }
     frame.append(jsonData)
     return frame
 }

 3.3 响应帧解析

 响应帧类型: 0x43（FILE_RESPONSE，已有）

 响应 JSON 结构（成功）:
 {
   "success": true,
   "message": "文件重命名成功",
   "data": {
     "id": 7408085068658278401,
     "fileName": "季报2024.pdf",
     "filePath": "/data/user/dirA/季报2024.pdf",
     "fileSize": 102400,
     "fileType": "pdf",
     "isFile": "Y"
   }
 }

 响应 JSON 结构（失败）:
 {
   "success": false,
   "message": "文件不存在",
   "errorCode": "FILE_NOT_FOUND",
   "data": null
 }

 Swift 响应解析示例:
 func parseRenameResponse(_ data: Data) {
     // 1. 解析帧头（8字节）
     guard data.count >= 8 else { return }
     let magic = [data[0], data[1]]
     guard magic == [0xFA, 0xCE] else { return }

     let frameType = data[2]                    // 期望 0x43 (FILE_RESPONSE)
     // let flags = data[3]
     let dataLen = data[4...7].withUnsafeBytes {
         $0.load(as: Int32.self).bigEndian
     }

     // 2. 读取 payload
     guard data.count >= 8 + Int(dataLen) else { return }
     let jsonData = data[8..<(8 + Int(dataLen))]

     // 3. 解析 JSON
     guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let success = json["success"] as? Bool else { return }

     if success {
         // 刷新文件列表 UI
         let fileInfo = json["data"] as? [String: Any]
         let newName = fileInfo?["fileName"] as? String
         print("重命名成功，新文件名: \(newName ?? "")")
     } else {
         let errorCode = json["errorCode"] as? String ?? "UNKNOWN"
         let message = json["message"] as? String ?? "未知错误"
         print("重命名失败: [\(errorCode)] \(message)")
     }
 }

 3.4 客户端错误码处理建议

 ┌─────────────────┬──────────────────────────────┐
 │    errorCode    │          建议提示语          │
 ├─────────────────┼──────────────────────────────┤
 │ NOT_LOGGED_IN   │ 请重新登录后再操作           │
 ├─────────────────┼──────────────────────────────┤
 │ INVALID_REQUEST │ 文件ID或新文件名不能为空     │
 ├─────────────────┼──────────────────────────────┤
 │ FILE_NOT_FOUND  │ 文件不存在或已被删除         │
 ├─────────────────┼──────────────────────────────┤
 │ FS_ERROR        │ 文件系统操作失败，请稍后重试 │
 ├─────────────────┼──────────────────────────────┤
 │ DB_ERROR        │ 服务器内部错误，请稍后重试   │
 └─────────────────┴──────────────────────────────┘

 3.5 交互流程图

 Client (Swift)                    Server (Java :10086)
      |                                    |
      |  ① 用户在文件列表点击"重命名"         |
      |  ② 弹出输入框，用户输入新文件名        |
      |  ③ 确认后构造 0x44 帧               |
      |-------- FILE_RENAME_REQ (0x44) --->|
      |         payload: {fileId, newFileName}
      |                                    |  ④ 校验登录态
      |                                    |  ⑤ 查询文件记录
      |                                    |  ⑥ 文件系统 rename
      |                                    |  ⑦ 更新 DB
      |<-------- FILE_RESPONSE (0x43) -----|
      |         payload: {success, data/errorCode}
      |                                    |
      |  ⑧ success=true → 刷新列表展示新名   |
      |  ⑧ success=false → 弹出错误提示     |

 ---
 四、验证方案

 1. 用 Java 调试客户端（参考 DirectoryClient.java 模式）构造 0x44 帧发送，验证服务端返回 0x43 成功响应
 2. 检查服务器存储目录，确认物理文件已被重命名
 3. 检查数据库 file 表对应记录的 fileName 和 filePath 字段已更新
 4. 发送 FILE_LIST_REQ(0x40) 验证列表返回新文件名
 5. 异常路径测试：传入不存在的 fileId、空 newFileName、目录 ID，验证错误码正确
