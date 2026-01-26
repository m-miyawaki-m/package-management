# scripts/modules/Install-Certificate.ps1
# 証明書インストールモジュール

function Install-Certificate {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [Parameter(Mandatory)]
        [string[]]$Certificates,

        [Parameter(Mandatory)]
        [string]$JavaHome
    )

    Write-LogSection "Certificate"

    $certsFolder = $Settings.tools.certs
    $keytoolPath = Join-Path $JavaHome "bin" "keytool.exe"
    $cacertsPath = Join-Path $JavaHome "lib" "security" "cacerts"

    # keytool存在確認
    if (-not (Test-Path $keytoolPath)) {
        Write-Log "keytoolが見つかりません: $keytoolPath" -Level "FAILED"
        return @{
            Status = "FAILED"
            Processed = 0
        }
    }

    # cacerts存在確認
    if (-not (Test-Path $cacertsPath)) {
        Write-Log "cacertsが見つかりません: $cacertsPath" -Level "FAILED"
        return @{
            Status = "FAILED"
            Processed = 0
        }
    }

    $successCount = 0
    $failCount = 0

    foreach ($certFile in $Certificates) {
        Write-Log "対象: $certFile"

        $certPath = Join-Path $Settings.shareBasePath $certsFolder $certFile

        if (-not (Test-Path $certPath)) {
            Write-Log "証明書ファイルが見つかりません: $certPath" -Level "FAILED"
            $failCount++
            continue
        }

        # エイリアス名（ファイル名から拡張子を除いたもの）
        $alias = [System.IO.Path]::GetFileNameWithoutExtension($certFile)

        try {
            # 既存の証明書を確認
            $checkResult = & $keytoolPath -list -keystore $cacertsPath -storepass "changeit" -alias $alias 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Log "結果: SKIPPED (既に登録済み: $alias)" -Level "SKIPPED"
                $successCount++
                continue
            }

            # 証明書をインポート
            $importResult = & $keytoolPath -importcert -trustcacerts -keystore $cacertsPath -storepass "changeit" -noprompt -alias $alias -file $certPath 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Log "結果: SUCCESS (キーストアに登録)" -Level "SUCCESS"
                $successCount++
            } else {
                Write-Log "keytoolエラー: $importResult" -Level "FAILED"
                $failCount++
            }
        }
        catch {
            Write-Log "証明書登録エラー: $_" -Level "FAILED"
            $failCount++
        }
    }

    if ($failCount -eq 0) {
        return @{
            Status = "SUCCESS"
            Processed = $successCount
        }
    } else {
        return @{
            Status = "FAILED"
            Processed = $successCount
            Failed = $failCount
        }
    }
}

Export-ModuleMember -Function Install-Certificate
