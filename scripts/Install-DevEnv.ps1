# scripts/Install-DevEnv.ps1
# 開発環境パッケージ管理 メインスクリプト

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# モジュール読み込み
. (Join-Path $scriptRoot "lib\Common.ps1")
. (Join-Path $scriptRoot "lib\StepHandlers.ps1")

# 設定ファイル読み込み
if (-not (Test-Path $ConfigPath)) {
    Write-Error "設定ファイルが見つかりません: $ConfigPath"
    exit 1
}

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$defaults = $config.defaults

# ログ初期化
Initialize-Log -LogBasePath $defaults.destBase
Write-Log "設定ファイル: $ConfigPath"

# 結果カウンター
$results = @{
    Success = 0
    Skipped = 0
    Failed = 0
}

# 共有ディレクトリ接続確認
Write-LogSection "事前チェック"

if (-not (Test-SharePath -Path $defaults.sourceBase)) {
    Write-LogSummary -Success 0 -Skipped 0 -Failed 1
    exit 1
}

# ツールループ
foreach ($tool in $config.tools) {
    Write-LogSection "$($tool.name) v$($tool.version)"

    $toolSourceBase = if ($tool.sourceBase) { $tool.sourceBase } else { $null }
    $toolFailed = $false

    # Stepループ
    $stepIndex = 0
    foreach ($step in $tool.steps) {
        $stepIndex++
        $stepType = $step.type

        Write-Log "[$stepIndex/$($tool.steps.Count)] $stepType"

        $stepResult = $null

        switch ($stepType) {
            "extract" {
                $stepResult = Invoke-ExtractStep -Step $step -Defaults $defaults -ToolSourceBase $toolSourceBase
            }
            "installer" {
                $stepResult = Invoke-InstallerStep -Step $step -Defaults $defaults -ToolSourceBase $toolSourceBase
            }
            "config" {
                $stepResult = Invoke-ConfigStep -Step $step -Defaults $defaults -ToolSourceBase $toolSourceBase
            }
            "env" {
                $stepResult = Invoke-EnvStep -Step $step -Defaults $defaults
            }
            "cert" {
                $stepResult = Invoke-CertStep -Step $step -Defaults $defaults -ToolSourceBase $toolSourceBase
            }
            default {
                Write-Log "  エラー: 未知のstepタイプ: $stepType" -Level "FAILED"
                $stepResult = @{ Success = $false; Message = "未知のstepタイプ" }
            }
        }

        # 結果カウント
        if ($stepResult.Success) {
            if ($stepResult.Skipped) {
                $results.Skipped++
            } else {
                $results.Success++
            }
        } else {
            $results.Failed++
            $toolFailed = $true
            Write-Log "  ツール '$($tool.name)' の残りのstepをスキップします" -Level "WARN"
            break
        }
    }

    if ($toolFailed) {
        Write-Log "[$($tool.name)] 失敗" -Level "FAILED"
    } else {
        Write-Log "[$($tool.name)] 完了" -Level "SUCCESS"
    }
}

# サマリー出力
Write-LogSummary -Success $results.Success -Skipped $results.Skipped -Failed $results.Failed

if ($results.Failed -gt 0) {
    exit 1
}

exit 0
