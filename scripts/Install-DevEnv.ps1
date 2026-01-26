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
