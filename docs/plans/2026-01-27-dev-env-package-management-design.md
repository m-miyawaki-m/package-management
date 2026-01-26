# 開発環境パッケージ管理システム 設計書

## 概要

PowerShellスクリプトを利用して、チーム開発環境のツールパッケージ管理を行うシステム。
共有ディレクトリからツールを取得し、インストール後、バッチを叩くだけで開発環境（Eclipse）が起動する状態まで構築する。

## 前提条件

- 対象: 小規模チーム（2-10人）
- 共有ディレクトリ: Windowsファイル共有（SMB）形式 `\\server\share`
- インストール先: 固定パス `C:\dev-tools`
- バージョン管理: プロジェクト別にツールバージョンを指定可能
- ツール形式: すべてZIP形式で配布

## 対象ツール

- JDK
- Eclipse
- WebLogic
- Gradle
- 証明書（JDKキーストアに登録）

## ディレクトリ構成

### ローカル（このリポジトリ）

```
package-management/
├── config/
│   ├── settings.json        # 共通設定（共有パス、インストール先など）
│   └── projects/
│       ├── projectA.json    # プロジェクトAの構成
│       └── projectB.json    # プロジェクトBの構成
│
├── scripts/
│   ├── Install-DevEnv.ps1   # メインスクリプト
│   ├── modules/
│   │   ├── Install-Jdk.ps1
│   │   ├── Install-Eclipse.ps1
│   │   ├── Install-WebLogic.ps1
│   │   ├── Install-Gradle.ps1
│   │   └── Install-Certificate.ps1
│   └── lib/
│       └── Common.ps1       # 共通関数
│
├── templates/
│   └── start-eclipse.bat.template
│
└── docs/
    └── plans/
        └── (この設計書)
```

### 共有ディレクトリ

```
\\server\share\dev-packages\
├── jdk/
│   ├── jdk-11.0.20.zip
│   └── jdk-17.0.8.zip
├── eclipse/
│   └── eclipse-2024-03.zip
├── weblogic/
│   └── weblogic-14.1.zip
├── gradle/
│   └── gradle-8.5.zip
└── certs/
    ├── internal-ca.cer
    └── proxy-cert.cer
```

### インストール先（バージョン共存）

```
C:\dev-tools\
├── jdk\
│   ├── 11.0.20\
│   └── 17.0.8\
├── eclipse\
│   ├── 2023-09\
│   └── 2024-03\
├── weblogic\
│   └── 14.1\
├── gradle\
│   ├── 8.5\
│   └── 8.7\
├── bin\
│   ├── start-projectA.bat
│   └── start-projectB.bat
└── logs\
    └── install-projectA-YYYYMMDD-HHMMSS.log
```

## 設定ファイル

### config/settings.json（共通設定）

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

### config/projects/projectA.json（プロジェクト設定）

```json
{
  "name": "projectA",
  "description": "プロジェクトAの開発環境",
  "tools": {
    "jdk": {
      "version": "17.0.8",
      "file": "jdk-17.0.8.zip"
    },
    "eclipse": {
      "version": "2024-03",
      "file": "eclipse-2024-03.zip",
      "workspace": "C:\\workspace\\projectA"
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
    "internal-ca.cer",
    "proxy-cert.cer"
  ]
}
```

## 処理フロー

### 実行コマンド

```powershell
.\Install-DevEnv.ps1 -Project projectA
```

### 処理ステップ

1. **設定読み込み**
   - `config/settings.json` を読み込み
   - `config/projects/projectA.json` を読み込み

2. **事前チェック**
   - 共有ディレクトリへの接続確認
   - 必要なZIPファイルの存在確認
   - インストール先の空き容量確認

3. **ツールのインストール（順序固定）**
   - JDK → ZIP展開 + 証明書登録
   - Gradle → ZIP展開
   - WebLogic → ZIP展開
   - Eclipse → ZIP展開

4. **起動バッチの生成**
   - テンプレートから `start-projectA.bat` を生成

5. **完了メッセージ**
   - 起動バッチのパスを表示

### バージョン共存の扱い

```
バージョン別フォルダが存在する？
├─ YES → スキップ（既にインストール済み）
└─ NO  → ZIP展開してインストール
```

環境変数はシステムに設定せず、起動バッチ内でローカル設定する。
プロジェクト切り替えは起動バッチを変えるだけで済む。

## ログ出力

### 出力先

```
C:\dev-tools\logs\install-projectA-20260127-143052.log
```

### ログフォーマット

