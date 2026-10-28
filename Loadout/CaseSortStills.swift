#if DEBUG
import SwiftUI
import AppKit

/// Debug only: renders case-sort stills offscreen (ImageRenderer, no window, no focus).
/// Run a Debug build with `LOADOUT_RENDER_CASE=<folder>`. It writes
///   demo-in-t<t>.png / demo-out-t<t>.png  her demo clock, 984 × 306, to set beside her renders
///   app-*.png                               real installs (a sandbox install's progress trace),
///                                           Reduce Motion, the badge and the drop target
/// No video: Mark records the app demos.
@MainActor
enum CaseSortStills {
    static var requestedFolder: URL? {
        ProcessInfo.processInfo.environment["LOADOUT_RENDER_CASE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static let installTimes = [0.4, 1.0, 1.25, 1.6, 2.4, 3.6, 4.8, 6.0, 6.9, 7.3, 7.9, 8.1, 8.3, 8.9]
    static let uninstallTimes = [0.5, 1.0, 1.2, 1.5, 1.8, 2.6, 4.0, 5.5, 7.2, 7.9, 8.6, 9.4]

    /// Her demo copy: ATL Nights, 24 LUTs, 6 titles and 2 transitions.
    static let demoSubject = CaseSortSubject(
        wording: .install, title: "ATL Nights v3", fileName: "ATL_Nights_Complete_v3.zip",
        kinds: Array(repeating: .lut, count: 24) + Array(repeating: .title, count: 6) + Array(repeating: .transition, count: 2))

    static func run(_ out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for t in installTimes { demo(t, uninstall: false, out) }
        for t in uninstallTimes { demo(t, uninstall: true, out) }
        appStills(out)
        NSLog("CaseSortStills: done")
    }

    private static func demo(_ t: Double, uninstall: Bool, _ out: URL) {
        let phases = CaseSort.demoPhases(at: t, uninstall: uninstall)
        var subject = demoSubject
        if uninstall { subject.wording = .remove }
        let view = CaseSortStripFrame(label: CaseSort.label(phases, direction: subject.direction), subject: subject,
                                      frame: CaseSortFrame(phases), layout: .demo)
        write(sheet(view), to: out.appendingPathComponent(String(format: "demo-%@-t%.2f.png", uninstall ? "out" : "in", t)))
    }

    /// Her mock's sheet: dark, #2A2A2D.
    private static func sheet<V: View>(_ view: V) -> some View {
        view.frame(width: 492, height: 153)
            .background(Color(caseHex: 0x2A2A2D))
            .environment(\.colorScheme, .dark)
    }

    // MARK: App stills

    private static func appStills(_ out: URL) {
        let (trace, kinds) = recordInstall()
        try? trace.map { String(format: "%.6f\t%.4f", $0.0, $0.1) }.joined(separator: "\n")
            .write(to: out.appendingPathComponent("app-install-trace.tsv"), atomically: true, encoding: .utf8)
        let subject = CaseSortSubject(wording: .install, title: "Cinematic Starter Pack",
                                      fileName: "Cinematic Starter Pack.zip", kinds: kinds,
                                      refresh: kinds.map(\.refresh).max() ?? .none)
        let layout = CaseSortLayout(kinds: kinds)
        let duration = trace.last?.0 ?? 0
        NSLog("CaseSortStills: real install of %d files took %.4f s", kinds.count, duration)

        // The real trace, played into the driver frame by frame (the copy is over in milliseconds,
        // so the cards keep her pace and never get ahead of it).
        func value(_ t: Double) -> Double { trace.last(where: { $0.0 <= t })?.1 ?? 0 }
        let driver = CaseSortDriver(direction: .install, layout: layout)
        let wanted: [(Double, String)] = [(0.5, "opening"), (1.6, "flying"), (3.0, "landing"), (layout.minimumDuration + 1.0, "arrival"),
                                          (layout.minimumDuration + 2.3, "latched"), (layout.minimumDuration + 3.2, "installed")]
        var t = 0.0
        var next = 0
        while next < wanted.count && t < 30 {
            t += 1.0 / 60
            driver.advance(by: 1.0 / 60, progress: value(t), finished: t >= duration)
            if t >= wanted[next].0 {
                write(sheet(CaseSortStripFrame(label: driver.label, subject: subject, frame: driver.frame, layout: layout)),
                      to: out.appendingPathComponent("app-install-\(next)-\(wanted[next].1).png"))
                next += 1
            }
        }
        // A slow copy: the same trace stretched to 12 s. The bar waits for the files.
        let slow = CaseSortDriver(direction: .install, layout: layout)
        t = 0
        while t < 6 {
            t += 1.0 / 60
            slow.advance(by: 1.0 / 60, progress: value(t / 12 * duration), finished: false)
        }
        write(sheet(CaseSortStripFrame(label: slow.label, subject: subject, frame: slow.frame, layout: layout)),
              to: out.appendingPathComponent("app-install-slow-copy-6s-of-12s.png"))

        // Reduce Motion: no flights; the bar follows progress, then a crossfade.
        let reduced = CaseSortDriver(direction: .install, layout: layout, reduced: true)
        reduced.advance(by: 0.05, progress: 0.55, finished: false)
        write(sheet(CaseSortStripFrame(label: reduced.label, subject: subject, frame: reduced.frame, layout: layout)),
              to: out.appendingPathComponent("app-reduced-0-progress.png"))
        reduced.advance(by: 0.05, progress: 1, finished: true)
        reduced.advance(by: 0.1, progress: 1, finished: true)
        write(sheet(CaseSortStripFrame(label: reduced.label, subject: subject, frame: reduced.frame, layout: layout)),
              to: out.appendingPathComponent("app-reduced-1-crossfade.png"))

        // The Library's turn-off toast at its midpoint, and a removal finished.
        let off = CaseSortSubject(wording: .turnOff, title: "4 LUTs", kinds: Array(repeating: .lut, count: 4))
        let offLayout = CaseSortLayout(kinds: off.kinds)
        let mid = CaseSortPhases(open: 1, progress: 0.5, arrival: 0)
        write(sheet(CaseSortStripFrame(label: CaseSort.label(mid, direction: .uninstall), subject: off,
                                       frame: CaseSortFrame(mid), layout: offLayout)),
              to: out.appendingPathComponent("app-toast-turn-off-mid.png"))

        write(ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 10) {
                CaseDropTarget.scene(open: 1)
                Text("Drop to install in Resolve").font(.title3.weight(.semibold)).foregroundStyle(Color.accentColor)
            }
        }.frame(width: 320, height: 220).environment(\.colorScheme, .light),
              to: out.appendingPathComponent("app-drop-target-open.png"))
    }

