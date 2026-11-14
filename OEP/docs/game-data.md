# ゲームデータ技術調査レポート

対象（プロジェクトルート直下、既存フォルダ。**変更・移動・削除はしていない**）:

- `NEKOPARA Vol. 1`
- `魔女的夜宴`

調査方法: ファイル/フォルダ構造、拡張子、サイズ、PE バージョンリソース、`.cf`/`.ini`、`krkr.console.log`、
XP3 インデックス（OEP core のリーダで読み取り）。**成人向け本文・画像・音声の抽出・表示・解析は行っていない。**
XP3 の内容プローブは「圧縮セグメントが展開できるか」の 1 件のみで、得られたバイト列は保存も解析もしていない。
唯一 `startup.tjs`（316 バイト、起動スタブ）だけを形式確認のために取り出し、先頭 48 バイトのヘッダを見て
削除した（下記）。

---

## 1. NEKOPARA Vol. 1

### 1.1 確認できたこと

**エンジン**: 吉里吉里Z / krkrz **1.2.0.3**

| 根拠 | 値 |
|---|---|
| PE バージョンリソース (`nekopara_vol1.exe`) | `FileDescription` = `TVP(KIRIKIRI) Z core / Scripting Platform for Win32`, `FileVersion` = `ProductVersion` = **1.2.0.3**, `InternalName` = `tvp2/win32` |
| バイナリ内文字列 | `Kirikiri Z Executable core /%1 (Compiled on %DATE% %TIME%) TJS2/%2`、PDB パス `...\krkrz_wamcustom\bin\win32\tvpwin32.pdb`（krkrz をタイトル向けにカスタムビルドしたもの） |
| 実行ファイルサイズ | 4,428,800 バイト（Win32、x86） |
| `.cf` | `nekopara_vol1.cf`: `datapath="$(appdatapath)/NekoWorks/nekopara_vol1"`, `vomstyle="layer"`（`\xNN` エスケープ） |

**構成**

```
NEKOPARA Vol. 1/
├── nekopara_vol1.exe            4,428,800
├── data.xp3                     1,191,846,359   1207 entries
├── voice.xp3                      143,844,045   4845 entries
├── evimage.xp3                    122,575,087     94 entries
├── emote.xp3                      311,876,489     88 entries
├── emotewin.xp3                 1,376,242,020     40 entries
├── emotewin_low.xp3               365,167,015     40 entries
├── adultsonly.xp3                 190,354,781   1650 entries
├── patch.xp3                        5,375,338     92 entries
├── patch2.xp3                           8,875      4 entries
├── *.xp3.sig (212 bytes × 9)       krkrz の署名ファイル
├── plugin/  26 個の DLL + .sig
├── savedata/savecheck
├── SteamEmu/ (Inventory / Saves / UGC / UserStats)
├── steam_api.dll                1,252,352
└── ds.ini                       Steam エミュレータ設定 (AppId=333600, Language=tchinese)
```

合計 **3,713,558,173 バイト（約 3.46 GiB）**。

**XP3 形式**（OEP core で全 9 アーカイブを解析）

- マジック `XP3\r\n \n\x1a\x8b\x67\x01`、インデックスオフセットは 8 バイト LE。
- インデックスは **zlib 圧縮 + 連鎖**（先頭ブロックが `0x80`（RAW + CONTINUE, サイズ 0）、本体は
  `0x01`（zlib））。krkrz の `XP3Archive.cpp` と同一のレイアウト。
- 全アーカイブのインデックス読み込みに成功し、全エントリの `info`/`segm`/`adlr` チャンクを取得できた。
- **内容は暗号化されていない**: 圧縮セグメントの展開プローブが成功した（フィルタ不要）。
- **ファイル名は保護ツールにより置換されている**: `data.xp3` は 1207 件中 **1205 件**が
  32 桁 hex の名前（例 `00205af36fa5c9c64262506aea76e018`）。展開プロテクト属性は 1206 件。
  プレーンテキストなのは警告エントリ（`$$$ This is a protected archive. $$$ …`）と `startup.tjs` のみ。
- `startup.tjs` は 316 バイトで、先頭が `TJS2100` + `DATA` チャンク。**TJS2 バイトコード**であり、
  テキストスクリプトではない。ハッシュは `魔女的夜宴` のものと完全一致（後述）。

**プラグイン（plugin/、26 DLL）**

