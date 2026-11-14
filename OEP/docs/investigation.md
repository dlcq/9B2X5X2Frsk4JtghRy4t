# 既存実装の調査レポート

調査日: 2026-11-14 / 対象: 2026-11 時点の各リポジトリ HEAD

3つの候補実装を clone し、README だけでなく **ソースコード**（エンジンの起動経路、iOS プラットフォーム層、
パッケージング、ライセンス表記）を確認した。調査に使った clone は `../_refs/`（リポジトリ外）に置き、
プロジェクトには取り込んでいない。

- `wamsoft/krkrz_ios` @ `003abad6`
- `OWCramer/KiriKit` @ 取得時 HEAD
- `FiresonZ/PocketKrKr` @ 取得時 HEAD
- 参照実装として `wamsoft/krkrz_dev` @ `21d20e97`（`src/core` サブモジュール = `wamsoft/krkrz` @ `7d91ba56`）
- `libsdl-org/SDL` @ `release-3.4.4`（krkrz_ios が固定しているバージョン）

---

## 1. 比較表

| 項目 | krkrz_ios (wamsoft) | KiriKit (OWCramer) | PocketKrKr (FiresonZ) |
|---|---|---|---|
| 吉里吉里バージョン | **krkrz 1.2.0.3 系**（`krkrz_dev` の `src/core` = `wamsoft/krkrz`） | krkr2 @`3ac366c`（KiriKiri 2/Z core）+ wamsoft/krkrsdl3 プラグイン | KiriKiri2 core を modernize |
| iOS 対応 | 公式。iOS/iPadOS 用の CMake + Xcode ビルド一式 | 対応（`Vendor/ShioriKrkr.xcframework` を生成） | 主目標だが「開発中」 |
| 言語 | C++ / Objective-C(++)(SDL 内部) / CMake / Python（生成スクリプト） | C++ + Swift Package（`CKiriKit` は C ABI） | C++ + Dart/Flutter |
| 描画 | SDL3 + **OpenGL ES**（`ogl` / `sdlogl` DrawDevice）または SDL_Renderer(Metal) | Metal コンポジタ（自前 `render/`） | ANGLE（Metal/Vulkan）+ IOSurface ゼロコピー |
| 音声 | エンジン内蔵（Ogg Vorbis / Opus、miniaudio）+ CoreAudio | 自前 audio + FFmpeg | エンジン側 |
| XP3 | エンジン本体が処理（標準 XP3、zlib 連鎖インデックス、保護属性） | エンジン + GARbro 由来の Cx/Hx 復号（実行時スキーム構築） | エンジン側 |
| TJS2 / KAG | フル（KAGParserEx など静的リンク） | フル（krkr2 core、E-mote も自前実装） | フル（KiriKiri2） |
| ビルド | macOS + Xcode 15+ / CMake 3.24+ / vcpkg / `krkrz_dev` clone。`make build/run/ipa` | Xcode 26+ / CMake / Ninja / **FFmpeg を Shiori のスクリプトで自前ビルド** / `fetch.sh` + `build-framework.sh` | Flutter SDK + vcpkg + CMakePresets、ANGLE |
| 依存 | SDL3 3.4.4、vcpkg（freetype, harfbuzz, libvorbis, opus, oniguruma, png, jpeg, lz4, xxhash…）、Elements / ThorVG | 上記 + FFmpeg n8.0.3（LGPL、静的） | ANGLE、Flutter engine |
| ライセンス | リポジトリは **MIT**。エンジン/プラグインは KiriKiri licence（BSD 系）、SDL は zlib | 自前コード **MPL-2.0**、krkr2 は KiriKiri licence、GARbro 部分 MIT、FFmpeg LGPL-2.1+ | **GPL-3.0** |
| メンテナンス | 活発（iOS 対応の修正は krkrz_dev の develop 系） | 活発（Shiori の一部） | 活発だが iOS は未完成 |
| アプリ形態 | **1タイトルをバンドルした単体アプリ**（`assetPack`）。ランチャーなし | Shiori アプリ用のフレームワーク。単体ランチャーなし | Flutter ランチャー + エンジン |
| 流用できるもの | エンジン本体、iOS ビルド定義、静的プラグイン構成、タッチ→マウス変換、VoiceOver 対応、IPA 書き出し | C ABI の設計、E-mote 実装、暗号化 XP3 のスキーム DB | C ABI（`engine_api`）、ANGLE/IOSurface の知見 |

