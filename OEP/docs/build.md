# ビルドと実行

開発環境は Windows。iOS の最終ビルドだけが macOS を必要とするため、ローカル（Mac）と
GitHub Actions の両方の手順を用意している。

| 対象 | 環境 | コマンド |
|---|---|---|
| OEP core（C++） | Windows / macOS / Linux | `cmake -S OEP/core -B build/core && cmake --build build/core` |
| core テスト | 同上 | `build/core/oep_tests[.exe]` |
| CLI | 同上 | `build/core/oep-cli[.exe] ...` |
| テストデータ | どこでも（ffmpeg は任意） | `python3 OEP/testdata/build-testdata.py --cli <oep-cli>` |
| iOS アプリ | **macOS + Xcode** | `OEP/engine/build-ios.sh build` |
| iOS 実機 / IPA | macOS + 署名 | `OEP/engine/build-ios.sh build-device` / `ipa` / `ipa-unsigned` |
| CI | GitHub Actions | `.github/workflows/ios.yml` |

---

## 1. Windows でできること（実際に検証済み）

### 1.1 core のビルドとテスト

```powershell
# Visual Studio Build Tools の開発者コマンドプロンプト、または vcvars64.bat を読み込んだ環境で
cmake -S OEP/core -B build/core -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/core
.\build\core\oep_tests.exe
```

`oep_tests.exe` は 77 チェックのユニットテスト（XP3 の読み書き、連鎖インデックス、zlib セグメント、
保護属性、ハッシュ名、切り詰め検出、PE バージョンリソース、`.cf` の `\xNN` 展開、
`krkr.console.log`（UTF-16LE）の解析、プラグイン台帳、JSON、ログ）を実行する。

実データを渡すとメタデータの統合テストも走る:

```powershell
.\build\core\oep_tests.exe "C:\Users\chevy\Desktop\DeepAICode\OniichanErogePlayer2\NEKOPARA Vol. 1" `
                           "C:\Users\chevy\Desktop\DeepAICode\OniichanErogePlayer2\魔女的夜宴"
```

### 1.2 CLI

```
oep-cli scan <folder> [--json] [--no-probe]      # 対応状況つきスキャン
oep-cli report <rootFolder> [--json]             # フォルダ配下を一括スキャン
oep-cli detect <folder>                          # エンジン特定のみ
oep-cli xp3 list <archive.xp3> [--limit N]
oep-cli xp3 verify <archive.xp3>
oep-cli xp3 extract <archive.xp3> <name> <outFile>
oep-cli xp3 pack <folder> <out.xp3> [--no-compress-index]
```

- 画面出力は UTF-8（Windows ではコンソール出力コードページを UTF-8 に設定）。
- 日本語パスは `GetCommandLineW` から UTF-16 で受け取り、内部は UTF-8 で扱う。
- `xp3 verify` は全エントリを読み出してサイズ一致を確認する（内容の解釈はしない）。

### 1.3 テストデータ

```powershell
python OEP\testdata\build-testdata.py --cli OEP\core\build\oep-cli.exe
```

- `OEP/testdata/mini-vn/data/startup.tjs` … 自作・全年齢の TJS2 スクリプト
  （Window/Layer 描画、Timer アニメーション、タッチ/キー入力、効果音、ESC で終了）
- `se.ogg` … ffmpeg の `sine` で生成（第三者の音源は使わない）
- `data.xp3` … 上記を `oep-cli xp3 pack` でアーカイブしたもの

生成物（`se.ogg`, `data.xp3`）はリポジトリに含めず、必要時に生成する。

### 1.4 Windows でできないこと

- Swift / SwiftUI のコンパイル（Apple SDK が必要）
- iOS アプリのリンク・実行
- krkrz の iOS ビルド

---

## 2. macOS での iOS ビルド

### 2.1 前提

| 必要なもの | 備考 |
|---|---|
| macOS + Xcode 15 以降（Command Line Tools 含む） | iOS SDK が必要。`xcodebuild -downloadPlatform iOS` も可 |
| CMake 3.24 以降 | `brew install cmake` |
| Python 3 | 設定生成スクリプト用 |
| [vcpkg](https://github.com/microsoft/vcpkg) | `VCPKG_ROOT` を設定 |
| ネットワーク | 初回は krkrz_dev（サブモジュール含む）・krkrz_ios・SDL3・vcpkg 依存を取得 |

### 2.2 手順

```bash
export VCPKG_ROOT=$HOME/vcpkg
cd OniichanErogePlayer2/OEP/engine

