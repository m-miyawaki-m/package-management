# 開発環境パッケージインストーラー 技術リファレンス

---

## 言語思想・設計原則

### PowerShell の基本思想

PowerShellは「動詞-名詞」形式のコマンドレット（Cmdlet）を中心に設計されたシェル言語であり、以下の特徴を持つ。

#### オブジェクトパイプライン

テキストベースの従来型シェル（bash, cmd）とは異なり、PowerShellは**オブジェクト**をパイプラインで受け渡す。

```powershell
# bash: テキスト処理（文字列の解析が必要）
ls -l | grep "^d" | awk '{print $9}'

# PowerShell: オブジェクト処理（プロパティに直接アクセス）
Get-ChildItem | Where-Object { $_.PSIsContainer } | Select-Object Name
```

**利点:**
- 型安全性：プロパティ名が明確、タイプミスで即エラー
- 構造化データ：JSONやXMLとの親和性が高い
- 一貫したAPI：すべてのコマンドレットが同じ方式

#### 動詞-名詞命名規則

```powershell
Get-Content      # 取得
Set-Content      # 設定
New-Item         # 作成
Remove-Item      # 削除
Test-Path        # テスト（存在確認）
Invoke-Command   # 実行
```

| 動詞 | 意味 | 例 |
|------|------|-----|
| `Get` | 取得・読み取り | `Get-Content`, `Get-ChildItem` |
| `Set` | 設定・書き込み | `Set-Content`, `Set-Location` |
| `New` | 新規作成 | `New-Item`, `New-Object` |
| `Remove` | 削除 | `Remove-Item` |
| `Test` | テスト・確認 | `Test-Path`, `Test-Connection` |
| `Invoke` | 実行 | `Invoke-Command`, `Invoke-WebRequest` |
| `Copy` | コピー | `Copy-Item` |
| `Move` | 移動 | `Move-Item` |
| `Import/Export` | インポート/エクスポート | `Import-Module`, `Export-Csv` |
| `ConvertFrom/To` | 変換 | `ConvertFrom-Json`, `ConvertTo-Json` |

#### エラーハンドリング哲学

PowerShellには**終了エラー（Terminating Error）**と**非終了エラー（Non-Terminating Error）**の2種類がある。

```powershell
# 非終了エラー（デフォルト）: 処理継続
Get-Item "存在しないパス"  # エラー表示後、次の行へ

# 終了エラーに変換
$ErrorActionPreference = "Stop"  # スクリプト全体
Get-Item "存在しないパス" -ErrorAction Stop  # 個別コマンド
```

本プロジェクトでは `$ErrorActionPreference = "Stop"` を採用し、予期しないエラーで即座に停止させる。

### 本プロジェクトの設計原則

#### 1. モジュール分離（単一責任）

各モジュールは単一の責務を持つ。

| モジュール | 責務 |
|-----------|------|
| Logger.psm1 | ログ出力と結果集計 |
| FileManager.psm1 | ファイル操作（コピー、ハッシュ、バックアップ） |
| Extractor.psm1 | アーカイブ解凍 |
| Installer.psm1 | インストーラー実行とレジストリ確認 |
| ConfigCopier.psm1 | 設定ファイルコピー |
| FileCopier.psm1 | 汎用ファイル/フォルダコピー |

#### 2. 明示的な戻り値

関数はハッシュテーブルで構造化された結果を返す。

```powershell
# 良い例: 構造化された戻り値
return @{
    Success = $true
    Skipped = $false
    Message = "コピー完了"
}

# 悪い例: ブール値だけでは情報不足
return $true
```

#### 3. 防御的プログラミング

入力値は常に検証し、存在確認を行う。

```powershell
# パターン: 操作前に必ず存在確認
if (-not (Test-Path $Source)) {
    Write-Log -Message "ソースが存在しません: $Source" -Level "ERROR"
    return @{ Success = $false }
}
```

#### 4. 冪等性（べきとうせい）

同じ操作を複数回実行しても結果が変わらない設計。

```powershell
# ハッシュ比較でスキップ判定
if ($sourceHash -eq $destHash) {
    return @{ Success = $true; Skipped = $true }  # 再実行しても安全
}
```

---

## PowerShell 5.1 固有の考慮事項

