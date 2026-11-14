// OEP - file system access for importing games.
//
// Two problems with the plain SwiftUI file importer motivated this file:
//
//   * presented from inside a sheet, `fileImporter` can leave the picker's
//     "Open" button inert;
//   * iOS's folder picker only enables "Open" while you are *inside* a folder.
//
// So OEP presents UIDocumentPickerViewController directly from the top-most view
// controller, and additionally offers the app's own Documents folder (exposed in
// the Files app) as a picker-free route.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - System picker (presented via UIKit)

enum DocumentPickerMode {
    case folder
    case archive
}

/// Presented from the main thread (UI action).  Deliberately not @MainActor so a
/// plain Button closure can call it without isolation bookkeeping.
enum SystemPicker {
    private static var coordinators: [Coordinator] = []

    static func present(mode: DocumentPickerMode,
                        onFinish: @escaping (Result<[URL], Error>) -> Void) {
        guard let presenter = topViewController() else {
            onFinish(.failure(CocoaError(.featureUnsupported)))
            return
        }

        let types: [UTType]
        switch mode {
        case .folder:
            types = [.folder]
        case .archive:
            types = [UTType(filenameExtension: "xp3") ?? .data, .folder]
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true

        let coordinator = Coordinator { result in
            onFinish(result)
        }
        picker.delegate = coordinator
        coordinators.append(coordinator)  // the picker holds the delegate weakly

        presenter.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let window = windows.first { $0.isKeyWindow }
            ?? windows.first { $0.rootViewController != nil }
            ?? scenes.first?.windows.first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            // A document picker is itself presented; never stack another on it.
            if presented is UIDocumentPickerViewController { return nil }
            top = presented
        }
        return top
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onFinish: (Result<[URL], Error>) -> Void
        private var finished = false

        init(onFinish: @escaping (Result<[URL], Error>) -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            finish(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(.failure(CocoaError(.userCancelled)))
        }

        private func finish(_ result: Result<[URL], Error>) {
            guard !finished else { return }
            finished = true
            onFinish(result)
            SystemPicker.coordinators.removeAll { $0 === self }
        }
    }
}

// MARK: - App Documents folder

/// The app's Documents directory.  It shows up as "On My iPhone / OEP" in Files
/// because the Info.plist enables file sharing and in-place opening.
enum DocumentsInbox {
    static var url: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    struct Entry: Identifiable, Hashable {
        var id: String { url.path }
        var url: URL
        var isDirectory: Bool
        var size: Int64
        var looksLikeGame: Bool
        var name: String { url.lastPathComponent }
    }

    /// Direct children of Documents: folders and loose .xp3 files.
    static func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]) else { return [] }

        var result: [Entry] = []
        for item in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            let name = item.lastPathComponent
            if !isDirectory && !name.lowercased().hasSuffix(".xp3") { continue }

            var looksLikeGame = false
            if isDirectory {
                looksLikeGame = FileManager.default.fileExists(
                    atPath: item.appendingPathComponent("data.xp3").path)
                    || FileManager.default.fileExists(
                        atPath: item.appendingPathComponent("data/startup.tjs").path)
            } else {
                looksLikeGame = name.lowercased() == "data.xp3"
            }
            result.append(Entry(url: item,
                                isDirectory: isDirectory,
                                size: Int64(values?.fileSize ?? 0),
                                looksLikeGame: looksLikeGame))
        }
        return result.sorted { lhs, rhs in
            if lhs.looksLikeGame != rhs.looksLikeGame { return lhs.looksLikeGame }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
