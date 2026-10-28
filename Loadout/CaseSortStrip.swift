import SwiftUI
import AppKit

// The case-sort strip: Maddy's install/uninstall counterpart of Lodge's wagon strip.
// A 41 pt header row over the dark 112 pt scene, 492 pt wide. The bar on the case is the real
// progress (`CaseRun.progress`): cards only land once their share of the files is in place.

/// Who and what a strip is about (the header's words and the scene's cards).
struct CaseSortSubject: Equatable {
    var wording: CaseRunWording
    /// The pack ("ATL Nights v3") or the items ("3 LUTs").
    var title: String
    /// The dropped file, for "Ready to install".
    var fileName: String?
    /// One per file.
    var kinds: [AssetKind]
    /// What Resolve needs afterwards (the badge on "Installed").
    var refresh: ResolveRefresh = .none

    var total: Int { kinds.count }
    var direction: CaseSortDirection { wording.direction }

    /// "24 LUTs · 6 titles · 2 transitions" (the three biggest kinds).
    var summary: String {
        let counts = Dictionary(kinds.map { ($0, 1) }, uniquingKeysWith: +)
        let top = AssetKind.allCases.filter { counts[$0] != nil }
            .sorted { counts[$0]! > counts[$1]! }.prefix(3)
        return AssetKind.allCases.filter { top.contains($0) }.map { $0.count(counts[$0]!) }.joined(separator: " · ")
    }

    static func assets(_ n: Int) -> String { "\(n) asset\(n == 1 ? "" : "s")" }
}

enum CaseRunWording: Equatable {
    case install
    case turnOn
    case turnOff
    case remove

    var direction: CaseSortDirection { self == .install || self == .turnOn ? .install : .uninstall }

    var working: String {
        switch self {
        case .install: return "Installing"
        case .turnOn: return "Turning on"
        case .turnOff: return "Turning off"
        case .remove: return "Removing"
        }
    }
}

/// One install, turn-on, turn-off or removal as the case shows it.
struct CaseRun: Identifiable, Equatable {
    let id = UUID()
    var subject: CaseSortSubject
    /// The real progress of the files moving, 0…1.
    var progress: Double = 0
    /// Every file is in place (and the index is saved).
    var finished = false

    var direction: CaseSortDirection { subject.direction }
    var layout: CaseSortLayout { CaseSortLayout(kinds: subject.kinds) }
}

enum Haptics {
    /// A soft tick as a latch snaps (only on a Force Touch trackpad; silent otherwise).
    static func latch() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

enum CaseBadge {
    /// What the "Installed" header asks of Resolve, if anything.
    static func text(for refresh: ResolveRefresh) -> String? {
        switch refresh {
        case .none: return nil
        case .updateLists: return "Update Lists"
        case .restart: return "Restart Resolve"
        }
    }
}

// MARK: - Header

struct CaseSortHeader: View {
    var label: CaseSortLabel
    var subject: CaseSortSubject

