# 開発環境パッケージ管理システム 仕様書

| 項目 | 内容 |
|------|------|
| 文書バージョン | 1.0 |
| 作成日 | 2026-01-27 |
| 対象システム | 開発環境パッケージ管理システム |

---

## 1. システム概要

### 1.1 目的
PowerShellスクリプトを使用して、チーム開発環境のツールパッケージを一括管理・インストールするシステム。

### 1.2 対象ユーザー
- 小規模チーム（2-10人）の開発者

### 1.3 システム構成

```
package-management/
├── config/
│   ├── settings.json           # 共通設定
│   └── projects/
│       └── <project>.json      # プロジェクト別設定
├── scripts/
│   ├── Install-DevEnv.ps1      # メインスクリプト
│   ├── lib/
│   │   └── Common.ps1          # 共通関数
│   └── modules/
│       ├── Install-Jdk.ps1
│       ├── Install-Eclipse.ps1
│       ├── Install-WebLogic.ps1
│       ├── Install-Gradle.ps1
│       └── Install-Certificate.ps1
└── templates/
    └── start-eclipse.bat.template
```

---

## 2. 動作環境

### 2.1 必須要件

| 項目 | 要件 |
|------|------|
| OS | Windows 10/11 |
| PowerShell | 5.1 以上 |
| 文字コード | UTF-8 |

### 2.2 ネットワーク要件

| 項目 | 要件 |
|------|------|
| 共有ディレクトリ | SMB形式（`\\server\share`） |
| アクセス権 | 読み取り権限 |

---

## 3. 設定ファイル仕様

### 3.1 共通設定（config/settings.json）

| プロパティ | 型 | 必須 | 説明 |
|------------|------|------|------|
| shareBasePath | string | Yes | 共有ディレクトリのUNCパス |
| installBasePath | string | Yes | ローカルインストール先パス |
| tools | object | Yes | ツール別サブディレクトリ名のマッピング |
| tools.jdk | string | Yes | JDK用サブディレクトリ名 |
| tools.eclipse | string | Yes | Eclipse用サブディレクトリ名 |
| tools.weblogic | string | Yes | WebLogic用サブディレクトリ名 |
| tools.gradle | string | Yes | Gradle用サブディレクトリ名 |
| tools.certs | string | Yes | 証明書用サブディレクトリ名 |

**例:**
```json
{
  "shareBasePath": "\\\\server\\share\\dev-packages",
  "installBasePath": "C:\\dev-tools",
  "tools": {
    "jdk": "jdk",
    "eclipse": "eclipse",
    "weblogic": "weblogic",
    "gradle": "gradle",
    "certs": "certs"
  }
}
```

### 3.2 プロジェクト設定（config/projects/<project>.json）

| プロパティ | 型 | 必須 | 説明 |
|------------|------|------|------|
| name | string | Yes | プロジェクト名 |
| description | string | No | プロジェクトの説明 |
| tools | object | Yes | ツール設定 |
| tools.jdk | object | Yes | JDK設定 |
| tools.jdk.version | string | Yes | バージョン（ディレクトリ名に使用） |
| tools.jdk.file | string | Yes | ZIPファイル名 |
| tools.eclipse | object | Yes | Eclipse設定 |
| tools.eclipse.version | string | Yes | バージョン |
| tools.eclipse.file | string | Yes | ZIPファイル名 |
| tools.eclipse.workspace | string | Yes | ワークスペースパス |
| tools.weblogic | object | Yes | WebLogic設定 |
| tools.weblogic.version | string | Yes | バージョン |
| tools.weblogic.file | string | Yes | ZIPファイル名 |
| tools.gradle | object | Yes | Gradle設定 |
| tools.gradle.version | string | Yes | バージョン |
| tools.gradle.file | string | Yes | ZIPファイル名 |
| certificates | string[] | No | 登録する証明書ファイル名の配列 |

