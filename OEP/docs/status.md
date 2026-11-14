# 実装状況（検証済み / 未検証）

このファイルは **実際に何を実行して確認したか** を記録する。推測で「動く」と書かない。

凡例:
- ✅ **検証済み** — この環境で実行し、結果を確認した
- 🟡 **実装済み・未検証** — コードはあるが、コンパイル/実行を確認できていない
- ⬜ **未実装**
- ❌ **この構成では不可能 / 対象外**

---

## 1. 検証環境

| 項目 | 値 |
|---|---|
| OS | Windows（`C:\Users\chevy\Desktop\DeepAICode\OniichanErogePlayer2`） |
| コンパイラ | MSVC 19.51（Visual Studio Build Tools 18） |
| CMake | 4.x（Build Tools 同梱の `cmake`） |
| その他 | Python 3.12、Node 24、ffmpeg、git |
| **無いもの** | macOS、Xcode、Swift ツールチェーン、Docker、GitHub リモート/認証 |

そのため **iOS アプリのコンパイルと実行は、この環境では一度も行っていない。**

---

## 2. OEP core（C++ / 移植可能部分）

| 機能 | 状態 | 検証方法 |
|---|---|---|
| XP3 リーダ（マジック、連鎖インデックス、raw/zlib） | ✅ | ユニットテスト（合成アーカイブ）+ 実データ 24 アーカイブ（9 + 15） |
| XP3 セグメント読み出し（raw / zlib、複数セグメント） | ✅ | ユニットテスト + 実データのプローブ |
| 展開プロテクト属性・ハッシュ名の検出 | ✅ | ユニットテスト + NEKOPARA/魔女的夜宴 |
| 壊れたアーカイブの検出（切り詰め・非 XP3） | ✅ | ユニットテスト |
| XP3 書き出し（pack、zlib インデックス） | ✅ | ユニットテスト（pack → read → verify の往復） |
| PE バージョンリソース（RT_VERSION）解析 | ✅ | 合成 PE のユニットテスト + 実 exe 2 件 |
| `.cf` / `.cfu` 解析（`\xNN` エスケープ） | ✅ | ユニットテスト + 実ファイル 2 件 |
| `krkr.console.log`（UTF-16LE）解析 | ✅ | ユニットテスト + 実ログ 1 件 |
| プラグイン台帳（iOS 可否） | ✅ | ユニットテスト + 実フォルダ 2 件（26 / 33 DLL） |
| ゲームスキャン / 対応状況判定 | ✅ | 実フォルダ 2 件 + 自作テストデータ |
| 重複検出用の署名 | 🟡 | ロジックは Swift 側。core では未実装 |
| ログ（リングバッファ、JSON 出力） | ✅ | ユニットテスト |
| UTF-8/UTF-16 パスと引数の扱い（Windows） | ✅ | 日本語フォルダ名で実行確認 |
| ビルド | ✅ | MSVC で `oep_core.lib` / `oep-cli.exe` / `oep_tests.exe` を生成 |

ユニットテスト: **77 チェック / 0 失敗**。実データ統合テストも成功（下記）。

### 実データでのスキャン結果（実行済み）

```
NEKOPARA Vol. 1 : krkrz 1.2.0.3 (PE version resource), 9 archives, startup.tjs あり, 一部対応
魔女的夜宴      : krkrz 1.2.0.3 (console log),        15 archives (+ patch4.xp3 は PE), 一部対応
```

---

## 3. iOS アプリ（SwiftUI ランチャー）

**すべて 🟡（実装済み・未コンパイル）。** Swift コンパイラが無い環境のため、
構文・型の検証は行えていない。CI（`.github/workflows/ios.yml`）で初めて検証される。

