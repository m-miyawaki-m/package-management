@echo off
chcp 65001 > nul
setlocal

rem ============================================
rem 開発環境パッケージ管理 インストーラ
rem ============================================

echo ============================================
echo 開発環境パッケージ管理 インストーラ
echo ============================================
echo.

rem 管理者権限チェック
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [警告] 管理者権限が必要です。昇格を要求します...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo [OK] 管理者権限で実行中
echo.

rem 設定ファイルパス
set CONFIG_PATH=%~dp0config\tools.json

rem 設定ファイル存在チェック
if not exist "%CONFIG_PATH%" (
    echo [エラー] 設定ファイルが見つかりません: %CONFIG_PATH%
    pause
    exit /b 1
)

echo [OK] 設定ファイル: %CONFIG_PATH%
echo.

rem PowerShellスクリプト実行
echo PowerShellスクリプトを実行します...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\Install-DevEnv.ps1" -ConfigPath "%CONFIG_PATH%"

set EXIT_CODE=%errorlevel%

echo.
echo ============================================
if %EXIT_CODE% equ 0 (
    echo インストールが完了しました
) else (
    echo インストール中にエラーが発生しました（終了コード: %EXIT_CODE%）
)
echo ============================================
echo.

pause
exit /b %EXIT_CODE%
