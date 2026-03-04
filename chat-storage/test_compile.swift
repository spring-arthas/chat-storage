
import SwiftUI

struct Friend: Identifiable, Hashable {
    let id: Int64
    let name: String
    let status: String
    let avatarColor: Color
    let avatarBase64: String?
}

struct ChatMessage: Identifiable, Equatable {
    var id: String { UUID().uuidString }
    let content: String
    let isMe: Bool
}

struct ChatDetailView: View {
    let friend: Friend
    var body: some View {
        Text(friend.name)
    }
}