## 2. 各実装の要点（ソースで確認したこと）

### krkrz_ios

- `krkrz_dev/src/core`（= `wamsoft/krkrz`）を `add_subdirectory` し、**単一の `krkrz` 実行ファイル**
  （`MACOSX_BUNDLE`）を作る。iOS は `dlopen` 不可のため全プラグインを静的リンクする
  （`CMakeLists.txt`: `list(APPEND TVP_PLUGINS_STATIC ${TVP_PLUGINS})`）。
- 起動データは `assetPack` でアプリバンドル直下にコピーする方式。`sdl3/environ/stdapp.cpp` の
  `InitPath()` が `data.xp3` → exe 結合 XP3 → `data/startup.tjs` の順に探し、iOS では
  見つからなければエラーで終了する（**iOS にはプロジェクトフォルダ選択ダイアログが無い**）。
- タッチはエンジン側で変換する：1本指=左ボタン、2本指タップ=ESC、2本指上下=ホイール
  （`sdl3/environ/form.cpp`。SDL 標準のタッチ→マウス変換は `SDL_HINT_TOUCH_MOUSE_EVENTS=0` で停止）。
- 読み上げ（`a11y`）は Elements + AccessKit 経由で UIAccessibility へ出力。
- IPA は `make ipa`（Release + `MASTER`、REPL 除外）。署名は `DEVELOPMENT_TEAM` と自動署名が前提。
- 制約: **1アプリ=1タイトル**。ランチャーで複数ゲームを扱うには、起動パスの決定とアプリ構成を
  こちらで用意する必要がある（本プロジェクトの主な追加点）。

### KiriKit

- `Engine/` を CMake で `ShioriKrkr.framework` にし、`Sources/CKiriKit`（C ABI）→ `Sources/KiriKit`
  （Swift）→ アプリ、という三層。エンジンは `Scripts/krkr2/fetch.sh` が pinned commit で取得し、
  `Scripts/krkr2/patches` を当てる。**この「pinned + パッチ」方式は OEP でも採用した。**
- 暗号化 XP3 を GARbro の公開データベースから実行時にスキーム構築して開く（`Engine/cx_decrypt.*`,
  `shiori_hx.*`）。タイトル固有鍵は同梱しない設計。
- E-mote を CatSystemKit のレンダラで自前実装している（`shiorikrkr_emote.*`）。NEKOPARA のような
  E-mote 依存タイトルには理論上の利点がある。
- ただし **Xcode 26 以降**と、Shiori 側 `Scripts/ffmpeg` でビルドした FFmpeg を要求する。
  GitHub Actions の標準 macOS ランナーで FFmpeg をフルビルドするのは時間・失敗リスクが大きい。
  また krkr2 系の core のため、対象2タイトル（krkrz 1.2.0.3 ビルド）とは系譜が異なる。

### PocketKrKr

- C++ エンジン（`cpp/core`）+ Flutter シェル。`engine_api` という C ABI を持ち、iOS では
  静的ライブラリとして Runner にリンク、ANGLE(Metal) のオフスクリーン描画を IOSurface 経由で
  Flutter テクスチャにゼロコピー表示する。
- **GPL-3.0**。OEP に組み込むと OEP 全体を GPL-3.0 で配布する必要がある。
- iOS は「主目标，开发中」。Flutter + ANGLE のビルド依存が重く、GitHub Actions での再現性も
  自前検証できない状態ではリスクが高い。

## 3. 技術選定

