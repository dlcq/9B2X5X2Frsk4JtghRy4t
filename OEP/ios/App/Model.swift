// OEP - data model shared by the launcher screens.
import Foundation

// MARK: - Support

enum SupportLevel: String, Codable, CaseIterable, Hashable {
    case supported
    case partial
    case unsupported
    case unknown

    init(rawValueOrUnknown value: String) {
        self = SupportLevel(rawValue: value) ?? .unknown
    }

    var title: String {
        switch self {
        case .supported: return "対応済み"
        case .partial: return "一部対応"
        case .unsupported: return "未対応"
        case .unknown: return "調査中"
        }
    }

    var shortTitle: String {
        switch self {
        case .supported: return "SUPPORTED"
        case .partial: return "PARTIAL"
        case .unsupported: return "UNSUPPORTED"
        case .unknown: return "UNKNOWN"
        }
    }
}

enum EngineKind: String, Codable, Hashable {
    case kirikiriZ
    case kirikiri2
    case sdlPort
    case unknown

    init(label: String) {
        let lower = label.lowercased()
        if lower.contains("z (krkrz)") || lower.contains("kirikiri z") {
            self = .kirikiriZ
        } else if lower.contains("kirikiri 2") {
            self = .kirikiri2
        } else if lower.contains("sdl") {
            self = .sdlPort
        } else {
            self = .unknown
        }
    }

    var title: String {
        switch self {
        case .kirikiriZ: return "吉里吉里Z"
        case .kirikiri2: return "吉里吉里2"
        case .sdlPort: return "吉里吉里 (SDL)"
        case .unknown: return "不明"
        }
    }
}

// MARK: - Engine scan report (decoded from the OEP core JSON)

struct Win32VersionInfo: Codable, Hashable {
    var valid: Bool
    var fileDescription: String
    var fileVersion: String
    var productName: String
    var productVersion: String
    var companyName: String
    var comments: String
}

struct ConsoleLogInfo: Codable, Hashable {
    var found: Bool
    var kirikiriVersion: String
    var tjs2Version: String
    var revision: String
    var buildStamp: String
    var platform: String
    var mounts: [String]
    var plugins: [String]
}

struct ScanEngine: Codable, Hashable {
    var kind: String
    var kindJa: String
    var version: String
    var tjs2Version: String
    var evidence: String
    var versionMatchesBundle: Bool
    var win32VersionInfo: Win32VersionInfo
    var consoleLog: ConsoleLogInfo
}

struct ScanArchive: Codable, Identifiable, Hashable {
    var fileName: String
    var fileSize: Int64
    var xp3Magic: Bool
    var indexOk: Bool
    var indexError: String?
    var entries: Int
    var orgBytes: Int64
    var arcBytes: Int64
    var compressedEntries: Int
    var protectedEntries: Int
    var hashedNames: Int
    var hasStartupScript: Bool
    var contentProbeAttempted: Bool
    var contentReadable: Bool
    var probeError: String?

    var id: String { fileName }
}

struct ScanPlugin: Codable, Identifiable, Hashable {
    var file: String
    var id: String
    var support: String
    var supportJa: String
    var note: String
}

struct ScanIssue: Codable, Identifiable, Hashable {
    var level: String
    var code: String
    var detail: String

    var id: String { code + "|" + detail }
    var supportLevel: SupportLevel { SupportLevel(rawValueOrUnknown: level) }

    var localized: String {
        if code.hasPrefix("plugin_missing:") {
            let plugin = String(code.dropFirst("plugin_missing:".count))
            return "プラグイン \(plugin) はiOS版に含まれません（\(detail)）"
        }
        if code.hasPrefix("plugin_partial:") {
            let plugin = String(code.dropFirst("plugin_partial:".count))
            return "プラグイン \(plugin) は一部のみ対応です（\(detail)）"
        }
        if code.hasPrefix("plugin_unknown:") {
            let plugin = String(code.dropFirst("plugin_unknown:".count))
            return "プラグイン \(plugin) の動作は未検証です（\(detail)）"
        }
        switch code {
        case "no_startup_script":
            return "起動スクリプト (startup.tjs) が見つかりません。エンジンが実行するものがありません。"
        case "engine_unversioned":
            return "バージョン情報がありません（EXE/ログ/設定なし）。アーカイブ構成から起動します。"
        case "engine_unknown":
            return "エンジンを特定できませんでした。アーカイブ構成のみを検出しています。"
        case "engine_version_differs":
            return "タイトルのエンジンバージョンが同梱エンジン (1.2.0.3) と異なります（\(detail)）。"
        case "engine_kirikiri2":
            return "吉里吉里2のタイトルです。TJS2/KAGの互換性はありますが、API差異の可能性があります。"
        case "data_archive_unreadable":
            return "data.xp3 のインデックスを読み込めません（\(detail)）。"
        case "archive_unreadable":
            return "アーカイブのインデックスを読み込めません（\(detail)）。"
        case "data_archive_filtered":
            return "data.xp3 の内容がタイトル固有の暗号化/フィルタで保護されています（\(detail)）。"
        case "archive_filtered":
            return "アーカイブの内容がタイトル固有の暗号化/フィルタで保護されています（\(detail)）。"
        case "hashed_storage_names":
            return "ファイル名が保護ツールにより置換されています（\(detail)）。エンジンはそのまま読み込めます。"
        case "extraction_protected":
            return "展開プロテクト属性が付いています（\(detail)）。再生には影響しません。"
        case "misnamed_xp3":
            return "拡張子が .xp3 ですがXP3形式ではありません（\(detail)）。"
        case "no_archives":
            return "アーカイブも data/ フォルダもありません。"
        default:
            return detail
        }
    }
}

