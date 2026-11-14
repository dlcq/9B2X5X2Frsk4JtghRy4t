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
