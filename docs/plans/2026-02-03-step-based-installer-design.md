# Step-Based Installer 設計書

## 概要

ツールごとの個別スクリプトを廃止し、JSONベースの設定ファイルとstep処理方式に移行する。

## 設定ファイル構造

### defaults + tools 構成

```json
{
  "defaults": {
    "sourceBase": "\\\\server\\share\\packages",
    "destBase": "C:\\dev-tools",
    "7zPath": "C:\\dev-tools\\7zip\\7z.exe"
  },
  "tools": [
    {
      "name": "ツール名",
      "version": "バージョン",
      "sourceBase": "（オプション）ツール固有の取得先",
      "steps": [...]
    }
  ]
}
```

### defaults

| プロパティ | 説明 |
|------------|------|
| `sourceBase` | ソースファイルの取得元ベースパス |
| `destBase` | インストール先ベースパス |
| `7zPath` | 7z.exe のパス |

### tools

| プロパティ | 必須 | 説明 |
|------------|------|------|
| `name` | Yes | ツール名（識別用） |
| `version` | Yes | バージョン |
| `sourceBase` | No | ツール固有の取得元（defaultsを上書き） |
| `steps` | Yes | 実行するstepの配列 |

## Stepタイプ

### extract - 7z/ZIP展開

```json
{
  "type": "extract",
  "source": "jdk\\jdk-17.0.8.7z",
  "destination": "jdk\\17.0.8"
}
```

| プロパティ | 説明 |
|------------|------|
| `source` | sourceBaseからの相対パス |
| `destination` | destBaseからの相対パス |

**動作:**
- 拡張子が `.zip` の場合: `Expand-Archive` を使用
- 拡張子が `.7z` の場合: `7zPath` の 7z.exe を使用

### installer - サイレントインストール

```json
{
  "type": "installer",
  "source": "7zip\\7z2301-x64.exe",
  "silentArgs": "/S /D=C:\\dev-tools\\7zip"
}
```

| プロパティ | 説明 |
|------------|------|
| `source` | sourceBaseからの相対パス |
| `silentArgs` | サイレントインストール用の引数 |

**動作:**
- ソースファイルの存在確認
- 引数を付けて実行、完了を待機

### config - 設定ファイル差し替え

```json
{
  "type": "config",
  "source": "eclipse\\eclipse.ini",
  "destination": "eclipse\\2024-03\\eclipse.ini"
}
```

| プロパティ | 説明 |
|------------|------|
| `source` | sourceBaseからの相対パス |
| `destination` | destBaseからの相対パス |

**動作:**
- 既存ファイルがあれば `.bak` に退避
- sourceをdestinationにコピー

### env - 環境変数設定

```json
{
  "type": "env",
  "name": "JAVA_HOME",
  "value": "C:\\dev-tools\\jdk\\17.0.8"
}
```

```json
{
  "type": "env",
  "name": "PATH",
  "action": "append",
  "value": "%JAVA_HOME%\\bin"
}
```

| プロパティ | 必須 | 説明 |
|------------|------|------|
| `name` | Yes | 環境変数名 |
| `value` | Yes | 設定する値 |
| `action` | No | `set`（デフォルト）または `append` |

**動作:**
- システム環境変数に設定（管理者権限必要）
- 既存値がある場合はログに記録してから上書き
- `action: append` の場合は既存PATHの末尾に追加

### cert - 証明書登録

```json
{
  "type": "cert",
  "source": "certs\\internal-ca.cer",
  "javaHome": "C:\\dev-tools\\jdk\\17.0.8"
}
```

```json
{
  "type": "cert",
  "source": "certs\\internal-ca.cer",
  "keystore": "C:\\dev-tools\\jdk\\17.0.8\\lib\\security\\cacerts"
}
```

| プロパティ | 説明 |
|------------|------|
| `source` | sourceBaseからの相対パス |
| `javaHome` | JAVA_HOMEパス（lib\\security\\cacertsを自動付与） |
| `keystore` | cacertsのフルパス（直接指定） |

