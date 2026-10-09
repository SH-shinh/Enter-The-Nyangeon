<#
.SYNOPSIS
  联机网络补偿压测回归：跑一组「延迟+抖动+丢包」条件，采集 sim-report 指标并断言阈值。

.DESCRIPTION
  - 每个条件启动 host + client（client 用 --coop-devsim=<cond> --coop-devsimreport --coop-devquit 保持连接）。
  - 两个进程都用 --coop-devautoquit 到点优雅退出（刷新 stdout，保证 sim-report 落盘）。
  - 解析 client 日志 `sim-report` 行：maxExtrap / maxEvents / hard_snaps；出现 SCRIPT ERROR 或超阈值判失败。

.EXAMPLE
  .\coop_sim_regression.ps1
  .\coop_sim_regression.ps1 -Duration 14 -Conditions "lat=0,jit=0,loss=0;lat=200,jit=50,loss=20"
#>
param(
    [string]$Godot = "H:\Godot_v4.7-stable_win64.exe",
    [string]$Project = "H:\Enter The Nyangeon",
    [string]$Conditions = "lat=0,jit=0,loss=0;lat=80,jit=20;lat=120,jit=30,loss=10;lat=200,jit=50,loss=20",
    [int]$Duration = 16,
    [double]$ExtrapThreshold = 60.0,
    [int]$ExtrapEventMax = 400
)

$ErrorActionPreference = "Continue"
$out = Join-Path $env:TEMP "coop_sim_regression"
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "== coop sim regression =="
Write-Host ("godot={0}" -f $Godot)
Write-Host ("duration={0}s  extrap_threshold={1}%  extrap_event_max={2}" -f $Duration, $ExtrapThreshold, $ExtrapEventMax)

$condList = @($Conditions.Split(";") | Where-Object { $_.Trim() -ne "" })
$results = @()
$failed = 0
$idx = 0
foreach ($cond in $condList) {
    $idx++
    $tag = $cond
    $hLog = Join-Path $out "h_$idx.log"; $hErr = Join-Path $out "h_$idx.err"
    $cLog = Join-Path $out "c_$idx.log"; $cErr = Join-Path $out "c_$idx.err"

    $hArgs = @('--headless', '--path', "`"$Project`"", '--', '--coop-host', '--coop-devbattle', '--coop-devsimreport', "--coop-devautoquit=$($Duration + 5)")
    $cArgs = @('--headless', '--path', "`"$Project`"", '--', '--coop-join=127.0.0.1', '--coop-devbattle', '--coop-devsimreport', '--coop-devquit', "--coop-devautoquit=$Duration", "--coop-devsim=$cond")

    $h = Start-Process -FilePath $Godot -ArgumentList $hArgs -RedirectStandardOutput $hLog -RedirectStandardError $hErr -PassThru
    Start-Sleep -Seconds 4
    $c = Start-Process -FilePath $Godot -ArgumentList $cArgs -RedirectStandardOutput $cLog -RedirectStandardError $cErr -PassThru

    # 等客户端到点优雅退出（autoquit），最多多等 8s
    $waited = 0
    while (-not $c.HasExited -and $waited -lt ($Duration + 8)) { Start-Sleep -Seconds 1; $waited++; $c.Refresh() }
    if (-not $h.HasExited) { Stop-Process -Id $h.Id -Force -ErrorAction SilentlyContinue }
    if (-not $c.HasExited) { Stop-Process -Id $c.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500

    $lines = @(); if (Test-Path $cLog) { $lines = Get-Content $cLog }
    $reports = $lines | Select-String "sim-report"
    $maxExtrap = 0.0; $lastHard = 0; $maxEvents = 0
    foreach ($r in $reports) {
        $m = [regex]::Match($r.Line, "extrap_rate=([0-9.]+)"); if ($m.Success) { $maxExtrap = [math]::Max($maxExtrap, [double]$m.Groups[1].Value) }
        $m2 = [regex]::Match($r.Line, "hard_snaps=([0-9]+)"); if ($m2.Success) { $lastHard = [int]$m2.Groups[1].Value }
        $m3 = [regex]::Match($r.Line, "extrap_events=([0-9]+)"); if ($m3.Success) { $maxEvents = [math]::Max($maxEvents, [int]$m3.Groups[1].Value) }
    }
    $errText = ""; if (Test-Path $cErr) { $errText = (Get-Content $cErr -Raw) }
    $scriptErr = ($errText -match "SCRIPT ERROR") -or (($lines -join "`n") -match "SCRIPT ERROR")

    $ok = (-not $scriptErr) -and ($maxExtrap -le $ExtrapThreshold) -and ($maxEvents -le $ExtrapEventMax)
    if (-not $ok) { $failed++ }
    $results += [pscustomobject]@{
        Condition   = $tag
        Reports     = $reports.Count
        MaxExtrap   = [math]::Round($maxExtrap, 1)
        ExtrapEvent = $maxEvents
        HardSnaps   = $lastHard
        ScriptError = $scriptErr
        Result      = if ($ok) { "PASS" } else { "FAIL" }
    }
}

$results | Format-Table -AutoSize
Write-Host ("failures={0}/{1}" -f $failed, $condList.Count)
if ($failed -gt 0) { exit 1 } else { exit 0 }
