// OEP - add game flow: pick -> scan -> review -> copy -> registered.
import SwiftUI
import UniformTypeIdentifiers

struct AddGameView: View {
    @Environment(\.oep) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var importer: ImportService

    @State private var showPicker = false
    @State private var titleDraft = ""
    @State private var didRequestPicker = false

    private var xp3Type: UTType {
        UTType(filenameExtension: "xp3") ?? .data
    }

    var body: some View {
        ZStack {
            OEPBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch importer.stage {
                        case .idle, .failed:
                            pickSection
                        case .scanning:
                            scanningSection
                        case .review:
                            reviewSection
                        case .copying:
                            copyingSection
                        case .done:
                            doneSection
                        }
                        if let message = importer.errorMessage, importer.stage != .done {
                            errorCard(message)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.folder, xp3Type],
                      allowsMultipleSelection: false) { result in
            handlePicked(result)
        }
        .onAppear {
            guard !didRequestPicker else { return }
            didRequestPicker = true
            showPicker = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ADD GAME")
                    .font(OEPFont.label(10))
                    .tracking(2.2)
                    .foregroundStyle(palette.purple)
                Text("ゲームを追加")
                    .font(OEPFont.title(24))
                    .foregroundStyle(palette.text)
            }
            Spacer()
            Button {
                importer.reset()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.subtext)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(palette.card))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }

    // MARK: - Stages

    private var pickSection: some View {
        OEPCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("フォルダを選択")
                    .font(OEPFont.title(17))
                    .foregroundStyle(palette.text)
                Text("ファイルアプリから、data.xp3 を含むゲームフォルダ（または data/startup.tjs）を選択してください。単体の .xp3 を選んだ場合はフォルダに包んでから取り込みます。")
                    .font(OEPFont.body(13))
                    .foregroundStyle(palette.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    importer.reset()
                    showPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text("フォルダを選ぶ")
                    }
                }
                .buttonStyle(OEPSecondaryButtonStyle())

                VStack(alignment: .leading, spacing: 6) {
                    bullet("元のフォルダは変更しません（読み取りのみ）")
                    bullet("アプリ内の管理領域へコピーしてから登録します")
                    bullet("アーカイブのインデックスだけを解析し、内容は読みません")
                }
            }
        }
    }

    private var scanningSection: some View {
        OEPCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.purple)
                    Text(importer.statusText.isEmpty ? "解析しています…" : importer.statusText)
                        .font(OEPFont.body(14))
                        .foregroundStyle(palette.text)
                }
                Text("XP3インデックス、設定ファイル、プラグイン構成を確認しています。")
                    .font(OEPFont.body(12))
                    .foregroundStyle(palette.subtext)
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let candidate = importer.candidate {
            OEPCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("解析結果")
                            .font(OEPFont.title(17))
                            .foregroundStyle(palette.text)
                        Spacer()
                        SupportBadge(level: candidate.report.level)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("タイトル")
                            .font(OEPFont.label(10))
                            .tracking(1.2)
                            .foregroundStyle(palette.subtext)
                        TextField("タイトル", text: $titleDraft)
                            .font(OEPFont.title(16))
                            .foregroundStyle(palette.text)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(palette.elevated.opacity(0.6))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(palette.border, lineWidth: 1))
                            )
                            .onChange(of: titleDraft) { newValue in
                                importer.updateTitle(newValue)
                            }
                    }

                    Divider().overlay(palette.border.opacity(0.6))

                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(key: "エンジン", value: candidate.report.engine.kind)
                        InfoRow(key: "バージョン", value: candidate.report.engine.version.isEmpty ? "不明" : candidate.report.engine.version)
                        InfoRow(key: "TJS2", value: candidate.report.engine.tjs2Version.isEmpty ? "不明" : candidate.report.engine.tjs2Version)
                        InfoRow(key: "アーカイブ", value: "\(candidate.report.archives.count)")
                        InfoRow(key: "サイズ", value: Fmt.bytes(candidate.totalBytes))
                        InfoRow(key: "ファイル数", value: "\(candidate.fileCount)")
                        InfoRow(key: "起動スクリプト", value: candidate.report.hasStartupScript ? "あり" : "なし")
                    }

                    if !candidate.report.issues.isEmpty {
                        Divider().overlay(palette.border.opacity(0.6))
                        Text("注意点")
                            .font(OEPFont.label(10))
                            .tracking(1.2)
                            .foregroundStyle(palette.subtext)
                        IssueListView(issues: candidate.report.issues)
                    }

                    Divider().overlay(palette.border.opacity(0.6))

                    Text("≒ \(Fmt.bytes(candidate.totalBytes)) をアプリ内にコピーします。空き容量に注意してください。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.subtext)

                    Button {
                        Task {
                            await importer.commit(library: library)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "tray.and.arrow.down.fill")
                            Text("ライブラリに追加")
                        }
                    }
                    .buttonStyle(OEPPrimaryButtonStyle())
                    .disabled(importer.errorMessage != nil)

                    Button("選び直す") {
                        importer.reset()
                        showPicker = true
                    }
                    .buttonStyle(OEPSecondaryButtonStyle())
                }
            }
        }
    }

    private var copyingSection: some View {
        OEPCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("コピー中")
                    .font(OEPFont.title(17))
                    .foregroundStyle(palette.text)
                ProgressView(value: importer.progress)
                    .tint(palette.purple)
                Text(importer.statusText)
                    .font(OEPFont.mono(11))
                    .foregroundStyle(palette.subtext)
                    .lineLimit(1)
                Text("\(Int(importer.progress * 100))%")
                    .font(OEPFont.mono(22, weight: .semibold))
                    .foregroundStyle(palette.text)
                Button("キャンセル") {
                    importer.cancel()
                }
                .buttonStyle(OEPSecondaryButtonStyle())
            }
        }
    }

    private var doneSection: some View {
        OEPCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(palette.supported)
                    Text("登録が完了しました")
                        .font(OEPFont.title(18))
                        .foregroundStyle(palette.text)
                }
                Text("ホームまたはライブラリからプレイできます。")
                    .font(OEPFont.body(13))
                    .foregroundStyle(palette.subtext)
                Button("閉じる") {
                    importer.reset()
                    dismiss()
                }
                .buttonStyle(OEPPrimaryButtonStyle())
                Button("続けて追加") {
                    importer.reset()
                    showPicker = true
                }
                .buttonStyle(OEPSecondaryButtonStyle())
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.unsupported)
            Text(message)
                .font(OEPFont.body(13))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.unsupported.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.unsupported.opacity(0.3), lineWidth: 1))
        )
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(palette.blue.opacity(0.8))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(OEPFont.body(12))
                .foregroundStyle(palette.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Picker

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await importer.prepare(url: url, library: library)
                if let candidate = importer.candidate {
                    titleDraft = candidate.title
                }
            }
        case .failure(let error):
            // A cancelled picker is not an error worth logging loudly.
            OEPCore.log(1, "import", "picker closed: \(error.localizedDescription)")
        }
    }
}