本プロジェクトはWindows標準のPowerShell 5.1を対象とする。PowerShell 7.x（Core）との互換性は保証しない。

### 5.1 制限事項と回避策

#### ConvertFrom-Json の戻り値

```powershell
# PowerShell 7.x: -AsHashtable オプションが使用可能
$config = Get-Content $path | ConvertFrom-Json -AsHashtable

# PowerShell 5.1: -AsHashtable なし → PSCustomObject が返る
$config = Get-Content $path | ConvertFrom-Json  # PSCustomObject
$config.defaults.sourceRoot  # プロパティアクセスは同じ
```

**PSCustomObjectとHashtableの違い:**
```powershell
# PSCustomObject: キーの動的追加が困難
$obj = [PSCustomObject]@{ Key = "Value" }
$obj.NewKey = "X"  # 動的追加は可能だが非推奨

# Hashtable: 動的操作が容易
$hash = @{ Key = "Value" }
$hash["NewKey"] = "X"  # OK
$hash.ContainsKey("Key")  # メソッドも使用可能
```

本プロジェクトではJSONからの読み込みはPSCustomObjectのまま使用し、スクリプト内で新規作成する場合はHashtableを使用する。

#### 配列の挙動

```powershell
# 要素が1つの場合、配列ではなくスカラーになる
$items = Get-ChildItem "*.txt"  # 1ファイルしかないとスカラー
$items.Count  # エラーまたは予期しない動作

# 回避策: @() で明示的に配列化
$items = @(Get-ChildItem "*.txt")  # 常に配列
$items.Count  # 0, 1, または複数（安全）
```

**本プロジェクトでの適用:**
```powershell
# Logger.psm1 - 結果集計
$succeeded = @($script:Results | Where-Object { $_.Status -eq "SUCCESS" })
$summary.Success = $succeeded.Count  # 0件でも安全
```

#### パイプライン出力の抑制

```powershell
# 戻り値を持つコマンドは意図せず出力に混入する
function Do-Something {
    New-Item -ItemType Directory -Path $path  # ディレクトリ情報が出力される
    return $true
}
# 呼び出し側で $true 以外のオブジェクトも受け取る

# 回避策1: Out-Null
New-Item -ItemType Directory -Path $path | Out-Null

# 回避策2: [void] キャスト
[void](New-Item -ItemType Directory -Path $path)

# 回避策3: $null への代入
$null = New-Item -ItemType Directory -Path $path
```

本プロジェクトでは `| Out-Null` を標準とする。

---

## PowerShell 構文詳細

### 変数とスコープ

#### スコープ修飾子

```powershell
$local:var    # ローカルスコープ（現在のブロック）
$script:var   # スクリプトスコープ（.ps1ファイル全体）
$global:var   # グローバルスコープ（セッション全体）
$private:var  # プライベート（子スコープから不可視）
```

**モジュール内でのスコープ:**
```powershell
# Logger.psm1
$script:LogFile = $null           # モジュール内で共有
$script:Results = [System.Collections.Generic.List[hashtable]]::new()

function Initialize-Log {
    $script:LogFile = "path/to/log"  # $script: が必要
}
```

#### 自動変数

| 変数 | 内容 |
|------|------|
| `$_` / `$PSItem` | パイプラインの現在のオブジェクト |
| `$?` | 直前のコマンドの成功/失敗（$true/$false） |
| `$LASTEXITCODE` | 直前の外部コマンドの終了コード |
| `$PSScriptRoot` | 実行中スクリプトのディレクトリ |
| `$PSCommandPath` | 実行中スクリプトのフルパス |
| `$args` | 関数に渡された未バインド引数 |
| `$null` | null値 |
| `$true` / `$false` | ブール値 |

### 演算子

#### 比較演算子

```powershell
-eq    # 等しい (equal)
-ne    # 等しくない (not equal)
-gt    # より大きい (greater than)
-ge    # 以上 (greater or equal)
-lt    # より小さい (less than)
-le    # 以下 (less or equal)
-like  # ワイルドカードマッチ
-match # 正規表現マッチ
```

```powershell
# 大文字小文字を区別する場合は 'c' プレフィックス
"ABC" -ceq "abc"  # $false
"ABC" -eq "abc"   # $true（デフォルトは case-insensitive）
```

