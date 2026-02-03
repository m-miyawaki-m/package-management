# 開発環境パッケージインストーラー 要件定義書

## 概要

共有ディレクトリから開発ツールを取得し、ローカル環境にインストールするPowerShell 5ベースのスクリプトシステム。

## 対象ツール一覧

| ツール名 | インストール方式 | 備考 |
|----------|------------------|------|
| 7zip | installer | 必須（失敗時は即停止） |
| TeraTerm | installer | |
| Git | installer | |
| TortoiseGit | installer | |
| TortoiseGitプラグイン | installer | |
| Chrome | installer | |
| ModHeader（Chromeプラグイン） | copy | ファイル配置のみ |
| A5:SQL Mk-2 | extract | ポータブル版、設定込み7z配布 |
| SQL Developer | extract + configCopy | 本体extract後、接続設定ファイルをコピー |
| WinMerge | installer | |
| Sakura Editor | installer | |
| Eclipse | extract | 設定済み7z配布 |
| WebLogic | extract | 設定済み7z配布 |
| Eclipse workspace | extract | 設定済み7z配布 |
| JDK | extract | 環境変数設定は別スクリプト |

## ディレクトリ構成

### スクリプト配置
```
package-management/
├── Install.bat                    # エントリポイント（権限確認・メニュー表示）
├── config/
│   └── tools.json                 # ツール定義・設定ファイル
└── scripts/
    ├── Main.ps1                   # 統括スクリプト
    ├── Clone-Repositories.ps1    # Gitクローン（単独実行可）
    ├── Set-JavaEnv.ps1           # JDK環境変数設定（単独実行可）
    └── modules/
        ├── Logger.psm1            # ログ出力・進行度表示
        ├── FileManager.psm1       # ファイル取得・ハッシュ比較・バックアップ
        ├── Extractor.psm1         # 解凍処理
        ├── Installer.psm1         # exe/msi実行・レジストリ確認
        ├── ConfigCopier.psm1      # 設定ファイルコピー
        └── FileCopier.psm1        # ファイルコピー
```

### ログ出力先（logRootで指定）
```
C:\dev-tools\logs\                 # defaults.logRoot
├── install-yyyyMMdd-HHmmss.log    # 詳細ログ
└── summary-yyyyMMdd-HHmmss.txt    # サマリーテーブル
```

## 設定ファイル仕様（tools.json）

```json
{
  "defaults": {
    "sourceRoot": "\\\\server\\share\\packages",
    "localRoot": "C:\\packages",
    "destRoot": "C:\\dev-tools",
    "backupRoot": "C:\\packages\\bk",
    "logRoot": "C:\\dev-tools\\logs",
    "7zPath": "C:\\dev-tools\\7zip\\7z.exe",
    "successCodes": [0, 3010]
  },
  "tools": [
    {
      "name": "7zip",
      "type": "installer",
      "source": "7zip",
      "version": "23.01",
      "displayName": "7-Zip",
      "silentArgs": "/S /D=C:\\dev-tools\\7zip",
      "required": true
    },
    {
      "name": "git",
      "type": "installer",
      "source": "git",
      "version": "2.43.0",
      "displayName": "Git",
      "silentArgs": "/VERYSILENT /NORESTART"
    },
    {
      "name": "tortoisegit-plugin",
      "type": "installer",
      "source": "tortoisegit-plugin",
      "silentArgs": "/S",
      "skipVersionCheck": true
    },
    {
      "name": "jdk",
      "type": "extract",
      "source": "jdk",
      "destination": "C:\\dev-tools\\jdk\\17"
    },
    {
      "name": "eclipse",
      "type": "extract",
      "source": "eclipse",
      "destination": "C:\\dev-tools\\eclipse"
    },
    {
      "name": "a5m2",
      "type": "extract",
      "source": "a5m2",
      "destination": "C:\\dev-tools\\a5m2"
    },
    {
      "name": "sqldeveloper",
      "type": "extract",
      "source": "sqldeveloper",
      "destination": "C:\\dev-tools\\sqldeveloper",
      "configCopy": {
        "source": "connections.xml",
        "destination": "%APPDATA%\\SQL Developer\\system\\connections.xml"
      }
    },
    {
      "name": "modheader",
      "type": "copy",
      "source": "chrome-plugins",
      "destination": "C:\\dev-tools\\chrome-plugins\\modheader"
    }
  ],
  "repositories": [
    {
      "name": "project-main",
      "url": "https://github.com/org/project.git",
      "destination": "C:\\workspace\\project"
    }
  ]
}
```

