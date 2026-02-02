# scripts/lib/StepHandlers.ps1
# Step処理関数モジュール

function Invoke-ExtractStep {
    <#
    .SYNOPSIS
        7z/ZIP展開を実行
    #>
    param(
        [Parameter(Mandatory)]
        [psobject]$Step,
        [Parameter(Mandatory)]
        [psobject]$Defaults,
        [string]$ToolSourceBase
    )

    $sourceBase = if ($ToolSourceBase) { $ToolSourceBase } else { $Defaults.sourceBase }
    $sourcePath = Join-Path $sourceBase $Step.source
    $destPath = Join-Path $Defaults.destBase $Step.destination

    Write-Log "  展開元: $sourcePath"
    Write-Log "  展開先: $destPath"

    # ソースファイル存在チェック
    if (-not (Test-Path $sourcePath)) {
        Write-Log "  エラー: ソースファイルが見つかりません" -Level "FAILED"
        return @{ Success = $false; Message = "ソースファイルが見つかりません: $sourcePath" }
    }

    # 展開先の親ディレクトリ作成
    $parentPath = Split-Path $destPath -Parent
    if (-not (Test-Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    # 既にインストール済みかチェック
    if (Test-Path $destPath) {
        Write-Log "  スキップ: 既に展開済み" -Level "SKIPPED"
        return @{ Success = $true; Message = "既に展開済み"; Skipped = $true }
    }

    try {
        $extension = [System.IO.Path]::GetExtension($sourcePath).ToLower()

        if ($extension -eq ".zip") {
            # ZIP展開
            Write-Log "  ZIP展開中..."
            Expand-Archive -Path $sourcePath -DestinationPath $destPath -Force
        }
        elseif ($extension -eq ".7z") {
            # 7z展開
            $7zPath = $Defaults.'7zPath'
            if (-not $7zPath -or -not (Test-Path $7zPath)) {
                Write-Log "  エラー: 7z.exe が見つかりません: $7zPath" -Level "FAILED"
                return @{ Success = $false; Message = "7z.exe が見つかりません" }
            }

            Write-Log "  7z展開中..."
            $tempPath = Join-Path $parentPath "_temp_extract"
            if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }

            $result = & $7zPath x "$sourcePath" -o"$tempPath" -y 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log "  エラー: 7z展開失敗 - $result" -Level "FAILED"
                return @{ Success = $false; Message = "7z展開失敗" }
            }

            # 展開されたディレクトリを特定
            $extractedItems = Get-ChildItem -Path $tempPath
            if ($extractedItems.Count -eq 1 -and $extractedItems[0].PSIsContainer) {
                # 単一フォルダの場合はその中身を移動
                Move-Item -Path $extractedItems[0].FullName -Destination $destPath -Force
            } else {
                # 複数アイテムの場合はtempPathをリネーム
                Move-Item -Path $tempPath -Destination $destPath -Force
            }

            if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force }
        }
        else {
            Write-Log "  エラー: 未対応の拡張子: $extension" -Level "FAILED"
            return @{ Success = $false; Message = "未対応の拡張子: $extension" }
        }

        Write-Log "  完了" -Level "SUCCESS"
        return @{ Success = $true; Message = "展開完了" }
    }
    catch {
        Write-Log "  エラー: $_" -Level "FAILED"
        return @{ Success = $false; Message = $_.ToString() }
    }
}

function Invoke-InstallerStep {
    <#
    .SYNOPSIS
        サイレントインストーラを実行
    #>
    param(
        [Parameter(Mandatory)]
        [psobject]$Step,
        [Parameter(Mandatory)]
        [psobject]$Defaults,
        [string]$ToolSourceBase
    )

    $sourceBase = if ($ToolSourceBase) { $ToolSourceBase } else { $Defaults.sourceBase }
    $sourcePath = Join-Path $sourceBase $Step.source
    $silentArgs = $Step.silentArgs

    Write-Log "  インストーラ: $sourcePath"
    Write-Log "  引数: $silentArgs"

    # ソースファイル存在チェック
    if (-not (Test-Path $sourcePath)) {
        Write-Log "  エラー: インストーラが見つかりません" -Level "FAILED"
        return @{ Success = $false; Message = "インストーラが見つかりません: $sourcePath" }
    }

    try {
        Write-Log "  インストール実行中..."
        $process = Start-Process -FilePath $sourcePath -ArgumentList $silentArgs -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Log "  完了" -Level "SUCCESS"
            return @{ Success = $true; Message = "インストール完了" }
        } else {
            Write-Log "  警告: 終了コード $($process.ExitCode)" -Level "WARN"
            return @{ Success = $true; Message = "終了コード: $($process.ExitCode)" }
        }
    }
    catch {
        Write-Log "  エラー: $_" -Level "FAILED"
        return @{ Success = $false; Message = $_.ToString() }
    }
}