    var body: some View {
        HStack(spacing: 7) {
            icon
            Text(phase)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(phaseStyle)
                .fixedSize()
            Text(detail)
                .font(detailIsName ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundStyle(detailIsName ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 13)
        .frame(height: 41)
        .accessibilityElement(children: .combine)
    }

    private var isInstall: Bool { subject.wording == .install }

    private var phase: String {
        switch label {
        case .ready: return isInstall ? "Ready to install" : subject.wording.working
        case .working: return subject.wording.working
        case .installed:
            if subject.direction == .uninstall { return "Installed" }
            return subject.wording == .turnOn ? "Turned on" : "Installed"
        case .removed: return subject.wording == .remove ? "Removed" : "Turned off"
        }
    }

    private var phaseStyle: AnyShapeStyle {
        switch label {
        case .working: return AnyShapeStyle(Color.accentColor)
        case .installed: return AnyShapeStyle(Color.green)
        default: return AnyShapeStyle(.primary)
        }
    }

    private var detailIsName: Bool {
        switch label {
        case .ready: return isInstall
        case .working: return true
        default: return false
        }
    }

    private var detail: String {
        let n = subject.total
        switch label {
        case .ready: return isInstall ? (subject.fileName ?? subject.title) : subject.title
        case .working: return subject.title
        case .installed:
            return subject.direction == .uninstall ? "· \(subject.title)" : "· \(CaseSortSubject.assets(n)) in Resolve"
        case .removed:
            return subject.wording == .remove ? "· \(CaseSortSubject.assets(n)) moved to the Trash"
                                              : "· \(CaseSortSubject.assets(n)) out of Resolve"
        }
    }

    @ViewBuilder private var icon: some View {
        switch label {
        case .ready, .removed:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(caseHex: 0x8E5CF0))
                .overlay(Capsule().fill(.white).frame(width: 8, height: 2).offset(y: -2))
                .frame(width: 16, height: 16)
        case .working:
            Circle().fill(Color.accentColor)
                .overlay(Image(systemName: "arrow.down")   // her icon, both ways
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                .frame(width: 16, height: 16)
        case .installed:
            Circle().fill(Color.green)
                .overlay(Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder private var trailing: some View {
        let n = subject.total
        switch label {
        case .ready:
            Text(CaseSortSubject.assets(n)).font(.system(size: 12)).foregroundStyle(.secondary)
        case .working(let f):
            (Text("\(CaseSort.filesDone(f, of: n))").bold().foregroundColor(.primary)
             + Text(" of \(n) · \(Int((CaseSort.clamp(f) * 100).rounded(.down)))%"))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        case .installed:
            if subject.direction == .install, let badge = CaseBadge.text(for: subject.refresh) {
                Label(badge, systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .fixedSize()
            } else {
                Text(subject.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        case .removed:
            EmptyView()
        }
    }
}

// MARK: - Strip

/// The header and scene for one frame. Pure drawing, so the stills renderer uses it too.
struct CaseSortStripFrame: View {
    var label: CaseSortLabel
    var subject: CaseSortSubject
    var frame: CaseSortFrame
    var layout: CaseSortLayout

    static let width = 492.0
    static let headerHeight = 41.0

    var body: some View {
        VStack(spacing: 0) {
            CaseSortHeader(label: label, subject: subject)
            CaseSortScene(frame: frame, layout: layout)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .environment(\.colorScheme, .dark)
                .accessibilityHidden(true)
        }
        .frame(width: Self.width)
    }
}

/// The strip following a `CaseRun` (or waiting, before Install is pressed). Calls `onSettled`
/// once when a run has finished and its last frame has been held.
struct CaseSortStrip: View {
    var run: CaseRun?
    /// What it shows while there's no run.
    var subject: CaseSortSubject
    var onSettled: (UUID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = CaseSortEngine()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: run == nil || engine.settledID == run?.id)) { timeline in
            let driver = engine.step(at: timeline.date, run: run, reduced: reduceMotion, onSettled: onSettled)
            let shown = run?.subject ?? subject
            let idle = shown.direction == .install ? CaseSortPhases.ready : .installed
            CaseSortStripFrame(label: driver?.label ?? CaseSort.label(idle, direction: shown.direction),
                               subject: shown,
                               frame: driver?.frame ?? CaseSortFrame(idle),
                               layout: driver?.layout ?? engine.layout(for: shown.kinds))
        }
    }
}

/// Holds the driver for the run on screen. Not observed: the timeline redraws every frame.
final class CaseSortEngine {
    private(set) var settledID: UUID?
    private var runID: UUID?
    private var driver: CaseSortDriver?
    private var lastDate: Date?
    private var cachedKinds: [AssetKind]?
    private var cachedLayout: CaseSortLayout?

    func layout(for kinds: [AssetKind]) -> CaseSortLayout {
        if let cachedLayout, cachedKinds == kinds { return cachedLayout }
        let layout = CaseSortLayout(kinds: kinds)
        cachedKinds = kinds
        cachedLayout = layout
        return layout
    }

    func step(at date: Date, run: CaseRun?, reduced: Bool, onSettled: @escaping (UUID) -> Void) -> CaseSortDriver? {
        guard let run else {
            runID = nil
            driver = nil
            return nil
        }
        if run.id != runID {
            runID = run.id
            driver = CaseSortDriver(direction: run.direction, layout: layout(for: run.subject.kinds), reduced: reduced)
            lastDate = date
        }
        guard let driver else { return nil }
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        let events = driver.advance(by: dt, progress: run.progress, finished: run.finished)
        if events.contains(where: { $0 == .latchLeft || $0 == .latchRight }) {
            Haptics.latch()
        }
        if driver.isSettled, settledID != run.id {
            settledID = run.id
            let id = run.id
            DispatchQueue.main.async { onSettled(id) }
        }
        return driver
    }
}

// MARK: - Library toast and drag-over

/// A turn-off, turn-on or removal: the strip plays over the Library.
struct CaseToast: View {
    let run: CaseRun
    var onSettled: (UUID) -> Void

    var body: some View {
        CaseSortStrip(run: run, subject: run.subject, onSettled: onSettled)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .allowsHitTesting(false)
    }
}

/// The case in the window's drop highlight: the latches flip and the lid opens (her open phase).
struct CaseDropTarget: View {
    static let stage = CaseSortStage(centerX: 100, base: 124, scale: 0.3, lift: 0, arc: 0,
                                     size: CGSize(width: 200, height: 136))
    static let layout = CaseSortLayout(counts: [:], stage: stage)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            let open = reduceMotion ? 1 : CaseSort.clamp(timeline.date.timeIntervalSince(start) / CaseSort.openDuration)
            Self.scene(open: open)
        }
        .frame(width: Self.stage.size.width, height: Self.stage.size.height)
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }

    static func scene(open: Double) -> some View {
        Canvas { context, _ in
            CaseSortPainter(layout: layout, drawsDesk: false, drawsCards: false)
                .paint(CaseSortFrame(CaseSortPhases(open: open, progress: 0, arrival: 0)), in: &context)
        }
        .frame(width: stage.size.width, height: stage.size.height)
    }
}