### 設定項目説明

#### defaults
| キー | 説明 |
|------|------|
| sourceRoot | 共有ディレクトリのルートパス |
| localRoot | ローカルにダウンロードしたファイルの保存先ルート |
| destRoot | インストール先（解凍先）のデフォルトルート |
| backupRoot | バックアップ保存先のルート |
| logRoot | ログファイル出力先のルート |
| 7zPath | 7-Zip実行ファイルのパス |
| successCodes | インストーラー成功とみなす終了コードのリスト（デフォルト: [0, 3010]） |

#### tools配列
| キー | 必須 | 説明 |
|------|------|------|
| name | ○ | ツール名（識別子） |
| type | ○ | インストール方式: `installer` / `extract` / `copy` |
| source | ○ | 共有ルートからの相対パス（フォルダ名） |
| destination | △ | インストール先（extractとcopyは必須） |
| version | △ | バージョン（installerタイプで必須、レジストリ比較用） |
| displayName | △ | レジストリ表示名（installerタイプで必須、アンインストール情報検索用） |
| silentArgs | - | インストーラーのサイレント引数 |
| required | - | true: 失敗時に即停止（7zip用） |
| skipVersionCheck | - | true: バージョン確認をスキップ（プラグイン用） |
| successCodes | - | 成功とみなす終了コードのリスト（defaultsを上書き） |
| configCopy | - | 設定ファイルコピー設定 |
| configCopy.source | - | コピー元ファイル名（共有フォルダ内） |
| configCopy.destination | - | コピー先パス（環境変数使用可） |

#### repositories配列
| キー | 説明 |
|------|------|
| name | リポジトリ名 |
| url | GitリポジトリURL |
| destination | クローン先ディレクトリ |

### Gitアクセストークン

Gitクローンを含む処理を選択した場合、メニュー選択直後にアクセストークンの入力を求める。

```
Gitアクセストークンを入力してください: ********
```

- **入力タイミング**: メニューで選択1または3を選んだ直後
- **保持方法**: PowerShell変数（SecureString）としてメモリに保持
- **有効期間**: スクリプト終了まで（プロセス終了で自動消去）
- **使用方法**: クローン時にURLに埋め込み `https://{token}@github.com/org/repo.git`

## 共有ディレクトリ構成

ツールごとにフラットなフォルダ構成。

- 基本: 1フォルダに1ファイル（アーカイブまたはインストーラー）
- configCopyがある場合: 本体 + 設定ファイルの2ファイル
- **複数ファイル検出時**: 該当ツールをFAILEDとしてスキップ（configCopyファイル除く）

```
\\server\share\packages\
├── 7zip\
│   └── 7z2301-x64.exe
├── jdk\
│   └── jdk-17.0.8.7z
├── eclipse\
│   └── eclipse-configured.7z
├── git\
│   └── Git-2.43.0-64-bit.exe
├── a5m2\
│   └── a5m2-2.17.7z              # 設定込み（Portableフォルダ含む）
├── sqldeveloper\
│   ├── sqldeveloper-20.x.7z      # アプリ本体
│   └── connections.xml           # 接続設定ファイル（configCopy用）
└── ...
```

## 処理フロー

### メインフロー

