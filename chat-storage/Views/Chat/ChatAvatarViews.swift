//
//  ChatAvatarViews.swift
//  chat-storage
//

import AppKit
import SwiftUI

enum ChatAvatarCache {
    static let shared = NSCache<NSString, NSImage>()
}

enum CurrentUserAvatarDisplay {
    static func initials(for name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "用" }
        return String(trimmed.prefix(2))
    }
}

struct CurrentUserAvatarBadge: View {
    let avatar: String?
    let username: String?
    var size: CGFloat = 34
    var fallbackColor: Color = TelegramTheme.success

    private var fallbackName: String {
        CurrentUserAvatarDisplay.initials(for: username)
    }

    var body: some View {
        Group {
            if let avatar, !avatar.isEmpty {
                AvatarDecodeView(
                    base64: avatar,
                    fallbacName: fallbackName,
                    fallbackColor: fallbackColor,
                    cache: ChatAvatarCache.shared,
                    customSize: size
                )
            } else {
                Circle()
                    .fill(fallbackColor.opacity(0.95))
                    .overlay(
                        Text(fallbackName)
                            .font(.system(size: max(11, size * 0.34), weight: .black))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.62)
                            .lineLimit(1)
                            .padding(.horizontal, 3)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct CurrentUserIdentityView: View {
    let avatar: String?
    let username: String?
    var subtitle: String? = nil
    var avatarSize: CGFloat = 36

    private var displayName: String {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "当前用户" : trimmed
    }

    var body: some View {
        HStack(spacing: 10) {
            CurrentUserAvatarBadge(avatar: avatar, username: username, size: avatarSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TelegramTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

enum AvatarImageEncoder {
    static func jpegBase64(from image: NSImage, maxPixelSize: CGFloat = 512, compressionQuality: CGFloat = 0.78) -> String? {
        guard let resized = resizedImage(image, maxPixelSize: maxPixelSize),
              let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality]) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    private static func resizedImage(_ image: NSImage, maxPixelSize: CGFloat) -> NSImage? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = min(1, maxPixelSize / max(sourceSize.width, sourceSize.height))
        let targetSize = NSSize(width: max(1, floor(sourceSize.width * scale)),
                                height: max(1, floor(sourceSize.height * scale)))
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: sourceSize),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
}

struct InteractiveAvatarView: View {
    let base64String: String?
    let fallbacName: String
    let fallbackColor: Color
    let cache: NSCache<NSString, NSImage>

    @State private var showingPopover = false

    private var cachedImage: NSImage? {
        guard let base64 = base64String, !base64.isEmpty else { return nil }
        return cache.object(forKey: base64 as NSString)
    }

    var body: some View {
        Group {
            if let image = cachedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else if let base64 = base64String, !base64.isEmpty {
                AvatarDecodeView(base64: base64, fallbacName: fallbacName, fallbackColor: fallbackColor, cache: cache)
            } else {
                Circle()
                    .fill(fallbackColor)
                    .frame(width: 32, height: 32)
                    .overlay(Text(fallbacName).font(.caption).foregroundColor(.white))
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            showingPopover = true
        }
        .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
            VStack {
                if let image = cachedImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 256, height: 256)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else if let base64 = base64String, !base64.isEmpty {
                    AvatarDecodeView(base64: base64, fallbacName: fallbacName, fallbackColor: fallbackColor, cache: cache, customSize: 256)
                } else {
                    Circle()
                        .fill(fallbackColor)
                        .frame(width: 256, height: 256)
                        .overlay(
                            Text(fallbacName)
                                .font(.system(size: 80, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
            }
            .padding(12)
        }
    }
}

struct AvatarDecodeView: View {
    let base64: String
    let fallbacName: String
    let fallbackColor: Color
    let cache: NSCache<NSString, NSImage>
    var customSize: CGFloat = 32

    @State private var decodedImage: NSImage?

    var body: some View {
        Group {
            if let nsImage = decodedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: customSize, height: customSize)
                    .clipShape(RoundedRectangle(cornerRadius: customSize > 32 ? 8 : customSize / 2))
            } else {
                Circle()
                    .fill(fallbackColor)
                    .frame(width: customSize, height: customSize)
                    .overlay(Text(fallbacName).font(customSize > 32 ? .system(size: 80) : .caption).foregroundColor(.white))
            }
        }
        .task {
            await decodeImageAsync()
        }
    }

    private func decodeImageAsync() async {
        if let cached = cache.object(forKey: base64 as NSString) {
            await MainActor.run { self.decodedImage = cached }
            return
        }

        let pureBase64 = base64.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pureBase64.isEmpty else { return }

        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            if let avatarData = Data(base64Encoded: pureBase64, options: .ignoreUnknownCharacters),
               let nsImage = NSImage(data: avatarData) {
                return nsImage
            }
            return nil
        }.value

        if let validImage = image {
            cache.setObject(validImage, forKey: base64 as NSString)
            await MainActor.run {
                self.decodedImage = validImage
            }
        }
    }
}