    /// Installs the sample pack into a throwaway sandbox (never Resolve's folders) and records
    /// the installer's progress reports.
    private static func recordInstall() -> ([(Double, Double)], [AssetKind]) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("LoadoutStills-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let paths = ResolvePaths.sandbox(at: root)
        try? fm.createDirectory(at: paths.lutRoot, withIntermediateDirectories: true)
        try? fm.createDirectory(at: paths.templatesRoot, withIntermediateDirectories: true)
        let zip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOADOUT_RENDER_ZIP"] ?? "/tmp/loadout-drop/Cinematic Starter Pack.zip")
        guard let scan = try? PackScanner(stagingRoot: root.appendingPathComponent("Staging")).scan([zip]) else {
            fatalError("CaseSortStills: couldn't scan \(zip.path)")
        }
        defer { scan.cleanUp() }
        let installer = Installer(paths: paths)
        let options = InstallOptions(packName: "Cinematic Starter Pack")
        var index = LibraryIndex()
        let planned = installer.plan(scan, options: options, index: index)
        var points: [(Double, Double)] = []
        let start = Date()
        _ = try? installer.install(planned, options: options, sourceName: zip.lastPathComponent, index: &index,
                                   using: LocalFileOperator(trashDirectory: paths.trashDirectory)) {
            points.append((Date().timeIntervalSince(start), $0))
        }
        return (points, planned.map(\.kind))
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
