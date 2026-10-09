param(
    [Parameter(Mandatory = $true)][string]$Project
)
$ErrorActionPreference = "Stop"

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Normalize([string]$s) {
    return ($s -replace "`r`n", "`n") -replace "`r", ""
}

$proj = (Resolve-Path -LiteralPath $Project).Path
$projGodot = Join-Path $proj "project.godot"
if (-not (Test-Path -LiteralPath $projGodot)) {
    throw "不是 Godot 工程（找不到 project.godot）：$proj"
}

# ---------- project.godot: 确保 convert_text_resources_to_binary=false ----------
$gp = Normalize ([System.IO.File]::ReadAllText($projGodot))
$keyLine = "export/convert_text_resources_to_binary=false"
if ($gp -match "(?m)^export/convert_text_resources_to_binary=") {
    $gp = [regex]::Replace($gp, "(?m)^export/convert_text_resources_to_binary=.*$", $keyLine)
} elseif ($gp -match "(?m)^\[editor\]\s*$") {
    $gp = [regex]::Replace($gp, "(?m)^(\[editor\]\s*)$", "`$1`n$keyLine", 1)
} else {
    if (-not $gp.EndsWith("`n")) { $gp += "`n" }
    $gp += "`n[editor]`n$keyLine`n"
}
[System.IO.File]::WriteAllText($projGodot, $gp, $utf8)
Write-Host "已确保 project.godot: $keyLine"

# ---------- export_presets.cfg: 注入 ModPack 预设 ----------
$presetsPath = Join-Path $proj "export_presets.cfg"
$templatePath = Join-Path $PSScriptRoot "ModPack.preset.cfg"

if (-not (Test-Path -LiteralPath $templatePath)) {
    throw "缺少模板：$templatePath"
}
$template = Normalize ([System.IO.File]::ReadAllText($templatePath))

if (Test-Path -LiteralPath $presetsPath) {
    $presets = Normalize ([System.IO.File]::ReadAllText($presetsPath))
} else {
    $presets = "[runnable_presets]`n`n"
}

if ($presets -match '(?m)^name="ModPack"\s*$') {
    Write-Host "已存在 ModPack 预设，跳过注入。"
} else {
    $matches = [regex]::Matches($presets, "(?m)^\[preset\.(\d+)\]\s*$")
    $maxIndex = -1
    foreach ($m in $matches) {
        $idx = [int]$m.Groups[1].Value
        if ($idx -gt $maxIndex) { $maxIndex = $idx }
    }
    $newIndex = $maxIndex + 1
    $block = $template.Replace("__PRESET_INDEX__", [string]$newIndex)

    if (-not $presets.EndsWith("`n")) { $presets += "`n" }
    $presets += "`n" + $block + "`n"

    if ($presets -match "(?m)^\[runnable_presets\]\s*$") {
        if ($presets -notmatch '(?m)^"ModPack"="ModPack"\s*$') {
            $presets = [regex]::Replace($presets, "(?m)^(\[runnable_presets\]\s*)$", "`$1`n`n`"ModPack`"=`"ModPack`"", 1)
        }
    } else {
        $presets = "[runnable_presets]`n`n`"ModPack`"=`"ModPack`"`n`n" + $presets
    }
    [System.IO.File]::WriteAllText($presetsPath, $presets, $utf8)
    Write-Host "已注入 [preset.$newIndex] name=`"ModPack`" 到 export_presets.cfg"
}

Write-Host ""
Write-Host "下一步："
Write-Host "  1) 把 mod 内容放到  $proj\mods\<mod_id>\  （含 mod.json 与 defs/ 等）"
Write-Host "  2) 运行  .\build_mod.ps1 -Godot <godot> -Project `"$proj`" -ModId <mod_id>"
Write-Host "注意：export_presets.cfg 的改动需在编辑器关闭时进行；若编辑器已打开请重启后再导出。"
