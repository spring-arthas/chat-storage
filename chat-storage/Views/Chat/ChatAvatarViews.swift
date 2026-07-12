//
//  ChatAvatarViews.swift
//  chat-storage
//

import AppKit
import SwiftUI

enum ChatAvatarCache {
    static let shared = NSCache<NSString, NSImage>()
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