```
Install.bat
    │
    ├─ 1. 管理者権限チェック（なければ昇格要求）
    ├─ 2. PowerShell実行ポリシー確認
    ├─ 3. メニュー表示
    │       ========================================
    │         開発環境セットアップ
    │       ========================================
    │       1. インストール + Gitクローン自動実行
    │       2. インストールのみ
    │       3. Gitクローンのみ
    │       ----------------------------------------
    │       選択してください (1-3):
    │
    ├─ 4. Gitクローンを含む場合（選択1または3）
    │       ├─ アクセストークン入力プロンプト表示
    │       └─ トークンをメモリに保持（スクリプト終了で消去）
    │
    └─ 5. 選択に応じてスクリプト呼び出し
           ├─ 1 → Main.ps1 実行後、Clone-Repositories.ps1 実行（トークン渡し）
           ├─ 2 → Main.ps1 のみ実行
           └─ 3 → Clone-Repositories.ps1 のみ実行（トークン渡し）

Main.ps1
           │
           ├─ モジュール読み込み
           ├─ tools.json 読み込み
           ├─ ログ初期化
           ├─ 共有ディレクトリアクセスチェック
           │       └─ アクセス不可 → FATAL出力して即停止
           │
           └─ ツールごとにループ（tools配列順に処理）
                  │
                  ├─ [FileManager] 共有からファイル情報取得
                  ├─ [FileManager] ローカルファイルとハッシュ比較
                  │       ├─ 同一 → スキップ判定へ
                  │       └─ 差異/未存在 → 取得（旧ファイルはbkへ）
                  │
                  ├─ type別処理分岐
                  │       ├─ installer → [Installer] サイレント実行
                  │       ├─ extract → [Extractor] 解凍（既存はbkへ）
                  │       └─ copy → [FileCopier] コピー
                  │
                  ├─ configCopyあり → [ConfigCopier] 設定ファイルコピー
                  │
                  └─ 結果記録（SUCCESS/SKIPPED/FAILED + 理由）
           │
           ├─ サマリー出力
           └─ 終了コード返却

[オプション] Clone-Repositories.ps1（単独実行可）
           │
           ├─ git --version でGitインストール確認
           │       └─ 失敗 → FATAL出力して即停止
           │
           ├─ tools.json の repositories を読み込み
           └─ 各リポジトリをクローン（トークン使用）

[オプション] Set-JavaEnv.ps1（単独実行可）
```

### ファイル取得・比較フロー

```
共有ディレクトリからファイル情報取得
    │
    ├─ 共有側ファイルのハッシュ計算（SHA256）
    │
    ├─ ローカルファイル存在チェック
    │       │
    │       ├─ 存在しない → 新規取得
    │       │
    │       └─ 存在する
    │               │
    │               ├─ ローカル側ハッシュ計算
    │               │
    │               └─ 比較
    │                       ├─ 一致 → スキップ判定へ
    │                       └─ 不一致 → 既存をbk/yyyyMMdd-HHmmss/に移動 → 取得
    │
    └─ ファイル取得完了
```

### 解凍処理フロー

```
解凍先ディレクトリ確認
    │
    ├─ 存在しない → 解凍実行
    │
    └─ 存在する
            │
            ├─ 既存ディレクトリを圧縮（ツール名-タイムスタンプ.7z）
            ├─ bk/yyyyMMdd-HHmmss/ に移動
            └─ 解凍実行
```

### copyタイプ処理フロー

```
コピー先確認
    │
    ├─ 存在しない → コピー実行
    │
    └─ 存在する
            │
            ├─ ハッシュ比較
            │       ├─ 一致 → SKIPPED
            │       └─ 不一致 → 既存をbk/yyyyMMdd-HHmmss/に移動 → コピー
            │
            └─ コピー対象は自動判定（ファイル/フォルダ）
```

### configCopy処理フロー

```
configCopy設定あり
    │
    ├─ コピー先フォルダ確認
    │       └─ 存在しない → 自動作成
    │
    ├─ コピー先に既存ファイルがある場合
    │       └─ backupRoot/yyyyMMdd-HHmmss/ にバックアップ
    │
    └─ 設定ファイルを共有から指定先にコピー
        例: \\server\share\packages\sqldeveloper\connections.xml
          → %APPDATA%\SQL Developer\connections.xml
```

※環境変数（%APPDATA%等）は `[Environment]::ExpandEnvironmentVariables()` で展開

