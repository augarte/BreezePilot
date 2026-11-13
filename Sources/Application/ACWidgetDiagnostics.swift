import Foundation

/// Temporary trace of widget intent work, written where `devicectl` may read it.
enum ACWidgetDiagnostics {
    static func log(_ message: String) {
        guard let directory = ACWidgetStore.container?.appendingPathComponent("Library/Caches") else { return }
        let url = directory.appendingPathComponent("widget-diagnostics.log")
        let line = "\(Date.now.formatted(.iso8601.timeSeparator(.colon))) [\(ProcessInfo.processInfo.processName)] \(message)\n"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
