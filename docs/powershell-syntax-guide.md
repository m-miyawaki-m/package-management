# PowerShell文法ガイド

本プロジェクトで使用したPowerShell文法の概要と詳細解説。

---

## 目次

1. [スクリプトの基本構造](#1-スクリプトの基本構造)
2. [変数](#2-変数)
3. [パラメータ定義](#3-パラメータ定義)
4. [関数](#4-関数)
5. [制御構文](#5-制御構文)
6. [ハッシュテーブルと配列](#6-ハッシュテーブルと配列)
7. [文字列操作](#7-文字列操作)
8. [ファイル操作](#8-ファイル操作)
9. [JSON操作](#9-json操作)
10. [モジュール](#10-モジュール)
11. [エラーハンドリング](#11-エラーハンドリング)
12. [外部コマンド実行](#12-外部コマンド実行)
13. [出力とログ](#13-出力とログ)
14. [パス操作](#14-パス操作)

---

## 1. スクリプトの基本構造

### 1.1 シバン行とエンコーディング

PowerShellスクリプトは `.ps1` 拡張子で保存。UTF-8（BOM付き推奨）で保存。

```powershell
# scripts/Install-DevEnv.ps1
# 開発環境パッケージ管理 メインスクリプト
```

### 1.2 エラー動作の設定

```powershell
$ErrorActionPreference = "Stop"  # エラー発生時にスクリプトを停止
```

| 値 | 動作 |
|----|------|
| `Stop` | エラーで停止 |
| `Continue` | エラーを表示して継続（デフォルト） |
| `SilentlyContinue` | エラーを無視して継続 |
| `Inquire` | ユーザーに確認 |

### 1.3 スクリプトのパス取得

```powershell
$scriptRoot = $PSScriptRoot  # スクリプト自身のディレクトリパス
```

---

## 2. 変数

### 2.1 基本的な変数

```powershell
$name = "value"           # 文字列
$number = 42              # 数値
$flag = $true             # ブール値（$true / $false）
$nothing = $null          # null値
```

### 2.2 変数のスコープ

```powershell
$script:LogFile = $null   # スクリプトスコープ（同一スクリプト内で共有）
$global:Config = @{}      # グローバルスコープ（セッション全体）
$local:temp = "value"     # ローカルスコープ（現在のブロック内）
```

**本プロジェクトでの使用例:**
```powershell
# Common.ps1
$script:LogFile = $null   # スクリプト全体でログファイルパスを共有

function Initialize-Log {
    $script:LogFile = Join-Path $logDir "install-$ProjectName-$timestamp.log"
}

function Write-Log {
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage
    }
}
```

---

## 3. パラメータ定義

### 3.1 CmdletBinding属性

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Project
)
```

| 属性 | 説明 |
|------|------|
| `[CmdletBinding()]` | 高度な関数機能を有効化（-Verbose, -Debug等） |
| `[Parameter(Mandatory)]` | 必須パラメータ |
| `[Parameter(Mandatory=$false)]` | 任意パラメータ（デフォルト） |

### 3.2 パラメータの型指定

```powershell
param(
    [string]$Name,              # 文字列
    [int]$Count,                # 整数
    [bool]$Flag,                # ブール値
    [string[]]$Items,           # 文字列配列
    [hashtable]$Config          # ハッシュテーブル
)
```

### 3.3 パラメータのバリデーション

```powershell
param(
    [ValidateSet("INFO", "SUCCESS", "SKIPPED", "FAILED", "WARN")]
    [string]$Level = "INFO"     # 許可値を制限 + デフォルト値
)
```

**本プロジェクトでの使用例:**
```powershell
# Common.ps1 - Write-Log関数
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "SKIPPED", "FAILED", "WARN")]
        [string]$Level = "INFO"
    )
    # ...
}
```

---

## 4. 関数

### 4.1 基本的な関数定義

```powershell
function Get-Greeting {
    param([string]$Name)
    return "Hello, $Name!"
}

# 呼び出し
$message = Get-Greeting -Name "World"
```

### 4.2 戻り値

```powershell
function Install-Tool {
    # ハッシュテーブルを返す
    return @{
        Status = "SUCCESS"
        Path = "C:\tools\app"
        Version = "1.0.0"
    }
}

# 呼び出しと結果の使用
$result = Install-Tool
Write-Host $result.Status    # SUCCESS
Write-Host $result.Path      # C:\tools\app
```

### 4.3 スクリプト内関数

```powershell
# Install-DevEnv.ps1内のローカル関数
function Update-Results {
    param([string]$Status)
    switch ($Status) {
        "SUCCESS" { $script:results.Success++ }
        "SKIPPED" { $script:results.Skipped++ }
        "FAILED"  { $script:results.Failed++ }
    }
}
```

---

## 5. 制御構文

### 5.1 if文

```powershell
if (条件) {
    # 処理
} elseif (条件2) {
    # 処理
} else {
    # 処理
}
```

**本プロジェクトでの使用例:**
```powershell
if (-not (Test-Path $settingsPath)) {
    Write-Error "設定ファイルが見つかりません: $settingsPath"
    exit 1
}

if ($projectConfig.certificates -and $projectConfig.certificates.Count -gt 0) {
    # 証明書がある場合のみ処理
}
```

### 5.2 switch文

```powershell
switch ($value) {
    "A" { Write-Host "Aです" }
    "B" { Write-Host "Bです" }
    default { Write-Host "その他" }
}
```

**本プロジェクトでの使用例:**
```powershell
switch ($Level) {
    "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    "SKIPPED" { Write-Host $logMessage -ForegroundColor Yellow }
    "FAILED"  { Write-Host $logMessage -ForegroundColor Red }
    "WARN"    { Write-Host $logMessage -ForegroundColor Yellow }
    default   { Write-Host $logMessage }
}
```

### 5.3 foreach文

```powershell
foreach ($item in $collection) {
    Write-Host $item
}
```

**本プロジェクトでの使用例:**
```powershell
foreach ($certFile in $Certificates) {
    Write-Log "対象: $certFile"
    # 証明書の処理
}
```

---

## 6. ハッシュテーブルと配列

### 6.1 ハッシュテーブル（連想配列）

```powershell
# 作成
$hash = @{
    Key1 = "Value1"
    Key2 = "Value2"
    Nested = @{
        SubKey = "SubValue"
    }
}

# アクセス
$hash.Key1              # Value1
$hash["Key2"]           # Value2
$hash.Nested.SubKey     # SubValue

# 追加・更新
$hash.Key3 = "Value3"
$hash["Key1"] = "NewValue"
```

**本プロジェクトでの使用例:**
```powershell
# 結果カウンター
$results = @{
    Success = 0
    Skipped = 0
    Failed = 0
}

# インクリメント
$results.Success++

# 戻り値
return @{
    Status = "SUCCESS"
    Path = $installPath
    Version = $version
}
```

### 6.2 配列

```powershell
# 作成
$array = @("item1", "item2", "item3")
$empty = @()

# アクセス
$array[0]               # item1
$array[-1]              # item3（最後の要素）
$array.Count            # 3

# 追加
$array += "item4"
```

---

## 7. 文字列操作

### 7.1 文字列展開（ダブルクォート）

```powershell
$name = "World"
$message = "Hello, $name!"           # Hello, World!
$path = "C:\$folder\$file"           # 変数が展開される
```

### 7.2 リテラル文字列（シングルクォート）

```powershell
$literal = 'Hello, $name!'           # Hello, $name!（展開されない）
$regex = '\{\{PROJECT_NAME\}\}'      # 正規表現パターン
```

### 7.3 文字列の置換

```powershell
# -replace演算子（正規表現）
$template = "{{NAME}} is {{AGE}} years old"
$result = $template -replace '\{\{NAME\}\}', 'John'
$result = $result -replace '\{\{AGE\}\}', '30'
```

**本プロジェクトでの使用例:**
```powershell
$batchContent = $template `
    -replace '\{\{PROJECT_NAME\}\}', $projectConfig.name `
    -replace '\{\{GENERATED_AT\}\}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss") `
    -replace '\{\{JAVA_HOME\}\}', $jdkResult.Path
```

### 7.4 フォーマット文字列

```powershell
# Get-Date
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"      # 20260127-143052
$formatted = Get-Date -Format "yyyy-MM-dd HH:mm:ss"  # 2026-01-27 14:30:52
```

---

## 8. ファイル操作

### 8.1 パスの存在確認

```powershell
if (Test-Path $path) {
    # ファイルまたはディレクトリが存在する
}

if (-not (Test-Path $path)) {
    # 存在しない
}
```

### 8.2 ディレクトリ作成

```powershell
New-Item -ItemType Directory -Path $path -Force | Out-Null
```

| パラメータ | 説明 |
|------------|------|
| `-ItemType Directory` | ディレクトリを作成 |
| `-Force` | 親ディレクトリも作成、既存でもエラーにしない |
| `| Out-Null` | 出力を抑制 |

### 8.3 ファイル削除

```powershell
Remove-Item $path -Recurse -Force
```

| パラメータ | 説明 |
|------------|------|
| `-Recurse` | サブディレクトリも含めて削除 |
| `-Force` | 読み取り専用でも削除 |

### 8.4 ファイル移動

```powershell
Move-Item -Path $source -Destination $dest -Force
```

### 8.5 ファイル読み込み

```powershell
$content = Get-Content $path -Raw       # ファイル全体を1つの文字列として読み込み
$lines = Get-Content $path              # 行ごとの配列として読み込み
```

### 8.6 ファイル書き込み

```powershell
Set-Content -Path $path -Value $content -Encoding UTF8
Add-Content -Path $path -Value $line -Encoding UTF8  # 追記
```

### 8.7 ZIP展開

```powershell
Expand-Archive -Path $zipPath -DestinationPath $destPath -Force
```

### 8.8 ディレクトリ内容の取得

```powershell
$items = Get-ChildItem -Path $path
$dirs = Get-ChildItem -Path $path -Directory      # ディレクトリのみ
$files = Get-ChildItem -Path $path -File          # ファイルのみ
$first = Get-ChildItem -Path $path | Select-Object -First 1
```

---

## 9. JSON操作

### 9.1 JSONファイルの読み込み

```powershell
# ハッシュテーブルとして読み込み
$config = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
```

| パラメータ | 説明 |
|------------|------|
| `-Raw` | ファイル全体を1つの文字列として読み込み |
| `-AsHashtable` | PSCustomObjectではなくハッシュテーブルに変換 |

**注意:** `-AsHashtable` はPowerShell 6.0以降で利用可能。

### 9.2 プロパティへのアクセス

```powershell
$settings.shareBasePath              # トップレベルプロパティ
$settings.tools.jdk                  # ネストされたプロパティ
$projectConfig.tools.jdk.version     # 深くネストされたプロパティ
```

---

## 10. モジュール

### 10.1 モジュールのインポート

```powershell
Import-Module $modulePath -Force
```

| パラメータ | 説明 |
|------------|------|
| `-Force` | 既にインポート済みでも再読み込み |

**本プロジェクトでの使用例:**
```powershell
Import-Module (Join-Path $scriptRoot "lib\Common.ps1") -Force
Import-Module (Join-Path $scriptRoot "modules\Install-Jdk.ps1") -Force
```

### 10.2 関数のエクスポート

```powershell
# モジュールファイルの末尾に記述
Export-ModuleMember -Function *              # すべての関数をエクスポート
Export-ModuleMember -Function Install-Jdk    # 特定の関数のみ
```

---

## 11. エラーハンドリング

### 11.1 try-catch文

```powershell
try {
    # エラーが発生する可能性のある処理
    Expand-Archive -Path $zipPath -DestinationPath $destPath -Force
}
catch {
    # エラー処理
    Write-Log "エラー: $_" -Level "FAILED"    # $_ は例外オブジェクト
    return @{ Status = "FAILED" }
}
```

### 11.2 エラー出力とスクリプト終了

```powershell
Write-Error "エラーメッセージ"
exit 1
```

---

## 12. 外部コマンド実行

### 12.1 コマンド実行と終了コード

```powershell
# & 演算子で外部コマンドを実行
$result = & $keytoolPath -list -keystore $cacertsPath -storepass "changeit" -alias $alias 2>&1

# 終了コードの確認
if ($LASTEXITCODE -eq 0) {
    Write-Log "成功"
} else {
    Write-Log "失敗: $result"
}
```

| 要素 | 説明 |
|------|------|
| `&` | コール演算子（コマンド/スクリプトを実行） |
| `2>&1` | 標準エラーを標準出力にリダイレクト |
| `$LASTEXITCODE` | 直前の外部コマンドの終了コード |

**本プロジェクトでの使用例:**
```powershell
# keytoolで証明書をインポート
$importResult = & $keytoolPath -importcert -trustcacerts -keystore $cacertsPath `
    -storepass "changeit" -noprompt -alias $alias -file $certPath 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Log "結果: SUCCESS (キーストアに登録)" -Level "SUCCESS"
} else {
    Write-Log "keytoolエラー: $importResult" -Level "FAILED"
}
```

---

## 13. 出力とログ

### 13.1 コンソール出力

```powershell
Write-Host "メッセージ"                              # 標準出力
Write-Host "成功" -ForegroundColor Green             # 色付き出力
Write-Host "警告" -ForegroundColor Yellow
Write-Host "エラー" -ForegroundColor Red
```

### 13.2 利用可能な色

| 色 | 用途例 |
|----|--------|
| `Green` | 成功 |
| `Yellow` | 警告、スキップ |
| `Red` | エラー |
| `Cyan` | 情報、ヒント |
| `White` | 通常（デフォルト） |

---

## 14. パス操作

### 14.1 パスの結合

```powershell
$path = Join-Path $basePath "subdir" "file.txt"
# 例: C:\base + subdir + file.txt → C:\base\subdir\file.txt
```

### 14.2 親ディレクトリの取得

```powershell
$parent = Split-Path $path -Parent
# 例: C:\base\subdir\file.txt → C:\base\subdir
```

### 14.3 ファイル名の取得

```powershell
$fileName = [System.IO.Path]::GetFileName($path)
# 例: C:\base\file.txt → file.txt

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($path)
# 例: C:\base\file.txt → file
```

---

## 付録: 本プロジェクトで使用したコマンドレット一覧

| コマンドレット | 用途 |
|----------------|------|
| `Get-Content` | ファイル読み込み |
| `Set-Content` | ファイル書き込み |
| `Add-Content` | ファイル追記 |
| `Test-Path` | パス存在確認 |
| `New-Item` | ファイル/ディレクトリ作成 |
| `Remove-Item` | ファイル/ディレクトリ削除 |
| `Move-Item` | ファイル/ディレクトリ移動 |
| `Get-ChildItem` | ディレクトリ内容取得 |
| `Expand-Archive` | ZIP展開 |
| `Join-Path` | パス結合 |
| `Split-Path` | パス分割 |
| `Get-Date` | 日時取得 |
| `ConvertFrom-Json` | JSON解析 |
| `Import-Module` | モジュール読み込み |
| `Export-ModuleMember` | 関数エクスポート |
| `Write-Host` | コンソール出力 |
| `Write-Error` | エラー出力 |
| `Select-Object` | オブジェクト選択/加工 |
