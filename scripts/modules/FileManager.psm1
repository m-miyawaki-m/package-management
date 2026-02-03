# scripts/modules/FileManager.psm1
# ファイル取得・ハッシュ比較・バックアップモジュール
#
# 分岐網羅コメント凡例:
#   [B-XX] = 分岐ポイント番号
#   T: = 真(True)の場合の処理
#   F: = 偽(False)の場合の処理

# スクリプトスコープ変数
$script:LastProgressTime = $null
$script:LastProgressPercent = 0

function Get-FileHashSHA256 {
    <#
    .SYNOPSIS
        ファイルのSHA256ハッシュを計算
    .DESCRIPTION
        指定ファイルのSHA256ハッシュ値を計算する。
        大きなファイルの場合は進行度を表示する（5秒経過 かつ 5%以上変化の条件）。
        4MBバッファを使用して効率的に処理する。
    .PARAMETER FilePath
        ハッシュを計算するファイルのパス
    .PARAMETER OperationName
        進行度表示に使用する操作名（デフォルト: "ハッシュ計算中"）
    .OUTPUTS
        string - SHA256ハッシュ値（大文字16進数）、ファイルが存在しない場合は$null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string]$OperationName = "ハッシュ計算中"
    )

    # [B-01] ファイル存在チェック
    #   T: ハッシュ計算処理へ続行
    #   F: $null を返して終了（ファイルなし）
    if (-not (Test-Path $FilePath)) {
        return $null
    }

    $fileInfo = Get-Item $FilePath
    $fileSize = $fileInfo.Length

    # 進行度表示のリセット
    $script:LastProgressTime = Get-Date
    $script:LastProgressPercent = 0

    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()

        $bufferSize = 4MB
        $buffer = New-Object byte[] $bufferSize
        $totalRead = 0

        # [B-02] ファイル読み込みループ（バッファ単位）
        #   条件: 読み込みバイト数 > 0
        #   T: バッファをハッシュ計算に追加し、次のチャンクへ
        #   F: ループ終了（ファイル末尾到達）
        while (($read = $stream.Read($buffer, 0, $bufferSize)) -gt 0) {
            $sha256.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
            $totalRead += $read

            # [B-03] ゼロ除算防止チェック
            #   T: 進行度計算と表示判定へ
            #   F: 進行度表示をスキップ
            if ($fileSize -gt 0) {
                $currentPercent = [math]::Round(($totalRead / $fileSize) * 100)
                $elapsed = (Get-Date) - $script:LastProgressTime

                # [B-04] 進行度表示条件判定
                #   条件: 5秒以上経過 かつ 5%以上変化
                #   T: 進行度をログ出力し、時刻とパーセントを更新
                #   F: 進行度表示をスキップ（頻繁な出力を抑制）
                if ($elapsed.TotalSeconds -ge 5 -and ($currentPercent - $script:LastProgressPercent) -ge 5) {
                    Write-LogProgress -Operation $OperationName -CurrentBytes $totalRead -TotalBytes $fileSize
                    $script:LastProgressTime = Get-Date
                    $script:LastProgressPercent = $currentPercent
                }
            }
        }

        $sha256.TransformFinalBlock($buffer, 0, 0) | Out-Null
        $hash = [BitConverter]::ToString($sha256.Hash) -replace '-', ''

        return $hash
    }
    finally {
        if ($stream) { $stream.Close() }
        if ($sha256) { $sha256.Dispose() }
    }
}

