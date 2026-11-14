// OEP - one KiriKiri session, driven through the C host API.
//
// krkrz performs a one-shot system initialisation (TVPSystemUninit is final), so
// a process plays one title.  The launcher stays alive behind the engine and
// comes back when the session ends; another title needs an app restart, which
// the UI states explicitly instead of pretending otherwise.
import Foundation
import UIKit

final class SessionController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing(GameEntry)
        case running(GameEntry)
        case finished(GameEntry, reason: String)
        case failed(String)

        var game: GameEntry? {
            switch self {
            case .preparing(let game), .running(let game), .finished(let game, _):
                return game
            case .idle, .failed:
                return nil
            }
        }

        var isActive: Bool {
            switch self {
            case .preparing, .running:
                return true
            default:
                return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var lastSessionSeconds: Int = 0
    @Published private(set) var engineRestartRequired: Bool = false
    @Published private(set) var lastFailureMessage: String?

    var onSessionRunning: (() -> Void)?
    var onSessionEnded: (() -> Void)?

    private weak var library: LibraryStore?
    private var activeGameID: UUID?
    private var startedAt: Date?
    private var cancelBeforeStart = false

    init() {
        SessionBridge.shared.session = self
        OEPHostSetEngineCallback(oepEngineEventCallback)
        engineRestartRequired = OEPHostEngineSessionUsed() != 0
    }

    func bind(library: LibraryStore) {
        self.library = library
    }

    // MARK: - Starting

    func play(_ game: GameEntry,
              library: LibraryStore,
              settings: AppSettings,
              folder: URL) {
        guard !phase.isActive else { return }
        if OEPHostEngineSessionUsed() != 0 {
            engineRestartRequired = true
            phase = .failed("このプロセスでは既にエンジンを実行しました。別のゲームを遊ぶにはアプリを再起動してください。")
            return
        }

        self.library = library
        activeGameID = game.id
        elapsedSeconds = 0
        lastFailureMessage = nil
        cancelBeforeStart = false

        if settings.keepScreenAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        OEPHostEngineSetPreferredFPS(Int32(settings.frameRate.rawValue))
        OEPHostSetSessionGameID(game.id.uuidString)

        library.recordSessionStart(game)
        startedAt = Date()
        phase = .preparing(game)
        OEPCore.log(1, "session", "preparing \(game.title) engine=\(game.engineTitle) v\(game.engineVersion)")

        // Let the loading screen paint before the (blocking) engine init.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.cancelBeforeStart else { return }
            self.startEngine(game: game, folder: folder)
        }
    }

    private func startEngine(game: GameEntry, folder: URL) {
        let rc = folder.path.withCString { pointer in
            OEPHostEngineStart(pointer)
        }
        if rc != 0 {
            let message: String
            switch rc {
            case -1: message = "エンジンは既に実行中です。"
            case -2: message = "このプロセスでは既にエンジンを実行しました。アプリを再起動してください。"
            case -3: message = "ゲームフォルダのパスが不正です。"
            default: message = "エンジンの初期化に失敗しました。診断画面のログを確認してください。"
            }
            lastFailureMessage = message
            phase = .failed(message)
            engineRestartRequired = OEPHostEngineSessionUsed() != 0
            finishSession(addPlaytime: false)
            OEPCore.log(3, "session", "engine start failed (\(rc)): \(message)")
            onSessionEnded?()
        }
    }

    func requestStop() {
        if case .preparing = phase, OEPHostEngineIsRunning() == 0 {
            cancelBeforeStart = true
            phase = .finished(phase.game ?? placeholder(), reason: "cancelled")
            finishSession(addPlaytime: false)
            onSessionEnded?()
            return
        }
        OEPCore.log(1, "session", "stop requested")
        OEPHostEngineRequestStop()
    }

    // MARK: - C events

    func handle(event: Int32, detail: String) {
        switch event {
        case OEPEngineEventStarting:
            OEPCore.log(1, "engine", "SDL_AppInit: \(detail)")
        case OEPEngineEventRunning:
            OEPCore.log(1, "engine", "engine loop running")
            if let game = phase.game {
                phase = .running(game)
            }
            onSessionRunning?()
        case OEPEngineEventTick:
            elapsedSeconds = Int(detail) ?? elapsedSeconds
        case OEPEngineEventPaused:
            OEPCore.log(1, "engine", "paused (background)")
        case OEPEngineEventResumed:
            OEPCore.log(1, "engine", "resumed (foreground)")
        case OEPEngineEventFailed:
            OEPCore.log(3, "engine", "failure: \(detail)")
            lastFailureMessage = detail.isEmpty ? "エンジンの初期化に失敗しました。" : detail
        case OEPEngineEventEnded:
            OEPCore.log(1, "engine", "engine ended: \(detail)")
            if let game = phase.game {
                phase = .finished(game, reason: detail)
            }
            finishSession(addPlaytime: true)
            engineRestartRequired = OEPHostEngineSessionUsed() != 0
            onSessionEnded?()
        default:
            break
        }
    }

    // MARK: - Teardown

    private func finishSession(addPlaytime: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        if addPlaytime, let id = activeGameID, let startedAt {
            let seconds = max(0, Date().timeIntervalSince(startedAt))
            lastSessionSeconds = Int(elapsedSeconds > 0 ? elapsedSeconds : Int(seconds))
            library?.recordPlaytime(id, seconds: TimeInterval(lastSessionSeconds))
        }
        activeGameID = nil
        startedAt = nil
    }

    private func placeholder() -> GameEntry {
        GameEntry(title: "ゲーム", folderName: "")
    }

    func dismissResult() {
        phase = .idle
    }
}

/// C callback registered with the host. Kept as a global constant so the pointer
/// stays valid for the lifetime of the process.
private let oepEngineEventCallback: @convention(c) (Int32, UnsafePointer<CChar>?) -> Void = {
    event, detail in
    let text = detail.map { String(cString: $0) } ?? ""
    DispatchQueue.main.async {
        SessionBridge.shared.session?.handle(event: event, detail: text)
    }
}

/// Small indirection so the C callback can reach the active controller without
/// capturing it in a C function pointer.
final class SessionBridge {
    static let shared = SessionBridge()
    weak var session: SessionController?
}
