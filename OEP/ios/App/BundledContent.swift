// OEP - the self-made test game that ships inside the app.
//
// A fresh install otherwise has nothing to run, which makes "does the engine
// work at all?" impossible to answer without importing several GB.  The build
// copies OEP/testdata/mini-vn into the bundle (see engine/ios-config.json), and
// this helper seeds the library with it on first launch.
import Foundation

enum BundledContent {
    static let folderName = "mini-vn-bundled"
    static let title = "mini-vn（テストデータ）"

    static func seedIfNeeded(library: LibraryStore) {
        let manager = FileManager.default
        if library.games.contains(where: { $0.folderName == folderName }) { return }

        guard let source = bundleURL() else {
            OEPCore.log(2, "bundle", "bundled test game not found in the app bundle")
            return
        }

        let destination = library.gamesURL.appendingPathComponent(folderName, isDirectory: true)
        do {
            if !manager.fileExists(atPath: destination.path) {
                try manager.createDirectory(at: destination, withIntermediateDirectories: true)
                let items = try manager.contentsOfDirectory(at: source,
                                                            includingPropertiesForKeys: nil)
                for item in items {
                    try manager.copyItem(at: item,
                                         to: destination.appendingPathComponent(item.lastPathComponent))
                }
            }
        } catch {
            OEPCore.log(3, "bundle", "could not copy the bundled test game: \(error.localizedDescription)")
            return
        }

        guard let report = OEPCore.scan(folder: destination.path) else {
            OEPCore.log(3, "bundle", "bundled test game could not be scanned")
            return
        }

        var entry = GameEntry(title: title, folderName: folderName)
        entry.engineKind = report.engineKind.rawValue
        entry.engineVersion = report.engine.version
        entry.tjs2Version = report.engine.tjs2Version
        entry.support = report.level
        entry.issueCodes = report.issues.map(\.code)
        entry.totalBytes = library.directorySize(destination)
        entry.archiveCount = report.archives.count
        if let data = try? JSONEncoder().encode(report) {
            entry.lastReportJSON = String(data: data, encoding: .utf8)
        }
        library.add(entry)
        OEPCore.log(1, "bundle", "seeded the bundled test game at \(destination.path)")
    }

    private static func bundleURL() -> URL? {
        let manager = FileManager.default
        if let url = Bundle.main.url(forResource: "mini-vn", withExtension: nil,
                                     subdirectory: "testdata") {
            return url
        }
        // assetPack mirrors into the bundle root; accept the plausible layouts.
        if let resource = Bundle.main.resourceURL {
            let candidates = [
                resource.appendingPathComponent("testdata/mini-vn"),
                resource.appendingPathComponent("mini-vn"),
                resource.appendingPathComponent("assets/testdata/mini-vn"),
            ]
            for candidate in candidates where manager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
