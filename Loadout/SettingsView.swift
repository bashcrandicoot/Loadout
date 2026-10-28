import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            FoldersSettings()
                .tabItem { Label("Folders", systemImage: "folder") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Show Resolve’s built-in LUTs", isOn: $model.showBuiltIn)
                Text("ACES, Arri, Film Looks and the other folders Resolve installs. Loadout never changes them.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("LUT preview frame", selection: $model.sampleFrame) {
                    ForEach(SampleFrame.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("DaVinci Resolve") {
                LabeledContent("Installed") {
                    Text(model.resolve?.displayName ?? "Not found")
                }
                if let resolve = model.resolve {
                    LabeledContent("Location") {
                        Text((resolve.appURL.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            Section {
                SettingsCreditsFooter()
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
    }
}

private struct FoldersSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Where Loadout installs") {
                folder("LUTs and DCTLs", model.paths.lutRoot.appendingPathComponent(ResolvePaths.lutSubfolder))
                folder("Fusion templates", model.paths.templatesRoot.appendingPathComponent("Edit"))
                folder(".drfx bundles", model.paths.templatesRoot)
            }
            Section("Loadout’s own files") {
                folder("Turned-off items", model.paths.parkedRoot)
                folder("Library index", model.paths.indexURL)
            }
            Section {
                Text("Resolve’s LUT folder is shared by every user on this Mac. If macOS protects it, Loadout asks for an administrator password with the standard macOS prompt. Loadout never sees or stores the password.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
    }

    private func folder(_ title: String, _ url: URL) -> some View {
        LabeledContent(title) {
            HStack {
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption.monospaced()).lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
                Button {
                    let existing = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
                    NSWorkspace.shared.activateFileViewerSelecting([existing])
                } label: { Image(systemName: "arrow.right.circle") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
    }
}
