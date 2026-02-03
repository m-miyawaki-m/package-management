# 開発環境パッケージインストーラー 実装計画

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 共有ディレクトリから開発ツールを取得し、ローカル環境に自動インストールするPowerShell 5.1スクリプトシステムを構築する

**Architecture:** バッチファイルをエントリポイントとし、Main.ps1が統括。各機能はモジュール（.psm1）に分離。tools.jsonで設定を外部化し、柔軟なツール管理を実現。

**Tech Stack:** PowerShell 5.1, バッチファイル, JSON, 7-Zip

**設計書:** `docs/plans/2026-02-03-package-installer-design.md`

---

## Task 1: Logger.psm1 - ログ出力モジュール

**Files:**
- Create: `scripts/modules/Logger.psm1`

**Step 1: モジュールファイル作成**

```powershell
# scripts/modules/Logger.psm1
# ログ出力モジュール

$script:LogFile = $null
$script:SummaryFile = $null
$script:StartTime = $null
$script:Results = @()

function Initialize-Log {
    param(
        [Parameter(Mandatory)]
        [string]$LogRoot
    )

    # ログディレクトリ作成
    if (-not (Test-Path $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    }

    $script:StartTime = Get-Date
    $timestamp = $script:StartTime.ToString("yyyyMMdd-HHmmss")
    $script:LogFile = Join-Path $LogRoot "install-$timestamp.log"
    $script:SummaryFile = Join-Path $LogRoot "summary-$timestamp.txt"
    $script:Results = @()

    # ログファイル初期化
    $header = "=" * 80
    $startMessage = "[$($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))] インストール開始"

    Add-Content -Path $script:LogFile -Value $header -Encoding UTF8
    Add-Content -Path $script:LogFile -Value $startMessage -Encoding UTF8
    Add-Content -Path $script:LogFile -Value $header -Encoding UTF8

    Write-Host $header -ForegroundColor Cyan
    Write-Host $startMessage
    Write-Host $header -ForegroundColor Cyan
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "SKIPPED", "WARNING", "ERROR", "FATAL")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$Level] $Message"

    # ファイル出力
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8
    }

    # コンソール出力（色分け）
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "SKIPPED" { "Yellow" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        "FATAL"   { "Red" }
        default   { "White" }
    }

    if ($Level -eq "FATAL") {
        Write-Host $logMessage -ForegroundColor White -BackgroundColor Red
    } else {
        Write-Host $logMessage -ForegroundColor $color
    }
}

function Write-LogSection {
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    $separator = "-" * 80
    $sectionHeader = "=== $Title ==="

    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $separator -Encoding UTF8
        Add-Content -Path $script:LogFile -Value "[INFO]  $sectionHeader" -Encoding UTF8
    }

    Write-Host $separator -ForegroundColor Cyan
    Write-Host "[INFO]  $sectionHeader" -ForegroundColor Cyan
}

function Write-LogProgress {
    param(
        [Parameter(Mandatory)]
        [string]$Operation,
        [Parameter(Mandatory)]
        [long]$Current,
        [Parameter(Mandatory)]
        [long]$Total
    )

    $percent = [math]::Round(($Current / $Total) * 100)
    $currentMB = [math]::Round($Current / 1MB)
    $totalMB = [math]::Round($Total / 1MB)

    $message = "$Operation... ${currentMB}MB / ${totalMB}MB ($percent%)"
    Write-Log -Message $message -Level "INFO"
}

function Add-Result {
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,
        [Parameter(Mandatory)]
        [string]$Type,
        [Parameter(Mandatory)]
        [ValidateSet("SUCCESS", "SKIPPED", "FAILED")]
        [string]$Status,
        [string]$LocalVersion = "-",
        [string]$SharedVersion = "-",
        [string]$Note = ""
    )

    $script:Results += [PSCustomObject]@{
        ToolName = $ToolName
        Type = $Type
        LocalVersion = $LocalVersion
        SharedVersion = $SharedVersion
        Status = $Status
        Note = $Note
    }
}

function Write-Summary {
    $endTime = Get-Date
    $duration = $endTime - $script:StartTime

    $header = "=" * 80
    $endMessage = "[$($endTime.ToString('yyyy-MM-dd HH:mm:ss'))] インストール完了"

    # ログファイルに終了メッセージ
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $header -Encoding UTF8
        Add-Content -Path $script:LogFile -Value $endMessage -Encoding UTF8
        Add-Content -Path $script:LogFile -Value $header -Encoding UTF8
    }

    Write-Host $header -ForegroundColor Cyan
    Write-Host $endMessage
    Write-Host $header -ForegroundColor Cyan

    # サマリーテーブル作成
    $summaryContent = @()
    $summaryContent += "インストール実行日時: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss')) - $($endTime.ToString('HH:mm:ss'))"
    $summaryContent += ""
    $summaryContent += "+" + ("-" * 16) + "+" + ("-" * 12) + "+" + ("-" * 16) + "+" + ("-" * 16) + "+" + ("-" * 10) + "+" + ("-" * 20) + "+"
    $summaryContent += "| ツール名       | 方式       | ローカルVer    | 共有Ver        | 結果     | 備考               |"
    $summaryContent += "+" + ("-" * 16) + "+" + ("-" * 12) + "+" + ("-" * 16) + "+" + ("-" * 16) + "+" + ("-" * 10) + "+" + ("-" * 20) + "+"

    foreach ($result in $script:Results) {
        $line = "| {0,-14} | {1,-10} | {2,-14} | {3,-14} | {4,-8} | {5,-18} |" -f `
            $result.ToolName.Substring(0, [Math]::Min(14, $result.ToolName.Length)),
            $result.Type.Substring(0, [Math]::Min(10, $result.Type.Length)),
            $result.LocalVersion.Substring(0, [Math]::Min(14, $result.LocalVersion.Length)),
            $result.SharedVersion.Substring(0, [Math]::Min(14, $result.SharedVersion.Length)),
            $result.Status,
            $result.Note.Substring(0, [Math]::Min(18, $result.Note.Length))
        $summaryContent += $line
    }

    $summaryContent += "+" + ("-" * 16) + "+" + ("-" * 12) + "+" + ("-" * 16) + "+" + ("-" * 16) + "+" + ("-" * 10) + "+" + ("-" * 20) + "+"
    $summaryContent += ""

    # 集計
    $successCount = ($script:Results | Where-Object { $_.Status -eq "SUCCESS" }).Count
    $skippedCount = ($script:Results | Where-Object { $_.Status -eq "SKIPPED" }).Count
    $failedCount = ($script:Results | Where-Object { $_.Status -eq "FAILED" }).Count

    $summaryContent += "集計:"
    $summaryContent += "  SUCCESS: ${successCount}件"
    $summaryContent += "  SKIPPED: ${skippedCount}件"
    $summaryContent += "  FAILED:  ${failedCount}件"

    # サマリーファイル出力
    if ($script:SummaryFile) {
        $summaryContent | Set-Content -Path $script:SummaryFile -Encoding UTF8
    }

    # コンソール出力
    foreach ($line in $summaryContent) {
        Write-Host $line
    }

    return @{
        Success = $successCount
        Skipped = $skippedCount
        Failed = $failedCount
    }
}

