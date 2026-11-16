import Foundation
import UserNotifications

@MainActor
struct SystemNotifications: NotificationPosting {
    static let lowSpaceIdentifier = "cachepop.lowspace"

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func postLowSpace(availableBytes: Int64) {
        Task {
            guard await requestPermission() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Your Mac is running out of space"
            content.body = "Only \(ByteSize.string(availableBytes)) is free. Open CachePop to see what can be cleaned."
            content.sound = .default
            let request = UNNotificationRequest(identifier: Self.lowSpaceIdentifier, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

@MainActor
struct SilentNotifications: NotificationPosting {
    func requestPermission() async -> Bool { false }
    func postLowSpace(availableBytes: Int64) {}
}