```
================================================================================
[2026-01-27 14:30:52] Install-DevEnv 開始
[2026-01-27 14:30:52] プロジェクト: projectA
[2026-01-27 14:30:52] 設定ファイル: config/projects/projectA.json
================================================================================

[2026-01-27 14:30:52] === JDK ===
[2026-01-27 14:30:52] 要求バージョン: 17.0.8
[2026-01-27 14:30:52] インストール先: C:\dev-tools\jdk\17.0.8
[2026-01-27 14:30:55] 結果: SUCCESS (新規インストール)

[2026-01-27 14:30:55] === Gradle ===
[2026-01-27 14:30:55] 要求バージョン: 8.5
[2026-01-27 14:30:55] インストール先: C:\dev-tools\gradle\8.5
[2026-01-27 14:30:55] 結果: SKIPPED (既存バージョン: 8.5)

[2026-01-27 14:30:55] === Eclipse ===
[2026-01-27 14:30:55] 要求バージョン: 2024-03
[2026-01-27 14:30:55] インストール先: C:\dev-tools\eclipse\2024-03
[2026-01-27 14:31:10] 結果: SUCCESS (新規インストール)

[2026-01-27 14:31:10] === Certificate ===
[2026-01-27 14:31:10] 対象: internal-ca.cer
[2026-01-27 14:31:11] 結果: SUCCESS (キーストアに登録)

[2026-01-27 14:31:11] === 環境変数・起動バッチ ===
[2026-01-27 14:31:11] 起動バッチ: C:\dev-tools\bin\start-projectA.bat
[2026-01-27 14:31:11] 結果: SUCCESS

================================================================================
[2026-01-27 14:31:11] Install-DevEnv 完了
[2026-01-27 14:31:11] 成功: 4, スキップ: 1, 失敗: 0
================================================================================
```

### 結果ステータス

| ステータス | 意味 |
|-----------|------|
| SUCCESS | 新規インストール成功 |
| SKIPPED | 既存バージョンあり（バージョン番号も表示） |
| FAILED | 失敗（エラー詳細も出力） |

コンソールにも同時出力し、ログファイルにも保存する。

## 起動バッチ

### テンプレート（templates/start-eclipse.bat.template）

```batch
@echo off
chcp 65001 > nul
setlocal

rem ============================================
rem {{PROJECT_NAME}} 開発環境 起動バッチ
rem 生成日時: {{GENERATED_AT}}
rem ============================================

set JAVA_HOME={{JAVA_HOME}}
set GRADLE_HOME={{GRADLE_HOME}}
set WEBLOGIC_HOME={{WEBLOGIC_HOME}}
set PATH=%JAVA_HOME%\bin;%GRADLE_HOME%\bin;%PATH%

echo プロジェクト: {{PROJECT_NAME}}
echo JAVA_HOME: %JAVA_HOME%
echo GRADLE_HOME: %GRADLE_HOME%
echo.

start "" "{{ECLIPSE_PATH}}\eclipse.exe" -data "{{WORKSPACE_PATH}}"
```

### 生成例（C:\dev-tools\bin\start-projectA.bat）

```batch
@echo off
chcp 65001 > nul
setlocal

rem ============================================
rem projectA 開発環境 起動バッチ
rem 生成日時: 2026-01-27 14:31:11
rem ============================================

set JAVA_HOME=C:\dev-tools\jdk\17.0.8
set GRADLE_HOME=C:\dev-tools\gradle\8.5
set WEBLOGIC_HOME=C:\dev-tools\weblogic\14.1
set PATH=%JAVA_HOME%\bin;%GRADLE_HOME%\bin;%PATH%

echo プロジェクト: projectA
echo JAVA_HOME: %JAVA_HOME%
echo GRADLE_HOME: %GRADLE_HOME%
echo.

start "" "C:\dev-tools\eclipse\2024-03\eclipse.exe" -data "C:\workspace\projectA"
```

## 使用方法

### 初回セットアップ

```powershell
# 1. リポジトリをクローン
git clone <repository-url>
cd package-management

# 2. 共通設定を環境に合わせて編集
notepad config\settings.json

# 3. プロジェクト設定を作成
notepad config\projects\myproject.json

# 4. インストール実行
.\scripts\Install-DevEnv.ps1 -Project myproject

# 5. 開発環境起動
C:\dev-tools\bin\start-myproject.bat
```

### 日常の使用

```batch
rem 開発環境を起動するだけ
C:\dev-tools\bin\start-myproject.bat
```
