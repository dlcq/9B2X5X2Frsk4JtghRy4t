# OEP — OniichanErogePlayer2

iOS 向けの吉里吉里（KiriKiri Z / krkrz）ビジュアルノベルプレイヤー。
既存の公式 iOS 実装 [wamsoft/krkrz_ios](https://github.com/wamsoft/krkrz_ios) とエンジン本体
[wamsoft/krkrz_dev](https://github.com/wamsoft/krkrz_dev) を土台に、**ランチャー・ゲーム管理・診断**を
OEP として追加したもの。

> このプロジェクトはゲームデータを同梱しない。ユーザーが自分の環境から取り込んだデータのみを再生する。
> リポジトリ内の 2 つのゲームフォルダ（`NEKOPARA Vol. 1`, `魔女的夜宴`）は開発環境の既存データで、
> **読み取りのみ**（メタデータ調査）に使い、変更・移動・削除・外部送信はしていない。

## できること

- 洗練されたダークテーマの SwiftUI ランチャー（ホーム / ライブラリ / 詳細 / 追加 / 設定 / 診断 / ログ）
- ゲームフォルダの取り込み（アプリの Documents フォルダ、またはファイルアプリのピッカーから。解析 → レビュー → コピー/移動 → 登録、進捗とキャンセル）
- 取り込んだゲームの起動（krkrz エンジンをアプリ内で実行、全画面）
- 対応状況の自動判定（エンジン特定、XP3 解析、プラグイン台帳から `対応済み / 一部対応 / 未対応 / 調査中`）
- 診断（エンジン情報、コンソールログ、プラグイン、アーカイブ、JSON 共有、メモリ、FPS）
- ログの絞り込み・検索・共有・削除
- 自作・全年齢のテストデータと、それを生成/パックするツール

## 構成

```
OEP/
├── core/     移植可能な C++17（XP3 リーダ/ライタ、エンジン検出、スキャン、ログ）+ テスト + CLI
├── ios/
│   ├── App/    SwiftUI ランチャー
│   └── Host/   Objective-C++ ホスト（C ABI で Swift と接続）
├── engine/    上流の pinned 取得・パッチ・ios-config・ビルドスクリプト
├── testdata/  自作の全年齢テストゲーム（生成スクリプト付き）
└── docs/      調査・設計・ビルド・実装状況
```

## クイックスタート

### Windows（この環境で検証済み）

```powershell
# core + CLI + テスト
cmake -S OEP/core -B build/core -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/core
.\build\core\oep_tests.exe

# 自分のゲームフォルダを解析（メタデータのみ）
.\build\core\oep-cli.exe scan "C:\path\to\game"

# テストデータを作って解析
python OEP\testdata\build-testdata.py --cli .\build\core\oep-cli.exe
```

### iOS（macOS が必要）

```bash
export VCPKG_ROOT=$HOME/vcpkg
cd OEP/engine
./build-ios.sh deps && ./build-ios.sh configure && ./build-ios.sh build
```

詳細は [docs/build.md](docs/build.md)。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/investigation.md](docs/investigation.md) | 既存3実装の比較と技術選定の理由 |
| [docs/game-data.md](docs/game-data.md) | 2つのゲームフォルダの技術調査（確認できたこと/未確認） |
| [docs/architecture.md](docs/architecture.md) | 全体設計、起動シーケンス、制約 |
| [docs/build.md](docs/build.md) | Windows / macOS / GitHub Actions / 署名と IPA |
| [docs/status.md](docs/status.md) | **検証済み・未検証の一覧（最初に読むべき）** |

## 現在の検証状況（要約）

| 範囲 | 状態 |
|---|---|
| OEP core（XP3 / 検出 / スキャン / ログ） | ✅ Windows でビルド・77 テスト成功・実データ解析成功 |
| パッチの適用 | ✅ 上流の pinned コミットへ `git apply` 成功 |
| iOS アプリのコンパイル（Simulator） | ✅ GitHub Actions の macOS で成功（エンジン込み） |
| エンジンの iOS ビルド（実機 arm64） | ✅ CI で成功（未署名 IPA 6.5MB を artifact に保存） |
| 実機 / Simulator での起動動作 | 🟡 未検証（この環境では実行できない） |
| 実タイトルの起動 | 🟡 未検証（メタデータ解析のみ） |
| IPA | ✅ 未署名 IPA を CI で生成（インストールには再署名が必要） |

**未検証のものを「動く」と報告しない。** 詳細と理由は [docs/status.md](docs/status.md)。

## ライセンス

- エンジン・プラグイン: KiriKiri licence（BSD 系）。ビルド時に取得し、改変は `engine/patches/` のみ。
- krkrz_ios のビルド定義: MIT。
- SDL3: zlib。miniz: MIT。
- ゲームデータ: 各権利者。本リポジトリには含めない。