**例:**
```json
{
  "name": "sample",
  "description": "サンプルプロジェクトの開発環境",
  "tools": {
    "jdk": {
      "version": "17.0.8",
      "file": "jdk-17.0.8.zip"
    },
    "eclipse": {
      "version": "2024-03",
      "file": "eclipse-2024-03.zip",
      "workspace": "C:\\workspace\\sample"
    },
    "weblogic": {
      "version": "14.1",
      "file": "weblogic-14.1.zip"
    },
    "gradle": {
      "version": "8.5",
      "file": "gradle-8.5.zip"
    }
  },
  "certificates": [
    "internal-ca.cer"
  ]
}
```

---

## 4. 処理フロー

### 4.1 メイン処理フロー

```
開始
  │
  ├─ 1. 設定ファイル読み込み
  │     ├─ settings.json
  │     └─ projects/<project>.json
  │
  ├─ 2. ログ初期化
  │     └─ <installBasePath>/logs/install-<project>-<timestamp>.log
  │
  ├─ 3. 事前チェック
  │     └─ 共有ディレクトリ接続確認
  │         └─ 失敗時 → 終了（exit 1）
  │
  ├─ 4. JDKインストール
  │     └─ 失敗時 → 終了（exit 1）
  │
  ├─ 5. 証明書インストール（任意）
  │     └─ certificates配列が存在する場合のみ実行
  │
  ├─ 6. Gradleインストール
  │
  ├─ 7. WebLogicインストール
  │
  ├─ 8. Eclipseインストール
  │
  ├─ 9. 起動バッチ生成
  │     └─ <installBasePath>/bin/start-<project>.bat
  │
  └─ 10. サマリー出力・終了
        └─ 失敗がある場合 → exit 1
終了
```

### 4.2 ツールインストール処理（共通）

```
インストール開始
  │
  ├─ バージョン別インストール先パス生成
  │     └─ <installBasePath>/<tool>/<version>
  │
  ├─ 既存バージョンチェック
  │     └─ 存在する場合 → SKIPPED
  │
  ├─ ZIPファイル存在確認
  │     └─ <shareBasePath>/<tool>/<file>
  │     └─ 存在しない場合 → FAILED
  │
  ├─ ZIP展開
  │     ├─ 一時ディレクトリに展開（_temp_<tool>）
  │     ├─ 展開されたディレクトリを特定
  │     └─ バージョン別ディレクトリにリネーム移動
  │
  └─ 結果返却
        ├─ Status: SUCCESS / SKIPPED / FAILED
        ├─ Path: インストール先パス
        └─ Version: バージョン
```

### 4.3 証明書インストール処理

```
証明書インストール開始
  │
  ├─ keytool.exe 存在確認
  │     └─ <JavaHome>/bin/keytool.exe
  │
  ├─ cacerts 存在確認
  │     └─ <JavaHome>/lib/security/cacerts
  │
  └─ 各証明書に対して
        │
        ├─ 証明書ファイル存在確認
        │     └─ <shareBasePath>/certs/<certFile>
        │
        ├─ エイリアス名生成
        │     └─ ファイル名から拡張子を除去
        │
        ├─ 既存登録確認
        │     └─ keytool -list -alias <alias>
        │     └─ 登録済みの場合 → SKIPPED
        │
        └─ 証明書インポート
              └─ keytool -importcert -trustcacerts -noprompt
              └─ パスワード: changeit
```

---

## 5. インターフェース仕様

### 5.1 メインスクリプト（Install-DevEnv.ps1）

**構文:**
```powershell
.\scripts\Install-DevEnv.ps1 -Project <プロジェクト名>
```

**パラメータ:**

| パラメータ | 型 | 必須 | 説明 |
|------------|------|------|------|
| -Project | string | Yes | プロジェクト名（config/projects/<name>.jsonに対応） |

**終了コード:**

| コード | 意味 |
|--------|------|
| 0 | 正常終了（失敗なし） |
| 1 | 異常終了（1つ以上の失敗あり） |

### 5.2 各インストールモジュールの戻り値

**Install-Jdk / Install-Eclipse / Install-WebLogic / Install-Gradle:**