`AlphaMovie`, `KAGParserEx`, `PackinOne`, `drawdeviceD3D`, `drawdeviceD3DZ`, `emoteplayer`,
`extNagano`, `extrans`, `getLangName`, `getSample`, `k2compat`, `kagexopt`, `krkrsteam`, `krmovie`,
`kztouch`, `layerExDraw`, `menu`, `multiimage`, `psbfile`, `squirrel`, `textrender`, `varfile`,
`win32dialog`, `windowEx`, `wuopus`, `wuvorbis`

注目点: `emoteplayer`（E-mote キャラクタ）、`squirrel`（Squirrel スクリプト VM）、`drawdeviceD3D`
（Direct3D）、`kztouch`（Windows タッチ）は **Windows 専用**。`krmovie` は krkrz 1.2.0.3 では
DLL だが、krkrz_dev では core の movie-player として実装されている。

### 1.2 未確認のこと

- 実際の起動・描画（Windows 実行ファイルは実行していない。エンジンを持ち込んでの検証も未実施）。
- `patch.xp3` / `patch2.xp3` の内容（インデックスのみ取得）。
- `squirrel` / `emoteplayer` がタイトル Scripts から実際に呼ばれているか（バイトコードの解析はしていない）。

---

## 2. 魔女的夜宴

### 2.1 確認できたこと

**エンジン**: 吉里吉里Z / krkrz **1.2.0.3**（コンソールログ + PE）

| 根拠 | 値 |
|---|---|
| `savedata/krkr.console.log` (UTF-16LE) | `Kiriki Z Executable core /1.2.0.3 (Compiled on Oct 28 2021 16:12:21) TJS2/2.4.28`、`Engine : Revision 1947, Last Changed 2023/07/21 12:07:28`、`Kirikiri : 1.2.0.3`、`OS : Windows 8 6.2.1008 (Win32)` |
| PE バージョンリソース | `FileDescription` = `Sabbat of the Witch`, `FileVersion` = `1.2.0.3`, `Comments` = `Yuzusoft/HIKARIFIELD`, `ProductName` = `TVP(KIRIKIRI) Z core …` |
| `.cf` | `SabbatOfTheWitch.cf`: `datapath="$(appdatapath)/Yuzusoft_HIKARIFIELD/SabbatOfTheWitch"`, `vomstyle="layer"`, `wheel="message"` |
| ログのマウント | `data.xp3`, `video.xp3`, `bgm.xp3`, `fgimage.xp3`, `bgimage.xp3`, `scn.xp3`, `voice.xp3`, `evimage.xp3`, `steam.xp3`, `adult.xp3`, `adult_evimage.xp3`, `adult_video1..3.xp3`（フォルダ内 xp3 を自動マウント） |
| ログの TJS 読込 | `saveload.tjs`, `UILoader.tjs`, `embFontLoader.tjs`（KAG 系の TJS 群） |

**構成**

```
魔女的夜宴/
├── SabbatOfTheWitch.exe         4,461,056   (PE, 1.2.0.3)
├── SabbatOfTheWitch_crack.exe   4,470,784
├── data.xp3                       777,967,962   4088 entries
├── voice.xp3                      795,965,985  28989 entries
├── bgimage.xp3                    403,640,415    109 entries
├── fgimage.xp3                    268,990,826   1555 entries
├── evimage.xp3                    454,277,500    320 entries
├── bgm.xp3                        166,249,636     94 entries
├── scn.xp3                          2,256,912     27 entries
├── video.xp3                      272,334,242     13 entries
├── adult.xp3                      751,321,645  12722 entries
├── adult_evimage.xp3            1,073,363,913     83 entries
├── adult_video1.xp3               544,595,935      7 entries
├── adult_video2.xp3             1,003,859,363      6 entries
├── adult_video3.xp3             1,006,137,838      6 entries
├── allage.xp3                      44,194,632     92 entries
├── steam.xp3                           19,704      4 entries
├── patch4.xp3                         130,560   ← XP3 ではない (MZ = PE)
├── plugin/  33 個の DLL + .sig
├── savedata/ (セーブ画像, data_anchor.ksd, datasu.ksd, krkr.console.log …)
├── 原版备份/ (SabbatOfTheWitch.exe 4,631,256, steam.xp3, steam_api.dll)
└── 全CG存档/ (datasu.ksd, 説明 txt)
```

合計 **7,574,513,165 バイト（約 7.05 GiB）**（16 の実 XP3 + PE 1 個）。

