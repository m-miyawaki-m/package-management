# scripts/Clone-Repositories.ps1
# Gitリポジトリクローンスクリプト（単独実行可）

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,
    [Parameter(Mandatory)]
    [SecureString]$AccessToken
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# モジュール読み込み
Import-Module (Join-Path $scriptRoot "modules\Logger.psm1") -Force

# 設定ファイル読み込み
if (-not (Test-Path $ConfigPath)) {
    Write-Error "設定ファイルが見つかりません: $ConfigPath"
    exit 1
}

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ログ初期化
Initialize-Log -LogRoot $config.defaults.logRoot

Write-Log -Message "=== Gitリポジトリクローン ===" -Level "INFO"

# Git確認
try {
    $gitVersion = & git --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Message "Gitがインストールされていません" -Level "FATAL"
        exit 1
    }
    Write-Log -Message "Git: $gitVersion" -Level "INFO"
}
catch {
    Write-Log -Message "Gitの確認に失敗しました: $_" -Level "FATAL"
    exit 1
}

# トークンを平文に変換
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccessToken)
$tokenPlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

# リポジトリクローン
$successCount = 0
$failCount = 0

foreach ($repo in $config.repositories) {
    Write-LogSection -ToolName $repo.name

    Write-Log -Message "URL: $($repo.url)" -Level "INFO"
    Write-Log -Message "クローン先: $($repo.destination)" -Level "INFO"

    # 既存チェック
    if (Test-Path $repo.destination) {
        Write-Log -Message "既に存在します。スキップします。" -Level "SKIPPED"
        Add-Result -ToolName $repo.name -Type "copy" -Status "SKIPPED" -Note "既存"
        continue
    }

    # クローン先ディレクトリの親を作成
    $parentDir = Split-Path $repo.destination -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # URLにトークンを埋め込み
    $authUrl = $repo.url -replace "https://", "https://${tokenPlainText}@"

    try {
        Write-Log -Message "クローン中..." -Level "INFO"

        $cloneResult = & git clone $authUrl $repo.destination 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "クローン完了" -Level "SUCCESS"
            Add-Result -ToolName $repo.name -Type "copy" -Status "SUCCESS"
            $successCount++
        }
        else {
            Write-Log -Message "クローン失敗: $cloneResult" -Level "ERROR"
            Add-Result -ToolName $repo.name -Type "copy" -Status "FAILED" -Note "clone失敗"
            $failCount++
        }
    }
    catch {
        Write-Log -Message "エラー: $_" -Level "ERROR"
        Add-Result -ToolName $repo.name -Type "copy" -Status "FAILED" -Note "例外"
        $failCount++
    }
}

# トークンをクリア
$tokenPlainText = $null

# サマリー
Write-Summary

Write-Log -Message "クローン完了: 成功=$successCount, 失敗=$failCount" -Level "INFO"

if ($failCount -gt 0) {
    exit 1
}
exit 0