| キー | 型 | 説明 |
|------|------|------|
| Status | string | SUCCESS / SKIPPED / FAILED |
| Path | string | インストール先パス（FAILEDの場合はnull） |
| Version | string | バージョン |
| Workspace | string | ワークスペースパス（Eclipseのみ） |

**Install-Certificate:**

| キー | 型 | 説明 |
|------|------|------|
| Status | string | SUCCESS / FAILED |
| Processed | int | 処理成功数 |
| Failed | int | 処理失敗数（FAILEDの場合のみ） |

---

## 6. ログ仕様

### 6.1 ログファイル

| 項目 | 値 |
|------|------|
| 出力先 | `<installBasePath>/logs/` |
| ファイル名 | `install-<project>-<yyyyMMdd-HHmmss>.log` |
| 文字コード | UTF-8 |

### 6.2 ログフォーマット

```
[yyyy-MM-dd HH:mm:ss] <メッセージ>
```

### 6.3 ログレベルと表示色

| レベル | コンソール色 | 用途 |
|--------|-------------|------|
| INFO | 標準（白） | 通常情報 |
| SUCCESS | 緑 | 成功 |
| SKIPPED | 黄 | スキップ |
| FAILED | 赤 | 失敗 |
| WARN | 黄 | 警告 |

### 6.4 ログ出力例

```
================================================================================
[2026-01-27 14:30:52] Install-DevEnv 開始
[2026-01-27 14:30:52] プロジェクト: sample
================================================================================
[2026-01-27 14:30:52] 設定ファイル: config/projects/sample.json

[2026-01-27 14:30:52] === 事前チェック ===
[2026-01-27 14:30:52] 共有ディレクトリ接続確認: OK

[2026-01-27 14:30:52] === JDK ===
[2026-01-27 14:30:52] 要求バージョン: 17.0.8
[2026-01-27 14:30:52] インストール先: C:\dev-tools\jdk\17.0.8
[2026-01-27 14:30:55] 結果: SUCCESS (新規インストール)

[2026-01-27 14:30:55] === Certificate ===
[2026-01-27 14:30:55] 対象: internal-ca.cer
[2026-01-27 14:30:56] 結果: SUCCESS (キーストアに登録)

[2026-01-27 14:30:56] === Gradle ===
[2026-01-27 14:30:56] 要求バージョン: 8.5
[2026-01-27 14:30:56] インストール先: C:\dev-tools\gradle\8.5
[2026-01-27 14:30:58] 結果: SUCCESS (新規インストール)

[2026-01-27 14:30:58] === WebLogic ===
[2026-01-27 14:30:58] 要求バージョン: 14.1
[2026-01-27 14:30:58] インストール先: C:\dev-tools\weblogic\14.1
[2026-01-27 14:31:05] 結果: SUCCESS (新規インストール)

[2026-01-27 14:31:05] === Eclipse ===
[2026-01-27 14:31:05] 要求バージョン: 2024-03
[2026-01-27 14:31:05] インストール先: C:\dev-tools\eclipse\2024-03
[2026-01-27 14:31:05] ワークスペース: C:\workspace\sample
[2026-01-27 14:31:10] 結果: SUCCESS (新規インストール)

[2026-01-27 14:31:10] === 起動バッチ生成 ===
[2026-01-27 14:31:10] 起動バッチ: C:\dev-tools\bin\start-sample.bat
[2026-01-27 14:31:10] 結果: SUCCESS

================================================================================
[2026-01-27 14:31:10] Install-DevEnv 完了
[2026-01-27 14:31:10] 成功: 6, スキップ: 0, 失敗: 0
================================================================================
```

---

## 7. 起動バッチ仕様

### 7.1 生成先

```
<installBasePath>/bin/start-<project>.bat
```

### 7.2 設定される環境変数

| 変数 | 値 |
|------|------|
| JAVA_HOME | JDKインストールパス |
| GRADLE_HOME | Gradleインストールパス |
| WEBLOGIC_HOME | WebLogicインストールパス |
| PATH | `%JAVA_HOME%\bin;%GRADLE_HOME%\bin;%PATH%` |

