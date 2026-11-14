// OEP - add game flow: pick -> scan -> review -> copy/move -> registered.
//
// Two routes are offered because iOS's folder picker only enables "Open" while
// you are inside a folder:
//   * the app's Documents folder (Files app > On My iPhone > OEP), which is the
//     most reliable route, and the folder is moved (not copied) into the library;
//   * the system document picker, for anything else the user can reach.
import SwiftUI
import UniformTypeIdentifiers

struct AddGameView: View {
    @Environment(\.oep) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var importer: ImportService

    @State private var didRequestPicker = false
    @State private var titleDraft = ""
    @State private var inboxEntries: [DocumentsInbox.Entry] = []
    @State private var pickerError: String?

    var body: some View {
        ZStack {
            OEPBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch importer.stage {
                        case .idle, .failed:
                            sourcesSection
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
                        if let pickerError {
                            errorCard(pickerError)
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
        .task { reloadInbox() }
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

    // MARK: - Source selection

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            OEPCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.purple)
                        Text("このアプリのフォルダから選ぶ（推奨）")
                            .font(OEPFont.title(15))
                            .foregroundStyle(palette.text)
                    }
                    Text("ファイルアプリで「このiPhone内 > OEP」にゲームフォルダをコピーしてください。フォルダごとコピーできます。ここに表示されたフォルダは、追加時にアプリの管理領域へ移動します（二重に容量を使いません）。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)

                    if inboxEntries.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "tray")
                                .foregroundStyle(palette.subtext)
                            Text("まだ何もありません")
                                .font(OEPFont.body(12))
                                .foregroundStyle(palette.subtext)
                            Spacer()
                            Button("再読み込み") { reloadInbox() }
                                .font(OEPFont.label(11))
                                .buttonStyle(.plain)
                                .foregroundStyle(palette.blue)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(inboxEntries) { entry in
                                HStack(spacing: 10) {
                                    Image(systemName: entry.isDirectory ? "folder" : "shippingbox")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(entry.looksLikeGame ? palette.blue : palette.subtext)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.name)
                                            .font(OEPFont.body(13))
                                            .foregroundStyle(palette.text)
                                            .lineLimit(1)
                                        Text(entry.isDirectory
                                             ? (entry.looksLikeGame ? "ゲームフォルダ" : "フォルダ")
                                             : "XP3 アーカイブ")
                                            .font(OEPFont.body(10))
                                            .foregroundStyle(palette.subtext)
                                    }
                                    Spacer(minLength: 6)
                                    Button("取り込む") {
                                        pickerError = nil
                                        Task {
                                            await importer.prepare(url: entry.url,
                                                                   library: library,
                                                                   origin: .documents)
                                            titleDraft = importer.candidate?.title ?? ""
                                        }
                                    }
                                    .font(OEPFont.label(11))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(palette.blue)
                                }
                                .padding(.vertical, 7)
                                if entry.id != inboxEntries.last?.id {
                                    Divider().overlay(palette.border.opacity(0.4))
                                }
                            }
                        }
                        Button("再読み込み") { reloadInbox() }
                            .font(OEPFont.label(10))
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.subtext)
                    }
                }
            }

            OEPCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.blue)
                        Text("ファイルアプリから選ぶ")
                            .font(OEPFont.title(15))
                            .foregroundStyle(palette.text)
                    }
                    Text("iOS のフォルダ選択は「フォルダの中に入ってから右上の『開く』」で確定します。『開く』が押せないときは、フォルダを開いてから押してください。ゲームの入ったフォルダ自体、またはその親フォルダのどちらでも選べます。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        pickerError = nil
                        SystemPicker.present(mode: .archive) { result in
                            handlePicked(result)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                            Text("フォルダ / .xp3 を選ぶ")
                        }
                    }
                    .buttonStyle(OEPSecondaryButtonStyle())
                }
            }

            OEPCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("取り込みについて")
                        .font(OEPFont.label(10))
                        .tracking(1.2)
                        .foregroundStyle(palette.subtext)
                    bullet("元のフォルダは変更しません（Documents からの追加時は移動します）")
                    bullet("アーカイブのインデックスだけを解析し、内容は読みません")
                    bullet("同じ内容のゲームは重複として登録を止めます")
                }
            }
        }
    }

    // MARK: - Stages

    private var scanningSection: some View {
        OEPCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView().tint(palette.purple)
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
                        InfoRow(key: "取り込み方法", value: candidate.shouldMove ? "移動" : "コピー")
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

                    Text(candidate.shouldMove
                         ? "≒ \(Fmt.bytes(candidate.totalBytes)) をアプリの管理領域へ移動します。"
                         : "≒ \(Fmt.bytes(candidate.totalBytes)) をアプリ内にコピーします。空き容量に注意してください。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.subtext)

                    Button {
                        Task { await importer.commit(library: library) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: candidate.shouldMove ? "arrow.right.circle.fill" : "tray.and.arrow.down.fill")
                            Text("ライブラリに追加")
                        }
                    }
                    .buttonStyle(OEPPrimaryButtonStyle())
                    .disabled(importer.errorMessage != nil)

                    Button("選び直す") {
                        importer.reset()
                        reloadInbox()
                    }
                    .buttonStyle(OEPSecondaryButtonStyle())
                }
            }
        }
    }

    private var copyingSection: some View {
        OEPCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(importer.statusText.hasPrefix("ゲームデータを移動") ? "移動中" : "コピー中")
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
                Button("キャンセル") { importer.cancel() }
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
                    reloadInbox()
                }
                .buttonStyle(OEPSecondaryButtonStyle())
            }
        }
    }

    // MARK: - Helpers

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

    private func reloadInbox() {
        inboxEntries = DocumentsInbox.entries()
    }

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await importer.prepare(url: url, library: library, origin: .picker)
                titleDraft = importer.candidate?.title ?? ""
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                OEPCore.log(1, "import", "picker cancelled")
            } else {
                pickerError = error.localizedDescription
                OEPCore.log(2, "import", "picker failed: \(error.localizedDescription)")
            }
        }
    }
}
