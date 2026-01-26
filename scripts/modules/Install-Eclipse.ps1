# scripts/modules/Install-Eclipse.ps1
# Eclipseインストールモジュール

function Install-Eclipse {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [hashtable]$ToolConfig
    )

    Write-LogSection "Eclipse"

    $version = $ToolConfig.version
    $fileName = $ToolConfig.file
    $workspace = $ToolConfig.workspace
    $toolFolder = $Settings.tools.eclipse

    Write-Log "要求バージョン: $version"

    # インストール先パス
    $installPath = Join-Path $Settings.installBasePath "eclipse" $version
    Write-Log "インストール先: $installPath"

    # ワークスペース
    if ($workspace) {
        Write-Log "ワークスペース: $workspace"
    }

    # 既存バージョンチェック
    if (Test-Path $installPath) {
        Write-Log "結果: SKIPPED (既存バージョン: $version)" -Level "SKIPPED"
        return @{
            Status = "SKIPPED"
            Path = $installPath
            Version = $version
            Workspace = $workspace
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

    $parentPath = Join-Path $Settings.installBasePath "eclipse"
    if (-not (Test-Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    try {
        $tempPath = Join-Path $parentPath "_temp_eclipse"
        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force

        $extractedDir = Get-ChildItem -Path $tempPath -Directory | Select-Object -First 1

        if ($extractedDir) {
            Move-Item -Path $extractedDir.FullName -Destination $installPath -Force
        } else {
            Move-Item -Path $tempPath -Destination $installPath -Force
        }

        if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

        # ワークスペースディレクトリ作成
        if ($workspace -and -not (Test-Path $workspace)) {
            New-Item -ItemType Directory -Path $workspace -Force | Out-Null
            Write-Log "ワークスペースディレクトリを作成: $workspace"
        }

        Write-Log "結果: SUCCESS (新規インストール)" -Level "SUCCESS"
        return @{
            Status = "SUCCESS"
            Path = $installPath
            Version = $version
            Workspace = $workspace
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

Export-ModuleMember -Function Install-Eclipse
