# テスト用設定ファイル運用ガイド

## 概要

`config/tools-test.json` は動作確認用の最小構成ファイル。各タイプ（installer / extract / copy）を1種類ずつ含む。

---

## 使用方法

### テスト実行

```batch
REM Main.ps1 を直接実行（テスト用設定を指定）
powershell -ExecutionPolicy Bypass -File scripts\Main.ps1 -ConfigPath config\tools-test.json
```

### 本番との切り替え

| 用途 | 設定ファイル |
|------|-------------|
| テスト | `config\tools-test.json` |
| 本番 | `config\tools.json` |

---

## 各タイプの動作確認ポイント

### 1. installer タイプ（notepadpp）

**確認項目:**
- [ ] レジストリから `displayName: "Notepad++"` を検索
- [ ] インストール済みバージョンと `version: "8.6.2"` を比較
- [ ] バージョン一致 → SKIPPED
- [ ] バージョン不一致/未インストール → サイレントインストール実行

**レジストリ検索パス:**
```
HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*
HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*
```

**手動確認コマンド:**
```powershell
# インストール済みバージョン確認
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Where-Object { $_.DisplayName -like "*Notepad++*" } |
    Select-Object DisplayName, DisplayVersion
```

### 2. extract タイプ（jdk）

**確認項目:**
- [ ] 共有フォルダからローカルへアーカイブコピー
- [ ] ハッシュ比較でスキップ判定
- [ ] 指定先 `C:\dev-tools\jdk\17` に解凍
- [ ] 解凍先が既存の場合、バックアップ後に解凍

**スキップ条件:**
- ローカルアーカイブのハッシュが共有と一致
- かつ解凍先ディレクトリが存在

### 3. copy タイプ（config-templates）

**確認項目:**
- [ ] 共有フォルダから `C:\dev-tools\config-templates` へコピー
- [ ] ファイルの場合: ハッシュ比較でスキップ判定
- [ ] フォルダの場合: 既存があればバックアップ後にコピー

---

## テスト用共有フォルダ構成

```
\\server\share\packages\
├── notepadpp\
│   └── npp.8.6.2.Installer.x64.exe  ← 単一ファイル必須
├── jdk\
│   └── jdk-17.0.10.7z               ← 単一アーカイブ必須
└── config-templates\
    └── (任意のファイル/フォルダ)
```

**注意:** 各フォルダには単一ファイルのみ配置。複数ファイルがあるとエラー。

---

## カスタマイズ例

### バージョンチェックをスキップ

```json
{
  "name": "test-installer",
  "type": "installer",
  "source": "test-installer",
  "silentArgs": "/S",
  "skipVersionCheck": true
}
```

### 必須ツール（失敗時に即停止）

```json
{
  "name": "critical-tool",
  "type": "installer",
  "source": "critical-tool",
  "version": "1.0.0",
  "displayName": "Critical Tool",
  "silentArgs": "/S",
  "required": true
}
```

### 設定ファイルコピー付き extract

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

---

## トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| `FAILED: 複数ファイルが存在` | sourceフォルダに2つ以上のファイル | 単一ファイルのみ配置 |
| `SKIPPED` なのに古いまま | ハッシュ一致で判定 | ローカルキャッシュ削除 |
| レジストリに見つからない | displayName不一致 | 正確な表示名を確認 |
| インストーラーがFAILED | 終了コードが successCodes 外 | ツール固有の successCodes を追加 |

### ローカルキャッシュクリア

```powershell
# テスト用にローカルキャッシュを削除
Remove-Item "C:\packages\notepadpp" -Recurse -Force
Remove-Item "C:\packages\jdk" -Recurse -Force
Remove-Item "C:\packages\config-templates" -Recurse -Force
```

---

## ログ確認

実行後のログは `C:\dev-tools\logs\` に出力:

| ファイル | 内容 |
|----------|------|
| `install-yyyyMMdd-HHmmss.log` | 詳細ログ |
| `summary-yyyyMMdd-HHmmss.txt` | 結果サマリー |
