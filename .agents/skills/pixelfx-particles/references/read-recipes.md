# 三个配方样本的逐行读法

目的：把 `build/fx/<分类>/<name>.gd` 读成一张**相位表**，再决定搬进 ENN 时哪些能留、哪些要改。
行号对应当前快照（commit `620f7556`）。

## 0. 通用读法（任何 build 脚本）

按顺序找四类东西，写在纸上：

1. **常驻件**：没有 `emit()/show()` 窗口的节点 —— 循环效果的"每帧非空"靠它们。
2. **一次性件**：带 `emit(p, t0)` / `emit(p, t0, t1)` / `show(n, t0, t1)` 窗口的节点 —— 相位表的主体。
3. **光**：`layer: "light"` 的 `glow()`、`twin()`、`light_add()`；它们是加法叠在 color 之上的。
4. **角色 / 地面附件**：`actor_node()`、`actor_points()`、`ring()`、`shape(... {"side": ±1})`。

然后看三样时间控制：`key()`（线性/阶梯）、分类 lib 的 `steps()/keyn()/keyf()`（按原版曲线采样）、
`loop_t()`（把 0→1 的循环时间喂给 shader 的 `t`）。

---

## 1. `status/poisoned`（循环 1.6s，72×64）—— 状态光环的标准结构

文件：`godot-particle/build/fx/status/poisoned.gd`

| 行 | 读法 |
|---|---|
| 1–8 | 头注释就是相位表：原版 blob、一句话意图、"每 0.8s 抖一下、起泡、推出环"、画布/原点、ramp、机制（身体 shader + 汗点 rect shader + 环 shader） |
| 11–12 | `TICK := 0.8` 是**节拍常量**，后面所有 `fposmod(t, TICK)` 都靠它；`MARGIN := 2` 是为了给身体贴图左右留摆动余量 |
| 16–21 | `P := fit("palette", 8)` 取 8 级 ramp；`S := shape_of()` 拿 stand-in 剪影；`R := Rng.new(seed*7+3)` 让"位置"用**另一个**随机流（避免与原版粒子共用后错位） |
| 23–33 | 原版的**数据计划**：从伤口 `_walk()` 走出 4 条暗脉（写进一张 `Image` 的 R 通道）、在身体上挑 6 个起泡点、找汗点。注意：这些是**构建期**算一次，不是每帧算 |
| 35–38 | 地面件：一盏随时间衰减的地光 + 一个环 shader 的**远半圈**（`back: true`） |
| 40–45 | `sample()` 把 `radius/thickness/alpha` 绑到 `fposmod(t, TICK)`：环每 0.8s 从 5 推到 27 再消失 —— 这就是"每 tick 推一圈" |
| 47–56 | 身体：`actor_node()` + 留白后的贴图当 `texture`，再挂 `_poisoned_body.gdshader`；uniform 里塞进 ramp、暗脉图（`asset("_veins", data)`）、6 个起泡点坐标 |
| 57–58 | `loop_t(body, "tw")`：shader 不许读 `TIME`，循环时间从 key 进 |
| 61–67 | 起泡爆裂：每个泡一个 `one_shot` 发射器（`emit: {"ring": [r, r]}` 起点、`radial_speed`、`gravity` 向上、`alpha_curve`），按 `i/3*TICK+0.38` 错开 |
| 69–75 | 汗点：每个点一个 `shape()` rect + `_poisoned_sweat.gdshader`，`lag` 错相；**这是"用 shader 画一次性过程"而不是用粒子** |
| 77–79 | 体光：`glow()` + `exp(-fposmod(t,TICK)/0.18)` 的脉冲 —— 节拍感和环同步 |

**搬进 ENN**：身体 shader 那段整段不要（ENN 不重绘身体）；留「地光 + 环 + 起泡 + 体光」，
环要正圆（`squash` 置 1、去掉 `side` 半圈），粒子换成 ENN 的 1–2px 贴图。
参考 `scenes/effects/pixelfx_corruption_aura.gd`（像素版同 id 的落地方案）。

---

## 2. `holy/heal-aoe`（一次性 2.9s，256×136）—— 用函数把"先后"写死

文件：`godot-particle/build/fx/holy/heal-aoe.gd`

