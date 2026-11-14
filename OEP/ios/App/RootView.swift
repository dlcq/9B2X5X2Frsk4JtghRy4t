// OEP - launcher bootstrap and root shell.
import SwiftUI
import UIKit

final class AppEnvironment: ObservableObject {
    let library = LibraryStore()
    let settings = SettingsStore()
    let session = SessionController()
    let importer = ImportService()

    init() {
        SessionBridge.shared.session = session
        session.bind(library: library)
        OEPHostLogSetMinimumLevel(Int32(settings.settings.logLevel))
        // Make the Files-visible inbox exist from the first launch.
        _ = DocumentsInbox.url
    }

    func applySettings() {
        OEPHostLogSetMinimumLevel(Int32(settings.settings.logLevel))
    }
}

// MARK: - Entry point invoked by the Objective-C++ host

@_cdecl("OEPHostRunLauncher")
public func OEPHostRunLauncher() -> Int32 {
    // Called on the main thread by SDL's UIKit delegate (postFinishLaunch).
    LauncherHost.shared.start()
}

final class LauncherHost {
    static let shared = LauncherHost()

    private var window: UIWindow?
    private(set) var environment: AppEnvironment?

    @discardableResult
    func start() -> Int32 {
        if environment == nil {
            let env = AppEnvironment()
            environment = env
            env.session.onSessionRunning = {
                LauncherHost.shared.hideLauncher()
            }
            env.session.onSessionEnded = {
                LauncherHost.shared.showLauncher()
            }
        }
        // The scene is normally connected by now, but the first runloop turn after
        // UIApplicationMain may race with scene attachment.
        presentWhenSceneIsAvailable(attempts: 12)
        return 0
    }

    private func presentWhenSceneIsAvailable(attempts: Int) {
        guard window == nil, let env = environment else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.presentWhenSceneIsAvailable(attempts: attempts - 1)
                }
            } else {
                OEPCore.log(3, "host", "no UIWindowScene; the launcher cannot be presented")
            }
            return
        }

        let root = RootView()
            .environmentObject(env)
            .environmentObject(env.library)
            .environmentObject(env.settings)
            .environmentObject(env.session)
            .environmentObject(env.importer)

        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .black

        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.backgroundColor = .black
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        self.window = window

        OEPCore.log(1, "host",
                    "launcher ready (core=\(OEPCore.version), engine=\(OEPCore.engineBuild))")
    }

    func hideLauncher() {
        window?.isHidden = true
        OEPCore.log(1, "host", "launcher hidden for the game session")
    }

    func showLauncher() {
        window?.isHidden = false
        window?.makeKeyAndVisible()
        OEPCore.log(1, "host", "launcher restored")
    }
}

// MARK: - Root

enum OEPTab: String, CaseIterable, Identifiable {
    case home
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "ホーム"
        case .library: return "ライブラリ"
        case .settings: return "設定"
        }
    }

    var icon: String {
        switch self {
        case .home: return "sparkles"
        case .library: return "square.stack.3d.up"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var session: SessionController

    @State private var tab: OEPTab = .home
    @State private var showAddGame = false

    private var palette: OEPPalette { OEPPalette.make(settings.settings.theme) }

    var body: some View {
        ZStack(alignment: .bottom) {
            OEPBackground()

            Group {
                switch tab {
                case .home:
                    HomeView(onAddGame: { showAddGame = true },
                             onOpenLibrary: { tab = .library },
                             onOpenSettings: { tab = .settings })
                case .library:
                    LibraryView(onAddGame: { showAddGame = true })
                case .settings:
                    SettingsView()
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: tab)

            OEPTabBar(selection: $tab)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

            sessionOverlay
                .transition(.opacity)
                .zIndex(10)
        }
        .environment(\.oep, palette)
        .sheet(isPresented: $showAddGame) {
            AddGameView()
                .environmentObject(env)
                .environmentObject(env.library)
                .environmentObject(env.importer)
                .environment(\.oep, palette)
        }
    }

    @ViewBuilder
    private var sessionOverlay: some View {
        switch session.phase {
        case .preparing(let game):
            EngineLoadingOverlay(game: game) {
                session.requestStop()
            }
        case .running:
            // The SDL window covers the launcher; nothing to draw.
            Color.clear.frame(width: 0, height: 0)
        case .finished(_, let reason):
            SessionResultOverlay(reason: reason,
                                 seconds: session.lastSessionSeconds,
                                 restartRequired: session.engineRestartRequired) {
                session.dismissResult()
            }
        case .failed(let message):
            SessionFailureOverlay(message: message,
                                  restartRequired: session.engineRestartRequired) {
                session.dismissResult()
            }
        case .idle:
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

// MARK: - Tab bar

struct OEPTabBar: View {
    @Environment(\.oep) private var palette
    @Binding var selection: OEPTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(OEPTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    selection = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .semibold))
                        if selection == tab {
                            Text(tab.title)
                                .font(OEPFont.label(11))
                                .tracking(0.6)
                        }
                    }
                    .foregroundStyle(selection == tab ? palette.text : palette.subtext)
                    .padding(.vertical, 11)
                    .padding(.horizontal, selection == tab ? 16 : 14)
                    .background(
                        Capsule()
                            .fill(selection == tab
                                  ? AnyShapeStyle(LinearGradient(
                                      colors: [palette.purple.opacity(0.24), palette.blue.opacity(0.12)],
                                      startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(Color.clear))
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.card.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
        )
        .animation(.easeOut(duration: 0.2), value: selection)
    }
}