function Invoke-ConfigStep {
    <#
    .SYNOPSIS
        設定ファイルを差し替え（既存は.bak退避）
    #>
    param(
        [Parameter(Mandatory)]
        [psobject]$Step,
        [Parameter(Mandatory)]
        [psobject]$Defaults,
        [string]$ToolSourceBase
    )

    $sourceBase = if ($ToolSourceBase) { $ToolSourceBase } else { $Defaults.sourceBase }
    $sourcePath = Join-Path $sourceBase $Step.source
    $destPath = Join-Path $Defaults.destBase $Step.destination

    Write-Log "  設定ファイル元: $sourcePath"
    Write-Log "  設定ファイル先: $destPath"

    # ソースファイル存在チェック
    if (-not (Test-Path $sourcePath)) {
        Write-Log "  エラー: 設定ファイルが見つかりません" -Level "FAILED"
        return @{ Success = $false; Message = "設定ファイルが見つかりません: $sourcePath" }
    }

    try {
        # 既存ファイルのバックアップ
        if (Test-Path $destPath) {
            $bakPath = "$destPath.bak"
            Write-Log "  既存ファイルをバックアップ: $bakPath"
            Copy-Item -Path $destPath -Destination $bakPath -Force
        }

        # 親ディレクトリ作成
        $parentPath = Split-Path $destPath -Parent
        if (-not (Test-Path $parentPath)) {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        }

        # コピー
        Copy-Item -Path $sourcePath -Destination $destPath -Force

        Write-Log "  完了" -Level "SUCCESS"
        return @{ Success = $true; Message = "設定ファイル差し替え完了" }
    }
    catch {
        Write-Log "  エラー: $_" -Level "FAILED"
        return @{ Success = $false; Message = $_.ToString() }
    }
}

function Invoke-EnvStep {
    <#
    .SYNOPSIS
        システム環境変数を設定
    #>
    param(
        [Parameter(Mandatory)]
        [psobject]$Step,
        [Parameter(Mandatory)]
        [psobject]$Defaults
    )

    $envName = $Step.name
    $envValue = $Step.value
    $action = if ($Step.action) { $Step.action } else { "set" }

    Write-Log "  環境変数: $envName"
    Write-Log "  値: $envValue"
    Write-Log "  アクション: $action"

    try {
        # 既存値を取得してログに記録
        $existingValue = [Environment]::GetEnvironmentVariable($envName, "Machine")
        if ($existingValue) {
            Write-Log "  既存値（バックアップ）: $existingValue"
        }

        if ($action -eq "append") {
            # PATHに追加
            if ($existingValue) {
                # 既に含まれているかチェック
                if ($existingValue -split ";" -contains $envValue) {
                    Write-Log "  スキップ: 既にPATHに含まれています" -Level "SKIPPED"
                    return @{ Success = $true; Message = "既にPATHに含まれています"; Skipped = $true }
                }
                $newValue = "$existingValue;$envValue"
            } else {
                $newValue = $envValue
            }
        } else {
            # 上書き
            $newValue = $envValue
        }

        [Environment]::SetEnvironmentVariable($envName, $newValue, "Machine")

        Write-Log "  完了" -Level "SUCCESS"
        return @{ Success = $true; Message = "環境変数設定完了" }
    }
    catch {
        Write-Log "  エラー: $_" -Level "FAILED"
        return @{ Success = $false; Message = $_.ToString() }
    }
}

function Invoke-CertStep {
    <#
    .SYNOPSIS
        証明書をキーストアに登録
    #>
    param(
        [Parameter(Mandatory)]
        [psobject]$Step,
        [Parameter(Mandatory)]
        [psobject]$Defaults,
        [string]$ToolSourceBase
    )

    $sourceBase = if ($ToolSourceBase) { $ToolSourceBase } else { $Defaults.sourceBase }
    $sourcePath = Join-Path $sourceBase $Step.source

    # キーストアパス解決
    if ($Step.keystore) {
        $keystorePath = $Step.keystore
    } elseif ($Step.javaHome) {
        $keystorePath = Join-Path $Step.javaHome "lib\security\cacerts"
    } else {
        Write-Log "  エラー: keystore または javaHome を指定してください" -Level "FAILED"
        return @{ Success = $false; Message = "keystore または javaHome が未指定" }
    }

    Write-Log "  証明書: $sourcePath"
    Write-Log "  キーストア: $keystorePath"

    # ソースファイル存在チェック
    if (-not (Test-Path $sourcePath)) {
        Write-Log "  エラー: 証明書ファイルが見つかりません" -Level "FAILED"
        return @{ Success = $false; Message = "証明書ファイルが見つかりません: $sourcePath" }
    }

    # keytoolパス
    $javaHome = if ($Step.javaHome) { $Step.javaHome } else { Split-Path (Split-Path (Split-Path $keystorePath -Parent) -Parent) -Parent }
    $keytoolPath = Join-Path $javaHome "bin\keytool.exe"

    if (-not (Test-Path $keytoolPath)) {
        Write-Log "  エラー: keytool.exe が見つかりません: $keytoolPath" -Level "FAILED"
        return @{ Success = $false; Message = "keytool.exe が見つかりません" }
    }

    # エイリアス名
    $alias = [System.IO.Path]::GetFileNameWithoutExtension($Step.source)

    try {
        # 既存の証明書を確認
        $checkResult = & $keytoolPath -list -keystore $keystorePath -storepass "changeit" -alias $alias 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "  スキップ: 既に登録済み" -Level "SKIPPED"
            return @{ Success = $true; Message = "既に登録済み"; Skipped = $true }
        }

        # 証明書をインポート
        Write-Log "  証明書を登録中..."
        $importResult = & $keytoolPath -importcert -trustcacerts -keystore $keystorePath -storepass "changeit" -noprompt -alias $alias -file $sourcePath 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "  完了" -Level "SUCCESS"
            return @{ Success = $true; Message = "証明書登録完了" }
        } else {
            Write-Log "  エラー: $importResult" -Level "FAILED"
            return @{ Success = $false; Message = "証明書登録失敗: $importResult" }
        }
    }
    catch {
        Write-Log "  エラー: $_" -Level "FAILED"
        return @{ Success = $false; Message = $_.ToString() }
    }
}

Export-ModuleMember -Function Invoke-ExtractStep, Invoke-InstallerStep, Invoke-ConfigStep, Invoke-EnvStep, Invoke-CertStep