#### 論理演算子

```powershell
-and   # AND
-or    # OR
-not   # NOT（! も可）
-xor   # XOR
```

```powershell
if (-not (Test-Path $path) -and $required) {
    Write-Error "必須ファイルがありません"
}
```

#### 文字列演算子

```powershell
-replace  # 正規表現置換
-split    # 分割
-join     # 結合
-contains # 配列に要素が含まれるか
-in       # 要素が配列に含まれるか
```

```powershell
# -replace: 正規表現（エスケープに注意）
"file.txt" -replace '\.txt$', '.bak'  # file.bak

# -split / -join
"a,b,c" -split ","      # @("a", "b", "c")
@("a", "b", "c") -join ","  # "a,b,c"

# -contains vs -in（順序が逆）
@(1, 2, 3) -contains 2  # $true
2 -in @(1, 2, 3)        # $true
```

### パラメータ定義

#### 高度な関数

```powershell
function Invoke-SilentInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [string]$SilentArgs,

        [Parameter()]
        [int[]]$SuccessCodes = @(0)
    )

    # 関数本体
}
```

| 属性 | 説明 |
|------|------|
| `[CmdletBinding()]` | 高度な関数機能を有効化 |
| `[Parameter(Mandatory)]` | 必須パラメータ |
| `[Parameter(Mandatory=$false)]` | 任意パラメータ（省略時デフォルト） |
| `[ValidateSet("A","B","C")]` | 許可値を制限 |
| `[ValidateRange(1,100)]` | 数値範囲を制限 |
| `[ValidateNotNullOrEmpty()]` | null/空文字を禁止 |

#### スプラッティング

多数のパラメータを渡す際に可読性を向上させる技法。

```powershell
# 通常の呼び出し（長い）
Copy-Item -Path $source -Destination $dest -Force -Recurse

# スプラッティング（ハッシュテーブル）
$params = @{
    Path = $source
    Destination = $dest
    Force = $true
    Recurse = $true
}
Copy-Item @params  # @ で展開
```

### エラーハンドリング

#### try-catch-finally

```powershell
try {
    $result = Invoke-RiskyOperation
}
catch [System.IO.FileNotFoundException] {
    # 特定の例外をキャッチ
    Write-Log "ファイルが見つかりません: $($_.Exception.Message)"
}
catch {
    # すべての例外をキャッチ
    Write-Log "予期しないエラー: $_"
}
finally {
    # 常に実行（クリーンアップ処理）
    if ($resource) { $resource.Dispose() }
}
```

#### $ErrorActionPreference

```powershell
$ErrorActionPreference = "Stop"           # スクリプト全体に適用
Get-Item "path" -ErrorAction SilentlyContinue  # 個別コマンドで上書き
```

| 値 | 動作 |
|----|------|
| `Stop` | 終了エラーとして停止 |
| `Continue` | エラー表示後、継続（デフォルト） |
| `SilentlyContinue` | エラーを無視して継続 |
| `Inquire` | ユーザーに確認 |

### .NET統合

PowerShellは.NET Frameworkと密接に統合されており、.NETクラスを直接使用できる。

#### 静的メソッド呼び出し

```powershell
[System.IO.Path]::GetFileName("C:\path\file.txt")  # file.txt
[System.IO.Path]::Combine("C:\base", "sub", "file.txt")  # C:\base\sub\file.txt
[Environment]::ExpandEnvironmentVariables("%APPDATA%\config")  # C:\Users\...\AppData\Roaming\config
[System.IO.File]::Exists($path)  # Test-Path の代替
```

#### オブジェクトのインスタンス化

```powershell
# new() 静的メソッド（推奨）
$list = [System.Collections.Generic.List[string]]::new()
$list.Add("item")

# New-Object コマンドレット
$list = New-Object System.Collections.Generic.List[string]

# コンストラクタ呼び出し
$encoding = [System.Text.Encoding]::UTF8
```

#### 本プロジェクトでの.NET使用例

```powershell
# Logger.psm1 - 高速なリスト操作
$script:Results = [System.Collections.Generic.List[hashtable]]::new()
$script:Results.Add(@{ ToolName = "git"; Status = "SUCCESS" })

# ConfigCopier.psm1 - 環境変数展開
$expandedPath = [Environment]::ExpandEnvironmentVariables($DestinationPath)

# Clone-Repositories.ps1 - SecureString処理
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccessToken)
$plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
```

