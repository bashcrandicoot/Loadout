#if DEBUG
import SwiftUI
import AppKit

/// Debug only: renders the case animation offscreen (ImageRenderer, no window, no focus) to
/// PNG frames and a few stills. Run a Debug build with `LOADOUT_RENDER_CASE=<folder>`; encode
/// the frames with ffmpeg. The install and turn-off scenes replay progress traces recorded
/// from real Installer / LibraryActions runs into a throwaway sandbox (never Resolve's folders).
@MainActor
enum CaseFilm {
    static var requestedFolder: URL? {
        ProcessInfo.processInfo.environment["LOADOUT_RENDER_CASE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static let fps = 30.0
    static let canvas = CGSize(width: 640, height: 360)

    /// A recorded progress trace: (seconds since start, progress).
    struct Trace {
        var points: [(Double, Double)]
        var duration: Double { points.last?.0 ?? 0 }
        func value(at t: Double) -> Double {
            points.last(where: { $0.0 <= t })?.1 ?? 0
        }
        func stretched(to seconds: Double) -> Trace {
            let k = duration > 0 ? seconds / duration : 1
            return Trace(points: points.map { ($0.0 * k, $0.1) })
        }
    }

    private static var frameIndex = 0
    private static var folder: URL!

    static func run(_ out: URL) {
        folder = out
        let fm = FileManager.default
        try? fm.removeItem(at: out.appendingPathComponent("frames"))
        try? fm.createDirectory(at: out.appendingPathComponent("frames"), withIntermediateDirectories: true)
        let (install, unload, kinds, removed) = recordTraces()
        NSLog("CaseFilm: install trace %d points over %.4f s, unload %d points over %.4f s",
              install.points.count, install.duration, unload.points.count, unload.duration)
        let installCards = CaseCard.cards(kinds: kinds)
        let unloadCards = CaseCard.cards(items: removed)
        log(install, "install-trace", out)
        log(unload, "unload-trace", out)

        hoverScene()
        sheetScene(cards: installCards, trace: install,
                   caption: "Install · \(kinds.count) files · real progress trace (local APFS copy: \(String(format: "%.0f", install.duration * 1000)) ms)",
                   still: "stash")
        toastScene(cards: unloadCards, trace: unload, direction: .unload,
                   caption: "Turn off in the Library · real progress trace", text: "Turning off \(AppModel.describe(removed))",
                   still: "unload")
        sheetScene(cards: installCards, trace: install.stretched(to: 3.2),
                   caption: "Slow copy · the same trace stretched to 3.2 s (bar follows progress, cards wait)",
                   still: "slow")
        sheetScene(cards: installCards, trace: install, reduced: true,
                   caption: "Reduce Motion · crossfade + bar", still: "reduced")
        closeups(out)
        NSLog("CaseFilm: wrote %d frames", frameIndex)
    }

    // MARK: Traces

    private static func recordTraces() -> (Trace, Trace, [AssetKind], [LibraryItem]) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("LoadoutFilm-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let paths = ResolvePaths.sandbox(at: root)
        try? fm.createDirectory(at: paths.lutRoot, withIntermediateDirectories: true)
        try? fm.createDirectory(at: paths.templatesRoot, withIntermediateDirectories: true)
        let zip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOADOUT_RENDER_ZIP"] ?? "/tmp/loadout-drop/Cinematic Starter Pack.zip")
        guard let scan = try? PackScanner(stagingRoot: root.appendingPathComponent("Staging")).scan([zip]) else {
            fatalError("CaseFilm: couldn't scan \(zip.path)")
        }
        defer { scan.cleanUp() }
        let installer = Installer(paths: paths)
        let options = InstallOptions(packName: "Cinematic Starter Pack")
        var index = LibraryIndex()
        let planned = installer.plan(scan, options: options, index: index)
        let op = LocalFileOperator(trashDirectory: paths.trashDirectory)

        var points: [(Double, Double)] = []
        var start = Date()
        _ = try? installer.install(planned, options: options, sourceName: zip.lastPathComponent, index: &index, using: op) {
            points.append((Date().timeIntervalSince(start), $0))
        }
        let install = Trace(points: points)

        let items = LibraryScanner(paths: paths).scan(index: index).filter { $0.isManaged && $0.state == .enabled }
        let off = Array(items.prefix(4))
        points = []
        start = Date()
        try? LibraryActions(paths: paths).disable(off, using: op) { points.append((Date().timeIntervalSince(start), $0)) }
        return (install, Trace(points: points), planned.map(\.kind), off)
    }

    private static func log(_ trace: Trace, _ name: String, _ out: URL) {
        let text = trace.points.map { String(format: "%.6f\t%.4f", $0.0, $0.1) }.joined(separator: "\n")
        try? text.write(to: out.appendingPathComponent("\(name).tsv"), atomically: true, encoding: .utf8)
    }

    // MARK: Scenes

    private static func hoverScene() {
        let total = 2.4
        var t = 0.0
        while t < total {
            let pose = t < 0.5 ? CasePose(lidOpen: CaseMotion.idleOpen, latches: [0, 0]) : CaseMotion.hoverPose(elapsed: t - 0.5)
            let view = ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Color.accentColor.opacity(t < 0.5 ? 0 : 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(t < 0.5 ? 0 : 1)
                    .padding(EdgeInsets(top: 50, leading: 24, bottom: 20, trailing: 24))
                VStack(spacing: 10) {
                    CaseScene(frame: CaseFrame(pose), layout: .target).scaleEffect(1.25).frame(height: 190)
                    Text("Drop to install in Resolve").font(.title3.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .opacity(t < 0.5 ? 0 : 1)
                }
                .padding(.top, 30)
            }
            emit(view, caption: "Drag over the window · lid opens wide, case bounces",
                 still: abs(t - 0.95) < 0.5 / fps ? "hover" : nil)
            t += 1 / fps
        }
    }

    private static func sheetScene(cards: [CaseCard], trace: Trace, reduced: Bool = false, caption: String, still: String) {
        let idle = 0.8
        let driver = CaseDriver(direction: .stash, cards: cards.count, reduced: reduced)
        var t = 0.0, tail = 0.0
        var shots: [String: Double] = [:]
        while tail < 0.4 {
            let frame: CaseFrame
            if t < idle {
                frame = CaseFrame(.idle(cards: cards.count))
            } else {
                let run = t - idle
                driver.advance(by: t - idle < 0.5 / fps ? 0 : 1 / fps,
                               progress: trace.value(at: run), finished: run >= trace.duration)
                frame = driver.frame(badge: true)
                if driver.isSettled { tail += 1 / fps }
            }
            var name: String?
            let pose = frame.poses.last?.pose
            if !reduced, let pose {
                if shots["fly"] == nil, pose.cards.contains(where: { $0.travel > 0.45 && $0.travel < 0.6 }), pose.cards.contains(where: { $0.travel < 0 }) {
                    shots["fly"] = t; name = "\(still)-1-cards-flying"
                } else if shots["lid"] == nil, driver.doneTime != nil, pose.lidOpen < 0.45, pose.lidOpen > 0.2 {
                    shots["lid"] = t; name = "\(still)-2-lid-shutting"
                } else if shots["glint"] == nil, let g = pose.glint, g > 0.4 {
                    shots["glint"] = t; name = "\(still)-3-latched-glint"
                }
            } else if reduced, shots["x"] == nil, frame.poses.count == 2, (frame.poses.last?.opacity ?? 0) > 0.45 {
                shots["x"] = t; name = "\(still)-crossfade"
            }
            if still != "stash" && still != "reduced" { name = nil }
            emit(sheetMock(CaseScene(frame: frame, direction: .stash, cards: cards, layout: .sheet, badgeText: "Restart"),
                           installing: t >= idle),
                 caption: caption, still: name)
            t += 1 / fps
        }
        if still == "stash" { emitStillOnly(name: "stash-4-done") }
    }

    private static var lastView: AnyView?

    private static func toastScene(cards: [CaseCard], trace: Trace, direction: CaseDirection, caption: String, text: String, still: String) {
        let driver = CaseDriver(direction: direction, cards: cards.count)
        var t = 0.0, tail = 0.0
        var shot = false
        while tail < 0.4 {
            driver.advance(by: t == 0 ? 0 : 1 / fps, progress: trace.value(at: t), finished: t >= trace.duration)
            if driver.isSettled { tail += 1 / fps }
            let frame = driver.frame(badge: false)
            var name: String?
            if !shot, let pose = frame.poses.last?.pose, pose.cards.contains(where: { $0.travel > 0.35 && $0.travel < 0.5 }) {
                shot = true; name = "\(still)-lifting-out"
            }
            let toast = ZStack(alignment: .topLeading) {
                CaseScene(frame: frame, direction: direction, cards: cards, layout: .toast)
                Text(text).font(.callout.weight(.medium)).lineLimit(2).frame(width: 180, alignment: .leading)
                    .padding(.leading, 18).padding(.top, 16)
            }
            .background(Color(white: 0.985), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.1)))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            let view = ZStack(alignment: .bottom) {
                libraryMock
                toast.scaleEffect(1.3, anchor: .bottom).padding(.bottom, 26)
            }
            emit(view, caption: caption, still: name)
            t += 1 / fps
        }
    }

    // MARK: Mocks (solid colours: materials don't render offscreen)

    private static func sheetMock<V: View>(_ stage: V, installing: Bool) -> some View {
        VStack(spacing: 0) {
            stage.frame(maxWidth: .infinity).padding(.top, 6).background(Color(white: 0.965))
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Cinematic Starter Pack.zip").font(.headline)
                Text("LUTs, titles and a .drfx bundle, ready for Resolve").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Spacer()
                Text("Cancel").padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color(white: 0.9), in: RoundedRectangle(cornerRadius: 6)).opacity(installing ? 0.5 : 1)
                Text(installing ? "Installing…" : "Install to Resolve").foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(installing ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 6))
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color(white: 0.955))
        }
        .frame(width: 540, height: 290)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.12)))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 6)
        .padding(.top, 34)
    }

    private static var libraryMock: some View {
        let colors: [Color] = [.orange, .pink, .purple, .blue, .teal, .indigo, .mint, .red]
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), spacing: 14), count: 4), spacing: 14) {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [colors[i].opacity(0.55), colors[(i + 3) % 8].opacity(0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 78)
                    .opacity(i < 4 ? 1 : 0.9)
            }
        }
        .padding(.top, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The rigged case at 1 pt per artboard unit (2× pixels), to check the stack against
    /// Maddy's flattened references (and the seam at the lid's top corners).
    private static func closeups(_ out: URL) {
        let poses: [(String, CasePose)] = [("closed", .shut(badge: false)),
                                          ("latches-open", CasePose(lidOpen: 0, latches: [0, 0], bar: 1)),
                                          ("open", CasePose(lidOpen: CaseMotion.stashOpen, latches: [0, 0], bar: 0.45))]
        for (name, pose) in poses {
            let view = ZStack(alignment: .topLeading) {
                Color(red: 0.92, green: 0.92, blue: 0.94)
                CaseBack(pose: pose, scale: 1)
                CaseFront(pose: pose, scale: 1)
            }
            .frame(width: 640, height: 560)
            write(view, to: out.appendingPathComponent("closeup-\(name).png"))
        }
    }

    // MARK: Output

    private static func emit<V: View>(_ content: V, caption: String, still: String?) {
        let view = ZStack(alignment: .topLeading) {
            Color(red: 0.925, green: 0.93, blue: 0.945)
            content.frame(width: canvas.width, height: canvas.height, alignment: .top)
            Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.4))
                .padding(.leading, 14).padding(.top, 10)
        }
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.colorScheme, .light)
        lastView = AnyView(view)
        write(view, to: folder.appendingPathComponent("frames").appendingPathComponent(String(format: "f%05d.png", frameIndex)))
        frameIndex += 1
        if let still { write(view, to: folder.appendingPathComponent("loadout-case-\(still).png")) }
    }

    private static func emitStillOnly(name: String) {
        if let lastView { write(lastView, to: folder.appendingPathComponent("loadout-case-\(name).png")) }
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
