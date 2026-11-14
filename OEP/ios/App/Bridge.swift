// OEP - thin Swift wrappers over the C host API.
import Foundation
import Darwin

enum OEPCore {
    static var version: String {
        guard let pointer = OEPHostCoreVersion() else { return "OEP core" }
        return String(cString: pointer)
    }

    static var engineBuild: String {
        guard let pointer = OEPHostEngineBuildInfo() else { return "engine unavailable" }
        return String(cString: pointer)
    }

    static var engineEmbedded: Bool {
        !engineBuild.lowercased().contains("unavailable")
    }

    /// Scans a folder with the portable core (archive indexes, config, version
    /// resources, plug-in inventory). Returns nil when the core rejects the folder.
    static func scan(folder: String) -> ScanReport? {
        guard let raw = OEPHostScanGameJSON(folder) else { return nil }
        defer { OEPHostFree(raw) }
        let json = String(cString: raw)
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(ScanReport.self, from: data)
        } catch {
            log(3, "bridge", "scan JSON decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func log(_ level: Int32, _ category: String, _ message: String) {
        category.withCString { categoryPointer in
            message.withCString { messagePointer in
                OEPHostLog(level, categoryPointer, messagePointer)
            }
        }
    }

    static func logText() -> String {
        guard let raw = OEPHostLogExport() else { return "" }
        defer { OEPHostFree(raw) }
        return String(cString: raw)
    }

    static func clearLog() {
        OEPHostLogClear()
    }

    static var logCount: Int { Int(OEPHostLogCount()) }
}

// MARK: - Log parsing for the log screen

struct OEPLogLine: Identifiable, Hashable {
    enum Level: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            }
        }
    }

    var id = UUID()
    var timestamp: String
    var level: Level
    var category: String
    var message: String

    var raw: String { "\(timestamp) [\(level.title)] \(category): \(message)" }

    /// Parses lines produced by oep::LogEntry::toLine().
    /// `2026-11-14T08:31:22.517 [INFO] scan: ...`
    static func parseAll(_ text: String) -> [OEPLogLine] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map { rawLine in
            let line = String(rawLine)
            var result = OEPLogLine(timestamp: "", level: .info, category: "app", message: line)
            if let bracketStart = line.firstIndex(of: "["),
               let bracketEnd = line[bracketStart...].firstIndex(of: "]") {
                result.timestamp = String(line[line.startIndex..<bracketStart])
                    .trimmingCharacters(in: .whitespaces)
                let levelText = String(line[line.index(after: bracketStart)..<bracketEnd])
                switch levelText {
                case "DEBUG": result.level = .debug
                case "WARNING": result.level = .warning
                case "ERROR": result.level = .error
                default: result.level = .info
                }
                let rest = line[line.index(after: bracketEnd)...]
                    .trimmingCharacters(in: .whitespaces)
                if let colon = rest.firstIndex(of: ":") {
                    result.category = String(rest[rest.startIndex..<colon])
                        .trimmingCharacters(in: .whitespaces)
                    result.message = String(rest[rest.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    result.message = rest
                }
            }
            return result
        }
    }
}

// MARK: - Live process metrics for the diagnostics screen

enum ProcessMetrics {
    static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    static func thermalStateLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "やや高い"
        case .serious: return "高い"
        case .critical: return "危険"
        @unknown default: return "不明"
        }
    }

    static var availableMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }
}

// MARK: - Engine console log (krkr.console.log)

/// krkrz writes its own console log (UTF-16LE, BOM) into the per-game
/// `user://` folder.  Reading its tail is the fastest way to see why a title
/// refused to start — script errors and plugin failures land there.
enum EngineConsoleLog {
    struct Entry: Identifiable {
        var id: String { url.path }
        var url: URL
        var modified: Date
        var size: Int64
        var text: String
    }

    static func recent(limit: Int = 3, maxBytes: Int = 24000) -> [Entry] {
        let manager = FileManager.default
        let roots = [
            manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            manager.urls(for: .documentDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }

        var found: [(url: URL, modified: Date, size: Int64)] = []
        for root in roots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                guard url.lastPathComponent == "krkr.console.log" else { continue }
                let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey])
                found.append((url,
                              values?.contentModificationDate ?? .distantPast,
                              Int64(values?.fileSize ?? 0)))
            }
        }

        return found
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { entry in
                Entry(url: entry.url,
                      modified: entry.modified,
                      size: entry.size,
                      text: readTail(entry.url, maxBytes: maxBytes))
            }
    }

    static func readTail(_ url: URL, maxBytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return decode(data)
    }

    static func decode(_ data: Data) -> String {
        let bytes = Array(data)
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
            return decodeUTF16(bytes.dropFirst(2), bigEndian: false)
        }
        if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
            return decodeUTF16(bytes.dropFirst(2), bigEndian: true)
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// krkrz writes the console log as UTF-16 LE with a BOM.  A tail read can cut
    /// a surrogate pair in half, so a lone trailing byte is dropped.
    private static func decodeUTF16(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) -> String {
        let body = Array(bytes)
        var units = [UInt16]()
        units.reserveCapacity(body.count / 2)
        var index = 0
        while index + 1 < body.count {
            let first = UInt16(body[index])
            let second = UInt16(body[index + 1])
            units.append(bigEndian ? (first << 8 | second) : (second << 8 | first))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Our own crash-safe file log (Documents/OEP/oep.log).
    static var hostLogURL: URL? {
        guard let pointer = OEPHostLogFilePath() else { return nil }
        return URL(fileURLWithPath: String(cString: pointer))
    }
}
