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
