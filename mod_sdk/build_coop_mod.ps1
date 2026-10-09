<#
.SYNOPSIS
  直接用 PCKPacker 打包 mod 源（无需工程副本/导出预设），并可选安装到 user://mods。

.EXAMPLE
  .\build_coop_mod.ps1
  .\build_coop_mod.ps1 -Install
#>
param(
    [string]$Godot = "H:\Godot_v4.7-stable_win64.exe",
    [string]$Project = "H:\Enter The Nyangeon",
    [string]$ModId = "etn_coop",
    [string]$Source = "",
    [switch]$Install
)
# Godot 在 stderr 输出 warning（如 ObjectDB leak）不应中断脚本；显式 throw 仍会终止。
$ErrorActionPreference = "Continue"

if ($Source -eq "") {
    $Source = Join-Path $PSScriptRoot "coop_mod\mods\$ModId"
}
if (-not (Test-Path -LiteralPath (Join-Path $Source "mod.json"))) {
    throw "找不到 mod.json：$Source\mod.json"
}

# 从 mod.json 读取版本号，用于自动命名版本化归档 etn_coop_<version>.zip
# 按 UTF-8 读取（mod.json 含中文等非 ASCII 时，PowerShell 5.1 默认 ANSI 读取会解析失败）
$manifest = [System.IO.File]::ReadAllText((Join-Path $Source "mod.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$version = ""
if ($manifest -and $manifest.version) { $version = [string]$manifest.version }
if ($version -eq "") { Write-Warning "mod.json 缺少 version，跳过版本化归档命名" }

$outDir = Join-Path $PSScriptRoot "coop_mod\build"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$pck = Join-Path $outDir "$ModId.pck"
if (Test-Path -LiteralPath $pck) { Remove-Item -Force $pck }

Write-Host "打包 pck：$pck"
$packer = Join-Path $PSScriptRoot "pack_mod.gd"
& $Godot --headless --path $Project --script $packer -- `
    "--mod-source=$Source" "--out=$pck" "--mod-id=$ModId" 2>&1 | ForEach-Object { $_ }
if (-not (Test-Path -LiteralPath $pck)) { throw "打包失败：未生成 $pck" }

$stage = Join-Path $outDir $ModId
if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Source "mod.json") (Join-Path $stage "mod.json")
Copy-Item $pck (Join-Path $stage "$ModId.pck")
if (Test-Path -LiteralPath (Join-Path $Source "icon.png")) {
    Copy-Item (Join-Path $Source "icon.png") (Join-Path $stage "icon.png")
}

$zip = Join-Path $outDir "$ModId.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Write-Host "已生成：$zip"

# 版本化归档：etn_coop_<version>.zip（对齐既有分发命名）
if ($version -ne "") {
    $zipVersioned = Join-Path $outDir "$ModId`_$version.zip"
    if (Test-Path -LiteralPath $zipVersioned) { Remove-Item -Force $zipVersioned }
    Copy-Item -LiteralPath $zip -Destination $zipVersioned -Force
    Write-Host "已生成版本归档：$zipVersioned"
}

if ($Install) {
    $dest = Join-Path $env:APPDATA "Godot\app_userdata\Enter The Nyangeon\mods\$ModId"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item (Join-Path $stage "*") $dest -Recurse -Force
    Write-Host "已安装到：$dest（重启游戏生效）"
}
