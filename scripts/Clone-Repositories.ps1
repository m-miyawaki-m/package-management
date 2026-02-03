# scripts/Clone-Repositories.ps1
# Gitリポジトリクローンスクリプト（単独実行可）
#
# 分岐網羅コメント凡例:
#   [B-XX] = 分岐ポイント番号
#   T: = 真(True)の場合の処理
#   F: = 偽(False)の場合の処理

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

# [B-01] 設定ファイル存在チェック
#   T: 設定読み込み処理へ続行
#   F: エラー出力、exit 1 で終了
if (-not (Test-Path $ConfigPath)) {
    Write-Error "設定ファイルが見つかりません: $ConfigPath"
    exit 1
}

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ログ初期化
Initialize-Log -LogRoot $config.defaults.logRoot

Write-Log -Message "=== Gitリポジトリクローン ===" -Level "INFO"

# [B-02] Gitコマンド確認例外処理
#   T(try成功): 終了コード判定へ
#   F(catch):   FATALログ出力、exit 1 で終了
try {
    $gitVersion = & git --version 2>&1
    # [B-03] Git終了コード判定
    #   T(≠0): FATALログ出力、exit 1 で終了
    #   F(=0): バージョン出力、続行
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

# トークンを平文に変換（SecureString → String）
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccessToken)
$tokenPlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

# リポジトリクローン
$successCount = 0
$failCount = 0

# [B-04] リポジトリループ
foreach ($repo in $config.repositories) {
    Write-LogSection -ToolName $repo.name

    Write-Log -Message "URL: $($repo.url)" -Level "INFO"
    Write-Log -Message "クローン先: $($repo.destination)" -Level "INFO"

    # [B-05] クローン先存在チェック
    #   T: SKIPPEDログ出力、次のリポジトリへ(continue)
    #   F: クローン処理へ続行
    if (Test-Path $repo.destination) {
        Write-Log -Message "既に存在します。スキップします。" -Level "SKIPPED"
        Add-Result -ToolName $repo.name -Type "copy" -Status "SKIPPED" -Note "既存"
        continue
    }

    # [B-06] 親ディレクトリ存在チェック
    #   T: ディレクトリ作成をスキップ
    #   F: 親ディレクトリを新規作成
    $parentDir = Split-Path $repo.destination -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # URLにトークンを埋め込み（認証用）
    $authUrl = $repo.url -replace "https://", "https://${tokenPlainText}@"

    # [B-07] git clone例外処理
    #   T(try成功): 終了コード判定へ
    #   F(catch):   エラーログ出力、失敗カウント加算
    try {
        Write-Log -Message "クローン中..." -Level "INFO"

        $cloneResult = & git clone $authUrl $repo.destination 2>&1

        # [B-08] git clone終了コード判定
        #   T(=0): SUCCESS設定、成功カウント加算
        #   F(≠0): FAILED設定、失敗カウント加算
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

# トークンをクリア（セキュリティ対策）
$tokenPlainText = $null

# サマリー
Write-Summary

Write-Log -Message "クローン完了: 成功=$successCount, 失敗=$failCount" -Level "INFO"

# [B-09] 終了コード判定
#   T: exit 1（失敗あり）
#   F: exit 0（すべて成功またはスキップ）
if ($failCount -gt 0) {
    exit 1
}
exit 0
