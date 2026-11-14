// OEP - overlays shown around a game session.
import SwiftUI

/// Shown while the engine initialises; the SDL window then covers the launcher.
struct EngineLoadingOverlay: View {
    @Environment(\.oep) private var palette
    let game: GameEntry
    var onCancel: () -> Void

    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            palette.background.opacity(0.86).ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(palette.border, lineWidth: 2)
                        .frame(width: 84, height: 84)
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(LinearGradient(colors: [palette.purple, palette.blue],
                                               startPoint: .leading,
                                               endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 84, height: 84)
                        .rotationEffect(.degrees(phase * 360))
                    Text(monogram)
                        .font(OEPFont.brand(22))
                        .foregroundStyle(palette.text)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }

                VStack(spacing: 8) {
                    Text(game.title)
                        .font(OEPFont.title(19))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                    Text("エンジン起動中")
                        .font(OEPFont.label(10))
                        .tracking(2.0)
                        .foregroundStyle(palette.purple)
                }

                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(palette.purple)
                    .frame(width: 180)

                Text("初回の読み込みには数秒かかることがあります。")
                    .font(OEPFont.body(11))
                    .foregroundStyle(palette.subtext)

                Button("キャンセル", action: onCancel)
                    .buttonStyle(OEPSecondaryButtonStyle())
                    .frame(width: 180)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }

    private var monogram: String {
        let text = String(game.title.prefix(2))
        return text.isEmpty ? "OEP" : text
    }
}

/// Shown when a session ends normally.
struct SessionResultOverlay: View {
    @Environment(\.oep) private var palette
    let reason: String
    let seconds: Int
    let restartRequired: Bool
    var onClose: () -> Void

    var body: some View {
        ZStack {
            palette.background.opacity(0.92).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: reason == "success" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(reason == "success" ? palette.supported : palette.partial)
                    Text(reason == "success" ? "ゲームを終了しました" : "ゲームが終了しました")
                        .font(OEPFont.title(18))
                        .foregroundStyle(palette.text)
                }
                if seconds > 0 {
                    InfoRow(key: "プレイ時間", value: Fmt.playtime(TimeInterval(seconds)))
                }
                if restartRequired {
                    Text("krkrz のエンジン初期化はプロセスごとに1回のため、続けて別のゲームを遊ぶにはアプリを終了して再起動してください。ライブラリとプレイ時間は保存されています。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("ライブラリに戻る", action: onClose)
                    .buttonStyle(OEPPrimaryButtonStyle())
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1))
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}

/// Shown when the engine could not start.
struct SessionFailureOverlay: View {
    @Environment(\.oep) private var palette
    let message: String
    let restartRequired: Bool
    var onClose: () -> Void

    var body: some View {
        ZStack {
            palette.background.opacity(0.94).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(palette.unsupported)
                    Text("起動できませんでした")
                        .font(OEPFont.title(18))
                        .foregroundStyle(palette.text)
                }
                Text(message)
                    .font(OEPFont.body(13))
                    .foregroundStyle(palette.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                if restartRequired {
                    Text("エンジンはこのプロセスで既に初期化されています。アプリを再起動してから再度お試しください。")
                        .font(OEPFont.body(12))
                        .foregroundStyle(palette.partial)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("診断画面のログに、エンジンが出力したエラーが残っています。")
                    .font(OEPFont.body(11))
                    .foregroundStyle(palette.subtext.opacity(0.8))
                Button("閉じる", action: onClose)
                    .buttonStyle(OEPSecondaryButtonStyle())
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1))
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}
