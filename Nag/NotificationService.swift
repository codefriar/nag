import Foundation
import UserNotifications

enum AlertStyle: Equatable, Sendable {
    case none, banner, alert
}

enum AuthorizationState: Equatable, Sendable {
    case denied
    case authorized(alertStyle: AlertStyle)
}

enum NotificationError: Error, Equatable {
    case notAuthorized
}

protocol NotificationPosting: Sendable {
    /// Requests permission on first use, then reports the current state.
    func authorizationState() async -> AuthorizationState
    func post(title: String, subtitle: String?, body: String?) async throws
}

struct NotificationService: NotificationPosting {
    func authorizationState() async -> AuthorizationState {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        switch settings.authorizationStatus {
        case .denied, .notDetermined:
            return .denied
        default:
            return .authorized(alertStyle: AlertStyle(settings.alertStyle))
        }
    }

    func post(title: String, subtitle: String?, body: String?) async throws {
        guard case .authorized = await authorizationState() else {
            throw NotificationError.notAuthorized
        }
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        if let body { content.body = body }
        content.sound = .default
        // A unique ID per request makes nags stack instead of replacing each other.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}

private extension AlertStyle {
    init(_ style: UNAlertStyle) {
        switch style {
        case .alert: self = .alert
        case .banner: self = .banner
        default: self = .none
        }
    }
}
