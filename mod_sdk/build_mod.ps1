param(
    [string]$Godot = "godot",
    [string]$Project = ".",
    [Parameter(Mandatory = $true)][string]$ModId
)
$ErrorActionPreference = "Stop"

$modDir = Join-Path $Project "mods\$ModId"
if (-not (Test-Path (Join-Path $modDir "mod.json"))) {
    throw "找不到 mod.json：$modDir\mod.json"
}

$outDir = Join-Path $Project "build"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$pck = Join-Path $outDir "$ModId.pck"
if (Test-Path $pck) { Remove-Item -Force $pck }

Write-Host "导出 pck（preset: ModPack）..."
& $Godot --headless --path $Project --export-pack "ModPack" $pck
if (-not (Test-Path $pck)) { throw "导出失败，未生成 $pck（确认存在名为 ModPack 的导出预设）" }

$stage = Join-Path $outDir $ModId
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $modDir "mod.json") (Join-Path $stage "mod.json")
Copy-Item $pck (Join-Path $stage "$ModId.pck")
if (Test-Path (Join-Path $modDir "icon.png")) {
    Copy-Item (Join-Path $modDir "icon.png") (Join-Path $stage "icon.png")
}

$zip = Join-Path $outDir "$ModId.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Write-Host "已生成：$zip"
