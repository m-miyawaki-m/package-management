# 開発環境パッケージ管理システム

PowerShellスクリプトを使用して、チーム開発環境のツールパッケージを一括管理・インストールするシステム。

## 概要

共有ディレクトリからツールを取得し、ローカル環境にインストール。バッチファイルを実行するだけで開発環境（Eclipse）が起動する状態まで自動構築します。

## 対象ツール

- JDK
- Eclipse
- WebLogic
- Gradle
- 証明書（JDKキーストアに登録）

## 動作環境

- Windows 10/11
- PowerShell 5.1以上
- 共有ディレクトリへのアクセス権

## ディレクトリ構成

```
package-management/
├── config/
│   ├── settings.json           # 共通設定
│   └── projects/
│       └── sample.json         # プロジェクト別設定
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

## クイックスタート

### 1. 共通設定を編集

`config/settings.json` を環境に合わせて編集:

```json
{
  "shareBasePath": "\\\\your-server\\share\\dev-packages",
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

### 2. プロジェクト設定を作成

`config/projects/myproject.json` を作成:

```json
{
  "name": "myproject",
  "description": "プロジェクトの説明",
  "tools": {
    "jdk": {
      "version": "17.0.8",
      "file": "jdk-17.0.8.zip"
    },
    "eclipse": {
      "version": "2024-03",
      "file": "eclipse-2024-03.zip",
      "workspace": "C:\\workspace\\myproject"
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

### 3. 共有ディレクトリにツールを配置

```
\\your-server\share\dev-packages\
├── jdk/
│   └── jdk-17.0.8.zip
├── eclipse/
│   └── eclipse-2024-03.zip
├── weblogic/
│   └── weblogic-14.1.zip
├── gradle/
│   └── gradle-8.5.zip
└── certs/
    └── internal-ca.cer
```

### 4. インストール実行

```powershell
.\scripts\Install-DevEnv.ps1 -Project myproject
```

### 5. 開発環境を起動

```batch
C:\dev-tools\bin\start-myproject.bat
```

## 機能

- **バージョン共存**: 同一ツールの複数バージョンをインストール可能
- **スキップ機能**: インストール済みバージョンは自動スキップ
- **ログ出力**: コンソールとファイルに処理結果を出力
- **証明書登録**: JDKのcacertsに証明書を自動登録

## ログ

インストールログは以下に出力されます:

```
C:\dev-tools\logs\install-myproject-20260127-143052.log
```

## ドキュメント

- [設計書](docs/plans/2026-01-27-dev-env-package-management-design.md)
- [仕様書](docs/specifications.md)

## ライセンス

MIT
