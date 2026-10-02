import AppKit
import SwiftUI
import UserNotifications

@main
struct NagApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = ComposeViewModel(
        notifications: NotificationService(),
        finish: { AppDelegate.finish() }
    )

    var body: some Scene {
        Window("New Nag", id: "compose") {
            ComposeView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be set before launch completes so foreground posts are presented.
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement apps don't come to the front on their own.
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Hides the window immediately, then quits after a short delay so the
    /// system can finish presenting the notification just posted.
    static func finish() {
        // orderOut (not close) so the last-window-closed rule doesn't quit early.
        NSApp.windows.forEach { $0.orderOut(nil) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            NSApp.terminate(nil)
        }
    }
}
