# scripts/Main.ps1
# 開発環境パッケージインストーラー 統括スクリプト
#
# 分岐網羅コメント凡例:
#   [B-XX] = 分岐ポイント番号
#   T: = 真(True)の場合の処理
#   F: = 偽(False)の場合の処理

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

# [B-01] 設定ファイル存在チェック
#   T: 設定読み込み処理へ続行
#   F: エラー出力、exit 1 で終了
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

# [B-02] 共有ディレクトリアクセスチェック
#   T: ツール処理ループへ続行
#   F: FATALログ出力、exit 1 で終了
if (-not (Test-ShareAccess -SharePath $defaults.sourceRoot)) {
    Write-Log -Message "共有ディレクトリにアクセスできません: $($defaults.sourceRoot)" -Level "FATAL"
    exit 1
}

# タイムスタンプ（バックアップ用）
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# ツールごとに処理
foreach ($tool in $config.tools) {
    Write-LogSection -ToolName $tool.name

    $status = "FAILED"
    $note = ""
    $localVersion = "-"
    $sharedVersion = "-"

    try {
        # 共有フォルダからファイル取得
        $sourceFolderPath = Join-Path $defaults.sourceRoot $tool.source

        # [B-03] configCopy設定存在チェック
        #   T: 設定ファイルを除外対象に指定
        #   F: 除外なし
        $excludeFile = $null
        if ($tool.configCopy) {
            $excludeFile = $tool.configCopy.source
        }

        $fileResult = Get-SingleFileFromFolder -FolderPath $sourceFolderPath -ExcludeFile $excludeFile

        # [B-04] ファイル取得結果チェック
        #   T: タイプ別処理へ続行
        #   F: エラーログ出力、結果記録、次のツールへ(continue)
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

        # [B-05] タイプ別処理 (switch)
        #   "installer": インストーラー実行
        #   "extract":   アーカイブ解凍
        #   "copy":      ファイル/フォルダコピー
        switch ($tool.type) {
            "installer" {
                # [B-06] バージョンチェック実行判定
                #   条件: skipVersionCheck=false かつ displayName設定あり かつ version設定あり
                #   T: レジストリからバージョン確認
                #   F: バージョンチェックをスキップ
                if (-not $tool.skipVersionCheck -and $tool.displayName -and $tool.version) {
                    $installed = Get-InstalledVersion -DisplayName $tool.displayName

                    # [B-07] インストール済み判定
                    #   T: バージョン比較へ
                    #   F: 新規インストールへ続行
                    if ($installed.Found) {
                        $localVersion = $installed.Version
                        $sharedVersion = $tool.version

                        # [B-08] バージョン一致判定
                        #   T: SKIPPED設定、switch抜け
                        #   F: アップデートインストールへ続行
                        if (Test-VersionMatch -InstalledVersion $installed.Version -TargetVersion $tool.version) {
                            Write-Log -Message "インストール済み (バージョン: $($installed.Version))" -Level "INFO"
                            $status = "SKIPPED"
                            $note = "バージョン一致"
                            break
                        }
                    }
                    $sharedVersion = $tool.version
                }

                # ファイル取得（ハッシュ比較）
                $sourceHash = Get-FileHashSHA256 -FilePath $sourceFile.FullName -OperationName "ハッシュ計算中(共有)"
                Write-Log -Message "ハッシュ(共有): $($sourceHash.Substring(0, 16))..." -Level "INFO"

                # [B-09] ローカルファイル存在チェック
                #   T: ハッシュ比較、必要に応じてコピー
                #   F: 新規取得
                if (Test-Path $localFilePath) {
                    $localHash = Get-FileHashSHA256 -FilePath $localFilePath -OperationName "ハッシュ計算中(ローカル)"
                    Write-Log -Message "ハッシュ(ローカル): $($localHash.Substring(0, 16))..." -Level "INFO"

                    # [B-10] ハッシュ不一致判定
                    #   T: バックアップ後、共有からコピー
                    #   F: ローカルキャッシュを使用（コピー不要）
                    if ($sourceHash -ne $localHash) {
                        Backup-File -FilePath $localFilePath -BackupRoot $defaults.backupRoot -Timestamp $timestamp
                        Copy-FileWithProgress -Source $sourceFile.FullName -Destination $localFilePath
                    }
                }
                else {
                    Write-Log -Message "ハッシュ(ローカル): なし（新規取得）" -Level "INFO"
                    Copy-FileWithProgress -Source $sourceFile.FullName -Destination $localFilePath
                }

                # [B-11] 成功コード設定判定
                #   T: ツール固有の成功コードを使用
                #   F: デフォルト成功コードを使用
                $successCodes = if ($tool.successCodes) { $tool.successCodes } else { $defaults.successCodes }
                $installResult = Invoke-SilentInstall -InstallerPath $localFilePath -SilentArgs $tool.silentArgs -SuccessCodes $successCodes

                # [B-12] インストール結果判定
                #   T: SUCCESS設定
                #   F: FAILED設定、必須チェックへ
                if ($installResult.Success) {
                    $status = "SUCCESS"
                }
                else {
                    $status = "FAILED"
                    $note = "exit code: $($installResult.ExitCode)"

                    # [B-13] 必須ツール判定
                    #   T: FATALログ出力、exit 1 で即終了
                    #   F: 次のツールへ続行
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

                # [B-14] ローカルアーカイブ存在チェック
                #   T: ハッシュ比較、スキップ判定へ
                #   F: 新規取得
                if (Test-Path $localFilePath) {
                    $localHash = Get-FileHashSHA256 -FilePath $localFilePath -OperationName "ハッシュ計算中(ローカル)"
                    Write-Log -Message "ハッシュ(ローカル): $($localHash.Substring(0, 16))..." -Level "INFO"

                    # [B-15] ハッシュ一致判定
                    #   T: 解凍先存在チェックへ
                    #   F: バックアップ後、共有からコピー
                    if ($sourceHash -eq $localHash) {
                        # [B-16] 解凍先存在チェック
                        #   T: SKIPPED設定、解凍不要
                        #   F: 警告ログ、再解凍が必要
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

                # [B-17] 解凍要否判定
                #   T: 解凍処理実行
                #   F: 解凍をスキップ（SKIPPED状態維持）
                if ($needExtract) {
                    $extractResult = Invoke-Extract -ArchivePath $localFilePath -Destination $tool.destination -SevenZipPath $defaults."7zPath" -BackupRoot $defaults.backupRoot -Timestamp $timestamp

                    # [B-18] 解凍結果判定
                    #   T: SUCCESS設定
                    #   F: FAILED設定
                    if ($extractResult) {
                        $status = "SUCCESS"
                    }
                    else {
                        $status = "FAILED"
                        $note = "解凍エラー"
                    }
                }

                # [B-19] configCopy処理判定
                #   条件: 失敗でない かつ configCopy設定あり
                #   T: 設定ファイルコピー実行
                #   F: 設定ファイルコピーをスキップ
                if ($status -ne "FAILED" -and $tool.configCopy) {
                    $configSourcePath = Join-Path $sourceFolderPath $tool.configCopy.source
                    $configCopyResult = Copy-ConfigFile -SourcePath $configSourcePath -DestinationPath $tool.configCopy.destination -BackupRoot $defaults.backupRoot -Timestamp $timestamp

                    # [B-20] 設定ファイルコピー結果判定
                    #   T: 処理完了（警告なし）
                    #   F: 警告ログ出力（本体は成功扱い）
                    if (-not $configCopyResult) {
                        Write-Log -Message "設定ファイルコピーに失敗しましたが、本体は成功しています" -Level "WARNING"
                    }
                }
            }

            "copy" {
                $copyResult = Copy-ToolFiles -SourcePath $sourceFile.FullName -DestinationPath $tool.destination -BackupRoot $defaults.backupRoot -Timestamp $timestamp

                # [B-21] コピー結果判定
                #   T: スキップ判定へ
                #   F: FAILED設定
                if ($copyResult.Success) {
                    # [B-22] スキップ判定
                    #   T: SKIPPED設定（ハッシュ一致でコピー不要だった）
                    #   F: SUCCESS設定（コピー実行された）
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
    # [B-23] ツール処理例外ハンドリング
    #   try内で例外発生時、FAILED設定
    catch {
        Write-Log -Message "エラー: $_" -Level "ERROR"
        $status = "FAILED"
        $note = "例外発生"
    }

    # 結果を記録
    Add-Result -ToolName $tool.name -Type $tool.type -Status $status -LocalVersion $localVersion -SharedVersion $sharedVersion -Note $note

    # [B-24] 結果ログ出力 (if-elseif-else)
    #   SUCCESS: 成功ログ出力
    #   SKIPPED: スキップログ出力
    #   FAILED:  エラーログ出力
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

# [B-25] 終了コード判定
#   T: exit 1（失敗あり）
#   F: exit 0（すべて成功またはスキップ）
if ($summary.Failed -gt 0) {
    exit 1
}
exit 0
