# 開発環境パッケージ管理システム

JSONベースの設定ファイルとStep処理方式で、チーム開発環境のツールを一括インストールするシステム。

## 概要

共有ディレクトリからツールを取得し、ローカル環境にインストール。管理者権限で `Install.bat` を実行するだけで開発環境を自動構築します。

## 特徴

- **JSONベース設定**: ツール・バージョン・取得先を設定ファイルで管理
- **Step処理方式**: 展開、インストーラ実行、設定差し替え、環境変数設定、証明書登録を柔軟に組み合わせ
- **PowerShell 5対応**: Windows標準環境で動作
- **ログ出力**: コンソールとファイルに処理結果を出力

## 動作環境

- Windows 10/11
- PowerShell 5.1以上
- 管理者権限（環境変数設定に必要）
- 共有ディレクトリへのアクセス権

## クイックスタート

### 1. 設定ファイルを編集

`config/tools.json` を環境に合わせて編集:

```json
{
  "defaults": {
    "sourceBase": "\\\\your-server\\share\\packages",
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
        { "type": "env", "name": "PATH", "action": "append", "value": "%JAVA_HOME%\\bin" }
      ]
    }
  ]
}
```

### 2. インストール実行

```batch
Install.bat
```

管理者権限で実行されます（自動昇格）。

## Stepタイプ

| タイプ | 説明 | 例 |
|--------|------|-----|
| `extract` | 7z/ZIP展開 | `{ "type": "extract", "source": "jdk\\jdk-17.0.8.7z", "destination": "jdk\\17.0.8" }` |
| `installer` | サイレントインストール | `{ "type": "installer", "source": "7zip\\setup.exe", "silentArgs": "/S" }` |
| `config` | 設定ファイル差し替え | `{ "type": "config", "source": "eclipse\\eclipse.ini", "destination": "eclipse\\2024-03\\eclipse.ini" }` |
| `env` | 環境変数設定 | `{ "type": "env", "name": "JAVA_HOME", "value": "C:\\dev-tools\\jdk\\17.0.8" }` |
| `cert` | 証明書登録 | `{ "type": "cert", "source": "certs\\ca.cer", "javaHome": "C:\\dev-tools\\jdk\\17.0.8" }` |

## ディレクトリ構成

```
package-management/
├── Install.bat                 # エントリーポイント
├── config/
│   └── tools.json              # ツール設定
├── scripts/
│   ├── Install-DevEnv.ps1      # メインスクリプト
│   └── lib/
│       ├── Common.ps1          # ログ、共通関数
│       └── StepHandlers.ps1    # 各タイプの処理関数
└── docs/
```

## ログ

インストールログは以下に出力されます:

```
C:\dev-tools\logs\install-20260203-143052.log
```

## ドキュメント

- [処理フロー](docs/processing-flow.md)
- [Step-Based Installer 設計書](docs/plans/2026-02-03-step-based-installer-design.md)

## ライセンス

MIT