### モジュール構造

#### .psm1 ファイル構成

```powershell
# scripts/modules/Example.psm1

# スクリプトスコープ変数
$script:InternalState = $null

# プライベート関数（エクスポートしない）
function Get-InternalValue {
    return $script:InternalState
}

# パブリック関数
function Initialize-Example {
    param([string]$Value)
    $script:InternalState = $Value
}

function Get-Example {
    return Get-InternalValue
}

# エクスポート（明示的に公開する関数を指定）
Export-ModuleMember -Function Initialize-Example, Get-Example
```

#### モジュールのインポート

```powershell
# 相対パスでのインポート
Import-Module (Join-Path $PSScriptRoot "modules\Logger.psm1") -Force

# -Force: 既にインポート済みでも再読み込み（開発時に有用）
```

---

## tools.json 構造

### 全体構造

```json
{
  "defaults": { ... },
  "tools": [ ... ],
  "repositories": [ ... ]
}
```

### defaults セクション

```json
{
  "defaults": {
    "sourceRoot": "\\\\server\\share\\packages",
    "localRoot": "C:\\packages",
    "destRoot": "C:\\dev-tools",
    "backupRoot": "C:\\packages\\bk",
    "logRoot": "C:\\dev-tools\\logs",
    "7zPath": "C:\\dev-tools\\7zip\\7z.exe",
    "successCodes": [0, 3010]
  }
}
```

| キー | 型 | 説明 |
|------|------|------|
| `sourceRoot` | string | 共有ディレクトリのルートパス |
| `localRoot` | string | ローカルキャッシュディレクトリ |
| `destRoot` | string | インストール先のデフォルトルート |
| `backupRoot` | string | バックアップ保存先ルート |
| `logRoot` | string | ログファイル出力先 |
| `7zPath` | string | 7z.exe のパス |
| `successCodes` | int[] | インストーラー成功とみなす終了コード |

### tools 配列

#### installer タイプ

```json
{
  "name": "git",
  "type": "installer",
  "source": "git",
  "version": "2.43.0",
  "displayName": "Git",
  "silentArgs": "/VERYSILENT /NORESTART",
  "required": false,
  "skipVersionCheck": false,
  "successCodes": [0, 3010]
}
```

| キー | 必須 | 型 | 説明 |
|------|------|------|------|
| `name` | ○ | string | ツール識別名 |
| `type` | ○ | string | `"installer"` 固定 |
| `source` | ○ | string | sourceRoot からの相対フォルダ名 |
| `version` | △ | string | 期待バージョン（レジストリ比較用） |
| `displayName` | △ | string | レジストリ表示名（部分一致検索用） |
| `silentArgs` | ○ | string | サイレントインストール引数 |
| `required` | - | bool | true: 失敗時に即停止 |
| `skipVersionCheck` | - | bool | true: バージョン確認スキップ |
| `successCodes` | - | int[] | defaults を上書き |

#### extract タイプ

```json
{
  "name": "eclipse",
  "type": "extract",
  "source": "eclipse",
  "destination": "C:\\dev-tools\\eclipse"
}
```

| キー | 必須 | 型 | 説明 |
|------|------|------|------|
| `name` | ○ | string | ツール識別名 |
| `type` | ○ | string | `"extract"` 固定 |
| `source` | ○ | string | sourceRoot からの相対フォルダ名 |
| `destination` | ○ | string | 解凍先ディレクトリ |

#### extract + configCopy タイプ

```json
{
  "name": "sqldeveloper",
  "type": "extract",
  "source": "sqldeveloper",
  "destination": "C:\\dev-tools\\sqldeveloper",
  "configCopy": {
    "source": "connections.xml",
    "destination": "%APPDATA%\\SQL Developer\\system\\connections.xml"
  }
}
```

| キー | 必須 | 型 | 説明 |
|------|------|------|------|
| `configCopy.source` | ○ | string | 共有フォルダ内のファイル名 |
| `configCopy.destination` | ○ | string | コピー先パス（環境変数可） |

#### copy タイプ

```json
{
  "name": "modheader",
  "type": "copy",
  "source": "chrome-plugins",
  "destination": "C:\\dev-tools\\chrome-plugins\\modheader"
}
```