**採用: `krkrz_ios`（wamsoft 公式）のビルド系 + `krkrz_dev` のエンジン本体。**
その上に OEP 独自の SwiftUI ランチャーとホスト層を追加する。

理由:

1. **エンジンの系譜が一致する。** 対象2タイトルはいずれも
   `TVP(KIRIKIRI) Z core 1.2.0.3`（PE バージョンリソース / コンソールログで確認）。
   `krkrz_ios` がビルドする `wamsoft/krkrz` は同じ 1.2.0.3 系で、TJS2 2.4.28 の実装を含む。
2. **公式の iOS 対応が存在する。** CMake/Xcode 生成、SDL3、GLES DrawDevice、静的プラグイン、
   IPA 書き出しまで揃っており、SDL 側の iOS 固有処理（タッチ変換、表示リンク、ライフサイクル）を
   再発明しなくてよい。
3. **ライセンスが緩やか。** ビルド系 MIT / エンジン KiriKiri licence（BSD 系）。GPL-3.0 の
   PocketKrKr と違い、OEP の配布条件を縛らない。
4. **ビルドの再現性。** KiriKit のような FFmpeg 自前ビルドや Xcode 26 依存がなく、
   GitHub Actions の macOS ランナーで完結できる（vcpkg のバイナリキャッシュを併用）。
5. **描画方式が対象タイトルに合う。** 2D レイヤ合成が主体の KAG 系タイトルには GLES の
   DrawDevice が適切で、D3D 依存（`drawdeviceD3D`）は iOS では使わない。

採用しなかった案:

- **KiriKit**: E-mote 実装と暗号化 XP3 対応は魅力だが、Xcode 26 + FFmpeg 自前ビルドが
  CI 前提の本プロジェクトと噛み合わない。将来、E-mote タイトル対応の参考実装として参照する。
- **PocketKrKr**: GPL-3.0 と Flutter/ANGLE 依存が OEP の構成に過剰。ライセンス条件も合わない。
- **独自エンジン**: 指示書の「既存実装を最大限活用する」に反する。互換性の再実装コストが非現実的。

## 4. OEP が追加したもの（既存実装との差分）

| 追加 | 内容 |
|---|---|
| ランチャー | SwiftUI のホーム/ライブラリ/詳細/追加/設定/診断/ログ画面 |
| 起動フロー | SDL の UIKit デリゲートは維持しつつ、`main()` をホストが持ち、ランチャー→エンジンの順に制御 |
| プロジェクトパス注入 | 取り込んだゲームフォルダをエンジンに渡す（`krkrz` への最小パッチ 2 箇所） |
| ゲーム取り込み | ファイルアプリからフォルダ/`.xp3` を選び、解析→レビュー→コピー→登録 |
| 解析 | OEP core（XP3 リーダ、PE バージョン情報、`.cf`、`krkr.console.log`、プラグイン台帳） |
| 診断 | 対応状況、アーカイブ、プラグイン、ログ、メモリ、セッション情報 |
| ライフサイクル | 表示リンクをホストが駆動。バックグラウンド/復帰、終了要求を明示的に処理 |

## 5. 既知の制約（設計上の割り切り）

- **1プロセス1タイトル。** krkrz の `TVPSystemUninit` は一度きりの終了処理で、再初期化を前提と
  していない（`common/base/SysInitIntf.cpp` の `TVPSystemUninitCalled` ほか）。ゲーム終了後に
  別タイトルを遊ぶにはアプリの再起動が必要で、UI 上もそのように表示する。
- **Windows 専用プラグインは動かない。** E-mote (`emoteplayer`)、`motionplayer`、`squirrel`、
  `yuzuex`、`lzfs`、Steam 系などは krkrz_dev に iOS 実装が無い。対応状況として明示する。
- **本物のタイトルでの起動検証は行っていない。** 検証は自作の全年齢テストデータと、
  エンジンソースの読解・ビルド定義の検証まで。詳細は `status.md` を参照。
