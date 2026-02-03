# scripts/modules/ConfigCopier.psm1
# 設定ファイルコピーモジュール（環境変数展開対応）
#
# 分岐網羅コメント凡例:
#   [B-XX] = 分岐ポイント番号
#   T: = 真(True)の場合の処理
#   F: = 偽(False)の場合の処理

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

    # 環境変数を展開（%APPDATA%等 → 実パス）
    $expandedDestination = [Environment]::ExpandEnvironmentVariables($DestinationPath)

    Write-Log -Message "設定ファイルコピー: $SourcePath → $expandedDestination" -Level "INFO"

    # [B-01] ソースファイル存在チェック
    #   T: コピー処理へ続行
    #   F: エラーログ出力、$false を返して終了
    if (-not (Test-Path $SourcePath)) {
        Write-Log -Message "設定ファイルが存在しません: $SourcePath" -Level "ERROR"
        return $false
    }

    # [B-02] コピー先ディレクトリ存在チェック
    #   T: ディレクトリ作成をスキップ
    #   F: 親ディレクトリを新規作成
    $destDir = Split-Path $expandedDestination -Parent
    if (-not (Test-Path $destDir)) {
        Write-Log -Message "コピー先フォルダを作成: $destDir" -Level "INFO"
        # [B-03] ディレクトリ作成例外処理
        #   T(try成功): 続行
        #   F(catch):   エラーログ出力、$false を返す
        try {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        catch {
            Write-Log -Message "フォルダ作成エラー: $_" -Level "ERROR"
            return $false
        }
    }

    # [B-04] 既存ファイル存在チェック
    #   T: バックアップ後、コピー実行
    #   F: バックアップをスキップ、コピー実行へ
    if (Test-Path $expandedDestination) {
        Write-Log -Message "既存ファイルをバックアップします" -Level "INFO"

        # [B-05] バックアップディレクトリ存在チェック
        #   T: ディレクトリ作成をスキップ
        #   F: タイムスタンプ付きディレクトリを新規作成
        $backupDir = Join-Path $BackupRoot $Timestamp
        if (-not (Test-Path $backupDir)) {
            # [B-06] バックアップディレクトリ作成例外処理
            #   T(try成功): 続行
            #   F(catch):   エラーログ出力、$false を返す
            try {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }
            catch {
                Write-Log -Message "バックアップフォルダ作成エラー: $_" -Level "ERROR"
                return $false
            }
        }

        # ファイル名にパス情報を含めて一意性を確保（衝突回避）
        $parentDir = Split-Path (Split-Path $expandedDestination -Parent) -Leaf
        $fileName = [System.IO.Path]::GetFileName($expandedDestination)
        $backupFileName = "${parentDir}_${fileName}"
        $backupPath = Join-Path $backupDir $backupFileName

        # [B-07] ファイル移動例外処理
        #   T(try成功): 続行
        #   F(catch):   エラーログ出力、$false を返す
        try {
            Move-Item -Path $expandedDestination -Destination $backupPath -Force
            Write-Log -Message "バックアップ完了: $backupPath" -Level "INFO"
        }
        catch {
            Write-Log -Message "バックアップエラー: $_" -Level "ERROR"
            return $false
        }
    }

    # [B-08] コピー実行例外処理
    #   T(try成功): $true を返す
    #   F(catch):   エラーログ出力、$false を返す
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
