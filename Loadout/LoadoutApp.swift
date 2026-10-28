import SwiftUI
import AppKit

/// The entry point. Unit tests get an empty host with no windows.
@main
enum LoadoutLauncher {
    static func main() {
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
/// `LOADOUT_DEMO_DROP=/path.zip` opens the drop sheet for that file.
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    AppDelegate.model?.handleDrop([URL(fileURLWithPath: drop)])
                }
            }
        }
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