struct ScanReport: Codable, Hashable {
    var folder: String
    var displayName: String
    var supportLevel: String
    var supportLevelJa: String
    var totalBytes: Int64
    var hasDataXp3: Bool
    var hasDataFolder: Bool
    var hasStartupScript: Bool
    var hasConfigFile: Bool
    var hasSaveFolder: Bool
    var engine: ScanEngine
    var archives: [ScanArchive]
    var plugins: [ScanPlugin]
    var issues: [ScanIssue]
    var startupCandidates: [String]
    var rootFiles: [String]

    var level: SupportLevel { SupportLevel(rawValueOrUnknown: supportLevel) }
    var engineKind: EngineKind { EngineKind(label: engine.kind) }
}

// MARK: - Library entry

struct GameEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var folderName: String
    /// Cheap content fingerprint (archive layout + sizes) used for duplicate detection.
    var signature: String = ""
    var importedAt: Date = Date()
    var engineKind: String = "unknown"
    var engineVersion: String = ""
    var tjs2Version: String = ""
    var support: SupportLevel = .unknown
    var issueCodes: [String] = []
    var totalBytes: Int64 = 0
    var archiveCount: Int = 0
    var isFavorite: Bool = false
    var lastPlayedAt: Date?
    var playtime: TimeInterval = 0
    var launchCount: Int = 0
    var lastReportJSON: String?

    var engineTitle: String { EngineKind(rawValue: engineKind)?.title ?? engineKind }

    var subtitle: String {
        var parts: [String] = [engineTitle]
        if !engineVersion.isEmpty { parts.append("v\(engineVersion)") }
        parts.append(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    enum Theme: String, Codable, CaseIterable, Identifiable {
        case midnight
        case oled

        var id: String { rawValue }
        var title: String {
            switch self {
            case .midnight: return "Midnight"
            case .oled: return "OLED Black"
            }
        }
        var subtitle: String {
            switch self {
            case .midnight: return "#090A0F を基調にした標準テーマ"
            case .oled: return "純黒背景で消費電力を抑えるテーマ"
            }
        }
    }

    enum FrameRate: Int, Codable, CaseIterable, Identifiable {
        case fps30 = 30
        case fps60 = 60
        case fps120 = 120

        var id: Int { rawValue }
        var title: String { "\(rawValue) fps" }
    }

    var theme: Theme = .midnight
    var frameRate: FrameRate = .fps60
    var keepScreenAwake: Bool = true
    var logLevel: Int = 2  // 0 debug, 1 info, 2 warning, 3 error

    var logLevelTitle: String {
        switch logLevel {
        case 0: return "デバッグ"
        case 1: return "情報"
        case 3: return "エラーのみ"
        default: return "警告以上"
        }
    }
}

// MARK: - Sorting

enum LibrarySort: String, CaseIterable, Identifiable {
    case lastPlayed
    case title
    case imported
    case size

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lastPlayed: return "最終プレイ順"
        case .title: return "名前順"
        case .imported: return "追加日順"
        case .size: return "サイズ順"
        }
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func playtime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)時間\(minutes)分" }
        if minutes > 0 { return "\(minutes)分" }
        return "\(total)秒"
    }

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    static func date(_ value: Date?) -> String {
        guard let value else { return "—" }
        return dateTime.string(from: value)
    }

    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relative(_ value: Date?) -> String {
        guard let value else { return "未プレイ" }
        return relative.localizedString(for: value, relativeTo: Date())
    }

    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
