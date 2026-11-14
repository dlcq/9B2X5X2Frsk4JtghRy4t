// OEP - settings.  Only options that really change behaviour are shown.
import SwiftUI

struct SettingsView: View {
    @Environment(\.oep) private var palette
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var session: SessionController

    @State private var showClearCacheConfirm = false
    @State private var clearedBytes: Int64?

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    appearanceSection
                    runtimeSection
                    dataSection
                    diagnosticsSection
                    aboutSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .navigationBarHidden(true)
            .confirmationDialog("キャッシュを削除しますか？",
                                isPresented: $showClearCacheConfirm,
                                titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    clearedBytes = library.clearCaches()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("一時ファイルのみ削除します。ゲームデータとライブラリは残ります。")
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .logs: LogsView()
                case .storage: StorageView()
                case .licenses: LicenseView()
                case .game(let id):
                    if let game = library.game(id: id) { GameDetailView(game: game) }
                case .diagnostics(let id):
                    if let game = library.game(id: id) { DiagnosticsView(game: game) }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SETTINGS")
                .font(OEPFont.label(10))
                .tracking(2.2)
                .foregroundStyle(palette.purple)
            Text("設定")
                .font(OEPFont.title(26))
                .foregroundStyle(palette.text)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Appearance")
            OEPCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("テーマ")
                        .font(OEPFont.body(14))
                        .foregroundStyle(palette.text)
                    HStack(spacing: 8) {
                        ForEach(AppSettings.Theme.allCases) { theme in
                            Button {
                                settings.settings.theme = theme
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(theme.title)
                                        .font(OEPFont.label(11))
                                    Text(theme.subtitle)
                                        .font(OEPFont.body(10))
                                        .foregroundStyle(settings.settings.theme == theme
                                                         ? palette.text.opacity(0.8)
                                                         : palette.subtext)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .foregroundStyle(settings.settings.theme == theme
                                                 ? palette.text : palette.subtext)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(settings.settings.theme == theme
                                              ? palette.purple.opacity(0.16)
                                              : palette.elevated.opacity(0.5))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(settings.settings.theme == theme
                                                          ? palette.purple.opacity(0.5)
                                                          : palette.border,
                                                          lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Runtime

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Game runtime")
            OEPCard(padding: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("フレームレート")
                            .font(OEPFont.body(14))
                            .foregroundStyle(palette.text)
                        Text("エンジンを駆動する CADisplayLink の上限です。端末が対応しない値は自動的に丸められます。")
                            .font(OEPFont.body(11))
                            .foregroundStyle(palette.subtext)
                        HStack(spacing: 8) {
                            ForEach(AppSettings.FrameRate.allCases) { rate in
                                Button {
                                    settings.settings.frameRate = rate
                                } label: {
                                    Text(rate.title)
                                        .font(OEPFont.mono(12, weight: .medium))
                                        .foregroundStyle(settings.settings.frameRate == rate
                                                         ? palateText : palette.subtext)
                                        .padding(.vertical, 9)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill(settings.settings.frameRate == rate
                                                      ? palette.purple.opacity(0.18)
                                                      : palette.elevated.opacity(0.5))
                                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                    .strokeBorder(settings.settings.frameRate == rate
                                                                  ? palette.purple.opacity(0.5)
                                                                  : palette.border,
                                                                  lineWidth: 1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("ゲーム起動後に変更した値は次回の起動から適用されます。")
                            .font(OEPFont.body(10))
                            .foregroundStyle(palette.subtext.opacity(0.8))
                    }

                    Divider().overlay(palette.border.opacity(0.6))

                    Toggle(isOn: Binding(
                        get: { settings.settings.keepScreenAwake },
                        set: { settings.settings.keepScreenAwake = $0 })
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("プレイ中はスリープしない")
                                .font(OEPFont.body(14))
                                .foregroundStyle(palette.text)
                            Text("ゲームセッション中だけ画面の自動ロックを無効にします。")
                                .font(OEPFont.body(11))
                                .foregroundStyle(palette.subtext)
                        }
                    }
                    .tint(palette.purple)
                }
            }

            OEPCard(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("エンジンの入力")
                        .font(OEPFont.body(14))
                        .foregroundStyle(palette.text)
                    Text("1本指タップ/ドラッグ = 左クリック、2本指タップ = ESC（戻る）、2本指の上下スワイプ = ホイール。krkrz の iOS 実装に固定されています。")
                        .font(OEPFont.body(11))
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var palateText: Color { palette.text }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Data")
            OEPCard(padding: 8) {
                VStack(spacing: 0) {
                    NavigationLink(value: Route.storage) {
                        row(icon: "internaldrive",
                            title: "ストレージ",
                            value: Fmt.bytes(library.totalBytes))
                    }
                    .buttonStyle(OEPRowButtonStyle())

                    Divider().overlay(palette.border.opacity(0.5)).padding(.leading, 48)

                    Button {
                        showClearCacheConfirm = true
                    } label: {
                        row(icon: "trash",
                            title: "キャッシュを削除",
                            value: clearedBytes.map { "\(Fmt.bytes($0)) 削除" } ?? Fmt.bytes(library.cacheBytes))
                    }
                    .buttonStyle(OEPRowButtonStyle())

                    Divider().overlay(palette.border.opacity(0.5)).padding(.leading, 48)

                    row(icon: "folder",
                        title: "ゲームの保存場所",
                        value: library.gamesURL.path.replacingOccurrences(
                            of: NSHomeDirectory(), with: "~"))
                        .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Diagnostics")
            OEPCard(padding: 8) {
                VStack(spacing: 0) {
                    NavigationLink(value: Route.logs) {
                        row(icon: "doc.text.magnifyingglass",
                            title: "ログ",
                            value: "\(OEPCore.logCount) 件")
                    }
                    .buttonStyle(OEPRowButtonStyle())

                    Divider().overlay(palette.border.opacity(0.5)).padding(.leading, 48)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("ログレベル")
                                .font(OEPFont.body(14))
                                .foregroundStyle(palette.text)
                            Spacer()
                            Picker("ログレベル", selection: Binding(
                                get: { settings.settings.logLevel },
                                set: {
                                    settings.settings.logLevel = $0
                                    OEPHostLogSetMinimumLevel(Int32($0))
                                })
                            ) {
                                Text("デバッグ").tag(0)
                                Text("情報").tag(1)
                                Text("警告以上").tag(2)
                                Text("エラーのみ").tag(3)
                            }
                            .pickerStyle(.menu)
                            .tint(palette.blue)
                        }
                        Text("エンジンのログは os_log にも出力されます。")
                            .font(OEPFont.body(10))
                            .foregroundStyle(palette.subtext)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)

                    Divider().overlay(palette.border.opacity(0.5)).padding(.leading, 48)

                    row(icon: "memorychip",
                        title: "メモリ使用量",
                        value: Fmt.bytes(Int64(ProcessMetrics.residentMemoryBytes())))
                        .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "About")
            OEPCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("OEP")
                            .font(OEPFont.brand(20))
                            .foregroundStyle(palette.text)
                        Text("OniichanErogePlayer")
                            .font(OEPFont.label(10))
                            .tracking(1.2)
                            .foregroundStyle(palette.subtext)
                        Spacer()
                        Text(appVersion)
                            .font(OEPFont.mono(11))
                            .foregroundStyle(palette.subtext)
                    }
                    Divider().overlay(palette.border.opacity(0.6))
                    InfoRow(key: "エンジン", value: OEPCore.engineBuild)
                    InfoRow(key: "コア", value: OEPCore.version)
                    InfoRow(key: "セッション", value: session.engineRestartRequired ? "実行済み（再起動が必要）" : "未実行")
                    Divider().overlay(palette.border.opacity(0.6))
                    NavigationLink(value: Route.licenses) {
                        HStack {
                            Text("ライセンス情報")
                                .font(OEPFont.body(14))
                                .foregroundStyle(palette.blue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.subtext)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.purple.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.purple)
            }
            Text(title)
                .font(OEPFont.body(14))
                .foregroundStyle(palette.text)
            Spacer()
            Text(value)
                .font(OEPFont.mono(11))
                .foregroundStyle(palette.subtext)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