function Copy-FileWithProgress {
    <#
    .SYNOPSIS
        進行度表示付きでファイルをコピー
    .DESCRIPTION
        ソースファイルをコピー先にコピーする。
        大きなファイルの場合は進行度を表示する（5秒経過 かつ 5%以上変化の条件）。
        4MBバッファを使用して効率的に処理する。
        コピー先ディレクトリが存在しない場合は自動作成する。
    .PARAMETER Source
        コピー元ファイルのパス
    .PARAMETER Destination
        コピー先ファイルのパス
    .PARAMETER OperationName
        進行度表示に使用する操作名（デフォルト: "ファイル取得中"）
    .OUTPUTS
        bool - コピー成功時は$true、失敗時は$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [string]$OperationName = "ファイル取得中"
    )

    # [B-05] ソースファイル存在チェック
    #   T: コピー処理へ続行
    #   F: エラーログ出力、$false を返して終了
    if (-not (Test-Path $Source)) {
        Write-Log -Message "ソースファイルが存在しません: $Source" -Level "ERROR"
        return $false
    }

    $sourceInfo = Get-Item $Source
    $fileSize = $sourceInfo.Length

    # [B-06] コピー先ディレクトリ存在チェック
    #   T: ディレクトリ作成をスキップ
    #   F: 親ディレクトリを新規作成
    $destDir = Split-Path $Destination -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # 進行度表示のリセット
    $script:LastProgressTime = Get-Date
    $script:LastProgressPercent = 0

    try {
        $sourceStream = [System.IO.File]::OpenRead($Source)
        $destStream = [System.IO.File]::Create($Destination)

        $bufferSize = 4MB
        $buffer = New-Object byte[] $bufferSize
        $totalRead = 0

        # [B-07] ファイルコピーループ（バッファ単位）
        #   条件: 読み込みバイト数 > 0
        #   T: バッファをコピー先に書き込み、次のチャンクへ
        #   F: ループ終了（ファイル末尾到達）
        while (($read = $sourceStream.Read($buffer, 0, $bufferSize)) -gt 0) {
            $destStream.Write($buffer, 0, $read)
            $totalRead += $read

            # [B-08] ゼロ除算防止チェック
            #   T: 進行度計算と表示判定へ
            #   F: 進行度表示をスキップ
            if ($fileSize -gt 0) {
                $currentPercent = [math]::Round(($totalRead / $fileSize) * 100)
                $elapsed = (Get-Date) - $script:LastProgressTime

                # [B-09] 進行度表示条件判定
                #   条件: 5秒以上経過 かつ 5%以上変化
                #   T: 進行度をログ出力し、時刻とパーセントを更新
                #   F: 進行度表示をスキップ（頻繁な出力を抑制）
                if ($elapsed.TotalSeconds -ge 5 -and ($currentPercent - $script:LastProgressPercent) -ge 5) {
                    Write-LogProgress -Operation $OperationName -CurrentBytes $totalRead -TotalBytes $fileSize
                    $script:LastProgressTime = Get-Date
                    $script:LastProgressPercent = $currentPercent
                }
            }
        }

        # [B-10] 完了時100%表示判定
        #   T: 100%表示を出力
        #   F: 0バイトファイルの場合は表示しない
        if ($fileSize -gt 0) {
            Write-LogProgress -Operation $OperationName -CurrentBytes $fileSize -TotalBytes $fileSize
        }

        return $true
    }
    catch {
        Write-Log -Message "ファイルコピーエラー: $_" -Level "ERROR"
        return $false
    }
    finally {
        if ($sourceStream) { $sourceStream.Close() }
        if ($destStream) { $destStream.Close() }
    }
}