| 行 | 读法 |
|---|---|
| 1–11 | 相位表：光种沉入 → 环滚出 → 经过处地面发亮 → "+" 芽冒出上浮；机制列出 4 个 shader 和各自的职责 |
| 14–16 | `SY := 0.2`（侧视压扁，**ENN 要改 1.0**）、`SEED := 0.3`（光种阶段时长）、`ROLL := 1.0`（环滚出时长） |
| 19–24 | `front(t)` = 环前沿当前半径（`out_cubic` 缓动）；`passed(d)` 是它的**逆函数**：距离 d 处**何时**被扫过。后面所有"经过才触发"的节点都按 `passed(d)` 排时间 |
| 27–40 | `star_strip()` 是**构建期贴图**：把原版 STAR 粒子的寿命拆成逐帧 7×7 条带，存成一张图挂到发射器上（`asset()` 会存 `.res`） |
| 44–46 | `REACH` 来自 `meta.options`（原版参数）；`rng.seed = 6` 固定 |
| 49–65 | 26 个 "+" 芽位：极坐标均匀采样、`t0 = passed(d) + 抖动`，装进两个 `PackedVector4Array` 直接当 shader uniform；另加 14 个 ring 骑手相位 |
| 67–73 | 环 = **两个半边 shader**（远半圈 `back: true`）+ 一盏地面光；`key(rg, "…/time", [[0,0],[D,D]])` 把 shader 时间线性推到底 |
| 75–81 | "+" 芽同理：两个半边 + 一盏光；数据全部从 uniform 进 |
| 83–98 | 光种：96 个点做 `emit.points`，`radial` / `radial_speed` 取**负值**表示向内收，`align: true` 让 streak 贴图朝速度方向；`emit(gather, 0.0, SEED-0.04)` 收束到 SEED |
| 100–107 | 光种本体：`sparkle()` + 两盏 `glow()`，`radius/alpha` 用 `pow(t/SEED, 2)` 键出来 |
| 109–133 | 释放：`flare()`、一束 `_heal_jet.gdshader`（`top/bot/r` 三根键 = 长度/宽度/存在）、光点、两盏加法光 |
| 135–160 | 星芒：`star_strip()` 造两色条带、`flip(stars, 10)` 让帧动画按粒子寿命播；light twin 用同样的参数 |
| 162–181 | 露水：把 26 个芽按 `t0` 分到 0.08s 的 bin，**每个 bin 一个 one-shot 发射器**，`emit(dew, t0)` 到点才开 |
| 183–201 | 余烬：按环前沿分 3 个半径带，`emit(em, passed(band_inner+4))` —— 环扫到才起 |
| 204–209 | `burst()`：复刻原版 `Lights.add()` 的半径收缩 + 强度平方衰减，纯函数式键控 |

**搬进 ENN**：`SY=0.2`→1.0、去掉 `back` 半圈、`shape()` 的 256×136 画布按 640×360 重算；
`passed()` 这种"逆函数排时间"的做法**直接可用**（ENN 的治疗圈也可以让"+"/光点等环扫到再冒）。
参考 `scenes/effects/pixelfx_heal_ring.gd` + `pixelfx_heal_plus.gd`。

---

## 3. `impacts/hit-spark`（一次性 0.5s）—— 三步节拍 + shader 顶替像素

文件：`godot-particle/build/fx/impacts/hit-spark.gd`

| 行 | 读法 |
|---|---|
| 1–7 | 相位表：偏心十字 + 白钻核心 → 锥形火花与热屑落下弹跳；机制说明十字是一个 shader、三个节拍点 `0.025 / 0.058 / 0.092 s` |
| 11–17 | `o := meta.options`（原版参数）、`R := JsRng`（复刻原版随机，**不是** Godot 的 RNG）、`A := o.aim`（打击方向） |
| 19–25 | 5 条光芒：角度 + 长度 + 宽度打包成 `Vector4`，一条长芒沿 `A`、其余按比例散开——这就是"偏心十字"的数据 |
| 26–34 | 9 颗火花 + 6 颗热屑：`spawn(kind, x, y, vx, vy, life, color, size, delay)` 用的全是原版的速度区间；`flush()` 把这一批计划一次性交给 GPU 发射器（lib 里实现） |
| 36–52 | 十字：一个 `shape("rays")`（`_rays.gdshader`）+ `steps()` 在三个节拍点切 `scale_len / scale_w / diamond / 颜色`，`show(cross, 0.0, 0.092)` 到点直接消失——**"三帧动画"用 uniform 阶梯实现** |
| 54–61 | 光：`exp(-t/0.045)` 的 pop（两盏 + 一条沿线光）+ 三盏常驻光（本体/前方/地面） |

**搬进 ENN**：这套"shader 阶梯 + one-shot 粒子 + 三盏光"就是命中反馈的最小骨架；
把画布缩到 32²–64²、光芒长度按 64px 角色重算，`JsRng` 可以换成固定种子的 `RandomNumberGenerator`
（原版随机只在"要不要对齐原版帧"时才需要）。

---

## 4. 读完之后：一张交付表

| 项 | 从脚本里抄什么 | 到 ENN 怎么落 |
|---|---|---|
| 时长 / 循环 | `meta.duration`、`meta.loop`、头注释 | `loop` → 循环贴花；一次性 → 烘焙帧数 = `duration × 45` |
| 画布 / origin | 头注释、`root.canvas_size/origin` | 按 64px 角色重算，别超 640×360 |
| 相位 | `emit/show` 窗口 + `key/steps` 的 t | 抄成 ENN 的时间轴常量（不要逐帧抄） |
| 配色 | `ramp palette` 头注释 + `P`/`C` 的索引用法 | 换 ENN 的紫/红/金 ramp |
| 光 | `glow/twin/light_add` 的半径与 alpha | 加法层，`light` 先给 0.5–0.8 再对参考 |
| 身体附件 | `actor_node/actor_points` | **删**，改用 `HurtBoxMeasure` 锚定 |
| 地面 | `SY`、`squash`、`side`、`back` | 改正圆、合半圈、按判定半径对齐 |
