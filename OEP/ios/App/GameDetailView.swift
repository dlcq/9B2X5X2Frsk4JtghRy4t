// OEP - game detail screen.
import SwiftUI

struct GameDetailView: View {
    @Environment(\.oep) private var palette
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss

    let game: GameEntry

    @State private var report: ScanReport?
    @State private var showArchives = false
    @State private var showRemoveConfirm = false
    @State private var scanError: String?

    private var current: GameEntry { library.game(id: game.id) ?? game }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                playBlock
                statsGrid
                supportBlock
                if let report {
                    archivesBlock(report)
                }
                actionsBlock
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(
            ZStack {
                OEPBackground()
            }
        )
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.toggleFavorite(current)
                } label: {
                    Image(systemName: current.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(current.isFavorite ? palette.partial : palette.subtext)
                }
            }
        }
        .task {
            await loadReport()
        }
        .confirmationDialog("ゲームを削除しますか？", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("ゲームとデータを削除", role: .destructive) {
                _ = library.remove(current, deleteFiles: true)
                dismiss()
            }
            Button("ライブラリからのみ削除") {
                _ = library.remove(current, deleteFiles: false)
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("アプリ内にコピーしたゲームデータも削除されます。取り込み元のフォルダは変更されません。")
        }
    }

    // MARK: - Sections

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(current.engineTitle.uppercased())
                    .font(OEPFont.label(10))
                    .tracking(1.8)
                    .foregroundStyle(palette.purple)
                Spacer()
                SupportBadge(level: current.support)
            }
            Text(current.title)
                .font(OEPFont.brand(28))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("エンジン v\(current.engineVersion.isEmpty ? "不明" : current.engineVersion)")
                if !current.tjs2Version.isEmpty {
                    Text("TJS2 \(current.tjs2Version)")
                }
                Text("\(current.archiveCount) archives")
            }
            .font(OEPFont.mono(11))
            .foregroundStyle(palette.subtext)
        }
    }

    private var playBlock: some View {
        PlayButton(game: current, disabledReason: playDisabledReason) {
            session.play(current,
                         library: library,
                         settings: settings.settings,
                         folder: library.folder(for: current))
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatTile(label: "Last played", value: Fmt.relative(current.lastPlayedAt))
                StatTile(label: "Playtime", value: Fmt.playtime(current.playtime))
            }
            HStack(spacing: 10) {
                StatTile(label: "Size", value: Fmt.bytes(current.totalBytes))
                StatTile(label: "Launches", value: "\(current.launchCount)")
            }
        }
    }

    private var supportBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Compatibility", trailing: current.support.shortTitle)
            OEPCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: supportIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.color(for: current.support))
                        Text(supportSummary)
                            .font(OEPFont.body(13))
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let report, !report.issues.isEmpty {
                        Divider().overlay(palette.border.opacity(0.6))
                        IssueListView(issues: report.issues)
                    } else if scanError != nil {
                        Text(scanError ?? "")
                            .font(OEPFont.body(12))
                            .foregroundStyle(palette.unsupported)
                    }
                }
            }
        }
    }

    private func archivesBlock(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Archives", trailing: "\(report.archives.count)")
            OEPCard(padding: 14) {
                VStack(spacing: 2) {
                    ForEach(report.archives.prefix(showArchives ? report.archives.count : 4)) { archive in
                        ArchiveRow(archive: archive)
                        if archive.id != report.archives.prefix(showArchives ? report.archives.count : 4).last?.id {
                            Divider().overlay(palette.border.opacity(0.4))
                        }
                    }
                    if report.archives.count > 4 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showArchives.toggle() }
                        } label: {
                            Text(showArchives ? "折りたたむ" : "すべて表示 (\(report.archives.count))")
                                .font(OEPFont.label(11))
                                .foregroundStyle(palette.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var actionsBlock: some View {
        VStack(spacing: 10) {
            NavigationLink(value: Route.diagnostics(current.id)) {
                HStack(spacing: 10) {
                    Image(systemName: "stethoscope")
                    Text("診断とログ")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.subtext)
                }
                .font(OEPFont.title(14))
                .foregroundStyle(palette.text)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.elevated.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                    Text("ライブラリから削除")
                    Spacer()
                }
                .font(OEPFont.title(14))
                .foregroundStyle(palette.unsupported)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.unsupported.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(palette.unsupported.opacity(0.25), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("追加日: \(Fmt.date(current.importedAt))")
            if !current.signature.isEmpty {
                Text("署名: \(current.signature.prefix(64))")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(OEPFont.mono(9))
        .foregroundStyle(palette.subtext.opacity(0.6))
        .padding(.top, 8)
    }

    // MARK: - Data

    @MainActor
    private func loadReport() async {
        let folder = library.folder(for: current)
        let path = folder.path
        let refreshed = await Task.detached(priority: .userInitiated) {
            OEPCore.scan(folder: path)
        }.value
        if let refreshed {
            report = refreshed
            // Keep the stored assessment in sync with what the core reports now.
            var updated = current
            updated.support = refreshed.level
            updated.issueCodes = refreshed.issues.map(\.code)
            updated.archiveCount = refreshed.archives.count
            if let data = try? JSONEncoder().encode(refreshed) {
                updated.lastReportJSON = String(data: data, encoding: .utf8)
            }
            if updated.support != current.support || updated.archiveCount != current.archiveCount {
                library.update(updated)
            }
        } else if let raw = current.lastReportJSON,
                  let data = raw.data(using: .utf8),
                  let stored = try? JSONDecoder().decode(ScanReport.self, from: data) {
            report = stored
            scanError = "現在のフォルダを再解析できませんでした。保存済みの診断情報を表示しています。"
        } else {
            scanError = "診断情報を取得できませんでした。"
        }
    }

    private var playDisabledReason: String? {
        if session.engineRestartRequired {
            return "このプロセスではエンジンを実行済みです。アプリを再起動すると遊べます。"
        }
        if session.phase.isActive { return "ゲームを起動しています…" }
        if current.support == .unsupported {
            return "未対応と判定されています。診断で理由を確認してください。"
        }
        return nil
    }

    private var supportIcon: String {
        switch current.support {
        case .supported: return "checkmark.seal.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .unsupported: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var supportSummary: String {
        switch current.support {
        case .supported:
            return "同梱エンジンで起動できる構成です。"
        case .partial:
            return "起動はできますが、タイトルが要求する一部の機能・プラグインがiOS版に含まれていません。"
        case .unsupported:
            return "起動に必要な要素が見つからないため、このビルドでは実行できません。"
        case .unknown:
            return "動作を確認できていない要素があります。診断の内容を確認してください。"
        }
    }
}