| キー | 必須 | 型 | 説明 |
|------|------|------|------|
| `name` | ○ | string | ツール識別名 |
| `type` | ○ | string | `"copy"` 固定 |
| `source` | ○ | string | sourceRoot からの相対フォルダ名 |
| `destination` | ○ | string | コピー先パス |

### repositories 配列

```json
{
  "repositories": [
    {
      "name": "project-main",
      "url": "https://github.com/org/project-main.git",
      "destination": "C:\\workspace\\project-main"
    }
  ]
}
```

| キー | 必須 | 型 | 説明 |
|------|------|------|------|
| `name` | ○ | string | リポジトリ識別名 |
| `url` | ○ | string | Git リポジトリ URL |
| `destination` | ○ | string | クローン先ディレクトリ |

---

## スクリプト詳細フロー

### Install.bat フロー

```
┌─────────────────────────────────────────────────────────────────┐
│ Install.bat 起動                                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. UTF-8 設定                                                   │
│    chcp 65001                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. 管理者権限チェック                                           │
│    net session >nul 2>&1                                        │
│    → 失敗: "管理者として実行してください" → exit 1              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. 設定ファイル確認                                             │
│    %SCRIPT_DIR%config\tools.json 存在チェック                   │
│    → 不在: エラー表示 → exit 1                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. メニュー表示                                                 │
│    ========================================                     │
│      開発環境セットアップ                                       │
│    ========================================                     │
│    1. インストール + Gitクローン自動実行                        │
│    2. インストールのみ                                          │
│    3. Gitクローンのみ                                           │
│    ----------------------------------------                     │
│    選択してください (1-3):                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ 選択 1          │ │ 選択 2          │ │ 選択 3          │
│ トークン入力    │ │                 │ │ トークン入力    │
│ Main.ps1 実行   │ │ Main.ps1 実行   │ │                 │
│ Clone実行       │ │                 │ │ Clone実行       │
└─────────────────┘ └─────────────────┘ └─────────────────┘
          │                   │                   │
          └───────────────────┼───────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. 完了メッセージ表示                                           │
│    exit 0                                                       │
└─────────────────────────────────────────────────────────────────┘
```

### Main.ps1 フロー

```
┌─────────────────────────────────────────────────────────────────┐
│ Main.ps1 起動 (-ConfigPath パラメータ)                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. モジュール読み込み                                           │
│    Import-Module Logger.psm1                                    │
│    Import-Module FileManager.psm1                               │
│    Import-Module Extractor.psm1                                 │
│    Import-Module Installer.psm1                                 │
│    Import-Module ConfigCopier.psm1                              │
│    Import-Module FileCopier.psm1                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. 設定ファイル読み込み                                         │
│    $config = Get-Content | ConvertFrom-Json                     │
│    $defaults = $config.defaults                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. ログ初期化                                                   │
│    Initialize-Log -LogRoot $defaults.logRoot                    │
│    → install-yyyyMMdd-HHmmss.log 作成                           │
│    → summary-yyyyMMdd-HHmmss.txt 作成                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. 共有ディレクトリアクセスチェック                             │
│    Test-ShareAccess -SharePath $defaults.sourceRoot             │
│    → 失敗: FATAL ログ出力 → exit 1                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. タイムスタンプ生成                                           │
│    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"              │
│    （全ツールで共通使用）                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. ツールループ開始                                             │
│    foreach ($tool in $config.tools) { ... }                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ 6.1 共有からファイル情報取得  │
              │ Get-SingleFileFromFolder      │
              │ → 複数ファイル: FAILED        │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ 6.2 タイプ別処理分岐          │
              │ switch ($tool.type)           │
              └───────────────────────────────┘
                              │
       ┌──────────────────────┼──────────────────────┐
       ▼                      ▼                      ▼
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│ installer    │       │ extract      │       │ copy         │
│ 処理フロー   │       │ 処理フロー   │       │ 処理フロー   │
│ (後述)       │       │ (後述)       │       │ (後述)       │
└──────────────┘       └──────────────┘       └──────────────┘
       │                      │                      │
       └──────────────────────┼──────────────────────┘
                              ▼
              ┌───────────────────────────────┐
              │ 6.3 結果記録                  │
              │ Add-Result -Status SUCCESS    │
              │           / SKIPPED / FAILED  │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ 次のツールへ (ループ継続)     │
              └───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 7. サマリー出力                                                 │
│    Write-Summary                                                │
│    → コンソール + summary-*.txt に結果テーブル出力              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 8. 終了                                                         │
│    失敗あり: exit 1 / すべて成功: exit 0                        │
└─────────────────────────────────────────────────────────────────┘
```

