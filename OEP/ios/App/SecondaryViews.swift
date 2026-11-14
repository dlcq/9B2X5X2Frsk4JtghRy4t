// OEP - log viewer, storage management and licence screens.
import SwiftUI

// MARK: - Logs

struct LogsView: View {
    @Environment(\.oep) private var palette

    @State private var lines: [OEPLogLine] = []
    @State private var filter: OEPLogLine.Level = .debug
    @State private var query = ""
    @State private var shareURL: URL?
    @State private var fileLogURL: URL?
    @State private var showClearConfirm = false

    private var visible: [OEPLogLine] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.reversed().filter { line in
            guard line.level >= filter else { return false }
            if trimmed.isEmpty { return true }
            return line.category.localizedCaseInsensitiveContains(trimmed)
                || line.message.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            controls
            if visible.isEmpty {
                Spacer()
                EmptyStateView(icon: "doc.text",
                               title: "ログがありません",
                               message: "操作やゲーム起動でここにログが追加されます。")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visible) { line in
                            row(line)
                            Divider().overlay(palette.border.opacity(0.35))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(OEPBackground())
        .navigationTitle("ログ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                if let fileLogURL {
                    ShareLink(item: fileLogURL) {
                        Image(systemName: "doc.badge.arrow.up")
                    }
                }
                Button {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("ログを削除しますか？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                OEPCore.clearLog()
                refresh()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .task { refresh() }
        .refreshable { refresh() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach([OEPLogLine.Level.debug, .info, .warning, .error], id: \.self) { level in
                    Button {
                        filter = level
                    } label: {
                        Text(level.title)
                            .font(OEPFont.label(9))
                            .tracking(0.6)
                            .foregroundStyle(filter == level ? palette.text : palette.subtext)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(filter == level ? color(for: level).opacity(0.22) : palette.card)
                                    .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.subtext)
                TextField("カテゴリ・メッセージを検索", text: $query)
                    .font(OEPFont.body(13))
                    .foregroundStyle(palette.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1))
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func row(_ line: OEPLogLine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(line.level.title)
                    .font(OEPFont.label(9))
                    .foregroundStyle(color(for: line.level))
                Text(line.category)
                    .font(OEPFont.mono(10, weight: .medium))
                    .foregroundStyle(palette.subtext)
                Spacer()
                Text(line.timestamp)
                    .font(OEPFont.mono(9))
                    .foregroundStyle(palette.subtext.opacity(0.6))
            }
            Text(line.message)
                .font(OEPFont.mono(11))
                .foregroundStyle(palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private func color(for level: OEPLogLine.Level) -> Color {
        switch level {
        case .debug: return palette.unknown
        case .info: return palette.blue
        case .warning: return palette.partial
        case .error: return palette.unsupported
        }
    }

    private func refresh() {
        lines = OEPLogLine.parseAll(OEPCore.logText())
        let text = OEPCore.logText()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oep-log.txt")
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        shareURL = url
        fileLogURL = EngineConsoleLog.hostLogURL
    }
}

// MARK: - Storage

struct StorageView: View {
    @Environment(\.oep) private var palette
    @EnvironmentObject private var library: LibraryStore

    @State private var sizes: [UUID: Int64] = [:]
    @State private var cacheBytes: Int64 = 0
    @State private var isMeasuring = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    StatTile(label: "Games", value: Fmt.bytes(library.totalBytes))
                    StatTile(label: "Cache", value: Fmt.bytes(cacheBytes))
                }
                OEPCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Installed")
                        if library.games.isEmpty {
                            Text("登録されたゲームはありません。")
                                .font(OEPFont.body(12))
                                .foregroundStyle(palette.subtext)
                        } else {
                            ForEach(library.games) { game in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.title)
                                            .font(OEPFont.body(13))
                                            .foregroundStyle(palette.text)
                                            .lineLimit(1)
                                        Text(game.folderName)
                                            .font(OEPFont.mono(9))
                                            .foregroundStyle(palette.subtext.opacity(0.7))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(Fmt.bytes(sizes[game.id] ?? game.totalBytes))
                                        .font(OEPFont.mono(11))
                                        .foregroundStyle(palette.subtext)
                                }
                                .padding(.vertical, 6)
                                Divider().overlay(palette.border.opacity(0.4))
                            }
                        }
                    }
                }
                OEPCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(key: "ライブラリ", value: library.rootURL.path)
                        InfoRow(key: "ゲーム", value: library.gamesURL.path)
                        InfoRow(key: "空き容量", value: Fmt.bytes(Int64(availableDiskBytes())))
                        if isMeasuring {
                            HStack(spacing: 8) {
                                ProgressView().tint(palette.purple)
                                Text("計測中…")
                                    .font(OEPFont.body(11))
                                    .foregroundStyle(palette.subtext)
                            }
                        }
                    }
                }
                Button {
                    Task { await measure() }
                } label: {
                    Text("使用量を再計測")
                }
                .buttonStyle(OEPSecondaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background(OEPBackground())
        .navigationTitle("ストレージ")
        .navigationBarTitleDisplayMode(.inline)
        .task { await measure() }
    }

    @MainActor
    private func measure() async {
        isMeasuring = true
        let games = library.games
        let folderProvider = library
        let result = await Task.detached(priority: .utility) { () -> [UUID: Int64] in
            var dict: [UUID: Int64] = [:]
            for game in games {
                dict[game.id] = folderProvider.directorySize(folderProvider.folder(for: game))
            }
            return dict
        }.value
        sizes = result
        cacheBytes = library.cacheBytes
        isMeasuring = false
    }

    private func availableDiskBytes() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