## バックアップ仕様

| 対象 | 条件 | 動作 |
|------|------|------|
| 取得した圧縮ファイル | ハッシュ不一致で再取得時 | backupRoot/yyyyMMdd-HHmmss/に移動 |
| 解凍先ディレクトリ | 既存ディレクトリが存在 | 7z圧縮してbackupRoot/yyyyMMdd-HHmmss/に移動後、新規解凍 |
| コピー先ファイル（copyタイプ） | 既存ファイルが存在 | backupRoot/yyyyMMdd-HHmmss/に移動後、上書き |
| 設定ファイル（configCopy） | 既存ファイルが存在 | backupRoot/yyyyMMdd-HHmmss/に移動後、上書き |

バックアップ先例: `C:\packages\bk\20260203-103000\`（backupRoot = `C:\packages\bk`）

**注意**: バックアップフォルダは実行ごとにタイムスタンプ付きで新規作成

## エラーハンドリング

| ツール | 失敗時の動作 |
|--------|--------------|
| 共有ディレクトリアクセス不可 | 即停止（FATAL）- 処理開始前にチェック |
| 7zip | 即停止（FATAL）- 他ツールの解凍ができないため |
| フォルダ内複数ファイル検出 | 該当ツールをFAILEDとしてスキップ、次へ継続 |
| その他 | ログにERROR記録、次のツールへ継続 |

### installerタイプのスキップ判定

レジストリのアンインストール情報からバージョン確認:
1. `displayName`でアンインストール情報を検索（`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`）
2. インストール済みバージョンを取得
3. tools.jsonの`version`と比較
   - 一致 → SKIPPED
   - 不一致/未インストール → インストール実行
4. `skipVersionCheck: true`の場合 → バージョン確認なし、常に実行（プラグイン用）

### インストーラー成功判定

終了コードによる成功判定:
- デフォルト: `0`（成功）、`3010`（再起動要求=成功扱い）
- ツールごとに`successCodes`で上書き可能

### 特殊ケース: ハッシュ一致だが解凍先なし

ローカルのアーカイブと共有のハッシュが一致しているが、解凍先ディレクトリが存在しない場合（手動削除等）:
- WARNING出力: `"jdk: ハッシュ一致だが解凍先が存在しません。再解凍します。"`
- 再解凍を実行

## モジュール責務

| モジュール | 責務 |
|------------|------|
| **Logger.psm1** | ログ初期化、色付きコンソール出力、ファイル出力、サマリー生成、進行度表示 |
| **FileManager.psm1** | ハッシュ計算（SHA256）、ファイル比較、取得（進行度付き）、バックアップ（ファイル移動） |
| **Extractor.psm1** | 7z/zip解凍、解凍先バックアップ（圧縮→移動） |
| **Installer.psm1** | exe/msiサイレント実行、終了コード確認、レジストリバージョン確認 |
| **ConfigCopier.psm1** | 設定ファイルコピー（環境変数展開対応） |
| **FileCopier.psm1** | ファイル/フォルダコピー（自動判定）、ハッシュ比較 |

## 進行度表示

大容量ファイルの処理時に進行度をログ形式で出力する。

### 対象処理と表示形式

| 処理 | 進行度 | 出力形式 |
|------|--------|----------|
| ハッシュ計算 | あり | `ハッシュ計算中... 52MB / 520MB (10%)` |
| ファイル取得 | あり | `ファイル取得中... 52MB / 520MB (10%)` |
| 解凍処理 | なし | `解凍中... (520MB)` → `解凍完了` |

### 進行度あり処理の出力例
```
[INFO]  ファイル取得中... 52MB / 520MB (10%)
[INFO]  ファイル取得中... 156MB / 520MB (30%)
[INFO]  ファイル取得中... 312MB / 520MB (60%)
[INFO]  ファイル取得中... 520MB / 520MB (100%)
[INFO]  ファイル取得完了
```

### 進行度なし処理（解凍）の出力例
```
[INFO]  解凍中... (520MB)
[INFO]  解凍完了
```

### 更新条件（進行度あり処理）
- **時間**: 5秒ごと
- **変化量**: 前回出力から5%以上変化した場合のみ

※両方の条件を満たした場合に出力（5秒経過しても5%未満の変化なら出力しない）

## ログ仕様

### 出力先

| 出力先 | 内容 |
|--------|------|
| コンソール | 全ログ + サマリーテーブル（色付き） |
| {logRoot}/install-yyyyMMdd-HHmmss.log | 詳細ログ（処理経過） |
| {logRoot}/summary-yyyyMMdd-HHmmss.txt | サマリーテーブルのみ |

※logRootはdefaultsで指定（例: `C:\dev-tools\logs`）

### ログレベル・色分け

| レベル | 色 | 用途 |
|--------|------|------|
| `[INFO]` | 白（デフォルト） | 通常情報 |
| `[SUCCESS]` | 緑 | 処理成功 |
| `[SKIPPED]` | 黄 | スキップ（問題なし） |
| `[WARNING]` | 黄 | 警告（継続可能な問題） |
| `[ERROR]` | 赤 | エラー（処理失敗） |
| `[FATAL]` | 赤背景+白文字 | 致命的エラー（即停止） |
| セクション区切り | シアン | `===`, `---` 等の区切り線 |

### 詳細ログフォーマット

```
================================================================================
[2026-02-03 10:30:00] インストール開始
================================================================================
[INFO]  設定ファイル: C:\package-management\config\tools.json
[INFO]  共有ルート: \\server\share\packages
[INFO]  ローカルルート: C:\packages
--------------------------------------------------------------------------------
[INFO]  === 7zip ===
[INFO]  ソース: \\server\share\packages\7zip\7z2301-x64.exe
[INFO]  ハッシュ(共有): A1B2C3D4...
[INFO]  ハッシュ(ローカル): なし（新規取得）
[INFO]  処理: ファイル取得 → インストール実行
[SUCCESS] 7zip インストール完了
--------------------------------------------------------------------------------
[INFO]  === jdk ===
[INFO]  ソース: \\server\share\packages\jdk\jdk-17.0.8.7z
[INFO]  ハッシュ(共有): E5F6G7H8...
[INFO]  ハッシュ(ローカル): E5F6G7H8...（一致）
[INFO]  解凍先: C:\dev-tools\jdk\17 → 存在する
[SKIPPED] jdk スキップ（ハッシュ一致・解凍済み）
--------------------------------------------------------------------------------
...
================================================================================
[2026-02-03 10:35:00] インストール完了
================================================================================
```

### サマリーファイルフォーマット（summary-yyyyMMdd-HHmmss.txt）

```
インストール実行日時: 2026-02-03 10:30:00 - 10:35:00
設定ファイル: C:\package-management\config\tools.json