### installer タイプ処理フロー

```
┌─────────────────────────────────────────────────────────────────┐
│ installer タイプ処理開始                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. バージョンチェック（skipVersionCheck=false の場合）          │
│    Get-InstalledVersion -DisplayName $tool.displayName          │
│    ↓                                                            │
│    ┌─ インストール済み ─────────────────────────────────────┐   │
│    │ Test-VersionMatch -InstalledVersion -TargetVersion     │   │
│    │ → 一致: SKIPPED "バージョン一致" → 処理終了            │   │
│    │ → 不一致: インストール続行                             │   │
│    └────────────────────────────────────────────────────────┘   │
│    ┌─ 未インストール ───────────────────────────────────────┐   │
│    │ → インストール続行                                     │   │
│    └────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. ハッシュ比較 (共有 vs ローカル)                              │
│    $sourceHash = Get-FileHashSHA256 (共有ファイル)              │
│    $localHash = Get-FileHashSHA256 (ローカルファイル)           │
│    ↓                                                            │
│    ┌─ ローカルなし / ハッシュ不一致 ────────────────────────┐   │
│    │ Backup-File (既存があれば)                             │   │
│    │ Copy-FileWithProgress (共有→ローカル)                  │   │
│    └────────────────────────────────────────────────────────┘   │
│    ┌─ ハッシュ一致 ─────────────────────────────────────────┐   │
│    │ コピーをスキップ（既存ローカルファイル使用）           │   │
│    └────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. インストーラー実行                                           │
│    Invoke-SilentInstall -InstallerPath -SilentArgs              │
│                         -SuccessCodes                           │
│    ↓                                                            │
│    ┌─ 成功 (exit code in successCodes) ─────────────────────┐   │
│    │ → SUCCESS                                              │   │
│    └────────────────────────────────────────────────────────┘   │
│    ┌─ 失敗 ─────────────────────────────────────────────────┐   │
│    │ required=true: FATAL → exit 1                          │   │
│    │ required=false: FAILED → 次ツールへ継続                │   │
│    └────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### extract タイプ処理フロー

```
┌─────────────────────────────────────────────────────────────────┐
│ extract タイプ処理開始                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. ハッシュ比較 (共有 vs ローカル)                              │
│    $sourceHash = Get-FileHashSHA256 (共有アーカイブ)            │
│    $localHash = Get-FileHashSHA256 (ローカルアーカイブ)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. スキップ判定                                                 │
│    ┌─ ハッシュ一致 AND 解凍先存在 ──────────────────────────┐   │
│    │ → SKIPPED "ハッシュ一致"                               │   │
│    └────────────────────────────────────────────────────────┘   │
│    ┌─ ハッシュ一致 AND 解凍先なし ──────────────────────────┐   │
│    │ → WARNING "ハッシュ一致だが解凍先なし。再解凍します"   │   │
│    │ → 解凍処理へ                                           │   │
│    └────────────────────────────────────────────────────────┘   │
│    ┌─ ハッシュ不一致 / ローカルなし ────────────────────────┐   │
│    │ Backup-File (既存アーカイブがあれば)                   │   │
│    │ Copy-FileWithProgress (共有→ローカル)                  │   │
│    │ → 解凍処理へ                                           │   │
│    └────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. 解凍処理                                                     │
│    Invoke-Extract -ArchivePath -Destination                     │
│                   -SevenZipPath -BackupRoot -Timestamp          │
│    ↓                                                            │
│    ┌─ 解凍先が既に存在 ─────────────────────────────────────┐   │
│    │ Backup-Directory (7z圧縮 → backupRoot へ移動)          │   │
│    │ 既存ディレクトリ削除                                   │   │
│    └────────────────────────────────────────────────────────┘   │
│    ↓                                                            │
│    7z x archive -o"destination" -y                              │
│    または Expand-Archive (.zip で 7z.exe 未インストール時)      │
│    → 成功: SUCCESS / 失敗: FAILED                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. configCopy 処理（configCopy 設定がある場合のみ）             │
│    Copy-ConfigFile -SourcePath (共有フォルダ内)                 │
│                    -DestinationPath (環境変数展開)              │
│                    -BackupRoot -Timestamp                       │
│    ↓                                                            │
│    ┌─ コピー先に既存ファイルあり ───────────────────────────┐   │
│    │ backupRoot/timestamp/ にバックアップ                   │   │
│    └────────────────────────────────────────────────────────┘   │
│    ↓                                                            │
│    ファイルコピー実行                                           │
└─────────────────────────────────────────────────────────────────┘
```

### copy タイプ処理フロー

```
┌─────────────────────────────────────────────────────────────────┐
│ copy タイプ処理開始                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Copy-ToolFiles 呼び出し                                      │
│    -SourcePath (共有ファイル/フォルダ)                          │
│    -DestinationPath (コピー先)                                  │
│    -BackupRoot -Timestamp                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. ファイル/フォルダ自動判定                                    │
│    $isDirectory = (Get-Item $SourcePath).PSIsContainer          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. コピー先存在チェック & ハッシュ比較（ファイルの場合）        │
│    ┌─ コピー先なし ─────────────────────────────────────────┐   │
│    │ → コピー実行へ                                         │   │
│    └────────────────────────────────────────────────────────┘   │
│    ┌─ コピー先あり（ファイル） ─────────────────────────────┐   │
│    │ $sourceHash = Get-FileHashSHA256 (共有)                │   │
│    │ $destHash = Get-FileHashSHA256 (コピー先)              │   │
│    │ → 一致: SKIPPED "ハッシュ一致"                         │   │
│    │ → 不一致: バックアップ後、コピー実行                   │   │
│    └────────────────────────────────────────────────────────┘   │
│    ┌─ コピー先あり（フォルダ） ─────────────────────────────┐   │
│    │ → バックアップ後、コピー実行                           │   │
│    └────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. バックアップ & コピー実行                                    │
│    ┌─ バックアップ ────────────────────────────────────────┐    │
│    │ Move-Item → backupRoot/timestamp/itemName             │    │
│    └───────────────────────────────────────────────────────┘    │
│    ┌─ コピー ──────────────────────────────────────────────┐    │
│    │ フォルダ: Copy-Item -Recurse                          │    │
│    │ ファイル: Copy-Item                                   │    │
│    └───────────────────────────────────────────────────────┘    │
│    → 成功: SUCCESS / 失敗: FAILED                               │
└─────────────────────────────────────────────────────────────────┘
```

### Clone-Repositories.ps1 フロー

```
┌─────────────────────────────────────────────────────────────────┐
│ Clone-Repositories.ps1 起動                                     │
│ -ConfigPath (設定ファイルパス)                                  │
│ -AccessToken (SecureString)                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. モジュール読み込み                                           │
│    Import-Module Logger.psm1                                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. 設定ファイル読み込み & ログ初期化                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Git インストール確認                                         │
│    git --version                                                │
│    → 失敗: FATAL "Gitがインストールされていません" → exit 1     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. SecureString → 平文変換                                      │
│    Marshal::SecureStringToBSTR                                  │
│    Marshal::PtrToStringAuto                                     │
│    Marshal::ZeroFreeBSTR (メモリクリア)                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. リポジトリループ                                             │
│    foreach ($repo in $config.repositories) { ... }              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ 5.1 クローン先存在チェック    │
              │ → 存在: SKIPPED "既存"        │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ 5.2 親ディレクトリ作成        │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ 5.3 URLにトークン埋め込み     │
              │ https://TOKEN@github.com/...  │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ 5.4 git clone 実行            │
              │ → 成功: SUCCESS               │
              │ → 失敗: FAILED                │
              └───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. トークン変数クリア                                           │
