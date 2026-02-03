# scripts/modules/Installer.psm1
# exe/msiインストーラー実行・レジストリバージョン確認モジュール

function Get-InstalledVersion {
    <#
    .SYNOPSIS
        インストール済みソフトウェアのバージョンを取得
    .DESCRIPTION
        Windowsレジストリのアンインストール情報から、指定された表示名に一致する
        ソフトウェアのバージョンを取得する。
        64bit/32bit両方のレジストリパスを検索する。
    .PARAMETER DisplayName
        検索するソフトウェアの表示名（部分一致）
    .OUTPUTS
        hashtable - @{Found=$true/$false, Version=バージョン文字列, DisplayName=表示名}
    .EXAMPLE
        Get-InstalledVersion -DisplayName "Visual Studio Code"
    #>
    [CmdletBinding()]
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
    <#
    .SYNOPSIS
        インストーラーをサイレント実行
    .DESCRIPTION
        exe/msiインストーラーを指定された引数でサイレント実行する。
        終了コードが成功コードリストに含まれているかを確認する。
        3010は再起動が必要な場合の成功コード。
    .PARAMETER InstallerPath
        インストーラーファイルのパス
    .PARAMETER SilentArgs
        サイレントインストール用の引数
    .PARAMETER SuccessCodes
        成功とみなす終了コードの配列（デフォルト: 0, 3010）
    .OUTPUTS
        hashtable - @{Success=$true/$false, ExitCode=終了コード}
    .EXAMPLE
        Invoke-SilentInstall -InstallerPath "C:\setup.exe" -SilentArgs "/S"
    #>
    [CmdletBinding()]
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
    <#
    .SYNOPSIS
        バージョン文字列を比較
    .DESCRIPTION
        インストール済みバージョンとターゲットバージョンを比較する。
        完全一致を先に試し、一致しない場合はドット区切りのパーツ単位で比較する。
        パーツ数が異なる場合は、短い方の長さまで比較し、すべて一致すれば$trueを返す。
    .PARAMETER InstalledVersion
        インストール済みのバージョン文字列
    .PARAMETER TargetVersion
        比較対象のターゲットバージョン文字列
    .OUTPUTS
        bool - バージョンが一致する場合は$true、一致しない場合は$false
    .EXAMPLE
        Test-VersionMatch -InstalledVersion "1.2.3" -TargetVersion "1.2.3"
    .EXAMPLE
        Test-VersionMatch -InstalledVersion "1.2.3.4" -TargetVersion "1.2.3"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstalledVersion,

        [Parameter(Mandatory)]
        [string]$TargetVersion
    )

    # バージョン文字列の正規化（先頭/末尾の空白を除去）
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

# 関数をエクスポート
Export-ModuleMember -Function Get-InstalledVersion, Invoke-SilentInstall, Test-VersionMatch