**XP3 形式**

- すべて標準 XP3（マジック、zlib 連鎖インデックス）。15 個の実アーカイブが読み込み成功。
- **`patch4.xp3` は XP3 ではない**: 先頭が `MZ` の PE（130,560 バイト）。拡張子だけが `.xp3`。
  OEP は「XP3 ではない」と判定して無視する（`misnamed_xp3`）。
- **ファイル名は保護ツールにより置換**: `data.xp3` の 4088 件中 4087 件が展開プロテクト属性で、
  名前は `倀` (U+5000) から始まる **連番の 1 文字**（`倀`, `倁`, `倂`, …）。NEKOPARA の hex 名と
  同様、名前だけが置換され、内容は暗号化されていない（圧縮セグメントの展開プローブ成功）。
- `startup.tjs` は **316 バイトの TJS2 バイトコード**（`TJS2100`）。**NEKOPARA のものと SHA-256 が一致**。
  両タイトルで同一の起動スタブが使われている（共通のパッケージ/保護ツール由来と推測。断定はしない）。

**プラグイン（plugin/、33 DLL）**

`AlphaMovie`, `KAGParserEx`, `PackinOne`, `SteamDrawDevice`, `drawdeviceD3D`, `drawdeviceD3DZ`,
`extNagano`, `extrans`, `getLangName`, `getSample`, `httprequest`, `json`, `k2compat`, `kagexopt`,
`krkrsteam`, `krmovie`, `layerExDraw`, `layerExSave`, `lzfs`, `menu`, `motionplayer`,
`motionplayer_nod3d`, `msdfrender`, `psbfile`, `psd`, `textrender`, `wfTypicalDSP`, `win32dialog`,
`win32ole`, `windowEx`, `wuopus`, `wuvorbis`, `yuzuex`

注目点: `motionplayer`（D3D モーション）、`yuzuex`（Yuzusoft 拡張）、`lzfs`、`msdfrender`、
`wfTypicalDSP`、`SteamDrawDevice` は iOS 版 krkrz_dev に存在しない。`psd` は krkrz_dev の
`psdfile` プラグインで代替可能。`json` は krkrz_dev にある。

### 2.2 未確認のこと

- 実際の起動・描画（未実施）。
- `yuzuex.dll` / `motionplayer.dll` が無い場合のタイトル側の挙動（スクリプトのフォールバック有無）。
- `patch4.xp3`（PE）の役割（実行ファイルの一種であること以外は未解析）。

---

## 3. 2フォルダの比較と OEP の対応判定

| 項目 | NEKOPARA Vol. 1 | 魔女的夜宴 |
|---|---|---|
| エンジン | krkrz 1.2.0.3 (Win32) | krkrz 1.2.0.3 (Win32) |
| TJS2 | 1.2.0.3 同梱（バージョン文字列は 2.4.1 系の警告文） | 2.4.28（ログ） |
| XP3 | 9 / 全て解析可・内容可読 | 15 / 解析可・内容可読（+ PE 1） |
| 名前保護 | hex ハッシュ名 | 連番文字名 |
| 起動スタブ | 316 B TJS2 バイトコード | 同左（同一ハッシュ） |
| iOS で不足するプラグイン | `emoteplayer`, `squirrel`, `psbfile`, `kztouch`, `win32dialog`, `krkrsteam`, D3D 系 | `motionplayer`, `yuzuex`, `lzfs`, `msdfrender`, `wfTypicalDSP`, `psbfile`, `win32dialog`, `win32ole`, Steam 系 |
| OEP の判定 | **一部対応**（起動系は揃うが E-mote/Squirrel が無い） | **一部対応**（motionplayer/yuzuex が無い） |

判定は OEP core の `scanGame()` が機械的に出したもので、`OEP/docs/status.md` と UI の
「対応状況」に同じコード（`plugin_missing:*` など）として現れる。
**「対応済み」とは表示していない。**

## 4. データの取り扱い

- 両フォルダに対して行ったのは **読み取りのみ**（ファイル一覧、サイズ、インデックス解析、
  バージョンリソース、設定ファイル、ログの解析）。
- 抽出したのは `startup.tjs`（316 バイト）1 件のみで、形式（TJS2 バイトコード）を確認したあと削除した。
  本文・画像・音声の抽出・表示・解析・再生は行っていない。
- 外部サービスへのアップロードは行っていない。OEP のリポジトリにもこれらのデータは含めていない。
