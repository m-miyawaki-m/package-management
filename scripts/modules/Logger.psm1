# scripts/modules/Logger.psm1
# ログ出力モジュール

# スクリプトスコープ変数
$script:LogFile = $null
$script:SummaryFile = $null
$script:StartTime = $null
$script:Results = [System.Collections.Generic.List[hashtable]]::new()

function Initialize-Log {
    <#
    .SYNOPSIS
        ログを初期化
    .DESCRIPTION
        ログディレクトリを作成し、ログファイルとサマリーファイルのパスを設定する
    .PARAMETER LogRoot
        ログファイルの出力先ルートディレクトリ
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogRoot
    )

    $script:StartTime = Get-Date
    $timestamp = $script:StartTime.ToString("yyyyMMdd-HHmmss")

    # ログディレクトリ作成
    if (-not (Test-Path $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    }

    $script:LogFile = Join-Path $LogRoot "install-$timestamp.log"
    $script:SummaryFile = Join-Path $LogRoot "summary-$timestamp.txt"
    $script:Results = [System.Collections.Generic.List[hashtable]]::new()

    # ヘッダー出力
    Write-Log "================================================================================" -Level "INFO" -IsSection
    Write-Log "[$($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))] インストール開始" -Level "INFO"
    Write-Log "================================================================================" -Level "INFO" -IsSection
}

function Write-Log {
    <#
    .SYNOPSIS
        ログメッセージを出力
    .DESCRIPTION
        コンソールに色付きで出力し、同時にログファイルにも出力する
    .PARAMETER Message
        出力するメッセージ
    .PARAMETER Level
        ログレベル (INFO/SUCCESS/SKIPPED/WARNING/ERROR/FATAL)
    .PARAMETER IsSection
        セクション区切り線の場合はtrue（シアン色で出力）
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "SKIPPED", "WARNING", "ERROR", "FATAL")]
        [string]$Level = "INFO",

        [switch]$IsSection
    )

    # ログレベルプレフィックス（区切り線以外）
    $logPrefix = ""
    if (-not $IsSection -and $Message -notmatch "^=+$" -and $Message -notmatch "^-+$" -and $Message -notmatch "^\[.*\]") {
        $logPrefix = "[$Level]`t"
    }

    $logMessage = "$logPrefix$Message"

    # コンソール出力（色分け）
    if ($IsSection -or $Message -match "^=+$" -or $Message -match "^-+$") {
        Write-Host $logMessage -ForegroundColor Cyan
    } else {
        switch ($Level) {
            "INFO"    { Write-Host $logMessage -ForegroundColor White }
            "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
            "SKIPPED" { Write-Host $logMessage -ForegroundColor Yellow }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
            "FATAL"   { Write-Host $logMessage -ForegroundColor White -BackgroundColor Red }
            default   { Write-Host $logMessage }
        }
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
    .DESCRIPTION
        ツール名を囲んだセクションヘッダを出力する
    .PARAMETER ToolName
        ツール名
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName
    )

    Write-Log "--------------------------------------------------------------------------------" -Level "INFO" -IsSection
    Write-Log "=== $ToolName ===" -Level "INFO" -IsSection
}

function Write-LogProgress {
    <#
    .SYNOPSIS
        進行度を出力
    .DESCRIPTION
        ファイル取得やハッシュ計算の進行度をログ形式で出力する
    .PARAMETER Operation
        操作名（例: "ファイル取得中", "ハッシュ計算中"）
    .PARAMETER CurrentBytes
        現在のバイト数
    .PARAMETER TotalBytes
        合計バイト数
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [long]$CurrentBytes,

        [Parameter(Mandatory)]
        [long]$TotalBytes
    )

    # MB単位に変換
    $currentMB = [math]::Round($CurrentBytes / 1MB, 0)
    $totalMB = [math]::Round($TotalBytes / 1MB, 0)

    # パーセント計算
    $percent = 0
    if ($TotalBytes -gt 0) {
        $percent = [math]::Round(($CurrentBytes / $TotalBytes) * 100, 0)
    }

    $progressMessage = "$Operation... ${currentMB}MB / ${totalMB}MB (${percent}%)"
    Write-Log $progressMessage -Level "INFO"
}

