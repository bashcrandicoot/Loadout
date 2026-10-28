import SwiftUI
import AppKit

/// Who makes Loadout and how to reach them.
enum Support {
    static let developerName = "bashframes"
    static let email = "bashframes@gmail.com"
    static let tipJarURL = URL(string: "https://ko-fi.com/bashframes")!
    static let longName = "Loadout for DaVinci Resolve"

    static var emailURL: URL { mailURL(body: nil) }
    static var supportEmailURL: URL { mailURL(body: "\n\n—\n\(versionSummary)") }

    static func mailURL(subject: String = "Loadout Support", body: String?) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let body { components.queryItems?.append(URLQueryItem(name: "body", value: body)) }
        return components.url ?? URL(string: "mailto:\(email)")!
    }

    /// "Loadout 1.0.0 (1), macOS 15.1.0, DaVinci Resolve 21.1.0"
    static var versionSummary: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var text = "Loadout \(version) (\(build)), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        if let resolve = ResolveDetector.find().first { text += ", \(resolve.displayName)" }
        return text
    }

    static var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(string: "\(longName)\nMade by \(developerName)\nSupport: ", attributes: base)
        var link = base
        link[.link] = emailURL
        credits.append(NSAttributedString(string: email, attributes: link))
        credits.append(NSAttributedString(string: "\n\nNot affiliated with Blackmagic Design.", attributes: base))
        return credits
    }

    static func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutCredits])
    }

    static func contactSupport() { NSWorkspace.shared.open(supportEmailURL) }
    static func openTipJar() { NSWorkspace.shared.open(tipJarURL) }
}

/// The "Made by bashframes · Support" line at the bottom of Settings.
struct SettingsCreditsFooter: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Made by \(Support.developerName)")
            Text("·").accessibilityHidden(true)
            Link("Support", destination: Support.supportEmailURL)
                .help("Email \(Support.email)")
            Text("·").accessibilityHidden(true)
            Link("Support Loadout ♥", destination: Support.tipJarURL)
                .help("Leave a tip for Loadout on Ko-fi")
                .accessibilityLabel("Support Loadout")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
