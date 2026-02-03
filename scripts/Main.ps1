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
