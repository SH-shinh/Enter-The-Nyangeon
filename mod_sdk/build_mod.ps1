param(
    [string]$Godot = "godot",
    [string]$Project = ".",
    [string]$Preset = "ModPack",
    [Parameter(Mandatory = $true)][string]$ModId
)
$ErrorActionPreference = "Stop"

$proj = (Resolve-Path -LiteralPath $Project).Path
$modDir = Join-Path $proj "mods\$ModId"
if (-not (Test-Path (Join-Path $modDir "mod.json"))) {
    throw "找不到 mod.json：$modDir\mod.json"
}

$outDir = Join-Path $proj "build"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$pck = Join-Path $outDir "$ModId.pck"
if (Test-Path $pck) { Remove-Item -Force $pck }

# ---------- 覆盖构建：自动生成 ModPackReplace 的 export_files（mod 目录全部 + replace_paths） ----------
if ($Preset -eq "ModPackReplace") {
    $presetsPath = Join-Path $proj "export_presets.cfg"
    if (-not (Test-Path -LiteralPath $presetsPath)) {
        throw "找不到 export_presets.cfg：先运行 setup_mod_project.ps1 -Replace"
    }

    $exportFiles = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $modDir -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($modDir.Length + 1).Replace('\', '/')
        if ($rel -notmatch '(^|/)\.') {
            $exportFiles.Add("res://mods/$ModId/$rel")
        }
    }

    $manifest = Get-Content -LiteralPath (Join-Path $modDir "mod.json") -Raw | ConvertFrom-Json
    if ($manifest.PSObject.Properties.Name -contains 'replace_paths') {
        foreach ($rp in $manifest.replace_paths) {
            $rp = [string]$rp
            if ($rp -eq "") { continue }
            $rel = $rp -replace '^res://', ''
            $abs = Join-Path $proj ($rel.Replace('/', '\'))
            if (-not (Test-Path -LiteralPath $abs)) {
                throw "replace_paths 指向的文件不存在：$rp"
            }
            $exportFiles.Add($rp)
        }
    }
    $exportFiles = @($exportFiles | Select-Object -Unique)
    $arr = (($exportFiles | ForEach-Object { '"' + $_ + '"' }) -join ", ")
    $exportLine = "export_files=PackedStringArray($arr)"

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($ln in ([System.IO.File]::ReadAllText($presetsPath) -split "`n")) {
        $lines.Add($ln.TrimEnd("`r"))
    }

    $nameIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq 'name="ModPackReplace"') { $nameIdx = $i; break }
    }
    if ($nameIdx -lt 0) { throw "未找到 ModPackReplace 预设；先运行 setup_mod_project.ps1 -Replace" }

    $start = -1
    for ($j = $nameIdx; $j -ge 0; $j--) {
        if ($lines[$j].Trim() -match '^\[preset\.\d+\]$') { $start = $j; break }
    }
    $end = $lines.Count
    for ($j = $start + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j].Trim().StartsWith("[")) { $end = $j; break }
    }

    $replaced = $false
    for ($j = $start; $j -lt $end; $j++) {
        if ($lines[$j] -match '^export_files=') { $lines[$j] = $exportLine; $replaced = $true; break }
    }
    if (-not $replaced) {
        for ($j = $start; $j -lt $end; $j++) {
            if ($lines[$j] -match '^export_filter=') { $lines.Insert($j + 1, $exportLine); $replaced = $true; break }
        }
    }
    if (-not $replaced) { throw "在 ModPackReplace 区块内找不到 export_filter/export_files 行" }

    [System.IO.File]::WriteAllText($presetsPath, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已生成 export_files：$($exportFiles.Count) 个文件（$Preset）"
}

Write-Host "导出 pck（preset: $Preset）..."
& $Godot --headless --path $proj --export-pack $Preset $pck
if (-not (Test-Path $pck)) { throw "导出失败，未生成 $pck（确认存在名为 $Preset 的导出预设）" }

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
