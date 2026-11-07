# 命令清单

`$G = 'H:\Godot_v4.7-stable_win64.exe'`，`$ROOT = 'H:\Enter The Nyangeon'`。

## 选型（快照只读）

```powershell
$SNAP = 'third_party\pixelfx-godot\godot'
# 按名字/标签搜
& $G --headless --no-header --path $SNAP -s res://tools/cli.gd -- list rage
& $G --headless --no-header --path $SNAP -s res://tools/cli.gd -- list poison status
# 已在本地快照里，也可以直接搜源码（PowerShell 的 -Path 不支持 **，用 Get-ChildItem 递归）
Get-ChildItem third_party\pixelfx-godot\godot\addons\pixelfx\fx -Recurse -Filter *.gd | Select-String -Pattern '"tags"'
# 渲染对照图（产物在快照 records/，看完删）
& $G --headless --no-header --path $SNAP -s res://tools/cli.gd -- render status/rage --zoom 4 --bg dark
# 自检：溢出、接缝、未播种随机、慢帧
& $G --headless --no-header --path $SNAP -s res://tools/cli.gd -- check status/rage
```

## 烘焙

```powershell
& $G --headless --path $ROOT -s res://script/bake_pixelfx_fx.gd
```

期望输出（节选）：

```text
BAKE ring n=90 … | aura n=72 … | bubbles n=108 … | frenzy n=54 (80, 80) err=0 | ms=…
FRAMES corruption_aura_frames.res worst=39 (frame 12) limit=70 empty=0
FRAMES corruption_bubbles_frames.res worst=87 (frame 58) limit=112 empty=0
FRAMES frenzy_aura_frames.res worst=68 (frame 1) limit=78 empty=0
```

非 0 退出 = bbox 越界或有空白帧，先修效果再接入。

## 抓帧（窗口模式，不要 headless）

预览场景放 `tests/_tmp_*_preview.tscn`，脚本末尾：

```gdscript
await get_tree().create_timer(wait).timeout
await RenderingServer.frame_post_draw
get_viewport().get_texture().get_image().save_png("res://tests/_tmp_x_%s.png" % mode)
get_tree().quit()
```

```powershell
$p = Start-Process -FilePath $G -ArgumentList '--path',"`"$ROOT`"",'res://tests/_tmp_x_preview.tscn','--','--mode=dub' -PassThru
Start-Sleep -Seconds 10
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
```

放大看细节用 Pillow（`load_workspace_dependencies` 里的 python）：

```powershell
& $PY -c "from PIL import Image; im=Image.open(r'…png').convert('RGB'); im.crop((330,250,500,420)).resize((680,680), Image.NEAREST).save(r'…zoom.png')"
```

## 启动检查

```powershell
Start-Process -FilePath $G -ArgumentList '--headless','--path',"`"$ROOT`"",'res://scenes/debuff/frenzy_effect.tscn','--quit-after','40' -PassThru -RedirectStandardError $env:TEMP\boot.txt
# 只关心：SCRIPT ERROR / Parse Error / Failed to load
```

`--quit-after` 退出时的 `ObjectDB instances were leaked` / `1 resources still in use` 是正常现象，不是脚本错误。

## 性能

```powershell
# 编辑器内/运行中都可以读
# MCP: editor_manage(op="monitors_get") 或 game_manage 看 fps / draw calls
```

显存估算：`帧数 × 宽 × 高 × 4` 字节（RGBA8）。

## Git

```powershell
git status --porcelain -- scenes/effects scenes/debuff addons/pixelfx script docs
git diff -- scenes/effects
```

提交前必须让用户确认；`tests/`、`third_party/` 不暂存。
