import SwiftUI

struct ComposeView: View {
    @Bindable var viewModel: ComposeViewModel
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bannerText {
                banner(bannerText)
            }
            Form {
                TextField("Title", text: $viewModel.title)
                    .focused($titleFocused)
                TextField("Subtitle", text: $viewModel.subtitle)
                TextField("Message", text: $viewModel.body, axis: .vertical)
                    .lineLimit(3...8)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Send") { Task { await viewModel.send() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canSend || viewModel.isSending)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            titleFocused = true
            await viewModel.refreshStatus()
        }
    }

    private var bannerText: String? {
        if let errorMessage = viewModel.errorMessage { return errorMessage }
        switch viewModel.hint {
        case .deniedPermission:
            return "Notifications are off for Nag."
        case .notPersistent:
            return "Nags will disappear on their own. Set Nag to “Alerts” to keep them on screen."
        case nil:
            return nil
        }
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if viewModel.hint != nil {
                Button("Open Settings") { viewModel.openNotificationSettings() }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