// MARK: - Licences

struct LicenseView: View {
    @Environment(\.oep) private var palette

    private struct Component: Identifiable {
        var id: String { name }
        let name: String
        let license: String
        let note: String
    }

    private let components: [Component] = [
        Component(name: "KiriKiri Z (krkrz_dev)",
                  license: "KiriKiri licence (BSD-style)",
                  note: "エンジン本体。wamsoft / W.Dee and contributors。krkrz 1.2.0.3 系のソースを静的リンクしています。"),
        Component(name: "krkrz_ios",
                  license: "MIT",
                  note: "iOS 向けの CMake / Xcode ビルド定義とプラグイン構成。"),
        Component(name: "SDL3",
                  license: "zlib",
                  note: "ウィンドウ、入力、音声、OpenGL ES コンテキスト。"),
        Component(name: "OEP core (miniz)",
                  license: "MIT",
                  note: "XP3 の zlib 展開に使用。"),
        Component(name: "OEP app",
                  license: "プロジェクト内 (private)",
                  note: "SwiftUI ランチャー、インポート、診断。"),
        Component(name: "vcpkg 依存ライブラリ",
                  license: "各ライブラリのライセンス",
                  note: "zlib, libpng, libjpeg-turbo, libwebp, FreeType, HarfBuzz, libvorbis, Opus, oniguruma, glm, lz4, xxHash, uchardet など。"),
        Component(name: "ゲームデータ",
                  license: "各権利者",
                  note: "このアプリには同梱していません。ユーザーが自身の環境から取り込みます。"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OEPCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OEP は吉里吉里Z (krkrz) を利用したプレイヤーです。")
                            .font(OEPFont.body(13))
                            .foregroundStyle(palette.text)
                        Text("ゲームのスクリプト・画像・音声は同梱しておらず、ユーザーが取り込んだデータのみを再生します。各ゲームの利用条件は権利者の定めに従ってください。")
                            .font(OEPFont.body(11))
                            .foregroundStyle(palette.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(components) { component in
                    OEPCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(component.name)
                                    .font(OEPFont.title(14))
                                    .foregroundStyle(palette.text)
                                Spacer()
                                Text(component.license)
                                    .font(OEPFont.label(9))
                                    .foregroundStyle(palette.blue)
                            }
                            Text(component.note)
                                .font(OEPFont.body(11))
                                .foregroundStyle(palette.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("エンジン同梱ライブラリの全文ライセンスは、krkrz の -license 出力および各ライブラリの配布物を参照してください。")
                    .font(OEPFont.body(10))
                    .foregroundStyle(palette.subtext.opacity(0.75))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background(OEPBackground())
        .navigationTitle("ライセンス")
        .navigationBarTitleDisplayMode(.inline)
    }
}
