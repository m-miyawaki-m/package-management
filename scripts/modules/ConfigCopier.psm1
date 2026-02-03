# scripts/modules/ConfigCopier.psm1
# 設定ファイルコピーモジュール（環境変数展開対応）

function Copy-ConfigFile {
    <#
    .SYNOPSIS
        設定ファイルをコピー（環境変数展開対応）
    .DESCRIPTION
        設定ファイルをソースからコピー先にコピーする。
        コピー先パスに含まれる環境変数（%APPDATA%など）を自動展開する。
        コピー先に既存ファイルがある場合はバックアップを作成する。
    .PARAMETER SourcePath
        コピー元の設定ファイルパス
    .PARAMETER DestinationPath
        コピー先パス（環境変数を含むことが可能）
    .PARAMETER BackupRoot
        バックアップルートディレクトリ
    .PARAMETER Timestamp
        タイムスタンプ（バックアップサブディレクトリ名として使用）
    .OUTPUTS
        bool - コピー成功時は$true、失敗時は$false
    .EXAMPLE
        Copy-ConfigFile -SourcePath "C:\source\config.xml" -DestinationPath "%APPDATA%\App\config.xml" -BackupRoot "C:\backup" -Timestamp "20240101-120000"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        [string]$Timestamp
    )

    # 環境変数を展開
    $expandedDestination = [Environment]::ExpandEnvironmentVariables($DestinationPath)

    Write-Log -Message "設定ファイルコピー: $SourcePath → $expandedDestination" -Level "INFO"

    # ソースファイル確認
    if (-not (Test-Path $SourcePath)) {
        Write-Log -Message "設定ファイルが存在しません: $SourcePath" -Level "ERROR"
        return $false
    }

    # コピー先フォルダ作成
    $destDir = Split-Path $expandedDestination -Parent
    if (-not (Test-Path $destDir)) {
        Write-Log -Message "コピー先フォルダを作成: $destDir" -Level "INFO"
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # 既存ファイルがある場合はバックアップ
    if (Test-Path $expandedDestination) {
        Write-Log -Message "既存ファイルをバックアップします" -Level "INFO"

        $backupDir = Join-Path $BackupRoot $Timestamp
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        $fileName = [System.IO.Path]::GetFileName($expandedDestination)
        $backupPath = Join-Path $backupDir $fileName

        Move-Item -Path $expandedDestination -Destination $backupPath -Force
        Write-Log -Message "バックアップ完了: $backupPath" -Level "INFO"
    }

    # コピー実行
    try {
        Copy-Item -Path $SourcePath -Destination $expandedDestination -Force
        Write-Log -Message "設定ファイルコピー完了" -Level "INFO"
        return $true
    }
    catch {
        Write-Log -Message "コピーエラー: $_" -Level "ERROR"
        return $false
    }
}

Export-ModuleMember -Function Copy-ConfigFile
