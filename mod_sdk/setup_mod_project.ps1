param(
    [Parameter(Mandatory = $true)][string]$Project,
    [switch]$Replace
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

# ---------- export_presets.cfg: 注入预设（ModPack；-Replace 时另加 ModPackReplace） ----------
function Add-Preset([string]$TemplateName, [string]$PresetName, [string]$PresetsIn) {
    if ($PresetsIn -match ('(?m)^name="' + [regex]::Escape($PresetName) + '"\s*$')) {
        Write-Host "已存在 $PresetName 预设，跳过注入。"
        return $PresetsIn
    }
    $templatePath = Join-Path $PSScriptRoot $TemplateName
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "缺少模板：$templatePath"
    }
    $template = Normalize ([System.IO.File]::ReadAllText($templatePath))

    $matches = [regex]::Matches($PresetsIn, "(?m)^\[preset\.(\d+)\]\s*$")
    $maxIndex = -1
    foreach ($m in $matches) {
        $idx = [int]$m.Groups[1].Value
        if ($idx -gt $maxIndex) { $maxIndex = $idx }
    }
    $newIndex = $maxIndex + 1
    $block = $template.Replace("__PRESET_INDEX__", [string]$newIndex)

    if (-not $PresetsIn.EndsWith("`n")) { $PresetsIn += "`n" }
    $PresetsIn += "`n" + $block + "`n"

    if ($PresetsIn -match "(?m)^\[runnable_presets\]\s*$") {
        $entryRe = '(?m)^"' + [regex]::Escape($PresetName) + '"="' + [regex]::Escape($PresetName) + '"\s*$'
        if ($PresetsIn -notmatch $entryRe) {
            $PresetsIn = [regex]::Replace($PresetsIn, "(?m)^(\[runnable_presets\]\s*)$", "`$1`n`n`"$PresetName`"=`"$PresetName`"", 1)
        }
    } else {
        $PresetsIn = "[runnable_presets]`n`n`"$PresetName`"=`"$PresetName`"`n`n" + $PresetsIn
    }
    Write-Host "已注入 [preset.$newIndex] name=`"$PresetName`" 到 export_presets.cfg"
    return $PresetsIn
}

$presetsPath = Join-Path $proj "export_presets.cfg"
if (Test-Path -LiteralPath $presetsPath) {
    $presets = Normalize ([System.IO.File]::ReadAllText($presetsPath))
} else {
    $presets = "[runnable_presets]`n`n"
}

$presets = Add-Preset "ModPack.preset.cfg" "ModPack" $presets
if ($Replace) {
    $presets = Add-Preset "ModPackReplace.preset.cfg" "ModPackReplace" $presets
}
[System.IO.File]::WriteAllText($presetsPath, $presets, $utf8)

Write-Host ""
Write-Host "下一步："
Write-Host "  1) 把 mod 内容放到  $proj\mods\<mod_id>\  （含 mod.json 与 defs/ 等）"
Write-Host "  2) 普通构建： .\build_mod.ps1 -Godot <godot> -Project `"$proj`" -ModId <mod_id>"
if ($Replace) {
    Write-Host "     覆盖构建： .\build_mod.ps1 -Godot <godot> -Project `"$proj`" -ModId <mod_id> -Preset ModPackReplace"
    Write-Host "     并在 mod.json 写 replace_files=true 与可选 replace_paths（要覆盖的本体 res:// 文件）"
} else {
    Write-Host "     需要覆盖本体文件时，重新运行本脚本并加 -Replace 注入 ModPackReplace 预设。"
}
Write-Host "注意：export_presets.cfg 的改动需在编辑器关闭时进行；若编辑器已打开请重启后再导出。"