| 画面 / 機能 | 状態 |
|---|---|
| ホーム（ブランド、Welcome、Continue Playing、統計、最近のゲーム、ADD GAME） | 🟡 |
| ライブラリ（検索、ソート、お気に入り、コンテキストメニュー、削除確認） | 🟡 |
| ゲーム詳細（エンジン、対応状況、問題点、アーカイブ、統計、PLAY、削除） | 🟡 |
| ゲーム追加（ファイル選択 → 解析 → レビュー → コピー進捗 → キャンセル → 完了） | 🟡 |
| 設定（テーマ、fps、スリープ防止、ログレベル、ストレージ、キャッシュ削除、バージョン） | 🟡 |
| 診断（エンジン、コンソールログ、プラグイン、アーカイブ、問題点、JSON 共有、メモリ） | 🟡 |
| ログ（レベル絞り込み、検索、共有、削除） | 🟡 |
| ローディング / セッション終了 / 起動失敗オーバーレイ | 🟡 |
| 永続化（`library.json`、設定の UserDefaults） | 🟡 |
| ファイル取り込み（セキュリティスコープ、重複検出、容量計算） | 🟡 |

## 4. エンジン統合

| 機能 | 状態 | 備考 |
|---|---|---|
| エンジンの静的リンク（krkrz_dev + SDL3 + プラグイン） | 🟡 | CMake 定義のみ。ビルド未検証 |
| ホストが `main()` を持ち、SDL の UIKit デリゲートを維持 | 🟡 | パッチ 0001 + `OEPHostMain.mm` |
| ランチャーからゲームフォルダを渡す（`OEPHostProjectPath`） | 🟡 | パッチ 0001 |
| 1 セッションの駆動（CADisplayLink → `SDL_AppIterate`） | 🟡 | `OEPEngineHost.mm` |
| バックグラウンド/復帰・メモリ警告・終了要求の配送 | 🟡 | 同上（SDL イベントを注入） |
| 起動失敗時にランチャーへ戻る | 🟡 | `exit()` を避ける設計 |
| 描画（GLES DrawDevice） | 🟡 | krkrz の既存実装。OEP 側の追加なし |
| 入力（タッチ→マウス、2本指 ESC） | 🟡 | krkrz の既存実装 |
| 音声（Ogg Vorbis / Opus） | 🟡 | エンジン内蔵デコーダ |
| 音量・画質のアプリ側設定 | ⬜ | エンジンへのブリッジが未実装。**UI にも出していない** |
| ゲーム終了後に別タイトルを起動 | ❌ | krkrz の初期化が一度きりのため。アプリ再起動が必要（UI に明示） |
| E-mote / motionplayer / squirrel / yuzuex 等 | ❌ | iOS 実装が krkrz_dev に無い（対応状況に表示） |

## 5. テストデータ（自作・全年齢）

| 項目 | 状態 |
|---|---|
| `startup.tjs`（Draw/Timer/入力/音声/終了） | ✅ 作成・XP3 へパック・スキャンで `supported` |
| 効果音（ffmpeg の sine で生成） | ✅ 生成確認 |
| エンジンでの描画・入力・音声の実再生 | 🟡 **未検証**（エンジンをビルド・実行できていない） |
| KAG3 を使うテストデータ | ⬜ 未作成（TJS 直叩きのみ。KAG はエンジン側の別レイヤ） |

## 6. ビルド / CI / IPA

CI で確認できたこと（GitHub Actions、公開リポジトリ）:

| ワークフロー | 結果 |
|---|---|
| `checks.yml` / core (GCC) | ✅ 成功（Linux でビルド + 77テスト + CLI スモーク） |
| `checks.yml` / Swift typecheck | ✅ 成功（iOS 16 SDK + ブリッジングヘッダで 16 ファイルを型検査） |
| `checks.yml` / ObjC++ host syntax | ✅ 成功（iOS SDK + SDL3 ヘッダで `-fsyntax-only`） |
| `ios.yml` / Configure (iOS Simulator) | ✅ 成功（vcpkg 依存・SDL3・krkrz・プラグインを構成） |
| `ios.yml` / Build (iOS Simulator) | ✅ 成功（エンジン + SwiftUI ホストをリンクし `krkrz.app` を生成） |
| `ios.yml` / Build unsigned device IPA | ✅ 成功（arm64 実機向け Release、署名なし） |
| `ios.yml` / 成果物 | ✅ `OEP-unsigned-ipa`(6.5MB) / `OEP-simulator-app`(12.5MB) / `ios-build-log` |
| `ios.yml`（取り込み修正後 7c5841d） | ✅ Simulator / 実機 IPA とも成功 |

