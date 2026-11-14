// OEP - per-game diagnostics.
import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.oep) private var palette
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var session: SessionController

    let game: GameEntry

    @State private var report: ScanReport?
    @State private var isScanning = false
    @State private var memoryBytes: UInt64 = 0
    @State private var showRawJSON = false
    @State private var engineLogs: [EngineConsoleLog.Entry] = []
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                liveSection
                engineLogSection
                if let report {
                    engineSection(report)
                    consoleLogSection(report)
                    pluginsSection(report)
                    archivesSection(report)
                    issuesSection(report)
                    rawSection(report)
                } else {
                    OEPCard {
                        HStack(spacing: 12) {
                            ProgressView().tint(palette.purple)
                            Text(isScanning ? "解析しています…" : "診断情報がありません")
                                .font(OEPFont.body(13))
                                .foregroundStyle(palette.subtext)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(OEPBackground())
        .navigationTitle("診断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await rescan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(palette.blue)
                }
                .disabled(isScanning)
            }
        }
        .task {
            memoryBytes = ProcessMetrics.residentMemoryBytes()
            engineLogs = EngineConsoleLog.recent()
            if report == nil { await loadStoredOrScan() }
        }
    }

    // MARK: - Sections

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Live")
            HStack(spacing: 10) {
                StatTile(label: "Memory", value: Fmt.bytes(Int64(memoryBytes)))
                StatTile(label: "Thermal", value: ProcessMetrics.thermalStateLabel())
                StatTile(label: "Session",
                         value: session.phase.isActive ? "\(session.elapsedSeconds)s" : "—")
            }
            OEPCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(key: "エンジン", value: OEPCore.engineBuild)
                    InfoRow(key: "コア", value: OEPCore.version)
                    InfoRow(key: "ログ件数", value: "\(OEPCore.logCount)")
                    InfoRow(key: "フォルダ", value: library.folder(for: game).path)
                }
            }
        }
    }

    /// The engine's own console log is the authoritative reason when a title
    /// refuses to start (script errors, missing plug-ins, archive problems).
    private var engineLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Engine console log",
                          trailing: engineLogs.isEmpty ? nil : "\(engineLogs.count)")
            OEPCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    if engineLogs.isEmpty {
                        Text("krkr.console.log はまだありません。エンジンを一度起動すると、ここにエラーの詳細が出ます。")
                            .font(OEPFont.body(12))
                            .foregroundStyle(palette.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(engineLogs) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(entry.url.path.replacingOccurrences(
                                        of: NSHomeDirectory(), with: "~"))
                                        .font(OEPFont.mono(9))
                                        .foregroundStyle(palette.subtext)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 6)
                                    Text(Fmt.date(entry.modified))
                                        .font(OEPFont.mono(9))
                                        .foregroundStyle(palette.subtext.opacity(0.7))
                                }
                                Text(entry.text.isEmpty ? "(空)" : entry.text)
                                    .font(OEPFont.mono(9))
                                    .foregroundStyle(palette.text)
                                    .lineLimit(120)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                ShareLink(item: entry.url) {
                                    Label("ログを共有", systemImage: "square.and.arrow.up")
                                        .font(OEPFont.label(10))
                                        .foregroundStyle(palette.blue)
                                }
                            }
                            if entry.id != engineLogs.last?.id {
                                Divider().overlay(palette.border.opacity(0.4))
                            }
                        }
                    }

                    if let hostLog = EngineConsoleLog.hostLogURL {
                        Divider().overlay(palette.border.opacity(0.4))
                        HStack(spacing: 6) {
                            Text("OEP ログ: \(hostLog.lastPathComponent)")
                                .font(OEPFont.body(11))
                                .foregroundStyle(palette.subtext)
                            Spacer()
                            ShareLink(item: hostLog) {
                                Label("共有", systemImage: "square.and.arrow.up")
                                    .font(OEPFont.label(10))
                                    .foregroundStyle(palette.blue)
                            }
                        }
                    }
                }
            }
        }
    }

    private func engineSection(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Engine", trailing: report.supportLevelJa)
            OEPCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(key: "種類", value: report.engine.kind)
                    InfoRow(key: "バージョン", value: report.engine.version.isEmpty ? "不明" : report.engine.version)
                    InfoRow(key: "TJS2", value: report.engine.tjs2Version.isEmpty ? "不明" : report.engine.tjs2Version)
                    InfoRow(key: "判定根拠", value: report.engine.evidence.isEmpty ? "—" : report.engine.evidence)
                    InfoRow(key: "同梱と一致", value: report.engine.versionMatchesBundle ? "はい (1.2.0.3)" : "いいえ")
                    if report.engine.win32VersionInfo.valid {
                        Divider().overlay(palette.border.opacity(0.6))
                        InfoRow(key: "EXE 説明", value: report.engine.win32VersionInfo.fileDescription)
                        InfoRow(key: "EXE 版", value: report.engine.win32VersionInfo.fileVersion)
                        InfoRow(key: "製品名", value: report.engine.win32VersionInfo.productName)
                    }
                    Divider().overlay(palette.border.opacity(0.6))
                    InfoRow(key: "起動スクリプト", value: report.hasStartupScript ? "あり" : "なし")
                    InfoRow(key: "data.xp3", value: report.hasDataXp3 ? "あり" : "なし")
                    InfoRow(key: "data/", value: report.hasDataFolder ? "あり" : "なし")
                    InfoRow(key: "設定ファイル", value: report.hasConfigFile ? "あり" : "なし")
                    InfoRow(key: "セーブ", value: report.hasSaveFolder ? "あり" : "なし")
                    InfoRow(key: "合計サイズ", value: Fmt.bytes(report.totalBytes))
                }
            }
        }
    }

    private func consoleLogSection(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Engine console log")
            OEPCard(padding: 14) {
                if report.engine.consoleLog.found {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(key: "Kirikiri", value: report.engine.consoleLog.kirikiriVersion)
                        InfoRow(key: "TJS2", value: report.engine.consoleLog.tjs2Version)
                        InfoRow(key: "Revision", value: report.engine.consoleLog.revision)
                        InfoRow(key: "ビルド", value: report.engine.consoleLog.buildStamp)
                        InfoRow(key: "平台", value: report.engine.consoleLog.platform)
                        InfoRow(key: "マウント数", value: "\(report.engine.consoleLog.mounts.count)")
                        if !report.engine.consoleLog.plugins.isEmpty {
                            InfoRow(key: "使用プラグイン",
                                    value: report.engine.consoleLog.plugins.joined(separator: ", "))
                        }
                    }
                } else {
                    Text("krkr.console.log は見つかりませんでした（初回起動前のゲームでは正常です）。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.subtext)
                }
            }
        }
    }

    private func pluginsSection(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Plug-ins", trailing: "\(report.plugins.count)")
            OEPCard(padding: 14) {
                if report.plugins.isEmpty {
                    Text("plugin フォルダに DLL はありません。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.subtext)
                } else {
                    VStack(spacing: 2) {
                        ForEach(report.plugins) { plugin in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(pluginColor(plugin.support))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plugin.file)
                                        .font(OEPFont.mono(12, weight: .medium))
                                        .foregroundStyle(palette.text)
                                    Text(plugin.note)
                                        .font(OEPFont.body(10))
                                        .foregroundStyle(palette.subtext)
                                }
                                Spacer(minLength: 8)
                                Text(plugin.supportJa)
                                    .font(OEPFont.label(10))
                                    .foregroundStyle(pluginColor(plugin.support))
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
    }

    private func archivesSection(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Archives", trailing: "\(report.archives.count)")
            OEPCard(padding: 14) {
                VStack(spacing: 2) {
                    ForEach(report.archives) { archive in
                        ArchiveRow(archive: archive)
                        if archive.id != report.archives.last?.id {
                            Divider().overlay(palette.border.opacity(0.4))
                        }
                    }
                }
            }
        }
    }

    private func issuesSection(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Findings", trailing: "\(report.issues.count)")
            OEPCard(padding: 14) {
                if report.issues.isEmpty {
                    Text("問題は検出されていません。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.supported)
                } else {
                    IssueListView(issues: report.issues)
                }
            }
        }
    }

    private func rawSection(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Raw report")
            OEPCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        showRawJSON.toggle()
                    } label: {
                        Text(showRawJSON ? "JSONを閉じる" : "JSONを表示")
                            .font(OEPFont.label(11))
                            .foregroundStyle(palette.blue)
                    }
                    .buttonStyle(.plain)
                    if showRawJSON, let data = try? JSONEncoder().encode(report),
                       let text = String(data: data, encoding: .utf8) {
                        Text(text)
                            .font(OEPFont.mono(9))
                            .foregroundStyle(palette.subtext)
                            .textSelection(.enabled)
                            .frame(maxHeight: 260)
                    }
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("診断JSONを共有", systemImage: "square.and.arrow.up")
                                .font(OEPFont.label(11))
                                .foregroundStyle(palette.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    @MainActor
    private func loadStoredOrScan() async {
        if let raw = game.lastReportJSON, let data = raw.data(using: .utf8),
           let stored = try? JSONDecoder().decode(ScanReport.self, from: data) {
            report = stored
        }
        await rescan()
    }

    @MainActor
    private func rescan() async {
        isScanning = true
        defer { isScanning = false }
        let path = library.folder(for: game).path
        let refreshed = await Task.detached(priority: .userInitiated) {
            OEPCore.scan(folder: path)
        }.value
        if let refreshed {
            report = refreshed
            writeShareFile(json: refreshed)
        }
        memoryBytes = ProcessMetrics.residentMemoryBytes()
        engineLogs = EngineConsoleLog.recent()
    }

    private func writeShareFile(json: ScanReport) {
        guard let data = try? JSONEncoder().encode(json) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oep-diagnostics-\(game.id.uuidString.prefix(8)).json")
        do {
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            OEPCore.log(3, "diagnostics", "could not write report: \(error.localizedDescription)")
        }
    }

    private func pluginColor(_ support: String) -> Color {
        switch support {
        case "available": return palette.supported
        case "partial": return palette.partial
        case "missing": return palette.unsupported
        default: return palette.unknown
        }
    }
}
