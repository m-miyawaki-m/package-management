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