+----------------+------------+----------------+----------------+----------+------------------+
| ツール名       | 方式       | ローカルVer    | 共有Ver        | 結果     | 備考             |
+----------------+------------+----------------+----------------+----------+------------------+
| 7zip           | installer  | -              | 23.01          | SUCCESS  |                  |
| jdk            | extract    | 17.0.8         | 17.0.8         | SKIPPED  | ハッシュ一致     |
| eclipse        | extract    | 2024-03        | 2024-06        | SUCCESS  | 旧版をbkに退避   |
| weblogic       | extract    | -              | 14.1.1         | SUCCESS  |                  |
| teraterm       | installer  | 5.0            | 5.1            | SUCCESS  |                  |
| git            | installer  | 2.43.0         | 2.43.0         | SKIPPED  | バージョン一致   |
| tortoisegit    | installer  | -              | 2.15.0         | SUCCESS  |                  |
| chrome         | installer  | 120.0          | 121.0          | FAILED   | exit code: 1603  |
| modheader      | copy       | -              | -              | SUCCESS  |                  |
| a5m2           | extract    | 2.17.0         | 2.17.0         | SKIPPED  | ハッシュ一致     |
| sqldeveloper   | extract    | -              | 23.1.0         | SUCCESS  |                  |
| winmerge       | installer  | 2.16.38        | 2.16.40        | SUCCESS  |                  |
| sakura         | installer  | -              | 2.4.2          | SUCCESS  |                  |
+----------------+------------+----------------+----------------+----------+------------------+

