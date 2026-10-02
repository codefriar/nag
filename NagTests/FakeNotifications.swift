import Foundation

/// Test double for `NotificationPosting`. It records every post and can
/// throw a configured error. With `holdPosts`, each post suspends until
/// `releasePost()` is called, so tests can observe the in-flight state.
actor FakeNotifications: NotificationPosting {
    struct Post: Equatable, Sendable {
        let title: String
        let subtitle: String?
        let body: String?
    }

    private(set) var posts: [Post] = []
    private let state: AuthorizationState
    private var postError: (any Error)?
    private let holdPosts: Bool
    private var postStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?

    init(
        state: AuthorizationState = .authorized(alertStyle: .alert),
        postError: (any Error)? = nil,
        holdPosts: Bool = false
    ) {
        self.state = state
        self.postError = postError
        self.holdPosts = holdPosts
    }

    func setPostError(_ error: (any Error)?) {
        postError = error
    }

    func authorizationState() async -> AuthorizationState {
        state
    }

    func post(title: String, subtitle: String?, body: String?) async throws {
        posts.append(Post(title: title, subtitle: subtitle, body: body))
        if holdPosts {
            postStarted = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            await withCheckedContinuation { release = $0 }
        }
        if let postError { throw postError }
    }

    func waitUntilPostStarted() async {
        guard !postStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releasePost() {
        release?.resume()
        release = nil
    }
}
