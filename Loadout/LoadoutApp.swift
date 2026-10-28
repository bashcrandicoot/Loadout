import SwiftUI
import AppKit

/// The entry point. Unit tests get an empty host with no windows.
@main
enum LoadoutLauncher {
    static func main() {
        #if DEBUG
        if let folder = CaseFilm.requestedFolder {
            // Offscreen film of the case animation: no windows, never activates.
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            MainActor.assumeIsolated { CaseFilm.run(folder) }
            exit(0)
        }
        #endif
        if AppModel.isRunningUnitTests {
            LoadoutTestHost.main()
        } else {
            LoadoutApp.main()
        }
    }
}

struct LoadoutTestHost: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

struct LoadoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        Window("Loadout", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1240, height: 780)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Loadout") { Support.showAboutPanel() }
                Button("Support Loadout…") { Support.openTipJar() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Assets…") { model.chooseFiles() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .sidebar) {
                Button("Reload Library") { model.reload() }
                    .keyboardShortcut("r")
            }
            CommandGroup(replacing: .help) {
                Button("Contact Support…") { Support.contactSupport() }
                Button("Support Loadout…") { Support.openTipJar() }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// Files opened from Finder or dropped on the Dock icon, plus a few launch options for screenshots.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: AppModel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if AppModel.isRunningUnitTests { NSApp.setActivationPolicy(.prohibited) }
        switch ProcessInfo.processInfo.environment["LOADOUT_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppModel.isRunningUnitTests else { return }
        Screenshots.startIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in Self.model?.handleDrop(urls) }
    }
}

/// `LOADOUT_SCREENSHOT=1` (with `open -g -j`) shows the window behind other apps without
/// activating Loadout, so `screencapture -l` can capture it while the user keeps working.
/// `LOADOUT_DEMO_DROP=/path.zip` opens the drop sheet for that file (after `LOADOUT_DEMO_DROP_DELAY` seconds).
/// `LOADOUT_DEMO_INSTALL_AFTER=s` then presses Install; `LOADOUT_DEMO_TURN_OFF_AFTER=s` turns off
/// the first three items Loadout installed (sandbox only), to watch the case run live.
enum Screenshots {
    static var isActive: Bool { ProcessInfo.processInfo.environment["LOADOUT_SCREENSHOT"] == "1" }

    @MainActor static func startIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard isActive else { return }
        drawWindowsAsActive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.unhideWithoutActivation()
            for window in NSApp.windows where window.isVisible || window.title == "Loadout" {
                if let size = env["LOADOUT_WINDOW_SIZE"]?.split(separator: "x"), size.count == 2,
                   let w = Double(size[0]), let h = Double(size[1]), window.title == "Loadout" {
                    window.setContentSize(NSSize(width: w, height: h))
                }
                window.orderBack(nil)
            }
            if let drop = env["LOADOUT_DEMO_DROP"], !drop.isEmpty {
                // LOADOUT_DEMO_DROP_DELAY=seconds leaves time to capture the Library first.
                let delay = Double(env["LOADOUT_DEMO_DROP_DELAY"] ?? "") ?? 0.4
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    AppDelegate.model?.handleDrop([URL(fileURLWithPath: drop)])
                    showDropSheetPanel(over: NSApp.windows.first { $0.title == "Loadout" })
                    if let after = Double(env["LOADOUT_DEMO_INSTALL_AFTER"] ?? "") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + after) { AppDelegate.model?.installPending() }
                    }
                }
            }
            if let after = Double(env["LOADOUT_DEMO_TURN_OFF_AFTER"] ?? ""), env["LOADOUT_SANDBOX"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + after) {
                    guard let model = AppDelegate.model else { return }
                    model.setEnabled(false, Array(model.items.filter { $0.isManaged && $0.state == .enabled }.prefix(3)))
                }
            }
        }
    }

    /// A sheet on a background window never finishes laying out, so screenshot mode shows the
    /// drop sheet's content in its own panel, placed where the sheet would be.
    static var showsDropSheetInPanel: Bool {
        isActive && !(ProcessInfo.processInfo.environment["LOADOUT_DEMO_DROP"] ?? "").isEmpty
    }
    private static var panel: NSWindow?

    @MainActor static func showDropSheetPanel(over parent: NSWindow?, attempt: Int = 0) {
        guard let model = AppDelegate.model else { return }
        guard model.pending != nil else {
            if attempt < 50 && model.errorMessage == nil {   // the scan runs in the background
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showDropSheetPanel(over: parent, attempt: attempt + 1) }
            }
            return
        }
        let host = NSHostingView(rootView: DropSheet().environmentObject(model))
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Install"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.contentView = host
        window.isReleasedWhenClosed = false
        if let frame = parent?.frame {
            window.setFrameTopLeftPoint(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - 52))
        }
        window.orderBack(nil)
        panel = window
    }

    /// Draws windows with their active look although Loadout stays in the background.
    static func drawWindowsAsActive() {
        let alwaysActive: @convention(block) (AnyObject) -> Bool = { _ in true }
        let implementation = imp_implementationWithBlock(alwaysActive)
        for name in ["isKeyWindow", "isMainWindow", "_hasActiveAppearance",
                     "_hasActiveAppearanceIgnoringKeyFocus", "hasKeyAppearance", "hasMainAppearance"] {
            if let method = class_getInstanceMethod(NSWindow.self, NSSelectorFromString(name)) {
                method_setImplementation(method, implementation)
            }
        }
    }
}