集計:
  SUCCESS: 9件
  SKIPPED: 3件 (ハッシュ一致のためスキップ)
  FAILED:  1件
```

※バージョン列は将来実装。現時点は `-` で表示。

## A5M2・SQL Developer の設定配布方式検討

### 背景

両ツールともコマンドラインでのDB接続インポート機能が制限されている：
- **A5M2**: A5M2cmd.exe（CLI）はGUI版のDB登録設定を直接利用不可
- **SQL Developer 20.x**: SQLcl Connection Manager は 23.3以降のみ

### 設定ファイルの保存場所

| ツール | アプリ本体 | 設定ファイル |
|--------|-----------|-------------|
| A5M2（ポータブル） | `C:\dev-tools\a5m2\` | `C:\dev-tools\a5m2\Portable\` ← 同一フォルダ内 |
| SQL Developer | `C:\dev-tools\sqldeveloper\` | `%APPDATA%\SQL Developer\` ← 別の場所 |

### 採用方式（現行）

| ツール | 方式 | 詳細 |
|--------|------|------|
| A5M2 | 設定込み7z配布 | Portableフォルダを含む7zを配布、extractのみで完了 |
| SQL Developer | extract + configCopy | 本体extract後、connections.xmlを%APPDATA%にコピー |

### 代替案（将来の簡略化）

処理を単純化する場合：
1. 両ツールとも extract のみ
2. 設定ファイルは共有に配置（手動インポート前提）
3. ログに「接続設定は手動でインポートしてください」と案内

この場合、configCopy機能は削除し、手動インポート手順をドキュメント化する。

## 将来実装予定

### バージョン比較機能

| 対象 | 取得方法 |
|------|----------|
| 共有側（配布） | tools.jsonの`version`フィールド |
| ローカル側 | 実行ファイルのバージョン情報 / レジストリ / コマンド実行結果 |

tools.json拡張例:
```json
{
  "name": "git",
  "type": "installer",
  "version": "2.43.0",
  "versionCheck": {
    "method": "command",
    "command": "git --version",
    "pattern": "git version ([\\d.]+)"
  }
}
```

## 処理順序と依存関係

- tools配列の**定義順**に処理を実行
- 7zipは必ず最初に定義し、他のextract処理より先に実行すること
- TortoiseGitプラグインはTortoiseGitより後に定義すること

**推奨順序例:**
1. 7zip（必須・最初）
2. その他のinstaller（Git, TortoiseGit, TortoiseGitプラグイン, Chrome, TeraTerm, WinMerge, Sakura）
3. extract（JDK, Eclipse, WebLogic, Eclipse workspace, A5M2, SQL Developer）
4. copy（ModHeader）

## 制約・前提条件

- PowerShell 5.1（Windows標準）
- 管理者権限が必要
- 7-Zipは最初にインストールされ、他ツールの解凍に使用（installerタイプなので7z.exe不要）
- 共有ディレクトリへのネットワークアクセスが必要
- 各共有フォルダには基本1ファイル（configCopyがある場合は2ファイル）

## PowerShell 5.1 互換性に関する注意

### ConvertFrom-Json の制限

`-AsHashtable` オプションはPowerShell 6.0以降のみ使用可能。
PowerShell 5.1では `PSCustomObject` として読み込み、ドット記法でアクセスする。

```powershell
# PS5.1での正しい使い方
$config = Get-Content $path -Raw | ConvertFrom-Json
$sourceRoot = $config.defaults.sourceRoot    # ドット記法でアクセス

# PS6+でのみ使用可（本プロジェクトでは使用不可）
# $config = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
```

### その他の注意点

- `Expand-Archive` は .zip のみ対応、.7z は 7z.exe を使用
- 環境変数の展開は `[Environment]::ExpandEnvironmentVariables()` を使用