**動作:**
- `javaHome` 指定時: `$javaHome\lib\security\cacerts` を使用
- `keystore` 指定時: 指定パスをそのまま使用
- keytoolで証明書をインポート

## エラーハンドリング

- step失敗時: そのツールの残りstepをスキップ、次のツールは続行
- エラー内容はログに記録

## ディレクトリ構成

```
package-management/
├── Install.bat                    # エントリーポイント
├── config/
│   └── tools.json                 # ツール設定
├── scripts/
│   ├── Install-DevEnv.ps1         # メインスクリプト
│   └── lib/
│       ├── Common.ps1             # ログ、共通ユーティリティ
│       └── StepHandlers.ps1       # 各タイプの処理関数
└── docs/
```

## 実行フロー

```
Install.bat
    │
    ├── 管理者権限チェック
    │   └── なければ昇格要求
    │
    ├── PowerShell実行ポリシーチェック
    │   └── 必要なら一時的にBypass
    │
    └── Install-DevEnv.ps1 実行
            │
            ├── 設定JSON読み込み
            ├── ログ初期化
            │
            └── toolsをループ
                    │
                    └── stepsをループ
                            │
                            ├── type判定
                            ├── Invoke-*Step 呼び出し
                            └── 結果をログ出力
```

## ログ出力

- **出力先:** コンソール + ファイル（`{destBase}\logs\install-yyyyMMdd-HHmmss.log`）
- **内容:**
  - 各stepの開始・終了
  - 環境変数の既存値（上書き前）
  - エラー詳細
  - 最終サマリー（成功/スキップ/失敗件数）

## PowerShell 5 対応

| 項目 | 対応 |
|------|------|
| `ConvertFrom-Json` | `-AsHashtable` 不可、`[psobject]` で扱う |
| 7z展開 | 7z.exe コマンド呼び出し |
| 環境変数設定 | `[Environment]::SetEnvironmentVariable($name, $value, "Machine")` |
| 文字エンコーディング | `-Encoding UTF8` を明示 |

## 設定ファイル例

```json
{
  "defaults": {
    "sourceBase": "\\\\server\\share\\packages",
    "destBase": "C:\\dev-tools",
    "7zPath": "C:\\dev-tools\\7zip\\7z.exe"
  },
  "tools": [
    {
      "name": "7zip",
      "version": "23.01",
      "steps": [
        { "type": "installer", "source": "7zip\\7z2301-x64.exe", "silentArgs": "/S /D=C:\\dev-tools\\7zip" }
      ]
    },
    {
      "name": "jdk",
      "version": "17.0.8",
      "steps": [
        { "type": "extract", "source": "jdk\\jdk-17.0.8.7z", "destination": "jdk\\17.0.8" },
        { "type": "env", "name": "JAVA_HOME", "value": "C:\\dev-tools\\jdk\\17.0.8" },
        { "type": "env", "name": "PATH", "action": "append", "value": "%JAVA_HOME%\\bin" },
        { "type": "cert", "source": "certs\\internal-ca.cer", "javaHome": "C:\\dev-tools\\jdk\\17.0.8" }
      ]
    },
    {
      "name": "gradle",
      "version": "8.5",
      "steps": [
        { "type": "extract", "source": "gradle\\gradle-8.5.7z", "destination": "gradle\\8.5" },
        { "type": "env", "name": "GRADLE_HOME", "value": "C:\\dev-tools\\gradle\\8.5" },
        { "type": "env", "name": "PATH", "action": "append", "value": "%GRADLE_HOME%\\bin" }
      ]
    },
    {
      "name": "eclipse",
      "version": "2024-03",
      "steps": [
        { "type": "extract", "source": "eclipse\\eclipse-2024-03.7z", "destination": "eclipse\\2024-03" },
        { "type": "config", "source": "eclipse\\eclipse.ini", "destination": "eclipse\\2024-03\\eclipse.ini" }
      ]
    }
  ]
}
```