│    $tokenPlainText = $null                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 7. サマリー出力 & 終了                                          │
│    失敗あり: exit 1 / すべて成功: exit 0                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## モジュール関数一覧

### Logger.psm1

| 関数 | パラメータ | 戻り値 | 説明 |
|------|-----------|--------|------|
| `Initialize-Log` | `-LogRoot` | void | ログ初期化、ファイル作成 |
| `Write-Log` | `-Message`, `-Level`, `-IsSection` | void | ログ出力（コンソール+ファイル） |
| `Write-LogSection` | `-ToolName` | void | セクションヘッダ出力 |
| `Write-LogProgress` | `-Operation`, `-CurrentBytes`, `-TotalBytes` | void | 進行度出力 |
| `Add-Result` | `-ToolName`, `-Type`, `-Status`, `-LocalVersion`, `-SharedVersion`, `-Note` | void | 結果エントリ追加 |
| `Write-Summary` | なし | hashtable | サマリーテーブル出力、集計返却 |

### FileManager.psm1

| 関数 | パラメータ | 戻り値 | 説明 |
|------|-----------|--------|------|
| `Get-FileHashSHA256` | `-FilePath`, `-OperationName` | string/null | SHA256ハッシュ計算 |
| `Copy-FileWithProgress` | `-Source`, `-Destination`, `-OperationName` | bool | 進行度付きコピー |
| `Backup-File` | `-FilePath`, `-BackupRoot`, `-Timestamp` | bool | ファイルをバックアップ |
| `Get-SingleFileFromFolder` | `-FolderPath`, `-ExcludeFile` | hashtable | フォルダから単一ファイル取得 |
| `Test-ShareAccess` | `-SharePath` | bool | 共有アクセス確認 |

