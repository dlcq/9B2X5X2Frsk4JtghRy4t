# OEP アーキテクチャ

## 1. 全体像

```
┌──────────────────────────────────────────────────────────────┐
│ OEP.app                                                      │
│                                                              │
│  SwiftUI ランチャー (Swift)                                  │
│   Home / Library / Detail / AddGame / Settings / Diagnostics  │
│        │                                                     │
│        │ C ABI (OEPHost.h)                                   │
│        ▼                                                     │
│  ホスト層 (Objective-C++)                                    │
│   OEPHostMain.mm     main() + SDL_RunApp への中継            │
│   OEPEngineHost.mm   1セッションの駆動・ライフサイクル       │
│   OEPCoreBridge.mm   OEP core の C ラッパ                    │
│        │                        │                            │
│        │ SDL_AppInit/Iterate/   │ oep_core (C++17)           │
│        │ Event/Quit             │  xp3 / detect / scan / log  │
│        ▼                        ▼                            │
│  KiriKiri Z (krkrz_dev, 静的リンク)  +  SDL3 + プラグイン     │
└──────────────────────────────────────────────────────────────┘
```

- **1 つの実行ファイル**にエンジン・SDL3・プラグイン・Swift ランチャーをすべて静的リンクする。
  iOS は `dlopen` できないため、プラグインはすべて静的（krkrz_ios と同じ方針）。
- エンジンと Swift の境界は **プレーン C**（`OEP/ios/Host/OEPHost.h`）だけ。Swift は
  `@_cdecl("OEPHostRunLauncher")` でホストから呼ばれ、エンジン起動は C 関数を呼ぶ。
  Swift の生成ヘッダ（`-Swift.h`）に依存しないので、CMake 生成の Xcode プロジェクトでも壊れにくい。

## 2. 起動シーケンス

```
UIApplicationMain (SDL が用意する UIKit デリゲート)
  └─ scene 接続 → postFinishLaunch
       └─ SDL_RunApp(..., OEPHostMain)
            └─ OEPHostMain → OEPHostRunLauncher()   [Swift]
                 ├─ ランチャー UIWindow を作成（windowLevel = normal+1）
                 └─ return 0   ← ここで main は終わるが、Cocoa の RunLoop は生き続ける

（ユーザー操作）
  PLAY → SessionController
       ├─ OEPHostEngineSetPreferredFPS
       ├─ OEPHostSetSessionGameID / library に最終プレイを記録
       ├─ エンジンへ `-orgname=OEP -appname=<gameID>` を渡す（user:// をゲームごとに分離）
       ├─ 0.25 秒後に OEPHostEngineStart(projectPath)   ※ローディング画面を描かせる
       │    ├─ OEPHostProjectPath() にパスを設定
       │    ├─ SDL_AppInit()            … krkrz の初期化（プロジェクト読込・ウィンドウ生成）
       │    ├─ CADisplayLink を mainRunLoop に登録
       │    └─ OEPEngineEventRunning を通知 → ランチャーウィンドウを隠す
       │
       └─ 終了（ゲーム側の終了 / ESC / SDL_EVENT_QUIT）
            ├─ SDL_AppQuit()             … TVPSystemUninit / 音声・ストレージ終了
            ├─ OEPEngineEventEnded を通知
            ├─ プレイ時間を保存
            └─ ランチャーウィンドウを再表示
```

### なぜ main をホストが持つのか

krkrz の iOS 実装は SDL の `SDL_MAIN_USE_CALLBACKS` を使い、`SDL_EnterAppMainCallbacks()` が
CADisplayLink を張ったあと **`exit()` でプロセスを終了する**（`src/main/ios/SDL_sysmain_callbacks.m`）。
そのままでは「ランチャー → ゲーム」の順序を作れず、起動失敗もアプリ終了になる。

OEP は `SDL_MAIN_HANDLED` でエンジン側の `main()` 生成を止め（パッチ 0001）、ホストが
`SDL_AppInit / SDL_AppIterate / SDL_AppEvent / SDL_AppQuit` を直接呼ぶ。これにより:

- 起動失敗時にランチャーへ戻れる（プロセスを殺さない）
- 背景/復帰・メモリ警告をホストから SDL イベントとして注入できる
- プレイ時間を毎秒ホストが把握できる

## 3. プロジェクトパスの決定（エンジン側パッチ）

