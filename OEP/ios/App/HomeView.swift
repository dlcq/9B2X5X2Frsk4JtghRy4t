// OEP - home screen.
import SwiftUI

struct HomeView: View {
    @Environment(\.oep) private var palette
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var session: SessionController

    var onAddGame: () -> Void
    var onOpenLibrary: () -> Void
    var onOpenSettings: () -> Void

    @State private var path: [Route] = []

    private var recentGames: [GameEntry] {
        library.filtered(sort: .lastPlayed, favoritesOnly: false, query: "").prefix(3)
            .map { $0 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    brandHeader
                    heroCard
                    statsRow
                    recentSection
                    addGameButton
                    engineFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .game(let id):
            if let game = library.game(id: id) {
                GameDetailView(game: game)
            } else {
                Text("ゲームが見つかりません")
            }
        case .diagnostics(let id):
            if let game = library.game(id: id) {
                DiagnosticsView(game: game)
            } else {
                Text("ゲームが見つかりません")
            }
        case .logs:
            LogsView()
        case .licenses:
            LicenseView()
        case .storage:
            StorageView()
        }
    }

    // MARK: - Header

    private var brandHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Text("OEP")
                        .font(OEPFont.brand(30))
                        .tracking(1.5)
                        .foregroundStyle(
                            LinearGradient(colors: [palette.text, palette.purple],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing))
                    Circle()
                        .fill(palette.blue)
                        .frame(width: 6, height: 6)
                        .offset(y: -10)
                }
                Text("ONIICHAN EROGE PLAYER")
                    .font(OEPFont.label(9))
                    .tracking(2.4)
                    .foregroundStyle(palette.subtext)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(palette.card)
                            .overlay(Circle().strokeBorder(palette.border, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        Group {
            if let last = library.lastPlayed {
                OEPGlowCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("CONTINUE PLAYING")
                                .font(OEPFont.label(10))
                                .tracking(1.8)
                                .foregroundStyle(palette.purple)
                            Spacer()
                            SupportBadge(level: last.support, compact: true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(last.title)
                                .font(OEPFont.title(24))
                                .foregroundStyle(palette.text)
                                .lineLimit(2)
                            Text(last.subtitle)
                                .font(OEPFont.body(12))
                                .foregroundStyle(palette.subtext)
                        }
                        HStack(spacing: 18) {
                            smallStat("最終プレイ", Fmt.relative(last.lastPlayedAt))
                            smallStat("プレイ時間", Fmt.playtime(last.playtime))
                        }
                        PlayButton(game: last, disabledReason: playDisabledReason(for: last)) {
                            play(last)
                        }
                    }
                }
            } else {
                OEPGlowCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("WELCOME")
                            .font(OEPFont.label(10))
                            .tracking(1.8)
                            .foregroundStyle(palette.blue)
                        Text("ライブラリはまだ空です")
                            .font(OEPFont.title(23))
                            .foregroundStyle(palette.text)
                        Text("吉里吉里のゲームフォルダを追加すると、ここから続きを遊べます。データはアプリ内の管理領域にコピーされ、元のフォルダは変更されません。")
                            .font(OEPFont.body(13))
                            .foregroundStyle(palette.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            onAddGame()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("ADD GAME")
                                    .tracking(1.2)
                            }
                            .font(OEPFont.title(15))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(LinearGradient(colors: [palette.purple, palette.blue],
                                                         startPoint: .leading,
                                                         endPoint: .trailing))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func smallStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(OEPFont.label(9))
                .tracking(0.8)
                .foregroundStyle(palette.subtext)
            Text(value)
                .font(OEPFont.mono(12, weight: .medium))
                .foregroundStyle(palette.text)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(label: "Games", value: "\(library.games.count)")
            StatTile(label: "Storage", value: Fmt.bytes(library.totalBytes))
            StatTile(label: "Played", value: Fmt.playtime(library.totalPlaytime))
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Library", trailing: library.games.isEmpty ? nil : "\(library.games.count) titles")
            OEPCard(padding: 14) {
                if recentGames.isEmpty {
                    EmptyStateView(icon: "square.stack.3d.up.slash",
                                   title: "ゲームがありません",
                                   message: "ADD GAME から吉里吉里のゲームフォルダを追加してください。",
                                   actionTitle: "ゲームを追加",
                                   action: onAddGame)
                } else {
                    VStack(spacing: 2) {
                        ForEach(recentGames) { game in
                            NavigationLink(value: Route.game(game.id)) {
                                GameRowView(game: game)
                            }
                            .buttonStyle(OEPRowButtonStyle())
                            if game.id != recentGames.last?.id {
                                Divider().overlay(palette.border.opacity(0.6))
                            }
                        }
                    }
                }
            }
            if !library.games.isEmpty {
                Button(action: onOpenLibrary) {
                    HStack(spacing: 6) {
                        Text("ライブラリを開く")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(OEPFont.label(11))
                    .tracking(0.6)
                    .foregroundStyle(palette.blue)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
    }

    private var addGameButton: some View {
        Button(action: onAddGame) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("ADD GAME")
                    .tracking(1.2)
                Spacer()
                Text("ファイルアプリからインポート")
                    .font(OEPFont.body(11))
                    .foregroundStyle(palette.subtext)
            }
        }
        .buttonStyle(OEPSecondaryButtonStyle())
    }

    private var engineFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(OEPCore.engineEmbedded ? palette.supported : palette.unsupported)
                .frame(width: 6, height: 6)
            Text(OEPCore.engineBuild)
                .font(OEPFont.mono(10))
                .foregroundStyle(palette.subtext.opacity(0.8))
            Spacer()
            Text(OEPCore.version)
                .font(OEPFont.mono(10))
                .foregroundStyle(palette.subtext.opacity(0.6))
        }
        .padding(.top, 6)
    }

    // MARK: - Actions

    private func playDisabledReason(for game: GameEntry) -> String? {
        if session.engineRestartRequired {
            return "このプロセスではエンジンを実行済みです。再起動後に遊べます。"
        }
        if session.phase.isActive {
            return "ゲームを起動しています…"
        }
        if game.support == .unsupported {
            return "このゲームは未対応と判定されています（診断を確認してください）。"
        }
        return nil
    }

    private func play(_ game: GameEntry) {
        session.play(game,
                     library: library,
                     settings: settings.settings,
                     folder: library.folder(for: game))
    }
}
