import Foundation
import os

/// Opt-in lifecycle logging. The app runs as a menu bar utility with no console,
/// so a sudden exit otherwise leaves nothing behind but a system crash report.
/// Enable with `--debug` on the command line, by setting the `debug` default,
/// or from the status item menu.
final class DebugLog {
    static let shared = DebugLog()

    private let logger = Logger(subsystem: "local.ruixiang.macbookduo", category: "lifecycle")
    private let queue = DispatchQueue(label: "local.macbookduo.debuglog", qos: .utility)
    private let formatter: DateFormatter
    private var handle: FileHandle?
    private var enabledFlag: Bool

    /// `~/Library/Logs/Duo Effect/debug.log`, rotated once it passes 4 MB.
    private(set) var fileURL: URL

    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Duo Effect", isDirectory: true)
        fileURL = logs.appendingPathComponent("debug.log")
        enabledFlag = CommandLine.arguments.contains("--debug")
            || UserDefaults.standard.bool(forKey: "debug")
        if enabledFlag { openFile() }
    }

    var isEnabled: Bool { queue.sync { enabledFlag } }

    func setEnabled(_ on: Bool) {
        queue.sync {
            guard on != enabledFlag else { return }
            enabledFlag = on
            UserDefaults.standard.set(on, forKey: "debug")
            if on { openFile() } else { handle?.closeFile(); handle = nil }
        }
        log(on ? "debug logging enabled" : "debug logging disabled")
    }

    func log(_ message: @autoclosure () -> String) {
        // The autoclosure keeps message construction off the hot path when off.
        guard isEnabled else { return }
        let line = "\(formatter.string(from: Date())) \(message())\n"
        logger.debug("\(line, privacy: .public)")
        queue.async { self.handle?.write(Data(line.utf8)) }
    }

    private func openFile() {
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)
        let size = (try? manager.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0
        if size > 4 * 1024 * 1024 {
            try? manager.removeItem(at: fileURL.appendingPathExtension("old"))
            try? manager.moveItem(at: fileURL, to: fileURL.appendingPathExtension("old"))
        }
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        handle?.seekToEndOfFile()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let header = "\(formatter.string(from: Date())) --- session start, version \(version), pid \(ProcessInfo.processInfo.processIdentifier)\n"
        handle?.write(Data(header.utf8))
    }
}
