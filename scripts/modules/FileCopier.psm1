# scripts/modules/FileCopier.psm1
# ファイル/フォルダコピーモジュール（copyタイプ用）
#
# 分岐網羅コメント凡例:
#   [B-XX] = 分岐ポイント番号
#   T: = 真(True)の場合の処理
#   F: = 偽(False)の場合の処理

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

    # [B-01] ソース存在チェック
    #   T: コピー処理へ続行
    #   F: エラーログ出力、失敗結果を返して終了
    if (-not (Test-Path $SourcePath)) {
        Write-Log -Message "コピー元が存在しません: $SourcePath" -Level "ERROR"
        return @{
            Success = $false
            Skipped = $false
        }
    }

    # ファイルかフォルダか自動判定（PSIsContainer=True: フォルダ）
    $isDirectory = (Get-Item $SourcePath).PSIsContainer

    # [B-02] コピー先存在チェック
    #   T: ハッシュ比較またはバックアップ処理へ
    #   F: バックアップをスキップ、コピー実行へ
    if (Test-Path $DestinationPath) {
        # [B-03] ファイル/フォルダ判定
        #   T(ファイル): ハッシュ比較でスキップ判定
        #   F(フォルダ): ハッシュ比較をスキップ、バックアップへ
        if (-not $isDirectory) {
            $sourceHash = Get-FileHashSHA256 -FilePath $SourcePath -OperationName "ハッシュ計算中(共有)"
            $destHash = Get-FileHashSHA256 -FilePath $DestinationPath -OperationName "ハッシュ計算中(ローカル)"

            # [B-04] ハッシュ一致判定
            #   T: スキップ結果を返して終了（コピー不要）
            #   F: バックアップ後、コピー実行へ
            if ($sourceHash -eq $destHash) {
                Write-Log -Message "ハッシュ一致のためスキップ" -Level "INFO"
                return @{
                    Success = $true
                    Skipped = $true
                }
            }
        }

        # バックアップ処理
        Write-Log -Message "既存をバックアップします: $DestinationPath" -Level "INFO"

        # [B-05] バックアップディレクトリ存在チェック
        #   T: ディレクトリ作成をスキップ
        #   F: タイムスタンプ付きディレクトリを新規作成
        $backupDir = Join-Path $BackupRoot $Timestamp
        if (-not (Test-Path $backupDir)) {
            # [B-06] バックアップディレクトリ作成例外処理
            #   T(try成功): 続行
            #   F(catch):   エラーログ出力、失敗結果を返す
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

        # [B-07] ファイル/フォルダ移動例外処理
        #   T(try成功): 続行
        #   F(catch):   エラーログ出力、失敗結果を返す
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

    # [B-08] コピー先親ディレクトリ存在チェック
    #   T: ディレクトリ作成をスキップ
    #   F: 親ディレクトリを新規作成
    $destDir = Split-Path $DestinationPath -Parent
    if (-not (Test-Path $destDir)) {
        # [B-09] ディレクトリ作成例外処理
        #   T(try成功): 続行
        #   F(catch):   エラーログ出力、失敗結果を返す
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

    # [B-10] コピー実行例外処理
    #   T(try成功): 成功結果を返す
    #   F(catch):   エラーログ出力、失敗結果を返す
    try {
        # [B-11] コピー方式判定
        #   T(フォルダ): -Recurse オプション付きでコピー
        #   F(ファイル): 単一ファイルコピー
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