Export-ModuleMember -Function Initialize-Log, Write-Log, Write-LogSection, Write-LogProgress, Add-Result, Write-Summary
```

**Step 2: 動作確認用テストスクリプト作成**

```powershell
# test-logger.ps1（一時ファイル、確認後削除）
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "scripts\modules\Logger.psm1") -Force

$testLogRoot = Join-Path $PSScriptRoot "test-logs"
Initialize-Log -LogRoot $testLogRoot

Write-Log -Message "テストメッセージ INFO" -Level "INFO"
Write-Log -Message "テストメッセージ SUCCESS" -Level "SUCCESS"
Write-Log -Message "テストメッセージ WARNING" -Level "WARNING"
Write-Log -Message "テストメッセージ ERROR" -Level "ERROR"

Write-LogSection -Title "テストセクション"

Add-Result -ToolName "test-tool" -Type "installer" -Status "SUCCESS" -Note "テスト"
Add-Result -ToolName "test-tool2" -Type "extract" -Status "SKIPPED" -Note "スキップ"

Write-Summary

Write-Host "`nテスト完了。test-logsフォルダを確認してください。"
```

**Step 3: 動作確認**

Run: `powershell -ExecutionPolicy Bypass -File test-logger.ps1`
Expected: 色付きログ出力、test-logsフォルダにログファイルとサマリーファイル生成

**Step 4: コミット**

```bash
git add scripts/modules/Logger.psm1
git commit -m "feat: add Logger module with color output and summary"
```

---

## Task 2: FileManager.psm1 - ファイル管理モジュール

**Files:**
- Create: `scripts/modules/FileManager.psm1`

**Step 1: モジュールファイル作成**

```powershell
# scripts/modules/FileManager.psm1
# ファイル取得・ハッシュ比較・バックアップモジュール

$script:LastProgressTime = $null
$script:LastProgressPercent = 0

function Get-FileHashSHA256 {
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
                Write-LogProgress -Operation $OperationName -Current $totalRead -Total $fileSize
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
                Write-LogProgress -Operation $OperationName -Current $totalRead -Total $fileSize
                $script:LastProgressTime = Get-Date
                $script:LastProgressPercent = $currentPercent
            }
        }

        # 100%表示
        Write-LogProgress -Operation $OperationName -Current $fileSize -Total $fileSize

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

Export-ModuleMember -Function Get-FileHashSHA256, Copy-FileWithProgress, Backup-File, Get-SingleFileFromFolder, Test-ShareAccess
```

**Step 2: 動作確認**

```powershell
# test-filemanager.ps1（一時ファイル）
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "scripts\modules\Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "scripts\modules\FileManager.psm1") -Force

Initialize-Log -LogRoot (Join-Path $PSScriptRoot "test-logs")

# テスト用ファイル作成
$testFile = Join-Path $PSScriptRoot "test-file.txt"
"Test content" | Set-Content $testFile

# ハッシュ計算テスト
$hash = Get-FileHashSHA256 -FilePath $testFile
Write-Log "Hash: $hash" -Level "INFO"

