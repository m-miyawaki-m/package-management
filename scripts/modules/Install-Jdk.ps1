# scripts/modules/Install-Jdk.ps1
# JDKインストールモジュール

function Install-Jdk {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [hashtable]$ToolConfig
    )

    Write-LogSection "JDK"

    $version = $ToolConfig.version
    $fileName = $ToolConfig.file
    $toolFolder = $Settings.tools.jdk

    Write-Log "要求バージョン: $version"

    # インストール先パス
    $installPath = Join-Path $Settings.installBasePath "jdk" $version
    Write-Log "インストール先: $installPath"

    # 既存バージョンチェック
    if (Test-Path $installPath) {
        Write-Log "結果: SKIPPED (既存バージョン: $version)" -Level "SKIPPED"
        return @{
            Status = "SKIPPED"
            Path = $installPath
            Version = $version
        }
    }

    # ZIPファイルパス
    $zipPath = Join-Path $Settings.shareBasePath $toolFolder $fileName

    if (-not (Test-Path $zipPath)) {
        Write-Log "ZIPファイルが見つかりません: $zipPath" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }

    # ZIP展開
    Write-Log "ZIPファイルを展開中: $zipPath"

    $parentPath = Join-Path $Settings.installBasePath "jdk"
    if (-not (Test-Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    try {
        # 一時ディレクトリに展開してからリネーム
        $tempPath = Join-Path $parentPath "_temp_jdk"
        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force

        # 展開されたディレクトリを特定（通常、ZIP内に1つのフォルダがある）
        $extractedDir = Get-ChildItem -Path $tempPath -Directory | Select-Object -First 1

        if ($extractedDir) {
            Move-Item -Path $extractedDir.FullName -Destination $installPath -Force
        } else {
            # フォルダがない場合はそのまま移動
            Move-Item -Path $tempPath -Destination $installPath -Force
        }

        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Write-Log "結果: SUCCESS (新規インストール)" -Level "SUCCESS"
        return @{
            Status = "SUCCESS"
            Path = $installPath
            Version = $version
        }
    }
    catch {
        Write-Log "インストールエラー: $_" -Level "FAILED"
        Write-Log "結果: FAILED" -Level "FAILED"
        return @{
            Status = "FAILED"
            Path = $null
            Version = $version
        }
    }
}

Export-ModuleMember -Function Install-Jdk
