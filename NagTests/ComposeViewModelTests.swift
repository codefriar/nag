import Foundation
import Testing

@MainActor
final class Spy {
    var finishCount = 0
    var openedURLs: [URL] = []
}

struct Boom: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
@Suite("ComposeViewModel")
struct ComposeViewModelTests {
    private func makeSUT(
        state: AuthorizationState = .authorized(alertStyle: .alert),
        postError: (any Error)? = nil,
        holdPosts: Bool = false
    ) -> (ComposeViewModel, FakeNotifications, Spy) {
        let fake = FakeNotifications(state: state, postError: postError, holdPosts: holdPosts)
        let spy = Spy()
        let viewModel = ComposeViewModel(
            notifications: fake,
            finish: { spy.finishCount += 1 },
            openURL: { spy.openedURLs.append($0) }
        )
        return (viewModel, fake, spy)
    }

    // MARK: canSend

    @Test("canSend is false for blank titles", arguments: ["", " ", "\n\t "])
    func canSendBlank(title: String) {
        let (viewModel, _, _) = makeSUT()
        viewModel.title = title
        #expect(!viewModel.canSend)
    }

    @Test("canSend is true for a non-blank title")
    func canSendValid() {
        let (viewModel, _, _) = makeSUT()
        viewModel.title = "Stand up"
        #expect(viewModel.canSend)
    }

    // MARK: send

    @Test("send posts trimmed values")
    func sendPostsTrimmedValues() async {
        let (viewModel, fake, _) = makeSUT()
        viewModel.title = "  Stand up \n"
        viewModel.subtitle = " now "
        viewModel.body = "\nStretch.\n"
        await viewModel.send()
        #expect(await fake.posts == [.init(title: "Stand up", subtitle: "now", body: "Stretch.")])
    }

    @Test("send passes nil for blank subtitle and body")
    func sendPassesNilForBlankOptionals() async {
        let (viewModel, fake, _) = makeSUT()
        viewModel.title = "Stand up"
        viewModel.subtitle = "   "
        viewModel.body = ""
        await viewModel.send()
        #expect(await fake.posts == [.init(title: "Stand up", subtitle: nil, body: nil)])
    }

    @Test("send finishes exactly once on success")
    func sendFinishesOnSuccess() async {
        let (viewModel, _, spy) = makeSUT()
        viewModel.title = "Stand up"
        await viewModel.send()
        #expect(spy.finishCount == 1)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isSending)
    }

    @Test("send when not authorized shows the error and keeps the window")
    func sendNotAuthorized() async {
        let (viewModel, _, spy) = makeSUT(postError: NotificationError.notAuthorized)
        viewModel.title = "Stand up"
        await viewModel.send()
        #expect(viewModel.errorMessage == "Notifications are off for Nag.")
        #expect(viewModel.hint == .deniedPermission)
        #expect(spy.finishCount == 0)
        #expect(viewModel.title == "Stand up")
    }

    @Test("send with a generic error shows its description and keeps the window")
    func sendGenericError() async {
        let (viewModel, _, spy) = makeSUT(postError: Boom())
        viewModel.title = "Stand up"
        await viewModel.send()
        #expect(viewModel.errorMessage == "boom")
        #expect(spy.finishCount == 0)
        #expect(!viewModel.isSending)
    }

    @Test("send does nothing when the title is blank")
    func sendNoopWhenCannotSend() async {
        let (viewModel, fake, spy) = makeSUT()
        viewModel.title = "   "
        await viewModel.send()
        #expect(await fake.posts.isEmpty)
        #expect(spy.finishCount == 0)
    }

    @Test("a second send while one is in flight is ignored")
    func secondSendWhileInFlightIsIgnored() async {
        let (viewModel, fake, spy) = makeSUT(holdPosts: true)
        viewModel.title = "Stand up"
        let first = Task { await viewModel.send() }
        await fake.waitUntilPostStarted()
        #expect(viewModel.isSending)
        await viewModel.send()
        await fake.releasePost()
        await first.value
        #expect(await fake.posts.count == 1)
        #expect(spy.finishCount == 1)
    }

    @Test("retrying after a failure clears the previous error")
    func retryClearsPreviousError() async {
        let (viewModel, fake, spy) = makeSUT(postError: Boom())
        viewModel.title = "Stand up"
        await viewModel.send()
        #expect(viewModel.errorMessage == "boom")
        await fake.setPostError(nil)
        await viewModel.send()
        #expect(viewModel.errorMessage == nil)
        #expect(spy.finishCount == 1)
    }

    // MARK: refreshStatus

    @Test("refreshStatus maps authorization state to a hint", arguments: [
        (AuthorizationState.denied, ComposeViewModel.Hint?.some(.deniedPermission)),
        (.authorized(alertStyle: .none), .some(.notPersistent)),
        (.authorized(alertStyle: .banner), .some(.notPersistent)),
        (.authorized(alertStyle: .alert), nil)
    ])
    func refreshStatusMapsHint(state: AuthorizationState, expected: ComposeViewModel.Hint?) async {
        let (viewModel, _, _) = makeSUT(state: state)
        await viewModel.refreshStatus()
        #expect(viewModel.hint == expected)
    }

    // MARK: cancel / settings

    @Test("cancel finishes without posting")
    func cancelFinishesWithoutPosting() async {
        let (viewModel, fake, spy) = makeSUT()
        viewModel.title = "Stand up"
        viewModel.cancel()
        #expect(spy.finishCount == 1)
        #expect(await fake.posts.isEmpty)
    }

    @Test("openNotificationSettings opens the Notifications settings pane")
    func openNotificationSettingsOpensPane() {
        let (viewModel, _, spy) = makeSUT()
        viewModel.openNotificationSettings()
        #expect(spy.openedURLs.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ])
    }
}
