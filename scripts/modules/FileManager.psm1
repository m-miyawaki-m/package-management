# scripts/modules/FileManager.psm1
# ファイル取得・ハッシュ比較・バックアップモジュール

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

        while (($read = $stream.Read($buffer, 0, $bufferSize)) -gt 0) {
            $sha256.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
            $totalRead += $read

            # 進行度表示（5秒経過 かつ 5%以上変化）
            $currentPercent = [math]::Round(($totalRead / $fileSize) * 100)
            $elapsed = (Get-Date) - $script:LastProgressTime

            if ($elapsed.TotalSeconds -ge 5 -and ($currentPercent - $script:LastProgressPercent) -ge 5) {
                Write-LogProgress -Operation $OperationName -CurrentBytes $totalRead -TotalBytes $fileSize
                $script:LastProgressTime = Get-Date
                $script:LastProgressPercent = $currentPercent
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

    $sourceInfo = Get-Item $Source
    $fileSize = $sourceInfo.Length

    # コピー先ディレクトリ作成
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

        while (($read = $sourceStream.Read($buffer, 0, $bufferSize)) -gt 0) {
            $destStream.Write($buffer, 0, $read)
            $totalRead += $read

            # 進行度表示（5秒経過 かつ 5%以上変化）
            $currentPercent = [math]::Round(($totalRead / $fileSize) * 100)
            $elapsed = (Get-Date) - $script:LastProgressTime

            if ($elapsed.TotalSeconds -ge 5 -and ($currentPercent - $script:LastProgressPercent) -ge 5) {
                Write-LogProgress -Operation $OperationName -CurrentBytes $totalRead -TotalBytes $fileSize
                $script:LastProgressTime = Get-Date
                $script:LastProgressPercent = $currentPercent
            }
        }

        # 100%表示
        Write-LogProgress -Operation $OperationName -CurrentBytes $fileSize -TotalBytes $fileSize

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

    if (-not (Test-Path $FilePath)) {
        return $false
    }

    $backupDir = Join-Path $BackupRoot $Timestamp
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $backupPath = Join-Path $backupDir $fileName

    Move-Item -Path $FilePath -Destination $backupPath -Force
    Write-Log -Message "バックアップ: $FilePath → $backupPath" -Level "INFO"

    return $true
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

    if (-not (Test-Path $FolderPath)) {
        return @{
            Success = $false
            Error = "フォルダが存在しません: $FolderPath"
        }
    }

    $files = Get-ChildItem -Path $FolderPath -File

    if ($ExcludeFile) {
        $files = $files | Where-Object { $_.Name -ne $ExcludeFile }
    }

    if ($files.Count -eq 0) {
        return @{
            Success = $false
            Error = "フォルダ内にファイルがありません: $FolderPath"
        }
    }

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

    try {
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
