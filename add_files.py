#!/usr/bin/env python3
"""
自动添加 Swift 文件到 Xcode 项目
"""

import subprocess
import os
import sys

def add_files_to_xcode():
    """使用 xcodebuild 命令添加文件"""
    
    project_path = "/Users/hljy/macProjects/chat-storage/chat-storage.xcodeproj"
    
    files_to_add = [
        "chat-storage/Models/frame/FrameTypeEnum.swift",
        "chat-storage/Models/frame/Frame.swift",
        "chat-storage/Models/frame/FrameBuilder.swift",
        "chat-storage/Models/frame/FrameParser.swift",
        "chat-storage/Models/request/UserRequest.swift",
        "chat-storage/Models/do/UserDO.swift",
        "chat-storage/Services/AuthenticationService.swift",
        "chat-storage/SocketManager+FrameHandling.swift",
    ]
    
    print("📋 需要添加的文件：")
    for f in files_to_add:
        full_path = f"/Users/hljy/macProjects/chat-storage/{f}"
        exists = "✅" if os.path.exists(full_path) else "❌"
        print(f"  {exists} {f}")
    
    print("\n⚠️  由于 Xcode 项目文件的复杂性，请按以下步骤手动添加：\n")
    print("1. 关闭 Xcode")
    print("2. 打开 Xcode")
    print("3. 在项目导航器中右键点击 'chat-storage' 组")
    print("4. 选择 'Add Files to \"chat-storage\"...'")
    print("5. 按住 Cmd 键，选中以下内容：")
    print("   - Models 文件夹")
    print("   - Services 文件夹")
    print("   - SocketManager+FrameHandling.swift")
    print("6. 勾选 'Create groups' 和 'Add to targets: chat-storage'")
    print("7. 点击 Add")
    print("\n✅ 完成后按 Shift+Cmd+K 清理，然后 Cmd+B 编译")

if __name__ == "__main__":
    add_files_to_xcode()
