import Foundation

/// Zip handling with the tools every Mac has (`ditto` and `zipinfo`).
enum Archive {
    enum Failure: LocalizedError {
        case tool(String, Int32, String)
        var errorDescription: String? {
            switch self {
            case let .tool(name, status, output): return "\(name) failed (\(status)): \(output)"
            }
        }
    }

    /// Unzips `zip` into `folder` (created if needed).
    static func extract(_ zip: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
    }

    /// Zips a folder's contents (used by tests to build packs).
    static func create(from folder: URL, to zip: URL, keepParent: Bool = false) throws {
        var args = ["-c", "-k", "--sequesterRsrc"]
        if keepParent { args.append("--keepParent") }
        try run("/usr/bin/ditto", args + [folder.path, zip.path])
    }

    /// The paths inside a zip.
    static func list(_ zip: URL) throws -> [String] {
        let output = try run("/usr/bin/zipinfo", ["-1", zip.path])
        return output.split(whereSeparator: \.isNewline).map(String.init)
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure.tool((tool as NSString).lastPathComponent, process.terminationStatus, output)
        }
        return output
    }
}
