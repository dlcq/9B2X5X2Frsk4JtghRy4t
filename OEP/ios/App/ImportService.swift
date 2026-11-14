// OEP - game import.
//
// The import pipeline never modifies the source: it reads the picked folder
// (or .xp3 file) through a security-scoped URL, scans it with the OEP core,
// shows the result, and only then copies it into the app container.
import Foundation

enum ImportError: LocalizedError {
    case accessDenied
    case emptySource
    case noEngineData
    case copyFailed(String)
    case cancelled
    case duplicate(String)
    case scanFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "フォルダにアクセスできませんでした。ファイルアプリから選び直してください。"
        case .emptySource:
            return "選択した場所にファイルがありません。"
        case .noEngineData:
            return "data.xp3 も data/startup.tjs も見つかりませんでした。吉里吉里のゲームフォルダを選択してください。"
        case .copyFailed(let message):
            return "コピーに失敗しました: \(message)"
        case .cancelled:
            return "インポートをキャンセルしました。"
        case .duplicate(let title):
            return "同じ内容のゲームが既に登録されています（\(title)）。"
        case .scanFailed:
            return "ゲームの解析に失敗しました。"
        }
    }
}

final class ImportService: ObservableObject {
    struct Candidate: Identifiable {
        var id = UUID()
        var sourceURL: URL
        /// A local copy used when the picked URL is a single .xp3 file that has to
        /// be wrapped in a folder before scanning.
        var stagingURL: URL?
        var sourceIsFolder: Bool
        var title: String
        var report: ScanReport
        var signature: String
        var totalBytes: Int64
        var fileCount: Int
    }

    enum Stage: Equatable {
        case idle
        case scanning
        case review
        case copying
        case done
        case failed
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = ""
    @Published private(set) var candidate: Candidate?
    @Published var errorMessage: String?

    /// Cross-thread cancellation flag: the copy runs off the main actor.
    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func set() {
            lock.lock(); value = true; lock.unlock()
        }
        func reset() {
            lock.lock(); value = false; lock.unlock()
        }
    }

    private let cancelFlag = CancelFlag()
    private var stagingDirectory: URL?

    var isBusy: Bool { stage == .scanning || stage == .copying }

    // MARK: - Step 1: pick and scan

    @MainActor
    func prepare(url: URL, library: LibraryStore) async {
        reset()
        stage = .scanning
        statusText = "フォルダを確認しています…"

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = values.isDirectory ?? false
            let scanTarget: URL
            var staging: URL?

            if isDirectory {
                scanTarget = url
            } else {
                // A single archive: wrap it so the engine sees a project folder.
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("OEP-Staging-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let destination = dir.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: destination)
                staging = dir
                stagingDirectory = dir
                scanTarget = dir
            }

            let sourceURL = scanTarget
            let folderCopy = sourceURL
            let signature = computeSignature(folder: folderCopy)
            let metrics = measure(folder: folderCopy)

            statusText = "アーカイブを解析しています…"
            let report = await Task.detached(priority: .userInitiated) {
                OEPCore.scan(folder: folderCopy.path)
            }.value

            guard let report else { throw ImportError.scanFailed }
            guard report.hasDataXp3 || report.hasDataFolder || !report.archives.isEmpty else {
                throw ImportError.noEngineData
            }

            let trimmedTitle = url.deletingPathExtension().lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            candidate = Candidate(sourceURL: sourceURL,
                                  stagingURL: staging,
                                  sourceIsFolder: isDirectory,
                                  title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle,
                                  report: report,
                                  signature: signature,
                                  totalBytes: metrics.bytes,
                                  fileCount: metrics.files)

            if let existing = library.duplicate(of: signature) {
                errorMessage = ImportError.duplicate(existing.title).localizedDescription
            }
            stage = .review
            statusText = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            stage = .failed
            OEPCore.log(3, "import", "prepare failed: \(error.localizedDescription)")
        }
    }

    func updateTitle(_ title: String) {
        candidate?.title = title
    }

    // MARK: - Step 2: copy into the library

