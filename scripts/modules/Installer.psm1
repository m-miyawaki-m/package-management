# scripts/modules/Installer.psm1
# exe/msiインストーラー実行・レジストリバージョン確認モジュール
#
# 分岐網羅コメント凡例:
#   [B-XX] = 分岐ポイント番号
#   T: = 真(True)の場合の処理
#   F: = 偽(False)の場合の処理

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

    # [B-01] レジストリパスループ（64bit→32bit順）
    foreach ($path in $registryPaths) {
        # [B-02] レジストリアクセス例外処理
        #   T(try成功): アプリ検索結果判定へ
        #   F(catch):   次のレジストリパスへ続行
        try {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like "*$DisplayName*" }

            # [B-03] アプリ発見判定
            #   T: 最初の一致を返して終了
            #   F: 次のレジストリパスへ続行
            if ($apps) {
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

    # [B-04] ループ終了（未発見）
    #   全レジストリパス検索後、アプリが見つからなかった場合
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

    # [B-05] インストーラー存在チェック
    #   T: インストール処理へ続行
    #   F: エラーログ出力、失敗結果を返して終了
    if (-not (Test-Path $InstallerPath)) {
        Write-Log -Message "インストーラーが存在しません: $InstallerPath" -Level "ERROR"
        return @{
            Success = $false
            ExitCode = -1
        }
    }

    Write-Log -Message "インストーラー実行: $InstallerPath $SilentArgs" -Level "INFO"

    # [B-06] インストーラー実行例外処理
    #   T(try成功): 終了コード判定へ
    #   F(catch):   エラーログ出力、失敗結果を返す
    try {
        $process = Start-Process -FilePath $InstallerPath -ArgumentList $SilentArgs -Wait -PassThru -NoNewWindow
        $exitCode = $process.ExitCode

        # [B-07] 終了コード成功判定
        #   T: 成功結果を返す（0または3010）
        #   F: エラーログ出力、失敗結果を返す
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

    # [B-08] 完全一致判定
    #   T: $true を返して終了
    #   F: パーツ単位比較へ続行
    if ($installed -eq $target) {
        return $true
    }

    # メジャー.マイナー.パッチ形式で比較
    $installedParts = $installed -split '\.'
    $targetParts = $target -split '\.'

    # 最小の長さで比較
    $minLength = [Math]::Min($installedParts.Length, $targetParts.Length)

    # [B-09] パーツ単位比較ループ
    for ($i = 0; $i -lt $minLength; $i++) {
        # [B-10] パーツ一致判定
        #   T: 次のパーツへ続行
        #   F: $false を返して終了（バージョン不一致）
        if ($installedParts[$i] -ne $targetParts[$i]) {
            return $false
        }
    }

    # [B-11] ループ終了（すべてのパーツが一致）
    #   短い方のパーツがすべて一致した場合、バージョン一致とみなす
    #   例: "1.2.3.4" と "1.2.3" → 一致
    return $true
}

# 関数をエクスポート
Export-ModuleMember -Function Get-InstalledVersion, Invoke-SilentInstall, Test-VersionMatch
