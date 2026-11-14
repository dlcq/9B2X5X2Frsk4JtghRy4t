// OEP - game library with search, favorites and sorting.
import SwiftUI

struct LibraryView: View {
    @Environment(\.oep) private var palette
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var session: SessionController

    var onAddGame: () -> Void

    @State private var path: [Route] = []
    @State private var query = ""
    @State private var sort: LibrarySort = .lastPlayed
    @State private var favoritesOnly = false
    @State private var removalTarget: GameEntry?
    @State private var showRemovalConfirm = false

    private var games: [GameEntry] {
        library.filtered(sort: sort, favoritesOnly: favoritesOnly, query: query)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchField
                    filterRow
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
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
            .confirmationDialog("ゲームを削除しますか？",
                                isPresented: $showRemovalConfirm,
                                titleVisibility: .visible) {
                Button("ゲームとデータを削除", role: .destructive) {
                    if let target = removalTarget {
                        _ = library.remove(target, deleteFiles: true)
                    }
                }
                Button("ライブラリからのみ削除") {
                    if let target = removalTarget {
                        _ = library.remove(target, deleteFiles: false)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(removalTarget.map {
                    "「\($0.title)」を削除します。データを消す場合、アプリ内にコピーしたファイルも削除されます。"
                } ?? "")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARY")
                    .font(OEPFont.label(10))
                    .tracking(2.2)
                    .foregroundStyle(palette.purple)
                Text("ゲームライブラリ")
                    .font(OEPFont.title(26))
                    .foregroundStyle(palette.text)
            }
            Spacer()
            Button(action: onAddGame) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(LinearGradient(colors: [palette.purple, palette.blue],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.subtext)
            TextField("タイトル・エンジンで検索", text: $query)
                .font(OEPFont.body(14))
                .foregroundStyle(palette.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.subtext)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(palette.card)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1))
        )
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(LibrarySort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                chip(icon: "arrow.up.arrow.down", text: sort.title, active: true)
            }

            Button {
                favoritesOnly.toggle()
            } label: {
                chip(icon: favoritesOnly ? "star.fill" : "star",
                     text: "お気に入り",
                     active: favoritesOnly)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(games.count) / \(library.games.count)")
                .font(OEPFont.mono(11))
                .foregroundStyle(palette.subtext)
        }
    }

    private func chip(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(OEPFont.label(11))
        }
        .foregroundStyle(active ? palette.text : palette.subtext)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(active ? palette.elevated : palette.card.opacity(0.6))
                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
        )
    }

    @ViewBuilder
    private var content: some View {
        if library.games.isEmpty {
            OEPCard {
                EmptyStateView(icon: "folder.badge.plus",
                               title: "ライブラリは空です",
                               message: "ファイルアプリから吉里吉里のゲームフォルダを追加してください。",
                               actionTitle: "ADD GAME",
                               action: onAddGame)
            }
        } else if games.isEmpty {
            OEPCard {
                EmptyStateView(icon: "magnifyingglass",
                               title: "該当するゲームがありません",
                               message: favoritesOnly
                                   ? "お気に入りのフィルタを解除するか、検索語を変更してください。"
                                   : "検索語を変更してください。")
            }
        } else {
            VStack(spacing: 2) {
                ForEach(games) { game in
                    NavigationLink(value: Route.game(game.id)) {
                        GameRowView(game: game)
                    }
                    .buttonStyle(OEPRowButtonStyle())
                    .contextMenu {
                        Button {
                            library.toggleFavorite(game)
                        } label: {
                            Label(game.isFavorite ? "お気に入りから外す" : "お気に入りに追加",
                                  systemImage: game.isFavorite ? "star.slash" : "star")
                        }
                        Button {
                            path.append(.diagnostics(game.id))
                        } label: {
                            Label("診断", systemImage: "stethoscope")
                        }
                        Button(role: .destructive) {
                            removalTarget = game
                            showRemovalConfirm = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                    if game.id != games.last?.id {
                        Divider().overlay(palette.border.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1))
            )
        }
    }
}