    @MainActor
    func commit(library: LibraryStore) async {
        guard var candidate else { return }
        reset(keepCandidate: true)
        stage = .copying
        cancelFlag.reset()
        progress = 0
        statusText = "ゲームデータをコピーしています…"

        let source = candidate.sourceURL
        let folderName = makeFolderName(title: candidate.title)
        let destination = library.gamesURL.appendingPathComponent(folderName, isDirectory: true)

        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let total = max(candidate.totalBytes, 1)
            let cancelled = await copyTree(from: source, to: destination, totalBytes: total)

            if cancelled || cancelFlag.isSet {
                try? FileManager.default.removeItem(at: destination)
                throw ImportError.cancelled
            }

            statusText = "登録しています…"
            let path = destination.path
            let report = await Task.detached(priority: .userInitiated) {
                OEPCore.scan(folder: path)
            }.value

            let finalReport = report ?? candidate.report
            candidate.title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            var entry = GameEntry(title: candidate.title,
                                  folderName: folderName)
            entry.signature = candidate.signature
            entry.engineKind = finalReport.engineKind.rawValue
            entry.engineVersion = finalReport.engine.version
            entry.tjs2Version = finalReport.engine.tjs2Version
            entry.support = finalReport.level
            entry.issueCodes = finalReport.issues.map(\.code)
            entry.totalBytes = candidate.totalBytes
            entry.archiveCount = finalReport.archives.count
            if let data = try? JSONEncoder().encode(finalReport) {
                entry.lastReportJSON = String(data: data, encoding: .utf8)
            }

            library.add(entry)
            OEPCore.log(1, "import",
                        "imported \(entry.title) (\(finalReport.archives.count) archive(s), support=\(finalReport.supportLevel))")

            cleanupStaging()
            stage = .done
            progress = 1
            statusText = "登録が完了しました"
            self.candidate = nil
        } catch {
            cleanupStaging()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            stage = .failed
            OEPCore.log(3, "import", "commit failed: \(error.localizedDescription)")
        }
    }

    func cancel() {
        cancelFlag.set()
        OEPCore.log(1, "import", "cancel requested")
    }

    func reset(keepCandidate: Bool = false) {
        if !keepCandidate {
            cleanupStaging()
            candidate = nil
        }
        stage = keepCandidate ? stage : .idle
        if !keepCandidate {
            progress = 0
            statusText = ""
            errorMessage = nil
        }
        cancelFlag.reset()
    }

    // MARK: - Helpers

    private func cleanupStaging() {
        if let stagingDirectory {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }
        stagingDirectory = nil
    }

    private func makeFolderName(title: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_ "))
        let sanitized = title.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        var name = String(sanitized).trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        if name.isEmpty { name = "game" }
        if name.count > 40 { name = String(name.prefix(40)) }
        let suffix = UUID().uuidString.prefix(8)
        return "\(name)-\(suffix)"
    }

    private func measure(folder: URL) -> (bytes: Int64, files: Int) {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return (0, 0) }
        var bytes: Int64 = 0
        var files = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                bytes += Int64(values?.fileSize ?? 0)
                files += 1
            }
        }
        return (bytes, files)
    }

    /// Fingerprint: the archive layout and sizes, which is stable for the same
    /// release and does not read any payload bytes.
    private func computeSignature(folder: URL) -> String {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return "" }

        var parts: [String] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let name = item.lastPathComponent.lowercased()
            if name.hasSuffix(".xp3") || name == "startup.tjs" {
                parts.append("\(name):\(values?.fileSize ?? 0)")
            }
        }
        return parts.joined(separator: "|")
    }

    /// Recursive copy with byte progress. Returns true when cancelled.
    /// Runs entirely off the main actor; only the progress text hops back.
    private func copyTree(from source: URL, to destination: URL, totalBytes: Int64) async -> Bool {
        let flag = cancelFlag
        let total = max(totalBytes, 1)
        let progressHandler: @Sendable (Int64, String) -> Void = { [weak self] copied, name in
            let fraction = min(1.0, Double(copied) / Double(total))
            DispatchQueue.main.async {
                guard let self else { return }
                self.progress = fraction
                self.statusText = "コピー中: \(name)"
            }
        }

        let work: @Sendable () -> Bool = {
            let fileManager = FileManager.default
            var copied: Int64 = 0

            func copyDirectory(_ from: URL, _ to: URL) -> Bool {
                if flag.isSet { return false }
                let items = (try? fileManager.contentsOfDirectory(
                    at: from,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])) ?? []

                for item in items {
                    if flag.isSet { return false }
                    let target = to.appendingPathComponent(item.lastPathComponent)
                    let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                    if values?.isDirectory == true {
                        do {
                            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                        } catch {
                            return false
                        }
                        if !copyDirectory(item, target) { return false }
                    } else {
                        do {
                            try fileManager.copyItem(at: item, to: target)
                            copied += Int64(values?.fileSize ?? 0)
                            progressHandler(copied, item.lastPathComponent)
                        } catch {
                            OEPCore.log(3, "import",
                                        "copy failed for \(item.lastPathComponent): \(error.localizedDescription)")
                            return false
                        }
                    }
                }
                return true
            }

            return copyDirectory(source, destination)
        }

        let succeeded = await Task.detached(priority: .userInitiated, operation: work).value
        return !succeeded
    }
}
