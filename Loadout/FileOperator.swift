import Foundation

/// One step of an install, a disable, an enable or a removal.
enum FileOp: Equatable {
    case makeDirectory(URL)
    /// Copies to a temporary name next to the destination, then renames (never a half-written file).
    case copy(from: URL, to: URL)
    case move(from: URL, to: URL)
    /// Moves to the Trash (undoable), never deletes.
    case trash(URL)

    var touchedURLs: [URL] {
        switch self {
        case .makeDirectory(let url), .trash(let url): return [url]
        case .copy(let from, let to), .move(let from, let to): return [from, to]
        }
    }
}

protocol FileOperating {
    /// Runs every step or none: if one fails, the ones before it are undone.
    func perform(_ ops: [FileOp]) throws
}

enum FileOpError: LocalizedError {
    case cancelled
    case privileged(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "The administrator password prompt was cancelled. Nothing was changed."
        case .privileged(let message): return message
        }
    }
}

/// Plain FileManager moves and copies, with rollback.
struct LocalFileOperator: FileOperating {
    /// Where trashed files go (tests); nil uses the user's Trash.
    var trashDirectory: URL?

    func perform(_ ops: [FileOp]) throws {
        let fm = FileManager.default
        var undo: [() -> Void] = []
        do {
            for op in ops {
                switch op {
                case .makeDirectory(let url):
                    var created: [URL] = []
                    var probe = url
                    while !fm.fileExists(atPath: probe.path) {
                        created.append(probe)
                        probe = probe.deletingLastPathComponent()
                    }
                    try fm.createDirectory(at: url, withIntermediateDirectories: true)
                    undo.append { for dir in created { try? fm.removeItem(at: dir) } }
                case .copy(let from, let to):
                    let temp = to.deletingLastPathComponent()
                        .appendingPathComponent(".loadout-\(UUID().uuidString)-\(to.lastPathComponent)")
                    try fm.copyItem(at: from, to: temp)
                    do {
                        try fm.moveItem(at: temp, to: to)
                    } catch {
                        try? fm.removeItem(at: temp)
                        throw error
                    }
                    undo.append { try? fm.removeItem(at: to) }
                case .move(let from, let to):
                    try fm.moveItem(at: from, to: to)
                    undo.append { try? fm.moveItem(at: to, to: from) }
                case .trash(let url):
                    let trashed: URL
                    if let trashDirectory {
                        try fm.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
                        trashed = Self.uniqueURL(trashDirectory.appendingPathComponent(url.lastPathComponent))
                        try fm.moveItem(at: url, to: trashed)
                    } else {
                        var result: NSURL?
                        try fm.trashItem(at: url, resultingItemURL: &result)
                        trashed = (result as URL?) ?? url
                    }
                    undo.append { try? fm.moveItem(at: trashed, to: url) }
                }
            }
        } catch {
            for step in undo.reversed() { step() }
            throw error
        }
    }

    /// `name.cube`, then `name 2.cube`, `name 3.cube`…
    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code) { return true }
        if ns.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EPERM)].contains(ns.code) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isPermissionError(underlying) }
        return false
    }
}

/// Runs the same steps as one shell script behind the standard macOS administrator prompt
/// (`do shell script … with administrator privileges`). Used only when the system LUT folder
/// refuses a normal write. Loadout never sees or stores the password.
struct PrivilegedFileOperator: FileOperating {
    func perform(_ ops: [FileOp]) throws {
        let script = Self.shellScript(for: ops, userID: getuid(), groupID: getgid(),
                                      trash: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
        let appleScript = "do shell script \(Self.appleScriptString(script)) with prompt \(Self.appleScriptString("Loadout wants to change DaVinci Resolve’s LUT folder.")) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: data, as: UTF8.self)
            if message.contains("-128") { throw FileOpError.cancelled }
            throw FileOpError.privileged("Couldn’t change the LUT folder: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// The shell script for `ops`. New files and folders are handed to the user, so later
    /// changes (disable, enable, remove) usually need no password.
    static func shellScript(for ops: [FileOp], userID: uid_t, groupID: gid_t, trash: URL) -> String {
        var lines = ["set -e"]
        let owner = "\(userID):\(groupID)"
        for op in ops {
            switch op {
            case .makeDirectory(let url):
                lines.append("mkdir -p \(q(url.path))")
                lines.append("chown \(owner) \(q(url.path))")
            case .copy(let from, let to):
                let temp = to.deletingLastPathComponent().appendingPathComponent(".loadout-\(UUID().uuidString)").path
                lines.append("cp -p \(q(from.path)) \(q(temp))")
                lines.append("chown \(owner) \(q(temp))")
                lines.append("mv -f \(q(temp)) \(q(to.path))")
            case .move(let from, let to):
                lines.append("mv \(q(from.path)) \(q(to.path))")
            case .trash(let url):
                let stamp = UUID().uuidString.prefix(8)
                let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
                let target = trash.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(stamp)\(ext)")
                lines.append("mv \(q(url.path)) \(q(target.path))")
                lines.append("chown \(owner) \(q(target.path))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Single-quotes for the shell.
    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// A double-quoted AppleScript string literal.
    static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Tries a normal write first; if the system LUT folder refuses it, asks for an administrator
/// password once for the whole batch.
struct AutoFileOperator: FileOperating {
    var paths: ResolvePaths

    func perform(_ ops: [FileOp]) throws {
        let local = LocalFileOperator(trashDirectory: paths.trashDirectory)
        do {
            try local.perform(ops)
        } catch where LocalFileOperator.isPermissionError(error)
                    && ops.contains(where: { $0.touchedURLs.contains(where: paths.mayNeedAdmin) }) {
            try PrivilegedFileOperator().perform(ops)
        }
    }
}
