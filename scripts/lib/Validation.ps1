# scripts/lib/Validation.ps1
# 環境検証モジュール

<#
.SYNOPSIS
    インストールされたツールの検証を行う関数群
.DESCRIPTION
    - JDK/Gradle: コマンド実行でバージョン確認
    - Eclipse/WebLogic: 設定ファイルからバージョン確認
#>

function Test-JdkInstallation {
    <#
    .SYNOPSIS
        JDKのインストールを検証
    .PARAMETER InstallPath
        JDKのインストールパス
    .RETURNS
        検証結果のハッシュテーブル
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath
    )

    $result = @{
        Valid = $false
        ExecutableExists = $false
        Version = $null
        Message = ""
    }

    # java.exe の存在確認
    $javaExe = Join-Path $InstallPath "bin" "java.exe"
    if (-not (Test-Path $javaExe)) {
        $result.Message = "java.exe が見つかりません: $javaExe"
        Write-Log $result.Message -Level "FAILED"
        return $result
    }
    $result.ExecutableExists = $true

    # バージョン確認
    try {
        $versionOutput = & $javaExe -version 2>&1
        $versionLine = $versionOutput | Select-Object -First 1

        # バージョン文字列を抽出 (例: "openjdk version "17.0.8"" → "17.0.8")
        if ($versionLine -match '"([^"]+)"') {
            $result.Version = $matches[1]
            $result.Valid = $true
            $result.Message = "JDK検証OK: バージョン $($result.Version)"
            Write-Log $result.Message -Level "SUCCESS"
        } else {
            $result.Message = "バージョン情報を解析できません: $versionLine"
            Write-Log $result.Message -Level "WARN"
            $result.Valid = $true  # 実行はできているのでOKとする
        }
    }
    catch {
        $result.Message = "java -version 実行エラー: $_"
        Write-Log $result.Message -Level "FAILED"
    }

    return $result
}

function Test-GradleInstallation {
    <#
    .SYNOPSIS
        Gradleのインストールを検証
    .PARAMETER InstallPath
        Gradleのインストールパス
    .PARAMETER JavaHome
        JAVA_HOMEパス（Gradle実行に必要）
    .RETURNS
        検証結果のハッシュテーブル
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath,

        [Parameter(Mandatory)]
        [string]$JavaHome
    )

    $result = @{
        Valid = $false
        ExecutableExists = $false
        Version = $null
        Message = ""
    }

    # gradle.bat の存在確認
    $gradleBat = Join-Path $InstallPath "bin" "gradle.bat"
    if (-not (Test-Path $gradleBat)) {
        $result.Message = "gradle.bat が見つかりません: $gradleBat"
        Write-Log $result.Message -Level "FAILED"
        return $result
    }
    $result.ExecutableExists = $true

    # バージョン確認（JAVA_HOMEを設定して実行）
    try {
        $env:JAVA_HOME = $JavaHome
        $versionOutput = & $gradleBat -v 2>&1 | Out-String

        # バージョン文字列を抽出 (例: "Gradle 8.5")
        if ($versionOutput -match 'Gradle\s+(\d+\.\d+(?:\.\d+)?)') {
            $result.Version = $matches[1]
            $result.Valid = $true
            $result.Message = "Gradle検証OK: バージョン $($result.Version)"
            Write-Log $result.Message -Level "SUCCESS"
        } else {
            $result.Message = "バージョン情報を解析できません"
            Write-Log $result.Message -Level "WARN"
            $result.Valid = $true  # 実行はできているのでOKとする
        }
    }
    catch {
        $result.Message = "gradle -v 実行エラー: $_"
        Write-Log $result.Message -Level "FAILED"
    }

    return $result
}

function Test-EclipseInstallation {
    <#
    .SYNOPSIS
        Eclipseのインストールを検証
    .PARAMETER InstallPath
        Eclipseのインストールパス
    .RETURNS
        検証結果のハッシュテーブル
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath
    )

    $result = @{
        Valid = $false
        ExecutableExists = $false
        Version = $null
        ProductName = $null
        Message = ""
    }

    # eclipse.exe の存在確認
    $eclipseExe = Join-Path $InstallPath "eclipse.exe"
    if (-not (Test-Path $eclipseExe)) {
        $result.Message = "eclipse.exe が見つかりません: $eclipseExe"
        Write-Log $result.Message -Level "FAILED"
        return $result
    }
    $result.ExecutableExists = $true

    # .eclipseproduct ファイルからバージョン確認
    $productFile = Join-Path $InstallPath ".eclipseproduct"
    if (Test-Path $productFile) {
        try {
            $content = Get-Content $productFile -Raw

            # バージョン抽出
            if ($content -match 'version\s*=\s*(.+)') {
                $result.Version = $matches[1].Trim()
            }

            # 製品名抽出
            if ($content -match 'name\s*=\s*(.+)') {
                $result.ProductName = $matches[1].Trim()
            }

            $result.Valid = $true
            $result.Message = "Eclipse検証OK: $($result.ProductName) バージョン $($result.Version)"
            Write-Log $result.Message -Level "SUCCESS"
        }
        catch {
            $result.Message = ".eclipseproduct 読み込みエラー: $_"
            Write-Log $result.Message -Level "WARN"
            $result.Valid = $true  # exeは存在するのでOKとする
        }
    } else {
        # .eclipseproduct がない場合、configuration/config.ini を確認
        $configIni = Join-Path $InstallPath "configuration" "config.ini"
        if (Test-Path $configIni) {
            $result.Valid = $true
            $result.Message = "Eclipse検証OK: config.ini 確認済み（バージョン情報なし）"
            Write-Log $result.Message -Level "SUCCESS"
        } else {
            $result.Message = "設定ファイルが見つかりません"
            Write-Log $result.Message -Level "WARN"
            $result.Valid = $true  # exeは存在するのでOKとする
        }
    }

    return $result
}

