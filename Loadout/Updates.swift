import SwiftUI
import Combine
import Sparkle

/// App updates, powered by Sparkle (https://sparkle-project.org), set up like Lodge's.
///
/// Sparkle reads the feed at `SUFeedURL` (Info.plist), shows its own "A new version is
/// available" window, and only installs updates signed with the private key that matches
/// `SUPublicEDKey` (Loadout's own key, Keychain account `loadout`). See docs/RELEASING.md.
@MainActor
enum AppUpdates {
    /// The one Sparkle controller for the app's lifetime. It isn't started for the unit tests'
    /// host or screenshot mode, so those never check for (or show) updates.
    static let controller = SPUStandardUpdaterController(
        startingUpdater: shouldStart, updaterDelegate: nil, userDriverDelegate: nil)

    static var updater: SPUUpdater { controller.updater }

    private static var shouldStart: Bool {
        !AppModel.isRunningUnitTests && !Screenshots.isActive
    }
}

/// Keeps "Check for Updates…" disabled while a check is already running
/// (the standard Sparkle SwiftUI pattern).
final class CheckForUpdatesViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
}

/// Loadout ▸ Check for Updates…
struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!viewModel.canCheckForUpdates)
    }
}
