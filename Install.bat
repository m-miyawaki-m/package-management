@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

:: ========================================
::   開発環境セットアップ
:: ========================================
::
:: 分岐網羅コメント凡例:
::   [B-XX] = 分岐ポイント番号
::   T: = 真(True)の場合の処理
::   F: = 偽(False)の場合の処理

:: [B-01] 管理者権限チェック
::   T: スクリプト続行
::   F: エラーメッセージ表示、exit /b 1
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 管理者権限が必要です。
    echo 右クリックして「管理者として実行」を選択してください。
    pause
    exit /b 1
)

:: スクリプトのディレクトリ
set "SCRIPT_DIR=%~dp0"
set "CONFIG_PATH=%SCRIPT_DIR%config\tools.json"

:: [B-02] 設定ファイル存在チェック
::   T: メニュー表示へ続行
::   F: エラーメッセージ表示、exit /b 1
if not exist "%CONFIG_PATH%" (
    echo 設定ファイルが見つかりません: %CONFIG_PATH%
    pause
    exit /b 1
)

:: メニュー表示
:menu
cls
echo ========================================
echo   開発環境セットアップ
echo ========================================
echo.
echo 1. インストール + Gitクローン自動実行
echo 2. インストールのみ
echo 3. Gitクローンのみ
echo.
echo ----------------------------------------
set /p choice="選択してください (1-3): "

:: [B-03] メニュー選択分岐
::   choice="1": install_and_clone へジャンプ
::   choice="2": install_only へジャンプ
::   choice="3": clone_only へジャンプ
::   その他: 無効選択メッセージ、menu へ戻る
if "%choice%"=="1" goto install_and_clone
if "%choice%"=="2" goto install_only
if "%choice%"=="3" goto clone_only

echo 無効な選択です。
goto menu

:install_and_clone
:: トークン入力
echo.
set /p "token=Gitアクセストークンを入力してください: "
:: [B-04] トークン入力チェック（install_and_clone）
::   T: インストール処理へ続行
::   F: エラーメッセージ表示、menu へ戻る
if "%token%"=="" (
    echo トークンが入力されていません。
    pause
    goto menu
)

:: インストール実行
echo.
echo インストールを開始します...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Main.ps1" -ConfigPath "%CONFIG_PATH%"

:: [B-05] インストール結果チェック（install_and_clone）
::   T(errorlevel=0): クローン処理へ続行
::   F(errorlevel≠0): トークンクリア、エラーメッセージ表示、exit /b 1
if %errorlevel% neq 0 (
    echo.
    echo インストール中にエラーが発生しました。
    set "token="
    pause
    exit /b 1
)

:: クローン実行
echo.
echo Gitクローンを開始します...
powershell -ExecutionPolicy Bypass -Command "& { $token = ConvertTo-SecureString '%token%' -AsPlainText -Force; & '%SCRIPT_DIR%scripts\Clone-Repositories.ps1' -ConfigPath '%CONFIG_PATH%' -AccessToken $token }"

set "token="
goto end

:install_only
echo.
echo インストールを開始します...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Main.ps1" -ConfigPath "%CONFIG_PATH%"
:: [B-06] インストール結果チェック（install_only）
::   T(errorlevel=0): end へジャンプ
::   F(errorlevel≠0): エラーメッセージ表示、exit /b 1
if %errorlevel% neq 0 (
    echo.
    echo インストール中にエラーが発生しました。
    pause
    exit /b 1
)
goto end

:clone_only
:: トークン入力
echo.
set /p "token=Gitアクセストークンを入力してください: "
:: [B-07] トークン入力チェック（clone_only）
::   T: クローン処理へ続行
::   F: エラーメッセージ表示、menu へ戻る
if "%token%"=="" (
    echo トークンが入力されていません。
    pause
    goto menu
)

echo.
echo Gitクローンを開始します...
powershell -ExecutionPolicy Bypass -Command "& { $token = ConvertTo-SecureString '%token%' -AsPlainText -Force; & '%SCRIPT_DIR%scripts\Clone-Repositories.ps1' -ConfigPath '%CONFIG_PATH%' -AccessToken $token }"

set "token="
goto end

:end
echo.
echo ========================================
echo 処理が完了しました。
echo ========================================
pause
exit /b 0