### 7.3 起動処理

Eclipseを指定のワークスペースで起動:
```batch
start "" "<ECLIPSE_PATH>\eclipse.exe" -data "<WORKSPACE_PATH>"
```

---

## 8. ディレクトリ構成

### 8.1 共有ディレクトリ（配置元）

```
<shareBasePath>/
├── jdk/
│   └── <jdk-file>.zip
├── eclipse/
│   └── <eclipse-file>.zip
├── weblogic/
│   └── <weblogic-file>.zip
├── gradle/
│   └── <gradle-file>.zip
└── certs/
    └── <certificate>.cer
```

### 8.2 インストール先

```
<installBasePath>/
├── jdk/
│   └── <version>/
├── eclipse/
│   └── <version>/
├── weblogic/
│   └── <version>/
├── gradle/
│   └── <version>/
├── bin/
│   └── start-<project>.bat
└── logs/
    └── install-<project>-<timestamp>.log
```

---

## 9. エラーハンドリング

### 9.1 致命的エラー（処理中断）

| エラー | 発生条件 | 終了コード |
|--------|----------|------------|
| 設定ファイル未検出 | settings.json が存在しない | 1 |
| プロジェクト設定未検出 | projects/<project>.json が存在しない | 1 |
| 共有ディレクトリ接続失敗 | shareBasePath にアクセスできない | 1 |
| JDKインストール失敗 | JDKのZIP展開に失敗 | 1 |

### 9.2 非致命的エラー（処理継続）

| エラー | 発生条件 | 動作 |
|--------|----------|------|
| 証明書インストール失敗 | 証明書ファイル未検出、keytoolエラー | 失敗をカウントして継続 |
| Gradle/WebLogic/Eclipse失敗 | ZIP未検出、展開エラー | 失敗をカウントして継続 |
| 起動バッチ生成失敗 | テンプレート未検出、書き込みエラー | 失敗をカウントして終了 |

---

## 10. 制限事項・注意事項

### 10.1 制限事項

1. **PowerShellバージョン**: ConvertFrom-Json -AsHashtable はPowerShell 6.0以降で利用可能。PowerShell 5.1では動作しない可能性あり。
2. **証明書パスワード**: cacertsのデフォルトパスワード `changeit` を使用。変更されている場合は動作しない。
3. **ZIPファイル構造**: ZIP内に1つのルートディレクトリがある前提。複数ディレクトリや直接ファイルがある場合は想定外の動作となる可能性あり。

### 10.2 注意事項

1. **管理者権限**: 証明書登録にはcacertsへの書き込み権限が必要。
2. **バージョン共存**: 同一ツールの複数バージョンは別ディレクトリにインストールされ共存可能。
3. **再実行**: 既にインストール済みのバージョンはスキップされる（上書きされない）。

---

## 11. 整合性確認結果

### 11.1 確認項目と結果

| 項目 | 結果 | 備考 |
|------|------|------|
| 処理フロー | OK | 設計書と実装が一致 |
| 設定ファイル形式 | OK | 設計書と実装が一致 |
| ログ出力形式 | OK | 設計書と実装が一致 |
| 起動バッチ形式 | OK | 設計書と実装が一致 |
| 戻り値形式 | OK | 各モジュールで一貫性あり |

### 11.2 未使用コード

Common.ps1に以下の関数が定義されているが、現在の実装では使用されていない:

| 関数 | 状態 | 理由 |
|------|------|------|
| Test-ZipFile | 未使用 | 各モジュールが独自にTest-Path実装 |
| Expand-ToolZip | 未使用 | 各モジュールが独自にExpand-Archive実装 |
| Get-InstalledVersion | 未使用 | 将来のバージョン一覧表示機能用と思われる |

**対応案:**
- 現状維持（将来の拡張用として保持）
- または各モジュールで共通関数を使用するようリファクタリング