function Test-WebLogicInstallation {
    <#
    .SYNOPSIS
        WebLogicのインストールを検証
    .PARAMETER InstallPath
        WebLogicのインストールパス
    .RETURNS
        検証結果のハッシュテーブル
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath
    )

    $result = @{
        Valid = $false
        Version = $null
        Message = ""
    }

    # 複数の場所でバージョン情報を探す
    $versionFound = $false

    # 1. registry.xml (MW_HOME直下)
    $registryXml = Join-Path $InstallPath "registry.xml"
    if (Test-Path $registryXml) {
        try {
            $content = Get-Content $registryXml -Raw
            if ($content -match 'version\s*=\s*"([^"]+)"') {
                $result.Version = $matches[1]
                $versionFound = $true
            }
        }
        catch {
            Write-Log "registry.xml 読み込みエラー: $_" -Level "WARN"
        }
    }

    # 2. inventory/registry.xml (12.2.x以降)
    if (-not $versionFound) {
        $inventoryXml = Join-Path $InstallPath "inventory" "registry.xml"
        if (Test-Path $inventoryXml) {
            try {
                $content = Get-Content $inventoryXml -Raw
                if ($content -match 'version\s*=\s*"([^"]+)"') {
                    $result.Version = $matches[1]
                    $versionFound = $true
                }
            }
            catch {
                Write-Log "inventory/registry.xml 読み込みエラー: $_" -Level "WARN"
            }
        }
    }

    # 3. wlserver/.product.properties
    if (-not $versionFound) {
        $productProps = Join-Path $InstallPath "wlserver" ".product.properties"
        if (-not (Test-Path $productProps)) {
            $productProps = Join-Path $InstallPath ".product.properties"
        }
        if (Test-Path $productProps) {
            try {
                $content = Get-Content $productProps -Raw
                if ($content -match 'version\s*=\s*(.+)') {
                    $result.Version = $matches[1].Trim()
                    $versionFound = $true
                } elseif ($content -match 'WLS_PRODUCT_VERSION\s*=\s*(.+)') {
                    $result.Version = $matches[1].Trim()
                    $versionFound = $true
                }
            }
            catch {
                Write-Log ".product.properties 読み込みエラー: $_" -Level "WARN"
            }
        }
    }

    # 4. wlserver/server/lib/weblogic.jar の存在確認（最終手段）
    $weblogicJar = Join-Path $InstallPath "wlserver" "server" "lib" "weblogic.jar"
    if (-not (Test-Path $weblogicJar)) {
        $weblogicJar = Join-Path $InstallPath "server" "lib" "weblogic.jar"
    }

    if (Test-Path $weblogicJar) {
        $result.Valid = $true
        if ($versionFound) {
            $result.Message = "WebLogic検証OK: バージョン $($result.Version)"
        } else {
            $result.Message = "WebLogic検証OK: weblogic.jar 確認済み（バージョン情報なし）"
        }
        Write-Log $result.Message -Level "SUCCESS"
    } else {
        # ディレクトリ構造の確認（最低限）
        $wlserverDir = Join-Path $InstallPath "wlserver"
        if (Test-Path $wlserverDir) {
            $result.Valid = $true
            if ($versionFound) {
                $result.Message = "WebLogic検証OK: バージョン $($result.Version)"
            } else {
                $result.Message = "WebLogic検証OK: wlserver ディレクトリ確認済み"
            }
            Write-Log $result.Message -Level "SUCCESS"
        } else {
            $result.Message = "WebLogicのディレクトリ構造が不正です"
            Write-Log $result.Message -Level "FAILED"
        }
    }

    return $result
}

function Test-AllInstallations {
    <#
    .SYNOPSIS
        全ツールのインストールを検証
    .PARAMETER JdkPath
        JDKパス
    .PARAMETER GradlePath
        Gradleパス
    .PARAMETER EclipsePath
        Eclipseパス
    .PARAMETER WebLogicPath
        WebLogicパス
    .RETURNS
        全検証結果のハッシュテーブル
    #>
    param(
        [string]$JdkPath,
        [string]$GradlePath,
        [string]$EclipsePath,
        [string]$WebLogicPath
    )

    Write-LogSection "環境検証"

    $results = @{
        AllValid = $true
        Jdk = $null
        Gradle = $null
        Eclipse = $null
        WebLogic = $null
    }

    if ($JdkPath) {
        Write-Log "JDK検証中: $JdkPath"
        $results.Jdk = Test-JdkInstallation -InstallPath $JdkPath
        if (-not $results.Jdk.Valid) { $results.AllValid = $false }
    }

    if ($GradlePath -and $JdkPath) {
        Write-Log "Gradle検証中: $GradlePath"
        $results.Gradle = Test-GradleInstallation -InstallPath $GradlePath -JavaHome $JdkPath
        if (-not $results.Gradle.Valid) { $results.AllValid = $false }
    }

    if ($EclipsePath) {
        Write-Log "Eclipse検証中: $EclipsePath"
        $results.Eclipse = Test-EclipseInstallation -InstallPath $EclipsePath
        if (-not $results.Eclipse.Valid) { $results.AllValid = $false }
    }

    if ($WebLogicPath) {
        Write-Log "WebLogic検証中: $WebLogicPath"
        $results.WebLogic = Test-WebLogicInstallation -InstallPath $WebLogicPath
        if (-not $results.WebLogic.Valid) { $results.AllValid = $false }
    }

    return $results
}

Export-ModuleMember -Function *
