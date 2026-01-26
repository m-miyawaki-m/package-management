# 開発環境パッケージ管理システム 実装計画

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** PowerShellスクリプトで共有ディレクトリからツールを取得し、開発環境をセットアップするシステムを構築する

**Architecture:** 設定ファイル駆動方式。settings.jsonで共通設定、projects/*.jsonでプロジェクト別構成を定義。メインスクリプトが設定を読み込み、各ツールモジュールを順次実行してインストール、最後に起動バッチを生成する。

**Tech Stack:** PowerShell 5.1+, JSON設定ファイル, Batchファイル

---

## Task 1: 共通関数モジュール作成

**Files:**
- Create: `scripts/lib/Common.ps1`

**Step 1: Common.ps1を作成**

```powershell
# scripts/lib/Common.ps1
# 共通関数モジュール

$script:LogFile = $null

function Initialize-Log {
    param(
        [string]$ProjectName,
        [string]$LogBasePath
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logDir = Join-Path $LogBasePath "logs"

    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $script:LogFile = Join-Path $logDir "install-$ProjectName-$timestamp.log"

    Write-Log "================================================================================"
    Write-Log "Install-DevEnv 開始"
    Write-Log "プロジェクト: $ProjectName"
    Write-Log "================================================================================"
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "SKIPPED", "FAILED", "WARN")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"

    # コンソール出力（色分け）
    switch ($Level) {
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "SKIPPED" { Write-Host $logMessage -ForegroundColor Yellow }
        "FAILED"  { Write-Host $logMessage -ForegroundColor Red }
        "WARN"    { Write-Host $logMessage -ForegroundColor Yellow }
        default   { Write-Host $logMessage }
    }

    # ファイル出力
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8
    }
}

function Write-LogSection {
    param([string]$SectionName)
    Write-Log ""
    Write-Log "=== $SectionName ==="
}

function Write-LogSummary {
    param(
        [int]$Success,
        [int]$Skipped,
        [int]$Failed
    )
    Write-Log ""
    Write-Log "================================================================================"
    Write-Log "Install-DevEnv 完了"
    Write-Log "成功: $Success, スキップ: $Skipped, 失敗: $Failed"
    Write-Log "================================================================================"
}

function Test-SharePath {
    param([string]$Path)

    if (Test-Path $Path) {
        Write-Log "共有ディレクトリ接続確認: OK"
        return $true
    } else {
        Write-Log "共有ディレクトリに接続できません: $Path" -Level "FAILED"
        return $false
    }
}

function Test-ZipFile {
    param(
        [string]$ShareBasePath,
        [string]$ToolFolder,
        [string]$FileName
    )

    $filePath = Join-Path $ShareBasePath $ToolFolder $FileName

    if (Test-Path $filePath) {
        return $true
    } else {
        Write-Log "ZIPファイルが見つかりません: $filePath" -Level "FAILED"
        return $false
    }
}

function Expand-ToolZip {
    param(
        [string]$SourceZip,
        [string]$DestinationPath
    )

    try {
        if (-not (Test-Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }

        Expand-Archive -Path $SourceZip -DestinationPath $DestinationPath -Force
        return $true
    }
    catch {
        Write-Log "ZIP展開エラー: $_" -Level "FAILED"
        return $false
    }
}

function Get-InstalledVersion {
    param(
        [string]$InstallBasePath,
        [string]$ToolName
    )

    $toolPath = Join-Path $InstallBasePath $ToolName

    if (-not (Test-Path $toolPath)) {
        return @()
    }

    return Get-ChildItem -Path $toolPath -Directory | Select-Object -ExpandProperty Name
}

Export-ModuleMember -Function *
```

**Step 2: 動作確認用のテストスクリプト作成**

```powershell
# scripts/Test-Common.ps1
$ErrorActionPreference = "Stop"

# モジュール読み込み
Import-Module (Join-Path $PSScriptRoot "lib\Common.ps1") -Force

# テスト用の一時ディレクトリ
$testDir = Join-Path $env:TEMP "package-management-test"
if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
New-Item -ItemType Directory -Path $testDir | Out-Null

# Initialize-Log テスト
Initialize-Log -ProjectName "test" -LogBasePath $testDir

# Write-Log テスト
Write-Log "INFOメッセージ"
Write-Log "成功メッセージ" -Level "SUCCESS"
Write-Log "スキップメッセージ" -Level "SKIPPED"
Write-Log "失敗メッセージ" -Level "FAILED"

# セクション出力テスト
Write-LogSection "テストセクション"

# サマリー出力テスト
Write-LogSummary -Success 2 -Skipped 1 -Failed 0

Write-Host "`nテスト完了。ログファイル: $script:LogFile" -ForegroundColor Cyan

# クリーンアップ
# Remove-Item $testDir -Recurse -Force
```

**Step 3: コミット**

```bash
git add scripts/lib/Common.ps1
git commit -m "feat: add common utility module with logging functions"
```

---

## Task 2: 設定ファイルテンプレート作成

**Files:**
- Create: `config/settings.json`
- Create: `config/projects/sample.json`

**Step 1: settings.jsonを作成**

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

**Step 2: sample.jsonを作成**

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

**Step 3: コミット**

```bash
git add config/settings.json config/projects/sample.json
git commit -m "feat: add configuration file templates"
```

---

## Task 3: JDKインストールモジュール作成

**Files:**
- Create: `scripts/modules/Install-Jdk.ps1`

**Step 1: Install-Jdk.ps1を作成**

```powershell
# scripts/modules/Install-Jdk.ps1
# JDKインストールモジュール

function Install-Jdk {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [hashtable]$ToolConfig
    )

    Write-LogSection "JDK"

    $version = $ToolConfig.version
    $fileName = $ToolConfig.file
    $toolFolder = $Settings.tools.jdk

    Write-Log "要求バージョン: $version"

    # インストール先パス
    $installPath = Join-Path $Settings.installBasePath "jdk" $version
    Write-Log "インストール先: $installPath"

    # 既存バージョンチェック
    if (Test-Path $installPath) {
        Write-Log "結果: SKIPPED (既存バージョン: $version)" -Level "SKIPPED"
        return @{
            Status = "SKIPPED"
            Path = $installPath
            Version = $version
        }
    }

    # ZIPファイルパス
    $zipPath = Join-Path $Settings.shareBasePath $toolFolder $fileName

    if (-not (Test-Path $zipPath)) {
        Write-Log "ZIPファイルが見つかりません: $zipPath" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }

    # ZIP展開
    Write-Log "ZIPファイルを展開中: $zipPath"

    $parentPath = Join-Path $Settings.installBasePath "jdk"
    if (-not (Test-Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    try {
        # 一時ディレクトリに展開してからリネーム
        $tempPath = Join-Path $parentPath "_temp_jdk"
        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force

        # 展開されたディレクトリを特定（通常、ZIP内に1つのフォルダがある）
        $extractedDir = Get-ChildItem -Path $tempPath -Directory | Select-Object -First 1

        if ($extractedDir) {
            Move-Item -Path $extractedDir.FullName -Destination $installPath -Force
        } else {
            # フォルダがない場合はそのまま移動
            Move-Item -Path $tempPath -Destination $installPath -Force
        }

        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Write-Log "結果: SUCCESS (新規インストール)" -Level "SUCCESS"
        return @{
            Status = "SUCCESS"
            Path = $installPath
            Version = $version
        }
    }
    catch {
        Write-Log "インストールエラー: $_" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }
}

Export-ModuleMember -Function Install-Jdk
```

**Step 2: コミット**

```bash
git add scripts/modules/Install-Jdk.ps1
git commit -m "feat: add JDK installation module"
```

---

## Task 4: 証明書インストールモジュール作成

**Files:**
- Create: `scripts/modules/Install-Certificate.ps1`

**Step 1: Install-Certificate.ps1を作成**

```powershell
# scripts/modules/Install-Certificate.ps1
# 証明書インストールモジュール

function Install-Certificate {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [string[]]$Certificates,

        [Parameter(Mandatory)]
        [string]$JavaHome
    )

    Write-LogSection "Certificate"

    $certsFolder = $Settings.tools.certs
    $keytoolPath = Join-Path $JavaHome "bin" "keytool.exe"
    $cacertsPath = Join-Path $JavaHome "lib" "security" "cacerts"

    # keytool存在確認
    if (-not (Test-Path $keytoolPath)) {
        Write-Log "keytoolが見つかりません: $keytoolPath" -Level "FAILED"
        return @{
            Status = "FAILED"
            Processed = 0
        }
    }

    # cacerts存在確認
    if (-not (Test-Path $cacertsPath)) {
        Write-Log "cacertsが見つかりません: $cacertsPath" -Level "FAILED"
        return @{
            Status = "FAILED"
            Processed = 0
        }
    }

    $successCount = 0
    $failCount = 0

    foreach ($certFile in $Certificates) {
        Write-Log "対象: $certFile"

        $certPath = Join-Path $Settings.shareBasePath $certsFolder $certFile

        if (-not (Test-Path $certPath)) {
            Write-Log "証明書ファイルが見つかりません: $certPath" -Level "FAILED"
            $failCount++
            continue
        }

        # エイリアス名（ファイル名から拡張子を除いたもの）
        $alias = [System.IO.Path]::GetFileNameWithoutExtension($certFile)

        try {
            # 既存の証明書を確認
            $checkResult = & $keytoolPath -list -keystore $cacertsPath -storepass "changeit" -alias $alias 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Log "結果: SKIPPED (既に登録済み: $alias)" -Level "SKIPPED"
                $successCount++
                continue
            }

            # 証明書をインポート
            $importResult = & $keytoolPath -importcert -trustcacerts -keystore $cacertsPath -storepass "changeit" -noprompt -alias $alias -file $certPath 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Log "結果: SUCCESS (キーストアに登録)" -Level "SUCCESS"
                $successCount++
            } else {
                Write-Log "keytoolエラー: $importResult" -Level "FAILED"
                $failCount++
            }
        }
        catch {
            Write-Log "証明書登録エラー: $_" -Level "FAILED"
            $failCount++
        }
    }

    if ($failCount -eq 0) {
        return @{
            Status = "SUCCESS"
            Processed = $successCount
        }
    } else {
        return @{
            Status = "FAILED"
            Processed = $successCount
            Failed = $failCount
        }
    }
}

Export-ModuleMember -Function Install-Certificate
```

**Step 2: コミット**

```bash
git add scripts/modules/Install-Certificate.ps1
git commit -m "feat: add certificate installation module"
```

---

## Task 5: Eclipse/WebLogic/Gradleインストールモジュール作成

**Files:**
- Create: `scripts/modules/Install-Eclipse.ps1`
- Create: `scripts/modules/Install-WebLogic.ps1`
- Create: `scripts/modules/Install-Gradle.ps1`

**Step 1: Install-Eclipse.ps1を作成**

```powershell
# scripts/modules/Install-Eclipse.ps1
# Eclipseインストールモジュール

function Install-Eclipse {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [hashtable]$ToolConfig
    )

    Write-LogSection "Eclipse"

    $version = $ToolConfig.version
    $fileName = $ToolConfig.file
    $workspace = $ToolConfig.workspace
    $toolFolder = $Settings.tools.eclipse

    Write-Log "要求バージョン: $version"

    # インストール先パス
    $installPath = Join-Path $Settings.installBasePath "eclipse" $version
    Write-Log "インストール先: $installPath"

    # ワークスペース
    if ($workspace) {
        Write-Log "ワークスペース: $workspace"
    }

    # 既存バージョンチェック
    if (Test-Path $installPath) {
        Write-Log "結果: SKIPPED (既存バージョン: $version)" -Level "SKIPPED"
        return @{
            Status = "SKIPPED"
            Path = $installPath
            Version = $version
            Workspace = $workspace
        }
    }

    # ZIPファイルパス
    $zipPath = Join-Path $Settings.shareBasePath $toolFolder $fileName

    if (-not (Test-Path $zipPath)) {
        Write-Log "ZIPファイルが見つかりません: $zipPath" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }

    # ZIP展開
    Write-Log "ZIPファイルを展開中: $zipPath"

    $parentPath = Join-Path $Settings.installBasePath "eclipse"
    if (-not (Test-Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    try {
        $tempPath = Join-Path $parentPath "_temp_eclipse"
        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force

        $extractedDir = Get-ChildItem -Path $tempPath -Directory | Select-Object -First 1

        if ($extractedDir) {
            Move-Item -Path $extractedDir.FullName -Destination $installPath -Force
        } else {
            Move-Item -Path $tempPath -Destination $installPath -Force
        }

        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        # ワークスペースディレクトリ作成
        if ($workspace -and -not (Test-Path $workspace)) {
            New-Item -ItemType Directory -Path $workspace -Force | Out-Null
            Write-Log "ワークスペースディレクトリを作成: $workspace"
        }

        Write-Log "結果: SUCCESS (新規インストール)" -Level "SUCCESS"
        return @{
            Status = "SUCCESS"
            Path = $installPath
            Version = $version
            Workspace = $workspace
        }
    }
    catch {
        Write-Log "インストールエラー: $_" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }
}

Export-ModuleMember -Function Install-Eclipse
```

**Step 2: Install-WebLogic.ps1を作成**

```powershell
# scripts/modules/Install-WebLogic.ps1
# WebLogicインストールモジュール

function Install-WebLogic {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [hashtable]$ToolConfig
    )

    Write-LogSection "WebLogic"

    $version = $ToolConfig.version
    $fileName = $ToolConfig.file
    $toolFolder = $Settings.tools.weblogic

    Write-Log "要求バージョン: $version"

    # インストール先パス
    $installPath = Join-Path $Settings.installBasePath "weblogic" $version
    Write-Log "インストール先: $installPath"

    # 既存バージョンチェック
    if (Test-Path $installPath) {
        Write-Log "結果: SKIPPED (既存バージョン: $version)" -Level "SKIPPED"
        return @{
            Status = "SKIPPED"
            Path = $installPath
            Version = $version
        }
    }

    # ZIPファイルパス
    $zipPath = Join-Path $Settings.shareBasePath $toolFolder $fileName

    if (-not (Test-Path $zipPath)) {
        Write-Log "ZIPファイルが見つかりません: $zipPath" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }

    # ZIP展開
    Write-Log "ZIPファイルを展開中: $zipPath"

    $parentPath = Join-Path $Settings.installBasePath "weblogic"
    if (-not (Test-Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    try {
        $tempPath = Join-Path $parentPath "_temp_weblogic"
        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force

        $extractedDir = Get-ChildItem -Path $tempPath -Directory | Select-Object -First 1

        if ($extractedDir) {
            Move-Item -Path $extractedDir.FullName -Destination $installPath -Force
        } else {
            Move-Item -Path $tempPath -Destination $installPath -Force
        }

        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Write-Log "結果: SUCCESS (新規インストール)" -Level "SUCCESS"
        return @{
            Status = "SUCCESS"
            Path = $installPath
            Version = $version
        }
    }
    catch {
        Write-Log "インストールエラー: $_" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }
}

Export-ModuleMember -Function Install-WebLogic
```

**Step 3: Install-Gradle.ps1を作成**

```powershell
# scripts/modules/Install-Gradle.ps1
# Gradleインストールモジュール

function Install-Gradle {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [hashtable]$ToolConfig
    )

    Write-LogSection "Gradle"

    $version = $ToolConfig.version
    $fileName = $ToolConfig.file
    $toolFolder = $Settings.tools.gradle

    Write-Log "要求バージョン: $version"

    # インストール先パス
    $installPath = Join-Path $Settings.installBasePath "gradle" $version
    Write-Log "インストール先: $installPath"

    # 既存バージョンチェック
    if (Test-Path $installPath) {
        Write-Log "結果: SKIPPED (既存バージョン: $version)" -Level "SKIPPED"
        return @{
            Status = "SKIPPED"
            Path = $installPath
            Version = $version
        }
    }

    # ZIPファイルパス
    $zipPath = Join-Path $Settings.shareBasePath $toolFolder $fileName

    if (-not (Test-Path $zipPath)) {
        Write-Log "ZIPファイルが見つかりません: $zipPath" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }

    # ZIP展開
    Write-Log "ZIPファイルを展開中: $zipPath"

    $parentPath = Join-Path $Settings.installBasePath "gradle"
    if (-not (Test-Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    try {
        $tempPath = Join-Path $parentPath "_temp_gradle"
        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force

        $extractedDir = Get-ChildItem -Path $tempPath -Directory | Select-Object -First 1

        if ($extractedDir) {
            Move-Item -Path $extractedDir.FullName -Destination $installPath -Force
        } else {
            Move-Item -Path $tempPath -Destination $installPath -Force
        }

        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Write-Log "結果: SUCCESS (新規インストール)" -Level "SUCCESS"
        return @{
            Status = "SUCCESS"
            Path = $installPath
            Version = $version
        }
    }
    catch {
        Write-Log "インストールエラー: $_" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }
}

Export-ModuleMember -Function Install-Gradle
```

**Step 4: コミット**

```bash
git add scripts/modules/Install-Eclipse.ps1 scripts/modules/Install-WebLogic.ps1 scripts/modules/Install-Gradle.ps1
git commit -m "feat: add Eclipse, WebLogic, and Gradle installation modules"
```

---

## Task 6: 起動バッチテンプレート作成

**Files:**
- Create: `templates/start-eclipse.bat.template`

**Step 1: start-eclipse.bat.templateを作成**

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

echo ============================================
echo プロジェクト: {{PROJECT_NAME}}
echo ============================================
echo JAVA_HOME: %JAVA_HOME%
echo GRADLE_HOME: %GRADLE_HOME%
echo WEBLOGIC_HOME: %WEBLOGIC_HOME%
echo ============================================
echo.

start "" "{{ECLIPSE_PATH}}\eclipse.exe" -data "{{WORKSPACE_PATH}}"
```

**Step 2: コミット**

```bash
git add templates/start-eclipse.bat.template
git commit -m "feat: add startup batch template"
```

---

## Task 7: メインスクリプト作成

**Files:**
- Create: `scripts/Install-DevEnv.ps1`

**Step 1: Install-DevEnv.ps1を作成**

```powershell
# scripts/Install-DevEnv.ps1
# 開発環境パッケージ管理 メインスクリプト

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Project
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# モジュール読み込み
Import-Module (Join-Path $scriptRoot "lib\Common.ps1") -Force
Import-Module (Join-Path $scriptRoot "modules\Install-Jdk.ps1") -Force
Import-Module (Join-Path $scriptRoot "modules\Install-Eclipse.ps1") -Force
Import-Module (Join-Path $scriptRoot "modules\Install-WebLogic.ps1") -Force
Import-Module (Join-Path $scriptRoot "modules\Install-Gradle.ps1") -Force
Import-Module (Join-Path $scriptRoot "modules\Install-Certificate.ps1") -Force

# 設定ファイル読み込み
$configRoot = Join-Path (Split-Path $scriptRoot -Parent) "config"
$settingsPath = Join-Path $configRoot "settings.json"
$projectPath = Join-Path $configRoot "projects" "$Project.json"

if (-not (Test-Path $settingsPath)) {
    Write-Error "設定ファイルが見つかりません: $settingsPath"
    exit 1
}

if (-not (Test-Path $projectPath)) {
    Write-Error "プロジェクト設定が見つかりません: $projectPath"
    exit 1
}

$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
$projectConfig = Get-Content $projectPath -Raw | ConvertFrom-Json -AsHashtable

# ログ初期化
Initialize-Log -ProjectName $Project -LogBasePath $settings.installBasePath
Write-Log "設定ファイル: $projectPath"

# 結果カウンター
$results = @{
    Success = 0
    Skipped = 0
    Failed = 0
}

function Update-Results {
    param([string]$Status)
    switch ($Status) {
        "SUCCESS" { $script:results.Success++ }
        "SKIPPED" { $script:results.Skipped++ }
        "FAILED"  { $script:results.Failed++ }
    }
}

# 事前チェック
Write-LogSection "事前チェック"

if (-not (Test-SharePath -Path $settings.shareBasePath)) {
    Write-LogSummary -Success 0 -Skipped 0 -Failed 1
    exit 1
}

# JDKインストール
$jdkResult = Install-Jdk -Settings $settings -ToolConfig $projectConfig.tools.jdk
Update-Results -Status $jdkResult.Status

if ($jdkResult.Status -eq "FAILED") {
    Write-Log "JDKのインストールに失敗したため、処理を中断します" -Level "FAILED"
    Write-LogSummary -Success $results.Success -Skipped $results.Skipped -Failed $results.Failed
    exit 1
}

# 証明書インストール（JDKが必要）
if ($projectConfig.certificates -and $projectConfig.certificates.Count -gt 0) {
    $certResult = Install-Certificate -Settings $settings -Certificates $projectConfig.certificates -JavaHome $jdkResult.Path
    if ($certResult.Status -eq "SUCCESS") {
        $results.Success++
    } else {
        $results.Failed++
    }
}

# Gradleインストール
$gradleResult = Install-Gradle -Settings $settings -ToolConfig $projectConfig.tools.gradle
Update-Results -Status $gradleResult.Status

# WebLogicインストール
$weblogicResult = Install-WebLogic -Settings $settings -ToolConfig $projectConfig.tools.weblogic
Update-Results -Status $weblogicResult.Status

# Eclipseインストール
$eclipseResult = Install-Eclipse -Settings $settings -ToolConfig $projectConfig.tools.eclipse
Update-Results -Status $eclipseResult.Status

# 起動バッチ生成
Write-LogSection "起動バッチ生成"

$templatePath = Join-Path (Split-Path $scriptRoot -Parent) "templates" "start-eclipse.bat.template"
$binPath = Join-Path $settings.installBasePath "bin"
$batchPath = Join-Path $binPath "start-$Project.bat"

if (-not (Test-Path $binPath)) {
    New-Item -ItemType Directory -Path $binPath -Force | Out-Null
}

try {
    $template = Get-Content $templatePath -Raw

    $batchContent = $template `
        -replace '\{\{PROJECT_NAME\}\}', $projectConfig.name `
        -replace '\{\{GENERATED_AT\}\}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss") `
        -replace '\{\{JAVA_HOME\}\}', $jdkResult.Path `
        -replace '\{\{GRADLE_HOME\}\}', $gradleResult.Path `
        -replace '\{\{WEBLOGIC_HOME\}\}', $weblogicResult.Path `
        -replace '\{\{ECLIPSE_PATH\}\}', $eclipseResult.Path `
        -replace '\{\{WORKSPACE_PATH\}\}', $eclipseResult.Workspace

    Set-Content -Path $batchPath -Value $batchContent -Encoding UTF8

    Write-Log "起動バッチ: $batchPath"
    Write-Log "結果: SUCCESS" -Level "SUCCESS"
    $results.Success++
}
catch {
    Write-Log "起動バッチ生成エラー: $_" -Level "FAILED"
    $results.Failed++
}

# サマリー出力
Write-LogSummary -Success $results.Success -Skipped $results.Skipped -Failed $results.Failed

if ($results.Failed -gt 0) {
    exit 1
}

Write-Host ""
Write-Host "開発環境を起動するには以下を実行してください:" -ForegroundColor Cyan
Write-Host "  $batchPath" -ForegroundColor Green
```

**Step 2: コミット**

```bash
git add scripts/Install-DevEnv.ps1
git commit -m "feat: add main installation script"
```

---

## Task 8: 最終確認・ドキュメント更新

**Files:**
- Update: `docs/plans/2026-01-27-dev-env-package-management-design.md`

**Step 1: READMEセクションを設計書に追記**

設計書の末尾に「クイックスタート」セクションを追加して使い方を明記。

**Step 2: 最終コミット**

```bash
git add -A
git commit -m "docs: finalize implementation plan"
```
