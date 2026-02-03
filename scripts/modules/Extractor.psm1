# scripts/modules/Extractor.psm1
# 7z/zip解凍モジュール
#
# 分岐網羅コメント凡例:
#   [B-XX] = 分岐ポイント番号
#   T: = 真(True)の場合の処理
#   F: = 偽(False)の場合の処理

function Invoke-Extract {
    <#
    .SYNOPSIS
        アーカイブを解凍
    .DESCRIPTION
        7z/zipアーカイブを指定ディレクトリに解凍する。
        解凍先が既に存在する場合は、事前にバックアップを作成する。
        .zipファイルで7z.exeが存在しない場合はExpand-Archiveを使用する。
        それ以外の場合は7z.exeを使用して解凍する。
    .PARAMETER ArchivePath
        解凍するアーカイブファイルのパス
    .PARAMETER Destination
        解凍先ディレクトリのパス
    .PARAMETER SevenZipPath
        7z.exeのパス
    .PARAMETER BackupRoot
        バックアップルートディレクトリ
    .PARAMETER Timestamp
        タイムスタンプ（バックアップサブディレクトリ名として使用）
    .OUTPUTS
        bool - 解凍成功時は$true、失敗時は$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$SevenZipPath,

        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        [string]$Timestamp
    )

    # [B-01] アーカイブ存在チェック
    #   T: 解凍処理へ続行
    #   F: エラーログ出力、$false を返して終了
    if (-not (Test-Path $ArchivePath)) {
        Write-Log -Message "アーカイブが存在しません: $ArchivePath" -Level "ERROR"
        return $false
    }

    # [B-02] 解凍先ディレクトリ存在チェック
    #   T: 既存ディレクトリをバックアップ後、解凍処理へ
    #   F: バックアップをスキップ
    if (Test-Path $Destination) {
        Write-Log -Message "既存ディレクトリをバックアップします: $Destination" -Level "INFO"

        $backupResult = Backup-Directory -DirectoryPath $Destination -BackupRoot $BackupRoot -Timestamp $Timestamp -SevenZipPath $SevenZipPath
        # [B-03] バックアップ結果チェック
        #   T: 解凍処理へ続行
        #   F: エラーログ出力、$false を返して終了
        if (-not $backupResult) {
            Write-Log -Message "バックアップに失敗しました" -Level "ERROR"
            return $false
        }
    }

    # [B-04] 解凍先親ディレクトリ存在チェック
    #   T: ディレクトリ作成をスキップ
    #   F: 親ディレクトリを新規作成
    $parentDir = Split-Path $Destination -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # ファイルサイズ取得
    $archiveInfo = Get-Item $ArchivePath
    $sizeMB = [math]::Round($archiveInfo.Length / 1MB)

    Write-Log -Message "解凍中... (${sizeMB}MB)" -Level "INFO"

    # 7z.exe または Expand-Archive を使用
    $extension = [System.IO.Path]::GetExtension($ArchivePath).ToLower()

    # [B-05] 解凍方式判定
    #   条件: .zipファイル かつ 7z.exe不存在
    #   T: PowerShell標準のExpand-Archiveを使用
    #   F: 7z.exeを使用（7zファイルまたは7z.exe存在時）
    if ($extension -eq ".zip" -and -not (Test-Path $SevenZipPath)) {
        # [B-06] Expand-Archive例外処理
        #   T(try成功): $true を返す
        #   F(catch):   エラーログ出力、$false を返す
        try {
            Expand-Archive -Path $ArchivePath -DestinationPath $Destination -Force
            Write-Log -Message "解凍完了" -Level "INFO"
            return $true
        }
        catch {
            Write-Log -Message "解凍エラー: $_" -Level "ERROR"
            return $false
        }
    }
    else {
        # [B-07] 7z.exe存在チェック
        #   T: 7z.exeで解凍処理へ続行
        #   F: エラーログ出力、$false を返して終了
        if (-not (Test-Path $SevenZipPath)) {
            Write-Log -Message "7z.exeが見つかりません: $SevenZipPath" -Level "ERROR"
            return $false
        }

        # [B-08] 7z.exe実行例外処理
        #   T(try成功): 終了コード判定へ
        #   F(catch):   エラーログ出力、$false を返す
        try {
            $arguments = "x `"$ArchivePath`" -o`"$Destination`" -y"
            $process = Start-Process -FilePath $SevenZipPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

            # [B-09] 7z.exe終了コード判定
            #   T(ExitCode=0): $true を返す
            #   F(その他):     エラーログ出力、$false を返す
            if ($process.ExitCode -eq 0) {
                Write-Log -Message "解凍完了" -Level "INFO"
                return $true
            }
            else {
                Write-Log -Message "7z.exe エラー: exit code $($process.ExitCode)" -Level "ERROR"
                return $false
            }
        }
        catch {
            Write-Log -Message "解凍エラー: $_" -Level "ERROR"
            return $false
        }
    }
}