`krkrz` の `MySDL3Application::InitPath()`（`sdl3/environ/stdapp.cpp`）は `argv[1]` →
バンドル内 `data.xp3` → exe 結合 XP3 → `data/startup.tjs` の順でプロジェクトを探し、iOS では
見つからないと失敗する。OEP は同関数の先頭で **`OEPHostProjectPath()`（weak ではない通常の C 関数）**
を参照し、返ってきたフォルダを最優先で使う。パッチは `#if defined(OEP_HOST_APP)` で囲んであるので、
OEP 以外のビルド（krkrz_ios 標準）には一切影響しない。

## 4. データ配置

iOS の krkrz は `user://` を `SDL_OpenUserStorage(orgname, appname)` に割り当てる
（`src/core/sdl3/base/storage.cpp`）。OEP は起動時に `-orgname=OEP -appname=<ゲームID>` を
エンジンへ渡すので、セーブデータとエンジンログは **ゲームごとのフォルダ** に分かれる。

```
<Application Support>/OEP/
├── library.json                 ゲーム一覧（Codable）
└── Games/<title>-<uuid8>/        インポートしたゲーム（フォルダごとコピー）
     ├── data.xp3
     ├── ...
     └── savedata/               エンジンが書くセーブデータ（user://）
```

- 取り込み元は **読み取りのみ**。コピー後に元フォルダへは触れない。
- ゲームの同一性は「`.xp3` のファイル名 + サイズ + `startup.tjs`」から作る署名で判定する
  （内容は読まない）。重複時は登録を止めて既存タイトルを知らせる。
- 削除は「ライブラリからのみ」と「データごと」を選べる。

## 5. 対応状況の判定

`oep::scanGame()` がフォルダを走査し、次の事実から `supported / partial / unsupported / unknown`
を機械的に決める。UI と診断画面はこの結果と `issues[]` をそのまま表示する（推測で「対応済み」に
しない）。

判定材料:

| 材料 | 取得方法 |
|---|---|
| エンジン種別・バージョン | `krkr.console.log`（UTF-16LE）、PE RT_VERSION、`.cf` |
| 起動スクリプト | XP3 インデックス内の `startup.tjs` / `data/startup.tjs` |
| アーカイブ | XP3 インデックス（連鎖 + zlib）、保護属性、名前置換の検出、内容プローブ 1 件 |
| プラグイン | `plugin/*.dll` の一覧と、krkrz_dev の iOS ビルド可否に基づく台帳 |
| 構成 | `data.xp3` / `data/` / `savedata/` の有無、合計サイズ |

## 6. 1 プロセス 1 タイトルという制約

`TVPSystemUninit()` は `TVPSystemUninitCalled` で一度きりに制限されており、krkrz は
「起動 → 終了」を 1 回しか想定していない。したがって OEP も **1 セッション/プロセス**とし、
セッション終了後はランチャーに戻るが、別タイトルの起動はアプリ再起動を要求する。
この制約は UI（セッション終了オーバーレイ、ホームの PLAY 無効理由）に明示している。

## 7. モジュール分割の方針

- `OEP/core`: 画面もエンジンも知らない portable C++。Windows でビルド・テストでき、iOS にも
  そのまま入る。**ロジックの検証はここで行う。**
- `OEP/ios/Host`: iOS とエンジンに依存する薄い層。C ABI のみ公開。
- `OEP/ios/App`: SwiftUI。状態（LibraryStore / SettingsStore / SessionController / ImportService）と
  画面。エンジンの内部には触れない。
- `OEP/engine`: 上流の pinned 取得・パッチ・CMake 注入・ビルドスクリプト。アプリのソースは持たない。

## 8. エラー処理の流れ

| 事象 | 挙動 |
|---|---|
| インポート元に `data.xp3` が無い | レビュー画面に「未対応」理由を出し、コピーさせない（続行は可能だが警告） |
| コピー中の容量不足/失敗 | 部分的に作ったコピー先を削除し、エラーを表示 |
| エンジン初期化失敗 | `OEPEngineEventFailed` → ランチャーに留まり、失敗理由と診断への導線を表示 |
| ゲーム中の強制終了要求 | `SDL_EVENT_QUIT` を注入 → エンジン本来の終了処理を通す |
| バックグラウンド | 表示リンクを停止し、`WILL_ENTER_BACKGROUND` をエンジンへ配送 |
| クラッシュ | 保存済み `library.json` とプレイ時間（前回起動時点）から復帰可能 |

## 9. ライセンス境界

- OEP のコード（Swift / Host / core）: 本プロジェクト内。
- エンジン・プラグイン: KiriKiri licence（BSD 系）。ビルド時に取得し、改変は `patches/*.patch` のみ。
- SDL3: zlib。miniz: MIT。vcpkg 依存は各ライブラリのライセンス。
- ゲームデータ: 同梱しない。ユーザーが自身の環境から取り込む。
