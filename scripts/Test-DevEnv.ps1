# scripts/Test-DevEnv.ps1
# 開発環境検証スクリプト（スタンドアロン）

<#
.SYNOPSIS
    インストール済みの開発環境を検証
.DESCRIPTION
    JDK, Gradle, Eclipse, WebLogic のインストール状態を確認し、
    バージョン情報を表示します。
.PARAMETER Project
    プロジェクト名（config/projects/<name>.json に対応）
.EXAMPLE
    .\Test-DevEnv.ps1 -Project sample
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Project
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# モジュール読み込み
Import-Module (Join-Path $scriptRoot "lib\Common.ps1") -Force
Import-Module (Join-Path $scriptRoot "lib\Validation.ps1") -Force

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

# ログ初期化（検証用）
Initialize-Log -ProjectName "$Project-verify" -LogBasePath $settings.installBasePath
Write-Log "プロジェクト: $Project"
Write-Log "検証開始"

# パス生成
$jdkPath = Join-Path $settings.installBasePath "jdk" $projectConfig.tools.jdk.version
$gradlePath = Join-Path $settings.installBasePath "gradle" $projectConfig.tools.gradle.version
$eclipsePath = Join-Path $settings.installBasePath "eclipse" $projectConfig.tools.eclipse.version
$weblogicPath = Join-Path $settings.installBasePath "weblogic" $projectConfig.tools.weblogic.version

# 検証実行
$result = Test-AllInstallations `
    -JdkPath $jdkPath `
    -GradlePath $gradlePath `
    -EclipsePath $eclipsePath `
    -WebLogicPath $weblogicPath

# 結果サマリー
Write-Log ""
Write-Log "================================================================================"
Write-Log "検証結果サマリー"
Write-Log "================================================================================"

$validCount = 0
$invalidCount = 0

# JDK
if ($result.Jdk) {
    if ($result.Jdk.Valid) {
        Write-Log "[OK] JDK: $($result.Jdk.Version)" -Level "SUCCESS"
        $validCount++
    } else {
        Write-Log "[NG] JDK: $($result.Jdk.Message)" -Level "FAILED"
        $invalidCount++
    }
}

# Gradle
if ($result.Gradle) {
    if ($result.Gradle.Valid) {
        Write-Log "[OK] Gradle: $($result.Gradle.Version)" -Level "SUCCESS"
        $validCount++
    } else {
        Write-Log "[NG] Gradle: $($result.Gradle.Message)" -Level "FAILED"
        $invalidCount++
    }
}

# Eclipse
if ($result.Eclipse) {
    if ($result.Eclipse.Valid) {
        Write-Log "[OK] Eclipse: $($result.Eclipse.Version)" -Level "SUCCESS"
        $validCount++
    } else {
        Write-Log "[NG] Eclipse: $($result.Eclipse.Message)" -Level "FAILED"
        $invalidCount++
    }
}

# WebLogic
if ($result.WebLogic) {
    if ($result.WebLogic.Valid) {
        Write-Log "[OK] WebLogic: $($result.WebLogic.Version)" -Level "SUCCESS"
        $validCount++
    } else {
        Write-Log "[NG] WebLogic: $($result.WebLogic.Message)" -Level "FAILED"
        $invalidCount++
    }
}

Write-Log "================================================================================"
Write-Log "合計: OK=$validCount, NG=$invalidCount"
Write-Log "================================================================================"

if ($invalidCount -gt 0) {
    Write-Host ""
    Write-Host "検証に失敗した項目があります。再インストールを検討してください。" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host ""
    Write-Host "すべての検証に成功しました。" -ForegroundColor Green
    exit 0
}