./build-ios.sh deps        # pinned 取得 + パッチ適用
./build-ios.sh configure   # gen-config.py + CMake (Xcode)
./build-ios.sh build       # Simulator 用ビルド

# Simulator へインストールして起動
xcrun simctl boot "iPhone 15" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted .work/build-simulator/krkrz/Debug-iphonesimulator/krkrz.app
xcrun simctl launch --console-pty booted dev.oep.oniichanerogeplayer
```

実機:

```bash
export DEVELOPMENT_TEAM=XXXXXXXXXX   # Apple Developer の Team ID
./build-ios.sh build-device          # 署名つき（自動署名）
```

### 2.3 取得するもの（pins.json）

| リポジトリ | 用途 |
|---|---|
| `wamsoft/krkrz_dev` @ pinned | エンジン本体 + プラグイン（サブモジュール） |
| `wamsoft/krkrz`（`src/core`） @ pinned | エンジン core。**パッチ 0001** を適用 |
| `wamsoft/krkrz_ios` @ pinned | iOS ビルド定義。**パッチ 0002** を適用 |
| SDL3 `release-3.4.4` | krkrz_ios の CMake が FetchContent で取得 |

パッチは 3 つだけ:

1. `0001-krkrz-core-oep-host.patch`
   - `sdl3/environ/main.cpp`: `OEP_HOST_APP` のとき `SDL_MAIN_HANDLED`（ホストが `main()` を持つ）
   - `sdl3/environ/stdapp.cpp`: `OEPHostProjectPath()` があればそれをプロジェクトフォルダにする
2. `0002-krkrz-ios-oep-app.patch`
   - `CMakeLists.txt`: `-DOEP_APP_DIR` 指定時に Swift を有効化し、`OEP/ios` を `add_subdirectory`
3. `0003-memfile-variant-null.patch`
   - `src/plugins/memfile`（サブモジュール）: `(tTJSVariant)NULL` が 64bit 非 Windows で
     曖昧になるため `tTJSVariant()` に置換（上流の移植性バグ）

### 2.4 プラグイン構成

`OEP/engine/ios-config.json` の `cmake.plugins`。既定は:

```
json KAGParserEx extrans AlphaMovie scriptsEx csvParser lineparser
memfile shrinkCopy virtualpad iosconfig
```

- krkrz_dev のプラグインのうち `layerExDraw` / `windowEx` / `menu` / `systemEx` /
  `messenger` / `fpslimit` / `binaryStream` / `varfile` / `addFont`（`<windows.h>`）と
  `fstat`（`<tchar.h>`）は **Win32 専用**なので iOS ビルドには入れていない（CI で実際に
  `layerExDraw/LayerExDraw.hpp:4: 'windows.h' file not found` を確認して除外した）。
  OEP のスキャナもこれらを「未対応」として報告する。

- iOS 専用の `virtualpad` / `iosconfig` は `krkrz_ios/plugins` から取る。
- タイトル固有プラグイン（`yuzuex`, `motionplayer`, `emoteplayer`, `squirrel` など）は
  krkrz_dev に iOS 実装が無いため含めない。含めたい場合は krkrz_dev 側に実装を追加するしかない。
- ビルドが通らないプラグインがあれば、この配列から外す（エンジン本体の機能は減るがビルドは通る）。

### 2.5 ビルドが失敗しやすい箇所

| 症状 | 対処 |
|---|---|
| `vcpkg` の iOS トリプレットが見つからない | `VCPKG_ROOT` と `triplets/`（krkrz_ios 同梱）を確認。krkrz_ios の `Makefile` と同じ `-DVCPKG_TARGET_TRIPLET` を使う |
| Swift のブリッジングヘッダが見つからない | `OEP/ios/Host/OEPHost-Bridging-Header.h` の絶対パスが `SWIFT_OBJC_BRIDGING_HEADER` に設定されているか確認 |
| `SDL_RunApp` の多重定義 | `OEP_HOST_APP` がエンジン側にも定義されているか（`OEP/ios/CMakeLists.txt` の `target_compile_definitions`） |
| プラグインのコンパイルエラー | `ios-config.json` の `cmake.plugins` から外す |
| `krkrz.app` の署名エラー | `DEVELOPMENT_TEAM` 未設定、または Keychain のロック。`security set-key-partition-list` が必要な場合あり |
| `CMake Error ... cmake_minimum_required: Compatibility with CMake < 3.5 has been removed` | CMake 4.x で古い依存を構成したときに出る。`build-ios.sh` は `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` を渡して回避している |
| `vcpkg ... failed to git show versions/baseline.json` | vcpkg を shallow clone すると krkrz の `builtin-baseline` を解決できない。full clone する（CI はそうしている） |

---

## 3. GitHub Actions

`.github/workflows/ios.yml`:

| ジョブ | 内容 |
|---|---|
| `core` | Ubuntu で OEP core をビルドし、ユニットテストと CLI スモークテストを実行 |
| `ios` | macOS ランナーで vcpkg を準備 → `build-ios.sh deps/configure/build` → Simulator 用 `.app` を成果物に。PR 以外では **未署名 IPA** も生成 |

- vcpkg のバイナリキャッシュを `actions/cache` で保持する（初回は 20〜40 分程度かかる）。
- 署名つき IPA を作る場合は、リポジトリの Secrets に証明書とプロファイルを置き、
  `xcodebuild -exportArchive` に渡す手順を追加する（`build-ios.sh ipa` がその入口）。

```bash
# 署名つき（Mac、または証明書を入れた CI）
export DEVELOPMENT_TEAM=XXXXXXXXXX
./build-ios.sh ipa
```

---

## 4. 署名と IPA（無料でできること / できないこと）

| 方法 | できること | 制約 |
|---|---|---|
| **未署名 IPA**（`ipa-unsigned`） | ビルド成果物としての `.ipa`（`Payload/OEP.app`） | **そのままではインストール不可**。Sideloadly / AltStore / Xcode などで自分の証明書で再署名が必要 |
| **Personal Team（無料 Apple ID）** | 実機にインストールして実行 | 7 日で失効、同時に署名できるアプリ数・端末数に制限、Game Center 等の一部 entitlement 不可 |
| **有料 Apple Developer Program** | Ad Hoc / App Store 配布、年間署名 | 年間費用が必要 |

「無料で誰でもインストールできる署名済み IPA」を配布することはできない（Apple の署名検証があるため）。
本プロジェクトの CI は **未署名 IPA の生成まで**を自動化し、署名は利用者の環境に委ねる。
この点を「できていないこと」として `status.md` に明記している。

---

## 5. 開発時のヒント

- `OEP/core` は C++17 のみ。Apple 固有 API を使っていないので、Windows でロジックを直してから
  CI に投げるとサイクルが速い。
- アプリのログは `oep::Logger`（`OEPHostLogExport`）に集約される。クラッシュ時も
  `library.json` はアトミック書き込みなので壊れにくい。
- ゲームのセーブデータは `<Application Support>/OEP/Games/<game>/savedata/` にできる
  （krkrz の `user://`）。バックアップはこのフォルダごとコピーすればよい。
