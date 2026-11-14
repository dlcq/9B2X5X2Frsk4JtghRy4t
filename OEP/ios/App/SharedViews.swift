// OEP - small views shared by the launcher screens.
import SwiftUI

enum Route: Hashable {
    case game(UUID)
    case diagnostics(UUID)
    case logs
    case licenses
    case storage
}

struct GameRowView: View {
    @Environment(\.oep) private var palette
    let game: GameEntry
    var showFavorite: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.purple.opacity(0.34), palette.blue.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                Text(monogram)
                    .font(OEPFont.brand(18))
                    .foregroundStyle(palette.text)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(game.title)
                        .font(OEPFont.title(15))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    if game.isFavorite && showFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.partial)
                    }
                }
                Text(game.subtitle)
                    .font(OEPFont.body(12))
                    .foregroundStyle(palette.subtext)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                SupportBadge(level: game.support, compact: true)
                Text(Fmt.relative(game.lastPlayedAt))
                    .font(OEPFont.label(9))
                    .foregroundStyle(palette.subtext.opacity(0.8))
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var monogram: String {
        let letters = game.title.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(2)
        let text = String(String.UnicodeScalarView(letters))
        return text.isEmpty ? "OE" : text.uppercased()
    }
}

struct PlayButton: View {
    @Environment(\.oep) private var palette
    let game: GameEntry
    let disabledReason: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("PLAY")
                        .font(OEPFont.title(16))
                        .tracking(1.4)
                }
            }
            .buttonStyle(OEPPrimaryButtonStyle())
            .disabled(disabledReason != nil)

            if let disabledReason {
                Text(disabledReason)
                    .font(OEPFont.body(11))
                    .foregroundStyle(palette.unsupported)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct IssueListView: View {
    @Environment(\.oep) private var palette
    let issues: [ScanIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(palette.color(for: issue.supportLevel))
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.localized)
                            .font(OEPFont.body(13))
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(issue.code)
                            .font(OEPFont.mono(10))
                            .foregroundStyle(palette.subtext.opacity(0.75))
                    }
                }
            }
        }
    }
}

struct ArchiveRow: View {
    @Environment(\.oep) private var palette
    let archive: ScanArchive

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: archive.indexOk ? "shippingbox" : "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(archive.indexOk ? palette.blue : palette.unsupported)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(archive.fileName)
                    .font(OEPFont.mono(12, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(detail)
                    .font(OEPFont.body(11))
                    .foregroundStyle(palette.subtext)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Fmt.bytes(archive.fileSize))
                .font(OEPFont.mono(11))
                .foregroundStyle(palette.subtext)
        }
        .padding(.vertical, 6)
    }

    private var detail: String {
        if !archive.xp3Magic { return "XP3ではありません（無視）" }
        if !archive.indexOk { return archive.indexError ?? "インデックス読み込みエラー" }
        var parts = ["\(Fmt.count(archive.entries)) entries"]
        if archive.hashedNames > 0 { parts.append("名前置換 \(Fmt.count(archive.hashedNames))") }
        if archive.protectedEntries > 0 { parts.append("保護属性 \(Fmt.count(archive.protectedEntries))") }
        if archive.contentProbeAttempted && !archive.contentReadable { parts.append("内容保護") }
        return parts.joined(separator: " · ")
    }
}