| 項目 | 状態 |
|---|---|
| Windows での core ビルド・テスト | ✅ |
| macOS ビルドスクリプト（`OEP/engine/build-ios.sh`） | 🟡 未実行（macOS 無し） |
| パッチの適用可能性 | ✅ クリーンな clone に対して `git apply --check` で確認（下記） |
| GitHub Actions ワークフロー | 🟡 作成済み・**未実行**（リモート/認証が無い） |
| 署名つき IPA | ❌ 未生成（証明書・macOS が必要） |
| 未署名 IPA | ✅ GitHub Actions で生成・artifact に保存（再署名してインストールする必要あり） |
| Simulator での起動 | 🟡 未実施（CI はビルドのみ。起動確認には macOS/Simulator が必要） |

## 7. 検証できなかったこと（明示）

1. **iOS アプリのコンパイル**（Swift/SwiftUI/ObjC++、Xcode プロジェクト生成）
2. ~~エンジンの iOS ビルド~~ → **CI で成功**（Simulator / 実機 arm64 とも）
3. **実機/Simulator での起動・描画・入力・音声**（ビルドは成功、実行は未検証）
4. **本物のタイトル（NEKOPARA / 魔女的夜宴）の起動**。行ったのはメタデータ解析のみ
5. **IPA のインストール**（生成は CI で成功。署名がないため実機にはそのまま入らない）
6. **GitHub Actions の実行**

これらは macOS と（CI を回すなら）GitHub リポジトリへの push があれば検証できる。
`OEP/engine/build-ios.sh` と `.github/workflows/ios.yml` はそのための入口として用意してある。

## 7.5 CI で判明した上流の制約（修正済み）

| 事象 | 対応 |
|---|---|
| vcpkg を shallow clone すると krkrz の `builtin-baseline` を解決できない | vcpkg を full clone（CI） |
| CMake 4.x が古い `cmake_minimum_required` を拒否（krkrz_vorbis 等） | `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` |
| `layerExDraw` / `windowEx` / `menu` / `systemEx` / `messenger` / `fpslimit` / `binaryStream` / `varfile` / `addFont` が `<windows.h>`、`fstat` が `<tchar.h>` | iOS ビルドから除外（スキャナも未対応として報告） |
| `memfile` の `(tTJSVariant)NULL` が 64bit 非 Windows で曖昧 | パッチ 0003 で `tTJSVariant()` に |
| elements の accesskit 実装が macOS 専用（`accesskit_macos_*`） | `ios-config.json` の `"a11y": false`（krkrz 自身も iOS では既定 OFF） |
| 自前パッチ 0001 が関数内で `extern "C"` 宣言していた | ファイルスコープへ移動 |

## 7.6 実機テストで見つかった問題（修正済み）

| 症状 | 原因 | 対応 |
|---|---|---|
| フォルダピッカーで「開く」が押せない / 押しても無反応 | (1) iOS のフォルダピッカーは**フォルダ内に入ってから**「開く」で確定する仕様、(2) シート内の `fileImporter` が無効化されることがある | `UIDocumentPickerViewController` を最前面の VC から直接表示。加えて**アプリの Documents フォルダ経由**（Files アプリ > このiPhone内 > OEP）の取り込みを追加。親フォルダを選ばれてもエンジンデータのあるサブフォルダを自動解決 |
| Documents 経由の取り込みで容量が二重になる | コピー実装のみだった | Documents 由来は**移動**（同一ボリュームのリネーム）に変更 |

この修正は CI（7c5841d）で Simulator / 実機 IPA のビルド成功まで確認済み。
**実機での動作確認はユーザー側での再インストール後に未実施。**

## 7.7 起動時クラッシュへの対策（実装済み・実機確認待ち）

実機で PLAY 直後にクラッシュしたため、原因を取れるようにした。

