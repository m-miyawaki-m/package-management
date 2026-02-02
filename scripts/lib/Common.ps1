# scripts/lib/Common.ps1
# 共通関数モジュール

$script:LogFile = $null

function Initialize-Log {
    <#
    .SYNOPSIS
        ログを初期化
    #>
    param(
        [Parameter(Mandatory)]
        [string]$LogBasePath
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logDir = Join-Path $LogBasePath "logs"

    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $script:LogFile = Join-Path $logDir "install-$timestamp.log"

    Write-Log "================================================================================"
    Write-Log "開発環境パッケージ インストール開始"
    Write-Log "日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "ログファイル: $($script:LogFile)"
    Write-Log "================================================================================"
}

function Write-Log {
    <#
    .SYNOPSIS
        ログ出力（コンソール＋ファイル）
    #>
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
    <#
    .SYNOPSIS
        セクションヘッダを出力
    #>
    param([string]$SectionName)
    Write-Log ""
    Write-Log "=== $SectionName ==="
}

function Write-LogSummary {
    <#
    .SYNOPSIS
        サマリーを出力
    #>
    param(
        [int]$Success,
        [int]$Skipped,
        [int]$Failed
    )
    Write-Log ""
    Write-Log "================================================================================"
    Write-Log "インストール完了"
    Write-Log "成功: $Success, スキップ: $Skipped, 失敗: $Failed"
    Write-Log "================================================================================"
}

function Test-SharePath {
    <#
    .SYNOPSIS
        共有パスの接続確認
    #>
    param([string]$Path)

    if (Test-Path $Path) {
        Write-Log "共有ディレクトリ接続確認: OK ($Path)"
        return $true
    } else {
        Write-Log "共有ディレクトリに接続できません: $Path" -Level "FAILED"
        return $false
    }
}

Export-ModuleMember -Function Initialize-Log, Write-Log, Write-LogSection, Write-LogSummary, Test-SharePath