# ファイルコピーテスト
$destFile = Join-Path $PSScriptRoot "test-file-copy.txt"
Copy-FileWithProgress -Source $testFile -Destination $destFile

# バックアップテスト
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Backup-File -FilePath $destFile -BackupRoot (Join-Path $PSScriptRoot "test-bk") -Timestamp $timestamp

# クリーンアップ
Remove-Item $testFile -Force
Remove-Item (Join-Path $PSScriptRoot "test-bk") -Recurse -Force

Write-Host "FileManagerテスト完了"
```

**Step 3: コミット**

```bash
git add scripts/modules/FileManager.psm1
git commit -m "feat: add FileManager module with hash and progress support"
```

---

## Task 3: Extractor.psm1 - 解凍モジュール

**Files:**
- Create: `scripts/modules/Extractor.psm1`

**Step 1: モジュールファイル作成**

```powershell
# scripts/modules/Extractor.psm1
# 7z/zip解凍モジュール

function Invoke-Extract {
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

    # アーカイブ存在確認
    if (-not (Test-Path $ArchivePath)) {
        Write-Log -Message "アーカイブが存在しません: $ArchivePath" -Level "ERROR"
        return $false
    }

    # 解凍先が既に存在する場合はバックアップ
    if (Test-Path $Destination) {
        Write-Log -Message "既存ディレクトリをバックアップします: $Destination" -Level "INFO"

        $backupResult = Backup-Directory -DirectoryPath $Destination -BackupRoot $BackupRoot -Timestamp $Timestamp -SevenZipPath $SevenZipPath
        if (-not $backupResult) {
            Write-Log -Message "バックアップに失敗しました" -Level "ERROR"
            return $false
        }
    }

    # 解凍先ディレクトリ作成
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

    if ($extension -eq ".zip" -and -not (Test-Path $SevenZipPath)) {
        # 7z.exeがない場合、.zipはExpand-Archiveを使用
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
        # 7z.exeを使用
        if (-not (Test-Path $SevenZipPath)) {
            Write-Log -Message "7z.exeが見つかりません: $SevenZipPath" -Level "ERROR"
            return $false
        }

        try {
            $arguments = "x `"$ArchivePath`" -o`"$Destination`" -y"
            $process = Start-Process -FilePath $SevenZipPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

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

    if (-not (Test-Path $DirectoryPath)) {
        return $true
    }

    $backupDir = Join-Path $BackupRoot $Timestamp
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $dirName = [System.IO.Path]::GetFileName($DirectoryPath)
    $backupFileName = "$dirName-$Timestamp.7z"
    $backupPath = Join-Path $backupDir $backupFileName

    Write-Log -Message "ディレクトリを圧縮してバックアップ: $backupPath" -Level "INFO"

    if (Test-Path $SevenZipPath) {
        # 7z.exeで圧縮
        try {
            $arguments = "a `"$backupPath`" `"$DirectoryPath`" -mx=1"
            $process = Start-Process -FilePath $SevenZipPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

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
        # 7z.exeがない場合はzipで圧縮
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

Export-ModuleMember -Function Invoke-Extract, Backup-Directory
```

**Step 2: コミット**

```bash
git add scripts/modules/Extractor.psm1
git commit -m "feat: add Extractor module with 7z and backup support"
```

---

## Task 4: Installer.psm1 - インストーラー実行モジュール

**Files:**
- Create: `scripts/modules/Installer.psm1`

**Step 1: モジュールファイル作成**

```powershell
# scripts/modules/Installer.psm1
# exe/msiインストーラー実行・レジストリバージョン確認モジュール

function Get-InstalledVersion {
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    # 64bit/32bit両方のアンインストール情報を検索
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $registryPaths) {
        try {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like "*$DisplayName*" }

            if ($apps) {
                # 最初に見つかったものを返す
                $app = $apps | Select-Object -First 1
                return @{
                    Found = $true
                    Version = $app.DisplayVersion
                    DisplayName = $app.DisplayName
                }
            }
        }
        catch {
            continue
        }
    }

    return @{
        Found = $false
        Version = $null
        DisplayName = $null
    }
}

function Invoke-SilentInstall {
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,
        [Parameter(Mandatory)]
        [string]$SilentArgs,
        [int[]]$SuccessCodes = @(0, 3010)
    )

    if (-not (Test-Path $InstallerPath)) {
        Write-Log -Message "インストーラーが存在しません: $InstallerPath" -Level "ERROR"
        return @{
            Success = $false
            ExitCode = -1
        }
    }

    Write-Log -Message "インストーラー実行: $InstallerPath $SilentArgs" -Level "INFO"

    try {
        $process = Start-Process -FilePath $InstallerPath -ArgumentList $SilentArgs -Wait -PassThru -NoNewWindow
        $exitCode = $process.ExitCode

        if ($exitCode -in $SuccessCodes) {
            Write-Log -Message "インストール完了 (exit code: $exitCode)" -Level "INFO"
            return @{
                Success = $true
                ExitCode = $exitCode
            }
        }
        else {
            Write-Log -Message "インストールエラー (exit code: $exitCode)" -Level "ERROR"
            return @{
                Success = $false
                ExitCode = $exitCode
            }
        }
    }
    catch {
        Write-Log -Message "インストーラー実行エラー: $_" -Level "ERROR"
        return @{
            Success = $false
            ExitCode = -1
        }
    }
}

function Test-VersionMatch {
    param(
        [Parameter(Mandatory)]
        [string]$InstalledVersion,
        [Parameter(Mandatory)]
        [string]$TargetVersion
    )

    # バージョン文字列の正規化（先頭の0や空白を除去）
    $installed = $InstalledVersion.Trim()
    $target = $TargetVersion.Trim()

    # 完全一致
    if ($installed -eq $target) {
        return $true
    }

    # メジャー.マイナー.パッチ形式で比較
    $installedParts = $installed -split '\.'
    $targetParts = $target -split '\.'

    # 最小の長さで比較
    $minLength = [Math]::Min($installedParts.Length, $targetParts.Length)

    for ($i = 0; $i -lt $minLength; $i++) {
        if ($installedParts[$i] -ne $targetParts[$i]) {
            return $false
        }
    }

    return $true
}

Export-ModuleMember -Function Get-InstalledVersion, Invoke-SilentInstall, Test-VersionMatch
```

**Step 2: コミット**

```bash
git add scripts/modules/Installer.psm1
git commit -m "feat: add Installer module with registry version check"
```

---

## Task 5: ConfigCopier.psm1 - 設定ファイルコピーモジュール

**Files:**
- Create: `scripts/modules/ConfigCopier.psm1`

**Step 1: モジュールファイル作成**

```powershell
# scripts/modules/ConfigCopier.psm1
# 設定ファイルコピーモジュール（環境変数展開対応）

function Copy-ConfigFile {
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
```

**Step 2: コミット**

```bash
git add scripts/modules/ConfigCopier.psm1
git commit -m "feat: add ConfigCopier module with env variable expansion"
```

---

## Task 6: FileCopier.psm1 - ファイル/フォルダコピーモジュール

**Files:**
- Create: `scripts/modules/FileCopier.psm1`

**Step 1: モジュールファイル作成**

```powershell
# scripts/modules/FileCopier.psm1
# ファイル/フォルダコピーモジュール（copyタイプ用）

function Copy-ToolFiles {
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

    # コピー先が存在する場合、ハッシュ比較
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
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        $itemName = [System.IO.Path]::GetFileName($DestinationPath)
        $backupPath = Join-Path $backupDir $itemName

        Move-Item -Path $DestinationPath -Destination $backupPath -Force
        Write-Log -Message "バックアップ完了: $backupPath" -Level "INFO"
    }

    # コピー先ディレクトリ作成
    $destDir = Split-Path $DestinationPath -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
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
```

**Step 2: コミット**

```bash
git add scripts/modules/FileCopier.psm1
git commit -m "feat: add FileCopier module with auto file/folder detection"
```

---

## Task 7: Main.ps1 - 統括スクリプト

**Files:**
- Create: `scripts/Main.ps1`

**Step 1: スクリプト作成**

```powershell
# scripts/Main.ps1
# 開発環境パッケージインストーラー 統括スクリプト

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot

# モジュール読み込み
Import-Module (Join-Path $scriptRoot "modules\Logger.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\FileManager.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\Extractor.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\Installer.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\ConfigCopier.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\FileCopier.psm1") -Force

# 設定ファイル読み込み
if (-not (Test-Path $ConfigPath)) {
    Write-Error "設定ファイルが見つかりません: $ConfigPath"
    exit 1
}

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$defaults = $config.defaults

# ログ初期化
Initialize-Log -LogRoot $defaults.logRoot

Write-Log -Message "設定ファイル: $ConfigPath" -Level "INFO"
Write-Log -Message "共有ルート: $($defaults.sourceRoot)" -Level "INFO"
Write-Log -Message "ローカルルート: $($defaults.localRoot)" -Level "INFO"

# 共有ディレクトリアクセスチェック
if (-not (Test-ShareAccess -SharePath $defaults.sourceRoot)) {
    Write-Log -Message "共有ディレクトリにアクセスできません: $($defaults.sourceRoot)" -Level "FATAL"
    exit 1
}

# タイムスタンプ（バックアップ用）
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# ツールごとに処理
foreach ($tool in $config.tools) {
    Write-LogSection -Title $tool.name

    $status = "FAILED"
    $note = ""
    $localVersion = "-"
    $sharedVersion = "-"

    try {
        # 共有フォルダからファイル取得
        $sourceFolderPath = Join-Path $defaults.sourceRoot $tool.source

        # configCopyがある場合は除外ファイルを指定
        $excludeFile = $null
        if ($tool.configCopy) {
            $excludeFile = $tool.configCopy.source
        }

        $fileResult = Get-SingleFileFromFolder -FolderPath $sourceFolderPath -ExcludeFile $excludeFile

        if (-not $fileResult.Success) {
            Write-Log -Message $fileResult.Error -Level "ERROR"
            $note = "ファイル取得エラー"
            Add-Result -ToolName $tool.name -Type $tool.type -Status "FAILED" -Note $note
            continue
        }

        $sourceFile = $fileResult.File
        Write-Log -Message "ソース: $($sourceFile.FullName)" -Level "INFO"

        # ローカルファイルパス
        $localFolder = Join-Path $defaults.localRoot $tool.source
        $localFilePath = Join-Path $localFolder $sourceFile.Name

        # タイプ別処理
        switch ($tool.type) {
            "installer" {
                # バージョン確認（skipVersionCheckでない場合）
                if (-not $tool.skipVersionCheck -and $tool.displayName -and $tool.version) {
                    $installed = Get-InstalledVersion -DisplayName $tool.displayName

                    if ($installed.Found) {
                        $localVersion = $installed.Version
                        $sharedVersion = $tool.version

                        if (Test-VersionMatch -InstalledVersion $installed.Version -TargetVersion $tool.version) {
                            Write-Log -Message "インストール済み (バージョン: $($installed.Version))" -Level "INFO"
                            $status = "SKIPPED"
                            $note = "バージョン一致"
                            break
                        }
                    }
                    $sharedVersion = $tool.version
                }

                # ファイル取得
                $sourceHash = Get-FileHashSHA256 -FilePath $sourceFile.FullName -OperationName "ハッシュ計算中(共有)"
                Write-Log -Message "ハッシュ(共有): $($sourceHash.Substring(0, 16))..." -Level "INFO"

                if (Test-Path $localFilePath) {
                    $localHash = Get-FileHashSHA256 -FilePath $localFilePath -OperationName "ハッシュ計算中(ローカル)"
                    Write-Log -Message "ハッシュ(ローカル): $($localHash.Substring(0, 16))..." -Level "INFO"

                    if ($sourceHash -ne $localHash) {
                        Backup-File -FilePath $localFilePath -BackupRoot $defaults.backupRoot -Timestamp $timestamp
                        Copy-FileWithProgress -Source $sourceFile.FullName -Destination $localFilePath
                    }
                }
                else {
                    Write-Log -Message "ハッシュ(ローカル): なし（新規取得）" -Level "INFO"
                    Copy-FileWithProgress -Source $sourceFile.FullName -Destination $localFilePath
                }

                # インストール実行
                $successCodes = if ($tool.successCodes) { $tool.successCodes } else { $defaults.successCodes }
                $installResult = Invoke-SilentInstall -InstallerPath $localFilePath -SilentArgs $tool.silentArgs -SuccessCodes $successCodes

                if ($installResult.Success) {
                    $status = "SUCCESS"

                    # 7zipが失敗した場合は即停止
                    if ($tool.required -and -not $installResult.Success) {
                        Write-Log -Message "必須ツールのインストールに失敗しました" -Level "FATAL"
                        exit 1
                    }
                }
                else {
                    $status = "FAILED"
                    $note = "exit code: $($installResult.ExitCode)"

                    if ($tool.required) {
                        Write-Log -Message "必須ツールのインストールに失敗しました" -Level "FATAL"
                        exit 1
                    }
                }
            }

            "extract" {
                # ハッシュ比較
                $sourceHash = Get-FileHashSHA256 -FilePath $sourceFile.FullName -OperationName "ハッシュ計算中(共有)"
                Write-Log -Message "ハッシュ(共有): $($sourceHash.Substring(0, 16))..." -Level "INFO"

                $needExtract = $true

                if (Test-Path $localFilePath) {
                    $localHash = Get-FileHashSHA256 -FilePath $localFilePath -OperationName "ハッシュ計算中(ローカル)"
                    Write-Log -Message "ハッシュ(ローカル): $($localHash.Substring(0, 16))..." -Level "INFO"

                    if ($sourceHash -eq $localHash) {
                        # ハッシュ一致、解凍先確認
                        if (Test-Path $tool.destination) {
                            Write-Log -Message "解凍先存在: $($tool.destination)" -Level "INFO"
                            $status = "SKIPPED"
                            $note = "ハッシュ一致"
                            $needExtract = $false
                        }
                        else {
                            Write-Log -Message "ハッシュ一致だが解凍先が存在しません。再解凍します。" -Level "WARNING"
                        }
                    }
                    else {
                        Backup-File -FilePath $localFilePath -BackupRoot $defaults.backupRoot -Timestamp $timestamp
                        Copy-FileWithProgress -Source $sourceFile.FullName -Destination $localFilePath
                    }
                }
                else {
                    Write-Log -Message "ハッシュ(ローカル): なし（新規取得）" -Level "INFO"
                    Copy-FileWithProgress -Source $sourceFile.FullName -Destination $localFilePath
                }

                if ($needExtract) {
                    $extractResult = Invoke-Extract -ArchivePath $localFilePath -Destination $tool.destination -SevenZipPath $defaults."7zPath" -BackupRoot $defaults.backupRoot -Timestamp $timestamp

                    if ($extractResult) {
                        $status = "SUCCESS"
                    }
                    else {
                        $status = "FAILED"
                        $note = "解凍エラー"
                    }
                }

                # configCopy処理
                if ($status -ne "FAILED" -and $tool.configCopy) {
                    $configSourcePath = Join-Path $sourceFolderPath $tool.configCopy.source
                    $configCopyResult = Copy-ConfigFile -SourcePath $configSourcePath -DestinationPath $tool.configCopy.destination -BackupRoot $defaults.backupRoot -Timestamp $timestamp

                    if (-not $configCopyResult) {
                        Write-Log -Message "設定ファイルコピーに失敗しましたが、本体は成功しています" -Level "WARNING"
                    }
                }
            }

            "copy" {
                $copyResult = Copy-ToolFiles -SourcePath $sourceFile.FullName -DestinationPath $tool.destination -BackupRoot $defaults.backupRoot -Timestamp $timestamp

                if ($copyResult.Success) {
                    if ($copyResult.Skipped) {
                        $status = "SKIPPED"
                        $note = "ハッシュ一致"
                    }
                    else {
                        $status = "SUCCESS"
                    }
                }
                else {
                    $status = "FAILED"
                    $note = "コピーエラー"
                }
            }
        }
    }
    catch {
        Write-Log -Message "エラー: $_" -Level "ERROR"
        $status = "FAILED"
        $note = "例外発生"
    }

    # 結果を記録
    Add-Result -ToolName $tool.name -Type $tool.type -Status $status -LocalVersion $localVersion -SharedVersion $sharedVersion -Note $note

    if ($status -eq "SUCCESS") {
        Write-Log -Message "$($tool.name) インストール完了" -Level "SUCCESS"
    }
    elseif ($status -eq "SKIPPED") {
        Write-Log -Message "$($tool.name) スキップ ($note)" -Level "SKIPPED"
    }
    else {
        Write-Log -Message "$($tool.name) 失敗 ($note)" -Level "ERROR"
    }
}

# サマリー出力
$summary = Write-Summary

# 終了コード
if ($summary.Failed -gt 0) {
    exit 1
}
exit 0
```

**Step 2: コミット**

```bash
git add scripts/Main.ps1
git commit -m "feat: add Main.ps1 orchestration script"
```

---

## Task 8: Clone-Repositories.ps1 - Gitクローンスクリプト

**Files:**
- Create: `scripts/Clone-Repositories.ps1`

**Step 1: スクリプト作成**

```powershell
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
    Write-LogSection -Title $repo.name

    Write-Log -Message "URL: $($repo.url)" -Level "INFO"
    Write-Log -Message "クローン先: $($repo.destination)" -Level "INFO"

    # 既存チェック
    if (Test-Path $repo.destination) {
        Write-Log -Message "既に存在します。スキップします。" -Level "SKIPPED"
        Add-Result -ToolName $repo.name -Type "git-clone" -Status "SKIPPED" -Note "既存"
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
            Add-Result -ToolName $repo.name -Type "git-clone" -Status "SUCCESS"
            $successCount++
        }
        else {
            Write-Log -Message "クローン失敗: $cloneResult" -Level "ERROR"
            Add-Result -ToolName $repo.name -Type "git-clone" -Status "FAILED" -Note "clone失敗"
            $failCount++
        }
    }
    catch {
        Write-Log -Message "エラー: $_" -Level "ERROR"
        Add-Result -ToolName $repo.name -Type "git-clone" -Status "FAILED" -Note "例外"
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
```

**Step 2: コミット**

```bash
git add scripts/Clone-Repositories.ps1
git commit -m "feat: add Clone-Repositories.ps1 with token support"
```

---

## Task 9: Set-JavaEnv.ps1 - Java環境変数設定スクリプト

**Files:**
- Create: `scripts/Set-JavaEnv.ps1`

**Step 1: スクリプト作成**

```powershell
# scripts/Set-JavaEnv.ps1
# JDK環境変数設定スクリプト（単独実行可）

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$JavaHome
)

$ErrorActionPreference = "Stop"

Write-Host "=== JDK環境変数設定 ===" -ForegroundColor Cyan

# JAVA_HOME確認
if (-not (Test-Path $JavaHome)) {
    Write-Error "指定されたJAVA_HOMEパスが存在しません: $JavaHome"
    exit 1
}

$javaBin = Join-Path $JavaHome "bin\java.exe"
if (-not (Test-Path $javaBin)) {
    Write-Error "java.exeが見つかりません: $javaBin"
    exit 1
}

# 現在の値を表示
$currentJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

Write-Host "現在のJAVA_HOME: $currentJavaHome"
Write-Host "設定するJAVA_HOME: $JavaHome"

# JAVA_HOME設定
try {
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $JavaHome, "Machine")
    Write-Host "JAVA_HOMEを設定しました" -ForegroundColor Green
}
catch {
    Write-Error "JAVA_HOMEの設定に失敗しました: $_"
    exit 1
}

# PATH設定
$javaBinPath = Join-Path $JavaHome "bin"

if ($currentPath -notlike "*$javaBinPath*") {
    try {
        # 古いJavaパスを除去（もしあれば）
        $pathParts = $currentPath -split ";" | Where-Object {
            $_ -and ($_ -notlike "*\jdk*\bin*") -and ($_ -notlike "*\java*\bin*")
        }

        # 新しいパスを追加
        $newPath = ($pathParts + $javaBinPath) -join ";"

        [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
        Write-Host "PATHに追加しました: $javaBinPath" -ForegroundColor Green
    }
    catch {
        Write-Error "PATHの設定に失敗しました: $_"
        exit 1
    }
}
else {
    Write-Host "PATHには既に含まれています" -ForegroundColor Yellow
}

# 確認
Write-Host ""
Write-Host "設定完了。新しいコマンドプロンプトで以下を実行して確認してください:" -ForegroundColor Cyan
Write-Host "  java -version"
Write-Host "  echo %JAVA_HOME%"

exit 0
```

**Step 2: コミット**

```bash
git add scripts/Set-JavaEnv.ps1
git commit -m "feat: add Set-JavaEnv.ps1 for JAVA_HOME setup"
```

---

## Task 10: Install.bat - エントリポイント

**Files:**
- Create: `Install.bat`

**Step 1: バッチファイル作成**

```batch
@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

:: ========================================
::   開発環境セットアップ
:: ========================================

:: 管理者権限チェック
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 管理者権限が必要です。
    echo 右クリックして「管理者として実行」を選択してください。
    pause
    exit /b 1
)

:: スクリプトのディレクトリ
set "SCRIPT_DIR=%~dp0"
set "CONFIG_PATH=%SCRIPT_DIR%config\tools.json"

:: 設定ファイル確認
if not exist "%CONFIG_PATH%" (
    echo 設定ファイルが見つかりません: %CONFIG_PATH%
    pause
    exit /b 1
)

:: メニュー表示
:menu
cls
echo ========================================
echo   開発環境セットアップ
echo ========================================
echo.
echo 1. インストール + Gitクローン自動実行
echo 2. インストールのみ
echo 3. Gitクローンのみ
echo.
echo ----------------------------------------
set /p choice="選択してください (1-3): "

if "%choice%"=="1" goto install_and_clone
if "%choice%"=="2" goto install_only
if "%choice%"=="3" goto clone_only

echo 無効な選択です。
goto menu

:install_and_clone
:: トークン入力
echo.
set /p "token=Gitアクセストークンを入力してください: "
if "%token%"=="" (
    echo トークンが入力されていません。
    pause
    goto menu
)

:: インストール実行
echo.
echo インストールを開始します...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Main.ps1" -ConfigPath "%CONFIG_PATH%"

if %errorlevel% neq 0 (
    echo.
    echo インストール中にエラーが発生しました。
    pause
    exit /b 1
)

:: クローン実行
echo.
echo Gitクローンを開始します...
powershell -ExecutionPolicy Bypass -Command "& { $token = ConvertTo-SecureString '%token%' -AsPlainText -Force; & '%SCRIPT_DIR%scripts\Clone-Repositories.ps1' -ConfigPath '%CONFIG_PATH%' -AccessToken $token }"

set "token="
goto end

:install_only
echo.
echo インストールを開始します...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Main.ps1" -ConfigPath "%CONFIG_PATH%"
goto end

:clone_only
:: トークン入力
echo.
set /p "token=Gitアクセストークンを入力してください: "
if "%token%"=="" (
    echo トークンが入力されていません。
    pause
    goto menu
)

echo.
echo Gitクローンを開始します...
powershell -ExecutionPolicy Bypass -Command "& { $token = ConvertTo-SecureString '%token%' -AsPlainText -Force; & '%SCRIPT_DIR%scripts\Clone-Repositories.ps1' -ConfigPath '%CONFIG_PATH%' -AccessToken $token }"

set "token="
goto end

:end
echo.
echo ========================================
echo 処理が完了しました。
echo ========================================
pause
exit /b 0
```

**Step 2: コミット**

```bash
git add Install.bat
git commit -m "feat: add Install.bat entry point with menu"
```

---

## Task 11: tools.json サンプル作成

**Files:**
- Modify: `config/tools.json`

**Step 1: サンプル設定ファイル作成**

```json
{
  "defaults": {
    "sourceRoot": "\\\\server\\share\\packages",
    "localRoot": "C:\\packages",
    "destRoot": "C:\\dev-tools",
    "backupRoot": "C:\\packages\\bk",
    "logRoot": "C:\\dev-tools\\logs",
    "7zPath": "C:\\dev-tools\\7zip\\7z.exe",
    "successCodes": [0, 3010]
  },
  "tools": [
    {
      "name": "7zip",
      "type": "installer",
      "source": "7zip",
      "version": "23.01",
      "displayName": "7-Zip",
      "silentArgs": "/S /D=C:\\dev-tools\\7zip",
      "required": true
    },
    {
      "name": "teraterm",
      "type": "installer",
      "source": "teraterm",
      "version": "5.2",
      "displayName": "Tera Term",
      "silentArgs": "/VERYSILENT /NORESTART"
    },
    {
      "name": "git",
      "type": "installer",
      "source": "git",
      "version": "2.43.0",
      "displayName": "Git",
      "silentArgs": "/VERYSILENT /NORESTART"
    },
    {
      "name": "tortoisegit",
      "type": "installer",
      "source": "tortoisegit",
      "version": "2.15.0",
      "displayName": "TortoiseGit",
      "silentArgs": "/S"
    },
    {
      "name": "tortoisegit-plugin",
      "type": "installer",
      "source": "tortoisegit-plugin",
      "silentArgs": "/S",
      "skipVersionCheck": true
    },
    {
      "name": "chrome",
      "type": "installer",
      "source": "chrome",
      "version": "121.0",
      "displayName": "Google Chrome",
      "silentArgs": "/silent /install"
    },
    {
      "name": "winmerge",
      "type": "installer",
      "source": "winmerge",
      "version": "2.16.40",
      "displayName": "WinMerge",
      "silentArgs": "/VERYSILENT /NORESTART"
    },
    {
      "name": "sakura",
      "type": "installer",
      "source": "sakura",
      "version": "2.4.2",
      "displayName": "サクラエディタ",
      "silentArgs": "/VERYSILENT"
    },
    {
      "name": "jdk",
      "type": "extract",
      "source": "jdk",
      "destination": "C:\\dev-tools\\jdk\\17"
    },
    {
      "name": "eclipse",
      "type": "extract",
      "source": "eclipse",
      "destination": "C:\\dev-tools\\eclipse"
    },
    {
      "name": "eclipse-workspace",
      "type": "extract",
      "source": "eclipse-workspace",
      "destination": "C:\\workspace\\eclipse"
    },
    {
      "name": "weblogic",
      "type": "extract",
      "source": "weblogic",
      "destination": "C:\\dev-tools\\weblogic"
    },
    {
      "name": "a5m2",
      "type": "extract",
      "source": "a5m2",
      "destination": "C:\\dev-tools\\a5m2"
    },
    {
      "name": "sqldeveloper",
      "type": "extract",
      "source": "sqldeveloper",
      "destination": "C:\\dev-tools\\sqldeveloper",
      "configCopy": {
        "source": "connections.xml",
        "destination": "%APPDATA%\\SQL Developer\\system\\connections.xml"
      }
    },
    {
      "name": "modheader",
      "type": "copy",
      "source": "chrome-plugins",
      "destination": "C:\\dev-tools\\chrome-plugins\\modheader"
    }
  ],
  "repositories": [
    {
      "name": "project-main",
      "url": "https://github.com/org/project-main.git",
      "destination": "C:\\workspace\\project-main"
    },
    {
      "name": "project-common",
      "url": "https://github.com/org/project-common.git",
      "destination": "C:\\workspace\\project-common"
    }
  ]
}
```

**Step 2: コミット**

```bash
git add config/tools.json
git commit -m "feat: add sample tools.json configuration"
```

---

## Task 12: 統合テスト

**Step 1: ディレクトリ構成確認**

```bash
ls -la scripts/
ls -la scripts/modules/
ls -la config/
```

Expected:
```
scripts/
├── Main.ps1
├── Clone-Repositories.ps1
├── Set-JavaEnv.ps1
└── modules/
    ├── Logger.psm1
    ├── FileManager.psm1
    ├── Extractor.psm1
    ├── Installer.psm1
    ├── ConfigCopier.psm1
    └── FileCopier.psm1

config/
└── tools.json
```

**Step 2: 構文チェック**

```powershell
# 各モジュールの構文チェック
$ErrorActionPreference = "Stop"
$modules = @(
    "scripts/modules/Logger.psm1",
    "scripts/modules/FileManager.psm1",
    "scripts/modules/Extractor.psm1",
    "scripts/modules/Installer.psm1",
    "scripts/modules/ConfigCopier.psm1",
    "scripts/modules/FileCopier.psm1",
    "scripts/Main.ps1",
    "scripts/Clone-Repositories.ps1",
    "scripts/Set-JavaEnv.ps1"
)

foreach ($module in $modules) {
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $module),
            [ref]$null,
            [ref]$null
        )
        Write-Host "OK: $module" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: $module - $_" -ForegroundColor Red
    }
}
```

**Step 3: 最終コミット**

```bash
git add -A
git commit -m "feat: complete package installer implementation

実装完了:
- Logger.psm1: ログ出力・進行度・サマリー
- FileManager.psm1: ハッシュ計算・ファイル取得・バックアップ
- Extractor.psm1: 7z/zip解凍
- Installer.psm1: サイレントインストール・レジストリ確認
- ConfigCopier.psm1: 設定ファイルコピー
- FileCopier.psm1: ファイル/フォルダコピー
- Main.ps1: 統括スクリプト
- Clone-Repositories.ps1: Gitクローン
- Set-JavaEnv.ps1: Java環境変数設定
- Install.bat: エントリポイント
- tools.json: サンプル設定

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## 実装後の確認事項

1. **実環境での動作確認**
   - 共有ディレクトリに実際のファイルを配置
   - tools.jsonのパスを実環境に合わせて修正
   - Install.batを管理者として実行

2. **ログ確認**
   - `logRoot`配下のログファイルを確認
   - サマリーファイルの内容確認

3. **バックアップ確認**
   - `backupRoot`配下にタイムスタンプ付きフォルダが作成されているか