function Add-Result {
    <#
    .SYNOPSIS
        結果エントリを追加
    .DESCRIPTION
        サマリー用の結果エントリを追加する
    .PARAMETER ToolName
        ツール名
    .PARAMETER Type
        インストール方式 (installer/extract/copy)
    .PARAMETER Status
        結果ステータス (SUCCESS/SKIPPED/FAILED)
    .PARAMETER LocalVersion
        ローカルバージョン（不明の場合は "-"）
    .PARAMETER SharedVersion
        共有バージョン（不明の場合は "-"）
    .PARAMETER Note
        備考
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [ValidateSet("installer", "extract", "copy")]
        [string]$Type,

        [Parameter(Mandatory)]
        [ValidateSet("SUCCESS", "SKIPPED", "FAILED")]
        [string]$Status,

        [string]$LocalVersion = "-",

        [string]$SharedVersion = "-",

        [string]$Note = ""
    )

    $script:Results.Add(@{
        ToolName = $ToolName
        Type = $Type
        Status = $Status
        LocalVersion = $LocalVersion
        SharedVersion = $SharedVersion
        Note = $Note
    })
}

function Write-Summary {
    <#
    .SYNOPSIS
        サマリーテーブルを出力
    .DESCRIPTION
        全結果のサマリーテーブルをコンソールとファイルに出力し、集計結果を返す
    .OUTPUTS
        hashtable - Success, Skipped, Failed のカウント
    #>
    [CmdletBinding()]
    param()

    $endTime = Get-Date

    # 集計
    $successCount = @($script:Results | Where-Object { $_.Status -eq "SUCCESS" }).Count
    $skippedCount = @($script:Results | Where-Object { $_.Status -eq "SKIPPED" }).Count
    $failedCount = @($script:Results | Where-Object { $_.Status -eq "FAILED" }).Count

    # サマリー内容を構築
    $summaryLines = @()
    $summaryLines += "インストール実行日時: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss')) - $($endTime.ToString('HH:mm:ss'))"
    $summaryLines += ""
    $summaryLines += "+----------------+------------+----------------+----------------+----------+------------------+"
    $summaryLines += "| ツール名       | 方式       | ローカルVer    | 共有Ver        | 結果     | 備考             |"
    $summaryLines += "+----------------+------------+----------------+----------------+----------+------------------+"

    foreach ($result in $script:Results) {
        $toolName = $result.ToolName.PadRight(14).Substring(0, 14)
        $type = $result.Type.PadRight(10).Substring(0, 10)
        $localVer = $result.LocalVersion.PadRight(14).Substring(0, 14)
        $sharedVer = $result.SharedVersion.PadRight(14).Substring(0, 14)
        $status = $result.Status.PadRight(8).Substring(0, 8)
        $note = if ($result.Note.Length -gt 16) { $result.Note.Substring(0, 16) } else { $result.Note.PadRight(16) }

        $summaryLines += "| $toolName | $type | $localVer | $sharedVer | $status | $note |"
    }

    $summaryLines += "+----------------+------------+----------------+----------------+----------+------------------+"
    $summaryLines += ""
    $summaryLines += "集計:"
    $summaryLines += "  SUCCESS: ${successCount}件"
    $summaryLines += "  SKIPPED: ${skippedCount}件 (ハッシュ一致のためスキップ)"
    $summaryLines += "  FAILED:  ${failedCount}件"

    # フッター
    Write-Log "================================================================================" -Level "INFO" -IsSection
    Write-Log "[$($endTime.ToString('yyyy-MM-dd HH:mm:ss'))] インストール完了" -Level "INFO"
    Write-Log "================================================================================" -Level "INFO" -IsSection
    Write-Log "" -Level "INFO"

    # サマリーをコンソールとログに出力
    foreach ($line in $summaryLines) {
        Write-Log $line -Level "INFO"
    }

    # サマリーファイルに出力
    if ($script:SummaryFile) {
        $summaryLines | Out-File -FilePath $script:SummaryFile -Encoding UTF8
    }

    # 集計結果を返す
    return @{
        Success = $successCount
        Skipped = $skippedCount
        Failed = $failedCount
    }
}

# 関数をエクスポート
Export-ModuleMember -Function Initialize-Log, Write-Log, Write-LogSection, Write-LogProgress, Add-Result, Write-Summary