| 対策 | 内容 |
|---|---|
| 例外の捕捉 | `SDL_AppInit` / エンジンループ / `SDL_AppQuit` を C++ の `try`/`catch(...)` と `@try`/`@catch` で包み、TJS/KAG 例外でもプロセスを落とさず `SessionFailureOverlay` に理由を出す |
| クラッシュ耐性ログ | `oep::Logger` にファイルシンクを追加し、`Documents/OEP/oep.log` へ逐次書き出し（1MB でローテーション） |
| 致命シグナル | SIGABRT/SEGV/BUS/ILL/FPE/TRAP で `[FATAL] SIGxxx` をログへ追記してから再送出、`NSException` も記録 |
| エンジンログの可視化 | 診断画面に `krkr.console.log`（UTF-16LE）の末尾を表示・共有。**起動失敗の本当の理由はここに出る** |
| ログ共有 | 設定 → ログから `oep.log` を共有 |

## 7.8 2回目の実機クラッシュ（原因判明・修正済み）

`oep.log` とエンジンログから原因が特定できた。

| 事象 | 原因 | 対応 |
|---|---|---|
| `Cannot find storage startup.tjs` → スクリプト例外 → SIGABRT | 現行 krkrz は**プロジェクトフォルダ内の `*.xp3` を自動マウントしない**（1.2.0.3 の "mount domain" 相当が無い）。プロジェクトパスをフォルダで渡すと `startup.tjs` が見つからない | パッチ 0001 に、プロジェクトフォルダの `*.xp3` を `TVPAddAutoPath("...xp3>")` で登録する処理を追加（`data.xp3` 先頭、`patch*.xp3` 最後） |
| `Data path does not exist, trying to make it ... failed.` | `user://`（SDL user storage）のディレクトリが無い環境（sideload ツールの入れ子コンテナ） | エンジン起動前に `<Application Support>/OEP/<appname>/` を作成し、結果をログに残す |

この修正は CI（`26dd60d` 以降）でビルド確認。実機確認は次回インストール後。

## 7.9 3回目の実機クラッシュ（原因判明・修正済み）

アーカイブのマウントは成功し `startup.tjs` が実行されたが、次の例外で停止した。

```
An exception occured at startup.tjs(31): hud = new Layer(this, null);
Internal Error: common/visual/DrawDevice.cpp line 240   (RemoveLayerManager)
```

`Layer(this, null)` はそのウィンドウの**プライマリレイヤ**を作る。1つの Window に
プライマリは1つだけなので、2つ目でレイヤマネージャの登録簿が壊れていた。
**テストデータ側の誤り**で、HUD を背景レイヤの子に修正（`new Layer(this, background)`）。
併せて、エンジン初期化前にランチャーウィンドウを隠すようにした（SDL のウィンドウが
key/visible になれず GLES 3.2 コンテキスト生成が失敗し 3.0 にフォールバックしていたため）。

### テストデータの同梱

`OEP/testdata/mini-vn` をアプリバンドルに含め（`ios-config.json` の `assetPack`）、
初回起動時にライブラリへ自動登録する（`BundledContent.swift`）。
効果音は ffmpeg 不要の WAV 生成（Python 標準ライブラリ）に変更した。

## 8. 意図的に実装しなかったもの

| 項目 | 理由 |
|---|---|
| カバー画像・サムネイル・背景画像 | 指示書 4.2。UI はタイポグラフィと図形のみで構成 |
| 画像の自動取得・生成 | 同上 |
| 音量スライダー | エンジンへ渡す実装が無いため。**動かない設定を並べない**方針 |
| 画質（描画品質）設定 | DrawDevice の切り替えはエンジン起動時引数/設定ファイルの領域で、OEP からは未実装 |
| 縦画面専用レイアウト | ゲームは横画面前提。ランチャーは両対応、ゲームは Info.plist の向きに従う |
| 複数タイトルの同時起動 | エンジンの制約（1 プロセス 1 初期化） |
| VoiceOver（読み上げ） | elements の accesskit ホストが macOS 専用のため iOS では無効化（krkrz の iOS 既定と同じ） |
