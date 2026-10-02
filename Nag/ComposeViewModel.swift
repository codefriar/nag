import AppKit
import Observation

@MainActor
@Observable
final class ComposeViewModel {
    enum Hint: Equatable, Sendable {
        case deniedPermission
        case notPersistent
    }

    static let notificationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )!

    var title = ""
    var subtitle = ""
    var body = ""
    private(set) var hint: Hint?
    private(set) var errorMessage: String?
    private(set) var isSending = false

    var canSend: Bool { !Self.trimmed(title).isEmpty }

    private let notifications: any NotificationPosting
    private let finish: @MainActor () -> Void
    private let openURL: @MainActor (URL) -> Void

    init(
        notifications: any NotificationPosting,
        finish: @escaping @MainActor () -> Void,
        openURL: @escaping @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        self.notifications = notifications
        self.finish = finish
        self.openURL = openURL
    }

    func refreshStatus() async {
        switch await notifications.authorizationState() {
        case .denied:
            hint = .deniedPermission
        case .authorized(alertStyle: .alert):
            hint = nil
        case .authorized:
            hint = .notPersistent
        }
    }

    func send() async {
        guard canSend, !isSending else { return }
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        do {
            try await notifications.post(
                title: Self.trimmed(title),
                subtitle: Self.nilIfBlank(subtitle),
                body: Self.nilIfBlank(body)
            )
            finish()
        } catch NotificationError.notAuthorized {
            errorMessage = "Notifications are off for Nag."
            hint = .deniedPermission
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        finish()
    }

    func openNotificationSettings() {
        openURL(Self.notificationSettingsURL)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nilIfBlank(_ text: String) -> String? {
        let value = trimmed(text)
        return value.isEmpty ? nil : value
    }
}
