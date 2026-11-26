# 粒子版命令清单（Windows）

```powershell
$G    = 'H:\Godot_v4.7-stable_win64.exe'
$PART = 'third_party\pixelfx-godot\godot-particle'
$PIX  = 'third_party\pixelfx-godot\godot'
```

上游的 `pfxp` 是 bash 包装（Linux 里用 `xvfb-run` 给渲染器）。Windows 上直接调 Godot，**参数照抄**即可：

| `./pfxp <x>` | Windows 等价 |
|---|---|
| 其它命令 | `& $G --headless --no-header --path $PART -s res://tools/cli.gd -- <x>` |
| `render` / `smoke` | `& $G --no-header --path $PART --rendering-driver opengl3 --fixed-fps 30 -s res://tools/cli.gd -- render …`（act 用 `--fixed-fps 60`） |
| `perf` | `& $G --no-header --path $PART --rendering-method gl_compatibility --rendering-driver opengl3 --disable-vsync --resolution 1280x720 -s res://tools/cli.gd -- perf …` |

## 0. 首次：导入

```powershell
& $G --headless --no-header --path $PART --import
```

只为生成 `$PART\.godot\`（导入缓存，上游 gitignore）。**跑完删掉**，快照保持干净。
之后的 `list/build/check/index` 都是 headless；`render/smoke/perf` 要真渲染器（会开窗口）。

## 1. 找效果

```powershell
# 按 id / 名字 / 描述搜索（分类名或 * 通配也行：fire、fire/*、*torch*）
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- list poison
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- list fire torch

# 目录（244 条一句话描述，按分类）
Select-String -Path "$PART\docs\CATALOG.md" -Pattern 'heal|status'

# registry：id -> {path, name, loop, duration, size, origin, actor, act}
Select-String -Path "$PART\addons\pixelfx_particles\fx\registry.gd" -Pattern '"status/poisoned"'

# 配方源码（真正要读的东西）
Get-ChildItem "$PART\build\fx\status" -Filter *.gd
```

## 2. 自检 / 渲染 / 对拍

```powershell
# 结构自检：场景能加载、meta 与 port/meta.json 一致、时间轴合理、seed 固定、没有渲染器不支持的东西
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- check status/poisoned holy/heal-aoe

# 渲染帧序列（画布原生尺寸）-> records/render/<id>/0000.png … + backdrop.png
& $G --no-header --path $PART --rendering-driver opengl3 --fixed-fps 30 -s res://tools/cli.gd -- render holy/heal-aoe
# 换个输出目录 / 只渲染不打印
& $G --no-header --path $PART --rendering-driver opengl3 --fixed-fps 30 -s res://tools/cli.gd -- render holy/heal-aoe --out res://records/render --quiet

# 演出（73 个带 act 的效果，60fps）-> records/render-act/<id>/
& $G --no-header --path $PART --rendering-driver opengl3 --fixed-fps 60 -s res://tools/cli.gd -- render melee/sword-slash --act

# 动态检查：每个场景装上节点、播到结束（要渲染器）
& $G --no-header --path $PART --rendering-driver opengl3 --fixed-fps 30 -s res://tools/cli.gd -- smoke status/poisoned

# 性能：单实例 + 64 并发
& $G --no-header --path $PART --rendering-method gl_compatibility --rendering-driver opengl3 --disable-vsync --resolution 1280x720 -s res://tools/cli.gd -- perf status/poisoned --stress 64 --loop-secs 3
```

**对拍（可选）**：`port/compare.py` 要和**像素版的参考渲染**比，所以先出参考，再打分。

```powershell
# ① 像素版出参考（写 godot/records/gallery/<id>/anim.webp）
& $G --headless --path $PIX -s res://tools/cli.gd -- render holy/heal-aoe --webp --scale 1 --out res://records/gallery
# ② 粒子版渲染自己的帧（上一节的 render）
# ③ 打分：records/compare/<id>/metrics.json + sheet.png（REF 上、PARTICLE 下）+ side.webp
python -I "$PART\port\compare.py" holy/heal-aoe
```

`compare.py` 需要 Python + numpy + Pillow。分数只是分诊信号（上游口径：≥ 0.6 算过，目标 0.75，眼睛决定）。

## 3. 改 / 造效果（只在快照里试验）

```powershell
# 从模板起一个 build 脚本（--loop 循环 / --sim 粒子模拟）
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- new fire/brazier

# build/fx/<id>.gd -> addons/pixelfx_particles/fx/<id>.tscn（会写 .tscn/.res/.import）
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- build fire/brazier

# 重建 registry.gd + docs/CATALOG.md（新增/改名后必须跑）
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- index
```

**注意**：`build`/`index` 会**改快照内文件**。快照是只读参考 —— 真要练手，先整份拷到 `$env:TEMP` 再动，
或练完 `git`-外的目录自己清理；不要把试验产物留在 `third_party/` 里。

## 4. 清理

```powershell
Remove-Item -Recurse -Force "$PART\records","$PART\.godot","$PIX\records" -ErrorAction SilentlyContinue
```

首次 `--import` 还会给上游没提交的脚本补写 `*.gd.uid`（`build/`、`tools/` 下）；想让快照与上游逐文件一致，
就把这批新增的 `*.gd.uid` 一并删掉。

跑完一定要清，否则下次 `git status` 里会出现一堆 `.godot/`、`records/`、`*.gd.uid`（虽然被 `.gdignore` 挡住不进导包）。

## 5. 搬进 ENN 后的检查

```powershell
# 启动检查：只关心 SCRIPT ERROR / Parse Error / Failed to load
Start-Process -FilePath $G -ArgumentList '--headless','--path','"H:\Enter The Nyangeon"','res://<你的场景>.tscn','--quit-after','40' -PassThru -RedirectStandardError $env:TEMP\boot.txt

# 性能：编辑器内用 MCP editor_manage(op="monitors_get") 看 fps / draw calls；
# 显存粗算：SubViewport 关闭时 ≈ 粒子贴图张数 × 面积 × 4B；开着 pixel_view 时每个实例多一张画布。
```