function Backup-Directory {
    <#
    .SYNOPSIS
        ディレクトリを圧縮してバックアップ
    .DESCRIPTION
        指定ディレクトリを7z（またはzip）形式で圧縮し、バックアップディレクトリに保存後、
        元ディレクトリを削除する。
        7z.exeが存在する場合は7z形式、存在しない場合はzip形式で圧縮する。
        バックアップファイル名: ディレクトリ名-タイムスタンプ.7z（または.zip）
    .PARAMETER DirectoryPath
        バックアップするディレクトリのパス
    .PARAMETER BackupRoot
        バックアップルートディレクトリ
    .PARAMETER Timestamp
        タイムスタンプ（バックアップサブディレクトリ名およびファイル名に使用）
    .PARAMETER SevenZipPath
        7z.exeのパス
    .OUTPUTS
        bool - バックアップ成功時は$true、失敗時は$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath,

        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        [string]$Timestamp,

        [Parameter(Mandatory)]
        [string]$SevenZipPath
    )

    # [B-10] バックアップ対象ディレクトリ存在チェック
    #   T: バックアップ処理へ続行
    #   F: $true を返して終了（バックアップ不要）
    if (-not (Test-Path $DirectoryPath)) {
        return $true
    }

    # [B-11] バックアップディレクトリ存在チェック
    #   T: ディレクトリ作成をスキップ
    #   F: タイムスタンプ付きディレクトリを新規作成
    $backupDir = Join-Path $BackupRoot $Timestamp
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $dirName = [System.IO.Path]::GetFileName($DirectoryPath)
    $backupFileName = "$dirName-$Timestamp.7z"
    $backupPath = Join-Path $backupDir $backupFileName

    Write-Log -Message "ディレクトリを圧縮してバックアップ: $backupPath" -Level "INFO"

    # [B-12] 圧縮方式判定
    #   T: 7z.exeで7z形式に圧縮
    #   F: PowerShell標準でzip形式に圧縮
    if (Test-Path $SevenZipPath) {
        # [B-13] 7z.exe圧縮例外処理
        #   T(try成功): 終了コード判定へ
        #   F(catch):   エラーログ出力、$false を返す
        try {
            $arguments = "a `"$backupPath`" `"$DirectoryPath`" -mx=1"
            $process = Start-Process -FilePath $SevenZipPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

            # [B-14] 7z.exe終了コード判定
            #   T(ExitCode≠0): エラーログ出力、$false を返す
            #   F(ExitCode=0): 圧縮成功、元ディレクトリ削除へ
            if ($process.ExitCode -ne 0) {
                Write-Log -Message "圧縮エラー: exit code $($process.ExitCode)" -Level "ERROR"
                return $false
            }
        }
        catch {
            Write-Log -Message "圧縮エラー: $_" -Level "ERROR"
            return $false
        }
    }
    else {
        # [B-15] Compress-Archive例外処理
        #   T(try成功): 圧縮成功、元ディレクトリ削除へ
        #   F(catch):   エラーログ出力、$false を返す
        $backupPath = Join-Path $backupDir "$dirName-$Timestamp.zip"
        try {
            Compress-Archive -Path $DirectoryPath -DestinationPath $backupPath -Force
        }
        catch {
            Write-Log -Message "圧縮エラー: $_" -Level "ERROR"
            return $false
        }
    }

    # 元ディレクトリ削除
    Remove-Item -Path $DirectoryPath -Recurse -Force
    Write-Log -Message "バックアップ完了: $backupPath" -Level "INFO"

    return $true
}

# 関数をエクスポート
Export-ModuleMember -Function Invoke-Extract, Backup-Directory