function Backup-File {
    <#
    .SYNOPSIS
        ファイルをバックアップディレクトリに移動
    .DESCRIPTION
        指定ファイルをバックアップルート配下のタイムスタンプディレクトリに移動する。
        バックアップパス: $BackupRoot/$Timestamp/filename
    .PARAMETER FilePath
        バックアップするファイルのパス
    .PARAMETER BackupRoot
        バックアップルートディレクトリ
    .PARAMETER Timestamp
        タイムスタンプ（サブディレクトリ名として使用）
    .OUTPUTS
        bool - バックアップ成功時は$true、ファイルが存在しない場合は$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        [string]$Timestamp
    )

    # [B-11] バックアップ対象ファイル存在チェック
    #   T: バックアップ処理へ続行
    #   F: $false を返して終了（バックアップ不要）
    if (-not (Test-Path $FilePath)) {
        return $false
    }

    # [B-12] バックアップディレクトリ存在チェック
    #   T: ディレクトリ作成をスキップ
    #   F: タイムスタンプ付きディレクトリを新規作成
    $backupDir = Join-Path $BackupRoot $Timestamp
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $backupPath = Join-Path $backupDir $fileName

    # [B-13] ファイル移動例外処理
    #   T(try成功): $true を返す
    #   F(catch):   エラーログ出力、$false を返す
    try {
        Move-Item -Path $FilePath -Destination $backupPath -Force
        Write-Log -Message "バックアップ: $FilePath → $backupPath" -Level "INFO"
        return $true
    }
    catch {
        Write-Log -Message "バックアップエラー: $_" -Level "ERROR"
        return $false
    }
}

function Get-SingleFileFromFolder {
    <#
    .SYNOPSIS
        フォルダから単一ファイルを取得
    .DESCRIPTION
        指定フォルダ内のファイルを取得する。
        ファイルが0件または複数件の場合はエラーを返す。
        特定ファイルを除外することも可能。
    .PARAMETER FolderPath
        検索対象フォルダのパス
    .PARAMETER ExcludeFile
        除外するファイル名（オプション）
    .OUTPUTS
        hashtable - @{Success=$true, File=FileInfo} または @{Success=$false, Error="エラーメッセージ"}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,

        [string]$ExcludeFile = $null
    )

    # [B-14] フォルダ存在チェック
    #   T: ファイル取得処理へ続行
    #   F: エラー結果を返して終了
    if (-not (Test-Path $FolderPath)) {
        return @{
            Success = $false
            Error = "フォルダが存在しません: $FolderPath"
        }
    }

    $files = Get-ChildItem -Path $FolderPath -File

    # [B-15] 除外ファイル指定チェック
    #   T: 指定ファイルをリストから除外
    #   F: 除外処理をスキップ
    if ($ExcludeFile) {
        $files = $files | Where-Object { $_.Name -ne $ExcludeFile }
    }

    # [B-16] ファイル0件チェック
    #   T: エラー結果を返して終了
    #   F: ファイル数判定へ続行
    if ($files.Count -eq 0) {
        return @{
            Success = $false
            Error = "フォルダ内にファイルがありません: $FolderPath"
        }
    }

    # [B-17] ファイル複数件チェック
    #   T: エラー結果を返して終了（曖昧性回避）
    #   F: 単一ファイルを返す
    if ($files.Count -gt 1) {
        return @{
            Success = $false
            Error = "フォルダ内に複数ファイルが存在します: $FolderPath ($($files.Count)件)"
        }
    }

    return @{
        Success = $true
        File = $files[0]
    }
}

function Test-ShareAccess {
    <#
    .SYNOPSIS
        共有ディレクトリへのアクセス可否をテスト
    .DESCRIPTION
        指定パスにアクセス可能かどうかをテストする。
        ネットワーク共有やローカルパスの疎通確認に使用する。
    .PARAMETER SharePath
        テスト対象のパス
    .OUTPUTS
        bool - アクセス可能な場合は$true、不可の場合は$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SharePath
    )

    # [B-18] 共有アクセス例外処理
    #   T(try成功): Test-Path結果を返す
    #   F(catch):   $false を返す（アクセス不可）
    try {
        # [B-19] パス存在チェック
        #   T: $true を返す（アクセス可能）
        #   F: $false を返す（パス不存在）
        if (Test-Path $SharePath) {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# 関数をエクスポート
Export-ModuleMember -Function Get-FileHashSHA256, Copy-FileWithProgress, Backup-File, Get-SingleFileFromFolder, Test-ShareAccess