### Extractor.psm1

| 関数 | パラメータ | 戻り値 | 説明 |
|------|-----------|--------|------|
| `Invoke-Extract` | `-ArchivePath`, `-Destination`, `-SevenZipPath`, `-BackupRoot`, `-Timestamp` | bool | アーカイブ解凍 |
| `Backup-Directory` | `-DirectoryPath`, `-BackupRoot`, `-Timestamp`, `-SevenZipPath` | bool | ディレクトリを圧縮バックアップ |

### Installer.psm1

| 関数 | パラメータ | 戻り値 | 説明 |
|------|-----------|--------|------|
| `Get-InstalledVersion` | `-DisplayName` | hashtable | レジストリからバージョン取得 |
| `Invoke-SilentInstall` | `-InstallerPath`, `-SilentArgs`, `-SuccessCodes` | hashtable | サイレントインストール実行 |
| `Test-VersionMatch` | `-InstalledVersion`, `-TargetVersion` | bool | バージョン比較 |

### ConfigCopier.psm1

| 関数 | パラメータ | 戻り値 | 説明 |
|------|-----------|--------|------|
| `Copy-ConfigFile` | `-SourcePath`, `-DestinationPath`, `-BackupRoot`, `-Timestamp` | bool | 設定ファイルコピー（環境変数展開） |

### FileCopier.psm1

| 関数 | パラメータ | 戻り値 | 説明 |
|------|-----------|--------|------|
| `Copy-ToolFiles` | `-SourcePath`, `-DestinationPath`, `-BackupRoot`, `-Timestamp` | hashtable | ファイル/フォルダコピー |

---

## バックアップ命名規則

| 対象 | バックアップ先 | 例 |
|------|----------------|-----|
| アーカイブファイル | `backupRoot/timestamp/filename` | `C:\packages\bk\20260203-103000\jdk-17.7z` |
| 解凍先ディレクトリ | `backupRoot/timestamp/dirname-timestamp.7z` | `C:\packages\bk\20260203-103000\eclipse-20260203-103000.7z` |
| コピー対象 | `backupRoot/timestamp/itemname` | `C:\packages\bk\20260203-103000\modheader` |
| 設定ファイル | `backupRoot/timestamp/parentdir_filename` | `C:\packages\bk\20260203-103000\system_connections.xml` |

---

## ログレベルと色

| レベル | 色 | 用途 |
|--------|------|------|
| `INFO` | 白 | 通常情報 |
| `SUCCESS` | 緑 | 処理成功 |
| `SKIPPED` | 黄 | スキップ（問題なし） |
| `WARNING` | 黄 | 警告（継続可能） |
| `ERROR` | 赤 | エラー（処理失敗） |
| `FATAL` | 赤背景+白文字 | 致命的エラー（即停止） |
| セクション | シアン | `===`, `---` 区切り線 |
