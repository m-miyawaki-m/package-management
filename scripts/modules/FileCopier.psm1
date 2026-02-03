# scripts/modules/FileCopier.psm1
# ファイル/フォルダコピーモジュール（copyタイプ用）

function Copy-ToolFiles {
    <#
    .SYNOPSIS
        ファイルまたはフォルダをコピー（copyタイプツール用）
    .DESCRIPTION
        ソースからコピー先にファイルまたはフォルダをコピーする。
        ソースがファイルかフォルダかを自動判定し、適切な方法でコピーする。
        ファイルの場合はハッシュ比較を行い、一致すればスキップする。
        コピー先に既存ファイル/フォルダがある場合はバックアップを作成する。
    .PARAMETER SourcePath
        コピー元のファイルまたはフォルダのパス
    .PARAMETER DestinationPath
        コピー先のパス
    .PARAMETER BackupRoot
        バックアップルートディレクトリ
    .PARAMETER Timestamp
        タイムスタンプ（バックアップサブディレクトリ名として使用）
    .OUTPUTS
        hashtable - @{Success=$true/$false, Skipped=$true/$false}
    .EXAMPLE
        Copy-ToolFiles -SourcePath "\\share\tools\app" -DestinationPath "C:\tools\app" -BackupRoot "C:\backup" -Timestamp "20240101-120000"
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

    # ソース確認
    if (-not (Test-Path $SourcePath)) {
        Write-Log -Message "コピー元が存在しません: $SourcePath" -Level "ERROR"
        return @{
            Success = $false
            Skipped = $false
        }
    }

    # ファイルかフォルダか自動判定
    $isDirectory = (Get-Item $SourcePath).PSIsContainer

    # コピー先が存在する場合の処理
    if (Test-Path $DestinationPath) {
        if (-not $isDirectory) {
            # ファイルの場合はハッシュ比較
            $sourceHash = Get-FileHashSHA256 -FilePath $SourcePath -OperationName "ハッシュ計算中(共有)"
            $destHash = Get-FileHashSHA256 -FilePath $DestinationPath -OperationName "ハッシュ計算中(ローカル)"

            if ($sourceHash -eq $destHash) {
                Write-Log -Message "ハッシュ一致のためスキップ" -Level "INFO"
                return @{
                    Success = $true
                    Skipped = $true
                }
            }
        }

        # バックアップ
        Write-Log -Message "既存をバックアップします: $DestinationPath" -Level "INFO"

        $backupDir = Join-Path $BackupRoot $Timestamp
        if (-not (Test-Path $backupDir)) {
            try {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }
            catch {
                Write-Log -Message "バックアップフォルダ作成エラー: $_" -Level "ERROR"
                return @{
                    Success = $false
                    Skipped = $false
                }
            }
        }

        $itemName = [System.IO.Path]::GetFileName($DestinationPath)
        $backupPath = Join-Path $backupDir $itemName

        try {
            Move-Item -Path $DestinationPath -Destination $backupPath -Force
            Write-Log -Message "バックアップ完了: $backupPath" -Level "INFO"
        }
        catch {
            Write-Log -Message "バックアップエラー: $_" -Level "ERROR"
            return @{
                Success = $false
                Skipped = $false
            }
        }
    }

    # コピー先ディレクトリ作成
    $destDir = Split-Path $DestinationPath -Parent
    if (-not (Test-Path $destDir)) {
        try {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        catch {
            Write-Log -Message "コピー先フォルダ作成エラー: $_" -Level "ERROR"
            return @{
                Success = $false
                Skipped = $false
            }
        }
    }

    # コピー実行
    try {
        if ($isDirectory) {
            Copy-Item -Path $SourcePath -Destination $DestinationPath -Recurse -Force
        }
        else {
            Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
        }
        Write-Log -Message "コピー完了" -Level "INFO"
        return @{
            Success = $true
            Skipped = $false
        }
    }
    catch {
        Write-Log -Message "コピーエラー: $_" -Level "ERROR"
        return @{
            Success = $false
            Skipped = $false
        }
    }
}

Export-ModuleMember -Function Copy-ToolFiles
