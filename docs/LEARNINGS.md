# Learnings / 经验库

> Append-only distilled knowledge worth keeping: non-obvious rules, gotchas, hidden coupling, design rationale.
> 追加式沉淀知识：非显而易见的规则、坑、隐式耦合、设计原因。**只在“发现值得留存”时追加，不做逐次读取流水。**
>
> Entry format / 条目格式:
> ```
> ### [System] One-line conclusion / 一句话结论
> - Evidence / 证据: path:line
> - Notes / 说明: ...
> - Source / 来源: code | user | test
> - Date / 日期: YYYY-MM-DD
> ```
> `Source` 说明：`code`=读代码得出；`user`=用户说明；`test`=运行验证。
> **`user` 来源优先级最高，AI 不得仅凭代码推断推翻**；与代码观察冲突时先复核代码，无法复核则以 `user` 为准并注明。
> 修正旧结论时**不删历史**：就地改正并更新日期，或在其下追加 `SUPERSEDED: <日期> <原因>`。
> 高影响但低置信的结论先放入下方「待确认 / To Confirm」区，用户裁定后再移入正文。

---

## 待确认 / To Confirm

> 高影响、低置信的结论；用户确认或纠正后按格式移入下方正文。

### [Coop/Testing] `relay_rejoin3` 的 host 侧偶发引擎错误会让整套回归判失败
- Evidence / 证据: `tests/run_coop_recovery_checks.py`（`--cases relay_rejoin3`，日志目录 `--log-dir`）、`tests/coop_recovery_checks.gd`；现象日志 `.godot/coop_recovery_checks/` 与 `.godot/coop_recovery_rerun/`
- Notes / 说明: 同一天三次运行（全量失败 → 单例通过 → 全量通过）中，仅首次全量执行的 `relay_rejoin3/host` 失败，报 Godot 引擎 `ERROR: Condition "!connected_peers.has(sender)" is true. Continuing.`（中继拆除阶段）。runner 会合并 stdout/stderr 并把任何非豁免 ERROR 当作失败，因此这条时序抖动会伪装成功能回归。未复现期间不要据此判定中继重连被改坏：先看是否只出现在 host 侧、再单独重跑该用例确认。尚不清楚触发条件（疑与上一用例的中继连接释放时序有关），待确认。
- Source / 来源: test
- Date / 日期: 2026-10-13

- Follow-up / 后续（2026-10-14，来源：test）：新一轮 full 的 `relay_rejoin3` 通过，但 LAN `rejoin3/host` 出现三条 `Unable to send packet on channel 0, max channels: 0`，功能断言仍为 0 失败；LAN/Relay 单独重跑通过。两种报错不能直接认定同根因；新增 AUD-TEST-002 跟踪，保持严格日志判定与原始失败证据。

- SUPERSEDED: 2026-10-14 同类 Relay 报错已由排队旧包/断线事件顺序的确定性守卫复现并修复；LAN 同 poll 多端退出另复现 ENet 原生成员通知及玩法发送错误，薄适配器修复后全套与复跑严格通过。旧历史现象不删除，详见下方新记录（来源：test）。

---

### [Foundation] Autoload 顺序 = `_ready` 顺序，Game 依赖后声明的 SupportData
- Evidence / 证据: `project.godot:25-36`, `script/Game.gd:23-26,151-152,171-172`
- Notes / 说明: 调整 autoload 顺序或让 `Game._ready` 更早访问 `SupportData` 会引发初始化问题。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Combat] `emit_enemy_damage_taken` 发生在 modifier/damage_multiplier/hp 扣减之前
- Evidence / 证据: `script/health_component.gd:124` → `:126-148`
- Notes / 说明: 该信号订阅者看到的 `final_damage` 不含后续阶段；而 `enemy_over_kill_damage` 用后置值。两者不可假设一致。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Combat] `damage_multiplier` 在 TRUE_DAMAGE 时不重置，会残留
- Evidence / 证据: `script/health_component.gd:130-132`, `script/weak_part.gd:19-28`
- Notes / 说明: WeakPart 命中会加 `TRUE_DAMAGE`，从而跳过应用与重置，pending multiplier 泄漏到下一次非真实伤害。
- Source / 来源: code
- Date / 日期: 2026-09-25
- SUPERSEDED: 2026-10-14 HealthComponent 统一消费倍率，真实伤害和拒绝/零伤害命中也清理；伤害契约守卫覆盖前后两次命中。来源：code | test。

### [Combat] 空的 `source_type` 被当作玩家方
- Evidence / 证据: `script/faction.gd:9-14`
- Notes / 说明: 未打来源标签的 `DamageData` 对敌人算友方、对玩家算敌对 —— 易造成误伤或“打不动”。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Combat] AoE 共用同一个 DamageData 实例
- Evidence / 证据: `script/explosion_damage.gd:117-120`, `script/kick.gd:45-51`, `scenes/debuff/fire_field.gd:86-103`
- Notes / 说明: 在 `on_damage_dealt` 里改该实例会影响所有命中目标；只有 WeakPart 先 `duplicate(true)`。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Combat] 敌方 `hurt_resis` 不减伤，仅 `global_hurt_damage` 有效
- Evidence / 证据: `script/health_component.gd:108-110`（公式被注释）, `script/EnemyStats.gd:158`
- Notes / 说明: `hurt_resis` 只影响飘字 "Resis " 前缀；玩家减伤公式在 `player_health_component.gd:72`。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Buff] Buff 数值/时长/层数在调用点，不在资源里
- Evidence / 证据: `resources/buff/buff.gd` (无 duration/value), `scenes/manager/buff_manager_base.gd:69,219-237`
- Notes / 说明: `apply_buff(buff, value, source_id)` 的 `value = [max_layer, magnitude, seconds]`，tick 率 `TICKS_PER_SECOND := 10`。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Buff] Stat 刷新延迟一帧
- Evidence / 证据: `scenes/manager/buff_manager_base.gd:51-62`
- Notes / 说明: enemy/summoned 宿主通过 `_process` 里 `update_body_ability()`；在命中途中移除 buff 可能不影响当次计算。Player 宿主例外（直接刷 `PlayerData`）。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Enemy] 真正的敌人基类是 `Enemy`，不是 `BaseEnemy`
- Evidence / 证据: `scenes/enemies/base_enemy.gd:1-2`（空 stub）, `script/entity_ENEMY.gd:1-2`
- Notes / 说明: 给“所有敌人”加逻辑应改 `entity_ENEMY.gd`。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Pooling] `get_pool` 可能返回非空闲节点
- Evidence / 证据: `scenes/manager/PoolManager.gd:97-123`
- Notes / 说明: 取用后必须检查 `is_idle == 1`；`clear_pool`/`erase_pool` 不释放节点；`FloatingPool.call_*` 空列表会报错。
- Source / 来源: code
- Date / 日期: 2026-09-25
- SUPERSEDED: 2026-10-08 `get_pool` 重写为空闲优先（返回的必为空闲节点或 `null`），`FloatingPool` 已删除；见下一条。

### [Pooling] `get_pool` 空闲优先，无空闲未达上限返回 null，满额才静默回收（2026-10-08 重写）
- Evidence / 证据: `scenes/manager/PoolManager.gd`（`get_pool`/`get_pool_idle`/`_recycle`/`detach`/`_node_pool`/`tree_exiting`、`IDLE_LIMITS`）、coop `mods/etn_coop/net/coop_visual_sync.gd`（改用 `PoolManager.detach`）
- Notes / 说明: 旧实现 `max_value > limit` 时**无条件** `idle_state()` 掉索引处节点，会把存在空闲时的活跃子弹/金币也回收（瞬移/丢值）；且空闲扫描上限 `min(size,64/32)` 会造成「假性无空闲」→ 继续实例化 → 无界增长。现改为：① `get_pool` 空闲优先——先弹 `entry.idle` 懒缓存（O(1)），缓存空则整表扫描并回填缓存（**无扫描上限**）；② 无空闲且 `body.size() < limit` 返回 `null`（调用方新建）；③ 仅 `size >= limit` 且无空闲时静默回收轮转槽位（`_recycle` 优先 `deactivate_silent()`，否则 `idle_state()`）。`limit = -1`（未列出的池）不设限、永不强收。`get_pool_idle` 永不强收（`CoinManager` 依赖，避免回收活跃金币丢值）。`IDLE_LIMITS` 兼作并发上限，故**不抬高**既有值即可保持原游戏手感；新增 `stone_bullet:40`/`cannon_bullet_1:20`/`cannon_flash_1:10` 收敛原先的无上限池。`detach(node)` 公开剥离（纯表现副本）；`_node_pool` + `tree_exiting` 自注销取代热路径 O(n) `_prune_freed_bodies`。⚠️ 调用方**仍应检查 `is_idle`**（防御自定义/异常池）；`clear_pool`/`erase_pool` 仍不释放节点。
- Source / 来源: code
- Date / 日期: 2026-10-08

### [Mod] 运行时替换 AnimatedSprite2D.sprite_frames 会 stop()，必须重新 play()
- Evidence / 证据: `mods/etn_coop/ui/coop_start_ball.gd:_apply_green_frames()`（`mod_sdk/coop_mod/mods/etn_coop/ui/coop_start_ball.gd` 镜像同步）在赋值新 `SpriteFrames` 后补 `sprite_2d.play("default")`；起始帧改 `randi_range(0, 19)` 对齐本体 `scenes/ball.gd:25`。本体 `scenes/yellow_ball.tscn:189` 的 `Sprite2D` 实为 `AnimatedSprite2D`（`autoplay = "default"`）。
- Notes / 说明: **现象**（user）：联机准备房绿球被碰撞推动时贴图不滚动（本体黄球正常）。**根因**：引擎 `scene/2d/animated_sprite_2d.cpp:set_sprite_frames()` 内部先 `stop()` 再赋值；`autoplay` 只在 `NOTIFICATION_READY` 触发一次，而子节点 `AnimatedSprite2D` 的 ready 早于根脚本 `_ready` → `coop_start_ball._ready → _apply_green_frames()` 换帧时把刚启动的播放停掉，且脚本只设 `frame`/`frame_progress` 未 `play()`。`ball.gd` 每帧只改 `speed_scale`/`rotation`；`playing=false` 时 `NOTIFICATION_INTERNAL_PROCESS` 关闭、帧永不推进（`speed_scale≈0` 时静止本就不动，故运动时才暴露）。**修法**：换 `sprite_frames` 后显式 `play("default")`（`play()` 置 `playing=true` 并 `set_process_internal(true)`），再设随机起始帧。**通用教训**：运行时给 `AnimatedSprite2D` 赋 `sprite_frames` 等同重载动画，必须紧跟 `play()`；不可依赖场景 `autoplay`（只在 ready 触发一次）。**多副本**：改动须同步 `mods/etn_coop/`（编辑器镜像/运行期）与 `mod_sdk/coop_mod/mods/etn_coop/`（打包源）。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Dead code] 多处遗留物，勿依赖
- Evidence / 证据: `script/transition_manager.gd`（未注册，已于 2026-10-24 删除）, `scenes/game_camera/transition.gd`, `DamageData.check()`, `GameTags.CONVERT`（`FloatingPool.gd`/`scenes/manager/floating_pool.tscn` 已于 2026-10-08 删除）
- Notes / 说明: `GameEvents.enemy_critical_hurt/fire_hurt/explosion_hurt/poison_hurt/normal_hurt` 无发射者；`on_hit_effects` 无填充者。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Input] Control 默认 `mouse_filter=STOP` 会吞掉触摸，世界交互收不到
- Evidence / 证据: `scenes/manager/interact_prompt.tscn:71-75`（Bubble 未设 mouse_filter）, `scenes/manager/interact_prompt.gd:26`（改为 IGNORE）
- Notes / 说明: 气泡提示 `Bubble`(PanelContainer) 默认 STOP，落在其上的 `InputEventScreenTouch` 会被 GUI 消费，无法到达 `InteractionManager._unhandled_input`；触屏世界交互的覆盖层需设 `MOUSE_FILTER_IGNORE`（或 PASS 且无人 `set_input_as_handled`）。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Combat] 恶寒伤害（`CHILL_DAMAGE`）仅由近战命中带 `chill_dot` 的敌人时产生
- Evidence / 证据: `scenes/manager/enemy_buff_manager.gd:88-102,156-163`, `resources/buff/enemy_buff/chill_dot.tres`
- Notes / 说明: `count_chill_damage` 挂在 `health_component.damage_taken` 上；仅当该次伤害含 `MELEE_DAMAGE` 且敌人已有 `chill_dot` 时，才按实际近战伤害 × `dot_damage` × `1.1^layer` 追加一次 `CHILL_DAMAGE`（经 `request_extra_damage` 投递，会再广播 `GameEvents.enemy_damage_taken`）。恶寒 DOT 跳数本身不造成伤害。燃烧上限存于 `enemy_buff_manager.current_buff["fire_dot"]["max_layer"]`（= `player.stats.fire_dot_layer`，默认 5、最小 1，`enemy_buff_manager.gd:116-121`）。做「燃烧+恶寒」联动道具（如 `sugar_cube`）须沿此路径挂钩，且触发用真实伤害需避免带 `CHILL_DAMAGE` 类型以免递归。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Buff] 玩家「有益 buff 持续时间」经 `_duration_multiplier` 钩子在创建 entry 时乘算
- Evidence / 证据: `scenes/manager/buff_manager_base.gd:225,242-244`, `scenes/manager/player_buff_manager.gd:26-32`, `script/Stats.gd`, `script/PlayerData.gd`（`base_buff_duration`/`buff_duration_mult`）, `resources/buff/buff.gd`（`is_debuff`）
- Notes / 说明: `erase_time = value[2] * TICKS_PER_SECOND * _duration_multiplier(buff)`；基类默认 1，仅 `PlayerBuffManager` 返回 `body.stats.buff_duration`，且 `Buff.is_debuff` 为 true 时返回 1。属性为乘区（1=100%），由 `base_buff_duration`（快照 `Stats.buff_duration`）× `buff_duration_mult`（道具/升级累加）合成，不吃 `ability_mult`。**仅创建时生效**：已挂 buff 的剩余时间不随后续属性变化重算（与 `dot_time` 一致）。玩家侧有害 buff：`debt_buff`、`player_fire_dot`、`gatling_speed_buff`（自我减速）已标 `is_debuff=true`。新增玩家 buff 若为 debuff 必须置 `is_debuff=true`，否则会被「有益 buff 时长」延长。（`buff_duration_mult` 目前无内容来源，恒 1。）
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Pooling] `PooledFollowFx` 默认跟随且目标失效即回收；「对象池 + 定点爆发」需覆写
- Evidence / 证据: `script/pooled_follow_fx.gd:23-29,31-39`, `scenes/update_item/sugar_cube_steam.gd:6-7`, `scenes/manager/PoolManager.gd:148-155`
- Notes / 说明: `PooledFollowFx._physics_process` 每帧把 `global_position` 对齐 `target`，且 `target` 失效即 `idle_state()`；而敌人池化死亡后 `Enemy.idle_state()` 会把 `global_position` 置回 `(0,0)`，若特效仍跟随就会跳回原点。要「在生成点爆发、用对象池回收」时，覆写 `_physics_process` 为空（停在生成坐标），仍由 `spawn_fx` 的 `follow_body`/`play_anim` 定位并播放，动画 method track 调 `idle_state` 回收。音效可放在覆写的 `play_anim()` 里（同 `convert_damage.gd`），如 `sugar_cube_steam.gd` 用 `SoundManager.play_sfx_once("EquipSounds7")`。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Player] 近战脚本必须挂在名为 `Kick` 的节点
- Evidence / 证据: `script/player.gd:56,128-129,182-183`
- Notes / 说明: `player.gd` 以 `$Kick` 取近战节点；`kick` 输入触发 `kick_start()`、每帧 `look_at(crosshair)` 都走它。节点名不是 `Kick`（如 `chinatsu_melee`）时 `kick==null`，近战永不触发。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Buff] 管理器信号的参数个数不匹配只在发射时爆错
- Evidence / 证据: `scenes/manager/buff_manager_base.gd:103`（`buff_applied.emit(buff, current_buff)`）
- Notes / 说明: `buff_applied` 2 参，`buff_expired`/`buff_consumed` 1 参。把 `buff_applied` 连到只收 1 参的回调，连接时不报，发射时报 `Method expected 1 argument(s), but called with 2`。统一回调需带默认参数收 2 个。
- Source / 来源: test
- Date / 日期: 2026-09-25

### [Buff] 层上限 = `floor(value[0] × stats.buff_layer_mult)`，倍率是「场景基准 + 被动加成」
- Evidence / 证据: `scenes/manager/player_buff_manager.gd:20-24`, `script/PlayerData.gd:311,374`, `script/Stats.gd:117`
- Notes / 说明: `entry["max_layer"]` 只在创建时定格，之后不重算。`stats.buff_layer_mult = base_buff_layer_mult`（场景导出基准）`+ buff_layer_mult_add`；若场景基准已非 1，再叠「+100% 上限」被动会相加放大（例：场景 2 + 被动 1 = 3 → base 1 的 buff 变 3 层）。`PlayerData.reset_date()` 不重置 `player.stats.buff_layer_mult`。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [UI] `<Char>_card.tscn` 结构固定，`ui/player_card.gd` 依赖固定节点路径
- Evidence / 证据: `ui/player_card.gd:9-15`, `scenes/player/ako/ako_card.tscn`, `ui/player_card_anim.tres`
- Notes / 说明: 所有角色卡节点树一致（`PlayerCard/ColorRect/Node2D/{TextureRect,TextureRect2,Sprite2D,PlayerPBG,PlayerP,Node2D/ColorRect/{Label,Label2}}`），共用 `player_card_anim.tres`。新建角色卡最省事＝复制现有卡再换资源/文本/配色。`player_card.gd` 用 `PlayerCard.scene_path` 覆盖根 `player`，故该字段应为 `res://...tscn`（不要写 `uid://`）。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [UI] 社团卡固定 4 槽；显示取决于 `PlayerData.character` / `group`
- Evidence / 证据: `ui/society_card.gd:3-14`, `scenes/main/menu_screen.gd:295-299`
- Notes / 说明: `player_card_1..4`；`menu_screen` 按 `for i in 4` 且 `PlayerData.character.has(id)` 过滤实例化，社团卡可见性由 `PlayerData.group.has(group_id)` 决定。新增角色需同时进入 unlock 列表与对应 group（无商店资源则没有购买路径）。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Combat] 敌人易伤走 `global_hurt_damage_mult`，且不影响当次命中
- Evidence / 证据: `script/EnemyStats.gd:52,159`, `resources/buff/enemy_buff/vuln_buff.tres`, `script/health_component.gd:113-124`
- Notes / 说明: 敌方 buff `ability="global_hurt_damage_mult"`，每层给该值 +`entry["value"]`；`global_hurt_damage = base × mult`。`GameEvents.emit_enemy_damage_taken` 在 `final_damage` 乘算之后发出，故命中时施加的易伤只影响后续命中。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [Editor] 已加载资源的内存缓存不随磁盘更新
- Evidence / 证据: 会话中 `resources/player/chinatsu.tres` 磁盘已改，`resource_manage load`/inspector 仍返回旧 `weapon`/`scene_path`；`chinatsu.tscn` Stats 的 `buff_layer_mult` 文件为 2.0 而编辑器显示 1.0。
- Notes / 说明: `filesystem_manage scan/reimport` 不强制重载已加载 `.tres`。以磁盘为准；重启编辑器，或对场景 `scene_open(force_reload=true)` 刷新。
- Source / 来源: test
- Date / 日期: 2026-09-25

### [Player] 玩家根脚本已统一为 `script/player.gd`，角色目录不再自带 `<char>.gd`
- Evidence / 证据: `scenes/player/momoi/momoi.tscn:3` 等 20 个角色场景根节点引用 `res://script/player.gd`（uid `uid://ci8narxcxkq0w`）；`script/player.gd:1-2`（`extends CharacterBody2D` / `class_name Player`）
- Notes / 说明: 角色目录内只保留 PS / melee / hair 等辅助脚本。**例外**：`hina`（`scenes/player/hina/hina.gd`）与 `aris_armed`（`aris_armed.gd`）仍用各自根脚本；`scenes/player/aris/aris.gd` 仍在磁盘但 `aris.tscn` 已改用 `script/player.gd`（疑似遗留）。判断“脚本缺失”前先看场景根节点引用，勿当工作区损坏。
- Source / 来源: user
- Date / 日期: 2026-09-25

### [Localization] `filesystem_manage reimport` 可能静默不重新生成 `.translation`，需先 `scan`
- Evidence / 证据: 编辑 CSV 后直接 `reimport`，`ETN_localization.*.translation` 的 mtime 不变（内容仍旧）；先 `filesystem_manage scan` 再 `reimport` 才更新（实测 2026-09-25，`ui/credits.tscn` 新增 `credits_button`/`credits_title` 时踩到）。
- Notes / 说明: 改 CSV 后先 `scan` 再 `reimport`；验证以 `.translation` 的 mtime 或运行时 `TranslationServer.translate("key")` 为准，而非 importer 返回的 `reimported`。游戏运行中 `reimport` 会被拒（`EDITOR_NOT_READY`），需先 `project_manage(stop)`。
- Source / 来源: test
- Date / 日期: 2026-09-25

### [UI] 全屏「朦胧」遮罩复用 `shaders/motion_screen.gdshader`
- Evidence / 证据: `ui/game_over_page.tscn`（`MotionScreen` + ShaderMaterial `f`/`grayscale`）, `ui/pause_screen.tscn`, `ui/credits.tscn`, `shaders/motion_screen.gdshader:1-11`
- Notes / 说明: `hint_screen_texture` 采样 + lod 参数 `f` 即全屏模糊（`grayscale`=false 保留颜色）。menu 弹窗以 `menu_screen` 的**最后一个子节点**实例化（盖在最上层），全屏 `ColorRect` 半透明黑压暗，`_unhandled_input` 判 `pause` 并 `set_input_as_handled()` 后关闭（配合 `ui/return.tscn`，其 `return.gd` 发 `pause` 动作）。`ui/credits.tscn` 是此模式的完整范例。
- Source / 来源: code
- Date / 日期: 2026-09-25

### [UI] `auto_text.gd` 只能挂 Label 类节点，且必须给固定预算（`box` / `base_size_x/y`）
- Evidence / 证据: `script/auto_text.gd:1`（`extends Label`）、`:36-42`（`_budget_size()` 无 `box` 时取自身 `size`）；`scenes/main/menu_screen.tscn` 的 `Node2D5/credits_button`（Button 点击 + 子 Label `AutoText` 跑 auto_text，`base_size_x=80`/`base_size_y=20`/`clip_text=true`）
- Notes / 说明: ①脚本基类为 `Label`，挂到 `Button` 会因「脚本基类必须是节点类的同类或父类」而不生效；Button 文字自适应用「Button（负责点击/主题）+ 子 Label（`auto_text.gd`、全铺满、`mouse_filter=IGNORE`）」。②**不给固定预算就不会缩放**：`_budget_size` 默认取 Label 自身 `size`，而 Label 的 `size` 又被其最小尺寸（文字宽度）撑大 → 永远“放得下”、字号不缩反溢；必须设 `base_size_x/y` 或 `box`（`box` 指向父 Button 时用其固定尺寸）。③`text` 填翻译键时 `auto_text` 内部用 `atr(text)` 取**译文**测量；`Label.text` 读到的仍是原始键（自动翻译在绘制期发生）。
- Source / 来源: test
- Date / 日期: 2026-09-25

### [UI] 鸣谢页 `credits.gd` 的内容数据格式：`SECTIONS`（`lang` + `members` + 可选 `color`）
- Evidence / 证据: `ui/credits.gd:8-16`（`SECTIONS`）、`:32-51`（`build_list`）；`ui/credits.tscn` 的 `Panel/.../ScrollContainer/ListBox`；CSV 键 `credits_program/art/design/music/copyright/special_thanks`、`coop_special_thanks`（联机版作者）、`credits_title/credits_button`
- Notes / 说明: 每节 `{ "lang": <表头>, "members": [<行>...], "color": <可选> }`；`lang` 为空则**不渲染表头**，只渲染 `members`；表头颜色默认 `HEADER_COLOR`，可用 `color` 覆盖（「特别鸣谢」用）。`lang`/`members` 填 CSV 键时靠 Label 的自动翻译生效（`Label.text` 仍是原始键，显示为译文），纯文本原样显示。**坑**：`_notification(NOTIFICATION_TRANSLATION_CHANGED)` 会在 `_ready` 之前触发（`Game.load_config()` 里 `set_locale` 即发），此时 `@onready` 的 `list_box` 仍为 `null` → `get_children()` 空指针崩溃；必须加 `is_node_ready()` 守卫；重建时用 `list_box.remove_child(n)` + `n.queue_free()`（只 `queue_free()` 是延迟的，同一帧多次重建会因 `get_children()` 仍返回待释放节点而重复追加）。
- Source / 来源: test
- Date / 日期: 2026-09-26

### [UI] 鸣谢页自动循环滚动（`credits.gd`）
- Evidence / 证据: `ui/credits.gd`（`_process`/`ScrollPhase`/`scroll_container.get("isDrag")`）、`script/ScrollBox.gd`（拖动直接改 `scroll_vertical`）、`ui/credits.tscn` 的 `ScrollContainer`
- Notes / 说明: 最大滚动量取 `vbar.max_value - vbar.page`（`<=0` 表示内容不超一屏，不动）。用 `scroll_vertical` **直接步进**（亚像素 `_frac` 累加取整），不要缓存绝对值，这样用户手动滚动后恢复时不会跳变。向下 `auto_scroll_speed` → 触底停 `auto_scroll_pause` → 匀速 `auto_scroll_return_speed` 倒滚回顶 → 顶部再停 `auto_scroll_pause` → 循环。**手动暂停**：监听 `ScrollContainer.gui_input`（触摸/鼠标/滚轮）+ 每帧读 `ScrollBox.gd` 的 `isDrag`，置 `_pause_left = manual_resume_delay`，拖动期间持续重置。`set_process(false)` 于隐藏时停；`show_credits()` 与 `build_list()` 都 `_reset_scroll()` 回顶。竖滚动条用 `vertical_scroll_mode = 3`(SHOW_NEVER) 隐藏（仍可程序滚动）。
- Source / 来源: test
- Date / 日期: 2026-09-26

### [Combat] 旧 `is_health` 玩家治疗路径实际失效（`is_health_request` 从未置 true）
- Evidence / 证据: 旧 `player.gd` 的 `_on_health()` 仅在物理帧 `if is_health_request == true` 时调用，而全项目无任何 `is_health_request = true`；`emit_signal("is_health")` 只连到空实现 `_on_is_health()`。`grs_grilled_corn.gd` 与 `last_stand_component.gd:_do_heal()` 曾走此路径 → 回血无效。
- Notes / 说明: 已删除 `is_health` 信号、`health_hp`、`is_health_request`、`_on_health`、`_on_is_health`，以及 22 个玩家 `.tscn` 的 `is_health` 连接和 `GameEvents.player_is_health`；两处调用改走统一治疗接口 `HealData.fill(...) + PlayerHealthComponent.take_damage(...)`，并在 `player_health_component.gd` 治疗分支补上 `stats.heal_mult`（默认 1）。今后新增治疗务必用统一接口。
- Source / 来源: code
- Date / 日期: 2026-09-26

### [Enemy] 活跃敌人改由生命周期登记，不再靠战斗区 CheckBox 探测
- Evidence / 证据: `scenes/manager/PoolManager.gd`（`register_active_enemy`/`get_active_enemies`/`get_random_active_enemy`/`reconcile_active_enemies`）, `script/entity_ENEMY.gd:90,93,125`（`_exit_tree`/`idle_state`/`active_state`）, `scenes/enemies/enemy_tank.gd:71,89`
- Notes / 说明: 旧 `PoolManager.enemies_group` 由 `main`/`test_room` 的 CheckBox Area2D 进出事件维护；`enemy_clear_unit` 的 `queue_free` 不清理它 → 失效引用污染计数、`size>80` 上限检测失真、`puzzle_cube` 可能对已释放节点调方法。现改为敌人实体在 `active_state()` 登记、`idle_state()`/`_exit_tree()` 注销，`_active_enemies: Dictionary(instance_id→Node)` 为唯一真源；`get_active_enemies()` 每次先剔除失效/`is_idle==1`，`active_enemy_count` 供上限判断，`reconcile_active_enemies()` 每 ~1s 用 `"Enemy"` 组（排除 `EnemyPart`）全量纠偏兜底。**重写 `active_state`/`idle_state` 的敌人子类必须调 `super` 或自行登记**（`enemy_tank` 未调 super，已手动补；automaton/sandbag/tester_automaton_shield/goliath 已调 super）。`spawn_stop`/`spawn_restart` 现仅在跨 80 阈值时各发一次。
- Source / 来源: code
- Date / 日期: 2026-09-26

### [Support] Kei EX 动画 `await` 与收招反向播放竞态，导致特效永久停留
- Evidence / 证据: `scenes/player_support/kei/kei_as.gd:50-74`
- Notes / 说明: `skill_active()` 用 `await animation_player.animation_finished` 串 `as_anim → as_loop`；而 `skill_end()`（由 `GameEvents.round_upgrade` / `SkillTimer` 触发）会 `play_backwards("as_anim")`，其完成同样发射 `animation_finished`，会唤醒挂起的协程再 `play("as_loop")` → 特效永久停留在 loop（表现为"收回动画被打断、特效不消失"）。修法：自增代数 `_as_gen`，`skill_end` 加一作废过期协程，`await` 返回后校验 `as_is_active and gen == _as_gen` 才播 `as_loop`。凡"await 动画完成 + 该动画可被外部打断/反向播放"的写法都需此类守卫。
- Source / 来源: code
- Date / 日期: 2026-09-26

### [Localization] `ETN_item_localization.csv` 实际为 CRLF/LF 混合，追加条目必须用 LF
- Evidence / 证据: 编辑前实测该文件 `bare LF=259 / CRLF=433`（`.gitattributes` 为 `* text=auto eol=lf`）；文件首 3 字节 `EF BB BF`（UTF-8 BOM）。
- Notes / 说明: 尽管 `.gitattributes` 要求 LF，工作区 CSV 仍留有大量 CRLF 行（历史工具写入）。新增条目仍按约定「追加到末尾」并用 LF，勿整体重写（会制造巨大 diff 且可能改编码）。推荐用 `[System.IO.File]::AppendAllText(path, text, New-Object System.Text.UTF8Encoding($false))`，字符串里的 `` `n `` 即 LF 且不会重复写 BOM。只加 key、值留空的行形如 `key, , , ,`（5 字段，与 `nagusa_doll_negative` 同款）。
- Source / 来源: test
- Date / 日期: 2026-09-26
- SUPERSEDED: 2026-09-28 「追加用 LF」改定为 **CRLF**（来源：user；规则见 `AGENTS.md` / `docs/CONVENTIONS.md` §2.4）。各文件既有行尾仍按实况保留，避免整文件转换。
- SUPERSEDED: 2026-10-13 5 组源文件已规范为 UTF-8 BOM/CRLF，`.gitattributes` 为 CSV 单独覆盖 eol，旧“既有行尾保留”说明不再描述当前状态。格式防护见 `tests/check_localization.py`（来源：test）。

### [Time] `process_mode` 只绕开 paused，不绕开 `Engine.time_scale`
- Evidence / 证据: `ui/transition.tscn:733,1004`（`process_mode=3`）, `scenes/enemies/boss/goliath.tscn:2704,2740`, `scenes/game_camera/gamecamera.gd:41`
- Notes / 说明: 转场/Boss 演出节点靠 `PROCESS_MODE_ALWAYS` 在 `paused` 下继续播放，但 `Engine.time_scale=0.07` 仍会把它们拖慢（表现为"子弹时间时转场/Boss 动画变慢"）。要让某段完全不受慢放影响，必须显式把 `time_scale` 压回 1；本项目用 `GameEvents.begin_time_block(tag)`。
- Source / 来源: code
- Date / 日期: 2026-09-26

### [Time] 慢放恢复逻辑不能挂在被 `Engine.time_scale` 缩放的动画/计时器上
- Evidence / 证据: 旧 `hina_ps.gd` 用 `qte_anim` 的 method track `emit_qte_end`（`scenes/player/hina/hina.tscn:438`）→ `qte_false` 复位 `Engine.time_scale`，而该 AnimationPlayer 自身被 0.07 缩放 → 恢复慢约 14 倍；`create_timer` 同样被缩放（`scenes/manager/round_manager.gd:98,116`）。
- Notes / 说明: 恢复/兜底必须用不受缩放的时间源（`Time.get_ticks_msec()` 墙钟，或 `create_timer(..., ignore_time_scale=true)`）。否则在转场/暂停/演出期间会卡在慢放（场景切换还会因 owner 被释放而永久泄漏 `time_scale`）。
- Source / 来源: code
- Date / 日期: 2026-09-26

### [Time] `Engine.time_scale` 已收敛到 `GameEvents` 唯一写者
- Evidence / 证据: `script/GameEvents.gd`（`request_slow`/`end_slow`/`clear_slow`/`begin_time_block`/`end_time_block`、`_process` 墙钟过期、`_ready` → `PROCESS_MODE_ALWAYS`）；调用方 `scenes/player/hina/hina_ps.gd`。（`ui/cheat_menu.gd` 原也调用 `request_slow`，2026-10-03 起改为 `get_tree().paused`，见下方 `[Debug]` 条目。）
- Notes / 说明: 新增慢放一律走 `GameEvents.request_slow(id, scale, hold)`，勿再裸写 `Engine.time_scale`。`hold>0` 为刷新式租约（停止请求即自动恢复），`hold==0` 为永久直到 `end_slow`。转场（`ui/transition.gd`）与 `emit_camera_move(black_frame=true)` 相机演出会 `begin_time_block` 压制慢放（阻断即清空、不恢复）；`game_over_page.gd:119` 的死亡慢放 tween 是唯一直接写者，靠 `emit_game_over` → `clear_slow()` 避免冲突。
- Source / 来源: code
- Date / 日期: 2026-09-26

### [Time] 子弹时间期间打开暂停菜单会被慢放
- Evidence / 证据: `hina_ps.gd:129` → `GameEvents.request_slow("hina_qte", 0.07)`；`ui/pause_screen.tscn` 根 `process_mode=2`（WHEN_PAUSED）+ AnimationPlayer `process_mode=3`（ALWAYS），但 `Engine.time_scale=0.07` 仍缩放其动画（`pause_in`/option 变慢）。对照 `ui/game_over_page.gd:121` 在 `paused=true` 前显式 `Engine.time_scale = 1` 故结算正常。
- Notes / 说明: 修复走时间管理器集中兜底——`GameEvents._process` 检测 `get_tree().paused` 翻转，`_apply_time_scale` 在 paused 为真时强制 `BASE_TIME_SCALE` 且**不清空** `_slow_requests`；取消暂停后自动恢复未过期慢放（hina QTE 从冻结点继续，不破坏判定）。`process_mode` 不豁免 `Engine.time_scale`。
- Source / 来源: user
- Date / 日期: 2026-09-27

### [Audio] `get_node` 查找缺失节点会先报错；链式 `get_node` 遇 null 直接崩溃
- Evidence / 证据: `scenes/manager/SoundManager.gd`（原 `play_voice`/`play_talk` 写 `voice.get_node(a).get_node(b)`；4 个 sfx 方法用 `get_node`）
- Notes / 说明: `get_node(name)` 路径缺失会**先打引擎错误**再返回 null（`if not player: return` 只挡崩溃、挡不住报错），应改 `get_node_or_null`；`get_node(a).get_node(b)` 在 `a` 缺失时对 null 调方法 → `Invalid call ... in base 'Nil'`。`play_voice`/`play_talk` 曾有此风险（入参来源 `ui/ark_of_Shittim/arona.gd:99`、`ui/game_over_page.gd:145`）。现加 `_get_sfx`/`_get_nested` 两步判空助手，并给 `bgm_player`/`animation_player`/`voice_player`/`stream`/`bus_index` 补守卫；缺失一律静默返回。
- Source / 来源: code
- Date / 日期: 2026-09-26

### [Editor] `script_patch` 对已被 `.tres` 引用的 `class_name` Resource 脚本会误报 reload/parse 失败
- Evidence / 证据: 给 `resources/upgrades/ability_upgrade.gd` 加 `const RARITY_COLORS` 后 `script_patch` 返回 `gdscript_reload_failed` / `error_code 43` / `fallback_line`（行号指向 EOF），但对同一文件 `script_manage(op="find_symbols")` 正常解析、运行期 `game_eval` 也能读到 `AbilityUpgrade.RARITY_COLORS`。
- Notes / 说明: 该脚本被大量 `.tres`（`resources/upgrades/*.tres`）引用，编辑器热重载失败会报成 parse error，实际文件有效。判断此类文件是否真的语法错误，用 `find_symbols` 或运行期 `game_eval` 复核，勿仅凭 `script_patch` 的 `diagnostics` 判定。
- Source / 来源: test
- Date / 日期: 2026-09-26

### [Support] 支援角色分两层（`SupportCharacter` + `SupportAS`），召唤物独立
- Evidence / 证据: `script/support_character.gd`, `script/support_as.gd`, `script/support_data.gd:59-73`, `scenes/player_support/kei/kei.tscn` + `kei_summoned.tscn`, `scenes/player_support/ayane/ayane.gd` + `ayane_as.gd`
- Notes / 说明: `support_pack` 根统一为 `SupportCharacter`（`Node2D`）：`_ready()` 应用被动（按存档 `support_data[id].LV` + `pa_value` 自算，不再依赖 `SupportData.now_count_ability`，避免读档后该值过期）并调 `_special_effect()`。`game_add_support()` 会把 `game_support` 注入 `ins.support_card`，基类优先用它、否则回退 `SupportData.game_support`。主动 EX 统一 `SupportAS`（费用累积/输入/守卫/信号）。kei 的召唤物已拆为 `KeiSummoned extends SummonedFollower`（`kei_summoned.tscn`）由支援根的 `_special_effect()` 生成进 `"PlayerRoot"`；EX（`kei_as`）随召唤物（光环 Area2D 需跟实体）。
- Source / 来源: code
- Date / 日期: 2026-09-26

### [Enemy] 无尽缩放原共用 `endless_mult`，且 `Curve.sample` 使攻击/血量在第 10 个无尽回合封顶
- Evidence / 证据: `scenes/manager/enemy_manager.gd`（原 `endless_damage = 1 + endless_mult.sample(x) * 0.2`，`x = endless_round / 10`）, `scenes/manager/enemy_manager.tscn`（`Curve_36etd`）
- Notes / 说明: HP/BossHP/攻击原共用一个曲线；`Curve.sample` 对 offset>1 端点钳制，故 `endless_round >= 10` 后三者都不再增长（攻击仅 +40%、HP 上限 3.0、Boss 1.4）。2026-09-27 攻击改为独立 `endless_damage_curve`(ease-out) + `endless_damage_rounds`(默认 30) + `endless_damage_bonus`(默认 1.0)，软上限 +100%；`game_eval` 验证 round1=1.065 / round10=1.541 / round20=1.859 / round30+=2.0。
- Source / 来源: code
- Date / 日期: 2026-09-27
- SUPERSEDED: 2026-09-28 无尽攻击不再软上限——去掉 `enemy_manager.gd:100` 的 `clamp(...,0,1)` 并线性延长 `endless_damage_curve`（`rounds=80`/`bonus=9`），第 100 关 ×10 后随无尽回合线性无限续涨。

### [Combat] `EnemyStats` 原用 `int()` 截断会把低基数敌人伤害压成 0
- Evidence / 证据: `script/EnemyStats.gd:161-162`（旧 `int(base * Enemy_damage_mult)`；新 `max(1, ceili(...))`，`base<=0` 保持 0）
- Notes / 说明: base 1 × 难度 `level_damage` 0.8 = 0.8 → 旧 `int` = 0，敌人完全无伤害；`ceili` 后为 1。`game_eval` 验证：base1×0.8→1（旧 0）、base5×0.9→5（旧 4）、base5×0.8→4、base0→0。⚠️ 改的是全模式共用结算点，普通模式敌人伤害会整体上浮；`shield`/`sandbag` 的 base0 用条件保留（不可无条件 `max(1,…)`）。
- Source / 来源: test
- Date / 日期: 2026-09-27

### [Combat] 玩家护甲系数 0.01→0.02 是敌人伤害偏低的根因
- Evidence / 证据: `script/player_health_component.gd:77`（`raw * 1/(1 + hurt_resis * armor_coeff)`，`armor_coeff` 默认 0.02，`:11`）；旧公式注释 `script/health_component.gd:112`（`armor * 0.01`）
- Notes / 说明: `stats.hurt_resis = (base_hurt_resis + hurt_resis_add) * hurt_resis_mult * ability_mult`（`PlayerData.gd:373`），系数翻倍使减伤显著增强。已抽出 `@export armor_coeff`（默认 0.02，保持现状），调低（如 0.01）可整体提升玩家受伤。该行 `floor(...)` 与 `:81` 的 `int` 赋值仍在压低最终伤害。
- Source / 来源: user
- Date / 日期: 2026-09-27
- SUPERSEDED: 2026-09-27 已移除 `armor_coeff`，护甲改为指数曲线（见下条）；本条目仅存史。

### [Combat] 玩家护甲改为指数减伤曲线（前陡后平，上限 80%）
- Evidence / 证据: `script/player_health_component.gd:34-35`（`_armor_reduction() = armor_cap * (1 - exp(-hurt_resis / max(0.001, armor_k)))`）、`:81`（`mitigated = max(1, floor(raw * (1 - reduction)))`）、`:11-12`（`armor_cap=0.8`、`armor_k=20`）
- Notes / 说明: 取代旧 `1/(1+hurt_resis*0.02)`（`armor_coeff` 已删）。前期每点护甲收益显著提高、后期趋近 `armor_cap` 上限；`armor_k` 越小前段越陡。22 个玩家场景未序列化该字段 → 脚本默认值全局生效，无需逐场景改。`game_eval` 验证：护甲 0/10/30/60/100/200 → 减伤 0%/31.5%/62.1%/76.0%/79.5%/80%（单调、前陡后平）；小 `raw` 经 `max(1,…)` 保底 1 点。⚠️ 与同日敌人伤害上调（`EnemyStats` `ceili`）配套：早期护甲更强、后期封顶，避免高护甲无敌。
- Source / 来源: user
- Date / 日期: 2026-09-27

### [Perf] 玩家属性重算改为合并/延迟，消除每发子弹/每次命中的同步全量重算
- Evidence / 证据: `script/PlayerData.gd:326-341`（`_ability_depth`/`_ability_pending` + 至多 8 代循环）、`scenes/manager/player_buff_manager.gd:16-24`（`call_deferred` 每帧合并）、`scenes/manager/summoned_manager.gd:7-18`（批量刷新）、`script/SummonedStats.gd:48-51`（移除逐个订阅）
- Notes / 说明: 原先玩家 buff 的 `_host_refresh` **同步**调 `update_player_ability()`，而 buff 由每发 `player_gun_shoot`、每次命中 `enemy_damage_taken` 等驱动 → 高频全量重算 + 信号级联（`concentrated_ammo`/`hasumi_ps`/`serika_ps`/`bug_eating_plant`/`nonomi_ps`/`tsurugi_ps` 等订阅者回头再调 update）。现改为：(1) 玩家 buff 刷新 `call_deferred` 每帧合并；(2) 重算期间嵌套 update 只置脏，由外层循环收敛（最多 8 代，防死循环）；(3) 召唤物 stats 由 `SummonedManager` 统一批量刷新，去掉每个召唤物的一次订阅；(4) `hp/max_ammo/pick_up_range_changed` 仅在值变化时发。`game_eval` 验证：病态重入 handler 最多触发 8 代（不死循环），属性重算结果正确（9→19）。⚠️ 语义变化：buff 带来的 `player.stats` 派生值现在最多延迟 1 帧生效（HUD/buff 图标本身仍即时）。
- Source / 来源: code + test
- Date / 日期: 2026-09-27

### [Pickup] 运行时开启 `Area2D.monitoring` 不为已重叠 body 补发 `body_entered`，导致长按拾取漏触发
- Evidence / 证据: `scenes/item/hold_pickup_item.gd:22-32,39-44`（`_ready` 常开 `monitoring` + `can_pick` 门控、`emit_can_pick` 时补开始）、`scenes/item/medical_kit.tscn`（`Area2D.monitoring = true`，原为 false；`spawn_anim` 在 t=0.2 的 method 轨道调 `emit_can_pick`）
- Notes / 说明: 医疗箱生成期间玩家已进入 35px 范围、随后才把 `monitoring` 置 true 时，没有新的进入跳变 → `_on_area_2d_body_entered` 不再触发，进度不走（须离开再进入）。改为 `Area2D` **始终监测**、用 `can_pick`（由 `emit_can_pick` 置真）门控：生成期间只记录 `player`，可拾取瞬间若 `player != null` 立即 `pick_progress()`。`game_eval`（真物理重叠）验证：生成中 `player_detected_before_can=true`、`on_pick_before_can=false`；`emit_can_pick()` 后 `can_pick`/`on_pick`/`timer_running` 均为 true。同类“先摆范围、后开监测”的拾取物都应沿用此模式。
- Source / 来源: user + test
- Date / 日期: 2026-09-27

### [Bullet] `r_move` 把 `direction` 写成速度量级 + `slow_down` 复用它 → 丢目标时指数放大到 inf/NaN → Rapier panic
- Evidence / 证据: `script/player_bullet.gd:181-184`（原 `direction = ...normalized() * speed`，现改为单位）、`:143`（`velocity = direction * v_value`）、`:160-166`（homing_range 门控）、`scenes/bullet/megu_bullet.gd:29`（重置 `acceleration`）
- Notes / 说明: `_physics_process` 先跑 `slow_down`（用上一帧 `direction`），再跑 `r_move`（把 `direction` 写成 `speed` 量级）。追踪丢目标/超范围时 `r_move` 被跳过、末尾 `limit_length(speed)` 不再兜底 → `velocity = direction * v_value` 每帧平方放大（实测 600 → 3.6e5 → 2.1e8 → … → inf/NaN）。非有限速度使子弹 `CollisionShape2D` 落在 NaN/∞ 坐标 → Rapier `parry2d bvh_binned_build.rs:61` / `rapier2d narrow_phase.rs:723` panic 每帧刷屏（Megu 高频喷火 + 追踪频繁丢敌，波次越高越易触发）。修法：`r_move` 保持 `direction` 单位、期望速度用 `direction * speed`；`active_state` 重置 `acceleration`；homing 加 `homing_range`(1400≈地图对角) 门控（超范围跳过、不回收）。受控验证：丢目标后 `velocity` 保持 ≤ speed、`finite_after=true`；同类隐患见 `normal_bullet.gd`（同期修复）。
- Source / 来源: user + test
- Date / 日期: 2026-09-27

### [Bullet] `PlayerBullet` 子类重写 `active_state()` 漏开墙壁射线 → 池化复用后永不撞墙
- Evidence / 证据: `scenes/bullet/megu_bullet.gd:27-49`（原缺 `ray_cast_2d.enabled = true` 与 `target_position`；2026-09-27 补）、`script/player_bullet.gd:108-136`（基类 `active_state` 才开射线并设 `target_position.x`）、`:84-106`（`idle_state` 关射线）
- Notes / 说明: 子弹对象池复用；`idle_state()` 会 `ray_cast_2d.enabled = false`，只有基类 `active_state()` 会重新打开并设 `target_position.x = speed*0.0167`。`megu_bullet` 重写 `active_state()` 未调 `super` → 复用后射线恒关，`_physics_process` 的 `is_colliding()` 永远 false → 不撞墙（首次生成时因场景默认 `enabled=true` 仍能撞，表现为“基本不撞/时好时坏”）。另 `megu_bullet._ready` 未调 super，射线长度停在场景固定 7px，高速时会穿墙。修法：子类 `active_state` 里 `ray_cast_2d.enabled = true` + `ray_cast_2d.target_position.x = speed*0.0167`（或调 `super.active_state()`）。`game_eval` 验证：idle 后 `enabled=false`、active 后 `enabled=true`、`target_x=10.02`；对墙实测发生反弹（velocity.x 反向）。
- Source / 来源: user + test
- Date / 日期: 2026-09-27

### [Combat] 接触击退 ≥ 玩家 `MAX_SPEED` 会把玩家钉在墙角无法脱身
- Evidence / 证据: `script/enemy_part.gd:112-139`（`_push_player` 每 `contact_interval` 推 `contact_knockback*1.5*resist`）、`script/player.gd:367-370`（`apply_knockback` 封顶 `stats.MAX_SPEED`）、`scenes/enemies/shield.tscn:55-56`（`contact_knockback` 250→100、加 `contact_interval=0.3`）
- Notes / 说明: `apply_knockback` 直接覆盖 `velocity`；玩家 `move()` 每帧只按 `ACCELERATION*delta`（≈12.9）把速度拉回 `输入*MAX_SPEED`。盾兵 `contact_knockback=250` → 击退 `250*1.5*0.8=300`（≈2× 玩家 `MAX_SPEED` 155），每 0.2s 复推；在墙角速度被墙抵消、位置冻结（实测 60 帧 pos 不变、`on_wall=true`、velocity≈166），连 `move()` 的反弹阈值（`>MAX_SPEED*2`）都够不到 → 输入无法脱身。修法：(1) `apply_knockback` 封顶到 `MAX_SPEED`；(2) 接触击退源的值应 `< MAX_SPEED`、间隔不宜过短。`game_eval` 验证：300 击退 → 封顶 155；shield 100/0.3（实际推 120 < 155）。
- Source / 来源: user + test
- Date / 日期: 2026-09-27
- SUPERSEDED: 2026-09-27 此修法已撤销（限速移除、盾兵数值还原）。真正根因是运行期 Area 残留导致的隔空推，见下条。

### [Enemy] 接触击退改用场景预置 `HitBox`（运行期 `Area2D + get_overlapping_areas()` 在 Rapier 下会残留 → 隔空推）
- Evidence / 证据: 旧 `script/enemy_part.gd:_build_knockback_area()`（运行期 `Area2D.new()` + `get_overlapping_areas()`）；新 `scenes/enemies/shield.tscn`（`HitBox` Area2D：`monitorable=false`、`collision_mask=2048`、形状 28×58）+ `script/enemy_part.gd`（`_on_kb_area_entered/exited` 维护 `_kb_contacts`、`contact_range` 距离保险）
- Notes / 说明: 旧实现运行期新建 `Area2D` 后反复 `get_overlapping_areas()`；Rapier2D 下这个重叠列表会**残留**——盾兵离开后仍长期报与玩家 HurtBox 重叠，于是每 `contact_interval` 隔空推（实测 `[PUSH] d` 从 13 一路到 223；玩家被从 (691,143) 推到 (1245,300) 甚至地图外），玩家“脱离后 5s 都恢复不过来”，全程与击退力度无关。改为场景预置 `HitBox`（`monitorable=false` 以免自动触发玩家受伤）+ `area_entered/exited` 边沿事件 + `contact_range` 距离保险。`game_eval` 验证：相邻→推一次 `(0,-375)`；远离→0 次；接触集合 `near=1 / far=0`。**通用教训：任何“持续判定某 Area 是否重叠”都不要依赖 `get_overlapping_areas()`，优先边沿事件或显式形状查询。**（`hurt_box.gd:_build_contact_probe` 用 `get_overlapping_bodies()` 的接触伤害同理待观察。）
- Source / 来源: user + test
- Date / 日期: 2026-09-27
- SUPERSEDED: 2026-09-27 触发实现已重做（见下条）：`_kb_contacts`→`_kb_targets`、直接 `apply_knockback`→`hit_received.emit(DamageData)`、mask 2048→10240（含召唤物）；“边沿事件 + 场景 HitBox + 距离保险”的核心结论仍成立。

### [Combat] 盾兵接触击退改用「0 伤害 DamageData」经目标受伤组件结算；玩家血量组件支持 0 伤害击退
- Evidence / 证据: `script/enemy_part.gd`（`_build_contact_damage_data` / `_physics_process`：`DamageData.fill({damage:0, knockback:250, type:MELEE, source:ENEMY})`，每 `contact_interval` 对 `_kb_targets` 逐个 `hit_received.emit`）、`script/player_health_component.gd`（早退放宽为仅 `is_invincible`；`base_damage<=0` 走 `_apply_player_knockback`，`:37-53` + `:146+`）、`scenes/enemies/shield.tscn`（HitBox `collision_mask=10240`）
- Notes / 说明: 玩家 `take_damage` 原在 `base_damage<=0` 直接 `return`，故“0 伤害 + 击退”的 DamageData 对玩家完全无效（召唤物侧 `_apply_knockback` 本就在伤害门之外，天然支持）。改为：仅 `is_invincible` 早退；`raw_damage<=0` 时若有 `knockback_force` 则只调 `_apply_player_knockback` 后 `return`（不扣血 / 不吃 `hurt_invalid` / 不进无敌帧 / 不触发 `on_hit_effects`）。护盾 HitBox mask 含 `player_box`(12)+`summoned_box`(14)，用 `Faction.of_entity(area.owner)==PLAYER_SIDE` 过滤 → 覆盖玩家与可受伤召唤物；对 `contact_invincible`（跳跃/无敌帧）跳过。`game_eval` 验证：玩家 hp 72→72、velocity 300（击退生效）；无敌帧内 `max_vel=0`；`mobu_trinity` 被击退、无伤害。
- Source / 来源: user + test
- Date / 日期: 2026-09-27
- SUPERSEDED: 2026-09-27 用户微调后 `enemy_part.gd` 移除了 `contact_invincible`/`contact_range` 门，并改为结算前后切换 `HitBox/CollisionShape2D.disabled` + `clear()` 数组；“跳跃/无敌帧跳过”改由 Area2D 检测层天然处理（不靠代码门）。见下条。

### [Combat] 盾兵接触击退·用户微调：形状启停 + 结算后清空数组（移除无敌/距离门）
- Evidence / 证据: `script/enemy_part.gd`（`add_damage_data()`：结算前后切 `HitBox/CollisionShape2D.disabled`、`_kb_targets.clear()`；`_physics_process` 冷却到位后调它）、`scenes/enemies/shield.tscn`（`contact_range=0.0`、HitBox 形状 28×58→22×50）
- Notes / 说明: 在「场景预置 HitBox + `_kb_targets` 数组 + 每 `contact_interval` 发 `{damage:0, knockback:250}` 的 DamageData」基础上，用户改为“结算时短暂启停形状 + 清空数组”以强制重置（规避残留）；同时移除了 `contact_invincible` 与 `contact_range` 判断 → 无敌帧/跳跃免疫改由 **Area2D 检测层**处理（玩家 HurtBox 的 `monitorable`/`monitoring` 状态），无需代码里的 `contact_invincible` 门（来源：user）。
- Source / 来源: user
- Date / 日期: 2026-09-27

### [Perf] 伤害数字显示频率随 FPS 自适应；降频不能改全局 tick
- Evidence / 证据: `scenes/manager/PoolManager.gd:17-28,181-209`（FPS EMA + `text_tick_skip` + `get_text_tick_skip()`），`script/enemy_hurt_floating_text.gd:60-70`（按 skip flush）
- Notes / 说明: `GameEvents.global_time_count`（0.1s，`round_timer.gd:173` / `test_room.tscn`）被 `EnemyStats`、状态机、子弹等大量系统共用，**不是**伤害数字专用；降频只能在消费者侧按 `PoolManager.get_text_tick_skip()` 跳过 tick，不能调 `GlobalTimer.wait_time`。35–55 为滞回带 + 每档停留 10 tick(~1s)，防止「飘字少→帧回升→飘字多」的反馈震荡。低帧时首击不立即弹。范围仅敌人聚合伤害数字。
- Source / 来源: user
- Date / 日期: 2026-09-27

### [UI] 触屏卡片：按「释放点位移」区分点按/滚动拖动，用静态锁 + 单指跟踪防多指重复触发
- Evidence / 证据: `ui/test_character_card.gd`（`_on_button_gui_input` 内 `TAP_MAX_DISTANCE` 位移阈值、`touch_index` 单指跟踪、`static var _selection_locked`；`_preview_text()` 先 `emit_player_card_touch` 再置 `on_touch`）
- Notes / 说明: 前提 `project.godot:204` `pointing/emulate_mouse_from_touch=false`，触屏不走 `Button.pressed`（Godot `BaseButton::gui_input` 只处理 `InputEventMouseButton`/`Motion`），所有触屏交互必须手写 `InputEventScreenTouch`。旧 `test_character_card` 只在「按住 >0.1s 后松手」就选角：拖动滚动松手也会触发，且每张卡各自 `on_touch`，多指会在同/异卡各触发一次 → 重复生成玩家。修法：① 记录 `touch_index`/按下坐标，松手时 `distance > TAP_MAX_DISTANCE` 判为滚动，不预览不选中；② 同卡 `touch_index != -1` 时忽略后续手指；③ `static var _selection_locked` 全局互斥，`_on_button_pressed` 开头置真、`await` 结束后复位；④ 两段式改为「第一次点按预览、第二次点按选中」，预览揭示先广播 `player_card_touch` 再设自身 `on_touch`（否则被自身 `touch_out` 清掉）。`game_eval` 验证：tap→preview、drag→reject、第二指被忽略、全局锁阻断。同类手写触摸卡（`ui/test_item_card.gd` 等）可复用此模式。
- Source / 来源: user + test
- Date / 日期: 2026-09-27
- SUPERSEDED: 2026-09-28 「触屏不走 `Button.pressed`」的引擎结论有误——Godot 4.7 的 `BaseButton::gui_input` 已原生处理 `InputEventScreenTouch` 并在抬起时 emit `pressed`。卡片两段式的「位移阈值 + 单指跟踪 + 全局锁」思路仍成立，但**必须同时移除 `Button.pressed` 直连**，否则第一次触摸就生效。详见文末 2026-09-28 条目。

### [UI] Godot 4.7 `BaseButton` 原生响应触摸并 `emit pressed`；`Button.pressed` 直连会绕过手写两段式
- Evidence / 证据: `ui/test_item_card.tscn`/`ui/test_enemy_card.tscn`/`ui/test_character_card.tscn`（原各有 `[connection signal="pressed" from="Button" to="." method="_on_button_pressed"]`）；引擎 `BaseButton::gui_input` 的 `Ref<InputEventScreenTouch>` 分支（按下记 `touch_index`，抬起 `on_action_event` → `action_mode=RELEASE` 时 `_pressed()` → emit `pressed`）；`ui/test_item_card.gd`/`ui/test_enemy_card.gd`/`ui/test_character_card.gd`。
- Notes / 说明: 与旧结论相反：4.7 `BaseButton` 直接处理触摸并在**第一次**触摸抬起时发 `pressed`，因此 `pressed` 直连业务函数的卡片会“一摸即生效”，绕过 `_on_button_gui_input` 里的 `on_touch` 两段式门（表现为首次触摸同时预览并执行）。修法：三张卡移除 `pressed` 连接，统一在 `_on_button_gui_input` 用「抬起点位移阈值 `TAP_MAX_DISTANCE=14` + 单指 `touch_index`」判点按（未预览→`_preview_text()`，已预览→`_on_button_pressed()`）；补 `InputEventMouseButton`（左键按下）分支保留桌面单击立即生效。`test_enemy_card` 另补 `GameEvents.player_card_touch.connect(touch_out)`（原来缺，点别的卡不收起文本），`touch_out` 改同步且 `_preview_text` 先广播再置自身状态。`game_eval` 验证：三卡 tap→preview(`on_touch=true,visible=true`)、second tap→apply(`on_touch=false`)、drag→reject；桌面 mouse click→apply。
- Source / 来源: code + test
- Date / 日期: 2026-09-28

### [UI] 测试菜单 RESET/CLOSE 同时连 `gui_input` 与 `pressed` → 移动端一次触摸双触发
- Evidence / 证据: `ui/test_menu.tscn`（`Reset`/`Close` 同接 `gui_input`+`pressed`）、`ui/enemy_test_menu.tscn`/`ui/character_test_menu.tscn`（`Close` 同）；对应 `_on_reset_gui_input`/`_on_close_gui_input` 内只是再调一次 `_on_*_pressed`。
- Notes / 说明: 因 4.7 `Button.pressed` 在触摸时也会触发（见上条），再手写 `InputEventScreenTouch` 的 `gui_input` 转发就会一次触摸调用两次处理函数（`RESET` 可能并发重载玩家）。修法：删掉这些 `gui_input` 连接及只做转发的 `_on_*_gui_input`，触摸与鼠标都交给 `pressed` 单一路径。
- Source / 来源: code + test
- Date / 日期: 2026-09-28

### [Save] 记分板每次保存多出两条相同记录：`submit_button` 同接 `gui_input`+`pressed`，4.7 触摸双触发
- Evidence / 证据: `ui/player_id_input.tscn:206-207`（原 submit/cancel 同接 `gui_input`+`pressed`）→ `ui/player_id_input.gd:48` `GameEvents.emit_player_id_print` → `ui/game_over_page.gd:62-78 print_player_score` → `script/Game.gd:92 save_record_as_json`（每条追加一行）。运行期 `game_eval`：`submit_button.get_signal_connection_list("pressed")==[]`，`gui_input` 仅 `_on_submit_button_gui_input`。
- Notes / 说明: 4.7 `BaseButton` 原生处理 `InputEventScreenTouch`（见上文 2026-09-28 两条）：触摸「按下」触发手写 `gui_input` 分支、触摸「抬起」再 `emit pressed`，同一次点击 `_on_submit_button_pressed` 执行两次 → 同一秒写入两条完全相同的 JSON（`date` 精确到秒，故截图两条一模一样）。桌面鼠标只走 `pressed`，故仅移动端复现；个别设备抬起事件可能被隐藏输入层吞掉，故表现为「部分玩家」。同类遗留节点一并修：`ui/player_id_input.tscn` submit/cancel、`scenes/main/menu_screen.tscn` score/credits、`ui/scoreboard.tscn` reverse_order（两次切换→净无变化，移动端排序按钮失效）、`ui/return.tscn` 根 Button（`_on_gui_input` 未判 `event.pressed`，down/up + `pressed` 多次 `pause_press`）。本次统一采用「删 `pressed` 直连、`gui_input` 单一路径」：各脚本加 `_is_button_press(event)`（`InputEventScreenTouch.pressed` / `InputEventMouseButton` 左键 / `ui_accept`），命中才调用原 `_on_*_pressed`，保留桌面鼠标与键盘/手柄激活。注意：`ui/test_menu.tscn` 等同根因节点用的是相反改法（删 `gui_input`、留 `pressed`）；同一节点只能保留一条路径，两法不可叠加。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [UI] 测试菜单 `GridContainer` 为 `mouse_filter=PASS`，指针事件会从卡片冒泡到 `ScrollContainer`
- Evidence / 证据: 运行期 `game_eval`：`EnemyTestMenu/Node2D/ScrollContainer/GridContainer.mouse_filter == 1`（PASS），卡片根与 `Button` 均 PASS，`ScrollContainer` 为 0（STOP）。
- Notes / 说明: 因此卡片点击（`BaseButton` PASS）会继续冒泡穿过 GridContainer 到达 ScrollContainer（这也是在卡片上拖动仍能滚动的原因）。若想在 ScrollContainer 的 `gui_input` 里做「点空白收起卡片文本」，必须排除落在卡片上的按压：用 `scroll_container.get_global_transform_with_canvas() * event.position`（`gui_input` 收到的 `event.position` 已是 ScrollContainer 本地坐标）求出画布全局点，再对 `box.get_children()` 逐个 `get_global_rect().has_point()` 判断；否则同一张卡的第二击会在按下时被误收起，之后变成「再预览」而不是「生效」。`ui/enemy_test_menu.gd` 已按此实现（点空白 / `Refresh` / `Close` / `use` 关闭时清文本）。`game_eval` 验证：卡点→preview、跨卡→前卡隐藏、空点→隐藏、同卡二击→apply、卡上拖拽→不响应。
- Source / 来源: code + test
- Date / 日期: 2026-09-28

### [Combat] 治疗溢出转临时生命统一收口在 `Stats.hp` setter
- Evidence / 证据: `script/Stats.gd`（`heal_overflow_to_t_hp` + `hp` setter 溢出分支）、`script/heal_data.gd`（`ignore_heal_mult` + `fill` cfg）、`script/player_health_component.gd:65`、`scenes/player/t_hp_count.gd:t_hp_clear()`
- Notes / 说明: `stats.hp += N` 与统一治疗路径（`HealData.fill → take_damage`）都会经过 `Stats.hp` setter，故溢出判定放在 setter 内（`v - max_hp > 0` 且 `heal_overflow_to_t_hp`）可覆盖**所有**治疗来源，包括直接 `stats.hp +=` 的 `school_bag`/`tactical_satchel`（它们不走治疗管线）。溢出分支在 `hp == v` 早退**之前**，故满血治疗也能转入 `t_hp`；`t_hp` setter 自动 clamp 到 `max_hp/2`，超出丢弃。固定数值治疗（不受 `heal_mult`）用 `HealData.ignore_heal_mult=true`（serina EX 每秒 5% max_hp）。开关只在 EX 期间开启，回合边界由 `t_hp_count` 兜底关闭。
- Source / 来源: user + code
- Date / 日期: 2026-09-27

### [Save] 支援角色购买不落盘（`unlock_support` 漏存档）；存档全靠"即改即存"，无退出兜底
- Evidence / 证据: `ui/support_shop.gd:152-160`（`unlock_support` 原无存档）、`script/support_data.gd:80-88`（`add_new_data` 原无存档）、`script/PlayerData.gd:13-20`（`player_pyroxenes` setter 调 `Game.save_playerdata()`）、`ui/character_shop_card.gd:125-131`/`ui/item_shop_card.gd:119-122`（同类商店在 `add_*` 内存档）、`scenes/main/menu_screen.gd:263,268`（Quit 直接 `get_tree().quit()`）、`script/Game.gd`（无 `NOTIFICATION_WM_CLOSE_REQUEST`）
- Notes / 说明: 购买支援时 `PlayerData.player_pyroxenes -= cost` 先触发 setter 存档（**此时 `support_data` 还没写入**），随后 `add_new_data` 只改内存不落盘 → 退出后碎片被扣、支援丢失。同类角色/道具商店都在 `add_*` 内显式 `Game.save_playerdata()`，唯独支援漏了。修法（A+B）：`unlock_support` 在 `add_new_data` 后补 `Game.save_playerdata()`，且 `add_new_data` 末尾也存档（数据层自持持久化，防未来调用者再漏）。**注意**：此处不能用 `SupportData.save_data()`——它会把购买前的 `now_lv=0/now_exp=-1` 写回、覆盖刚加的新条目。全局无退出存档（`get_tree().quit()` 不触发 `NOTIFICATION_WM_CLOSE_REQUEST`），故所有持久化都必须"即改即存"。`game_eval` 验证：模拟购买→清内存→`Game.load_playerdata()` 后 `support_data.has("serina")=true`、`LV=1`、碎片正确。
- Source / 来源: user + test
- Date / 日期: 2026-09-27

### [Save] Godot 加载 `.res`/`.tres` 时脚本已删除的属性会被静默丢弃 → 存档字段改名/删除必须做迁移
- Evidence / 证据: 2026-10-04 重写 `script/scene_data.gd`（删 `game_version`、加 `save_version`）后加载旧 `user://PlayerData.res`：旧档里已不再声明的 `game_version` 直接消失（不报错），而保留原名的 `support_savedata` 正常读到；实测旧档 2876 B → 迁移并自动重写为 1718 B 新档、原档存为 `PlayerData.res.bak`，`character`(22)/`group`(6)/`support_savedata`(3)/`game_mode`/`player_pyroxenes`/`game_support` 全部保全。
- Notes / 说明: Resource 反序列化只填充脚本仍声明的属性，未声明者被丢弃（无警告）——所以**改名/删除存档字段是破坏性变更**：改名前须在迁移期按旧名读取再写新名，删除前确认确为冗余。`SceneData.save_version` 默认值必须是 **0** 而非当前版本：旧档无该字段会解析为默认值，若默认=当前版本则旧档被误判为最新、永久跳过迁移。`save_playerdata` 采用「临时文件 → 备份旧档 `.bak` → 替换」的原子写，避免写坏唯一存档。
- Source / 来源: code + test
- Date / 日期: 2026-10-04
- SUPERSEDED: 2026-10-13 仅修正末句“原子写”的可靠性结论：当前是两次 rename，无失败回滚或备份加载；损坏主档还会在首次货币变化时覆盖有效 `.bak`。字段迁移结论仍有效。隔离复现见 `docs/CODEBASE_AUDIT_20261018.md`（归档） 的 AUD-SAVE-001，准确流程已更新 `ARCHITECTURE.md` §2（来源：test）。
- SUPERSEDED: 2026-10-13 本轮已修复恢复/写入路径：`scene_data_store.gd:15,41` 验证主档后读取备份，只轮换有效主档，不先移走主路径；双坏档/未来版本禁止自动覆盖。7 类回归通过。原字段迁移结论保留（来源：test）。

### [UI] 升级卡/道具卡文本只来自 `id` 派生的翻译 key，不读 `AbilityUpgrade` 文本字段
- Evidence / 证据: `ui/ability_upgrade_card.gd:76-79`（`upgrade.id + "_name"/"_description"/"_forward"/"_negative"`）、`ui/upgrade_item_card.gd:34-37`（同）；全项目无 `upgrade.name/description/forward/negative` 的显示消费
- Notes / 说明: 卡片把这些 key 交给 `Label` 自动翻译渲染；`.tres` 的 `name/description/forward/negative` 对升级卡与局内道具卡**无显示作用**。新增道具只需在 `ETN_item_localization.csv` 补 `<id>_name/_description/_forward/_negative` 四行（`.tres` 文本留空也行），未补则卡面直接显示原始 key。
- Source / 来源: code
- Date / 日期: 2026-09-27

### [Localization] CSV 未闭合引号会吞并后续行，导致整段翻译丢失（UI 显示原始 key）
- Evidence / 证据: `ETN_shop_localization.csv:33,34,35,38,39,40`（`vi_VN` 列的值以 `"` 开头但未闭合、且越南语被截断）；`ui/ark_of_Shittim/talk_text.gd:8`（对话用 `tr(talk_text)` 渲染）；`resources/talk/plana/*.tres`（`talk_text` 即这些 key）
- Notes / 说明: CSV 引号字段允许跨行，**未闭合的 `"` 会把后续行并入同一字段**，使该 key 及其后若干记录被合并/丢失，`.translation` 无对应条目 → `tr(key)` 返回 key 本身 → UI 显示 `plana_work_in_4` 之类的原始 key。排查法：用 RFC4180 解析器（如 `Microsoft.VisualBasic.FileIO.TextFieldParser`）或标准状态机整文件解析，检查**每行字段数是否为预期列数**；逐行统计引号奇偶会误报——多行合法字段本就呈奇数。修好 CSV 后必须 `filesystem_manage scan` → `reimport` 重新生成 `.translation`（见下方 §Localization 条目）。
- Source / 来源: code + test
- Date / 日期: 2026-09-27

### [Enemy] 敌人血量/攻击已曲线化；Boss 血量必须独立曲线（基础血量悬殊）
- Evidence / 证据: `script/enemies_spawn.gd:get_level()`（`hp_mult = hp_base.sample(x) * pow(hp_lv, hp_growth_curve.sample(now_round/max_round))`、`damage_mult = level_damage * round_damage_curve.sample(x)`）；`scenes/manager/enemy_manager.tscn`（`Curve_round_hp`/`Curve_round_boss_hp`/`Curve_hp_growth`/`Curve_round_dmg`）；`scenes/enemies/boss/erosion_tower.tscn`(max_hp 18000)/`goliath.tscn`(25000) vs 杂兵 35~650
- Notes / 说明: 各 `enemies_spawn_lv_*`/Boss 场景的 `damage_mult`/`hp_mult` 导出值已清空回默认 1.0，运行时由 `enemy_manager` 的曲线驱动——**不要再往场景里写这两个值**（会被 `=` 覆盖）。Boss 与杂兵的 `hp_mult` **不能共用一条曲线**：Boss 基础血量高 2~3 个数量级，标定值反而更小（5.0/6.5 vs 杂兵 28/35），故 `round_boss_hp_curve` 单独一条，按 `boss_round` 选。base 曲线按 `(now_round-1)/(max_round-1)` 归一化，普通20/闪击15自动等比；无尽时 x clamp 到 1、`hp_growth_curve` 指数封顶 2（不再无限增减）。
- Source / 来源: code
- Date / 日期: 2026-09-27
- SUPERSEDED: 2026-09-28 无尽血量不再封顶——`endless_mult`（`Curve_36etd`）已线性延长至 x=1000，见下方 [Curve] 条目。

### [Editor] 手写 tscn 的 `Curve` 按存储切线采样，`TANGENT_LINEAR`(1) 不生效
- Evidence / 证据: 手写 `enemy_manager.tscn` 的 `_data = [Vector2(0,0), 0.0, 0.0, 1, 1, Vector2(1,2), 0.0, 0.0, 1, 1]`（模式 1 + 切线 0）→ `sample(0.05)=0.0145`（零切线三次贝塞尔/smoothstep），而非线性 0.1；运行时 `Curve.new()` + `set_point_left/right_mode(i, Curve.TANGENT_LINEAR)` 会自动把该点切线设为相邻段斜率，采样即线性
- Notes / 说明: Godot 4.7 `Curve.sample()` 按存储的 `left/right_tangent` 做三次插值；`TangentMode.LINEAR` 只在通过编辑器/API 改模式时**触发切线重算**（= 该段斜率 dy/dx），从 tscn 文本加载并不会重算。所以**手写曲线必须自己写切线**：要线性段，就把该点朝相邻段一侧的切线写成该段斜率（`left_tangent=上一段斜率`、`right_tangent=下一段斜率`，端点外侧=0），模式用 0(FREE) 即可（本项目既有曲线皆 mode 0 + 显式切线）。省事做法：`game_eval` 里 `add_point` + `set_point_*_mode(LINEAR)`，再读回 `get_point_left/right_tangent` 誊进 tscn。
- Source / 来源: test
- Date / 日期: 2026-09-27

### [Localization] `ETN_localization.csv` 的 `vi_VN` 列曾整体错位，必须按 `zh_CN` 重译而非只补空缺
- Evidence / 证据: 修正前 `ETN_localization.csv`（`player_armor`=护甲值/Armor）的 `vi_VN` 误为「Lượng Đạn Tối đa」(=Max Ammo，属 `player_max_ammo`)；约 18–51 行系统性偏移（`en`/`pt` 列正确，仅 `vi_VN` 错位）。
- Notes / 说明: 疑因历史插入/重排键时未同步该列。仅填空白单元格无法修正非空但错位的译值，需以 `zh_CN` 为源重译整列（2026-09-27 已做，含补 `player_heal_mult` 的 `en`/`pt`）。校验用 `Microsoft.VisualBasic.FileIO.TextFieldParser` 逐条比对列数/空值，勿用 `Import-Csv`（多行引号字段会误判）。同批：`ETN_item_localization.csv` 尾 8 个新道具补 en/pt/vi，`ETN_player_localization.csv` 补 `ako_ps_*`/`chinatsu_ps_*`，`ETN_shop_localization.csv` 补 2 处 vi。
- Source / 来源: code
- Date / 日期: 2026-09-27

### [Localization] `ETN_item_localization.csv` 的 `pt` 列声调字符曾损坏成 `?`（非乱码显示）
- Evidence / 证据: 2026-09-27 实测该文件 `pt` 列有 100 个字段含损坏 `?`（`Muni??o`/`Ra??o`/`Repuls?o`/`n?o`/`rob?` 等）；字节级确认为 ASCII `0x3F`（如 `mx_ration_c_type_name` 的 pt 为 `3F 3F 6F`），非控制台乱码。`zh_CN/en/vi_VN` 及其余 4 个 CSV 均干净。
- Notes / 说明: 损坏仅发生在声调字符（`ç→??`、`ã/õ/ô→?`），字母主体保留，故按「还原重音」修复即可，无需重译（共 63 个大小写敏感 token，定点替换后仅剩 `lentes?` 等正常句末问号）。**排查编码类问题必须用字节/`\uXXXX` 转义输出判断**：控制台（及 grep 显示）会把正常重音字符渲染成 `??`，极易误判为损坏；`Import-Csv` 亦不可靠，应用 `Microsoft.VisualBasic.FileIO.TextFieldParser`。改后须 `filesystem_manage scan` → `reimport` 重新生成 `.translation`。
- Source / 来源: code
- Date / 日期: 2026-09-27

### [Export] 运行时 `DirAccess` 枚举 `res://` 目录在导出后失效（文本资源被导出为 `*.tres.remap`）
- Evidence / 证据: `ui/enemy_test_menu.gd` 原 `add_enemy_card()`（`DirAccess.open("res://resources/enemy")` + `file.ends_with(".tres")`）；直接扫描 `H:\GodotExport\Enter The Nyangeon v 0.4.1.1.exe` 确认每个敌人资源以 `resources/enemy/<name>.tres.remap` 存在（真实二进制内容在 `res://.godot/exported/...`）。导出后 `get_files()` 返回 `*.tres.remap`，`ends_with(".tres")` 恒假 → 黄球敌人列表为空；编辑器内因读的是真实 `.tres` 而正常。Windows/Android 导出同现象（移动端同样失效）。
- Notes / 说明: 修复＝改用导出数组（`@export var enemy_group: Array[EnemyCard]`，在场景内填 `ext_resource` 引用，参照 `ui/character_test_menu.gd:add_player_card()`），并把 `resources/enemy/*.tres` 在场景里显式引用（兼作「确保进包」）。**代价：新增敌人需手动加入数组/场景。** 一般规则：不要在运行时用 `DirAccess` 枚举 `res://` 来发现资源；要枚举就用导出数组/清单资源。`game_eval` 验证：`enemy_group.size()==15`、`GridContainer` 卡片数 15、id 与原字母序一致（排除 `goliath`/`erosion_tower`）。`user://` 下的 `DirAccess`（`Game.gd:74,226`）不受影响。
- Source / 来源: user + test
- Date / 日期: 2026-09-27

### [Mod] PCK 挂载后发现内容用 `ResourceLoader.list_directory`（不是 `DirAccess`）
- Evidence / 证据: `script/mod_manager.gd`（`_scan_defs_dirs` 调 `ResourceLoader.list_directory("res://mods/<id>/defs/<kind>")`）；`ResourceLoader.list_directory()` 返回「编辑器原始文件名」（目录名带 `/`），而 `DirAccess` 在导出 `res://` 只返回 `*.tres.remap`（见本文件 `[Export]` 条目）。
- Notes / 说明: mod pck 挂载到 `res://` 后，其 `defs/**` 可用 `ResourceLoader.list_directory` 枚举；`DirAccess` 不可靠。实现首选**构建期生成 `content_index.json`**（列资源路径），目录扫描作兜底。
- Source / 来源: code + test
- Date / 日期: 2026-10-04

### [Mod] `editor/export/convert_text_resources_to_binary` 默认 true → 运行时 `load()` 读不到 mod 的 `.tres`
- Evidence / 证据: `project_manage settings_set` 改该键时读回 `old_value=true`；Godot 4.7 文档 `ResourceLoader.load()` 注记「该设置 true 时导出会把文本资源转二进制，运行时 `load()` 读不到」。
- Notes / 说明: mod 系统依赖运行时按路径 `load()`，故**本体与 mod 工程都必须设 false**（已在本体 `project.godot` 的 `[editor]` 设为 false）。这是 mod 能否加载的关键前置。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Mod] `ProjectSettings.load_resource_pack` 可从 `user://` 挂载；缺 pck 返回 false（不崩）
- Evidence / 证据: `script/mod_manager.gd:_mount_one`；`game_eval` 实测：用 `PCKPacker` 生成 `user://mods/selftest/selftest.pck` + `mod.json`，重启后 `ModManager` 挂载成功并注册角色 `selftest_hero`（`get_characters()` 返回 1）；无 pck 的 `testmod` 报 `pck 不存在：testmod.pck` 且不阻断启动。
- Notes / 说明: 挂载失败仅记 `error`；启用状态存 `user://mods/mods_state.json`。pck 一旦挂载无法卸载，启停一律靠重启。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Mod] 选人接入用「多态 populate + MOD 社团卡 + 通用卡」；society_card 无 class_name 需路径继承
- Evidence / 证据: `ui/society_card.gd`（抽出 `populate_player_cards(box)`）、`scenes/main/menu_screen.gd:society_card_filter`（改为 `await society_card.populate_player_cards(player_card_box)`）、`ui/mod_society_card.gd`（`extends "res://ui/society_card.gd"`）、`ui/mod_player_card.gd`/`.tscn`。
- Notes / 说明: `ui/society_card.gd` **没有 `class_name`**，子类必须用 `extends "res://ui/society_card.gd"`（路径继承）而非标识符继承。MOD 社团卡覆写 `check_group()`（按 `ModManager.get_characters()` 是否非空显隐，绕过 `PlayerData.group` 门）与 `mouse_select_anim`/`mouse_out_anim`/`on_select_handle`/`out_select_card`（避免依赖 AnimationPlayer 动画资源）。通用卡实例化后**必须在 `add_child` 前**设 `player_card`（否则 `_ready` 读到 null）。`game_eval` 验证：`society_card_box` 出现 MOD 卡、`populate_player_cards` 填入 1 张卡、`_on_pressed` 后 `LevelSelect.player == card.player`。
- Source / 来源: test
- Date / 日期: 2026-10-04
- SUPERSEDED: 2026-10-17 通用「MOD」卡现于 `ui/mod_society_card.gd` 照搬本体社团卡的悬停/选中动画；`mod_society_base` 的空实现仍适用于 mod 自带卡。

### [Mod] 补丁/依赖引擎（P0.5）：注册表内存合并 + 拓扑排序
- Evidence / 证据: `script/mod_patch.gd`（`class_name ModPatch`；`apply_all`/`apply_one`/`_op_set`/`_op_inherit`）、`script/mod_manager.gd`（`_resolve_order`/`_apply_patches`/`_collect_patch_files`/`_register_path` 覆盖分支）。
- Notes / 说明: 补丁对 `_registry` 内存资源操作，**首次修改 `duplicate(true)`** 以免污染 `ResourceLoader` 共享缓存 / 本体资源。加载顺序：依赖缺失或成环 → 停用；`conflicts` 命中已加载者 → 后加载者停用；Kahn 拓扑 + 稳定 tie-break `(load_order, id)`，结果可复现。同名 id 仅 `manifest.overrides` 允许覆盖（后者胜 + 警告）。`game_eval` 验证：replace/add/remove/inherit 生效、缺 target 跳过；依赖缺失使 `c` 停用、`d1`↔`d2` 冲突后者停用、顺序 `["a","d1","b"]`。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Mod] 道具/支援接入（P2）：追加导出数组 + 注册表解析场景
- Evidence / 证据: `script/mod_manager.gd`（`_inject_supports`/`has_upgrade`；`_register_path` 对 `upgrades` 按同目录同名 `.tscn` 约定填 `scene`）、`scenes/manager/upgrade_manager.gd`（`_ready` 追加 `upgrade_pool`；`apply_upgrade` 经 `ModManager.get_scene` 解析 + 场景缺失不再崩）、`ui/score_card.gd`（`load_all_equip` 经 `ModManager.get_resource` 解析）。
- Notes / 说明: 支援走 autoload `SupportData.support_pool`，启动后追加即可；道具的 `upgrade_manager` 是**每局场景节点**，故在其 `_ready` 追加 `ModManager.get_content("upgrades")`（场景实例晚于 autoload，安全）。本体道具场景按 id 拼路径 `res://scenes/update_item/<id>.tscn`，而 mod 内容在 `res://mods/...` 下 → 约定 `defs/upgrades/<id>.tscn` 同目录同名，`apply_upgrade`/`score_card` 先查注册表。`game_eval` 验证：注册 1 道具 + 1 支援 → `has_upgrade=true`、`get_scene` 返回同目录 `.tscn`、`SupportData.support_pool` 3→4、`upgrade_manager` 池 112→113 且含 mod 项。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Mod] 敌人/波次接入（P3）：pool_id 校验 + 运行期构造波次并入 enemy_manager
- Evidence / 证据: `script/mod_manager.gd`（`_validate_enemy`/`get_mod_waves`/`_build_wave_scene`）、`scenes/manager/enemy_manager.gd`（`_ready` 追加 + `_group_index`）。
- Notes / 说明: `EnemyCard.id` 必须与 `body` 根 `pool_id` 一致（`PoolManager.try_claim_spawn` 按 id 计生成上限、敌人 `active_state()` 按 `pool_id` 登记），不一致则加载时跳过并告警。波次生成器结构：`Node2D` + `enemies_spawn.gd` + 子 `EnemySpawnCDTime`(Timer) + `timeout` 连接；运行期用 `PackedScene.pack()` 把构造的 Node 打包（子节点设 `owner`、Timer 连接信号），再 `append` 到 `enemies_spawn_group[group]`（元素须为 PackedScene）。`enemy_manager` 是**每局场景节点**，故在其 `_ready` 注入（此时 `@onready enemies_spawn_group` 已就绪）。`game_eval` 验证：`entest_grunt` 注册、`entest_bad`（`pool_id` 不符）跳过、`get_mod_waves` 返回 1 波、`enemy_manager.enemies_spawn_group[0]` 1→2 且可实例化。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Mod] 模式/关卡/entry 接入（P4）：UI 追加 + ModAPI + api_version 门控
- Evidence / 证据: `ui/gamemode_button.gd`（`_ready` 追加 `ModManager.get_content("game_modes")`）、`ui/level_select.gd`（`_inject_mod_levels()` 用 `ui/level_button.tscn` 模板 + 设 `level`/`level_select` 后 `add_child`）、`script/mod_api.gd`（`class_name ModAPI` 静态门面）、`script/mod_manager.gd`（`_run_entry_scripts` 的 `api_version` 门控）。
- Notes / 说明: 关卡按钮父容器为 `Node2D2/Node2D/Node2D/VBoxContainer`；`level_button.gd` 的 `level_select` 必须在 `add_child` 前设置（其 `_ready` 会连接 `level_select` 的信号）。`ModAPI` 静态方法可访问 autoload `ModManager`（**运行时有效**；编辑器静态分析因 autoload 缓存滞后会误报 `Identifier not found`）。entry 脚本实例化到 `ModManager` 下；`api_version > ModAPI.VERSION` 跳过并告警。`game_eval` 验证：`gamemode_button` grid 2→3、`level_select` 4→5、entry `_ready` 读到 `ModAPI.VERSION`、api=999 时 entry 被跳过。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Mod] 角色 player_card 一致性：注册表为真源 + 进战斗强制对齐
- Evidence / 证据: `script/mod_manager.gd`（`_validate_character`/`_index_characters`/`_index_card`/`_on_player_card_id`/`_on_first_round_add`）、`script/player.gd:12-13`、`script/PlayerData.gd:272`（`player_select = player.player_card.id`）、`ui/game_ui.gd:49-52`、`ui/pause_screen.gd:152-157`、`ui/game_over_page.gd:154-159`、`ui/ability_shop_ps_card.gd:154,170-173`、`scenes/player/momoi/momoi.tscn:265-266`。
- Notes / 说明: 角色有两处 `PlayerCard`——选人 UI 卡（`ui/mod_society_card.gd:42` 会注入注册表 card）与**战斗场景根**（`player.player_card`，被 `get_player_base_ability`/HUD/暂停/结算/PS 商店读取）。以 `defs/characters` 注册表为真源。注册时 `_validate_character` 实例化场景（**不入树**，`_ready` 不跑，读 `@export`）校验：缺 `scene_path` → **跳过**；根 `player_card` 空/`id` 不一致、`ps_card` 空 → **告警**。`_index_characters` 建 `scene_path → PlayerCard`（含 `branches`）；`GameEvents.player_card_id` 记录所选场景；`first_round_add` 处理器（连接早于 `main.gd`，故先于 `get_player_base_ability()`）把 `player.player_card` 对齐到注册表。`ps_card` 无法对齐，mod 必须自备。`game_eval` 验证：场景根 `player_card=null` → 进战斗后对齐为注册 id；缺 `scene_path` 的卡被跳过；三条校验告警如期输出。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Mod] 社团卡：自带优先、否则通用卡（按 mod 认领去重）
- Evidence / 证据: `ui/mod_society_base.gd`、`ui/mod_society_card.gd`（改用 `get_unclaimed_characters()`）、`script/mod_manager.gd`（`_scan_societies`/`_register_society`/`get_mod_societies`/`has_society_mod`/`get_unclaimed_characters`/`ensure_unlocked`）、`scenes/main/menu_screen.gd`（`_setup_mod_society` + `society_card_filter` 的 `has_method` 守卫）。
- Notes / 说明: 社团卡是 **UI 场景**而非资源，故走独立 `_societies` 集合（`{scene, mod, group_id}`）而非 `_registry`。自带社团卡**必须继承 `ui/mod_society_base.gd`**（覆写动画方法避免依赖动画资源 + 按 `members` 注入 `player_card`），场景仍需含 `AnimationPlayer` 节点（父类 `@onready card_anim = $AnimationPlayer`）。去重按 **mod 粒度**：mod 提供 ≥1 社团 → 其全部角色不进通用卡。`group_id` 默认解锁（`ensure_unlocked` 并入 `PlayerData.group`），走前缀/唯一治理。`society_card_filter` 加 `has_method("populate_player_cards")` 守卫防完全自定义卡崩溃。`game_eval` 验证：`msoc`（带社团）+`nsoc`（无）→ `societies=1`、`has_msoc=true`/`has_nsoc=false`、`unclaimed=["nsoc_hero"]`、`group_has(msoc_g)=true`、菜单 `box_delta=2`、自带卡填 `msoc_hero`、通用卡填 `nsoc_hero`。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Tooling] Windows PowerShell 5.1 读取 UTF-8 无 BOM 的 `.ps1` 会把非 ASCII 当 ANSI → 解析失败
- Evidence / 证据: 运行 `mod_sdk/setup_mod_project.ps1`（含中文 `Write-Host`/`throw` 文案）报 `MissingEndCurlyBrace` 等解析错误；文件加 UTF-8 BOM 后正常执行。`build_mod.ps1` 同理。
- Notes / 说明: PowerShell 5.1 以 `-File` 执行脚本时按当前 ANSI 代码页解码，非 ASCII（中文）会乱码并破坏引号/括号配对。含非 ASCII 的 `.ps1` 必须存为 **UTF-8 with BOM**（仅脚本工具相关；不影响本体/导出）。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Editor] 用工具新增 autoload 会重写 `project.godot`；新 autoload 标识符在编辑器静态分析里滞后
- Evidence / 证据: 手工编辑 `project.godot` 加 `[editor]`/autoload 后被 `autoload_manage add` 覆盖回写；新增 autoload 后 `script_create`/`script_patch` 对引用该 autoload 的脚本报 `Compile Error: Identifier not found: ModManager`，但运行时 `game_eval` 正常解析（`ModManager:<Node#…>`）。
- Notes / 说明: 改 autoload/导出设置**优先用 MCP 工具**（会写盘且与编辑器内存一致）；手工改文件易被编辑器回写覆盖。新增 autoload 的静态分析滞后是会话缓存，重启编辑器可消，不影响运行与导出。`[autoload]` 顺序即 `_ready` 顺序，工具 `add` 追加到末尾。
- Source / 来源: test
- Date / 日期: 2026-10-04

### [Localization] 就地填写 CSV 译文：含 ASCII 逗号的字段必须加双引号；替换勿吞掉 `\r`
- Evidence / 证据: 2026-09-27 给 34 条敌人 `<id>_name/_description` 补 en/pt/vi 时，描述译文含 ASCII 逗号却未加引号 → 行被拆成多余列、译文错位（`translate("droid_helmet_smg_description")` 只返回首个逗号前片段，余下串进 pt 列）。另用正则 `...(?<zh>...?), , , \r?$` 就地替换时 `\r` 被匹配消费，32 行退化为 LF（实测 `LF=32/CRLF=80`）。
- Notes / 说明: ① **任何含 ASCII 逗号/双引号的字段必须用 `"..."` 包裹**（描述几乎都含逗号，一律加引号最省事）；纯文本名无逗号可不加。② 就地改行用 `(?m)^<key>[^\r\n]*`（`[^\r\n]` 不含 `\r`）替换，或改后用 `[regex]::Replace($t,"(?<!\r)\n","`r`n")` 归一，避免 CR 丢失。③ 非 ASCII 值不要直接塞进 PowerShell 命令行（易被控制台编码弄坏）；走 UTF-8 JSON 临时文件 + `[System.IO.File]::ReadAllText(...,UTF8)` 传入，输出用 `[System.IO.File]::WriteAllText($p,$t,(New-Object System.Text.UTF8Encoding($true)))` 保留 BOM。④ 多行引号字段会跨行；此类「整文件重写」前需确认无嵌入换行，否则仍走 `AppendAllText`（追加）。验证：`TranslationServer.set_locale(loc)` + `translate(key)` 应返回完整译文（逗号后不截断）。
- Source / 来源: test
- Date / 日期: 2026-09-27

### [Export] `addons/godot_ai/**` 默认会被打进导出包；已用 `exclude_filter` 排除
- Evidence / 证据: 4 个 preset 原为 `export_filter="all_resources"` + `exclude_filter=""`；扫描 `H:\GodotExport\Enter The Nyangeon v 0.4.1.1.exe` 含 488 条 `addons/godot_ai/...` 路径（`.gdc`+`.remap`），磁盘上 313 文件 / ~2.07 MB。`_mcp_game_helper` 这个 autoload（`project.godot` → `res://addons/godot_ai/runtime/game_helper.gd`）由插件自带 `addons/godot_ai/export/mcp_export_plugin.gd`（`EditorExportPlugin`）在 `_export_begin` 清除 `autoload/_mcp_game_helper`、`_export_end` 恢复，故正常导出**不会运行**该 helper（独立发布版 `EngineDebugger.is_active()==false`，不监听端口）。2026-09-28 复验：外部改好 `exclude_filter` 后，编辑器内导出 v0.4.1.2 仍含 488 条——因**运行中的编辑器把内存里的旧 preset 回写覆盖了文件**；用 `--headless --export-release` 读盘导出后降到 **1 条**（仅 `addons/godot_ai/plugin.cfg` 字符串残留在 `project.binary` 的 `editor_plugins/enabled`，无实际文件），`godot-rapier2d` 63→62 条仍保留、可正常启动。**重启编辑器后**再导出 v0.4.1.2（2026-09-28 01:46）：exe 仅剩 1 条 `addons/godot_ai/plugin.cfg`（只是 `project.binary` 里 `editor_plugins/enabled` 的路径字符串，**无实际文件**），apk 的 `godot_ai` 条目为 **0**；两端 `project.binary` 均无 `_mcp_game_helper`（autoload 已被插件剥离）。
- Notes / 说明: 已在 `export_presets.cfg` 的 Windows/Android/Linux/iOS 四 preset 设 `exclude_filter="addons/godot_ai/*, addons/.godot_ai_update/*"`（Godot 的 `*` 可跨 `/`，一条覆盖子目录，已用 `String.match` 实测；`exclude_filter` 对资源文件同样生效）。**关键坑**：改 `export_presets.cfg` 后必须**重启编辑器**（或在导出对话框 Resources 页的 exclude 字段里直接填），否则编辑器导出时会用内存旧 preset 覆盖该文件、排除失效。**切勿排除整个 `addons/*`**：`addons/godot-rapier2d` 是运行时 GDExtension（物理），必须保留。改动只影响导出，不影响编辑器内使用 MCP 插件。重新导出后需扫描产物确认无 `addons/godot_ai/`。
- Source / 来源: user + test
- Date / 日期: 2026-09-27

### [Combat] 信号回调内同步改 `Area2D.monitoring` 会被引擎拒绝（须 deferred；动画轨道同理）
- Evidence / 证据: 运行 run r44902-1 报 `Function blocked during in/out signal. Use set_deferred("monitoring", true/false).`，栈：`script/hurt_box.gd:36 _on_area_entered`（`hit_received.emit`）→ `script/summoned_health_component.gd:90` → `script/summoned_follower.gd:158`（直接写 `hurt_box.monitoring = false`）；另一条同因 `:161 hurt_anim.play("hurt_anim")`，其 `HurtAnim` 动画含轨道 `scenes/summoned/mobu_trinity/mobu_trinity.tscn:167 .:monitoring`，`play()` 会同步应用 t=0 的 key 去写 `monitoring`。
- Notes / 说明: 在 `area_entered`/`body_entered` 等物理信号回调内对 `Area2D` 调 `set_monitoring`（直接赋值或动画 value 轨道）都会被引擎锁阻断。修法：把整套写入移出信号锁——`summoned_health_component.gd:96-97` 改 `owner.call_deferred("invincibility_frames")`（一处同时覆盖直接赋值与动画播放两个报错点），或在函数内对 `monitoring`/`play` 分别 `set_deferred`/`call_deferred`。`GameEvents.emit_*` 派生的调用链同样处于信号锁内。
- Source / 来源: test
- Date / 日期: 2026-09-28

### [Combat] 可受伤召唤物受伤击退 / 转发玩家击退改由 `SummonedHealthComponent` 导出开关控制（默认关）
- Evidence / 证据: `script/summoned_health_component.gd:9-11`（`knockback_on_hurt`/`transfer_knockback`/`knockback_mult` 默认 false/false/1.0）、`:85-91`（转发前按开关 `duplicate(true)` 清 `knockback_force`）、`:118-124`（受伤击退按开关，并乘 `knockback_mult`）、`:35-43`（玩家近战友伤击退保留、不受开关与系数影响）；三个使用方 `scenes/summoned/mobu_trinity/mobu_trinity.tscn`（`can_hurt=true`）、`scenes/player_support/kei/kei_summoned.tscn`、`scenes/update_item/utaha_turret_body.tscn`。
- Notes / 说明: 转发路径 `emit_deal_damage_to_player` → `scenes/player/ichika/ichika_ps.gd:75-76` 接 `player.health_component.take_damage` → `player_health_component.gd:148 _apply_player_knockback`；故转发时不清 `knockback_force` 会让玩家被击退。用 `duplicate(true)` 而非原地清零，是为了不污染可能被 AoE/穿透弹复用的共享 `DamageData`。三个字段默认值让现有场景「不击退 / 不传递击退 / 系数 100%」；将来某召唤物需要击退时在 `.tscn` 勾选并调 `knockback_mult` 即可。
- Source / 来源: user
- Date / 日期: 2026-09-28

### [Combat] 「吃无敌帧 / 无视无敌帧」由检测发起方决定，非伤害类型
- Evidence / 证据: 目标侧：`script/hurt_box.gd:39-42` 自身 `area_entered`（普通子弹/近战 HitBox）与 `:85-116` 接触探针/接触列表，受 `monitoring`/`contact_invincible` 门控；来源侧：`scenes/bullet/laser_bullet.gd:84-97` 激光用自己 `HitBox.get_overlapping_areas()` 后直接 `hit_received.emit`，只要求目标 `monitorable=true` + 形状启用。玩家受击 i-frame 只 `set_invulnerable(true)`（不动 `monitorable`），故激光照打；跳跃 `set_dodge(true)` 关 `monitorable` 才连激光一起躲。
- Notes / 说明: 无敌帧分两档（`script/hurt_box.gd`）：`set_invulnerable(v)` 切 `monitoring`/`contact_invincible`（普通档，挡目标侧检测）；`set_dodge(v)` 在其上再切 `monitorable`（闪避档，连来源侧检测即激光也挡）。**不要**把 `monitorable` 无条件折进普通档——那会让激光也被 i-frame 挡住，破坏「激光无视无敌帧」。新增敌人攻击时按「由谁检测」决定归属：目标 HurtBox 监听的走普通档规则，来源自查询的（`get_overlapping_areas`）走 `monitorable`。同构应用到召唤物：跳跃=`set_dodge`，受击 `invincibility_frames`=`set_invulnerable`，还原由 `HurtAnim` 的 `.:monitoring`/`.:contact_invincible` 轨道负责。
- Source / 来源: user
- Date / 日期: 2026-09-28
- SUPERSEDED: 2026-10-21 玩家侧不再按「检测发起方」自动决定：普通爆炸/接触也吃普通无敌帧，激光改为在 `DamageData.flags` 显式打 `GameTags.IGNORE_IFRAME`；详见下一条。召唤物仍沿用本条 Area2D 检测层语义。

### [Combat] 玩家受击统一无敌帧门控（2026-10-21）
- Evidence / 证据: `script/game_tags.gd:42` 新增 `IGNORE_IFRAME`；`script/player_health_component.gd:44-60` `_is_iframe_blocked()`、`:65-83` 早退分支、`:111-116` 门控与同步 `contact_invincible`；`scenes/bullet/laser_bullet.gd:76-85` 给激光 `DamageData.flags` 打标记；`script/hurt_box.gd:30-37` 普通档/闪避档、`:90-105` 接触探针。实机 `game_eval`（FakePlayer + Stats + HurtBox）结果 `[990.0, 990.0, 980.0, 980.0, true]`（同帧两爆炸只扣一次、IGNORE_IFRAME 穿透普通档、闪避挡 IGNORE_IFRAME）与 `[false, true, 87.0]`（DOT 后不置 contact，普通命中后置 true）；`tests/test_player_iframe_gate.gd` 7/7 通过。
- Notes / 说明: 非治疗正伤害在 `hurt_invalid` 之前统一过门控：`hurt_box.monitorable=false`（跳跃/闪避）优先拦截；`IGNORE_IFRAME` 放行普通档；其余按 `hurt_box.contact_invincible` 拦。非 DOT 放行时**同步**置 `contact_invincible=true`，同一物理帧后续接触/爆炸立即被挡；DOT 不置（DOT 只 `start()` 计时器、不调 `_on_invincible_frame()`，置了会永久残留）；被挡时重置 `damage_multiplier`。不要改回查 `invincible_frame.time_left`：DOT 分支会启动计时器但不走 `_on_invincible_frame()`，因此必须看 `contact_invincible`。`HurtBox.set_invulnerable()` 仍用 deferred 切 `monitoring`，避免 Area2D 信号锁内改状态。DOT、治疗、0 伤害击退、友军、倒地、作弊 `is_invincible` 保持原语义。召唤物未接此门控。
- Source / 来源: user
- Date / 日期: 2026-10-21

### [Physics] `Area2D.monitorable=false` 能挡「新建立」的重叠，但**不清除既有重叠**（Rapier2D）
- Evidence / 证据: `game_eval`（mobu 场景）：目标 HurtBox `monitorable` 置 false 前建立的重叠，观察 6 个物理帧后 `probe.get_overlapping_areas().has(hb)` 仍为 `true`；反过来，在 `monitorable=false` 状态下**先**建好 probe 再等帧，则 `count=0`（不建立）；恢复 true 后 `count=1`。
- Notes / 说明: 来源侧检测（`get_overlapping_areas()`）的「无视无敌帧」拦截只在**进入时**生效：跳跃/`set_dodge` 若在已与激光重叠后才切换 monitorable，Rapier 的既有重叠会残留、激光仍能打到（该次）。玩家跳跃亦同此边界。`monitorable` 变化不触发物理对重算；需要即时生效时应配合形状启停（`CollisionShape2D.disabled`）或让来源每帧重建重叠查询（激光因光束形状每轮启停，通常不受影响）。
- Source / 来源: test
- Date / 日期: 2026-09-28

### [Curve] Godot `Curve` 超域不外推；无尽里要续涨必须在 x>1 补点（末点切线按需设定）
- Evidence / 证据: 引擎 `scene/resources/curve.cpp`（`Curve::get_index` 对 `p_offset > 末点.x` 返回末点下标；`Curve::sample` 命中末点即返回其 y → 硬钳制，不 extrapolate）；`scenes/manager/enemy_manager.tscn` 中 `endless_mult`、`hp_growth_curve`、`endless_damage_curve` 均由 x∈[0,1] 扩到 `x=1000` 并追加远点；`game_eval` 验证 `endless_damage_curve.sample(1.0)=1.0`、`sample(2.0)=2.0`、`sample(8.0)=8.0`（线性续涨），`hp_growth_curve.sample(1.0)=2.0`。
- Notes / 说明: ① `Curve.sample()`（走原始点，非 baked）在末点之外**返回末点 y**、不会沿趋势外推；只把 `max_domain` 调大而不加点无效（`get_index` 依据末点 x）。② **哪些曲线在无尽能这样延**：`endless_mult`、`hp_growth_curve` 的 X 无代码 clamp；`endless_damage_curve` 的 X 原本在 `scenes/manager/enemy_manager.gd:100` 被 `clamp(...,0,1)`，2026-09-28 已去掉该 clamp（改 `xd = endless_round / endless_damage_rounds`）并延长曲线。而 `round_hp_curve`/`round_boss_hp_curve`/`round_damage_curve` 的 X 在 `script/enemies_spawn.gd:49,55` **仍**被显式 `clamp(...,0,1)`，**永远采不到 x>1**，给它们加远点也是死数据。③ 加点要点：`_limits` 的 `max_value`/`max_domain` 先调够大（否则加点被 clamp 回旧域）；新段形状由两端切线决定（两端切线=段斜率 ⇒ 该段严格线性；起点切线保持=末点旧切线即无缝衔接）。当前切线/端点值由用户在编辑器微调，**不要硬编码进文档/代码**。④ 语义提醒：`hp_growth_curve` 的采样结果是**指数**（`pow(max(1,level_hp), hp_growth)`），续涨会使 `level_hp>1` 的难度呈超指数增长、很快触及 `EnemyStats` 的 int64 上限；普通难度 `max(1,0.8)=1` 不受指数项影响。
- Source / 来源: test
- Date / 日期: 2026-09-28

### [Bullet] `PlayerBullet` 命中后的判定形状关闭挂在 0.1s `global_time_count` 上 → 穿透弹整段穿过敌人不结算
- Evidence / 证据: 原 `script/player_bullet.gd` 的 `close_shape()` 连 `GameEvents.global_time_count`（`ui/round_timer.tscn:465-466`，`GlobalTimer.wait_time=0.1`）→ `time_count()` 才重开 `collision_shape_2d`；命中结算 `apply_penetrate_dealt`（`:70-87`）在敌人 `health_component` 的 `on_damage_dealt` 内调用。已改为按**物理帧**计数（`hit_shape_cd_frames`，默认 1，`script/player_bullet.gd:29-31,149-153,200-211`、`scenes/bullet/normal_bullet.gd:9-11,128-132,176-187`）。
- Notes / 说明: 每次命中后子弹 `CollisionShape2D` 被关掉近一个 tick（≈ speed×0.05~0.1），在极快/高穿透的 Aris（`bullet_speed=1200`、PS T1 最高 +8 穿透，`scenes/player/aris/aris_ps.gd:42`）上表现为 120px 内敌人全部被跳过、不掉血；基础穿透=1 的角色第一发即回收，故几乎只有 Aris 明显中招。修法把冷却降到物理帧、并加 `_shape_gen` 作废「命中后回池、同帧复用」残留的延迟关闭（原 `set_deferred` 关/直接赋值开存在竞态）。**`normal_bullet.gd`（`SummonedBullet`）已同批改为同一套**；`scenes/bullet/mashiro_sniper_bullet.gd` 也有 `close_shape`/`time_count`，但**其 `close_shape()` 全项目无调用者（死代码）**，命中靠 `add_damage_data` 每 0.1s tick 对 `enemy_group` 结算，故未改。禁用窗口越短越不跳敌、但大体积敌人有被二次命中风险，可调 `hit_shape_cd_frames`（0=不关闭）。
- Source / 来源: user + code
- Date / 日期: 2026-09-28

- SUPERSEDED: 2026-10-04 命中冷却方案被「按目标冷却」取代（来源：user）。「命中后整体关 `CollisionShape2D` + `hit_shape_cd_frames`」无法区分同一敌人/另一个敌人，关形状那一帧必然漏敌（Aris 高速穿透根因）。现由 `HitBox.manages_own_hits` + `rehit_interval_seconds`（秒，默认 0.1）自检 HurtBox、形状常开实现「不漏敌 + 低速多段」。详见文末 2026-10-04 条目。

### [Bullet] 玩家直击子弹必须在 `player_hitbox`(16) 或 `summoned_hitbox`(18) 层，敌 HurtBox 才检测得到
- Evidence / 证据: 全部敌/Boss `HurtBox.collision_mask = 163840`（图层 16+18，`scenes/enemies/sweeper.tscn:242` 等 20 处）；`script/player_bullet.gd` 子弹的标准配置是 `collision_layer = 32772`（16+3，`scenes/bullet/momoi_bullet.tscn:26` 等）。`scenes/bullet/aris_bullet.tscn` 原为 `collision_layer = 4`（只有第3层 `bullet`），2026-09-28 改为 `32772`。
- Notes / 说明: Aris 此前**仍能命中**——子弹自身 `collision_mask = 16384`（`enemy_hurtbox`=15）与敌 HurtBox 的 layer 15 构成重叠对，物理后端仍会向敌 HurtBox 派发 `area_entered`，故第16层在 Rapier2D 下并非硬性前提（但与同脚本其它子弹不一致，属隐患）。**新增玩家直击子弹照抄 `32772`**；召唤物/支援子弹用 `131072`（18，如 `normal_bullet.tscn`、`kei_bullet.tscn`）；迫击炮弹（`yuzu_bullet`/`hibiki_bullet`，4096）靠落点 `ExplosionDamage` 的 source-side 检测（`script/explosion_damage.gd:125-131`，mask 288768 含 15）结算，层号无需 16。死代码不删史：本次仅修 aris_bullet。
- Source / 来源: user + code
- Date / 日期: 2026-09-28

### [UI] option 菜单移动端触摸：`PanelContainer` 走手写分支，`OptionButton` 用 STOP 覆盖层拦截
- Evidence / 证据: `script/game_option.gd`（`resolutions_block.mouse_filter` 按 `OS.has_feature("mobile")` 切 STOP/IGNORE、`_show_mobile_notice`、`_on_resolutions_touch_block_gui_input`、`mouse_selected_full_screen`/`mouse_selected_vs` 的移动端触摸分支）、`ui/game_option.tscn`（`ResolutionsTouchBlock` 与 `Resolutions` 同矩形 `(400,64)-(536,84)`、树序后置）、`ui/mobile_notice.tscn`/`ui/mobile_notice.gd`（节点现挂在 `game_option.tscn` 内）
- Notes / 说明: 承接 4.7 `BaseButton` 原生处理 `InputEventScreenTouch`（见本文件 2026-09-28 条目）。option 内三个桌面专用项需「移动端触摸无效并弹提示」：`FullScreen`/`V-Sync` 是 `PanelContainer`（非 BaseButton），在其 `gui_input` 回调的 `OS.has_feature("mobile")` 分支里检测 `InputEventScreenTouch` 后弹提示；`Resolutions` 是 `OptionButton`，触摸会原生弹出下拉且**无法用 `gui_input` 信号取消**，故在其上覆盖一个同矩形、树序后置的 `Control`（`mouse_filter=STOP`，桌面端在 `_ready` 置 `IGNORE`）拦截触摸，下拉不再弹出。提示框 `ui/mobile_notice.tscn` = `PanelContainer`+`Label`（继承全局 `fonts/theme.tres`），`process_mode=ALWAYS`（暂停菜单下也能播），`notice()` 淡入 0.12s → 停留 3s → 淡出 0.3s，并按 `get_viewport_rect()` 底部居中；文案 key `option_mobile_only_notice` 交给 `Label` 自动翻译（`ETN_localization.csv`）。
- Source / 来源: code + user
- Date / 日期: 2026-09-28

### [UI] 支援升级按钮：花费封顶 + 悬停激活/2s 收回 + 全屏 `ClickCatcher`（滑条区仅拖动）
- Evidence / 证据: `script/support_data.gd`（`const EXP_PER_PYROXENE := 200`、`get_upgrade_max_stones()`）、`ui/support_ui/upgrade_button.gd`（`get_player_pyroxenes()` 取 `min`、`add_support_upgrade()` 再 `min`、`RETRACT_DELAY := 2.0`、`_create_click_catcher()`/`_fit_click_catcher()`/`_on_click_catcher_gui_input()`）、`ui/support_ui/upgrade_button.tscn`（`CloseTimer.wait_time = 2.0`，实例于 `ui/shop_menu.tscn:3150`）
- Notes / 说明: ① **花费封顶**：满级所需青辉石 = `ceil((SupportData.max_exp - SupportData.now_exp)/200)`（`max_exp` 由 `count_max_exp()` 按 `exp_curve` 累加 1..99，对应 `max_lv=100`，见 `docs/SYSTEMS.md` §5.6）；滑条上限取 `min(持有, 所需)`，确认时再 `min` 一次只花到上限，避免越过满级浪费。② **交互**：鼠标悬停即展开（`mouse_entered → open_menu`），移出启动 2s `CloseTimer`（重入取消、超时 `close_menu`）；`HSlider` 保持 `mouse_filter=STOP`（其区域只拖动、点按不生效），面板其余区域点按生效。③ **点别处收回**：激活时在按钮父节点（`lv_up`）下 `Control.new()` 创建全屏透明 `ClickCatcher`（`STOP`、`move_child(…,0)` 置于按钮之前 → 命中在按钮下方），点它 `accept_event()` + `close_menu()`（因此点别处**只收回、不触发其它 UI**）。④ 坑：`_ready` 里父节点仍在 setup，`add_child` 必须 `call_deferred`（否则报 "Parent node is busy setting up children"，`move_child` 随之失败）；`ClickCatcher` 用 `get_parent().get_global_transform_with_canvas().affine_inverse()` 把视口四角换算成本地矩形铺满（`var inv: Transform2D = …` 显式标注，`:=` 推断会报 "Cannot infer the type of inv"）。⑤ `Label` 默认 `mouse_filter=2`(Ignore) 不挡点击，**`HSlider` 才是原先「挡住识别」的元凶**。⑥ 已知边界：`ClickCatcher` 在树上早于 `Node2D/Node2D`（角色立绘带/`ChangeShop`），点那一块不收回。
- Source / 来源: code + user
- Date / 日期: 2026-09-28

### [UI] 支援升级满级经验口径不一致：`max_exp` 逐项截断 vs 升级阈值浮点累加 → 99→100 卡死
- Evidence / 证据: `script/support_data.gd:75-90`（`_total_exp_to_lv` / `count_max_exp` / `get_upgrade_max_stones`）、`script/support_data.gd:168-177`（`count_exp`）
- Notes / 说明: 旧实现里 `max_exp: int` 用 `+=` 把曲线值逐项截断成整数累加，而 `count_exp()` 内的 `var last_exp = 0` **未标注类型**（GDScript 里 `=` 不推断类型，是 Variant）按 float 累加，`next_exp`/`now_count_exp` 又是 `int`——导致真实升级阈值比商店封顶的 `max_exp` 多出「所有小数部分之和」。本机 `max_lv=100`：真实阈值 350647、旧 `max_exp` 350596，**差 51 exp（< 1 青辉石 200）**；玩家到 99 级后 `now_exp` 追平旧 `max_exp`，`get_upgrade_max_stones()` 算得 `remaining<=0` 返回 0，`ui/support_ui/upgrade_button.gd:71` 的 `h_slider.max_value=0` 锁死滑条、`check_upgrade()` 永不触发，表现为「99 级差最后一点经验无法升级」。修法：新增 `_total_exp_to_lv(lv)` 统一口径（float 累加后 `round`），`count_max_exp()` 取 `_total_exp_to_lv(100)`，`count_exp()` 取 `last_exp = _total_exp_to_lv(now_lv)`、`next_exp = _total_exp_to_lv(now_lv+1) - last_exp`（`last_exp` 显式 `: int`）；`get_upgrade_max_stones()` 在 `now_lv < max_lv` 且 `remaining<=0` 时兜底返回 1，旧存档可买 1 颗自愈。验证（`game_eval`）：`max_exp == _total_exp_to_lv(100) == 350647`、旧整型累加 `350596`、LV99 `stones == 1`、买 1 颗后 `now_exp >= 350647`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-01

### [Bullet] 玩家蓄力激光改「场景预置 BeamHitBox + 边沿事件」，消除运行期 Area2D 增删与逐 tick `get_overlapping_areas()`
- Evidence / 证据: `scenes/bullet/player_laser_beam.gd`（`_setup_segments`/`_update_segments`/`_on_beam_area_entered`/`_seed_contacts`/`_apply_damage`/`_build_beam_points_tracking`/`_wall_ray`/`_exit_tree`）、`scenes/bullet/player_laser_beam.tscn`（`BeamHitBox` + `Seg0..Seg9`）
- Notes / 说明: 旧实现每物理帧按有效目标数 `_ensure_segments` 增删运行期 `Area2D`，并以每 0.1s × 每段 `get_overlapping_areas()` 结算（Rapier2D 下昂贵且会残留，`LEARNINGS` 321/457）。改为场景预置 `Area2D`（`monitorable=false`）+ N 个 `CollisionShape2D`：段数由子节点推导并逐个 `duplicate` 形状（PackedScene 子资源默认跨实例共享）；`area_entered/exited` 维护 `_contacts`；`_time_count` 遍历集合发 `hit_received`；超折线点数的段退化到端点并 `disabled`（不 `queue_free`）；`active_state()` 做一次种子查询；`_apply_damage` 过滤 `is_instance_valid`/`monitorable`。另加 `is_finite` 守卫，防 NaN/∞ 进入 `PhysicsRayQueryParameters2D`/`RectangleShape2D.size` 触发 Rapier panic（见 `LEARNINGS` 302-306）。`game_eval` 验证：`segment_count=10`/`_seg_shapes=10`/形状个体 ID 唯一/初始全 disabled；lag 折线用满 10 段；短折线 2 段启用、8 段 disabled；含 INF 点全段 disabled 不报错；`area_entered` 门控在 `is_idle` 下忽略、非 HurtBox 忽略。
- Source / 来源: user + code + test
- Date / 日期: 2026-09-29

### [Bullet] 蓄力激光闪退加固：transform 级 finite 守卫 + `is_instance_valid(laser)` + `_last_hit_time` 清理
- Evidence / 证据: `scenes/bullet/player_laser_beam.gd`（`follow` 入口 `/` 校验 `muzzle_global.is_finite()`/`is_finite(aim_angle)`；`_build_beam_points_lag` 目标坐标 finite + `p` finite 否则 break + `segment_count<=0` 提前返回）、`scenes/weapon/Supernova_Abi_Eshuhs_Sword_of_Light/charge_laser_gun.gd:114-157`（`laser` 统一 `is_instance_valid`）、`scenes/player/aris_armed/aris_armed_ps.gd:_reset_energy_buff`（`_last_hit_time.clear()`，`:35` 连 `round_end`）
- Notes / 说明: 上一轮只对「形状尺寸 / 墙体射线」做 finite 守卫，漏了**激光自身 transform**——`BeamHitBox` 是激光子节点，激光 `global_rotation/position` 为 NaN 时其全局 transform 仍会把 NaN 送进 Rapier，形状级守卫覆盖不到；`aim_angle` 来自 `charge_laser_gun._update_aim` 的 `global_position.direction_to(crosshair_pos).angle()`，故 `follow()` 入口必须校验输入。lag 路径此前未过滤目标坐标（tracking 已过滤），已对齐。`charge_laser_gun` 原先只判 `laser == null`，改为 `is_instance_valid` 防已释放引用。`_last_hit_time` 以敌人 `instance_id` 为 key 只增不减，改为回合结束清理。`game_eval` 验证：含 INF 目标的 lag 折线 11 点全有限；tracking 含 INF 目标回退为 2 点全有限；`follow(NAN)`/`follow(INF)` 不污染 `global_position`。
- Source / 来源: user + code + test
- Date / 日期: 2026-09-29

### [Enemy] 策反敌人索敌改用 `Targeting` 帧缓存 + `get_target()` 帧节流 + 无目标待机
- Evidence / 证据: `script/entity_ENEMY.gd`（`get_target`/`_select_target`/`is_standby`/`get_nearest_enemy`/`active_state/idle_state` 缓存重置）、`scenes/enemies/automaton.gd`、`scenes/enemies/tester_automaton_shield.gd`、`scenes/enemies/enemy_tank.gd`（`rand_target_position` 限次）、`scenes/enemies/sandbag.gd`/`sweeper.gd`、`script/targeting.gd`
- Notes / 说明: **卡顿根因**——策反敌人在 `get_target()` 走 `get_nearest_enemy()`，原实现用 `get_tree().get_nodes_in_group("Enemy")` 全组扫描（含池化 `is_idle`、`EnemyPart`），且 `automaton`/`tester_automaton_shield`/`enemy_tank` 在 `tick_physics`（每帧）里多处调用 `get_target()`/`get_target_position()`，晚期大量策反（上限 base10 + ako 3×10）叠加使开销 O(策反数 × 全组 × 帧率)。修法：① `get_nearest_enemy()` 贴脸 `enemy_body` 优先、否则 `Targeting.nearest_enemy()`（按物理帧缓存、只取 `PoolManager` 活跃敌人、天然排除 `is_idle`/`EnemyPart`/`PLAYER_SIDE`）；② `get_target()` 按物理帧节流缓存（`TARGET_CACHE_FRAMES≈0.1s`，**null 也缓存**，否则无目标时每帧重扫），`get_target_position()` 读缓存节点但位置实时 → 未策反瞄准不降精度；③ **无目标待机**：`is_standby()`（策反且无目标）时 `automaton`/`tester_automaton_shield`/`enemy_tank` 停止移动、炮塔/枪/头不转向、`shoot_bullet` 直接返回；`sweeper` 基类方向已 ZERO、`sandbag.get_direction_to_player` 加 guard。`enemy_tank.rand_target_position` 同时改为有限次尝试（防越界/长循环）。注意 `tester_automaton_shield.time_count` **不调 `super`**，故节流做在 `get_target()` 调用点而非 `time_count`。`game_eval` 验证：新增 `a`（ENEMY）与 `b`（PLAYER_SIDE）后 `b.get_target()==a` 且 `b.is_standby()==false`；`a` 移除后 `b.get_target()==null`、`b.is_standby()==true`。
- Source / 来源: user + code + test
- Date / 日期: 2026-09-29

### [UI/Perf] 立绘大图未压缩 + 菜单常驻 → 移动端显存爆 → 单张 Sprite 局部/整张串角色；改为按需加载
- Evidence / 证据: 修复前 `ui/shop_menu.gd:45-46`（`_ready` 即 `add_charavter_card/add_item_card`）、`ui/shop_menu.tscn`（`shop_card_group`×18 + `shop_item_group`×12 导出数组）、`ui/ark_of_Shittim/arona.gd:_ready → get_now_clothes`；全部立绘 `compress/mode=0`；新增 `script/lazy_texture.gd`、`ui/shop_menu.gd:_process/_lazy_scroll/_on_shop_closed`、`ui/support_shop.gd:_process/_on_shop_open/_on_shop_closed`、`ui/character_shop_card.gd`/`ui/support_ui/support_shop_card.gd`/`ui/menu_box_button.gd` 的 `reveal/conceal`。
- Notes / 说明: **现象**：移动端部分玩家商店/选角立绘**单张 Sprite 内一部分是另一个角色**（不是整块错、不是资源引用错——已逐字节核对磁盘与 APK `.ctex` 一致、无重复 UID、`ext_resource` uid↔path 全一致）。**根因**：立绘按 Lossless 导入，运行时未压缩 RGBA8；`ui/ark_of_Shittim/*_picture.png` 2400×4800 ≈ 44MB、玩家/支援立绘 ≈ 11MB；`shop_menu.tscn` 被 `menu_screen.tscn` 静态实例，导出数组一次性引用全部 → 主菜单即载入 ~850MB → 低配移动端显存不足 → 纹理被驱逐/上传不完整 → 残留上一张不同角色的纹理（Arona/Plana），呈现为“局部/整张串图”。**修法**：① 大图字段从 `Texture2D` 改为 `@export_file` **路径**（`.tres` 迁移，加载资源不再带大图）；② `LazyTexture.load_uncached` 用 `CACHE_MODE_IGNORE` 载入、丢引用即释放；③ 列表**滚动懒加载**（`reveal/conceal` 按 `ScrollContainer` 可见矩形 + 余量）；④ `shop_menu` 打开才载店主/卡片、关闭释放；⑤ **清空场景内嵌的默认大图**（`<char>_card.tscn`×21 及若干 UI 场景），否则实例化即载入并显示错误默认图。⚠️ 以后新增商店/卡片 UI 勿内嵌大立绘 `texture`；大图一律走 `sprite_path` + `LazyTexture`。`game_eval` 验证：菜单加载角色卡大图 0 张、`arona.sprite.texture==null`；`emit_shop_open()` 后仅可见 9/18 载入；`_on_shop_closed()` 后归 0、支援列表同理（3→0）。
- Source / 来源: user + code + test
- Date / 日期: 2026-09-29

### [UI/Perf] 懒加载 `reveal()` 每帧调 `load_uncached` → 每帧重解码大图 → 卡顿；须幂等 + 引用计数 + 滚动门控
- Evidence / 证据: `ui/shop_menu.gd:_lazy_scroll`/`ui/support_shop.gd:_process`/`ui/menu_box_character.gd:_process` 每帧调 `card.reveal()`；修复前 `ui/character_shop_card.gd` 等 `reveal()` = `LazyTexture.load_uncached(path)`（`CACHE_MODE_IGNORE`）；`ui/scoreboard.tscn` 根为默认 `visible=true` 的 `Control` → `menu_box_character._process` 在主菜单常驻。修复见 `script/lazy_texture.gd`（`acquire/release` 引用计数缓存）、各卡 `_revealed_path` 幂等、`_lazy_force`/滚动门控、`menu_box_character` 用 `MenuBox.is_open`。
- Notes / 说明: `ResourceLoader.CACHE_MODE_IGNORE` **不缓存**，每次调用都重新解码 `.ctex`。懒加载/滚动列表**绝不能每帧调 reveal**；`reveal()` 必须幂等（记录已加载路径，同路径直接返回），并用 `acquire/release` 让同路径只解码一次、离开时真正释放。进阶：`_process` 仅在滚动值变化或刚打开的前几帧重算，并依 UI 真实展开状态（`is_open`/`visible`）门控，别假设子节点默认不可见。`game_eval` 验证：菜单加载缓存 0；`emit_shop_open()+_process` 后缓存 11（9 可见角色 + 2 店主）；重复 `reveal()` 返回同一纹理实例（幂等）；`_on_shop_closed()` 后缓存/加载归 0。
- Source / 来源: user + code + test
- Date / 日期: 2026-09-29

### [Map] 越界回位须以物理墙 `FloorWall` 内壁为界；`SpawnMap` used cells 凸包偏小会误拉贴墙单位
- Evidence / 证据: `script/map_bounds.gd`（autoload `MapBounds`）；`scenes/manager/summoned_manager.tscn:13-15`（菱形竞技场 Area2D，中心 (704,448)）；运行期射线（`PhysicsRayQueryParameters2D`，mask 256）实测可走范围 center (704,448)，x∈[-160,1568] / y∈[16,880]（即 x±864 / y±432）；`SpawnMap`（组 `"Map"`）used cells 凸包仅 x±768 / y±384；`scenes/main/main.tscn:87-92`（`FloorWall` TileSet `physics_layer_0/collision_layer=256`；玩家 `scenes/player/momoi/momoi.tscn:261 collision_mask=256`，256 层全项目仅 `FloorWall` 使用）。
- Notes / 说明: 玩家/敌人/召唤物被击退或穿墙甩出地图时由 `MapBounds` 每 1s（10×`global_time_count`）拉回。边界**不可取自 `SpawnMap` 凸包**——它比物理墙内壁小约 96px（贴墙的正常单位会被误拉回），必须取玩家实际会碰撞的 `FloorWall`（层 256）内壁：从地图中心（组 `CenterPosition`=BattleRoom）向 ±x/±y 射线，命中点构成菱形可行走边界（4 条全命中才用，否则回退 `SpawnMap` 凸包）。召唤物来源用组 `"Summoned"`（含 kei/utaha_turret/mobu，覆盖支援 kei 登场召唤物）并**跳过 `is_idle==1`**（`script/summoned.gd:24-30` 闲置坐标 `(10000,-10000)`）；敌人用 `PoolManager.get_active_enemies()`。`game_eval` 验证：出界敌人 (2500,1500) 1s 后回到 (1493,463) 且在内；`_is_out((1540,448))==false`（贴墙内不误判）、`_is_out((1600,448))==true`。
- 回位落点必须**按实体本体碰撞半径内缩边界**，否则大体型会被墙挤穿（用户实测 Boss goliath 被挤出）：`_body_radius()` 只取实体**直接子节点**的 `CollisionShape2D`/`CollisionPolygon2D` 外接半径最大值（goliath 本体 `CircleShape2D radius=23`；玩家 `radius=7`；sandbag `12`），**不要**用 `entity.collision_shape_2d` 属性——玩家该属性指向 `PickBox`（`CircleShape2D radius=35`）会过度内缩；再用 `Geometry2D.offset_polygon(_hull, -radius, JOIN_MITER)`（4px 分桶缓存）得内缩多边形，取其上最近点再内推 `INSET=8px`、清 `velocity`，静默无冷却。验证：goliath (2600,1500)→(1499,462) 且 3s 内稳定不反弹；玩家 (radius 7)→(-133.7,448.8)；sandbag (radius 12)→(713.7,818.9)。
- 2026-10-01 修正：**触发判定与体型解耦**。原实现 `_is_out(pos, radius)` 也用半径内缩多边形判定，导致「贴着墙」（玩家圆心距墙仅 7px，而内缩边界 16px）被判出界、沿墙走反复被传送；Boss 更严重（内缩 31px）。现 `_is_out(pos)` 只用真实边界 `_hull` **外扩 `OUT_MARGIN=24px`**（`_outer_hull`，`Geometry2D.offset_polygon(_hull, +24, JOIN_MITER)`）判定——圆心须越墙 ≥24px 才触发；`radius` 仅用于**落点**内缩。`offset_polygon` 正 delta 在尖角（底/顶顶点约 53°）触发 miter 限值→bevel，实测底/顶顶点外扩约 26.8px、左右顶点 24px，均≥24。`game_eval` 验证（底墙 y=880）：`_is_out((704,875/890/900/905))=false`、`_is_out((704,920))=true`；`nearest_inside((704,1200),0)=(704,872)`、`nearest_inside((704,1200),23)=(704,845.17)`（半径 23 + INSET 8，离墙 34.8px，Boss 不再被挤穿）。**教训：触发阈值与落点安全边距是两个独立诉求，不能共用一个多边形。**
- Source / 来源: code + test + user
- Date / 日期: 2026-09-29（2026-10-01 更新触发策略）

### [Combat] `area_entered/exited` 回调解引用 `.owner` 前必须 `is_instance_valid`（钻头 exit 悬空引用闪退）
- Evidence / 证据: `scenes/player/kasumi/kasumi_drill.gd`（`Area2D2.collision_mask=286720` = `summoned_box`(14)+`enemy_hurtbox`(15)+`prop_hurtbox`(19)，`_on_hit_box_exited` 原为 `if hurtbox is HurtBox and body_group.has(hurtbox) and !hurtbox.owner.is_in_group("Summoned")`）；对照安全实现 `scenes/debuff/fire_field.gd:109-111`、`scenes/enemies/enemy_fire_field.gd:113-114`（exit 不碰 `.owner`）、`script/enemy_part.gd:136-137`（取 owner 前 `is_instance_valid`）；同类被释放来源 `scenes/main/main.gd:69-76 enemy_clear_unit()`（回合结束/升级对所有 Enemy `queue_free()`）、`oil_barrel.gd:27`、召唤物死亡。
- Notes / 说明: 钻头 `body_group` 会收集敌人/召唤物（`mobu` 的 HurtBox group `SummonedBox`）/道具的 `HurtBox`；这些单位在钻头仍重叠时被释放（回合清场、召唤物死亡、油桶击毁）后，`area_exited` 可能带着**已释放**的 `hurtbox`（或 `owner`）进回调，`hurtbox.owner` 即 use-after-free → 访问冲突 `0xC0000005`。此前的 `cd28f9f` 只给 `add_damage_data` 的 emit 循环加了 `is_instance_valid`，漏了 exit 回调。修法：回调开头先 `hurtbox == null or not is_instance_valid(hurtbox)` 提前返回，再 `is HurtBox`/`has()`，取 `owner` 前再 `owner != null and is_instance_valid(owner)`。同批一并加固所有「集合循环内 `is_instance_valid(i)` 之后才解引用 `i.owner.*`」的点：`script/fire_damage.gd`（`:60` 后 buff）、`scenes/debuff/fire_field.gd:91`（百分比伤害 + buff）、`scenes/update_item/kitchen_knife.gd:90`（斩杀线）、`scenes/update_item/renge_fire_field.gd:87`、`scenes/enemies/enemy_fire_field.gd:79`（`add_fire_dot`）、`scenes/player/utaha/melee.gd:53`（`upgrade_summoned` 的 `sort_group[0].owner`）；并给上述脚本及钻头的 `area_entered/exited` 回调统一加 `is_instance_valid` 前导守卫。注：`i.owner` 通常随 `i` 一起释放，属纵深防御；但 emit 可能在同一循环内释放 owner（如 `fire_field.gd` 的 `i.hit_received.emit` 后再取 `i.owner.enemy_buff_manager`），故 owner 相关访问应尽量放在 emit 之前或 emit 后重新校验。通用规则：凡是 `area_entered`/`area_exited`/`body_*` 回调里取 `.owner`，或把对象存进集合并在之后复用，都要先做有效性判断（`Faction.of_entity`、`is_in_group` 用到的 `owner` 尤甚）。
- Source / 来源: code + user
- Date / 日期: 2026-09-30

### [UI] 固定宽度本地化 Label 需挂 `auto_text`；新增 `wrap_fallback_below` 实现「单行优先、过小才换行」
- Evidence / 证据: `script/auto_text.gd:9-10`（`wrap_fallback_below` 导出）、`:64-66`（`wrap_fallback_below>0` 时按 `_need_wrap` 选换行）、`:76-83`（`_need_wrap`：单行能放到不低于阈值就用单行，否则换行）、`:85-91`（`_apply_autowrap`，`_setting_autowrap` 防 `minimum_size_changed` 重入）；`ui/ark_of_Shittim/shop_tag_button.tscn:5,140-161`（Label 挂 `auto_text`，`base_size_x=60`/`base_size_y=31`/`min_font_size=7`/`wrap_fallback_below=10`，矩形扩为 `4,2..64,33`）；同期适配 `ui/shop_menu.tscn`（`support_pa` Label2，扩宽到 110）、`ui/game_option.tscn`（14 个文字 Label，`sounds_sfx` 左扩到 89）、`ui/scoreboard.tscn`（`scoreboard_name` + `normal_sort/character_sort/gamemode_sort`）、`ui/menu_box.tscn`（`select_name`）。
- Notes / 说明: ① 越南语普遍比中/英长，窄矩形 Label（商店页切换 `button_character`=`Mở khóa nhân vật`、`button_clothes`=`Trang phục`、`support_pa`=`Hào quang hỗ trợ`、`sounds_sfx`=`Hiệu ứng âm thanh`）会溢出；凡「显示翻译键 + 固定宽度/clip」的 Label 都要挂 `auto_text` 并给固定预算（`base_size_x/y` 或 `box`），否则不缩放（见本文件 2026-09-25 条目）。② 新字段语义：`wrap_fallback_below > 0` = 先按单行量，单行所需字号 ≥ 该值就单行渲染；只有单行必须缩到该值以下才启用 `AUTOWRAP_WORD_SMART`。默认 `0` 保持旧行为，既有 `auto_text` 场景不受影响。阈值取可读下限附近（本次 10），`min_font_size` 为硬下限。③ `auto_text` 基类为 `Label`，**Button 自带文字无法直接挂**；`ui/player_id_input.tscn` 的 `button_confirm/cancel`、`ui/open_save_file.tscn` 是 Button，本次未改（如需适配按 `menu_screen` 的 `credits_button` 模式加全铺满子 Label）。④ `label.text` 由父脚本（`shop_tag_button.gd:14`、`menu_box.gd:25`）在 `_ready` 后写入时，靠 `minimum_size_changed` 触发重排，`atr(text)` 取译文测量。
- Source / 来源: code
- Date / 日期: 2026-09-30

### [UI/Font] 越南语字体：像素字缺预组合字形 + Godot 只逐字形回退 → 运行时仅替换「本地化文本」节点
- Evidence / 证据: 像素字体 cmap 实测（`fonts/BoutiqueBitmap9x9_1.9.ttf`/`7x7_1.7`/`9x9_Bold_1.9`）含 `a/n/đ/Đ/ă` 与 CJK，**缺** `ơ ư ộ ữ ế ạ ồ`；`RobotoCondensed-Light/Bold` 越南语字形齐全。项目现状：`project.godot` `theme/custom="res://fonts/theme.tres"`（`default_font=BoutiqueBitmap9x9_Bold_1.9`）；显式字体 override `theme_override_fonts/font` **231 处** + `normal_font` 1 处（67 场景），仅引用 3 个像素字体。修复：`script/locale_font.gd`（autoload `LocaleFont`）。`game_eval` 验证：vi 下「键」Label→`RobotoCondensed-Light`、无 override 的键 Label→`RobotoCondensed-Bold`、代码拼装越南语文本→Roboto、纯数字(`12/15`)与英文名(`SAIBA MOMOI`)保持像素；zh 下全部还原。
- Notes / 说明: ① **根因**：像素字只覆盖部分越南语字形，缺失字由 `allow_system_fallback=true` 走 OS 系统字体 → 「像素字 + 系统字」混排。② **不能只加 `Font.fallbacks`**：Godot 回退**逐字形**（源码 `text_server_adv.cpp` `_shape_run` 按 `.notdef` 子串回退、`FontPriorityList` 主字体永远优先），`set_script_support_override("Latn", false)` 也不能让主字体对整段拉丁让位。③ **最终规则（v3）**：只替换「显示本地化文本」的文字控件——`_needs_robo` = 文本是本地化键（`TranslationServer.translate(text) != text`）**或** 含像素字缺失的越南语/拉丁扩展字形（`not pixel.has_char(cp)`，cp 属 `0xC0-0x24F`/`0x300-0x36F`/`0x1E00-0x1EFF`）；覆盖代码拼装译文（`talk_text.gd:8` 的 `tr()`、`ability_shop_item_card.gd` 词条）。数字/符号/硬编码英文/CJK **保持不变**。④ 映射：`9x9`/`7x7`→`RobotoCondensed-Light`（Thin 偏细，弃用）、`9x9_Bold`→`RobotoCondensed-Bold`。⑤ 实现坑：`Control` **没有** `get_theme_font_override`；读 override 用 `has_theme_font_override` + `get_theme_font`（有 override 时返回 override）。⑥ 触发：`_ready`、`SceneTree.node_added`、`minimum_size_changed`（文本后填重判，如初始为空的 `shop_menu.ps/ex_skill`）、`NOTIFICATION_TRANSLATION_CHANGED`（全树重扫）；故 `Game.gd:261`/`langue_button.gd` 无需改动。原状态存节点 meta `_locale_font_orig` 以便精确还原；设置 override 会触发 `minimum_size_changed`，靠 `applied` 幂等标记防重入。⑦ 边界：主题资源内嵌字体（`ui/game_option.tscn` 的 `OptionButton/PopupMenu`、`ui/langue_button.tscn` 的 `PopupMenu`）不在范围。
- SUPERSEDED: 2026-09-30 初版(v2) 曾对**所有** `Control` 的字体 override + 根 `theme` + 节点自带 `theme` 一律换 Roboto（导致数字/HUD/结算页数字也变 Roboto，观感差）；已改为上面的「仅本地化文本」规则(v3)。
- Source / 来源: code + test
- Date / 日期: 2026-09-30

### [UI] 立绘懒加载改造遗漏消费方：`support_select_ui` 列表卡未调 `reveal()` → 支援选择界面全黑
- Evidence / 证据: `ui/support_ui/support_shop_card.gd:27`（`reveal()` 定义，走 `LazyTexture.acquire`）；正确调用点 `ui/support_shop.gd:76`（商店）、`ui/character_shop_card.gd:64`→`ui/shop_menu.gd:227`、`ui/menu_box_button.gd:44`→`ui/menu_box_character.gd:58`；**遗漏** `ui/support_ui/support_select_ui.gd:add_null_card()/add_cards()`（改造前 `support_shop_card.tscn` 内嵌默认立绘，改造清空后未接 `reveal()`，导致列表 NULL/KEI/AYANE/SERINA 只有名字、下方全黑）。修复：`add_null_card()` 与 `add_cards()` 两个循环的 `add_child(ins)` 之后补 `ins.reveal()`（3 处）。`game_eval` 验证：`test_menu` 下 `support_box` 4/4 卡片 `support_sprite.texture != null`。
- Notes / 说明: ① 列表类立绘卡（`character_shop_card` / `support_shop_card` / `menu_box_button` / `player_card`）的立绘由**外部**调用 `reveal()/conceal()`（滚动懒加载由父级 `_process` 驱动，或一次性 `reveal()`）。改造/新增加载器后，必须给**所有消费方**接上——`support_shop_card` 有两个消费方（`support_shop` 商店 / `support_select_ui` 选择界面，后者还含 `character_test_menu` 复用），只接了前者。② `support_select_ui` 列表短、一次全可见，直接 `add_child` 后 `reveal()` 即可；`clear_box()` 释放卡片时 `_exit_tree` 会 `release`，无泄漏。③ 同类问题排查法：列 `LazyTexture` 使用点 + `func reveal/conceal` 定义 + 其调用点 + 所有 `hframes=4` 立绘节点的加载器，逐一确认每个资源路径字段（`PlayerCard.sprite_path` / `CharacterCard.character_sprite_path` / `ClothesCard.sprite_path` / `SupportCard.character_sprite_path`）都有被调用的加载器。
- Source / 来源: code + test
- Date / 日期: 2026-09-30

### [UI/Font] 越南语 Roboto 缺 `♪/♩` 与 CJK → 给 `Font.fallbacks` 挂像素字兜底
- Evidence / 证据: cmap 实测 `fonts/RobotoCondensed-Light.ttf`/`RobotoCondensed-Bold.ttf` **无** `U+2669/U+266A`（`♪/♩`，出现于商店对白 `ETN_shop_localization.csv` 的 `arona_head_1/2` vi 文本），也无 CJK；`BoutiqueBitmap*` 均有。修复 `script/locale_font.gd:_ready`：`ROBOTO_BODY.fallbacks = [PIXEL_9]`、`ROBOTO_BOLD.fallbacks = [PIXEL_BOLD]`。验证：`ROBOTO_BODY.fallbacks.size()==1`，`ROBOTO_BODY.has_char(0x266A)==true`（走 fallback）、`fallbacks[0].has_char(0x266A/0x4E2D)==true`。
- Notes / 说明: ① `Font.fallbacks`（`Array[Font]`）在**逐字形缺字**时生效；vi 下这些符号原本靠 `allow_system_fallback` 走 OS 字体（实机多数正常），挂像素字 fallback 后稳定不依赖系统字体。② 坑：`const ROBOTO_BODY := preload(...)`（常量）**不能**直接 `ROBOTO_BODY.fallbacks = ...`（Parse Error: Cannot assign a new value to a constant）；需先赋给局部变量（`var body_font: FontFile = ROBOTO_BODY`）再设属性。③ 葡语无此问题：其字符全在 Latin-1（`ã õ ç á é…`），像素字全覆盖（实测 pt 列 20 个非 ASCII 字符 20/20 命中），故 `LocaleFont` 只对 `vi_VN` 生效即可。
- Source / 来源: code + test
- Date / 日期: 2026-09-30

### [Buff] `buff_erase_timer` 在 `BuffManagerBase` 架构里 = 秒数（旧独立 buff 里只是开关）
- Evidence / 证据: `scenes/manager/buff_manager_base.gd:226`（`erase_time = value[2] * TICKS_PER_SECOND * _duration_multiplier(buff)`）; 旧实现 `HEAD:scenes/player_buff/debt_buff.gd` 的 `buff_timer.wait_time = 999`（硬编码）
- Notes / 说明: 重构前 debt_buff 是独立 Node，时长硬编码 999s，`buff_erase_timer` 只当「硬币加成开关」用（`>0` 才给）。重构后走 `BuffManagerBase`，`value[2]` 直接决定 erase_time，而 `serika.tscn` 的 `serika_ps` **漏填 `buff_erase_timer`**（默认 0）→ 负债 buff 一个 tick 即过期，T0 属性惩罚不生效、T1 硬币加成仅 1s。修法：场景补 `buff_erase_timer = 999`，并把硬币开关从 `erase_time` 解耦（`_create_entry` 新增 `raw_value`，`debt_component.gd` 读 `raw_value[3]`，Serika 侧用 `coin_gate` 0/1）。**新增/移植走该 manager 的 buff 时必须显式填 `buff_erase_timer`（秒）**，不要沿用旧「开关」语义。
- Source / 来源: code + user
- Date / 日期: 2026-10-01

### [Stats] `@onready` 初始化不经过 setter → `usable_coin` 缓存滞留 0，`min_coin` 形同虚设
- Evidence / 证据: `script/Stats.gd:122-124`（现为只读 getter `usable_coin = coin - min_coin`）; Godot 文档「Properties → When setter/getter is not called」：初始化值（含 `@onready`）**直接写入底层字段，不调 setter**
- Notes / 说明: `@onready var coin = initial_coin` 初始化**直接写底层字段**，`coin` setter 在 `_ready` 阶段一次都不跑；若把 `usable_coin` 当普通缓存字段只在 setter 里更新，则会一直滞留 0（`min_coin` 失效）。Serika `min_coin=-99999` 本应允许 0 金币负债消费，实际 `usable_coin=0 < cost` → `coin_lack`；捡到硬币后 setter 才跑、自愈。修法：`usable_coin` 改为**只读 getter**（按需 `coin - min_coin`），不再依赖 setter 副作用。教训：Godot 里「随属性重算的缓存」不要只放在带 setter 的变量的初始化路径上。
- SUPERSEDED: 2026-10-01 初版结论说「把 `usable_coin = v - min_coin` 移到 setter 提前 return 之前即可」——错，初始化根本不调 setter，移位无效。
- Source / 来源: code + user
- Date / 日期: 2026-10-01

### [Buff] 负债 debuff 的 `ability_mult` 曾从 `global_damage` 移除 → "降低全部属性"不全
- Evidence / 证据: `script/PlayerData.gd:392`（`global_damage = max(0.01, base_global_damage * global_damage_mult * ability_mult)`，重构中被去掉了尾项）; `resources/buff/components/debt_component.gd:14`（`PlayerData.ability_mult = DEBT_VALUE[idx]`）
- Notes / 说明: `debt_component` 靠 `PlayerData.ability_mult` 实现「负债降全部属性」，但重构时 `global_damage` 不再乘 `ability_mult`，导致负债不降全局伤害。已恢复。改动 `_recompute_player_ability()` 时注意哪些派生量吃 `ability_mult` 是**有意**的（Serika 负债惩罚依赖它）。
- Source / 来源: code + user
- Date / 日期: 2026-10-01

### [Buff] 独立 buff→`BuffManagerBase` 重构遗留：`remove_by_layer` 未随旧场景迁移
- Evidence / 证据: 旧场景 `HEAD:scenes/player_buff/aris_buff.tscn`/`hasumi_buff.tscn`/`bullet_damage_mult_1_buff.tscn`/`luck_buff.tscn` 均 `is_remove_by_layer = true`（`retribution_buff.tscn`、`enemy_buff/fire_dot.tscn` 亦 true）；重构后对应 `.tres` 漏填（`resources/buff/buff.gd:8` 默认 false）。已补 `remove_by_layer = true`（`resources/buff/player_buff/{aris_buff,hasumi_buff,bullet_damage_mult_1_buff,luck_buff}.tres`）。
- Notes / 说明: 旧体系里 `_on_buff_timer_timeout` 按 `is_remove_by_layer` 决定「到期掉 1 层 vs 整栈清空」，而 `erase_buff`（consume 路径）对上述 buff 一律整栈清空，二者本就不一致。新体系只有一个 `remove_by_layer` 同时管「到期」和 `consume_event`，无法完全复刻旧行为。取舍：`aris_buff`（`aris_ps.gd:65,69` 每次过热回落 emit 一次，旧掉 1 层）、`hasumi_buff`（无 consume，纯到期掉层）必须 true；`bullet_damage_mult_1_buff`（射出一发 consume）与 `luck_buff`（暴击 consume）旧 consume 是整栈清空，实践层数基本为 1，true/false 等价，随旧场景恢复为 true。另 `gatling_speed_buff`（`kotori`/`nonomi` 的 `buff_value=-0.2` 自我减速）补 `is_debuff=true`。**迁移任何旧 `scenes/*_buff/*.tscn` 时须逐项核对 `is_remove_by_layer`、`is_debuff`、`buff_erase_timer`（=新 `value[2]` 秒）与旧 `.gd` 里是否硬编码过时长（如 `debt_buff` 的 999）。**
- Source / 来源: code + user
- Date / 日期: 2026-10-01

### [Enemy] 路线目标必须独立于 `player` 存储，否则任何重置 `player` 的逻辑会丢路线
- Evidence / 证据: `script/entity_ENEMY.gd`（`route_target` 字段、`_select_target()` 优先级、`idle_state()` 清空）、`scenes/enemies/enemies_spawn/enemy_path.gd`（`set_body_target` 写 `route_target`、`idle_state` 清）、`script/spawn_anim.gd`（`DEFAULT_ROUTE`、`_setup_path` 带参/兜底/`push_error`）、`resources/enemy/enemy.gd`（新增 `route`）、`resources/enemy/red_sweeper.tres`（挂 `enemy_path.tscn`）
- Notes / 说明: **现象**：红清扫器（路线型敌人）本应沿 `enemy_path` 跑，却直接追玩家。**机制**：以前路线目标只靠 `enemy_path.set_body_target()` 改写 `enemy_body.player`；`player` 是通用字段，任何地方（或漏建路线时）让它变回真实玩家，`_select_target()` 就返回玩家 → 追玩家。且只有 `path_spawn` 会建路线，`test_room.spawn_test_enemy()`/`ui/test_menu.gd` 等生成器不设 `has_path`，必然丢路线。**修法（防御性）**：① `entity_ENEMY` 新增独立 `route_target`，`_select_target()` 按 `aggro_override → route_target → player` 取；`idle_state()` 清空（每次生成由 `_setup_path` 重设）。② 保留 `enemy_body.player = self` 兼容旧读取，但路线以 `route_target` 为准 → 重置 `player` 不再丢路线。③ 路线声明下沉到 `EnemyCard.route`，`spawn_anim.spawn_enemy_body()` 每次生成解析来源，**所有生成器**都会挂路线。④ `has_path` 但 `path==null` 兜底 `DEFAULT_ROUTE`；`route_scene==null` / `route_target` 未设时 `push_error`，**不再静默失败**。`game_eval` 验证：仅 `red_sweeper.route` 非空；不设 `has_path` 仅靠 `EnemyCard.route` 即 `route_target==enemy_path`；把 `enemy.player` 改成别的节点并清缓存后 `get_target()` 仍是 `enemy_path`；`has_path=true/path=null` 走兜底且 `push_error`；池化复用后仍只有 1 个 `enemy_path` 子节点且 `route_target` 重设。**通用教训**：需要长期稳定的目标/引用不要塞进会被别的系统复用的通用字段，用专用字段 + 每次生成重断言 + 数据驱动 + 失败出声。
- Source / 来源: code + test
- Date / 日期: 2026-10-02

### [Enemy/Boss] 血量归零不结算：`EnemyStats.hp` setter 提前 return 漏发死亡事件；聚合型 Boss 结算又依赖子单位 `hp_changed`
- Evidence / 证据: `script/EnemyStats.gd:77-97`（死亡分支原在 `if hp == v: return` / `if hp > max_hp: return` **之后**）；三塔 Boss：`resources/enemy/erosion_tower.tres`→`erosion_tower_group.tscn`（`BossHP`/聚合 `EnemyStats`）、`erosion_tower_group.gd:34-38 count_hp`/`:127-128 count_now_hp`/`:89-91 boss_dead`（`if stats.hp <= 0` 才 `emit_boss_round_end()`）；`goliath.gd:182-187`（`hp==0` 返回 `IDLE`，**无状态机 DEAD 兜底**）。
- UPDATE 2026-10-25: 塔组改为出招序列驱动后 `count_hp` 已移除（阶段判断改由 `_phase_for_hp` 计算），聚合血量逻辑仍在 `count_now_hp`/`boss_dead`；上文 `erosion_tower_group.gd:34-38` 锚点作废，现见 `erosion_tower_group.gd:201-204,270-282,381-389`。
- Notes / 说明: **现象**：kitchen_knife 斩杀后有时 Boss 血条归零但不出结算、继续攻击。**机制**：① `EnemyStats.hp` setter 把死亡判定放在两个提前 `return` 之后；当 `hp==0` 再受击（`hp == v`）或 `max_hp` 被下调导致旧 `hp > max_hp` 时，`hp` 被写成 0 却**跳过死亡分支** → 无 `hp_changed`、无 `is_dead`、无 `on_dead`。② 三塔 Boss 的结算门 `boss_dead` 只读聚合 `stats.hp`，而聚合值由 `count_now_hp` 挂在**每座塔的 `hp_changed`** 上维护；塔的死亡一旦被 ① 吞掉，聚合值停留 >0 → `boss_dead` 不结算，其余塔继续打。Goliath 单 Boss 共用同一 setter，且没有状态机 `DEAD` 兜底，一旦命中同样「0 血继续打」。**修法**：① `EnemyStats.hp` 把 `v <= 0 and dead_lock == false` 的死亡分支提到所有提前 `return` **之前**（先 `hp = v` 再 emit）。② `erosion_tower_group.boss_dead()` 开头强制 `count_now_hp()` 重算聚合值，并加 `_dead_started` 幂等门（`active_state()` 复位）。③ `erosion_tower.on_dead()` / `goliath.on_dead()` 加 `if is_idle == 1: return` 幂等门（`erosion_tower` 有 `is_dead`+状态机 DEAD 双路）。**通用教训**：事件型 setter 的副作用（信号/结算）不要放在「值未变就提前 return」之后；聚合型实体的结算不要只信任「子单位信号已同步」，入口处显式重算更稳。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [Perf] 高频角色 PS 的「全量重算 / 扩散生成」必须节流（Nonomi 重算合并；Momoi/Midori 扩散 0.1s CD）
- Evidence / 证据: 起因 `scenes/player/nonomi/nonomi_ps.gd:109-115`（`add_coin` 命中得币）→ `script/Stats.gd:134-142`（coin setter 发 `coin_changed`）→ `nonomi_ps.gd:76-88`（`set_playerdata` 同步 `update_player_ability()`）；范式参照 `scenes/manager/player_buff_manager.gd:16-24`（每帧合并）。修后：`nonomi_ps.gd:91-101`（`_schedule_recompute`/`_flush_recompute`）、`:132-140`（`coin_cost_count` 批量后再调度）。扩散：`scenes/player/momoi/MomoiPS.gd:53-59`（顶层 `_last_diffuse_ms` 0.1s CD）、`scenes/player/midori/MidoriPS.gd:41-76`（tag 计数始终执行，CD 只包 `_spawn_poison_diffuse`）。基座：`script/PlayerData.gd:326-341`（`update_player_ability` 全量重算+信号）。
- Notes / 说明: 移动端约第 11 波掉帧：Nonomi 加特林命中即得币，每次 `coin_changed` 都同步全量重算玩家属性，绕过了 `player_buff_manager` 的每帧合并；Momoi `add_fire_diffuse`（挂 `enemy_damage_taken`，每击）与 Midori `add_poison_diffuse`（挂 `enemy_damage_taken_dead`，每杀）会反复 reposition+`reset()` 最多 31 个扩散节点并生成大量 `dot_spread` 飘字。修法：① Nonomi 的 `set_playerdata`/`coin_cost_count` 统一走 `_schedule_recompute()`（`call_deferred` 每帧合并一次 `update_player_ability`），派生值最多延迟 1 帧；② Momoi `add_fire_diffuse` 顶层 0.1s CD；③ Midori 因函数内含 `tag_set["poison_diffuse"]["quantity"]` 链式计数，CD 只拦生成段、计数照常扣减（方案 B），保证爆发期减少节点/飘字但链式语义不漂移。CD 一律用 `Time.get_ticks_msec()` 墙钟而非 Timer，不受 `Engine.time_scale` 影响（见 `[Time]` 条目）。**教训**：凡挂在 `enemy_damage_taken`/`enemy_damage_taken_dead` 上的「生成对象 / 全量重算」都要有频率上限；扩散类函数的 CD 若与状态副作用混在一处，CD 只能包住生成部分。
- Source / 来源: user + code
- Date / 日期: 2026-10-02

### [Enemy/Boss] Boss 重写 `on_dead` 不走 `idle_state` → 尸体 HurtBox 仍可被判定：尸体吃伤害但总血不降
- Evidence / 证据: 普通敌人 `entity_ENEMY.on_dead`→`idle_state()` 会 `hurt_box_shape_2d.disabled = true`（`script/entity_ENEMY.gd:114`）；`scenes/enemies/boss/erosion_tower.gd:194-203 boss_death_anim()` 只关本体 `collision_shape_2d`（原未关 HurtBox）；`scenes/enemies/boss/goliath.gd:494` `on_dead()` 同样未关。表现链路：`script/health_component.gd:_take_damage_internal` → `GameEvents.emit_enemy_damage_taken`（`script/enemy_hurt_floating_text.gd` 飘字）+ `owner._hurt_flash()` + 击退；而 `EnemyStats.hp` setter 因 `dead_lock` 已置位 no-op → 总血不变。
- Notes / 说明: **现象**：三塔组里某塔先死、其余塔仍活时，攻击死塔会出现飘字/白闪，但聚合血条不动（单塔/goliath 死亡动画期间同理）。**机制**：两个 Boss 都重写 `on_dead()` 且没调用 `idle_state()`，HurtBox 形状未禁用；且 `CollisionShape2D.disabled=true` 不保证补发 `area_exited`，`kitchen_knife.enemy_group` 等集合可能仍持有该 HurtBox 直接 `hit_received.emit`。**修法（纵深）**：① 通用门 `health_component._take_damage_internal` 在 `is_invincible` 后加 `if stats.hp <= 0 and not stats.is_test_target: return`；② `summoned_health_component.take_damage` 加 `if stats.max_hp > 0 and stats.hp <= 0: return`（`max_hp<=0` 的转发型召唤物 `hp` 恒 0，必须排除，否则会挡掉「代为承伤转发玩家」分支）；③ `erosion_tower.boss_death_anim()` / `goliath.on_dead()` 补 `hurt_box_shape_2d.disabled = true`；④ `scenes/update_item/kitchen_knife.gd:damage_add` 反向遍历，跳过并从 `enemy_group` 移除 `stats.hp <= 0` 目标（`is_test_target` 除外）。`game_eval` 验证：hp=0 的 `HealthComponent` 不再发 `damage_taken`/飘字，`is_test_target=true` 仍结算。**通用教训**：重写 `on_dead()` 时要么调用 `idle_state()`，要么显式关闭 `hurt_box_shape_2d`；且「已死不再结算」的兜底应放在 `HealthComponent` 层，不能只靠关碰撞形状。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [PS] iori 分裂子代必须打 `SPLIT_CHILD` 标记，否则子代会持续触发分裂
- Evidence / 证据: `scenes/player/iori/iori_ps.gd`（`check_bullet` 依 `damage_data.source_node` 解析子弹、`shoot_bullet` 用 `duplicate(true)` 复制父级 `damage_data`）、`script/game_tags.gd`（新增 `SPLIT_CHILD`）；防连锁先例 `scenes/update_item/shrapnel_bullet.gd:39`（`flags.has("shrapnel_bullet")`）。
- Notes / 说明: 旧 `shoot_bullet` 复制父级 `damage_data`，子代 `source_node` 仍指向**父子弹**；`check_bullet` 遂永远在父子弹上判定，唯一去重 `bullet_group.has(父)` 又会因父子弹命中后立即 `idle_state()`（`in_idle`→`remove_bullet`）而失效 → 任一子代命中都会再次 `shoot_bullet(父)`，即「分裂后的子弹又分裂」，且从回池后的 `(0,0)` 位置生成、并把父级 `on_damage_dealt` 闭包也带过来误改父子弹状态。修法（采用 A）：① `shoot_bullet` 复制后 `_keep_foreign_callbacks()` 剔除绑定在父子弹上的 `on_damage_dealt`（保留 MidoriPS 等玩家级回调，其 `get_object()` 非父子弹）；② `flags.append(GameTags.SPLIT_CHILD)` 打标；③ 入树后把 `source_node` 改指向子代自身。`check_bullet` 增门：`damage_data == null` / 非 `BULLET_DAMAGE` / 非 `PLAYER` / 含 `SPLIT_CHILD` / `get_node_or_null` 无效 / 无 `apply_penetrate_dealt` / `is_idle==1` 一律 return。**结论**：原始子弹（玩家枪械、`shrapnel_bullet`/`pratt_helmet` 经 `player_bullet_launcher`→`emit_player_shot_position`→`player.gd:bullet_hit_damage`）不带标记、可分裂；分裂子代带标记、不再分裂。**通用教训**：凡「生成物要参与同一套命中/触发判定」的机制（分裂/连锁/召唤投射物），必须在生成物上打显式来源标记并让判定读取该标记；不要依赖「同一实例复用」的集合去重，它会随对象回池而失效。
- Source / 来源: user + code
- Date / 日期: 2026-10-02
- SUPERSEDED: 2026-10-08 触发函数 `check_bullet` 已重命名/改造成 `_on_projectile_hit`（改监听 `GameEvents.player_projectile_hit`），不再从 `damage_data.source_node` 解析子弹；`SPLIT_CHILD` 防连锁的结论仍有效。见下方 2026-10-08 iori 条目。

### [PS] iori 分裂继承比例 `damage_mult` 在迁移到 `damage_data` 时被漏乘（恒 100%）
- Evidence / 证据: `scenes/player/iori/iori_ps.gd:100-110`（`_configure_split_bullet` 复制父级 `damage_data` 后补 `base_damage *= damage_mult`）、`:12,24-35`（`damage_mult` = 0.5/0.6/0.8/1.0）；旧实现 `HEAD:iori_ps.gd` 曾 `now_bullet.bullet_damage = bullet_body.bullet_damage * damage_mult`。
- Notes / 说明: `damage_data` 迁移时弹射增伤 `update_bullet_damage` 已正确改为 `base_damage *= collision_damage_mult`，但分裂路径改成 `duplicate(true)` 后**丢掉了 `* damage_mult`**，子代恒继承父级 100% 伤害，T1/T2/T3（50/60/80/100%）不生效。修法：复制后 `node.damage_data.base_damage = max(1, round(node.damage_data.base_damage * damage_mult))`（`base_damage` 为 int，用 `round` 对齐 `player.gd:476` 等惯例）。同轮按用户要求 T1/T2 弹射由 +1 调为 +2（`PlayerData.collision_num_add += 2`，`ETN_player_localization.csv` 的 `iori_ps_1/2` 四语种同步）。**通用教训**：把「逐字段赋值」重构为「整体 `duplicate` + 少量覆写」时，必须逐一核对旧的逐字段乘算/覆写是否被保留——此处 `damage_mult` 被静默丢弃且无编译器告警（只写不读的变量）。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Physics] Area2D 形状启停必须在物理 query flush 之外（统一 deferred + gen 守卫）
- Evidence / 证据: `script/player_bullet.gd:199-213`（`_request_shape_disabled`/`_set_shape_disabled_guarded`）、`scenes/bullet/normal_bullet.gd`、`megu_bullet.gd`、`enemy_bullet.gd`、`stone_bullet.gd`、`poison_ring.gd`、`mashiro_sniper_bullet.gd`；`script/entity_ENEMY.gd:113-114,144-145`、`scenes/enemies/boss/{goliath,erosion_tower}.gd`、`scenes/enemies/{modded,enhanced}_sweeper.gd`、`script/{explosion_damage,fire_damage}.gd`、`scenes/summoned/summoned_hit_box.gd`、`scenes/item/pyroxenes.gd`、`scenes/summoned/mobu_trinity/soft_collision.gd`、`scenes/update_item/murky_hand_scythe_icon.gd`、`scenes/player/mashiro/cross_bullet.gd`、`scenes/player/utaha/UtahaPS.gd`、`scenes/player_support/kei/kei_as.gd` 等改 `set_deferred`。
- Notes / 说明: 玩家报错链「大量 `area_set_shape_disabled(): Can't change this state while flushing queries` → 大量 `buffer_create(): VkResult error -10 (VK_ERROR_TOO_MANY_OBJECTS)` → 卡退」。根因之一：`idle_state()`/`active_state()`/`on_dead()`/`_on_body_entered()` 等会在命中/死亡结算（物理 query flush 期）被调用，却**同步**直写 `Area2D` 的 `CollisionShape2D.disabled`。修法统一为延迟写入：子弹家族抽 `_request_shape_disabled(value)`（`_shape_gen += 1` + `call_deferred("_set_shape_disabled_guarded", value, _shape_gen)`），`close_shape()`/冷却重开/`idle_state()`/`active_state()` 全走它，靠 `_shape_gen` 作废「回池后同帧复用」的旧延迟调用；非子弹实体统一 `set_deferred("disabled", …)`（同一形状的所有写入都改为 deferred 时，`set_deferred` 的 FIFO 顺序天然正确，无需 gen）。**代价**：形状状态最多晚 1 帧生效（`coin.gd`/`close_shape` 早已如此）。只对「`enable` 决定当帧命中」的近战（`kick.gd`/`chinatsu_melee.gd`）和依赖「立即启停重置残留」的 `enemy_part.gd` 保持同步（其调用点非 flush）。**通用教训**：凡 `Area2D`/`CollisionShape2D` 的启停可能落在 `area_entered/exited`、`body_entered/exited`、`hit_received` → 伤害结算这条链上，一律 `set_deferred`/`call_deferred`，不要同步直写。
- Source / 来源: user + code
- Date / 日期: 2026-10-02

### [Pickup] 金币无界池：满额并入最近活跃金币（`CoinManager`），且不要给 `coins` 加 `IDLE_LIMITS`
- Evidence / 证据: `scenes/manager/coin_manager.gd`（`drop_coin`/`_nearest_active`/`register`/`unregister`）、`scenes/item/coin.gd`（`absorb`/`coin_scale`/`active_state`登记）、`project.godot [autoload]`（新增 `CoinManager`）；旧实现 `script/entity_ENEMY.gd:_coin_drops`/`scenes/enemies/sandbag.gd:_coin_drops` 直接 `PoolManager.get_pool("coins")`。
- Notes / 说明: `coins` 池原先无 `IDLE_LIMITS` 项（`limit=-1`）→ 全忙时 `get_pool` 不回收、调用方持续 `instantiate` → 节点无界增长（`VK_ERROR_TOO_MANY_OBJECTS` 诱因之一）。修法：新增 autoload `CoinManager` 做金币专用层，`COIN_POOL_CAP=150`；满额时把新掉落并入**最近一枚**活跃金币（`coin.absorb(value, pick_up)` 累加值 + 重算缩放 + 补发 `enemy_coin_drops`），**不新建节点**，总值守恒。**不要给 `coins` 加 `IDLE_LIMITS`**：`limit>=0` 时 `get_pool` 会对即将交出的槽位强制 `idle_state()`，把活跃金币当空闲回收，调用方随即覆写 `coin` → 旧值丢失；一律 `get_pool_idle` + 自管计数。合并目标须过滤 `is_idle==1`（回池金币）、失效节点、`can_pick==false`（抛物线/Boss 金币是 `CoinRoot` 的**孙节点**，`main.coin_clear_unit` 只遍历直接子节点、回合末不返还其值）。视觉缩放改边际递减 `0.8 + 1.7*(1-exp(-coins/56.7))`（小值≈旧线性 0.03/枚、渐近上限 2.5）。单线程下合并与拾取不会真并发；`drop_coin`（含 `_coin_drops` 的 `call_deferred`）与 `coin._physics_process` 天然错开。`game_eval` 验证：200 次掉落值 1 → 活跃 150、总值 200；再落值 5 → 活跃仍 150、总值 205；`can_pick==false` 被 `_nearest_active(true)` 跳过、`_nearest_active(false)` 命中。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02
- UPDATE: 2026-10-08 `get_pool` 重写后，`limit>=0` 不再是「无条件强收即将交出的槽位」，而是「仅满额且无空闲时静默回收」。结论不变——**仍不要给 `coins` 加 `IDLE_LIMITS`**（`coins` 一律走 `get_pool_idle` + `CoinManager` 自管 `COIN_POOL_CAP`），否则满额会回收活跃金币丢值。

### [Pickup] 逐枚监听一次性事件会漏掉「事件之后才生成」的对象（青辉石 → coin_box 自动拾取）
- Evidence / 证据: `scenes/item/coin_box.gd`（`_ready`/`_on_pyroxenes_pick_up`/`_flushed`、`add_coin()` 循环）、`scenes/manager/coin_manager.gd`（`auto_pick`/`_on_pyroxenes_pick_up`/`_on_round_start`）、`scenes/item/coin.gd`（`active_state`/`absorb` 的 `auto_pick` 分支；已移除逐枚 `pyroxenes_pick_up.connect(auto_pick)`）、`scenes/enemies/boss/goliath.gd:507`/`erosion_tower_group.gd:146`。
- Notes / 说明: **现象**——Boss 死掉 100 枚 `coin_box` 金币（`add_coin()` 每 0.03s 掉一枚、每枚抛物线 3s 落地），在没掉完时拾取青辉石，**只自动拾取了已掉完的金币**。**根因**：`coin.gd` 原先每枚金币各自在 `_ready` 连 `GameEvents.pyroxenes_pick_up.connect(auto_pick)`，而该信号是**一次性**的——信号发射后才由 `coin_box` 生成的金币在连接前信号已成过去式，永远收不到。**修法**：① 用持久「全局状态」（`CoinManager.auto_pick`）替代逐枚订阅，`coin.active_state()`/`absorb()` 时读取并置 `can_pick/pick_up`；② 活跃集生命周期登记（`CoinManager._active`）让事件发射时能遍历到已存在对象（含抛物线飞行中金币）；③ `coin_box` 对同一事件置 `_flushed`，把**异步节流循环**（`await timer.timeout`）改为 `if _flushed: continue` 立即补发剩余；④ `round_start` 复位状态。**通用教训**：凡「某一次性事件要让**事件之后陆续生成**的对象也生效」，不要用逐对象订阅该信号（必然漏新对象），要用持久状态位 + 生命周期登记在对象激活时读取；异步生成器（带 `await` 的循环）在需要「立即全量」时要提供 flush 通道。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [Input] 移动端外接键鼠/手柄：`control_mode` 与虚拟摇杆脚本态会跨设备/回合残留，导致触屏 UI 消失且全部输入失效
- Evidence / 证据: `script/Game.gd`（`_unhandled_input` 事件推断 `control_mode`、新增 `reset_control_mode()` 连 `round_start`）、`ui/game_ui.gd:40-47`（`control_mode != 1` 隐藏 `VirtualJoypad`）、`ui/Knob.gd`/`ui/MouseKnob.gd`（新增 `_release_all()`、`event.canceled`、`visibility_changed`、`NOTIFICATION_APPLICATION_FOCUS_OUT|SUSPENDED|PAUSED|EXIT_TREE`、`game_mode_changed`、`round_start` 清理）、`script/player.gd:97`（`reset_control_flags()` 连 `round_start`）、`scenes/manager/upgrade_manager.gd:54-59`、`scenes/manager/round_manager.gd:98,116`、`ui/UpgradeScreen.gd`（`_closed` 幂等）。
- Notes / 说明: **0.4 回归背景**——0.4 加入 `InputEventJoypadButton → control_mode = 2`（`Game.gd:48`）后，移动端接外接键鼠/仿 Xbox 手柄时，`GameUI` 会按 `control_mode` 隐藏/显示触摸摇杆。旧实现下：① `control_mode` 只在设备事件时改、**回合边界不复位**；② `TouchScreenButton` 隐藏时引擎会 `set_process_input(false)`（并只释放其自身 `action`），但 `Knob/MouseKnob` 的脚本态（`finger_index` + `Input.action_press("move_*")`）不会被清；③ `InputEventScreenTouch.canceled`（4.7 有该字段）未处理。于是切换设备/隐藏摇杆时摇杆脚本态残留，触摸 UI 不再恢复。本次加固：`control_mode` 增识别 `InputEventKey`(→0)/`InputEventJoypadMotion`(→2)，并在 `round_start` 按平台复位（移动端=1/桌面=0）；摇杆 `_release_all()` 覆盖 canceled/不可见/焦点/暂停/退出/模式切换/回合；`player` 回合边界复位 `player_stop/can_control/can_move/can_jump`（`player_stop` 旧实现一旦为真无复位路径）；升级页移动端改用 `MOUSE_MODE_VISIBLE`（旧 `MOUSE_MODE_HIDDEN` 会让外接鼠标指针不可见）；`_on_round_start` 的 timer 加 `ignore_time_scale=true`，`UpgradeScreen` Next/Refresh 加 `_closed` 幂等防触摸双触发。**踩坑**：Godot 3 的 `NOTIFICATION_SUSPENDED` 在 Godot 4 不存在（会 `Parser Error: Identifier not declared`），移动端挂起通知应写 `NOTIFICATION_APPLICATION_PAUSED`（2015，配合 `NOTIFICATION_APPLICATION_FOCUS_OUT` 2017）。**通用教训**：设备驱动的全局 UI 状态（`control_mode`）必须在回合/场景边界复位；手写的触摸摇杆必须处理 `canceled` 与「不可见/失焦/暂停」并显式清 `Input.action_*`，不能依赖引擎对 `TouchScreenButton` 的自动释放。
- Source / 来源: user + code
- Date / 日期: 2026-10-02

### [Combat] 玩家侧爆炸「爆炸伤害」加成统一收口在 `ExplosionDamage`（不再各创建点手写）
- Evidence / 证据: `script/explosion_damage.gd:103-142`（`add_damage_data()` 调 `apply_player_explosion_bonus`；静态 `should_apply_player_explosion_bonus`/`apply_player_explosion_bonus`）；`scenes/bullet/yuzu_bullet.gd:95-99`（爆炸本身打 `EXPLOSION_DAMAGE` 标签）；已删除手写乘算：`scenes/update_item/ink_cartridge.gd`、`scenes/update_item/matcha_ramune.gd`、`scenes/update_item/cherino_matryoshka.gd`、`scenes/player/kasumi/kasumi_drill.gd`、`scenes/player_support/ayane/ayane_as.gd`、`scenes/update_item/shiroko_drone_icon_2.gd`；PS 不再全局打标：`scenes/player/yuzu/YuzuPS.gd`、`scenes/player/hibiki/HibikiPS.gd`；测试 `tests/test_explosion_bonus.gd`。
- Notes / 说明: 旧 `DamageData` 迁移时，yuzu/hibiki 迫击炮弹（`PlayerMortarBullet.bullet_explosion()`，两者共用 `yuzu_bullet.gd`）只 `duplicate` 子弹 `damage_data`，丢了旧版 `bullet_damage * player.stats.explosion_damage` 的乘区 → 爆炸伤害加成失效；PS 的 `player.damage_types.append(EXPLOSION_DAMAGE)` 只是标签、不产生倍率（还误标了普通子弹）。改为在 `ExplosionDamage` 按类型+阵营统一结算：`damage_type.has(EXPLOSION_DAMAGE)` 且 `source_type` 非空、`Faction.of_source()==PLAYER_SIDE`（`PLAYER`/`EQUIP`/`CONVERTED`/`SUMMONED`）时 `duplicate(true)` 后乘 `stats.explosion_damage`（保底 1）；`NEUTRAL`（`oil_barrel`/`enemy_tank`）与 `ENEMY`（`cannon_bullet`/`enemy_missile_1`）不吃。**来源判空是必须的**：空 `source_type` 会被 `Faction.of_source` 判成玩家侧（见本文件 2026-09-25 条目），会误给敌方/中性爆炸加成。新增爆炸务必给 `source`；今后不要再在创建点手写爆炸倍率。该脚本被 `.tscn` 引用，编辑器热重载会误报 `gdscript_reload_failed`，故测试用 `CACHE_MODE_IGNORE` 新鲜加载（见本文件 2026-09-26 条目）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [Localization] 改 `ETN_localization.csv` 后仅 MCP `reimport` 不重新生成 `.translation`，需再 `scan`（编辑器聚焦）
- Evidence / 证据: 追加 `delete_confirm` 行（UTF-8 BOM + CRLF）后 `filesystem_manage(reimport, ["res://ETN_localization.csv"])` 返回 `reimported`，但 `ETN_localization.*.translation` 的 `LastWriteTime`/大小不变，运行期 `TranslationServer.translate("delete_confirm")` 仍返回 key；随后 `filesystem_manage(scan)` 才更新 4 个 `.translation`（大小各 +28~36B），`translate` 四语正确返回。
- Notes / 说明: CSV 导入器（`importer="csv_translation"`，`dest_files` 为 4 个 `.translation`）只有在编辑器文件系统重新检测到变更时才重跑。MCP 的 `reimport` 单独调用在编辑器未聚焦/未检测到改动时可能只刷新单文件条目、不重生成产物。**流程**：改 CSV →（`reimport`）→ `scan` 等待 `settled` → 再验证。注意 `.translation` 是 `compress=true` 二进制，不能靠 grep 明文 key 判断是否更新，应看时间戳/大小或用 `TranslationServer.translate` 运行期验证。
- Source / 来源: test
- Date / 日期: 2026-10-02

### [Perf] 空闲 BuffCard 停物理帧；DOT 跳伤复用 DamageData 槽；高频受击音「同帧 ≤1 次 + ≥40ms」节流
- Evidence / 证据: `ui/BuffCard.gd:18-35`（`idle_state` `set_physics_process(false)` / `active_state` `set_physics_process(true)`）；`scenes/manager/enemy_buff_manager.gd:28-30,76-86,129-152`（`_fire_dot_ddata`/`_poison_dot_ddata` 槽 + `add_damage_data(..., slot)` 走 `DamageData.fill`）；`scenes/debuff/fire_diffuse.gd:32-38`（`value` 提到敌人循环外）；`scenes/manager/SoundManager.gd:18-20,49-59`（`play_sfx_throttled`）+ `script/health_component.gd:150`。
- Notes / 说明: 起因：Momoi 的燃烧 DOT 让大量敌人每 0.1s 各跳一次伤害，放大 `enemy_damage_taken` 扇出、`BuffCard.set_value` 刷新与 `HurtSounds` 重播；Profiler 见通用 `_physics_process` 456 次、`set_value` 1.21ms、`play_sfx` 高频。修法：① 池中空闲 BuffCard 关闭 `_physics_process`（敌人场景普遍带 `BuffBox`，`BuffManagerBase._obtain_buff_card` 会为每个敌人 buff 建卡）；② fire/poison DOT 的 `DamageData` 用成员槽 `fill` 复用（消费方同步读取、不跨跳持有）；`count_chill_damage` 走 `request_extra_damage`、会被 `_pending_extra` 暂存，**必须仍每次新建（slot=null）**；③ `fire_diffuse.fire_dot_add` 的 `value` 数组由「每敌一次」提到「每激活一次」；④ 高频受击音走 `SoundManager.play_sfx_throttled("HurtSounds")`，保留密集手感但不重播。**注意**：Momoi `fire_dot_append_damage` 的燃烧 +50% 承伤对**所有**伤害来源生效，曾提议按 `BULLET_DAMAGE` 早退被用户否决，**不得早退**。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [UI] `support_shop.update_exp` 订阅全局 `count_exp_changed`，可能在未选卡时触发
- Evidence / 证据: `ui/support_shop.gd:47`（`_ready` 连接 `SupportData.count_exp_changed` → `update_exp`）、`:128`（原直接读 `now_support_card.max_lv`）；触发源 `script/support_data.gd:36`（`now_count_exp` setter emit），经 `get_card`/`load_data`/`count_exp`；选关阶段 `ui/support_ui/support_select_ui.gd:40-73` 就调 `SupportData.get_card`，此时 `support_shop.now_support_card` 仍为 null，而 `now_lv` 可从存档 >0。
- Notes / 说明: 现象：进入支援商店流程报 `Invalid access to property or key 'max_lv' on a base object of type 'Nil'`（`support_shop.gd:128`），游戏进入 debugger break。修法：`update_exp` 开头 `if now_support_card == null: return`。`game_eval` 验证：null 卡 + `now_lv=5` 调 `update_exp` 不再崩；赋真实卡后 `lv_value` 正常显示。**通用**：UI 若通过全局信号订阅数据变更，回调必须能容忍「自身上下文尚未初始化」（如尚未选卡/未入树）。
- Source / 来源: code + test
- Date / 日期: 2026-10-02

### [Bullet] 敌方子弹撞墙改用 HitBox `body_entered`，不再用 RayCast2D
- Evidence / 证据: `scenes/bullet/enemy_bullet.gd:41-57`（`_ready` 连 `body_entered` + `_on_body_entered`）、`:74-114,129-141`（已删 `ray_cast_2d`）；`scenes/bullet/enemy_bullet.tscn`/`enemy_bullet_2.tscn`/`enemy_bullet_3.tscn` 的 Area2D `collision_mask` `2048→2050`、`RayCast2D` 节点删除；墙来源 `scenes/main/main.tscn:244`（`Wall` TileMap，TileSet `physics_layer_0/collision_layer=2`）、`script/props/prop_wall_body.gd:8-13`（`StaticBody2D`，层 2 + `BulletWall` 组）。
- Notes / 说明: 起因：`enemy_bullet_3` 经 `FormationController` 发射时被置 `speed=0`（`scenes/bullet/launcher/formation_launcher.gd:188`），旧 `active_state` 令 `ray_cast_2d.target_position.x = speed*0.0167 = 0` → 零长度射线，`enemy_gun_7` 的阵型弹穿墙。修法：`EnemyBullet` 的 Area2D 纳入 `bullet_wall`(2) 层，`body_entered` 命中 `BulletWall` 组即 `bulletSmoke + idle_state()`；删除射线判墙/反弹分支（敌人子弹 `collision_num` 全为 0，无需反弹）。`game_eval` 验证：`enemy_bullet_3` 与 `enemy_bullet.tscn` 同动态 `StaticBody2D`(层2、`BulletWall`) 重叠后 `is_idle` 0→1、无墙时保持 0；`RayCast2D` 不存在、`collision_mask=2050`。**注意**：`PlayerBullet`（`script/player_bullet.gd`）/`normal_bullet`/`megu_bullet` 等仍用射线撞墙，本改动不影响；TileMap 与 `PropWallBody` 都是 `StaticBody2D`，故用 `body_entered` 而非 `area_entered`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [Perf] 召唤物索敌排序：合并到每帧一次 + 平方距离
- Evidence / 证据: `script/summoned.gd:65-78`（`_mark_sort_dirty` + `sort_enemy.call_deferred()`、`distance_squared_to`）、`:38-63`（三处 enter/exit/converted 改为置脏）；消费方 `script/summoned_follower.gd:78-89`、`script/turret_summoned.gd:82-85`。
- Notes / 说明: Profiler 见 `Summoned.sort_enemy 2.05ms` + `Summoned.<anonymous> 1.39ms`（后者是 `sort_custom` 的 lambda）。原实现每次 `area_entered/exited` 都**全量** `sort_custom`，一帧 5 次事件 → 5 次排序、239 次比较；比较器每次跑 GDScript lambda + `distance_to`（含 sqrt）。改法：① 变更只置 `_sort_dirty`，`call_deferred` 合并为**每帧最多排一次**（`enemy_body[0]` 至多晚 1 帧更新，原本也只在事件时排、随敌人移动本就滞后，无行为损失）；② 用 `distance_squared_to`（省 sqrt）、`origin` 只取一次。`game_eval` 验证：排序结果正确（[10,50,100]→移动后 [50,100,999]）、连续两次置脏只排一次（`_sort_dirty` 守卫）、帧末自动清脏。**通用**：挂在 `area_entered/exited` 上的「全量排序/重算」都应合帧（标脏 + deferred）并避免在比较器里做重活。
- Source / 来源: test
- Date / 日期: 2026-10-02

### [Perf] buff 卡池取用从 O(N) 线性扫描改为 O(1) 空闲栈
- Evidence / 证据: `scenes/manager/PoolManager.gd:33-39`（`_idle_buff_cards`/`_idle_buff_set`）、`:78-82`（`lear_buff_box` 清栈）、`:233-263`（`get_buff_pool` 出栈 + `_scan_buff_box_idle` 兜底 + `push_idle_buff_card`/`clear_idle_buff_cards`）；投放入口 `ui/BuffCard.gd:26-31`（`release_to_pool` 末尾 push）；消费方 `scenes/manager/buff_manager_base.gd:362-382`（`_obtain_buff_card`，逻辑未改）。
- Notes / 说明: Profiler 见 `BuffManagerBase._obtain_buff_card 2.47ms / 12 次`（≈206µs/次）。原因：旧 `get_buff_pool()` 对全局 `buff_box` 做**裸 `for child in get_children()`**，无索引；敌人死亡时 `release_idle_cards()` 把闲置卡 reparent 回全局池，池子随波次增长 → 每次取卡 O(N)。改法：`release_to_pool` 时把卡（`[instance_id, card]`）压入空闲栈并按 id 去重，`get_buff_pool` 出栈返回首个 `is_idle==1` 的有效卡，无效项跳过并清 id；栈空再退回线性兜底（正确性保底）。`game_eval` 验证：release 后 `_idle_buff_cards.size()==1`、重复 push 被去重仍为 1、`get_buff_pool()` 返回同一张且栈清空、栈内卡被 free 后取用跳过无效项不报错。
- Source / 来源: test
- Date / 日期: 2026-10-02

### [Spawn] 按敌人 id 的并发生成上限：必须用 pending 预占，不能只在落地时判
- Evidence / 证据: `scenes/manager/PoolManager.gd`（`ENEMY_SPAWN_CAPS`、`_active_by_id`/`_pending_by_id`、`try_claim_spawn`/`release_spawn_claim`、`register/unregister_active_enemy`、`_add/_sub/_rebuild_active_by_id`、`clear_active_enemies` 清两表）；`script/enemies_spawn.gd:106-113`、`script/raid_spawn.gd:88-90`（请求前 `try_claim_spawn`，失败 `break`）；`script/spawn_anim.gd`（`_claimed_id`、`_release_claim`、`enemy_spawn_anim`/`spawn_enemy_body`/`idle_state`/`on_round_end`/`_exit_tree`）。
- Notes / 说明: 需求：`tester_automaton_shield=12`、`droid_helmet_smg=15`、`lighttank_helmet=4` 场上并发上限，超限跳过。**关键坑**：`spawn_anim.enemy_spawn_anim()` 会 `await spawn`（动画 ~0.3s）后才 `active_state()` 登记；突袭潮 `raid_spawn` 一个循环就请求 16 个盾兵，若只在「落地/激活时」判上限，16 个检查读到同一旧计数 → 仍会超。故必须在**生成请求时预占 pending**（`try_claim_spawn`：`active+pending < cap` 才 +1），落地时 `release_spawn_claim`（pending−1，同时 `active_state` 已 +1，净值不变）。释放必须覆盖**所有**中止路径（`can_spawn==false`、`idle_state`、`on_round_end`、`_exit_tree`），否则 `queue_free` 打断 `await` 协程会泄漏 pending 永久占坑。`game_eval` 验证：12 次 claim 全 true、第 13 次 false、release 后可再 claim；`register/unregister_active_enemy` 使 `get_active_count_by_id` 0→1→0；无上限 id（如 `sweeper`）恒 true 且 pending 0；`clear_active_enemies` 清空 pending。**通用教训**：任何「延迟落地」的生成（带 `await`/动画/协程）做并发上限，都要在请求阶段预留名额并在全部中止路径归还；只判「已落地数量」对同帧批量请求无效。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [Perf] 玩家子弹 rotation 改「初始化 + 变向」更新；子弹拖尾 `line.gd` 空闲停物理
- Evidence / 证据: `script/player_bullet.gd`（`active_state` 末尾 `rotation = direction.angle()`；`_physics_process` 删除每帧 `rotation = velocity.normalized().angle()`；反弹分支与 `r_move` 补 rotation；`flight_time` 保留）、`scenes/bullet/megu_bullet.gd`（自反弹后补 rotation）、`scenes/line.gd`（`is_idle` setter → `set_physics_process(not v)`）。
- Notes / 说明: Profiler 见 `PlayerBullet._physics_process 1.60ms×755`（Nonomi 弹数放大）与拖尾 `_physics_process 1.65ms×212`（每弹 2 条 `Line2D`）。① 原实现每弹每帧 `rotation = velocity.normalized().angle()`（normalize+atan2+写 transform），直线弹纯浪费；改为 `active_state()` 定型一次、仅在 `r_move()`（追踪/`can_r`）与反弹时更新。`flight_time += delta` 保留（`mint_chocolate_parfait.gd:22-24` 依赖）。② 拖尾 `line.gd` 空闲子弹仍每帧回调（原只靠 `is_idle` 早退）；`is_idle` 改带 setter，空闲 `set_physics_process(false)`、激活开，去掉池中空闲拖尾空转（**未改更新频率**）。`game_eval` 验证：`line.is_idle=true` → `is_physics_processing()==false`、`false`→`true`；子弹 `active_state` 后 `rotation==direction.angle()`、直线帧 `_physics_process` 不改 rotation、`r_move` 后 rotation 随速度更新。⚠️ `megu_bullet` 自写 `active_state`（不调 super）且反弹在自身闭包，需自行补 rotation；`yuzu_bullet`/`normal_bullet` 各有 `_physics_process`，不受影响。
- Source / 来源: code + test
- Date / 日期: 2026-10-02

### [Enemy] 恶寒把 `MAX_SPEED` 压低会让加速度归零 → 击退后持续滑行
- Evidence / 证据: `script/EnemyStats.gd`（`MAX_SPEED = base_MAX_SPEED * max(0.1, MAX_SPEED_mult)` `:167`；新增 `move_acceleration()` `:172`）；7 处原 `ACCELERATION = stats.MAX_SPEED / stats.SPEED_TIME` 改为 `stats.move_acceleration()`（`automaton.gd:78` / `sweeper.gd:47` / `tester_automaton_shield.gd:94` / `enemy_tank.gd:168` / `sandbag.gd:124` / `boss/goliath.gd:136` / `boss/erosion_tower.gd:70`）；`entity_ENEMY.move()` `:171-172`；恶寒 `CHILL_SPEED_PENALTY=-0.02`（`enemy_buff_manager.gd`）改 `MAX_SPEED_mult`。
- Notes / 说明: 现象：恶寒叠高层后敌人被击退会**一直滑行**。机制：`ACCELERATION = stats.MAX_SPEED / SPEED_TIME`，`MAX_SPEED` 被恶寒压到 `0.1×base`（甚至接近 0）→ 加速度趋 0，`move_toward(velocity, direction*MAX_SPEED, ACCELERATION*delta)` 几乎不改变 velocity。修法：`EnemyStats.move_acceleration()` 取 `max(base_MAX_SPEED, MAX_SPEED) / max(SPEED_TIME, 0.001)`——以基准速度为下限（只有更快时才提高），恶寒降速时加速度保持基础值，击退后能按基础加速度收停。`game_eval` 验证：base 80 / SPEED_TIME 0.1，`MAX_SPEED_mult=0.1` → `MAX_SPEED=8`、`move_acceleration()=800`（= base 值，未降）；`MAX_SPEED_mult=2` → `MAX_SPEED=160`、`=1600`；`SPEED_TIME=0` 走 0.001 兜底不崩。范围仅敌人；玩家 `MAX_SPEED` 有 `clamp(50,…)`（`PlayerData.gd:355`）不受影响。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [UI/Pause] Boss 过场直接写 `get_tree().paused` 与暂停菜单 `WHEN_PAUSED` 失配 → 卡在暂停界面
- Evidence / 证据: `ui/pause_screen.gd:37`（`visibility_changed` → `paused = visible`）、`:69/164`（`show_pause`/`_input` 闸门 + `_pause_locked`）、`:122`（`_on_pause_lock`，锁定时 `hide_pause_screen`）；`ui/pause_screen.tscn:1696`（根 `process_mode=2` WHEN_PAUSED）；Boss 过场 `scenes/enemies/boss/goliath.gd:99-122`、`scenes/enemies/boss/erosion_tower_group.gd:104-138`（`get_tree().paused=true … =false`）；`scenes/manager/round_manager.gd:101/137`；生成窗口 `script/spawn_anim.tscn:160-166`（method track t=0.8 发 `spawn`）。
- Notes / 说明: **现象**：Boss 战开始的瞬间点暂停，若过场结束前没取消，就卡在暂停界面但 Boss 战已开始，回到战斗立刻又进暂停。**机制**：Boss 出场有 ~0.8s 生成窗口（`spawn_anim` 在 t=0.8 发 `spawn`），此间 `paused=false`、可暂停；玩家暂停 → `paused=true`、暂停菜单可见；同帧稍后生成协程恢复 → Boss `active_state()` → `boss_enter_anim()` 先 `paused=true`（无变化）再 `await` **ALWAYS 的过场动画**，动画结束**无条件** `paused=false` → 菜单可见但 tree 未暂停。`PauseScreen` 根是 WHEN_PAUSED，此时其输入/按钮全部失效 → 卡死。**修法（方案 A）**：`GameEvents` 增 `pause_lock(locked)`；`PauseScreen` 接锁后 `_pause_locked=true`、`show_pause`/`_input` 早退、并强制 `hide_pause_screen()`（→ visible/paused 一致）；4 处 Boss 演出与 `round_manager` 升级暂停对在写 `paused` 前后 `emit_pause_lock(true/false)`。`game_eval` 验证：`show_pause()` → visible/paused 均 true；`emit_pause_lock(true)` → 均 false；锁定期 `show_pause()` 无效；`emit_pause_lock(false)` 后可正常打开。**通用教训**：`get_tree().paused` 只能有一个「协调者」；`PROCESS_MODE_WHEN_PAUSED` 的 UI 其可见性必须与 `paused` 严格同步，任何外部写 `paused` 前后都要协调。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [UI/Pause] 回合收尾窗口用 Esc 会在升级页丢鼠标；`hide_pause_screen` 强改鼠标是根因
- Evidence / 证据: `ui/round_timer.gd:106-110`（`round_time<=0` 后 `await create_timer(0.9)` 才 `emit_round_end`）、`scenes/manager/round_manager.gd._on_round_end`（`round_end` 后 `await create_timer(1.0)` 才转场）、`ui/pause_screen.gd:88-95`（原 `hide_pause_screen` 写 `CONFINED_HIDDEN`）、`scenes/crosshair/crosshair.gd:37-39`（`round_upgrade → touch_mode_hide` 写 `VISIBLE`）、`scenes/manager/upgrade_manager.gd:54-59`（桌面 `round_end` 写 `HIDDEN`）。
- Notes / 说明: **现象**：每回合结束、转场开始前按 Esc → 暂停菜单打开；随后升级页（三选一）出现但**鼠标丢失**（升级页拿不到指针）。**机制**：回合收尾有两段可暂停窗口（倒计时归 0 后的 0.9s + `_on_round_end` 的 1s），此时 `can_pause` 仍为 true；Esc 开菜单（`mouse_mode=VISIBLE`）。随后 `emit_round_upgrade` 上 `crosshair` 设 `VISIBLE`、`pause_screen.hide_pause_screen()` 设 `CONFINED_HIDDEN`，执行顺序不定 → 可能最终隐藏。**修法**：① 收尾全程 `pause_lock`——`round_manager._on_round_end` 开头（覆盖 1s+转场+升级）与 `round_timer` 归 0 分支（覆盖 0.9s）各 `emit_pause_lock(true)`，`_on_round_start` 解锁；② `hide_pause_screen()` **不再写 `Input.mouse_mode`**，升级页/商店指针交给 `crosshair` 的 `VISIBLE`；仅 `_on_pause_lock` 确实关闭可见菜单时补 `CONFINED_HIDDEN`。`game_eval` 验证：`hide_pause_screen()` 后 `mouse_mode` 仍为 VISIBLE；锁定期 `show_pause()` 无效；锁定时菜单可见→关闭并转 `CONFINED_HIDDEN`、菜单隐藏→鼠标不变。**通用教训**：切界面时不要在多处竞争写 `Input.mouse_mode`；「谁显示 UI 谁持有指针模式」，通用关闭函数不应强改全局鼠标。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [Autoload] autoload 顶层 `preload` 其依赖 autoload 的场景会成环；且改 autoload 后编辑器旧解析缓存不自动失效
- Evidence / 证据: `scenes/manager/coin_manager.gd` 原为 `const COIN_SCENE := preload("res://scenes/item/coin.tscn")`，而 `coin.gd:45/57/91` 引用 autoload `CoinManager`（`project.godot [autoload]`）。新增该 autoload 后编辑器持续报 `coin_manager.gd:89 Parse Error: Cannot infer the type of "d"`（该行早已改为 `_get_coin_scene()`，带类型的 `var d: float` 在第 106 行）与 `coin.gd:45 Identifier not found: CoinManager`；但运行期 `game_eval` 证明可编译：`/root/CoinManager` 存在、`load("res://scenes/item/coin.gd")` 与 `coin.tscn` 均成功、`drop_coin` 存在。`tests/test_explosion_bonus.gd` 的旧报错同理——重跑 `test_run(suite="explosion_bonus")` 11/11 通过。
- Notes / 说明: ① **成环**：autoload 脚本不要在顶层 `preload` 一个其脚本又引用该 autoload 的场景（`coin.gd` ↔ `CoinManager`），清缓存冷启动可能报 `Identifier not found`；改为惰性 `load`（`_get_coin_scene()` 缓存 `PackedScene`）或 `@export PackedScene`。② **编辑器缓存**：运行中给 `project.godot` 增删 autoload / 改 autoload 脚本后，编辑器对旧 GDScript 的解析缓存**不会自动失效**，`GDScript::reload` 会持续回报旧内容的错误（行号对不上现行源码），`filesystem_manage(scan)` 也未必清掉，需**重启编辑器**。③ 判定真伪顺序：现行源码行内容 → `script_manage(find_symbols)` 解析 → 运行期 `load`/`game_eval`；`editor_manage(logs_clear, clear_debugger_errors=True)` 只清 Debugger Errors 面板，`logs_read(source="editor")` 的历史 Logger 行仍在（不代表当前错误）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [Enemy] `@export` 变量直接当运行期倒计时自减 → 配置值一次性消耗、第二次失效
- Evidence / 证据: `scenes/bullet/launcher/laser_launcher.gd` 原 `time_count()` 里 `life_time -= 1`（`@export var life_time`），`active_state()` 未重置；`scenes/enemies/boss/erosion_tower.tscn:1571-1579` 两 launcher 设 `life_time=500`；塔组窗口 `erosion_tower_group.gd:19 shoot_time_max=60`。
- UPDATE 2026-10-25: 塔组已改为序列驱动，`shoot_time_max` 字段移除；窗口计算现见 `erosion_tower_group.gd:188-199` 与 `resources/boss/tower_attack/*.tres`。
- Notes / 说明: **现象**：erosion_tower 激光的 `life_time` 改了没效果。**机制**：`@export` 值被当运行期计数器自减，第一次激活后就到 0，之后 `if life_time > 0` 永不成立 → 不再 `stop_rotating`（配置只生效一次）；且倒计时从 `active_state()` 起算、把固定 `warning_time=15` 预警也算进去，`life_time ≤ 15` 时预警阶段就“到期”，而 `stop_rotating()` 有 `is_rotating` 门被静默丢弃，随后预警结束 `start_rotating()` 照启动 → 反转不停。**修法**：配置与运行期分离（`life_time` 保持不动的 `@export`，新增 `life_time_left`，`active_state()` 重装并同时重置 `warning_time`/`end_time`/`is_stop`），life 计时移到预警之后。**通用教训**：任何 `@export`/`const`/场景覆盖值都不可在运行期被原地自减当计数器；要倒计时应另存私有计数器并在每次激活重装。`game_eval` 验证：`life_time=20` 35 tick 后 `is_stop=true`；第二次激活仍按 20 停止（重置生效）；`life_time=0` → 预警后直接 idle 不出光；`total_active_ticks(100)==130`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-02

### [Combat] `DamageData`/`HealData` 构建器对未入树节点调 `get_path()` 会刷「Cannot get path of node」红字
- Evidence / 证据: `scenes/player/mashiro/mashiro_ps.gd:137-146`（`call_deferred("add_child", ins)` 后同帧 `DamageData.fill(..., "node": ins)`）、`script/damage_data.gd:146-151`（`_apply_cfg` 的 `n.get_path()`）、`script/damage_data.gd:194-200`（`from()`）、`script/heal_data.gd:43-46`；报错栈 `damage_data.gd:148 ← _fill ← mashiro_ps.gd:141 ← GameEvents.emit_enemy_damage_taken ← health_component._take_damage_internal ← health_component.take_damage ← mashiro_sniper_bullet.add_damage_data ← GameEvents.emit_global_time_count ← test_room._on_timer_timeout`；正常对照 `scenes/update_item/winnipesaukee_stone.gd:44-53`、`scenes/update_item/cherino_matryoshka.gd:33-43`（先同步 `add_child` 再 `fill`）。修复：`damage_data.gd`/`heal_data.gd` 对 `get_path()` 加 `is_inside_tree()` 守卫（未入树不再调 `get_path()`，`hit_box_center` 仍照常取）；`scenes/player/mashiro/cross_bullet.gd:20-23`（`active_state()` 入树后补 `damage_data.source_node = get_path()`，使新建分支的 `source_node` 与复用分支一致）。测试 `tests/test_damage_data.gd`（5/5）；`game_eval` 验证未入树 `source_node==""`、入树 `=="/root/EvalSrcNode2"` 且无错误日志。
- Notes / 说明: **现象**：Mashiro PS 处刑弹生成时每帧刷 `<C++ 错误> Condition "!is_inside_tree()" is true. Returning: NodePath()`（一屏）。**根因**：`ins` 用 `call_deferred("add_child")` 延迟入树，同一帧的 `DamageData.fill` 因 `"node": ins` 触发 `damage_data.gd` 的 `n.get_path()`——`Node.get_path()` 要求节点在树内，否则打印该 C++ 错误并返回空 `NodePath`。`cross_group.size() <= 30` 期间每次触发都走新建分支故持续刷屏；>30 复用已入树实例不报错。**修法**：① 构建器对 `get_path()` 加 `is_inside_tree()` 守卫，未入树则 `source_node` 留空（与旧行为等效，仅免红字；`node` 键保留，`hit_box_center` 仍照常取 `n.global_position`）；② 需要 `source_node` 指向自身的生成物（子弹/爆炸/处刑弹），在 `active_state()`（deferred 入队顺序保证 `add_child` 先于 `active_state`，此时已入树）补 `damage_data.source_node = get_path()`。**通用教训**：`DamageData`/`HealData.fill({node})` 与 `.from(node)` 会调 `Node.get_path()`，传入的节点必须已 `add_child`；凡 `call_deferred("add_child")` 之后立刻 `fill(..., node=自身)` 都踩同一坑。
- Source / 来源: code + test
- Date / 日期: 2026-10-02

### [Bullet] erosion_tower 激光逐 tick `get_overlapping_areas()` → 玩家跳出/跳跃后仍持续掉血；改边沿事件 + `monitorable` 过滤
- Evidence / 证据: `scenes/bullet/laser_bullet.gd:95-119`（`add_damage` 遍历 `_contacts`、过滤 `is_instance_valid`/`monitorable`；`_on_hit_box_area_entered/_on_hit_box_area_exited` 维护集合；`_seed_contacts` 激活时一次）、`:71-83`（`laser_shoot` 清空+seed、`laser_end` 清空）；对照 `scenes/bullet/player_laser_beam.gd:333-362`（同模式）；`script/hurt_box.gd:30-37`（`set_dodge` 切 `monitorable`）；`script/player.gd:324`（跳跃 `set_dodge(true)`）。
- Notes / 说明: **现象**：erosion_tower 激光在玩家跳出范围（含跳跃闪避）后仍持续造成伤害。**机制**：旧实现每 0.1s tick 用 `hit_box.get_overlapping_areas()` 实时取重叠——Rapier2D 下该列表会**残留**（`LEARNINGS` 321/463），且代码未过滤 `monitorable`；玩家跳跃 `set_dodge(true)` 置 `monitorable=false` 能挡新重叠但**不清既有重叠**，于是已与光束重叠时跳跃/走开仍被结算。**修法**：改为边沿事件 —— `HitBox.area_entered/exited` 维护 `_contacts`（只收 `HurtBox`），`laser_shoot()` 清空后做一次 `get_overlapping_areas()` 种子查询补「激活瞬间已重叠不补发 `area_entered`」，`laser_end()` 清空（淡出禁用形状、Rapier 不补发 `area_exited`）；`add_damage()` 遍历集合，先 `is_instance_valid`、再 `if not hurtbox.monitorable: continue`，最后 `emit`。与 `player_laser_beam` 统一。**通用教训**：持续判定某 Area 是否重叠不要依赖 `get_overlapping_areas()` 轮询，优先边沿事件，并在结算处过滤目标的 `monitorable`（残留重叠不会因 `monitorable` 变化而清除）。
- Source / 来源: user + code
- Date / 日期: 2026-10-03
- SUPERSEDED: 2026-10-10 边沿事件方案对「跳跃/闪避躲出」不成立（`monitorable` 切换不补发 `area_exited`，接触集合残留），已改为**每结算 tick 用 `intersect_shape` 即时查询**；见下方同日新条目。旧结论中「不要依赖 `get_overlapping_areas()` 轮询」仍成立，但改用 `intersect_shape`（即时空间查询，非缓存列表）后不再需要边沿事件集合。
### [Perf/UI] 伤害数字频率设置：手动档=上限，FPS 自适应只降不升；滑条触屏需自映射
- Evidence / 证据: `script/Game.gd`（`damage_text_freq` 默认 4，`save_config`/`load_config`）、`scenes/manager/PoolManager.gd`（`get_text_tick_skip()` = `max(_freq_ceiling_skip(), _text_tick_skip)`，`_freq_ceiling_skip()` 手动档 0/1/2/3/4→0/4/3/2/1）、`script/enemy_hurt_floating_text.gd`（`skip<=0` 清 `_pending` 停字，防 `0>=0` 每 tick flush）、`ui/game_option.tscn` Graphics 第 3 行（`DamageFreq` + `DamageFreqValue`）、`script/game_option.gd:_on_damage_freq_value_changed`、`ui/damage_freq_slider.tscn`/`ui/damage_freq_slider.gd`（触屏 `_apply_touch` 按 x 比例吸附）、`project.godot`（`pointing/emulate_mouse_from_touch=false`）
- Notes / 说明: 设置项语义定为「上限频率 + 自动只降」：手动档映射到 `ceiling_skip`（最高=1…低=4），最终 `final_skip = max(ceiling, FPS 自适应档)`，默认档=最高/1 时退化为纯自适应。滑条吸附 5 档（0/25/50/75/100%，`step=1`、`max=4`）。**坑**：① `skip=0`（关闭）必须让消费者提前 `return` 并清 `_pending`，否则 `mini(accum+1,0)=0` 且 `0>=0` 每 tick 都 `_flush`。② 滑条触屏：项目关闭了 `emulate_mouse_from_touch`，`HSlider` 原生只认鼠标，触屏须在 `gui_input` 回调里按 `local_x/size.x` 映射到值（**不要** override `_gui_input`，会顶掉原生鼠标拖动；用 `gui_input.connect` 叠加）。③ 桌面鼠标 + 触屏两条路径共用 `value_changed` → `script/game_option.gd` 写盘，`setting_status()` 用 `set_value_no_signal` 回填避免开面板即存盘。手动档在移动端同样有效（分辨率那种「桌面专属」限制不适用）。
- Source / 来源: user + code
- Date / 日期: 2026-10-03
### [Perf/UI] 特效频率设置：固定类全局间隔 + 跟随类按 body 去重；拦截即需 idle_state
- Evidence / 证据: `script/Game.gd`（`effect_freq` 默认 4，`save_config`/`load_config`）、`scenes/manager/PoolManager.gd`（`_fx_manual_mult`/`_fx_fps_mult`/`_fx_interval_ms`/`fx_allowed`/`fx_allowed_body`/`_fx_follow_allowed`，`spawn_fx` 入口 `effect_freq_off` + body 去重，`FX_BASE_MS`）、`script/health_component.gd:149`（受击闪白 `fx_allowed_body(&"hit_flash_white", owner)`）、`scenes/bullet/hit_flash.gd:active_state`、`scenes/bullet/bullet_smoke.gd`/`bullet_smoke_2.gd:smoke_anim`、`script/explosion.gd:shoot_particles`、枪口调用点（`player_gun.gd`/`enemy_gun.gd`/`enemy_gun_5/7/8.gd`/`tank_gun_1.gd`/`goliath.gd`/`charge_laser_gun.gd`/`turret_summoned.gd`/`luminous_nova.gd`）、`scenes/update_item/ink_cartridge.gd`、`ui/game_option.tscn` Graphics 第 4 行、`script/game_option.gd:_on_effect_freq_value_changed`
- Notes / 说明: 设置项 `Game.effect_freq`（0=关 / 1=×4 / 2=×3 / 3=×2 / 4=×1，默认 4），最短间隔 = `基准间隔 * 手动系数 * FPS 系数`，FPS 系数只增（复用伤害数字的 `_fps_ema`）。**两种粒度**：固定类（枪口/命中火花/受击闪白/子弹烟/爆炸/地面涂装）用 `fx_allowed(category)` 全局每类一个间隔；按实体类（受击闪白、燃烧/中毒/恶寒/策反/蒸汽）用 `fx_allowed_body(category, body)` 按 `[category, body_id]` 记录，避免多敌人互相挤占。跟随类只在 `PoolManager.spawn_fx()` 内拦：`effect_freq==0` 跳过；同一 body 已有同类 FX（扫池 `is_idle==0 and target==body`）则跳过，再走 `FX_FOLLOW_BASE_MS=200`；**无需改调用点**（`enemy_buff_manager.gd:134/150/158` 每 DOT tick、`entity_ENEMY.gd:274` 每次策反都会调 `spawn_fx`，是高频源）。**坑**：① 不能只改 `PoolManager.get_pool()` 返回 null 来节流——大量调用点对 `null`/非空闲的处理是**再实例化一个**，会绕过节流；必须在调用点或特效脚本入口显式判。② FX 节点 `is_idle` 初值不统一（`hit_flash`=1，`bullet_smoke`/`shoot_flash_2`=0），在 `active_state()`/`smoke_anim()` 内「拦截即不播」时**必须调 `idle_state()`**，否则节点永久占池槽。③ `damage_text_freq` 的档位词 `damage_freq_off/low/mid/high/max` 可复用于特效面板，只需新增 `option_effect_freq`。
- Source / 来源: user + code
- Date / 日期: 2026-10-03
- SUPERSEDED: 2026-10-03 受击闪白改为**独立设置** `Game.hit_flash_freq`（`config.ini [game]`，默认 4），由 `PoolManager.hit_flash_allowed(body)` 控制（基准 `HIT_FLASH_BASE_MS=60`、按实体 `_fx_body_last_ms`、`_fx_manual_mult_of(Game.hit_flash_freq) * _fx_fps_mult()`），**不再**走 `effect_freq`/`fx_allowed_body`；`FX_BASE_MS` 已移除 `&"hit_flash_white"` 条目。解耦后 `effect_freq=0` 时闪白仍按自身档位，`hit_flash_freq=0` 才停。UI Graphics 第 5 行 `HitFlashFreq`，key `option_hit_flash_freq`；`_fx_manual_mult()` 重构为 `_fx_manual_mult_of(v)` + 无参包装。
### [UI] option GAME 面板套 ScrollContainer：需包一层 Control 内容层；reparent 会改脚本里的节点路径
- Evidence / 证据: `ui/option.tscn`（`Node2D2/Scroll` ScrollContainer + `Node2D2/Scroll/Content` Control；`Graphics`/`Sounds` 移入 Content；`vertical_scroll_mode=3`、`horizontal_scroll_mode=0`、脚本 `res://script/ScrollBox.gd`）、`ui/option.gd`（41 条 `Node2D2/Graphics/` → `Node2D2/Scroll/Content/Graphics/`）
- Notes / 说明: GAME 面板（`Node2D2` = Graphics + Sounds）行数多到接近装满时，套一个纵向 `ScrollContainer` 即可保持绝对排版不变。要点：① ScrollContainer 的**直接子必须是 Control**（这里是 `Content`，`custom_minimum_size` 决定滚动范围；其实 Node2D 子节点不参与 min-size 计算）；原 `Graphics`/`Sounds`（Node2D）挂到 `Content` 下，局部变换保持（(0,0)/(0,88) 不变）→ 视觉排版一致。② **`Scroll.offset_top` 要设 0**（不是可视区顶部 20）：若设 20，`Content` 的原点下移 → 所有设置整体下移 20px；顶部 20px 由更晚绘制的根 `ColorRect2` 盖住即可。③ ⚠️ 编辑器 reparent 后，`.tscn` 底部 `[connection from="..."]` 会**自动**更新（本次已验证），但 `option.gd` 里的字符串路径**不会**，必须整体替换（`replaceAll`）。④ 触屏拖拽必须复用 `script/ScrollBox.gd`（`extends ScrollContainer`，自实现 `InputEventScreenTouch/Drag` + 鼠标拖拽）；项目 `pointing/emulate_mouse_from_touch=false`，ScrollContainer 原生只认滚轮/滚动条拖拽。滚轮原生可用。⑤ 在滑条/开关上拖拽由其自身捕获（不滚动），空白/标签（`mouse_filter=IGNORE`）处可拖拽滚动。⑥ 加设置行后记得调大 `Content.custom_minimum_size.y`。
- Source / 来源: user + test
- Date / 日期: 2026-10-03
- SUPERSEDED: 2026-10-03 GAME 页整体容器化（来源：user）——`Node2D2` 由 `Node2D`→`Control`（承载开合动画），`Content`→`VBoxContainer`，`Graphics`/`Sounds` 由 Node2D→`VBoxContainer`，各设置行改为 `HBoxContainer`（Label 固定宽右对齐 + 控件），`V-Sync` 改名 `VSync`，`Resolutions`+`ResolutionsTouchBlock` 包进 `ResolutionSlot`(Control) 叠放；`option.gd` 改用 `%唯一名` 访问（`%FullScreen`/`%Resolutions`/`%DamageFreq`…），`[connection]` 路径随之更新。上面「绝对排版/局部变换保持/`offset_top`」等结论不再适用。容器化后行距仍为 32px（实测 `Content=(588,380)`、Graphics/Sounds 行 y=0/29/57/85/113/141）。
- SUPERSEDED: 2026-10-04 选项菜单拆分（来源：user + test）——GAME 页从 `ui/option.tscn` 拆出为独立场景 `ui/game_option.tscn` + `script/game_option.gd`（`extends OptionMenu`），Controls 拆为 `ui/controls_option.tscn`；`option.gd` 精简为通用容器（仅整体开关动画 + 按 `GameEvents.menu_button` 的 `button_id`/子页 `option_id` 切换）。上面「`option.gd` 41 条路径整体替换」不再适用：路径与 `%唯一名` 现落在 `game_option.gd`（`%` 作用域是 game_option 自身实例，跨场景实例解析不到）；`MobileNotice` 移入 `game_option.tscn` 并改用 `global_position` 定位。子页基类 `script/option_menu.gd` 增 `shown` 守卫（未显示页 `menu_hide()` 直接返回，避免反向播放 `option_in` 闪现）。

### [Bullet] 墙面反弹按等距（64×32, 2:1）地面空间反射；子弹空闲关物理 + 朝向按需更新
- Evidence / 证据: `script/iso_projection.gd`（`to_ground`/`to_screen`/`ground_normal`/`bounce`）、`script/player_bullet.gd:158-167,199`、`scenes/bullet/normal_bullet.gd:135-153`、`scenes/bullet/megu_bullet.gd:33,63`、`scenes/bullet/mashiro_sniper_bullet.gd:72-73,91-92,152`、`tests/test_iso_projection.gd`
- Notes / 说明: 地图为等距投影（`main.tscn` TileSet `tile_shape=1`、`tile_size=64×32`，墙碰撞菱形 `points (0,8)(-32,-8)(0,-24)(32,-8)`），屏幕空间 `velocity.bounce(normal)` 与地面真实镜面反射不一致。改为 `IsoProjection.bounce`：`vg=M⁻¹v` → `ng=normalize(Mᵀn)` → `vg-2(vg·ng)ng` → `v=M vg`（M 列 = 等距基 `(1,0.5)/(1,-0.5)`，即 2:1）。菱形边法线 `(1,±2)` 映射到地面轴 `(1,0)/(0,1)`；验证 `(0,1)` 撞 `(1,-2)` → `(2,0)`（旧屏幕反射为 `(0.8,-0.6)`）。**只在反弹帧执行，无每帧开销**。**量产优化**：`PlayerBullet`/`SummonedBullet`/`mashiro_sniper_bullet` 的 `idle_state`→`set_physics_process(false)`、`active_state`→`true`，空闲子弹不再每帧空转（对齐 `entity_ENEMY`/`BuffCard`/`Line` 约定）；`normal_bullet` 删除每帧 `rotation = velocity.normalized().angle()`，改 `active_state` 定型 + `r_move`/反弹更新；`rotation = velocity.angle()` 去掉多余 `normalized()`；反弹缓存重复的 `get_collision_point()`。属性墙（`PropWallBody`）也按地面空间处理。⚠️ `megu_bullet.active_state` 不调 super，需自行 `set_physics_process(true)`；`PlayerBullet` 子类若重写 `idle_state`/`active_state` 不走 super，必须同步物理开关与 `rotation` 复位。
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Debug] 作弊菜单改为树暂停 + dev_mode 门控；暂停下靠 process_mode=ALWAYS 收输入
- Evidence / 证据: `ui/cheat_menu.gd`（`Game.dev_mode` 门控、`_set_pause` 走 `GameEvents.emit_pause_lock` + `get_tree().paused`、`_exit_tree` 兜底、`spawn_enemy` 用 `spawn_anim` 且置实例 `process_mode=ALWAYS`、`script/spawn_anim.gd:idle_state` 归还池时复位 `PROCESS_MODE_INHERIT`）、`ui/cheat_menu.tscn`（根 `process_mode=3`、居中 `Dim`+`Panel`、15 张 `test_enemy_card`）、`script/Game.gd`（`dev_mode` 读写 `config.ini`）、`script/player_health_component.gd:38`（`is_invincible` 早退连治疗一起挡）
- Notes / 说明: 打开作弊菜单 = 暂停（不再走 `GameEvents.request_slow`），根 CanvasLayer `process_mode=3` 才能在 `paused` 下收 `_unhandled_input` 与点按钮；暂停写者按「暂停语义」约定配对 `emit_pause_lock`，避免与暂停菜单互踩。`PlayerHealthComponent.is_invincible=true` 时 `take_damage` 会连治疗一起早退，故「无敌下回血」需在调统一治疗接口前后临时关闭再恢复。暂停下生成敌人：`spawn_anim` 的生成信号在 AnimationPlayer 0.8s method track，需给该实例 `process_mode=ALWAYS` 才会在暂停中播放并落地（生成的敌人本体仍随树暂停静止）。入口经 `Game.dev_mode` 门控（默认 false，手动改 `config.ini [game] developer_mode`）。
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Combat] `HealthComponent` 被玩家召唤物复用：全局增伤/秒杀类作弊必须按受击者阵营门控
- Evidence / 证据: `script/health_component.gd:_take_damage_internal`（`Game.one_hit_kill` + `Faction.of_entity(owner)==ENEMY_SIDE` 门）、`script/summoned_follower.gd:24`（`@onready var health_component = $HealthComponent`）、`scenes/summoned/mobu_trinity/mobu_trinity.tscn:423`（`HealthComponent`）、`script/Game.gd`（`one_hit_kill` 运行时开关，不写 config）
- Notes / 说明: `HealthComponent` 不只敌人用：玩家召唤物 `SummonedFollower`/`mobu_trinity` 也挂它。任何「玩家对敌一击必杀/全局增伤」类作弊若在 `HealthComponent` 内**无条件**改写 `final_damage`，会把玩家自家召唤物一起秒掉。正确做法按受击者阵营门控：`Faction.of_entity(owner)`（敌人携带 `faction`；玩家/召唤物/策反单位靠组兜底，见 `script/faction.gd`）等于 `Faction.ENEMY_SIDE` 才生效。敌→敌友伤已在 `_is_friendly_fire` 早退，故无需再判来源阵营。玩家本体走独立脚本 `PlayerHealthComponent`，不受影响。
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Camera] 屏幕震动必须走独立偏移，不能与 `_process` 争写 `position`
- Evidence / 证据: `scenes/game_camera/gamecamera.gd:20-22`（`shake_offset` 声明）、`:57-66`（`_process` 每帧写 `self.position = base + shake_offset`）、`:71-89`（`shake_screen` 只 tween `shake_offset`、结束归零）；相机为玩家子节点（如 `scenes/player/momoi/momoi.tscn:420` instance `res://scenes/game_camera/gamecamera.tscn`），且开 `position_smoothing_enabled=true`（`scenes/game_camera/gamecamera.tscn:59-60`）。
- Notes / 说明: **旧实现** `shake_screen` 用 tween 把 `self.position` 从当前值动画到「当前值+随机偏移」，而 `_process` 每帧又按 crosshair 重写 `self.position` → 两路互相覆盖，`position_smoothing` 再平滑一次，表现为战斗（尤其高射速、每发都 `emit_shake_screen`，`script/player_gun.gd:125`）时整屏随机抖动/回弹（玩家会描述成"像网络丢包"）。**修法**：震动只写独立 `shake_offset`，`_process` 里 `position = base + shake_offset`，两路合成唯一写入点；`shake_screen` 结束 `shake_offset = Vector2.ZERO`。**通用规则：任何每帧写相机 transform 的逻辑都必须与 `_process` 的写入口合并，避免多写者互相覆盖。**
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Perf] 移动端帧率对齐 60Hz + 启用 shader cache/baker（项目无 2D 物理插值）
- Evidence / 证据: `script/Game.gd` `_ready()`（`if OS.has_feature("mobile"): Engine.max_fps = 60`）；`project.godot` `[rendering] shader_compiler/shader_cache/enabled=true`；`export_presets.cfg` Android `[preset.1.options] shader_baker/enabled=true`；实体在物理帧移动（`script/player.gd:235`、`script/entity_ENEMY.gd:182`），相机在 `_process`（`gamecamera.gd:57`）。
- Notes / 说明: 项目未开 2D 物理插值（`project.godot` 无 `physics/common/physics_interpolation`）。高刷屏（90/120Hz）渲染帧率高于物理 60Hz 时，2D 无插值会产生 judder；移动端限 `Engine.max_fps=60` 使两者对齐（桌面不受影响，高刷上限降到 60）。`shader_cache`/`shader_baker` 用于减少战斗中新特效首次出现时的运行期 shader 编译顿挫（原均为关闭）。**属"部分机型反馈但本地无法复现"下的盲修措施，未在问题机型实测**；若无效需按"渲染器/`hdr_2d`/物理插值"继续排查。
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Item] energy_supplement 致命保护依赖「扣血信号早于受击信号」的时序，且需在装备时主动 arm
- Evidence / 证据: `scenes/update_item/energy_supplement.gd`（`_setup` 现主动调 `player_hp_count()`；`fatal_damage_health` 开头加 `max_hp<=1` 早退）、`script/player_health_component.gd:120-121`（`stats.hp -= final_damage` 同步发 `hp_changed`，随后才 `emit_player_hurt_hp`）、`script/PlayerData.gd:361,416-417`（玩家 `max_hp` 仅此一处赋值，改变时必补发 `hp_changed`）。
- Notes / 说明: 保命效果靠「`hp_changed` 先跑 `player_hp_count`（`max_hp==1` 则断开/不连）→ 之后 `player_hurt_hp` 才可能触发 `fatal_damage_health`」来保证 `max_hp==1` 不生效；该顺序在 `take_damage` 中成立（hp setter 的 `await` 在 `hp_changed.emit()` 之后，不阻断本次 caller 继续）。**旧坑**：原实现只在 `_setup` 连接 `hp_changed`、不主动调用，满血拾取后需「掉血→回满」才会 arm `fatal_damage_health`。**加固**：`fatal_damage_health` 自身也判 `max_hp<=1`，不再单靠断开时序。
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Combat] AOE 范围攻击 `area_exited`/`body_exited` 回调解引用参数前必须 `is_instance_valid`（2026-09-30 加固的遗漏清单）
- Evidence / 证据: 2026-09-30 条目（本文件 `[Combat] area_entered/exited 回调解引用 .owner 前必须 is_instance_valid`）只加固了 `fire_damage`/`fire_field`/`enemy_fire_field`/`renge_fire_field`/`kitchen_knife`/`player/utaha/melee`/`kasumi_drill`；本轮补齐遗漏：`scenes/update_item/murky_hand_scythe_icon.gd`、`spiked_shell.gd`、`scenes/bullet/{mashiro_sniper_bullet,chill_ring,enemy_missile_1}.gd`、`scenes/debuff/{fire_diffuse,poison_diffuse}.gd`、`scenes/update_item/{shiro_missile,shiroko_drone_icon_2,cathedral_candle}.gd`、`scenes/player/{utaha,hoshino,chinatsu}/*melee.gd`、`script/{kick,entity_ENEMY}.gd`。
- Notes / 说明: 与 `kasumi_drill` 同因——目标单位在 AOE 判定框仍重叠时被释放（回合清场 / `queue_free` / 召唤物死亡 / 油桶击毁），`area_exited`/`body_exited` 可能带着已释放的 `Area2D`/`body` 进回调，任何 `is`/`is_in_group`/`.owner`/`.stats` 访问都是 use-after-free。修法：每个 `*_entered/*_exited` 回调开头 `if x == null or not is_instance_valid(x): return`；组内循环（`fire_diffuse.fire_dot_add`、`poison_diffuse.poison_dot_add`/`sort_enemy`、`shiro_missile`/`shiroko_drone_icon_2.sort_enemy`）反向遍历剔除失效项（原只用 `!= null`，但 freed 引用在 GDScript 里非 null，会在取 `.enemy_buff_manager`/`.stats` 时崩）。另修 `poison_ring.apply_poison_dealt`：闭包前先 `on_damage_dealt.clear()` 且判空 `victim`/`enemy_buff_manager`（`kikyou_doll.add_poison_ring` 复用分支原先原地改 `damage_data`、不清闭包 → 每次激活叠加施毒）；`murky_hand_scythe_icon`/`mashiro_sniper_bullet` 的 `on_damage_dealt` 闭包补判空。
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Refs] 非 AOE 的悬空引用/守卫补全：召唤物索敌、`get_node(body_path)`、软碰撞、链式取节点
- Evidence / 证据: 召唤物 `script/summoned.gd`（`_on_area_2d_body_entered/exited` 加 `is_instance_valid`；新增 `_prune_enemy_body()`，`sort_enemy` 调用它）、`script/summoned_follower.gd:78`、`script/turret_summoned.gd:54`（`tick_physics` 开头 prune）、`scenes/update_item/shiroko_drone_icon_2.gd:56`、`scenes/update_item/shiro_missile.gd:152`；软碰撞 `scenes/summoned/mobu_trinity/soft_collision.gd`（entered/exited 守卫 + `_physics_process` 反向剔除）；`get_node(body_path)`→`get_node_or_null` + 判空：`scenes/player/{momoi/MomoiPS,midori/MidoriPS,utaha/UtahaPS,mashiro/mashiro_ps,tsurugi/tsurugi_ps}.gd`、`scenes/update_item/{matcha_ramune,mint_chocolate_parfait,shrapnel_bullet,black_ninpero,flammable_explosives,fuel_tank,red_ninpero,peroro_wheel,solvent_extraction_set,winnipesaukee_stone,ink_cartridge}.gd`；范围回调守卫：`scenes/player_support/kei/kei_as.gd`、`scenes/manager/summoned_manager.gd`、`scenes/item/hold_pickup_item.gd`、`scenes/item/pyroxenes.gd`、`scenes/ball.gd`、`script/props/prop_interact.gd`；链式取节点：`script/support_data.gd:72`（`GameUI.support_box` 分步 + `get("support_box")`）、`ui/ark_of_Shittim/arona.gd:137`（`SoundManager.talk` 分步 `get_node_or_null`）。
- Notes / 说明: 承接同日 AOE 守卫条目，把同类模式铺到非 AOE。①**召唤物索敌数组** `Summoned.enemy_body` 只在 `body_exited`/`converted_changed` 时移除，敌人被 `queue_free` 而边沿事件未补发时会残留 freed 引用；`enemy_body[0].global_position`（`summoned_follower`/`turret_summoned`）与 `sort_enemy` 比较器都会 use-after-free，故抽 `_prune_enemy_body()` 在排序与取值前剔除。②**`get_node(body_path)`**（`enemy_damage_taken` 回调携带 `owner.get_path()`）在同步链内一般有效，但延迟 DOT / 跨帧复用会让路径失效，`get_node` 找不到会先 `push_error` 再返回 null → `.enemy_buff_manager`/`.health_component` 崩；统一 `get_node_or_null` + 判空早退（`aris_armed_ps`/`ako_ps` 本已如此，本次对齐其余）。③**链式取节点**（`a.get_node(b).get_node(c)`）中间任一为空即崩，改分步 `get_node_or_null` 判空。④`PropInteract`/`hold_pickup_item`/`pyroxenes`/`ball` 的 body 回调只判 `!= null`，freed 引用非 null → 补 `is_instance_valid`。
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Perf] Boss 血条 Tween 复用；`locale_font` 非越南语早退
- Evidence / 证据: `scenes/enemies/boss/boss_hp.gd`（新增 `_hp_tween`/`_hp2_tween`，`update_hp` 先 `kill()` 再用；文本 `str(stats.hp) + "/" + str(stats.max_hp)`）；`script/locale_font.gd:53`（`_on_node_added` 首行 `if not is_vietnamese(): return`）。
- Notes / 说明: ①`EnemyStats.hp` setter 有 `hp_change_cd` 节流（`script/EnemyStats.gd:102-110,121-129`），`hp_changed` 约每 0.1s 一次（首击/死亡即时），故 Boss 血条并非每击重建 Tween，而是每 0.1s 分配 2 个 `Tween`（0.05s/0.3s，旧的不 `kill` 会短暂并存）；改为持有成员 Tween、`is_valid()` 时 `kill()` 后重设，消除重复分配。②`locale_font._on_node_added` 原对**所有**新节点执行：文本控件判断 + `minimum_size_changed.connect` + `set_meta`，再 `_apply_node`；战斗中新子弹/飘字/特效高频新增，非越南语时这些全是纯浪费。加 `is_vietnamese()` 首行早退后，非 vi 直接返回；`apply()` 全树还原不变，切回非 vi 时旧 `minimum_size_changed` 连接触发 `_restore`（records 空即早退）无害。
- Source / 来源: user + code
- Date / 日期: 2026-10-03

### [Rendering] 长发 SubViewport 为「并集轮廓」服务；缩尺寸须按裁剪不变式同步改 4 处
- Evidence / 证据: `scenes/player/yuzu/yuzu.tscn`（`CanvasGroup/SubViewportContainer/SubViewport/Hair`；容器 `offset -320,-202,320,158`、`pivot (320,180)`、`SubViewport 640x360`、`Hair (320,180)`）；同型共 13 处：`scenes/player/{yuzu,tsurugi,serika,kasumi,iori,nonomi,hoshino,hina,hasumi,aris,aris_armed}.tscn` + `scenes/player_support/kei/kei_summoned.tscn`；绘制 `scenes/player/yuzu/yuzu_hair.gd:32-76`、容器材质 `shaders/sprite_outline.gdshader:10-20`。
- Notes / 说明: 头发用 `_draw()` 画多股圆/多边形，`sprite_outline` 需采样纹理，故先栅格化到 `SubViewport`（`transparent_bg`、`use_hdr_2d`、`render_target_update_mode=4` UPDATE_ALWAYS、1:1、`stretch=false`）再对**并集**轮廓描边——**去掉 SubViewport 会让股与股重叠处露出内部黑线**（故不能简单换 Line2D）。`640x360` 只是屏幕尺寸模板，头发实际仅占玩家原点附近约 64×48px；缩到 `128×128` 像素量降 ~14×，并连带缩小 `CanvasGroup` 的 `screen_outline` pass。等价裁剪不变式（玩家屏幕位置严格不变）：`SubViewport.size=(W,H)`；容器 `offset=(-320+x0, -202+y0, -320+x0+W, -202+y0+H)`；`pivot = Hair.position = (320-x0, 180-y0)`。本次取 `x0=256,y0=116` → `size(128,128)`、offsets `-64,-86,64,42`、pivot/Hair `(64,64)`。`TEXTURE_PIXEL_SIZE` 随 SubViewport 变但显示 1:1，描边像素宽不变。
- Source / 来源: code + test
- Date / 日期: 2026-10-04

### [Bullet] 命中结算改「按目标冷却」：形状常开 + 自检 HurtBox，兼顾不漏敌与低速多段
- Evidence / 证据: `script/hit_box.gd`（`_enter_tree` 兜底 `damage_data`；`manages_own_hits`/`rehit_interval_seconds`（秒，默认 0.1）；`_setup_self_hits`/`_on_self_hit_area_entered`/`_on_self_hit_area_exited`/`_clear_self_hits`/`_tick_self_hits(delta)`/`_emit_self_hit`，`_hit_contacts` 懒初始化）、`script/hurt_box.gd:39-48`（`_on_area_entered` 跳过 `manages_own_hits` 的 HitBox + `damage_data == null` 早退）、`script/player_bullet.gd`（`_ready` 置 `manages_own_hits=true` + `_setup_self_hits()`；`_physics_process` 调 `_tick_self_hits(delta)`；删 `hit_shape_cd_frames`/`cd_time`/`close_shape` 判定逻辑）、`scenes/bullet/normal_bullet.gd`（同）、`scenes/bullet/normal_bullet.tscn:19`（`collision_mask 0→16384`）、`scenes/bullet/megu_bullet.gd`（`_ready`/`active_state` 调 `super`）、`scenes/bullet/yuzu_bullet.gd`（`does_direct_hit()=false` 榴弹不直击 + 爆炸判空）、`tests/test_bullet_self_hits.gd`（10/10；编辑器 @tool 下 `GameEvents`/`ExtensionHooks` 为占位 autoload，测试置 `HitBox.runtime_self_hit_notify=false` 隔离运行时通知）
- Notes / 说明: **不得用「命中后整体关 `CollisionShape2D`」做冷却**——单形状无法区分「同一敌人/另一个敌人」，关的那一帧对全部敌人失明，高速穿透弹（Aris `bullet_speed=1200`）会整段穿敌不掉血（见上方 2026-09-28 条目的 SUPERSEDED）。改为玩家侧直击弹（`PlayerBullet`/`SummonedBullet`）**自检**：`PlayerBullet._ready` 用 `does_direct_hit()` 钩子判定是否开启（迫击炮弹 `PlayerMortarBullet` 覆写为 `false`——榴弹原本 `collision_mask=0` 且不在敌 HurtBox 检测层内，**只有落点爆炸伤害**，切自管理时必须显式排除，否则会凭空产生直击伤害）；自身 `area_entered/exited` 维护 `HurtBox` 集合，进入**即刻**结算一次，之后按 `rehit_interval_seconds`（秒，默认 0.1；0=本次接触只命中一次）在 `_tick_self_hits(delta)` 重复结算。**形状全程常开** → 不漏其它敌人；同目标冷却 → 保留低速多段。`HurtBox._on_area_entered` 对 `manages_own_hits` 早退避免双结算；`EnemyBullet`（打玩家）**不**自管理，仍走目标侧，保留玩家无敌帧（`set_invulnerable` 只切 `monitoring`，来源侧会绕过，见本文件 2026-09-28 条）。性能：`_hit_contacts` 懒初始化、每帧仅一句空表早退、不做逐帧 `get_overlapping_areas()` 轮询，且省掉命中后每次 `call_deferred` 形状开关；净开销可忽略。**通用教训**：「对同一目标重复、对其它目标不遗漏」的判定必须按目标记录状态，不能靠全局开关近似；且玩家侧自检会绕过 `monitoring` 档无敌帧，敌方攻击勿沿用。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-04

### [UI] 共享 `floating_text` 池 + 「相同则跳过」样式缓存 → 敌人伤害数字残留拾取物的白色/24号
- Evidence / 证据: `ui/floating_text.gd`（`set_style` 原用 `_last_color`/`_last_size` 缓存，值相同则跳过写入）；**触发点**：`scenes/item/medical_kit.gd:11-19`（玩家**满血**拾取医疗包时给补偿金币浮字，`play_anim` 白→粉 + 直接 `label.set(font_size, 24)`，绕过 `set_style`）。运行期实证（`game_eval` 遍历 `PoolManager.pool["floating_text"]`）：某实例 `_last_color=d834b1`/`_last_size=16`，而 Label 实际 `#ffffff`/`24`。同类直写点（已统一改走 `set_style`）：`scenes/item/pyroxenes.gd`、`script/player.gd:add_text`、`scenes/main/main.gd:91-92`、`scenes/update_item/{chocolate_coin,intact_atlantis_medal,effective_cure,murky_hand_scythe}.gd`、`scenes/debuff/{fire_diffuse,poison_diffuse}.gd`。
- Notes / 说明: `floating_text` 是**共享对象池**，`enemy_hurt_floating_text`/`PoolManager.add_text`/拾取物/`player.add_text` 混用。当某写入者**绕过 `set_style`** 直接改 `Label`（或 `play_anim` 用动画 method track 改色），`set_style` 的 `_last_*` 缓存即失真；随后敌人伤害浮字调 `set_style(粉,16)` 因「与缓存相同」被**跳过** → 实际显示上一条残留的**白色/24 号**（Yuzu 榴弹战斗中「打着打着时不时白字、字号偏大」的根因；用户实机确认触发点为**满血拾取医疗包**。`damage_data` 本身完全正常，全是 `[bullet_damage,explosion_damage]`）。修法：`set_style` 改为**始终写入**（移除跳过快取），并把全部直写点（含医疗包）统一改走 `set_style`。回归测试 `tests/test_floating_text_style.gd`。**通用教训**：跨系统共享的对象池，凡被「缓存上次值以跳过写入」优化的 setter，都会因**其它写入者绕过该 setter**而失效——共享池上的样式 setter 必须无条件写入，或把「上次值」失效绑到回池/`reset`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-04

### [Mod/UI] MOD 管理迁入 option 页签：排序持久化 + 图标 + 共享 toggle；页签列会遮挡左对齐内容
- Evidence / 证据: `script/mod_manager.gd`（`ORDER_PATH=user://mods/mods_order.json`；`_load_order`/`_save_order`/`get_order`/`set_order`；`_cmp_order` 先用户序、后 `(load_order,id)`；`list_mods()` 返回 `icon` 并按 `_cmp_order` 排序；`_mod_icon_path` 先 loose `rec.dir/icon.png` 再 `manifest.icon`）；`script/mod_option.gd`（`extends OptionMenu`；行 = SelectBar + `TextureRect` 图标 + Label + `ui/option_toggle.tscn`；`_input` 手写鼠标/触屏拖动 + `_target_index`/spacer 换位；`_move_selected` 上下箭头；`Image.load`→`ImageTexture`）；`script/option_toggle.gd`（`set_on(v, animate)`，`seek(current_animation_length, true)` 无动画定位）；`ui/mod_option.tscn`（`Scroll.offset_left=122` 避开页签列、`Content.size_flags_horizontal=3`）；`ui/option.tscn`（`menu_box/Mod` + 第三个 `option_button.tscn`，`button_id=option_mod`）；`scenes/main/menu_screen.gd`（删自建 MOD 按钮，`ensure_unlocked()` 移入 `_ready`）；`ETN_localization.csv`（`mod_*`）。
- Notes / 说明: ① **页签列遮挡**：`ui/option.tscn` 内页签列 `Node2D`（含 `ColorRect` x 0..139）排在 `menu_box` **之后** → 绘制在子页内容之上；GAME 页靠 Label `horizontal_alignment=2`（右对齐）+ `offset_transform_position` 规避，**左对齐的新子页**必须把 `Scroll.offset_left` 推到页签列（≈139）之外，否则开头被裁（本次 MOD 提示首两字消失即此因）。② `user://` 下的裸 PNG **不能用 `load()`**（未 import），须 `Image.load(path)`→`ImageTexture.create_from_image()`；`res://`（pck 内）才走 `load()`。③ 用户排序只作**同级 tie-break**，依赖/冲突仍由拓扑强约束；且与启停一样**重启生效**（pck 不可卸载）。④ 小坑：`@onready var x: Button = %UpBtn` 若节点实为 `TextureButton` → 运行时 `Trying to assign value of type 'TextureButton' to a variable of type 'Button'`（断点），类型须写 `TextureButton`/`BaseButton`。⑤ 共享 `ui/option_toggle.tscn` 抽自 game_option 的开关三件套，仅 MOD 页使用（未重构 game 页）。
- SUPERSEDED: 2026-10-18 管理页改为分栏布局（Content 左 144、左侧分组列表/右侧详情），旧 `Scroll.offset_left=122`、`SelectBar` 与行内 tooltip 描述失效；页签列遮挡仍需保持内容左边界在 139 之外。（来源：code）
- SUPERSEDED: 2026-10-18 GAME 页改为卡片分区并复用 `ui/option_toggle.tscn`；GAME 不再靠 Label 右对齐 + `offset_transform_position` 规避页签列，内容统一从 x=150 起排；共享开关现同时服务 GAME 与 MOD，并补了 focus/`ui_accept`。（来源：code）
- Source / 来源: user + code + test
- Date / 日期: 2026-10-04

### [Extension] 本体扩展点用默认空 `Callable` 槽 + `intercept/notify` 守卫，未注入即单机零回归
- Evidence / 证据: `script/extension_hooks.gd`（autoload `ExtensionHooks`，`project.godot` 声明在 `ModManager` 之后）；接管点 `GameEvents.change_scene`、`GameEvents.emit_game_over`（附 `force_emit_game_over`）、`GameEvents.emit_round_upgrade_end`（附 `force_round_upgrade_end`）、`scenes/main/main.gd:first_round`（仅门控 `round_manager.first_round_start()`）、`script/health_component.gd:take_damage(damage_data, bypass_hook=false)`、`scenes/item/coin.gd:add_coin`、`script/Stats.gd`（玩家 `hp<=0` 且 owner 在 `"Player"` 组时问 `player_death_gate`）、`script/player.gd:set_downed_state/get_downed`、`scenes/main/menu_screen.gd`（`populate_menu_buttons`）。
- Notes / 说明: mod 系统只能注入内容资源 + 跑 `entry` 脚本（`mod_patch.gd` 只改注册资源字段），**无法在运行时改写/拦截既有方法**；故联机等需要改流程的能力必须由本体预留扩展点。设计约定：① 槽默认 `Callable()`，`intercept(cb,args)` 未注入返回 false、`notify(cb,args)` 未注入静默，本体行为与单机逐字节一致；② 接管类返回 true = mod 已接管，本体跳过默认分支（含 `clear_slow()` 一并交给 mod）；③ 需要「mod 绕过自身钩子再回投」的场景（伤害仲裁）留 `bypass_hook` 形参；④ `first_round_start_gate` **只**门控 `round_manager.first_round_start()`，client 仍需本地 `SupportData.game_add_support()`/`PoolManager.get_buff_box()`（对齐 coop 分支）。`ExtensionHooks` 必须声明在 `ModManager` 之后，但 mod `entry` 是 `call_deferred` 执行，届时所有 autoload 已就绪，注册时序无冲突。
- Source / 来源: user + code
- Date / 日期: 2026-10-05

### [Bullet] `ProjectileSpawner` 统一生成：顺序语义靠 `add_before_activate`/`deferred_add`/`pre_activate`/`post` 复刻，不能只抽「取池+入树」
- Evidence / 证据: `script/projectile_spawner.gd`（`spawn_core` 位置参数；`acquire(pool_id,scene)`；`notify_local`/`mark_remote`）；迁移点 `script/player_gun.gd`（add→emit→activate）、`script/bullet_launcher.gd`/`_2.gd`、`scenes/update_item/player_bullet_launcher.gd`、`scenes/bullet/launcher/formation_launcher.gd`、`script/turret_summoned.gd`、`scenes/{player,player_support,update_item,enemies,bullet,weapon}` 下的道具/PS/支援/敌人/激光生成点。
- Notes / 说明: 各生成点**入树/激活顺序不一致**：`player_gun` 是 `add→emit_player_shot_position→active_state`；`bullet_launcher`/`player_bullet_launcher`/`formation_launcher` 是 `active_state→add`；`bullet_launcher_2` 分支 2 与 `shiro_missile`/`mashiro_ps` 用 `call_deferred("add_child")`（且 `source_node=get_path()` 须在入树后）。统一抽骨架时必须：① `pre_activate` 在 **transform 之后、activate 之前** 执行，正好覆盖 `hit_box_center=global_position` 这类位置依赖（曾用 configure 会拿到未设置的坐标）；② `deferred_add` 时 `post` 也延迟（`Callable.call_deferred`，靠消息队列 FIFO 保证 add 先于 post）；③ `scale=Vector2.ZERO` 作「不改写缩放」哨兵（player_gun 的缩放由 `player.bullet_hit_damage` 回填）；④ 高频站点用缓存的 method `Callable`，避免每发 lambda/Dictionary 分配；⑤ 无法走 `spawn_core` 的特例（`mashiro_sniper_bullet` 用 `self.duplicate()`）用 `ProjectileSpawner.notify_local()` 手动触发通知，保证钩子覆盖率。⑥ `configure` 在入树前执行，**不得**访问新节点的 `@onready`/`_enter_tree` 子节点（如 `stone_bullet.hit_box`）——新实例此时为 `null`，会 `Invalid access ... on Nil`（`winnipesaukee_stone` 实测崩溃）；这类「入树后才可用」的初始化放 `pre_activate`（入树后、activate 前）。所有通知最终由 `spawn_core` 末尾统一触发 `ExtensionHooks.on_projectile_spawned`。
- Source / 来源: user + code
- Date / 日期: 2026-10-05

### [UI] MOD 菜单列表行名字被裁：`Label.clip_text=true` + 承载 `ScrollContainer` 不撑宽
- Evidence / 证据: `script/mod_option.gd:96,103`（`label.clip_text=true`、`text = name vVersion`）；`ui/mod_option.tscn:262-267`（内层 `ScrollContainer` 承载 `%List`，`horizontal_scroll_mode=3`）。实测（实例化 `ui/mod_option.tscn`）：单行时 `List.size=(59,24)`、`label.size=(1,17)` 名字不可见；`label.clip_text=false` 后 `List=(283,24)`、`label=(225,17)` 名字显示。
- Notes / 说明: `Label.clip_text=true` 会把 Label 最小宽度压成 0；`%List` 所在内层 `ScrollContainer` 实测**不会**把 `List`/行撑到容器宽（把 `horizontal_scroll_mode` 改成 `0`(DISABLED) 也未撑开），于是行按最小宽排版、名字 Label 被挤成 ~0 宽而被裁。修复：`_make_row()` 里 `label.clip_text=false`，让名字计入最小宽度（`List` 随最长名字变宽）。**别走改 `horizontal_scroll_mode` 的路，实测无效**。
- Source / 来源: code + test
- Date / 日期: 2026-10-05

### [Mod] 联机 mod 对齐联机版：新增本体 `ExtensionHooks` 通知槽与调用点
- Evidence / 证据: `script/extension_hooks.gd` 新增 `on_player_melee`/`on_player_reload`/`on_pyroxenes_gain`/`local_player_change_gate`；调用点 `script/kick.gd`（`kick_anim.play` 后）、`script/player_gun.gd`（换弹动画开始处，3 处）、`scenes/item/pyroxenes.gd`（`emit_pyroxenes_pick_up` 后）、`ui/character_test_menu.gd`/`ui/test_menu.gd`（free+re-add 前 `intercept` 守卫）。
- Notes / 说明: mod 无法拦截既有方法，故同步「近战/换弹/pyroxenes/换人」必须由本体在调用点 `ExtensionHooks.notify/intercept`。判定为参考死代码/无对应接口而**不接**：`mashiro_charge_state`（联机版无调用点）、`character_event`（本基无 mika/seia）、`register_test_room_target`（联机版无调用点）、`state` 状态机与 `update_network_remote_visual`（本基无）。另：本体 `test_room.tscn` 的 `BattleRoom` 无分组 → mod 侧按名兜底找房间中心；mod 侧对齐项详见 `mod_sdk/coop_mod/README.md`。
- Source / 来源: code + user
- Date / 日期: 2026-10-05

### [Mod] 远端镜像被本体 `test_room.reset_clear_unit` 清除 / 返回标题需彻底复位
- Evidence / 证据: `scenes/main/test_room.gd:56-73 reset_clear_unit()` 只保留 `"Player"` 组的 `PlayerRoot` 子节点；mod `coop_net.gd:spawn_remote_player` 把远端镜像移出 `"Player"`、加入 `"RemotePlayer"` → 测试房 `reset_data` 时被 `queue_free`。修复：新增 `_respawn_remote_players()` + `_schedule_respawn_remotes()`（进一局后 +0.3s/+0.9s 各补生）与 `_client_scene_ready` 时 host 补生；`_reset_run_state()` 用于返回标题/断线/重开。`--coop-devreset`（entry）触发 `GameEvents.emit_test_room_reset()` 后打印 `after-reset remotes`，实测 host/client 均 `remotes=1`。
- Notes / 说明: ① 远端镜像**不要**放进 `"Player"` 组（会让本体 `get_first_node_in_group("Player")` 取到远端，风险高）；改用「场景重置后补生」。② 返回标题（`change_scene(path,"")`）必须 `_reset_run_state()`（清 `battle_active`/roster/`selected_player_scene_by_peer`/`scene_ready_peers`/`_applying_change`/`_force_release`/`_pending_scene_path` + 取消补生 token），否则**同进程**重开会异常（角色落原点/不显示、无法建房），只有重启进程才恢复。③ `close_connection(silent)` 走同一复位，避免 "offline" 覆盖失败状态。
- Source / 来源: user + test
- Date / 日期: 2026-10-05

### [Mod] LAN 暂停对齐联机版：只停本地玩家，不暂停世界（`pause_visibility` hook）
- Evidence / 证据: `script/extension_hooks.gd` 新增 `pause_visibility`（通知，参数 `[visible, pause_screen]`）与 `is_lan_session`（返回 bool）；`ui/pause_screen.gd`（`_ready` 的 `visibility_changed` 优先 `ExtensionHooks.pause_visibility`，**未注入才** `get_tree().paused = visible`；`_input` 在 `can_pause/_pause_locked` 守卫后加「LAN 且隐藏时提前 return」）；`net/coop_net.gd`（`_on_pause_visibility(visible, pause_screen)`：LAN 下 `get_local_player().set_deferred("player_stop", visible)` + `set_meta("pause_menu_open", visible)` + `pause_screen.process_mode = PROCESS_MODE_ALWAYS`，非 LAN 走 `get_tree().paused`；`_is_lan_session` 直接返回 `is_lan_game`）。`--coop-devpause`（entry）自测。
- Notes / 说明: 对齐联机版 `ui/pause_screen.gd`（LAN 下**不** `get_tree().paused`，只 `local_player.player_stop = visible` + `pause_menu_open = visible`；`pause_screen` 用 `PROCESS_MODE_ALWAYS`；`pause_screen._input` 隐藏时 return，打开交给 `player._unhandled_input`）。**根因**：LAN 下若 `get_tree().paused=true` 会停掉 `CoopNet._physics_process`（默认 `PROCESS_MODE_INHERIT`），暂停期间停止上报本地状态/应用快照，恢复时跳变；且与「只冻结自己、世界继续」的联机语义不符。**零回归**：`pause_visibility` 未注入（未装 mod）时本体仍 `get_tree().paused=visible`；注入了但非 LAN 时 mod 也设 `get_tree().paused`（单机逐字节一致）。`pause_menu_open` 本体 `player.gd` 不读，按用户要求用 **mod meta** 记录（与联机版语义一致）。本体侧只有 `pause_screen.gd` 一处行为分支变化（走 hook），玩家/输入路径未改。`--coop-devpause` 实测（host+client 双进程 LAN）：`before paused=false player_stop=false vis=false lan=true` → `open paused=false player_stop=true meta=true process_mode=3(ALWAYS)` → `closed paused=false player_stop=false meta=false`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] LAN 下 `get_player` 未发 → 本体 crosshair 空引用（团队结束红字）
- Evidence / 证据: `scenes/main/test_room.gd:36-51`（`reset_data()` 开头 `player = get_first_node_in_group("Player"); if player == null: return`，LAN 下本地玩家尚未生成 → 早退 → `emit_get_player()` 不执行）；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（旧 `_place_and_refresh_local_player` 的 `base_emits = current_scene_path.contains("test_room") or multiplayer.is_server()` 误判 → 双方都不补发；现改为放下本地玩家后无条件 `GameEvents.emit_get_player.call_deferred()`）；崩溃点 `scenes/crosshair/crosshair.gd:44-46 game_over_hide`（`player.stats.hp` 空引用），触发链 `ui/pause_screen.gd:366 yes_mouse_selected(player_dead=true)` → `GameEvents.emit_game_over` → mod `_gate_game_over` → `_force_team_game_over_authoritative` → `force_emit_game_over(true)` → `game_over` → crosshair；`ui/player_up_screen_date.gd:21-23`（13 个 `get_player` 监听器里唯一会重复 `connect` 的）；`ui/game_over_page.gd:142-159`（`play_voice`/`get_player` 同样解引用 `player.player_card`）。
- Notes / 说明: LAN 进 `test_room` 时本体 `reset_data` 因玩家未生成而早退，`get_player` 从未发出，`crosshair`/`player_up_screen_date`/`game_over_page` 等的 `player` 恒 null；主机/客机任一方触发团队结束（暂停 Quit→Yes 或全员倒地）都会 `crosshair.game_over_hide(true)` 空引用。“客机先退、主机再退”只是本次测试顺序，与断线无因果。修法：① mod 侧放下本地玩家后**无条件补发** `get_player`（该函数仅 LAN 调用）；② 本体 `player_up_screen_date.get_player()` 幂等（`player==null` 早退 + `coin_changed.is_connected` 守卫）——审计 13 个监听器仅此一个会因重复 emit 报 `already connected`，其余都只是重新取玩家/隐藏菜单（幂等）；③ 本体 `crosshair.game_over_hide()` 加 `player==null` 守卫（纵深）。**通用教训**：`GameEvents.emit_get_player` 是「一次性事件」，依赖它的 UI 只在发出后有效；当 mod 在场景 `_ready` 之后才生成玩家时必须补发；判断「本体会不会发」不能靠场景名/是否 server 的启发式（会误判），要么无条件补发 + 让消费端幂等，要么显式追踪事件。实测（双进程 LAN + `--coop-devpause`）：双端 `crosshair player=<本地玩家>`、团队结束无 `SCRIPT ERROR`、无 `already connected`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 跨端命中反馈互通：视觉结算回放 + 测试房预置敌人确定性注册 + 远程反馈频率选单
- Evidence / 证据: 本体 `script/health_component.gd`（`take_damage(damage_data, bypass_hook, suppress_feedback)`；新增 `play_hit_feedback(actual, data, do_flash, do_text)`；`_take_damage_internal(damage_data, suppress_feedback)` 里 `damage_taken.emit`/`_hurt_flash` 受 `suppress_feedback` 门控）、`script/player_health_component.gd`/`script/summoned_health_component.gd`（同 `play_hit_feedback`）；mod `net/coop_net.gd`（`_server_enemy_hit` 改 `take_damage(data, true, true)` + 以 `hp_before-hp_after` 计实际伤害 → `_replay_hit_feedback` + `rpc("_remote_hit_feedback", net_id, actual, cfg, attacker)`；`_on_server_enemy_damage_taken` 广播 `attacker=host`；`_remote_hit_feedback`/`_replay_hit_feedback`/通用火花 `bullet_smoke`；`_register_existing_test_room_enemies` 按 `EnemiesRoot` 子索引分配 `TEST_ROOM_NET_BASE+i`；`net/coop_settings.gd` + `remote_effect_allowed`/`remote_flash_allowed`/`_remote_text_should_emit`；`_spawn_one_visual`/`_spawn_one_effect` 加远程特效门）；`ui/coop_menu.tscn`/`.gd`（`OPTION` 页签 + `OptionPanel` + 三条 `res://ui/damage_freq_slider.tscn`）；`i18n/coop_i18n.gd`；`net/coop_visual_sync.gd:spawn_visual_effect`（命中火花）。
- Notes / 说明: ① **根因**：本体命中反馈全部产生在 `HealthComponent._take_damage_internal` 内；旧 mod 在 `take_damage` 入口 `enemy_damage_interceptor` 把客机结算整段跳过 → 客机命中无冒烟/无闪白/无飘字；对端只收旧的 `_remote_enemy_hit`（只 `_hurt_flash` + 发 `GameEvents.enemy_damage_taken`，而**飘字监听的是 `health_component.damage_taken`**）→ 对端无飘字；命中烟不在该路径 → 对端无烟。② **修法（视觉结算回放）**：新增 `play_hit_feedback`（只 `damage_taken.emit` + `_hurt_flash`，**不扣血、不发 gameplay 信号**）；host 处理客机命中时 `suppress_feedback=true` 抑制自然表现，再由 `_replay_hit_feedback` 统一按来源回放 + 广播；`is_remote = attacker_peer != 本地` 决定用 coop 门槛还是本体全局门（本地玩家自身走本体门）。③ **测试房预置敌人**（`test_room.tscn` 内静态沙包）双方各自副本、不走 `spawn_anim`、从不注册 → 对端看到的是"对方机器上另一个沙包"，血量不变；改为按 `EnemiesRoot` **子节点索引**分配相同 net_id（host `server_owned=true`、client `false`），**不生成镜像**、复用本地节点。④ **频率选单**：`net/coop_settings.gd`（`user://etn_coop_settings.cfg`）三档独立（特效/闪白/飘字，0=关 / 1=×4 / 2=×3 / 3=×2 / 4=×1），仅作用于**其它联机玩家**来源；本地玩家与敌人/Boss 走本体全局设置。⑤ **通用教训**：「表现信号」与「gameplay 信号」必须分离——回放命中绝不能用 `GameEvents.emit_enemy_damage_taken`（会让各端 PS/道具重复结算金币/扩散/buff）；预置/静态实体做联机同步优先"确定性 net_id + 复用本地节点"，避免生成镜像造成重复。实测（双进程 LAN + `--coop-devpreplaced`）：两端 `count=10`；host 先打 `35→25`、客机 `25`；客机再打后 host `25→15`、客机 `15`（客机命中走 suppress+回放）；`--coop-devmenu` 校验 OPTION 页/三滑条；无 `SCRIPT ERROR`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 复活型敌人（测试房沙包）不能把 `is_dead` 当永久死亡
- Evidence / 证据: `scenes/enemies/sandbag.gd:on_dead()`（`GameEvents.emit_enemy_dead_position` + `stats.spawn_hp()`）、`_on_enemy_stats_is_dead()`（`on_dead.call_deferred()`）；`script/EnemyStats.gd:134-136`（`spawn_hp()`：`dead_lock=false; hp=max_hp`）、`:81-94`（hp 归零才 `is_dead.emit()` 且需 `dead_lock==false`）；mod `net/coop_net.gd:_on_server_enemy_dead`（原：一触发即 `erase` 三表 + `rpc("_despawn_enemy_remote")`）、`_connect_enemy_dead()`（`is_dead.connect(..., CONNECT_ONE_SHOT)`）。
- Notes / 说明: **现象**：联机测试房客机击杀沙包后，客机镜像直接消失，主机沙包仍在并回满血。**根因**：沙包 `on_dead` 会 `spawn_hp()` 回满血复活，且 `on_dead` 是 `call_deferred`；而我们的 `_on_server_enemy_dead` 在 `is_dead` 同步触发时**立即** despawn，发生在复活之前 → 客机镜像被删、主机 net_id 已丢、`is_dead`（ONE_SHOT）未重连（`dead_lock` 又被 `spawn_hp` 复位，故本体侧能再次"死亡"但 mod 不再处理）。**修法**：`_on_server_enemy_dead` 先发死亡演出，`await get_tree().process_frame ×2` 等 `call_deferred` 的 `on_dead` 跑完，再判 `is_instance_valid(enemy) and enemy.stats.hp > 0` → **复活**（保留 net_id + `_connect_enemy_dead()` 重连，靠快照同步满血，不发 despawn）；否则**真死**（原 despawn）。抽出 `_connect_enemy_dead()` 供 `register_enemy_spawn`/`_register_existing_test_room_enemies` 复用。**通用教训**：`is_dead`/`on_dead` 不等于"实体已永久消失"——凡 `on_dead` 可能回血/重置（假人、可复活单位）的敌人，despawn 决策必须**延迟且以最终 hp/有效性为准**，不能在同一帧内当作死亡终态；ONE_SHOT 死亡信号在复活后要重连。实测（`--coop-devpreplaced` 客机致命 999）：两端 `count=10 hp#0=35`（镜像不消失、回满血）；无 `SCRIPT ERROR`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 正常关卡联机三问题：回合/升级未同步、客机敌人朝向、客机子弹穿透
- Evidence / 证据: ① 回合：本体 `ui/round_timer.gd:112/117/142 emit_round_end()`、`scenes/manager/round_manager.gd:108-139 _on_round_end`、`scenes/main/main.gd:60-64`（`first_round_start_gate` 只放行 host）、mod `net/coop_net.gd:_gate_first_round`；联机版 `NetworkManager._on_round_end:2483`/`_remote_round_end:2490`、`_on_round_upgrade:2439`/`_remote_round_upgrade:1640`、`round_manager.gd:125-126`（客机清场后 return）、`round_timer.gd:116-134/154`（客机首轮计时 + 不发 round_end）。② 朝向：本体敌人 `sweeper.gd:73-75`/`automaton.gd:146-148`/`sandbag.gd:155-169` 等按 `direction.x` 翻 `graphics.scale.x`；mod `net/coop_enemy_proxy.gd`（只同步位/速/血、`_disable_physics_recursive` 关了镜像物理）。③ 穿透：本体 `script/hit_box.gd:73-80 _emit_self_hit`、`script/player_bullet.gd:76-92`/`scenes/bullet/normal_bullet.gd:112-125`（生命周期闭包在 `damage_data.on_damage_dealt`，只在 `health_component._take_damage_internal` 执行）、mod `_intercept_enemy_damage`。
- Notes / 说明: ① **回合**：`_gate_first_round` 让客机不跑 `first_round_start` → 客机不发 `round_start` → `round_timer.init_round` 不执行 → **客机永不 `emit_round_end`** → 客机不转场/升级、可操作、敌人不清，host 升级页等全员 ready 永久卡住。修法（联机版同款）：本体 `ExtensionHooks` 加 `round_end_emit_gate`/`round_end_proceed_gate`；`round_timer` 3 处 emit 前加 gate + 移植客机首轮计时；`round_manager._on_round_end` 加 proceed gate。mod：host `round_end`→`_remote_round_end`、`round_upgrade`→`_remote_round_upgrade`（均排除 test_room，因 `test_room.reset_data` 也 emit round_end），客机分别 `emit_round_end()` / `emit_round_upgrade()`+`emit_player_buff_clear()`+`paused=true`。升级天然按端独立（`apply_upgrade` 加本机 `Player` 组玩家 + 写本机 `PlayerData.current_upgrades`；level_state 同步不含 `current_upgrades`）。② **朝向**：镜像物理帧被关，本体翻面逻辑不跑；proxy 按快照 `target_velocity.x` 符号补翻 `enemy.graphics.scale.x`（保留幅值），并把 `_disable_physics_recursive` 收敛为仅 `set_physics_process(false)`（对齐联机版）。③ **穿透**：子弹生命周期绑在 `on_damage_dealt`，客机被 `_intercept_enemy_damage` 跳过 → 既不降穿透也不回池。修法：本体 `ExtensionHooks` 加 `projectile_self_hit_gate`；`HitBox` 加 `on_remote_hit`+`run_remote_hit`，`_emit_self_hit` 前加 gate；各子弹 `apply_penetrate_dealt` 把闭包同时登记到 `on_remote_hit`（开头 `clear()` 防池化复用累积）；mod gate 客机转发 host + `bullet.run_remote_hit(enemy)`（本地复刻穿透/烟/回池）。**通用教训**：「本地不结算」若用整段跳过 `_take_damage_internal` 实现，会连带吞掉绑在该路径上的**对象生命周期/表现**（子弹穿透、冒烟、回池），必须把这些与 gameplay 解耦并在转发路径单独回放；回合切换/升级这类"本地状态机"在联机下要么 host 权威驱动、要么每端独立跑，混用会卡死；一次性/客机专属的 `_on_first_round_add` 计时不要依赖只放行 host 的 `first_round_start_gate`。
- Source / 来源: user + code
- Date / 日期: 2026-10-05

### [Mod] LAN 报错：镜像污染全局组 / 池残留已释放节点 / Buff 事件 lambda 悬空
- Evidence / 证据: ① `script/follow.tscn:5`（`[node name="Follow" type="Marker2D" groups=["Follow"]]`）、`script/follow.gd:3`（`follow_use=false`）、`scenes/update_item/black_ninpero.gd:20-27`（`_on_equip` 遍历 `get_nodes_in_group("Follow")`、对每个未占用节点 `add_child(同一 sprite_2d)`；同类还有 `ancient_battery`/`nagusa_doll`/`millennium_flag`/`puzzle_cube` 等）、mod `net/coop_net.gd:spawn_remote_player`（原只把镜像根移出 `Player`/加 `RemotePlayer`，未处理子节点 `Follow` 组）。② `scenes/manager/PoolManager.gd:get_pool/get_pool_idle`（直接 `body[pool_index].is_idle`）、`scenes/main/test_room.gd:reset_clear_unit`/`scenes/main/main.gd:bullet_clear_unit`（`queue_free` BulletRoot 子节点未从池注销）。③ `scenes/manager/buff_manager_base.gd:426-441 _ensure_event`（`sig.connect(func(...): _consume_by_event(evt))`；`_event_subs` 只记 bool）；mod `net/coop_visual_sync.gd:_queue_free_after`（原 `timer.timeout.connect(func(): if is_instance_valid(node): node.queue_free())`）。
- Notes / 说明: **现象**：LAN 下主机在测试房选升级道具后出现 `Can't add child 'BlackNinperoIcon' ... already has a parent 'PlayerRoot'`、`Lambda capture at index 0 was freed`、`Invalid access ... 'is_idle' ... previously freed`。**根因与修法**：① 每个玩家场景的 `Follow` 在**全局 `Follow` 组**，升级道具 `_on_equip` 对每个未占用 Follow 都 `add_child` 同一图标；LAN 下远端镜像的 Follow 也在组里 → 同一图标 add 两次（且错跟镜像）。修：`spawn_remote_player` 把镜像**及后代**移出 `Follow` 组。② 清场直接 `queue_free` 池化子弹/特效但未注销 → 池内残留已释放项 → `get_pool` 访问 `is_idle` 崩。修：`PoolManager._prune_freed_bodies(entry)` 取用前剔除失效项 + clamp index；`reset_clear_unit` 释放前 `erase_pool`。③ `BuffManagerBase._ensure_event` 的 lambda 连到长生命周期信号（`GameEvents`/`stats`），manager 释放后连接仍在 → 触发时 `self` 捕获已释放。修：`_event_subs[evt]` 存 `{sig, cb}`，`_exit_tree` 逐个 disconnect。④ mod `_queue_free_after` 的定时器 lambda 捕获 Node，特效被提前释放（重置）后触发报同一错。修：改用 `WeakRef`（lambda 不再捕获 Node）。**通用教训**：① 联机镜像会进入**全局组**，凡"遍历全局组并对每个成员执行副作用"的本体逻辑（`Follow` 等）都要在镜像生成时把其成员移出共享组；② 对象池的 `queue_free` 必须先从池注销（或在取用处剔除失效项），否则"清场后第一个 `get_pool`"必崩；③ 连到长生命周期信号的 lambda 不要直接捕获会释放的 Object（用 `WeakRef` 或释放时 disconnect），Godot 会在捕获失效时打印 `Lambda capture ... was freed`。验证：双进程 LAN `--coop-devbattle --coop-devreset --coop-devpause --coop-devpreplaced` 无 `SCRIPT ERROR`/`Invalid`/`Lambda`/`previously freed`；`--coop-devfollow` 两端 `total=1 remote=0`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05
- UPDATE: 2026-10-08 `PoolManager._prune_freed_bodies` 已移除，改为 `_node_pool`（`instance_id -> pool_id`）反向映射 + `tree_exiting` 自注销（`_on_pooled_node_exit`），同样保证 `queue_free` 后不再访问失效项；`erase_pool`/`clear_pool` 同步清反向映射。

### [Mod] 命中飘字同屏重复（回放重入广播）+ 敌人 buff 权威同步（施加者属性 / 镜像跳过）
- Evidence / 证据: ① 双飘字：mod `net/coop_net.gd:_replay_hit_feedback` 调 `script/health_component.gd:play_hit_feedback`（内部 `damage_taken.emit`），而 `_on_server_enemy_damage_taken` 正 `connect` 在同一 `damage_taken` 上（`register_enemy_spawn`/`_register_existing_test_room_enemies`）→ 回放 emit 触发其再次 `rpc("_remote_hit_feedback", ..., attacker=host)`；客机对同一次命中收 `attacker=client` + `attacker=host` 两条 → 同屏两次。② buff：`scenes/bullet/poison_ring.gd:44-57`（`manager.apply_buff` 在 `on_damage_dealt` 闭包内）、`scenes/manager/enemy_buff_manager.gd`（DOT `player.stats.dot_damage/dot_time/global_damage/fire_dot_layer`）、联机版 `enemy_buff_manager.gd:96-97/113-118`（`_is_remote_mirror` 跳过镜像 DOT）。
- Notes / 说明: ① **双飘字**：`_replay_hit_feedback` 置 `_replaying_feedback` 期间，`_on_server_enemy_damage_taken` 直接 return（mod）。② **buff 权威**：客机加敌人 buff 原本只在本地镜像（且被拦截跳过），host 真敌人永不受益。改：本体 `ExtensionHooks` 加 `enemy_buff_apply_gate`/`on_enemy_buff_removed`；`buff_manager_base.apply_buff` 增 `applier_stats` 参数并存 `entry["applier_stats"]`、入口 gate、`_remove_buff_entry` 通知；`enemy_buff_manager` 用 `_estat(entry,key)`（施加者属性优先）替换 `player.stats.*`，并加 `_is_remote_mirror()` 在 `add_damage_data`/`count_chill_damage` 跳过（镜像不结算 DOT）。mod：客机 → `_gate_enemy_buff_apply` → `_server_apply_enemy_buff`（host 权威 apply + `_remote_enemy_buff` 广播）；客机镜像收到 `_remote_enemy_buff` 应用（`_applying_remote_buff` 放行 gate、仅表现）；到期 `_on_enemy_buff_removed` → `_remote_enemy_buff_remove`。**通用教训**：① 反向回放（mod 主动调本体"表现函数"）时，本体表现函数内部 emit 的信号若又连回 mod 的网络监听器，会**重入广播**，必须用重入守卫（同 `_replaying_feedback`）；② 「本地不结算」的拦截还会吞掉绑在结算路径上的**状态写入**（buff 应用），需为该类状态单独建立权威转发通道，并把**施加者上下文**（如 DOT 的属性）随包带上，否则权威端会用错属性；③ 客机镜像同样要跑表现（card/FX），但必须屏蔽其结算（`_is_remote_mirror`），且移除也要同步。验证：`--coop-devbuff` 客机加 `poison_dot` → host `keys=["poison_dot"]` hp `35→5`、客机镜像 `keys=["poison_dot"]` hp 同步；`--coop-devbattle --coop-devreset --coop-devpause --coop-devpreplaced --coop-devfollow` 无 `SCRIPT ERROR`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 伤害/proc 按 peer id 归属：host 权威分发 + 归属端发射（避免 host 道具被客机伤害误触发）
- Evidence / 证据: 本体 `script/health_change_data.gd`（新增 `owner_peer`）、`script/damage_data.gd`（reset/`_apply_cfg`）、`script/health_component.gd:_take_damage_internal`（`suppress_proc` 守卫三处 `emit_enemy_*`）、`script/extension_hooks.gd:enemy_proc_owner_suppress`、`script/GameEvents.gd:player_projectile_hit`、`script/hit_box.gd:_emit_self_hit`（gate 前 `emit_player_projectile_hit`）、`scenes/manager/buff_manager_base.gd:apply_buff(applier_stats, applier_peer)`、`scenes/manager/enemy_buff_manager.gd:add_damage_data(..., owner_peer)`、`scenes/player/iori/iori_ps.gd`/`scenes/update_item/mint_chocolate_parfait.gd`（改监听 `player_projectile_hit`）；mod `net/coop_net.gd`（`_damage_to_dict` 带 `owner_peer`/`source_node`；`_server_enemy_hit` 设 owner_peer= sender + `last_attacker_by_net_id` + `killed` → `rpc_id(attacker,"_remote_enemy_proc")`；`_on_server_enemy_damage_taken` 按 owner_peer 回传；`_remote_enemy_proc` 归属端发射；`_gate_enemy_proc_owner_suppress`）。
- Notes / 说明: **目标**：每个玩家的道具/PS 只为**自己的伤害**触发，且触发在**自己端**；host 不再被客机伤害误触发。**机制**：`owner_peer` 作"独立 id"落点；host 结算后按 `owner_peer` 决定：本机 → 自然 emit；客机 → `suppress_proc` 抑制 host 本地 emit + `_remote_enemy_proc` 发回归属端发射。击杀（`hp_before>0 && hp_after<=0`）与 DOT（`entry.applier_peer`）同归属。**为什么不是"过滤 51 个监听器"**：全局信号无法按归属过滤；但每个客户端进程只有本机玩家的道具/PS，故"只在归属端发射"即等价归属。**β 难点（`source_node` 需活来源）**：权威回传是延迟的，届时来源子弹已 `idle_state` 回池 → `iori_ps`（分裂）/`mint_chocolate_parfait`（按 `flight_time` 加乘）失效；改为二者监听 `GameEvents.player_projectile_hit`（`HitBox._emit_self_hit` 命中瞬间发射、携带 live bullet），其余仍走权威回传。**通用教训**：① 多玩家共享"全局权威事件"（如 `enemy_damage_taken`）时，用"归属 id + 只在归属端发射"代替"在权威端统一发射"，可零侵入所有监听器地实现归属；② 需要"活对象"的旧式 proc（从事件里 `get_node(source_node)`）与"权威延迟回放"天然冲突，应改挂到**命中瞬间**的信号；③ 一次性/延迟回放路径要把**权威数值**与**归属 id**一起带回，且击杀判定用 hp 前后差比 `is_dead` 信号更精确（复活型敌人）。验证：`--coop-devowner` 客机命中 → host `proc=0`、客机 `proc=1`（`op=<客机 id>`）；`--coop-devbattle --coop-devreset --coop-devpause --coop-devpreplaced --coop-devfollow --coop-devbuff` 无 `SCRIPT ERROR`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05
- 补充 / 2026-10-14: 活对象信号迁移不等于前置数值已跨端生效；COOP-008 的实际 wire roundtrip 证明仍缺伤害修饰契约，见文末 [Coop/Combat] 条目。
- SUPERSEDED: 2026-10-14 随后以本体前置阶段和协议 v5 补齐数值契约，真实双端 damage 场景已通过；上述补充保留为修复前观察。

### [Mod] 命中闭包本地回放 / 测试房重置-换角色同步 / 道具视觉同步
- Evidence / 证据: `scenes/bullet/poison_ring.gd:44-57`（`apply_buff` 在 `hit_box.damage_data.on_damage_dealt` 闭包内，只在 `_take_damage_internal` 执行）、`ui/character_test_menu.gd:31-47 reset_player()`（`emit_test_room_reset`）、`scenes/main/test_room.gd:56-91`（`reset_clear_unit` 清 PlayerRoot 非"Player"/召唤物/特效；`refresh_enemies` 清非 `initial_enemies`）、mod `net/coop_net.gd`（`_intercept_enemy_damage`/`_gate_projectile_self_hit` 本地跑 `on_damage_dealt`；`_replace_player_for_peer` 远端分支补 `player_scene_by_peer`；`_on_local_test_room_reset`/`_despawn_owned_summons_local`；`_remote_item_visual`/`_hook_visual_roots`/`_remote_visual_node`）；本体 `script/hit_box.gd`（**移除** `on_remote_hit`/`run_remote_hit`）、`script/player_bullet.gd`/`normal_bullet.gd`/`megu_bullet.gd`。
- Notes / 说明: ① **DOT**：客机命中镜像被拦截跳过 `_take_damage_internal`，绑在其上的 `on_damage_dealt`（poison ring 的 `apply_buff`）不跑 → 无 buff/card/DOT；改为客机转发前本地跑 `damage_data.on_damage_dealt`（host 转发伤害无闭包不重复）。**教训**：拦截结算会吞掉绑在结算路径上的**玩法闭包**（不只 buff，还有 `player.damage_dealt` 等），必须把这些闭包在攻击者端**本地回放**（权威回传延迟会让 `source_node` 子弹回池，故不适用）。② **换角色**：`_replace_player_for_peer` 远端分支漏写 `player_scene_by_peer` → 后续按旧路径重建镜像（切换后仍显示旧角色）；测试房 `reset_clear_unit` 清远端镜像/召唤物却无补生/despawn → 加 `_on_local_test_room_reset` 重同步 + 只对本机拥有召唤物广播 despawn（按 `summoned_owner_by_net_id`）。③ **道具视觉**：A 常驻图标用命名约定 `update_item/<id>_icon.tscn` 在非拥有者端挂到镜像 Follow；B 生成特效用 `SELayer`/`ForegroundLayer`/`BulletRoot` 的 `child_entered_tree`（延迟一帧，排除 ProjectileSpawner 已广播/remote_visual）→ 对端纯视觉副本。**通用教训**：联机镜像/重置要按 owner id 区分"该玩家的"与"别人的"；"仅视觉"回放要屏蔽结算。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 联机手感补齐：#1 敌人命中预测 / #6 远程表现 / #3 网络诊断 HUD
- Evidence / 证据: 对齐联机版 `NetworkEnemyProxy.note_predicted_damage/apply_snapshot`、`NetworkManager._predict_enemy_death/_replay_hit_feedback/get_network_debug_text`。mod `net/coop_enemy_proxy.gd`（重写：`auth_hp`+`pending_damage` 列表、`note_predicted_damage`、`_compute_display`/`_confirm_pending`/`_expire_pending`、`apply_snapshot` 校正 + 快照证存活时 `_revive_local_mirror`）；`net/coop_net.gd`（`_get_predicted_enemy_damage`/`will_enemy_hit_kill`/`_predict_enemy_death`；`_intercept_enemy_damage`+`_gate_projectile_self_hit` 命中瞬间 `_replay_hit_feedback`+`_predict_enemy_death`；`_remote_hit_feedback(..., predicted)` 攻击者回声去重；`_play_remote_enemy_spawn_anim`/`_play_remote_scene_transition_start`/`_play_coin_pickup_visual`；`_update_network_diagnostics`/`_diag_ping`/`_diag_pong`/`get_network_debug_text`）；`ui/net_debug_hud.gd`（代码构建 CanvasLayer，F9 开关）；`entry/coop_entry.gd`（创建 HUD + `_unhandled_input` F9 + `--coop-devhud`）。
- Notes / 说明: ① **预测**：客机命中时立即 `note_predicted_damage`（显示血量 = auth_hp - pending）并播闪白/飘字/预测死亡（镜像 `idle_state`），不等 host 回传；host 快照到达后 `apply_snapshot` 确认/校正，若证未死则 `_revive_local_mirror`（清 `predicted_dead` + `active_state`）。直接命中走 `_server_enemy_hit` 广播带 `predicted=true`，攻击者收到回声时跳过（已本地预测）；DOT/自然伤害走 `_on_server_enemy_damage_taken` 带 `predicted=false`，攻击者仍收飘字。② **表现**：远程敌人补 `spawn_anim` 生成动画、切场景补 `Transition.play_left_start` 转场、远处拾币补 tween 飞向拾取者。③ **诊断**：0.5s 窗口 ping/pong 估 RTT、丢包与子弹/特效收发速率，HUD 代码构建、F9 切换、`set_network_diag_enabled` 联动。**通用教训**：预测本质是「乐观显示 + 权威校正」，镜像血条可先降后回，必须以快照为最终真值；本地预测造成的即时表现要与权威回放互斥（用来源 + predicted 标志区分），否则同一命中双表现。实测（双进程 LAN）：`--coop-devpreplaced` 客机 `dev preplaced#0 predicted=1 pending=999` → host 权威后镜像回满 `hp#0=35 count=10`；HUD `rtt=7ms loss=0%`；`--coop-devbattle --coop-devpreplaced --coop-devowner --coop-devbuff --coop-devring --coop-deveffect --coop-devbullet --coop-devcoin --coop-devfollow` 无 `SCRIPT ERROR`/`Invalid`/`Lambda`/`previously freed`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 道具视觉全量复刻 + 红字根治（%Sprite2D / RPC 越权 / monitoring 轮询）
- Evidence / 证据: 本体无 upgrade→世界视觉数据源（`scenes/manager/upgrade_manager.gd:169-176` 只实例化 `<id>.tscn`；`script/equip_item.gd:49-76` 三种挂点靠全局组）。mod 新增 `net/coop_item_visuals.gd`（清单+挂载+sanitize+内部视觉剥离）、`net/coop_visual_driver.gd`（位置驱动）；`net/coop_net.gd`（`_remote_item_visual` 改 any_peer + 委托清单；`_hook_visual_roots` 扩 EquipLayer/FloorLayer/PlayerRoot；`PERSISTENT_BODY_SCENES` + `_register_persistent_body`；`_clear_peer_item_visuals`）；`net/coop_player_proxy.gd`（镜像枪惰性 + `_disable_areas` 停 process）；`net/coop_summoned_proxy.gd`/`net/coop_visual_sync.gd`（停 process）。
- Notes / 说明: ① **`%Sprite2D` 红字**：`utaha_turret_icon.tscn` 不是独立图标（内嵌于 `utaha_turret_body.tscn`），旧逻辑盲目按 `<id>_icon.tscn` 实例化才触发；改为按**清单**只实例化确认安全的图标。② **RPC 越权**：`_remote_item_visual` 原为 `authority`，客机升级时自己 `rpc` 触发 `not allowed ... authority is 1`；纯视觉故改 `any_peer`。③ **monitoring 红字海**：镜像禁伤害时关 `monitoring` 却没停 `_physics_process`，本体 `hurt_box.gd:92` 每 0.1s 轮询 `_contact_probe.get_overlapping_bodies()`；三处禁用函数补 `set_physics_process(false)`+`set_process(false)`。④ **挂点必须取镜像自身标记**：本体用全局 `get_first_node_in_group`（会挂到本地玩家）；mod 在**镜像子树**内按字段/组查找。**关键坑**：`spawn_remote_player` 早前把镜像的 `Follow` 移出了全局组，故 follow 挂点只能按字段（不能按组）在镜像子树内找；hat/rail/muzzle 仍按组。⑤ **武器同步=角色场景同步**：本体无运行时换枪（枪是角色场景静态 `ExtResource`，`player.gd:56 %Gun`），镜像按 roster 角色场景实例化即含正确枪；只需把镜像 `Gun` 置惰性（否则 `player_gun.gd:40-41` 认全局 `Player` 会朝本机玩家开火）。⑥ **内部视觉（视觉与玩法同场景）**：`add_child` 前 `root.set_script(null)` 剔除 `EquipItem`（`_ready` 不跑玩法），再递归禁用 Area2D/CollisionShape2D/Timer、隐藏 Label；少量每帧偏移由 `coop_visual_driver.gd` 读镜像玩家驱动。⑦ **icon 内嵌挂点污染**：图标场景内嵌 `Follow/Hat/Rail/Muzzle` 子节点会进全局组、被后续道具误占；实例化后 `_sanitize_groups` 全部移出。实测（双进程 LAN，双向授予 `black_ninpero/cowboy_hat/sniper_scope/suppressor/cathedral_candle/kitchen_knife/little_kei/utaha_turret/shiroko_drone`）：镜像端 `item-visual ... node=...` 全部建成、`utaha_turret/shiroko_drone` 走召唤（`summons=2`）、无 `%Sprite2D`/RPC/`monitoring` 红字；综合回归（preplaced/owner/buff/ring/effect/bullet/coin/follow）零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 远端投射物"穿过敌人不消失"：命中即 idle 的投射物必须通知 despawn
- Evidence / 证据: `scenes/update_item/shiro_missile.gd:52-63`（`idle_state()` 含 `add_explosion()` 但**无** `on_projectile_despawned` 通知）、`:121-127`（命中 HurtBox → `idle_state.call_deferred()`）；对照 `script/player_bullet.gd:90-96`（`idle_state` 有通知）；mod `net/coop_visual_sync.gd:71`（`_disable_damage` 关掉远端克隆的 `monitoring`）、`:82-99`（`despawn_visual_bullet` 调 `idle_state`）、`:176-186`（`_acquire` 淘汰也调 `idle_state`）、`net/coop_net.gd:714-729`（`_on_projectile_despawned` 才广播销毁）。修：`scenes/update_item/shiro_missile.gd` 与 `scenes/player/mashiro/cross_bullet.gd` 的 `idle_state()` 补通知；`shiro_missile.gd` 新增 `visual_idle_state()`（复位但不 `add_explosion`）；mod 定 `_visual_idle()` 优先调 `visual_idle_state`。
- Notes / 说明: **现象**：本机 shiroko_drone 的导弹命中敌人 → 爆炸并消失；其它玩家视角导弹**穿过敌人**、过一阵才在错误位置消失。**根因**：远端导弹是 mod 的纯视觉克隆，`_disable_damage` 关了 `monitoring`/碰撞 → `area_entered` 永不触发 → 不会命中；其销毁只能靠拥有者广播 `on_projectile_despawned`，而 `shiro_missile.idle_state` **漏了通知** → 远端克隆只能等自身 `time_count` 到 `kill_time=110` 才 `add_explosion()+idle`。**次生**：即便补通知，远端 `despawn` 会调克隆的 `idle_state` → 再 `add_explosion` → 观察端重复爆炸；故加无副作用的 `visual_idle_state`。**另一处回归**：T1 曾给 `coop_visual_sync._disable_damage` 对每个 `Area2D` 加 `set_physics_process(false)`，而子弹/导弹移动在自身 `_physics_process`（`player_bullet.gd:153/188`）→ 会冻住远端子弹；已撤销（`monitoring is off` 轮询只来自 player/summon 镜像的 HurtBox，由 `coop_player_proxy._disable_areas`/`coop_summoned_proxy._disable_damage_nodes` 处理）。**通用教训**：凡"命中即回池/隐藏"的投射物，`idle_state` 必须通知 `on_projectile_despawned`（否则远端视觉不销毁"穿模"）；远端克隆销毁应走"无副作用"的专用方法（否则本地爆炸/音效会在观察端重复）；`RefCounted` 版辅助脚本里不能用 `multiplayer`（会导致依赖它的 `_visual` 整体编译失败）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 远端命中反馈按来源还原（子弹烟 / 大或小爆炸 / 音效）
- Evidence / 证据: 本体命中表现分三处：受击者通用（`script/health_component.gd:158-164` `HurtSounds`+闪白+飘字，`suppress_feedback` 门控）、攻击物自带（`script/player_bullet.gd:76-92` 烟、`script/explosion_damage.gd:72-101` 大/小爆炸+`ExplosionSounds`）、近战脚本自带 `HurtSounds2`（`scenes/player/hoshino/melee.gd:136/166/175`、`utaha/melee.gd:105/141`、`chinatsu_melee.gd:79`、`script/kick.gd:48`、`spiked_shell.gd:73`、`iori_ps.gd:83`、`kasumi_drill.gd:210`）。mod `net/coop_net.gd`：新订阅 `GameEvents.player_projectile_hit`→`_on_any_projectile_hit`（按 `PlayerBullet`/`SummonedBullet` 分类广播 `bullet_smoke`/`bullet_smoke_2`）；`_on_explosion_effect`/`_on_hit_sfx`/`_broadcast_hit_sfx`/`_server_hit_sfx`/`_remote_hit_sfx`/`_remote_sfx_allowed`；`_replay_hit_feedback` 去通用 `REMOTE_SPARK_SCENE` + 补 `HurtSounds`。本体 `script/extension_hooks.gd` 新增 `on_explosion_effect`/`on_hit_sfx`；`explosion_damage.gd` 两处 notify。
- Notes / 说明: **模型**：命中表现由**造成伤害的拥有者**产出并广播（与子弹视觉/召唤物 owner 权威同思路），其它端复刻、排除发起端。**关键点**：① 子弹烟绑定 live bullet 且对象池复用，`_hook_visual_roots` 只在首次创建广播 → 必须由拥有者在 `player_projectile_hit` 按**子弹类**广播正确烟；② `DamageData` 不带"哪张烟/大或小爆炸/音效"，故爆炸变体需本体 hook（`is_explosion`/`is_small_explosion`），近战 `HurtSounds2` 需在**调用点** hook（它同时用于近战与装备如 `spiked_shell`，且应"每挥击一次"而非"每敌人一次"）；③ `_replay_hit_feedback` 原对**所有来源**放同一通用烟，且不播 `HurtSounds`（`play_hit_feedback` 无）→ 攻击者"真烟+通用烟"双份、观察者只有通用烟；改为去通用烟 + 补 `HurtSounds`。**远端音效限流**（多玩家）：每 key `80/mult` ms + 全局 `33ms`，复用 `remote_effect_freq` 档位（0=关远端命中音）；本地自身不受限。**对象池污染**：`explosion.tscn`/`small_explosion.tscn` 无 `pool_id` 字段却在 `_ready` 注册本体池，`CoopVisualSync._remove_effect_from_gameplay_pools` 需按场景路径映射 `big_explosion`/`small_explosion` 并剔除。实测（双进程 LAN）：客机 shiroko_drone 引爆 → 观察端 `ExplosionSounds` 次数与爆炸次数一致、无红字；`--coop-devitems/devbullet` 触发 `prog-hit`（`bullet_smoke_2`）；综合回归零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 远端"123456789"飘字不消失 + 主机属性被重置（镜像进了 Player 组）
- Evidence / 证据: ① `ui/floating_text.tscn:130`（Label 默认文本 `text = "123456789"`，`start()` 才改写并播 `new_animation`，末尾才 `idle_state` 隐藏）；`script/enemy_hurt_floating_text.gd:84-109`、`PoolManager.add_text`、`player.gd:439 add_text` 等都会 `ForegroundLayer.add_child` 后 `start()`；mod `net/coop_net.gd:_maybe_broadcast_visual_node` 监听 `ForegroundLayer` 广播新子节点，接收端 `coop_visual_sync.spawn_visual_effect` 实例化但不调 `start` → 显示占位 `123456789`。② `ui/AbilityBox.gd:31-33`（`player = get_first_node_in_group("Player")` 后缓存，只在 `GameEvents.get_player` 时重取）；`net/coop_net.gd:spawn_remote_player` 原顺序 `root.add_child(p)` → `p.remove_from_group("Player")`：镜像场景根默认 `groups=["Player"]`，入树窗口内若有 `get_first_node_in_group("Player")`（如 AbilityBox 缓存 / 玩家场景 _ready 发 `get_player`）就会拿到镜像 → 之后面板显示镜像的基础属性。
- Notes / 说明: ① 飘字内容动态、各端各自本地生成，**不应广播**；`_maybe_broadcast_visual_node` 增加 `scene_path.ends_with("ui/floating_text.tscn")` 跳过；`_remove_effect_from_gameplay_pools` 补 `floating_text` 场景→池名映射（防御）。② 镜像**必须先移出 `Player` 组再 `add_child`**（`remove_from_group` 在入树前即生效），保证 `get_first_node_in_group("Player")` 恒为本机玩家；实测镜像 `in Player group? false`、`PlayerGroupSize=1`。**通用教训**：本体大量用全局组 `Player`（`AbilityBox`/`PlayerData.get_player`/道具 `get_first_node_in_group`）取"本机玩家"，联机镜像若在入树窗口内短暂进组，会被这些缓存链路抓到；镜像必须在**入树前**清组。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 测试房"角色卡"换人未同步（绕过 local_player_change_gate）
- Evidence / 证据: 三条换角色路径中只有两条走钩子——`ui/character_test_menu.gd:36`（`reset_player`）与 `ui/test_menu.gd:100`（`_on_reset_pressed`）用 `ExtensionHooks.intercept(local_player_change_gate, [path, Vector2.ZERO])`；而 `ui/test_character_card.gd:_on_button_pressed`（原 `:82-87`）**直接** `player.queue_free()`+`instantiate`+`PlayerRoot.add_child`，未走钩子。mod 侧链路正常：`coop_net.gd:_gate_local_player_change`→`request_local_player_change`→`_replace_player_for_peer`（本地替换 + `rpc("_replace_player_remote")` + `_schedule_respawn_remotes`）。
- Notes / 说明: **现象**：联机测试房里用角色卡换角色，其它端镜像不更新；按"重置"才更新。**根因**：角色卡路径绕过 `local_player_change_gate` → mod 收不到换人事件 → 不广播。**修法**：把 `ui/test_character_card.gd` 的直接替换段包进 `if not ExtensionHooks.intercept(local_player_change_gate, [player_path, Vector2.ZERO]): ...`，与另两条路径统一（未装 mod 时行为不变）。**通用教训**：本体存在多条"换本地玩家场景"的入口，mod 只对其中用了 `local_player_change_gate` 的生效；新增/发现直替路径要一并接钩子。
- Source / 来源: user + code
- Date / 日期: 2026-10-05

### [Mod] 召唤物/道具同步转向 + 开火表现（无人机转向 / 炮台转向+开火）
- Evidence / 证据: `net/coop_summoned_proxy.gd`（`setup` 用 `has_method` 判定 `can_get_rotation`/`can_apply_rotation`；`_physics_process` 调 `apply_network_visual_rotation`；`_get_visual_rotation` 优先 `get_network_visual_rotation`）；本体此前**无任何脚本实现**这两个方法。转向实为子节点：`shiroko_drone_icon_2.gd:58/64` 设 `shiroko_drone.v`，`shiroko_drone_icon.gd:28-31` lerp；`turret_summoned.gd:65-70` 转 `%Sprite2D` 子 sprite + `shoot_r`，开火动画 `_shootAnim():191`。修：`turret_summoned.gd` 加 `get/apply_network_visual_rotation`+`_rotate_turret_visual`+`network_play_action`，`_shoot_bullet` 发 `on_summoned_action`（带 `GunSounds4`+闪光场景/位置，并给闪光 `coop_action_flash` meta）；`shiroko_drone_icon_2.gd` 加 `get/apply_network_visual_rotation`；`extension_hooks.gd` 加 `on_summoned_action`；mod `coop_net.gd` `_on_summoned_action`/`_server_summoned_action`(本地应用+中继)/`_remote_summoned_action`（`network_play_action`+`spawn_visual_effect`+`_remote_hit_sfx`），`_maybe_broadcast_visual_node` 跳过 `coop_action_flash`。
- Notes / 说明: ① **转向**：代理本就支持"优先用 `get/apply_network_visual_rotation`"，只需本体实现；镜像 `tick_physics`/物理被禁，`v` 不会被覆盖。② **开火**：新增事件 hook，沿用"拥有者广播、其它端复刻"；**host 收到客机的动作时必须在 `_server_summoned_action` 里本地也应用一次**（否则 host 侧镜像不播，实测漏掉→已修）。③ 开火音走上一轮的远端音效限流（每 key 80/mult + 全局 33ms）；炮口闪光由动作统一广播，owner 的本地闪光打 `coop_action_flash` meta 让 SELayer 通用广播跳过，避免重复。④ 无人机按需求**只做转向**，不发动作。实测（双进程 LAN，客机 `--coop-devitems`）：代理 `getRot/applyRot=true`；客机炮台 32 次开火 → host 镜像收到 32 次 `act=shoot`、node=ok；零红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 同步缺口审计与大批修复（敌人 AI/动画、玩家镜像、池化特效、召唤、Boss、掉落）
- Evidence / 证据: 见各处 `file:line`。核心：`entity_ENEMY.active_state()`（`script/entity_ENEMY.gd:126-150`）会 `state_machine.set_physics_process(true)`，而 `_spawn_enemy_remote` 在其后调用（`coop_net.gd:_spawn_enemy_remote`）→ 镜像本地跑 AI/开火；`script/EnemyStateMachine.gd:21-33` 驱动 AI/动画；池化道具靠 `active_state` 复用（`murky_hand_scythe.gd`/`renge_doll.gd`/`kikyou_doll.gd`/`nagusa_doll.gd`）；`goliath.gd`/`erosion_tower_group.gd` 的进场/死亡演出会 `get_tree().paused=true`。
- Notes / 说明: 本轮修复（按批）：
  **批1（H1+H2）**：`_spawn_enemy_remote` 在 `active_state()` 后调 `CoopEnemyProxy.disable_mirror_ai()` 关 root 物理 + StateMachine；`_revive_local_mirror` 同样再关；`_disable_network_simulation()` 抽出。敌人快照新增 `states`（`coop_net._send_enemy_snapshot`：取 `state_machine.current_state`，变化检测含 state，rpc 加 `states` 参数），`CoopEnemyProxy.apply_snapshot(pos,vel,hp,state)` 按 state 差异 `enemy.transition_state(from,to)` 驱动动画（纯表现）。—— 不再本地跑 AI/开火，动画由 host 快照驱动。
  **批2（M1/M2）**：玩家状态包新增 `max_hp`（`_send_local_player_state`/`_server_receive_player_state`/`_apply_player_state`/`proxy.apply_state`），镜像先写 `max_hp` 再钳制血量；`_apply_visual_state` 补身体瞄准旋转（`sprite_2d.look_at` + `-10°/5°` 钳制，本体 `player.gd:233/256-259`）；新增 `GameEvents.player_gun_shoot` 订阅 → `_remote_player_gun_shoot` 让镜像重放 `gun._shootAnim()`。buff/EX 实为"无消费者/本地 UI"，无需同步。
  **批3（M3/M4/M5/M9）**：新增 `ExtensionHooks.on_visual_activated`，在镰刀/火场/毒环/冰环的**激活点**通知，mod `_on_visual_activated` 每次广播（修"只广播首次"）；`turret_summoned.reload_ammo` 发 `on_summoned_action("reload")`，`network_play_action("reload")` 播装弹；`robotic_vacuum_cleaner_body` 补 `get/apply_network_visual_rotation`（同步 `sprite_2d.v`）；`_spawn_enemy_remote` 镜像激活 `body_part`（仅视觉）。
  **批4（M6/M8）**：`goliath`/`erosion_tower_group` 的进场/死亡**镜像端跳过相机/暂停演出**（只播动画，避免镜像本地 `get_tree().paused`），host 侧不变；`pyroxenes` 生成发 `on_pickup_spawned` → 广播纯视觉副本（`_layer_group_of` 加 `CoinRoot`）。**未做**：medkit（各端独立随机生成，属设计）、coin_box 抛物线只同步起点、SceneProp（油桶，当前关卡未放置）。
  **通用教训**：① 镜像敌人必须"视觉激活与 AI 解耦"——`active_state()` 会重开 AI，须在其后再关；② 镜像敌人动画需 host 权威状态位驱动（否则修停 AI 后会冻住）；③ 复用型池化特效需在**激活点**广播而非 `child_entered_tree`；④ Boss 演出里的 `get_tree().paused`/相机移动必须按端隔离，镜像不能本地执行。实测（双进程 LAN）：镜像敌人 `root_phys=false sm_phys=false`、状态随快照切换（1->1 等）；`--coop-devspawn` 生成真实 sweeper 后 `enemies=11`；综合回归零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 批A：客机重复刷怪门 + host 敌人锁定客机玩家 + 角色事件通道接口
- Evidence / 证据: 参考版 `scenes/manager/enemy_manager.gd:round_enemy_spawn_start` 有 `if is_lan_game and not multiplayer.is_server(): return`，我们无 → 客机第 2 回合起本地刷怪（`round_manager._on_round_start`→`emit_round_start`→`enemy_manager`，`GameEvents.round_upgrade_end.connect(_on_round_start)`）。参考版 `script/entity_ENEMY.gd:215-245 get_nearest_player`（扫 "Player" 组、客机跳镜像），我们 `_select_target` 直接返回 `_ready` 缓存 `get_first_node_in_group("Player")`，且镜像被移出 "Player" 组（`coop_net.gd:spawn_remote_player`）→ host 敌人只追 host。参考版 `broadcast_player_character_event`（`NetworkManager.gd:727`）+ `apply_network_character_event`。
- Notes / 说明: **H1**：`script/extension_hooks.gd`+`round_enemy_spawn_gate`；`enemy_manager.round_enemy_spawn_start` 首行 gate；mod `_gate_round_enemy_spawn()`=非 host 返回 true（测试房无回合，未实测，以逻辑+参考版一致为准）。**H2**：`entity_ENEMY._select_target` 改走 `get_nearest_player()`（物理帧缓存；`multiplayer.multiplayer_peer!=null and is_server` 时加扫 `"RemotePlayer"`；`_is_valid_player_target` 过滤 `is_downed`）；并把子类绕过 `get_target()` 的选敌点改用它：`enhanced_sweeper.get_direction_to_player`、`modded_sweeper.get_direction_to_player`、`sweeper` 冲撞距离、`goliath` 5 处 `player.global_position`→`get_target_position()`、`enemy_tank` 守卫/`tank_gun_1` 目标。**M5**：`extension_hooks.gd`+`on_character_event`；`player.gd`+`broadcast_character_event`/`apply_network_character_event`（转发子节点，同 `apply_network_character_state` 款式）；mod `_on_character_event`/`_server_character_event`/`_remote_character_event`/`_apply_character_event`。**通用教训**：联机镜像一旦移出 `"Player"` 组（为修面板缓存），所有"敌人选敌/朝向/开火"里直接 `get_first_node_in_group("Player")`/`player.` 的路径都会退化为只认本机，必须统一改走 `get_target()`；敌波生成入口（`enemy_manager.round_enemy_spawn_start`）必须按端门控。实测（双进程 LAN `--coop-devspawn`）：host 敌人 `get_target()` 指向 `CoopRemote_*[RemotePlayer]`；M5 探针客机发 `dev_probe`→host `apply_character_event node=ok`；综合回归零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05
- SUPERSEDED: 2026-10-07 上述 `enhanced_sweeper.gd`/`modded_sweeper.gd` 实为**孤儿脚本**（两场景根脚本本就是 `sweeper.gd`），已删除；运行期增强/改装清扫者选敌走 `sweeper.gd` 的 `get_target()`。

### [Mod] 批B–E：切包/可靠通道/枪口闪光/升级就绪/特效池化/伤害洞/掉落事件
- Evidence / 证据: 参考版 `NetworkManager.gd:27 BULLET_BATCH_LIMIT=128`、`_flush_pending_bullet_batches` 切包（1379-1412）、`_server_visual_effect` reliable（1476-1491）、`broadcast_player_bullet_reliable`（652-667）、`UpgradeScreen.gd:224-250` 就绪指示；`NetworkVisualSync` 特效池化（54-192）；`_open_player_damage_hole` 遍历全部（334-394）；`_apply_shared_pyroxenes` 发拾取事件（1717-1723）。
- Notes / 说明: **批B**：`coop_net._flush_visuals` 改按 `BULLET_BATCH_LIMIT=128` 切包（`_send_visual_batches`）；特效批 RPC 改 `reliable`；新增 reliable 子弹通道（`_pending_visual_reliable` + `_spawn_visual_bullet_reliable_batch`/`_server_...`，按 `bullet.has_meta("coop_reliable_visual")` 路由）；`player_gun._shoot` 每次开火发 `on_visual_activated`（修枪口闪光只在首次）。**批C（M4）**：`GameEvents.upgrade_ready_changed(slot,is_ready)`；`UpgradeScreen` 代码构建 3 个就绪标签并连接；mod `_gate_round_upgrade_end`/`_server_round_upgrade_ready` 广播 `_remote_round_upgrade_ready_changed`，接收端按本端视角槽位 `_upgrade_slot_for`（排除自己）emit。**批D（M6）**：`coop_visual_sync` 新增 `_effect_pool`（按 scene_path，仅缓存有 `is_idle` 的可复用特效；`_acquire_effect`/`_track_effect`），`spawn_visual_effect` 复用而非每次 instantiate；`reset()` 一并清空。**批E**：L3 `_apply_shared_pyroxenes_local` 补 `emit_pyroxenes_pick_up`；L4 选人等待消息带 `(已选/总数)`；L5 `_summoned_root(scene_path)` 对 `shiroko_drone` 返回 `EquipLayer`；L6 `_open_player_damage_hole` 遍历全部 HitBox。**未做**：L1（我们 gate 是同步替换、无需等待）、L2（本地倒地全屏演出/慢动作，属体验向、留待按需）。实测：综合回归（spawn/preplaced/owner/buff/ring/bullet/effect/coin/follow/items/charevent）零错误；`enemy net=1 target=CoopRemote_*[RemotePlayer]`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] L2：本地倒地全屏灰度遮罩 + 短暂慢动作
- Evidence / 证据: 参考版 `ui/game_over_page.gd:183-206 player_down_screen/player_revived_screen`（`motion_screen.material` 设 `grayscale`、`Engine.time_scale=0.1` 0.5s 后恢复）；本体 shader `shaders/motion_screen.gdshader`（`f`/`v`/`grayscale`，`ui/game_over_page.tscn:24-26` 用 `f=1.1,v=15.0,grayscale=true`）；本体 `script/player.gd:140/146` 发 `ExtensionHooks.on_player_downed/on_player_revived`。
- Notes / 说明: mod 新增 `ui/motion_down_screen.gd`（CanvasLayer，复用本体 `motion_screen.gdshader`，全屏 ColorRect，淡入/淡出 + `Engine.time_scale=0.1` 0.5s 后恢复）；`coop_net` 在本地玩家下/复活时 `_show_motion_down`/`_hide_motion_down`（`_on_player_downed`/`_on_player_revived`/`_apply_revive_local`），并在 `_reset_player_sync` 收起。**纯本地表现**，不影响其它端（`Engine.time_scale` 仅本进程）。**通用教训**：`Engine.time_scale` 会拖慢同进程的 `create_timer`，恢复计时须用 `create_timer(t, true, false, true)`（ignore_time_scale）。实测（双进程 LAN `--coop-devmotion`）：客机 `show`→`hide`、`time_scale` 恢复 1.0；综合回归零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 敌人策反同步 + host 敌人 buff 广播（超出参考版）
- Evidence / 证据: 参考版 `NetworkManager` **无**策反/阵营同步（比对确认为共享限制）。本体：`script/entity_ENEMY.gd`（`apply_conversion_power`/`_on_convert`/`_on_revert`/`convert_gauge`/`Converted` 组/`_set_convert_visual`/`_convert_tick`），`script/health_component.gd:85/211`（伤害带 `convert_power`），`scenes/player/ako/ako_chain.gd:72`、`scenes/update_item/yukari_doll.gd:57`（**直接调用** `apply_conversion_power`）。buff：`scenes/manager/buff_manager_base.gd:81 apply_buff` + `enemy_buff_apply_gate`；mod `_gate_enemy_buff_apply`（`:434` host 返回 false→host 发起 buff 不广播）。
- Notes / 说明: **策反**：`ExtensionHooks.enemy_conversion_interceptor`（`apply_conversion_power` 入口拦截）；客机转发 `_server_enemy_conversion` 由 host 权威结算；快照新增 `conv_flags`/`gauges`，`CoopEnemyProxy.apply_snapshot(..., converted, gauge)`（仅在变化时）调 `entity_ENEMY.apply_network_conversion(gauge, converted)`（只做阵营/组/描边/gauge，无 buff/音效/damage_data）；`_convert_tick` 镜像守卫。伤害型 `convert_power` 本就随 `_damage_to_dict`（`convert`）到 host。**host buff 广播**：`ExtensionHooks.on_enemy_buff_applied`（`apply_buff` 末尾 notify）；mod `_on_enemy_buff_applied`（`_applying_remote_buff`/非 host/非 ENEMY 跳过；`converted_buff` 不广播）→ `rpc("_remote_enemy_buff")`；**移除** `_server_apply_enemy_buff` 的显式 rpc（统一由 hook 广播，避免双播）；`_remote_enemy_buff` 跳过 `converted_buff`（镜像不加策反 card）。**通用教训**：① 直接方法调用（非伤害管线）的机制在客机上只作用于镜像，必须像伤害一样经 hook 转发 host；② 状态类机制（策反/阵营）适合走快照变化检测、镜像只复刻表现；③ host 发起的实体状态若原本只写本地（buff 应用 gate 在 host 返回 false），需要单独的 host→client 广播通道。实测（双进程 LAN）：`--coop-devconvert` 客机转发→host `converted=true`、客机镜像 `true`、到期 revert 两端一致（无 ETN 报错）；`--coop-devbuff` host 施加→客机镜像 `keys=["poison_dot"]`；综合回归零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-05

### [Mod] 敌人部件（body_part）hp / 闪白 / 碎裂 / 预测同步
- Evidence / 证据: 部件 `script/enemy_part.gd`（独立 `@export var stats: EnemyStats` + 子级 `HealthComponent`；`_hurt_flash():87`、`idle_state():45`（`is_idle=1`、隐藏、断 `time_count`）、`active_state():66`（`is_idle=0`、`stats.spawn_hp()` 会**重置满血**）、`on_dead():102`→`idle_state`；`stats.is_dead`→`_on_enemy_stats_is_dead():99`）。`script/health_component.gd:31 take_damage` 先 `ExtensionHooks.intercept(enemy_damage_interceptor,[damage_data,owner])`；`:171 damage_taken.emit` 仅由 `suppress_feedback` 门控（`:79 suppress_proc` 只门控 `enemy_*_proc`）。部件当前仅 `scenes/enemies/tester_automaton_shield.tscn:177 body_part=[NodePath("Graphics/Shield")]` 使用。mod `net/coop_net.gd`：`_net_entity_of`（优先 `coop_owner_net_id`）、`_handle_part_hit`、`_server_enemy_part_hit`、`_connect_enemy_parts`/`_tag_enemy_parts`、`_on_server_enemy_part_damage_taken`、`_remote_enemy_part_hp`、`_enemy_part_hps`、`_spawn_enemy_remote(...,part_hps)`。
- Notes / 说明: **此前部件 hp 完全不同步**：部件镜像无 `net_id` meta → `_intercept_enemy_damage`/`_gate_projectile_self_hit` 直接放行 → 客机打部件只在本地镜像掉血；host 真实部件也各算各的。修法（mod-only）：① 镜像部件打 `coop_owner_net_id`/`coop_part_index` meta，`_net_entity_of` 优先返回部件 → 拦截器识别并转发；② 客机 `_handle_part_hit` **与根同款即时预测**（`_get_predicted_enemy_damage` + `_replay_hit_feedback` 闪白，部件无飘字节点故无飘字 + 乐观扣血 `predicted_hp` + 归零 `predicted_dead`/`idle_state`）→ `rpc_id(1,_server_enemy_part_hit)`；③ host `take_damage(data,true,false)`（不抑制 → host 原生闪白/受击音 + `damage_taken`），`_connect_enemy_parts` 连部件 `damage_taken` → `_on_server_enemy_part_damage_taken` → `rpc("_remote_enemy_part_hp",net_id,idx,hp,true)`（host 自身打 + 客机转发的**单一广播点**）；④ 镜像 `_remote_enemy_part_hp`：写 `predicted_hp`、撤销/触发 `predicted_dead`、`hp<=0`→`stats.hp=0`+`idle_state`（碎裂）、否则写 hp + `remote_flash_allowed` 门控的 `_hurt_flash`；⑤ 晚加入 `_enemy_part_hps` 随 `_spawn_enemy_remote` 一次性下发（`register_enemy_spawn` 与 `_send_existing_enemies_to_peer` 两处）。**关键坑**：`active_state()` 会 `stats.spawn_hp()` 重置满血 → 必须在 `active_state()` **之后**再写下发/预测的 hp。**根/部件组件误取**：`_health_component_of` 原为纯递归，对 `tester_automaton_shield` 会先进入 `Graphics` 子节点取到**部件**组件（`Graphics` 排在 `HealthComponent` 之前）→ 根伤害/预测/闪白都落到部件；改为**优先直属子级 HealthComponent**再递归，根与部件各自独立。实测（双进程 LAN `--coop-devpart`）：host 生成 `tester_automaton_shield` 部件 hp=[200]；客机打部件 50（实际生效 5）→ 两端 200→195、客机即时预测 after=195=settled=195；客机再打根 30 → 两端根 380→350 且部件仍 195（根/部件独立）；零红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06

### [Mod] #3 补充验证：host 打部件广播 + 重发已存在敌人携带 part_hps
- Evidence / 证据: `--coop-devparthost`（mod `net/coop_net.gd` 新增探针 `_dev_part_hp_applied`/`_dev_part_flash_applied` + `dev_part_stats()`）；`--coop-devrejoin`（`dev_resend_existing()`→`_send_existing_enemies_to_peer`、`dev_evict_enemy()`）；入口 `entry/coop_entry.gd`。
- Notes / 说明: ① **host 打部件 → 客机镜像同步**（此前只测了客机打）：host 用 `dev_hit_enemy_part` 打自己真实部件 200→195，客机镜像 `early=200 late=195`，`dev_part_stats()={hp_applied:1, flash_applied:1}` → 权威 hp 广播到达且闪白已应用（`_remote_enemy_part_hp` 的 flash 分支确实执行）。② **重发已存在敌人携带 part_hps**：客机 `dev_evict_enemy(1)` 移除镜像（part0=-1）后，host `dev_resend_existing()` → `_send_existing_enemies_to_peer` 重发，客机重新生成 net=1 且 part0 恢复到 host 当前值（190=190）；证明该路径的 `_spawn_enemy_remote(...,part_hps)` 与常规广播一致。③ **观察（非 #3 问题）**：`--coop-devbattle` 双端各自换场景，加入时会触发 host 再次 `host battle start`（场景重入），运行期临时生成的敌人不会在“中途加入”场景中被客机保留（预置敌人仍经 `_register_existing_test_room_enemies` 重建）；这是加入流程/scene 同步的既有行为，与部件无关，故“中途加入的部件 hp”无稳定可测场景，改以 `dev_resend_existing` 直接验证补发通道。
- Source / 来源: test + code
- Date / 日期: 2026-10-06

### [Mod] utaha_turret 开火后坐 tween 在远端 scale 不断放大（目标取当前值）
- Evidence / 证据: `script/turret_summoned.gd:_shootAnim`（原：`tween_property(sprite, "scale", 当前scale, dur).from(当前 − (0.15,−0.4))`）、`:network_play_action`（mod 加，`coop_net.gd:_remote_summoned_action`→`network_play_action("shoot")`）；`scenes/enemies/enemy_tank.gd:_shootAnim` 同款；`%Sprite2D` 由 `script/render_sprites.gd:12-20` 生成 `hframes` 个子 Sprite（初值 scale=1）。
- Notes / 说明: **根因**：tween 的**目标 scale 取"调用瞬间的当前 scale"**。远端镜像由 `shoot_timer.wait_time` 驱动 `dur=min(wait,0.3)`，但镜像的 `shoot_time_count` 不跑、`wait_time` 停留在场景默认，于是 `dur` 与拥有者实际射速不一致；当开火间隔 < `dur` 时两段 tween 重叠，下一次调用读到的"当前 scale"已是抬高的中间值 → 目标被抬高 → 起始再 `+0.4` → **每次开火让静止值上移，累积放大**。拥有者本地 `dur == 实际开火间隔`（`shoot_time_count` 每次设 `wait_time`），tween 恰好在下一发前结束，故只在远端暴露。**修法**：`_shootAnim` 改为**锚定每个 sprite 的基准 scale**（首次记录到 `_recoil_base`）+ 保存 `_recoil_tween` 并在开新动画前 `kill()` 上一段 → 幂等，不再累积；`enemy_tank.gd` 同款修。**后坐时长一致**：`ExtensionHooks.on_summoned_action` 通知新增第 7 参 `dur`（`extension_hooks.gd:56` 注释同步；`turret_summoned.gd` 开火传 `_recoil_duration()`、换弹传 `0.0`），mod `_on_summoned_action`/`_server_summoned_action`/`_remote_summoned_action` 透传 `action_dur`，`network_play_action(action, dur)` → `_shootAnim(dur)`，使镜像后坐时长=拥有者当前射速（对持久/升级后射速变化也正确）。**验证**：双进程 LAN `--coop-devitems --coop-devscale`（+`dev_turret_scale()` 打印 `%Sprite2D` 各子 scale）：连续 6 次采样（~12s，含 fast 0.24s/慢 1.0s 两种射速、拥有端与镜像端）scale 恒回落 ~1.0、峰值 ≤ ~1.39（后坐拉伸量），无累积放大；换弹动画正常；零红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06

### [Mod] follow_icon 简化（去 CharacterBody2D）+ 远端跟随链式同步
- Evidence / 证据: `scenes/update_item/follow_icon.gd`（原 `extends CharacterBody2D` + `move_and_slide()`）；15 个 `scenes/update_item/*_icon.tscn` 根为 `CharacterBody2D` 且**无** `collision_layer/mask`、无 `CollisionShape2D`/`Area2D` 子节点。本体链式机制见 `scenes/update_item/black_ninpero.gd:21-26`、`voodoo_doll.gd`、`equip_item.gd:69 attach_follow_icon`（从全局 `"Follow"` 组取 `follow_use==false` 的标记；每个图标场景内含 `Follow` 子标记，形成链表）。mod `net/coop_item_visuals.gd:build_icon`（原每个远端图标各自 `_ensure_marker(mirror,"follow")`）。
- Notes / 说明: **简化**：`follow_icon.gd` 改 `extends Node2D`，`velocity` 改为普通成员，`move_and_slide()` → `global_position += velocity * delta`（无碰撞形状时二者等价）；15 个图标场景根 `type="CharacterBody2D"` → `type="Node2D"`（仅改类型，无副作用）。**远端链式**：`build_icon` 的 `follow` 分支改为取同一镜像上一个图标——`prev = mirror.get_meta("coop_last_follow_icon")`，标记 `= prev.get_node_or_null("Follow")`；首个图标回退 `_ensure_marker(mirror,"follow")`（镜像玩家自身 `Follow`）；建好后 `mirror.set_meta("coop_last_follow_icon", icon)`。`coop_net._clear_peer_item_visuals`/`_clear_item_visuals` 释放图标时 `remove_meta`。**根因回顾**：镜像玩家的 `Follow` 被 `spawn_remote_player` 移出全局组（防污染），`_ensure_marker` 每次都在镜像玩家下新建标记 → 所有远端 follow 图标都追在玩家附近，不成链。**验证**：双进程 LAN `--coop-devfollows`（授予 6 件 follow 道具）+ 探针 `dev_follow_marks()`，两端链路径均为 `CoopRemote_X/Follow ← iconA/Follow ← iconB/Follow ← …`（一个跟一个），零红字。**注意**：同一 `PlayerRoot` 下本地与远端同名图标会触发 Godot 自动改名（`@Node2D@id`），无害；链按子节点名 `"Follow"` 解析，与图标自身名字无关。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06

### [Mod/Base] 联机测试房主机首件道具属性被重置：`test_room.reset_data` 早退致 `base_*` 未捕获
- Evidence / 证据: `scenes/main/test_room.gd:reset_data()` 开头 `player = get_first_node_in_group("Player"); if player == null: return`；`PlayerData.base_*` 默认全 0（`script/PlayerData.gd:60-80`）；`update_player_ability()` 用 `base_*+累加器` 重算（`PlayerData.gd:342+`）；`base_*` 仅由 `test_room.reset_data()`（`:48`）与 `main.first_round()`（`main.gd:56`）捕获。诊断实测（双进程 LAN `--coop-devbattle --coop-devitems`）：主机 `test_room.reset_data enter player=false`（此后无 reset_date/get_player_base_ability 打印）→ `base_max_hp=0`；客机 `player=true` → `base_max_hp=72`。mod `net/coop_net.gd:1855` 早已注释此早退并只补 `emit_get_player`（未补 base 捕获）。
- Notes / 说明: **现象**：主机开房进测试房，拿第一个道具时属性全部塌成默认（`max_hp≈1`、`bullet_damage≈1`…），手动重置角色后恢复。**根因**：LAN 下本地玩家由 `GameEvents.change_scene` 延迟 `add_child`，而 `test_room._ready` 用 `await create_timer(0.1)` 后 `reset_data()`，主机此时可能尚未入 `"Player"` 组 → 早退 → `PlayerData.reset_date()`/`get_player_base_ability()` 全跳过 → `base_*` 保持默认 0；首个道具触发 `EquipItem._ready → update_player_ability()`，用 `base_*=0` 重算 → 属性塌成默认。**修法（本体）**：`test_room.reset_data()` 不再"玩家为空即 return"，改为**有界等待玩家入组**（最多 30 帧）+ 重置令牌 `_reset_token` 防并发/过期；等待到则完整执行 `reset_date`/base 捕获/`update_*`/`emit_*`。`main.first_round()` 亦加同样的有界等待守卫（正常关卡因 `first_round_add` 是 `add_child` 之后的 deferred、玩家场景根自带 `groups=["Player"]`，本不会触发，仅防御）。**另修**：`coop_net._server_player_selected` 增加 `battle_active` 分支——已开打时**不重载整局**（原会 `GameEvents.change_scene` 触发 `first_round`/`reset_data` 清空主机进度与属性），改为只给新客机 `_remote_change_scene` 并补生在局镜像/敌人/召唤物。**验证**：修复后主机 `base_hp=72`（修复前 0）、`dev-items granted` 正常；中途加入 `host battle start` 仅 1 次且新玩家正常入局；综合回归（items/buff/convert）零红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06

### [Mod] 远端玩家镜像受击闪白卡住不恢复：漏启动 InvincibleFrame 计时器
- Evidence / 证据: 本体受击路径 `script/player_health_component.gd:116-125`（`owner.invincible_frame.start()` + `owner._on_invincible_frame(true)`）；`script/player.gd:417 _on_invincible_frame(anim)` 只把 `flash_opacity` 设为 1，`await 0.1s` 后降 0.3，**不归零**；归零在 `player.gd:436 _on_invincible_frame_end()`，由 `InvincibleFrame`（Timer `wait_time=0.5, one_shot=true`，`player.gd:97` 连接 `timeout`）触发。mod 旧实现 `net/coop_net.gd:_remote_player_hurt` 只 `p.call("_on_invincible_frame", true)`。
- Notes / 说明: **现象**：主机视角下客机镜像受击后一直卡闪白（停在 0.3），拥有者自身正常。**根因**：mod 对远端镜像只调了 `_on_invincible_frame(true)`，未 `start()` 镜像的 `InvincibleFrame` 计时器 → `timeout → _on_invincible_frame_end` 永不执行 → `flash_opacity` 不归零。**修法**：`_remote_player_hurt` 复刻本体组合——先 `p.get("invincible_frame").start()`（回退 `get_node_or_null("InvincibleFrame")`）再 `_on_invincible_frame(true)`；连续受击时每次 `start()` 重新计时（同本体）。**不需动本体**：`coop_player_proxy._disconnect_remote_global_signals` 只断开来自 `GameEvents`/`PlayerData` 的信号，不会断 `InvincibleFrame.timeout`，故镜像的归零回调仍有效。实测（双进程 LAN，客机周期对自己放敌方向激光、主机轮询镜像 `flash_opacity`）：`1.00 → 0.30 → 0.00`，受击后 ~0.5s 归零，不再卡住；零红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06


### [Mod] 联机准备房流程：测试房作为准备房（选人 / 就绪 / 房主难度）
- Evidence / 证据: mod `mod_sdk/coop_mod/mods/etn_coop/net/coop_flow.gd`（编排）+ `net/coop_net.gd`（`FlowPhase` 状态机、`select_begin/select_all_ready/select_cancelled/select_ready_changed` 信号、`enter_lobby/request_begin_select/report_select_ready/_maybe_finish_select/cancel_select`、`_gate_change_scene` 的 `ALL_READY` 分支、`_build/_apply_level_state` 增 `game_mode`）；UI `ui/coop_room_label.gd` / `ui/coop_start_ball.gd` / `ui/coop_select.gd` / `ui/coop_ready.gd` / `ui/coop_difficulty.gd`；本体 `resources/level/level.gd` 增 `@export level_scene_path`。
- Notes / 说明: 关键坑：① **进准备房不得触发选人握手**——`enter_lobby()` 置 `_force_release=true`、走 `_gate_change_scene` 顶部短路并广播 `_remote_change_scene`，否则会把测试房当战斗、等全员选人而卡死。② **选人阶段不得自动开战**——`_server_player_selected` 在 `_select_flow_active` 时**只记录** `selected_player_scene_by_peer`，否则全员点完角色立刻 `_broadcast_roster` 跳过难度。③ 房主难度走本体 `level_button` → `GameEvents.change_scene` → gate 的 `ALL_READY` 分支统一广播 roster + `game_mode`；游戏模式即 `PlayerData.game_mode`（字符串数组）随 `level_state` 下发。④ 覆盖层挂当前场景下（切场景自动释放），引用处一律 `is_instance_valid` 守卫。⑤ dev 无头自测若在 autoload `_ready` 内直接 `change_scene` 会丢 `first_round_add`（主机的开始球不生成）——`--coop-devflow` 先等 1s 主场景稳定；`--coop-devbattle` 用 `auto_enter_lobby=false` 保持旧语义。⑥ 开始球复用本体 `ball.gd`（`extends`），实例 `yellow_ball.tscn` + 绿色 `modulate`，不新增贴图；覆写 `_physics_process` 防本体按 velocity 把动画冻住。⑦ **房主转场**：`enter_lobby`/`begin_battle` 直连 `GameEvents.change_scene`，须先 `await _play_scene_transition_start()` 才有左划转场（否则硬切），详见下方同主题条目。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06


### [Mod] 联机准备房：选人阶段全局暂停 + ESC 分层语义 + 难度被已就绪遮盖
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_ready` 设 `PROCESS_MODE_ALWAYS`、`_set_select_pause()`、`request_begin_select/_remote_select_begin` 暂停、`begin_battle/gate ALL_READY/_remote_change_scene/_reset_run_state` 解除、`abort_select_to_lobby/_remote_abort_select_to_lobby`、`is_all_ready()`）；`net/coop_flow.gd`（`_on_character_confirmed` 顺序、`_dismiss_select` 延迟释放、`_close_ready` 立即隐藏、`_on_select_aborted`）；`ui/coop_select.gd`（`_unhandled_input` 吞 Esc + 房主 abort）、`ui/coop_ready.gd`/`ui/coop_difficulty.gd`（`PROCESS_MODE_ALWAYS`，难度 `layer=102`）。
- Notes / 说明: **① 选人阶段整体暂停**：用户期望房主开始后测试房停止活动。做法是各端 `get_tree().paused=true`；因 `player.gd:195-202` 在 `player_stop==false` 时按 `pause`(Esc) 会开暂停菜单，暂停后 player 被冻结不再收输入，加上覆盖层 `_unhandled_input` 吞 Esc，双保险。`CoopNet` 必须 `PROCESS_MODE_ALWAYS`，否则暂停期间 `_physics_process` 停（状态上报/快照停，恢复跳变），虽 RPC 回调本身不受 pause 影响，但设为 ALWAYS 更稳。覆盖层也必须 ALWAYS：否则暂停下 Controls 不处理输入，且卡片 `add_card` 动画不播完 → `mouse_filter` 停在 IGNORE 无法点击。**② ESC 分层**：选人层（房主未选角）→ `abort_select_to_lobby()` 取消整轮回准备房并解除暂停；已就绪层 → 仅取消本人；难度层 → `cancel_select()` 回选人层（后两者世界保持暂停）；客机在选人层 Esc 仅吞掉。**③ 难度被已就绪遮盖根因**：`_on_character_confirmed` 里 `report_select_ready(true)` 早于 `_open_ready()`；房主作为最后就绪者时该调用**同步**触发 `select_all_ready` 先开难度，之后才 `_open_ready` 叠上去。修法：把 `report_select_ready` 放到最后，`_open_ready` 加 `is_all_ready()/_difficulty` 守卫，`_close_ready` 先 `visible=false`，难度层 102 > 已就绪 101。**④ 释放时机**：确认角色后不要立即 `queue_free` 选人层（`player_card.add_player` 的 `await` 会在被释放的实例上恢复），改为 `visible=false` + 0.4s 后释放。验证：`--coop-devflow` 两端选人期 `paused=true`、进关卡解除；`--coop-devflow --coop-devabort` 两端 `phase=1 paused=false`；无红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06


### [Mod] 本体 sprite_outline shader 吞掉 modulate：用同款 shader + tint 染绿开始球
- Evidence / 证据: `shaders/sprite_outline.gdshader:7-29`（`COLOR = mix(outline, texture(TEXTURE, UV), orginal_color.a)`，全程未读取传入的 `COLOR`/modulate）；`mod_sdk/coop_mod/mods/etn_coop/ui/coop_start_ball.gd`（`GREEN_SHADER_CODE` 常量 + `_apply_green_material()` 用代码构建 ShaderMaterial）。
- Notes / 说明: **现象**：给开始球的 `AnimatedSprite2D.modulate` 设绿色无效，球仍是本体黄色。**根因**：`canvas_item` shader 若在 `fragment()` 里直接 `COLOR = texture(...)`，不乘传入的 `COLOR`（其中含 `modulate`/父级调制）就把它丢弃——所以带 outline shader 的 sprite **modulate 完全失效**。**修法**：在脚本里用代码构建同款 shader（加 `uniform vec4 tint`，`c.rgb *= tint.rgb`）替换该球 Sprite 的 `ShaderMaterial`，既显绿又保留 `outline` 高亮（`ball.gd:set_highlight` 仍写 `outline_width`）。**另一坑**：`ball.gd` 的可推动/碰撞在 `_physics_process` 与 `_on_push_box_body_entered`，覆写它们会失去“和其它球一样”的碰撞互动；染绿开始球须 `super()` 复用本体 `_ready`、**不**覆写这两个方法、并保留根节点 `Capsule`/`UseItem` 组与碰撞层。验证：`--coop-devflow` 两端 `start ball spawned`、流程正常；`material_manage.shader_validate` 通过；无红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06


### [Mod] coop UI 场景化 + 编辑器镜像（mod_sdk 构建源 + res://mods/etn_coop 可编辑镜像）
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_{select,ready,difficulty}.tscn`、`ui/coop_start_ball.tscn`；`net/coop_flow.gd` 改为 preload `.tscn` 并 `instantiate()`；`script/mod_manager.gd:463-464`（`replace_files` 取自 manifest，默认 false → 本体优先）；`export_presets.cfg` 四个 preset 的 `exclude_filter` 追加 `mods/etn_coop/*`；镜像 `H:\Enter The Nyangeon\mods\etn_coop\`。
- Notes / 说明: `mod_sdk/.gdignore` 让 Godot 编辑器完全看不到 mod 源，无法可视化编辑 UI。做法：把整套 mod 源另复制一份到本体工程 `res://mods/etn_coop/` 作为“编辑器镜像”，场景里脚本 `[ext_resource]` 统一写 `res://mods/etn_coop/...`（与运行期 pck 路径一致，编辑器与 pck 都能解析）。**构建始终从 `mod_sdk/coop_mod/mods/etn_coop/` 打包**（`build_coop_mod.ps1`）。因 `replace_files=false`，运行期本体 `res://mods/etn_coop/` 会遮蔽 pck 同名文件 → 开发时改镜像即时生效，但两处需同步。导出用 `exclude_filter="... , mods/etn_coop/*"` 排除镜像源码。三个覆盖层从代码 `_build()` 改为 `.tscn` 静态布局 + 脚本 `@onready %` 动态填充；`layer`/`process_mode` 写在场景里，**勿在脚本 `_ready` 里再写死**（否则编辑器里调整会被覆盖）。验证：`--coop-devflow` 两端流程正常（选人/就绪/难度/开始球/暂停/进关卡），编辑器 `filesystem scan` 后可见并可打开这些 `.tscn`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06


### [Mod/Base] 社团注册表与“只实例化已解锁”（社团/角色/支援）
- Evidence / 证据: `script/mod_manager.gd`（`const BASE_SOCIETIES`、`get_base_societies()`、`_build_reserved_ids`）；`scenes/main/menu_screen.gd`（`_setup_societies`/`_current_unlocked_gids`/`_sync_societies`）；`scenes/main/menu_screen.tscn`（删 6 个内联社团节点 + ext_resource）；`ui/society_card.gd`（`_peek_player_card` + 改造 `populate_player_cards`）；`ui/mod_society_base.gd`/`ui/mod_society_card.gd`；`ui/character_shop_card.gd:add_character`（末尾 `GameEvents.emit_check_data()`）；`mod_sdk/coop_mod/mods/etn_coop/ui/coop_select.gd`。
- Notes / 说明: ① **社团单一来源**：本体社团原来硬编码在 `menu_screen.tscn`（6 内联节点）与 coop 选人里；改为 `ModManager.BASE_SOCIETIES`（id+scene）+ `get_base_societies()`，menu 与 coop 都从这里生成（coop 另加 `get_mod_societies()` + MOD 通用卡）。本体以后加社团只改一行。② **本体必须“只实例化已解锁 + 动态补建”**：菜单是常驻场景，玩家会在**商店当场解锁新社团**（`character_shop_card.add_character()` 往 `PlayerData.group/character` 追加），所以不能只在 `_ready` 建一次；改为首建已解锁 + 监听 `GameEvents.check_data`（`add_character` 末尾新增 emit，`cost==0` 也能触发）→ `_sync_societies()` 比较解锁 gid 列表，变化才重建（`check_data` 在菜单按钮交互时也发，靠差异挡掉）。③ **不实例化锁定角色**：`ui/society_card.gd:populate_player_cards` 原为 `load(path).instantiate()` 后判 `PlayerData.character.has(id)`，锁定实例未 `free()`（泄漏）；改为先用 `PackedScene.get_state().get_node_property_value(0, …)` 读根节点导出的 `player_card.id` 预判（兼容 `uid://` 路径，`DC_card` 即用 uid），只对已解锁实例化；peek 失败回退“实例化→判断→free”。④ **支援**只取 `SupportData.support_data`（已解锁），与本体关卡选择一致。验证：`_peek` 六个社团卡均正确读出成员 id；直接以 `res://scenes/main/menu_screen.tscn` 作主场景 headless 启动无报错；`--coop-devflow` 回归通过。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-06


### [Mod] 大厅「已准备」门槛：开始球非房主准备 + 房主门槛 + 名牌准备标签
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`lobby_ready_by_peer` + `toggle_local_ready`/`_server_lobby_ready`/`_remote_lobby_ready`/`_apply_lobby_ready`(幂等)/`are_all_players_ready`/`_clear_lobby_ready`/`_set_player_ready_tag`/`_refresh_all_ready_tags`；在 `request_begin_select` 调 `_clear_lobby_ready`，`enter_lobby`/`_reset_run_state`/`begin_battle`/`abort_select_to_lobby` 清）；`net/coop_name_tag.gd`（子标签 `ReadyTag` + `set_ready()`）；`ui/coop_start_ball.gd`（`interact` 分支 + `_show_not_ready_hint()`）；`i18n/coop_i18n.gd`（`coop_prepared`/`coop_players_not_ready`）。
- Notes / 说明: ① 大厅「已准备」(`lobby_ready_by_peer`) 与选人「已就绪」(`select_ready_by_peer`) 是**两套独立状态**，不要混用。② 房主**不计入** `are_all_players_ready()`（遍历 `multiplayer.get_peers()`；无客机=true，房主可单独开始）。③ 同步：非房主 `toggle_local_ready` 本地乐观 + `rpc_id(1,"_server_lobby_ready")`，host `_apply` 后 `rpc("_remote_lobby_ready", sender, value)` 回播；`_apply_lobby_ready` 幂等（同值直接返回）避免回播重复触发动画。④ 进入选人时 `_clear_lobby_ready()` 清空并 `rpc("_remote_lobby_ready_clear")`（否则客户端名牌标签残留）；断线/回准备房/开战亦重置。⑤ 名牌「已准备」是 `coop_name_tag` 的**子 Label**，随名牌每帧 `position` 更新 → 自动跟随跳跃；0.1s `modulate.a 0→1` + `position:y` 自下而上（≈8px），取消时反向并隐藏。⑥ 开始球红字提示**仅房主端本地**（host 互动但未全员时就绪时），0.1s 进 → 停 2s → 0.1s 收。验证：`--coop-devflow --coop-devready` 双进程，host `before-all=false → after-all=true`（wait≈1.0s）后进选人；无红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07


### [Mod] 选人/难度 UI 顺序 + 动画接入 + 难度按钮激活 + 绿球贴图随 mod 运行时建帧
- Evidence / 证据: `net/coop_flow.gd`（`_on_character_confirmed` 改 `_set_select_interactive(false)` + `_open_ready` 遮盖、不再 `_dismiss_select`；`_on_ready_cancel`/`_on_select_cancelled` 用 `_set_select_interactive(true)`；`_on_select_aborted` 才 `_close_select`；`_close_difficulty` 先 `play_hide` 再 0.4s 释放）；`ui/coop_select.gd`（`set_interactive(v)` = `process_mode ALWAYS/DISABLED`、`play_hide`）；`ui/coop_difficulty.gd`（`_ready` 里 `_populate_levels()` 后 `player_selected.emit()` + `_anim.play("show_anim")`、`play_hide`）；`ui/coop_start_ball.gd`（`_apply_green_frames`/`_load_green_texture`，删 `GREEN_SHADER_CODE`）；新增 `sprites/item/green_ball.png`（随 mod 打包）。
- Notes / 说明: ① **顺序/遮盖**：选人层(layer100)、已就绪(101)、难度(102)——确认角色后**不收回**选人层，先 `set_interactive(false)`（`process_mode=DISABLED`，禁其输入与 `AnimationPlayer`）再打开已就绪层**遮盖**它；就绪/难度取消时 `set_interactive(true)` 原位恢复（无需重播进场）；只有真正关闭（房主整轮取消）才 `play_hide` 倒放 + 延时释放；进关卡由场景切换接管、不收回。② **难度按钮初始不可点**：`level_button.tscn` 根 `mouse_filter=2`（IGNORE），`level_button.gd:_ready` 靠 `level_select.player_selected → open_mouse` 才开；本体流程会发该信号，coop 难度层必须自己 `player_selected.emit()`（在 populate 之后）激活，否则“难度选择按钮是关闭状态”。③ **mod pck 的 png 无导入资源**：不能作 `.tscn` 静态 `Texture2D` 引用；`coop_start_ball` 在 `_ready` 用 `load()`（编辑器内命中已导入）否则 `Image.load_png_from_buffer` 取图，按**与本体黄球一致的 20 区/顺序**构建 `SpriteFrames`（帧序不变），保留本体 `sprite_outline` 材质。④ `AnimationPlayer.play_backwards("show_anim")` 需该层 `process_mode` 非 DISABLED（关闭前若被禁用要先恢复）。验证：`--coop-devflow` 两端 `start ball spawned`、无 AnimationPlayer/脚本红字；`find_symbols` 全通过。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07


### [Mod] 房号显示调整：准备房右上角 + 关卡内暂停页
- Evidence / 证据: `ui/coop_room_label.gd`（字体 `BoutiqueBitmap7x7_1.7`/字号 10、`_process` 仅在 `current_scene_path` 含 `test_room` 且 `_select_flow_active==false` 时显示）；`net/coop_net.gd:_on_pause_visibility/_update_pause_room_label/_build_pause_room_label`（在 `pause_screen` 的 `Node2D10/Node2D9/langue_button` 下方 `+PAUSE_ROOM_OFFSET_Y(40)` 插 `PanelContainer+Label`）；本体 `ui/pause_screen.tscn`（`langue_button` 实例位置 `(-27,-24)`，LANGUAGE 下拉占 y13..33）。
- Notes / 说明: 房号在准备房显示右上角；进入选人/关卡隐藏；关卡内在**暂停页**显示（暂停页 `ui/pause_screen.tscn` 的主菜单组 `Node2D10/Node2D9` 里有 `langue_button`(LANGUAGE)——把 Label 挂到其父、位置 = `langue_button.position + (0,40)`，即下拉正下方）。样式：暂停页为深色小面板 + 白字 + 深绿描边（`Color(0.03,0.28,0.10)`）；右上角保留绿字。**耦合点**：暂停页内部路径 `Node2D10/Node2D9/langue_button` 若本体重构会失效（已加回退：找不到则挂暂停页根固定位置）。纯 mod 实现，不改本体。验证：`--coop-devflow --coop-devpause` host `dev-pause open/closed` 正常、无红字。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07


### [Mod] 联机队友头顶生命条（含临时生命）+ 倒地呼吸红 + HELP!
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_health_bar.gd`（新增，`extends Control` + `_draw()` 自绘）；`net/coop_name_tag.gd`（布局常量、`attach_health_bar()`、`HelpTag`/`_update_help()`）；`net/coop_net.gd`（`_attach_name_tag` 仅远端挂条、`_send_local_player_state`/`_server_receive_player_state`/`_apply_player_state` 增 `t_hp`/`max_t_hp`、`dev_health_state`）；`net/coop_player_proxy.gd:apply_state`（同步 `max_t_hp`/`t_hp` + `net_t_hp` meta）；`i18n/coop_i18n.gd`（`coop_help`）；`entry/coop_entry.gd`（`--coop-devhp`）。
- Notes / 说明: ① 生命条数据源统一 `player.get("stats")`：本地直读实况，远端读 proxy 写入的镜像 stats。**临时生命此前不同步**（远端 `t_hp` 恒 0，本体 `Stats.t_hp`/`max_t_hp` 见 `script/Stats.gd:173-183`），故玩家状态 RPC 新增 `t_hp`/`max_t_hp`（追加在 `max_hp` 之后，带默认值向后兼容）；proxy 设置必须**先 `max_t_hp` 再 `t_hp`**（`t_hp` setter 依赖上限 clamp）。② 倒地**无需新增同步**：远端已由 `_remote_player_down_changed → player.set_downed_state` 设 `player.is_downed`（`script/player.gd:41`），血条与 HELP! 直接读该属性；倒地血条整条呼吸红（`sin`），并显示 HELP!（`BoutiqueBitmap7x7`/字号 12/白字红边，`sin` 上下浮动）。③ 布局（名牌本地坐标）：`HelpTag -31 / ReadyTag -17 / CoopHealthBar -6 / 名牌文本 0`；`ReadyTag` 上移为血条预留槽（本地/远端一致，本地无条也留空）。④ 仅远端挂条：`peer_id != 本机 id` 才 `attach_health_bar`；本地玩家自身血量见底部 HUD。⑤ `hp` 仍由 proxy clamp ≥1，倒地只由 `is_downed` 呈现（不显示 1 点血）。验证：双进程 LAN `--coop-devhp` 客户端可见 host 的 `hp`/`t_hp`；定向脚本验 `HelpTag`/`CoopHealthBar` 位置（-31/-6/78）、倒地可见+浮动、恢复隐藏、`ReadyTag=-17`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [UI] 顶层 Control/PanelContainer 固定锚点偏移不随子内容自动改宽，需 reset_size + 手动贴边
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_room_label.gd`（原 `offset_left=-300`/`offset_right=-8` 固定 292px 宽 → 黑色底板过大；改为 `_panel.reset_size()` + 每帧 `_panel.position = Vector2(vw - _panel.size.x - 8, 8)`）。
- Notes / 说明: CanvasLayer 下作为顶层 Control 的 `PanelContainer`，其 `size` 由 anchors/offsets 决定；子 `Label` 文本变长**不会**让父容器自动加宽（仅设 `grow_horizontal` + 双边右锚在本场景实测无效，`panel.size` 恒为初值）。可靠做法：文本变更后 `reset_size()`（把 size 撑到 `get_combined_minimum_size()`）再手动定位；`Label.horizontal_alignment=RIGHT` 保持右对齐，右缘固定距屏幕右 8px。定向脚本验证：`192.168.1.5:24591` → 98x17、`ROOM1234` → 66x17，右缘均 632（视口 640）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 房主离开（硬杀/掉线）检测与统一回主菜单
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_on_peer_disconnected`/`_on_server_disconnected`/`_should_return_client_to_menu`/`_schedule_host_left_return`/`_handle_host_left`/`_show_session_closed_notice`、`_network_heartbeat`/`_host_heartbeat`、`HOST_TIMEOUT_MSEC`、`MENU_SCENE`）；`i18n/coop_i18n.gd`（`coop_host_left`）；`entry/coop_entry.gd`（`--coop-devhostdrop`/`--coop-devquit`）。
- Notes / 说明: ① 房主硬杀时 ENet 在本机不一定及时触发 `server_disconnected`（实测 40s 内无），必须加**应用层心跳**：房主每 1s `_host_heartbeat`（reliable），客户端 8s 未收到即判定离开；战斗期 `_apply_player_state`(~20Hz) 也刷新存活时间。心跳用墙钟（`Time.get_ticks_msec`）计时——`Engine.time_scale` / 场景切换会让基于 delta 的计时漂移。② **严禁在 multiplayer 信号回调栈内释放传输**（`multiplayer.multiplayer_peer = null`）→ segfault；先同步占位去重，再 `call_deferred("_handle_host_left")`，入口 `await tree.process_frame` 脱离回调栈。③ 客户端处理器统一：解除暂停（选人/升级暂停会让客机卡住）→ 底部 toast（挂当前场景下新建 CanvasLayer，随切场景释放）→ 过场 → `GameEvents.change_scene(menu,"")` + 鼠标可见；去重标志 `_returning_to_menu_due_to_close` 在 `_reset_run_state` 清零。④ **自测坑**：无头 `--coop-devbattle` 套件末尾会自行 `close_connection(true)` 并 `quit()`，会掩盖断线检测（曾误判为“未检测到”）；验证房主离开须用 `--coop-devquit`（跳过套件关连接/退出，改由回菜单后 `tree.quit()` 刷新日志）。验证：优雅 `--coop-devhostdrop` 即时检测；硬杀 host 约 8s 后检测并回 `menu_screen`；正常对局 20s 无误报。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 网络补偿：快照缓冲插值 / 自适应延迟 / 快照分频（纯 mod）
- Evidence / 证据: `net/coop_snapshot_buffer.gd`（新增：`push`/`sample`/`compute_delay`，外推 `EXTRAP_MAX_MS=120`、传送 `TELEPORT_DIST=220`）；`coop_enemy_proxy.gd`/`coop_player_proxy.gd`/`coop_summoned_proxy.gd`（`_physics_process` 按 `render_t = now - interp_delay` 采样 + `_interp_delay`/`_inc_extrap`/`_inc_hard_snap`）；`coop_net.gd`（`ENEMY_SNAPSHOT_INTERVAL=0.066`、`_send_enemy_snapshot` 优先级分频 + `_snapshot_cadence_mult`、`get_network_timing`/`_sample_jitter`、RTT 常开、`net_sim_loss_pct`、`net_extrap_events`/`net_hard_snaps`）；`entry/coop_entry.gd`（`--coop-devnetlag`）。
- Notes / 说明: ① 远端实体由「每帧 lerp 目标」改为**快照缓冲 + 过去时间采样**：`render_t = 本地now - interp_delay`；两快照间线性插值、早于首条取首、晚于末条按末速度外推（≤120ms 后冻结，Overwatch 式 clamp）。② 自适应延迟 `delay = clamp(max(2×快照间隔, rtt/2 + 2×jitter), 0.05, 0.20)` —— 前提是 **RTT/抖动常开采集**（此前只在 F9 HUD 开启时跑，`_update_network_diagnostics` 早退于 `not net_diag_enabled`；已解耦，HUD 仅控显示/速率；`set_network_diag_enabled(off)` 不再清 `_latency_samples`）。③ 敌人快照 8Hz→15Hz（间隔 66ms，令 2×≈132ms 落在延迟预算内）+ 距离分频（近 1 / 中 2 / 远 3 tick；hp 变化立即发）；召唤物 12.5Hz→15Hz；玩家仍 20Hz。④ `push` 时位移 >220 视为传送 → 清缓冲瞬移，避免大位移插值滑行；硬校正仅越界（敌人/召唤 128、玩家 96）触发。⑤ 采样写成员变量（`sample_pos/sample_vel`）避免每帧 Dictionary 分配。⑥ `--coop-devnetlag=N` 仅接收端丢敌人快照，用于压测外推；无头验证 25–30% 丢包下无 `SCRIPT ERROR`、`ext` 计数上升、`snap=0`；优雅房主离开回归仍通过。取舍：命中仍**客户端权威**、玩家受伤仍本地「伤害洞」结算，未做服务器回滚 hitreg。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 命中轻量校验（保持客户端权威，favor-the-shooter）
- Evidence / 证据: `net/coop_net.gd`（`_intercept_enemy_damage` 转发时附 `victim_pos`；`_server_enemy_hit(net_id, cfg, victim_pos)` + `_validate_enemy_hit`/`_enemy_expected_pos`/`_record_enemy_pos`；常量 `HIT_VALIDATE_MAX_DIST=2400`/`HIT_VALIDATE_TOL=200`/`HIT_HISTORY_MAX=16`；变量 `_enemy_pos_history`、`net_hits_accepted/rejected`）；`entry/coop_entry.gd`（dev status 增 `hit=ok/rej`）。
- Notes / 说明: ① host 在 `_send_enemy_snapshot` 每 tick 记录活跃敌人位置历史（环形 16），供回滚合理性校验。② 校验三项：**目标存活**（`hp>0`）、**攻击者→敌人距离** ≤ 2400、**回滚合理性**（客户端所见 `victim_pos` 与 host 历史中最接近 `now-(rtt/2+插值延迟)` 的点偏差 >200 才拒）。仅拦明显异常，不改权威。③ **坑**：`health_component.take_damage` 传给 `enemy_damage_interceptor` 的 `owner` 是 `HealthComponent.owner`；对**测试房内嵌预置敌人**该 owner 的 `global_position` 实测为 `(0,0)`（其镜像未按快照同步到位），故 `victim_pos` 可能为 `(0,0)` —— 回滚校验对 `(0,0)`/近零视为“未同步”跳过，避免误伤；`--coop-devpreplaced` 回归命中被接受（`hit=1/0`），无 `SCRIPT ERROR`。④ 计数并入 F9 HUD 与 `dev status`。取舍：命中仍**客户端权威**，未做服务器回滚 hitreg；玩家受伤仍本地「伤害洞」结算。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 插值打磨：自适应延迟（实测间隔）/ 缓入外推 / 传送残影
- Evidence / 证据: `net/coop_snapshot_buffer.gd`（`observed_interval_ms()` EMA、`compute_delay(..., observed_ms)` 增第三项、外推 `damp = 1 - ahead/EXTRAP_MAX_MS`、`teleported`/`consume_teleport()`）；`net/coop_dash_ghost.gd`（新增，`spawn/_find_sprite/_frame_texture`）；`coop_enemy_proxy.gd`/`coop_player_proxy.gd`/`coop_summoned_proxy.gd`（`_interp_delay` 传 `_buffer.observed_interval_ms()`；`_spawn_ghost`）。
- Notes / 说明: ① 自适应延迟新增第三项 **1.8×实测快照间隔(EMA)**：对低速率（远距分频达 3×）敌人自动加大延迟，显著减少外推频率；仍 clamp [0.05, 0.20]。② 外推改**缓入衰减**（速度随 `ahead` 线性衰减到 0），末段平滑冻结，避免线性外推过冲后回弹抖动。③ 传送/大位移（>64px）硬校正时，`CoopDashGhost.spawn` 在旧位置生成一个取当前帧贴图的 `Sprite2D` 残影，0.25s 淡出后释放，降低瞬移突兀感。④ 跨脚本静态调用：`SnapshotBuffer.compute_delay` 与 `DashGhost.spawn` 均为 `static func`，preload 后按脚本名直接调用（mod 无 `class_name`）。验证：`--coop-devnetlag=25` 无 `SCRIPT ERROR`；定向脚本验 `DashGhost.spawn` 在旧位置生成 1 个带贴图的 Sprite2D。取舍不变：命中仍客户端权威（轻量校验），玩家受伤仍本地结算。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Tooling] 压测回归：网络模拟 + sim-report + PS 脚本；⚠️ PS `Set-Content` 会改编码
- Evidence / 证据: `net/coop_net.gd`（`_enemy_snapshot` 延迟队列 `_sim_snapshot_queue`/`_pump_sim_queue`、`_emit_sim_report`、`sim_latency_ms/sim_jitter_ms/sim_loss_pct`、`net_remote_frames/net_extrap_frames/net_snapshot_sends/net_snapshot_entities`）；`entry/coop_entry.gd`（`--coop-devsim=lat=..,jit=..,loss=..`/`--coop-devsimreport`/`--coop-devautoquit=<sec>`）；`mod_sdk/coop_sim_regression.ps1`。
- Notes / 说明: ① 延迟模拟 = 接收端把敌人快照入队、按 `now + lat ± jit` 释放；丢包 = 按概率丢弃；作用域 = 敌人快照（插值主目标）。② 指标每 2s 打印 `sim-report`；**必须用 `--coop-devautoquit` 优雅退出**，force-kill 会丢失 stdout 缓冲导致报表不全。③ **严重坑**：PowerShell 5.1 的 `Set-Content`（未指定 `-Encoding`）默认 ANSI/GBK，用它改写含中文的 `.gd` 会把 UTF-8 中文转成 GBK/`?`，Godot 报 `Unicode parsing error` 且整脚本解析失败；**改任何文本文件一律用编辑工具（Edit/Write），不要用 PowerShell 做文本替换**（本次 `coop_enemy_proxy/coop_player_proxy/coop_summoned_proxy` 被损坏）。④ 恢复手段：`ProjectSettings.load_resource_pack(build_pck, true)` 挂载上次构建的 pck，再用 `GDScript.source_code` 导出脚本原文（pck 内含脚本文本）。⑤ 回归脚本条件用 `;` 分隔（`-Conditions "a;b"`），避免 `-File` 传 PowerShell 数组丢空元素。验证：默认 4 条件各 5 次报表、`extrap_rate≈16–20%`、`hard_snaps=0`、无 `SCRIPT ERROR`，全部 PASS。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 敌人快照分包 + 直线弹延迟补偿
- Evidence / 证据: `net/coop_net.gd`（`ENEMY_SNAPSHOT_ENTITY_LIMIT=32` + `enemy_snapshot_batch_limit`、`_send_enemy_snapshot` 切包发送；`_spawn_one_visual` → `_compensate_bullet_spawn`）；`entry/coop_entry.gd`（`--coop-devsnapbatch=<n>`）。
- Notes / 说明: ① **ENet 对 `unreliable`/`unreliable_ordered` 包不重组，超过 MTU 会整包丢弃**；敌人快照原为单包广播，敌人多时整包丢 → 该帧所有敌人一起卡顿/外推。改为按实体数切包（视觉弹早有 `BULLET_BATCH_LIMIT` 先例），接收端无需改。② 子弹延迟补偿（纯表现）只对**匀速直行弹**：按单向延迟 `clamp(rtt/2,0,0.25s)` 沿 `Vector2.RIGHT.rotated(r)` 前推 `speed*delay`，并把 `kill_time` 扣 `int(delay*10)`（`kill_time` 单位=0.1s tick，见 `scenes/bullet/enemy_bullet.gd:16/161`；`decay_time` 走减速）；`homing`/`slow_down`/`decay_time!=0`/`can_r`/`collision_num>0` 弹**跳过**（前推会过冲/穿墙/偏航）。③ 判定用已序列化的 `BULLET_PROP_NAMES` 属性（接收端 `e["pr"]` 可得）。验证：`--coop-devsnapbatch=1` 时 host `snap_sends==snap_entities`（逐实体分包）、client `enemies=10`/血量正常无报错；定向脚本验直线弹前推 `(60,0)`/`k=109`、homing/slow/ricochet 不前推、90° 朝向前推 `(0,25)`；`coop_sim_regression.ps1` 4 条件全 PASS。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] LAN 发现 / 版本握手 / 队友 HUD + 实时战绩（连接体验与信息面板）
- Evidence / 证据: `net/coop_lan_discovery.gd`（新增）；`net/coop_net.gd`（`_client_hello`/`_hello_reject`/`_hello_accept`/`_accept_peer`/`_kick_peer_deferred`/`_update_handshake_timeouts`、`browse_lan_start`/`browse_lan_stop`/`get_lan_rooms`、`_update_lan_advertise`、`_ensure_team_stat`/`_add_team_damage`/`_add_team_kill`/`_broadcast_team_stats`/`_remote_team_stats`/`dev_team_stats`）；`ui/coop_team_hud.gd`（新增）、`ui/coop_scoreboard_panel.gd`（新增）、`ui/coop_menu.gd`（`_build_room_list`/`_refresh_room_list`）；`entry/coop_entry.gd`（注入 HUD/面板 + `--coop-devdiscover`/`--coop-devbadver`/`--coop-devsnapbatch`）。
- Notes / 说明: ① **同机 UDP 发现坑**：广播发送端若也 `bind(DISCOVERY_PORT)` 会与 browse 端抢端口 → 发送端应 `bind(0)`（只发不收），browse 端绑 `DISCOVERY_PORT`；同机跨进程广播有时不回流，故额外单播 `127.0.0.1:24592`。② **握手踢人顺序**：`rpc_id(reject)` 后立即 `disconnect_peer` 会丢可靠包（客机只看到 host 掉线） → 延迟 0.5s 再踢（`_kick_peer_deferred`）；`_on_peer_connected` 改为等握手通过后 `_accept_peer` 再接入，未握手 5s 超时踢。③ **战绩伤害累加两处**：`HealthComponent` 在 `suppress_feedback=true` 时不发 `damage_taken`（`script/health_component.gd:171-172`），故客机转发命中（`_server_enemy_hit`）需单独累加伤害，否则只统计到 host 本地命中。④ `_local_or_remote_player` 返回前加 `is_instance_valid` 守卫，避免 `_refresh_name_tag` 链报 "Trying to return a previously freed instance"。⑤ `_update_handshake_timeouts` 需先判 `multiplayer.multiplayer_peer == null`（`is_server()` 在无 peer 时会报 `get_unique_id`）。验证：同机 `--coop-devdiscover` 找到 1 房；`--coop-devbadver` 被拒且收到 reason；真实流程（auto lobby）握手通过并进准备房；`dev status team=` 显示客机 35 伤害；`coop_sim_regression.ps1` 4 条件全 PASS，无 `SCRIPT ERROR`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 战绩改为可编辑场景；移除队友 HUD（SUPERSEDED：上一条的「队友 HUD」与代码构建战绩面板）
- Evidence / 证据: `ui/coop_scoreboard.gd` + `ui/coop_scoreboard.tscn` + `ui/coop_scoreboard_row.tscn`（新增）；删除 `ui/coop_team_hud.gd`、`ui/coop_scoreboard_panel.gd`；`entry/coop_entry.gd`（`ScoreboardScene = preload(...tscn)` → `instantiate()`）。
- Notes / 说明: ① 用户判定**队友 HUD 观感不佳 → 移除**（头顶 `coop_health_bar.gd` 保留）。② 战绩 UI 从代码构建改为 **`.tscn` 静态布局 + 脚本填数据**：行用模板场景 `coop_scoreboard_row.tscn`（`%Name/%Kills/%Damage/%Coins` 四个 `unique_name_in_owner` Label，列宽用 `custom_minimum_size`），主场景 `coop_scoreboard.tscn`（居中 `PanelContainer`，标题/表头为静态节点）；脚本只做输入注册、按 `CoopNet.team_stats` 实例化行并设文本。**版式/字体/颜色/位置均可在编辑器手动调整**。③ 手写 mod `.tscn` 要点：`load_steps = ext_resource + sub_resource + 1`；容器子节点 `layout_mode = 2`；`unique_name_in_owner = true` 才能用 `%Name`；`process_mode = 3`(ALWAYS) 保证暂停下仍响应。④ 数据侧不变（host `team_stats` 周期广播）。验证：双进程 `--coop-devbattle` 无 `SCRIPT ERROR`、场景实例化正常、`dev status team=` 计数正常。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 记分板大数缩写（K/M/B/T）；⚠️ 编辑器镜像手调 UI 必须回同步到 mod_sdk 源码
- Evidence / 证据: `ui/coop_scoreboard.gd`（`static func _fmt_num` / `_trim_decimal`，应用于 `%Kills/%Damage/%Coins`；排序仍用原始 `damage`）；`mod_sdk/coop_mod/mods/etn_coop/ui/coop_scoreboard.tscn` 与 `coop_scoreboard_row.tscn`（由编辑器镜像 `mods/etn_coop/ui/` 回同步）。
- Notes / 说明: ① 显示格式化：`<1000` 原样；否则 `K/M/B/T`，1 位小数、去尾随 `.0`，含**进位保护**（`999950 → 1M` 而非 `1000K`）；只影响显示，排序/统计用原始值。② **关键坑**：`mods/etn_coop/ui/*` 是**编辑器镜像**，用户在编辑器手动调整的 UI **只存在于镜像**；而 `build_coop_mod.ps1` 从 **`mod_sdk/coop_mod/mods/etn_coop/` 源码**打包 → **必须把镜像改动回同步到 `mod_sdk` 源码**，否则重建 pck 会丢失该 UI（本次已把两个 `.tscn` 从镜像复制回源码）。③ 修改脚本时源与镜像两份要一致。验证：`_fmt_num` 断言 9 例（0/999/1000/1234/12000/1500000/999950/2e9/4e12）全 OK；`coop_sim_regression.ps1` 4 条件全 PASS，无 `SCRIPT ERROR`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] OPTION 页新增调试窗口开关（持久化）+ 调试 HUD 顶中/字号 8
- Evidence / 证据: `net/coop_settings.gd`（`DEBUG_SECTION="debug"` / `debug_hud` / `apply_debug_hud`）；`entry/coop_entry.gd`（`_hud.add_to_group("CoopNetDebugHud")` + 启动按存档 `set_shown`）；`ui/coop_menu.tscn`（新增 `RowDebugHud` + `option_toggle.tscn` 的 ext_resource；`load_steps` 19→20）；`ui/coop_menu.gd`（`%DebugHudToggle`/`%DebugHudValue`、`_on_debug_hud_toggled`、`_refresh_option_sliders`、切到 OPTION 页刷新）；`ui/net_debug_hud.gd`（`PRESET_CENTER_TOP` + `GROW_DIRECTION_BOTH` + `offset_top=12`、`font_size` 8）；`i18n/coop_i18n.gd`（`coop_option_debug_hud`/`coop_on`/`coop_off`）。
- Notes / 说明: ① 复用本体 `res://ui/option_toggle.tscn`（`extends PanelContainer`，发 `toggled(on)`，自带 hover/触屏处理），在菜单 OPTION 页顶部加开关；**手机无 F9 时从菜单开启**。② HUD 与菜单解耦：entry 把 `_hud` `add_to_group("CoopNetDebugHud")`，菜单用 `get_tree().get_first_node_in_group(...)` 调 `set_shown`；状态存 `user://etn_coop_settings.cfg` 的 `[debug] debug_hud`，entry 启动即应用（手机可常显）。③ 菜单开关在切到 OPTION 页时按 HUD **实际 `visible`** 刷新（兼容 F9 改动）。④ 手写 `.tscn` 要点：实例节点写 `[node name=... parent=... instance=ExtResource("8_toggle")]` 并加 `unique_name_in_owner = true`；新增 `ext_resource` 需同步改 `load_steps`。⑤ 调试 HUD 顶部居中：`MarginContainer` 必须用 `PRESET_CENTER_TOP` + `grow_horizontal = GROW_DIRECTION_BOTH` 才会按内容水平居中。验证：`coop_menu.tscn` 实例化后 `%DebugHudToggle`/`%DebugHudValue` 均可解析、值为 `coop_off`；`--coop-devhud` 单进程无 `SCRIPT ERROR`；`coop_sim_regression.ps1` 4 条件全 PASS。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07
- UPDATE: 2026-10-08 联机 mod 调试 HUD 热键由 F9 改为 **F4**（`entry/coop_entry.gd` `KEY_F9→KEY_F4`、`ui/net_debug_hud.gd` 文案/注释、`net/coop_net.gd` 注释、`mod_sdk/coop_mod/README.md` 同步）。本体另新增 F3 调试性能面板 `DebugPerformanceMonitor`（见 `ARCHITECTURE.md` §1 autoload #15）。

### [Mod] 调试开关改为本体同款样式（去拉伸、置拉杆下方、去 ON/OFF 文本）
- Evidence / 证据: `ui/coop_menu.tscn`（`RowDebugHud` 移至 `RowRemoteText` 之后 / `OptionNote` 之前；`DebugHudToggle` 去掉 `size_flags_horizontal = 3`、加 `size_flags_vertical = 4`；删除 `DebugHudValue`）；`ui/coop_menu.gd`（删除 `_debug_hud_value` 引用）；`res://ui/option_toggle.tscn`（与本体开关同款：`PanelContainer` 18×18）。
- Notes / 说明: ① `option_toggle.tscn` 本就是**复刻本体的 FullScreen/Shake/VSync 开关**（`PanelContainer` 18×18 + 深色 `ColorRect` 轨道 + `Node2D` 黄色滑块 + `full_on/full_out/selected/selected_out` 四段动画）；之前难看的原因是**在实例上设了 `size_flags_horizontal = 3` 把轨道拉伸成长条**。本体做法：`custom_minimum_size = (18,18)` + `size_flags_vertical = 4`（SHRINK_CENTER），**不横向拉伸**。② 按用户要求置于 OPTION 页**拉杆下方**并**移除 ON/OFF 文本**（本体开关无文字）。验证：`coop_menu.tscn` 实例化后 `%DebugHudToggle` 解析正常、`%DebugHudValue` 已移除；`coop_sim_regression.ps1` 全 PASS。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [GDScript] 成员变量名不可与虚拟方法同名；无类型 `call()` 结果的 `:=` 无法推断
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_chat.gd`（原 `@onready var _input: LineEdit` 与 `func _input(event)` 冲突 → `Parse Error: Function "_input" has the same name as a previously declared variable`，改名 `_input_box` 后通过）；`var ammo_pos := player.get_node_or_null(...)`（`player` 来自无类型 `coop.call(...)` → `Parse Error: Cannot infer the type of "ammo_pos"`，改为 `var ammo_pos: Node = ...` 后通过）。
- Notes / 说明: ① Godot 会把 `_input/_process/_ready/_unhandled_input` 等视为要覆写的虚方法，**同名成员变量会直接 Parse Error**；给控件/节点起变量名时避开这些。② 从无类型对象上 `.call()`/动态属性取到的值是 Variant，`:=` 不能推断其类型 → 必须显式标注（`: Node`）或用 `=`。用编辑器 MCP 的 `script_patch` 返回值里的 `diagnostics` 可即时确认是否 Parse 通过（`diagnostics: []` + `reloaded: true`）。
- Source / 来源: code + test
- Date / 日期: 2026-10-07

### [Mod] 聊天室：本机回显 + host 排除发送者分发；开窗时按「谁显示 UI 谁持有指针」还原
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`send_chat` 本地 `_append_chat` 后 host `_fanout_chat(...,0)` / client `rpc_id(1,"_server_chat")`；`_server_chat` 用 `get_remote_sender_id()` 再 `_fanout_chat(sender, clean, sender)` 排除发送者；`_remote_chat` 广播到接收端；`_reset_run_state` 清 `chat_log`）；`ui/coop_chat.gd`（开窗记 `Input.mouse_mode` 与 `player_stop` 后置 VISIBLE/true，隐藏按原值还原；`_input` 用 `set_input_as_handled` 抢在 LineEdit 的 `ui_accept` 之前处理 Enter）。
- Notes / 说明: ① 本地先回显保证手感，但 host 再全广播会给发送者重复一条 → host 分发必须**排除发送者**（逐 `rpc_id`）。② 聊天开窗需要显示鼠标并冻结玩家：沿用本体「谁显示 UI 谁持有指针」原则，关闭时还原**开窗前的**鼠标模式与 `player_stop`（倒地时原值即 true，不误置 false），不要在多处竞争写全局鼠标。③ 无头自测 `--coop-devchat` 双进程实测两端 `log=2`、无重复、无 `SCRIPT ERROR`。
- Source / 来源: code + test
- Date / 日期: 2026-10-07

### [Mod] 聊天室手机按钮：游玩期勿吞鼠标 → `mouse_filter=IGNORE` + `_input` 手动命中判定
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_chat.gd`（`_make_button()` 设 `mouse_filter = Control.MOUSE_FILTER_IGNORE` 且不连 `pressed`；`_input` 的 `_button_hit(event)`：`InputEventScreenTouch` 命中矩形始终 true，`InputEventMouseButton` 左键仅 `_is_open` 时 true，且 `Engine.get_process_frames() - _last_touch_frame <= 1` 忽略触摸模拟出的鼠标）。
- Notes / 说明: **坑**：`Control`（含 `TextureButton`）`mouse_filter=STOP` 会**吞掉命中它的鼠标事件**，使 `player._unhandled_input` 的 `fire` 收不到点击——按钮放在 HUD 上时，玩家瞄向 HUD 点击会「既不开火也不开窗」。要「手机触摸可点、桌面游玩期不误触/不挡开火」，应把按钮设为 `IGNORE`（纯显示、永不 consume），改在 `_input` 用 `_btn.get_global_rect().has_point(event.position)` 手动判定：`InputEventScreenTouch` 始终可触发；`InputEventMouseButton` 仅聊天窗激活（鼠标可见）时触发。另须用帧号守卫忽略「触摸模拟出的鼠标事件」（`input_devices/pointing/emulate_mouse_from_touch` 默认开），否则一次触摸会双触发。验证（无头探针）：`filter=2 alpha=0.45 mouse_closed=false touch=true mouse_open=true`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 聊天室连续发送：淡出期内再按回车重聚焦并取消淡出
- Evidence / 证据: `ui/coop_chat.gd`（`_input` ACTION 三态：隐藏→`_open_chat()`；可见且 `_input_box.has_focus()`→`_submit()` 发送+失焦+`_schedule_hide()`；可见未聚焦→`_refocus()` 增加 `_hide_token` 取消淡出、kill tween、`grab_focus()`）。
- Notes / 说明: 发送后窗口仍 `_is_open` 并进入 2 秒淡出期，此时输入框已失焦；若 ACTION 仍一律走 `_submit()`，用户必须等窗口完全消失才能再输入，连发体验差。改为按 `has_focus()` 区分「发送」与「重聚焦」，重聚焦用 `_hide_token` 令在途的 `_schedule_hide()` 协程在超时后发现 token 不符而放弃隐藏。验证（无头探针）：发送后 `focus=false text='' token=1`；重聚焦后 `focus=true token=2`；2.6s 后 `still_open=true`（淡出被取消）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] coop_menu 交互控件靠 `_set_buttons_enabled` 白名单恢复 STOP；新增控件必须入列
- Evidence / 证据: `ui/coop_menu.gd:_set_buttons_enabled()`（先 `_panel.find_children("*","Control",true,false)` 把 `_panel` 下所有 Control 递归设 `MOUSE_FILTER_IGNORE`，再把 `controls` 白名单设为 `STOP`(启用)/`IGNORE`(禁用)；`:359-370`，`controls` 本轮已加入 `_debug_hud_toggle`）。
- Notes / 说明: coop 覆盖层打开时 `_panel` 子树的**所有 Control 都被递归设为 `MOUSE_FILTER_IGNORE`**，只有列入 `_set_buttons_enabled()` 里 `controls` 数组的控件才会在打开时恢复 `STOP`。因此 **任何新增的可交互控件（Button/LineEdit/HSlider/开关…）都必须加进该数组**，否则收不到 `mouse_entered/gui_input`，表现为「点了没反应、悬停也没有动画」——这也是调试开关此前失效的根因（场景里那些控件写着 `mouse_filter = 2` 只是初始值，靠这个白名单在运行时恢复）。验证：`coop_menu.tscn` 实例化后调 `_set_buttons_enabled(true)` → `%DebugHudToggle.mouse_filter == 0`（STOP），`false` → `== 2`（IGNORE）；`coop_sim_regression.ps1` 全 PASS。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod][本体] 联机升级「继续」：前半过场由 mod 播到黑屏并保持，本体经 `round_upgrade_cover_hold` 跳过前半只播后半
- Evidence / 证据: `script/extension_hooks.gd`（`round_upgrade_cover_hold` 读槽 + `on_round_upgrade_cover_consumed` 通知槽）、`scenes/manager/round_manager.gd:98-110`（`_on_round_start` 命中槽则跳过 `play_left_start`+`await left_end_start`，只 `play_left_end`）、`mods/etn_coop/net/coop_net.gd:_gate_round_upgrade_end/_cover_then_report_ready/_gate_round_upgrade_cover_hold/_on_round_upgrade_end_local`、`mods/etn_coop/ui/coop_round_wait.tscn`、`ui/GameEvents.gd`（`round_upgrade_closing`）、`ui/UpgradeScreen.gd:next_round_button`、`ui/player_up_screen_date.gd:_ready`。
- Notes / 说明: **现象**：联机中「客机先点继续、主机后点继续」时客机的属性/装备栏（`player_up_screen_date`）停留不消失。**根因/设计**：升级页只由 `round_upgrade` 显示、`round_start` 隐藏，而 `round_start` 受 `GameEvents.emit_round_start()` 的 `round_switch` 门控；联机推进的旧路径在 `emit_round_upgrade_end` 的 gate 调用内**同步重入** `force_round_upgrade_end`（客户端先就绪 → 主机点继续时触发），与主机先点就绪时（走 RPC `_server_round_upgrade_ready`）不对称。**修法（新流程）**：点继续时本体先发 `round_upgrade_closing` 收起升级 UI；mod 在 `round_upgrade_end_gate` 内本机 `Transition.play_left_start()`（前半到黑屏）并**保持**，`await Transition.left_end_start` 后再显示「等待所有人就绪」遮罩并上报就绪（**推迟到封面完成之后**，保证所有端封面都完成再统一放后半；同时消除同步重入）。全员就绪 → `force_round_upgrade_end` → 本体 `_on_round_start` 经 `round_upgrade_cover_hold` 跳过前半、只 `play_left_end` 揭示并 `emit_round_start`。`round_upgrade_cover_hold` 由本体在播后半前经 `on_round_upgrade_cover_consumed` 通知 mod 复位，避免下一回合误跳过。等待期间 `pause_lock=true` + `get_tree().paused=true`，`pause_screen.show_pause()` 被 `_pause_locked` 拦下 → ESC 无效。掉线兜底：`_on_peer_disconnected` 剔除其就绪态并重判 `_maybe_finish_round_upgrade`。
- Source / 来源: user + code
- Date / 日期: 2026-10-07

### [Mod][本体] 联机支援：每人自带 + EX 充能按击杀归属 + kei 范围 buff 跨端 + EX 光环视觉镜像
- Evidence / 证据: `script/GameEvents.gd`（`enemy_dead_score_owned`）、`script/health_component.gd:_take_damage_internal`（死亡分支 `not suppress_proc` 发 owned 分）、`script/support_as.gd`（改听 `enemy_dead_score_owned`）、`script/extension_hooks.gd`（`player_buff_apply/remove_interceptor`）、`scenes/player_support/kei/kei_as.gd`（光环命中远端镜像转交 + `_on_skill_end` 兜底移除）、`mods/etn_coop/net/coop_net.gd`（`_remote_enemy_proc(score)`、`_gate_player_buff_*`/`_server_relay_player_buff`/`_remote_player_buff`、`_on_local_support_ex_active/end`/`_remote_support_ex`、`support_by_peer`）、`mods/etn_coop/ui/coop_select.gd`（`report_local_support`）。
- Notes / 说明: **约定**——支援是"每人各自本地"（各端 `SupportData.game_add_support` 生成自己的 support_pack；选择 `support_id` 仅同步供可见性/扩展），伤害/治疗/子弹只在拥有者端生效，只有"范围 buff"跨端。**坑 1（充能）**：旧 `enemy_dead_score` 由 `EnemyStats.hp` setter 在权威端为**所有**击杀发出，而 `health_component` 的 `suppress_proc` 只压 `enemy_damage_taken*`、**不压 score**，客机镜像 hp 又恒 `>0` → 旧实现下"主机对所有击杀充能、客机几乎不充能"。修法：新增 `enemy_dead_score_owned(score, owner_peer)`，由 `health_component` 死亡分支在 `not suppress_proc` 时带 `damage_data.owner_peer` 发出、`SupportAS` 据此只为本机击杀充能；host 对客机归属击杀 `suppress_proc` 拦住本地、经 `_remote_enemy_proc(score)` 让客机本机发。**坑 2（镜像阵营）**：`Faction.of_entity` 对远端玩家镜像（在 `RemotePlayer` 组、无 `faction`）返回 `ENEMY_SIDE`，故 kei 光环原逻辑根本不会命中镜像；改以 `has_meta("peer_id")` 识别镜像并经拦截槽转交其本机给真实玩家上/去 buff。**坑 3（视觉代理）**：本体 `*_as.tscn` 直接实例化会把 `SupportAS._ready` 的信号（改本机 `SupportData.now_cost`）带上；故接收端实例化后 `set_script(null)` 再 `add_child`，并关 `Area2D.monitoring/monitorable`，作纯视觉代理（serina 挂玩家镜像、kei 挂 kei 召唤物镜像）。**已知边界（下一轮）**：同 `kei_buff` id 多来源叠加时 `BuffRouter.remove_buff` 按 id 移除会互相影响；断线不清远端 buff（对方进程消失）。
- SUPERSEDED: 2026-10-07 上述"已知边界"已由 `Buff.source_refcount`（来源引用计数）解决，见下方新条目。
- Source / 来源: user + code
- Date / 日期: 2026-10-07

### [Support] `game_support` 可为 `null`（非 `null_support`）；`game_add_support()` 漏判 → 空 HUD 卡 / 结算 Nil
- Evidence / 证据: `script/support_data.gd:20`（`var game_support: SupportCard` 默认 null）、`:55-61`（`reset_game_support()` 原只在 `!= null` 时降级、`game_add_support()` 原只判 `"null"`）、`:68-74`（无条件下发 UI）；`script/Game.gd:227-235`（无档 `load_playerdata()` 直接 return，`game_support` 保持 null）；`ui/support_ui/support_select_ui.gd:31-47`（`check_data()` 只写 `now_support`，不回写 `game_support`）；`ui/support_card.gd:23-26`（`support_card == null` 时 `get_card()` 什么都不设）；旁证 `ui/game_ui.gd:45` 已补 null 守卫。
- Notes / 说明: **现象/路径**：全新存档、从未点选任何支援时，`game_support` 稳定为 `null`；`game_add_support()` 的 `game_support.support_id == "null"` 既不命中也无法正确早退，随后仍 `support_ui.instantiate()` 并把空的 `support_card` 挂进 `GameUI.support_box` → HUD 出现一张无立绘/武器名/进度条的空卡（并伴 Nil 访问报错）；`ui/game_over_page.gd:69` 读 `game_support.support_id` 同样会在结算时踩 Nil。**修法（C=A+B）**：A 守卫——`game_add_support()` 改 `game_support == null or support_id == "null"` 早退；`game_over_page` support 字段判空回退 `"null"`。B 归一——`reset_game_support()` 把 `null` 与「未解锁」统一置为 `null_support`；`Game.load_playerdata()` 读档后若 null 亦补 `null_support`；`support_select_ui.check_data()`（`test_menu==false` 分支）兜底回写。**通用教训**：单例里"未选择"的哨兵值必须唯一且显式（此处应始终是 `null_support` 而非有时 `null`），否则每个消费点都要各自判空，漏一处就是空 UI/Nil。**验证（`game_eval`，2026-10-07）**：`game_support=null` → `reset_game_support()`/`check_data()` 后均变为 `null_support`；`game_support=null` 进 `main.tscn` 后 `GameUI.support_box.get_child_count()==0`、无 Nil 报错；置 `kei` 后 `game_add_support()` 得 1 张 `kei` 卡。整局 game log 零错误。
- Source / 来源: code + test
- Date / 日期: 2026-10-07

### [Buff] `Buff.source_refcount`：多来源共享 buff 只算一份、按 source_id 独立增删（kei 光环）
- Evidence / 证据: `resources/buff/buff.gd`（`source_refcount`）、`resources/buff/player_buff/kei_buff.tres`（`source_refcount = true`）、`scenes/manager/buff_manager_base.gd`（`entry["sources"]`、`apply_buff` 的 `source_refcount` 分支、`remove_source`/`remove_source_all`、`_sync_card_layer` 显示来源数）、`script/buff_router.gd:remove_source`、`scenes/player_support/kei/kei_as.gd`（`_aura_source_id()`、apply/remove 传 `source_id`）、`mods/etn_coop/net/coop_net.gd`（`_remote_player_buff(.., source_id)`、`_local_buff_source_id`、断线 `_remote_clear_player_buff_source`）。
- Notes / 说明: `BuffManagerBase.current_buff` **按 `buff.id` 唯一**、`remove_buff` 整条移除；多来源同 id 时旧行为是"层数/数值叠不叠取决于 `buff_layer_mult`，且任一来源 `remove_buff` 会把所有来源一起删"。新增 `Buff.source_refcount` 语义：**多来源只维持"存在"，数值只算 1 层**（不叠），内部按 `entry["sources"]`（`source_id -> true`）记录来源集合，`remove_source` 只扣该来源、最后一个来源离开才 `_remove_buff_entry`。`source_id` 取**拥有者 peer id**（`str(multiplayer.get_unique_id())`；单机 `"1"`），apply/remove 必须成对同一 id。卡片层数 `_sync_card_layer` 对 `source_refcount` 条目显示"当前来源数"（**仅展示**；`entry["layer"]` 恒 1，保证 `_remove_ability(entry, layer)` 数值正确）。与 `_uses_source_caps`（`chill_ring` 的来源独立**叠层加值**）是**两套机制**，别混用。联机 owner 断线：host 广播 `_remote_clear_player_buff_source(id)` → 各端 `player_buff_manager.remove_source_all(str(id))` 清残留层。**通用教训**："多来源共享 buff"若希望效果不叠，别用层数表达来源数（`remove_buff` 会整条删；改层数又会改数值），要单独维护来源集合。
- Source / 来源: user + code
- Date / 日期: 2026-10-07

### [Buff][Mod] `Buff.per_source_layers` + 联机召唤物范围光环（kei/utaha）跨端
- Evidence / 证据: `resources/buff/buff.gd`（`per_source_layers`）、`resources/buff/summoned_buff/utaha_buff.tres`（`per_source_layers = true`）、`scenes/manager/buff_manager_base.gd`（`_uses_source_caps` 读字段、`remove_source` 支持 source-caps 模式按来源移除全部层、`remove_source_all` 兼顾两种模式）、`scenes/manager/enemy_buff_manager.gd`（保留 `chill` 判定）、`scenes/player_support/kei/kei_as.gd` 与 `scenes/player/utaha/UtahaPS.gd`（入组 `"CoopSummonAura"` + `network_summon_aura_info()`）、`mods/etn_coop/net/coop_net.gd`（`_tick_summon_auras`/`_send_summoned_buff`/`_server_relay_summoned_buff`/`_remote_summoned_buff`/`_apply_summoned_buff_local`）。
- Notes / 说明: **根因**：队友召唤物在本机只是镜像，`coop_summoned_proxy._disable_damage_nodes()` 清零其 `collision_layer/mask` → kei/utaha 的 `Area2D` 光环探测不到；且镜像挂 `owner_peer_id`/`summoned_net_id`（非 `peer_id`），转发门只认玩家。**修法**：本体光环实现 `network_summon_aura_info()`（位置取**碰撞形状** `global_position`、半径取场景 `CircleShape2D.radius`）并入组；mod 在拥有者端 10Hz(`global_time_count`) 按半径扫描远端召唤物镜像，`key="<source_id>|<buff_id>|<net_id>"` diff 后转发到其 owner peer（host 直发/client 经 host 中继），目标端对真实召唤物 `BuffRouter.apply_buff/remove_source`；边界用滞回（进 R / 出 R+8）防抖动。**两种来源语义**：`kei_buff` 用 `source_refcount`（多来源只算 1 层、最后来源离开才移除）；`utaha_buff` 用 `per_source_layers`（按来源叠层、`remove_source` 移除该来源**全部层数**，`_remove_ability(entry, n)`）。`Buff` 上两字段互斥，至多开其一。断线：host 广播 `_remote_clear_player_buff_source(id)` → 各端对**玩家 + 本机所有召唤物** `remove_source_all`。**通用教训**：跨越"只算一份"与"按来源叠层"两种语义时，统一 `remove_source(buff, source_id)` 入口、按 `_uses_source_caps` 分流即可；镜像碰撞被清零的实体，范围判定要改由拥有者端按位置扫描。
- Source / 来源: user + code
- Date / 日期: 2026-10-07

### [Mod][Support] 医疗箱 host 权威同步 + 支援生成效果跨端聚合（serina/ayane 组合）
- Evidence / 证据: 本体 `script/support_character.gd`（`get_medkit_spawn_modifiers()` 默认 `{}`）、`scenes/player_support/serina/serina.gd`（`{rate_mult, at_player:true}`）、`scenes/player_support/ayane/ayane.gd`（`{on_take_spawn:1}` + LAN 下跳过本地 `connect`）、`script/extension_hooks.gd`（`medkit_spawn_gate`/`on_medkit_spawned`/`on_medkit_taken`）、`scenes/manager/pick_item_manager.gd:add_medical_kit`（gate + notify）、`scenes/item/medical_kit.gd`（`coop_medkit_consumed` 守卫、`consume_remote()`、`on_medkit_taken`）；mod `mods/etn_coop/net/coop_net.gd`（`support_mods_by_peer`、`report_local_support(id, mods)`、`_local_support_modifiers`、`_refresh_medkit_mods`、`_gate_medkit_spawn`、`_on_medkit_spawned`/`_remote_spawn_medkit`、`_on_medkit_taken`/`_server_medkit_taken`/`_remote_medkit_consumed`、`_handle_ayane_on_take`、`_send_existing_medkits_to_peer`）、`ui/coop_select.gd:_report_local_support`（随 id 上报 modifier）。
- Notes / 说明: **模型**：医疗箱由 **host 权威**生成——只有 host 的 `PickItemManager` 产生随机箱，客机 `medkit_spawn_gate` 一律返回 true（本端不生成），host 生成后 `rpc("_remote_spawn_medkit")` 广播，全端同一批；拾取由**拾取者本机**结算（治疗/满血转金币随玩家状态 RPC 传播），host 只负责 `_mark_medkit_consumed` + 广播移除（客机 `consume_remote()` 只播消失演出）。**支援聚合**：各端所选支援的 `get_medkit_spawn_modifiers()` 经既有 `support_by_peer` 通道随 `report_local_support(id, mods)` 同步（纳入 `level_state.support_mods` 供晚加入、断线/复位清理），host `_refresh_medkit_mods()` 聚合 `rate_mult=max`（上限 2.0）、`at_player=any`、`on_take=any` 并写入本机 `PickManager`；`at_player` 时 host 从所有 serina 携带者中**随机选一名**落其脚下（否则随机 tile）。**关键坑**：① 客机 `ayane._special_effect` 必须按 `ExtensionHooks.is_lan_session` 跳过本地 `connect`，否则 host 集中处理 + 本端触发会**双生成**；② 读远端支援 modifier 不能只看序列化的 `SupportData`，需**临时 instantiate `support_pack`（不入树 → 不触发 `_ready`/`_special_effect`）**再 `get_medkit_spawn_modifiers()` 后 `free()`；③ 聚合值必须在 `game_add_support()`（first_round）之后 deferred 写 `PickManager`，否则会被本机支援的 `_special_effect` 覆盖。**本体 hook 均默认空 → 单机逐字节一致。**
- Source / 来源: code + user
- Date / 日期: 2026-10-07

### [Mod] 跟随型召唤物镜像：StateMachine 被关后动画/朝向/瞄准/开火必须由 proxy 直接驱动
- Evidence / 证据: `mods/etn_coop/net/coop_summoned_proxy.gd`（`_disable_remote_simulation`：`set_physics_process(false)` + `StateMachine.set_physics_process(false)`；`apply_state(..., state, facing)`）、`script/summoned_follower.gd`（`get/apply_network_visual_rotation`、`get_network_state/facing`、`apply_network_state`、`network_play_action`、`_on_gun_shoot`）、`scenes/player_support/kei/luminous_nova.gd`（`_shootAnim(dur)`）、`mods/etn_coop/net/coop_net.gd`（`send_summoned_state(..., state, facing)` 三处）
- Notes / 说明: 跟随型召唤物（`SummonedFollower`：`kei_summoned`/`mobu_trinity`）的移动/待机/跳跃动画、朝向翻转（`graphics.scale.x`/`halo.flip_h`）、枪口 `gun.look_at`、开火 `gun._shoot()` 全部在 `tick_physics`/`transition_state`（由 `StateMachine._physics_process` 驱动）里。镜像端为防 AI/移动把 StateMachine + physics 全关 → 这些**一次都不跑**（旧行为：镜像永远停场景默认 `idle` 贴图、不翻转、不瞄准、不开火）。修法：快照增 `state`/`facing`（`send_summoned_state`），`SummonedFollower` 实现 `apply_network_state`（只切动画/翻转/跳跃表现）与 `get/apply_network_visual_rotation`（枪口角复用已有 rotation 通道）；开火在拥有者 `SummonedGun.shoot_bullet` 时 `notify(on_summoned_action, ...)` 广播闪光/音效/后坐（**子弹本体仍由 `ProjectileSpawner` 广播，勿双生**）。`TurretSummoned` 早有 `network_play_action` + aim 通道（`extends Summoned`，不在 `SummonedFollower`，不受影响）。**通用教训**：镜像"关掉整机模拟"省心，但任何依赖该 process 的视觉都会静默丢失；表现要么由 proxy 每帧直接写、要么保留一个只做视觉的分支。
- Source / 来源: code + test
- Date / 日期: 2026-10-07

### [Mod] 聊天室升级页按钮：升级页背景不透明且 layer 更高，按钮须放到上层 CanvasLayer
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_chat.tscn`（`%UpgradeChatButton` 挂 `CoopChat` layer 119；HUD 按钮在本地玩家 `$GameUI/AmmoPosition`）、`ui/coop_chat.gd`（`_upgrade_active` 由 `GameEvents.round_upgrade`→true / `round_upgrade_end`+`round_upgrade_closing`+`round_start`+`game_over`→false 驱动；`_ensure_upgrade_button()`；`_pointer_free()`）、`ui/UpgradeScreen.tscn:440-456`（`layer=2`，不透明 `ColorRect`）、`ui/game_ui.tscn:182`（`GameUI` 默认 `layer=1`）。
- Notes / 说明: **现象**：升级页里看不到/点不到手机开聊按钮。**根因**：升级页 `UpgradeScreen` 是 `layer=2` 且背景不透明，玩家 HUD 按钮在 `$GameUI`（默认 `layer=1`）→ 被完全盖住（视觉与命中都被遮挡）。**修法**：在 `CoopChat`（`layer=119`）放第二个按钮 `%UpgradeChatButton`（场景节点，位置/大小编辑器可调），升级阶段显示；用事件（而非轮询）控制显隐，兼容升级页「刷新」重建（刷新不重发 `round_upgrade`，但仍在升级阶段，按钮保持）。**门控放宽**：鼠标分支由「仅 `_is_open`」改为「指针空闲」`_is_open or Input.mouse_mode==MOUSE_MODE_VISIBLE`——游玩期准星把鼠标设为 `CONFINED_HIDDEN`（不处理也不 consume，不误触/不挡开火），升级页/暂停等鼠标 `VISIBLE` 时桌面可点。**无头限制**：headless 会把 `Input.mouse_mode` 强制为 VISIBLE（写 `CONFINED_HIDDEN` 读回仍为 `0`），故「隐藏」分支只能靠条件本身保证、无法无头断言。**Enter 仍归聊天**（LAN 下不触发升级页 `ui_accept`；升级确认走空格/手柄A/鼠标）。验证（无头探针）：两按钮鼠标(VISIBLE)命中=true、触摸=true、触摸后同帧鼠标被守卫忽略=false、升级态开关 `begin=true/end=false`；双进程 LAN `--coop-devchat` 两端 `log=2` 无 `SCRIPT ERROR`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 联机救援进度必须 host 权威："人越多越快"是全局量，各端独立累加无法体现
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd:4782`（`_server_update_rescue`）、`:4823`（`_count_rescuers_for`）、`:4847`（`_broadcast_rescue_progress`）、`:4863`（`_apply_rescue_progress`）、`:4960`（`_complete_revive`）、`:260`（`RESCUE_SYNC_INTERVAL`）、`:4171`（`dev_force_local_downed`）
- Notes / 说明: 旧机制是「每端本地按住 `use` 各自累加 2.5s，谁先满谁发请求」——`进度 += delta` 只含本端，**多人在场不会更快**（各自照旧 2.5s）。要「人越多越快」，人数是**跨端共享量**，必须由 host 结算：host 每物理帧对每个倒地目标统计 96px 内「存活且未倒地」玩家数 `count`，`progress += delta * count`（时长 = 2.5s ÷ 人数），无人时 2× 衰减，达阈值复活；进度以 `unreliable` RPC 10Hz 广播（空 dict = 无救援），client 纯展示（`interact_prompt` 每个目标独立气泡，隐藏 use 图标）。**关键坑**：`--coop-devdown` 原实现只 `dev_set_local_hp(0)`，**并不会触发倒地**（`is_downed` 由 `set_downed_state` 写、经 `player_death_gate` 在真正死亡时才调用），故需 `dev_force_local_downed()` 直接 `set_downed_state(true)` 才能测。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] Boss 过场（镜头/暂停）与 FEVER/rage 需 host 权威跨端；客机暂停必须有墙钟看门狗兜底
- Evidence / 证据: `scenes/enemies/boss/goliath.gd:128-157`、`scenes/enemies/boss/erosion_tower_group.gd:106-160`（真 Boss 演出 `emit_camera_move/emit_ui_visible/emit_pause_lock` + `get_tree().paused`；镜像 `has_meta("network_remote_enemy")` 直接 return）；`ui/round_timer.gd:132-166`（FEVER/rage 本地触发 `emit_fever_time_start()` + `add_rage_buff()`）；本体 `script/extension_hooks.gd`（新增 `fever_time_gate`）；mod `mods/etn_coop/net/coop_net.gd`（`_on_local_camera_move/_remote_boss_camera_move/_release_boss_cinematic/_tick_boss_cinematic/_gate_fever_time/_remote_fever_time_start`、`CINEMATIC_MAX_MSEC`、连接 `camera_move/camera_reset/ui_visible/fever_time_start`）。
- Notes / 说明: **根因**：① Boss 过场由真 Boss 本地执行、镜像端跳过 → 客机无镜头/无暂停（host 独自觉进入暂停）；② FEVER/rage 各端各自倒计时触发，客机 `add_rage_buff` 对 BOSS 组镜像 `apply_buff` 经 `enemy_buff_apply_gate` 转发 host → **host 被重复上 buff**。**修法**：过场用 `camera_move` 广播**世界坐标**（`Marker2D` 不能过 RPC，客机建临时 marker 复刻），`black=true` 时客机本地 `paused=true` + `pause_lock(true)`；复位走**幂等** `_release_boss_cinematic()`。FEVER 用 `fever_time_gate` 让客机不本地触发，host 广播 `_remote_fever_time_start`（客机只驱动 `play_fever_anim` 视觉），rage buff 只 host 施加经 `_remote_enemy_buff` 同步。**关键坑**：客机在过场中被 `get_tree().paused=true`，若 `camera_reset` 丢失/房主硬杀就会**永久卡暂停/黑屏**——必须有**不依赖 RPC 的兜底**：`CoopNet` 本就 `PROCESS_MODE_ALWAYS`，用 `_physics_process` 每帧查**墙钟**（`Time.get_ticks_msec`，不受 `Engine.time_scale` 影响）超 `CINEMATIC_MAX_MSEC` 强制释放，并在断线/复位所有挂点调用同一释放函数。**通用教训**：跨端复刻"会暂停整棵树"的演出时，暂停方必须自带超时兜底与幂等恢复路径；`Marker2D`/Node 引用不可跨 RPC，广播其世界坐标即可。
- Source / 来源: user + code
- Date / 日期: 2026-10-07

### [Mod][Character] coin_box 抛物线按折线同步 / 角色状态 int 只回放视觉 / Hina QTE 联机改动画慢放
- Evidence / 证据: `scenes/item/coin_box.gd:18-30`、`scenes/item/parabola_path.gd:11-33`（`drop()` 内先 `body.active_state()` 再建 `curve`/tween）、`scenes/item/coin.gd:63`（`on_coin_spawned`）；mod `mods/etn_coop/net/coop_net.gd`（`_on_coin_spawned` 抛物线分支、`_register_parabola_coin`、`_remote_parabola_coin`、`_update_coin_trajectories`、`_sample_polyline`、`coin_traj`/`PARABOLA_DURATION`）；`scenes/player/aris/aris_ps.gd`、`chinatsu/chinatsu_ps.gd`、`hoshino/hoshino_ps.gd`（get/apply 状态）、`kasumi/kasumi_melee.gd:30-37`+`kasumi/kasumi_ps.gd`（M5 事件）、`hina/hina_ps.gd`（`_qte_slow_begin/_qte_slow_end`）；`script/player.gd:167-193`（聚合子节点 int 状态 / 转发事件）。
- Notes / 说明: **① 抛物线金币**：`drop()` 里 `body.active_state()`（触发 `on_coin_spawned`）**早于** `curve` 构建，故只能按 `net_id` 延后一帧读 `parabola.curve` 转世界坐标广播；客机按折线+**墙钟**驱动 `coin_traj` 飞行、落地才 `can_pick`（拾取仍走 host 共享）。**② 角色状态**：`cstate` 是 int 且 `player.gd` 对直接子节点 OR 聚合；**`apply_network_character_state` 只准写视觉节点**——Aris 若写 `gun_heat.k` 会触发 `k_changed`→`add_heat_critical`/`gun_ammo_count` 玩法；Hoshino 若写 `melee_rank/shot_rank` setter 会 emit `*_rank_change`→`enhancement_shot_count`。**③ Kasumi 钻头是瞬态**（`kasumi_melee` 临时实例化、非持续状态、且无 `on_player_melee` 调用点）→ 用预留的 M5 角色事件通道广播、镜像生成 `set_script(null)` 的纯视觉钻头。**④ Hina QTE**：`Engine.time_scale=0.07` 是**每进程**的；客机只慢自己、房主会连同 mod 的 delta 发送节奏（`_state_timer`/`_snapshot_timer`）一起饿死→全场卡顿，且客机镜像跳帧、敌人仍常速（子弹时间手感失效）。联机改为**等比慢放 QTE 动画**（`qte_bar/AnimationPlayer.speed_scale=0.07`；bar 本就由 `qte_anim` 的 `bar:position` 轨道驱动），世界不减速。**通用教训**：跨端回放"角色持续状态"一律只动视觉、别碰会发 gameplay 信号的 setter；会改 `Engine.time_scale` 的本地机制在联机下要么改动画慢放、要么 host 权威广播。
- Source / 来源: user + code
- Date / 日期: 2026-10-07

### [Mod] 聊天室「发送即释放」：控件占用/释放与窗口淡出解耦
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_chat.gd`（`_acquire_controls`/`_release_controls`/`_controls_held`；`_open_chat`/`_refocus` 占用、`_submit`/`_hide_now` 释放）。
- Notes / 说明: 原实现把「恢复鼠标 + 解冻玩家」放在 `_hide_now()`（发送后 2 秒淡出结束才跑）→ 发送后 2 秒内鼠标仍 `VISIBLE`、玩家仍冻结，无法立刻继续操作。改为占用/释放两半并**幂等**：`_open_chat`/`_refocus` 占用（记 `_prev_mouse_mode`/`_prev_player_stop`，置鼠标 `VISIBLE` + `player_stop=true`），`_submit`/`_hide_now` 释放（按原值还原）。**发送即释放**（鼠标/操作立即恢复），窗口仍按 2 秒淡出；2 秒内回车重聚焦会再次占用。游玩态释放后指针隐藏（准星捕获）而窗口仍可见，属预期。验证（无头探针）：acquire 幂等=`true`、submit 后 `held=false`+失焦+窗口仍 `visible`、release 幂等=`false`、refocus 后 `held=true`；LAN 两端 `log=2` 无 `SCRIPT ERROR`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-07

### [Mod] 聊天按钮下方延迟小字：数据取常开的 `get_network_timing`、两个按钮各挂一个、场景节点需 force_reload
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_chat.gd`（`_make_ping_label`/`_hide_ping`/`_refresh_pings`/`_apply_ping_label`；`_ensure_button`/`_ensure_upgrade_button` 同步显隐）、`ui/coop_chat.tscn`（`%UpgradePingLabel` + 7x7 字体 ext_resource）、`net/coop_net.gd`（`get_network_timing`/`get_network_quality_debug_text`）。
- Notes / 说明: 主 HUD 按钮是**代码构建**（挂本地玩家 `$GameUI/AmmoPosition`，含 reparent）→ 延迟小字也代码构建、作其兄弟节点；升级页按钮是**场景节点** → 小字也放场景节点 `%UpgradePingLabel`（编辑器可调位置）。数据用**常开采集**的 `get_network_timing()["rtt"]`（`net_rtt_ms` 只在刷新点更新、且用采样均值更有代表性）；颜色复用 `get_network_quality_debug_text()`（good/fair/poor → 绿/黄/红），与 F9 HUD 同口径；`_process` 节流 0.3s、仅变化写入。**坑**：编辑 `coop_chat.tscn` 后若编辑器已加载该场景，`scene_open` 默认不重读（`reloaded_from_disk=false`）、`node_find` 看不到新节点 → 须 `scene_open(force_reload=true)`（或等 filesystem 重扫）；新增 `[ext_resource]` 字体可只写 `path`（uid 可选）。
- Source / 来源: code + test
- Date / 日期: 2026-10-07

### [Mod] 聊天按钮命中判定用带类型参数接收已释放对象会崩（`_hit_test`）；删除孤儿 sweeper 脚本
- Evidence / 证据: `mods/etn_coop/ui/coop_chat.gd:406`（`func _hit_test(btn: TextureButton, event: InputEvent)`；`_button_hit:403` 调 `_hit_test(_btn, event) or _hit_test(_upgrade_btn, event)`；`_ensure_button` 把 `_btn` 挂到本地玩家 `$GameUI/AmmoPosition`）；`scenes/enemies/enhanced_sweeper.tscn:3`/`modded_sweeper.tscn:3` 根脚本 = `sweeper.gd`（uid://caqfbtqobq27l），`scenes/enemies/{enhanced,modded}_sweeper.gd` 无任何场景/资源引用（其 uid 仅出现在各自 `.uid`，且无 `class_name`）。
- Notes / 说明: **崩溃**：游戏 break reason = `Invalid type in function '_hit_test' ... argument 1 (previously freed)`。根因：场景切换/进测试房时本地玩家重建 → 挂在玩家 `GameUI/AmmoPosition` 下的 `_btn` 被释放，而 `_input` 早于 `_process`（`_ensure_button` 重建）触发，把已释放对象传给**带类型参数** `btn: TextureButton` → Godot 在参数类型检查处直接报错，函数体里的 `is_instance_valid(btn)` 守卫根本轮不到执行。修法：`_hit_test` 参数去类型（`func _hit_test(btn, event: InputEvent)`），已释放引用可进门、由内部 `is_instance_valid` 拦掉；镜像 `mods/etn_coop/ui/coop_chat.gd` 与源码 `mod_sdk/coop_mod/mods/etn_coop/ui/coop_chat.gd` 两份同改。**孤儿脚本**：`scenes/enemies/{enhanced,modded}_sweeper.gd` 曾被误当在用（两场景根脚本本就是 `sweeper.gd`），本轮连同 `.uid` 一并删除（`filesystem_manage remove` 因 `res://ui/res/button.res` 二进制依赖拒绝，改由直接删文件 + `filesystem scan`）。**通用教训**：① GDScript 带类型参数对**已释放实例**会在入参边界报 `Invalid type ... previously freed`，`is_instance_valid` 守卫必须配合**无类型参数**（或调用方先判有效）才生效；② 「靠 `_process` 重建的引用」不要在 `_input` 等更早回调里直接使用，跨帧可能仍指向已释放对象。验证：`game_eval` 构造并释放 `TextureButton` 后 `chat.call("_hit_test", freed, event)` 返回 `false`（`freed=true`，无报错）；删除后 `filesystem scan` 通过、`iori_ps.gd`/`hit_box.gd`/`coop_chat.gd` `find_symbols` 均正常，重跑无 break。
- Source / 来源: code + test
- Date / 日期: 2026-10-07

### [Mod][Base] 版本比较：`game_version` 作“最低支持本体版本”，按数字段比较并忽略 `-test` 后缀
- Evidence / 证据: `script/Game.gd:10`（`version_number = "v0.5.1.2-test"`）；`script/mod_manager.gd:_mount_one`（原 `gv != Game.version_number` 仅告警；`_version_parts`/`_version_gte`）；`mods/etn_coop/net/coop_net.gd:_client_hello`（原 `game_ver != Game.version_number`；`_versions_equal`/`_version_parts`）；`mods/etn_coop/mod.json` 与 `mod_sdk/coop_mod/mods/etn_coop/mod.json`（`version` 0.1.1、`game_version` v0.5.1.2-test）。
- Notes / 说明: **规则**——manifest `game_version` 语义 = **最低支持的本体版本**（不再要求相等）；比较取 `v` 后按 `.` 拆数字段、丢弃首个 `-` 及其后（`-test` 等）、去尾零、缺位补 0，逐段比。**两处用途**：① 本体 `mod_manager` 仅在「本体 < 声明最低版本」时 `push_warning`（**不阻断挂载**，符合既有宽松设计）；② mod LAN 握手 `_versions_equal` 按数字段判等 → 测试版 `v0.5.1.2-test` 与正式版 `v0.5.1.2` 视为同版本可互通。**动机**：`-test` 是测试标签，正式版会去掉后缀；若沿用字符串精确比较，正式版与更高版本都会误报/误拒。**通用教训**：本体版本若带 `-test` 等后缀，任何“版本门槛”比较都必须归一化后按数字段比，别用字符串相等。

### [Mod] 打包版本号约定与产物
- Evidence / 证据: `mod_sdk/build_coop_mod.ps1`（默认输出 `mod_sdk/coop_mod/build/etn_coop.pck` + `etn_coop.zip`）；本次额外产出 `build/etn_coop_0.1.1.zip`。
- Notes / 说明: 版本号三处同步——`mod.json.version`、`coop_net.gd:MOD_VERSION`、以及（用于分发归档的）`etn_coop_<version>.zip`；当前 **0.1.1**。`build/` 已被 `.gitignore` 忽略，产物不入库。
- SUPERSEDED: 2026-10-08 版本升至 0.1.2（`PROTOCOL_VERSION` 同步 1→2），归档改由 `build_coop_mod.ps1` 自动产出 `etn_coop_<version>.zip`。
- Source / 来源: user + code
- Date / 日期: 2026-10-07

### [Foundation] `Object.get_meta(name, null)` 不抑制“缺少 meta”的报错，仅非 null 默认值才抑制
- Evidence / 证据: `mods/etn_coop/net/coop_item_visuals.gd:92`（原 `mirror.get_meta("coop_last_follow_icon", null)`）；运行日志 `The object does not have any 'meta' values with the key 'coop_last_follow_icon'. (coop_item_visuals.gd:92 @ build_icon)`。
- Notes / 说明: Godot 的 `get_meta(name, default)` 只在 `default != null` 时返回默认并跳过报错；显式传 `null` 会被当作“未提供默认” → 缺 key 仍 `push_error`。判存在请用 `has_meta(name)` 再 `get_meta(name)`（本轮改法），或传一个非 null 哨兵值。首个 follow 图标时该 meta 尚未写入，故必触发。
- Source / 来源: test + code
- Date / 日期: 2026-10-08

### [GDScript] 硬类型 `Node` 变量访问 native 属性（如 `global_position`）是 parse error；脚本自定义属性按动态放行
- Evidence / 证据: `scenes/player/iori/iori_ps.gd:84`（`ExtensionHooks.notify(..., [..., bullet_body.global_position])`，`bullet_body: Node`）→ `Parse Error: Identifier "global_position" not declared in the current scope`；同文件 `bullet_body.penetrate`（脚本属性）不报错。
- Notes / 说明: Godot 4 静态检查对 **native 属性**（`global_position`/`rotation`/`global_rotation`/`scale`）在硬类型基类缺失时直接 parse error；而 **GDScript 脚本自定义属性**（`penetrate`/`speed`/`damage_data`…）解析器无法穷举子类 → 按动态访问放行、不报错。子弹实际是 `HitBox`→`Area2D`。修法：把用 native 属性的参数类型 `Node` 收窄为 `Node2D`（`add_flash`/`shoot_bullet`），调用处 `shoot_bullet(bullet_body as Node2D)` 显式转换（信号 `player_projectile_hit` 声明为 `Node`）。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod] 中继客机不进准备房：引擎 `connected_to_server` 依赖自定义 peer 显式 admit host(peer 1)
- Evidence / 证据: `mods/etn_coop/net/coop_relay_peer.gd`（旧 `join_admitted` 只把服务端 `join_prepared.peers` 列出的 peer 放进 `_peers_to_connect`，再由 `_poll` `emit peer_connected`）；引擎 `SceneMultiplayer::_admit_peer` 只在 `p_id == 1` 时 `emit_signal("connected_to_server")`（`modules/multiplayer/scene_multiplayer.cpp`）；`mods/etn_coop/net/coop_net.gd:384-389`（`_on_connected_to_server` 才发 `_client_hello`）、`:440-451`（房主 `_accept_peer` 才 `_remote_change_scene` 送 `test_room`）、`:6694-6695`（`_on_relay_room_joined` 仅改状态、不切场景）。
- Notes / 说明: **现象**（user）：房主中继开房已进准备房，客机面板显示「已作为 N 加入中继」（`relay_room_joined` 已触发、传输通），但客机不切 `test_room`、房主也看不到客机。**根因**：中继客机能否进入准备房完全取决于能否发出 `_client_hello`，而该 RPC 只由引擎的 `connected_to_server` 触发；对自定义 `MultiplayerPeerExtension`，`connected_to_server` 只在 peer 发出 `peer_connected(1)` 时产生。旧实现只 admit 服务端 `join_prepared.peers` 列出的 peer——若该服务端列表不含 host(1)，客机永不 admit host → 不发 hello → 房主不 `_accept_peer` → 不进准备房，且约 5s 后因未握手被踢。**修法**（`coop_relay_peer.gd`）：① `join_admitted` 时若 `_unique_id != 1` 且列表无 1，强制补入 host(1)（协议保证 host=1、client≥2）；② `_on_data` 收到谁的数据就 `_queue_peer(source)`——因 relay `_poll()` 在引擎 drain `_incoming` **之前** emit `peer_connected`，房主可在同一帧接纳客机的 `_client_hello`，无需依赖服务端 join 通知；③ 新增 `_admitted` 去重（防重复 `peer_connected` 导致重复 hello / 重复 `_remote_change_scene`）；④ `--debug` 下打印控制帧与 admit 日志。**通用教训**：凡自定义 `MultiplayerPeerExtension`，**必须**确保「对端=1」被显式 admit，否则引擎端到端信号（`connected_to_server`）与对端包的受理（`connected_peers.has(sender)`）都不会发生；网络层 peer 的发现不能只信服务端下发的成员列表，应以「协议保证的 host id + 实际收到的数据源」共同兜底。**待真机验证**（未跑中继服务端）：改后需房主/客机双端 relay 实测客机自动进 `test_room`。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 特效通道（无 velocity）只广播 spawn、无 despawn：长期物远端残留累积；客机回合边界不跑本体 bullet_clear
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`（`_on_projectile_spawned`：`bullet.get("velocity")==null` → `_pending_effects`；`_on_projectile_despawned`：原只处理 `remote_visual`/`net_visual_id`）、`scenes/main/main.gd:120 bullet_clear_unit`（仅由 `scenes/manager/round_manager.gd:141` 在 host 非测试房触发）、`coop_net.gd`（`_gate_round_end_proceed` 令客机在 `round_manager` 的 bullet_clear 之前 return）、`scenes/bullet/player_laser_beam.gd`（`extends RayCast2D`，无 velocity）、`scenes/bullet/launcher/laser_launcher.gd`（`extends Node2D`，无 velocity）。
- Notes / 说明: **现象**（user）：联机远端 `player_laser_beam` 本机消失后对方侧不消失、每回合累积。**根因**：`_on_projectile_spawned` 以「有无 `velocity`」分流，无 velocity 者走**特效通道**（只发一次 spawn、无 id、无 despawn）；`_on_projectile_despawned` 原只回收 `net_visual_id`/`remote_visual` → 持续激光/发射器远端永不回收。跨回合更不清：`_visual.reset()` 只在换场（`_reset_player_sync`）触发；且本体 `bullet_clear` 只在 host 非测试房分支跑，**客机被 `_gate_round_end_proceed` 提前 return，`BulletRoot` 下远端视觉/特效无人清**。**修法**：① 特效通道分配 `net_effect_id`（`_on_projectile_spawned`）→ `_on_projectile_despawned` 广播 `_despawn_visual_effect`/`_server_despawn_visual_effect` → `CoopVisualSync.despawn_visual_effect` 按 id 回收（含 `_ended_effect` 防迟到复活）；② 新增 `_clear_round_visuals()` 挂 `_on_round_start`（两端都触发）：`_visual.reset()` + 释放 `BulletRoot` 下带 `remote_visual` 的子节点 + 清 pending 队列。**敌人无需 mod 另清**：本体 `scenes/main/main.gd:83 enemy_clear_unit`（`EnemiesRoot` 的 `Enemy` 子节点 `erase_pool`+`queue_free`）挂在 `round_manager.enemy_clear`+`GameEvents.round_upgrade`+`round_upgrade_end`，两端都会跑。**另修**：`_despawn_owned_summons_local` 客户端越权调 authority-only `_despawn_summoned_remote` → 改走 `request_summoned_despawn`（host/client 分流）。两份副本（`mods/coop` + `mod_sdk/coop_mod`）同步改。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 持久身体/召唤物 despawn：无 is_idle 与直接 queue_free 都漏发；换角色不清 EquipLayer
- Evidence / 证据: `scenes/update_item/shiroko_drone.gd:7-10`（`_on_equip` 把 body 挂 `EquipLayer`）、`scenes/update_item/robotic_vacuum_cleaner_body.gd` 与 `shiroko_drone_icon_2.gd`（`extends CharacterBody2D`，**均无 `is_idle`**）、`coop_summoned_proxy.gd:46,82-87`（仅按 `is_idle` 判定 despawn）、`coop_net.gd:_replace_player_for_peer`（换角色只 `old.queue_free()`，不清 EquipLayer、不发 summon despawn）。
- Notes / 说明: **现象**（user）：测试房内选带视觉道具（如 shiroko_drone）后重置/换角色，残留 `shiroko_drone_body`。**定位更正**：该残留属**持久身体/召唤同步**通道（`PERSISTENT_BODY_SCENES`：drone/vacuum body 由 `_on_equip` 挂到 `EquipLayer`，`_register_persistent_body` 走召唤同步），**不是** `item_visual_by_peer`（`shiroko_drone` 不在任何图标清单，`_remote_item_visual` 打印 none）；两者根脚本**都无 `is_idle`**，`CoopSummonedProxy` 永不发 despawn；换角色时 base 只释放玩家节点，EquipLayer 孤儿 body 与本机/远端镜像都不清。**修法**：① proxy 本地拥有者连 `summoned.tree_exiting` → 未发过则 `request_summoned_despawn`（覆盖无 is_idle 与直接 `queue_free`）；② `_replace_player_for_peer` 本地分支调 `_despawn_owned_summons_local()`、远端分支调新 `_despawn_peer_summons(peer_id)`。**同类补齐**：通用视觉通道（`_on_visual_activated`/`_maybe_broadcast_visual_node`）原也无 despawn → 现分配 `net_effect_id` + 连 `tree_exiting`，释放时广播 `_despawn_visual_effect`（复用特效通道 id/RPC）；带 id 的一次性特效不再被远端 6s 抢先释放（`CoopVisualSync.spawn_visual_effect` 的 `_queue_free_after` 仅在无 id 时启用）；回合兜底 `_clear_round_visuals` 扩到 `CoinRoot` 的远端 medkit 镜像（客机 `item_clear` 被 gate 跳过）。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 聊天室自动显示（PEEK）与输入（COMPOSE）双态：只调背景/输入框透明度、面板不拦截鼠标
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_chat.gd`（`_composing`、`_peek_show`、`_set_peek_visual`、`_on_chat_received`、`_activate`、`_set_mouse_ignore`；`PEEK_BG_ALPHA`/`PEEK_INPUT_ALPHA=0.4`）、`ui/coop_chat.tscn`（`Scroll.vertical_scroll_mode=3`）。
- Notes / 说明: 需求：新消息自动显示、不聚焦、更透明、不拦鼠标、隐藏滚动条、游戏结束保留。修法：把单一 `_is_open` 拆成 `_is_open`（可见）+ `_composing`（输入态）。`_on_chat_received` 在关闭时 → `_peek_show()`（显示、`_composing=false`、滚动到底、`_schedule_hide(HIDE_DELAY)`；peek 中再来消息重置计时，淡出中亦重置重显）；PEEK 下 `_activate()` → `_refocus()` 升格为 COMPOSE（占用控件+聚焦+恢复满不透明）。**透明度只动面板 StyleBox 的 `bg_color.a` 与 `_input_box.modulate.a`（0.4 ↔ 原值 `_orig_bg_alpha`），消息 `Label` 保持 1.0**——改整个面板 `modulate` 会连文字一起变淡，故不用。**不拦截**：`_ready` 递归把面板子树 `mouse_filter=IGNORE`（输入靠程序 `grab_focus`，键盘仍可输入），避免可见面板吞掉游玩期鼠标点击/挡开火。**滚动条**：`vertical_scroll_mode=3`（SHOW_NEVER）隐藏但仍可程序滚动。**游戏结束**：`_on_game_over` 不再 `_hide_now()`（结算/团队结束页保留窗口、peek 继续）。`_schedule_hide(delay)` 参数化，peek 与 compose 共用 `_hide_token`。**坑**：stylebox 是场景内 sub_resource，运行时改 `bg_color` 仅影响本面板；`get_theme_stylebox("panel")` 可能非 flat，须判类型。验证（无头探针）：peek(open/comp=false/holds=false/bg=0.40/in=0.40)、compose(comp=true/held=true/focus=true/bg=0.94/in=1.0)、submit 后 held=false、game_over 后仍 open、面板子树全 IGNORE、vmode=3；LAN 两端 `log=2` 无错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] 战绩金币改「各自获取」：共享拾取按拾取者归属 + 个人金币复用 player_coins_get 上报
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_add_team_coins`；`_broadcast_team_stats` 去掉 coins 覆盖；`_do_shared_coin_pickup`/`_server_pickup_coin` 归属；`_apply_shared_coin_local` 打 `_applying_shared_coin`；`_on_local_coins_get`/`_server_coin_gain`；`install_hooks` 连 `GameEvents.player_coins_get`）。
- Notes / 说明: 原 `_broadcast_team_stats` 每周期把 host 的共享 `stats.coin` 覆盖到每个人的 `team_stats[pid]["coins"]` → 全行相同。改为按「各自获取」：① **共享拾取归拾取者**（host 在 `_do_shared_coin_pickup` 记 `get_unique_id()`；client 经 `_server_pickup_coin` 记 `get_remote_sender_id()`）；② **个人金币加成**（满血医疗箱转金币 / coin_return / chocolate_coin / atlantis medal / 策反清场结算）都经既有 `GameEvents.player_coins_get` → `_on_local_coins_get` 上报 host 归属本人。**区分关键**：共享拾取唯一走 mod 的 `_apply_shared_coin_local`，其发 `player_coins_get` 时用 `_applying_shared_coin` 抑制，避免个人通道重复计入——**零本体改动**。跨回合累计，`_reset_run_state` 清空。验证（无头探针）：personal 50→`team[1].coins=50`、抑制期 30 不计、非 LAN 999 不计；`_do_shared_coin_pickup(77)`→host 77、再 `_add_team_coins(2,30)` 后 `_broadcast_team_stats` 不覆盖（77/30 保持）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [UI][Mod] 记分板击杀/金币缩写阈值按列宽估算；BoutiqueBitmap9x9 @ font_size 8 数字约 4.79px/位
- Evidence / 证据: `mods/etn_coop/ui/coop_scoreboard.gd` 与 `mod_sdk/coop_mod/mods/etn_coop/ui/coop_scoreboard.gd`（`KILLS_ABBREV_AT=100000` / `COINS_ABBREV_AT=1000000`、`_fmt_num(n, abbrev_at=1000)`）；列宽见 `ui/coop_scoreboard_row.tscn`（Name 100 / Kills 60 / Damage 80 / Coins 70，字体 `res://fonts/BoutiqueBitmap9x9_1.9.ttf`、`font_size=8`）；字体度量由 `fonts/BoutiqueBitmap9x9_1.9.ttf` 解析：`unitsPerEm=1000`、数字/`K`/`B`/`T` advance `599`、`M` `799`。
- Notes / 说明: 需求：击杀与金币只在数字过大时才用 K/M，伤害保持 ≥1000 起缩写。实测该字体 `font_size 8` 下数字约 `599/1000*8 = 4.79px/位`（`M`≈6.39px），击杀列 60px 可容 ~12 位、金币列 70px ~14 位 → 纯“撑爆列宽”几乎不会发生，阈值实为观感选择。取 6 位（10 万）/7 位（100 万）：`99999` 原样、`100000→100K`；`999999` 原样、`1000000→1M`；进位保护保留（`_fmt_num(999950,100000)`→`1M`）。`_fmt_num` 默认阈值 1000 使伤害调用不变。**通用教训**：缩写阈值应按**实际字体 advance × 列宽**估算（TTF 的 `unitsPerEm`/`hmtx` 可直接算），而非套用“1000”这类约定值。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 敌人池化重登记不清旧 net_id 映射 → 快照重复发包 / 网表泄漏
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`register_enemy_spawn` 原只 `enemy.remove_meta("net_id")` 后直接写入新 id；`_attach_enemy_proxy` existing 分支只改映射不重跑 `setup`；`_clear_round_visuals`/`_apply_enemy_snapshot` 只删 3 个字典）、`script/entity_ENEMY.gd:96-97`（`idle_state()` 只置 `is_idle=1`，不清 `net_id`/映射）。
- Notes / 说明: 池化敌人再次激活时 `script/spawn_anim.gd:109` 会再次 notify `on_enemy_spawned` → `register_enemy_spawn` 分配**新** net_id，但旧 `enemy_by_net_id`/`enemy_scene_by_net_id`/`enemy_proxy_by_net_id` 条目仍指向同一敌人；`CoopEnemyProxy` 被复用但内部 `net_id` 停在旧值。后果：`_send_enemy_snapshot` 按多 key 对同一敌人重复发包、跨回合 O(回合数) 增长；旧失效分支也漏清快照缓存/位置历史/击杀归属。修法：新增 `_forget_enemy_net_id(net_id)` 统一清 7 张表；`register_enemy_spawn` 重登记前按旧 id 清理；`_attach_enemy_proxy` existing 分支重跑 `setup` 刷新；死亡/失效/回合清理均改走 `_forget_enemy_net_id`。**通用教训**：池化实体的“重新登记”必须与“注销”对称，否则按 id 建的注册表只增不减。
- Source / 来源: code + user
- Date / 日期: 2026-10-08

### [Mod] Relay 开房握手期被误判「房主离开」→ 8s 后弹回主菜单
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_network_heartbeat`（`HOST_TIMEOUT_MSEC=8000`，按 `multiplayer.is_server()` 分支）、`mod_sdk/coop_mod/mods/etn_coop/net/coop_relay_peer.gd:146-149`（`_unique_id` 到 `room_created` 才置 1）。
- Notes / 说明: relay 主机在 `room_created` 之前 `get_unique_id()==0` → `is_server()==false` → 心跳走**客户端**分支；若中继服务端 >8s 才回包，即触发 `_schedule_host_left_return()`（关连接 + 过场回主菜单）。修法：`_network_heartbeat` 在 peer 非空后加 `if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return`。**注意 `get_connection_status()` 定义在 `MultiplayerPeer` 上，不在 `SceneMultiplayer`（`multiplayer`）上**，写成 `multiplayer.get_connection_status()` 会每帧 `Invalid call`。**通用教训**：任何“按 `is_server()`/`get_unique_id()` 分流”的逻辑，在传输握手完成前都不可靠，用连接状态门控。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod] 联机 any_peer 信任边界加固：路径白名单 + 数值上限 + 归属校验
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（新增 `_is_safe_remote_path`/`_is_safe_item_id`/`_sanitize_for_authority`/`_sanitize_player_state`/`_sanitize_buff_value`/`_sanitize_event_data` 与 `MAX_NET_*` 常量；接入 `_server_enemy_hit`/`_server_enemy_part_hit`/`_server_enemy_conversion`/`_server_apply_enemy_buff`/`_server_relay_player_buff`/`_server_relay_summoned_buff`/`_server_visual_bullet_batch`/`_server_visual_bullet_reliable_batch`/`_server_visual_effect_batch`/`_server_visual_node`/`_server_register_summoned`/`_server_summoned_spawn`/`_server_summoned_action`/`_server_summoned_state`/`_server_request_player_change`/`_server_player_ready`/`_server_player_selected`/`_server_receive_player_state`/`_server_support_ex`/`_server_pickup_coin`/`_server_medkit_taken`/`_server_shared_pyroxenes_gain`/`_server_coin_gain`/`_remote_item_visual`/`_server_player_info`/`_server_hit_sfx`/`_server_despawn_visual_bullet`/`_server_despawn_visual_effect`）。
- Notes / 说明: 联机以 `any_peer` RPC 接受大量客机输入，原先可让 host `load()`/实例化任意资源路径、上报任意伤害/金币/策反/玩家状态。加固（保持 host 权威语义，不影响单机/主机自身路径）：① **资源路径**仅允许 `res://` 且命中前缀（`res://scenes/`/`res://script/`/`res://resources/`/`res://mods/`），buff 限 `res://resources/buff/*.tres`、玩家场景限 `res://scenes/player/`+`res://mods/`，禁 `..`/反斜杠；② **数值** sanity 上限 `MAX_NET_DAMAGE=MAX_NET_CONVERT=2^50`、`MAX_NET_STAT=1e9`，非数值拒绝，buff 值限 3 项并 clamp；③ **玩家状态**非有限坐标直接拒帧，`hp/max_hp/t_hp/ammo/state/character_state` clamp；④ **归属**：`summoned_action`/`summoned_state`/`summoned_buff` 校验 owner==sender，`support_ex` 强制 owner=sender，`pickup_coin` 用 host 记录的币值（未知 net_id 拒绝）、`medkit_taken` 要求已知 net_id；⑤ `item_id` 限 `[a-z0-9_]`。**通用教训**：`any_peer` RPC 的参数是不可信输入，即便局域网友好房也应做路径白名单与数值夹取，避免“客机让主机加载任意资源 / 撑爆数值 / 伪造归属”。验证：双进程 headless LAN（`--coop-host`/`--coop-join=127.0.0.1` + `--coop-devbattle --coop-devpreplaced --coop-devbuff`）`remotes=1`/`enemies=10`、buff 两端同步，零 `SCRIPT ERROR`/`Invalid`/`previously freed`。
- Source / 来源: code + user + test
- Date / 日期: 2026-10-08

### [Mod] 视觉通道接收端信任漏洞（V1–V6）：伤害洞 / 方法调用 / 属性 set / 任意场景
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_visual_sync.gd`（`spawn_visual_bullet:74-75` `for k in pr.keys(): bullet.set(str(k),pr[k])`；`:80-83` `bullet.call(pre_method/method_name)`；`spawn_visual_effect:190-191` `effect.set`；`:194-195` `effect.call`；`:166-167` `get_first_node_in_group(root_group)`；`_open_player_damage_hole:325+` `maxi(1,damage)` 无上限；`laser_bullet.gd:125 open_network_player_damage_hole`）；`coop_net.gd` 的 `_server_visual_bullet_batch`/`_reliable_batch`/`_server_visual_effect_batch`/`_server_visual_node` 原仅校验路径前缀后 `_spawn_one_visual/_spawn_one_effect`→接收端 `properties.get("eb")`/`dmg`/`kb` 原样使用。
- Notes / 说明: 视觉通道被当"纯表现"，接收端几乎全信任客户端：① **V1 伤害洞**——客机可传 `eb=true`+任意 `dmg/kb`，host 与其余端（batch 会转发）会开"敌方弹伤害洞"→ 对 host/所有玩家造成任意伤害（合规上 `eb=true` 只应来自 host 的敌方弹广播）；② **V2 方法/父组注入**——`m`/`pre` 任意 → `call()`；`grp` 任意 → 可把场景塞进 `EnemiesRoot`/`PlayerRoot`；③ **V3 场景过宽**——`res://scenes/**` 允许 enemies/boss/player/manager，而 `_disable_damage` 只清碰撞、不停 `_physics_process`/AI → 可在 host 跑活敌方场景（甚至经 `ProjectileSpawner` 再广播）；④ **V4 属性注入**——`pr` 所有键 `set()`（发送端有白名单，接收端没有）。修法：接收端对客机来源一律经 `_sanitize_bullet_entry`/`_sanitize_effect_entry`（路径走 `SAFE_VISUAL_SCENE_PREFIXES`、`method/pre`∈`SAFE_VISUAL_METHODS`、`grp`∈`SAFE_VISUAL_GROUPS`、`pr` 按 `BULLET/EFFECT_PROP_NAMES` 过滤、**强制 `eb=false`**），`spawn_visual_effect` 加 `allow_hole`、`_remote_visual_node`/`_remote_summoned_action` 加 `no_hole`（客机来源禁洞；host→client 的 authority 路径不变）；`_open_player_damage_hole` clamp。**通用教训**：① "纯表现"通道若接收端会 `instantiate`/`set`/`call`/决定父节点或开放伤害，就必须按**不可信输入**全字段校验，别只校验路径；② 发送端白名单 ≠ 接收端白名单（发送端过滤只防本机误发，挡不住构造包）；③ "伤害洞"这类会改变判定层的开关必须**区分来源**（只允许权威端开启）；④ 场景路径白名单要排除 gameplay 目录，且 `_disable_damage` 不清 AI/physics 时更需路径限制。验证：双进程 LAN（client `--coop-devbullet --coop-deveffect`）host `visuals=5 effects=5 rej=0`，零错误；`--coop-devselflaser` host `hp 72→50`（合法伤害洞未受影响）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] 高频通道令牌桶限频（被 host 转发放大的 unreliable 通道）
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`：新增 `_rate_allow_tokens(peer,cat,rate/s,burst)`（令牌桶，`_rpc_bucket`），接入 `_server_receive_player_state`(45/s,15)、`_server_summoned_state`(按 net_id 30/s,6)、`_server_player_gun_shoot`(60/s,20)、`_server_player_hurt`(60/s,20)、`_server_hit_sfx`(60/s,20)、`_server_visual_bullet_batch`/`_server_visual_bullet_reliable_batch`/`_server_visual_effect_batch`(300/s,30)；`_clear_peer_rate`/`_reset_run_state` 清 `_rpc_bucket`。
- Notes / 说明: 高价值目标是「**unreliable + 被 host 向全队转发**」的通道：1 个客机洪泛会被 host 放大成 N 份。unreliable 丢弃安全（下一包覆盖）→ 加限频零玩法风险，主要收益是阻断放大。选择令牌桶而非固定窗口是因为高频通道在窗口边界用固定窗口会顿挫；桶允许小突发更贴合真实射击/受击节奏。上限一律取合法频率 ≥2×（player_state 20Hz→45/s；summoned_state 15Hz/召唤→按 net_id 30/s 避免多召唤玩家被误伤）。**`_server_enemy_hit` 是 reliable，丢弃=丢真实伤害，故不限频**。已验证 client→host 命中转发（`--coop-devowner`：host `proc=0`、client `proc=1→2`）与移动/常规回归不受影响。**通用教训**：① 判断是否限频看两点——是否 reliable（丢=丢状态）、是否被 host 转发放大；② 高频通道用令牌桶、低频/经济用固定窗口即可；③ 按 net_id/实体而非仅 peer 聚合，避免多实体玩家被误伤。
- Source / 来源: code + user + test
- Date / 日期: 2026-10-08

### [Mod] 退出语义（客机只结算自己）+ 反滥用限频 + 镜像坐标限幅（10–13）
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`：`_gate_game_over`（客机分支 `_schedule_client_leave_local`→`_leave_session_local`→`close_connection`；host 分支不变）、`_server_request_team_game_over`（改为忽略）；新增 `_rate_allow`/`_clear_peer_rate`/`_count_summons_owned_by` + `MAX_SUMMONS_PER_PEER`/`RPC_RATE_WINDOW_MSEC`，接入 `_server_shared_pyroxenes_gain`/`_server_coin_gain`/`_server_pickup_coin`/`_server_medkit_taken`/`_server_chat`/`_server_register_summoned`；`_server_receive_player_state` 用 `MapBounds.nearest_inside`（`script/map_bounds.gd:69`）。
- Notes / 说明: **#10 语义变更（来源 user）**：原「LAN 下 `emit_game_over` 一律团队结束」改为——**房主退出 → 全员结算；客机退出 → 只结算自己**（本机照常 `GameEvent.game_over` 结算页 + deferred 断线，host/其余玩家继续）。重要前提：LAN 下客机的 `emit_game_over` **只来自暂停退出**（`pause_screen` 4 处），`Stats`（`player_death_gate` 已接管为倒地）与 `round_manager`（客机被 `round_end_proceed_gate` 挡掉）都不会在客机触发，故只改 `_gate_game_over` 客机分支是安全且完备的。`_server_request_team_game_over` 保留但忽略，防止已握手客机绕过 gate 结束整局。**实测坑**：`_gate_game_over` 返回 false 才会走本机结算（`game_over_page.time_count_stop`），返回 true 会吞掉本地结算、只能等 host 广播。**#11 已知残留**：`_remote_item_visual` 为 `any_peer` 经引擎 `server_relay`，客机可伪造 `owner_peer` 刷图标（纯视觉），按决定不修。**#12**：`_rate_allow` 1s 固定窗口，对经济（coin/pyroxenes/medkit/pickup）与 chat 限频、`_server_register_summoned` 每 peer 召唤数上限，防已握手客机 DoS/刷取。**#13**：`MapBounds.nearest_inside` 在 hull 未就绪时原样返回，故无副作用。**通用教训**：① 改联机"结算/结束"语义前，先穷举本端所有 `emit_game_over` 触发点（哪些在客机被其他 gate 挡掉），否则会误伤非退出场景；② 反滥用限频优先覆盖"经济/资源"这类明确可获利通道；③ 坐标类校验除了有限性还应限幅（`MapBounds` 已是现成工具，且对 `RemotePlayer` 不自动纠偏故需手动）。验证：仅 client `--coop-devpause` → client `client left run (self-settle)`、host `peer disconnected` 后 `battle=true`/`remotes=0`/`enemies=10` 继续；常规双进程 LAN 回归零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] 断线残留清理：倒地/救援/图标/召唤物按 peer 清，记分板行保留到本局结束
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_on_peer_disconnected`（原只清 player/proxy/scene/support/aura/handshake；新增 `down_peer_ids`/`_rescue_progress`/`_rescue_rescuer_count`、`_clear_peer_item_visuals`、`selected_player_scene_by_peer`、`_despawn_peer_summons_networked`/`_despawn_peer_summons`、`_broadcast_rescue_progress`、`_check_team_game_over`）；`_server_update_rescue`（目标失效分支补 `down_peer_ids.erase`）；`_rescue_progress` 由 host 权威维护、`item_visual_by_peer` 图标挂在 `PlayerRoot` 不随镜像释放。
- Notes / 说明: 客户端中途退出后，host 侧会残留：`down_peer_ids` 条目（每帧 `_server_update_rescue` 空转）、救援进度/气泡、挂在 PlayerRoot 的道具常驻图标、该 peer 拥有的召唤物镜像（其余端也保留）。按 peer 清理并在 host 广播（救援进度、召唤物 despawn）。**决策（来源 user）**：`team_stats`/`player_name_by_peer`/`last_attacker_by_net_id` **刻意保留到本局结束**——记分板行与击杀归属延续，不做“掉线即删行”。**通用教训**：断线清理要覆盖“挂在别人父节点下的视觉/进度态”（图标、prompt），否则随镜像释放的假设会漏；`from-peer` 与 `to-peer` 两侧的镜像都要清（host 广播 + client 本地清）。验证：双进程 LAN，client `--coop-devautoquit=14` 中途退出 → host `remotes=0`、记分板行仍在、零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] 握手门控：服务端 any_peer RPC 只接受已握手 peer（Relay 无 kick 帧的兜底）
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_server_sender_ok()`（`_handshaked_peers.has(get_remote_sender_id())`）加在所有服务端 `any_peer` handler 的 `is_server()` 之后（约 43 处）；`_diag_ping` 仅 host 分支门控；`_remote_item_visual` 因经引擎 `server_relay` 在客户端也需执行故不加；`coop_relay_peer._disconnect_peer`（协议无 `kick_peer` 帧，只能清本地 `_known_peers`）。
- Notes / 说明: LAN 上 `disconnect_peer` 能直接踢未握手连接；**Relay 无法踢单个逻辑 peer**（中继协议 `create_room/join_room/client_ready → room_created/...` 没有 kick/close_peer 帧），被拒客户端若不自觉 close，其 socket 仍在。用统一门控保证「未握手/被拒」peer 无法调用任何权威 RPC（与 #3 消毒互补）。**易错点**：① `_handshaked_peers` 只在 host 填充，门控必须写在 `is_server()` 分支内，否则会误伤客户端处理的 relayed RPC（如 `_remote_item_visual`）；② `_diag_ping` 双向，需 `if is_server() and not _server_sender_ok()`；③ `_server_chat` 原**没有** `is_server()` 守卫，需补。验证：`--coop-devbadver` 版本不一致 → host 拒绝、client 自 `close_connection`、host `peer disconnected`、零错误。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod] 退出期释放传输：`_notification` 拆分 + `multiplayer` 可能为 null
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_notification`（`WM_CLOSE_REQUEST` 走完整 `close_connection`；`EXIT_TREE`/`PREDELETE` 只 `transport.peer.close()` + 置空，并 `if multiplayer != null` 守卫）；`close_connection`（`_reset_run_state()` 加 `get_tree() != null` 守卫）。
- Notes / 说明: 原实现在 `EXIT_TREE`/`PREDELETE` 也跑完整 `close_connection`（含 `_reset_run_state` 的 emit/queue_free 与 `multiplayer.multiplayer_peer = null`），在引擎销毁路径上有副作用风险（README 曾记「multiplayer 回调栈内释放会 segfault」）。改为退出期最小释放。**实测坑**：`EXIT_TREE`/`PREDELETE` 时 `multiplayer` 可能已为 `null`，直接 `multiplayer.multiplayer_peer = null` 会报 `Invalid assignment ... on a base object of type 'null instance'`，必须判空。验证：游戏 headless `--quit` 无该错误。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod] 信任边界补漏（1–9）：漏门控 / 无上限批量 / 未消毒的 buff-stats 与支援 mods / buff 白名单过窄
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`：`_client_scene_ready` 原缺 `_server_sender_ok()`；`_server_visual_effect_batch`/`_server_visual_bullet_batch`/`_server_visual_bullet_reliable_batch` 无 `batch.size()` 上限；`support_mods_by_peer[sender]=mods.duplicate()` 与 `_refresh_medkit_mods` 的 `rate = max(rate, mods.rate_mult)` 无上限；`_server_apply_enemy_buff` 的 `stats`/`source_id` 未消毒；`_server_boss_pattern_event` 的 `event_data` 未消毒；`SAFE_BUFF_PREFIX` 仅 `res://resources/buff/`；`_server_enemy_hit` 的 `victim_pos` 未查有限；`_client_hello` 的 `game_ver` 未限长；`_server_summoned_state` 的 `state`/`facing` 未夹。
- Notes / 说明: 上一轮信任边界加固的漏项：① `_client_scene_ready` 漏门控 → 未握手 peer 可换 roster/敌人/召唤列表；② 视觉批量逐条 `load()`/实例化、未限 `size()` → 超大数组 DoS（合法发送按 `BULLET_BATCH_LIMIT` 切包，故 cap `*2` 不影响）；③ 医疗箱「rate_mult 上限 2.0」只在文档、代码未落地 → 客机可令 host 医疗箱洪泛；④ 施加者 DOT 属性 `stats` 白名单缺失 → 客机可塞超大 `dot_damage`；⑤ buff 白名单过窄会挡 `res://mods/` 自定义 buff；⑥ `victim_pos=NaN` 可跳过回滚校验。**通用教训**：① 新增 `any_peer` handler 必须同批加握手门控，否则漏网（列表化核对）；② 凡 "接收数组/字典后逐条实例化/存储" 的接口都要加 `size()`/字段白名单上限；③ 文档声明的上限必须在代码里夹（README 的 2.0 未夹即被利用）；④ 路径白名单要同时覆盖本体与 `res://mods/`，否则误挡 mod 内容。验证：游戏 headless `--quit` 干净，双进程 LAN（含 `--coop-devbuff`、`--coop-devautoquit`）`remotes=1`→`remotes=0`、零错误。
- Source / 来源: code + user + test
- Date / 日期: 2026-10-08

### [Mod] 崩溃隐患修复（H1–H6）：召唤通道注入活敌 / buff 类型未校验 / `Engine.time_scale` 裸写 / 死链接线
- Evidence / 证据: ① `coop_net.gd:_server_register_summoned`（原 `SAFE_REMOTE_SCENE_PREFIXES`）、`_spawn_summoned_local`（`_disable_remote_simulation` 后又 `active_state()`）、本体 `script/entity_ENEMY.gd:132-151`（`active_state` 重开物理/StateMachine、`register_active_enemy`、`global_time_count.connect`）。② `_server_apply_enemy_buff`/`_remote_enemy_buff`/`_remote_player_buff`/`_apply_summoned_buff_local` 的 `load(buff_path)`；`script/buff_router.gd:3`（`buff: Buff`）、`buff_manager_base.gd:81`（`buff: Buff`）。③ `ui/motion_down_screen.gd:42/61/64`（直写 `Engine.time_scale`）。④ `coop_summoned_proxy.gd:73` / `coop_net.gd:_on_visual_node_tree_exiting`（场景拆除时 `multiplayer` 为 null）。⑤ `player_buff_apply_interceptor`/`player_buff_remove_interceptor`（`extension_hooks.gd:41/43` 声明但本体从未调用）。⑥ `coop_relay_peer.gd:_on_control` 的 `peers` 未校验类型。
- Notes / 说明: **H1**：召唤通道场景白名单过宽（含 `res://scenes/enemies/`），且 `_spawn_summoned_local` 在 `_disable_remote_simulation` 之后调 `active_state()`——本体 `entity_ENEMY.active_state()` 会重开物理/AI/StateMachine、`PoolManager.register_active_enemy`、`global_time_count.connect(time_count)` → 客机可让 host 生成会移动/开火的敌人，镜像释放后留下悬空信号连接（`previously freed`）。修：召唤改专用白名单 `SAFE_SUMMON_SCENE_PREFIXES`（`scenes/summoned/`、`player_support/kei/kei_summoned.tscn`、`update_item/utaha_turret(_body)`/`shiroko_drone_body`/`robotic_vacuum_cleaner_body`、`res://mods/`），并在 `active_state()` 后调 `CoopSummonedProxy.disable_mirror_sim()` 再停用（同时修掉「所有远端召唤镜像本地跑 AI」）。**H2**：buff 资源只校验路径前缀，非 `Buff` 资源喂给 `apply_buff`/`BuffRouter`（形参 `Buff`）会运行期类型错误 → `load` 后 `if not (buff is Buff): return`（本体 enemy buff 均 `script_class="Buff"`，安全）。**H3**：`motion_down_screen` 直写 `Engine.time_scale` 违反单写者约定（与 Hina QTE 等互相覆盖、可能残留）→ 改 `GameEvents.request_slow("coop_down",0.1,0.5)`/`end_slow`。**H6**：`player_buff_*_interceptor` 是本轮之前遗漏的本体接线（mod 装了却从不触发）→ 在 `script/buff_router.gd` 的 `apply_buff`/`remove_buff`/`remove_source` 接 `ExtensionHooks.intercept(...)`（未装 mod 返回 false，零回归），使光环对远端镜像的 buff 转交归属端。**顺带**：`tree_exiting` 回调在场景拆除时 `multiplayer` 可能为 null → 加判空（本次回归实测暴露并修复）。**通用教训**：① 通道的"场景白名单"要按**用途**收窄（视觉/召唤各一套），不能共用 `res://scenes/` 宽前缀；② 本体 `active_state()` 常会**重开**被禁用的物理/AI，禁用必须在 `active_state()` 之后再做；③ 凡是会 `call`/`set`/`instantiate` 的"表现"回调都要同时校验路径+方法+属性+类型；④ `Engine.time_scale` 严禁裸写；⑤ 声明给 mod 的 hook 必须在**本体有真实调用点**（否则死链，功能静默失效）；⑥ `tree_exiting`/`_exit_tree` 里访问 `multiplayer` 必须先判空（节点已不在树）。验证：游戏 headless `--quit` 干净；双进程 LAN（`--coop-devbattle --coop-devpreplaced --coop-devbuff --coop-devsummon --coop-devmotion`）`summons=1`/`remotes=1`/`time_scale=1.0`、零错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] 联机敌人人数缩放：生命/伤害走 spawn_anim 收口，数量走 enemies_spawn.round_mult
- Evidence / 证据: `script/spawn_anim.gd:96-112`（`spawn_enemy_body` 读 `ExtensionHooks.enemy_spawn_stat_scale()` 后写 `max_hp_mult`/`Enemy_damage_mult`/`Enemy_bullet_damage_mult`，部件同系数）、`script/enemies_spawn.gd:48-51`（`get_level` 读 `enemy_spawn_count_scale(now_round,max_round)` 乘 `round_mult`）、`script/extension_hooks.gd`（两个 query 槽）、`mods/etn_coop/net/coop_net.gd`（`_enemy_spawn_stat_scale`/`_enemy_spawn_count_scale`，`is_lan_game` 才生效）。
- Notes / 说明: **收口点选择**：血量/伤害所有刷怪路径（`enemies_spawn`/`path_spawn`/`raid_spawn`/Boss 的 `enemy_spawn_launcher`）最终都调 `spawn_anim.spawn_enemy_body()`，故钩子放此即全覆盖；数量只有 `enemies_spawn` 走 `round_mult`（`path_spawn`/`raid_spawn` 用固定 `enemy_quantity`，不覆盖）。**同步**：host 权威，`max_hp_mult`/绝对 `max_hp` 随快照走 `coop_net.gd:3609/4397`，客机自动跟随、无需新字段；客机战斗敌人经 `_spawn_enemy_remote` 生成不走 `spawn_anim`，不会二次加成；客机被 `_gate_round_enemy_spawn` 拦截不调数量钩子。**单机零回归**：未注入/非 LAN 时 `is_valid()==false` 直接跳过。**数值**（固定）：生命 `1+0.5·(N-1)`、伤害 `1+0.1·(N-1)`、数量 `1+0.5·(N-1)·taper`（`EARLY_ROUNDS=max_round×0.5`，仅前期）。**通用教训**：给 mod 加"敌人强度缩放"优先找**唯一刷怪收口**（`spawn_anim`），数量类只能改波次生成器，且要区分 `round_mult`（随回合）与固定数量路径。
- Source / 来源: code + user
- Date / 日期: 2026-10-08

### [Mod] coop_chat `_apply_ping_label` 悬空 Label：带类型参数 + 已释放实例 → 退出测试房崩溃（`_hit_test` 同类残留）
- Evidence / 证据: `mods/etn_coop/ui/coop_chat.gd:413`（`_refresh_pings` 调 `_apply_ping_label(_ping_label,...)`）、`:417`（原 `func _apply_ping_label(label: Label, ...)`）、`:386-391`（`_hide_ping` 只改 `visible` 不清悬空引用）、`:318-334`（`_ensure_button` 玩家失效分支早退）、`:44`/`:108-111`（`_process` 顺序）；既有 `_hit_test` 同类条目（`coop_chat.gd:452` 已去类型化）。
- Notes / 说明: `_ping_label`/`_btn` 动态挂在本地玩家 `Player/GameUI/AmmoPosition` 下（`_ensure_button`），退出测试房玩家被释放 → Label 一并释放，变量变悬空（freed，非 null）。`_process` 顺序 `_ensure_button` → `_ensure_upgrade_button` → `_refresh_pings`：退出瞬间 `coop` 仍有效且 `is_lan_game==true`，但玩家已失效，`_ensure_button` 早退只调 `_hide_ping()` 未清引用；`_refresh_pings` 随后把 freed 的 `_ping_label` 传给**带类型参数** `label: Label` → Godot 在**入参类型检查**处抛 `Invalid type ... previously freed`，函数体内 `is_instance_valid(label)` 守卫根本轮不到执行。修：① `_apply_ping_label` 参数去类型（对齐 `_hit_test`）；② `_hide_ping` 与新增 `_hide_btn` 在引用失效时置 `null`，`_ensure_button` 三个早退分支改调 `_hide_btn()`。`_upgrade_ping`（`%UpgradePingLabel`）是常驻 CanvasLayer 场景子节点，不受影响（coop_chat 挂 `get_tree().root` 跨场常驻）。**通用教训**：同一脚本内凡「动态挂到会随场景释放的节点下、又靠 `_process` 重建的引用」，其消费者函数参数必须**去类型**，否则 `is_instance_valid` 守卫形同虚设；`_hit_test` 修了不代表同类全清，要全脚本扫一遍带类型参数。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] 房主进准备房/开战硬切无转场：`enter_lobby`/`begin_battle` 漏 `Transition.play_left_start`
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`（`enter_lobby` 原 `:7076` 直接 `GameEvents.change_scene(LOBBY_SCENE, host_scene)`；`begin_battle` 原 `:7256` 直接 `GameEvents.change_scene(scene_path, local_player_scene_path)`；客机 `_remote_change_scene` `:6204-6205` 有 `_play_scene_transition_start`）；本体基准 `scenes/main/menu_screen.gd:172-176`（`Transition.play_left_start()` → `await Transition.left_end_start` → `change_scene`）；`ui/transition.gd:13-22`；`script/GameEvents.gd:195-196`（`tree.tree_changed` 后仅当 `is_left_end_start==true` 才 `play_left_end`）。
- Notes / 说明: 房主建房（`host_game:7477` / `_on_relay_room_created:7547`）经 `enter_lobby` 直接 `change_scene`，**未** `play_left_start` → `is_left_end_start` 恒 false → `change_scene` 跳过 `play_left_end`，测试房硬切无转场；客机因 `_remote_change_scene` 调了转场助手而有转场，两端不一致。修法：把助手 `_play_remote_scene_transition_start` → 通用 `_play_scene_transition_start`（`coop_net.gd:5601`，null-guard + `play_left_start` + `await left_end_start`），在 `enter_lobby`（rpc 广播后、`change_scene` 前）与 `begin_battle`（`_broadcast_roster`/`_force_release` 后、`change_scene` 前）各补 `await _play_scene_transition_start()`。两者调用方（`host_game`/`_on_relay_room_created`/dev 入口）均不 await，转协程安全。**通用教训**：本体转场是「调用方先 `play_left_start` 并 await，`change_scene` 负责 `play_left_end`」的两段式——mod 任何绕过本体 UI、直接调 `GameEvents.change_scene` 的入口都必须自带这一段，否则硬切；`--coop-devbattle` 走 `auto_enter_lobby=false` 不经 `enter_lobby`，故常规回归覆盖不到，需用 `--coop-devflow` 验证。验证：`--coop-host --coop-devflow --coop-devautoquit=22` 日志 `enter lobby` → `start ball spawned` → `dev-flow in lobby` → 选人 → `main.tscn` 全流程无 `SCRIPT ERROR`；`build_coop_mod.ps1` 43 files；`coop_sim_regression.ps1` 4/4 PASS。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod/Server] 断线重连：稳定 token + host 宽限迁移（方案 B 新 id）+ 服务端同 token 替换/连接心跳
- Evidence / 证据: 客户端 `mods/etn_coop/net/coop_settings.gd:ensure_client_token`（UUID 持久化 `profile/client_token`）；`net/coop_relay_peer.gd:create_relay_host/join_relay_room`（控制帧带 `token`）、`net/coop_network_transport.gd:create_relay(...,token)`；`net/coop_net.gd`：`_client_hello(...,token)`/`_peer_token`/`_token_peer`/`_old_peer_for_rejoin`/`_migrate_peer_state`/`_begin_peer_grace`/`_update_rejoin_timeouts`/`_cleanup_peer`（原 `_on_peer_disconnected` 主体）、客机 `_begin_reconnect`/`_tick_reconnect`/`_try_reconnect`/`_finish_reconnect`/`_abort_reconnect_to_menu`/`_release_transport_for_reconnect`/`_show_reconnect_overlay`/`_freeze_local_player_for_reconnect`；`ui/coop_reconnect_overlay.gd`（代码构建 CanvasLayer）；`net/coop_name_tag.gd:set_offline`；`i18n/coop_i18n.gd`（`coop_reconnecting`/`coop_status_reconnected`/`coop_peer_offline`）；`entry/coop_entry.gd:--coop-devdrop=<sec>`；服务端 `mod_sdk/coop_mod/server/relay_server.py`（`Peer.token/last_seen`、`join_room` 同 token 先 `remove_peer` 旧连接、`heartbeat_peers` 主动 PING + `PEER_TIMEOUT_MSEC`）。
- Notes / 说明: **方案 B（新 id + host 迁移）**：重连必然拿到新 peer id（ENet 由 host 分配、Relay 由服务端 `next_peer_id` 分配），故 host 用持久化 UUID token 识别「同一玩家」，把旧 id 的全部 per-peer 状态（角色/名字/team_stats/support/倒地/镜像字典）迁移到新 id；`_accept_peer` 改成只在缺失时填默认角色，避免覆盖迁移值。**宽限**：`_on_peer_disconnected` 对已握手且有 token 的 peer 不立即破坏性清理（保留镜像与字典、冻结 `player_stop`），`REJOIN_GRACE_MSEC=45s` 内等待 token 重连，超时才 `_cleanup_peer`；宽限期内 `_check_team_game_over` 直接 return（防其余人倒地误结束）。**客机保持场景**：断线不回菜单、不 `change_scene`，仅遮罩 + 冻结 + 退避（1.5→2→…→5s）重连，成功判定 `_hello_accept`；`close_connection` 在 `_reconnecting` 时**不** `_reset_run_state`、不清 `_last_join_params`，故本地升级/金币/位置自然保留。**严禁在 multiplayer 信号回调栈内改 peer** → `_begin_reconnect` 用 `_release_transport_for_reconnect.call_deferred()`。**服务端**：`join_room` 在容量判断前对同 token 的旧 `clients` 先 `remove_peer`（释放名额，解决满房误拒 + 半开幽灵占位）并广播 `peer_disconnected(old_id)` 让 host 进宽限；`heartbeat_peers` 主动 PING 清半开。**房主关房自动区分**：Relay 重连得 `Room not found` → `_on_relay_error` 立即回菜单（LAN 连接失败退避数次后回菜单）。**通用教训**：① 跨重连的稳定身份只能客户端自持 + host 侧迁移，服务端只负责连接生命周期；② 宽限必须冻结但不清，且团队结束/升级就绪判定要跳过掉线者；③ 半开旧连接不清理会占满名额，必须在服务端加同 token 替换 + 连接心跳；④ 任何"保持本地状态"的重连都要求断线路径绕过 `_reset_run_state`。**实测**：双进程 LAN `--coop-devdrop=5` → host `offline grace`→`migrate 1159166132->1260631889`→`accept`，client `reconnect attempt 1`→`reconnected`，0 SCRIPT ERROR；Relay（本地 7716）同流程、服务端 `assigned_peer_id=2→3`，0 错误；`coop_sim_regression.ps1` 4/4 PASS。**已知局限**：掉线期间 host 若推进回合，客机仍停旧回合；房主自身重连未做。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod] 掉线期间 host 的回合切换冻结：跨回合推进等待重连（不丢升级）
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`：`_deferred_round_end`/`_round_upgrade_active`/`_in_round_upgrade`/`_wait_reconnect_name`；`_gate_round_end_emit`（host 且 `_reconnecting_peers` 非空 → 记 `_deferred_round_end` 并 return true）；`_maybe_finish_round_upgrade`（宽限非空 → return）；`_on_rejoin_settled`（宽限清空后补发 `GameEvents.emit_round_end()` + `_maybe_finish_round_upgrade()` + 广播 `_remote_wait_reconnect("")`）；`_begin_peer_grace`（广播 `wait_reconnect_show`/`_remote_wait_reconnect(name)`）；`_client_hello` 重连识别后若 `_round_upgrade_active` 补发 `rpc_id(new,"_remote_round_end")`+`_remote_round_upgrade`；`_remote_round_upgrade` 幂等 + `_on_round_upgrade_end_local` 复位。UI：`ui/coop_round_wait.gd:show_message(text, light)`（light=隐藏 Background 遮罩 + 字号12、回合计时下方顶部居中 + `MOUSE_FILTER_IGNORE`）、`_apply_wrap`（按视口宽度换行）；`net/coop_flow.gd:_on_wait_reconnect_show/hide`；`i18n/coop_i18n.gd:coop_wait_reconnect`。本体触发点：`ui/round_timer.gd:147/153/181`（`_round_end_emit_blocked`）、`round_manager.gd:86-109`（`round_upgrade_end`→`_on_round_start`→`emit_round_start`→`init_round` 递增）、`script/GameEvents.gd:258-264`（`round_upgrade_end` gate / `force_round_upgrade_end`）。
- Notes / 说明: **根因**：回合号递增发生在两端各自的 `round_start`（`round_timer.init_round` → `now_round_num += 1` → `PlayerData.now_round`），而回合推进由 host 权威广播驱动；客机断线期间收不到 `_remote_round_end`/`_remote_round_upgrade`/`_remote_round_upgrade_end`，host 却继续推进 → 客机停旧回合。**修法（A：host 冻结回合切换）**：host 在重连宽限内暂缓两个跨回合卡点——① `emit_round_end` 触发（`_gate_round_end_emit` 记 `_deferred_round_end` 并阻止，覆盖普通/Boss）；② 升级页推进（`_maybe_finish_round_upgrade` 直接 return）。宽限清空（重连成功或超时清理）→ `_on_rejoin_settled` 解冻并补发。这样回合号在客机断线期间不变，客机回来无缝续上，无需回合 resync。**升级不丢（方案 B 补）**：重连识别后若 host 正在升级页（`_round_upgrade_active`），补发清场+升级页让重连者参与本次升级；客机 `_in_round_upgrade` 幂等防重复打开。**UI**：新增 `wait_reconnect_show/hide` 信号 + `coop_round_wait` light 模式（宽限期间世界仍可操作，故隐藏整屏黑底遮罩且鼠标穿透，文字字号12、置于回合计时下方顶部居中——2026-10-09：原 `LIGHT_TOP_MARGIN=12` 与 `ui/round_timer.tscn` 顶部居中计时（Control 高约 40px）重叠遮挡，改为 `LIGHT_TOP_MARGIN=44`、`LIGHT_BAND_HEIGHT=24` 下移到计时下方，避开左上 HUD 与 y≈82 的 FEVER 横幅），名字按视口宽度 `autowrap`（`MAX_NAME_LEN=12`）。**通用教训**：① "本地不回退的持续状态"（回合号）在断线重连下要么 host 冻结推进、要么做 resync；冻结更简单且语义符合"全员同步推进"；② 冻结必须在**所有**跨边界触发点，漏一个（如 Boss `end_boss_round`）就会穿透；③ 冻结只是 host 逻辑暂停，不暂停世界时 UI 遮罩必须鼠标穿透，否则玩家无法瞄准；④ 长玩家名要换行兜底（`MAX_NAME_LEN=12` 宽字符可超宽）。**实测**：`--coop-devfreeze` 白盒探针 host `{before:false, during:true, deferred:true, after:false}`；LAN `--coop-devdrop=5` 重连仍通、0 SCRIPT ERROR；`coop_sim_regression.ps1` 4/4 PASS。**未覆盖**：test_room 无回合计时器，回合冻结的真实端到端（正常关卡+升级页）留待实机验证。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod/Server] 中继加入加固：客机握手超时 + 拒绝容错 + 重复加入防抖 + 服务端 pending/id 回收
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`：`PROTOCOL_VERSION` 1→2、`HELLO_ACCEPT_TIMEOUT_MSEC=6000`、`_hello_sent_msec`/`_hello_acked`/`_relay_connect_in_flight`、`_update_client_handshake_timeout()`（`_physics_process` 调用）、`_hello_reject(reason: String = "")`、`_client_hello` 增 `mod_version` 校验、`create_relay_room`/`join_relay_room` 顶置 in-flight 守卫、`is_connect_in_flight()`、`close_connection`/`_reset_run_state`/`_on_*` 复位、`_update_rejoin_timeouts` 加 `multiplayer_peer==null` 守卫；`net/coop_relay_peer.gd:_close` 先发 `leave_room`；`ui/coop_menu.gd:_set_relay_busy` 锁定/解锁按钮；`i18n/coop_i18n.gd` 新增 `coop_status_host_version_old`/`coop_status_handshake_timeout`；服务端 `mod_sdk/coop_mod/server/relay_server.py`：`Room.pending`、`all_peers`/`alloc_peer_id`、`join_room` 同 token 覆盖 pending+clients 且复用 id、容量含 pending、`client_ready` 移 pending→clients、`remove_peer` 仅对已准入广播、`cleanup_rooms`/`heartbeat_peers` 用 `all_peers`。
- Notes / 说明: **现象**：中继「显示已加入但没进房」+ 编辑器大量 `RPC ... expected N argument(s)` 报错。根因：对端（旧构建）coop mod 版本不同、RPC 契约不一致；而 `_client_hello` 只校验 `PROTOCOL_VERSION`+`game_version`、**忽略 `MOD_VERSION`**，且客机没有 `_hello_accept` 超时 → 握手失败后一直卡在「已加入」。**修法**：① 客机发 hello 后 `HELLO_ACCEPT_TIMEOUT_MSEC` 内收不到 `_hello_accept`/有效 `_hello_reject` → 关闭连接并提示 `coop_status_handshake_timeout`；② `_hello_reject(reason: String = "")` 默认参兼容旧房主 0 参 reject；③ `PROTOCOL_VERSION` 递增使旧房主主动拒新客机，`_client_hello` 补 `MOD_VERSION` 校验使新 host 拒旧客机（README 声称校验但代码漏项，已补）；④ 中继重复点击：客户端 `_relay_connect_in_flight` 防抖 + 按钮禁用 + `_close` 发 `leave_room`；服务端此前 `join_room` 每次 `next_peer_id++` 且同 token 去重只扫已准入 `clients`、pending 不被跟踪/不占容量 → 反复加入被当作新成员排到后面；改为 `pending` 集合覆盖去重与容量、`alloc_peer_id` 复用空出的 id、只对已准入 peer 广播 `peer_disconnected`（防幽灵事件）。**通用教训**：① 版本握手必须校验「会变的那部分」——RPC 契约变更就递增 `PROTOCOL_VERSION`，且客机侧必须有握手超时兜底（对端旧时连 reject 都可能解析失败）；② 中继这类「每次点击新建连接」的入口要做 in-flight 防抖 + 主动 `leave_room`，服务端要维护 pending 集合、复用 id、只对已准入广播。**实测**：LAN `coop_sim_regression.ps1` 单条件 PASS；`--coop-devbadver` 客机日志 `handshake rejected by host: game_version` 且不再每帧刷 `get_unique_id` 报错；本地 relay（新服务端 7799）host+client 端到端 `handshake accepted`、进入 `test_room`、服务端 `assigned_peer_id=2`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] coop_chat 面板整棵 `mouse_filter=IGNORE` 连带禁用 ScrollContainer 滚轮 / 触屏拖动
- Evidence / 证据: `mods/etn_coop/ui/coop_chat.gd`（原 `_ready` 的 `_set_mouse_ignore(_panel)` 递归把 `%Scroll` 也设 `MOUSE_FILTER_IGNORE`，引入于 `ca0a055`；现 `_acquire_controls` 输入态恢复 `_scroll.mouse_filter = STOP` + `mouse_force_pass_scroll_events = false`，`_release_controls` 恢复 `IGNORE`）；`mods/etn_coop/ui/coop_chat.tscn`（`Scroll` 节点挂 `res://script/ScrollBox.gd`）；`project.godot:213`（`pointing/emulate_mouse_from_touch=false`）。
- Notes / 说明: **根因**：为「游玩期面板不吞点击/不挡开火」而把 `Panel` 整棵子树递归设 `IGNORE`，而 `ScrollContainer` 的滚轮必须自身接收事件（`STOP`）才有反应 → 滚轮一并失效。**修法**：只在输入态（`_composing`：鼠标可见、玩家冻结）把 `_scroll` 恢复 `STOP`，并 `mouse_force_pass_scroll_events=false` 独占滚轮；发送/关闭/peek 恢复 `IGNORE`，保持不吞游戏输入。**触屏拖动**：项目关闭 `emulate_mouse_from_touch`，必须复用 `script/ScrollBox.gd`（`extends ScrollContainer`，自实现 `ScreenTouch/ScreenDrag` + 鼠标拖拽），挂到 `Scroll` 即可；因消息 `Label`/`LogBox` 均为 `IGNORE`，触摸穿透到 `Scroll`，与拖动不冲突。**通用教训**：递归把 Control 子树设 `IGNORE` 时，若树内有 `ScrollContainer`，会静默禁用其滚轮；应把「不拦截」限制在非滚动子树，或在激活态按需恢复 `STOP`。两份副本（`mods/` 镜像 + `mod_sdk/` 源码）须同步。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 断线帧 RPC 刷屏：周期发送前须判「连接状态」，仅判 peer 非空不够
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`：新增 `_net_connected()`（`is_lan_game` + peer 非空 + `get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED`）；`_physics_process` 发送块（`_send_local_player_state`/`_send_enemy_snapshot`/`_server_update_rescue`/`_flush_visuals`）、`_update_network_diagnostics`（`_diag_ping`）、`_network_heartbeat` 改用之；`_send_local_player_state` 顶部加防御门控。
- Notes / 说明: **现象**：断线瞬间 `coop_net.gd:_send_local_player_state(): Trying to call an RPC via a multiplayer peer which is not connected`（红字刷屏）。根因：`_physics_process` 只判 `multiplayer.multiplayer_peer == null`，而房主/中继断开后 peer 对象仍在、状态变 `DISCONNECTED`，且 `is_lan_game`/`battle_active` 仍为真 → 继续 `rpc_id(1,...)`。**通用教训**：`MultiplayerPeer` 对象非空 ≠ 可发送；任何周期/事件发送前都要判 `get_connection_status()==CONNECTION_CONNECTED`（ENet 与自定义中继 peer 同理），正确范例见 `_network_heartbeat`。`_on_visual_node_tree_exiting` 因场景拆除期 `multiplayer` 可能为 null，保留显式 null 判断、不套用统一门控。**实测**：LAN host 10s 后退出、客机仍在战斗中 → 无该错误、正常走 `host session closed -> return to menu`；`coop_sim_regression.ps1` PASS。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] 自定义 MultiplayerPeerExtension 的 `_get_packet_peer/_channel/_mode` 必须 peek 队首（引擎先问后取）
- Evidence / 证据: `mods/etn_coop/net/coop_relay_peer.gd`：`_get_packet_script()` pop 后才写 `_current_pkt_peer/_channel/_mode`；`_get_packet_peer/_channel/_mode` 原返回这三个值 → 改为 peek `_incoming[0]`（空队列回退旧值）。引擎 `modules/multiplayer/scene_multiplayer.cpp:SceneMultiplayer::poll()` 每个包先 `get_packet_peer()`/`get_packet_channel()`/`get_packet_mode()`，再 `get_packet()`（弹出），随后 `ERR_CONTINUE(!connected_peers.has(sender))`。
- Notes / 说明: **现象**（user）：中继下偶发红字 `poll: Condition "!connected_peers.has(sender)" is true`（join 一次、断线收尾一次）。**根因**：sender 错位一拍——引擎先问 peer 再取包，而我们的 `_get_packet_peer()` 返回「上一次 pop 的 peer」（首包为初始 0）。于是首包 sender=0、某 peer 断开后下一包 sender=残留的断开 id → `!connected_peers.has(sender)`；单客户端时同源掩盖，多客户端会**把 A 的包记成 B 发的**（权威/归属问题更严重）。**修法**：三个 getter 改为 peek 队首（`_incoming[0]`），`_get_packet_script` 继续维护 `_current_*` 仅作空队列兜底。**通用教训**：自定义 `MultiplayerPeerExtension` 里，凡引擎在 `poll()` 中「取包前」调用的 getter（peer/channel/mode）都必须返回**队首**数据；pop 与这些 getter 的读取顺序不可想当然。**实测**：本地中继端到端 host 14s 退出、client 战斗中 → host/client `connected_peers` 报错均为 0，`handshake accepted`、正常 `host session closed -> return to menu`；`coop_sim_regression.ps1` PASS；重导出 `etn_coop_0.1.2.zip`（pck 601756 B）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] 无 peer 时的信号/延迟回调清单与守卫（`is_server`/`get_unique_id` 报错收口）
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd` 新增 `_has_peer()`（peer 非空，不要求 CONNECTED）；守卫点：`_on_server_enemy_damage_taken`/`_on_server_enemy_part_damage_taken`/`_on_server_enemy_dead`（含 await 后复检）、`_add_team_damage/_add_team_kill/_add_team_coins`/`_broadcast_team_stats`、`_local_buff_source_id`/`_send_player_buff`/`_on_local_support_ex_end`、`_assign_effect_broadcast_id`/`_maybe_broadcast_visual_node`/`_register_persistent_body`、`get_local_player`/`set_local_display_name`/`_join_index_of`/`_display_name_for`/`_local_display_name`/`_refresh_all_name_tags`/`_refresh_all_ready_tags`/`_handle_part_hit`。
- Notes / 说明: **现象**（user）：`coop_net.gd:6799 @ _on_server_enemy_damage_taken(): No multiplayer peer is assigned`（敌人 `damage_taken` 信号在会话结束后仍触发）。**根因**：`multiplayer.multiplayer_peer == null` 时 `is_server()/get_unique_id()` 报错；引擎默认 peer 是 `OfflineMultiplayerPeer`（单机不报），只有 `close_connection()`/`_notification`/`_release_transport_for_reconnect` 把 peer 置 null 后，仍连着敌人/部件 `damage_taken`、`is_dead`（由 `register_enemy_spawn`/`_connect_enemy_dead`/`_connect_enemy_parts` 连接）与 `child_entered_tree`→（`_maybe_broadcast_visual_node.call_deferred`）视觉广播、以及菜单改名/名牌刷新等非 RPC 入口才会命中。**修法**：`MultiplayerPeer` 对象非空 ≠ 可发送——RPC 发送用 `_net_connected()`（含 CONNECTED），本地可用工具用 `_has_peer()`（仅非空）并给合理默认（`get_local_player` 回退 `"Player"` 组、`_join_index_of` 回退 1、`_display_name_for` 回退 `_default_display_name`、`_local_buff_source_id` 回退 `""`）；`_on_server_enemy_dead` 的 `await` 之后必须**复检**。**通用教训**：会话结束/重连窗口里，凡「信号回调」「`call_deferred` 延迟调用」「菜单/UI 工具」都可能无 peer，务必先判 `_has_peer()`/`_net_connected()` 再碰 `is_server()/get_unique_id()/get_peers()`。**实测**：`--coop-devname` 与 game_eval 强制 `multiplayer_peer=null` 后调用上述工具，editor 日志 0 条 `No multiplayer peer`；中继 host+client 端到端 0 条该错误、0 SCRIPT ERROR；`coop_sim_regression.ps1` PASS；重导出 `etn_coop_0.1.2.zip`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08


### [Mod] 记分板行生命周期：加入即建 0 行 + 房主正式开始清零（准备房 `battle_active` 已为 true）
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`（`_ensure_team_stat`/`_broadcast_team_stats`/新增 `_reset_team_stats`；`_accept_peer` 与 `_on_first_round_add` host 分支补 `_ensure_team_stat(pid)`+`_broadcast_team_stats()`；`_broadcast_roster` 顶部调 `_reset_team_stats()`；周期广播在 `_physics_process:3778` 仅 `is_lan_game and multiplayer.is_server() and battle_active` 时跑）。`ui/coop_chat.gd`/`ui/coop_scoreboard.gd`（移动端点聊天按钮显示战绩 + 聊天窗显示时按尺寸左移）。`export_presets.cfg` Android `exclude_filter` 含 `mods/etn_coop/*`（移动端只吃已装 pck）。
- Notes / 说明: 需求：进正式关卡后战绩不应残留准备房（测试房）数据；准备房有玩家加入即出现 0 行。**非显然点**：`battle_active` 在 `_on_first_round_add`（准备房也触发）即置 true → 1s 周期 `_broadcast_team_stats` 在准备房**就在跑**（这正是测试房数据能累积并带入关卡的原因）；但周期广播只 `_ensure_team_stat(host)`，新加入者不会自动建行。修法：① `_accept_peer`（握手通过）与 `_on_first_round_add`（host）调 `_ensure_team_stat(pid)` + `_broadcast_team_stats()` → 加入即 0 行且全员可见；② `_broadcast_roster()`（房主选关/开战唯一出口：`_gate_change_scene` 的 `ALL_READY` 分支 / `_server_player_selected`）顶部 `_reset_team_stats()`：清空后按当前 `multiplayer.get_peers()` 重建**全员 0 行**并 `rpc("_remote_team_stats")`，准备房累计不带入关卡；③ 掉线仍**保留行**（配重连，`_cleanup_peer` 注释），不重连的幽灵行会在下次正式开始按当前 peers 重建时消失。**移动端部署坑**：Android preset `exclude_filter` 排除 `mods/etn_coop/*`，移动端只加载 `user://mods/etn_coop/etn_coop.pck`（桌面另有本体镜像遮蔽 pck → 桌面验证通过不代表手机生效）；改完必须 `mod_sdk/build_coop_mod.ps1` 重打包并把新 pck/zip 覆盖到手机才能生效。**通用教训**：`team_stats` 只在 `_reset_run_state` 清、**不随场景切换**清——凡「每局重置」的数据要挂到明确的阶段边界（此处 `_broadcast_roster`），别指望换场景。验证：`game_eval`（host）预置 `{1:…,99:…}` → `_reset_team_stats()` 后仅 `{1:{0,0,0}}`（幽灵 99 清除）；`_ensure_team_stat(7)` 幂等不覆盖已有值；桌面 `game_eval` 另验桌面/移动/peek 三种显隐与左移 `offset=-59`（`chat_left=432`、面板右缘 485、间隙 6）；两份副本一致、`find_symbols` 通过；`build_coop_mod.ps1` 44 files。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod][Summon] 召唤物等级改固有属性 + 镜像友方近战击退：HurtBox「探测专用」+ 顶部伤害闸门
- Evidence / 证据: 本体 `script/SummonedStats.gd:22-27`（`level_enabled`/`max_level`/`level_damage_add=6`/`level_up_exp_base=3`/`level_exp_growth=10`）、`script/summoned.gd`（`summon_level_changed` 信号、`add_summon_exp/set_summon_level`、`get_level_display_position`、`_setup_level_display`）、`script/summoned_health_component.gd:32-35`（顶部 `summoned_damage_interceptor`）、`script/extension_hooks.gd`（两槽）、`scenes/player/utaha/melee.gd:45-61`（改调 `body.add_summon_exp(1,&"utaha",player_ps.up_v)`，删 `summoned_group`）、`scenes/summoned/summon_level_display.tscn` + `script/summon_level_display.gd`、`scenes/manager/PoolManager.gd`（`summon_level_display:16`）、3 个召唤物场景的 `LevelDisplayAnchor`；mod `mods/etn_coop/net/coop_summoned_proxy.gd:219-237`（`_enable_melee_detect`）、`coop_net.gd:6329-6493`（闸门 + kb/upgrade/level-state RPC）。
- Notes / 说明: **等级=召唤物固有属性**：原 `utaha/melee.gd` 的 `summoned_group` 字典（挂在攻击者）迁到 `Summoned`（状态 + `add_summon_exp`），任何来源（utaha 近战 / 未来道具）喂同一经验池；配置在 `SummonedStats`，默认每级 +6，来源可传 `damage_add_override` 覆盖（utaha 被动升到 12 覆盖）。**镜像命中**：队友召唤物在本机是镜像且 `_disable_damage_nodes` 把 HurtBox 层/监测/形状全关 → 本机近战检测不到。改为「探测专用」（`layer=8192`+`monitorable`+`monitoring=false`+形状开）后，本机近战 HitBox 能收集到它；**关键**：这会让敌方爆炸/激光/盾/狙击（掩码都含 `summoned_box`）也命中镜像，而镜像 `max_hp<=0` 分支会 `emit_deal_damage_to_player` 误伤本机玩家——故 `SummonedHealthComponent.take_damage` **最顶部**加伤害闸门，镜像非友方近战一律丢弃。**转发**：镜像击退经 `summoned_damage_interceptor`、升级经 `summoned_upgrade_interceptor`，host 直发 / client 经 host 中继到 owner，owner 对真实召唤物 `apply_network_melee_knockback`/`add_summon_exp`；owner 的 `summon_level_changed` 反向广播 `apply_network_summon_level_state` 驱动各端镜像头顶显示。**显示**：复刻旧 UtahaPS 进度节点，走对象池，高度用场景锚点挂在 `%AnimatedSprite2D` 下随跳跃上下（缺失回退固定高度）。**通用教训**：① 「让镜像可被本地命中」必须同时恢复层 + `monitorable`，且用**顶部闸门**收口所有镜像伤害，否则 `max_hp<=0` 转发玩家的分支会反噬本机；② 召唤物数值/等级类跨端修改一律走「闸门转发 → owner 权威结算 → 回广播状态」，镜像端只显示；③ 固有属性化后新增来源（道具）无需再开网络通道。验证：`find_symbols` 全通过、headless 启动 + mod `entry ready`（含新钩子）零错误；带客户端双进程 LAN 实机待验。
- Source / 来源: code
- Date / 日期: 2026-10-08

### [Mod] 测试房球菜单的本地镜头/UI 信号被 host 无差别转播 → 只同步 black_frame 过场
- Evidence / 证据: `scenes/ball.gd:61`（`GameEvents.emit_camera_move(camera_marker, false)`）、`ui/test_menu.gd`/`ui/enemy_test_menu.gd`/`ui/character_test_menu.gd`（开关菜单时 `emit_camera_move(false)` + `emit_ui_visible`）；`mods/etn_coop/net/coop_net.gd`：`_host_cinematic_active`（新增）、`_on_local_camera_move`（新增 `if not black_frame: return`）、`_on_local_camera_reset`、`_on_local_ui_visible`（新增 `_host_cinematic_active` 门控）、`_release_boss_cinematic`（复位 flag）。Boss 侧恒为 `black_frame=true`：`scenes/enemies/boss/goliath.gd:133/148`、`scenes/enemies/boss/erosion_tower_group.gd:125/149`。
- Notes / 说明: **现象**（user）：联机测试房里任一玩家使用球（道具/角色/敌人测试菜单）打开菜单，其它玩家镜头被一并改动，不符预期。**根因**：`GameEvents.camera_move`/`ui_visible` 是全局信号，host 侧 `_on_local_camera_move`/`_on_local_ui_visible` 无条件 `rpc` 转播，本意只服务 Boss 黑幕过场；全代码唯一的非黑幕 `camera_move` 就是 `ball.gd`（`coop_start_ball.gd` 重写 `interact` 后已不发镜头，旧注释「如开始球」过时）。**修法**：host 侧只转播 `black_frame=true` 的过场镜头；用 `_host_cinematic_active`（black 镜头置 true、`camera_reset` 置 false、`_release_boss_cinematic` 兜底复位）把 `ui_visible` 也限定在过场期间；客机 UI 恢复由 `_release_boss_cinematic` 的 `emit_ui_visible(true)` 兜底，故过场结束时那条 `ui_visible(true)` 即使被跳过也无碍。**通用教训**：Boss 过场用的全局镜头/UI 信号与本地交互（球菜单）共用同一通道时，联机桥必须用「过场标志」区分，不能无条件转播。两份副本（`mods/etn_coop`、`mod_sdk/coop_mod/mods/etn_coop`）同步；`find_symbols` 通过。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 测试房本体重置会连带清远端镜像与 follow 图标 → 按 peer 记 item id 并在镜像重生时重建
- Evidence / 证据: `scenes/main/test_room.gd:71` `reset_clear_unit()`（清 `PlayerRoot` 下非 "Player" 组子节点，含远端镜像与挂在 PlayerRoot 的 follow 图标）；`mods/etn_coop/net/coop_net.gd`：`item_ids_by_peer`（新增）、`_remote_item_visual`（记录 id）、`_clear_peer_item_visuals`（erase id）、`_rebuild_peer_item_visuals`（新增）、`spawn_remote_player`（重生后调 rebuild）、`_reset_run_state`（清 id）。图标挂点见 `net/coop_item_visuals.gd:104-108`（follow 类挂 PlayerRoot，hat/rail/muzzle/internal 挂镜像）。
- Notes / 说明: **现象**（user）：测试房本机重置/换角色后，屏幕上其它玩家的道具视觉一并消失且不恢复。**根因**：`test_room_reset` 先触发本体 `reset_clear_unit`，把 PlayerRoot 下远端镜像与 follow 图标全部 `queue_free`（其余挂镜像随之释放）；随后 `_on_local_test_room_reset` 调 `_clear_item_visuals()` 清空 `item_visual_by_peer`（该表只登记远端 peer，本机道具不在此表），而 `_respawn_*`/`spawn_remote_player` 只补生镜像、不重建视觉。**修法**：新增 `item_ids_by_peer` 持久记录每个远端 peer 的道具 id（按接收序，供 follow 链复刻），镜像每次（重）生成时 `_rebuild_peer_item_visuals` 重建；`_clear_item_visuals` 保留但只清失效节点引用，`item_ids_by_peer` 不随本机重置清（仅换角色/断线清该 peer、`_reset_run_state` 全清）。**时机**：`test_room_reset` 回调中 coop 先于 `reset_data`，即时补生会被随后 `reset_clear_unit` 再清，真正生效的是 `_schedule_respawn_remotes` 的 0.3s/0.9s 重生（重建挂在该 spawn 路径）；本机重置带 `Transition` 左侧擦除过场，重生间隙被遮挡。**通用教训**：本体「整层清理」式重置会波及外挂在公共根节点（PlayerRoot/EquipLayer 等）的 mod 视觉，凡是可跨端复现的视觉都需独立记录来源数据并在宿主节点重生后重建。两份副本同步；`find_symbols` 通过。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 测试房重置清他人"场景内道具实体"：spawn 钩子重建不足 → 去无差别清空 + 与重生解耦的显式重建
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`：`_on_local_test_room_reset()` 原末尾 `_clear_item_visuals()`（清所有 peer 的 `item_visual_by_peer`，已删）；新增 `_rebuild_all_remote_item_visuals()`（`:3349`），调用点 `_on_local_test_room_reset()`（`call_deferred`）与 `_respawn_remotes_after()`（`:3688`，`_respawn_remote_players()` 之后）；`_rebuild_peer_item_visuals()`（`:3322`）保持不变。相关链：`upgrade_manager.gd:176`（道具 `player.add_child`）→ 异端 `_remote_item_visual` → `ItemVisuals.build_internal_visual`（`coop_item_visuals.gd:120`，挂远端镜像下）。
- Notes / 说明: **现象**（user，独立程序）：测试房本机重置/换角色后，其它玩家的"场景内道具实体"（`little_kei`/`kitchen_knife`/`cathedral_candle`/`spiked_shell` 等）消失且不恢复。**前一版修复不足**：只在 `spawn_remote_player()` 里挂重建，依赖"远端镜像真的被重建"。实测仍复现——`_on_local_test_room_reset()` 末尾的 `_clear_item_visuals()` 会**主动清掉其它 peer 已登记的视觉**（本机不持有这些节点），一旦镜像未被 `reset_clear_unit` 释放或补生提前 return（`spawn_remote_player` 的 valid 早退），重建就从不触发。**修法**：① 本机重置不再无差别清 `item_visual_by_peer`（`_clear_item_visuals` 仅留给 `_reset_player_sync`）；② 新增 `_rebuild_all_remote_item_visuals()`，遍历 `item_ids_by_peer` 的非本机 peer 逐个重建（幂等：先清该 peer 旧引用再按记录 id 重建 follow/hat/rail/muzzle/internal），在重置时 `call_deferred` 一次、并在 `_respawn_remotes_after` 补生后各兜一次——**不依赖镜像是否被释放/重建**。**通用教训**：跨端 mod 视觉的"清理-重建"不要耦合"宿主节点是否会重生"这一不确定路径；重置时只应清自己，他人视觉必须按独立记录的来源数据显式重建。**SUPERSEDED: 2026-10-08 本文件上一条 [Mod] 测试房本体重置会连带清远端镜像与 follow 图标 的"spawn 钩子重建"方案不足，以本条为准。** 两份副本同步；`find_symbols` 通过；`build_coop_mod.ps1 -Install` 已覆盖 `%APPDATA%\...\mods\etn_coop`（pck SHA256 一致）。待双端实机验收。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 测试房重置清他人召唤/持久身体镜像：reset_clear_unit 连带清远端镜像 → 记录 net_id 变换+等级并重建
- Evidence / 证据: `scenes/main/test_room.gd:71` `reset_clear_unit()`（清 PlayerRoot 非"Player"子节点、EquipLayer、SELayer、Summoned 组等）；`mods/etn_coop/net/coop_net.gd`：新增 `summoned_last_transform_by_net_id`/`summoned_last_level_state_by_net_id`（`:668-669`）、`_rebuild_remote_summons()`（`:3371`）；写入点 `_register_local_summoned`(`:2785`)/`_spawn_summoned_local`(`:6329`)/`_summoned_state_remote`(`:6388`)/`_remote_summoned_level_state`(`:6587`)；清理点 `_despawn_summoned_local`/`_despawn_peer_summons`/`_reset_player_sync`；调用点 `_respawn_remotes_after`（`:3725`）在 `_respawn_remote_players()` 之后。镜像挂点见 `_summoned_root`（`:6291`，无人机挂 EquipLayer，其余 PlayerRoot）。
- Notes / 说明: **现象**（user，独立程序，类别=b 独立实体/召唤物）：测试房本机重置/换角色后，其它玩家的召唤/持久身体镜像（炮塔/无人机/吸尘器/黑雾镰刀等，含 `PERSISTENT_BODY_SCENES`）消失且不恢复（本机自己的随换角色正确清除）。**根因**：本体 `reset_clear_unit` 直接 `queue_free` 这些挂在 PlayerRoot/EquipLayer 的镜像；`_on_local_test_room_reset` 只 `_despawn_owned_summons_local()`（仅清本机拥有的），**不重建远端拥有的镜像**，且 `reset_clear_unit` 绕过 `_despawn_summoned_local`（net_id→scene/owner 元数据仍在）。**修法**：按 net_id 持续记录最近变换（`_spawn_summoned_local`/`_summoned_state_remote`/`_register_local_summoned`）与等级显示状态（`_remote_summoned_level_state` 先记再应用）；新增 `_rebuild_remote_summons()`，跳过本机拥有者，对失效镜像 `erase` 后按记录的 `scene_path`+变换 `_spawn_summoned_local` 重建，并在 `_spawn_summoned_local` 内补回已记录的等级状态；在 `_respawn_remotes_after`（0.3s/0.9s）调用。位置随后由 owner 的 `send_summoned_state`(~30Hz) 自校正。**通用教训**：测试房"整层清理"重置对"挂在公共根节点（PlayerRoot/EquipLayer/SELayer）的跨端镜像"是破坏性的；这类镜像必须能按独立元数据（net_id→scene/owner/变换/等级）在重置后重建，且"本机拥有"与"远端拥有"要区分处理。**SUPERSEDED 关联**：本文件上一条 [Mod] 测试房重置清他人"场景内道具实体" 只覆盖 `item_visual_by_peer`（挂在玩家身上的道具视觉），不覆盖本条 summon/持久身体镜像；两者互补，均保留。两份副本同步；`find_symbols` 通过；`build_coop_mod.ps1 -Install` 已覆盖（pck SHA256 一致）。待双端实机验收。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 玩家特殊近战同步：mod 自动挂本地 Kick/AnimationPlayer.animation_started（无需改本体）
- Evidence / 证据: 基础近战 `script/kick.gd:24` 调 `ExtensionHooks.on_player_melee`（共用 `script/kick.tscn`，无 AnimationPlayer）；特殊近战动画在 `Kick/AnimationPlayer` 上播（`scenes/player/hoshino/melee.gd` `melee_anim_play`、`scenes/player/utaha/melee.gd`、`scenes/player/chinatsu/chinatsu_melee.gd`、`scenes/player/kasumi/kasumi_melee.gd` 的 `$AnimationPlayer`）。mod `mods/etn_coop/net/coop_net.gd`：`_sync_local_melee_hook`（`:3022`，`_physics_process` 每帧幂等连接本地玩家 `kick.get_node_or_null("AnimationPlayer").animation_started`）、`_on_local_melee_anim_started`（`:3048`）、`_capture_local_melee_anim`（`:3054`，kick 按下时读 `current_animation` 兜底）、`_broadcast_local_melee_anim`（`:3007`，过滤 `RESET`、80ms 去重、走 `_server_player_melee`/`_remote_player_melee`）、`_remote_player_melee`（`:3081`，优先镜像 `kick/AnimationPlayer.has_animation` 播放 + `kick/GPUParticles2D.restart()`，否则回退 `player.kick_anim`）。
- Notes / 说明: 需求：特殊近战（hoshino 连段 normal_melee/melee_1..3、utaha/chinatsu/kasumi 的 melee_anim）在镜像端回放。**通用做法**：本体基础近战已通过 `on_player_melee` 广播；特殊近战本体无任何钩子，但动画统一在 `Kick` 的 `AnimationPlayer` 上播、且基础 `kick.tscn` 无 AnimationPlayer，故 mod 可**只挂本地玩家 Kick 的 `animation_started`** 自动探测（不需改本体、新角色零调整）。要点：① 仅挂本地玩家（镜像不挂，避免回环）；② 过滤 `RESET`（hoshino 收招 play RESET）；③ `animation_started` 对"同一动画重播"是否触发因版本而异，补一路"按下 kick 时读 `current_animation`"兜底 + 80ms 去重；④ 回放优先镜像 Kick 自带 AnimationPlayer（含该 anim 才播），基础近战回退 `kick_anim`；⑤ 同时 `restart` 镜像 `Kick/GPUParticles2D`；⑥ 接受方法轨道副作用（hoshino `melee_shake` 会让队友镜头抖、音效轨道出声，user 已确认接受）。**未做**：位移/无敌/召唤物升级/伤害（各有权威链或由位置快照跟随）；ako/tsurugi（非动画型）留下一轮。两份副本同步、`find_symbols` 通过、`build_coop_mod.ps1 -Install` 已覆盖（pck SHA256 一致）。待双端实机验收。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] Ako 链 锁+拖+绳索视觉同步：客机拖动需 host 权威冻结/夹取 + 绳索确定性视觉
- Evidence / 证据: 本体 `scenes/player/ako/ako_chain.gd`（`lock_enemy` 冻结 + `_process_locked` 每帧夹到 `max_range` 拖动 + 周期策反；新增 `ako_index`、`throw_chain/lock_enemy/release_enemy` 调 `player.broadcast_character_event("ako_chain_*")`；`_process_locked` 夹取加 `coop_ako_host_drives` meta 守卫）、`scenes/player/ako/ako_chain_controller.gd:add_chain`（`chain.ako_index = chains.size()`）。mod `mods/etn_coop/net/coop_net.gd`：`_on_character_event` 识别 `ako_chain_*`→`_handle_local_ako_chain`（`:2423`）、`_server_ako_event`（`:2458`）、`_remote_ako_event`（`:2485`）、`_apply_ako_lock/_apply_ako_unlock`（`:2511/:2523`）、`_tick_ako_locks`（`:2531`，host 每帧锚点夹取+BOSS/超时兜底）、`_ensure_ako_chain_visual`（`:2569`）、`_tick_ako_chain_visuals`（`:2603`，THROWING/LOCKED/RETURNING + 驱动 `rope.pin_point/target_pos`）、`_release_local_ako_locks`（`:2672`）、`_reset_ako_state`（`:2687`）。
- Notes / 说明: 需求：Ako 甩链锁敌+拖动在其它端可见，**房主与客机都要能拖**，保留策反，要有绳索视觉。**权威模型**：敌人 host 权威 → 锁定/拖动必须 host 执行；客机链命中镜像敌人后报 host `net_id`，host `frozen=true`（已策反则 false）并按锚点 `= owner.sprite_2d.global_position`（`root_offset` 默认 ZERO）夹到 `max_range`（默认 120）；BOSS 超距 / owner 断线 / 看门狗 → 释放。策反沿用 `enemy_conversion_interceptor`。**抖动规避**：客机锁定时给链设 `coop_ako_host_drives` meta，本体跳过本地夹取（user 同意此耦合）。**绳索视觉**：owner 广播 throw/lock/release；其它端在 owner 镜像下实例化 `ako_chain.tscn`（根 `set_script(null)`、禁 HitBox），用确定性状态机（抛 500/收 600 速度、120 上限）驱动 `Rope.pin_point/target_pos`；owner 本机走真实链、不重复渲染。**通用教训**：跨端"持续牵引敌人位置"类技能必须把位置权威收敛到 host，并让本地端停手，否则客机本地夹取会被快照回滚、产生抖动/争用。清理：`_cleanup_peer`（host 解冻+广播）、`_reset_player_sync`、`_on_local_test_room_reset`（`_release_local_ako_locks`，防链随换角色被释放而 host 侧永久冻结）。两份副本同步、`find_symbols`（3 脚本）通过、`build_coop_mod.ps1 -Install`（pck SHA256 一致）。待双端实机验收。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

- UPDATE 2026-10-08: 补 `_ako_force_release_owner`/`_remote_ako_force_release`（`coop_net.gd`）——host 因 BOSS/超距/看门狗/敌人失效强制释放时，回通知 owner 本机链 `release_enemy()`，避免客机链一直显示锁定到自身超时。
- UPDATE 2026-10-25: 上述 host 夹取只对带 `frozen` 的本体敌人成立；侵蚀之塔这类「聚合实体根」（Node2D，无 `frozen`）现在会被拒绝并收回链，不再把整组 Boss 拖走（见下方「[Coop] Ako 链锁到塔组根…」）。

### [Mod] tsurugi 第二枪后坐同步：开火事件带枪节点路径 + 镜像第二枪一并禁用
- Evidence / 证据: 本体 `scenes/player/tsurugi/second_shoot.gd`（按住 kick → `second_gun.is_shoot=true`；第二枪=`Kick/blood_n_gunpowder`=PlayerGun，主枪=`GraphicsGun/Gun`）；`script/player_gun.gd:_shoot()` → `GameEvents.emit_player_gun_shoot(self)`；子弹走 `ProjectileSpawner.spawn_core`→`on_projectile_spawned`（已同步），枪口走 `on_visual_activated`（已同步）。mod `coop_net.gd`：`_on_local_gun_shoot`（`:7513`，改带 `p.get_path_to(gun)`）、`_server_player_gun_shoot`（`:7530`）、`_remote_player_gun_shoot`（`:7547`，按路径解析镜像枪 `_shootAnim`，失败回退主枪）；`coop_player_proxy.gd:setup`（`second_gun` 同主枪关 physics/process + 锁 `is_shoot=false`）。`coop_player_proxy._apply_weapon_look` 已对 `second_gun.look_at`。
- Notes / 说明: 需求：tsurugi 特殊近战（第二枪连续射击）在其它端正确表现。**原有缺陷**：`player_gun_shoot(gun)` 虽带枪节点，但 mod `_on_local_gun_shoot` **忽略参数**、`_remote_player_gun_shoot` 一律重放**主枪**后坐 → 第二枪开火时其它端看到主枪动画、第二枪不播 fire。**修法**：开火广播随带 `p.get_path_to(gun)`（限长 ≤64、禁 `..`），镜像端 `get_node_or_null(path)` 解析对应枪调 `_shootAnim`，失败回退主枪——对主枪/第二枪/未来任意 PlayerGun 通用。**镜像安全**：第二枪此前只靠 `is_shoot=false`；现与主枪一并 `set_physics_process/process(false)` 且锁 `is_shoot=false`，**不会本地开火/生成本地子弹**；其开火仅由 `_remote_player_gun_shoot` 直调 `_shootAnim` 回放，瞄准由代理 `_apply_weapon_look` 负责。**通用教训**：多枪角色的"开火表现"广播必须带"是哪把枪"（相对路径最通用），否则会统一打在主枪上。纯 mod 改动，无需重导出。两份副本同步、`find_symbols` 通过、`build_coop_mod.ps1 -Install`（pck SHA256 一致）。待双端实机验收。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 测试房重置重建召唤镜像"歪 90°"：视觉旋转 ≠ 本体旋转，重建必须分开
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`：`_summoned_state_remote`（`:6813`）原把状态流的 `rotation` 写进 `summoned_last_transform_by_net_id[net_id]["r"]`；`_rebuild_remote_summons`（`:3784`）原把该值当 `global_rotation` 传给 `_spawn_summoned_local`。视觉旋转来源：`script/turret_summoned.gd:84`（返回 `v`）、`scenes/update_item/shiroko_drone_icon_2.gd:73`、`scenes/update_item/robotic_vacuum_cleaner_body.gd:63`、`script/summoned_follower.gd:176`（枪口角）；应用走 `apply_network_visual_rotation`（只转子节点/sprite，不动本体）。`_spawn_summoned_local`（`:6754`）/`_register_local_summoned`（`:3126`）写的 `"r"` 是本体 `global_rotation`（这些类型恒为 0）。
- Notes / 说明: **现象**（user）：测试房重置后不再清别人的炮塔/无人机（上轮修复生效），但**整体歪约 90°**。**根因**：召唤物有"视觉旋转"（瞄准/子 sprite 朝向，`get_network_visual_rotation`）与"本体旋转"（`global_rotation`）两套语义；`_summoned_state_remote` 把**视觉旋转**覆盖到 `"r"`，重建时又把它当本体旋转 `global_rotation = 视觉角`，且无人复位本体旋转 → 永久歪。**修法**：`_summoned_state_remote` 改为合并写入独立键 `"vr"`（保留 `"r"`=本体旋转）；`_rebuild_remote_summons` 本体用 `"r"` 出生、视觉用 `"vr"` 经 `apply_network_visual_rotation` 应用。**通用教训**：跨端重建/同步"朝向"必须区分"本体变换"与"仅视觉朝向"；把只读的视觉朝向误写进本体变换会累积成固定偏移（普通出生路径因传的是本体 `global_rotation` 才没暴露）。纯 mod 改动，`-Install` 即可。两份副本同步、`find_symbols` 通过、pck SHA256 一致。待实机验收。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Player] utaha 近战对召唤物：升级与击退必须同一目标（最近者）
- Evidence / 证据: `scenes/player/utaha/melee.gd`：`add_damage_data()`（命中帧由 `melee_anim` method track 调用，`utaha.tscn:437`）原对 `sort_group` 内**每个**召唤物 `hit_received.emit`，走 `SummonedHealthComponent.take_damage` 友军近战分支 `_apply_knockback`（`script/summoned_health_component.gd:42-49`）→ 全部击退；而 `upgrade_summoned()` 只对 `sort_group[0]` 喂经验（`:45-61`）。改为只对 `sort_group[0]` 发 `hit_received`。另删除未被连接的 `_on_area_2d_body_entered`/`_on_area_2d_body_exited`（`utaha.tscn:1056-1057` 的 `body_entered/exited` 连的是 `UtahaPS`，非 `Kick`）。
- Notes / 说明: 需求（user）：utaha 近战面对召唤物时，**只有被升级的那个（最近者）被击退**。原实现"升级最近一个、击退全部"。修后二者严格同取 `sort_group[0]`。联机侧无需改：mod 按每次 `hit_received` 转发（`_gate_summoned_damage`），基座只发一次即只转发一个。**通用教训**：同一挥击里"选取目标"（升级/增益）与"结算效果"（击退/伤害）必须共用同一目标选择，否则会造成"部分命中"的意外。纯本体改动，独立程序需重导出。`find_symbols` 通过。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] MOD 管理面板行描述 tooltip：整行命中 + CanvasLayer 无缩放可直接比坐标
- Evidence / 证据: `script/mod_option.gd`（`_process` 悬停、`_row_at`、`_show_tooltip`、`_toggle_touch_tooltip`、`_on_list_scroll_gui_input`）、`ui/mod_option.tscn`（`Tooltip` 节点 `z_index=20`）、`script/mod_manager.gd:list_mods()`（返回 `description`）；对照 `ui/player_card.gd:59-89`（`_touch_mode` 门控 `_process` 轮询 `get_global_mouse_position()` + `get_global_rect()`）与 `ui/enemy_test_menu.gd:22-29`（`gui_input` 空白区收起 + `get_global_transform_with_canvas() * event.position`）。
- Notes / 说明: 需求（user）：MOD 行悬停显示跟随鼠标的描述框（名字+版本+作者+描述）、触屏点按显示/再点或点空白隐藏/拖动隐藏。**复用模式**：① 鼠标悬停用 `_process` 每帧 `get_global_mouse_position()` + 整行 `get_global_rect().has_point()` 轮询（比 `mouse_entered/exited` 稳，且覆盖行内开关等子控件），并用 `_touch_mode`（`_input` 里 `InputEventScreenTouch` 置真、真实 `InputEventMouse`（`device != DEVICE_ID_EMULATION`）置假）在触屏时关闭轮询；② 触屏点按切换、点列表空白/拖动隐藏。**坐标要点**：MOD 面板挂在 `CanvasLayer` 下且无缩放，`get_global_mouse_position()` 与 `get_global_rect()` 同系可直接比较；列表空白处用 `list_scroll.get_global_transform_with_canvas() * event.position` 把 `gui_input` 本地坐标换算到画布（同 `enemy_test_menu`）。tooltip 节点是场景静态节点（便于可视化编辑），描述为空时隐藏描述行、不加新本地化键。`game_eval` 实测：悬停跟随、触摸点按切换、`_row_at` 整行命中、长描述自动换行均正常。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08
- SUPERSEDED: 2026-10-18 管理页改为右侧常驻详情，tooltip 节点、`_process` 轮询与触屏点按显隐逻辑已移除；描述改由详情页 Label 常驻显示。（来源：code）

### [Mod] MOD 描述本地化用「中文原句作翻译键」+ PowerShell 读 mod.json 必须 UTF-8
- Evidence / 证据: `mods/etn_coop/mod.json`、`mod_sdk/coop_mod/mods/etn_coop/mod.json`（`author` / `description`）；`mods/etn_coop/i18n/coop_i18n.gd` 与打包源同名文件（`MESSAGES` 新增「中文原句」为键 + en，`install()` 对缺失语言回落 en）；`mod_sdk/build_coop_mod.ps1`（原 `Get-Content -Raw | ConvertFrom-Json` 改为 `[System.IO.File]::ReadAllText(path, UTF8) | ConvertFrom-Json`）。
- Notes / 说明: ① 本体 MOD 面板 tooltip 的 `TipDesc` 是**默认自动翻译的 Label**，故 mod.json `description` 可直接填中文原句（它同时作为翻译键），mod 侧在 `coop_i18n.gd` 以该原句为 key 提供 en 即可中英切换。相比用语义键（如 `coop_description`）：这样在 mod 未挂载/未启用、i18n 未注册时仍显示可读中文，而非露出原始键。未给 pt/vi 时 `install()` 自动回落 en。② **坑**：`mod.json` 一旦含中文，`build_coop_mod.ps1` 原用 `Get-Content -Raw | ConvertFrom-Json` 在 PowerShell 5.1 下按 ANSI(GBK) 读取 → JSON 解析失败、`$version` 变空（漏生成版本化 zip）并刷 `ConvertFrom-Json` 报错；改 `ReadAllText(..., UTF8)` 后正常。**通用规则：脚本/工具读取可能含非 ASCII 的 UTF-8 文件必须显式指定 UTF-8。**
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08
- SUPERSEDED: 2026-10-18 `description` 现由 MOD 管理页右侧详情常驻展示；自动翻译规则与中文原句作 key 的用法不变。（来源：code）

### [Buff] buff 场景→组件重构丢失 `player_buff_success` 广播：tsurugi PS[1] 濒死复活加成失效
- Evidence / 证据: 旧 `scenes/player_buff/last_stand_buff.gd:clear_buff()` 调 `GameEvents.emit_player_buff_success(self)`；新组件 `resources/buff/components/last_stand_component.gd` 成功路径 `check_player_hp()`→`_remove_self()`→`deactivate()` 未再发。`GameEvents.emit_player_buff_success` 定义于 `script/GameEvents.gd`，全仓仅 `scenes/player/tsurugi/tsurugi_ps.gd:35` 订阅（`add_player_ability`）。修法：组件在 `deactivate()` 非超时分支 `manager.buff_success.emit(resource)`，`scenes/manager/player_buff_manager.gd:_relay_buff_success` 转发到 `GameEvents.player_buff_success(buff: Buff)`；payload 由 Node 改为 Buff（无其它订阅者/mod 引用）。
- Notes / 说明: **同类孤儿信号**：同次重构还遗留 `GameEvents.enemy_hit_position`（`emit_enemy_hit_position` 从未被调用，唯一订阅者 `scenes/update_item/test_ammo.gd:5`；`test_ammo` 无任何 item/shop 引用，已删除信号+场景）。**通用教训**：信号从"场景脚本"迁移到"资源 + 组件"时，旧场景里 emit 的全局事件必须逐个迁移；审计法=对每个 `GameEvents` 信号交叉检查 `emit_*` 调用与 `.connect`，"有订阅、无发射"即回归。另：编辑器 `@tool` 测试上下文**没有 autoload 实例**，组件内对 `GameEvents`/`PlayerData` 的访问需 `!= null` 短路守卫，`tests/` 才能覆盖该路径（`test_last_stand_success.gd`）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

### [Mod] player_laser_beam 远端不跟随/不追踪：一次性特效通道不足，需按 effect_id 建持续光束状态通道
- Evidence / 证据: `scenes/bullet/player_laser_beam.gd`（无 `velocity`；`follow()` `:99`；新增 `network_get_beam_state`/`network_apply_beam_state`、`_physics_process` 远端插值）；`scenes/weapon/Supernova_Abi_Eshuhs_Sword_of_Light/charge_laser_gun.gd:120-124`（`active_state`→`notify_local` 早于 `:155-158` 的 `follow`）；`mods/etn_coop/net/coop_net.gd`（`_on_projectile_spawned` 无 velocity → 一次性特效通道；新增 `_follow_nodes`/`_flush_follow_states`/`_sanitize_follow_entry`/`_server_effect_follow_batch`/`_remote_effect_follow_batch`/`_apply_remote_follow`）、`mods/etn_coop/net/coop_visual_sync.gd`（`get_effect`）；`scenes/update_item/homing_bullet.gd:32-46`（仅本地设 `point_targets`）。
- Notes / 说明: **现象**（user）：联机远端 `player_laser_beam` 不跟随玩家、停在**上一发**位置；拾取追踪弹后远端仍射直线。**根因**：光束无 `velocity` → 走一次性特效通道，只在激活瞬间发一次坐标，无持续更新；且广播时机在 `follow()` 之前 → 读到复用实例上一发的 `global_position`；追踪目标 `point_targets` 只在拥有者本地由 `homing_bullet` 设置、未入网 → 远端恒走直线路径。**修法**：本体加 `network_get_beam_state()`（枪口 + `_angles` + 各段锁定敌人 `net_id`）/`network_apply_beam_state(p, angles)`；mod 以 `net_effect_id` 为键登记本地光束，每 0.05s unreliable 广播状态（client→host 消毒/限流后转发并本地套用；host 直接广播），接收端 `get_effect(eid)` 取回克隆、套角度并用 `enemy_by_net_id` 反查 `net_id` 写 `set_point_target`；远端位置在 `_physics_process` 指数插值向目标点（`active_state` 重置 `_net_remote_driven`）。**通用教训**：任何「每帧由本体驱动的持续视觉」（无 velocity 的光束/发射器）都不能走一次性特效通道，须按其 `net_effect_id` 建持续状态通道，且状态要能被远端**完整重建**（位置 + 角度 + 目标引用按 net_id）；本体无 helper 时 mod 用 `has_method` 跳过（向后兼容）。两份副本同步、`MOD_VERSION` 0.1.2→0.1.3。待双端实机验收。
- Source / 来源: user + code
- Date / 日期: 2026-10-08

### [Mod] 持续视觉状态通道泛化：murky_hand_scythe 回程飞向接收端本机玩家
- Evidence / 证据: `scenes/update_item/murky_hand_scythe.gd:50/78`（每次激活走 `on_visual_activated`）；`scenes/update_item/murky_hand_scythe_icon.gd:32`（`_ready` 抓本机 `Player`）、`:65-68`（回程 `dir_v = (player.global_position - ...)` 归位）；mod `coop_net.gd`（`_on_visual_activated` 登记 `_follow_nodes`、`_flush_follow_states` 分流 `network_get_visual_state`、`_sanitize_follow_entry` 支持 `r/sc`、`_apply_remote_follow` 走 `network_apply_visual_state`）。
- Notes / 说明: **现象**（user 追问「其它同类问题」）：`murky_hand_scythe` 远端飞出/环绕段正常，回程段却飞向**接收端自己的玩家**，到不了拥有者身边就隐藏。**根因**：与 `player_laser_beam` 同源——无 `velocity` 走一次性视觉通道，克隆后按**本机**外部驱动（`player` 引用）继续跑，未同步拥有者轨迹。**修法**：把已建的持续状态通道泛化为通用形态（`network_get_visual_state`/`network_apply_visual_state(p,r,sc)`），`_on_visual_activated` 也登记实现该方法的节点；镜像 `_net_remote_driven` 时 `_physics_process` 只把位置/朝向/缩放插值到网络目标并保留 `sprite_2d` 自旋、跳过本地归位；采集端跳过 `is_idle==1`（视觉通道节点 idle 不回收 `net_effect_id`）。**判据**：自驱型（`laser_launcher` 自行计时旋转）本就无需通道；外部驱动型（跟随/追踪/归位 owner）必须持续同步。**排错法**：审「无 velocity 但被本体每帧驱动」的持续视觉，凡克隆端自己按本机 `Player`/状态机跑的都属此类。两份副本同步。待双端实机验收。
- Source / 来源: user + code
- Date / 日期: 2026-10-08
- SUPERSEDED: 2026-10-24 「采集端跳过 `is_idle==1`」已被「idle 显式通知远端 + 克隆按 eid 复用」替代，见下方《远端镰刀回收后不消失/越打越多》。（来源：code + test）

### [Mod] 远端镰刀回收后不消失/越打越多：spawn 必须按 effect_id 复用克隆，idle 必须显式通知远端
- Evidence / 证据: `scenes/update_item/murky_hand_scythe.gd:49/77`（每次激活 `on_visual_activated`，`net_effect_id` 不变）；`mods/etn_coop/net/coop_net.gd:3853-3885`（同节点重播 spawn）、`:6795-6802`（旧：`is_idle==1` 直接跳过）、`:6911-6936`（follow 套用）；`mods/etn_coop/net/coop_visual_sync.gd:186`（旧：先取共享池任意空闲节点）、`:198-206`（旧克隆映射被覆盖后既不隐藏也不释放）、`:255-273`（池上限 24 才回收）；`scenes/update_item/murky_hand_scythe_icon.gd:70-81`（`_net_remote_driven` 分支跳过本地归位）。复现：HEAD 旧 PCK 双进程 LAN，3 轮 idle/shoot 远端克隆 `count=2→3→4` 且旧克隆保持可见。
- Notes / 说明: **现象**（user）：联机时远端视角的镰刀回收到拥有者身边后不消失，反复射击后场面残留多把。**根因**：池化道具特效节点由本体复用、`net_effect_id` 不变，但接收端 spawn 不按 eid 复用克隆；同时拥有者 idle 时 follow 通道直接 `continue`，远端克隆因 `_net_remote_driven` 跳过本地归位而永不自行隐藏 → 每轮激活新增一个可见克隆，旧克隆被覆盖映射后无人回收。**修法**：① `CoopVisualSync.spawn_visual_effect` 同 eid 优先复用 `_by_effect_id` 中的同一节点（失效/待删先剔除），`_acquire_effect` 跳过被其它 eid 占用的节点；② 新增 `idle_effect(eid)`：`idle_state()` 隐藏但保留映射、不写 `_ended_effect`（该 eid 之后还要复用）；③ `_flush_follow_states` 对 `network_get_visual_state` 的 idle 节点按 `FOLLOW_IDLE_RESYNC_MSEC=500` 节流发 `{eid,h}`（unreliable，转入 idle 立即发、重发自愈），`_sanitize_follow_entry` 在坐标校验前分流 `h`，`_apply_remote_follow` 收到 `h` 调 `idle_effect`；④ 本体 `network_apply_visual_state` 收到活跃状态时若处于 idle 则恢复 `is_idle=0`/`visible=true` 并吸附到目标（不重跑 `active_state()`，避免重启飞/环绕计时）。**通用教训**：① 稳定 `effect_id` 的持续视觉，接收端必须按 id 复用节点，「共享池取空闲」只适用于一次性/无稳定 id 的特效；② 空闲通知要区分「暂时隐藏（保留映射、可复用）」与「终态 despawn（写 ended、不可复活）」，混用会让 id 永久失效或克隆永久残留；③ 以 unreliable 传可见性状态必须配节流重发 + 活跃状态自愈，否则迟到的隐藏包会把克隆永久隐藏。协议 v5→v6（follow 载荷新增 `h`），`MOD_VERSION` 0.1.12→0.1.13；两份 mod 副本同步。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-24

### [Mod] 联机延迟基线：中继链路/服务器是主因，mod 侧为固定插值滞后与 WS 可靠化
- Evidence / 证据: 同机两 headless peer 实测（`--coop-host`/`--coop-relay-host`）+ `sim-report`：LAN RTT ~4–10ms；默认中继 `mc.yqst.top:32085` RTT ~115ms；对服务器基础 TCP 握手 RTT ~27–61ms（中位 31）。代码：`mods/etn_coop/net/coop_snapshot_buffer.gd:compute_delay`（floor `snapshot_interval*2`、clamp `[0.05,0.20]`）、`coop_relay_peer.gd:_put_packet_script`（`_ws.send` 可靠有序）、`:212-224`（收到一律标 reliable）、`coop_net.gd`（`unreliable_ordered` 玩家/敌人状态 `:4440/4460/5520`）、`coop_sim_regression.ps1`。
- Notes / 说明: **结论**：中继高延迟**主要来自链路/服务器**（星型转发 + 物理往返；同机两 peer 也 ~115ms ≈ 2×基础 RTT + ~50ms 服务器/WS 转发开销），mod 自身处理在 LAN 回环仅 ~4–10ms。**mod 侧次要因素**：① 插值 floor `2×interval` 造成 LAN 也有 ~132ms（敌人）/100ms（玩家）固定滞后；② 中继把所有 `unreliable*` 通道塞进单条可靠有序 WebSocket → 丢包/拥塞时队头阻塞（本次 loss=0 未触发，WiFi/移动网会放大）。**已做（本次）**：`compute_delay` floor 2.0→1.35、`DELAY_MIN` 0.05→0.033、`observed` 封顶 `2.2×interval` 再乘 1.2、jitter 2.0→1.5（固定滞后降到 ~89/68ms）；`_put_packet_script` 检查 `send()` 失败并计数 + F4 `send_fail` 诊断；sim-report 增 `delay=%.0f`。**未做（服务端线）**：中继改 UDP/ENet 或 WebTransport 才能真正低延迟不可靠；就近部署 / `TCP_NODELAY`。**测量注意**：`--coop-*` dev 入口在 `_handle_dev_args` 末尾（`coop_entry.gd:893-912`）会 `close_connection` + `quit`（约 11s），做持续测量需加 `--coop-devquit` 保持连接。**18% extrap 多为良性**：静止敌人 600ms 心跳 + 120ms 外推窗口 ≈ 18%，非真卡。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod] UPnP `discover()` 阻塞可达 ~8s，必须后台线程且 `unmap()` 不可 join
- Evidence / 证据: 实测 `UPNP.new().discover(2000, 2)` 在无 UPnP 网关的机器上阻塞 **8006ms**（`err=27 ERR_TIMEOUT`），与 timeout(2000) 不严格对应；`mod_sdk/coop_mod/mods/etn_coop/net/coop_upnp.gd`（`map` 起线程、`_finish` 主线程回报、`unmap` 只置 `_release_pending`）；`coop_net.gd`（`host_game` 按 `settings.upnp_enabled` 调 `map(_lan_port)`、`close_connection` 调 `unmap`）。
- Notes / 说明: **坑**：① 在 Godot 4.7 `UPNP.discover()` 同步阻塞时间受本机 SSDP/网络环境影响，可能远超传入的 timeout（本机实测 8s）；放主线程会卡死开房。② `unmap()` 若 `wait_to_finish()` 会**冻结主线程最多 ~8s**，故改为不阻塞：线程运行中只置 `_release_pending`，等线程结束后的 `_finish` 在后台 `delete_port_mapping`；线程已结束则立即删。③ 同一时刻只允许一个映射线程（运行中 `map` 回 `busy`），避免线程引用互相覆盖/泄漏。④ `--check-only --script` 会因 autoload（`GameEvents`/`ExtensionHooks`）未注册而误报 `Identifier not found`，不是真错误；判脚本正确请用 `--headless --editor --quit` 或实际运行。
- Source / 来源: test + code
- Date / 日期: 2026-10-09

### [Mod] coop 覆盖层 `_set_buttons_enabled` 白名单：后代统一 IGNORE，新控件漏登记即点不动
- Evidence / 证据: `mods/etn_coop/ui/coop_menu.gd`（`_build_interactive_controls()` / `_set_buttons_enabled()`、`on_coop_selected():352` 调 `_set_buttons_enabled(true)`）；复现控件 `%UpnpToggle`/`%PortInput`/`%LanAddrToggle`/`%PublicAddrToggle`。
- Notes / 说明: 打开覆盖层时 `_set_buttons_enabled(true)` 先 `_panel.find_children("*","Control",true,false)` 把**所有后代**设 `MOUSE_FILTER_IGNORE`，再只把登记名单内的控件恢复 `MOUSE_FILTER_STOP`。因此**新增可交互控件（按钮/开关/输入框）必须加入 `_build_interactive_controls()`**，否则表现为「悬停无反应、点不动」（UPnP 开关、端口输入框曾如此；debug HUD 开关是早期同样问题补登记后才可用）。`--coop-devmenu` 已加断言（打印 `upnp/port/lan/pub` 的 `mouse_filter==STOP`）。房间标识（`ui/coop_room_label.gd`）不经过该名单，另设 `MOUSE_FILTER_STOP` + `gui_input`。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 弹 toast 勿在场景切换期 add_child：会触发 tree_changed 提前唤醒 change_scene 的 await
- Evidence / 证据: `script/GameEvents.gd:202`（`change_scene`：`tree.change_scene_to_file(path)` → `await tree.tree_changed` → `get_first_node_in_group("PlayerRoot").call_deferred(...)`）；`mods/etn_coop/net/coop_net.gd`（`show_coop_toast` 曾每次 `host_parent.add_child(layer)`）；复现：`--coop-host --coop-devbattle` 中 UPNP 失败 toast 与进关同帧，报 `Cannot call method 'call_deferred' on a null value`（`PlayerRoot` 未就绪）。
- Notes / 说明: `SceneTree.tree_changed` 是**任何**节点增删都会发；`change_scene` 用它等待换场景，但战斗中任何 `add_child`（如弹 toast）若恰好先于换场景的 tree_changed 发生，就会提前唤醒 await，此时新场景尚未就绪 → `get_first_node_in_group("PlayerRoot")` 为 null。**修法（mod 侧）**：toast 常驻化——在 `CoopNet._ready` 建一次 `CanvasLayer`+`mobile_notice`，之后只调 `notice(key)`（不增删节点）。通用原则：mod 在联机流程中**避免在场景切换窗口内增删节点**；确需弹窗/生成 UI 时优先常驻节点复用。
- Source / 来源: test + code
- Date / 日期: 2026-10-09

### [Mod] 多网卡选本机局域网 IP：用 get_local_interfaces + 名称/网段启发式
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`（`get_local_lan_ip`/`get_local_lan_ip_summary`/`_lan_ip_score`/`VIRTUAL_IFACE_KEYWORDS`）；本机 `Get-NetIPAddress`：真实 `192.168.31.220`、SSTAP `10.198.75.60`、虚拟 `172.19.83.237`。修复后房间标识/复制为 `192.168.31.220`。
- Notes / 说明: `IP.get_local_addresses()` 顺序不定，多网卡（尤其 SSTAP/VPN/虚拟机 TUN）时常先返回虚拟网卡地址，导致「局域网 IP」显示错误、同网段客机连不上。Godot **无默认网关 API**，故用启发式：`IP.get_local_interfaces()` 逐接口，`name`/`friendly` 含 `sstap/tap/tun/vpn/vmware/virtualbox/hyper-v/vethernet/wsl/docker/...` 则大幅降权；网段优先 `192.168.*` > `172.16-31.*`/其它 > `10.*`（SSTAP 常用 10.x）。极端情况（真实也是 10.x 且有虚拟 10.x）仍可能不完美。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] ENet 客户端支持域名（FQDN）；内网穿透地址用「域名[:端口]」即可
- Evidence / 证据: Godot 官方文档 `ENetMultiplayerPeer.create_client(address, port)`——`address` 可为 FQDN 或 IPv4/IPv6；`mods/etn_coop/net/coop_net.gd`（`parse_host_port`/`_format_host_port`、`get_room_share_text`）、`mods/etn_coop/ui/coop_menu.gd`（`_on_join_pressed` 拆分粘贴的 `host:port`）。
- Notes / 说明: CGNAT 下用 playit.gg / frp 等内网穿透时，公网入口常是 `域名:随机端口`（与游戏本地监听端口不同）。① 客机加入：ENet 原生支持域名，直接填域名即可，无需 DNS 改码。② 房主分享：`get_room_share_text()` 原会强制拼 `:_lan_port`，对穿透地址会变成 `域名:P:24591`；改为解析地址自带端口（`host`/`host:port`/`[v6]:port`/裸 IPv6），无端口才补 `_lan_port`。③ 手动「公网地址」字段放宽允许 `:`/`[`/`]`。④ 客机「加入」框支持粘贴 `host:port` 自动拆到端口框。
- Source / 来源: code（官方文档）+ user
- Date / 日期: 2026-10-09

### [Mod] 网络自检只能给线索：UPnP external 判 CGNAT / 虚拟网卡名判代理 / HTTP 出口 IP
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`（`detect_virtual_adapters`/`_is_private_or_cgnat_ip`/`run_network_selfcheck`/`_on_netcheck_http_completed`、常驻 `HTTPRequest`）；`mods/etn_coop/ui/coop_menu.gd`（`%NetCheckButton`/`%NetCheckResult`）；`VIRTUAL_IFACE_KEYWORDS`。
- Notes / 说明: Godot 无 traceroute/默认网关 API，**外网可达性无法本机验证**。能可靠拿到的线索：① UPnP `external_address` 若属 `10/172.16-31/192.168/100.64-127` → 运营商 CGNAT/多 NAT（端口转发无效）；② `IP.get_local_interfaces()` 中名字命中虚拟关键字**且具备可用 IPv4** 的接口（排除 `Loopback Pseudo-Interface`/`Teredo Tunneling Pseudo-Interface` 等伪接口）→ 疑似代理/加速器（本机命中 `SSTAP 1`）；③ `HTTPRequest` 查到的出口公网 IP 若 ≠ 广播地址/路由器公网 → 代理改出口。UPnP 失败时拿不到路由器 WAN，CGNAT 只能「疑似 + 建议中继」。实现注意：`HTTPRequest` **常驻**（`_ready` 建，避免弹窗改场景树触发 `tree_changed`）；先 emit 本地结论再异步补出口 IP（避免等待）；首选 `https://api.ipify.org` 失败回退 `http://ip-api.com/line/?fields=query`，用 `String.is_valid_ip_address()` 校验。
- Source / 来源: code + test
- Date / 日期: 2026-10-09

### [Mod] 本体 option 菜单可注入自定义页；coop 选项内容「代码构建 + 一处复用两处」
- Evidence / 证据: `script/extension_hooks.gd`（`populate_option_pages`）；`ui/option.gd:_ready`（`ExtensionHooks.notify(..., [menu_box, option_button_box])`）；`mods/etn_coop/entry/coop_entry.gd`（`_populate_option_pages`）；`mods/etn_coop/ui/coop_option.gd`/`coop_option_page.gd`；`mods/etn_coop/ui/coop_menu.tscn`（`%CoopOption` 实例）。
- Notes / 说明: 本体 `ui/option.tscn` 的子页（`menu_box` 下）与页签按钮（`option_button_box/VBoxContainer` 下）由 `option.gd:menu_button_press/botton_out_anim` 按 `option_id`/`button_id` **自动**联动显隐——注入的新页只需 `option_id`、实现 `menu_show/menu_hide`（可 `extends "res://script/option_menu.gd"`，需自带 `AnimationPlayer` 的 `option_in`）。扩展点 `populate_option_pages` 让 mod 无需改 `option.tscn`。**复用技巧**：coop 选项内容不做 `.tscn` 静态布局，而由 `coop_option.gd` 在 `_ready` **代码构建**（`ScrollContainer` 防溢出），从而同一实例化场景既嵌覆盖层 OPTION 页、又作本体 option 的 COOP 页；但覆盖层 `_set_buttons_enabled` 会把 `_panel` 全部后代设 `IGNORE`，故内容脚本须暴露 `get_interactive_controls()` 供白名单登记。本体 option 菜单在主菜单与暂停菜单都存在，因此该处是**开房后仍能访问 coop 设置/自检**的正确挂点。
- Source / 来源: code + test
- Date / 日期: 2026-10-09

### [Mod] 内容发现的三处静默失效：`characters` 提前 return / `get_global_name` 判类型 / inherit 不写 `_order`
- Evidence / 证据: `script/mod_manager.gd:519-535`（`_scan_mod` 原在 `manifest.characters` 非空时 `return`，整个 `defs/` 扫描被跳过 → 同 mod 的道具/敌人全丢）、`:650-654`（`_type_ok` 用 `get_script().get_global_name()==cls`，mod 用 `extends "res://resources/player/player.gd"` 时 global_name 为空、自带 `class_name` 时返回自定义名 → 两种子类都被判类型不符拒收）、`:601-648`（`_register_path` 显式+扫描会重复注册）；`script/mod_patch.gd:_op_inherit`（写到 `base` 的 kind、且不 append `_order` → `get_content()` 遍历不到 inherit 条目，但 `get_resource` 按 id 取得到）。
- Notes / 说明: ① `manifest.characters` 改为**显式补充**：只跳过 `characters` 这一 kind 的目录扫描，其余 kind 照常；同 mod 同 kind 同 id 重复注册静默跳过（在 `_register_path` 用 `existing.mod == rec.id` 判定）。② 类型判定改 `_script_inherits()` 沿 `get_base_script()` 回溯比对 `global_name`（兼容无/自定义 class_name 的子类；不要用 `is_class`/`get_global_name` 单点判断）。③ `inherit` 需 target 的 kind 落表 + 走 `_validate_id` + append `_order`，故 `ModPatch.apply_all` 增传 `order` 与 `validate` Callable。④ `_resolve_order` 的 conflicts 改**双向图**（原单向漏拦）；`_run_entry_scripts` 改按 `_resolved_order`（原按 `_mods` 目录枚举序，`dependencies` 在 entry 阶段失效）。
- Source / 来源: code
- Date / 日期: 2026-10-09

### [Mod] 角色解锁：`PlayerCard.unlock_mode`（auto/shop）逐角色声明，与商店购买解耦
- Evidence / 证据: `resources/player/player.gd`（新增 `card_scene`/`unlock_mode`）；`script/mod_manager.gd`（`ensure_unlocked` 仅并 `auto` 角色/分支；`is_character_locked`/`get_unclaimed_unlocked_characters`/`_validate_shop_unlocks`；`KIND_CLASS` 加 `shop_characters: CharacterCard`）；`ui/mod_society_base.gd`/`ui/mod_society_card.gd`（按锁过滤 + `check_group` 覆写）；`ui/shop_menu.gd`（`shop_card_group` 并 `get_content("shop_characters")`、`shop_item_group` 并 `get_content("clothes")`）；`ui/character_shop_card.gd`（不改，购买写 `PlayerData` + `emit_check_data`）。
- Notes / 说明: 原实现 `ensure_unlocked()` 把所有 mod 角色 id 写入 `PlayerData.character` → 商店卡取到即走「已拥有」分支（`deal_anim`、按钮关）→ mod 角色永远买不到。改为逐角色声明：`auto` 自动解锁、`shop` 不进 `PlayerData.character` 需购买；`shop` 必须配同名 `defs/shop_characters/<id>.tres`（`CharacterCard`），缺条目注册告警。`branches` 各自声明（shop 主卡的 auto 分支会被告警）。注意 `shop_characters` 是 `CharacterCard`（付费商店卡，字段 `cost/name_1/weapon_icon/group`），与 `characters` 的 `PlayerCard` 是**两种资源**，不能互相追加（类型不符）。`clothes` 接入时 `PlayerData.clothes_group` 按 `id_name` 键可能缺失，`ui/item_shop_card.gd` 用 `.get(id_name, [])` 兜底、`cloth_change.gd`/`arona.gd` 改经 `ModManager.get_resource("clothes", id)` 解析（mod 服装不在 `res://resources/clothes/`）。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] ExtensionHooks 命名链式钩子：add_hook/remove_hook(priority) 避免多 mod 互相覆盖
- Evidence / 证据: `script/extension_hooks.gd`（新增 `_hooks`、`add_hook(name,cb,priority)`/`remove_hook`/`run_hooks`/`notify_hooks`/`has_hook`；保留原有 `Callable` 字段）。
- Notes / 说明: 原有钩子是 `Callable` 字段，直接赋值即**覆盖**，多 mod 争同一钩子时后者静默顶掉前者。新增命名钩子按 priority 排序（大者先）链式调用：接管类 `run_hooks` 遇 true 短路、通知类 `notify_hooks` 全跑；直接给字段赋值仍是覆盖语义（零回归）。mod 应优先用 `add_hook`。另：`_validate_character` 改用 `PackedScene.get_state()` peek（不再实例化战斗场景，启动更快），`first_round_add` 对齐改遍历 `"Player"` 组全部玩家（原只改第一个，多人/联机错误）。
- Source / 来源: code
- Date / 日期: 2026-10-09

### [Mod] ModAPI 写入接口 + 运行时翻译注入（add_translation）；zip 重装清理与上限
- Evidence / 证据: `script/mod_api.gd`（新增 `get_content_mod`/`get_societies`/`get_unclaimed_*`/`list_mods`/`register_content`/`add_translation`）；`script/mod_manager.gd`（抽出 `_register_res` 供 `_register_path` 与 `register_content` 共用；`_mod_translations` + `add_translation`；`_fail_mod` 发 `mods_changed`；`import_zip` 加 `_clear_dir`/pck 校验/`IMPORT_MAX_FILES`/`IMPORT_MAX_BYTES`；删除空 `_load_state`）。
- Notes / 说明: ① mod 之前只能通过 `_registry/_register_path` 内部结构做运行期注册（兼容层被逼这么写）→ 提供 `ModAPI.register_content(kind,id,res,mod_id,scene_path?,card_scene_path?)`，内部仍走 `_validate_id`（前缀/冲突）与 `_order` 追加，保持治理一致。② mod 自带翻译原未接入 → `add_translation(locale,key,value)` 懒建 `Translation(locale)` 后 `TranslationServer.add_translation()`；entry 是 `call_deferred`，早于菜单建卡，故 PS 文案（含 `ui/*_card` 的 `tr(key)` 回退）能命中。③ `ZIPReader` 的 `read_file` 会整块读入内存，故先查条目数、解压中累加体积，超限即 `_clear_dir(dest)` 回滚；重装必须清旧目录否则残留文件。④ `Translation.add_message(src, xlated)` 是单 locale 对象，多语言要按 locale 各建一个。
- Source / 来源: code
- Date / 日期: 2026-10-09

### [Mod] 玩家 `scene_path` 必须 `res://`：uid 被联机白名单拒绝 → 静默回退 momoi + 换人被拒锁死相机
- Evidence / 证据: `resources/player/aris_armed.tres`（原 `scene_path = "uid://coyh4dj2pbd2f"`，已改为 `res://scenes/player/aris_armed/aris_armed.tscn`；全项目 22 个 `resources/player/*.tres` 中唯一写 uid）；`mods/etn_coop/net/coop_net.gd`（`SAFE_PLAYER_PREFIX="res://scenes/player/"`、`_is_safe_remote_path` 要求 `begins_with("res://")`；新增 `_resolve_scene_path`（`ResourceUID.uid_to_path`）；`_server_player_selected`/`_server_player_ready`/`_server_request_player_change` 先解析后校验、非法 `push_warning`；`report_local_selection`/`_gate_change_scene`/`_gate_local_player_change` 入口规范化）；相机锁点 `scenes/ball.gd:61`（`emit_camera_move(camera_marker,false)`）。
- Notes / 说明: **现象**（user）：联机时房主外的客机选 `aris_armed` 无效、测试房换角色镜头卡住且角色变 momoi、进关卡前选角色也变 momoi。**根因**：`aris_armed.tres` 的 `scene_path` 是全项目唯一写成 `uid://` 的；单机 `load(uid)` 能加载所以房主本机正常，但联机路径白名单拒绝 uid（要求 `res://` 前缀）→ 客机选择被 `_server_player_selected` 静默替换成 `DEFAULT_PLAYER_SCENE`(momoi)，`_server_request_player_change` 直接 `return`。**镜头卡住机制**：测试房球菜单打开时把本机相机锁到小球（`can_move=false`）；正常换角色会 free 旧角色并新建（旧相机随旧角色销毁、新角色自带相机），换人被拒时角色不替换 → 旧相机一直锁在球上。违反既有约定（本文件 `[UI] <Char>_card.tscn` 条目：`scene_path` 应为 `res://...tscn`，不要写 `uid://`）。**修法**：本体改回 `res://`；mod 侧各入口先 `_resolve_scene_path` 再校验，非法路径 `push_warning`（不硬报错）。**通用教训**：跨端路径白名单前先解析 uid；不要静默回退默认角色——既掩盖配置错误，又可能连带副作用（相机锁死）；换人失败可在 UI/日志显式反馈。两份副本（`mods/etn_coop`、`mod_sdk/coop_mod/mods/etn_coop`）同步。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 通用「MOD」社团卡按 4 个/卡自动续卡（继承 mod_society_base + 消费方切片）
- Evidence / 证据: `ui/society_card.gd:3-14`（`player_card_1..4`）、`ui/mod_society_base.gd:9`（`members`）、`ui/mod_society_card.gd:1,10`（改为 `extends "res://ui/mod_society_base.gd"`，仅保留 `set_page()`）、`scenes/main/menu_screen.gd:21,73-86,101-102,107-112`（`MOD_PAGE_SIZE = 4` 切片 + `_mod_generic_ids()` + `_current_unlocked_gids()` token）、`mods/etn_coop/ui/coop_select.gd:12,85-102` 与镜像 `mod_sdk/coop_mod/mods/etn_coop/ui/coop_select.gd`。
- Notes / 说明: **现象**（user）：通用社团卡超过 4 个角色时不会续卡。**根因**：通用卡原把全部未认领角色塞进 `PlayerCardBox`（`menu_screen.tscn` 的固定宽 552 `HBoxContainer` + `clip_contents=true`），每张 `mod_player_card` 宽 120、加默认间距恰好容 4 张，第 5 张起被裁掉且无滚动（外层不是 ScrollContainer），不可选。**修法**：`mod_society_card.gd` 改为继承 `mod_society_base.gd`（直接复用 `members`/`check_group`/`populate_player_cards`，减少与 mod 自带卡的重复），消费方 `menu_screen._setup_societies()` 与 `coop_select._build_societies()` 按 `MOD_PAGE_SIZE = 4` 将 `get_unclaimed_unlocked_characters()` 切多为 typed `Array[String]` 并 `set("members", slice)`（**必须在 `add_child` 前**，否则 `_ready` 的 `check_group` 读到空）、标签 `MOD`/`MOD 2`/…。`menu_screen._current_unlocked_gids()` 的通用 token 由 `"__mod_generic__"` 改为带数量 `"__mod_generic__:<n>"`，否则解锁数变化但社团集合列表不变时 `_sync_societies()` 不重建（新增页不出现）。`Object.set()` 写入 typed `Array[String]` 属性验证通过（untyped 列表会类型错误）。两份 coop 副本逐行同步。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 语言注册表 + 数据驱动语言选择器 + LocaleFont 多 locale 泛化
- Evidence / 证据: `script/mod_manager.gd`（`signal languages_changed`、`const BASE_LANGUAGES`、`_languages`、`register_language`、`get_languages`）；`script/mod_api.gd:57,76`（`get_languages`/`register_language`）；`ui/langue_button.gd` + `ui/langue_button.tscn`（数据驱动下拉 + 动态触摸行 + `display_font`）；`script/locale_font.gd`（`_locale_fonts`/`_locale_ranges`/`register_locale_fonts`/`_needs_replacement`）；`script/Game.gd:322`（启动 `set_locale`）。
- Notes / 说明: **需求**（user）：让社区 mod 能补翻译并新增游戏语言。**旧限制**：`ui/langue_button.tscn`/`gd` 把 4 语言写死（OptionButton 4 个静态 item + `match index 0..3` + 4 个静态触摸行），新语言选不到；`locale_font.gd` 只认越南语（`is_vietnamese()` + `_to_vi`）。**方案**：`ModManager` 新增 `BASE_LANGUAGES`（zh_CN/en/pt/vi_VN）+ `_languages` + `register_language(locale, display_name, opts)`（同 locale **覆盖**、`opts.font_map/glyph_ranges` 经 `LocaleFont.register_locale_fonts` 安装、`languages_changed` 通知）。`ui/langue_button` 数据驱动：`_rebuild()` 清空重填 OptionButton（`clear()`+`add_item`）并代码生成触摸行（`PanelContainer>Label`，`gui_input` 绑定 locale），`display_font` 应用到选中项/`PopupMenu`/触摸行。`locale_font.gd`：`_to_vi`→`_locale_fonts`（locale→{Font:Font}）+ `_locale_ranges`，`_map_key()` 支持 `vi`↔`vi_VN` 前缀匹配，`_needs_robo`→`_needs_replacement(text, pixel, ranges)`（本地化键 or 注册区间内像素字缺字形）。**时序坑**：entry 由 `_run_entry_scripts.call_deferred()` 执行，可能晚于 `langue_button._ready` → 靠 `languages_changed` 重建；`register_language` 末尾 `LocaleFont.apply.call_deferred()` 兜底。**边界**：桌面原生 `PopupMenu` 无逐项字体，只有当前选中语言按 `display_font` 生效（触摸行逐项正确）。`.tscn` 删除了静态 4 item/4 行/4 条 `gui_input` 连接。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 翻译批量导入（additive）；覆盖本体键不可靠（HashSet 迭代序）
- Evidence / 证据: `script/mod_manager.gd:745-780`（`register_translation`/`register_translation_resource`/`register_translations_from_dir`）；`script/mod_api.gd:105-118`；`ETN_localization.csv.import`（`dest_files` = 同目录 `<name>.<locale>.translation`）；`ResourceLoader.list_directory`（4.7 引擎方法，见 `godot-ai_api_manage`）；Godot `core/string/translation_domain.cpp`（`add_translation` → `translations.insert`（HashSet）；`get_message_from_translations` 用 `score >= best_score`）。
- Notes / 说明: **需求**（user）：mod 需批量补翻译（原只有逐条 `add_translation`）。**新增** `ModAPI.register_translation(t)` / `register_translation_resource(path)` / `register_translations_from_dir(dir)`（backing 在 `ModManager`）。范式：CSV 放 `mods/<id>/i18n/*.csv`（表头 `,zh_CN,en,...`）→ 本体工程导入生成同目录 `<name>.<locale>.translation` → entry `register_language` + `register_translations_from_dir`。**语言必须显式 `register_language`（user 裁定，不自动）**；扫描跳过 `.csv/.import/.remap/.uid`、**不做运行时 CSV 解析**（user 裁定），只注册能 `load` 成 `Translation` 的导入产物。`VERSION` 仍为 1（additive）。**关键限制**：只保证**新增键**；**覆盖本体既有键不可靠**——同 locale 的多个 `Translation` 存于 `HashSet`，同分（`score >= best_score`）时胜负取决于哈希迭代序、不确定。另：`add_translation`/`register_translation*` **不触发** `NOTIFICATION_TRANSLATION_CHANGED`，须在 entry（早于菜单构建）注册，中途注册不刷新已建 UI。**实测**（4.7 headless 探针）：`register_translation` 新键命中；`register_translations_from_dir("user://trtest")` 计数 1 且新键命中；非法路径返回 false；对 `en`/`option_full_screen` 注入 mod 同键 → **base 值 "Full Screen" 胜、mod "OVERRIDDEN" 未生效**（覆盖不可靠的实例证据）。`ResourceLoader.list_directory` 对 loose 目录与 pck 均可用（同 `_scan_societies`）。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] replace_files 覆盖能力落地：ModPackReplace 预设 + replace_paths 自动列举
- Evidence / 证据: `mod_sdk/ModPackReplace.preset.cfg`（`export_filter="resources"`）；`mod_sdk/setup_mod_project.ps1`（`-Replace` 注入）；`mod_sdk/build_mod.ps1`（`-Preset` + 自动写 `export_files`）；`script/mod_manager.gd:503-508`（挂载成功且 `replace_files` 时 `push_warning`）；Godot `editor/export/editor_export.cpp`（`export_filter` 取 `all_resources/scenes/resources/exclude/customized`；选中文件存 `export_files=PackedStringArray(...)`）、`ProjectSettings.load_resource_pack(pack, replace_files=true, offset=0)`。
- Notes / 说明: `replace_files` 原只是 manifest 开关、引擎路径已通（`_mount_one`），但缺**能产出含本体路径的 pck** 的工具链。新增：覆盖型预设 `ModPackReplace`（`export_filter="resources"`、不排除本体目录）+ `setup_mod_project.ps1 -Replace` 注入 + `build_mod.ps1 -Preset ModPackReplace` 构建（枚举 `mods/<id>/**` + `mod.json.replace_paths`（须真实存在）自动写入 preset 的 `export_files`，免去编辑器手点）。**关键点**：`export_files` 按**文件路径**（ConfigFile 加载时 `FileAccess::exists` 为假会丢弃 → 不能用目录/通配）；`resources` 模式会连带所选场景的依赖一起导出。**边界**：`replace_files=true` 只影响**挂载后加载**的文件；早于挂载的 autoload 脚本、被 `preload` 缓存的资源不可覆盖（要覆盖 autoload 须把 `ModManager` 提到 `[autoload]` 最前，本工具不做）；无运行时白名单（`load_resource_pack` 不返回文件清单）；启用时运行期告警可审计。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 卸载：uninstall(id) + 待删标记 + 面板按钮（pck 运行期不可卸载）
- Evidence / 证据: `script/mod_manager.gd`（`PENDING_UNINSTALL_PATH`、`uninstall()`、`_delete_mod_dirs`/`_delete_dir_recursive`/`_path_under_mod_roots`/`_read_pending`/`_write_pending`/`_process_pending_uninstalls`；`_ready` 在 `_scan_installed()` 前调用）；`ui/mod_option.tscn`（`UninstallBtn`）；`script/mod_option.gd`（`_on_uninstall_pressed`/`_on_uninstall_confirmed`/`_mod_display_name` + 代码建 `ConfirmationDialog`）；`ETN_localization.csv`（`mod_uninstall`/`mod_uninstall_confirm`/`mod_uninstall_select`/`mod_uninstall_ok`/`mod_uninstall_fail`/`mod_uninstall_pending`/`mod_cancel`）。
- Notes / 说明: 需求（user）：正式卸载。**约束**：pck 挂载后运行期不可卸载（内容已并入 `_registry`）→ 卸载只移除文件与状态，**本会话仍生效、重启后完全移除**；Windows 上已挂载 `.pck` 常被占用删不掉 → `uninstall` 先禁用 + 清 `mods_state.json` + 从 `_mods`/`_resolved_order` 移除，再删该 id 在**所有** `_mod_dirs()` 根（`user://mods` + 桌面 exe 旁 `mods`）下的目录；删不掉则写 `user://mods/.pending_uninstall.json`，`_ready()` 挂载前 `_process_pending_uninstalls()` 重删（此时未挂载故可删）。删除路径经 `_path_under_mod_roots` 严格限定在 mod 根内（根本身拒绝），防越界。UI：面板级「卸载」按钮作用于选中行 + 二次确认。**实测**（4.7 headless 探针，已删临时文件）：注入假记录 → `uninstall` 返回 `deleted=true`/`dir_gone=true`/`state_has=false`/`restart_required=true`；pending 分支 `pend_gone=true`/标记清空；`_path_under_mod_roots` 守卫正确；7 个新本地化键 4 语命中（reimport+scan 后 `.translation` 生效）。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 记分板 mod 支持：动态筛选（本体扫描+mod）+ 记录解析兜底/占位
- Evidence / 证据: `script/mod_manager.gd`（`get_base_characters`/`get_base_game_modes`：`ResourceLoader.list_directory` 扫 `res://resources/player`/`game_mode`，`all_player.tres` 回退）；`script/mod_api.gd`（`get_base_characters`/`get_base_game_modes`）；`ui/menu_box_character.gd`/`ui/menu_box_gamemode.gd`（本体+mod 按 id 去重）；`ui/score_card.gd`（`_resolve`/`_resolve_gamemode` + `const NULL_PICTURE`）；`resources/player/all_player.tres`（仅 19 个，缺 `ako`/`chinatsu`/`aris_armed`）。
- Notes / 说明: 需求（user）：记分板筛选能自动加载新角色/模式；用 mod 内容打完记录后再移除也要能正常处理。**筛选**原为静态（角色取 `all_player.tres`、模式取场景 `@export gamemode_group`）→ 改动态：本体 = 运行时扫 `res://resources/player`（取 `is PlayerCard`，**含分支形态**如 `aris_armed`）+ mod `get_characters()`；模式 = 扫 `res://resources/game_mode`（3 个）+ `get_content("game_modes")`（`ui/menu_box_character.gd`/`ui/menu_box_gamemode.gd`，按 id 去重）。**记录**（`score_card`）原只按本体路径 `load("res://resources/<kind>/<id>.tres")`，mod/已卸载 id → `null` → 空引用报错；改为优先 `ModManager.get_resource(kind,id)`、回退本体（`load_resources()`/`_resolve_gamemode()` 用 `ResourceLoader.exists()` 守卫，缺失**静默返回 null**，避免 `load()` 对不存在路径刷红）；缺失**占位降级（策略 B）**：角色立绘=`res://sprites/player_support/null_picture.png` + 显示原 id、支援回退 `null_support`、模式卡/道具卡**跳过**、关卡显示原 id；**不自动清理**旧记录（交给面板删除/清空）。**导出风险**：`DirAccess` 枚举 `res://` 导出后失效（见 `[Export]` 条），故用 `ResourceLoader.list_directory`（pck 可用）+ `all_player.tres` 回退；仍需真机验证本体 `res://resources/player` 可枚举。**实测**（4.7 headless 探针，已删临时文件）：`get_base_characters()`=22 且含 `ako/chinatsu/aris_armed`、`get_base_game_modes()`=3、ModAPI 两接口一致；`menu_box_character` 按钮=本体+mod 去重；伪造「已移除 mod」记录 `load_record_data()` 无报错、立绘=null_picture、名称=原 id、模式/道具卡子项=0。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 跨端“跟随 sprite 的持续视觉”必须走逐帧钩子，`apply_network_character_state` 承载不了
- Evidence / 证据: `scenes/player/aris_armed/aris_armed.gd:76-77`（本体 `tick_physics` 每帧 `jet_particles_r/l.position.y = sprite_2d.position.y + 5`）、`:233-238`（`apply_network_character_state` 仅切 `emitting`）；`scenes/player/StateMachine.gd:15-22`（`tick_physics` 由 StateMachine 驱动）；`mods/etn_coop/net/coop_player_proxy.gd:106`（镜像 `state_machine.set_physics_process(false)`）、`:216-241`（`_apply_visual_state` 每帧只驱动 `sprite_2d`/`gun`/`halo_root`/`hat`）、`:247-249`（`apply_network_character_state` 仅状态变化时调用）。
- Notes / 说明: **现象**（user）：联机时 `aris_armed` 房主起飞/悬浮，客机镜像的喷气粒子停在地面不动。**根因**：`tick_physics` 不在镜像端跑（StateMachine 停用）；proxy 的逐帧视觉只覆盖 sprite/gun/halo/hat，不含喷气粒子；而唯一为 aris 接线的 `apply_network_character_state` 只在 `target_character_state` **变化时**调一次，天然无法承载连续位移。**修法**：新增**逐帧**钩子 `player.gd:apply_network_character_visual(sprite_y, delta)`（默认转发子节点 PS）+ `aris_armed` 实现（读 proxy 已插值的 `sprite_2d.position.y` 写粒子 Y），proxy `_apply_visual_state` 每帧 `call`。`sprite_y` 复用既有玩家状态包，无新网络字段。**通用教训**：① 跨端"跟随 sprite 的持续视觉/偏移"用**逐帧**钩子，别塞进变化触发的 `*_state`；② 玩家侧原有逐帧接口只有 `set_player_lookat`（瞄准语义）与 `apply_network_heading_direction`（仅 `heading!=0` 时，且全项目无实现=闲置），语义都不合适，故新增钩子；③ 新增/改动须**同步 `mods/etn_coop` 与 `mod_sdk/coop_mod/mods/etn_coop` 两副本**（本项两份 `coop_player_proxy.gd` 改后逐字一致）。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 救生圈清弹：本体 mask 快照回归 + 客机敌人子弹是视觉副本/despawn 不回报 → 只有房主有效
- Evidence / 证据: `scenes/update_item/lifebuoy.gd:17-31,39-42`（受伤→`area_entered` 清 `group EnemyBullet` + `bullet_clear`）、`lifebuoy.tscn:165`（mask，git 首个提交 `128`、快照 `f7c4292` 改为 `65536`）；标准敌弹 `scenes/bullet/enemy_bullet.tscn:12` / `enemy_bullet.gd:116`（layer `128`）；客机视觉副本 `coop_visual_sync.gd:87-90,293-326`（`_disable_damage` 清层、`_open_player_damage_hole` 压成 `ENEMY_BULLET_LAYER=128`；激光 `laser_bullet.gd:128` 层 `0`）；`coop_net.gd:2975-2983`（`remote_visual` 的 `on_projectile_despawned` 直接 return、不回报 host）。
- Notes / 说明: **现象**（user）：救生圈在联机下只有房主有效，客机无法清除敌人子弹。**根因**：① 本体快照把 `lifebuoy` 的 `Area2D.collision_mask` 从 `128`（enemy_bullet）改成 `65536`（enemy_hitbox=layer 17），标准敌弹在 `128` → 连单机都清不到普通弹；② 联机客机的敌人子弹是 `CoopVisualSync` 的纯视觉副本，层被压成 `128`（或激光 `0`），不在 mask 内；且即使清到，`remote_visual` 的 `idle_state` 只在本地回收、不回报 host → host 真子弹仍在（其它端也还在）→ “只有房主有效”。**修法**：本体 mask 回 `128`；新增 `ExtensionHooks.on_enemy_bullet_clear(pos, radius)`（`lifebuoy.gd` 触发时 `notify`），mod 侧（host 权威）本机即时按半径清 `group EnemyBullet`（普通弹 `bullet_clear`、导弹 `enemy_missile_1` 无 `bullet_clear`→`idle_state`），非 host 再 `rpc_id(1,"_server_enemy_bullet_clear",pos,radius)`——host 清真子弹经既有 `on_projectile_despawned`(`net_visual_id`) 广播 `_despawn_visual_bullet` 传遍各端。**通用教训**：① 跨端“世界状态清除”必须由 host 权威执行；客户端清本地视觉副本不等于清除权威实体，且 `remote_visual` 的 despawn 被有意丢弃（防回环），不能依赖它回报；② 新增“受伤类道具世界效果”优先走 `ExtensionHooks` 通知（对齐现有 `on_*` 约定）；③ 清弹须带 `source_faction` 过滤 + 令牌桶限频 + 归属校验（`player_by_peer_id` 距触发点 ≤400）防越权；④ **视觉副本的碰撞层（`_disable_damage`/`_open_player_damage_hole`）会改变基于层检测的本体逻辑**，排查“联机某道具失效”先比对真体与副本的层配置。实测范围：只清普通弹 + 导弹，**不清**激光/狙击/爆炸 AoE（不在 `EnemyBullet` 组，`lifebuoy` 的 65536 位亦无效）。两份 mod 副本同步。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 倒地队友方位箭头：纯本地表现，读远端镜像 `is_downed` 即可，无需新网络字段
- Evidence / 证据: `mods/etn_coop/ui/coop_downed_indicator.gd`（新建）、`mods/etn_coop/entry/coop_entry.gd`（`_ready` 挂 `get_tree().root`）、`mods/etn_coop/net/coop_net.gd`（新增 `get_display_name_for()`；倒地同步见 `_remote_player_down_changed`/`set_downed_state`）、本体 `ui/Arrow.gd:48-82`（屏幕坐标/夹边/指向数学）、`ui/arrow_icon.png`。
- Notes / 说明: 需求（user）：联机时给其它玩家显示濒死队友的屏幕边缘指示箭头（类似 raid warring 箭头）。**做法**：mod 侧 `CanvasLayer` 挂根，每帧遍历 `CoopNet.player_by_peer_id`（**只含远端**）中 `is_downed==true` 的镜像，屏外者夹到屏幕边缘 + 箭头指向 + 名字标签（`get_display_name_for`），屏内隐藏（交给其头顶已有 `HELP!`），本地玩家自己倒地时不显示。**关键复用点**：倒地已在各端同步到镜像的 `is_downed`（`_remote_player_down_changed → set_downed_state`），故指示器**零网络字段、零本体改动**；`CoopNet`/`player_by_peer_id`/`get_local_player`/`is_lan_game` 均为现成公开接口。本体 `ui/Arrow.gd` 指向静态 `Marker2D`（仅 `get_player` 时取坐标）不可直接跟踪移动目标，但屏幕坐标数学可照抄。**通用教训**：① 联机"状态型 UI"（倒地/血条/名牌）直接读镜像的同步属性即可，不必新增 RPC；② 屏幕边缘指示器用 `get_viewport().get_camera_2d()` + `get_viewport_rect().size/zoom` 求可见矩形（拉伸 `canvas_items` 下根视口=640×360），只转 icon、标签保持水平。两份 mod 副本同步；版本仍 0.1.5。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Localization] 装备卡显示走 CSV 键翻译；`.tres` 的 name/description/forward 只是同源副本且已漂移
- Evidence / 证据: `ui/ability_upgrade_card.gd:76-79`（`name_label.text = upgrade.id + "_name"`、`description_label.text = id + "_description"`、`forward.text = id + "_forward"`、`negative.text = id + "_negative"`，Label 自动翻译）；`ui/upgrade_item_card.gd:36`、`ui/test_item_card.gd:79` 同法；`resources/upgrades/ability_upgrade.gd:39`（仅 `@export`，全仓库无脚本读其 `.forward`）；`project.godot:217`（CSV 导入产物 `.translation` 已注册）；对比 `resources/upgrades/renge_doll.tres:16-18` 与 CSV `renge_doll_forward`——同 key 文本已不一致。
- Notes / 说明: 运行时装备卡文案 = `TranslationServer` 对键 `<id>_name/_description/_forward/_negative` 的翻译（`ETN_item_localization.csv` → `<name>.<locale>.translation`），`.tres` 里的 `name/description/forward/negative` **不参与该卡显示**，只是同源文本副本。故改文案**以 CSV 为准**，`.tres` 可顺带同步但不可当权威（`renge_doll` 的 `.tres` 与 CSV 各自漂移，且新条目往往只写 CSV）。改 CSV 后须 reimport 才重写 `.translation`；实测仅 `filesystem_manage reimport` 后 `.translation` mtime 未变（编辑器缓存未落盘），**再跑一次 `scan` 后才刷新**。
- Source / 来源: code
- Date / 日期: 2026-10-09

### [Mod] Boss 死亡动画/音效客机缺失 + 支援 HUD 挂到隐藏镜像（镜像污染全局组）
- Evidence / 证据: 支援 HUD：`script/support_data.gd:59-75`（`get_first_node_in_group("GameUI")`）、`ui/game_ui.tscn:182`（GameUI 在组 `["GameUI"]`）、`coop_player_proxy.gd:_disable_local_nodes`（只 `visible=false`、不移出组）、`ui/support_select_ui.gd:71-72`→`ui/character_test_menu.gd:25-47`（选支援→`reset_player()`→`game_add_support()`）。Boss 死亡：`goliath.gd:143-157`（`boss_death_anim` 无 `_net_boss_visual`）、`goliath.gd:556-568`（`_coin_drops`）、`erosion_tower.gd:64-74`（镜像判定要自身 meta）、`coop_net.gd:5623-5670`（`_spawn_enemy_remote` 只给根打 `network_remote_enemy`）、`coop_net.gd:5399-5427`（`_on_server_enemy_dead` 2 帧即 despawn）、`coop_net.gd:5440-5441`（`icon==""` 通用死亡空操作）、`erosion_tower_group.gd:106-137,172-184`、`erosion_tower_group.tscn:59`（塔组根无 `BOSS/Enemy` 组）。
- Notes / 说明: **现象**（user）：① 测试房选支援后客机 EX 条不显示但 EX 能放；② Boss（goliath/erosion 塔组）死亡在客机无动画/音效（入场正常）。**根因①**：本体 `game_add_support` 用 `get_first_node_in_group("GameUI")`，而联机每个远端镜像各有一个 `GameUI` 在组里（被 proxy 隐藏但**未移出组**）；测试房选支援经 `reset_player()` 把本地玩家重加到最后 → 该查找命中镜像隐藏 UI → 卡片不可见（support pack 在 PlayerRoot 故 EX 正常）。**根因②**：goliath `boss_death_anim` 从不广播；erosion 塔广播 `erosion_tower_visual` 但客机处理器要**子塔自身**带 meta（meta 只打在塔组根、`body_part` 空）→ 丢弃；通用死亡回退因 Boss `icon==""` 空操作；且 `_on_server_enemy_dead` 2 帧就 despawn，即便重播也会被立刻删。**修法**：① 本体 `game_add_support` 优先 `get_first_node_in_group("Player").game_ui`（镜像已移出 `"Player"` 组），mod proxy 把镜像 `GameUI`/`Camera2D` 移出 `"GameUI"`/`"PlayerCamera"` 组；② goliath 死亡补 `_net_boss_visual`，erosion 子塔放宽为「自身或父带 meta」，塔组新增 `erosion_tower_group_visual` 广播+回放，`_coin_drops` 对镜像守卫（跳过金币、死亡动画后自释放），mod 对 `/boss/` 场景延时 `BOSS_DEATH_DESPAWN_SEC=4s` 兜底回收。**通用教训**：① 联机镜像会给**每个**子 UI/相机节点带上全局组标记，本体 `get_first_node_in_group` 类查找会被镜像劫持——mod 生成镜像时应把所有「全局单例语义」的组（`GameUI`/`PlayerCamera`/`Player`/`Follow`…）从镜像移出；② Boss 专属演出（长动画+音效）必须 host 广播、镜像回放，且**回收要等演出播完**（普通敌人通用死亡可以立即 despawn，Boss 不能）；③ 镜像回放玩法脚本的方法轨（如 `_coin_drops`）要加 `network_remote_enemy` 守卫，避免客机本地重复生成奖励/二次结算。两份 mod 副本同步；版本仍 0.1.5。实测待双进程 LAN。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Mod] 倒地玩家仍被伤害：目标筛选过滤 `is_downed` 不等于伤害免除
- Evidence / 证据: `script/entity_ENEMY.gd:243-250`（`_is_valid_player_target` 已过滤 `is_downed`）、`:190-210`（`get_target`/`_select_target` 兜底 `return player`）、`script/player_health_component.gd:37-42`（`take_damage` 只挡 `is_invincible` + 友伤）、`script/player.gd:126-146`（`set_downed_state` 只 `player_stop`/视觉，不禁伤害）、`mods/etn_coop/ui/motion_down_screen.gd`（`grayscale=true` 全屏）、`coop_net.gd:3452-3464`（`_show/_hide_motion_down`）、`:7665-7701`（结算入口）、`script/GameEvents.gd:589-597`（`emit_game_over`/`force_emit_game_over` 均 `game_over.emit`）。
- Notes / 说明: **现象**（user）：① 被击倒等待救援的玩家仍被敌人攻击（掉血/受击闪白/击退）；② 倒地时若结算，屏幕仍是黑白（倒地遮罩未清）。**根因**：目标筛选只让敌人"不再选倒地者"，但**已发射弹/激光/近战/接触伤害**仍经 `PlayerHealthComponent.take_damage` 结算，而该函数不认 `is_downed`；`_select_target` 的 `player` 兜底还会把倒地 `player` 当目标。倒地黑白由 `motion_down_screen` 提供，只在复活/`_reset_player_sync` 清理，**结算路径不清** → 残留到 game over 页。**修法**：① `PlayerHealthComponent.take_damage` 顶部 `if owner.is_downed: return`（免伤+免击退+不触发受击反馈）；② `_select_target` 兜底对倒地 `player` 返回 null；③ mod 连 `GameEvents.game_over` → `_hide_motion_down()`（胜/负结算均清倒地黑白；`game_over_page` 自身按胜负的 grayscale 保留）。**通用教训**：① "不被选为目标" ≠ "不受伤害"——死亡/倒地/无敌类状态必须在**伤害结算入口**再加不变量，否则在途弹/接触/AoE 照样命中；② 全屏后效（黑白/灰度）的开关要覆盖所有"结束该状态"的路径（复活、重开、结算），漏一条就会残留到别的界面。单机 `is_downed` 恒 false，零回归。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Combat] 池化/长生命周期节点不得长期缓存 `player`：换角色后必须重新解析（`PlayerRef`）
- Evidence / 证据: 新增 `script/player_ref.gd`（`resolve()`/`ensure()`）；原崩溃点 `scenes/bullet/normal_bullet.gd:41,52-53,108-109,115`（`_ready` 抓 `player`，`active_state`/`apply_penetrate_dealt` 再读 `player.stats.bullet_scale`、`player.global_position`）；同类点 `script/player_bullet.gd:49,60-61,81,144-145`；本机玩家销毁重建入口 `ui/test_character_card.gd:93-99`、`ui/test_menu.gd:104-110`、`ui/character_test_menu.gd:36-42`（LAN 下被 mod `local_player_change_gate` 拦截  `mods/etn_coop/net/coop_net.gd:_replace_player_for_peer` 内 `old.queue_free()` + `root.add_child(新角色)`）；清场窗口 `ui/test_character_card.gd:100-102`（`left_end` 动画 0.5s 后才 `emit_test_room_reset()`  `scenes/main/test_room.gd:75-78` 清 BulletRoot 与池）。本次一并收口的同类点：`scenes/bullet/{normal_bullet,player_bullet 同族 megu_bullet,yuzu_bullet,mashiro_sniper_bullet,enemy_missile_1}`、`script/{summoned,summoned_follower,entity_ENEMY,enemies_spawn,explosion_damage}`、`scenes/player_support/kei/{luminous_nova,kei_summoned}`、`scenes/player_support/ayane/ayane_as`、`scenes/debuff/fire_field`、`scenes/item/{coin,game_tv,vending_machine,hold_pickup_item}`、`scenes/manager/{pick_item_manager,enemy_buff_manager,upgrade_manager}`、`scenes/crosshair/crosshair`、`scenes/shop/shop_ui`、`ui/UpgradeScreen`。
- Notes / 说明: **现象**（user）：联机报 `SummonedBullet.active_state: Invalid access to property or key 'stats' on a base object of type 'previously freed'`（`normal_bullet.gd:108`），栈为 `coop_net._server_visual_bullet_batch  _spawn_one_visual  coop_visual_sync.spawn_visual_bullet:86 bullet.call("active_state")`。**根因**：`player = get_tree().get_first_node_in_group("Player")` 只在 `_ready()` 里抓一次（节点一生只跑一次 `_ready`），而子弹/召唤物/敌人都是池化或长期存活对象；玩家节点在换角色时被 `queue_free` 重建，旧引用成为已释放实例，之后任何 `player.xxx` 都报 `previously freed`（**`base object` 是 `player`，key 才是被访问的属性名**）。联机里最先炸的是**远端视觉弹**：换角色时本机世界被暂停（本地不开火），但 `CoopNet` 常驻 `PROCESS_MODE_ALWAYS`、RPC 暂停下照收（mod README 479），对端 kei 弹批次照常到达  复用视觉池里 idle 的旧 `kei_bullet`（`has_line=true`，唯一走 `line.scale_mult = player.stats.bullet_scale` 的弹） 踩到旧玩家。**修法**：`PlayerRef.resolve/ensure`（先 `is_instance_valid` + `is_inside_tree` 校验，失效再按 `"Player"` 组重新解析）；跨帧持有 `player` 的节点统一加 `_ensure_player()`（或就地 `PlayerRef.ensure`），取到 `null` 时**早退而不是继续解引用**；`normal_bullet.gd`/`player_bullet.gd` 的 `has_line` 分支只在 `p != null` 时覆写 `scale_mult`，不再影响穿透/命中烟等原有逻辑。**通用教训**： 池化/长生命周期节点禁止在 `_ready()`/`_on_equip()` 缓存 `player`（或任何会被销毁重建的场景节点）：要么每次取用重新解析，要么订阅 `GameEvents.get_player`（本体在 `test_room.reset_data()` 里 `emit_get_player()`）； 换角色的旧角色已释放、清场还没到窗口是真实存在的（转场 0.5s + RPC 不受暂停影响），不要假设本地不触发就不会被触发； 联机视觉/镜像回调会绕过本地暂停，任何只依赖本地时序的假设都要重新审视。**未覆盖（已知同类但风险低）**：`scenes/update_item/*` 约 40 个道具脚本（挂 EquipLayer，换角色后随 `reset_clear_unit()` 清掉重建）与 `scenes/player/*` 内部脚本（玩家场景子节点，随玩家一起销毁），本 PR 未逐个人工核对，如需彻底收口可按同一 `PlayerRef` 模式补。
- Source / 来源: user + code
- Date / 日期: 2026-10-09

### [Combat] `PlayerRef` 收口补遗：fire_field 回归 + `EquipItem` 基类自动刷新 `player` + 派生长存体
- Evidence / 证据: `scenes/debuff/fire_field.gd:91-114`（PR 把 `if !body_group.is_empty():` 换成 `if p == null: return` 后，`for i in body_group:` 仍是 2 tab → 落入 `if p == null` 分支成死代码，火场不再结算）；`script/equip_item.gd:11-19`（`_player` 后备 + `player` getter `PlayerRef.ensure`/setter）；51 个 `extends EquipItem` 子类删除自身 `var player: Node`（否则成员重名报错）；`script/entity_ENEMY.gd`（`create_damage_data` 的 `converted_damage(_ensure_player(),…)`、`_select_target` 兜底、`settle_converted_clear`）；`scenes/enemies/tank_gun_1.gd`、`scenes/item/coin.gd:add_coin()`、`scenes/manager/interaction_manager.gd:_is_blocked`、`script/health_component.gd:90-108`、`scenes/main/main.gd:player_portal_unit`、`resources/buff/components/last_stand_component.gd:77`；派生长存体 `scenes/update_item/{murky_hand_scythe_icon,player_bullet_launcher,robotic_vacuum_cleaner_body,shiroko_drone_icon_2}.gd`。
- Notes / 说明: 跟进 PR 的「未覆盖」清单做彻底收口。**关键更正**：`upgrade_manager.apply_upgrade` 是 `player.add_child(up_item)`，即 update_item 道具**本体是玩家的子节点、随玩家一起销毁**，并非 PR 所说「挂 EquipLayer」；真正会跨越换角色存活的是它们派生到 `EquipLayer`/`PlayerRoot` 的长存体（如 `shiroko_drone_icon_2`、`robotic_vacuum_cleaner_body`、`murky_hand_scythe_icon`）。尽管如此，仍按约定对 `EquipItem` 家族统一收口：在基类加**自动刷新**的 `player` 属性（后备 `_player`，读时 `PlayerRef.ensure`），子类只删重名声明即可，无需改动各 `player.xxx` 调用点。**回归教训**：GDScript 的缩进错误（尤其把外层 `if` 换成守卫时忘了重排被包裹的循环）**不是 parse error**，`--check-only` 查不出，必须结合逻辑/差异复核（火场死循环即此类）。`hold_pickup_item` 的 `player` 语义是「范围内玩家」，故只置空不重解析（重解析会破坏在范围内不变量），已由 PR 保证安全。`map_bounds`/`support_data` 属按需解析，无需改。
- Source / 来源: user + code
- Date / 日期: 2026-10-09


### [UI] 联机选人层「已确认」标志 `_confirming` 必须随 `set_interactive(true)` 复位
- Evidence / 证据: `mods/etn_coop/ui/coop_select.gd:47-53`（`set_interactive`）、`:124-128`（`_on_player_card_id` 早退）、`mods/etn_coop/net/coop_flow.gd:153-158`（`_on_ready_cancel`）；镜像 `mod_sdk/coop_mod/mods/etn_coop/ui/coop_select.gd`
- Notes / 说明: **现象**（user）：进入选人界面，就绪后按 ESC 取消，则无法再次选人就绪（主机/客机皆然）。**根因**：确认角色时置 `_confirming=true`；ESC 取消走 `_on_ready_cancel` → `_close_ready()` + `_set_select_interactive(true)` 重新启用本层，但选人层实例**不重建**，`_confirming` 恒为 true → `_on_player_card_id` 一直早退，不再 emit `character_confirmed`。**修法**：`set_interactive(true)` 时复位 `_confirming=false`；同一条路径覆盖「难度面板取消」的 `_on_select_cancelled`。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [UI] 联机开始球红字提示 Y 必须高于交互气泡顶部（气泡约占 y∈[-94,-53]）
- Evidence / 证据: `mods/etn_coop/ui/coop_start_ball.gd:17`（`HINT_BASE_Y` 由 `-66.0` 改为 `-124.0`）、`scenes/manager/interact_prompt.gd:92-94`（`_end_y() = -bubble.size.y - 12`）、`scenes/manager/interact_prompt.tscn:71-74`（`Bubble.offset_top=-41`、`offset_bottom=0`）
- Notes / 说明: **现象**（user）：房主未全员就绪时点绿球，红字「需要所有玩家准备」被绿球的交互气泡（「开始游戏」）挡住。**根因**：气泡 `Root.y = -h - 12 ≈ -53`（h≈41），其 `Bubble` 子节点 `offset_top=-41`、`offset_bottom=0` → 气泡世界占 y∈[-94,-53]；而提示 `HINT_BASE_Y=-66` 正落在其内，且气泡 `z_index=100`（`interaction_manager.gd:148`）> 标签 `z_index=20`，故被盖住。**修法**：`HINT_BASE_Y=-124.0`，高于气泡顶并预留字高 + 4px 描边 + 10px 下滑动画余量。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [UI] 联机选人层禁用 process_mode 会冻结角色卡 select_anim，应只切输入
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_select.gd:set_interactive`（原 `process_mode = ALWAYS/DISABLED`，现改为只切输入 + `_interactive` 守卫 `_unhandled_input`）；`ui/player_card.gd:201-221`（`add_player` 先 `emit_player_card_id` 再 `card_anim.play("select_anim")`）；`mods/etn_coop/ui/coop_select.tscn:183`（`process_mode = 3` 固定在场景里）
- Notes / 说明: **现象**（user）：进入选人界面确认角色后「选择动画」不播放，按 ESC 取消就绪后才补播。**根因**：确认时 `emit_player_card_id` **同步**触发 `CoopFlow._on_character_confirmed` → `set_interactive(false)` 把整个选人 CanvasLayer `process_mode=DISABLED`，随后 `add_player` 才 `card_anim.play("select_anim")`——AnimationPlayer 已随整层停处理被冻结，直到取消就绪 `set_interactive(true)` 恢复后才从 t=0 补播。**修法**：`set_interactive` 不再改 `process_mode`（保持场景 `ALWAYS`，暂停下仍可交互、动画照跑），只切输入可交互性；新增 `_interactive` 标志，`_unhandled_input` 开头 `if not _interactive: return`，保证被 CoopReady(layer101)/CoopDifficulty(102) 覆盖期间**不吞 Esc**（交给上层遮罩）。确认动画此时在 68% 半透明遮罩下播放（用户选定方案 1）。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [UI] 官方 player_card 的 mouse_close 依赖 level_select_out 恢复，coop 取消就绪须自行 mouse_open
- Evidence / 证据: `ui/player_card.gd:34-35,168-176`（`player_card_selected→mouse_close` 置 `mouse_filter=IGNORE`；`level_select_out→mouse_open` 恢复并复位 `on_select`/`on_touch`）；`ui/society_card.gd:33-46`（切换社团重新 `instantiate` 角色卡）；`mod_sdk/coop_mod/mods/etn_coop/ui/coop_select.gd:_set_cards_interactive`（遍历 `%PlayerBox` 调 mouse_open/mouse_close；mod `Button` 卡退化为 `disabled`）
- Notes / 说明: **现象**（user）：取消就绪后**当前社团**的角色卡无法再选择，只有切换社团重新加载的卡能选。**根因**：官方 `player_card.gd` 在选择时经 `GameEvents.player_card_selected→mouse_close` 把所有官方卡的 `mouse_filter` 置 `IGNORE`，而恢复用的 `mouse_open` 只挂在 `level_select_out` 上；coop 流程从不发 `level_select_out` → 当前社团的卡永久不可点；切换社团会重新实例化卡（新卡默认可点）故只有新卡能用。`_confirming=false`（上一处修复）只是必要条件，挡在 `mouse_filter` 之后。**修法**：`set_interactive(true)` 遍历 `%PlayerBox` 子节点，官方卡调 `mouse_open()`（顺带播 `select_out`、复位 `on_select`/`on_touch`），mod 卡（`mod_player_card.gd`，`Button`）置 `disabled=false`；`set_interactive(false)` 对称 `mouse_close()`/`disabled=true`；两种卡用 `has_method("mouse_open")` 区分。注意官方卡与 mod 卡形态不同：官方是 `PanelContainer`+手写 gui_input，mod 是 `Button`+`pressed`。
- SUPERSEDED / 已被替代: 2026-10-13 通用 mod 卡（`ui/mod_player_card.gd`）改为 `extends "res://ui/player_card.gd"` 的 `PanelContainer` 子类，同样具备 `mouse_open/mouse_close`，coop 的 `_set_cards_interactive` 对其改走前者；`card is BaseButton` 退化路径仅对 mod 自定义的 `Button` 选人卡保留。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [Combat] `spawn_core(add_before_activate=false)` 会在入树前调 `active_state`，`@onready` 为 null → cross_bullet 动画不播、生成后不消失
- Evidence / 证据: `scenes/player/mashiro/mashiro_ps.gd:148-153`（`spawn_core(cross_bullet, "", ..., false, true, true, ...)`，第 9 参 `add_before_activate=false`、第 10 参 `deferred_add=true`）；`script/projectile_spawner.gd:69-81`（else 分支：**先同步 `_activate(node)`（`active_state()`）再 `call_deferred("add_child")`**）；`scenes/player/mashiro/cross_bullet.gd:22-28`（`active_state` 用 `@onready animation_player`，并把 `damage_data.source_node = get_path()`）；`scenes/player/mashiro/cross_bullet.tscn:160-176`（消失唯一出口是 `atk_anim` 末尾（t=0.5）method track 调 `idle_state()`）；对照 `script/player_gun.gd:152-158`（`add_before_activate=true`）、`script/player_bullet.gd:128-131`/`script/explosion_damage.gd:64-66`/`scenes/update_item/shiro_missile.gd:80-83`（同批 `is_ready` 门）；回归根源见 `LEARNINGS.md:838-842`（那次修复假定 `active_state` 在 `deferred add_child` **之后**执行并写入 `source_node`）。
- Notes / 说明: **现象**（user）：Mashiro 处刑弹 `cross_bullet` 小概率残留（生成后不消失）。**机制**：`cross_bullet` 每次生成都是 `scene.instantiate()` 新建（`pool_id=""`，不入池），`spawn_core` 对新建节点走 `add_before_activate=false` → 先 `active_state()` 后 `call_deferred("add_child")`。未入树时 `@onready` 尚未解析，`animation_player` 为 `null`，`animation_player.play("atk_anim")` 报 `Invalid call ... 'Nil'` 并中断函数 → 动画不播 → 末尾 method track 的 `idle_state()` 永不触发 → 精灵永久可见；同函数前面的 `get_path()`（未入树）也重现了 `Condition "!is_inside_tree()"` 红字（即 `LEARNINGS.md:838-842` 的修复被回退）。**为何"小概率"**：`cross_group` 上限 31（`mashiro_ps.gd:135`），只有**新建分支**（前 31 个）会中招；`>30` 后走复用分支（`mashiro_ps.gd:145` 的 `ins.call_deferred("active_state")`，此时已入树、正常），被复用者 0.5s 后正常隐藏，故残留数量封顶且随复用被逐步"洗掉"，取决于 proc 次数/节奏而时有时无。**修法**：给 `cross_bullet.gd` 补 `is_ready` 门（`_ready → is_on_ready → active_state`，`active_state` 顶部 `if is_ready == false: return`），使入树前调用空转、待 `deferred add_child` 触发的 `_ready` 再真正激活；并新增 `animation_finished` 回调调 `idle_state()` 作兜底（不再只依赖末尾 method track）。**通用教训**：`spawn_core(add_before_activate=false)` 的消费方，其 `active_state()` **必须**能在入树前安全空转（`is_ready` 门或不用 `@onready`/`get_path()`）；凡消失依赖 AnimationPlayer（method track / 动画结束）的节点，务必确认动画真的在树内播放，并优先用 `animation_finished` 而非"精确落在末尾"的 method track。验证：`game_eval` 未入树 `active_state` 后 `is_idle=1`（空转、无红字）；入树 2 帧后 `is_ready=true/is_idle=0/visible=true/playing=true`；0.9s 后 `is_idle=1/visible=false/pos=(0,0)`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [GDScript] `Tween.set_parallel(true)` 会把"紧邻其前"的 tweener 一并纳入并行步（组"并行段+间隔"须用 `parallel()`）
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_start_ball.gd:_show_not_ready_hint`（原 `set_parallel(true)` + `...chain().tween_interval(HOLD)` + `...chain().set_parallel(true)` → 停留失效；现改为 `tween_property(); parallel().tween_property(); tween_interval(); tween_property(); parallel().tween_property(); tween_callback()`）；引擎文档 `Tween.set_parallel()` 的 Note / `parallel()` 条目（`docs.godotengine.org` class_tween）
- Notes / 说明: **现象**（user）：开始球"需要所有玩家准备"红字"不会停留"——进场后立刻淡出、中间间隔时段处于隐形状态。**根因**：`Tween.set_parallel(true)` 官方注释明确"**Just like with `parallel()`, the tweener added right before this method will also be part of the parallel step**"；`chain().set_parallel(true)` 会把其**前一个** tweener（即 `tween_interval(HOLD)`）拉进并行组，于是随后的淡出 `tween_property` 与这个 interval **并行同时开始**（0.1s 内淡出），interval 剩余时间都在隐形——外观即"不停留/间隔被跳过"。**修法**：不要用全局 `set_parallel(true)` + `chain()` 混搭；要"两两并行成段、段间顺序"时用 `parallel()` 逐个配对：`tp(a); parallel().tp(b)` 即 a∥b，再直接 `tp(c)` 即接在 a∥b 之后。同理 `set_parallel(true)` 若紧跟某个 tweener 也会把那个 tweener 并入其后的并行段。**通用教训**：Tween 并行/顺序混排优先用 `parallel()`（局部、无状态）而非 `set_parallel()`（全局模式 + 回头吞前一个），可避免此类隐蔽的"间隔不生效"。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [Bullet] 光束/激光结算改用每 tick `intersect_shape` 即时查询：`monitorable` 切换不补发 `area_exited`，边沿事件集合会残留
- Evidence / 证据: `scenes/bullet/laser_bullet.gd:86-123`（`add_damage` 遍历 `_overlapping_areas()`，`intersect_shape` 即时查询，过滤 `is_instance_valid`/`monitorable`；形状 disabled 时跳过；已删除 `_contacts`/`_on_hit_box_area_entered/_on_hit_box_area_exited`/`_seed_contacts`）、`scenes/bullet/player_laser_beam.gd:340-377`（同款，逐启用段形状查询）；`script/hurt_box.gd:30-37`（`set_dodge` 切 `monitorable`）、`script/player.gd`（跳跃 `set_dodge(true)`）；`LEARNINGS.md:556`（`monitorable` 变化不触发物理对重算/不清既有重叠）。
- Notes / 说明: **现象/验证**（承接 2026-10-03 条目）：`game_eval` 实测——正常走进→走出光束后接触集合正确移除；但**跳跃/闪避**（`monitorable=false`）不会补发 `area_exited`，即使人已移出光束、再 `monitorable=true` 落地，`area_entered/exited` 维护的集合仍残留该目标 → 落地后继续被结算（`jump_out ... after_land=true`）；同一引擎行为也让"躲出后走回光束内"不再补发 `area_entered`，导致**反向漏打**。**修法**：结算不再依赖边沿事件集合，改为每次伤害 tick（0.1s，非每帧）用 `PhysicsShapeQueryParameters2D` + `PhysicsDirectSpaceState2D.intersect_shape` 查当前形状**真实覆盖**的 HurtBox——`laser_bullet` 用 `hit_box` 单形状、`player_laser_beam` 遍历 `_seg_shapes` 中启用段；再照旧过滤 `monitorable`（保留跳跃无敌）。`laser_bullet.add_damage` 在 `collision_shape_2d.disabled` 时跳过（保持"光束成长"期间不结算）。**关键**：用 `intersect_shape`（即时空间查询）而非 `Area2D.get_overlapping_areas()`（Rapier 缓存列表会残留，`LEARNINGS` 321/463）；`global_time_count` 由 Timer（`round_timer`/`test_room._on_timer_timeout`）在 idle 帧发出，故查询不在物理 flush 期、安全。**通用教训**：任何"进入/离开"判定若目标可能切换 `monitorable`，不能只信 `area_entered/exited` 集合；用即时形状查询取当前重叠集合并过滤 `monitorable`，才能同时避免"离开仍受伤"与"回入不再受伤"。验证（`game_eval`，实际物理步进）：在光束内 `add_damage` → 命中 1 次；`monitorable=false` 移出、再 `true` 落地 → `overlap=false`、`add_damage` 0 次命中；移回光束内 → `overlap=true`、`add_damage` 命中 1 次。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Coop] `multiplayer.get_peers()` 不含房主自身 → 客机光环 buff 中继到房主被静默丢弃
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`（`_is_valid_relay_peer` 新增于 `_has_peer` 后；`_server_relay_player_buff`、`_server_relay_summoned_buff` 原守卫 `multiplayer.get_peers().has(peer)`/`.has(owner_peer)`）；对照 `coop_net.gd` 既有约定 `{1} ∪ get_peers() ∪ {self}`（`_join_index_of`）与聊天房主本地 `_append_chat`（`_fanout_chat` 只遍历 `get_peers()`）。
- Notes / 说明: **现象**（user）：联机房主的范围 buff（支援 kei 光环）能作用于客机，客机的光环却不作用于房主。**根因**：客机光环命中房主玩家/房主召唤物的镜像后经 `rpc_id(1, "_server_relay_*_buff", peer=1, ...)` 转发；房主侧 `multiplayer.get_peers()`（返回已连接 client，**不含房主自身 id=1**）判 `has(1)==false` → 直接 `return` 丢弃。房主→客机方向走 `_send_player_buff` 的 `rpc_id(peer, ...)` 直发、不过此守卫，故正常。**修法**：新增 `_is_valid_relay_peer(peer)`（`peer == 本机 id` 或 `get_peers().has(peer)`）；目标为房主自身时**直接本地调用** `_remote_player_buff`/`_remote_summoned_buff`（`@rpc("call_remote")` 的 `rpc_id(1,...)` 不会本地执行，与聊天房主本地处理同构），否则照旧 `rpc_id`。无回环：本地落地再进 `BuffRouter` → `_gate_player_buff_apply`，`target peer_id == 本机 id` 早退不转发。客机→客机方向 `get_peers()` 含对方，本就正常。须同步 `mods/etn_coop/`（编辑器镜像/运行期）与 `mod_sdk/coop_mod/mods/etn_coop/`（打包源）两份 `coop_net.gd`。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [Buff] 范围光环统一到本体基类 `BuffAura`；kei/utaha 已迁移
- Evidence / 证据: `script/buff_aura.gd`（`class_name BuffAura extends Area2D`：`_should_affect`/`_on_body_entered`/`_on_body_exited`/`set_active`/`_clear_buffed`/`network_summon_aura_info`）、`scenes/player_support/kei/kei_aura.gd`（`extends BuffAura`，重写 `aura_value_for`/`network_aura_value`）、`scenes/player_support/kei/kei_as.gd`（`@onready var aura: BuffAura = $Area2D`，`_on_skill_active/end` 调 `set_active`）、`scenes/player/utaha/UtahaPS.gd`（`@onready var aura: BuffAura = $Node2D/Area2D`，`ps_upgrade` t2 `set_active(true)`）、`scenes/player_support/kei/kei_as.tscn` / `scenes/player/utaha/utaha.tscn`（`Area2D` 挂光环脚本、export 迁移、删除 `body_entered/exited` 连接）、`docs/CONVENTIONS.md` §11。
- Notes / 说明: **动机**：范围 buff 的联机适配点多（镜像识别、`BuffRouter` 入口、buff 路径白名单、召唤物 `CoopSummonAura` 契约、失活兜底清理），此前靠各光环手写、易漏。**抽取**：基类内聚目标探测（`Player` 组 / `has_meta("peer_id")` 镜像 / `Converted`；`Summoned`）、`BuffRouter.apply_buff/remove_source(aura_source_id)`、`set_active` 切形状并在失活时 `_clear_buffed()`、`network_summon_aura_info()`。**可重写钩子** `aura_buff_for/aura_value_for` 支持「按目标类型给不同 buff/数值」——kei 对玩家用玩家值、对召唤物用召唤物值。**镜像识别用 `peer_id` 而非 `Faction`**：远端玩家镜像无 `faction` 且在 `RemotePlayer` 组，`Faction.of_entity` 会误判为敌方（`faction.gd:26`）。**行为变更**：kei 远端召唤物数值由「玩家值」统一为「召唤物值」（`KeiAura.network_aura_value`，来源：user）。**本体实现、光环迁移本身 mod 零改动**：`_tick_summon_auras` 只依赖组 + `network_summon_aura_info`，`player_buff_*_interceptor` 走 `BuffRouter` 不变（后续为清理视觉代理副作用补了 mod，见下条）。**编辑器坑**：改 `class_name` 新文件后要 `filesystem_manage scan`；改已加载脚本后编辑器内存缓存不刷新，用 `script_create` 同内容触发 `reload`（见 `LEARNINGS` 2026-10-02/09-25）。验证：`game_eval` 实测基类 apply/remove 路由与失活清理、`KeiAura` 玩家/召唤物数值分流与 `network_aura_value`、两场景实例化后 `Area2D is BuffAura/KeiAura` 且 export 正确。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Coop] 光环迁移的视觉代理副作用 + coop mod 重建 0.1.6（get_peers 修复入包）
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd` 与 `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_apply_support_aura_visual` 对 kei 视觉代理 `Area2D` 补 `area.set_script(null)`；`const MOD_VERSION: String = "0.1.6"`）、`mod_sdk/coop_mod/mods/etn_coop/mod.json`（`version` 0.1.6）、`mod_sdk/build_coop_mod.ps1`（`-Install`）。
- Notes / 说明: **① 视觉代理副作用**：kei 光环迁移到 `BuffAura` 后，`kei_as.tscn` 的 `Area2D` 自带 `KeiAura` 脚本；mod 的 EX 视觉代理只清了根脚本，遗留的 `Area2D._ready` 会把代理加入 `"CoopSummonAura"` 组。因 `active=false`，`_tick_summon_auras` 会跳过，**本无害**；但为干净起见，`_apply_support_aura_visual` 对 `Area2D` 也 `set_script(null)`。**② 打包**：此前 coop mod 已打包/安装的 pck 是 0.1.5（构建 03:49），**不含** 之后（14:39）才改的 `_is_valid_relay_peer` 中继修复——打包/装机环境仍是旧行为；`res://mods/etn_coop/` 源码虽已修，但 `ModManager` 只挂 `user://mods/`（及 exe 旁 `mods/`）的 pck，故本机运行要重打包。重跑 `mod_sdk/build_coop_mod.ps1 -Install` → `build/etn_coop.pck` + `etn_coop.zip` + `etn_coop_0.1.6.zip`，覆盖安装到 `%APPDATA%\...\mods\etn_coop\`。**③ 版本号**：握手按 `MOD_VERSION` 严格匹配（`_client_hello` 处理里 `str(mod_ver) != MOD_VERSION` → `mod_version` 拒绝），故不仅改 `mod.json`，`MOD_VERSION` 也须同步 0.1.6；旧 0.1.5 端将无法与本版互连（RPC 契约未变，`PROTOCOL_VERSION` 仍 2）。两份 mod 副本须同步。校验：新 pck（708776 B）内可搜到 `_is_valid_relay_peer` 与视觉代理清理注释，已安装目录 `mod.json`=0.1.6。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Coop] 支援 EX 视觉跨端：房主中继用 `rpc()` 不含自身 → 看不到客机 EX
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd` 与 `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd` 的 `_server_support_ex`（原仅 `rpc("_remote_support_ex", multiplayer.get_remote_sender_id(), support_id, active)`；现改为 `var sender := multiplayer.get_remote_sender_id()` + `_apply_support_aura_visual(sender, support_id, active)` 本地回放 + `rpc("_remote_support_ex", sender, ...)`）；`_on_local_support_ex_active/end`、`_remote_support_ex`、`_apply_support_aura_visual`。
- Notes / 说明: **现象**（user）：联机双方都带 kei 时，客机放 EX 房主**看不到**客机的 kei EX 视觉（房主放 EX 客机能看到）。**根因**：`_server_support_ex` 用 `rpc(...)` 广播，而 `_remote_support_ex` 是 `@rpc("authority","call_remote")`——`rpc()` 不会在本地（房主）执行，故房主永不创建远端 EX 的视觉代理。**修法**：房主在广播前对 `sender` 本地调用一次 `_apply_support_aura_visual(sender, support_id, active)`（owner≠本机，安全；`_support_auras` 按 owner 去重，不会重复）。**诊断结论（临时 `--coop-devex` 打印 + `--coop-devexauto` 双端自动复现，代码已全部移除）**：① 镜像 kei 召唤物的 `kei_as` 输入已被 `CoopSummonedProxy._disable_support_scripts()` → `SupportAS.network_disable()` **正确禁用**（`is_processing_unhandled_input()==false`）；② EX 视觉代理正确挂在**对端 owner** 的 kei 镜像上（`tgt_owner=<对端> tgt_local=false`），自我回声 `aura skip-self`；③ **未复现**"使用者视角内多份 EX 动画"（user 描述的 bug 1）——当前构建每端每 EX 只出现 1 份、目标正确。**通用教训**：房主作为中继时，凡用 `rpc()`（`call_remote`）转发"给其它端"的表现/事件，若房主自己也应看到，**必须额外本地调用一次**；与 `get_peers` 条目同属"`rpc` 广播不含自身"这一类坑。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10
- SUPERSEDED: 2026-10-10 其中"③ 未复现 bug 1"被推翻——当时只读了 `AnimationPlayer.is_playing()`，漏看共享材质；真因见下一条（场景共享 ShaderMaterial 跨实例串扰）。

### [Rendering][Mod] 场景子资源 `ShaderMaterial` 默认跨实例共享 → 联机多实例互相串改动画（kei EX 光环多份/不收回）
- Evidence / 证据: `scenes/player_support/kei/kei_as.tscn`（`ShaderMaterial_g7pc1` 无 `resource_local_to_scene`；`AnimationPlayer` 轨道 `ColorRect:material:shader_parameter/size`）；`scenes/player_support/serina/serina_as.tscn`（两处）；本体修复：给被动画驱动的 `ShaderMaterial` 子资源加 `resource_local_to_scene = true`（`kei_as`/`serina_as`，并审计后加 `chill_ring`/`poison_ring`/`chill_shockwave`/`cross_bullet`/`utaha`/`ginseng_doll`/`student_council_hard_hat`/`gamecamera`）；mod 兜底：`mods/etn_coop/net/coop_net.gd` 的 `_localize_material_subtree`（EX 视觉代理就地 `material.duplicate()`）+ `coop_summoned_proxy.gd` 的 `_localize_material_subtree`（远端召唤物镜像材质私有化）。诊断日志（每实例 `user://logs/devex_<peer>.log`）证据：`aura create owner=1 target=.../kei tgt_owner=1 tgt_local=false`（代理挂点正确）、每次 EX 只 1 个代理、镜像 `kei_as` 的 `AnimationPlayer.is_playing()==false`。
- Notes / 说明: **现象**（user）：联机双人同带 kei，**只房主放 EX**，客机屏幕却**两只 kei 都亮环**；本人端 8s 后能收回，**对端环卡住不回收**；客机也没吃到 EX buff。**根因**：Godot 场景里 `[sub_resource]` **默认被该场景的所有实例共享**（除非 `resource_local_to_scene=true`）；`kei_as` 的动画改的是 `ColorRect.material`（**共享** ShaderMaterial）的 `shader_parameter/size` → **同机上所有 `kei_as` 实例（本机真实 + 队友镜像 + mod 的 EX 代理）一起亮**；代理 `queue_free()` 时共享材质停在半途 → 环卡住；`AnimationPlayer.is_playing()` 探针只反映"该实例自己的 AnimationPlayer"，看不到共享材质的 `size`，故一直"复现不出"。单机只有一只 kei 才不暴露，联机多实例必现。**修法**：① 本体场景给被动画驱动的 `ShaderMaterial` 加 `resource_local_to_scene=true`（每实例一份材质）→ **需重导 exe**；② mod 侧兜底（免重导）：对 mod 自建的 EX 代理与远端召唤物镜像调 `_localize_material_subtree()` 就地复制材质，使代理/镜像与本机真实实例解耦。**通用教训**：凡"多实例共存 + `AnimationPlayer` 动画驱动 `material:shader_parameter/...`"的场景，其 ShaderMaterial 子资源必须 `resource_local_to_scene=true`，否则实例间串扰（kei 光环、环类特效、玩家镜像尤甚）。排查这类问题要读**材质 shader 参数**（如 `material.shader_parameter/size`）或枚举**所有** `kei_as` 子节点，仅看 `is_playing()` 会漏判。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Coop] 测试目标（沙袋）meta `network_test_target` 从未设置 → 客机高伤害打沙袋致其消失
- Evidence / 证据: `scenes/enemies/sandbag.tscn`（`EnemyStats.max_hp = 35`、`is_test_target = true`）、`scenes/enemies/sandbag.gd:134`（`on_dead()` 调 `stats.spawn_hp()` 复活）；mod `coop_net.gd`：`will_enemy_hit_kill`/`_predict_enemy_death` 读 `enemy.get_meta("network_test_target")`（全项目**只读不写**）、`_predict_enemy_death` 置 `predicted_dead` 并 `idle_state()` 隐藏镜像、`_on_server_enemy_dead` 的"2 帧后 hp>0 才复活，否则 `_forget_enemy_net_id`+`rpc("_despawn_enemy_remote")`"启发式。修复：新增 `_enemy_is_test_target`（读 `stats.is_test_target`）替代 meta；`_on_server_enemy_dead` 对测试目标只 `_connect_enemy_dead` 重连、永不 despawn；`_validate_enemy_hit` 放行 hp<=0 的测试目标。
- Notes / 说明: **现象**（user）：联机测试房客机打沙袋有概率把沙袋打消失，**伤害越高越容易**。**根因**：① `network_test_target` 这个"测试目标不预测致死"的 meta **从未被 set**，分支恒不生效 → 客机高伤害使预测血量 ≤0 → `_predict_enemy_death` 置 `predicted_dead` 并 `idle_state()` 隐藏镜像；② 房主 `_on_server_enemy_dead` 用"等 2 帧、hp>0 才算复活"的启发式，高伤害连击时这 2 帧窗口里沙袋（`dead_lock` 已被上一帧 `spawn_hp` 释放）又被打到 0 → 误判真死 → `_forget_enemy_net_id` + `rpc("_despawn_enemy_remote")` → 客机镜像 `queue_free` **永久消失**（房主也不再登记它、不再补发）。低伤害到不了 0 故不触发。**修法**：用真实字段 `stats.is_test_target`（`_enemy_is_test_target`）判测试目标：客户端不预测致死、房主永不 despawn、命中校验放行复活窗口内的命中。**通用教训**：① 代码里"读但从不写"的 meta/标志是隐蔽死逻辑，加此类分支时务必确认有写入点；② 用"延迟 N 帧后看 hp 推断复活"这类启发式判定会与高频伤害竞态，能直接读稳定字段（`is_test_target`）就别猜。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Coop] 客机施加的 DOT 击杀不为其支援 EX 充能：转发丢失 `applier_peer` → 归属恒为 host
- Evidence / 证据: 本体归属链 `script/support_as.gd:30`（`_on_score_owned` 按 `owner_peer` 过滤：`owner_peer != 0 and owner_peer != multiplayer.get_unique_id()` 才跳过）、`script/health_component.gd:192`（死亡分支 `emit_enemy_dead_score_owned(int(stats.score), int(damage_data.owner_peer))`）、`scenes/manager/enemy_buff_manager.gd:169/185/139`（DOT `add_damage_data(..., owner_peer=entry["applier_peer"])`）、`scenes/manager/buff_manager_base.gd:81,95-96,120`（`apply_buff(..., applier_peer)`，层叠分支仅 `applier_peer != 0` 才覆盖）；mod `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（原 `_server_apply_enemy_buff` 调 `apply_buff(buff, value, source_id, stats)` **未传第 5 参** → 恒 0）、`_gate_enemy_proc_owner_suppress`（`op != 0` 才抑制）、`_on_server_enemy_damage_taken`（`owner_peer=0` 归一为 host id → 不转发）。
- Notes / 说明: **现象**（user）：联机客机的 DOT（燃烧/中毒/恶寒）跳伤击杀时，不为客机自己的支援 EX 充能（反而给 host 充能）。**根因**：客机对敌人镜像加 DOT buff 经 `_gate_enemy_buff_apply`→`_server_apply_enemy_buff` 转发 host 权威 `apply_buff`，但**未带 `applier_peer`**（缺省 0）→ host 结算 DOT 时 `owner_peer=0` → `_gate_enemy_proc_owner_suppress` 不抑制、host 本地发 `enemy_dead_score_owned(score, 0)` → host 被当归属方；`_on_server_enemy_damage_taken` 又把 0 归一为 host id → **不转发**客机，客机拿不到击杀分。全库确认 `applier_peer` 参数从未被任何本体调用点赋非 0 值（形同虚设）。**本质是设计不对称**：host 用 0 作"本机"哨兵，本体层叠分支 `if applier_peer != 0` 便让 host 永远夺不回客机归属，而客机又能覆盖 host → 无法表达"最后施加者"。**修法**（语义经 user 裁定为「最后施加者持有」，含数值）：① `_server_apply_enemy_buff` 用服务端可信 `multiplayer.get_remote_sender_id()` 作 `applier_peer` 传入（不采信包内自报）；② `_on_enemy_buff_applied`（host）对 entry 归属归一：`resolved_peer = applier_peer if !=0 else host`，直接改写 `entry["applier_peer"]`（绕过本体"0 不覆盖"），归属为本机时清空 `entry["applier_stats"]` 使 DOT 数值回退本地 `player.stats`、客机归属沿用其快照。**通用教训**：① 联机把"本机"编码为哨兵 0、另一端用真实 peer，会让"谁覆盖谁"单向不对称——凡是"最后写入者胜"的状态，别用 0 兼作"未指定/本机"；② 转发机制必须与被转发数据同步带上**全部上下文**（这里除此前的 `applier_stats` 外还有 `applier_peer`），漏一个就静默退化成"权威端自充"。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [Coop][UI] 救援进度气泡须自设 `z_index=100`，否则被远端名牌 `HELP!` 盖住
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd:7555`、`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:7555`（`_ensure_rescue_prompt_for` 在 `parent.add_child(prompt)` 后新增 `prompt.z_index = 100`）；`mods/etn_coop/net/coop_name_tag.gd:53`（名牌 `z_index=10`）、`:27,114`（`HelpTag` 本地 y=`HELP_BASE_Y=-31`，世界约 目标-92）；`scenes/manager/interact_prompt.gd:92-94`（`_end_y = -h - 12`）+ `scenes/manager/interact_prompt.tscn:71-74`（`Bubble` y∈[-41,0]，故气泡世界约 y∈[目标-118, 目标-77]）；`scenes/manager/interaction_manager.gd:148`（本体交互气泡 `z_index=100` 约定）。
- Notes / 说明: **现象**（user）：联机救倒地队友时，救援进度气泡（`interact_prompt.tscn` 实例，显示 `RESCUE xx%`）被队友头顶 `CoopNameTag/HelpTag` 的 `HELP!` 遮挡。**根因**：`_ensure_rescue_prompt_for` 新建 `interact_prompt` 实例时**未设 `z_index`（默认 0）**，而远端名牌子树 `z_index=10`（镜像本体 `z_index` 最高 3 → 有效 ≤13）；且几何上气泡完整包住 `HELP!`。**修法**（user 选定「气泡覆盖 help」）：对齐本体 `InteractionManager._build_bubble`（`scenes/manager/interaction_manager.gd:148`）的 `z_index=100`，在挂到父节点后设 `prompt.z_index = 100`；救援结束气泡隐藏后 `HELP!` 自然重现，无需跨端同步抑制状态。**通用教训**：凡从 `interact_prompt.tscn` 自行新建的实例都要显式设 `z_index`，不能指望交互管理器那一路（它只对自己创建的 `_bubble` 设值）。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [Bullet] 蓄力激光被子弹大小道具缩放（非均匀 transform）→ Rapier2D 内部无限递归 → 原生栈溢出闪退
- Evidence / 证据: `scenes/update_item/mushroom_hat.gd:7`（`PlayerData.bullet_scale_mult += 2`）→ `script/PlayerData.gd:366`（`stats.bullet_scale`）；`scenes/weapon/Supernova_Abi_Eshuhs_Sword_of_Light/charge_laser_gun.gd:122`（激活发 `emit_player_shot_position(..., laser)`）→ `script/player.gd:90/507`（`bullet_body.scale = Vector2(stats.bullet_scale, stats.bullet_scale)`，对激光本体也生效）→ `scenes/bullet/player_laser_beam.gd`（原 `active_state` 的 `self.scale.x = 1.0` 只复位 x，留下 `(1, bullet_scale)` 非均匀缩放；`_overlapping_areas` 的 `params.transform = s.global_transform` 与 `BeamHitBox` 下 10 个段形状注册）。崩溃物证：Windows 应用程序错误 `c00000fd`（STATUS_STACK_OVERFLOW，出错模块 `ntdll.dll`）；2026-10-10 21:23 的 WER minidump（`C:\ProgramData\Microsoft\Windows\WER\ReportQueue\AppCrash_Godot*\WER977F.tmp.mdmp`）解析：崩溃线程 8.3MB 栈中约 2.9 万帧重复落在 `addons/godot-rapier2d/bin/libgodot_rapier.windows.x86_64-pc-windows-msvc.dll`（+0x821b38/+0x72f3e0）。
- Notes / 说明: **现象**（user）：`aris_armed` 拿"增大子弹体积"道具后开**蓄力激光**直接卡死闪退、控制台无红字。**根因**：激光是场景预置 `BeamHitBox`（`Area2D` + N 个 `RectangleShape2D` 段），`_overlapping_areas()` 用 `s.global_transform` 做 `intersect_shape`；`GameEvents.player_shot_position → Player.bullet_hit_damage` 把激光节点按 `bullet_scale` 缩放，`active_state()` 只复位 x → 非均匀（再叠加段旋转即剪切）的 transform 交给 Rapier2D，Rapier 内部陷入递归直到栈溢出（原生崩溃，不会打印 GDScript 的 "Stack overflow" 红字）。`bullet_scale=1` 时为单位缩放故不发作；`concentrated_ammo`/`crystal_haniwa` 等一切抬 `bullet_scale_mult` 的道具同因。**为何只此一例**：普通 `PlayerBullet` 缩放后保持均匀 `(bs,bs)`；`mashiro_sniper_bullet` 虽同样只复位 x（非均匀），但走 `area_entered` 边沿事件、不走 Rapier 形状查询，故不触发（按 user 决定本次不改它）。**修法**（按 user 要求保留"狙击弹式整节点只缩 Y"的视觉）：`active_state()` 读一次 `player.stats.bullet_scale`（经 `PlayerRef.ensure`）存 `_thickness_scale`，设 `self.scale = Vector2(1.0, t)`（线宽/`Line2D` 点位/命中粒子随 Y 放大，X 不变），同时把碰撞容器 `beam_hit_box.scale = Vector2(1.0, 1.0/t)` 反向抵消——`laser(1,t) × BeamHitBox(1,1/t) = (1,1)`，`BeamHitBox` 及段形状的全局 transform 恒为等距，Rapier 的形状注册与 `intersect_shape` 都安全。`_update_segments` 改用"缩放后几何"写段形状（`dscaled=(d.x,d.y*t)`、`s.position=(mid.x,mid.y*t)`、`s.rotation=dscaled.angle()`、`rect.size=(max(|dscaled|,1), hit_box_width*t)`），两端缩放相消后世界判定与可视光束精确一致（含追踪弯束），命中宽度随视觉同步变粗。**通用教训**：① 任何喂给 Rapier2D 的 `Transform2D`（碰撞形状的父链、`intersect_shape`/`cast` 的 `params.transform`）都须无缩放、无剪切，否则可能不是报错而是**原生递归栈溢出**；② 想用节点 `scale` 做视觉形变，必须让它别沿父链污染碰撞子树——给碰撞容器反向缩放（或改用几何数据），二者取其一；③ 排查"卡死无红字"优先看 Windows `Application Error`/WER（`c00000fd`=栈溢出）并解 minidump 看重复栈帧落在哪个 dll，比在 Godot 日志里翻更有效。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Editor] 干净克隆仍依赖被忽略的 `godot_ai`，需检查插件、autoload 与测试脚本
- Evidence / 证据: `.gitignore:10`、`project.godot:38,64`、`docs/ARCHITECTURE.md:22`、`tests/test_damage_data.gd:1-2`、`README.md`「缺少 `godot_ai` 时」。
- Notes / 说明: `addons/godot_ai/` 不入库，但项目配置仍启用其插件并注册 `_mcp_game_helper`；`tests/` 的 `@tool` 测试脚本还继承插件提供的 `McpTestSuite`。本地缺少插件时，不能宣称克隆后即可无报错启动；需在关闭编辑器时同时移除缺失 helper 的 autoload 配置与插件启用路径，并在本地 `tests/` 下添加空 `.gdignore` 避免扫描依赖插件基类的脚本（配置插件运行测试前删除）。辅助插件不属于游戏逻辑，MCP 测试套件仍依赖它。本次仅核对静态配置，未验证清理后的完整游戏启动；README 已提供本地处理步骤，未修改仓库运行配置。
- Source / 来源: code
- Date / 日期: 2026-10-10

### [Mod][Mobile] aris_armed 移动端进关闪退：用 entry 型 mod 做免重装热修（形态 A）
- Evidence / 证据: mod 源 `mod_sdk/mobile_hotfix/mods/aris_mobile_hotfix/`（`mod.json` + `entry/aris_hotfix_entry.gd` + `safe_outline.gdshader`）；构建 `mod_sdk/build_coop_mod.ps1`（内部 `mod_sdk/pack_mod.gd` PCKPacker，免工程副本）→ `mod_sdk/coop_mod/build/aris_mobile_hotfix.zip`；产物 pck 含 3 文件 `res://mods/aris_mobile_hotfix/{mod.json,entry/aris_hotfix_entry.gd,safe_outline.gdshader}`。入口 `_ready` 打印 `[aris_hotfix] ready ...`；`--aris-fix=sv,outline` 实测解析为 `jets=false sv_hdr=true outline=true root_hdr=false`。候选对应 `scenes/player/aris_armed/aris_armed.tscn:404-416`（喷气粒子未设 `emitting=false`，全项目玩家仅此）、`:418-441`（SubViewport `use_hdr_2d=true`）、`:419`（CanvasGroup 材质 = `shaders/screen_outline.gdshader` 的 `hint_screen_texture`）、`project.godot` `viewport/hdr_2d=true`。
- Notes / 说明: **现象**（user）：移动端（Redmi K70 Ultra / 天玑 9300+ / Immortalis-G720 / Vulkan）反馈 `aris_armed` 进正常关卡即闪退，本机无法复现；项目有"移动端渲染问题=部分机型、盲修过一版未根治"前科（本文件 2026-10-03 移动渲染条目）。**做法**：不改本体、不重打 288MB APK，用 **entry 型 mod** 运行期热修。**为何免重装**：ModManager 在 `_ready` 里 `_run_entry_scripts.call_deferred()`（首帧）实例化 entry，早于玩家生成；入口挂 `get_tree().node_added`，玩家进场当帧即可改节点（换角色/换关重建会再次触发）；移动端 mod 只扫 `user://mods/`（Android=`/Android/data/<pkg>/files/mods/`），游戏内 MOD 页可导入 zip、重启生效。**本次补丁**：① `GraphicsHalo/JetParticlesR/L` 由 `_process` 按 `player.is_hovering` 驱动（进场 false→首帧不发射，且保留悬浮喷气）；② 玩家下所有 `SubViewport.use_hdr_2d=false`；③ 根视口 `use_hdr_2d=false`（项目设置运行时改不了，尽力）；④ `CanvasGroup.material` 换成 mod 自带 `safe_outline.gdshader`（同样做并集轮廓描边，但用 `TEXTURE`/`UV` 取代 `hint_screen_texture`/`SCREEN_UV`，并保留 `outline_width`/`flash_opacity`/`outline_color` 接口以免 `player.gd` 的 `set_shader_parameter` 报错）。**形态 A 边界**：改不了渲染器与全局 `viewport/hdr_2d` 启动值；若崩溃早于 `node_added`（`load(PackedScene)`/纹理上传期）则拦不到 → 需转**形态 B**（`replace_files=true` 覆盖 `res://scenes/player/aris_armed/aris_armed.tscn`，`mod_sdk/ModPackReplace.preset.cfg` + `build_mod.ps1 -Preset ModPackReplace`）。**操作坑**：PowerShell 默认执行策略禁直接 `& x.ps1`，须 `powershell -NoProfile -ExecutionPolicy Bypass -File <ps1>`。**状态**：根因未坐实（无设备 logcat），本 mod 为兜底热修；实机若不崩即保留，否则按 `--aris-fix=` 二分后转形态 B 或落本体。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Coop] 联机无尽第 15 关 boss 后不断跳关：视觉副本青辉石自动拾取 → host 误触发 end_boss_round
- Evidence / 证据: `ui/round_timer.gd:64`（`pyroxenes_pick_up→end_boss_round`）、`:189-197`（新增 `boss_round_pending_end` 守卫）、`:94-96`（`boss_round()` 置真）、`:186-187`（`round_end` 清假）；`scenes/item/pyroxenes.gd:11-20`（`remote_visual` 视觉副本直接 inert）、`:69-70`（10s autostart Timer 自动 `add_pyroxenes`）；`scenes/item/pyroxenes.tscn:418-421`（Timer `wait_time=10, autostart=true`）；`scenes/enemies/boss/goliath.gd:557-572` / `erosion_tower_group.gd:201-216`（boss 掉 `pyroxenes.tscn`）；`scenes/manager/enemy_manager.tscn:93`（`lv15=[goliath_spawn,tower_spawn]` 均 `boss_round=true`）；mod `mods/etn_coop/net/coop_net.gd:3250-3251,3184-3216`（`on_pickup_spawned→_on_visual_activated` 广播视觉副本）、`:3643-3677`（`_apply_shared_pyroxenes_local` 无条件补发 `pyroxenes_pick_up`）、`:2399-2404`（`_clear_round_visuals` 增清 CoinRoot `remote_visual`）；`mods/etn_coop/net/coop_visual_sync.gd:183-195`（`remote_visual` 提前到 `add_child` 之前）、`:351-360`（拾取类视觉禁 Timer）。
- Notes / 说明: **现象**（user）：联机无尽模式（只勾无尽、未勾闪击，3 人）第 15 关 boss 后进入第 16 关，计时正常但立刻转场升级，且不断跳关、超过 20 关。**根因**：`round_timer.end_boss_round` 原本对**任何** `pyroxenes_pick_up` 都在 3.5s 后 `emit_round_end`（不判是否 boss 回合）；而 coop 会把 boss 掉的青辉石作为**纯视觉副本**广播到客机，`coop_visual_sync._disable_damage` 只关碰撞、**未停脚本与 Timer**，副本 10s 后仍自动 `add_pyroxenes` → `on_pyroxenes_gain` → host `_apply_shared_pyroxenes_local` 无条件补发 `pyroxenes_pick_up` → host 在**下一回合**误触发 `round_end`。3 人局每个 boss 至少 2 个客机副本各发一次；叠加 `spawn_visual_effect` 在 `add_child` 之后才打 `remote_visual` 导致视觉副本 `_ready` 回环再广播，可持续制造带 Timer 的副本 → 「无限持续」。**修法**：① 本体给 boss 回合加「等待拾取」标志 `boss_round_pending_end`（`boss_round()` 置真、`end_boss_round()` 消费、`round_end`/`game_over` 清假），非 boss 回合的杂散拾取一律忽略；② 本体 `pyroxenes.gd` 对 `remote_visual` 副本直接 inert（`_ready` 停 Timer + `is_pick=true`，`_on_body_entered`/`add_pyroxenes` 亦守卫）；③ coop `spawn_visual_effect` 把 `remote_visual` 提前到 `add_child` 前（消除回环再广播），并对 `res://scenes/item/` 拾取类视觉禁用 Timer；④ coop `_clear_round_visuals` 回合边界清 CoinRoot 下 `remote_visual` 副本。**通用教训**：凡本体有「收到 X 信号即结束回合」的逻辑，X 又可能是联机镜像/视觉副本产生的，必须在**本体侧**加状态守卫（回合归属），不能只依赖 mod 保证副本干净；另「视觉副本=纯表现」的前提要涵盖 **Timer/脚本**，只关碰撞不足。验证：`godot --headless` 载入四脚本零报错；`tests/test_round_boss_guard.gd`（4 test 全 PASS：非 pending 不结束、`round_end` 清标志、默认 false、`remote_visual` 青辉石 inert）。两副本 `coop_net.gd`/`coop_visual_sync.gd` 逐字节一致。待双端实机验收。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Coop] 本体修复随 mod 覆盖分发 + 青辉石共享按 net_effect_id 去重（B1 保险）
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/mod.json`（`replace_files:true` + `replace_paths`）；`script/mod_manager.gd:506-510`（按 `replace_files` 挂载 + 审计告警）；`scenes/item/pyroxenes.gd`（`on_pyroxenes_gain` 传 `self`）；`mods/etn_coop/net/coop_net.gd`（`_pyroxenes_share_key` / `_credited_pyroxenes` / `_on_pyroxenes_gain(amount,node)` / `_server_shared_pyroxenes_gain(amount,key)` / `_apply_shared_pyroxenes_remote(amount,key)` / `_apply_shared_pyroxenes_local(amount,key)`；`:30-31` `PROTOCOL_VERSION=3` / `MOD_VERSION="0.1.8"`）；构建 `mod_sdk/setup_mod_project.ps1 -Replace`（注入 `ModPackReplace` 预设）、`mod_sdk/build_coop_mod.ps1`（改用 `--export-pack ModPackReplace`）。
- Notes / 说明: 需求（user）：**不再发本体**，但要让联机 mod 携带本体修复（`ui/round_timer.gd` 的 boss 守卫、`scenes/item/pyroxenes.gd` 的 `remote_visual` inert）分发；并加保险防止青辉石共享被重复来源刷到 clamp 上限 9999。**覆盖分发**：`project.godot` 已有 `export/convert_text_resources_to_binary=false`；`setup_mod_project.ps1 -Replace` 注入 `ModPackReplace`；`mod.json` 设 `replace_files:true` + `replace_paths:["res://ui/round_timer.gd","res://scenes/item/pyroxenes.gd"]`；`build_coop_mod.ps1` 的 replace 分支生成 `export_files`（镜像 mod 目录 + replace_paths）后 `godot --export-pack ModPackReplace`。**关键坑**：`ModPackReplace` 模板用 `export_filter="resources"`（选中资源 **+ 依赖**）→ pck 连带 mod 场景的全部本体依赖，实测 **~20MB / 789 文件**；`replace_files=true` 会把这些依赖一并覆盖（与本体基本同源，功能无碍但体积大）。想瘦身须走两 pck（内容用 `pack_mod.gd` 正常打包 + 覆盖 pck 由 entry 用 `load_resource_pack(path,true)` 挂载），本轮未做。`export_filter="all_resources"+exclude_filter`（ModPack 风格，5.4MB）**无法强制包含**被排除目录（`ui/*`,`scenes/*`）下的两个脚本（`include_filter` 也不生效）。另验证：本体 `.gd` 在导出包里编成 `res://x.gdc` + `res://x.gd.remap`；raw text `.gd`（`pack_mod.gd` 路线）无法覆盖本体（remap 会把 `.gd` 重定向回本体 `.gdc`）。**B1 去重**：青辉石视觉 id 跨端一致（host `net_effect_id` / 客机视觉 `_coop_effect_id`），`_on_pyroxenes_gain(amount, node)` 取其作 key，`_credited_pyroxenes` 保证每个 key 网络内只结算一次（`_on_round_start`/`_reset_player_sync` 清空）；`_apply_shared_pyroxenes_local` 同理兜底。RPC 加 `key` 参数 → `PROTOCOL_VERSION` 2→3（握手拒绝旧版）。
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [Support] 支援 EX 开局可用/无 cd 连放：`SupportData.ex_cost` 未初始化（=0）使门槛恒真
- Evidence / 证据: `script/support_as.gd:43`（`now_cost >= ex_cost` 门槛）、`:58`（`skill_end` 复位 `now_cost=0`）、`:35-40`（`cost_count` 达标发 `support_ex_ready`）；`script/support_data.gd:132-154`（`get_card` 的 `has_card` 分支不直接设 `ex_cost`）、`:184`（`count_exp` 仅在 `now_lv>0` 设 `ex_cost`）、`:59-80`（`game_add_support` 不保证 `ex_cost` 与生成的支援一致）、`:42-49`（`ex_cost`/`now_cost` 定义）；`script/Game.gd:235`（`load_playerdata` 设 `game_support` 不调 `get_card`）；`mods/etn_coop/ui/coop_select.gd:31-33`（默认空支援不调 `get_card`）。修复：`mods/etn_coop/net/coop_net.gd`（`_on_first_round_add` → `_normalize_support_cost`）、`ui/coop_select.gd`（默认空支援补 `get_card`）。
- Notes / 说明: **现象**（user，配图）：支援 HUD 显示 READY 但充能条为空——`cost_count` 在 `now_cost>=ex_cost` 时发 `support_ex_ready`（`support_card.gd:29` 的 `value=now_cost/ex_cost` 画成 `0/0` 空条），两者同时成立只可能 `ex_cost==0`；此时 `now_cost(0)>=ex_cost(0)` 恒真 → 开局即可放，`skill_end` 又把 `now_cost` 归 0 → 无限连放。**根因**：`SupportData.ex_cost` 只在 `get_card()` 里赋值，而 `get_card` 的 `has_card` 分支靠 `count_exp()`，`count_exp` 又只在 `now_lv>0` 时 `ex_cost=now_support.ex_cost`；一旦「支援场景被生成但 `get_card` 未按本体语义设 ex_cost」（存档 `load_playerdata` 设 `game_support` 不调 get_card、`coop_select` 默认空支援不调 get_card），`ex_cost` 停在默认 0。**联机侧修复（随 mod 分发）**：`CoopNet._on_first_round_add` 末尾 `_normalize_support_cost.call_deferred()`——在 `main.first_round` 的 `game_add_support()` 之后 `get_card(game_support)` 同步 + 兜底 `if ex_cost<=0: ex_cost=game_support.ex_cost` + `now_cost=0`；`coop_select._ready` 默认空支援补 `get_card`。**留档（本体根治，暂不改）**：① `support_data.gd:get_card` 的 `has_card` 分支应无条件 `ex_cost=now_support.ex_cost`，`game_add_support` 生成前调 `get_card(game_support)`；② `support_as.gd` 的 `_unhandled_input`/`skill_active` 加 `ex_cost>0` 门。**关键约束/实测**：`SupportData` 是 autoload 且先于 `ModManager` 加载 → `support_data.gd` **不可**随 mod `replace_files` 覆盖；而 `support_as.gd`（`class_name SupportAS`，子类 `extends SupportAS`）**可**覆盖且作用于子类——实测：临时 pck 覆盖 `res://script/support_as.gd`（加标记方法）后，`serina_as.tscn` 实例 `has_method(marker)==true`、`get_base_script().resource_path==res://script/support_as.gd` 且源码含标记。故将来做本体防御门可经 replace 分发。
- SUPERSEDED: 2026-10-21 本体已根治：`support_data.get_card` 无条件写 `ex_cost`、`game_add_support` 生成前同步并清零、`support_as` 加 `ex_cost>0` 门控；mod 的 `_normalize_support_cost` 已删除。本条「本体根治暂不改」不再适用。（来源：user + code + test）
- Source / 来源: user + code + test
- Date / 日期: 2026-10-10

### [Coop] 联机死亡门抢先于生命数复活：Ichika 杂鱼酱被动失效、HP 归零直接倒地
- Evidence / 证据: `script/Stats.gd:156-168`（`hp` setter 在 `hp<=0` 时**先**问 `player_death_gate`，命中即 `return`，之后才到 `life_num > 0` 的复活分支）；`script/extension_hooks.gd:18`（`player_death_gate`）；`mods/etn_coop/net/coop_net.gd:2339-2350`（`_gate_player_death`）；`scenes/player/ichika/ichika_ps.gd:16,57-63,65-76`（连 `GameEvents.player_revive` → 消耗 mobu + `PlayerData.add_player_revive`；`round_start_add_mobu` 增 `PlayerData.life_num_add`）。
- Notes / 说明: **现象**（user）：联机下 Ichika 生命值归零时不消耗杂鱼酱（mobu）复活，而是直接进入濒死（倒地），疑似生命数机制在联机未生效。**根因**：本体 `Stats.hp` setter 在 `hp<=0` 时先调 `ExtensionHooks.player_death_gate`（联机 `_gate_player_death` 对本地玩家无条件 `set_downed_state(true)` 并返回 true），命中即 `return`，**永远走不到后面的 `life_num > 0` 复活分支**——`GameEvents.player_revive` 不发、mobu 不消耗、也不回血；单机 gate 为空 Callable→false，故正常。**修法（仅改 mod，本体零改动）**：`_gate_player_death` 在本地玩家 `stats.life_num > 0` 时返回 false，把控制权交还本体走生命数复活；生命数耗尽才转倒地。**通用教训**：`player_death_gate` 位于「生命数复活」**之前**，联机接管死亡时必须显式放行 `life_num`，否则一切「归零复活」被动/道具在联机被吞；写此类 gate 要对照本体 `hp` setter 的完整分支顺序。**验证（test，单进程 host）**：注入同款修复门 + 真实 `Stats.hp` setter（断开 test_room `protect_player`）——`life_num>0` 时 `hp=0 → life 1→0、hp 回 50%、is_downed=false`；`life_num=0` 时 `hp=0 → is_downed=true`。临时探针 `--coop-devrevive` 测试后已移除。两份 mod 副本同步。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-11

### [Coop] 移动流量下中继连不上：mod 自加的 WS 握手超时过短（联机版无此超时）
- Evidence / 证据: `mods/etn_coop/net/coop_relay_peer.gd:11-12`（`JOIN_HANDSHAKE_TIMEOUT_MSEC`/`CONNECT_TIMEOUT_MSEC`）、`:81-126`（`_poll` 超时判定与 `_action_sent` 发帧）、`:160,164,180`（`room_created` 清 / `join_prepared` 起算 / `join_admitted` 清）；`mods/etn_coop/net/coop_net.gd:32,34`（`HELLO_TIMEOUT_MSEC`/`HELLO_ACCEPT_TIMEOUT_MSEC`）；默认地址 `ui/coop_menu.gd:585`（`mc.yqst.top:32085`）；参考版对比：`H:\Enter-The-Nyangeon-Co-op\script\network\RelayMultiplayerPeer.gd:50-63`（`STATE_CONNECTING` 直接 return，**无任何超时**）、`H:\ETN_coop_0.4.1.3\script\network\RelayMultiplayerPeer.gd:25-26`（仅 `JOIN_HANDSHAKE_TIMEOUT_MSEC=15000`，无 CONNECT 超时）。
- Notes / 说明: **现象**（user）：手机走流量时连不上中继，WS 握手耗很久。**根因**：联机版参考实现的 WS 连接/握手**完全没有超时**（一直等 `WebSocketPeer` 自己失败），我们 mod 在「中继加入健壮性」里自加了 `CONNECT_TIMEOUT_MSEC=10000`（移动流量慢握手常在完成前就被 10s 掐断）、`JOIN_HANDSHAKE_TIMEOUT_MSEC=15000`、`HELLO_ACCEPT_TIMEOUT_MSEC=6000`、`HELLO_TIMEOUT_MSEC=5000`。**修法（仅改 mod）**：全部放宽到 **30s**（`HELLO_TIMEOUT_MSEC` 房主踢未握手须 ≥ 客机 `HELLO_ACCEPT_TIMEOUT_MSEC`）；并修一处缺口——`_join_handshake_started_msec` 原先只在收到 `join_prepared` 时才起算，导致「WS 已 open 但 `room_created`/`join_prepared` 迟迟不来」**无超时永久卡 CONNECTING**，现改为**发送建/入房控制帧时即起算**、`room_created`/`join_admitted` 清除。**通用教训**：① 给「跨网 + 移动流量」的握手加超时宁可放宽（对称于无超时的参考实现），过紧会把慢网络用户直接挡在门外；② 超时计时器要覆盖**每一段等待**（发帧→首个回复、回复→准入），否则存在永久挂起的空窗；③ 排查「联机连不上/卡住」先与联机版参考实现比对常量，mod 与本体/参考的行为差异常是新引入的坑。两份 mod 副本同步；运行时用打包 pck，需重建后生效。
- Source / 来源: user + code
- Date / 日期: 2026-10-11

### [UI] 返回难度选择必须撤销待启动计时器，隐藏页面不会取消入场
- Evidence / 证据: `ui/level_select.gd:27`、`ui/level_button.gd:79,94,96`、`ui/level_button.tscn:284`。
- Notes / 说明: 当前返回仅发送 `level_select_out` 并播放 `RESET`，难度按钮已启动的 0.5 秒 Timer 没有停止，超时也没有检查取消状态。源码推导存在“返回后仍进入战斗”的路径，尚待实机复现；修复时需同时取消计时器、复位选择状态并守卫超时回调。静态 UI/UX 检查详见 `docs/UI_UX_REVIEW.md`。
- SUPERSEDED: 2026-10-10 已由实际场景回归复现并修复；返回调用 `cancel_selection()`，计时器和触屏延迟回调一并失效，超时再校验页面状态；重新进入可选择。当前规则已上提 `ARCHITECTURE.md` 的菜单章节。
- Source / 来源: code + test
- Date / 日期: 2026-10-10

### [UI] 记分板筛选的触屏点按阈值不对称，向上拖动会通过点击判断
- Evidence / 证据: `ui/menu_box_button.gd:84-95`、`ui/menu_box_character.tscn:9`、`ui/menu_box_gamemode.tscn:10`。
- Notes / 说明: 释放时使用 `offset <= 10`，负向大位移同样成立；还缺少横向距离、手指索引和取消状态检查。源码算式已复核，真实触屏事件路由尚待验证；应采用二维距离阈值与单指跟踪，避免滚动误选。
- SUPERSEDED: 2026-10-10 已改为二维距离、同指跟踪与取消/目标区域检查（`ui/menu_box_button.gd:86`）；`_input` 提前观察滚动消费的拖动和释放，延迟清理手指状态。合成事件已覆盖四方向、拖回原点、多指与取消，Android 真机事件路由仍待测。
- Source / 来源: code + test
- Date / 日期: 2026-10-10

### [UI] 装备负百分比预览先取整会丢失书包的减伤收益
- Evidence / 证据: `ui/ability_shop_item_card.gd:217,285`、`resources/equip/bag.tres:28`。
- Notes / 说明: 第三属性负值预览使用 `int(value) * 100`，书包实际条目 `-0.05` 因而表达为 `0%`，累计属性却采用 `int(value * 100)`。应统一属性格式化口径，先缩放再按明确精度取整；该结论来自资源及算式复核，未执行游戏内升级。
- SUPERSEDED: 2026-10-10 预览改为 `roundi(value * 100)`（`ui/ability_shop_item_card.gd:217`），实际书包资源的场景回归确认 `-5%`；未改其他属性格式化入口。
- Source / 来源: code + test
- Date / 日期: 2026-10-10

### [UI] 动画 method track 的焦点设置需要等待延迟调用完成
- Evidence / 证据: `ui/level_select.gd:49`、`ui/option.tscn:78`、`tests/test_ui_ux_regressions.gd`。
- Notes / 说明: 难度页动画 method track 会启用按钮焦点；`animation_finished` 后再等一个 `process_frame` 才抢焦点，避免 deferred method 尚未执行时控件仍为 `FOCUS_NONE`。测试应等待动画完成而非固定 0.3 秒，渲染首帧较慢时固定计时可能早于动画完成。设置通过递归焦点开关隔离缩放隐藏的子页，见 `ARCHITECTURE.md`。
- Source / 来源: code + test
- Date / 日期: 2026-10-10

### [UI] 社团清卡信号也会在退出选角时发出，不能视为继续填卡的许可
- Evidence / 证据: `scenes/main/menu_screen.gd:society_card_filter`、`scenes/main/menu_screen.gd:change_player_card`、`tests/test_ui_ux_regressions.gd:_check_navigation`。
- Notes / 说明: 社团切换等待 `player_card_clear_done` 后逐张填充角色，但 Esc 返回也会调用 `change_player_card()` 发同一信号。因此清卡后要核验选角仍打开；填充方法内部有逐卡 Timer，返回可能发生在填充途中，完成后仍需再次核验并清理。社团上下导航在 `_input` 阶段消费事件，否则原生 GUI 焦点导航可能先吃掉方向键；难度页必须排除，避免切换背景社团。
- Source / 来源: code + test
- Date / 日期: 2026-10-11

### [UI] 角色焦点预览会打断入场动画，丢失恢复输入的关键帧
- Evidence / 证据: 用户 2026-10-11 反馈选角页连续左右键后无法确认；`ui/society_card.gd:populate_player_cards`（逐卡等待 0.07 秒）；`ui/player_card_anim.tres:398,416`（`add_card` 长 0.1 秒，末帧将 mouse_filter 设为 STOP）；`ui/player_card.gd:97,196,202`；`tests/test_ui_ux_regressions.gd:_check_character_focus`。
- Notes / 说明: 上一轮单次左右焦点检查不足以覆盖连续导航。社团刚填完时快速三次右键可以聚焦仍在入场的末张卡；原 `focus_entered → select_card` 打断 `add_card`，使 mouse_filter 永久停在 IGNORE，焦点仍存在但 `add_player` 拒绝 Enter。最小复现修复前稳定失败；仅提前完成末张卡入场动画即可通过。修复以 `_entering/_switching` 保护不可打断动画，完成后再应用预览；恢复输入同时服从 `_input_open`，不重新启用难度页后的背景卡。新增连续/重复方向键、分支期间切换焦点及 Enter 确认检查。
- SUPERSEDED: 2026-10-11 用户复测仍可触发，明确发生在角色完全显示后，且 Esc 可以正常返回。上述入场窗口问题及修复仍有测试证据，但不能视为已解决用户报告的全部症状；稳定显示后的问题继续调查。已使用渲染窗口验证鼠标位置、键盘输入状态，并复制本机 etn_coop MOD 到隔离目录，尚未复现该剩余问题；需以真实运行的焦点/输入记录定位。
- SUPERSEDED: 2026-10-11 后续真实日志及折返回归已复现剩余问题，见下条；入场保护继续保留，用于独立的入场输入锁问题。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-11

### [UI] 稳定显示后的连续左右导航失效：等待真实运行记录定位
- Evidence / 证据: 用户 2026-10-11 复测反馈「角色已完全显示后，连续按左右键」「Esc 可以正常返回」；当时 `scenes/main/menu_screen.gd:_trace_character_input` 的临时 `[DEBUG-nav2]` 记录；本机 `user://logs/ETN_debug.log`。
- Notes / 说明: 调查时，入场动画修复不足以覆盖此症状。实际渲染窗口、四张卡片上的真实鼠标位置、`Input.parse_input_event` 方向键输入和本机 etn_coop 包副本的组合检查通过，但没有复现用户剩余问题，因此等待真实焦点/输入/动画日志。
- SUPERSEDED: 2026-10-11 用户再次复现后的日志已定位：爱丽丝 → 柚子 → 动画中右返，焦点误入分支按钮并随面板隐藏而丢失；见下条。临时诊断代码已移除，本条从待确认区移入正文保留调查历史。
- Source / 来源: user + test
- Date / 日期: 2026-10-11

### [UI] 角色卡尺寸动画期间必须显式指定左右焦点邻居
- Evidence / 证据: 用户 2026-10-11 反馈「角色已完全显示后，连续按左右键」「Esc 可以正常返回」并再次复现；真实 `user://logs/ETN_debug.log` 出现角色卡 → `BranchButton` → null；`scenes/main/menu_screen.gd:_link_player_card_focus`；`ui/player_card.gd:_has_card_focus/_on_card_focus_exited/switch_branch`；`ui/player_card_anim.tres:1020`；`tests/test_ui_ux_regressions.gd:_check_character_focus`。
- Notes / 说明: 爱丽丝预览展开后，左移柚子并在 0.1 秒退场动画中右返，卡片宽度变化会使原生几何搜索选中仍可见的分支按钮；随后文本面板隐藏释放焦点，方向键与 Enter 均失效，Esc 仍走菜单返回逻辑。修复前折返检查失败，修复后通过。社团填卡后统一设置角色卡的左右邻居，边界指向自身，避免动画影响目标；本体分支按钮沿用同一左右路径。Tab 仍能进入分支按钮，卡片把子按钮焦点视为自身预览焦点；切换分支的 RESET 隐藏面板前先将焦点交回角色卡，避免另一条丢焦点路径。
- SUPERSEDED: 2026-10-19 分支切换不再先播 `RESET`（改为 `branch_anim` 从展开态直接过渡，结束后按焦点确定性复位），因此不再有「RESET 隐藏面板」这一路径；`switch_branch` 仍会先把焦点交回角色卡，并新增 `_switching` 防重入。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-11

### [UI] 鼠标悬停与键盘焦点各自驱动预览，会同时展开两张角色卡
- Evidence / 证据: 用户提供录像 `C:/Users/gytxtx/Videos/2026-10-11 14-19-13.mp4`，约 31–42 秒可见绿子/柚子等角色同时展开；`ui/player_card.gd:_input/_apply_hover/_on_card_anim_finished`；`tests/test_ui_ux_regressions.gd:_check_character_preview_input`。
- Notes / 说明: 原预览条件为「拥有焦点或鼠标落在矩形内」，两种输入可分别激活不同角色。真实渲染测试复现绿子和柚子同时展开而键盘焦点在柚子，该路径 Enter 仍可确认；录像未显示按键事件，不能仅凭双预览认定仍然丢失输入。修复让真实鼠标位移进入角色卡时转移焦点，预览及分支动画恢复仅依据所属角色焦点，零位移事件不抢回键盘焦点。新增检查在修复前失败、修复后通过，涵盖鼠标接管、静止指针、零位移事件和 Enter 确认。触屏原有两次点按流程保留。
- 用户确认 / User confirmation: 用户随后明确录像主要问题为「同时展开两张角色卡，选中状态混乱」，本条修复对应此问题。带本机 MOD 副本的选角专项 30 项通过，无 MOD 的完整渲染 UI 回归 227 项通过。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-11

### [UI] 主菜单悬停动画与键盘焦点必须共用同一个选中项
- Evidence / 证据: 用户 2026-10-11 明确主界面问题为「多项同时高亮，Enter 确认项与鼠标指向不一致」；`script/menu_button.gd:_ready/menu_button_press/mouse_exitedd_anim`；`tests/test_ui_ux_regressions.gd:_check_main_menu_focus`。
- Notes / 说明: 主菜单按钮原先将 `mouse_entered/mouse_exited` 与 `focus_entered/focus_exited` 同时绑定到高亮动画，但悬停并不转移焦点。真实渲染场景复现：键盘聚焦开始游戏，鼠标移到测试房后两项高亮，Enter 仍确认开始游戏；11 项专项中 6 项失败。修复改为真实鼠标位移通过 GUI 事件接管焦点，动画只由焦点变化驱动，修复后 11 项全通过。不要仅把高亮条件改为「焦点或悬停」，也不要逐帧按静止鼠标位置抢回焦点；触摸预览同样先聚焦，失焦后清理两次点按标记，延迟回调需再检查焦点和菜单是否禁用。
- Validation / 验证: 独立用户目录完整渲染 UI 回归 104 项通过；复制本机已安装 MOD 后主菜单专项 11 项通过。
- Coverage / 覆盖边界: 上述 11 项仅覆盖鼠标与键盘焦点交接，不覆盖 MOD 注入后的上下邻居；后续用户补充 QUIT 下键跳回 OPTION，另见下条。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-11

### [UI] MOD 插入菜单后，所有入口都必须重建上下焦点邻居
- Evidence / 证据: 用户 2026-10-11 反馈安装 MOD 后选中 QUIT 按下键跳到 OPTION；`ui/menu_button.tscn:101,102`；`scenes/main/menu_screen.tscn` 的 Quit 实例；`mod_sdk/coop_mod/mods/etn_coop/entry/coop_entry.gd:_populate_menu_buttons`；`scenes/main/menu_screen.gd:_link_menu_button_focus`；`tests/test_ui_ux_regressions.gd:_check_main_menu_order`。
- Notes / 说明: 共用菜单按钮场景写死上邻居为 TestRoom、下邻居为 Option；Quit 实例未覆盖这些属性。COOP 插入 Quit 上方后只设置自身上下邻居，不能修正 Quit 继承的目标。修复在菜单启用时按可见子节点顺序统一设置所有按钮的上下邻居，首尾指向自身，跳过待删除、不可聚焦及禁用的原生按钮。带本机 MOD 副本的专项修复前 27 项中 10 项失败，修复后 27 项全通过，覆盖真实 COOP 及额外入口插入、隐藏和重排。连续按键测试必须检查每一步的焦点，不能只检查最后一次；错误循环可能最终回到起点而被误判为通过。
- Validation / 验证: 无 MOD 的完整渲染 UI 回归 120 项通过；带本机 MOD 副本的主菜单专项 27 项通过。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-11

### [UI] 测试房道具卡必须在鼠标释放后区分点击与列表拖动
- Evidence / 证据: 用户 2026-10-11 反馈鼠标拖动测试房道具列表会选中按到的道具；`ui/test_item_card.gd:_on_button_gui_input/_input`；`script/ScrollBox.gd:set_scrollbox_gui_input`；`tests/test_ui_ux_regressions.gd:_check_test_item_mouse`。
- Notes / 说明: 道具卡原先在左键按下时调用 `_on_button_pressed()`，而事件通过 PASS 冒泡给 ScrollBox 启动滚动，因此同一手势既发放道具又滚动。真实卡片与真实 ScrollBox 的最小渲染回归已复现：列表滚动成功，但按下即发放道具且消耗次数。修复把业务动作延后到有效释放；使用视口坐标记录整个手势的最大位移，避免滚动造成卡片本地坐标漂移，也避免拖出再拖回被当作点击。释放的延迟清理必须校验按压序号，否则同帧下一次按下可能被前一次清理取消。专项覆盖正常点击、拖动滚动、拖回、小抖动、列表外释放、无对应按下、禁用、连续点击及触屏两次点按，14 项通过，带本机 MOD 副本同样 14 项通过。
- Validation / 验证: 无 MOD 的完整渲染 UI 回归 134 项通过；日志仍有既有 `godot_ai` 缺失及退出资源清理告警。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-11

### [UI] ScrollBox 把滚轮当拖动起点会让列表在未按鼠标时跟随指针
- Evidence / 证据: 用户 2026-10-11 反馈角色列表在不拖动时也随鼠标移动；`script/ScrollBox.gd:set_scrollbox_gui_input/_input/_end_drag`；`ui/character_test_menu.tscn:13`；`tests/test_ui_ux_regressions.gd:_check_scroll_mouse_state`。
- Notes / 说明: 原脚本对任意 `InputEventMouseButton.pressed` 设置 `isDrag=true`，滚轮没有对应释放事件，导致随后无按键的鼠标移动仍滚动列表；右键也会错误启动。最小真实 GUI 回归 6 项中 3 项失败。修复限定左键启动及移动掩码，提前观察释放并在隐藏/失焦时清理，同时按 index 保持触屏手势归属。扩展后的无 MOD 专项 14 项通过。前轮道具卡点击回归未覆盖共用滚动脚本的滚轮状态，不能用其通过来推断所有列表手势都正常。
- Compatibility / 兼容边界: 本机 `etn_coop 0.1.9` 的 `replace_files=true`，其 `res://script/ScrollBox.gd.remap` 指向包内旧 `ScrollBox.gdc`；带该包专项 14 项中 7 项仍失败。本地源码修复不会自动更新已编译 MOD；当前仓库 SDK 为 0.1.6，不能直接重建替换为该旧版本。尚未改动本机安装包。
- Validation / 验证: 无 MOD 完整 UI 回归首次 148 项中一项系统鼠标位置检查失败；未改动相关代码的复跑 148 项全部通过。日志仍有既有 `godot_ai` 缺失及退出资源清理告警。已询问是否同时修补本机 MOD，答复到达前保留安装包。
- 用户确认 / User confirmation: 用户随后明确选择“项目源码修复，保留本机 MOD 包”；本次以源码修复为范围，不修补、重建或替换本机 MOD，带旧包仍受上述覆盖限制。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-11

### [UI] 难度页辅助焦点与开关动画需要独立的页面输入门控
- Evidence / 证据: `ui/level_select.gd:_input/_lock_selection/_set_auxiliary_enabled`；`ui/support_ui/support_select_ui.gd:open_list/close_list`；`ui/gamemode_type.gd:add_game_mode/erase_game_mode/set_interactive`；`tests/test_ui_ux_regressions.gd:_check_level_keyboard_regions`。
- Notes / 说明: 支援展开后聚焦已选项目必须等待动画及容器布局完成，并核验展开序号，否则 Tab 或 Esc 离开后旧回调会抢回焦点。模式切换中焦点变化不能打断填色动画，冲突模式引发的新切换需用序号淘汰旧恢复回调；完成后恢复鼠标输入仍须服从页面门控，避免难度确认或返回后重新启用。`AnimationPlayer.play("RESET")` 的离散 visible 轨道不会在调用当帧立即应用，测试收起和返回应等待动画完成，不能仅等一次 `process_frame`。模式互斥按资源配置执行：闪击与无尽可共存，二者均与 `hujiu` 冲突。
- Validation / 验证: 独立用户目录完整渲染 UI 回归 182 项通过；最终带本机 MOD 副本的难度页渲染专项 33 项通过，无 MOD 及带 MOD 的无窗口专项各 28 项通过。本机 MOD 包保持原样。日志仍含既有 `godot_ai/runtime/game_helper.gd` 缺失及退出资源清理告警。
- Coverage / 覆盖边界: 上述检查未逐帧观察入场按钮亮度；用户随后反馈选择角色后所有难度按钮闪动，新增过程检查已复现，修复见下一条。
- Source / 来源: test
- Date / 日期: 2026-10-11

### [UI] 难度初始化不能复用从高亮首帧开始的失焦动画
- Evidence / 证据: 用户 2026-10-11 反馈选择角色后所有难度按钮闪一遍；`ui/level_select.tscn:417-429`；`ui/level_button.gd:open_mouse/cancel_selection`；`ui/level_button.tscn:125-164`；`tests/test_ui_ux_regressions.gd:_observe_level_entry/_check_level_entry_visuals/_check_character_focus`。
- Notes / 说明: 入场动画在 0.2 秒通过 `player_selected` 对全部难度按钮调用 `open_mouse`，复用 `cancel_selection` 撤销旧选择。原取消播放的 `mouse_out` 在首帧强制写入完全高亮的遮罩、纹理和宽度，再用 0.1 秒退回默认，导致非焦点按钮也集体闪亮。无窗口过程检查在修复前稳定捕捉到三个非默认按钮变亮，最终焦点仍正确，说明只检查入场完成状态会漏报。修复以 `RESET` + `advance(0)` 同步复位外观，继续保留计时器停止和选择序号失效。回归采样持续到页面真正启用焦点再等待动画稳定，避免渲染首帧或着色器编译较慢时固定等待时长提前结束检查。
- Validation / 验证: 无 MOD 完整渲染回归 187 项通过，包含真实选角确认后逐帧采样；带本机 MOD 副本的难度专项渲染 37 项、无窗口 32 项通过。本机 MOD 包未修改。
- Source / 来源: user + test
- Date / 日期: 2026-10-11

### [UI] 支援主卡的焦点描边不能放在圆角裁剪内部或列表下方
- Evidence / 证据: 用户截图 `codex-clipboard-744b0aae-3f29-485b-beb4-ac0feb89a4c2.png`；`ui/support_ui/support_select_ui.tscn` 的 `main_card.clip_children=1` 及其兄弟 `MarginContainer`；`ui/level_select.gd:_create_focus_outline`；`tests/test_ui_ux_regressions.gd:_check_support_focus_frame`。
- Notes / 说明: 原 ReferenceRect 作为主卡子节点绘制直角框，圆角遮罩裁掉四角，后绘制的兄弟列表还遮住了侧边。前轮截图验证的是列表项目焦点，没有覆盖主卡持有焦点时展开列表的外框。修复为独立圆角 Panel 描边，置于主卡和列表上方并忽略鼠标输入，随主卡矩形变化同步尺寸；其他卡片保留矩形焦点框。实际渲染像素检查覆盖四个圆角和两侧，原实现失败、修复后通过，同时检查展开与收起状态。支援键盘展开测试等待实际动画和布局完成，避免截图读回耗时导致固定 0.2 秒检查提前结束。
- Validation / 验证: 无 MOD 渲染专项 39 项通过；最终带本机 MOD 副本的难度页渲染专项 41 项通过，包含新增的收起状态检查。本机 MOD 包保持原样。
- Source / 来源: user + test
- Date / 日期: 2026-10-11

### [Android] 自适应图标必须按安全圆校验，不能只检查方形留白
- Evidence / 证据: `android/icons/launcher_foreground.svg:2`、`android/icons/launcher_monochrome.svg:2`、`export_presets.cfg:137`；维护规则见 `docs/CONVENTIONS.md` §6.1。
- Notes / 说明: 432×432 图层的安全区为居中、直径 264 px 的圆，位于同尺寸方形角落的猫耳仍可能被裁切。隔离 APK 中实际导出的前景及单色层最远像素半径约 127.47 px，低于安全半径 132 px；后续调整需要重新校验完整主体。
- Source / 来源: test
- Date / 日期: 2026-10-13

### [Localization] 重导入会重写该 CSV 全部 locale 的 `.translation`；只改一列时未改动 locale 也会出现字节抖动
- Evidence / 证据: 2026-10-13 合入 PR #5（仅改 5 个 CSV 的 `pt` 列，en/vi 列经解析 0 改动）后，`scan` 重建 `.translation`：`ETN_item_localization.en.translation` 与 `.vi_VN.translation` 无内容变化但字节不同（en 25744→25744、vi_VN 34830→34838），`zh_CN` 未变，仅 `pt` 为实义变化。
- Notes / 说明: `OptimizedTranslation` 为 hash/bucket 序列化，同内容在不同导入批次可能产生不同字节（引擎版本/写入顺序差异）。只改某一 locale 列时，提交范围应**只含该 locale 的 `.translation`**，把其余 locale 的抖动用 `git checkout --` 还原，避免无意义二进制 diff。改 CSV 的完整流程：`scan`（或重聚焦编辑器）→ 生成 `.translation` → 抽样校验 → 只提交受影响 locale（`reimport` 可能静默不生效，见上方 2026-09-25 条目；游戏运行中需先 `project_manage(stop)`）。
- Source / 来源: test
- Date / 日期: 2026-10-13

### [UI/Mod] 页签工厂只统一采用接口的控件，旧安装包不会自动变样式
- Evidence / 证据: 用户确认目标为已安装 COOP；直接挂载其 `etn_coop.pck` 核对 `entry/coop_entry.gd:138`、`ui/coop_ui_style.gd:23`，与工作区 `mods/etn_coop/` 副本一致；`script/mod_api.gd:13`；`tests/test_ui_ux_regressions.gd:_check_settings`。
- Notes / 说明: 已安装 COOP 0.1.14 自建 `Button`，使用 11 号字、独立绿色主题和 32 像素最小高度；本体页签为带动画的 `PanelContainer` 和 19 号文字。隔离验证确认即使移除 mod 主题，组件和动画差异仍在。新增 `ModAPI.create_option_tab` 后，本体与采用接口的 mod 页签共用场景；带原安装包的渲染检查中，测试页签外观统一，旧 COOP 页签仍保持其自定义样式。SDK 示例更新不会替换玩家已有 `.pck`，需 mod 作者采用接口并重新发布。不要把“共存检查通过”写成“旧 COOP 样式已修复”。
- Follow-up / 后续（2026-10-16，来源：user | code | test）：用户指出当前 COOP 导航仍有细微差异。隔离复制并挂载当前安装的 **0.1.10** 后，运行时确认它与本体共用 `res://ui/option_button.tscn` 根组件，但其已打包 entry 仍自行 `Label.new()`，节点名 `coop_option`，字体/字号/描边由 Mod 写死；本体的 `Label` 文本为空。两者同为 19 号字，差异来自新共享 Label 的内部留白、裁切及垂直排版：本体 Label 局部矩形 `(6,3,116,25)`、`clip_text=true`，Mod 自建 Label 为 `(6,5,116,22)`、`clip_text=false` 且未采用内部留白；因此仅根节点一致不能证明文字一致。工作区 `mod_sdk/coop_mod/mods/etn_coop/entry/coop_entry.gd:139` 已用 `ModAPI.create_option_tab`，需重新打包安装才影响实际游戏。此次 0.1.10 与此前 0.1.14 是不同安装包的观察，不能混写为同一实现。核对记录：`.godot/settings_nav_audit_20261016/installed-tab-inspection.log`。
- SUPERSEDED: 2026-10-16 上述将旧文字实现归因于“当前已安装 PCK”的结论不成立。空工程独立挂载重装前备份 `installed-backup/etn_coop.pck`，输出 `OLD_PCK_USES_FACTORY=true`、`OLD_PCK_MANUAL_LABEL=false`；旧实现实际来自项目内 `mods/etn_coop/` 镜像。此前只隔离了 user://，未隔离 res://，读取的虚拟路径不能证明来自安装包。用户指出的视觉差异仍成立，原因修正为旧镜像遮蔽安装包（来源：code | test）。
- Follow-up / 后续（2026-10-16，来源：code | test）：按用户“重新安装”要求，已用当前 SDK 源构建 87 文件 PCK，并替换用户安装目录，同时备份并同步项目镜像。空工程校验新 PCK entry 与源文件 SHA-256 一致；运行时 COOP 只有共享 Label，矩形、字体、留白与本体一致。82 项设置断言通过，存档、联机配置、Mod 状态和 project.godot 哈希不变；旧包/镜像保留于 `.godot/coop_reinstall_20261016/2db82db4/`。现有插件及退出资源报错仍保留。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-13


### [Mod] ZIP 中存在 PCK 条目不等于安装成功；重装失败不会自动保留旧包
- Evidence / 证据: `script/mod_manager.gd:1241,1255,1259`、`script/mod_option.gd:457`；`docs/CODEBASE_AUDIT_20261018.md`（归档） AUD-MOD-001。
- Notes / 说明: 当前导入先清旧目录，文件打开失败时跳过但仍返回 `ok=true`。隔离探针先安装真实 PCK，再用 PCK 同路径目录/文件冲突包重装，结果提示成功却无 PCK。需要先暂存并完整校验，再交换目录；修复前调用者不能把成功返回当作所有文件写入成功，也不能依赖失败回滚。
- Source / 来源: test
- Date / 日期: 2026-10-13
- SUPERSEDED: 2026-10-13 本轮已改为 `mod_installer.gd:4` 的暂存/验证/交换事务，文件/目录冲突、写入/交换失败及超限明确失败并保留旧安装。真实已挂载 PCK 更新亦通过。旧“失败不保留旧包”仅描述修复前行为（来源：test）。

### [Testing] Godot 退出 0 与断言完成标记不能排除原生错误
- Evidence / 证据: `tests/run_ui_ux_checks.py:98`、`tests/test_ui_ux_regressions.gd:127`；`docs/CODEBASE_AUDIT_20261018.md`（归档） AUD-TEST-001。
- Notes / 说明: 两次隔离 UI 回归均 133 项断言通过、runner 退出 0，仍打印信号发射期间同步 `free()` 导致的原生 `ERROR:`。当前 runner 只检查 stderr 的 `SCRIPT ERROR:` 和 stdout 完成标记。错误检查应合并两条流，精确区分退出资源计数例外和真正错误；在动画信号恢复栈中拆除场景要延迟/队列释放并等待完成。此现象定位于测试拆除，不能直接当作正式 UI 故障。
- Source / 来源: test
- Date / 日期: 2026-10-13
- SUPERSEDED: 2026-10-13 runner 已使用 `godot_check_output.py` 合并检查两条输出流，只精确豁免退出资源计数；动画信号恢复后的场景改为 queue_free 并等待一帧。133 项 UI 回归通过，原信号释放错误消失；通用“退出 0 不足以证明成功”结论保留（来源：test）。

### [Android] 自适应图标必须按安全圆校验，不能只检查方形留白
- Evidence / 证据: `android/icons/launcher_foreground.svg:2`、`android/icons/launcher_monochrome.svg:2`、`export_presets.cfg:137`；维护规则见 `docs/CONVENTIONS.md` §6.1。
- Notes / 说明: 432×432 图层的安全区为居中、直径 264 px 的圆，位于同尺寸方形角落的猫耳仍可能被裁切。隔离 APK 中实际导出的前景及单色层最远像素半径约 127.47 px，低于安全半径 132 px；后续调整需要重新校验完整主体。
- Source / 来源: test
- Date / 日期: 2026-10-13

### [Android] 图层尺寸合规与主体最小尺寸需分别核验
- Evidence / 证据: `android/icons/launcher_foreground.svg:1`、`:2`、`android/icons/launcher_monochrome.svg:2`、`export_presets.cfg:138`；[Android 官方设计要求](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。
- Notes / 说明: 当前自适应图层 432×432 px 对应 xxxhdpi 下的 108×108 dp；彩色前景与单色层可见主体均为 216×174 px，即 54×43.5 dp。SVG 矩形轮廓顶点距中心最远约 128.16 px，小于安全圆半径 132 px，且主体距画布四边至少 108 px，大于外缘保留区 72 px。安全区与留白符合要求，但若按主体宽高均至少 48 dp 严格核验，高度仍不足；不能用画布大小代替可见主体大小。轮廓顶点距离与上条 APK 栅格像素距离采用不同测量口径。
- Source / 来源: code + test
- Date / 日期: 2026-10-13

### [Coop] 选人准入与共享金币规则由用户敲定
- Evidence / 证据: 当前会话用户选择；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:1046,6941,6954`；`docs/SYSTEMS.md` §5.8 / §8。
- Notes / 说明: 选人开始后拒绝新加入、允许原身份断线重连；共享金币按拾取者倍率向上取整后共享全队。后续不得仅凭旧实现恢复成 SELECT 中随意接纳新身份，或对客机只结算未乘倍率的币值。倍率属性继续沿用现有客机自报、有界同步模型。
- Source / 来源: user
- Date / 日期: 2026-10-13

### [Coop] 延迟节点回调传 ObjectID；重连中的召唤物必须等待连接与握手
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:4200,7230`、`net/coop_summoned_proxy.gd:98`；`tests/coop_recovery_checks.gd`。
- Notes / 说明: `call_deferred(child)` 传入类型为 Node 的参数时，child 若已释放，错误发生在参数转换阶段，函数内部 is_instance_valid 尚未执行。改为传 instance_id 和会话代次，执行时重新解析、校验节点和所属会话。另一处实测错误来自保留场景重连时召唤物 proxy 在 CONNECTING 阶段发送 RPC：不仅需要 peer 非 null，还要 CONNECTED 及客机握手通过，再标记 despawn_sent 或发送状态。两项错误均被严格日志回归捕获并修复。
- Source / 来源: test
- Date / 日期: 2026-10-13

### [Localization] Python strict CSV 仍会漏掉 Godot 吞引号的写法
- Evidence / 证据: `tests/check_localization.py:10`、`tests/test_localization_format.py`；`.godot/repository_audit_full/csv_messages.log`。
- Notes / 说明: 原字段中裸 `"Samuela the Beyond"` / `"Fruit Jelly"` / `"Momoyodou"` 被 Python csv.reader(strict=True) 保留，却被 Godot importer 去掉引号。须将整个字段括起、内部双引号写为两个。本分支原本修正 5 处 CSV 写法并重新生成 3 个 item 翻译资源；对齐上游时确认 `3e77cb5`/`44e2651` 已独立落地同样的修正（合并后 CSV 逐字节一致），故 rebase 后本分支不再改动 CSV 与 `.translation`，只保留 `.gitattributes` 行尾规则与守卫脚本。新守卫同时检查裸引号。
- Source / 来源: test
- Date / 日期: 2026-10-13

### [Mod] `ExtensionHooks` 的命名链式钩子（add_hook/run_hooks）全仓库零调用，实际语义是「后赋值者覆盖」
- Evidence / 证据: `script/extension_hooks.gd:128-174`（定义 add_hook/remove_hook/has_hook/run_hooks/notify_hooks）；本体 78 个调用点全部走单 Callable 的 `ExtensionHooks.intercept/notify`（如 `script/buff_router.gd:5`、`script/GameEvents.gd:186`）；联机 Mod 直接赋值约 40 个槽（`mod_sdk/coop_mod/mods/etn_coop/entry/coop_entry.gd:63-64`、`net/coop_net.gd:1780-1830`）。
- Notes / 说明: `:129` 的注释宣称「多个 mod 需要挂钩同一扩展点时用 add_hook/remove_hook，避免直接赋值互相覆盖」，但本体从未调用 `run_hooks/notify_hooks`，该能力实际未接通：第二个 Mod 挂钩同类扩展点会静默覆盖前一个，无告警。要真正支持多 Mod 共存，需让本体调用点改走命名钩子并按 Mod 归属登记。
- SUPERSEDED: 2026-10-13 已修复——新增 `intercept_named`/`notify_named`/`is_hook_active`，本体 86 处调用点迁移到命名入口，命名回调与字段赋值双轨共存（见下方同名条目的新记录）。
- Source / 来源: code
- Date / 日期: 2026-10-13

### [Mod] 启动期自动停用（缺依赖/依赖环/冲突）会被写进 `mods_state.json`，造成永久禁用
- Evidence / 证据: `script/mod_manager.gd:344-350`（`_fail_mod` 写 `_mods[id]["enabled"] = false`）、`:119-127`（`_save_state` 遍历全部 Mod 落盘）、`:1171-1176`（`set_enabled` 触发保存）。
- Notes / 说明: Mod A 因依赖 B 缺失被停用时，用户此后任意一次切换别的 Mod 开关都会把 `A: false` 持久化；即使之后装上 B，A 也不会自动恢复。应把「用户启用状态」与「本次解析结果」分开存储。
- SUPERSEDED: 2026-10-13 已修复——`_fail_mod()` 不再改 `enabled`（只写 `error`/`mounted`），`enabled` 回归「用户启用意图」并被 `_save_state` 持久化；另新增 `_disable_dependents()`：某 Mod 挂载失败时递归摘除依赖它的 Mod（同样只写运行期字段）。已用隔离 user 目录 + 3 个测试 Mod（缺依赖 / 缺 pck / 依赖缺 pck）验证：自动停用不再落到 `mods_state.json`，依赖方被正确摘出 `_resolved_order`。
- Source / 来源: code
- Date / 日期: 2026-10-13

### [Coop] 本体倒地文案键由联机 Mod 提供，本体 CSV 未定义
- Evidence / 证据: `script/player.gd:138,144` 使用 `lan_player_down` / `lan_player_revived`（`_downed_text` 在同名或空翻译时回退英文 `DOWN!`/`REVIVED!`）；5 个 `ETN_*localization.csv` 均无这两个键；由 `mod_sdk/coop_mod/mods/etn_coop/i18n/coop_i18n.gd:130-132` 注入。
- Notes / 说明: 未安装联机 Mod 时这两条文案永远是英文，单机中文本地化被 Mod 绑架。跨模块复用文案键应回归本体 CSV。
- Source / 来源: code
- Date / 日期: 2026-10-13

### [Coop] 联机信任模型由用户敲定：好友房默认可信，不做反作弊校验
- Evidence / 证据: 用户 2026-10-13 判断（主机/客机数据校验「没有必要，而且对主机性能和延迟都拖累比较大」）；涉及 `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:3776-3784`（青辉石来源）、`:5988-6028`（命中位置历史）、`:6007`（回滚校验）、`:7479-7523`（召唤物所有权）；性能相关 `:325-358`（限流）、`:6157-6159`、`:6260-6262`（per-peer 转发）、`:1084`、`:6240`（reliable 大包）。
- Notes / 说明: **反作弊类语义校验＝可选/可删**：青辉石来源校验、命中位置历史回滚、召唤物所有权拒绝分支、`max_hp`/`ammo` 语义上限、命中音效 key 白名单。**必须保留的三类护栏不是反作弊**：① 防崩 / 防远程代码执行——`_is_safe_remote_path` 路径白名单（客机可借此在 host 上 `load()` 任意场景并执行其脚本）、`is_finite`/`_finite_v2` 有限性、条目数上限（`BULLET_BATCH_LIMIT`、召唤物 32 上限）；② 防会话错乱——`_server_sender_ok()` 握手门控、`_session_generation` 代次校验；③ 玩法正确性——召唤物 owner 路由、`MapBounds.nearest_inside` 位置夹取、青辉石同颗 key 去重、客机拾取医疗箱后 host 端实体必须移除。性能事实：`_rate_allow`/`_rate_allow_tokens` 与 `_sanitize_*` 都是每 RPC / 每视觉条目一次的本地计算（量级 μs，无往返），且限流是**提前丢弃洪泛的性能保护**——删校验基本省不到 CPU，也不会降低延迟。真正拖累 host 与延迟的是：客机→host 视觉转发的 per-peer `rpc_id` 循环（每条包序列化 `peers-1` 次）、发送侧视觉队列无上限、以及 reliable 通道承载大包（`:1084` 全表广播、`:6240` 可靠视觉批）造成的队头阻塞。**落地（2026-10-13，code）**：已删除命中位置历史回滚及其全部连带结构（`_record_enemy_pos` / `_enemy_expected_pos` / `_enemy_pos_history` / `HIT_VALIDATE_MAX_DIST` / `HIT_VALIDATE_TOL` / `HIT_HISTORY_MAX` 与调用点），`_validate_enemy_hit` 精简为「目标存活」检查，`attacker`/`victim_pos` 保留为参数占位以免改动 RPC 签名；纯表现发送队列封顶（`_queue_visual`/`_queue_effect` + `PENDING_VISUAL_MAX=256`/`PENDING_VISUAL_RELIABLE_MAX=512`/`PENDING_EFFECT_MAX=256`）；UI 每帧轮询加早退与节流（`coop_menu`/`coop_room_label`/`coop_chat`/`coop_downed_indicator`）。per-peer 扇出改广播、reliable 全表 roster 改增量经评估后**未做**：前者需在包内携带来源 peer id 才能让 sender 忽略自身，后者要同步改 5 处 `_client_sync_roster` 接收语义，收益与风险不匹配。
- Source / 来源: user
- Date / 日期: 2026-10-13

### [Mod] ExtensionHooks 命名钩子已接通：本体调用点走 `*_named`，字段直接赋值继续兼容
- Evidence / 证据: `script/extension_hooks.gd:134-160`（`intercept_named`/`notify_named`/`_slot_of`/`is_hook_active`）；本体 78 处 `intercept/notify(ExtensionHooks.xxx,...)` 迁移为 `*_named("xxx",...)`，另有 8 处改用 `is_hook_active`（`scenes/main/main.gd:71`、`scenes/main/menu_screen.gd:52`、`script/projectile_spawner.gd:83,96`、`scenes/manager/enemy_buff_manager.gd:67`、`ui/pause_screen.gd:39,79`、`ui/round_timer.gd:73`、`scenes/player/hina/hina_ps.gd:36`、`scenes/player_support/ayane/ayane.gd:7`、`script/summoned_follower.gd:233`）。
- Notes / 说明: 语义＝先跑 `add_hook` 命名回调（按 priority，接管类任一 true 短路），再跑同名字段赋值；`hook_name` 必须与字段同名，拼错在运行期 `push_error`（不再静默失效）；`is_hook_active(name)` 供「注入才覆盖默认值」的查询式分支。**例外**：`enemy_spawn_stat_scale` / `enemy_spawn_count_scale` 返回数值，属覆盖语义，仍走字段直接调用，不参与命名链式。旧 `intercept(cb,args)`/`notify(cb,args)` 保留给已发布 mod（本体已不再调用）。验证：56→58 个改动脚本 Godot 解析全过；`enemy_*_scale` 之外的直连 `.call()/.is_valid()` 已清零（静态集合比对 45 个调用名全部命中声明字段）。
- Source / 来源: code
- Date / 日期: 2026-10-13

### [Relay] `relay_server.py` 加固：CSPRNG 房间码、join 限速、资源上限、丢帧背压与并发心跳
- Evidence / 证据: `mod_sdk/coop_mod/server/relay_server.py`（608 → 760 行）—— `_secure_choice = secrets.choice`、`generate_room_code()`（长度/字母表不变）、`join_block_reason`/`record_join_fail`（每连接 8 次/60 s、每 IP 40 次/60 s、30 s 冷却）、`MAX_ROOMS=256` / `MAX_TOTAL_CLIENTS=512`、`send()` 超水位丢帧 + 连续 3 次断开、`heartbeat_peers()` 并发 gather；`tests/test_relay_limits.py`。
- Notes / 说明: 帧格式、控制消息类型与字段名、房间码字母表、帧长上限全部未变（客户端无需改动）；新增行为均由带默认值的环境变量控制：`MAX_ROOMS`、`MAX_TOTAL_CLIENTS`、`WRITE_OVERFLOW_LIMIT`、`JOIN_FAIL_WINDOW_SEC`、`MAX_JOIN_FAILS_PER_PEER`、`MAX_JOIN_FAILS_PER_IP`、`JOIN_BLOCK_SEC`。原实现「超水位 `await drain()` 5 s」会让一个只发不读的客户端拖住整条广播链与心跳，现改为丢帧保全部。注意：房间码仍是 4 字符（20 bit），限速只缓解枚举、不改变熵；如需强抗枚举必须加长或引入口令（会破坏现有 UI/客户端约定）。
- Source / 来源: code
- Date / 日期: 2026-10-13

### [Mod] `etn_coop` 不再整文件覆盖本体脚本：manifest 去掉 `replace_files`/`replace_paths`
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/mod.json`（删除 `replace_files: true` 与 `replace_paths: ["res://ui/round_timer.gd","res://scenes/item/pyroxenes.gd"]`，`name` 改为「ETN Coop 联机」）；本体这两个文件已内建 `ExtensionHooks` 调用（`ui/round_timer.gd:73,77,81`、`scenes/item/pyroxenes.gd:20,63`）。
- Notes / 说明: 覆盖是冗余的，且经 `ModPackReplace` 构建时会把打包时刻的本体脚本嵌进 pck，在用户机上覆盖本体、把本体后续修复回退；`docs/ARCHITECTURE.md:161` 记录过同类事故（0.1.9 携带 `ScrollBox.gd.remap`）。`version` 字段刻意未改：它需与 `coop_net.gd` 的 `MOD_VERSION` 保持一致。
- Source / 来源: code
- Date / 日期: 2026-10-13

### [Render] 2D 物理插值开启后：逐帧 `_process` 驱动的节点须关插值，传送/复用点须 `reset_physics_interpolation()`
- Evidence / 证据: `project.godot` `[physics] common/physics_interpolation=true`；`scenes/game_camera/gamecamera.tscn`、`camera_2d.tscn` 的 Camera2D `physics_interpolation_mode = 2`(OFF)；`script/player.gd` 的 `halo` 设 OFF；池化基类 `script/player_bullet.gd`、`script/entity_ENEMY.gd`、`scenes/item/coin.gd` 等的 `active_state()`/`idle_state()` 顶部 `reset_physics_interpolation()`；`script/map_bounds.gd` 拉回后 reset；coop 镜像 `coop_enemy_proxy.gd`/`coop_summoned_proxy.gd` 关插值、`coop_visual_sync.gd`/`coop_net.gd` 出生点 reset。依据 issue #4（Naitrate，高刷显示器角色/摄像机抖动）。
- Notes / 说明: 高刷屏下渲染帧率 > 物理 60Hz 时，物理体按 60Hz 跳步、而相机在 `_process` 每帧跟随 → 相对抖动。开启插值让物理体在 tick 间平滑，但：① 位置在 `_process` 每帧赋值的节点（相机、逐帧 lerp 的视觉子节点）会与内插叠加 → 必须 `physics_interpolation_mode = OFF`（相机建议配 `position_smoothing` 由引擎在 `_process` 平滑）；② 对象池复用/传送时若不理会，会从旧坐标插值「拉丝」一帧 → 在最终定位后 `reset_physics_interpolation()`；③ 在 `_physics_process` 内移动的节点**不要**每 tick reset（会抵消内插）；④ 迁移期：新增需要逐帧 `_process` 定位的视觉节点应主动设 OFF，新增池化/传送点应补 reset。移动端原先硬编码 `Engine.max_fps = 60` 的 workaround 已由「帧率上限设置」取代。
- Source / 来源: user + test
- Date / 日期: 2026-10-13

### [Mod] 通用 mod 选人卡保持原版风格 = 继承 player_card.gd + 克隆原版节点树
- Evidence / 证据: `ui/mod_player_card.gd`（`extends "res://ui/player_card.gd"`，覆写 `_ready`/`_update_visual` + `_apply_generic_visual`）；`ui/mod_player_card.tscn`（克隆 `scenes/player/ako/ako_card.tscn` 节点树，加载 `ui/player_card_anim.tres`）；`ui/mod_society_base.gd:50-58`（缺 `card_scene` 时实例化并注入 `player_card`）。
- Notes / 说明: 原通用卡是 `Button`+简化 `VBox`，与本体 `PanelContainer`+`player_card_anim` 的展开/分支动画风格不一致。改用克隆原版节点树 + 继承 `player_card.gd` 后，`branch_anim` 的 method track 调到覆写的 `_update_visual`，分支切换时同步名字/武器/立绘/光环/配色。父类 `_ready` 不写名字/武器标签（原版靠场景烘焙），故通用卡须在 `_apply_generic_visual` 自行赋值；`player_card` 由 `mod_society_base` 在 `add_child` 前注入，`_ready` 判空后卫。宽 135 与原版一致（4×135+间距=552 正好铺满固定宽 `PlayerCardBox`）。⚠️ 复制卡场景勿内嵌角色专属大图（名字艺术字/halo），halo 运行时由 `PlayerCard.halo` 注入。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-13

### [Mod] unlock_mode=shop 缺 shop_characters 时用 PlayerCard 合成通用商店卡
- Evidence / 证据: `script/mod_manager.gd:_validate_shop_unlocks/_register_synthesized_shop_card/_synthesize_shop_card/_shop_weapon_icon`（`DEFAULT_SHOP_CHARACTER_COST=6`、`WEAPON_TYPE_ICON_DIR="res://ui/weapon"`）；`resources/player/player.gd`（新增 `@export_enum(...) weapon_type`）；22 份 `resources/player/*.tres` 补齐 `weapon_type`；`ui/character_shop_card.gd:add_character`（空 `group` 保护）。`ui/character_shop_card.tscn` 本身即原版风格且数据驱动，故商店侧只需数据。
- Notes / 说明: 原本 shop 角色缺 `defs/shop_characters/<id>.tres` 仅 `push_warning`，角色永远无法购买。现改为在 `_scan_mod` 之后（该 mod 角色/商店条目均已注册）用其 `PlayerCard` 合成 `CharacterCard` 并经 `_register_res`（走 id 治理）注册进 `shop_characters`，`ui/shop_menu.gd` 既有 `get_content("shop_characters")` 循环自动收录。字段映射：`name` 末空格拆 `name_1/2`、`sprite_path`→`character_sprite_path`、`weapon`→`weapon_name`、`weapon_type`→`weapon_type_name`+`weapon_icon`（`ui/weapon/<type>_icon.png`，缺失为 null）、`cost=6`、`group=""`。`weapon_type` 取值 AR/FT/GL/HG/MG/MT/RG/RL/SG/SMG/SR；本体 18 份取自同名商店卡，无商店卡的 aris/midori/momoi/yuzu 按武器表现（RG/SR/AR/GL，user 裁定）。合成卡 `group` 为空，`add_character` 必须跳过空串，否则写入 `PlayerData.group` 空项。
- SUPERSEDED / 已被替代: 2026-10-13 本轮同日的实现已被下方「武器类型可下拉+手输」条目替换——`_shop_weapon_icon` 已移除，`player.gd` 由 `@export_enum` 改 `PROPERTY_HINT_ENUM_SUGGESTION`，合成卡不再在扫描期解析图标而改为显示期解析。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-13

### [Mod] 武器类型可下拉+手输：全局注册表 + 商店显示期解析
- Evidence / 证据: `resources/player/player.gd`（`@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "AR,FT,GL,HG,MG,MT,RG,RL,SG,SMG,SR") var weapon_type`）；`script/mod_manager.gd`（`_weapon_types`/`_seed_weapon_types`/`register_weapon_type`/`get_weapon_type_name`/`get_weapon_type_icon`/`get_weapon_types`，`BUILTIN_WEAPON_TYPES`，`API_VERSION=2`）；`script/mod_api.gd`（`register_weapon_type`/`get_weapon_type_name`/`get_weapon_type_icon`，`VERSION=2`）；`ui/character_shop_card.gd:get_card`。
- Notes / 说明: ①「下拉 + 手输」用 Godot 原生 `PROPERTY_HINT_ENUM_SUGGESTION`（`@export_custom`）——`@export_enum` 只能下拉、不能输入（`core/object/property_info.h` 列有 `PROPERTY_HINT_ENUM_SUGGESTION`）。② `_scan_content()`（`mod_manager.gd:87`）早于 `_run_entry_scripts`（`:90`），mod 在 entry 里注册的类型扫描期不可见 → 合成商店卡只存 `weapon_type` code，名称/图标延迟到 `character_shop_card.get_card()` 用注册表解析（卡片自带非空优先）。③ `register_weapon_type` 的 code 仅允许字母/数字/下划线/短横线（防路径穿越），图标只从“已注册 `icon_path`”加载；内置图标目录固定 `res://ui/weapon/<code>_icon.png`。④ 未知类型：名称回退原 code、图标 null，不崩。⑤ 编辑器 inspection：`@export_custom` 不做语法校验，但 hint 简单无碍。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-13

### [Mod] 角色 id 必须 `<mod_id>_` 前缀；想「无后缀」只能把 mod_id 取短
- Evidence / 证据: `script/mod_manager.gd:930-937`（`if not id.begins_with(mod_id + "_"): return "缺少 mod 前缀..."`）
- Notes / 说明: 自动注册 id 一律要求以 `<mod_id>_` 开头，否则被拒、角色不出现（非致命：push_warning + 跳过）。若想让角色 id 无额外后缀（如 `foo_izzy`），须令 `mod_id=foo` + 角色 id=`foo_izzy`；`mod_id=foo_izzy` + 角色 id=`foo_izzy` 不合法。`overrides` 可绕过该前缀校验（`_validate_id` 开头 `if overrides.has(id): return ""`），但语义不符且丧失 reserved 冲突保护，勿用。
- Source / 来源: code + test
- Date / 日期: 2026-10-14

### [Mod] 复制本体角色场景做 mod 角色：删 `[gd_scene]` 的 uid，只改 3 处引用
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_izzy.tscn:1`（`[gd_scene format=3]` 去 uid）、`:4`（`player_card`→mod `.tres`）、`:7`（`ps_card`→mod PS `.tres`）、`:29`（PS 节点→mod `_ps.tscn`）；游戏进程实测 `get_characters()` 含该角色、`mounted=true`、无 `player_card 对齐` 告警。
- Notes / 说明: 场景 `uid` 全局唯一，复制必须删（编辑器重分配）；指向**新建** mod 资源的 `ext_resource` 只写 `path`（不写 uid），指向本体资源的保留原 uid/path。节点 `unique_id` 是场景内唯一，整树复制安全。PS 节点由 `script/player.gd:169-186` 按**方法名**扫描子节点定位 → 节点名可任意改（如 `MomoiPS`→`PS`）。
- Source / 来源: test
- Date / 日期: 2026-10-14

### [Mod] mod 源放项目根 `mods/` 时别用 `build_coop_mod.ps1`（会镜像自拷贝）
- Evidence / 证据: `mod_sdk/build_coop_mod.ps1:51-67`（`$mirror = <Project>/mods/<ModId>`；Source 与 mirror 同为项目根 `mods/<id>` 时 `Copy-Item` 自我复制报错）；`mod_sdk/build_local_mod.ps1`（PCKPacker 直打 + `-Install`）
- Notes / 说明: `build_coop_mod.ps1` 假设「源在 `mod_sdk/coop_mod/mods/`、镜像在项目根 `mods/`」两者不同；源若直接放项目根 `mods/`，Source==mirror → `.uid` 同步阶段自我复制报错。改用 `build_local_mod.ps1`（直接 `--script pack_mod.gd` 打 `mods/<id>/**`，无需工程副本/镜像），pck 输出 `mods/_build/`（落在 gitignore 的 `/mods/` 下，保持 git 干净）。边界：PCKPacker 原样打包**打不进 PNG 贴图**（运行时无导入器，需 `.ctex`）→ 自带贴图走「工程副本 + `setup_mod_project.ps1` + `build_mod.ps1`（ModPack 预设）」。
- Source / 来源: test
- Date / 日期: 2026-10-14

### [Tooling] 含中文的 `.ps1` 必须存为 UTF-8 **带 BOM**（PS 5.1 否则按 ANSI 解析）
- Evidence / 证据: `mod_sdk/build_local_mod.ps1` 无 BOM 时 `Write-Host "已生成：$pck（...）"` 的中文引号被 ANSI 撕裂 → `TerminatorExpectedAtEndOfString`；`mod_sdk/build_coop_mod.ps1`/`setup_mod_project.ps1` 均为 UTF-8 BOM。
- Notes / 说明: Windows PowerShell 5.1 读无 BOM 脚本按系统 ANSI(GBK)。写文件用 `[IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding($true)))` 生成 BOM。同理：从 PS 读含中文的 JSON 用 `[IO.File]::ReadAllText(path,[Text.Encoding]::UTF8)`，别用 `Get-Content`（默认 ANSI，会把合法 JSON 读坏报错）。
- Source / 来源: test
- Date / 日期: 2026-10-14

### [Editor] 在 `mods/` 下新增文件后，编辑器 Errors 面板可能残留 stale parse error（游戏进程正常）
- Evidence / 证据: 新增 mod 文件后编辑器报 `Function "_seed_weapon_types()" not found in base self`（`res://script/mod_manager.gd:86`），但磁盘 `mod_manager.gd:1184` 有该定义；从编辑器运行游戏时 `/root/ModManager` 存在、`doom_slayer_izzy` `mounted=true`、角色注册成功。
- Notes / 说明: 属编辑器脚本重载缓存滞后（与 AGENTS 所述新增 autoload 的静态分析滞后同类）；重启编辑器可清。判定以「磁盘 grep + 游戏日志/`game_eval`」为准，勿据编辑器残留报错否定改动。
- Source / 来源: test
- Date / 日期: 2026-10-14

### [Mod] 聊天窗释放鼠标须按「当前阶段」还原，不能写回过期快照
- Evidence / 证据: `mods/etn_coop/ui/coop_chat.gd` 与 `mod_sdk/coop_mod/mods/etn_coop/ui/coop_chat.gd`（`_acquire_controls` 记 `_prev_mouse_mode` + 新增 `_prev_overlay_active`；`_release_controls` 仅当 `_pointer_overlay_active()` 与捕获时相同才 `Input.mouse_mode = _prev_mouse_mode`；新增 `_game_over_active` 与 `_pointer_overlay_active()`）；阶段写指针者 `scenes/crosshair/crosshair.gd:33-39`（`round_upgrade`→VISIBLE、`round_start`→CONFINED_HIDDEN）、`ui/game_over_page.gd:105`（VISIBLE）、`scenes/manager/upgrade_manager.gd:60-62`。
- Notes / 说明: **现象**（user）：升级页（鼠标可见）里用聊天窗发送消息后鼠标被隐藏。**根因**：`_release_controls` 无条件写回**开聊瞬间**的快照 `_prev_mouse_mode`，而快照会随游戏阶段过期——游玩期开聊捕获 `CONFINED_HIDDEN`，随后回合结束、升级页由 `crosshair` 置 `VISIBLE`，发送时又写回过期的 `CONFINED_HIDDEN`；反向（升级页开聊 → 回到游玩）同理会写出错误值。**修法**：释放时仅当「当前是否处于可见指针覆盖层阶段」（`_upgrade_active`/`_game_over_active`）与捕获时一致，才写回快照；阶段已变则**不覆盖**（`crosshair`/结算页等当前持有者已写好正确模式）。纯游玩期发送仍还原为游玩捕获模式（隐藏），符合既有的「发送即释放、游玩态指针隐藏属预期」约定（见 2026-10-07 同主题条目）。不硬编码任何鼠标常量；两处副本同改。验证：`godot-ai_script_patch` 对镜像 `res://mods/etn_coop/ui/coop_chat.gd` 解析 `diagnostics=[]`（无语法错误），两副本 `MD5` 一致。
- Source / 来源: user + code
- Date / 日期: 2026-10-14

### [Relay] 可靠 WebSocket 连接不能在背压时跳整帧后继续工作
- Evidence / 证据: `mod_sdk/coop_mod/server/relay_server.py:175-202`；`mod_sdk/coop_mod/mods/etn_coop/net/coop_relay_peer.gd:268`；`docs/CODEBASE_AUDIT_20261018.md` AUD-NET-001。
- Notes / 说明: 中继首两次超水位直接跳帧，水位恢复即清计数，不关闭连接。控制帧与可靠 RPC 共用此路径，客户端没有额外重传。真实发送函数配合可控 transport 水位，已复现控制帧丢失、下一游戏包仍发送；不能把“慢端不阻塞广播”视为可靠性已保证。修法需有界排队或明确断连；当前尚未实施。
- Source / 来源: test
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-14 首次超水位改为明确断开慢端，保留非阻塞广播；2 项背压回归先红后绿，不再容忍跳帧。（来源：test）
- SUPERSEDED: 2026-10-14 进一步改为分级水位：软水位（256 KiB）给宽限（默认 5s）继续写可靠帧，硬水位（默认 4 MiB）或宽限超时再断开慢端；仍禁止跳帧。证据：`mod_sdk/coop_mod/server/relay_server.py:28-30,172-205`、`tests/test_relay_limits.py`。（来源：user + code）

### [Mod] 依赖校验必须覆盖冲突过滤后的最终集合
- Evidence / 证据: `script/mod_manager.gd:272-340`；本地审计记录（未入本次提交）；AUD-MOD-002。
- Notes / 说明: 缺依赖检查在 conflicts 之前，挂载失败传播无法覆盖排序阶段的冲突剔除。A/B 冲突、C 依赖 B、D 依赖 C 时，真实排序返回 `[a,c,d]`。最终集合需要满足依赖闭包，同时继续保留 `enabled` 为用户意图，不能借机恢复永久停用行为。
- Source / 来源: test
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-14 按拓扑顺序验证依赖已进入 kept，直接/传递依赖随冲突停用；用户启用意图保留，生命周期回归通过。（来源：test）

### [Mod] 安装清理与卸载递归的链接行为不同，字符串前缀不能证明删除边界
- Evidence / 证据: `script/mod_manager.gd:1262-1287`；`script/mod_installer.gd:124`；AUD-MOD-003。
- Notes / 说明: 安装器清理会检查链接，但卸载对 `current_is_dir()` 直接递归。Windows 隔离实验在 Mod 子目录创建 junction 指向 Mod 根外、同一实验根中的哨兵，真实卸载返回成功且删除外部哨兵。此结论需要已有本地链接，不表示 ZIPReader 会生成链接。后续统一清理时须保留“不跟随链接”原则，普通路径前缀检查不足以替代它。
- Source / 来源: test
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-14 卸载已在根/嵌套目录先检测链接，Windows 两类 junction 哨兵保留且隐藏目录可删除；不跟随链接的原则继续有效。（来源：test）

### [Save/Mod] 旧 Resource 存档迁移要保留对象身份，不能按文件名猜内容 ID
- Evidence / 证据: `script/scene_data_store.gd:18`、`script/Game.gd:250`；`tests/run_support_persistence_checks.py`。
- Notes / 说明: 支援真实 ID 与资源文件名可以不同；旧档所选资源与已购字典引用同一个 ext_resource。只在同步读档期间为明确缺失的 Mod 依赖提供临时 SupportCard 占位，便可按对象身份从已购字典 key 恢复真实 ID，再转 v3 纯 ID/LV/exp。加载后移除 ResourceFormatLoader，不污染普通资源缓存；未来版本与坏档保护保持。启停、旧备份、仅购买未选中支援及不同文件名均由真实 PCK 跨进程验证。
- Source / 来源: test
- Date / 日期: 2026-10-14

### [Coop] 同 poll 多端退出需同时处理底层 ENet 状态和 Relay 排队包
- Evidence / 证据: `net/coop_enet_peer.gd:48,75`、`net/coop_relay_peer.gd:139,227`（均位于 `mod_sdk/coop_mod/mods/etn_coop/`）；`tests/coop_recovery_checks.gd:_simultaneous_leave_case/_relay_queue_case`。
- Notes / 说明: 原生 ENet poll 发出断线信号时，其他底层 peer 可能已无通道但尚在 SceneMultiplayer 成员表，既有引擎成员广播与玩法 RPC 都会报 max channels: 0；汇总一次原生 poll 的事件并检查底层目标状态后转发可避免该路径。Relay 则须在移除 sender 时丢弃其已排队数据、禁止晚到数据自动重建身份，并让同 ID 重连先断后连；仅修复 getter 的 peek 顺序不足以解决此类报错。两类新增守卫先红后绿，全套 12 组与三组复跑严格通过，没有扩大日志豁免。
- Source / 来源: code | test
- Date / 日期: 2026-10-14


### [Relay] 准入时必须补齐最新成员，join_prepared 的快照可能漏掉并发 pending 客机
- Evidence / 证据: `mod_sdk/coop_mod/server/relay_server.py:441,465,490`、`mod_sdk/coop_mod/mods/etn_coop/net/coop_relay_peer.gd:233`；本地审计记录（未入本次提交） --case relay_join`
- Notes / 说明: 两端均 join 后再依次 ready，第二端的初始 peers 只有 host；第一端 ready 的公告不送 pending 第二端，第二端 ready 也不补第一端。未知 sender 拒收本身是正确边界，漏公告会让可靠数据被持续静默丢弃。真实三端回归首轮失败、单例复跑成功不能消除竞态；应修准入公告而非放宽未知数据接入。当前未修，见 AUD-NET-002。
- Source / 来源: test
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-14 服务端在 client_ready 准入前补发当前成员公告，并对重复 ready 幂等；确定性测试及真实三端重连通过。AUD-NET-002 resolved。来源：code | test。

### [Coop/Combat] 前置伤害修饰不能通过结算后 proc 补偿，必须进入本次命中的数值契约
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:2255,5823,6000,8548`、`script/health_component.gd:146-155`；诊断 `--case damage_wire`
- Notes / 说明: SDK 实际 wire roundtrip 丢失 damage_modifier（1→0），同一 base=10、×2 修饰从本地扣 20 变为权威扣 10；组件 damage_multiplier 也没有携带。host 抑制前置 proc，归属端回传事件在扣血之后，修改镜像不能改变本次权威 HP。旧「活对象信号迁移」只解决引用有效性，不证明 mint_chocolate_parfait 等增伤已跨端结算；COOP-008 当前未修。不能简单传 Callable 或放开 host 全局 proc。
- Source / 来源: test
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-14 新增前置阶段和 v5 resolved_damage 数值契约；真实 wire、Hina/Kotori/近战藏品、Mint 自管理子弹及独立部件双端检查通过。COOP-008 resolved；目标条件使用命中端快照。来源：code | test。
- SUPERSEDED: 2026-10-14 用户要求将尚未提交上游的本批协议变更统一为 v4，以上 v5 为调整前标记；数值契约保持。

### [Upgrade] 归零后只乘增长系数不能产生刷新增益，稀有度权重会被清零
- Evidence / 证据: `scenes/manager/upgrade_manager.gd:35,131,138,205,293`；诊断 `--case gameplay`
- Notes / 说明: refresh_mult 初始/选中复位为 0，*=1.1 后仍为 0；rare=2 权重乘它，真实刷新后约 0.01→0，建池排除。基准乘区与累计增益需分开考虑。health_percent 还使用 int/int，81/82 得到 0；当前低血量奖励又乘恒零倍率，此问题应在修刷新时一并覆盖。AUD-LOOT-001 当前未修，勿把观察型诊断当通过型守卫。
- Source / 来源: test
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-14 改为累计额外增益、总倍率保留基准 1；浮点血量比例同时修复。刷新/选择复位守卫通过，AUD-LOOT-001 resolved。来源：code | test。

### [Coop/Interpolation] 衰减速度必须积分成位移，v*t*damp 会让位置回退
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_snapshot_buffer.gd:124-130`；诊断 `--case snapshot`
- Notes / 说明: T=120ms、最新 x=10/vx=100，当前采样 10→12.25→13→12.25→10，且超过 T 后速度从 0 恢复为旧 100。公式 t*(1-t/T) 后半段减少，不能表示平滑停止；应积分速度并保持末端位置和零速度。AUD-NET-003 当前未修，玩家/敌人/召唤物 proxy 共用该缓冲。
- Source / 来源: test
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-14 使用衰减速度积分并保持末端位置/零速度，逐毫秒单调性与冻结守卫通过。AUD-NET-003 resolved。来源：code | test。


### [Coop/Equip] 跟随图标必须只占用所属玩家的一个 Follow 挂点
- Evidence / 证据: `script/equip_item.gd:79`、`scenes/update_item/mint_chocolate_parfait.gd:5`、`tests/coop_recovery_checks.gd:_damage_case`
- Notes / 说明: 联机镜像可能保留 Follow 组，旧 Mint 遍历所有空挂点会把同一节点重复 add_child，真实双端测试出现 already has a parent。Mint 改走通用 helper；helper 用所属玩家 is_ancestor_of 过滤，只占一个点后返回。数值回归必须保留严格原生错误检查，不能仅看 failures=0。
- Source / 来源: test
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-26 「只占一个点」的 `is_ancestor_of` 过滤同时切断了图标内置 Follow 链——图标挂在 `PlayerRoot` 下、不是玩家后代，于是第二件起静默不生成（见下方 `[Equip] 跟随图标是链表` 条目）。归属判定改为「玩家自身子树 + 本玩家图标链（`follow_owner` meta）」，联机镜像仍被排除；本条保留为修复前观察。来源：user + code + test。

### [UI/Mod] 已挂载不代表脚本入口已运行，兼容信息需区分最低本体版本与 API 要求
- Evidence / 证据: `script/mod_manager.gd:538,976`；`mod_sdk/README.md` §2。
- Notes / 说明: game_version 是最低本体版本声明，不足时只告警；api_version 超过本体支持版本时跳过 entry，但此前资源包可能已经 mounted=true，列表 error 也未因此写入错误。兼容 UI 不能仅凭 mounted 显示“完整运行正常”，也不能将这两类检查统一标为整包拒载。当前 list_mods 尚未公开版本要求与 entry 执行结果，新增详情须补相应数据契约。
- SUPERSEDED: 2026-10-18 `list_mods()` 现已返回 `game_version`/`game_version_ok`/`dependencies`/`overrides`/`replace_paths`/`adds`，详情页以「支持版本」展示最低支持本体版本并做兼容判定；entry 执行结果仍未单独暴露，UI 不把 `mounted` 写成 entry 已成功运行。（来源：code）
- Source / 来源: code
- Date / 日期: 2026-10-14

### [Mod/UI] 管理页分栏详情的数据与交互边界
- Evidence / 证据: `script/mod_manager.gd:list_mods/_content_counts/_manifest_array`；`script/mod_option.gd`（`_refresh`/`_group_key`/`_make_row`/`_update_detail`/`_update_restart_bar`/`_on_undo`/`_move_spacer_to`）；`ui/mod_option.tscn`（`Summary`/`RestartBar`/`ListPanel`/`DetailPanel`）。
- Notes / 说明: ① `list_mods()` 的兼容字段必须同时暴露声明值与判定结果（`game_version` + `game_version_ok`）；仅给声明值会让 UI 自行重复版本解析，且 `Game` 未就绪时容易误判。② 分组只影响展示：`_current_ids()` 只收 `is_row` 行，上下按钮/拖动按用户顺序写 `mods_order.json`，`set_order()` 的 `mods_changed` 会在拖动结束后重建列表并重新分组。③ 带分组头时 spacer 的 `get_index()` 含表头，拖动目标索引必须先按行计算、再按 spacer 是否位于目标前修正，否则会插到错误位置；`_cancel_drag()` 应恢复到 `_drag_origin_index`，不能使用当前 spacer 位置。④ 待重启是 UI 会话态：启停/排序可撤销到本次基线；导入/卸载不可逆（pck 运行期不可卸），仍计入待重启。⑤ “重启游戏”只能退出进程（`get_tree().quit()`），引擎运行期无法真正热重载 pck。⑥ 列表行与详情无图标时均显示名称首字符（中文首字、英文转大写，跳过空白/标点），不要用 mod id 代替显示名。⑦ 描述/详情 Label 自动翻译，mod 可用中文原句作翻译键。
- Source / 来源: code + test
- Date / 日期: 2026-10-18

- SUPERSEDED: 2026-10-18 上述②把「过滤表头后的显示顺序」等同于「用户顺序」的实现判断不成立，④的首次拖动撤销也缺少基线。现分别读取全局顺序与显示目标，仅移动所选 ID；首次拖动保存基线，刷新前取消拖动，待重启按净差异重算。35 项隔离断言通过，覆盖错误分组不改变无关冲突优先级、交错停用项、首次拖动/混合操作撤销、原地/取消拖动、空顺序配置、实际磁盘恢复与不可逆标记保留。此前「排序可撤销」只能作为设计意图，不能当作旧实现已正确的证明。稳定规则已上提 `SYSTEMS.md`「管理面板排序与状态修正」。（来源：code | test）
- Validation / 验证（2026-10-18）: 设置集成另有 45 项断言通过；旧本地测试仍检查 `ColorRect.scale.x`，与恢复原版后写 `size.x`（选中 114、悬停 9、收起 0）的动画不符，已仅在本地测试中修正断言。两项命令仍因既有 `godot_ai/runtime/game_helper.gd` 缺失及退出资源日志返回非零，未处理 `project.godot`。（来源：code | test）

### [Git] 本地忽略 `.import`，不提交 `.gitignore` 改动
- Evidence / 证据: `docs/CONVENTIONS.md` §6.1；本地 `.git/info/exclude` 的 `*.import` 与索引 `skip-worktree` 标记。
- Notes / 说明: 用户要求忽略 `.import` 且不提交 `.gitignore`。2026-10-14 已将 627 个 `.import` 改动及 `.gitignore` 从暂存区排除；972 个已跟踪 `.import` 用本地 `skip-worktree` 跳过，新文件用 `.git/info/exclude` 忽略，不删除文件或取消既有跟踪。后续暂存须继续排除 `.gitignore`。`skip-worktree` 只影响本地索引，未来上游若修改这些文件，同步前需按需清除标记并保留本地内容。
- Source / 来源: user
- Date / 日期: 2026-10-14

### [Localization] CSV 引号修复后须同时核验生成的 Translation 资源
- Evidence / 证据: `ETN_item_localization.csv`；`ETN_item_localization.en.translation`、`ETN_item_localization.vi_VN.translation`；Godot 4.7 隔离工程逐 key 对照 CSV，结果 `TRANSLATION_CHECK failures=0 changes=4`。
- Notes / 说明: 上游 CSV 已修正字段内双引号，但既有英/越 Translation 仍缺少部分引号；当前重新导入结果补回 `samuela_the_beyond_description` 的英/越引号及 `jellies_cushion_description`、`sakura_daifuku_description` 的越南语引号。SUPERSEDED: 2026-10-14 先前「对齐上游后本分支不再改动 `.translation`」仅描述当时提交范围，本次分类提交纳入已逐项验证的两份生成资源；CSV 未改动。
- Source / 来源: test
- Date / 日期: 2026-10-14

### [Version] 本体与联机 Mod 发布版本回滚，格式版本保留
- Evidence / 证据: `script/Game.gd:13`；`mod_sdk/coop_mod/mods/etn_coop/mod.json`、`net/coop_net.gd:32-33`；`script/scene_data.gd:7`。
- Notes / 说明: 用户明确回滚本体与联机 Mod 的发布版本：`v0.5.1.4` → `v0.5.1.3`、`0.1.12` → `0.1.10`，manifest 的最低本体版本声明同步恢复为上游原值 `v0.5.1.2-test`。协议 v5、存档格式 v3 和 Android 模板版本保留，既有功能修复不回滚；entry 继续按前置伤害信号是否存在进行能力检查。后续不能仅凭发布版本号推断是否具备本轮新接口。
- Source / 来源: user
- Date / 日期: 2026-10-14
- SUPERSEDED: 2026-10-14 用户确认本批变更尚未提交上游，联机协议由 v5 统一调整为 v4；存档格式 v3 及其他版本约定不变。
- SUPERSEDED: 2026-10-14 用户改定本体发布版本为 `v0.5.1.4`（导出文件名同步 0.5.1.4），联机 Mod 仍 `0.1.10`；本条回滚结论仅适用于当时。（来源：user）
- SUPERSEDED: 2026-10-20 用户改定联机 Mod 发布版本为 `0.1.11`，manifest 最低本体版本提升为 `v0.5.1.4`；本条最低版本结论不再适用。（来源：user）

### [Coop/Version] 尚未提交上游的联机协议变更统一为 v4
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:32`（`PROTOCOL_VERSION = 4`）；上游基线 `78ed5ad` 同字段为 3。
- Notes / 说明: 用户说明本批变更尚未提交上游，要求协议从 v5 调整为 v4，将新增身份恢复、金币倍率与前置伤害等契约变化合并为相对上游 v3 的一次升级。发布版本继续保持本体 `v0.5.1.3` / 联机 Mod `0.1.10`，存档格式 v3 保留；联机双方需使用本批一致的新构建。
- Source / 来源: user
- Date / 日期: 2026-10-14

### [Git/Scope] 本批重新提交仅包含本体与官方联机修复
- Evidence / 证据: 本轮提交清单；`tests/isolated_godot.py`、`tests/export_boundary_helpers.py`。
- Notes / 说明: 用户明确排除 EasyTier 联机、UI 设计草案及开发配置。开发配置范围已确认包含 `.gitattributes`、`android/.build_version`、`.repository-audit/`，以及既有 `.gitignore`、`project.godot`、`.import`；`export_presets.cfg` 的发行包隔离修复保留。被排除内容与原提交在本地备份保留，公共回归工具已从拓展测试中拆出，永久守卫不再依赖本地审计工具状态。本体/官方联机发布版本仍为 `v0.5.1.3` / `0.1.10`，协议为 v4。
- Source / 来源: user
- Date / 日期: 2026-10-14
- Implementation / 实现: CSV 的 CRLF 规则移到本地 `.git/info/attributes`；验证目录按项目约定校准行尾，本次不改动 CSV 源内容或提交开发配置。
- Validation / 验证: 独立候选工作区通过 16 项 Python 单元测试、23 项设置检查、7 组存档恢复、4 组支援跨进程迁移，以及安装、生命周期、伤害契约、5 组联机场景、刷新/外推和实际 PCK 导出隔离检查。

### [Git/Scope] 官方联机通用接入应提交，独立附属包不提交
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_extensions.gd`、`net/coop_net.gd`、`ui/coop_menu.gd`；`docs/COOP_EXTENSION_API.md`。
- Notes / 说明: 用户再次明确：涉及官方联机 Mod 的代码应提交，独立 EasyTier 附属包不要提交。官方通用提供者注册、菜单页签、状态栏及生命周期接入属于官方代码；附属包源码、工具清单、构建/下载脚本及附属专用测试继续保留本地。UI 设计草案与开发配置仍排除。
- SUPERSEDED: 2026-10-14 上轮把官方通用拓展接入一并排除的执行范围过宽，本轮补交官方部分；前条记录的其他提交边界不变。
- Validation / 验证: 仅安装官方源码 PCK，通用提供者的 21 项生命周期契约和 17 项实际菜单检查通过；未安装任何附属 Mod。
- Source / 来源: user
- Date / 日期: 2026-10-14

### [Upgrade] 最高稀有度由回合曲线主导、刷新额外抬升；防御低血加成不随拥有数量归零
- Evidence / 证据: `scenes/manager/upgrade_manager.tscn`（`round_weight_curve_3` 0.01→0.55，`curve1` 1→0.35，`curve2` 0.05→0.75）；`scenes/manager/upgrade_manager.gd:64-70`（回合基准权重）、`:132/139`（`refresh_mult=(1+x)*1.1-1`，稀有档×`(1+refresh_mult)`）、`:294`（`health_percent` 浮点）；`scenes/manager/item_weight_manager.gd:52`（`DEFENSE` 标签权重 0）、`:150-153`（`max(0, defense_bonus - defense_tag_quantity*0.3)` + 低血项）。
- Notes / 说明: 用户裁定**升级权重按 PR 保留**。最高稀有度「早期回合抽不到、随回合推进才给权重」由 `round_weight_curve_3`（回合曲线）承担，PR 未改回合边界路径（`round_weight_upgrade`）；PR 只把刷新路径从 `curve3 * refresh_mult`（`refresh_mult` 初值 0、`*=1.1` 恒 0 → 稀有档归零）改为 `curve3 * (1 + refresh_mult)`，故刷新次数也会额外抬升稀有档（且无上限）。防御类由 `max(0, defense_bonus - 0.3×拥有数)` 随获取数量衰减回基准；PR 未改 `item_weight_manager.gd`（与 main 零差异），仅令低血旁路 `(2+now_round)*refresh_mult` 从恒 0 变为生效——该项是加法且与拥有数量无关。
- Source / 来源: user
- Date / 日期: 2026-10-14

### [Coop] 命中预测二次乘算与强制断线重复信号（PR #7 合并后修复）
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:2041-2043,2251-2253,5831-5836`（`cfg.resolved_damage` 已含 `global_hurt_damage`+前置修饰）、`:8626-8633`（`_get_predicted_enemy_damage` 再乘一次 `global_hurt_damage`）、`:8658-8666`（`_predict_enemy_death`）；`mod_sdk/coop_mod/mods/etn_coop/net/coop_enet_peer.gd:38-46,127-130`（`_disconnect_peer(force=true)` 手动调用 + 原生 `peer_disconnected` 各排一次事件）；`script/health_component.gd:213-240`。
- Notes / 说明: ① 客机命中预测把已求值的 `resolved_damage` 又乘一次 `global_hurt_damage` → 镜像血条/致死预测偏大、与飘字不一致；改为 `_predict_enemy_death` 直接取 `maxi(0, damage)`（入参已是最终值）。② ENet 强制断开时断线事件在同一 poll 入队两次 → `peer_disconnected` 双发；`_poll` 断线分支先判 `_admitted.has(id)`、出表即视为重复跳过。③ `resolve_damage` 补 `damage_data==null or stats==null` 空守卫，`_resolve_damage` 对 `owner.get_path()` 判空，防 RPC 路径崩溃。
- Source / 来源: user + code
- Date / 日期: 2026-10-14

### [Git/Scope] 当前分支仅保留远端道具动态表现同步与重复外观修复
- Evidence / 证据: 用户 2026-10-14 明确要求；本地备份分支 `backup/before-items-only-20261014`；`tests/coop_item_visual_checks.gd`。
- Notes / 说明: 本轮以 `upstream/main` 的 `78ed5ad` 重建分支，只保留菜刀瞄准回填、内部道具显示快照/驱动、外观去重/补建/重建、必要的道具缓存迁移、协议 v4 及专用回归和说明。此前本体存档、伤害、Mod 生命周期、设置页签、中继加固、通用联机拓展及分享标签等改动保存在备份分支，不属于本分支交付范围；主线已有内容保留。
- Source / 来源: user
- Date / 日期: 2026-10-14

### [Coop/Visual] 纯视觉道具动画必须隔离资源并过滤玩法轨道
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_item_visuals.gd:_prepare_visual_resources`、`coop_visual_driver.gd:apply_state`；`tests/coop_item_visual_checks.gd:_item_visual_case`。
- Notes / 说明: 原场景动画可能重新启用碰撞；只在生成时禁用形状不足以隔离远端伤害。复制材质与动画库后过滤方法/音频及碰撞/计时器/Label 轨道，避免 seek 改动拥有者的共享材质。远端绕行和护盾/触发动画来自拥有者快照，不能依赖已剥离的 EquipItem 脚本。
- Source / 来源: code
- Date / 日期: 2026-10-14

### [Combat] `PlayerRef.ensure` 形参不能用强类型 `Node`：已释放实例会在入参检查处就崩
- Evidence / 证据: `script/player_ref.gd:27`（`static func ensure(from: Node, cached: Variant)`）；崩溃点 `script/summoned.gd:38`（`player = PlayerRef.ensure(self, player)`），经 `script/summoned_follower.gd:146 get_direction_to_player()` 触发，报 `MobSummoned._ensure_player: Invalid type in function 'ensure' in base 'GDScript'. The Object-derived class of argument 2 (previously freed) is not a subclass of the expected argument class.`，游戏开局即 `game_status.status=break`（`can_debug=false`，无法继续）。
- Notes / 说明: `PlayerRef` 收口（2026-10-09 条目）只防了「读属性时 previously freed」，漏了「把已释放实例当实参传给强类型形参」——Godot 在**进入函数前的入参类型检查**就抛错，函数体内的 `is_instance_valid(cached)` 根本执行不到。修法：`cached` 改弱类型 `Variant`，但**必须先判 `is_instance_valid` 再判类型**——写成 `cached is Node and is_instance_valid(cached)` 时，`cached is Node` 会在已释放实例上先抛 `Left operand of 'is' is a previously freed instance.`，函数体内的判定同样执行不到；正确顺序为 `is_instance_valid(cached) and cached is Node and cached.is_inside_tree()`（`is_instance_valid` 对已释放实例安全），一处收口即覆盖全部 65 处调用点。通用：任何「接收可失效对象缓存」的工具函数，形参都别用具体 Object 类型，一律收成 `Variant` 再运行期校验。
- Source / 来源: user + code
- Date / 日期: 2026-10-14

### [Render] 2D 物理插值改为设置项（默认关）；逐帧驱动视觉须关插值（`3e21ac0` 遗漏项）
- Evidence / 证据: `script/Game.gd`（`var physics_interp: bool = false`、`apply_physics_interp()` 运行期设 `get_tree().physics_interpolation`；`config.ini` 的 `[game] physics_interp`）；`ui/game_option.tscn` / `script/game_option.gd`（Graphics 页开关 `%PhysicsInterp`，移动端隐藏）；`scenes/crosshair/crosshair.gd:_ready`、`scenes/player/momoi/momoi_ex_range.gd:_ready`、`scenes/manager/interact_prompt.gd:_ready`、`scenes/player_support/serina/serina_as.gd:_on_ready`（`aura`）、`scenes/update_item/life_jacket.gd:_on_equip`（`Node2D2`）均设 `physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF`。
- Notes / 说明: ① `3e21ac0` 全局开启物理插值后，凡「由 `_process` 每帧写自身 transform」的视觉节点都须关插值（`CONVENTIONS.md:102` 规则①），否则插值会在物理 tick 间把它渲染在上一次位置 → 准星/指示器滞后、与真实瞄准点错位；该提交漏了准星、Momoi EX 指示器、交互气泡、serina aura、救生衣护盾。② `SceneTree.physics_interpolation` 可在运行期安全赋值，故做成 Graphics 设置项、默认关（迁移期仍可能有个别视觉错位），无需重启；用户 2026-10-14 裁定默认关。
- Source / 来源: user + code
- Date / 日期: 2026-10-14

### [Render] 物理插值开启时射击特效“频闪”——调查结论（暂不修，保留开关）
- Evidence / 证据: 现象（user）：开插值后玩家/炮塔开火时枪口火焰、子弹烟、子弹“频闪（一闪一闪）/偏移”，关闭插值即消失。尝试 B（射击栈 FX 根 `physics_interpolation_mode=OFF` + `turret_summoned._shoot_bullet` 由 `call_deferred` 改物理 tick 内直接调用）**实测无效**；未验证 A（射击栈 `GPUParticles2D` 转 `CPUParticles2D`）。Godot 4.7 文档：2D 物理插值只支持 `CPUParticles2D`、GPU 粒子不插值；物理 tick 外写被插值对象 transform 会 jitter。
- Notes / 说明: 根因**未定位**。处理=保留 `Game.physics_interp` 设置项（默认关，Graphics 页 `RowPhysicsInterp` 可开，见 `9ffece1`），由玩家自行取舍；后续若要根治，优先评估 A（转 `CPUParticles2D`，射击栈粒子量小、代价可忽略）。**勿重复 B**。
- Source / 来源: user + code
- Date / 日期: 2026-10-14

### [Coop/Visual] 远端瞄准必须与位置共用插值时间
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_snapshot_buffer.gd:85`、`coop_player_proxy.gd:170`；`tests/coop_item_visual_checks.gd:_knife_smoothness_probe`；用户 2026-10-15 反馈另一客户端菜刀卡顿。
- Notes / 说明: 用户确认症状为「菜刀移动或挥砍画面跳动，但角色移动正常」。静态方向检查通过不能证明连续转向平滑。已提交版本在双进程 LAN、60 FPS 连续扫动准星时，远端菜刀 75% 帧保持不动，而拥有者持续转动；原因是镜像准星只在收包时回填。瞄准点与位置一起入缓冲并按同一时间采样后，镜像准星和身体/武器统一读取采样值，避免位置滞后但瞄准超前。世界原点也是有效目标，不能用 `Vector2.ZERO` 作为未初始化哨兵。已有在制插值只完成入缓冲、未接回表现时，远端菜刀会完全停止转向，故回归必须覆盖实际镜像道具驱动。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-15

### [Coop/Damage] 命中伤害数字不能用目标 HP 差替代
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_server_enemy_hit`、`_get_predicted_enemy_damage`、`_predict_enemy_death`；`script/health_component.gd:_take_damage_internal`；`tests/coop_knife_damage_checks.gd`。
- Notes / 说明: 用户确认「客机玩家的菜刀，同次命中的伤害数字在主机与客机视角不同」。双端回归复现：减伤目标主机 `45`/客机 `22`，易伤目标主机 `45`/客机 `90`，斩杀主机 `50`/客机 `99999`。预测遗漏 TRUE_DAMAGE 且血条路径重复乘承伤倍率；主机以 HP 差作为飘字又截断了过量伤害。统一从真实结算取得命中数值、保留有效扣血记分后，两端数字一致。沙袋回血经 `Enemy._on_is_dead → on_dead.call_deferred()` 发生，回归若跨帧取 HP 差会误把回血计入同次命中。契约已上提 `SYSTEMS.md` §2.3。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-15

### [Coop/Integration] PR #9 以最新主线求值契约为准，移除重复预测修复
- Evidence / 证据: `upstream/main@0b7e446`；主线提交 `7cc6cc3`、`8a992ff`、`7dd2470`；`coop_net.gd:_prepare_enemy_hit`、`_server_enemy_hit`；`coop_snapshot_buffer.gd:sample`。
- Notes / 说明: 核对主线后确认：主线已统一 `resolve_damage` 与 `resolved_damage`、支持真实伤害并修正预测二次乘算。本分支旧版数值修复与其重叠，合并时沿用主线；新增差异仅保留瞄准插值与主机命中数字取值，不恢复旧预测助手。快照欠载外推沿用主线的积分位移，追加瞄准目标保持。上条菜刀数值复现描述针对更新主线前的旧分支，不能当作最新主线仍存在全部问题的证据。
- Validation / 验证: 对齐主线后的 LAN/Relay 道具视觉及菜刀伤害双端回归均通过；主线伤害契约断言 `DAMAGE_CONTRACT_RESULT failures=0`，本机只按既有道具 runner 精确豁免缺失 godot_ai 的三条日志与退出资源计数。
- Source / 来源: code + test
- Date / 日期: 2026-10-15

### [Mod/UI] 旧 `replace_files` 覆盖包会把新版 `ui/option_button.tscn` 打回无 `Label` 版本 → 设置页内置页签文字全空、只剩 COOP
- Evidence / 证据: 本机 `user://mods/etn_coop/mod.json`（`"name":"ETN Coop (skeleton)"`、`"replace_files":true`、`replace_paths:["res://ui/round_timer.gd","res://scenes/item/pyroxenes.gd"]`）；`logs/ETN_debug2026-10-16T01.54.55.log` 的 `[ModManager] etn_coop 使用 replace_files 覆盖本体文件`；安装包 `etn_coop.pck` 目录表除 `mods/etn_coop/**` 外还含 `ui/option_button.tscn`、`script/option_button.gd`、`ui/option_toggle.tscn`、`script/ScrollBox.gd`、`script/Game.gd`、`script/extension_hooks.gd` 等本体文件；该 pck 内 `ui/option_button.tscn` 节点仅 `Game/Node2D/ColorRect/AnimationPlayer`（**无 `Label`**），而现行 `ui/option_button.tscn:261` 有 `Label`、`script/option_button.gd:5` 的 `@export var text` 把标题写入该 `Label`。
- Notes / 说明: `ui/option_button.tscn` 本是 `coop_menu.tscn`（覆盖层页签）的依赖，`ModPackReplace` 预设 `export_filter="resources"` 会连带导出依赖，被 `replace_files=true` 一并覆盖到用户机 → 新版本体 UI 被旧快照回退。本体 `ui/option.tscn` 仍实例化 3 个内置页签并设 `text="GAME"/"CONTROLS"/"MOD"`，但旧组件无 `Label`，文字无处可写 → 内置页签渲染为空白；只有 mod 自建 COOP 页签（自带 `Label`）可见，表现为「option 里只剩 COOP」。根源是覆盖型打包把本体依赖当覆盖文件（同类事故见本文件 2084/2213）。修复=删除旧安装目录 + 用当前源码重打（`mod_sdk/build_coop_mod.ps1`，源码 `mod.json` 已去 `replace_files`，走 `pack_mod.gd` 的 PCKPacker 路线；新包 87 文件、目录表仅 `mods/etn_coop/**`、无本体覆盖）。实测（`game_eval` 实例化 `ui/option.tscn`）：四页签 `option_game=GAME / option_controls=CONTROLS / option_mod=MOD / option_coop=COOP` 全部有文字。注意编辑器下 `res://mods/etn_coop/` 镜像会遮蔽 pck，镜像仍为旧实现（`mod.json` 带 `replace_files`、entry 手搓额外 `Label`），与运行期 pck 不同源，需另行同步。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [Mod] replace_files 挂载前目录审计：未声明本体覆盖降级为不覆盖
- Evidence / 证据: `script/pck_directory.gd:list_paths`（只读解析 PCK v4 目录表，校验 magic/version/flags/dir_offset，异常返回 `null`）；`script/mod_manager.gd:_mount_one`（`replace_files` 分支调 `_audit_replace`，未声明则置 `replace_files=false` + `push_error`）、`_audit_replace`/`_covered`。
- Notes / 说明: 承接同日「旧覆盖包打回本体 UI」事故，加运行期守卫：`replace_files=true` 的包挂载前核对目录表，`res://mods/<id>/` 之外且未在 `manifest.replace_paths` 声明的路径判为未声明覆盖 → 降级挂载（mod 内容照常加载、本体零覆盖）；已声明则保留 `replace_files=true` 放行。匹配含 `<decl>.` 前缀（覆盖 `.gdc/.remap/.import` 边车），避免精确匹配误判。目录无法解析（非 v4/目录加密/损坏）时跳过守卫不误拦。**仅写日志**，不改 MOD 管理页。隔离 user:// 实测三情形：坏包(未声明)→降级、无 `replace_files`→不动作、全量声明→放行。
- Source / 来源: code + test
- Date / 日期: 2026-10-16

### [Mod/VFX] IZZY 裁决处决 AoE 改「来源侧 Area2D + `hit_received`」，并加红色冲击波
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd:456`（`_aoe_execute` 用 `$AoEHitBox` 圆形 Area2D + `get_overlapping_areas()`）、`:494`（`_spawn_shockwave` 挂 `SELayer`）；`mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.tscn`（`AoEHitBox`：`collision_layer=0`/`collision_mask=16384`/`monitorable=false`/`monitoring=false`，`CircleShape2D radius=80`）；`mods/doom_slayer_izzy/vfx/doom_shockwave.tscn`+`.gd`；`script/hit_box.gd:27`（`ENEMY_HURTBOX_LAYER=16384`）、`script/hurt_box.gd:39`（目标侧只认 `HitBox`）、`script/health_component.gd:21`（`hit_received`→`take_damage`）。
- Notes / 说明: 原 `_aoe_execute` 是 `get_nodes_in_group("Enemy")` 手动距离扫描 + 直接 `health_component.take_damage`，伤害类型 `EXPLOSION_DAMAGE`。改为来源侧 Area2D（与近战 `_swing` 同路径）：AoE 检测敌方 `HurtBox`（层 16384）并 `hit_received.emit`，伤害因此走标准管线（护甲/加成/无敌帧）且类型改 `MELEE_DAMAGE`。要点：①AoE 的 Area2D 必须 `monitorable=false` 且层=0，否则会被敌方 HurtBox 当入射 HitBox 触发误命中；②切换 `monitoring`/`shape.disabled` 后要 `await get_tree().physics_frame`（这里等 2 帧）重叠表才刷新，`get_overlapping_areas()` 才读得到；③过滤取 `a.get_parent()`（HurtBox 的父即敌人实体）判 `EnemyPart`/`is_idle`，因为 `EnemyPart` 也有同层 HurtBox；④已处决目标同帧 HurtBox 可能仍在，用 `ent == center` 排除。冲击波用本体 `shaders/shock_wave_2.gdshader` 的 ColorRect 环：环 RGB = `ColorRect.color`，且**环仅在 `size > thickness` 时显形**（`mask` 公式所致），故 `thickness` 要设细值（0.05→0.02）而非 0.6→0，环才由小到大可见；半径按 `size(0..0.5) × 矩形边长` 计，取 160px 矩形 → 0.5 即半径 80、对齐 AoE。特效一次性，播完 `queue_free`（本体 `range_explosion` 不自动回收）。另：该 AoE **命中至少一个敌人时播一次 `HurtSounds2`**（`hit_any` 布尔，口径同 `_crucible3_tick:337-339`；只命中被处决目标时因 `ent == center` 排除而不响——处决本身已有 `execute_sounds`）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [Mod/Audio] 替换 mod BGM 资源后裁决 BGM 静默不出：`load()` 返回 null 被 `_bgm_enter` 静默早退 + 未重启/重导入
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd:88`（旧代码 `if intro == null: return`，在 `SoundManager.bgm_fade_out`/`play_bgm` 之前 → 本体 BGM 一秒不断）；`mods/doom_slayer_izzy/script/doom_audio.gd:22-37`（旧 `load_stream` 失败无任何告警）；修复后实测 `BGMCHECK intro_null=false intro_len=9.24 loop_null=false loop_len=59.16`、`LOOPMODE=1 loop_end=2839679`，`_bgm_enter` 后 `ENTER@3.5 playing=true db=0.0 len=9.24`→`ENTER@12 len=59.16 loop=true`。
- Notes / 说明: 症状「进裁决 DOOM BGM 完全不响、本体 BGM 一秒不断、无淡出切换」= `_bgm_enter` 在动 BGM 前 early return，唯一路径是 `intro == null`（`bgm_intro()` 加载失败）。触发条件：**编辑器内运行 + 替换了 `res://mods/<id>/BGM/*.wav` + 未重启 Godot / 未 reimport** → 该资源的导入缓存/引用未复位，`load()` 拿不到新文件。要点：①编辑器内联调时 mod 源（`res://mods/<id>/`）优先于 `user://mods` 的 pck（`mod_manager.gd:570` `load_resource_pack(pck, replace_files=false)` → 项目文件优先），所以**换 BGM 不必重打 pck，但必须让 Godot 重新导入**（重开编辑器或 `filesystem reimport`）。②失败要**告警**，不要静默 return，否则只表现为「没声音」。③`_bgm_enter` 切 loop 曾用 `await SoundManager.bgm_player.finished`：本体任何换歌（`cut_finish`→`bgm_loop_play`；捡紫水晶 `main.gd:33`→`_on_bgm_timer_timeout`；boss）只要在 intro 期间换掉 `bgm_player.stream`，`finished` 就**永不触发**、loop 永不播 → 改用 `create_timer(intro.get_length(), true, false, true)`（`ignore_time_scale=true`，避免处决慢放拉伸计时）+ `_bgm_gen` 守卫。④`bgm_loop()` 旧版 `loop_end = data.size()/(2*ch)` 在 QOA（`compress/mode=2`）下用的是**压缩字节**，会把 59.16s 的循环截成 ~11.95s；应直接信任导入的 `edit/loop_mode=2`（本次实测 `loop_end=2839679` 即完整），仅在导入未设循环时兜底且用 `get_length()*mix_rate` 算帧数。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [Mod/Camera] 处决镜头倾斜改 15°、命中震屏加强且随连击档位递增（震屏互斥，勿叠加第二个）
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd:44`（`EXEC_TILT := 0.261799`）、`:191`（`_cam_execute` 用 `EXEC_TILT * ±1`）；`mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd:276`（`apply_execution_camera` → `emit_shake_screen(8 + tier, 55.0 + 10.0 * tier, 0.03)`）、`:274-275`；`scenes/game_camera/gamecamera.gd:71-89`（`shake_screen(length, shake_range, freq)` = length 次、每次 ±range 像素随机、freq 秒补间）、`:76`（`on_shake` 互斥）。
- Notes / 说明: 处决**命中**震屏走既有 `apply_execution_camera`（`_execute:429` 对**普通+裁决处决都调**），故「加强」= 直接改该处参数而非再 `emit_shake_screen` 一次 —— 因 `gamecamera.gd:76` 的 `on_shake` 同一时刻只跑一个震屏，后发的会被忽略，新增会把 `apply_execution_camera` 那次吞掉。`EXEC_TILT` 由 `0.07`(≈4°) 改 `0.261799`(15°=π/12，与 `HELD_ROT` 同值)，普通/裁决共用 `_cam_execute` 故都生效。实测 `get_script_constant_map()`：`EXEC_TILT=0.261799 deg≈15.000`。`emit_shake_screen` 参数含义易误读：第 1 参是**次数**（非时长）、第 3 参是每步补间秒数。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [Mod/Audio] 调整个别 SFX 音量：mod SFX 是各自 AudioStreamPlayer，只能改节点的 `volume_db`
- Evidence / 证据: `mods/doom_slayer_izzy/script/doom_audio.gd:16-20`（`SFX_VOLUME_DB` 增益表）、`:60-80`（`register_sfx` 新建/已存在都设 `volume_db`）；`scenes/manager/SoundManager.gd:38-42`（`play_sfx(name)` 仅 `$SFX/<name>.play()`，无音量参数）。实测 `SFXVOL crucible_sword_attack db=6.0 / crucible_sword_start db=6.0 / execute_sounds db=0.0`。
- Notes / 说明: mod 音效经 `DOOM_AUDIO.register_sfx` 注册为 `SoundManager/SFX/<name>` 的独立 `AudioStreamPlayer`（`bus="SFX"`）。`play_sfx` 没有音量参数、WAV 导入也无音量项，所以调音量 = 改该节点 `volume_db`（`SFX_VOLUME_DB` 表，未列出为 0）。注意「已存在则跳过」分支**也要同步 `volume_db`**，否则复用旧节点时改动不生效（本次已处理）。只对 mod 自带音有效；本体音（如 `Swing1`/`HurtSounds2`）不在此表内、改不到。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [Mod/SFX] 裁决处决起手补放挥砍音 `crucible_sword_attack`
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd:414-415`（`_execute` 内 `if crucible_exec: SoundManager.play_sfx("crucible_sword_attack")`）；`:412`（动画 `play(anim)` 之后）、`:448`（`_kill` 命中时的 `execute_sounds` 不变）。实测 `SFX/crucible_sword_attack` 存在、`db=6.0`、可 `play()`。
- Notes / 说明: 裁决处决此前只有命中音（`execute_sounds`），无挥舞音；补上与裁决挥舞同源的 `crucible_sword_attack`，**仅裁决处决、起手播放一次**（`crucible_exec` 分支），普通处决不补。音量沿用 `SFX_VOLUME_DB`(+6 dB)。判定标志 `crucible_exec` 在 `_execute:401` 已算好，复用之。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [Mod/Glory] 「可处决」概率固定为 60%（原 25%+5%×PS等级）
- Evidence / 证据: `mods/doom_slayer_izzy/script/glory_manager.gd:17-18`（`BASE_CHANCE := 60.0`、`CHANCE_PER_PS := 0.0`）、`:226-227`（`_chance() = BASE_CHANCE + CHANCE_PER_PS * _ps_level()`）。实测运行时 `_chance()=60.0`、`BASE_CHANCE=60.0 CHANCE_PER_PS=0.0`。
- Notes / 说明: 由「25/30/35/40%（T0–T3）」改为**恒 60%**（把 PS 档位增量置 0，保留公式结构便于回改）。该概率仅在**致死命中**时滚动（`try_stagger:185-206`），且受 `MAX_EXEC=3`、`CD_MS=2000`、非 BOSS/EnemyPart、需有描边材质等门控；敌人不会出生即可处决（除非自带 `ds_executable` buff，走 `_process:41-47`）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16
- SUPERSEDED: 2026-10-25 取消生成冷却 `CD_MS`，`try_stagger()` 只剩 `MAX_EXEC=3` 的并发上限作为节奏闸门；概率仍恒 60%，其余门控（致死命中 / 非 BOSS·EnemyPart / 描边材质 / 联机 host 权威）不变。（来源：user）

### [Mod/PS] IZZY 裁决三段倍率按 PS 等级查表 + T2 挥砍 hitbox×2 + T3 子弹命中回能/计量
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd:62`（`COMBO_MULT := [[2,2,3],[3,3,4],[3,4,5],[4,5,6]]`）、`:252`（`_tier()=clampi(now_t,0,3)`）、`:265`（第1/2段 `dmg=base*COMBO_MULT[_tier()][idx]`）、`:309`（第3段 `base=kick*global*COMBO_MULT[_tier()][2]`，`tick=base*0.4`×4）、`:368-370`（`_apply_hitbox`：`_tier()>=2` 时 `_shapes[idx].radius/height×2`）；`mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd:42`（连接 `GameEvents.player_bullet_hit_enemy`）、`:202-208`（handler）。实测：`COMBO_MULT` 正确、`hitbox@T2 r=48/h=156`（×2）、`hitbox@T1 r=24/h=78`、`hook_connected=true`、非裁决期 `now_t=3` 手动 emit 后 `meter=4.0`（=T3 上限 400×1%）。
- Notes / 说明: 三段倍率改为按 `now_t` 查表（T3=原 4/5/6，低阶更低，属「基础调低由升级补回」的设计）；第1/2段取 `[tier][0/1]`，第3段(投掷)取 `[tier][2]`。T2 起**只放大挥砍 capsule**（第3段判定 `CRUCIBLE3_HIT_RANGE=120`、处决 AoE `80` 不变；普通近战走 `_default_shape` 不受影响）——在 `_apply_hitbox` 里改 `_shapes[idx]` 的 `radius/height`，每次挥砍按当前 tier 重算。T3 起子弹命中：**裁决期回能量、非裁决期回计量条**（各 `max_meter()*1%`，不设限）；用本体 `GameEvents.player_bullet_hit_enemy`（`GameEvents.gd:132`，由 `player_bullet.gd:87` 经 `player.gd:480-481 apply_penetrate_dealt` 触发，霰弹多弹丸=多次）。注意 `add_meter` 满会 `activate_crucible()`，故子弹命中可把计量打满自动进裁决；`add_energy`/`add_meter` 各自内部按 `crucible` 状态门控。文案（PS 卡 `t_level`）本次未做。另：**T2 起每次处决叠 2 层 combo**（T0/T1 +1）；`add_combo(units:=1)` 加层数、`add_execution_combo()` 封装 `2 if now_t>=2 else 1`，`melee.gd:449` 改调 `add_execution_combo()`。实测 `now_t` T1/T2/T3 调一次后 `combo=1/2/2`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16
- SUPERSEDED: 2026-10-16 上条「T2 起放大挥砍 capsule」已改为 **T1 起**（`melee.gd:368` `_tier()>=1`）；文案与弹匣封顶见下条。

### [Mod/PS] IZZY：判定扩大改到 T1；弹匣上限封顶 2（参考 tsurugi）；PS 文案注册(zh_CN+en)
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd:368`（`var s := 2.0 if _tier() >= 1 else 1.0`）；`mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd`（`_ready` 内 `PlayerData.set_player.connect(_apply_ammo_cap)` + `PlayerData.max_ammo_value = 2`；`_apply_ammo_cap(): PlayerData.max_ammo_value = 2`）；`mods/doom_slayer_izzy/entry/doom_slayer_izzy_entry.gd`（`_ready` 同步调 `_register_texts()`，8 条 `ModAPI.add_translation`）；封顶机制 `script/PlayerData.gd:364`（`clamp(1, base_max_ammo + max_ammo_add*max_ammo_mult, max_ammo_value)`）、`:201`（每轮重置 9999）、`scenes/player/tsurugi/tsurugi_ps.gd:22,28`（参考实现）。
- Notes / 说明: ①判定扩大由 T2 提到 **T1**（`_tier()>=1` 挥砍 capsule `radius/height×2`；T0 仍 1×；T2 只保留处决叠 2 层）。②弹匣**上限封顶 2**：走 `PlayerData.max_ammo_value`（拾取 `max_ammo_add` 只加在 clamp 前，被上限截住）；每轮 `reset_date()` 置 9999，靠 `set_player` 信号由角色 PS 重新封顶（与 tsurugi/Hibiki 同法），PS `_ready` 也立即设一次兜底。③PS 文案键 `doom_slayer_izzy_izzy_ps_0..3`，在 `entry` 同步注册 `zh_CN`+`en`（`add_translation` 不触发 TRANSLATION_CHANGED，须早于菜单/商店构建）；选人卡取 `_ps_0`（`ui/player_card.gd:150`）、局内 PS 卡取 `_ps_0..3`（`ability_shop_ps_card.gd:178-183`），缺键回退 en。实测：`tr(_ps_0)` 中/英文正确、`max_ammo_value=2`、`hitbox@T0 r=24`/`@T1 r=48`、`max_ammo_add=50` 后 `stats.max_ammo=2`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [Mod/Egg] IZZY 彩蛋：每回合 10% 把局内 HUD 名字 IZZY → 122V
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd:22-23`（`EGG_NAME := "122V"`、`EGG_CHANCE := 0.10`）、`:45`（`GameEvents.round_start.connect(_on_round_start_name)`）、`:225-234`（`_on_round_start_name` 覆写 `GameUI.player_name.text`）；名字来源 `ui/game_ui.gd:51`（`player_name.text = player.player_card.name`，仅 `_ready` 设一次）。实测：`gui/label/connected` 正常、300 次调用命中 29 次 `122V`（≈10%）。
- Notes / 说明: 彩蛋**只覆写局内 HUD 标签**（`GameUI/PlayerName`），`GameUI` 是 `player` 根节点的兄弟（PS `player = NodePath("..")`），故 `player.get_node("GameUI").player_name` 可达；每回合重掷（命中 `122V`、否则还原 `IZZY`）。**故意不改 `player.player_card.name`**：那是共享 `PlayerCard` 资源，HUD/暂停页(`pause_screen.gd:162`)/结算页(`game_over_page.gd:157`)/选人卡(`player_card.gd:148`)/联机名都读它，改了会泄漏且需还原。触发用 `GameEvents.round_start`（每回合含第 1 回合）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [Mod/Coop] IZZY 联机同步：状态/事件镜像、镜像隐藏 HUD、待处决 host 权威、LAN 处决不慢放
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd`（`get/apply_network_character_state`、`apply_network_character_event`、`_build_hud` 远端 return、`_setup_local` 本地独占、`_is_lan`、`apply_execution_camera` 慢放门、`enter_crucible` 广播 `ds_crucible_on`）；`scenes/doom_slayer_izzy_melee.gd`（`_is_lan`、`_execute:443` 慢放门、`_kill` 广播 `ds_execute`、AoE `HurtSounds2` 走 `on_hit_sfx`）；`script/glory_manager.gd:189`（`try_stagger` host 门）+`:233`（`_is_lan`）。参考：`scenes/player/hina/hina_ps.gd:31-49`（LAN 不用全局 `Engine.time_scale`）；`mods/etn_coop/net/coop_net.gd:4615/250/2124/1755`；`coop_player_proxy.gd:82`(`network_remote_player`)/`:250`/`:314-319`；`script/extension_hooks.gd:92-94,104`。单端实测：`is_lan=false`、`apply_network_character_state` 置位→镜像 `crucible=true`、remote guard 不改 `max_ammo_value`、local `_setup_local`→cap=2。
- Notes / 说明: **A 视觉镜像**——`apply_network_character_state(state)` 解析 `combo(state&0xFF)`/`crucible(state>>8&1)`，**只写镜像 `crucible`**（借 melee `_update_held` 显示持剑），不触发玩法；镜像 `_build_hud` 直接 return（隐藏 combo/能量条，避免与本地串味）。**B 一次性事件**——`player.broadcast_character_event`→`on_character_event`→coop 转发→对端 `apply_network_character_event` 仅回放**世界表现**（`ds_crucible_on`→`crucible_sword_start`；`ds_execute`→`execute_sounds`+mirror `Kick/crucible_burst`.restart()），不含镜头/震屏/慢放。**C 待处决 host 权威**——`try_stagger` 在 `_is_lan() and not multiplayer.is_server()` 时直接 `return false`（客机不掷骰/不打标记），等 host 掷中后 coop 复制 `ds_executable` buff，客机 `_process` 见 buff 本地标记描边；host 端行为不变。**D LAN 处决不慢放**——`_execute`/`apply_execution_camera` 的 `request_slow` 在 LAN 跳过（世界与动画都正常速度，无等比慢）。**关键坑**：coop 镜像实例化整个玩家场景 → 镜像 PS `_ready` 也会跑，**必须把全局副作用（`PlayerData.max_ammo_value=2` / `set_player` 连接 / 子弹命中 hook）限制为本地**（`_setup_local` deferred + `_is_remote()` 守卫），否则客机玩别的角色会被误封顶弹匣/误充能。**待补**：完整双端联机回归（需本地两实例）尚未跑。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-16

### [UI] 通用「MOD」社团卡不可点/无悬停：整卡 ColorRect 默认 STOP 吞事件 + base 悬停为空实现
- Evidence / 证据: `ui/mod_society_card.tscn`（旧版 `Node2D/ColorRect` 未设 `mouse_filter`，默认 `STOP`；对照本体卡 `ui/ED_card.tscn:258` 设 `mouse_filter = 2`）、`ui/mod_society_base.gd:12-17`（`mouse_select_anim`/`mouse_out_anim` 为 `pass`）、`ui/mod_society_card.gd`（现照搬 `ui/society_card.gd:68-100` 的四个交互方法，播放 `select_anim`/`out_anim`/`on_select_anim`/`out_select_anim`）。
- Notes / 说明: 根 `PanelContainer` 的 `gui_input`/`mouse_entered` 会被覆盖其上的子 `ColorRect` 拦截（只有右侧十几像素空白可点）；任何整卡覆盖层都必须 `MOUSE_FILTER_IGNORE`。通用卡改为**照搬本体社团卡场景**（`StyleBoxEmpty` 主题、深色条、渐变、完整 `AnimationPlayer` 动画库），仅把图标 `TextureRect` 换成页码 `Label`（`MOD`/`MOD 2`）；悬停可见效果为本体卡同款底部 2px 白色下划线 + `ButtonSounds2`。`mod_society_base` 的空悬停实现仍只用于 mod 自带卡。实测：`hovered=ModSociety`、`current_animation=select_anim`、点击后 `on_select=true`/`on_select_anim`、`Node2D.position.x` 动画到 -24。
- Source / 来源: user + test
- Date / 日期: 2026-10-17
- SUPERSEDED: 2026-10-17 初版悬停用 Tween 做高度 28→30；已改为照搬本体社团卡动画；ColorRect IGNORE 结论不变。
### [UI/Layout] 滚动容器会被内容最小宽度反向撑开，页签动画不能写死容器位置
- Evidence / 证据: `ui/game_option.tscn:320`、`ui/option_button.tscn:12`、`tests/test_ui_ux_regressions.gd` 的 `_check_settings_layout`。
- Notes / 说明: GAME 的横向滚动禁用，内容最小宽度超过预留空间时，`grow_horizontal=2` 会让滚动区向左右扩张；仅增大左边距后实测内容从 x=143 开始，而非目标 x=162。同步收紧首行标签及频率滑条的最小宽度后，滚动区稳定为 `(162,40)`、宽 450。VBox 管理页签位置，RESET 中的绝对 `position=(24,40)` 应移除，`on_out` 的绝对位移须改为等量相对 `offset_transform_position`，避免改布局后动画覆盖排版；高亮轨道及样式不变。
- SUPERSEDED: 2026-10-16 页签改为固定位置，动画仅缩放背景，不再使用 `offset_transform_position`；GAME 的内容最小宽度结论仍适用。详见下方长扩展标题条目及 `ARCHITECTURE.md` 设置菜单布局（来源：code | test）。
- SUPERSEDED: 2026-10-17 用户要求页签间距/动画保留 main 原版：恢复 `on_select`/`selected`，删除未被调用的 `on_out` 及 `RESET`/`selected` 中的 `position`/`rotation` 轨道，不再使用 scale 动画（来源：user）。
- Source / 来源: code | test
- Date / 日期: 2026-10-15

### [UI/Layout] 长扩展页签会撑宽导航内容，焦点跟随可使整列横向偏移
- Evidence / 证据: 修复前 `ui/option.tscn:200-213`（横纵滚动均为模式 3、`follow_focus=true`）、`ui/option_button.tscn:244-261`（Label 无宽度收敛或省略）、`script/option_button.gd:5-10`（标题直接传给 Label）；2026-10-16 当前工作区 Godot 4.7 渲染复现，截图 `.godot/settings_nav_audit_20261016/07-long-title.png`。
- Notes / 说明: 用 `ModAPI.create_option_tab` 加入 `NETWORK SETTINGS` 后，导航项宽度从 128 增至 184；聚焦长标题后，不仅长标题裁切，原有 CONTROLS 也出现左侧裁切，整列内容发生横向偏移。导航隐藏滚动条不等于禁止横向滚动，`follow_focus` 也会影响横轴。现有设置布局回归只覆盖短标题 CUSTOM / EXTRA，60 项断言通过不能证明长标题安全。后续修复应同时约束共享页签的文字最小宽度和导航横向滚动策略，并保留完整标题的可获取方式；本次仅检查，未改实现。
- Follow-up / 后续（2026-10-16，来源：code | test）：已禁用横向滚动，并让共享 Label 单行省略、根 tooltip 同步完整标题；纵向溢出显示滚动条。页签与文字位置固定，仅背景按行尺寸缩放，消除动画打断导致的对齐差异。`clip_text` 会连像素字的外描边一起裁掉，须用 Label 的 `normal` StyleBox 内部留白保护描边和阴影，不能只增加父容器外边距。首次打开自动显示 GAME，重开聚焦当前页。新增回归在修复前捕获 9 项失败，修复后断言全部通过；测试命令仍因本地 godot_ai 缺失及既有退出资源日志判为非零，未改本地插件配置。
- SUPERSEDED: 2026-10-17 用户要求保留原版页签间距与动画并移除悬停 tooltip：恢复 main 的 Label 排版（不省略、无内部留白），长标题直接裁切；页签只保留 `on_select`/`selected`，删除 `on_out` 与未用轨道（来源：user）。
- Source / 来源: code | test
- Date / 日期: 2026-10-16

### [UI/Rendering] 设置导航右缘的黑色竖线是需修复的绘制缺陷
- Evidence / 证据: 用户明确指出“导航栏与右侧内容区有一条明显的黑色竖线，不是阴影”；修复前 `ui/option.tscn` 的 `Node2D/TextureRect` 在 x=140–156 绘制黑色到透明的渐变，起始颜色为 `(0,0,0,1)`；`tests/test_ui_ux_regressions.gd:_check_settings_seam`；截图 `.godot/settings_nav_audit_20261016/seam-before.png` / `seam-after.png`。
- Notes / 说明: 前轮“基础布局正常”的检查漏掉该边界缺陷；用户修正为权威输入，不能以阴影设计解释而忽略。像素复核确认 1280×720 渲染的 x=280 起始列为 `(0,0,0)`，右侧背景为 `(18,18,18)`。移除额外贴图及其资源后，x=280–310 与右侧背景一致；GAME / MOD / CONTROLS / COOP 的新增像素断言均通过，设置专项 82 项断言通过。整次运行仍因本地 godot_ai 缺失和已有退出资源报错返回非零，未修改插件配置。
- SUPERSEDED: 2026-10-16 用户明确要求重新添加右侧阴影；“移除全部阴影”的处理改为“保留柔和阴影，避免纯黑竖线”，此前黑线观察仍成立（来源：user）。
- Follow-up / 后续（2026-10-16，来源：code | test）：新增宽 14、最大 alpha=0.35 的渐变 `SidebarShadow`，置于内容后方且忽略鼠标；纹理使用 `expand_mode=1`，避免 64 宽资源撑大节点。实际像素从 `(12,12,12)` 平滑回到背景 `(18,18,18)`，四页阴影像素检查通过；设置专项 82 项断言通过。截图：`.godot/settings_nav_audit_20261016/soft-shadow-game.png`。
- Source / 来源: user | code | test
- Date / 日期: 2026-10-16

### [UI/Input] 设置页签的选中动画去重不会阻止重复切页事件
- Evidence / 证据: `script/option_button.gd:46`、`ui/option.gd:menu_button_press`、`tests/test_ui_ux_regressions.gd:_check_settings_repeat_activation`；`.godot/settings_repeat_before.log` / `.godot/settings_repeat_final.log`。
- Notes / 说明: 用户报告重复点击激活项仍触发事件。原 `set_selected()` 虽对相同状态直接返回，但执行在音效及 `GameEvents.menu_button` 发出之后，无法阻止页面重新显示或刷新。修复在点击入口消费激活输入后检查 `on_show`，对当前项直接返回。鼠标、触屏、Enter 的修复前检查共捕获 6 项失败；修复后带已安装 MOD 副本的隔离设置专项 41 项断言通过，含关闭/重开与切页。测试命令仍因已有 godot_ai 文件缺失及退出资源错误返回非零，不能宣称整次运行无错误；未改 `project.godot`。本地 tests 改动按约定不提交。
- Source / 来源: user | code | test
- Date / 日期: 2026-10-16

### [UI/Input] 触屏切换设置页签必须同步导航焦点
- Evidence / 证据: 用户报告移动端切到其他页签后 GAME 仍有选中态；`ui/option.gd:button_open`、`script/option_button.gd:26-35,46-58`；`.godot/settings_touch_before.log`、`.godot/settings_touch_focus_probe.log`、`.godot/settings_touch_after.log`。
- Notes / 说明: 设置打开时 GAME 持有焦点，ScreenTouch 不会自动把焦点交给新页签。原逻辑虽把 GAME 的 `on_show` 置 false，仍因 `has_focus()` 播放 `on_select`，留下宽度 4% 的金色背景。隔离渲染回归通过真实触屏输入复现 4 项失败；只释放旧焦点即可消除背景，鼠标不在 GAME 区域，动画等待结束后结果相同。修复在激活入口先 `grab_focus()`，再处理重复点击及切页。此前重复激活检查通过不代表触屏切页焦点正确；原有结论仅覆盖事件去重。稳定职责见 `ARCHITECTURE.md` 的「设置页签激活与焦点」。
- Validation / 验证: 修复后设置专项 49 项断言通过，覆盖本体/扩展页签触屏往返、唯一高亮、重复触摸去重、鼠标及 Enter；测试仍有既有退出渲染资源错误和临时目录清理错误，不能宣称测试进程无错误。本地测试不提交。
- Device / 真机: Pixel 5 / Android 14 同签名覆盖安装成功，保留应用数据与已安装 Mod。修复前实际点击 CONTROLS 可见 GAME 左缘金色残留；修复后 CONTROLS / MOD / COOP 以及返回 GAME 再切出均无残留。截图与 APK 在 `.godot/settings_touch_20261017/`。
- Source / 来源: user | code | test
- Date / 日期: 2026-10-17


### [Godot/GDScript] 脚本里的空字符转义字面量会在 Godot 4.5+ 刷 "Unexpected NUL character"
- Evidence / 证据: 修复前 `script/pck_directory.gd:66` 的 `path.ends_with("\u0000")`；本机 Godot v4.7.stable 无头复现：含该字面量的脚本会让启动日志多出该报错，去掉 `pck_directory.gd` 中唯一一处后，完整启动（`--headless --verbose --quit`）由 3 条降为 0 条（连续两次）。
- Notes / 说明: Godot 4.5/4.7 给字符串解析加上 NUL 检查后，GDScript 里写 `"\u0000"` 这种含空字符的字符串字面量，会被当成非法字符处理并打印 `Unicode parsing error ... Unexpected NUL character`（实测一个字面量约 3 条）。启动日志开头那 3 条报错即来自 `pck_directory.gd`（被 `mod_manager.gd:28` 以 `preload` 引入，ModManager autoload 编译时触发）。PCK 目录表的路径字段按 4 字节对齐并以 NUL 填充、`path_len` 含填充，正确做法是按**字节**裁掉尾部 NUL 再 `get_string_from_utf8()`，不要用含空字符的字符串字面量比较。与本地 godot_ai 缺失、PCK 挂载本身无关。
- Source / 来源: code + test
- Date / 日期: 2026-10-17

### [UI] 设置页签保留 main 原版间距/动画，清理未用轨道并移除悬停 tooltip
- Evidence / 证据: `ui/option_button.tscn`（保留 `on_select` 三条轨道与 `selected` 的 size/position；删除未被调用的 `on_out`；`RESET` 仅留 `Node2D/ColorRect:position`/`size` 与 `.:offset_transform_position`；`selected` 删除 `ColorRect:rotation`）；`ui/option.tscn` 移除 VBox 的 `size_flags_horizontal=3` 与显式 `separation=4`，回到原版自然行高/间距；`script/option_button.gd:26-35,46-58`（删除 `_resize_highlight` 与两处 `tooltip_text`，`set_selected(false)` 回退为 `play_backwards("on_select")`）；`ui/menu_button.tscn` 的 `RESET` 三条轨道均被 `on_select` 使用，未改。
- Notes / 说明: 用户（source）指出页签按钮重做过，实际只用 `on_select`（悬停）与 `selected`（点击后整条金色底）；`on_out`、`RESET` 及 `.:position`/`rotation` 属遗留未用部分。`offset_transform_position` 在 Godot 4.7 默认 `offset_transform_visual_only=true`，只做视觉偏移，不改按钮自身 position/size，不影响 VBox 排版。长标题不再省略且无 tooltip，超出导航区直接裁切。设置专项回归与截图见 `tests/run_ui_ux_checks.py --settings-only`。

### [Mod/Melee] IZZY 近战暴击（对齐本体；此前近战完全不暴击）
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd:264-267`（`_roll_melee`）、`:294-296`（`_swing` 写 `base_damage`/`is_crit`）、`:347/365`（`_crucible3_tick` 每 tick roll）、`:499/502`（`_aoe_execute` 整次 roll）；`_kill` 保持 `TRUE_DAMAGE` 不变。本体参考 `scenes/player/chinatsu/chinatsu_melee.gd:69-75`、`hoshino/melee.gd:126-132`、`utaha/melee.gd:72-78`、`script/kick.gd:39-44`；`damage_data.gd:127-128`（`DamageData.make` 支持 `crit` 键）。实测：`crit_luck=100` → `_roll_melee(100)=150/crit=true`；`crit_luck=0` → `100/false`；`_swing(100,...)` 后 `hit_box.base=150 is_crit=true`。
- Notes / 说明: 之前 IZZY 的 `_swing` 只写 `hit_box.damage_data.base_damage`、**从不 roll `critical_luck`/设 `is_crit`**，`_crucible3_tick`/`_aoe_execute` 的 `DamageData.make` 也未带 `crit` → 近战（普通/裁决连击/处决 AoE）**全部不暴击**。现对齐本体：`luck<critical_luck → base*critical_damage, is_crit=true`；**普通近战+裁决1/2段**经 `_swing` roll；**第3段每 tick 各自 roll**；**AoE 整次 roll 一次**（命中同伤害）；**处决本体 TRUE_DAMAGE 仍不暴击**（直接取 hp）。`critical_damage` 实测基础值 `1.5`；`is_crit` 驱动暴击飘字（`enemy_hurt_floating_text.gd:30`）。联机下 `base_damage` 已含暴击倍率，随伤害字典传 host（`coop_net.gd:_damage_to_dict`），权威结算一致。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-17

### [Mod/Melee] 裁决剑伤害继承 50% 子弹基础伤害（B 口径：段倍率之后加固定值）
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd:70`（`BULLET_INHERIT := 0.5`）、`:274-280`（`_bullet_inherit()`/`_crucible_hit_base(mult)`）、`:288`（裁决 1/2 段）、`:336`（第 3 段 `tick = base*0.4 + _bullet_inherit()`，**每 tick 各自 +50% 子弹**）、`:511`（AoE `_crucible_hit_base(3.0)`）。实测（kick=20、bullet=10、global=1、crit=1.5）：`_bullet_inherit()=5`、`_crucible_hit_base(2)=45`、`_crucible_hit_base(3)=65`、`crit_luck=100` 时 `_roll_melee(45)=68/crit=true`。
- Notes / 说明: 仅**裁决剑**（1/2/3 段 + 处决 AoE）继承；**普通近战/枪托不继承**。口径 B：继承部分 = **固定 `0.5 × stats.bullet_damage`**，**不吃 `global_damage`、不吃段倍率**；第 3 段**每个 tick 各加一次**（4 tick → 共 `2×bullet`），不是分摊。暴击作用于含继承的总伤害（`_roll_melee` ×`critical_damage`），即「暴击考虑 50% 子弹伤害」。数值样例（IZZY 基础）：第1段 T0 非暴击 45 / 暴击 68；第3段 T0 throw base=60、tick=24+5=29（4 tick 共 116）；AoE 65 / 暴击 98。联机无额外改动（`base_damage` 已含继承+暴击，随伤害字典传 host）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-17

### [Mod/PS] `_ps_0` 文案补充连击说明（处决获每层 +10% 全局伤害）
- Evidence / 证据: `mods/doom_slayer_izzy/entry/doom_slayer_izzy_entry.gd:28,34`（`_register_texts()` 的 `doom_slayer_izzy_izzy_ps_0` zh/en）；`ui/player_card.gd:150`（选人卡取 `_ps_0`）。实测 `tr(_ps_0)` 中/英均为新文案，pck 已重打安装。
- Notes / 说明: 句序为「弹匣上限 → 待处决概率 → 处决连击（每层 +10% 全局伤害）→ 计量满换裁决剑」；en 同步调整语序。因选人卡描述直接用 `_ps_0`，该句也会出现在选人卡上（符合既有约定）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-17

### [Mod/Society] 社团卡照搬本体（BOOM 图标）+ buff 图标改 mod 自带
- Evidence / 证据: `mods/doom_slayer_izzy/defs/societies/doom_slayer_izzy_team.tscn`（照搬 `ui/ED_card.tscn`；脚本 `res://ui/mod_society_card.gd`；`group_id="doom_slayer_izzy_team"`、`members=["doom_slayer_izzy_izzy"]`；图标 `res://mods/doom_slayer_izzy/sprites/BOOM_icon.png`）；`mods/doom_slayer_izzy/resources/buff/executable.tres`（图标 → `res://mods/doom_slayer_izzy/sprites/dead_buff.png`，uid `uid://bk6jwuhcqcm4v`）。实测：root/script/gid/members 正确、icon 路径正确、动画列表 `[RESET,on_select_anim,out_anim,out_select_anim,select_anim]`、`buff.icon` 指向 mod 自带、`ModManager.get_mod_societies()=1` 且 gid 正确。
- Notes / 说明: ①复制 `ui/ED_card.tscn` 时**必须去掉 `[gd_scene]` 里重复的 uid**（否则与本体 ED_card 的 uid 冲突），本次已移除；②社团卡用 `mod_society_card.gd`（继承 `mod_society_base.gd`，带本体悬停/选中动画）；③`BOOM_icon.png` 与 `ED_icon.png` 同为 **223×50**，`TextureRect` 的 offsets/scale 无需改；④buff 图标改为 mod 自带后，**mod 不再依赖未跟踪的本体 `sprites/buff_icon/dead_buff.png`**（该文件在 0.5.1.3 不存在、也不在 git 中），提升了 0.5.1.3 兼容性与干净 checkout 可用性。mod 社团 `group_id` 由 `ModManager._scan_societies` 自动加入 `PlayerData.group`（`mod_manager.gd:1195-1197`），`menu_screen._setup_societies` 据此显示。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-17

### [Mod/PS] 计量/能量跨回合继承 50%（回合结束减半；裁决态保留）
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd:46`（`GameEvents.round_upgrade.connect(_on_round_upgrade_carry)`）、`:80`（`_on_round_upgrade_carry`：裁决期 `energy*=0.5`、否则 `meter*=0.5`）、`_reset_soft`（不再清 `meter/energy/crucible/BGM`，只重置 combo/`crucible_index`）、`_on_change_scene`（换关全清）。实测：非裁决 `meter 120 → round_upgrade → 60` 且 `_reset_soft` 保留 60；裁决 `energy 200 → 100`、`crucible=true` 保持；`_on_change_scene` 后 `meter/energy/crucible = 0/0/false`。
- Notes / 说明: 目的=缓解「每回合重新处决攒能量、前期攒够时回合快结束」的节奏问题。触发点 `GameEvents.round_upgrade`（回合结束、升级界面前，`round_manager.gd:143`，每回合一次）。裁决态**跨回合保留**（不退出、DOOM BGM 继续），只把剩余 `energy` 减半；非裁决则 `meter` 减半带着走。换关/新局/`reset_done` 仍全清。**已知未处理**：关卡 BGM 轮替（`main.gd:33` 捡紫水晶 + 240s `BGM_timer` → `_on_bgm_timer_timeout` → `bgm_slow_fade_out`）仍会把裁决 BGM 顶掉；纯 mod 挡需依赖本体私有方法名/节点（脆弱 hack），本次按用户意见不做。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-17

### [Mod/Fix] 导出游戏里角色立绘/头像缺失：`sprite_path` 不能用 mod 本地 UID，必须写路径
- Evidence / 证据: `mods/doom_slayer_izzy/defs/characters/doom_slayer_izzy_izzy.tres:10` 原 `sprite_path = "uid://cpi3qx3s5vgqn"`，改为 `sprite_path = "res://mods/doom_slayer_izzy/sprites/izzy_picture.png"`；读取处 `ui/player_card.gd`（`_apply_sprite(card.sprite_path)`）、`ui/game_ui.gd:50`、`ui/pause_screen.gd:160`、`ui/game_over_page.gd:155`、`ui/menu_box_button.gd:49`、`ui/score_card.gd:164`、`ui/test_character_card.gd:42` 均为 `LazyTexture.load_uncached(path)` → `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)`。实测：`sprite_path` 为路径后 `LazyTexture.load_uncached()` 返回非空、`resource_path` 正确；mod 内已无 `= "uid://"` 字符串。
- Notes / 说明: 导出游戏的基础 `uid_cache.bin` **不含 mod 的 UID**（导出 `exclude_filter` 排掉 `mods/*`，uid_cache 按导出资源重建），因此 `load("uid://...")` 返回 null → 立绘、局内 HUD 头像、暂停/结算/分数卡头像、测试房头像全缺；脚本/文本/场景路径都正常，所以只表现为「图没了」。`PlayerCard.sprite_path` 这类**普通字符串属性**无法像 `ext_resource` 那样按 `path=` 回退，**必须写 `res://` 路径**。`ext_resource` 同时带 `uid`+`path` 的可回退，无需改。此问题与版本无关（0.5.1.3/0.5.1.4 导出都会中招）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-17

### [Mod/Packaging] mod 元数据改名 + 换 mod 图标；zip 暂存别放构建副本内
- Evidence / 证据: `mods/doom_slayer_izzy/mod.json`（`name=DOOM SLAYER IZZY`、`author=SH`、`description=神秘穿越而来的BOOM…→https://space.bilibili.com/21140459←`、`game_version=v0.5.1.4`、`version` 保持 `0.1.0`）；`mods/doom_slayer_izzy/icon.png` 为 `izzy_mod_icon.png`（256×256）的副本。实测安装目录 `icon.png=256x256`、`mod.json` 解析正确、pck 内含新 `name/author/game_version`、zip 含 `pck/icon.png/mod.json`。
- Notes / 说明: ①MOD 管理面板**优先用安装目录的 `icon.png`**（README §2），所以换图标必须把新图复制成 **mod 根目录 `icon.png`** 并在安装时覆盖旧图；只放在 `sprites/` 或只写 `mod.json.icon` 字段不够（旧 `icon.png` 优先）。②打包脚本末尾不自建 zip 时，手动 `Compress-Archive` 的**暂存目录不要放在构建副本内**（如 `<copy>/build/<id>/`）——ModPack 预设的 `exclude_filter` 未排除 `build/`，下次导出会把 `res://build/...` 一起打进 pck（本次已改用 `%TEMP%` 暂存并清掉旧 stage）。③`mod.json` 用 UTF-8 保存，`description` 可含全角标点与 URL（JSON 字符串内无需转义）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-18

### [UI] GAME 设置页用 MOD 同款卡片分区；ScrollContainer 子项最小宽度超出会反向撑宽并两侧回弹
- Evidence / 证据: `ui/game_option.tscn`（`Scroll` offset_left=134（右侧无额外偏移），`Content` → `DisplayCard`/`FeedbackCard`/`AudioCard`，卡片 `StyleBoxFlat_card` 与 `Theme_row`/`Theme_section`；四个 `option_toggle.tscn` 实例 `track_color=Color(0.164706,...)`）；`script/game_option.gd`（`_bind_toggle`/`_bind_toggle_label`/`_set_full_screen` 等，`setting_status()` 用 `set_on(v,false)`）；`script/option_toggle.gd`（`focus_entered/focus_exited`、`ui_accept`、`track_color`）；`ETN_localization.csv`（`option_group_display/feedback/audio`）。
- Notes / 说明: ① GAME 页原 `Graphics`/`Sounds` 长列表改为三张深色卡片；DISPLAY 两行标签左对齐并包 126×22 固定 wrapper，滑条行固定「标签 126 + 滑条扩展 + 数值 64」，右控件槽 128；FEEDBACK/AUDIO 仍为右对齐标签。内容最小宽度 446，须落在 ScrollContainer 可视宽 446（454 - 8 滚动条）内；超出时 `grow_horizontal=BOTH` 会把 `Scroll` 撑出页面边界。② 关闭态开关在页面暗底上几乎不可见；共享 `option_toggle` 新增导出 `track_color`，GAME 实例设为 0.164706，MOD 保持默认 0.0784314。③ 共享开关新增焦点高亮与 `ui_accept`（Enter/Space/手柄 A），处理输入后 `accept_event()`；GAME 行标签点击转发到 `toggle()`，移动端全屏/垂直同步仍由 `_on_toggle_changed` 回滚并提示。④ 三组标题使用新增本地化键，CSV 仍在末尾追加（UTF-8 BOM + CRLF）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-18
- Follow-up / 后续（2026-10-18，来源：user + test）：DISPLAY 两行原本 `CellA`/`CellB` 都设 `size_flags_horizontal=3`，RowDisplay 的右列（下拉框）更宽时 HBox 会给两行 `CellA` 分配不同宽度，导致左列开关与右列控件错位。现固定 `CellA=152`、`CellB=262`，仅 `CellB` 扩展；标签改为 126×22 固定 wrapper + 左对齐 + `clip_text`，两行右控件槽统一 128。4 语言下 `FullScreen`/`VSync`/`MaxFps` 的 x 一致、`Resolutions`/`PhysicsInterp` 的 x 一致，`Content` 最小宽 446（Scroll 宽 454，x=134）。
- SUPERSEDED: 2026-10-18 设置项标签最终统一右对齐，数值槽改为 96×22 并启用 `clip_text`，避免文本最小宽度挤短滑条；按钮与 PopupMenu 须分别统一字体。当前规范见 `CONVENTIONS.md` §6。（来源：user | code | test）

### [Mod/UI] 本轮原型对照以用户附图「B · 列表 + 常驻详情」为准
- Evidence / 证据: 用户 2026-10-18 附图 `codex-clipboard-413402ed-c756-48c6-a76e-191da22bba18.png`；历史同方向截图 `.godot/prototype_mod_list/mod_list_B.png`；实现 `ui/mod_option.tscn`、`script/mod_option.gd`。
- Notes / 说明: 用户明确纠正参考对象为附图中的左右双栏方案，包含顶部统计/待重启条、左侧三组列表及右侧常驻详情；此前找到的 js.design 纵向详情画板与 HTML 弹窗原型均不能代替此参考。历史 B 截图的底色、分组数量与待重启数量不同，也不能视为附图的同一状态。此纠正只确定本轮对照来源，不代表用户已要求改代码或确认全部视觉细节。
- Source / 来源: user
- Date / 日期: 2026-10-18


### [Mod/UI] 行排序会抢占触屏滚动；开关支持确认键不等于可获得焦点
- Evidence / 证据: `script/mod_option.gd:397`、`:413`；`ui/option_toggle.tscn:160`；本地复现 `tests/mod_ui_audit.gd`，日志 `.godot/mod_ui_audit_20261018/audit.log`。
- Notes / 说明: 当前 Mod 行在触屏按下时 `accept_event()`，移动超过 6 像素即进入排序，父级 `ScrollContainer` 无法接管。隔离渲染检查中，从行上向上滑动 100 个逻辑像素，`scroll_vertical` 始终为 0，却改写顺序并产生待重启项；尚未 Android 实机复核。另：共享 Toggle 脚本虽处理 `ui_accept`，场景根 `PanelContainer` 未设焦点，Mod 创建行也未补设；运行时行与开关 `focus_mode=0`，`grab_focus()` 被拒绝，不能据处理函数存在就认定键盘可用。本条记录现状，尚未修复。
- Source / 来源: code | test
- Date / 日期: 2026-10-18
- SUPERSEDED: 2026-10-18 已修复：Mod 行设为 `MOUSE_FILTER_PASS`，触屏按下/拖动交给父级滚动，轻点选中，触屏排序使用上下移按钮；鼠标仍可整行拖动排序。Mod 页创建的行与 Toggle 显式启用焦点，方向键选择、Tab 切换与刷新后的焦点恢复均经真实输入验证。共享 Toggle 场景仍不默认启用焦点，其他使用方须按需设置。复现脚本已转为断言回归，修复后日志 `.godot/mod_ui_fix_20261018/audit.log`：触屏滑动 `scroll=59`、顺序不变，无待重启改动。Android 实机仍待验证。来源：code | test。

### [Coop/UI] 联机覆盖层卡片化：LAN 左右分栏常驻房间列表；PageScroll 与动态房间按钮必须进白名单
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_menu.tscn`（Panel `(146,32) 489×320`；Header → `PageScroll/PageContent` → StatusBox；LAN `LanSplit` 左 272 / 右 190；RoomList/RoomStatus/RoomCount）；`ui/coop_menu.gd`（`_build_room_list`/`_refresh_room_list`/`_clear_room_list`/`_refresh_room_status`/`_set_selected_mode`/`_build_interactive_controls`）；`ui/coop_option.gd` + `ui/coop_option.tscn` + `ui/coop_theme.tres`；`i18n/coop_i18n.gd`（`coop_section_*`）。实测 4 语言：Panel 489、PageScroll 478、PageContent 470、Left 272 / Right 190、RoomList 178，右边缘 635 不越界；扩展契约 `checks=17 failures=0`。
- Notes / 说明: ① `_set_buttons_enabled()` 会把 `_panel` 全部后代设 `IGNORE`，`PageScroll` 本身、竖向滚动条和动态房间按钮都必须加入 `_build_interactive_controls()`，否则触摸拖动/房间点击失效。② 房间列表改为 `%RoomList` 常驻右列，`_clear_room_list()` 同时从白名单移除旧按钮；`_refresh_room_status()` 区分扫描中/无房间/有房间数量。③ 房间行点击沿用 `_on_room_pressed`：回填 IP/端口并直接加入，不再走二级菜单。④ 紧凑字号（分区 12 / 行 13 / LAN 分栏行 12 / 按钮与输入 11 / 说明 IP 9）避免 272/190 两列撑宽；按钮 `clip_text + text_overrun_behavior=3`。⑤ 编辑器里 coop 翻译未注册时 Label 以原始 key 计算最小宽度，Panel 可能显示 500 宽；运行期注册 `coop_i18n` 后为 489，不要按编辑器宽度改布局。⑥ `SakiServerRow` 移入 Relay 卡片后改名查找易失效，已加 `unique_name_in_owner` 并用 `%SakiServerRow`。⑦ `coop_option.tscn` 自带 `coop_theme.tres`，所以本体 option 的 COOP 页也获得同一卡片/像素按钮样式。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-18
- Follow-up / 后续（2026-10-18，来源：user + test）：仅把 PageScroll 放进白名单仍不够——vbar 可能在构建白名单之后才创建。 `_set_buttons_enabled(true)` 现显式设 PageScroll/vbar STOP，并给白名单控件 `mouse_force_pass_scroll_events=true`；`_input` 增加页面矩形内滚轮兜底（服务器子菜单打开时跳过）。运行期探针：wheel=48 / drag=80 / vbar=57，Filters scroll=0 vbar=0。

### [Mod/UI] 第三方 mod 的 pck 夹带 `mods/etn_coop` 旧编译脚本会遮蔽联机 UI（新场景 + 旧脚本）
- Evidence / 证据: `user://mods/doom_slayer_izzy/doom_slayer_izzy.pck` 内含 `mods/etn_coop/ui/coop_menu.gdc`、`coop_menu.gd.remap` 与旧 `coop_menu.tscn`；`ModManager` 只扫描 `user://mods`，etn_coop 的镜像 `res://mods/etn_coop` 仅提供项目资源，doom pck 的 `.gd.remap` 让新场景加载旧编译脚本。实测新 etn_coop pck + 镜像后：`coop_menu.gd` 仍 `has_method("_resolve_page_scroll")==false`、`PageScroll.mouse_filter==2`、点击命中 `CoopMenu`；禁用 doom pck 后：`has_resolve=true`、`filter=0`、滚轮 `48`、vbar 拖动 `57`。另：镜像的 `net/coop_net.gd` 仍是旧版，导致 `coop.extensions` 访问报错；对镜像做完整 SDK 同步后消失。
- Notes / 说明: ① 排查时不要只看 `option.tscn`/新卡片是否出现——**场景可以来自镜像，脚本却来自第三方 pck 的 `.gdc`**；用 `has_method` 或新加的方法确认运行脚本版本。② 第三方 mod 打包时若工程里包含 `res://mods/etn_coop/`（例如复制了联机镜像），会把 `mods/etn_coop/**` 一并打进自己的 pck；它的 `.gdc`/`.remap` 会遮蔽同名 `.gd`，且其 load_order 更高时更明显。修复=重打该 mod 时排除 `mods/etn_coop/**`，或临时把该 pck 移出 `user://mods`。③ 只同步 UI 文件不够；编辑器镜像若长期未全量同步，会出现 `coop_net.gd` 等旧依赖报错，需用 SDK 源整体覆盖镜像。④ `PageScroll` 的 vbar 可能晚于白名单创建，启用时必须动态 `get_v_scroll_bar()` 补 `STOP`；页面矩形内保留 `_input` 滚轮兜底。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-18

### [Coop/UI] 手动给页签加 `option_button_box` 后，脚本必须兼容新旧 VBox 路径
- Evidence / 证据: 镜像 `ui/coop_menu.tscn` 的页签移到 `Node2D/option_button_box/VBoxContainer`（用户手动加 `Title` + ScrollContainer），SDK 源仍是 `Node2D/VBoxContainer`；`script/coop_menu.gd` 新增 `_tabs_vbox()`（新路径优先、旧路径回退），`_setup_tab_input()` 设 `focus_mode=ALL`。运行期验证：`_tabs_vbox()` 返回 VBox、LAN/RELAY/OPTION `focus_mode=2`、`PageScroll.mouse_filter=0`，红字 `Node not found` 消失。
- Notes / 说明: ① 用户手动调整镜像后不要直接整体同步 SDK→镜像，否则会覆盖 `Title`/`option_button_box`；先保留镜像，等用户确认后再把场景搬回 `mod_sdk/`。② `_build_extension_pages()` 找不到页签容器时 `push_warning` 并返回，避免无条件 `get_node()` 抛红字。③ 内置页签设置 `focus_mode=ALL` 可消除 `option_button.gd:54 grab_focus()` 警告。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-18

### [Coop/UI] 语义色 + 粗体层级 + LAN 扫描省略号动画
- Evidence / 证据: `ui/coop_menu.tscn`（`Theme_section` 浅绿 `0.549/0.941/0.721` + Bold，分隔线低透明绿；`RoomCount`/`RelayRoomCodeLabel` 浅绿 Bold；`LocalIpLabel` 青；说明冷灰；`Title` 浅绿 Bold）；`ui/coop_theme.tres`（按钮 hover/focus 文字浅绿、占位符冷灰）；`ui/coop_option.gd`（卡片标题/数值 Bold + 浅绿）；`ui/coop_menu.gd`（`_scanning_text`/`_tick_scan_dots`，`SCAN_DOT_INTERVAL=0.38`，`coop_lan_scanning_base`；`_set_status` 同时给状态点与文字上色）。运行期实测：状态文本 `正在扫描局域网..` → `...`，`_scan_phase=2→3`，`RoomStatus` 颜色 `(1,0.78,0.12)`，`RoomCount` 颜色 `(0.549,0.941,0.721)` 且字体为 `BoutiqueBitmap9x9_Bold_1.9.ttf`。
- Notes / 说明: ① 配色走语义而非每卡主题：浅绿=标题/数值，青=地址，琥珀=扫描/等待，红=错误，冷灰=说明；主文本保持白色。② 只有分区标题和数值用 Bold，行标签保持 regular，避免字号/字重一起变重。③ 扫描动画只在 `_browsing && 无房间` 时运行，有房间隐藏、无房间显示静态“未发现房间”；同色点循环不改布局。④ 用户手动加的 `Title`/`option_button_box` 场景已搬回 `mod_sdk`，镜像与源码同步；安装版 pck 已重打。⑤ `doom_slayer_izzy.pck` 仍禁用（旧 `mods/etn_coop` 会遮蔽新 UI）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-18
- SUPERSEDED: 2026-10-18 用户反馈绿色标题/Bold 过土；分区标题与 COOP 题头恢复灰/白 regular，数值恢复白 regular；仅保留状态色、IP 青和扫描动画。（来源：user）

### [Coop/UI] ESC 关闭联机覆盖层要走 `_input`，且不能先做手柄判断
- Evidence / 证据: `ui/coop_menu.gd` 新增 `_handle_cancel_input()`，在 `_input()` 顶部优先处理；`_unhandled_input()` 只保留手柄方向/确认。运行期实测：首次 ESC `on_coop=false`；重开后打开服务器子菜单，ESC 只关子菜单（`submenu.visible=false`、`on_coop=true`）；再按 ESC `on_coop=false`。旧实现把 `if not _is_gamepad_event(event): return` 放在 `_is_ui_cancel()` 之前，键盘 ESC 被提前丢弃。
- Notes / 说明: ① 取消键统一在 `_input()` 消费，早于 GUI/`_unhandled_input`，避免主菜单/暂停页同时响应 ESC。② 顺序：已打开的删除确认框先让弹窗处理；服务器子菜单先只关子菜单；否则 `out_coop_selected()`。③ `ui_cancel`/`pause` 都走 `_is_ui_cancel`，键盘 ESC 与手柄 B 一致；`set_input_as_handled()` 防止重复关闭。④ 旧 `_file_dialog` 守卫是误加（本场景没有该变量），已移除；确认框是 `_saved_confirm`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-18

### [UI] 支援列表展开后主卡背景覆盖候选区域，悬停命中须先查候选
- Evidence / 证据: `ui/support_ui/support_select_ui.tscn:55-62`（`select_anim` 的 `main_card:size` 轨道将高度从 140 扩到 260；:67-79 是 `MarginContainer` 轨道）、`ui/support_ui/support_select_ui.gd:37`（主卡绑定的 `hit_test` 排除列表矩形，候选优先命中）、`:207`（候选绑定设 `hover_root`，允许按容器实际悬停命中）、本地 `tests/test_ui_ux_regressions.gd:_check_support_details`。
- Notes / 说明: 主卡与候选列表互为兄弟节点，但展开后的主卡背景矩形包含列表区域；不能先用 `main_card.get_global_rect().has_point()` 决定详情，否则鼠标指向候选也会显示当前支援。应先检查裁剪后的列表区域与候选矩形，再回退主卡。已选候选可能忽略鼠标事件，需结合实际 GUI 悬停所属区域和几何位置读取；边缘截图测试定位到立绘区时也不能使用动画后的主卡底边。浮层贴边只做 clamp 会让它在列表区域纵向钉住（下界 = 视口底 - 浮层高），必须越界时翻到指针另一侧；已显示后换卡不应重新等待悬停延迟。跟随定位要用 `InputEventMouseMotion.position` 缓存（现为 `ui/hover_tooltip.gd:115` 的 `shared.pointer`，锚点见 `:232`），不要用 `get_mouse_position()`：窗口拉伸或测试注入合成事件时它与 GUI hover 不同步、可能滞后一帧，浮层会显得“鼠标动完才动”；缓存后可在 `_input` 里当帧 `place_at`。触屏不显示详情（工程关闭 `emulate_mouse_from_touch`，点按即选中会让浮层闪现），见 `SYSTEMS.md` 同名条目的触屏说明。
- Validation / 验证: 隔离存档的难度页专项检查中，当前支援等级 21、候选等级 37，鼠标和键盘预览均显示对应等级，且不改变全局出战支援；四语言边缘截图已核对。
- Source / 来源: code | test
- Date / 日期: 2026-10-18
- Follow-up / 后续（2026-10-18，来源：code）：该浮层已由 `support_select_ui.gd` 自管理的 `_details_*` 迁到统一组件 `ui/hover_tooltip.gd` + `HoverTooltipBinding`，`ui/support_ui/support_details.gd/.tscn` 已删除；上述结论不变，落点改为绑定的 `hit_test`/`hover_root` 与宿主的 `_viewports` 跨层协调。

### [UI] 隐藏的 PanelContainer 不排版子 Label，首次定高必须自己算
- Evidence / 证据: `ui/hover_tooltip.gd:_layout`（:235-298，先设 `label.size.x = 内容宽 - INSET*2`，再用 `get_line_count()` 与 `Font.get_height()` + `line_spacing` 自行定高）、`ui/hover_tooltip.tscn`（宿主 `visible=false`）、`ui/support_ui/support_select_ui.gd:221`（文本来源）。
- Notes / 说明: 宿主初始隐藏时容器不会 sort 子节点，Label 宽度停留在 1px；首次 `reset_size()` / `get_combined_minimum_size()` 会按 1px 宽换行（示例文本 120 行 → 只排出 24 行），把面板定成截断高度，且该缓存滞后一帧，连续调用 `reset_size()` 当帧无效。正确做法是先按目标宽度强制换行，再用 `get_line_count()`（总行数，需自行按可用高度截断；统一宿主的段数上限为 16）、`Font.get_height()` 与 `line_spacing` 算高：`lines × (行高 + line_spacing) - line_spacing + 上下内边距`（末行不加行距）。
- Validation / 验证: 隔离存档首次悬停即得到 287px（修复前 612px 空盒），四语言截图与 67 项难度页回归通过；迁移到统一宿主后由 `_layout` 承担同一算法，本地专项回归补了 320×240 窄视口重测与超长文案截断断言（用例未入库）。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [UI] Label 没有逐行宽度接口；浮层按内容收窄要用 Font.get_string_size 反推
- Evidence / 证据: `ui/hover_tooltip.gd:_text_width`（按 `\n` 分段调 `Font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)`，再 `clampf(_measured_width + INSET*2, MIN_WIDTH, width)` 决定面板宽）；本地专项回归（未入库）的「短内容收窄面板」「窄视口重测」「超长截断」断言。
- Notes / 说明: `Label` 只暴露 `get_line_count()`/`get_visible_line_count()`/`get_line_height()`；`get_line_width()` 属于 `TextEdit`，写到 Label 上是运行期 `Invalid call. Nonexistent function`（本次实测，导致 `_layout` 中断、11 项断言连带失败）。固定宽度（350）会让短提示变成大片空盒，改为按字体测量未换行文本宽度即可自适应：长段落测量值超上限被 clamp，换行后仍占满上限；短文本贴合内容。直接对 Label 设 `size` 能正常 shaping，不受「隐藏容器不排版」影响，但含换行的文本要先按 `\n` 分段，否则整串宽度无意义。
- Validation / 验证: 截图专项 156 项通过；`tooltip-shared-keyboard` 面板由约 430px 收窄到约 187px，长文与支援详情四语言截图行距、分组正常。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [Tooling] `--check-only` 不注册 autoload，会把 autoload 标识符误报为未定义
- Evidence / 证据: `godot --headless --path . --check-only --script res://ui/hover_tooltip.gd` 报 `Compile Error: Identifier not found: LocaleFont`（`project.godot:25-39` 已注册该 autoload）；改为工程内 SceneTree 脚本在 `_initialize()` 里 `load()` 同一文件即通过，`tests/run_ui_ux_checks.py --level-focus-only` 也 46 项 0 失败。
- Notes / 说明: `--check-only` 在 autoload 实例注册前编译目标脚本，凡直接引用 `GameEvents`/`SupportData`/`LocaleFont` 等单例的脚本都会被误判，不能据此把代码改回 `get_tree().root.get_node(...)`。批量语法校验应在工程内用 SceneTree 脚本 `load()`（此时 autoload 已就绪），或直接跑 UI 回归。本机缺 `addons/godot_ai`（本地插件状态）会让回归脚本以 1 退出，但 `UI_UX_RESULT ... failures=0` 仍可信。
- Source / 来源: code | test
- Date / 日期: 2026-10-18


### [UI/Export] Tooltip 的 free() 在本机 Windows Release 模板中导致整脚本解析失败
- Evidence / 证据: `ui/hover_tooltip.gd:39-43`（`mount()` 的失效父节点分支）；用户导出的 `E:/Enter The Nyangeon v0.5.1.4-test.exe` 及其启动日志报 `Parse Error: Function "free()" not found in base self.`（`:41`）。本地复现入口 `.godot/tooltip_export_debug/release_loop.py`，最小对照入口 `minimal_release.py`，完整游戏验证日志 `game-regression-runtime.log`。
- Notes / 说明: 用户反馈 Windows EXE 内 Tooltip 完全不显示。实际 Release 启动在加载宿主脚本时即解析失败，尚未执行到该释放分支也会使所有绑定失效。独立最小工程排除了游戏资源与 Mod：`free()` 和 `self.free()` 均复现，改为 Node 的 `queue_free()` 后通过，失效父节点的未挂载宿主在帧末释放。源码运行及用编辑器引擎 `--main-pack` 挂载同一 EXE 都可通过，不能替代真正 Release 可执行文件的运行验证。本条结论限于本机 Godot 4.7 stable 官方模板的实测，未据此推断其它版本/平台。
- Validation / 验证: 原始 EXE 复现 `script_loaded=false`；最小 `free()` / `self.free()` 对照均 `valid=false`，`queue_free()` 为 `valid=true`。修复后的完整游戏 Release 专项 `checks=6 failures=0`，覆盖宿主加载、16 个 Label 初始化、真实道具卡键盘与鼠标显示、实际本地化正负效果、失效父节点释放。最终交付包恢复原主菜单并移除临时验证入口。
- Source / 来源: user | code | test
- Date / 日期: 2026-10-18

- Follow-up / 后续（2026-10-18，来源：code | test）：按用户要求扩查同类发行版差异：484 个本体脚本、37 个官方联机脚本夹具及 844 个本体场景/资源，在源码、真实 Windows Debug EXE、真实 Windows Release EXE 中均全部加载成功。其余 7 处 `对象.free()` 的脚本未出现同类解析失败；另用最小 Release EXE 执行显式 Node、推导 Node2D、动态变量三种接收者的 `.free()`，均正常释放，因此不要机械替换全部对象上的 free 调用。这里只验证调用形式和加载兼容性，不代表所有业务分支、所有平台均完成回归。报告见 `docs/CODEBASE_AUDIT_20261018.md`，证据见 `.godot/release_compat_20261018/`（本地，不提交）。

### [Boss] 新 Boss 必须走 BossSchedule；`enemy_group` 不会自动生成 BossCard
- Evidence / 证据: `script/boss_round_controller.gd:35-56`（`plan_for_round` 只读 `BossSchedule.entries/endless_entries`）、`scenes/manager/enemy_manager.gd:159-177`（有 plan 才走控制器）、`script/mod_manager.gd:545-552`（`get_mod_boss_schedules`）；`get_mod_boss_waves` 已移除，避免半支持的旧式波次路径。
- Notes / 说明: 只注册 `defs/bosses/*.tres` 不会自动刷 Boss；必须提供 `defs/boss_schedules/*.tres`，首版用 `BossEncounterEntry.trigger = ROUND_START` + `round_min/round_max` 指定回合。`BossCard.body` 根节点必须继承 `BossEnemy`，否则 `spawn_anim` 只告警、不会注册到控制器。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [Boss] 无动画时 enter/death 信号必须延迟一帧发
- Evidence / 证据: `script/boss_enemy.gd:_play_anim_and_emit`（`anim_name == ""` 时 `call_deferred("_emit_boss_signal", sig)`）、`script/boss_cinematic.gd:_wait_signal`（先 connect 再等待）。
- Notes / 说明: `BossCinematic.play_enter/play_death` 是先调用 `boss.play_*_anim()` 再 `connect` 等待信号；若无 AnimationPlayer 时同步 `emit`，信号会在 connect 前丢失，控制器卡在 8 秒超时/暂停树。实测无动画 Boss 死亡后 `paused=true`、`boss_round_active=true` 持续到超时；改为 deferred emit 后立即恢复并结算。
- Source / 来源: test
- Date / 日期: 2026-10-18

### [Boss] `round_timer` 旧信号与新 profile 的分工
- Evidence / 证据: `ui/round_timer.gd:102-119`（`boss_round()` 从 `BossRoundController.get_profile()` 取时间）、`:248-264`（超时模式 RAGE/END/FAIL/CUSTOM）、`:312-328`（`end_boss_round` 只在 `end_on_pickup` 时消费）、`script/boss_round_controller.gd:59-93`（控制器发旧 `boss_round_start` 兼容 BGM/计时）。
- Notes / 说明: 新 Boss 回合仍发旧 `boss_round_start`/`boss_round_end`，`main.gd` 的 BGM 与 `round_timer` 不需重写；`BossRoundProfile` 只覆盖时间/超时/结算策略。旧 `goliath`/`erosion_tower_group` 无 controller profile，继续走 90 秒/rage/青辉石原路径。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [Boss] 多 Boss 血条：HBox 最多 4 槽，死亡演出后移除并补位
- Evidence / 证据: `ui/boss_hp_group.tscn`/`ui/boss_hp_group.gd`（`max_visible=4`、`_active/_pending`、FIFO 补位、`_set_mode` 切换 `SingleRoot`/`MultiRoot` 并 reparent）、`ui/boss_hp_slot.tscn`/`ui/boss_hp_slot.gd`（`SingleLayout`/`MultiLayout` 可编辑子树，复刻 `boss_hp.tscn` 黑底/灰边/`TextureProgressBar` 白拖尾+红渐变/像素字体；单 Boss 原布局、名字 15→9 缩字号、多 Boss 最多两行/省略号/tooltip）、`script/boss_round_controller.gd:_ensure_hp_group/_remove_boss_bar/_dispose_hp_group`。
- Notes / 说明: `SingleRoot` / `MultiRoot` 统一 `(0,309)`、`640×44`；单 Boss 内容贴底部复刻原 `boss_hp.tscn`（名字 `-名字-` 覆盖血条左侧、HP16、血条 15px），多 Boss 名字上排只显示名字、HP10、血条仍 15px。超过 `max_visible_hp_bars` 的 Boss 只存在于等待队列，不显示血条/名字。Boss 死亡演出结束后才 `remove_boss`，剩余槽位按生成顺序回填。实测 5 个同时生成：4 槽 + 1 pending，首个死亡后自动补成 4 槽；单槽宽度 640、4 槽约 155；长名字降到 9px、两行；单/多 Boss 截图确认黑底/灰边/红色渐变/像素字体与旧 `boss_hp.tscn` 一致。视觉节点全部在 `boss_hp_slot.tscn`，脚本不再写位置；`auto_fit_name=false` 可保留手动字体。之前错位根因：单 Boss 父高 21、多 Boss 40，而场景按 40 调整并使用 `offset_bottom=-21`，运行到 21 高时布局被压成 0；统一 44 后修复。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [Boss/UI] HUD 视觉必须放 `.tscn`，脚本只绑数据；否则手动调整会被运行期覆盖
- Evidence / 证据: `ui/boss_hp_slot.tscn`（`SingleLayout`/`MultiLayout` 两套可编辑子树、`Background`/`Border*`/`BossName`/`BarArea`/`HP2`/`HP`/`HPValue`）、`ui/boss_hp_group.tscn`（`SingleRoot`/`MultiRoot` + HBox）、`ui/boss_hp_slot.gd`（只绑定/切换显隐/生成渐变纹理）、`ui/boss_hp_group.gd`（只切 Root、`reparent` 槽位）。
- Notes / 说明: 原 `BossHPSlot` 在代码里 new 控件并由 `_apply_layout()` 写位置/尺寸，用户在编辑器里改的任何布局都会被运行期覆盖。改为场景后，单/多布局、边框、字体、渐变、位置都在 `boss_hp_slot.tscn` 编辑；`BossHPGroup` 只切换 `SingleRoot`/`MultiRoot` 并 reparent 槽位。`auto_fit_name=false` 可关闭自动缩字号，保留手动字体。渐变抽到 `ui/boss_hp_gradient_white.tres` / `boss_hp_gradient_red.tres`，脚本按 BarArea 宽度生成 `GradientTexture2D`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-18

### [Boss] 多阶段必须由控制器串行播完整暂停演出
- Evidence / 证据: `script/boss_enemy.gd:_on_boss_hp_changed/_apply_phase_effects`（只切阶段/加 buff/无敌，不直接播动画）、`script/boss_cinematic.gd:play_phase`（完整 pause 外壳）、`script/boss_round_controller.gd:_on_boss_phase_changed/_run_phase_queue`（按 Boss 排队）。
- Notes / 说明: 阶段动画由控制器调用 `BossCinematic.play_phase()`，不能由 `BossEnemy` 自己 `play_phase_anim()` 后直接发信号，否则多个阈值同时跨过会并发 `paused=true`。无阶段动画时 `BossEnemy` 延迟一帧发 `boss_phase_anim_finished`，让 `BossCinematic` 先 connect。实测 40% HP 触发 phase_index=1、无敌 0.8s 后恢复。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [Boss] 无尽轮换使用 `endless_round`，不是全局 now_round
- Evidence / 证据: `resources/boss/boss_schedule.gd:endless_mode`、`script/boss_round_controller.gd:plan_for_round(..., endless_round)`、`_pick_entry` 的 `_rotation`、`scenes/manager/enemy_manager.gd` 传入 `endless_round`。
- Notes / 说明: 固定条目用全局回合号；`endless_entries` 用无尽回合号匹配 `round_min/round_max`，并按 `group` 过滤（建议 `lv_endless_boss`）。`ROTATION` 默认按条目顺序循环，`WEIGHTED` 保留权重随机；`first_round_add` 重置 rotation。不要让无尽表在普通无尽回合也命中，否则每回合都会出 Boss。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [Boss] 回合中途加入只预留接口，默认 ADD（已被 Phase 2.5 取代）
- Evidence / 证据: `resources/boss/boss_encounter_entry.gd`（`Trigger`/`Role`/`TimerMode`/`OnNormalTimeout` 字段）、`script/boss_round_controller.gd:95-114`（`arm_mid_round_encounters`/`fire_trigger` 当前只告警/缓存）、`:12`（`enable_mid_round_encounters=false`）。
- Notes / 说明: 首版只评估 `ROUND_START`；中途加入默认 `NORMAL_CONTINUES` + `Role.ADD` + `OnNormalTimeout.END_WITH_BOSS`，即普通计时/刷怪继续，Boss 死亡不结束回合。启用前不要依赖 `begin_encounter` 自动触发；需先实现触发器评估与普通回合超时策略。
- SUPERSEDED: 2026-10-18 Phase 2.5 已启用；`enable_mid_round_encounters=true`，触发器、三种 `IntruderEndMode`、`NormalSpawnMode`、missed 倒放离场均已实现并通过运行时探针。
- Source / 来源: code
- Date / 日期: 2026-10-18

### [Boss] BossHPGroup 必须实例化场景，不能 `.new()`
- Evidence / 证据: `ui/boss_hp_group.gd:13-16` 依赖场景子节点 `SingleRoot/MultiRoot`；`script/boss_round_controller.gd:_ensure_hp_group()` 改用 `load("res://ui/boss_hp_group.tscn").instantiate()`。
- Notes / 说明: `BossHPGroup.new()` 只有脚本、没有 `SingleRoot`/`MultiRoot`/`Bars`，`@onready` 为 null，运行时报 `Node not found: "SingleRoot"` 并中断 Boss 生成。血条预览/运行时都必须从 `.tscn` 实例化。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [Boss] 分时入场读秒不能只依赖 global_time_count
- Evidence / 证据: `script/boss_round_controller.gd:_process()` 用 0.1s 累加器推进 `encounter.spawn_elapsed_seconds`；`_on_global_time_count()` 只负责回合中途触发器。
- Notes / 说明: `GameEvents.global_time_count` 来自 `RoundTimer`，在某些场景（未正式开回合、暂停/测试）可能不推进；分时入场若只挂它，延迟 Boss 会永远 pending。改用控制器 `_process` 后读秒仍随 `paused` 停止，测试与正常回合一致。`FIRST_BOSS_READY` 的 `max_first_spawn_wait` 也走同一计时。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [Boss] `spawn_conditions` 与 `bosses` 下标必须对齐
- Evidence / 证据: `resources/boss/boss_round_entry.gd:spawn_conditions`、`script/boss_round_controller.gd:_init_scheduled_spawns()`。
- Notes / 说明: 条件数组按 `bosses` 下标对应；数量不足时缺失项按“立即入场”处理并告警，多余条件被忽略。`SCHEDULED` 模式应同时清空/设置 `spawn_mode`，否则容易误走旧 `SINGLE/SEQUENCE/SIMULTANEOUS` 路径。
- Source / 来源: code
- Date / 日期: 2026-10-18

### [Boss] `STOP_FOR_ROUND` 不能提前清 `spawn_stopped`
- Evidence / 证据: `script/boss_round_controller.gd:_resume_spawns_if_needed()`。
- Notes / 说明: 只有 `STOP_WHILE_BOSS_ALIVE` 可以在 Boss 死后恢复刷怪；旧逻辑先清 `spawn_stopped` 再判断模式，导致 `STOP_FOR_ROUND` 状态显示为已恢复（虽然全局 spawner 仍停着）。应先判断模式，再清标志。
- Source / 来源: code | test
- Date / 日期: 2026-10-18

### [UI] `branch_anim` 按「展开态」起步；分支切换不能被焦点转移重播 `select_card`
- Evidence / 证据: `ui/player_card.gd:108-145,194-246`（`_preview_open` 幂等守卫、`_switching` 先于 `grab_focus`、播放前 seek `select_card` 末帧、结束按焦点/触屏状态复位）、`ui/player_card_anim.tres:438-521`（`branch_anim` 只改立绘 x/alpha，首帧与 `select_card` 末帧一致）、`Button.focus_mode` 默认 `All`（鼠标按下会抢焦点）、`tests/test_ui_ux_regressions.gd:1033-1052`。
- Notes / 说明: 先播 `RESET` 会把整张卡瞬时打回收起布局，且 `branch_anim` 不改卡宽/面板位置，于是全程停在收起态；只删 `RESET` 还不够：鼠标按下分支按钮会抢焦点（`focus_mode=All`），`focus_entered → select_player_card()` 与松开时的 `grab_focus()` 都会把 `select_card` 从 t=0 重播（t=0 正是收起姿态），`branch_anim` 随即冻结在半展开态。修法是：`select_player_card()` 用 `_preview_open` 防重播；`switch_branch()` 先置 `_switching` 再交还焦点，并在分支动画前瞬间 seek `select_card` 末帧；结束再按 `_input_open` + 焦点（触屏用 `_touch_mode and on_touch`）套 `select_card`/`select_out` 末帧。`touch_out_player_card()` 与 `mouse_open()` 的 `select_out` 都要带 `_switching` 守卫，否则触屏摸别的卡、或难度页关闭会打断分支动画并永久卡住 `_switching`。另注意 `select_out` 的 `.:size` 末帧会先于 `.:custom_minimum_size` 应用，被旧的 165 夹住，seek 后要按 `Vector2(custom_minimum_size.x, size.y)` 补一次宽。官方测试用 `pressed.emit()` 绕过鼠标抢焦点，所以没暴露这条路径。
- Validation / 验证: `python tests/run_ui_ux_checks.py --godot <Godot 4.7> --character-focus-only` → `checks=15 failures=0`；临时探针（鼠标/键盘/触屏/焦点切走/难度页 17 项）→ `failures=0`。
- Source / 来源: user + code | test
- Date / 日期: 2026-10-19

### [Mod/Glory] 待处决敌人贴身接触不再造成伤害（接触锁 + 停火）
- Evidence / 证据: `mods/doom_slayer_izzy/script/glory_manager.gd:24`（`CONTACT_LOCK_META="ds_contact_lock"`）、`:47`（`_process` 的 has_buff 分支每帧 `_lock_contact`）、`:70-71`（`_mark` 里 `_lock_contact` + `_interrupt_weapons`）、`:85-97`（`_lock_contact`：`base_damage=0`、`knockback_force=0`、`source_type.clear()`）、`:100-116`（`_unlock_contact` 优先 `create_damage_data()` 重建）、`:144`（`_clear_enemy` 解锁）。本体：`script/hurt_box.gd:125-136`（`_emit_contact` 读敌人 `damage_data`，空 source → `Faction.of_source` 视为玩家侧 → 不 hostile）、`script/EnemyStateMachine.gd:22`（`frozen` 只让状态机 return）、`script/entity_ENEMY.gd:131-136`（`_interrupt_weapons`）。
- Notes / 说明: 待处决只设 `frozen=true` **不会**阻止贴身接触（玩家 HurtBox 接触探针读**敌人自身**的 `damage_data`）与定时器攻击。现标记时把敌人 `damage_data` 的 `base_damage`/`knockback_force` 归 0、`source_type` 清空（空 source 被 `Faction.of_source` 视为玩家侧 → 玩家接触探针直接跳过，连命中/i-frame/击退都不触发），并 `_interrupt_weapons()`；`_process` 每帧重锁，防 `create_damage_data` 重跑覆盖；解除时优先 `create_damage_data()` 按当前阵营重建（兼容被策反）。`_lock_contact` 在 `_mark` 的 server 判断之前调用，客机镜像也锁（避免本地预测受伤）。**残余**：标记前已发射的子弹、已生成的火场/毒环等持续伤害不处理（用户确认先不处理）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-19

### [BGM/Mod] 裁决态 BGM 不被随机轮替顶掉：本体 `bgm_rotate_gate` + mod 注册
- Evidence / 证据: `script/extension_hooks.gd:68`（`var bgm_rotate_gate: Callable = Callable()`）；`scenes/main/main.gd:51`（`bgm_loop_play` 内 `if ExtensionHooks.intercept_named("bgm_rotate_gate", []): return`）、`:238`（`_on_bgm_timer_timeout` 开头 gate + `BGM_timer.start()` 后 return）；`mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd:52`（`_ready` 里 `ExtensionHooks.add_hook(&"bgm_rotate_gate", ...)`）、`:69`（`_bgm_rotate_blocked()` 返回 `crucible`）、`:98`（`_exit_tree` 里 `remove_hook`）。
- Notes / 说明: 关卡内会顶掉裁决 BGM 的入口：`_on_bgm_timer_timeout`（捡紫水晶 `main.gd:42` + 240s `BGM_timer` → `bgm_slow_fade_out`）与 `bgm_loop_play`（`cut_finish`）。本体在这两处先查 `bgm_rotate_gate`：返回 true 则本次跳过（轮替入口仍 `BGM_timer.start()` 保持计时）。mod 只在**本地 PS**（`not _is_remote()`）注册、`_exit_tree` 解绑；镜像 PS 不注册（避免用远端裁决态挡本机轮替）。**Boss 曲路径不挡**（用户确认允许覆盖）。干净本体无该门 → `add_hook` 惰性、自动退化（不崩，但仍会被轮替）。⚠ 门在 `main.gd`/`extension_hooks.gd`（本体），**不在 mod pck 内**，需重新导出本体才生效。
- Source / 来源: user + code
- Date / 日期: 2026-10-19

### [UI] 触屏收回预览要按 `_preview_open`，不能只看 `on_touch`
- Evidence / 证据: `ui/player_card.gd:237-250`（`touch_out_player_card` 改为 `on_select == false and _preview_open`）、`ui/player_card.gd:257-270`（首次触摸时若 `_preview_open` 已为真则只接管 `on_touch`）、`scenes/main/menu_screen.gd:287-288`（选角自动聚焦首卡）、`ui/player_card.gd:111-118`（`add_card` 结束在非触屏模式先 `_apply_hover`）。
- Notes / 说明: 移动端进入选角时首卡由自动焦点走 `select_player_card()` 展开，`_preview_open=true` 但 `on_touch=false`；旧的 `touch_out_player_card` 只在 `on_touch` 为真时收回，导致触摸其它卡时首卡始终不播放 `select_out`。`_preview_open` 是展开状态的并集，`on_touch` 只标记触摸来源；触摸切换必须按 `_preview_open` 收回。另：已展开的卡被直接点击时要先把 `on_touch` 接管为 true 且不重播 `select_card`，否则会先收回再展开。用户确认保留“进入即展开首卡”，只修触摸收回。
- Validation / 验证: `python tests/run_ui_ux_checks.py --godot H:\Godot_v4.7-stable_win64_console.exe --character-focus-only` → `checks=19 failures=0`（新增触屏首卡收回检查）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-19

### [Boss] Goliath 冲撞方向不能被基类 `time_count()` 覆盖：用独立 `charge_dir`
- Evidence / 证据: `script/entity_ENEMY.gd:300-302`（`time_count()` 每次都 `direction = get_direction_to_player()`）、`scenes/enemies/boss/goliath.gd:244-257`（子类仅在 `move_mode != 1` 时重设 `direction`）、`:281-350`（冲撞移动/反弹改读 `charge_dir`）、`:428-447`（蓄力结束写入起手方向）。
- Notes / 说明: 基类 `time_count()` 由 `GameEvents.global_time_count` 每 0.1 秒驱动一次，即便 `move_mode == 1` 也会先把 `direction` 拉回玩家方向；Goliath 原来的“冲撞期间不改 direction”实际无效，轨迹会持续追踪玩家。冲撞方向必须用独立字段 `charge_dir`（起手按玩家方向 ±10°，撞墙后按玩家方向 ±15° 重新瞄准，并用 30° 最小离墙法线分量与 3 帧撞墙锁防止贴墙连撞），移动与朝向翻转都读它；`direction` 继续留给非冲撞状态。非 Fever 反弹速度为撞墙瞬间 `velocity.length() × 0.5`，Fever 不减半。
- Source / 来源: user + code
- Date / 日期: 2026-10-19

### [Boss] Goliath 周期出招靠 `move_mode` 动画轨推进；破手用 `explosion_anim`
- Evidence / 证据: `scenes/enemies/boss/goliath.gd:405-475`（`transition_state`）、`:815-978`（HP 破手 + 周期调度）、`:524-654`（`L_shoot`/`R_shoot` 短路与射击取消）、`scenes/enemies/boss/goliath.tscn`（`BodyAnim` 的 `shoot_ready` t=2→`move_mode=3`、`turret_shoot_ready` t=0.5→5、`RESET`→0）、`scenes/enemies/boss/explosion_anim.gd`。
- Notes / 说明: 周期调度只负责在 IDLE 结束后把 `move_mode` 置为 2/1/4；`SHOOTINGREADY`→`SHOOTING` 与 `TURRETREADY`→`TURRETSHOOT` 仍由 `BodyAnim` 的 value track 推进。因此 `_shoot_template` 必须在置 `move_mode=2` 前写好；取消射击时仅把 `move_mode=0` 不够，`shoot_ready` 的 t=2 track 仍可能把状态推回 `SHOOTING`，`transition_state(SHOOTING)` 必须再用 `_shooting_disabled/_shoot_cancel` 守门。60% 随机爆一只手后射击 2→1 且 `L_shoot`/`R_shoot` 按已毁手短路；30% 爆另一只并取消当前射击。手臂特效 `explosion_anim` 的 `explosion` 一次性、`smoke` 持续到死亡/重置，音效 4 次 × 0.25s；远端通过 `goliath_visual` 回放 `destroy_*_arm_visual`，镜像不得自己随机选边。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-19

### [Boss] Goliath 阈值打断：所有攻击协程都要 generation 守门
- Evidence / 证据: `scenes/enemies/boss/goliath.gd:428-500`（`transition_state` 的 SHOOTING/TURRETSHOOT 守门与远端离开攻击态兜底）、`:544-682`（射击 generation/cancel）、`:683-737`（大炮 generation/cancel）、`:739-774`（冲撞 generation）、`:859-970`（HP 阈值与 `_interrupt_*`）、`:1006-1041`（1.5s override 与周期步进）。
- Notes / 说明: 60% / 30% 时若 `move_mode` 为 1/2/3/4/5，`_interrupt_current_attack()` 立即打断当前招式，设置 `_next_attack_delay_override = attack_interval`（1.5s），IDLE 后由 `_interval_before_next_step()` 消费；IDLE 时跨阈值不打断、不额外加时。射击用 `_shoot_generation + _shoot_cancel` 并停止两个 shoot timer；冲撞用 `_charge_generation`，蓄力与 `_end_charge` 的 `await` 后都校验；大炮用 `_big_gun_generation + _big_gun_cancelled`，`TURRETSHOOT` 入口守门，**只停止后续发射**，已发射炮弹继续爆炸/散射。`SHOOTINGREADY` / `TURRETREADY` 入口重置对应 cancel 标记，避免一次打断永久挡掉后续招式；远端另用 `interrupt_attack_visual` 和离开攻击态的 transition 兜底停止本地协程。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-19

### [Boss] Goliath 大炮落点夹取与冲撞防连墙
- Evidence / 证据: `scenes/enemies/boss/goliath.gd:300-369`（撞墙锁读帧顺序）、`:345-369`（冲撞反弹改为玩家方向 + 最小离墙角）、`:690-737`（大炮落点 `MapBounds.nearest_inside`）、`script/map_bounds.gd:70-75`（`ensure_ready` / `nearest_inside`）。
- Notes / 说明: 大炮随机落点先加 ±150，再 `MapBounds.nearest_inside(shoot_p, 0.0)` 夹到墙体内壁凸包；`MapBounds.ensure_ready()` 保证首次 1s tick 前也不会静默失效。冲撞反弹改为玩家方向 ±15°，用 30° 最小离墙法线分量（`sin30°=0.5`）防止玩家贴墙时直接再次撞同一面墙，并用 3 帧撞墙锁避免角落连续反弹。锁的读帧顺序必须是“先算 `can_check_bounce = _charge_bounce_lock <= 0`，再递减”，否则实际只跳过 2 帧。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-19

### [Boss][Coop] Goliath 视觉事件按 `net_id` 定向；镜像手枪/大炮改视觉-only
- Evidence / 证据: `scenes/enemies/boss/goliath.gd:140-176`（`_local_net_id`/`_net_boss_visual`/`net_id` 过滤）、`:544-682`（镜像 `L_shoot`/`R_shoot` 跳过投射物、`sync_shoot_template_*`）、`:690-737`（host 真实炮弹 + `spawn_cannon_visual`、`_coop_visual_broadcast`）、`:730-737`（镜像纯视觉炮弹）、`:891-941`（断手状态、`get_network_boss_visual_state`、远端无条件打断）；`scenes/enemies/cannon_bullet.gd:20-82`（`visual_only` 不生成爆炸/子子弹、自动释放）；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:1255-1273,5836-5852,8119-8133`（加入/重连后定向补发）。
- Notes / 说明: 所有 `goliath_visual` 载荷带 `net_id`，远端只处理匹配自己的事件；射击模板通过 `sync_shoot_template_random/strafe` 提前同步，镜像不再使用默认模板。镜像只保留枪声/火光/蓄力与炮塔动画，跳过 `L_launcher`/`R_launcher`/`StaticBullet1`/真实 `cannon_bullet` 的本地生成，host 的投射物走 `ProjectileSpawner` 权威同步。host 的真实炮弹不是经 `ProjectileSpawner` 生成，池化复用不会触发通用 `child_entered_tree` 广播；改为主动 `spawn_cannon_visual` 带夹取落点，host 炮弹标 `_coop_visual_broadcast` 防通用视觉通道重复，镜像用 `cannon_bullet.visual_only` 生成纯视觉炮弹（`add_explosion`/`shoot_bullet` 直接返回）。中途加入/重连由 `_send_boss_visual_states_to_peer()` 在 `_send_existing_enemies_to_peer()` 之后定向补发断手事件，避免旧客户端重复特效，也不需要升协议版本。另：Godot 4.7 下 `get_meta("net_id", null)` 在不存在 meta 时会报错，统一用 `has_meta` + `_local_net_id()` 取值。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-19

### [Boss] 固定第 15 关也是 Boss 关；lv15 / lv20 同名 Boss 必须按 EnemyCard.id 归一
- Evidence / 证据: `scenes/manager/enemy_manager.tscn:93,98,100`（`lv15` / `lv20` / `lv_endless_boss` 均为 Boss 池）、`scenes/enemies/enemies_spawn/goliath_spawn.tscn`、`tower_spawn.tscn`、`goliath_spawn_lv_20.tscn`、`tower_spawn_lv_20.tscn`（均 `boss_round=true`）；`scenes/manager/enemy_manager.gd:204-270`（权重抽取/身份归一/衰减与加成）。
- Notes / 说明: 除第 20 关外，普通模式第 15 关（`lv15`）也是 Boss 关，而 `lv15` 与 `lv20` 是同一 Goliath / Erosion Tower 的两套场景（基础版与 lv20 版）。若按 `PackedScene.resource_path` 记账，同名 Boss 会被当成两个；权重必须取生成场景根节点的 `enemy` 数组里的 `EnemyCard.id`（`goliath` / `erosion_tower`）作为身份，才能让第 15、20 关和无尽共享衰减/加成。`goliath_spawn_lv_10.tscn` 当前未被 `enemy_manager` 引用。`hujiu` 第 5 关原先强制 `spawn_num=1`（Tower），2026-10-19 已移除，与其它 Boss 关一样走权重。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-19

### [Boss] 乱入原生 Boss 必须显式跳过 `boss_round_end` 与运镜/暂停
- Evidence / 证据: `scenes/enemies/boss/goliath.gd`（`on_dead()` 的 `emit_boss_round_end` 与 `boss_enter_anim`/`boss_death_anim` 的相机/暂停分支）、`scenes/enemies/boss/erosion_tower_group.gd`（`boss_dead()` 与同名演出分支）、`script/spawn_anim.gd`（`is_intruder` → 实体 meta `boss_intruder`）。
- Notes / 说明: 本体 Goliath / 侵蚀之塔在死亡时会 `emit_boss_round_end()`，乱入若沿用旧路径会触发 `round_timer.rage_mode_end()`，把普通回合的 60s 计时直接停掉；入场/死亡演出还会 `camera_move` + `get_tree().paused`。乱入标记必须在两个 Boss 的入口/死亡流程里统一判断，只跳过相机/暂停与 `boss_round_end`，保留入场、死亡动画与 30% 金币掉落。`erosion_tower_group` 的入场演出是非暂停分支时仍要 `await` 入场动画后调用 `attack_state()`，否则乱入塔不会攻击。
- Source / 来源: code + test
- Date / 日期: 2026-10-20

### [Boss] `erosion_tower_group` 根节点不在 `Enemy` 组，普通清场不会回收
- Evidence / 证据: `scenes/enemies/boss/erosion_tower_group.tscn:59`（根节点无 `groups`；子塔才是 `BOSS`/`Enemy`）、`scenes/main/main.gd:99-108`（只遍历 `EnemiesRoot` 的直接子节点并筛 `Enemy` 组）。
- Notes / 说明: 普通 `enemy_clear_unit()` 只处理 `EnemiesRoot` 下**直接**子节点中的 `Enemy` 组；塔组根节点不入组，所以塔组必须在自身死亡/离场时 `queue_free`，或由调用方用显式索引清理。Boss 乱入用组 `"BossIntruder"` 同时登记 `spawn_anim` 与落地实体，`round_end` / `game_over` / FEVER 超时统一 `queue_free`；仅依赖现有清场会留下塔组根节点。
- Source / 来源: code + test
- Date / 日期: 2026-10-20

### [Enemy] 回合清场不能走 `on_dead` / `stats.is_dead`，只能走纯视觉入口
- Evidence / 证据: `scenes/main/main.gd:enemy_clear_unit()`；`script/entity_ENEMY.gd:play_clear_death()`（`DeathAnim`/`DEATH_ANIM_SCRIPT.spawn_for_enemy`）；`scenes/enemies/enemy_tank.gd:play_clear_death()`（`ExplosionAnim.play_explosion_only()`）；`script/death_anim.gd:on_death_anim(play_sound)`。
- Notes / 说明: 清场时直接调用 `on_dead()` 或 emit `stats.is_dead` 会触发 `_coin_drops`、`settle_converted_clear`/分数、`emit_enemy_dead_position` 等 gameplay 结算，且坦克类会播专属死亡动画/伤害爆炸。清场必须只调用视觉入口：普通敌人复用 `DeathAnim` 的 `death_gpu`（传 `play_sound=false`），坦克用 `ExplosionAnim.play_explosion_only()`（不启动 `smoke`、不播音效）。`clear_death_played` meta 用于去重（`enemy_clear_unit` 可能被 `round_end`/`round_upgrade` 多次触发）；`ExplosionAnim.play()` 保留黑烟+音效，仅 Goliath 手部使用。清场视觉按一次性实例化 + 约 1.2 秒后 `queue_free`，不入对象池。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-20

### [Chip] 词条 Buff 必须在 `active_state()` 前应用并立即刷新属性
- Evidence / 证据: `script/spawn_anim.gd:spawn_enemy_body()`（`update_body_ability()` → `ChipManager.apply_to_enemy()` → `active_state()`）；`script/entity_ENEMY.gd:active_state()`（`stats.spawn_hp()`）；`scenes/manager/buff_manager_base.gd:_host_refresh()`（延迟到 `_process` 才 `update_body_ability()`）。
- Notes / 说明: `active_state()` 会按当前 `stats.max_hp` 回满血，词条的血量 Buff 必须在它之前应用；应用后还要立刻再调一次 `stats.update_body_ability()`，不能只依赖 `BuffManagerBase` 的延迟刷新，否则首帧仍按旧上限回血。Boss 默认由 `chip_include_boss=false` 排除，白名单/标签匹配不能替代该门槛。
- Source / 来源: code + test
- Date / 日期: 2026-10-20

### [UI/Input] 难度悬停保持与移动端预览必须分开 mouse/focus 与 touch 路径
- Evidence / 证据: `project.godot:213`（`pointing/emulate_mouse_from_touch=false`）；`ui/level_button.gd`（`mouse_in` / `mouse_out` / `previewed`）；`ui/level_select.gd`（`_on_level_previewed`、`prepare_level_selection`）；`ui/gamemode_button.gd`（自动/手动浩劫标记）。
- Notes / 说明: 难度展开与焦点解耦：`level_button` 用 `_preview_open` + `open_preview/close_preview` 管状态，`level_select` 只保留一个 `_open_level_button`；焦点移到支援/模式或鼠标移出难度时不收起，展开另一个难度、确认、返回或重新进入时才收起。移动端不会产生 `mouse_entered`/`focus_entered`，必须由第一次 `InputEventScreenTouch` 显式触发 `open_preview()`，第二次触摸才确认。浩劫自动勾选用 `_havoc_auto_selected` 与 `_auto_toggle` 区分来源：只有自动勾选会在悬停其它难度或离开难度页时撤销，手动勾选保留。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-20

### [UI] `enemy_mod_box` 与 `ENEMY MOD` 标题是兄弟节点，必须同时隐藏滚动容器
- Evidence / 证据: `ui/gamemode_button.tscn`（标题/分隔线在 `.../VBoxContainer/VBoxContainer`；`enemy_mod_box` 在平级的 `.../VBoxContainer/ScrollContainer2`）；`ui/gamemode_button.gd:_update_enemy_mod_visibility()`（同时切换 `enemy_mod_section` 与 `enemy_mod_scroll`）。
- Notes / 说明: 只隐藏标题所在的 `VBoxContainer` 不会隐藏 `ScrollContainer2` 下的敌人词条卡片。未开启 `havoc` 时必须同时隐藏 `enemy_mod_section` 和 `enemy_mod_scroll`；不要再加 `enemy_mod_hint`。`ENEMY MOD` 固定英文、禁用自动翻译，标题显示 `(当前/要求)`；数量不足点击开始时播放标题字体闪红和失败音效。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-20

### [Chip] 硬化外壳是次数盾，扣血前必须在 `HealthComponent` 结算
- Evidence / 证据: `script/EnemyStats.gd`（`shield_active/shield_max_hits/shield_hits`、`shield_broken`、`reset_shield()`）；`script/health_component.gd:_take_damage_internal()`（扣血前把本次伤害设为 1、耐久 -1、归零时发 `shield_broken`）；`resources/buff/components/shield_component.gd`（10 + 2×回合、封顶 40，破盾移除 Buff）。
- Notes / 说明: 次数盾必须在 `HealthComponent` 扣 `stats.hp` 前处理，才能让飘字/`damage_taken` 都是 1；不能在 `spawn_hp()` 重置护盾，否则 `spawn_anim` 刚施加的 Buff 会在 `active_state()` 里被清掉。护盾耐久按回合在 `activate()` 时固定，不随敌人存活跨回合成长，也不重生；破盾当击仍只扣 1。`Game.one_hit_kill` 跳过护盾。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-20

### [Chip] 同场上限是“存活/生效标记数”，不是每回合生成数
- Evidence / 证据: `scenes/manager/chip_manager.gd`（`_active_count`、`_marked`；`apply_to_enemy()` 达上限直接返回；`_on_marked_enemy_dead` / `_on_marked_buff_expired` / `_on_marked_enemy_exiting` 调用 `_release_marked()`）；`ui/chip_hud.gd`（计数实时刷新）。
- Notes / 说明: 词条敌人死亡、被清除，或该词条的全部 Buff 失效（例如硬化外壳破盾）时立即释放 1 个同场名额；后续敌人补位。`prepare_round()` 清零并清空 `_marked`，旧敌人的迟到信号不会误扣新回合。词条改为全局共享池，不再按词条分配固定名额；权重只决定每次新附着选哪个词条，权重更新放到回合结束。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-20

### [UI] 词条 HUD 默认不显示计数，CanvasLayer 用 layer=1
- Evidence / 证据: `ui/chip_hud.tscn`（`layer = 1`、`Root.scale = Vector2(0.5, 0.5)`）；`ui/chip_hud.gd`（`debug_show_counts`、count Label 默认隐藏）；`scenes/player/momoi.tscn`（pause CanvasLayer layer=3）。
- Notes / 说明: 战斗内词条 HUD 只保留图标，不显示标题和名称；同场计数仍由 `ChipManager.get_chip_counts()` / `chip_assigned` / `chip_released` 提供，仅在 `debug_show_counts=true` 时显示。ChipHud 必须与 `RoundTimer` 同为 layer 1，否则会盖住 layer 3 的 pause 菜单；整体缩放 50% 用 Root 的 scale + 中心 pivot 实现，Root 透明度 0.7，位置贴近 `RoundTimer` 下方。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-20

### [VFX] 护盾特效复用 tower `defense_mod` 时的尺寸/定位坑
- Evidence / 证据: `scenes/debuff/shield_effect.tscn`（复制 `ripple` shader、内外渐变和 `defense_shield_anim`）；`scenes/debuff/shield_effect.gd:fit_to_enemy()`；`resources/buff/components/shield_component.gd:activate/deactivate()`。
- Notes / 说明: 复制 tower `defense_mod` 时内部 `Node2D` 的 `position` 必须归零，tower 的 `(0,-44)` 是 Boss 专用偏移。护盾特效只随 ShieldComponent 生命周期创建/释放，tower 本体保持原样。`SUPERSEDED: 2026-10-20` 后续统一改为按 `HurtBoxShape2D` 形状最大边 ×1.1 自适应，不再读取 Sprite；原 `AnimatedSprite2D`/`get_rect` 逻辑已删除。
- SUPERSEDED: 2026-10-21 不能递归 `find_child("HurtBoxShape2D")`：`tester_automaton_shield` 会先命中 `Graphics/Shield`，其它敌人也可能命中最先遍历到的子部件/弱点；必须取 `body.hurt_box_shape_2d` / `HurtBox/HurtBoxShape2D` 本体框，并让特效每帧跟随旋转的 HurtBox。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-20

### [Coop/Mod] mod pck 内 `.tscn` 的 ext_resource UID 必须与 `.tres` 头部 UID 一致
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_theme.tres:1`（`uid://cq6shkh3j5pwh`）；`ui/coop_menu.tscn:13`（原引用 `uid://0ivk887ius3a`）；`build_coop_mod.ps1` 的 PCKPacker 构建日志出现 `ext_resource, invalid UID ... using text path instead`。
- Notes / 说明: 编辑器会靠 `.godot/uid_cache.bin` 把旧 UID 解析到路径，所以镜像内看不出来；PCK 不带 UID 缓存，构建/运行时会报警并回退文本路径。同步编辑器生成或改名的 `.tres` 后，若 `.tscn` 仍引用旧 UID，需把引用改成 `.tres` 头部的新 UID（或去掉 `uid` 属性），再重新打包。
- Source / 来源: code + test
- Date / 日期: 2026-10-20

### [Combat] 腐化的有效上限必须收口在 `Stats.hp` setter，且 `corruption` 声明在 `hp` 之前
- Evidence / 证据: `script/Stats.gd`（`corruption` setter、`get_effective_max_hp()`、`hp` setter 的 overflow/clamp）、`script/player_health_component.gd:_accumulate_corruption_on_hit()`、`scenes/item/medical_kit.gd`、`ui/game_ui.tscn`（`Corruption_HP_BAR`）
- Notes / 说明: 腐化不是直接改 `max_hp`（会被 `PlayerData._recompute_player_ability()` 覆盖），而是独立 `corruption` + 有效上限。治疗/溢出/赋值全部经 `Stats.hp` setter，故只改这一处即可覆盖所有治疗来源；`heal_overflow_to_t_hp` 的溢出基准也必须同步改为有效上限。`@onready` 初始化不经过 setter，但运行期外部赋值会访问 `hp`，因此 `corruption` 必须声明在 `hp` 之前；`max_hp` 被 `PlayerData` 重算后要调 `reclamp_corruption()`，否则腐化可能超过 `max_hp-1`。
- Source / 来源: code + test
- Date / 日期: 2026-10-20

### [Coop/Mod] 玩家状态 RPC 追加字段必须同步 sanitize 索引、proxy 赋值顺序与协议版本
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_sanitize_player_state` 返回 13 项、`_server_receive_player_state`/`_apply_player_state` 末尾追加 `corruption`）、`net/coop_player_proxy.gd:apply_state`、`net/coop_health_bar.gd`
- Notes / 说明: `_sanitize_player_state` 的每个返回值靠位置索引传递，追加字段必须同时改所有 `safe[i]` 调用点，否则会把腐化当 hp/t_hp 使用。镜像赋值顺序必须是 `max_hp → corruption → max_t_hp → t_hp → hp`：腐化 setter 依赖 `max_hp`，hp 又要按有效上限钳制。RPC 参数数量变化即破坏旧客户端，必须递增 `PROTOCOL_VERSION`（本次 4→5）并同步两份副本与 `mod.json`。
- Source / 来源: code + test
- Date / 日期: 2026-10-20

### [UI] 血条大数值：HP_VAL / +临时生命 / -腐化不能放在同一水平带
- Evidence / 证据: `ui/game_ui.tscn`（`HP_VAL` / `T_HP_VAL` / `CORRUPTION_VAL` / `Life_value` 的 offset 与 `scale=2`）；用户反馈 4 位数时腐化数字严重重叠
- Notes / 说明: `Label` 默认不裁剪，`scale=2` 会把 4 位数文本放大到约 108px，超过 133px 血条的中段；三个标签锚点都在同一带内时会互相覆盖。`+N` / `-N` 必须放到血条右下的独立两行（相对中心 `offset 25..62`，即屏幕约 151..188，字号 10、`scale=1`），避开 `Life_value`（`x3`）、下方弹药数字与玩家名。`HP_VAL` 5 位数时约 132px，仍能放进血条，但会贴近 `xN`，极端数值如需再处理。
- Source / 来源: user + code
- Date / 日期: 2026-10-20

### [UI] 本地血条层级：临时生命必须绘制在腐化之上（用户裁定）
- Evidence / 证据: `ui/game_ui.tscn`（`HP_BAR` 子节点顺序：`HP_BAR_3` → `Corruption_HP_BAR` → `Temporary_HP_BAR2` → `Temporary_HP_BAR`；`Corruption_HP_BAR.show_behind_parent=true`）；用户反馈临时生命段被腐化紫段盖住。
- Notes / 说明: `show_behind_parent` 的子节点在父节点自身纹理之前绘制，多个同标志兄弟按声明顺序绘制；因此要让青色临时生命盖住紫色腐化，`Corruption_HP_BAR` 必须设 `show_behind_parent=true` 并排在 `Temporary_HP_BAR2` 之前。此改动只影响本地 HUD 表现，不改 `Stats` 有效上限或腐化数值；联机队友头顶 44×4 小血条按用户要求不调整。极端情况下临时生命会暂时完全盖住紫段，腐化量仍以 `-N` 为准。
- Source / 来源: user + code
- Date / 日期: 2026-10-20

### [Combat] 召唤物转伤必须用 flag 与玩家直接受伤区分，否则会误积累腐化
- Evidence / 证据: `script/summoned_health_component.gd:92-98`（`max_hp <= 0` 的召唤物把伤害转发给 `GameEvents.deal_damage_to_player`）、`scenes/player/ichika/ichika_ps.gd:75-76`（转伤接到玩家 `health_component.take_damage`）、`script/player_health_component.gd:142-145`（腐化积累入口）
- Notes / 说明: Ichika 的 mobu 等召唤物 `SummonedStats.max_hp` 默认为 0，受伤时不扣自身生命而是转给玩家；转伤与玩家直接受伤共用 `take_damage`，仅凭 `source_type` 无法区分（两者都是敌方来源）。必须在 `SummonedHealthComponent` 转发时复制伤害并追加 `GameTags.SUMMON_TRANSFER`，玩家侧据此跳过 `corruption_power` 与连续受伤窗口，否则召唤物挨打也会给玩家积累腐化。转伤不更新 `_last_corruption_hit_msec`，因此不会把两次玩家直接受伤的窗口接起来。
- Source / 来源: code + test
- Date / 日期: 2026-10-20

### [Chip] 提交清理时误删词条运行接入：`prepare_round()` 与 `apply_to_enemy()` 必须同时保留
- Evidence / 证据: `scenes/manager/enemy_manager.gd:round_enemy_spawn_start()`（联机 gate 后 `prepare_round()`）；`script/spawn_anim.gd:spawn_enemy_body()`（`update_body_ability()` 后、`active_state()` 前 `apply_to_enemy()`）；`git show b581a9d` 不含这两处，OpenCode 快照 `399b5cb...` 保留正确版本。
- Notes / 说明: 2026-10-21 整理 TORMENT 提交时，`Remove-ChipBlock` 脚本把两处词条接入从工作区/暂存区剔除，导致词条选择仍保存但 `_active_chips` 为空、HUD 无图标、敌人无 Buff。分离提交时不要用会改写工作区的脚本剔除功能代码；若必须拆分，只操作 index，提交后检查这两个调用点并跑一次刷怪冒烟。
- Source / 来源: code + git
- Date / 日期: 2026-10-21

### [Combat/Chip] 延迟死亡必须在扣血前拦截并锁 1 血，`EnemyStats.hp` setter 会同步触发死亡
- Evidence / 证据: `script/EnemyStats.gd:86-97`（`v <= 0 && !dead_lock` 时同帧 `is_dead.emit()`、`emit_enemy_dead_score`）；`script/entity_ENEMY.gd:562-564`（`_coin_drops`/`on_dead` deferred）；`script/health_component.gd`（`_fatal_damage_guards` 位于护盾与 `one_hit_kill` 之后、overkill/扣血之前）；`resources/buff/components/frenzy_delay_death_component.gd`
- Notes / 说明: 不能在 `is_dead` 之后补救（掉落/分数已结算）；守卫只把 `final_damage` 降到 `hp-1`，期间重复致命返回 0 且不续时。4 秒到期用 `take_damage(..., bypass_hook=true, resolved_damage=hp)` 走原生死亡链，保证击杀归属/掉落/击杀类道具一次性结算；`Game.one_hit_kill`、`stats.is_test_target`、`GameTags.EXECUTE_DAMAGE` 跳过拦截。策反/回池/清 Buff 通过 `deactivate()` 注销 guard 并停表。
- Source / 来源: code + user
- Date / 日期: 2026-10-21

### [Mod/IZZY] 处决伤害必须带 `GameTags.EXECUTE_DAMAGE` 才能穿透延迟死亡
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd:493`、`mods/doom_slayer_izzy/script/glory_manager.gd:135`（`TRUE_DAMAGE + ds_execute + EXECUTE_DAMAGE`）；`mods/doom_slayer_izzy/entry/doom_slayer_izzy_entry.gd:60-68`（待处决只放行 `ds_execute`）；`glory_manager.gd:160-203`（进待处决即 `_settle_on_entry`，清标记时 `_restore_stats`）
- Notes / 说明: izzy 的 `enemy_damage_interceptor` 仍在 `take_damage` 最开头，优先于狂怒 fatal guard；首次致死命中可能先被 `try_stagger` 标成待处决（60%），这是 hook 顺序决定的抢占。若处决伤害被狂怒 guard 拦下，会出现「处决失败 + 已提前结算后再恢复 + 4 秒真死再结算」的重复分数/金币，因此确认处决优先。两条拦截通道语义不同，不要合并。
- Source / 来源: user + code
- Date / 日期: 2026-10-21

### [Chip] 狂怒燃烧条的坐标空间与逐实例材质
- Evidence / 证据: `scenes/debuff/frenzy_effect.gd:13`（`visual_scale` 默认 0.5）、`:103-122`（`shrink` 统一缩尺寸/间距；effect 根 `position = center`，bar Y 需 `head_top - center.y`）、`:133-172`（`_sprite_bounds` 返回本体局部 Y；`AnimatedSprite2D` 走 `SpriteFrames.get_frame_texture()`）、`scenes/debuff/frenzy_effect.tscn:8-12`（`resource_local_to_scene = true`）
- Notes / 说明: 特效根在 `HurtBox` 中心，但视觉 sprite 顶部是敌人本体局部坐标；两者混用会让 bar 多偏移一个 `center.y`（`visual_scale=1.0` 时约 20px 而不是 10px，`0.5` 时约 10px 而不是 5px）。`AnimatedSprite2D` 没有 `get_rect()`，直接调用会在运行时报 `Invalid call`，需回退到 `SpriteFrames` 当前帧纹理并按 `centered`/`offset` 还原矩形。`BurnBar` 的 `ShaderMaterial` 必须逐实例（场景 `resource_local_to_scene` + `_ready()` 内 `duplicate()`），否则多个狂怒敌人共享同一个 `progress`。整体缩放用 `visual_scale` 统一缩尺寸与间距，不要直接给特效根加 `scale`：根在 HurtBox 中心，根缩放会把 bar 一起往身体中心拉，破坏头顶位置。
- SUPERSEDED: 2026-10-21 用户要求统一头顶 VBox；`BurnBar` 不再由 effect 本地定位、不再用 `visual_scale` 缩放，改由 `Enemy.OverheadStack` 底部锚定，条底距 BuffCard 2px。旧「bar 多偏移 center.y」结论仅适用于 fallback 分支。来源：user。
- Source / 来源: code + test
- Date / 日期: 2026-10-21

### [Chip] 狂怒头顶显示统一走 `Enemy.OverheadStack`，透明 padding 不应参与定位
- Evidence / 证据: `script/entity_ENEMY.gd:616-691`（`_setup_overhead_display` / `add_overhead_item` / `_refresh_overhead_layout`）、`:693-763`（当前动画逐帧 opaque used-rect + 静态缓存）、`:765-788`（HurtBox/CollisionShape 回退）；`scenes/debuff/frenzy_effect.gd:135-145`（`_attach_bar`）、`:147-154`（`_sync_bar_shader_size`）、`:40-46`（`_exit_tree` 摘除 bar）；`scenes/debuff/frenzy_effect.tscn`（`BurnBar` 44×6、`SHRINK_CENTER`、`resource_local_to_scene`）。
- Notes / 说明: 用户要求所有敌人/Boss 头顶内容统一成 VBox：`BuffBox` 固定最底部，额外内容（狂怒燃烧条/未来状态）自动往上排。`Enemy._ready()` 运行时接管原 `MarginContainer/BuffBox`，不逐场景改 18 个 `.tscn`；`BuffBox` 的 unique name 与 BuffManager 路径保持兼容。布局必须用 `OverheadStack.get_combined_minimum_size()` + `MarginContainer` 50% 缩放，底边 = 可见头顶 - 2px；VBox `separation=4` 在 50% 下视觉为 2px。**不要用整帧顶边**：`sweeper` 帧 64×64 但内容约 26×21、顶部约 25px 透明 padding，会把头顶抬高；应按当前动画帧纹理 `get_used_rect()`（`AtlasTexture` 先裁 region）加 `centered`/`offset`/sprite transform 求最高不透明点，并缓存 used-rect。隐藏的 `BurnBar` 不占 VBox 高度，`begin_burn()` 显示后 VBox 自动向上增长。实测 sweeper：未致命 stack `18×26`；致命后 `44×36`、bar `(309,138,22,3)`、buff `(309,143,22,13)`，卡底到头顶 2px。截图用 `SubViewport` 可避开主菜单遮挡；MCP `game` 截图在暂停+多帧后可能出现残影，以 `SubViewport.get_texture().get_image()` 落盘为准。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-21

### [Coop/Chip] 狂怒延迟死亡的击杀归属仅保证 host 侧结算
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd:2236-2264`（客机命中由 `enemy_damage_interceptor` 拦截并上报 host，客机本地不跑扣血）；`mods/etn_coop/net/coop_net.gd:8269`（host 向归属端 `rpc_id(..., "_remote_enemy_proc", ..., killed, score)`）；`:8627`（`_remote_enemy_proc`）
- Notes / 说明: 延迟死亡期间 host 不死亡、不上报 killed；4 秒后由 host 的 Timer 结算，客机的击杀/得分/EX 充能归属会丢失或记到 host。本次确认只做单机语义，`mods/etn_coop` 不改；联机遇到时按此限制说明，不视为回归。
- Source / 来源: code + user
- Date / 日期: 2026-10-21

### [Combat/Chip] 重甲的动态承伤乘区必须用组件除回旧系数，并按命中事件刷新
- Evidence / 证据: `resources/buff/components/armored_component.gd`（`_target_factor()`、`_apply_factor()`、`UPDATE_EPSILON`）；`script/EnemyStats.gd:172`（`global_hurt_damage = base × global_hurt_damage_mult`）；`script/EnemyStats.gd:74-134`（`hp` setter 的 `hp_change_cd` 10Hz 节流）；`script/health_component.gd:257`、`script/health_component.gd:168`（`damage_taken` 逐击发射）。
- Notes / 说明: 词条重甲从静态 `modifiers`（×0.7）改为按 `hp/max_hp` 动态系数：`factor = clamp(1.8 - 1.6 × r, 0.2, 1.0)`。`Buff.modifiers` 只能表达常量，动态效果必须走 `component_scene`；改 `global_hurt_damage_mult` 时要用 `mult / old_factor × new_factor`，才能与其它承伤乘区叠加并在移除时还原。只监听 `hp_changed` 不够：它受 `hp_change_cd` 10Hz 节流，同帧多段命中会按旧血量继续吃高减伤；需同时监听 `HealthComponent.damage_taken`（逐击）。系数变化小于 `UPDATE_EPSILON=0.005` 时跳过刷新，避免无意义的 `update_body_ability()`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-21

### [Chip] 50% 破甲边界不能复用承伤刷新的 `UPDATE_EPSILON`
- Evidence / 证据: `resources/buff/components/armored_component.gd:64-69`（`crossed` 与 `UPDATE_EPSILON` 判断）、`:81-82`（`_is_broken` / `BREAK_EPSILON`）、`tests/test_armored_component.gd`（1000 HP 下 `502 → 498 → 502`）
- Notes / 说明: `hp_change_cd` 与 `damage_taken` 都可能让小步跨线只变化约 0.4%，小于 `UPDATE_EPSILON=0.005` 时会被直接跳过，导致 50% 碎甲视觉/音效不触发。阈值类状态必须单独用更小的 `BREAK_EPSILON=0.0001` 比较，并在 `_is_broken` 发生翻转时强制刷新；不要为了碎甲把伤害刷新 epsilon 一并调小，否则每次命中都会 `update_body_ability()`。
- Source / 来源: code + test
- Date / 日期: 2026-10-21

### [Chip/Visual] 暂停中仍需保留的短命演出要用 `create_timer(timeout, false)`
- Evidence / 证据: `scenes/debuff/armor_break.gd:16`
- Notes / 说明: `SceneTree.create_timer` 默认 `process_always=true`，暂停时仍走表；0.55s 的碎甲碎片/冲击环会在暂停查看或调试断点期间直接 `queue_free`，看起来像没生成。需要随游戏暂停冻结的演出应传 `false`，让计时器继承树的 pause 状态。
- Source / 来源: code + test
- Date / 日期: 2026-10-21

### [Chip] `chip_target_tags` 与 `chip_target_enemy_ids` 同时为空 = 普通敌人不限目标
- Evidence / 证据: `scenes/manager/chip_manager.gd:286-290`（两侧都空直接 `return true`）；`resources/game_mode/chip_armored.tres`（已删除 `chip_target_tags`）
- Notes / 说明: 需要让某词条对所有普通敌人生效时，把两个目标数组留空即可，不要额外写通配标签。Boss 仍由 `chip_include_boss=false` 独立排除，与目标过滤无关。
- Source / 来源: user + code
- Date / 日期: 2026-10-21

### [UI/Chip] HUD 动态创建的 Control 要逐个设 `mouse_filter=IGNORE`，父节点 IGNORE 不会自动穿透子控件
- Evidence / 证据: `ui/chip_hud.gd:37-72`（`slot_box`、`panel`、`row`、`icon`、`count_label` 全部显式设 `MOUSE_FILTER_IGNORE`）；`ui/chip_hud.tscn` 中 `Root`/`Slots` 原本已是 `mouse_filter=2`
- Notes / 说明: `Control` 默认 `MOUSE_FILTER_STOP`；只把容器设为 `IGNORE` 时，其上动态 `new()` 的 `PanelContainer`/`HBoxContainer`/`TextureRect`/`Label` 仍会吃掉鼠标事件。纯展示型 HUD 的每个动态控件都要单独设 `IGNORE`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-21

### [Rendering/Shader] 全屏屏幕纹理叠加层必须自带 `BackBufferCopy(copy_mode=VIEWPORT)`
- Evidence / 证据: `ui/crt_overlay.tscn`（`BackBufferCopy` 排在 `Filter` 之前，`copy_mode=2`）、`shaders/screen_outline.gdshader` / `shaders/shock_wave.gdshader`（游戏中已有的中途屏幕读取）
- Notes / 说明: 2D 每帧只在**首个** `hint_screen_texture` 使用者处自动拷贝屏幕。描边/冲击波等已在绘制中途读过屏幕，后置的全屏滤镜若不自带 `BackBufferCopy`，只能拿到那一次的半帧画面（实测会错位/重复）。`copy_mode` 必须改成 `VIEWPORT`(2)：默认 `RECT`(1) 只拷贝 `rect`（默认 `(-100,-100,200,200)`）。全屏 ColorRect 还要 `mouse_filter=IGNORE`，否则吞掉所有输入。
- Source / 来源: code + test
- Date / 日期: 2026-10-21

### [Rendering/Shader] CRT 扫描线/荫罩按设计分辨率虚拟网格生成，不能按物理像素
- Evidence / 证据: `shaders/crt_filter.gdshader`（`virtual_size`、`fetch()` 吸附虚拟像素中心、`mask(..., floor(base_uv * virtual_size))`）；`ui/crt_overlay.gd:_sync_virtual_size`（读 `display/window/size/viewport_width/height`）
- Notes / 说明: 参考实现跑在 640×360 的 SubViewport 上（1 texel = 1 游戏像素）。本项目没有全局 SubViewport，若按 `SCREEN_UV × 物理分辨率` 生成扫描线，720/1080 等非整数倍窗口会出现摩尔纹和错位。改为按 640×360 建虚拟网格：采样用 `(floor(vpix)+0.5)/virtual_size` + `filter_nearest`，荫罩也用同一网格且不随 `warp` 抖动。`hdr_2d=true` 时屏幕纹理为线性色，全程线性运算、不做 sRGB 转换。
- Source / 来源: code + test
- Date / 日期: 2026-10-21
- SUPERSEDED: 2026-10-21 换用 pend00「VHS and CRT monitor effect」后，扫描线与荫罩不再共用同一网格（荫罩频率改为 `resolution.x / 3`），采样也不再吸附虚拟像素中心、不做亮度守恒。见下方两条新结论。

### [Rendering/Shader] VHS/CRT 荫罩频率必须取 `resolution.x / 3`，扫描线才用 `resolution.y`
- Evidence / 证据: `shaders/crt_filter.gdshader:142`（`grille_res = max(resolution.x / 3.0, 1.0)`）、`shaders/crt_filter.gdshader:145-151`（三通道相位 0 / 1.05 / 2.1）、`shaders/crt_filter.gdshader:161-166`（扫描线直接用 `resolution.y`）；`ui/crt_overlay.gd:_sync_resolution` 把 `resolution` 同步为 640×360。
- Notes / 说明: 参考 shader 的 `resolution` 同时喂给 pixelate、扫描线、荫罩；它的默认 640×480 是按「物理画面宽/3」选的，直接套 640×360 会让荫罩正弦变成亚像素频率（摩尔纹 + 整体偏色）。拆开后的规则：荫罩用 `resolution.x/3`（一条 RGB 条 = 2 逻辑像素；`sinc = abs(sin)` 使每通道 3 逻辑像素一组），扫描线 / 噪点 / pixelate 仍用 `resolution`。改 `resolution` 时不要动 `/3`。另 `pixelate` 默认关：游戏本身已是像素画，二次吸附只会糊。
- Source / 来源: code + test + user
- Date / 日期: 2026-10-21

### [Rendering/Shader] 移植 Godot 3 屏幕 shader 到 Godot 4 的三处必改项
- Evidence / 证据: `shaders/crt_filter.gdshader:13`（`hint_screen_texture, repeat_disable, filter_nearest`）、原站 (Godot 3) 代码中 `text.r = clamp(0.0, 1.0, r * brightness)` 与 `clamp(vec3(0.0), vec3(1.0), ...)` 的参数顺序；`shaders/crt_filter_material.tres`（`overlay = true`）。
- Notes / 说明: ① Godot 3 的 `SCREEN_TEXTURE` 在 4.x 要声明为 `uniform sampler2D ... : hint_screen_texture`，否则编译失败；像素画项目用 `filter_nearest`（别照抄 `filter_linear_mipmap`）。② 原帖早期代码把 `clamp` 写成 `(min, max, value)`，在部分驱动上直接输出纯白，必须改成 `(value, min, max)`（帖内作者已修）。③ 叠在全屏 `ColorRect` 上时必须 `overlay = true`，否则读到的是 ColorRect 自己的白色纹理/UV，画面会翻转或全白。
- Source / 来源: code + test
- Date / 日期: 2026-10-21

### [Tooling/Config] 手改 `user://config.ini` 必须写无 BOM 的 UTF-8，否则 `ConfigFile.load` 静默失败
- Evidence / 证据: `script/Game.gd:315-316`（`config.load(CONFIG_PATH)` 未检查返回值）；实测 PowerShell 5.1 `Set-Content -Encoding UTF8` 写入 BOM 后，`Game.load_config()` 全部退回默认值（`crt_filter` 读成 false）。
- Notes / 说明: 调试读档/开关时改 `%APPDATA%\Godot\app_userdata\<项目名>\config.ini`，用 `[System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding($false)))`，或先备份再恢复。BOM 存在时 `load` 返回错误但不报错，所有键静默走默认值。
- Source / 来源: test
- Date / 日期: 2026-10-21

### [Chip] 死亡触发领域依赖 `is_dead` 同步回调先于 deferred idle/清 Buff
- Evidence / 证据: `script/EnemyStats.gd:86-97`（`hp<=0` 时同步 emit `is_dead`）、`script/entity_ENEMY.gd:572-574`（`_coin_drops` / `on_dead` deferred）、`script/entity_ENEMY.gd:134`（`idle_state()` 内 `clear_all_buff()`）、`resources/buff/components/corruption_field_component.gd:32-40`（`_on_dead` 同步生成领域）
- Notes / 说明: 死亡生成型词条必须在 `EnemyStats.is_dead` 的同步回调里读取 `body.global_position` 并生成；`entity_ENEMY.on_dead` 与 `idle_state` 都是 deferred，之后才会清 Buff/回池。若在 `deactivate()` 或回池后再生，位置已被归零且组件可能已断开。`source_refcount` 领域使用独立 `source_id`，离开/闪避/过期只移除自己的来源。
- Source / 来源: code + test
- Date / 日期: 2026-10-21

### [VFX/Chip] 地面颜料滩挂 `YSort`，根 `z=-1` 放到角色脚下
- Evidence / 证据: `scenes/main/main.tscn:240-260`（`FloorLayer` 在 `YSort` 前；`YSort/FloorWall`、`SpawnMap`、`Wall` 均 `visible=false`；背景层在 `z=-10/-9`）、`scenes/main/test_room.tscn:173-201` 同结构；`scenes/debuff/corruption_field.tscn`（根 `z_index=-1`，`PaintBase`/`PaintEdge`/`Bubbles` 继承）、`resources/buff/components/corruption_field_component.gd:_spawn_field()`（优先 `PlayerRoot` 父节点 `YSort`，回退 `SELayer`）
- Notes / 说明: 腐化领域需要显示在角色/敌人脚下时，用 `YSort` + 根 `z_index=-1`：角色和敌人保持 `z=0`，背景在 `z=-10/-9`，颜料滩/气泡位于两者之间。当前战斗场景的地面 TileMap 是 `visible=false`，所以 `z=-1` 不会被地板盖住；如果以后启用可见地面 TileMap，需要再给它单独分层。不要用 `SELayer` 作为常规地面层，它会盖在角色脚上。
- Source / 来源: code + test
- Date / 日期: 2026-10-21

### [Build/Mod] `ModPack` 预设未排除 `mods/*`，会把其他 mod 的旧脚本一起打进当前 mod pck
- Evidence / 证据: `mod_sdk/ModPack.preset.cfg`（`export_filter="all_resources"`，`exclude_filter` 不含 `mods/*`）；`mod_sdk/build_mod.ps1:4`（默认 `Preset="ModPack"`）与 `:22`（仅 `ModPackReplace` 分支生成 `export_files`）；实测 `user://mods/doom_slayer_izzy/doom_slayer_izzy.pck` 含 `mods/etn_coop/ui/coop_menu.gdc`、`coop_menu.gd.remap` 与旧场景，且 `load_order=100` 使其遮蔽新 etn_coop。
- Notes / 说明: `build_mod.ps1` 默认走 ModPack 预设时不会限定 `export_files`，`all_resources` 会把工程内 `mods/` 下所有 mod 一并导出；被卷入的旧 `.gdc`/`.remap` 会按 load_order 遮蔽同名新脚本/场景（症状：`PageScroll.mouse_filter` 运行期变 2、扫描点动画与主题颜色丢失）。修复：优先用 `build_local_mod.ps1`（PCKPacker 只打单个 `mods/<id>/`），但它不带 `.godot/imported`，含贴图/音频的 mod 会缺导入产物；需保留导入资源时应走导出预设并显式只导出当前 mod（`export_files`），同时排除 `mods/*`。
- Source / 来源: code + user
- Date / 日期: 2026-10-21

### [Coop/UI] return 关闭与支援 EX 初始化已移入本体，mod 不再断开/兜底
- Evidence / 证据: `script/extension_hooks.gd`（`return_pressed_gate`）；`ui/return.gd:_on_pressed`（先 `intercept_named`）；`script/support_data.gd:get_card/game_add_support`（无条件写 `ex_cost` + 生成前同步/清零）；`script/support_as.gd`（`ex_cost<=0` 时不计费、不 ready、不释放）；`mods/etn_coop/entry/coop_entry.gd:_gate_return_pressed`；`mods/etn_coop/ui/coop_menu.gd`（删除 `_setup_return_button`）；`mods/etn_coop/net/coop_net.gd`（删除 `_normalize_support_cost`）。
- Notes / 说明: 联机覆盖层打开时返回按钮经 hook 只关闭覆盖层，其它菜单仍走本体 `Game.pause_press`；支援 EX 的 `ex_cost` 由本体在 `get_card`/`game_add_support` 初始化，`ex_cost<=0` 的支援不再充能/释放。`coop_select._ready` 的默认空支援 `get_card` 保留为选人初始化，不是兜底。此后 mod 不再需要断开 `return.gd` 信号或修正 `SupportData`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-21
### [Chip] 腐化场 0.4s、攻击附腐化、感染不占同场上限
- Evidence / 证据: `scenes/debuff/corruption_field.gd`（`corruption_interval=4`、`INFECT_TICKS=10`、`_infect_enemies`）；`script/chip_corruption_rules.gd`；`script/projectile_spawner.gd`、`script/entity_ENEMY.gd`、`scenes/enemies/tank_gun_1.gd`（写 `DamageData.corruption_power`）；`script/player_health_component.gd:169`；`resources/buff/components/corruption_field_component.gd`（`BuffRouter.apply_buff` 传入 carrier）
- Notes / 说明: 0.4s 在 10Hz 下必须用 4 tick，不是浮点计时；攻击附加腐化只写直接命中（子弹/近战/炮台炮弹/爆炸复制），DOT/场地不写，由玩家受击侧统一应用 `corruption_power`。感染敌人走 `BuffRouter.apply_buff` 直接加同一个 `chip_corruption_buff`，不调用 `ChipManager.apply_to_enemy`，因此不增加 `_active_count`/`_counts`，也不占词条上限；感染持续到死亡，领域过期不清除。`corruption_field_component.activate()` 会调用 `body.create_damage_data()`，确保感染后近战/接触伤害的缓存也刷新。
- Source / 来源: code + user
- Date / 日期: 2026-10-21

### [Chip] 计分倍率按选中词条总数，在结算时对最终总分乘一次
- Evidence / 证据: `scenes/manager/chip_manager.gd:208-214`（`get_selected_chip_count()` 优先 `_selected_chips`，未准备时回退 `_load_selected_chip_modes()`；`get_score_multiplier()`）；`ui/game_over_page.gd:93-105,145`（`_apply_chip_score_bonus()` 在写 `ScoreNum` 前结算）
- Notes / 说明: 倍率必须按选关页选中的词条总数计算，不能按每回合随机生效的 `_active_chips`，否则选中 >3 时倍率会随抽取浮动。`_selected_chips` 在 `prepare_round()` 中按 `PlayerData.game_mode` 去重加载，客机不准备词条时回退到同一过滤逻辑。结算放在 `time_count_stop()` 写分数/记录之前，对最终总分（击杀 + 金币 - 消费）乘一次，`score <= 0` 不放大，并用 `_chip_score_bonus_applied` 防重复；不要把倍率塞进 `score_defeats_count()`，否则金币/消费扣分不会同步。词条上限额外部分只对超过 `active_chip_limit` 的数量生效，并叠在基础 40 封顶之上。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-21
### [Chip/VFX] 腐化载体染色：描边 shader 用 tint uniform，无 shader 用 `sprite_2d.modulate`
- Evidence / 证据: `shaders/sprite_outline.gdshader`（`corruption_tint` / `corruption_amount`，最终 `mix(COLOR.rgb, tint, amount)`，默认 amount=0）；`resources/buff/components/corruption_field_component.gd:_apply_tint/_clear_tint`（有描边材质时设 uniform，无材质时设 `original.lerp(tint, 0.3)`，并恢复原值/原材质）；`scenes/enemies/lighttank_helmet.tscn:134`（`sprite_2d = Graphics/TankGraphics`）、`:145-164`（`CanvasGroup` 下的 `tank_body`/`tank_turret` 无 shader）；`scenes/enemies/enemy_tank.gd:127,168`（`graphics.modulate` 受击闪白/恢复）
- Notes / 说明: `sprite_outline.gdshader` 在 fragment 直接重写 `COLOR`，会忽略 CanvasItem `modulate`，所以普通描边敌人必须走 shader 的 `corruption_tint` / `corruption_amount`；`modded_sweeper` 的蓝色通道很低，乘法 tint 会变成暗红并接近 `red_sweeper`，必须用 `mix` 向浅紫补蓝。坦克的 `TankGraphics` 没有 shader，用 `sprite_2d.modulate` 的 `original.lerp(浅紫, 0.3)` 让 `tank_body`/`tank_turret` 一起变紫。不要全局改描边 shader 去乘 modulate：子弹/UI 有 `Color(100,1.5,1.5)` 等高亮值，会造成回归；新 uniform 默认 0 不影响其它资源。不要改 `graphics.modulate`（`EnemyTank._hurt_flash()` 占用）；移除 Buff 时恢复 modulate、材质或 shader 参数。
- Source / 来源: code + test
- Date / 日期: 2026-10-21

### [Coop/Chip] host 词条 Buff 早于 net_id 注册时必须排队补发
- Evidence / 证据: `script/spawn_anim.gd:spawn_enemy_body()`（词条 Buff 在 `active_state()` 前应用）；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_on_enemy_buff_applied()` / `_on_enemy_spawned()` / `_pending_enemy_buff_events`。
- Notes / 说明: host 的词条 Buff 往往在敌人拿到 `net_id` 前触发，立即广播会被 `body.has_meta("net_id")` 拦掉。必须按 instance_id 缓存，等 `register_enemy_spawn()` 完成后 flush；`chip_id` 随 `_spawn_enemy_remote()` 同步，晚加入路径也要带上。
- Source / 来源: code + test
- Date / 日期: 2026-10-22

### [Coop/Chip] 客机词条状态以 host active IDs 为准，腐化领域只做 visual-only
- Evidence / 证据: `scenes/manager/chip_manager.gd:apply_network_round_state()` / `get_network_round_state()`；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_remote_chip_round_state()`；`resources/buff/components/corruption_field_component.gd` / `scenes/debuff/corruption_field.gd`（`visual_only`）；`resources/buff/components/frenzy_delay_death_component.gd`（`network_begin_burn/network_finish_burn`）。
- Notes / 说明: 客机不能本地 `prepare_round()` 抽词条，否则会与 host RNG 不一致；HUD 只接 host 的 active IDs/cap/counts。客机腐化领域使用 `player_only`：只对本地玩家执行 0.4 秒 1% 最大生命腐化与 30% 减速，不感染敌人；场由 host 的 `field_spawned` 广播生成。狂怒燃烧条由 host 的 burn_started/finished 事件驱动本地倒计时。
- Source / 来源: code + test
- Date / 日期: 2026-10-22


### [Coop/Chip] 池化敌人残留旧 net_id 会让后续波次 Buff 广播丢失
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_live_enemy_net_id()`、`_on_enemy_buff_applied()`、`_on_enemy_spawned()`、`_pending_enemy_buff_events`。
- Notes / 说明: 敌人回池后节点上的 `net_id` meta 可能保留；下一次生成时词条 Buff 在 `register_enemy_spawn()` 前应用，若只检查 `has_meta("net_id")` 会把 Buff 发到已删除的旧镜像，表现为 host 有词条、客机只有首波有。必须校验 `enemy_by_net_id[id] == body`，无效时排队到新 net_id 注册后 flush。
- Source / 来源: code + test
- Date / 日期: 2026-10-22

### [Coop/Chip] 客机首回合 round_switch 可能为 false，远程 round_end 必须强制发信号
- Evidence / 证据: `script/GameEvents.gd:force_emit_round_end()`；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_remote_round_end()`、`_on_rejoin_settled()`。
- Notes / 说明: 客机首回合不走 `round_manager.first_round_start()`，`GameEvents.round_switch` 可能仍为 false，普通 `emit_round_end()` 会静默失败，导致客机不执行 `RoundManager._on_round_end()` 和 `main.enemy_clear_unit()`，看不到敌人清场动画。远程 round_end 必须使用强制版本。
- Source / 来源: code + test
- Date / 日期: 2026-10-22

### [VFX/Coop] bullet_smoke_2 不能只靠 AnimationPlayer method track 回池
- Evidence / 证据: `scenes/bullet/bullet_smoke_2.gd`（`smoke_anim()` 代次 + `SMOKE_ANIM_FALLBACK_SEC`）；`scenes/bullet/bullet_smoke_2.tscn`（移除 `AnimationPlayer.autoplay`）；`mod_sdk/coop_mod/mods/etn_coop/net/coop_visual_sync.gd:_schedule_smoke_idle()`；`mods/etn_coop/net/coop_net.gd:_on_any_projectile_hit()`。
- Notes / 说明: 双方 Kei 自动射击时，同一命中点会高频产生 `bullet_smoke_2`，远端正则还会走可复用特效池。若只依赖 0.2s 的 AnimationPlayer method track 调 `idle_state()`，快速重触发/池复用可能让 method track 没机会执行，表现为同一个烟节点常驻命中点、每次命中又播一次。`smoke_anim()` 必须用代次保护并在动画时长后兜底 `idle_state()`；远端 smoke 再加 1s 存活兜底。移除 autoplay，生命周期由调用方显式控制。
- Source / 来源: code + test
- Date / 日期: 2026-10-22

### [Mod/Hooks] `intercept_named` / `notify_named` 的槽名必须在 extension_hooks.gd 显式声明
- Evidence / 证据: `script/extension_hooks.gd:_slot_of()`；`scenes/manager/field_mod_manager.gd`（`field_mod_spawn_gate` / `on_field_mod_started` / `on_field_mod_stopped`）
- Notes / 说明: 命名钩子不是任意字符串都能用；`_slot_of()` 只接受 `extension_hooks.gd` 中已声明的 `Callable` 字段，未声明会 `push_error` 并返回空 Callable。新增钩子时必须同时补字段，否则单机虽然继续执行（intercept 返回 false），但会刷错误日志。`FieldModManager` 的场地效果仍为 host 权威，`apply_network_round_state()` 不发 `field_chips_changed`。
- Source / 来源: code + test
- Date / 日期: 2026-10-22

### [Map/Chunks] SpawnMap 是刷怪安全区，不是整张可走地图
- Evidence / 证据: `scenes/main/main.tscn:263`（`SpawnMap`）、`script/map_bounds.gd:get_walkable_polygon/get_boundary_source`、`script/map_chunks.gd`、`scenes/field_mods/terrain_field_effect.gd`
- Notes / 说明: 用户确认 `SpawnMap` 比实际可走地图小一圈，只用于防止刷怪超出地图；地形分块必须使用 `FloorWall` 射线得到的 `MapBounds` 真实 hull。当前地图实测 `SpawnMap` 为 625 cells，全图 hull 为 729 cells（外圈 104 cells）；`TERRAIN_INSET_PX=20` 会把外圈全部裁掉，不能用于全图分块，当前用 8px。不要把地形写进 `SpawnMap`，也不要改它的 used cells；overlay 使用独立 `TileMapLayer`。`MapBounds` 回退 `spawnmap` 时地形只能覆盖安全区，必须告警。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-22

### [Map/Chunks] 分块尺寸按词条配置；腐化蔓延固定 4×4 并按边缘侧轮转
- Evidence / 证据: `script/map_chunks.gd:get_grid()`、`script/map_chunk_grid.gd`、`scenes/field_mods/corruption_spread.gd`、`scenes/field_mods/corruption_warning_tileset.tres`
- Notes / 说明: `MapChunks` 不再写死 4×4，按 `chunk_size` 缓存 `MapChunkGrid`；`chip_corruption_spread` 明确使用 `4×4`，以菱形四条斜边各建**整条边**的侧区。`ratio` 表示**可走面积比例**，不是地图宽度：20% 起、每 3 回合 +5%、40% 封顶；块中心到所选边距离作为排序依据，沿边投影在两端之间才归入该侧区，按距离层累加到最接近 `全图可走 cells × ratio`。整块量化会带来约一个距离层的误差（首波实测 17.1%–23.0%）。**SUPERSEDED 2026-10-22**：每波改用 `_collect_cells_by_depth()` 按 `cell 中心到边距离 <= _best_depth` 二次筛选，`_band_cells` 变 cell 级，轮廓从 128×64 块级阶梯降为 64×32 菱形齿（同层块内约 17%~22% 外缘 cell 被裁掉，面积略小于块级）；`_chunks` 仍保留整块，仅用于 `_spawn_fog()` 撒点。原描述：每波把该距离层内全部块的 cells 汇成毒雾区，换边时重算目标面积，只按起始侧轮转，四侧轮完重洗但不重置比例。按设计**不做连通性/避让校验**，允许压缩玩家行动空间。视觉不再使用 `corruption_field`：预警用紫色 `WarningLayer`，生效由可复用 `FogField` 在 `YSort` 下为每块生成 `FogCloud` 粒子毒雾（`FogSettings` 控制参数，`density` 为总倍率）；玩家在 band cells 内每 tick 刷新减速，每 0.4 秒累积腐化。激活时播放一次 `CorruptionSpawn`。**2026-10-22 机制调整**：新增 5 秒间隔（`interval_ticks=50`，`Phase.IDLE`），雾延长到 10 秒（`active_ticks=100`），每次腐化 1% → 3%（满打约 75% max_hp）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-22

### [VFX/Fog] `smoke_sprite_1.png` 是空心烟环，不能当浓雾纹理
- Evidence / 证据: `sprites/particle/smoke_sprite_1.png`（1536×128、12 帧、128×128/帧，逐帧 alpha 均值 7–11，f10–f11 全透明）；旧 `resources/fog/poison_fog_settings.tres` 的 `scale_min/max=2.0/4.0` + `amount=6`
- Notes / 说明: 该图中心空洞、边缘稀疏，单帧 alpha 极低；放大 2–4 倍且只放 6 朵时得到的是「几团模糊半透明方块」而非雾。像素风雾气改用 `NoiseTexture2D`（`resources/noise/fog_noise.tres`）同时作粒子纹理与 shader 噪声源，在 fragment 里乘径向衰减再做 Bayer 抖动 + alpha 量化，才消除 quad 方形边界。`NoiseTexture2D` 作粒子纹理时需 `texture_filter=NEAREST` 才出像素块；`GPUParticles2D` 的 `material` 若为共享 `ShaderMaterial`，用 `set_instance_shader_parameter()` 给每朵不同 `seed_offset`。
- Source / 来源: code + test
- Date / 日期: 2026-10-22

### [Tooling] `editor_screenshot` 传 `max_resolution=1280` 会 transport failed
- Evidence / 证据: 1280×720 窗口项目下连续两次 `godot-ai_editor_screenshot(max_resolution=1280)` 返回 transport error；`960` 正常
- Notes / 说明: 用 960 或更小；2x 整数缩放项目在缩略图里像素块会变模糊，像素级判定需另想办法。`project_run` 后要等约 2 秒让 game helper 变 live 再截图；`game_eval` 在游戏窗口后台化时返回 `EVAL_GAME_NOT_READY`（主循环未推进），需聚焦窗口或重启游戏。
- Source / 来源: test
- Date / 日期: 2026-10-22

### [VFX/Fog] `FogField.emit_points` 的 `emitter_spacing` 是发射盒尺寸，不是点间距
- Evidence / 证据: `scenes/effects/fog/fog_field.gd:47-52`（`_spawn_cloud` 的 size 直接用 `emitter_spacing`）；`scenes/field_mods/corruption_spread.gd:276-280`（每块只传一个 `chunk.world_center`）；`scenes/main/main.tscn:77`（`tile_size = 64×32`）；`script/map_chunk_grid.gd:36`
- Notes / 说明: 腐化蔓延用 4×4 chunk，相邻块中心间距约 `128×64` px；每块只 `emit_points` 一个点、发射盒 = `fog_emitter_spacing`（默认 64），粒子中心只覆盖块中心 ±32，靠 `size_min/max_px` 补缝。180~260px 时水平方向两边各覆盖约 58px，合计 116 < 128 → 出现**竖向缝隙**；`emit_rect` 路径因间距 80 且整片连续，不出现此问题。修法：`size_min_px/size_max_px` 提到 `220/320` 即可，`amount`/`dissolve`/falloff 不动可保留团块感。注意把 `fog_emitter_spacing` 调大只是放大发射盒，会把同样的粒子摊薄，需同时提高 `fog_density`。`tests/fog_tuner.gd` 的「块布局 emit_points」开关按 `block_x/block_y`（默认 128×64）撒点，可不用等回合就复现。
- Source / 来源: code + test
- Date / 日期: 2026-10-22

### [Net/Field] 客机不发 `field_chips_changed`，场地词条联机必须独立 RPC
- Evidence / 证据: `scenes/manager/chip_manager.gd:236-252`（`apply_network_round_state()` 只 emit `chips_changed`）；`scenes/manager/chip_manager.gd:292-296`（`_refresh_active_field_chips()` 不发 `field_chips_changed`）；`scenes/manager/field_mod_manager.gd:30-32`；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:1824,2333-2485`（`install_hooks` / `_bind_field_sync` / `_attach_field_effect` / `_remote_field_wave`）；`scenes/field_mods/corruption_spread.gd:9-11,335-380`（`wave_*` 信号 / `get_network_state` / `apply_remote_wave`）
- Notes / 说明: 客机 `FieldModManager` 永远不会启动场地效果；腐化蔓延改为 host 在 `_start_warning()` emit `wave_started(cells: PackedVector2Array, fog_points: PackedVector2Array)`，`coop_net` 用 `@rpc("authority","call_remote","reliable")` 广播快照，客机以 `is_remote=true` 实例化 `corruption_spread.tscn` 并 `apply_remote_wave()` 重建 `_band_cells`/`_remote_fog_points`，本地跑 2s/10s/5s 相位但 IDLE 不自动开波（每波由快照重新对齐，误差不累积）。晚加入在 `_accept_peer` / `_client_scene_ready` 调 `_send_field_state_to_peer()` 补发；`is_remote` 效果仍只扫 `"Player"` 组，玩家减速/腐化各自本地结算，`RemotePlayer` 不受影响。单进程验证：`apply_remote_wave(..., ACTIVE, 50)` 后 `band=3`、`fog=true`、state `cells/points=3/2`，50 tick 后回 IDLE 且 `band=0`，再 60 tick 仍不开波。**修正（2026-10-22，来源：user + test）**：只靠 `_on_round_start` 的 `_bind_field_sync` 会漏掉首次开波——双端实测日志里 `attach` 早于 `bind`（`field_mod_started` 在 deferred 绑定前已发出）。改为 `coop_net.install_hooks()` 注入 `ExtensionHooks.on_field_mod_started/stopped`，`_bind_field_sync` 仅兜底并用 `get_active_effects()` 补接；新增 `wave_activated`/`wave_ended` 做 ACTIVE/IDLE 补发（host 需与 pck 同版本的新 exe）。
- Source / 来源: code + test
- Date / 日期: 2026-10-22

### [Chip] 玩家词条 Buff 每回合会被 `player_buff_clear` 清空，必须重挂
- Evidence / 证据: `scenes/manager/round_manager.gd:151`（`emit_player_buff_clear()`）、`scenes/manager/player_buff_manager.gd:10-11`（`player_buff_clear` → `clear_all_buff`）、`scenes/manager/chip_manager.gd`（`_clear_player_chips()` / `_apply_player_chips()` / `_on_local_player_ready()` / `_apply_player_chips_deferred()` / `prepare_round()` / `apply_network_round_state()`）、`mods/etn_coop/net/coop_net.gd`（`_place_and_refresh_local_player()` 的 `emit_get_player`）
- Notes / 说明: `round_upgrade` 会清空玩家全部 Buff，玩家词条的常驻 Buff 不能只挂一次；`prepare_round()` 开头先 `_clear_player_chips()`，抽完 `_active_chips` 后 `_apply_player_chips()` 重挂。客机不走 `prepare_round()`，必须在 `apply_network_round_state()` 末尾补挂，否则客机看不到玩家词条效果。**`active_ids` 可能早于本地玩家生成**：`apply_network_round_state()` 那次 `_apply_player_chips()` 会因 `PlayerRef.resolve()` 为空直接返回，之后不会自动补。必须监听 `GameEvents.get_player` / `PlayerData.set_player`，用延迟队列在本地玩家就绪后重挂；玩家实例变化时先清理旧 target，避免来源残留。`_reset_run()`、`_on_round_end()` 也要清理，避免跨局/回合残留。
- Source / 来源: code
- Date / 日期: 2026-10-23

### [Chip] 玩家词条共享抽取池、计入 TM/计分，但不增加敌人同场上限
- Evidence / 证据: `scenes/manager/chip_manager.gd:get_selected_enemy_chip_count()` / `_cap_for_round()` / `get_score_multiplier()`；`ui/gamemode_button.gd:76-85`（`get_selected_mod_count()` 统计全部，`get_selected_enemy_mod_count()` 复用）；`ui/level_select.gd:274`
- Notes / 说明: 用户裁定：玩家削弱词条与敌人/场地词条共用 `enemy_mod_box` 和同一 `active_chip_limit` 抽取池；`havoc_min_enemy_mods` 与每词条 +3% 计分按**选中总数**（含玩家词条）；但同场敌人上限的额外部分只按选中 `ENEMY` 词条数计算。因此用 3 个玩家词条满足 TM 会比用敌人词条更难，这是预期。
- Source / 来源: user
- Date / 日期: 2026-10-23

### [Buff] `max_ammo_mult` 只乘 `max_ammo_add`，不是弹匣基础倍率
- Evidence / 证据: `script/PlayerData.gd:370`（`clamp(1, base_max_ammo + max_ammo_add * max_ammo_mult, max_ammo_value)`）；`script/buff_stat_map.gd` 未映射 `max_ammo_mult`
- Notes / 说明: 想用 `Buff.modifiers` 做“弹匣 -30%”时不能映射到 `max_ammo_mult`——它只放大 `max_ammo_add`，基础 `max_ammo_add=0` 时完全无效。真正的基础倍率字段是 `hurt_resis_mult`（护甲/减伤）与 `reload_timer_mult`（换弹时间），弹匣类削弱需新增 `max_ammo_base_mult` 并改进 `PlayerData` 重算，或走 `BuffComponent`。
- Source / 来源: code
- Date / 日期: 2026-10-23

### [Buff/UI] 玩家 debuff 会自动显示在玩家 Buff 栏
- Evidence / 证据: `scenes/manager/player_buff_manager.gd:47-50`（`_buff_box()` 返回 `body.game_ui.buff_box`）、`scenes/manager/buff_manager_base.gd:451-472`（`_obtain_buff_card()`）、`ui/BuffCard.gd:39-57`（图标/层数/环形进度）
- Notes / 说明: 经 `BuffRouter.apply_buff(player, ...)` 挂到玩家的 Buff 无需额外 UI 代码就会进 Buff 栏。卡片只显示 `Buff.icon`、层数和环形进度，不显示 `Buff.name`；因此玩家词条 Buff 必须配置 `icon`。`source_refcount=true` 时层数显示来源数，单来源不显示数字；`is_debuff=true` 时 `PlayerBuffManager._duration_multiplier()` 返回 1.0，不会吃到玩家“有益 Buff 持续时间”加成。99999 秒的常驻 buff 环形进度几乎一直满格，属于预期。
- Source / 来源: code + user
- Date / 日期: 2026-10-23

### [Combat] 玩家端 `TRUE_DAMAGE` 需要单独分支，否则仍吃护甲和 `hurt_mult`
- Evidence / 证据: `script/player_health_component.gd:124-151`（真伤分支跳过 `_armor_reduction()`、`stats.hurt_mult`、`damage_modifier` 与 `damage_multiplier`）；`script/health_component.gd:256`（敌人端原有真伤分支）
- Notes / 说明: 敌人 `HealthComponent` 早已用 `TRUE_DAMAGE` 跳过全局易伤和伤害修饰，但玩家 `PlayerHealthComponent` 原实现没有检查该 flag。轨道炮击要“10% 最大生命真伤”必须在玩家端补同等分支；否则面板数值会先被护甲/减伤/修正吃掉。真伤仍然尊重 `is_invincible`、`hurt_box.contact_invincible`、`stats.hurt_invalid`、临时生命 `t_hp` 和敌人 `shield_active`。
- Source / 来源: code + test
- Date / 日期: 2026-10-23

### [VFX/Field] 场地逻辑 10Hz tick，但毫秒倒计时必须由 marker 逐帧更新
- Evidence / 证据: `scenes/field_mods/orbital_barrage.gd`（`on_tick()` 只推进 IDLE/WARNING 相位）；`scenes/effects/orbital_strike_marker.gd`（`_process(delta)` 更新 `%0.3f` 倒计时）
- Notes / 说明: 场地词条统一走 `GameEvents.global_time_count` 10Hz，不能为了倒计时把整条逻辑改成逐帧；把视觉倒计时放在 marker 自己的 `_process()`，逻辑仍在 10Hz 结算。这样 label 连续显示 `4.000→0.000`，爆炸最多比 label 归零晚一个 10Hz tick；不要在 effect 的 `on_tick()` 里只显示一位小数。
- Source / 来源: code
- Date / 日期: 2026-10-23

### [Chip/Gun] `max_ammo=1` + `bullet_cost=2` 必须把弹药扣到 0，不能要求“弹药足够才能开火”
- Evidence / 证据: `script/player_gun.gd:134,159,229-230`；`scenes/update_item/concentrated_ammo.gd:5-11`；`resources/buff/player_buff/chip_bad_ammo_buff.tres:16`
- Notes / 说明: `_shoot()` 在扣弹前只检查 `now_bullet_ammo <= 0` 触发换弹；`consume_ammo()` 把 `now - cost` clamp 到 0。若为了避免负数改成 `now >= cost` 才能开火，浓缩弹构筑（`max_ammo=1`）会既打不出子弹也不触发换弹。负弹药不会出现，HUD 也不会显示负数；扣到 0 后下一次扳机换弹。
- Source / 来源: code + test
- Date / 日期: 2026-10-23

### [Combat/Damage] 连射衰减系数是每颗子弹的生成快照，池化子弹必须每次 spawn 覆盖 meta
- Evidence / 证据: `script/player_gun.gd:143,190-195,217-227`；`script/player.gd:492,526-530`
- Notes / 说明: `_pending_damage_mult` 在 `_shoot()` 时按当前 streak 算出，`_configure_bullet()` 写入 `player_damage_mult` meta；`PlayerData` 在 base 伤害之后读取。子弹来自对象池，若只在生成新子弹时设 meta，复用旧子弹会沿用上一次的系数；每次 spawn 必须覆盖。streak 是扳机计数，多弹丸同一次 `_shoot()` 共享同一系数；换弹/停火 1 秒归零，第一发 1.0，第 11 发起 0.8（cap 0.2）。
- Source / 来源: code + test
- Date / 日期: 2026-10-23

### [Chip] 后坐力削弱用加算，避免与浓缩弹的 `+0.5` 相乘
- Evidence / 证据: `resources/buff/player_buff/chip_bad_ammo_buff.tres:16`；`scenes/update_item/concentrated_ammo.gd:5-11`；`script/PlayerData.gd:139`
- Notes / 说明: 用户拍板用 `bullet_recoil_mult` 的 `mode:"add", amount:0.5`；浓缩弹 1.5 → 2.0。若用 `mode:"mult", amount:1.5` 会 1.5 → 2.25，叠乘后后坐力过强，也与“+50 个百分点”描述不符。
- Source / 来源: user + code
- Date / 日期: 2026-10-23

### [Chip/Coin] 惩罚型金币掉落必须绕开 `coin_mult`，否则可套利
- Evidence / 证据: `scenes/item/coin.gd`（`ignore_coin_mult`、`idle_state()` 重置）；`scenes/item/parabola_path.gd`（同名导出参数）；`resources/buff/components/sonic_coin_drop_component.gd`
- Notes / 说明: 浩劫金币加成会放大拾取额，若扣款按原值、拾回再乘 `coin_mult`，玩家可通过反复受击净赚；因此 `parabola_path` 掉落时设 `body.ignore_coin_mult=true`，让拾回额与扣除额一致。
- Source / 来源: user + code
- Date / 日期: 2026-10-23

### [Coin] 青辉石后的全局 `auto_pick` 会吸走之后生成的所有金币，惩罚掉落要逐枚 opt-out
- Evidence / 证据: `scenes/manager/coin_manager.gd:24-32`（`pyroxenes_pick_up` 置 `auto_pick=true`，`round_start` 重置）；`scenes/item/coin.gd:24-35,52-75,87-90`（`_ready→active_state`、`active_state/auto_pick/absorb`）；`scenes/item/parabola_path.gd`（`drop()` 取池/实例化 body 后重置 flag 与飞行层、`idle_state`/`_release_body`）；`script/player.gd:557-560`（`PickBox.area_entered` 无条件置 `pick_up`）；`scenes/update_item/multipurpose_rope.gd`、`robotic_vacuum_cleaner_body.gd`（自动拾取守卫）
- Notes / 说明: 不能改 `CoinManager.auto_pick` 本身，否则正常金币也会失去青辉石后的自动吸取；惩罚金币用 `ignore_auto_pick=true`，只阻断自动飞向玩家，仍保留玩家走近 `PickItem` 拾取。**body 的 `_ready()` 可能早于 `drop()` 的 flag 写入**：`drop()` 从 `coins` 池取 idle body 或实例化后，必须立即清 `pick_up/target/can_pick` 再写 flag；仅设置 flag 不会清除已置真的状态。路径 scene 已不再自带 body，不需要 `_enter_tree()` 预写。**另有一条出生点重叠路径**：金币起点就是玩家位置，玩家 `PickBox` 会在出生帧把 `pick_up` 置真（不看 `can_pick`），落地后 `can_pick=true` 即自动飞回；因此惩罚金币飞行期间必须 `collision_layer=0`，落地恢复后再清 `pick_up/target`。绳索/吸尘器是另外的自动来源，也必须检查 `ignore_auto_pick`。索尼克落地动画用 `fall_duration=1.2`，旧 `coin_box` 保持 `3.0`。
- Source / 来源: user + code
- Date / 日期: 2026-10-23

### [Coin/Pool] `parabola_path` 双池化：路径根与金币 body 分离回收
- Evidence / 证据: `scenes/item/parabola_path.gd`（`PATH_POOL_ID`/`COIN_POOL_ID`、`_acquire_body`、`idle_state`、`_release_body`、`_reset_drop_config`）；`scenes/item/coin.gd`（`idled` 信号）；`scenes/item/coin_box.gd`、`resources/buff/components/sonic_coin_drop_component.gd`（`get_pool_idle`）；`scenes/main/main.gd`（`coin_clear_unit` 的 `Path2D` 分支）
- Notes / 说明: 旧实现里 `parabola_path` 自带 coin body，且 `body.free_self -> queue_free` 会把整条路径销毁，无法复用。现改为路径根入 `parabola_coins`，body 入 `coins`。关键顺序：`idle_state()` 先让 body 发 `idled`，再在 `_release_body()` 里把 body `reparent` 回 `CoinRoot`、补 `PoolManager.add_pool("coins", body)`，最后才把路径标记 `is_idle=1`；否则路径池可能返回仍挂着 body 的路径。`coin_box` 末尾会 `erase_pool("coins")`，所以释放 body 时必须重新 `add_pool`。路径池跨索尼克/coin_box 共用，idle 时重置为 coin_box 默认参数，避免索尼克配置泄漏；`is_idle`/`PathFollow2D` 与 `coin.idled` 是这套回收协议。`main.coin_clear_unit()` 只遍历 `CoinRoot` 直接子节点，必须单独处理 `Path2D`，否则未拾取路径会一直留着。
- Source / 来源: code + user
- Date / 日期: 2026-10-23

### [Coop/Chip] B1 索尼克掉币：客户端上报、host 生成、拾取者独得
- Evidence / 证据: `resources/buff/components/sonic_coin_drop_component.gd`（`player_coin_drop_interceptor`、`spawn_burst_at`）、`script/extension_hooks.gd`（`player_coin_drop_interceptor`）、`scenes/item/coin.gd` / `scenes/item/parabola_path.gd`（`personal_pickup`）、`mods/etn_coop/net/coop_net.gd`（`_gate_player_coin_drop`、`_server_player_coin_drop`、`_remote_parabola_coin`、`_server_pickup_coin`、`_do_shared_coin_pickup`）
- Notes / 说明: 客户端不能在本地生成索尼克路径，否则 `_on_coin_spawned()` 只在 host 执行，客机掉币不会广播。现由客户端发 `total + origin` 给 host，host 校验频率/位置/激活词条后用静态 `spawn_burst_at()` 生成，沿用 `on_coin_spawned → _register_parabola_coin` 广播。`personal_pickup` 必须随 `_remote_parabola_coin` 同步：拾取时 host 只 `rpc_id(picker, "_apply_shared_coin_remote")`，其余端只收 despawn；host 自己拾取只本地加币，不再广播加币。普通金币 `personal_pickup=false`，仍走共享逻辑。`ignore_auto_pick` / `ignore_coin_mult` 也要同步，且 host 的 `_gate_coin_pickup` / `_server_pickup_coin` 必须读取 `ignore_coin_mult`，否则索尼克金币会被自动吸走或乘 `coin_mult`。严格反作弊未做：金额信任客户端，仅 clamp/限速/位置校验。
- Source / 来源: code + user
- Date / 日期: 2026-10-23

### [Chip/Damage] `chip_sonic` 受击掉金币用 `stats.is_hurt`，含 DOT 每 tick
- Evidence / 证据: `script/Stats.gd:7,176`（`is_hurt`）；`script/player_health_component.gd:177,202`（`damage_taken` 也会在 `play_hit_feedback` 发出）；`resources/buff/components/sonic_coin_drop_component.gd`（`_on_hurt`）；`resources/game_mode/chip_sonic.tres`
- Notes / 说明: 用户明确要求 DOT 每跳也触发、不做去抖；`stats.is_hurt` 只在真实结算扣血后发，`damage_taken` 还会被联机表现回放 `play_hit_feedback()` 复用，监听后者会让客机凭空掉钱。同一时间多段伤害会多次扣款/掉落，属于预期。
- Source / 来源: user + code
- Date / 日期: 2026-10-23

### [Item/Path] `parabola_path` 复用给惩罚掉落时，落点必须用 `MapBounds` 压回地图
- Evidence / 证据: `scenes/item/parabola_path.gd`（`_pick_end_pos`）；`script/map_bounds.gd`（`nearest_inside`）
- Notes / 说明: `coin_box` 默认落点在 `30~120` 内且不 clamp；索尼克 360° 且 `80~260`，可能落到墙外。`clamp_to_walkable=true` 时每枚最多重采样 `target_attempts=8`，最终用 `nearest_inside(world, 16)` 兜底；默认关闭，避免改变旧掉落。
- Source / 来源: code
- Date / 日期: 2026-10-23

### [Coop/Field] 场地伤害的“房主结算”是房主计算、客机落地
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_on_host_orbital_blast`、`_remote_orbital_damage`）；`scenes/field_mods/orbital_barrage.gd`（`strike_blast_fired`）；`script/player_health_component.gd`（`TRUE_DAMAGE`）
- Notes / 说明: 玩家 HP 由各客户端本地权威，房主不能直接改远端玩家的 `Stats.hp`。轨道炮击采用房主用远端玩家代理位置/同步 `max_hp` 计算命中与 10% 真伤，再定向 RPC 给客机，客机用本地 `PlayerHealthComponent` 应用；客机视觉层绝不自行扫描范围或调用 `_apply_damage()`。不要再把“房主结算”误解为房主直接扣远端 HP。
- Source / 来源: user + code
- Date / 日期: 2026-10-23

### [Coop/Field] 取活玩家不能只扫 `"Player"` 组
- Evidence / 证据: `scenes/field_mods/orbital_barrage.gd:_alive_players()`；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（远端镜像加入 `"RemotePlayer"` 组，`_remote_player_down_changed()` 同步 `is_downed`）
- Notes / 说明: 房主本地玩家在 `"Player"`，客机玩家在房主侧只是 `"RemotePlayer"` 代理。只扫 `"Player"` 会让轨道炮击永远锁房主；房主倒地后列表为空，落点回退随机 cell。场地取点必须同时扫描两个组、按 `instance_id` 去重，并过滤 `is_downed`/`hp<=0`；这样房主死后才会转火存活客机，所有玩家都倒地才允许随机兜底。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-23

### [Map] R1 场地词条在物理就绪前调用 `ensure_ready` 会把 `MapBounds` 边界毒化成 SpawnMap 兜底（贴墙每秒回传）
- Evidence / 证据: `script/map_bounds.gd`（`_ensure_hull` 原早退 `_hull>=3` 永久缓存兜底；新增 `_retry_physics_frame` / `invalidate` / `_wall_crossing` / `_apply_pull`）；`script/GameEvents.gd:183-204`（`change_scene_to_file` 后 deferred `first_round_add` → `main.first_round()` → `round_manager.first_round_start()` → `emit_round_start` → `ChipManager.prepare_round` → `FieldModManager.apply_field_chips` deferred → effect `start`）；`scenes/field_mods/corruption_spread.gd:69` / `orbital_barrage.gd:50` / `terrain_field_effect.gd:38`（首帧 `MapChunks.ensure_ready()` → `MapBounds.ensure_ready()`）；`script/map_chunks.gd:46,175-180`（用 hull 建 cells，来源非 walls 时 warning）；`scenes/field_mods/field_mod_effect.gd`（新增 `_await_bounds_ready`）。玩家录像：R1 带腐化蔓延，腐化带明显不贴真实墙、留下 SpawnMap 与墙之间的一整圈地板，贴那圈下墙约每秒被拉回。
- Notes / 说明: **现象**（user）：导出的 PC 测试版偶发“下方贴墙约 1 秒回传一次”；玩家录像带腐化蔓延场地词条，腐化生成边界明显比真实可行走区小一圈，且这一圈会触发回传。**根因**：`Game.change_scene()` 在场景切换后 deferred 发 `first_round_add`，同帧内 `round_start → ChipManager.prepare_round → FieldModManager`（deferred）就启动了场地 effect；此时主场景的 `FloorWall` 刚进树、Rapier 还没跑过带新墙体的物理步，effect 的 `MapChunks.ensure_ready() → MapBounds.ensure_ready()` 4 条射线全部 miss → `_hull` 回退 `SpawnMap` 凸包（±768/±384，比墙内壁 ±864/±432 小一圈），且 `_ensure_hull` 的“`_hull>=3` 就早退”把它**永久缓存** → 腐化蔓延只按 spawn-safe 区生成；玩家/敌人贴真墙时超出这个小边界，`_is_out` 每 1s 判出界并拉到兜底边（下方差约 48px + miter，实测被拉到 y≈872）。首帧没被场地词条抢跑时，第一次构建是 round_start 后 1s 的 tick，物理已就绪 → 正常，故只“有时”出现。**修法**（A+B+C1）：① 只有 `boundary_source=="walls"` 才早退，兜底每次调用都重试射线（同物理帧一次），`first_round_add` / `Map` 实例变化 `invalidate()`；② `FieldModEffect.start()` 先 `await _await_bounds_ready()`（≤60 物理帧 ≈1s，超时打 warning 后仍以当前边界启动）再连 tick / `on_start`；③ 正常 walls 路径完全不动；仅兜底边界改用“中心→实体”墙射线（`entity_dist > wall_dist + 24` 才拉，落点 `hit - dir*(radius+INSET)`），贴墙不误拉；腐化蔓延每波 `_prepare_wave()` 前检查边界来源变化并重建 cells/块/边，`_await_bounds_ready` 先 `is_inside_tree()` 守卫避免空树 `get_tree()` 报错。**探针实测**（headless `map_bounds_probe.tscn`，已删除）：主场景加入树后同帧 `first_source=spawnmap`，下一物理帧 `after_physics_source=walls`；强制兜底 + 下墙贴墙 `(704,878)` 位置不变；墙外 `(704,940)` → 拉到 `(704,872)`；再强制兜底后 2 帧 `ensure_ready` 恢复 `walls`。**通用教训**：任何“惰性构建 + 失败回退”的边界/缓存，回退值绝不能用“已构建”作为终态；要么重试到可信来源，要么把回退标记为不可信并禁止其参与判定。依赖物理查询的初始化不要在场景刚进树的同帧信任结果。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-24

### [UI] 立绘卡片离树只释放引用，隐藏才清空纹理
- Evidence / 证据: `script/lazy_texture_binding.gd:8-32`、`ui/player_card.gd:173-185`、`tests/refactor_reuse_checks.gd:_check_cards`（本地测试不提交）。
- Notes / 说明: 三类卡片重构前离开场景树时释放 LazyTexture 引用，但仍保留显示节点的 texture；共用绑定需保持此区别。owner.tree_exiting 仅释放并清空路径记录，clear 才同时置空纹理；重新入树后 reveal 会重新 acquire，不把仍有 texture 误当成已持有缓存引用。四类真实卡片（含继承的 mod_player_card）已验证离树/重新入树与共享引用平衡，结果见 REFACTOR_REUSE.md。
- Source / 来源: test
- Date / 日期: 2026-10-20

### [Upgrade] 纯属性重复扫描须忽略说明注释，按函数体核对
- Evidence / 证据: `scenes/update_item/samuela_the_beyond.gd:1-7`；`tests/run_refactor_reuse_checks.py:effect_lines/repeated_effect/verify_item_diff`（本地测试不提交）。
- Notes / 说明: 初轮依赖完整文件模板，漏掉了 extends 与函数之间带说明注释的 samuela_the_beyond；该脚本并无特殊首次效果。复查已补齐，合计 35 个道具。识别相同首次/叠加效果时须按函数体剔除空行/说明注释，再核对属性表达式、顺序与 quantity=1 守卫；不能因脚本头部注释而排除候选，也不能去重首次/后续不同的 s_bullet。当前守卫仅针对同型常量属性赋值，不代表所有复杂道具均可机械重构。
- Source / 来源: code
- Date / 日期: 2026-10-20

### [Shop] 确认动画之后才读触屏余额，解锁通知之前不扣款
- Evidence / 证据: `ui/shop_purchase_card.gd:57-89`、`ui/character_shop_card.gd:add_character`、`ui/item_shop_card.gd:add_item`、`script/PlayerData.gd:13-20`；本地 `tests/shop_purchase_flow_checks.gd` 追踪（不提交）。
- Notes / 说明: 触屏 yes 先等待选中动画，随后才判断余额与价格；shoot/鼠标立即判断。共用流程须先调用商品解锁（角色/社团各按需存档并发 check_data；服装按分组存档），再重读当前价格扣款。货币 setter 的 pyroxenes_changed 又早于其存档，所以通知中读到的主档可能仍是扣款前值。把存档合成一次、提前缓存价格或统一触屏/鼠标的等待点都会改变可观察行为；本次只提取流程，没有改变这些契约。
- Source / 来源: code
- Date / 日期: 2026-10-20

### [DOT] 火与毒扩散共享生命周期，但不能统一计时与选敌时机
- Evidence / 证据: `scenes/debuff/fire_diffuse.tscn:23-25`、`poison_diffuse.tscn:22-23`、`script/dot_diffuse.gd:18-57`、`scenes/debuff/poison_diffuse.gd:6-41`；本地 `tests/diffuse_lifecycle_checks.gd`（不提交）。
- Notes / 说明: 火 Timer 为单次、毒 Timer 为重复模式；共同超时回调只先置 add_end=true、结算、关闭探测，不停 Timer 或清目标。毒仅在集合进出时排序，结算前不会因目标移动重新排序；已有 poison_diffuse 标签不覆盖。集合在进入结算时非空、剔除后全无效，或毒 enemy_num=0，仍生成扩散飘字。上述差异已用原版基线与真实物理/Timer 对照确认，提取共用逻辑时不可顺手统一或提前短路。
- Source / 来源: code + test
- Date / 日期: 2026-10-20

### [Upgrade] 旧抽取入口无仓库内调用，但“备用”抽样方法与标签上下文仍须保留
- Evidence / 证据: 基线 `1e84934` 的 `scenes/manager/upgrade_manager.gd:73-126,142-150,199-231,259-287,300-306`、`ui/UpgradeScreen.gd:201-214`、`script/mod_api.gd:60-61`；2026-10-20 对本体、SDK、官方 coop 与文本场景/资源进行静态引用扫描。
- Notes / 说明: 当前选卡走 add_upgrade_card→get_triple_choice→get_random_options→get_random_item_from_pool，get_random_options 虽标“备用”仍是正式路径。pick_upgrades 未发现仓库内调用；tag_sort 仅被该旧入口调用，tag_count 的调用已注释。round_bouns 与 tag_1/2/3 的读取仅属旧算法，可作为后续清理候选；但 round_bouns_upgrade 仍负责回合权重等现用流程，不能随字段一并删除。tags_group 仍由 get_current_context 以 player_tags 键输出，即使当前本体没有活跃写入，也应保留字段与上下文形状。本轮仅核实，未删除代码；外部已打包或以动态拼接方法名调用的 Mod 兼容性无法由此静态扫描保证。
- Source / 来源: code
- Date / 日期: 2026-10-20
- Follow-up / 后续（2026-10-20，来源：code + test）：用户授权清理后已删除上述三个旧方法、四个字段、旧增量及注释调用，现用方法与 tags_group 保留；此前“仅核实、未删除”描述属于核实阶段。固定 5 种子的 50 场景、966 项断言、520 条当前行为追踪与改前一致，现用 14 个方法的可执行内容仅减少旧字段增量；详见 `docs/UPGRADE_LEGACY_CLEANUP.md`。仓库外 Mod 直接调用旧方法的兼容风险仍存在。

### [UI] 难度页入场窗口内展开的预览会被父级忽略，按钮动画永久卡在展开态
- Evidence / 证据: `ui/level_select.tscn:410-435`（`select_in` 在 t=0.2 的 method track 调 `emit_player_selected`）；`ui/level_button.gd:26-27,61-87`（`player_selected→open_mouse` 启用鼠标/焦点、`mouse_entered/focus_entered→mouse_in→open_preview`、新增 `_preview_allowed` 门控）；`ui/level_select.gd:306-324`（`animation_finished` 后再等一个 `process_frame` 才置 `_keyboard_ready=true`）、`:222-234`（未就绪时 `previewed` 被忽略/收起）；入场窗口内调用 `open_preview()` → `_preview_open=true` 且 `_open_level_button=null`，之后不再被收起。
- Notes / 说明: **现象**（user）：进入难度选择时，鼠标在难度框内来回移动，有概率某个按钮的动画一直保持展开。**根因**：动画 method track 先启用按钮的鼠标/焦点，`_keyboard_ready` 晚一帧；窗口内 hover 展开后 `previewed` 被父级忽略且不记录 `_open_level_button`，该按钮 `_preview_open` 永久为 true → 后续 `open_preview()` 全部早退、父级也只会关闭“被记录的那一个”。若入场时鼠标停在非第一个难度上，ready 后第一个难度又展开，便会同时出现两个展开且其中一个卡死。**修法**：`level_button.mouse_in/open_preview` 经可选 `is_preview_ready()` 门控（`level_select` 返回 `_keyboard_ready and not _selection_pending`；`coop_difficulty` 无该方法、行为不变），父级在忽略路径主动 `close_preview()` 兜底。**通用教训**：① 「按钮先播动画、再通知父级」的预览模式必须让父级能在通知时拒绝并回滚本地状态；② 动画 method track 启用输入与逻辑就绪标志分属两帧时，门控应画在按钮侧或延后启用，不能只靠父级忽略信号；③ 卡死类 UI 问题优先核对「按钮本地状态」与「父级记录」是否会失配。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-24

### [UI/Boss] 乱入提示复用 FEVER 横幅时，FEVER 播放入口必须写回默认文本
- Evidence / 证据: `ui/round_timer.gd`（`play_fever_anim()` / `play_boss_intruder_anim()` / `_play_banner(text)`）、`ui/round_timer.tscn:399-435`（`FeverTime` 节点与 `fever_time`/`fever_anim` 动画）
- Notes / 说明: `!! BOSS RAID !!` 与 `>> FEVER TIME >>` 共用同一个 `$FeverTime/Label` 和两段动画；只在乱入时改文本会让下一次 FEVER 继续显示 RAID 文本。当前两条触发在时间上互斥（乱入为回合开始后 10–25s；FEVER 在普通计时归零或 Boss 超时），但新增任何复用该横幅的触发都必须走 `_play_banner(text)`，并在各自的播放入口显式给文本。
- Source / 来源: code
- Date / 日期: 2026-10-24

### [PlayerData] `_recompute_player_ability` 的 clamp 参数全部颠倒，属性上限是死参数；满弧公式含整数除法
- Evidence / 证据: `script/PlayerData.gd:354,359,362,370,374-376,378,379,386`（`clamp(下界常量, 计算值, 上界)`，如 `:354` `clamp(0, ...critical_luck..., 101)`、`:359` `clamp(50, ...MAX_SPEED..., MAX_SPEED_value)`、`:362` max_hp 上界 99999）；`:384` `360 * (1 - 1/player.stats.bullet_count)`，`script/Stats.gd:61` `bullet_count: int`。
- Notes / 说明: GDScript `clamp(value, min, max)`，这里 value 位放的是常量下界，实际语义为 `max(下界, 计算值)`——下界碰巧生效、**上界全部不生效**：暴击率可超 101（>100 即必暴）、速度/HP/弹药/弹速/伤害的 9999/99999 级上限均可被乘区突破且不可逆。满弧分支 `1/bullet_count` 是 int/int 整除，count≥2 恒得 0 → 弧度恒 360（本意 360*(1-1/count) 避免首尾重叠），单弹 arc=0、多弹全圆。修复需逐条改回 `clamp(计算值, 下界, 上界)` 与 `1.0/count`，并核对各上限的既有实际表现（改动会改变数值行为，须跑数值回归）。
- Source / 来源: code
- Date / 日期: 2026-10-24
- Follow-up / 后续（2026-10-24，来源：code）：当日已按上述结论修复——`_recompute_player_ability` 内 11 处 clamp 改回 `clamp(计算值, 下界, 上界)`、满弧公式改 `1.0/count`；另全局排查并修复 7 处同型误用（`EnemyStats.gd:168`、`mashiro_sniper_bullet.gd:193`、`tester_automaton_shield.gd:130`、`GunOverheating.gd:47-48`、`spiked_shell.gd:51`、`ability_upgrade_card.gd:56`）。上限参数首次真正生效，属性数值行为会变化（超上限不再穿透）。
- Follow-up / 后续（2026-10-24，来源：code）：修复同时让**外部注入的上限变量第一次真正生效**，合并前需实机确认：`PlayerData.max_ammo_value`（`scenes/player/tsurugi/tsurugi_ps.gd` 弹匣 2、`scenes/player/hibiki/HibikiPS.gd` 1、`scenes/update_item/concentrated_ammo.gd` 1）、`PlayerData.max_bullet_speed`（`scenes/update_item/crystal_haniwa.gd` 150）、`PlayerData.MAX_SPEED_value`（`scenes/update_item/encyclopedia.gd` 锁当前速度）。另有数值调整：子弹伤害上限 `999999` → `9999999`（`PlayerData.gd`），Aris 过热路径的独立上限 `99999` → `9999999`（`GunOverheating.gd`），否则该路径仍会卡在旧上限。

### [Stats] 暴击率 101 上限：判定值与溢出消费分工（PS3 读总量，PS1 刻意封顶）
- Evidence / 证据: `script/PlayerData.gd`（`get_critical_luck_total()` = `max(0, base_critical_luck + critical_luck_add) * critical_luck_mult * ability_mult`；`_recompute_player_ability` 用 `clamp(get_critical_luck_total(), 0, 101)` 写 `stats.critical_luck`）、`scenes/player/hasumi/hasumi_ps.gd:53-59`（PS1 射速读封顶后的 `stats.critical_luck`）、`:66-74`（PS3 暴伤 `int(get_critical_luck_total()) - 100`）、`scenes/update_item/buried_treasure_map.gd`（幸运→暴击改走 `critical_luck_add` 增量 + `reset_done` 清账）、`hasumi_ps_1/3` 卡面文案（`ETN_player_localization.csv`）。
- Notes / 说明: `stats.critical_luck` 只服务判定与 HUD（判定 `randf_range(0,100) < crit`，≥100 与 250 等价必暴），上限由 `clamp(..., 0, 101)` 负责。**溢出消费按用途区分**：PS3「每溢出 1% 暴击率 +2% 暴伤」读未封顶总量 `get_critical_luck_total()`；**PS1「每 1% 暴击率 +1% 射速」刻意读封顶后的判定值**——2026-10-24 用户裁定射速不应随溢出无限成长，加成上限停在 +101%（早期曾改为读总量，随后按此裁定改回）。`critical_luck_add` 仍不封顶（Hasumi PS0 换弹叠 5/8/15%、怀表/狙击镜、藏宝图等都写它）。藏宝图原直接写 `stats.critical_luck`（绕过 clamp，且只被 PS1 读到），改为对 `critical_luck_add` 做「先扣旧再加新」的增量记账并在 `PlayerData.reset_done` 清本地记账，避免 `reset_date()` 归零后扣成负数、也避免它重新把 `stats.critical_luck` 顶过 101；同一重算代内重复进入由 `new_luck_add == luck_add` 早退收敛。若以后要让 PS1 也吃溢出，改回 `get_critical_luck_total()` 即可。
- Source / 来源: user + code
- Date / 日期: 2026-10-24

### [GDScript] 基类调用子类方法必须声明桩，否则整个 class_name 注册链编译失败
- Evidence / 证据: `ui/ability_shop_card_base.gd:_attempt_purchase` 调 `item_upgrade()` 时基类未声明，报 `Function "item_upgrade()" not found in base self`，连带两个子类 `Could not resolve class "AbilityShopCardBase"`；同仓库既有模式 `ui/shop_purchase_card.gd`（基类声明 `_get_purchase_cost`/`_grant_purchase`）、`script/fire_field_base.gd`（钩子 `_field_lifetime` 等均带默认实现）。
- Notes / 说明: GDScript 2 对基类内直接调用未声明方法是**硬编译错误**（不是 warning），且基类编译失败会让 class_name 无法注册、所有按类名引用的脚本连锁失败。基类模板方法（Templated Hook）必须显式声明空桩或默认实现；探针脚本 `--script` 模式 `load()` 全部相关脚本是验证这类继承链的最小手段（`--check-only --script` 不注册 autoload，不可用）。
- Source / 来源: code
- Date / 日期: 2026-10-24

### [Pickup] `coin.can_pick` 不随 `idle_state()` 重置：parabola 飞行态污染金币池，复用币 `pick_up=true` 却永不归位
- Evidence / 证据: `scenes/item/parabola_path.gd:50`（`drop()` 取池时置 `body.can_pick = false`，落地 `:83` 才恢复）；`scenes/item/coin.gd` `idle_state()`（重置 `pick_up/target/ignore_*` 但**不重置 `can_pick`**）；`scenes/manager/coin_manager.gd` `_activate()`（复用池内金币时不设 `can_pick`）。实测（SceneTree 探针 + 真实场景）：sonic 掉币 → 拾取回池（`can_pick` 残留 false）→ `CoinManager.drop_coin` 复用该币 → PickBox `area_entered` 置 `pick_up=true`，但 `coin._physics_process` 要求 `pick_up && can_pick` 同真 → 金币永久躺在原地，玩家走近/站上去都无反应，币值不入账。
- Notes / 说明: **现象**（user）：单机启用 sonic 词条后，获得大量金币时受伤，掉落的金币部分无法捡起；用 Trainer 把拾取范围 ×10 后成堆卡死币在玩家眼皮底下可见（PickBox 在币重新激活时补发 `area_entered` 置 `pick_up=true`，卡死状态更显眼）。**根因**：`can_pick` 的生命周期只由 `parabola_path.drop()` 维护，回池时残留 `false`；`coins` 池被 parabola（sonic/coin_box）与 `CoinManager` 双方共用，后者假设池内金币 `can_pick=true`（首次生命周期成立、复用后不成立）。**修法**：① `coin.gd idle_state()` 重置 `can_pick = false`（回池即失能，状态显式化）；② `coin_manager.gd _activate()` 显式置 `can_pick = true`（地面投放立即可拾取）；`parabola_path.drop()` 本就显式写 false/true，不受影响。**通用教训**：双消费方共用的对象池，激活路径必须显式设置**全部**门控状态，不能依赖「上一次使用者恰好留对了值」；`idle_state()` 的重置清单与 `drop()/active_state()` 的写入清单要对齐审计（本例 `pick_up/target/ignore_*/add_end` 都有对齐，唯独漏 `can_pick`）。
- Source / 来源: code + test
- Date / 日期: 2026-10-24

### [UI/Coop] 共享 `level_button` 直接写父级 `transition_started`，父级未声明会中断 `_on_timer_timeout`
- Evidence / 证据: `ui/level_button.gd:148-155`（`:151` 直接赋值、`:155` 才 `GameEvents.change_scene`）、`ui/level_select.gd:17`（单机难度页声明该属性）、`mod_sdk/coop_mod/mods/etn_coop/ui/coop_difficulty.gd`（`_populate_levels` 把 `level_select` 指向自身但修复前未声明；已解包 `etn_coop_0.1.10`～`0.1.13` 的 pck 均不含该字符串）、`mod_sdk/coop_mod/mods/etn_coop/entry/coop_entry.gd:1012-1016`（devflow 直接 `change_scene`，绕过按钮）。
- Notes / 说明: **现象**（user）：0.5.2.0-test 联机模式选完人后卡在难度选择界面，房主点关卡不转场、客机停在「等待房主选择」；反馈集中在移动端。**根因**：`level_select` 是挂 `coop_difficulty.gd` 的 `CanvasLayer`，GDScript 对不存在属性的赋值是**运行时错误并中断当前函数**（运行中的游戏 `game_eval` 实测：`Invalid assignment of property or key 'transition_started' with value of type 'bool' on a base object of type 'CanvasLayer'`），`_on_timer_timeout` 在 151 行结束 → 转场与 `change_scene` 都不执行。**为何漏测**：联机自动化全走 `--coop-devflow`，房主侧直接 `GameEvents.change_scene(...)` 绕过 `level_button`；README 声称的「难度按钮走 level_button」从未被自动跑过。**修法**：`coop_difficulty.gd` 补 `var transition_started: bool = false`（与单机页对齐；两份副本同步；协议仍 v6，`MOD_VERSION` 0.1.13→0.1.14 仅作发布标记，旧 PCK 因握手版本号不等会被拒）。**移动端放大因素**：联机难度面板只有 ESC 取消、没有屏幕返回按钮，手机无 ESC → 连退出都做不到。验证：`tests/run_coop_difficulty_start_checks.py`（本地、从 `mod_sdk` 打包 pck、隔离 user://、headless 走 `level_button → Timer → change_scene`；修复前 `checks=5 failures=2` 并打印 `level_button.gd:151` 的 SCRIPT ERROR，修复后 `failures=0`），单机难度页 `--level-focus-only` 37 项仍通过。**通用教训**：① 共享 UI 脚本向父级写属性时，父级必须声明；② 带 `await`/Timer 的启动回调里一次运行时错误就足以让整个流程静默卡死；③ 自动化若绕过真实 UI 入口，等于没测该入口。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-24

### [Coop/Enemy] 敌人「非死亡移除」不会自动同步，host 侧 queue_free 必须以离树为最终事实广播 despawn
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`register_enemy_spawn` → `_connect_enemy_despawn`、`_on_server_enemy_exiting`；`_connect_enemy_dead`/`_on_server_enemy_dead` 先 `_forget_enemy_net_id` 再延时 despawn）；`scenes/manager/enemy_manager.gd:318-338`（`resolve_boss_intruder_timeout` / `_clear_boss_intruders` 直接 `queue_free`）；`scenes/enemies/boss/goliath.gd:275-305`、`scenes/enemies/boss/erosion_tower_group.gd:187-213`（`boss_intruder_escape`）；`scenes/main/main.gd:99-110`（`enemy_clear_unit` 跳过 `"BOSS"` 组）；本地双进程回归 `tests/run_coop_intruder_despawn_checks.py`（不入库：修复前 host/client 双 FAIL，修复后 PASS）。
- Notes / 说明: **现象**（user）：联机 TM 乱入 Boss 死亡或离场后客机仍残留，含其自带 `BossHP` 血条，后续回合也不消失。**根因**：coop 只同步 `stats.is_dead`，而乱入 Boss 的**离场**（FEVER 超时倒放入场动画后 `queue_free`）与**清场**（`round_end` / `game_over` / 首轮 `_clear_boss_intruders`）都不 emit `is_dead`，也没有 despawn 广播；客机镜像不在 `enemy_clear_unit` 的清理范围内（`"BOSS"` 组被跳过）→ 永久残留。**修法**：host 登记敌人时挂 `tree_exiting`，离树时若该 net_id 仍映射到本节点就 `_forget_enemy_net_id` + `rpc("_despawn_enemy_remote")`（复用现有 RPC，协议不变）。**为什么安全**：普通敌人死亡在 `_on_server_enemy_dead` 里先抹掉映射、节点之后才离树 → 回调早退，不截断死亡动画；普通敌人死亡走 `idle_state()` 回池、不离树；场景切换/回标题在真正换场景前已 `_reset_enemy_sync()` 清空映射。**通用教训**：只挂「死亡」信号的同步方案必然漏掉「超时离场 / 回合清场 / 被系统直接移除」，实体移除应以「节点离树」为最终事实并做幂等广播；新增移除路径时不要再逐点补钩子。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-25

### [Coop/Field] 场地词条音效在客机是「纯表现」，host 播了不代表客机有声
- Evidence / 证据: `scenes/field_mods/orbital_barrage.gd:155,199`（host 播 `BlipSounds1` / `ExplosionSounds2`）；`scenes/effects/orbital_barrage_remote.gd`（客机纯表现，2026-10-25 在 `add_marker`/`spawn_blast` 补同一 key 与节流，`apply_state` 传 `play_sound=false`）；`scenes/field_mods/corruption_spread.gd:310` + `:363-380`（`is_remote` 镜像 `apply_remote_wave(ACTIVE)` → `_activate_wave()` 本地播 `CorruptionSpawn`，已同步）；本地单进程回归 `tests/field_sfx_checks.gd`（不入库）。
- Notes / 说明: **现象**（user）：联机场地词条音效不同步。**结论**：轨道炮击的落点提示与逐发爆炸音只在 host 的 `orbital_barrage.gd` 里播，客机 `OrbitalBarrageRemote` 只复刻 marker/粒子 → 客机完全无声；腐化蔓延反而本来就是同步的（客机镜像 `apply_remote_wave(ACTIVE)` 会走 `_activate_wave()`，同一 `AudioStreamPlayer` 重播，听感一次）。**约定**：新增场地词条时，host 的每个 `SoundManager.play_sfx*` 都要在对应客机纯表现脚本里以同一 key/节流参数回放；补发历史状态（`apply_state`）不补播音效；不要给已同步的腐化蔓延再加第二份。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-25

### [Coop] Ako 链锁到塔组根（无 `frozen` 的聚合 Node2D）→ 整组 BOSS 被拖、远端激光留在原地
- Evidence / 证据: `scenes/enemies/boss/erosion_tower_group.tscn:59`（塔组根无 `groups`、无 `frozen`；子塔才是 `BOSS`/`Enemy`）、`script/spawn_anim.gd:146`（net_id 打在塔组根）、`scenes/player/ako/ako_chain.gd:144`（本体 BOSS 超距只释放不拖）、`scenes/bullet/launcher/laser_launcher.gd`（发射器是塔体子节点，客机看到的是特效克隆）；mod `mods/etn_coop/net/coop_net.gd`：`_resolve_enemy_net_id`（`:3183` 回溯父链）、`_apply_ako_lock`（`:3293`，原实现对根写 `frozen`）、`_tick_ako_locks`（`:3346`，只对 `BOSS` 组跳过夹取）、`_on_projectile_spawned`（`:3637`，一次性特效通道）、`_effect_anchor_of/_bind_effect_anchor/_tick_effect_anchors`（`:3726/:3773/:3790`）；`docs/LEARNINGS.md:3379`（不存在的属性赋值会中断当前函数）。
- Notes / 说明: **现象**（user）：联机侵蚀之塔 Boss 被 Ako 链拖动；塔移动后客机端激光留在原地（伤害洞也在原地），房主/客机两种角色都能复现。**根因**：链命中子塔后 `_resolve_enemy_net_id` 沿父链回溯到塔组根；host `_apply_ako_lock` 对根写 `frozen` → GDScript 运行时错误并中断函数，但错误前 `_ako_lock_by_enemy` 已登记；`_tick_ako_locks` 只对 `BOSS` 组跳过夹取，塔组根不在组里 → 整组塔被夹到 Ako 120px 内。客机激光是 `on_projectile_spawned` 的一次性特效克隆，只在生成时定位，不随镜像塔移动。**「房主和客机都会」不是本体 bug**：两条锁定路径最终都汇到 host 的同两个 mod 函数；本体没有写塔组根位置的代码，战斗动画也不移动发射器（只有 `enter_anim` 移动 `Graphics`，且开火在入场结束后）。**修法（纯 mod）**：① `_apply_ako_lock` 对 `enemy.get("frozen") == null` 的聚合实体返回 false、不再登记；host 本机入口与 `_server_ako_event` 按返回值收回链（`_ako_release_owner_chain`），`_tick_ako_locks` 加不可冻结防御分支；② `laser_launcher` 特效 entry 附 `an`(宿主 net_id)+`ap`(相对 net entity 根的路径)，客机解析镜像发射器并逐帧把克隆 `global_position` 贴过去（只锚位置、旋转仍自驱）。**通用教训**：① 聚合实体根（Node2D + 聚合 stats）没有 `Enemy.frozen`，按 net entity 写敌人字段前必须做能力检查，拒绝时不能只吞错误、必须撤销登记；② 一次性视觉克隆若宿主会移动，必须按 net_id + 相对路径绑定镜像节点，不能只信生成时世界坐标；③ 「房主和客机都复现」先确认权威路径是否都汇到 host，再判断本体；④ 塔组根故意不在 `BOSS`/`Enemy` 组（`main.gd:enemy_clear_unit` 只清直接子节点），不要为了这条链把根加组。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-25

### [Chip/Field] 轨道炮击金币优先取点只认落地金币，且选点必须 host 权威
- Evidence / 证据: `scenes/manager/coin_manager.gd`（`get_active_coins()`）；`scenes/field_mods/orbital_barrage.gd`（`_collect_gold_samples` / `_score_gold_candidates` / `_choose_gold_target` / `_choose_target_point`）；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_on_host_orbital_marker`）。
- Notes / 说明: **金币密集**只能读 `CoinManager` 的活跃集，不能扫 `CoinRoot` 直接子节点（会漏掉挂在 `PathFollow2D` 下的金币、也拿不到回池真源）；取样必须过滤 `pick_up`（已被玩家 PickBox 触发归位，马上消失）、`can_pick == false`（抛物线/Boss 演出飞行期）、`is_idle == 1`（回池）与无效/出树节点。按面值加权并对单枚设上限（默认 10），否则一枚合并大币会压过真实密度；候选用世界空间分桶质心 + 半径内权重线性衰减，避免逐点聚类。无合格金币/最高分 < `gold_min_weight` 时回退玩家；全部候选都离已有落点太近时仍取最密集点，不转去打玩家。客机只收 marker 坐标、不评估金币，**不要**在客机重复选点。
- Source / 来源: user + code
- Date / 日期: 2026-10-25

### [Coop/Field] 场地词条给远端玩家的 debuff 必须走玩家 buff RPC，不能对代理直接 apply_buff
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_gate_player_buff_apply` / `_support_buffed_peers` / `_on_local_support_ex_end` / `_remote_player_buff`）；`scenes/field_mods/orbital_barrage.gd`（`_apply_player_slow` / `get_player_slow_config`）；`scenes/manager/buff_manager_base.gd`（`apply_buff` / `_create_entry` / `source_refcount`）。
- Notes / 说明: `BuffRouter.apply_buff(远端玩家代理, ...)` 虽会被 `player_buff_apply_interceptor` 转交到客机，但该通道同时把 `peer -> buff.resource_path` 写进只按 peer 记**单路径**的 `_support_buffed_peers`（供支援 EX 结束兜底移除）；场地词条复用它会把光环路径覆盖掉，导致支援 buff 的兜底移除指向错误路径。轨道炮击改为 host 在 `_on_host_orbital_blast` 用既有 `_remote_player_buff` RPC 直接下发 buff（不新增 RPC/协议），客机 `_remote_player_buff` 对本地真实玩家 `BuffRouter.apply_buff`。减速 buff 用 `source_refcount=true`：多次命中只刷新 1.5 秒、不叠层；`is_debuff=true` 才不吃“有益 Buff 持续时间”加成。数值由本体 `get_player_slow_config()` 提供（含 `buff_path`/`value`/`source_id`），mod 不另写一份。
- Source / 来源: user + code
- Date / 日期: 2026-10-25

### [Boss][Tower] 塔组攻击窗口会被激光 `total_active_ticks` 拉长：招式时长必须以它为下限
- Evidence / 证据: `scenes/bullet/launcher/laser_launcher.gd:204-205`（`total_active_ticks = WARNING_TICKS + life_time + END_TICKS`）、`scenes/enemies/boss/erosion_tower.tscn:1571-1579`（两台 launcher `life_time=120/150` → 150/180 tick）、`scenes/enemies/boss/erosion_tower_group.gd:188-199`（`_effective_window`）、`:165-179`（`_begin_step`）；旧实现见 git 历史 `_active_attack_ticks()`。
- Notes / 说明: 旧 `_active_attack_ticks()` 对**所有 `can_shoot` 塔**的 `launcher_pool_1` 取 max，而三座塔（含弹幕/召唤）都实例化同一个 `erosion_tower.tscn`、各自带两台 launcher，所以只要任一塔参战窗口就会变成 180 tick（18s）——「弹幕招只有 6 秒」是错觉，旧阶段 1 实际每轮恒为 180+25 tick。2026-10-25 改序列驱动后，窗口下限只统计 `tower_type==1` 的激光塔，`window_ticks` 才真正可控；要让非激光招维持旧时长，需在 `.tres` 里显式写 180。**通用教训**：用「节点是否存在某组件」推断「本次是否真的会用到它」不可靠（这里是 launcher 继承），能力判断应按角色/开关字段来做。
- Source / 来源: code
- Date / 日期: 2026-10-25

### [Mod/PS] 裁决态子弹伤害乘区用**加法 +1.0**，不能用 `*=2 / /=2`
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_ps.gd`（`_apply_bullet_bonus()` / `_remove_bullet_bonus()`、`activate_crucible()` / `exit_crucible()` 接线、`_reset_hard()` 只清 `_bullet_bonus_applied` 不做减法）；生效点 `script/PlayerData.gd:381`（`bullet_damage = clamp(max(1, base+add) * bullet_damage_mult * ability_mult, 1, 9999999)`）；共享该字段的道具：`scenes/update_item/aether_piece.gd:5`（+0.15）、`dumbbell_set.gd:5`（+0.12）、`s_bullet.gd:6`（**`*= 0.4`**）等 20+ 处。
- Notes / 说明: `bullet_damage_mult` 是全项目共享乘区，语义以 `+=/-=` 为主；升到裁决态时 `+= 1.0`（+100 个百分点）、退出时 `-= 1.0`，加法与顺序无关，能精确还原裁决期间新拿到的加算。**不能**用 `*= 2` 再 `/= 2`：升级界面在裁决态仍生效（`_on_round_upgrade_carry` 保留裁决态），期间拾取的道具会被乘除回滚吞掉一半加算。**生命周期**：`_reset_soft`（回合开始）不动该加成（裁决态跨回合保留）；`_reset_hard` 只清标志不减法（`reset_date()` 已把字段复位为 1，再减会变负，与 `_combo_bonus` 同款约定）。**已知限制**：`s_bullet` 是唯一用 `*= 0.4` 的道具，若在裁决态生效期间拾取，退出时按 `max(0, x-1.0)` 还原会少约 0.4；规避＝非裁决态拾取，或后续把 `s_bullet` 改加法。
- Source / 来源: user + code
- Date / 日期: 2026-10-25

### [UI][Input] 全屏模态遮罩只盖内容区时，KEEP 黑边里的点击会穿透到「伸出内容区」的控件
- Evidence / 证据: `project.godot:57`（`canvas_items`，未设 aspect → KEEP）、`ui/level_select.tscn`（遮罩 `ColorRect` 原为 `(0,0,640,360)`）、`ui/level_select.gd`（`MODAL_BACKDROP_MARGIN` / `_extend_modal_backdrop`）、`scenes/main/menu_screen.tscn:2144-2156`（`SocietyCardBox` x=594，`ScrollContainer` 内容坐标 x≈586..699，比 640 内容区多出约 59px）
- Notes / 说明: 视口只渲染 640×360（`get_visible_rect()`），比 16:9 宽的窗口两侧是未绘制的黑边；黑边里的点击会被拉伸变换映射到内容区**之外**的坐标，而 GUI 命中测试只按控件矩形判定、不看视口裁剪 → 伸出内容区的可交互控件（这里是最右侧社团卡列）会被黑边点击命中，难度页整屏遮罩因为只有 640×360 挡不住，表现为「点黑边，背后社团切了一组」。修法：全屏模态的遮罩/输入屏障必须把**命中矩形**外扩出内容区（本项目 `MODAL_BACKDROP_MARGIN=1024`，覆盖到约 7:1 比例）；只扩命中区不扩外观——视口外不会绘制，画面不变。注意这只修有遮罩的模态页：没有遮罩的页面（如裸选角页）同样会被黑边点击命中伸出内容区的控件。
- Source / 来源: user + code
- Date / 日期: 2026-10-25

### [UI] 切社团的异步填充必须可取消：`on_select` 是既有的代次信号
- Evidence / 证据: `scenes/main/menu_screen.gd:271-308`（`society_card_filter` / `_society_seq`）、`scenes/main/menu_screen.gd:327-334`（`change_player_card` 先摘树再释放）、`ui/society_card.gd:33-52`（`populate_player_cards` 的 `on_select` 检查）、`ui/mod_society_base.gd:43-64`、`scenes/main/menu_screen.tscn`（`SelectPlayer/AnimationPlayer` 的 `change_player_card` 在 t=0.14s method track 调 `change_player_card()`）
- Notes / 说明: `player_card_clear_done` 是**全局信号**，每次清卡会唤醒**所有**正在等它的 `society_card_filter` 协程；旧请求若不检查请求序号，就会和新请求各跑一遍 0.07s/张 的填充循环，同一个 `PlayerCardBox` 里混进上一社团的角色卡（表现为卡池混卡 / 重复 / 数量翻倍）。填充循环跑在卡片脚本里、mod 会覆写单参数 `populate_player_cards(box)`，所以不能给它加参数，改用卡片自己的 `on_select` 当代次信号：新社团被选中时父级先对旧卡 `out_select_card()`（同步置 false），旧循环下一轮即退。**契约**：`on_select_handle()` 必须先置 `on_select = true` 再 `emit_society_card_selected()`，否则首轮填充会被自己取消。另一个坑：`AnimationPlayer.play()` 对**正在播放的同一动画不会重置**、method track 不重放 → 清卡动画播放中（尤其过了 t=0.14 的 track 之后）再点社团会永远等不到 `player_card_clear_done`（`_society_switching` 卡死、新社团卡池不生成）；重播前需先 `stop()`，但只在重播同一条动画时 stop，避免打断 `select_player` / `out_player` 的滑入滑出。
- Source / 来源: user + code
- Date / 日期: 2026-10-25

### [Combat] 腐化下的「满血 / 最大生命值为 1」判定必须用 `get_effective_max_hp()`，不能直接比 `max_hp`
- Evidence / 证据: `script/Stats.gd:145-158,211-233`（`corruption` 绝对扣减 + `get_effective_max_hp()`）；`scenes/update_item/energy_supplement.gd:24-44`（`player_hp_count()` 原 `hp == max_hp`、`fatal_damage_health()` 原 `max_hp <= 1`）；`resources/buff/components/last_stand_component.gd:80-130`（新增 `_effective_max_hp()` + `on_timeout`/`check_time_start`/`check_player_hp`）；`scenes/update_item/student_council_hard_hat.gd:22-25`（半血阈值）；反例 `scenes/item/medical_kit.gd:12` 已用有效上限。
- Notes / 说明: 腐化不改 `max_hp`，只把有效上限压成 `max_hp - corruption`，所以任何 `hp == max_hp` / `hp >= max_hp` 的满血判定在腐化 > 0 时**永不成立**：`energy_supplement` 的免死因此完全不 arm；`last_stand` 的 buff 永远无法靠回血提前结束，且 `on_timeout` 的 `hp < max_hp` 恒真 → 超时必 game over。反过来，`fatal_damage_health` 的 `max_hp <= 1` 早退在腐化到有效上限 1 时也不再成立，会让「每次致命伤害保留 1 血」变成无限触发，必须按有效上限早退。`last_stand` 组件也可能挂 `EnemyStats`（独立类、不继承 `Stats`、无 `get_effective_max_hp`），helper 需 `has_method` 回退 `max_hp`。腐化保持**绝对数值扣减**（用户裁定），加 `max_hp` 的道具是纯收益；各比例腐化来源仍在各自计算处换算成整数后再 `add_corruption`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-25

### [Coop] 退房收尾协程不能用 `_session_generation` 判活：`close_connection` 会把它自己作废
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_schedule_host_left_return` / `_handle_host_left` / `_on_server_disconnected` / `close_connection` / `_reset_run_state`）；复现：host `--coop-host --coop-devbattle`、client `--coop-join=127.0.0.1 --coop-devbattle --coop-devquit`（隔离 `user://` + `mod_sdk/pack_mod_source.ps1` 打包 0.1.14 源码），主机退出后客机停在 `peer disconnected: 1` / `server disconnected`，45s 无任何输出、无 `host session closed -> return to menu`，进程常驻；加窗口跑同样结果。玩家日志同样停在 `server disconnected`（`ETN_debug2026-10-25T16.07.35.log:308-310`、`ETN_debug (1).log:39-40`）。
- Notes / 说明: `_on_peer_disconnected(1)` 里 `_schedule_host_left_return()` 先 queue `_handle_host_left`，同一 poll 的 `_on_server_disconnected()` 又 queue `close_connection(true)`；延迟队列按序执行时 `_handle_host_left` 在 `await tree.process_frame` 处挂起，紧随其后的 `close_connection` 递增 `_session_generation`、且 `_reset_run_state` 把 `_returning_to_menu_due_to_close` 清回 false，协程恢复后 `generation != _session_generation` 直接 return → 客机不回菜单、停在已断线的战斗场景（玩家/测试表现为「崩溃/卡死」，实际是死局常驻）。修法：①新增 `_session_epoch`，只由 `host_game`/`join_game`/`create_relay_room`/`join_relay_room`/`close_session` 递增，退房协程用它判活；②`_on_server_disconnected` 在 `_returning_to_menu_due_to_close` 为真时直接 return（收尾权归 `_handle_host_left`）；③`_reset_run_state` 不再清该标志（改由新会话入口清）；④`_remote_change_scene` 客机侧补 `_flow_phase = FlowPhase.BATTLE`（dev-flow 实测客机停在 3/ALL_READY、host 已 4/BATTLE；阶段不一致会让 `is_all_ready()` 等阶段判定在客机上停在旧值）。**通用教训**：任何「延迟执行 + await」的收尾协程，判活令牌必须只由「开启新局」递增；不能用收尾动作自己也会递增的代次（`_session_generation` 被 `close_connection` 递增），否则协程在第一次 await 后就被自己弄死。验证：主机退出 → 客机 `host session closed -> return to menu` → `returned to menu: res://scenes/main/menu_screen.tscn`；`tests/run_coop_recovery_checks.py` 13 项全 PASS。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-25

### [Coop] 宽限期 peer 仍在状态字典里但已不在 `get_peers()`：定向 `rpc_id` 必须先判存活
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_begin_peer_grace` 保留状态、`_cleanup_peer` 超时才清、新增 `_peer_online`）；玩家日志 `ETN_debug2026-10-25T16.20.08.log:100-121`（同一 peer 连续 11 条 `Attempt to call RPC with unknown peer ID`）。
- Notes / 说明: 45s 宽限期内 host 会把断线 peer 的镜像/角色/归属关系都留着，但它已从 `multiplayer.get_peers()` 移除，此时任何 `rpc_id(<存储 id>, ...)` 都会被引擎判为未知 peer：只会刷屏，且对已断端毫无意义。修法：新增 `_peer_online(id)`（`_net_connected()` + `get_peers().has(id)`，本机 id 恒真），覆盖三类定向发送——补发类（`_send_existing_enemies_to_peer`/`_send_existing_summons_to_peer`/`_send_existing_medkits_to_peer`/`_send_boss_visual_states_to_peer`/`_send_orbital_state_to_peer`/`_send_field_state_to_peer`/`_send_chip_state_to_peer`）、归属类（attacker/owner_peer 的 `_remote_enemy_proc`、`_remote_summoned_melee_kb`、`_remote_summoned_upgrade`、`_send_player_buff`/`_send_summoned_buff` 的 host 分支）、播报类（`_on_host_orbital_blast` 循环、`_send_orbital_player_slow`）。注意**客机侧不能用它判其他客机**（客机 `get_peers()` 只有房主 1），所以经 host 中转的分支保持原样。**通用教训**：`MultiplayerPeer` 连接态正常 ≠ 目标 peer 还活着；只要 id 来自字典/持久归属（而不是刚收到包的 sender 或本帧 `get_peers()` 迭代），发送前一律判存活。
- Source / 来源: code + test
- Date / 日期: 2026-10-25

### [Boss] 乱入撤退不能 await 由状态机驱动的 animation_finished
- Evidence / 证据: 旧 `scenes/enemies/boss/erosion_tower_group.gd:boss_intruder_escape()`（`stop_shoot()` → `play_backwards("enter_anim")` → `await tower_1.animation_player_3.animation_finished`）；`scenes/enemies/boss/erosion_tower.gd:242-252`（`idle_anim()`/`attack_anim()` 写同一个 `animation_player_3`）；`scenes/enemies/boss/erosion_tower.tscn:1048-1051`（`idle` `loop_mode=1`）；`script/EnemyStateMachine.gd:21-32`（状态机是独立子节点，`tower.set_physics_process(false)` 关不掉）；`ui/round_timer.gd:_finish_intruder_fever()`（await resolve 后才 `emit_round_end`）。
- Notes / 说明: **现象**（user）：TM 乱入刷侵蚀之塔，60s 计时归零 → FEVER 结束后塔组撤退，撤退中打爆一柱 → 计时器停在 0、无转场、普通刷怪继续跑、回合不结束。**根因**：撤退的 `stop_shoot()` 把 `can_shoot` 置 false，下一物理帧塔状态机从 `SHOOTING` 切 `IDLE` → `idle_anim()` 把同一个 `animation_player_3` 换成循环 `idle`（`attack_anim` 同样循环）；循环动画**不发** `animation_finished` → 退场协程永挂 → `resolve_boss_intruder_timeout()` / `_finish_intruder_fever()` 永不返回 → `round_end` 永不发。触发条件只是「撤退瞬间塔在出招窗口内」，与是否打爆柱子无因果。**修法**：先 `state_machine.set_physics_process(false)` 冻结驱动源并显式 `tower.stop_shoot.emit()`，再按入场动画长度做固定时长等待（有界）；`boss_intruder_wait_death()` 改 deadline 轮询；`_finish_intruder_fever()` 加 token + 8s watchdog 兜底。**通用教训**：退场/结算流程不要 await 由 AI/状态机驱动、可能被替换成循环动画的动画信号；先冻结驱动源，再用有界等待，并为终止信号（`round_end`）准备兜底。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-25

### [Boss] 乱入侵场/撤退必须用 HealthComponent.is_invincible 免疫：`set_deferred` 关形状挡不住
- Evidence / 证据: `scenes/enemies/boss/erosion_tower_group.gd`（`_set_towers_invincible`、`boss_enter_anim`、`boss_intruder_escape`）、`scenes/enemies/boss/goliath.gd:188-215,250-283,308-346`（`idle_state`/`active_state`/`boss_enter_anim`/`_clear_enter_invincible_*`/`boss_intruder_escape`）、`script/health_component.gd:9,78,244`（`is_invincible` 在 `_take_damage_internal` 最前端拦掉一切伤害；`resolve_damage` 同步返回 0）、伤害旁路 `scenes/debuff/fire_field.gd:46-48`（直接 `hit_received.emit`）与 `script/health_component.gd:58-75`（pending extra）、既有先例 `script/boss_enemy.gd:95`（离场无敌）。
- Notes / 说明: 入场阶段 HurtBox 已由 `active_state()` 打开（`script/entity_ENEMY.gd:150-169`），乱入路径不暂停（塔/Goliath 均如此），玩家在 3.0s/2.5s 入场内能直接打到 Boss；撤退只对碰撞形状 `set_deferred`，同帧命中、DOT/火场、pending extra、`one_hit_kill` 仍会结算。用 `HealthComponent.is_invincible` 统一免疫（同时阻断暴击/破盾/击退/策反/命中特效），入场结束按 `_dead_started/_intruder_escaping/_is_idle/hp<=0` 守卫恢复；`active_state`/`idle_state`/`update_tower` 复位防止池化残留；`network_remote_enemy` 镜像不设（客机 HP 与伤害预测由快照/host 驱动）。撤退中免疫还顺带消除了「撤退中被打死」与退场/自释放竞争。**通用教训**：演出期免伤不要只靠关碰撞形状或死亡流程早退，必须走伤害结算最前端的免疫闸门。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-25

### [Boss] 乱入撤退中击杀由 `_intruder_escaping` 门统一吞掉（含 Goliath），该门 load-bearing
- Evidence / 证据: `scenes/enemies/boss/erosion_tower_group.gd:291-297`（`boss_dead` 的 `if _intruder_escaping: return`）、`scenes/enemies/boss/goliath.gd:900-904`（`on_dead` 的 `is_idle == 1 or _intruder_escaping` 早退）、`scenes/enemies/boss/goliath.gd:1139-1140`（`_on_enemy_stats_is_dead` 只排 `on_dead`）、`scenes/enemies/boss/goliath.tscn`（`death_anim` 的 `_coin_drops` method 轨；`BossEnter`/`DeathAnim` 为 `process_mode=3` 专用播放器）、`scenes/enemies/boss/erosion_tower.tscn:641-644`（单塔 `dead` 3.5s、非循环）。
- Notes / 说明: 复核「撤退中死亡」：**不是**本次卡死主因。单塔 `dead` 非循环、会正常结束；Goliath 退场等的是专用 ALWAYS 播放器（AI 只写 `$BodyAnim`/`$LegAnim`），没有塔那种「循环 idle 覆盖等待目标」；两处 `_intruder_escaping` 早退阻止死亡路径在退场期间 `boss_death_anim`/`_coin_drops` 自释放（否则退场 await 的对象被提前释放 → 同款永久挂起），因此该门必须保留。撤退中击杀不结算奖励是既定行为（与「撤退不结算奖励」一致）。Goliath 仍需有界等待：其 `boss_intruder_escape`/`boss_intruder_wait_death` 原本无超时，节点在 await 期间被移除（game_over 清场/切场景/未来清理路径）同样会让 `resolve` 永久挂起。**通用教训**：撤退优先的早退门与有界等待必须成对存在——只靠早退挡死亡、或只靠有界等待兜底都不够。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-25

### [Coop] release 包闪退没有栈：用「事件级面包屑日志 + 内存心跳」取证
- Evidence / 证据: 新增 `mod_sdk/coop_mod/mods/etn_coop/net/coop_trail.gd`（`user://logs/coop_trail.log`，轮转保留 3 份、单文件 256KB、≤50 行/秒、写后 flush、退出 `seal()`）；埋点位于 `coop_net.gd`（`gate_scene`/`remote_scene`/`peer_on`/`peer_off`/`server_off`/`grace`/`cleanup`/`migrate`/`hello_ok`/`close`/`teardown`/`first_round`/`spawn_remote`/`scene_ready`/`reset_sync`），`_physics_process` 每 10s 一行 `mem` 心跳。开关 `coop_settings.debug.network_trail`（默认开）。
- Notes / 说明: **现象**：玩家/自己复现的客机闪退在 `ETN_debug.log` 里只表现为「输出戛然而止」，而导出 release 模板不含 crash handler，无法区分「原生崩溃 / 主线程卡死 / 被系统或玩家结束」。**做法**：只记**事件级**（不逐帧）关键节点并逐行 flush，崩溃时最后一行就是现场；`mem` 心跳区分「内存涨爆」与「原生崩溃」。实测一条完整链路可直接读出：`peer_off` → `server_off(flag=true)` → `cleanup` → `teardown begin` → `close(silent=true)` → `teardown transport_closed` → `transition_done` → `gate_scene(menu)` → `teardown menu=menu_screen`。**两个实现坑**：①重开日志必须 `FileAccess.READ_WRITE` + `seek_end`，用 `WRITE` 会在 `_notification` 的 EXIT_TREE/PREDELETE 二次打开时把整份现场截断（首版实测只剩 3 行）；②退出路径要 `seal()` 而不是 `close()`，否则后续任何 `mark` 会重开文件。**通用教训**：release 版取证不要指望引擎栈，自己写「事件级 + 逐行 flush + 可轮转」的面包屑，比事后让玩家复现便宜得多。
- Source / 来源: code + test
- Date / 日期: 2026-10-25

### [Coop] 劣化链路下的「假掉线」：心跳单次超时判定 + 超大包声明都会放大重连风暴
- Evidence / 证据: `coop_net.gd`（`HOST_TIMEOUT_MSEC` 8000→12000、新增 `HOST_MISS_LIMIT=3`/`HOST_MISS_CHECK_MSEC=1000`、`_network_heartbeat` 连续缺失计数、`_host_miss_count` 复位点）、`coop_enet_peer.gd`（`_get_max_packet_size()` `1 << 24` → `1 << 16`）。
- Notes / 说明: 玩家日志里 host 侧反复「连上→断开」、同一 token 换 peer id，触发条件是虚拟局域网的丢包/抖动。旧逻辑「8s 没收到房主包就拆链」会把房主主线程短暂卡顿（换关加载、boss 演出）误判成房主离开 → 客机拆链重连 → host 进 45s 宽限 → 重连迁移反复执行；`_get_max_packet_size` 声明 16MB 时超大 RPC 会直接交给 ENet 分片，丢一个分片就整包重传，可靠通道队头阻塞会把心跳一起拖住。现在：超时后按 1s 一拍累计、连续 3 次才判（约 15s 才认掉线，宽限 45s 内仍可重连），单包上限收口 64KB（视觉批量本来已按 `BULLET_BATCH_LIMIT` 分块）。**实测**：双端 test_room 空转 100s，内存 622.6MB 恒定不涨、无 `Lambda capture`/`unknown peer ID`/`SCRIPT ERROR`；`run_coop_recovery_checks.py` 13 项全 PASS。
- Source / 来源: code + test
- Date / 日期: 2026-10-25

### [Equip] 跟随图标是链表：挂点归属过滤不能只看玩家子树（`is_ancestor_of`）
- Evidence / 证据: 22 个角色场景各带 **1 个** `Follow`（`scenes/player/shiroko/shiroko.tscn:275` 等）、15 个 `scenes/update_item/*_icon.tscn` 各自内置 `Follow` 子节点（如 `black_ninpero_icon.tscn:52`）；`script/equip_item.gd`（`attach_follow_icon` / `_follow_owned_by` / `FOLLOW_OWNER_META`）；回归引入 `7cc6cc3`（2026-10-14 加 `is_ancestor_of` 守卫，当时仅 mint/tnt 走 helper）与 `35d28e9`（2026-10-24 把 kikyou/renge/nagusa/yukari_doll、black/red_ninpero、cherino_matryoshka 7 件改调 helper → 故障面 9/15 件），`docs/AUDIT_REFACTOR_20261024.md:22,40` 当时判断「与 mint/tnt 现行一致」；镜像侧 `mod_sdk/coop_mod/mods/etn_coop/net/coop_item_visuals.gd:89-112`（按「复刻本体的链表」实现镜像链）、`coop_net.gd:5625-5629`（镜像 Follow 移出全局组）；玩法连带 `scenes/update_item/kikyou_doll.gd:24-25`、`nagusa_doll.gd:36-37`、`renge_doll.gd:44-45`（`doll == null` 早退）。
- Notes / 说明: **现象**（user）：跟随式道具只有第一件能生成并跟随玩家，后面再拿看不到生成。**根因**：挂点链是「玩家.Follow ← icon1.Follow ← icon2.Follow ← …」，图标挂在 `PlayerRoot` 下、其内置 Follow **不是玩家后代** → `local_player.is_ancestor_of(follow)` 恒假 → 除玩家自带的那个挂点外全部被跳过；该挂点 `follow_use=true` 后，9 件走 helper 的道具全部返回 null（无图标、无报错），依赖 `doll` 的毒环/冰环/火场同时失效。6 件仍手写循环的道具（voodoo_doll/ancient_battery/millennium_flag/flammable_explosives/puzzle_cube/peroro_kagami_mochi）不受影响，所以现场常表现为「第一件出图、之后 helper 系不出图」。**修法**：`attach_follow_icon` 只占用「玩家自身子树」或「本玩家图标链（图标带 `follow_owner` meta 且指向该玩家）」上的挂点，新建图标打 meta 续链；无 `PlayerRoot`/无可用挂点时 `push_warning`；6 件手写循环一并收敛到 helper（它们自建的图标没有 meta，不收敛就无法被后续道具续链）。**通用教训**：给「遍历全局组 + 对每个成员做副作用」加归属过滤时，别只判「是不是玩家后代」——挂点常被挂在玩家之外的容器下（图标链是典型反例）；归属判定要覆盖**所有合法宿主**（玩家子树 + 已归属的挂点链），并给失败路径留 warning，避免「静默什么都不生成」。验证：`tests/follow_chain_checks.gd`（headless）全部 15 件跟随道具依次链式挂载（玩家→icon1→…→icon15）、镜像/未消毒镜像挂点零占用、换玩家后挂到新玩家挂点、`kikyou/nagusa/renge_doll` 的 `doll` 非空；同一探针在旧守卫下 1 件即 `failures=1`（可作负向对照）。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-26

### [Equip] 帽子/导轨/枪口挂点也要按「玩家子树」过滤；道具释放必须回收图标并复位 `*_use`
- Evidence / 证据: `script/equip_item.gd`（`attach_rail_icon` / `attach_hat_icon` / `attach_muzzle_icon` 的 `local_player.is_ancestor_of(marker)`；`_attached_icons` / `_exit_tree` / `_clear_attached_icons` / `_track_icon`）；4 件手写枪口道具收敛（`scenes/update_item/suppressor.gd`、`blunderbuss_muzzle.gd`、`muzzle_brake.gd`、`fuel_tank.gd`）；挂点定义 `script/hat.tscn:5`（组 `Hat`）、`script/picatinny_rail.tscn:5`（组 `Rail`）、`script/muzzle.tscn:5`（组 `Muzzle`）；玩家侧位置 `scenes/player/shiroko/shiroko.tscn:308`（Hat 在 `Graphics/AnimatedSprite2D` 下）、`:311`（Gun 在 `Graphics` 下）、`scenes/weapon/White_Fang_465/white_fang_465.tscn:107,111`（Rail/Muzzle 在武器 `Sprite2D` 下）；镜像只移出 Follow 组（`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:5625-5629`），Hat/Rail/Muzzle 仍留在全局组；`scenes/update_item/follow_icon.gd`（失效 `follow_mark` 守卫）。
- Notes / 说明: **问题**：`attach_hat_icon` / `attach_rail_icon`（以及 4 件自写循环的枪口道具）只从全局组取第一个空闲挂点，LAN 下镜像玩家的 Hat/Rail/Muzzle 也在组里 → 本地道具可能挂到镜像身上；手写循环还缺 `break`，多个空闲挂点会把同一图标重复 `add_child`（`already has a parent`）。**为什么这里不需要 follow 那套 meta**：帽子/导轨/枪口的图标本身就是挂点的**子节点**，图标内嵌的同类挂点天然还在玩家子树内，`local_player.is_ancestor_of(marker)` 同时满足「排除镜像」与「继续续链」。**回收**：`EquipItem` 记录 `{icon, marker, field}`，`_exit_tree` 时回收图标并复位挂点的 `hat_use` / `picatinny_rail_use` / `muzzle_use` / `follow_use`——测试房重置只清 `EquipLayer` 与 `PlayerRoot` 的非 Player 节点、**保留玩家**，不复位会让玩家自带挂点永远处于已占用状态，下一轮第一件同类道具直接挂不上（玩家场景自带的 `Follow` 同理）。**注意**：链式图标嵌套（icon2 在 icon1 内嵌挂点下）意味着释放上游道具会连带释放下游图标；当前所有道具都在同一时机一起释放（重置/切场景），可接受，但后续若出现"单独移除某件道具"就需重建链。**通用教训**：给挂点组加归属过滤后必须同时回答「谁占的谁释放」——`*_use` 是玩家节点上的持久状态，只回收图标不复位标记，下一次就静默挂不上；这类"释放即失效"的状态最好跟占用者绑定生命周期，而不是散落在各道具脚本里。验证：`tests/mount_chain_checks.gd`（headless）Hat/Rail/Muzzle 各自双件链式挂载、镜像挂点零占用、释放道具后图标回收 + 4 个挂点复位 + 新道具可重新占用；`tests/follow_chain_checks.gd` 仍 `failures=0`。
- Source / 来源: user + code + test
- Date / 日期: 2026-10-26
- UPDATE: 2026-10-26 已实现「释放期自愈」，上面"单项移除需重建链"的遗留已处理：`_clear_attached_icons` 倒序释放（嵌套挂点把下游图标 `reparent` 到上游宿主）+ follow 链按快照重建（`_collect_follow_chain` / `_rebuild_follow_chain`）；宿主运行时现取（`icon.get_parent()` / `follow_mark`），`marker` / `owner` 只在图标被外部提前释放（如 `reset_clear_unit` 先清 `PlayerRoot`）时兜底，且对象参数不能写 `Node` 类型（已释放实例会先于 `is_instance_valid` 抛错）。探针 `tests/mount_chain_checks.gd` 增加阶段 2/3/4（中间件移除、全量释放、先清图标再清道具），关闭自愈后该探针报 16 条 FAIL/SCRIPT ERROR 可作负向对照。来源：code + test。

### [Combat] `Timer.start(t)` 会把 `t` 写回 `wait_time`：「缩短/覆盖时长」必须缓存原始值
- Evidence / 证据: `script/player_health_component.gd`（`invincible_frame_mult/add/override`、`_cache_invincible_frame_time()`、`invincible_frame_duration()`、`_start_invincible_frame()`）；`script/player.gd:430` `_on_invincible_frame()` 与 `:445-456` `_on_invincible_frame_end()`；22 个玩家场景 `InvincibleFrame` 全部 `wait_time=0.5`（如 `scenes/player/shiroko/shiroko.tscn:353-355`）。
- Notes / 说明: Godot 4 的 `Timer.start(time_sec)` 在 `time_sec > 0` 时先 `set_wait_time(time_sec)` 再启动，因此把 `timer.wait_time` 当作「原始时长」时，第二次调用已被上一次的缩短值污染（0.5 → 0.1 → 0.02…）。任何「按倍率/绝对覆盖缩短计时器」的接口都必须在计时器被改写**之前**缓存原始值（这里在 `PlayerHealthComponent._ready()` 缓存到 `_base_invincible_frame_time`），并让所有 `start()` 收敛到唯一入口 `_start_invincible_frame()`。`_ready()` 里不能依赖玩家父节点的 `@onready var invincible_frame`（子节点 `_ready` 先于父节点赋值），需回退 `get_parent().get_node_or_null("InvincibleFrame")`。0 秒不可由 Timer 表达（`wait_time` setter 最小 0.001），用 `MIN_IFRAME_SECONDS=0.001` 表示「无无敌帧」；不要 `timer.stop()` 后手动清 `contact_invincible`，那会漏掉 `_on_invincible_frame_end()` 里的闪白归零。验证：`tests/test_invincible_frame_override.gd`（10 项全绿）+ headless 探针（`PlayerData.invincible_frame_mult=0.2 → 组件 0.2 → wait_time 0.1`；`chip_easy_fall_buff` 经 `BuffRouter → PlayerBuffManager → PlayerData → 组件` 生效，移除后恢复 0.5）。
- Source / 来源: code + test
- Date / 日期: 2026-11-01

### [Visual] 受击闪烁不要用固定时长动画：无敌帧时长可变时必须代码驱动 visible
- Evidence / 证据: `script/player.gd`（`INVINCIBLE_FLASH_INTERVAL=0.075`、`_start_invincible_flash()` / `_stop_invincible_flash()` / `_update_invincible_flash()`、`_process`）；22 个玩家场景的 `Invincible frame` 动画全部 `length=0.5`，分两套轨道——11 个角色只闪 `Graphics:visible`（如 `scenes/player/shiroko/shiroko.tscn`），11 个长发角色闪 `GraphicsHalo` + `CanvasGroup` + `GraphicsGun`（如 `scenes/player/aris/aris.tscn`，`CanvasGroup` 是根子节点、`Graphics` 在其下）。
- Notes / 说明: 旧实现在 `_on_invincible_frame()` 里 `invincible_frame_anim.play("Invincible frame")`，动画把 visible 关键帧烘焙成固定 0.5s；一旦无敌帧时长变化（`chip_easy_fall` 缩到 0.1s、未来道具延长），闪烁会拖尾/不同步；而把 0.1s 直接塞进 0.5s 动画（speed_scale=5）会得到约 35Hz 的切换，视觉上会糊成灰。正确做法是代码按**固定 0.075s 周期**切 visible、总时长读 `InvincibleFrame`，于是 0.1s 只闪一下、0.5s 与旧动画节奏一致、任意时长都能适配。闪烁节点**不要硬编码**：长发角色由 `CanvasGroup` 包身体（`Graphics` 在其下）+ 根级 `GraphicsHalo`/`GraphicsGun`，其余角色只有 `Graphics`；按 `has_node("CanvasGroup")` 选集合。`_process` 里补 `invincible_frame.time_left <= 0` 兜底恢复（跳跃/飞行/倒地不走 `tick_physics` 的收尾），否则 visible 可能停在 false 让角色短暂隐形。场景动画保留但不再播放（`_start_invincible_flash()` 里 `stop()`），22 个 tscn 零改动。验证：headless 探针在 shiroko（`Graphics`）与 aris（`CanvasGroup`/`GraphicsHalo`/`GraphicsGun`）上得到 `true → false → true`、多节点同步、停止后恢复可见、动画未播放。
- Source / 来源: code + test
- Date / 日期: 2026-11-01

### [Coop] 镜像受击表现必须带上拥有端的可变时长；RPC 契约变更要同时升协议与 mod 版本
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_local_iframe_duration()`、`_remote_player_hurt(peer_id, iframe_duration)`、`_server_player_hurt(iframe_duration)`、`PROTOCOL_VERSION = 7`、`MOD_VERSION = "0.1.16"`）、`mod_sdk/coop_mod/mods/etn_coop/mod.json:4`（0.1.16）、`script/player_health_component.gd:invincible_frame_duration()`；镜像为完整 `player.tscn` 实例（`coop_net.gd:spawn_remote_player`），且 `net/coop_player_proxy.gd:356-388` 只停输入/gun/state_machine/Area2D，**玩家根 `_process` 未停**。
- Notes / 说明: 玩家伤害是**每端本地权威**（`net/coop_visual_sync.gd:_open_player_damage_hole` 给敌方视觉弹开 `enemy_bullet`(128) 层伤害洞，本地 HurtBox 本地结算），所以词条数值两端天然生效；但镜像受击表现靠 `_remote_player_hurt` 回放，旧实现固定 `timer.start()`（镜像场景默认 0.5s），一旦拥有端时长可变（`chip_easy_fall` 缩到 0.1s、未来道具/技能延长）就表现不一致。修法：拥有端算 `health_component.invincible_frame_duration()` 随受击广播，接收端 `timer.start(clampf(duration, 0.001, 5.0))`，非有限值/`<=0` 直接忽略；本体代码驱动的 visible 闪烁会自动跟随该时长。`PROTOCOL_VERSION` 与 `MOD_VERSION`（含 `mod.json`）必须在同一提交/同一次发布一起升——任一不同都会在握手阶段被拒绝（`protocol` / `mod_version`）。**通用教训**：镜像表现里凡是「拥有端可变、且镜像不参与判定」的时长/状态，都不要用镜像场景的默认值，必须随事件上报；同时注意镜像的可见性/闪烁若要跑代码驱动，依赖玩家根 `_process` 未被 proxy 禁用，若未来 proxy 停根节点 process，需要改用 proxy 驱动或保留该节点。验证：`tests/coop_hurt_duration_checks.gd`（本地、不入库，静态契约检查 `failures=0`）；`coop_net.gd` 源码 `GDScript.reload()` 编译通过。
- Source / 来源: code + test
- Date / 日期: 2026-11-01

### [UI] 触屏二次确认的归属区默认只看 tooltip 目标矩形：目标小于卡片时，卡片其它区域永远无法确认
- Evidence / 证据: `ui/hover_tooltip.gd:100-102`（按下时 `_active.owns_press(event.position)` 不成立即 `dismiss()`）、`ui/hover_tooltip_binding.gd:15,81-86,128-140`（新增 `press_bounds` / `owns_press()`，默认回退 `visible_rect()`）、`ui/ability_shop_card_base.gd:10,24-38`（按卡面 `Node2D/ColorRect3` 接整卡归属区）；`ui/ability_shop_item_card.tscn:161-165`（成本条 `3..35 × 2..12`）与 `:245-250`（图标区 `EquipTextP`，`ui/ability_shop_item_card.gd:19-28` 只把它当第二个提示绑定）；对照 `ui/ability_shop_ps_card.tscn:156-161`（PS 卡 `upgrade` 本来就盖住整卡 `3..67 × 2..46`）；前提 `project.godot:215` `pointing/emulate_mouse_from_touch=false`。
- Notes / 说明: **现象**（user）：移动端能力商店（局内升级页）的装备卡必须点顶部那条「↑ 数字」成本条才能升级，点图标只会反复弹提示，判定区域太小。**根因**：触屏确认态存在卡片 `on_touch` 上，但「这一下算不算点在本卡」由宿主按**绑定目标控件的矩形**判定；装备卡只把成本条 `Node2D/upgrade` 绑成目标，图标区是另一个 `EquipTextP` 绑定 → 第二下点图标被判为「点别处」→ `dismiss()` → `on_preview_closed` 把 `on_touch` 清回 false → 同一次释放走 `touch_button()` 又变成「首点预览」，于是永远到不了 `_attempt_purchase()`。PS 卡的 `upgrade` 面板本来就把整卡当矩形，所以同一套代码下枪卡正常、5 张装备卡不正常（用户看到的差异就是这么来的，不是两个功能）。**修法**：把「悬停/提示目标」与「确认命中区」解耦——`HoverTooltipBinding.press_bounds`（返回画布坐标 `Rect2`）+ `owns_press()`，默认不设置时行为不变；`AbilityShopCardBase` 用卡面 `Node2D/ColorRect3`（含升级页对 `Node2D/AbilityShop:scale` 的入场缩放，用 `get_global_transform_with_canvas()` 现算）作为整卡归属区，装备卡与 PS 卡统一。保留「首点预览 / 二次点按确认 / 拖动取消」语义，不改成单击即买。**通用教训**：提示目标可以很小（局部元素），确认命中区必须是用户以为的可点区域；两者默认相等会静默吃掉同卡其它区域的二次点按，且只在「目标 != 卡片」的卡片上暴露。验证：`tests/test_ui_ux_regressions.gd` 的 `_check_ability_shop_touch`（本地用例，按约定不提交）用 `push_input` 走真实 GUI 路由，改前 2 条 FAIL（二次点图标不升级 / 不能连升）而成本条 PASS，改后 8 项全 PASS；全套 UI 回归 142 项 0 失败。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-01

### [Coop] 重连「解冻」不能无条件对写 `player_stop`；本机倒地态不走镜像同步通道
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`：`_freeze_local_player_for_reconnect`（旧实现 `p.player_stop = on` / `p.can_control = not on`）、`_finish_reconnect`（调 `_freeze(false)`）、`_remote_peer_rejoined`（只写 `down_peer_ids` + 调 `_remote_player_down_changed`）、`_remote_player_down_changed`（首行 `peer_id == 本机 id → return`）、`_revive_all_downed_for_upgrade` / `_complete_revive`（`rpc("_remote_revived")`）；本体 `script/player.gd:191-205`（`set_downed_state(true)` 只写 `player_stop=true`）、`:267-288`（`_unhandled_input` 受 `player_stop` 门控）、`:370-373`（`move()` 受 `player_stop` 门控）。
- Notes / 说明: **现象**（user）：联机玩家倒地（全屏黑白 + 0 血）后断线自动重连，回来仍是 0 血黑白，但能移动/射击。**根因**：重连收尾把「掉线期间冻结」与「倒地硬停」当成同一个布尔对写，解冻时无条件 `player_stop=false`；同时 host 权威的倒地标记只同步「他人镜像」，本机永远不校正，掉线期间 host 的升级统一复活/队友救起（`_remote_revived`）又必然错过 → 两端分叉。**修法**：① 冻结/解冻改快照：`_reconnect_prev_stop/_prev_control/_prev_downed`，解冻时 `player_stop = downed_now or (prev_stop and not prev_downed)`（冻结前已倒地则只看当前倒地态，升级复活后能正常放开），并 `_ensure_motion_down_visible()` 补回黑白遮罩；② `_reconcile_local_downed_state(host_down)` 在 `_remote_peer_rejoined` 里对 `new_id == 本机 id` 生效：host down → `set_downed_state(true)` + 硬停 + 遮罩；host up 且本机仍倒地/0 血 → `_apply_revive_local(本机, 1.0)` 满血复活（分不清升级复活 1.0 与救援 0.5，取满血）；③ 重连成功刷新本地 `peer_id` meta / 本地 proxy，避免 `_gate_player_buff_apply/remove` 把本机光环 buff 转发到旧 id。**已知取舍**：断线前 down 上报（reliable）恰好未送达的极小窗口，以 host 为权威 → 重连后满血复活。**通用教训**：① 「网络断开时的临时冻结」和「玩法状态的硬停」不能共用同一个写入路径，解冻必须按状态还原而不是按事件对写；② 凡是「本机 vs 他人镜像」分流的同步函数，本机一侧一定要有独立的校正入口（`peer == self` 早退的函数不能顺手当成状态恢复）；③ 断线期间由服务端推进的状态变更（复活/结算/升级）在重连时必须按权威补同步，不能指望广播重放。验证：`tests/coop_reconnect_downed_checks.gd`（本地、不入库，静态契约 `failures=0`）；`tests/run_coop_recovery_checks.py --cases downed_rejoin rejoin3 upgrade` 全 PASS（`downed_rejoin`：重连后仍硬停/遮罩在 → host 说存活时满血复活 → host 说倒地时幂等补回）。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-02

### [Mod/IZZY] 动画单键隐藏 `Graphics/Gun` + 唯一程序恢复点 ⇒ 镜像回放/被打断后枪永久隐身
- Evidence / 证据: `mods/doom_slayer_izzy/scenes/doom_slayer_izzy_izzy.tscn`（`crucible_execute_1`=`Animation_6ooj6` 的 `tracks/5`、`crucible_execute_2`=`Animation_rlvvn` 的 `tracks/6`，`Graphics/Gun:visible` 原只有 t=0 的 `false` 单键）；`mods/doom_slayer_izzy/scenes/doom_slayer_izzy_melee.gd`（旧唯一恢复点 `_end_execution()` 的 `player.gun.visible = true`，仅在 `_execute()` 协程末尾）；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:4699-4701`（`_remote_player_melee` 在远端镜像 `kick_anim.play("crucible_execute_*")`，镜像没有处决逻辑）；`coop_player_proxy.gd:321-332/356-360`（proxy 只关相机/UI/输入，Kick 的 `_process` 仍在跑，镜像显示裁决剑同依赖此 `_process`）。
- Notes / 说明: **现象**（user）：IZZY 偶发「枪械消失」。**根因**：处决动画只在 t=0 把 `Graphics/Gun:visible` 置 `false`，恢复只靠 `_end_execution()` 一次调用 → ① 联机镜像回放处决动画时镜像端永不执行恢复（其他玩家眼里 IZZY 的枪永久隐身）；② 动画被别的动画顶掉/处决协程中断时无恢复点。**实测澄清**：单键 value 轨道在动画开始时写一次、播放中不再逐帧重写（暂停期间手动置 true 不会被写回），所以「本地暂停打断」并非成因，别据此过度设计。**修法**：① 场景两条轨道补 `t=length(0.7)` 的 `true` 结束键；② `melee.gd` 新增 `GUN_HIDE_ANIMS` + `_hook_gun_guard()`（`_ready` 里连 `kick_anim.animation_finished`）与 `_sync_gun_visible()`（`_process` 每帧：只有「正在播隐藏枪的动画」才允许不可见，否则强制恢复，不依赖 `_executing`，故镜像端同样生效）。**通用教训**：① 动画里「只写一次的状态」（隐藏/显隐/scale）必须配结束键，且程序侧恢复点不能是唯一保险；② 联机镜像只回放动画，不会跑拥有端的收尾逻辑——凡是靠「动画 + 拥有端代码」共同维护的状态，镜像端都要有独立兜底（这里放在 `Kick._process` 自愈，避免跨 mod 依赖）。验证：`tests/izzy_gun_visibility_checks.gd`（本地、不入库；修复前 3 条 FAIL，修复后 `failures=0`）。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-02

### [Enemy] `EnemyCard.chip_tags` 的 `"melee"/"ranged"` 是词条匹配标签，不是 AI 角色
- Evidence / 证据: `resources/enemy/enemy.gd:12`（`chip_tags`）、`scenes/manager/chip_manager.gd:472-483`（只用于 `_matches_target`）；`resources/enemy/menacing_automaton.tres`、`tester_automaton.tres`、`tester_automaton_shield.tres` 都标了 `"melee"`，但它们挂 `automaton.gd`/`tester_automaton_shield.gd`，`shoot_range` 300~450 属远程站桩射击。
- Notes / 说明: 给「所有敌人」加走位/角色逻辑时**不要**复用 `chip_tags` 判定近战/远程——那会让 `menacing_automaton` 变成贴脸怪。AI 角色改由各脚本 `_init()` 给出默认值（`Enemy.ai_role`），既覆盖全部同类变体与 Mod 复用，又不需要改 16 个 `.tscn`。
- Source / 来源: code
- Date / 日期: 2026-11-04

### [Enemy/Boss] Boss 的 `time_count()` 会调 `super`，基类 tick 改动必须按角色短路
- Evidence / 证据: `scenes/enemies/boss/goliath.gd:361-364`（`super.time_count()` 后按 `move_mode` 重写 `direction`）、`scenes/enemies/boss/erosion_tower.gd:84-85`（同样 `super.time_count()`）；`goliath.gd:1`、`erosion_tower.gd:1` 都是 `extends Enemy`；`goliath.gd:188-202` 的 `idle_state/active_state` 也调 `super`。
- Notes / 说明: 在 `Enemy.time_count()` 里加钩子会**实际作用到 Boss**（不是只影响杂兵）。钩子必须 `ai_role == MELEE` 才改写 `direction`，Boss 恒为 `NONE`；并且只放 Boss 时 `EnemyAI` 不应建场。`EnemyPart` 是 `Node2D`、塔组根也是 `Node2D`，天然不进这套逻辑。
- Source / 来源: code
- Date / 日期: 2026-11-04

### [Enemy/AI] 导航场用等权 BFS 即可；边界必须等 `MapBounds` 的 `walls`
- Evidence / 证据: `script/map_chunks.gd:162-213`（可行走格由 `MapBounds.get_walkable_polygon()` 内缩 `TERRAIN_INSET_PX=8` 后逐点判定）、`main.tscn:76`（`tile_shape=1` 等距、`tile_size=64×32`）；实测 `MapChunks.get_all_cells().size() == 729`（`tests/ai_probe.gd`，本地不入库）。
- Notes / 说明: 等距瓦片四邻接的世界间距恒等 ≈35.8px，所以 729 格用 `Array` FIFO 的等权 BFS 就够（2600 次松弛 ≈0.3–1ms），不需要优先队列/`AStarGrid2D`。但**首帧** `MapBounds` 的 4 条墙射线可能还没就绪，此时 `get_boundary_source() != "walls"`、hull 会退化成 `SpawnMap` 兜底（比真实可走区小一圈），必须「不建场、下次重试」，否则场会永久建小。
- Source / 来源: code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 障碍格不能用逐格物理查询：会把 Boss/敌人/玩家自己标成障碍
- Evidence / 证据: `script/props/prop_wall_body.gd:9-14`（障碍碰撞体 `collision_layer = 256`(层9 wall)，`block_bullets` 时 `|=2`，`collision_mask = 0`）；`scenes/enemies/sweeper.tscn:162-163`（敌人根 `layer=8`）、玩家 `layer=1`、`enemy_part=11/1024`。
- Notes / 说明: 若用 `intersect_point` 逐格扫，Boss（`CharacterBody2D`，体积极大）与正在格子上的敌人/玩家都会被算成障碍，场会瞬间被自己堵死。正确做法：建拓扑时遍历 `StaticBody2D` 且 `collision_layer & 256`，取子 `CollisionShape2D` 的世界 AABB 外扩 28px 标记覆盖格——只认静态墙体，零逐格物理查询。
- Source / 来源: code
- Date / 日期: 2026-11-04

### [Enemy/AI] 冲撞：sweeper 根系只与墙碰撞，收尾必须唯一，撞墙即结束
- Evidence / 证据: `scenes/enemies/sweeper.tscn:162-163`（`layer=8 / mask=256`）、`mystic_sweeper.tscn:178-179` 与 `enhanced/modded`（`mask=258` = 墙 256 + 子弹墙 2，**不含玩家层 1 / 敌人层 4**）；`scenes/enemies/sweeper.gd`（`get_next_state` 里 `move_mode != 0` 时一直走 `match`，而 `move_mode` 只在收尾那一处清零）。
- Notes / 说明: ① 因为只与墙碰撞，冲撞中 `get_slide_collision_count() > 0` 只可能是墙/障碍，「撞到墙就结束」不需要按碰撞体类型筛选；② 收尾必须走**同一个** `_end_charge(cd)`（清 `can_charge/move_mode/charge_time/charge_dir` 并停 `AnimationPlayer`），漏清 `move_mode` 会永久卡在 `CHARGING`；③ 结束时要同时清 `charge_time/charge_dir`，否则状态机重评前的 3 tick 仍以 3× 速度冲；④ 发起前只判定一次通路（`ai_charge_path_clear`），失败给 1 秒重试，不要逐帧重判。
- Source / 来源: code + user
- Date / 日期: 2026-11-04

### [Enemy/AI] 难度参数注入放 `spawn_anim` 且 `idle_state()` 必须清空；阻挡注册要按来源计数
- Evidence / 证据: `script/spawn_anim.gd:87-155`（`spawn_enemy_body` 是普通波次/测试房/作弊菜单共用入口）、`script/entity_ENEMY.gd:idle_state()`、`script/enemy_nav_field.gd`（`add_block/remove_block` 用 `_block_sources` + `_block_counts` 引用计数）。
- Notes / 说明: 敌人是池化的，难度 profile 必须在**每次生成**时注入、在 `idle_state()` 清空，否则上一局的难度参数会被带进下一局；反之若注入点放在 `_ready` 或别处，池化复用就不会刷新。阻挡同理：多词条重叠时若只 `erase` 不解引用计数，先结束的那个词条会把共同格子解锁，导致仍在生效的障碍被 AI 无视。客机镜像会 `active_state()` 但不走 `spawn_anim`，天然拿不到 profile，再加 `has_meta("network_remote_enemy")` 早退即可零开销。
- Source / 来源: code
- Date / 日期: 2026-11-04

### [Enemy/AI] 包围手感：侧向权重不能是常数，方位不能各敌随机；距离带的方向别写反
- Evidence / 证据: `script/entity_ENEMY.gd`（`_melee_band_weight()` 的 `near_gate` / `far_gate`、`_melee_steer()` 的 `flow.rotated(turn * weight)`）、`script/enemy_ai.gd`（`_assign_melee_slots()`、`_nearest_slot_error()`、`_mean_bearing()`、`predict_anchor()`）、`tests/ai_probe.gd` 的 `_run_formation_checks()`。
- Notes / 说明: 一期实现里 `weight = encircle * smoothstep(engage*0.6, engage*1.6, dist)` 是**越远越大且恒定**，于是远处敌人也全程斜着走 → 手感「呆、来得慢」。正确形状是「远 → 只做最小散开（`far_spread`），环带 → 全力占位，贴脸 → 归零」，即 `max(encircle * near_gate * far_gate, far_spread * (1-far_gate))`。**两个 gate 的方向极易写反**：写成 `1 - smoothstep(engage, ring*0.9, dist)` 会让环带权重恒为 0（探针的 `w_ring`/`w_close` 断言就是守这个）。方位同理：用实例 id 奇偶各敌随机会东倒西歪，必须在 5Hz 求解里集中算「均匀槽位」再下发，且分配要用「去最近空槽角距升序」的贪心（同角距按距离定序）——先到先挑会让总位移变大、来回换位。另：`Dictionary.get(key)` 在缺失时返回 **null**，用 `var g: Dictionary = dict.get(k)` 会直接运行时报 `assign Nil to Dictionary`，必须写成 `var g = dict.get(k)` 再判空。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 「留空 = 关闭」是危险默认：功能型系统留空必须回退到安全基线
- Evidence / 证据: `resources/level/normal.tres`（原无 `enemy_ai`）、`script/spawn_anim.gd`（`_resolve_ai_profile()` 原来 `level.enemy_ai` 为空即返回 null）、`script/entity_ENEMY.gd`（`ai_steer()` 原来 `if not has_field and ai_profile == null: return base_dir`）、`apply_soft_collision()`（接触推挤间距 ≈27px）。
- Notes / 说明: **现象**（user）：实机截图中敌人沿竖直方向排成一列、彼此间距约 27px。**根因不是 AI 逻辑错，而是 AI 根本没开**：`normal.tres` 没有 `enemy_ai` → `spawn_anim` 注入 `null` → `ai_steer()` 早退 → 全员同向直冲 + 碰撞挤成队列。**识别特征**：队列间距等于碰撞半径而不是排斥半径（88px），说明连 `_ai_separation` 都没跑，可直接判定为「AI 未启用」。**修法**：① `normal.tres` 挂上 `resources/enemy_ai/normal.tres`；② `spawn_anim` 增加 `DEFAULT_AI_PROFILE` 兜底，`level.enemy_ai == null` 或 `current_level == null` 时回退基线，只有 Boss / 测试房 / 路线型才返回 null；③ 去掉 `ai_steer()` 里「无 profile 无场就原样返回」的早退，改为始终施加一次基础扇开（`FAN_BASE`），任何漏网场景都不会出现完美直线；④ `Game.dev_mode` 下每回合打印一次 `[ETNAI] level=… profile=…`。**通用教训**：可选配置的默认语义要按「功能是否应该存在」来选——难度档位一类的东西留空应回退基线（`null` 只保留给「明确不该有」的实体），否则新难度/Mod 关卡/调试入口都会静默退化成没有功能，而玩家只会描述成「敌人很傻」，难以从表现反推是配置没接上。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 只旋转场方向不会让人「停在包围半径上」；近零向量不能归一化
- Evidence / 证据: `script/entity_ENEMY.gd`（`_steer_intent()` 的 `dir = flow*radial + flow.orthogonal()*…*weight`、`if dir.length_squared() < 0.0004: return Vector2.ZERO`）、`tests/ai_probe.gd` 的径向驻留三连断言（`R*1.4` 向内 / `R*0.6` 向外 / 正好 `R` 不继续贴）。
- Notes / 说明: 一期用 `dir = flow.rotated(turn * weight)` 实现「包围」，但**径向分量恒朝玩家**——环只是走位曲线，敌人最终仍会贴成一团，看起来就是「围了但没停」。要真正驻留必须显式给径向符号：`radial = clampf((dist-R)/(R*0.35), -1, 1)`，门外向内、门内向外、正好在半径上为 0。**第二个坑**：`radial≈0` 且方位已对齐时合成结果是近零向量，此时 `normalized()` 会把浮点噪声放大成任意方向（实测被「前方阻挡」回退成了反向，表现为站在包围圈上却往外跑）。修法是长度阈值以下**直接返回零向量**（交给 `move()` 减速停下），且不要回退成 `flow`（那会继续贴上去）。
- Source / 来源: code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 密度场分散的两个必踩坑：自身 splat 污染邻格、后压让队伍越走越慢
- Evidence / 证据: `script/enemy_ai.gd`（`_build_density()` 的 1/0.45/0.2 核、`_self_kernel()`、`_apply_density_push()` 的 `DENSITY_BACKPRESSURE = 0.35`）、`tests/ai_probe.gd` 的「挤在一起有推力 / 单独一只无推力」断言。
- Notes / 说明: ① 把每只敌人 splat 到自身格 + 邻格后，若采样邻格时**不扣掉自己的份额**，单独一只也会被自己推开（实测「单独一只不应有密度推力」直接 FAIL）；必须按邻居方向减 `0.45`（四邻）/`0.2`（对角）。② 直接用密度梯度做排斥会变成**后压**：人群在前方时把后排往后推，队伍整体减速但依然挤。做法是把合力按「朝目标方向」拆开——横向全保留、朝目标分量保留、背离目标只留 35%。③ 一字排开时密度梯度几乎全是径向（被抑制后不足以分道），仍需「正前方排队」的对称破缺（左右按实例奇偶各半），否则又是一条线。
- Source / 来源: code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 远程若共用一个 standoff 半径，视觉上就是「一圈摆拍」
- Evidence / 证据: `script/enemy_ai.gd`（`_assign_ranged_slots()` 的方位槽 + `_jitter_of()` 半径抖动 + `_has_line_of_sight()` → `INTENT_REPOS`）、`script/entity_ENEMY.gd`（`AIIntent` 的 `HOLD/KITE/REPOS/CHASE` 径向规则）。
- Notes / 说明: 原实现所有远程用同一个 `standoff = lerp(back, shoot, ratio)`，于是它们永远停在一个完美同心圆上、还常常挤在同一侧，看起来极不自然。远程需要和近战一样有**方位槽**（`clamp(n,1,8)` 均分）与**半径抖动**（按实例 id 稳定，0.85~1.15），并夹在 `[back+12, shoot*0.95]` 内避免站到贴脸位。另外「走 A」只在有视线时成立：被障碍挡住就该 `REPOS` 换位（目标角偏移 ±50°，符号取稳定的 `_ai_strafe_sign`），否则会对着墙原地横移。
- Source / 来源: code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 包围环不能直接当极坐标目标点：玩家靠边时会大面积出界，敌人就去顶墙
- Evidence / 证据: `script/enemy_ai.gd`（`_fit_slot()` 的收缩循环、`SLOT_WALL_MARGIN=24`、`_invalidate_slot()`）、`script/map_bounds.gd:169-200`（`nearest_inside` + `_poly_for_radius` 的 4px 分桶腐蚀缓存）、`tests/ai_probe.gd` 的 `_run_wall_checks()`（场地中心 / 贴边两种场景的槽点合法性断言）。
- Notes / 说明: **现象**（user）：敌人数量多起来后大量敌人贴着墙挤。**根因**：环带半径随人数增长（`max(ring, n*28/TAU)`，40 只≈178px），而槽位只下发 `(角度, 半径)`、从未校验该点是否在场内；玩家靠边时环的大半圈落在场地外，被分到那些角度的敌人径向与切向都指向墙，`move_and_slide` 只能让它们沿墙蹭。**修法**：新增 `_fit_slot()` 逐级收缩半径（0.8/步、上限 12 步），接受条件必须同时满足「离内壁 ≥24px」「不在阻挡格」「相对目标可达」，收不下去就 `_ai_slot_valid=false` 退回 `flow`。两个细节：① `MapBounds.is_inside_walkable()` 判的是**墙内壁**，不含本体半径，必须用 `nearest_inside(point, 24) == point` 来留余量，否则收缩出来的"合法点"身体仍插墙；② 半径也必须 `lerp` 平滑，只平滑角度会让收缩档位（142→91）跳变。**已知取舍**：在 90° 角落，物理上只能站进约 1/4 平面，会有一半槽位判不可用（探针实测 `radii={104}`、`invalid=4`），这些敌人退回 `flow` 直接贴身——比顶墙好，若要更平整需做「自由弧重排」。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 对称多方向探针在「完全被包围」时会相互抵消：出界的实体永远出不来
- Evidence / 证据: `script/enemy_ai.gd`（`_apply_wall_push()` 的 `if EnemyNavField.is_solid(position)` 分支，直接取 `MapBounds.nearest_inside(position, 24) - position`）、`tests/ai_probe.gd` 的「出界敌人应被推回场内」断言。
- Notes / 说明: 离墙力用 8 方向探针累加反向力，在正常贴墙时有效；但当实体被击退出界、或卡在障碍格中心时，**8 个方向的探针全是 solid**，正负两两抵消 → 合力≈0 → 离墙力为 0，实体永久卡死。必须先判自身格：`is_solid(position)` 为真则直接朝 `nearest_inside` 走（权重放大到 2.0）。**通用教训**：任何"多方向采样求合力"的势场都要有「采样点自身非法」的兜底分支，否则最需要逃生的那种情况恰好得到零向量。
- Source / 来源: code + test
- Date / 日期: 2026-11-04

### [UI] CanvasLayer 的 visible 会连带隐藏子节点：叠加层不能挂在「会被关掉的菜单」下
- Evidence / 证据: `ui/cheat_menu.gd`（`close_menu()` 里 `self.visible = false`；`_get_ai_overlay()` 把叠加层挂到 `get_parent()` 而不是自己）、`ui/ai_debug_overlay.gd`（`layer=90`、`process_mode=PROCESS_MODE_ALWAYS`）、`tests/ai_probe.gd` 的 `_run_overlay_checks()`。
- Notes / 说明: 想把调试叠加层做进开发者控制台时，直觉是把它当成菜单的子节点；但 `cheat_menu` 关闭时执行 `self.visible = false`，而 CanvasLayer 的可见性会**递归隐藏全部子节点**——结果是「一关菜单叠加层就没了」，恰好破坏了「关掉菜单才能正常看战斗」的用法。正确做法：叠加层挂到 `get_parent()`（战斗场景根），由菜单**懒创建**并只保存引用，关闭只 `set_enabled(false)`。另外两点：① 叠加层必须 `process_mode = PROCESS_MODE_ALWAYS`，否则菜单打开时 `get_tree().paused = true` 会让它停止刷新；② `layer` 要低于 F3 性能面板（100），否则图例会盖住性能数字。**绘制侧可测**：`CanvasItem.draw` 信号 + 运行时创建的 `Control` 可以让脚本自己持有绘制目标，但 `_draw` 不能在绘制流程外调用，所以取数（`build_snapshot()`）与绘制（`_on_draw()`）必须分离，测试只断言前者，再用一帧 `process_frame` 让引擎真正跑一次绘制（`draw_passes` 计数器可验证确实执行过）。
- Source / 来源: code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] "散开"类势场必须单向：允许反向分量 + 满强度归一化 = 散得开但不接近
- Evidence / 证据: `script/enemy_ai.gd`（`DENSITY_BACKPRESSURE=0.0`、`DENSITY_MAG_REF=2.5`、`_apply_density_push()` 里 `push = lateral + toward*max(radial,0)*0`）、`script/entity_ENEMY.gd`（`_steer_intent()` 里近战 `CHASE` 径向恒 `+1`、`CUTOFF` 的径向 `clamp(..., 0, 1)`）、`tests/ai_probe.gd` 的 `_run_press_intercept_checks()`。
- Notes / 说明: **现象**（user）：密度场让敌人向外散开、不接近玩家。**根因是两件事叠加**：① 后压系数 0.35 保留了「背离玩家」的径向分量，人群越挤、后排越被往外推；② 推力被 `normalized()` 成单位长度，哪怕只有一只同伴在 60px 外，也产生满强度（`separation_strength` 0.28~0.45）的横向分量，把前进方向拧偏 16~24°。**修法**：背离目标的分量直接丢弃（系数 0），幅度按拥挤度软饱和（`|push|/2.5`）。**更一般的教训**：任何「把同类推开」的势场，如果既不禁止反向分量、又不做幅度衰减，最终都会表现为「散得开但不推进」——玩家的直观描述通常是「AI 在发呆 / 不追我」，而不是「排斥太强」。另外，靠「停在某个半径上」制造包围感是错的：正确做法是分角色（一部分贴身压迫、一部分前插到预判落点），并让两组的径向分量都**不为负**。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 全员径向压向同一点 + 横向力无预算 + 槽位按下标分配 = 包围退化成追尾队列
- Evidence / 证据: `script/enemy_ai.gd`（`LATERAL_CAP=0.6`、`RING_SPACING=34`、`RING_SLOT_SIZE=32`、`_assign_melee_slots()` 的「前排/同心环」与 `members.sort_custom(按 bearing)`、`_apply_slot()` 的 `minf(lerpf(...), radius)`）、`script/entity_ENEMY.gd`（`_steer_intent()` 的横向封顶与「失效槽不再 `return flow`」）、`tests/ai_probe.gd` 的「队列状排列也应被铺开到整圈 / 40 只应出现多层 / 极密人群仍偏向玩家 / 槽位失效不应退化成纯 flow」。
- Notes / 说明: **现象**（user，截图）：`candidates=89` 时近战聚成一条竖直长队，间距等于碰撞半径。**四个叠加原因**：① 横向力没有预算——切向 ≤0.75 + 密度 ≤0.45 + 反排队 ≤0.45，合计最大 1.65 > 径向 1.0，归一化后净方向被横向主导，整群侧滑打转；② 槽位按 `press_list[i]` 的**数组下标**分配（`PoolManager` 注册顺序），与位置无关，等于随机指方位，`min(|turn|/max_turn,1)` 又把它饱和成恒定侧推；③ 73 人同时径向 +1 压同一个点，只能沿到达方向排成队列；④ 槽点站不住时直接 `return flow`，失去全部方位信息，全员跟随同一条导航流向——89 人时靠墙槽位大量失效，这一条被成倍放大。**修法**：横向合力封顶 0.6；按方位角排序后同序分配（队列会被铺成整圈）；近战拆成「前排贴脸 ≤6 + 同心环（容量 `floor(TAU*R/32)`，人多自动扩圈）+ 前插」三层；失效槽只置 `valid=false`、仍按保留方位塑形。**识别特征**：队形沿玩家移动轴、间距=碰撞半径、`CHASE` 人数≈全部近战。**通用教训**：包围不能靠"所有人朝同一个点走 + 排斥力自然分开"，人数一多就必须显式分层（每层有独立半径与容量），否则任何排斥力都会被"全员径向"压成一条线。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 槽位只会向内收缩 + 失效即压流 = 玩家在场地角落时全员挤进轴线
- Evidence / 证据: `script/enemy_ai.gd`（`_fit_slot()` 的「先收缩再外扩」双段搜索、`_slot_ok()`、`_free_arc()`、`_assign_queue_push()` 的 `_ai_queue_pressure`、`_assign_melee_slots()` 第 7b 步用 `arc_span` 算容量与角度）、`script/entity_ENEMY.gd`（`_steer_intent()` 里 RING 的 `radial *= 1-QUEUE_DAMP*pressure`）、`tests/ai_probe.gd` 的 `_run_corner_checks()`。
- Notes / 说明: **现象**（user，截图）：玩家待在菱形场地**下半区**时，`RING 62 / CHASE 10` 全部挤在场地竖轴附近，形成一条竖直窄带，后排"不靠近"。**根因**：① `_fit_slot` 只会把半径**向下收缩**——玩家靠近顶点时，朝外的方位永远无解，整圈环带大量判失败；② 失效槽的降级是"径向=1 + 沿 flow 压上"，于是这几十只全部沿导航流向汇入楔形轴线；③ 角度按**整圈 360°** 分配，不管该方向能不能站，白白制造失效槽；④ 环带没有队列纪律，后排一直死推，视觉上就是"挤成一坨互相顶"。**修法**：`_fit_slot` 改成"原半径 → 向内收缩 → 向外增长"双段搜索（`SLOT_MAX_RADIUS=420`）；新增 `_free_arc()` 求最长连续可站立弧，环带的角度与容量都按这段弧来；`_ai_queue_pressure` 只对 RING 衰减径向（前排与前插不衰减）。**验证**：把玩家放到菱形下顶点上方 40px、40 只近战 → 槽点全合法、失效 ≤10%、覆盖弧 <270° 且空档朝场外、≥3 档半径。**通用教训**：任何"目标点搜索"如果只允许单向调整（只收缩/只外扩），在几何受限区域一定会大面积失败，而大面积失败又会被"降级策略"放大成完全不同的行为；另外**验收必须覆盖场地角落**，开阔地永远测不出这类问题。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 角色分配只看距离会选错人：贴脸但被卡住的敌人抢走前排/前插名额
- Evidence / 证据: `script/enemy_ai.gd`（`_enemy_velocity()`、`_score_intercept()`、`_score_front()`、`ROLE_HYSTERESIS/CLOSING_REF/ETA_REF/RANGED_DANGER_SPEED`、`_assign_melee_slots()` 第 5/7 步改按分数选人）、`tests/ai_probe.gd` 的 `_run_role_score_checks()`。
- Notes / 说明: 九期之前前排=离玩家最近的 N 个、前插=离预判点最近的 N 个，**完全不看速度**。问题在于"距离近"不等于"能干活"：一个被挤在人堆里、`velocity≈0` 的敌人会被选中当前排/前插，结果它既贴不上去也堵不到位。改法：用 `velocity`（`move_and_slide` 之后的实际速度）参与评分——前排分 = `0.6×1/(1+d/ring) + 0.4×clamp(接近速度/140)`，前插分 = `0.55×1/(1+ETA/2s) + 0.45×朝向对齐`，并给当前角色 `+0.15` 留任加成防抖。两个细节：① 位置项**不要硬截断**（`1-d/(2ring)` 在远处恒为 0，会让远处敌人只剩速度项可比），要用 `1/(1+d/ring)` 这种平滑衰减；② 速度抖动大（碰撞会让 `velocity` 突变），所以位置项权重给到 0.6、速度项 0.4，再加滞回。**通用教训**：凡是"从一群单位里挑几个担任角色"的分配，判据至少要同时包含**空间位置**与**运动趋势**；只有位置的分配在拥挤场景下会系统性地挑到"卡住的那批"。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 等距格子的 4 邻接流向场没有正方向分量：敌人上下方会左右摇摆
- Evidence / 证据: `script/enemy_nav_field.gd`（`NEIGHBORS4` 四个格偏移 + `flow[i] = normalize(_world[best] - _world[i])`）、`script/enemy_ai.gd`（`_has_line_of_sight` 驱动的 `_ai_flow_direct`、`_smooth_field_flow()`、`TANGENT_DEADZONE`）、`script/entity_ENEMY.gd`（`ai_steer()` 里 `_ai_flow_direct ? toward : _smooth_field_flow(...)`、`_steer_intent()` 的切向死区）、`tests/ai_probe.gd` 的 `_run_sway_checks()`。
- Notes / 说明: **现象**（user）：敌人在玩家正上方/正下方时左右摇摆。**根因**：等距瓦片 `64×32` 下 4 邻接的世界偏移只有 `(±32,±16)`，所以流向场的取值只有 `(±0.894,±0.447)` 四个对角方向，**没有正上/正下**。敌人在玩家正上/正下时，`toward` 与格轴成 45°，两条对角线的 BFS 距离对称，跨格时选中的对角线会翻面 → 左右摆；斜向敌人因为 `toward` 本身就接近某个对角方向，所以看不出来。更糟的是摆动会让"相对锚点的方位差"变号，`signf(turn)` 翻面使切向力反向，与摆动形成正反馈。**修法**：① 直线可走就别用场（`_ai_flow_direct`，开阔地这一条就够了）；② 被挡时用两点采样平均（当前点 + 沿目标方向 26px）让锯齿抵消；③ 切向加 3° 死区。**识别特征**：只有正上/正下/正左/正右摆、斜向正常 → 一定是格流锯齿，不要试图用调 `max_turn_deg`、加方向平滑或加大排斥来压，那只会把摆动换成延迟。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] `time_count()` 覆写不调 `super` 会静默丢掉脱困递减与策反结算
- Evidence / 证据: `scenes/enemies/tester_automaton_shield.gd:67`、`scenes/enemies/enemy_tank.gd:129` 的完整覆写；基类 `script/entity_ENEMY.gd:625` 尾部的 `_ai_unstuck_ticks -= 1` 与 `_convert_tick()`；连线在 `script/entity_ENEMY.gd:212`（`GameEvents.global_time_count.connect(time_count)`）；对照组 `automaton.gd:61`/`sweeper.gd:36`/`goliath.gd:361` 都调了 `super.time_count()`。
- Notes / 说明: `GameEvents.global_time_count` 直接连的是对象上的 `time_count`，子类一旦定义同名方法就**整体覆盖**基类实现。基类里除了闪白/击退，还顺手做两件很容易被忘掉的事：① `_ai_unstuck_ticks` 递减 —— 不递减的话 `EnemyAI._update_stuck()` 一旦置 8 就永不归零，该单位会**永久侧移**；② `_convert_tick()` —— 策反进度结算，不调就**永远无法策反**。`tester_automaton_shield` / `enemy_tank` 都属于后者，属于长期存在的隐性 bug。**注意不能简单改成调 `super.time_count()`**：那会执行两遍 `flash_time`/`knockback_time` 递减（一个 tick 减两次），正确做法是在覆写末尾手动补这两行。**通用教训**：这个仓库大量系统用 `GameEvents.global_time_count.connect(time_count)`，任何 `time_count` 覆写都要检查基类尾巴上有没有"顺手做的事"；加新敌人脚本时优先写 `super.time_count()` + 自身增量，而不是完整复制。
- Source / 来源: code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 「不在候选集里」的敌人其 `_ai_*` 会冻结，重新入集前必须清掉
- Evidence / 证据: `script/enemy_ai.gd` 的 `_is_candidate()`（`faction == PLAYER_SIDE` 直接 false）与 `debug_candidates()`；`script/entity_ENEMY.gd` 的 `_on_revert()`、`apply_network_conversion()` 解除分支、`_reset_ai_runtime()`、`idle_state()`；`tests/ai_probe.gd` 的 `_run_convert_checks()`。
- Notes / 说明: 策反（`faction = PLAYER_SIDE`）期间敌人被排除在 `EnemyAI._candidates` 之外，于是求解器**不再为它写任何 `_ai_*` 字段**——`_ai_intent`、`_ai_anchor`、`_ai_slot_angle/_ai_slot_valid/_ai_target_radius`、三种推力、`_ai_flow_direct` 全部冻结在策反前的最后一帧。解除策反后到下一次 5Hz 求解之间有最多 200ms，`ai_steer()` 会拿这些过期值做形塑：旧 `_ai_anchor` 可能是几秒前的玩家位置，旧意图可能还是 `CUTOFF`，表现为"刚变回来时愣一下、围着旧点转"。**修法**：解除时调 `_reset_ai_runtime()` 把运行时状态清空（`idle_state()` 复用同一个函数），清空后的首帧恰好是安全兜底——`_ai_intent == NONE` 直接走纯 `flow`，`_ai_anchor == ZERO` 会回退到 `predict_anchor`。**通用教训**：凡是"某个实体在某些状态下不参与某个系统"的设计，都要在**重新参与**的那一刻清掉该系统留给它的缓存，否则读到的就是历史值；并且给缓存留一个"未初始化"哨兵（这里是 `ZERO`）比留"上一次的值"安全得多。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 名额要设"保底"：三层会被前排+前插吃光，人少时环带直接为 0
- Evidence / 证据: `script/enemy_ai.gd` `_assign_melee_slots()` 的三层保底（`count >= 6` 时 `intercept ≤ count-2`、`attack ≤ count-1-intercept`）、`resources/enemy_ai/{insane,torment}.tres`、`tests/ai_probe.gd` 的 `_run_full_form_checks()`。
- Notes / 说明: `attack_slots`（前排贴脸）与 `intercept_ratio/cutoff_*`（前插围堵）各自独立算人数，**两者相加可能把 n 吃满**：旧 TORMENT 在 n=8 时是 `前排 5 / 前插 3 / 环带 0` —— 三层里的"包围环"直接消失，看起来像"完全体只有两层"。修法是加**结构性保底**：`count >= 6` 时强制 `intercept ≤ count-2`、`attack ≤ count-1-intercept`，保证三层各至少 1 个（n=6 → 3/2/1，n=8 → 4/3/1）。**通用教训**：多角色配额系统里，每个角色各自 `clamp` 是不够的，必须再加一条"总和不超预算 + 每个角色保底"的约束；另外 `attack_slots` 这类名字极易被误解成"围堵人数"，文档里要写清"它只管前排"。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-04

### [Enemy/AI] 性能必须先测：静态估算把最贵的一项低估了 10 倍
- Evidence / 证据: `tests/ai_probe.gd` 的 `_run_perf_checks()`（本地、不入库）实测 n=89：`solve_now` 8324µs，其中 `_apply_wall_push` **2005µs**、反排队 1836µs、槽位分配 4897µs（**含反排队**）。优化后 3239µs。涉及 `script/enemy_ai.gd` 的 `_apply_wall_push()` / `_assign_queue_push()` / `_slot_ok()` / `_sorted_indices()`、`script/enemy_nav_field.gd` 的 `_clearance` / `_near_solid` / `cell_*`。
- Notes / 说明: 直觉会以为"O(n²) 反排队 + 排序"是大头，实际**最大单项是每敌 8~16 次墙探针**（`is_solid` ≈1µs，89 只 × 12 ≈ 1ms）。四条可复用结论：① `world_to_cell` / `is_solid` / `nearest_inside` 都是 ~1µs 的引擎调用，**能预计算成按格数组就别逐次调**（`_clearance`、`_near_solid`、`_margin_ok`）；② 同一函数里对同一个点反复换格是纯浪费（`_slot_ok` 原来 3 次）；③ 计时口径要看清——`_assign_melee_slots` 的计时**包含**它内部调用的 `_assign_queue_push`，否则会重复计算、误判热点；④ "排序键预计算 + 手写归并排序（不走 Callable）"只省了 ~150µs（`sort_custom` 没想象中贵），而"墙探针快速放行"一改就省 1.8ms。**每次只改一项并复测**，否则无法归因。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Enemy/AI] Godot 4 的 `get()`/动态派发很便宜，别为它重构：真正的成本是 ~1µs 的引擎调用次数
- Evidence / 证据: `script/enemy_ai.gd`（`_candidates: Array[Enemy]` + `_ctx_pos/_ctx_vel/_ctx_intent` 快照、`_is_candidate/_resolve_target` 直接字段、`predict_anchor` 位置精确缓存）、`script/enemy_nav_field.gd`（`epoch`）、`script/entity_ENEMY.gd`（`_ai_flow_*` 记忆化）；基准 `tests/ai_probe.gd::_run_perf_checks()`：3239µs → 3173µs（**-2%**），`ai_steer` 8.00µs 不变。
- Notes / 说明: 把 89 只敌人的逐敌 `get()`/`global_position`/`set()` 全部换成类型化直接字段 + 打包数组快照后，总耗时只降 2%——**`Object.get()`/属性访问在 Godot 4 里是 ~0.1µs 量级**，不是瓶颈。真正的成本结构是：`world_to_cell` / `is_solid` / `nearest_inside` 各 **~1µs**，`_slot_ok` 每次最少 1 次换格、`_fit_slot` 89 次、密度 8 次、墙探针被放行后 0 次；再加上 GDScript 本身的算术体积（89 只 × 每人上百次浮点运算）。**结论**：① 优化优先"减少引擎调用次数"（预计算表、缓存、放行门），而不是"减少动态派发"；② 减法比换写法有用——本次真正的收益来自"墙探针放行"（-1.8ms）这种**跳过整段工作**的改动；③ 到了 3ms 量级后，剩下的只能靠**减少参与量**（人数上限/降频/静止跳过）或换语言（GDExtension），继续抠写法收益 <5%。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Enemy/AI] 每敌成本降不下去时，用「战术分层人数上限」把尖峰与人数解耦
- Evidence / 证据: `script/enemy_ai.gd` 的 `TACTICAL_LIMIT = 60` 与 `_trim_group()`、`script/entity_ENEMY.gd` 的 `_ai_tactical`；`tests/ai_probe.gd::_run_perf_checks()` 实测 n=40/89/150 → 1411/2677/3652µs，其中 slots+queue（战术部分）在 89 与 150 时分别是 1192+354 / 1212+366（**基本不变**）。
- Notes / 说明: 当一个 AI 系统的单次求解成本主要由「~1µs 的引擎调用 × 每敌次数 × 人数」决定时，继续抠写法收益 <5%（见上一条），真正的杠杆是**限制参与量**。做法是按目标分组、只保留最近 K 只进入战术层（角色/槽位/反排队），其余清空意图退回纯场流——`_steer_intent()` 对 `INTENT_NONE` 已经直接返回 `flow`，所以"降级"是零成本的既有路径，不需要新分支。两个必须做对的细节：① 被裁掉的敌人要**主动清** `_ai_intent/_ai_slot_valid/_ai_flow_direct`，否则会带着上一轮的意图和陈旧的直线判定继续被塑形；② 上限按**目标**而非全局计（联机两个玩家各 60），否则一个玩家会把另一个的份额吃光。⚠️ 该上限只约束战术层，`_collect`/密度/离墙仍随人数线性增长——要彻底封顶得连 `_candidates` 一起裁，代价是远处敌人失去离墙逃生。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Enemy/AI] 给敌人加 AI 状态前先问"客机要不要"：镜像不模拟 AI，两个拦截点缺一不可
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_enemy_proxy.gd`（`network_remote_enemy` meta、`disable_mirror_ai()`）、`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_send_enemy_snapshot()` 打包 `pos/vel/hp/state/converted/gauge`）、`script/enemy_ai.gd` 的 `_is_candidate()`、`script/entity_ENEMY.gd` 的 `ai_active()` 与 `ai_steer()` 顺序、`tests/ai_probe.gd` 的 `_run_coop_mirror_checks()`。
- Notes / 说明: 本项目是 **host 权威 + 客户端镜像快照插值**。镜像节点的判据是 `has_meta("network_remote_enemy")`，必须同时保持两个拦截点：① `EnemyAI._is_candidate()` 直接排除（否则镜像会占前排/环带/前插名额、被 splat 进密度场、被算进角色评分）；② `Enemy.ai_active()` 让 `ai_steer()` 在**调用 `ensure_solved()` 之前**返回 `base_dir`（否则客户端会自己跑求解）。缺任何一个都会变成"客户端也跑 AI"——表现是位置抖动、双份决策、甚至两边敌人走位不一致。反过来，**任何新的 `_ai_*` 运行时字段都不要加进快照**：镜像不模拟，同步过去只会覆盖出双份真相。当前快照只带 `pos/vel/hp/state/converted/gauge`，这是刻意的。
- Source / 来源: code + test
- Date / 日期: 2026-11-04

### [Coop/Relay] 建房/入房有四段独立时钟；服务端先超时只会给客机一条无原因的 `STATE_CLOSED`
- Evidence / 证据: `mod_sdk/coop_mod/server/relay_server.py:40-53`（4 个超时常量，均读环境变量）、`:612`（HTTP 头读取）、`:680-691`（读循环剩余时间 + `except asyncio.TimeoutError` 打 `[ADMIT] timeout`）、`:473-475`（`join_room` 接受时记 `peer.joined_at`）、`:501`（`client_ready` → 准入）；客户端 `mod_sdk/coop_mod/mods/etn_coop/net/coop_relay_peer.gd:11-12`（两个 30 s 常量）、`:84-91`（`STATE_CLOSED` 只报 "Relay connection failed"）；`tests/test_relay_limits.py` 的 `RelayTimeoutConfig` / `RelayAdmissionDeadline`。
- Notes / 说明: ①「读 HTTP Upgrade 头」的 10 s 从 TCP accept 后起算（DNS/TCP 时间不计入），可它一旦先到点，客户端侧只看得到 `STATE_CLOSED → "Relay connection failed"`，完全看不出是服务端提前掐断——2026-10-11 把客户端握手放宽到 30 s 时漏了这里，2026-11-05 才统一到 30 s。原则：**服务端任何握手超时必须 ≥ 客户端同段预算**，否则报错信息会退化成一个没有任何线索的 disconnect。②`join_prepared → client_ready` 原本没有专属时限：`join_room` 接受后 `peer.room` 已非空，`JOIN_TIMEOUT_SEC` 立刻失效，只剩 20 s 无数据兜底；而服务端每 5 s 发 PING、客户端自动回 PONG 会刷新 `last_seen`，所以「TCP 活着但不推流程」的客机永远回收不掉，pending 又计入房间容量 → 别人看到 `Room full`。现在用独立 `ADMIT_TIMEOUT_SEC` 从 `join_room` 接受起算，`client_ready` 到达（`admitted=True`）后失效。③这类到点在实现上是 `asyncio.wait_for` 抛 `TimeoutError` 结束的，会落进通用 `except Exception`，必须单独 `except asyncio.TimeoutError` 才能留下可分辨的日志，否则日志里只有一条 `[DISCONNECT]`。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-05


### [Combat] `damage_taken` 的数值含过杀，表现回放也会发它 —— 统计类消费者必须自己选口径
- Evidence / 证据: `script/health_component.gd:161-168`（先算 `overkill_damage`，再 `stats.hp = max(0, hp - final_damage)`，最后 `damage_taken.emit(final_damage, ...)`）；`script/health_component.gd:50-56`（`play_hit_feedback` 也 `damage_taken.emit`，但不扣血）；`scenes/enemies/dps_count.gd`（沙袋 DPS 表按原值累计）
- Notes / 说明: 挂在该信号上的统计（DPS 表/伤害计量/连击计数）拿到的不是「实际扣血」：目标只剩 35 血时一发 99999 记 99999（沙袋 `is_test_target=true` 且 0 血仍放行，几乎每发都是过杀）。要「构筑输出」就直接累加（沙袋 DPS 的选择），要「有效输出」必须自己用命中前的 `stats.hp` 夹一次。另：联机客机命中表现回放走 `play_hit_feedback` → 同一信号，本地计量会把它计入（与飘字一致）；做玩法结算的监听者不能假设「发信号 = 真掉血」。
- Source / 来源: code
- Date / 日期: 2026-11-05

### [Godot/2D] Y-sort 会递归展平 `sort_y` 子树，TileMapLayer 可与玩家/敌人交错
- Evidence / 证据: `main.tscn` 的 `YSort`/`PlayerRoot`/`FieldModRoot` 均 `y_sort_enabled=true`；Godot `renderer_canvas_cull.cpp::_collect_ysort_children` 在 `child_items[i]->sort_y` 为真时递归展平；`tile_map_layer.cpp` 在 y-sort 模式下按 `map_to_local().y + tile_y_sort_origin + y_sort_origin` 建每格 quadrant。
- Notes / 说明: 挂在 `YSort` 下、自身开 `y_sort_enabled` 的 `TileMapLayer` 不需要退回“每格一个 Sprite2D”也能和角色/敌人前后遮挡；`TileData` 的每 tile `y_sort_origin` 决定排序点，`0` = 按格中心、`16` = 按底边。`barricade_tileset.tres` 按现有 Wall 标准用 `0`。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Godot/TileMapLayer] 独立 layer 的 cell body 归属于 layer 节点，`BulletWall` 组可直接被子弹命中
- Evidence / 证据: `scenes/bullet/enemy_bullet.gd:52-58`（`body_entered` + `is_in_group("BulletWall")`）、`script/player_bullet.gd:177-190`（RayCast collider 同组检查）、`scenes/field_mods/barricade.gd::_build_overlay`；引擎 `tile_map_layer.cpp::_physics_update_cell` 的 `body_attach_object_instance_id(body, tile_map_node ? tile_map_node->get_instance_id() : get_instance_id())`。
- Notes / 说明: 独立 `TileMapLayer`（不是旧 `TileMap` 子层）的物理 body instance id 就是 layer 节点自身，所以 `add_to_group("BulletWall")` 对玩家 RayCast 与敌人 Area2D 都生效。层必须同时含 `bullet_wall(2)` 与 `wall(256)`（本项目用 `collision_layer=258`）；只给 2 会挡不住角色，只给 256 会挡不住子弹。`EnemyNavField` 的自动障碍扫描现在认两类：`StaticBody2D`，以及 **`NavObstacle` 组**的 TileMapLayer/TileMap used cells；独立 TileMapLayer 加入 `NavObstacle` 后无需 `add_block`，cells 变化后 `invalidate()` 即可。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Godot/TileSet] 64×32 等距 tile 用 `texture_region_size=(64,32)+size_in_atlas=(1,2)` 得到 64×64 绘制区域
- Evidence / 证据: `scenes/main/main.tscn` 的 `TileSet_5duvi`/`TileSet_1vifn`（`texture_region_size=Vector2i(64,32)`、`0:0/size_in_atlas=Vector2i(1,2)`、`texture_origin=(0,16)`）；Godot `tile_set.cpp::TileSetAtlasSource::get_tile_texture_region()`：`region_size = texture_region_size * size_in_atlas`。
- Notes / 说明: 新墙体优先复用该标准：`tile_size=(64,32)`、`tile_shape=1`、每 tile 1×2、`texture_origin=(0,16)`、碰撞菱形 `(0,16),(-32,0),(0,-16),(32,0)`。`tile_wall_1.png`（256×64、4 个 64×64 变体）按 4 列 × 2 行放置为 `0:0`/`1:0`/`2:0`/`3:0`；不要再自算 13 之类的 origin（现有素材按现有标准画，`16` 即可）。
- Source / 来源: code + user
- Date / 日期: 2026-11-05

### [Map/Bounds] 阻挡词条必须在 `MapBounds.get_boundary_source()=="walls"` 之后生成墙体
- Evidence / 证据: `script/map_bounds.gd:19,325-344`（从 `CenterPosition` 向 ±x/±y 射线，mask=256 取 `FloorWall` 内壁）；`script/map_bounds.gd:35-48`（只有 `first_round_add` 会 invalidate，正常局内不重建）；`scenes/field_mods/field_mod_effect.gd` 的 `_await_bounds_ready()`；`scenes/field_mods/barricade.gd::on_start()` 的 walls 门控。
- Notes / 说明: 若在兜底 `spawnmap` 阶段就把 layer 258 的墙放下，之后 `MapBounds` 重试射线时可能先命中新墙，把“可行走菱形”缩到墙内侧，触发每秒一次的误拉回。用 `FieldModEffect` 的基类会先等 walls；自建效果也必须显式门控，且不要用 SpawnMap 兜底 hull 生成阻挡物。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [GDScript/FieldMods] 无类型 Array 不能直接赋给 `Array[MapChunk]`；连通性过滤在玩家种子无效时会静默跳过
- Evidence / 证据: `scenes/field_mods/terrain_field_effect.gd:59`（本轮由 `chunks = _filter_connected_chunks(chunks)` 改为 `chunks.assign(...)`）、`:215-244`（`_reachable_cells()` 以玩家格为 BFS 种子，种子无效时返回空基线，`_filter_connected_chunks()` 直接返回源块）。
- Notes / 说明: GDScript 4.7 实测把 `_filter_connected_chunks()` 返回的无类型 `Array` 直接赋给 `Array[MapChunk]` 会在运行时抛 `Trying to assign an array of type "Array" to a variable of type "Array[MapChunk]"`，打断场地词条；必须用 `Array.assign()` 复制。另：任何调用 `TerrainFieldEffect` 的阻挡词条都要在 `on_start()` 先确认玩家在当前 `all_cells` 内，否则连通性过滤会静默失效，可能把玩家/刷怪口围死。
- Source / 来源: test + code
- Date / 日期: 2026-11-05

### [Tool/Godot] 运行期保存 `.tscn` 模板用 `PackedScene.pack` + `ResourceSaver.save`，只在编辑器运行时可写 `res://`
- Evidence / 证据: `scenes/field_mods/barricade_template_editor.gd` 的 `_save_to()`（Node2D 根 + `ObstacleMapTemplate` 脚本 + `Core`/`Optional` 复制层 → `PackedScene.pack` → `ResourceSaver.save`）；`scenes/field_mods/barricade_templates/default.tscn` 即由该工具写出。
- Notes / 说明: 工具是开发工具，不是 EditorPlugin；用 F6 在编辑器里运行，`res://` 可写。导出后的游戏 `res://` 只读，不能保存模板。目录创建要用 `ProjectSettings.globalize_path()` 转原生路径再 `DirAccess.make_dir_recursive_absolute()`；直接传 `res://...` 会报 `Could not create directory: 'res://scenes'`。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Map/Editor] 主地图中心是 `BattleRoom (704,448)`，模板红边界/参考图都要用它
- Evidence / 证据: `scenes/main/main.tscn` 的 `BattleRoom` Marker2D `position=(704,448)`；`BackLayer/MapTest2` Sprite2D `position=(704,450)`、`rotation=-0.453786`、`scale=2.48`、`skew=-0.663225`；`scenes/field_mods/barricade_template_editor.tscn` 的红色菱形 `[(704,16),(1568,448),(704,880),(-160,448)]`。
- Notes / 说明: 地图不是以原点为中心；模板编辑器如果按 (0,0) 画红边界会整体错位。`MapChunks` 的 cell 坐标与 `main.tscn` 的 `YSort` 同系；模板的 Core/Optional 层保持原点，不要给节点加位移。地图背景是旋转/斜切的 Sprite2D，不是等距 TileMap，所以模板工具必须复制它的 transform 才能“所见即所得”。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Map/Barricade] 整图模板的随机浮动只做减法；加法随机必须配连通性修复
- Evidence / 证据: `scenes/field_mods/barricade.gd` 的 `_pick_terrain_chunks()`（`Optional` 按 `optional_keep_chance` 只保留/移除）、`_carve_out()`（只移除玩家/中心/portal/敌人/召唤物/预留格上的墙）、`_ensure_connectivity()` / `_find_wall_bridge()`（从玩家格 BFS 自由格；不可达区沿墙格最短路径拆开并 warning）。
- Notes / 说明: 只移除墙不会产生新的封闭区；随机加墙可能把区域围死，必须每次生成后做自由格连通性检查。连通性修复在墙格图上 BFS 找“不可达自由区 → 已可达区”的最短拆墙路径，比逐块丢弃整图模板更细。模板目录扫描要“编辑器优先 `DirAccess`（能立刻看到刚保存的文件），导出回退 `ResourceLoader.list_directory`”；`_` 开头的模板文件跳过。实测：合成 4 格环包住 1 格自由格 → 修掉 1 格后全图 706/706 可达。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Godot/TileMapLayer] 离树读模板 cells 可行；模板实例用 `free()`，隐藏挂载兜底
- Evidence / 证据: `scenes/field_mods/barricade.gd` 的 `_read_template_layers()`；模板场景根 `ObstacleMapTemplate` + `Core`/`Optional`；`PackedScene.instantiate()` 后不加入树即可 `get_used_cells()`/`get_cell_atlas_coords()`。
- Notes / 说明: 模板只是数据源，Core/Optional 的 `collision_enabled=false`；离树读不到时（防御分支）挂到隐藏 `Node2D` 下再读，然后 `queue_free()`；正常路径直接 `free()`。不要在模板层上挂碰撞/可见的 Reference 到运行时（工具里的参考图不写进模板文件）。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Godot/2D] Y-sort 链上不能有非 y-sort 中间节点，否则整棵子树按该节点 y 排序
- Evidence / 证据: `scenes/field_mods/barricade.tscn`（根 `Barricade` 现在 `y_sort_enabled=true`，子层 `ObstacleWall` 也开）；`scenes/field_mods/barricade.gd::_build_overlay()`；运行时把 `BarricadeEffect` 根临时设 `y_sort_enabled=true` 后，玩家在墙后时墙能遮住玩家腿部（截图对比）。
- Notes / 说明: 层级是 `YSort → FieldModRoot → FieldMod_chip_barricade（BarricadeEffect）→ ObstacleWall（TileMapLayer）`。之前效果根 `y_sort_enabled=false`，Godot 的 y-sort 遇到非 y-sort 中间节点会把整棵墙体子树当成一个节点（按效果根 y≈0 排序），结果墙体永远在玩家后面、玩家永远盖住墙。**修复 = 从 YSort 到具体 TileMapLayer/Sprite 的每一级中间节点都开 y_sort_enabled**；墙层 `y_sort_origin=-3` 让排序点落在视觉底边中心（tile base 中心在格子中心 -3）。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Godot/TileSet] 碰撞多边形相对格子中心；`texture_origin` 的偏移必须在多边形上补偿
- Evidence / 证据: `scenes/field_mods/barricade_tileset.tres` 的 4 个 tile 从 `PackedVector2Array(0,16,-32,0,0,-16,32,0)` 改为 `PackedVector2Array(0,0,-32,-16,0,-32,32,-16)`；`barricade_tileset.tres` 的 `texture_origin=(0,16)`；TileSet 编辑器的白点图对应 texture `(32,16),(0,32),(32,48),(64,32)`，换算到格子中心即新 points。
- Notes / 说明: TileSet 编辑器里多边形看起来是相对**贴图区域中心**画的；运行时 body 原点在**格子中心**，而贴图又被 `texture_origin` 上移。`texture_origin=16` 时，编辑器预览与运行时碰撞差 16px；要让碰撞对齐贴图中心，必须把多边形整体上移 16。四个变体必须同步改，否则同一墙不同视觉变体碰撞位置不同。墙体视觉/碰撞仍共用 `ObstacleWall` 层，物理层 `258`。
- Source / 来源: code + user
- Date / 日期: 2026-11-05

### [Godot/TileMapLayer] `BulletWall` 组必须挂在 TileMapLayer 节点上；效果根上的组不会被子弹 body 命中
- Evidence / 证据: `scenes/field_mods/barricade.tscn` 的 `ObstacleWall` 节点 `groups=["BulletWall"]`；`scenes/field_mods/barricade.gd::_build_overlay()` 对场景层做防御性补组；实测 `shiroko_bullet.tscn`（`player_bullet.gd` RayCast mask=2）与 `enemy_bullet.tscn`（Area2D mask=2050）撞墙 `is_idle` 均 0→1，`ObstacleWall.is_in_group("BulletWall")` 为真。
- Notes / 说明: 独立 TileMapLayer 的每个 cell 物理 body instance id 绑定 layer 节点；子弹检查的是 body 的组，所以组要挂在 `ObstacleWall`，不是 `BarricadeEffect` 根。场景里直接写 `groups=["BulletWall"]` 比运行时临时 `add_to_group` 更容易检查；代码仍保留补组防御。模板工具的 `CoreEdit`/`OptionalEdit` 是 `collision_enabled=false` 的数据层，不需要也不应挂这个组。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Godot/工具] Random 模板层是“必放 + 随机外观”，不要和 Optional 的“随机存在”混用

SUPERSEDED: 2026-11-06 用户澄清 Random 是墙体贴图随机，本质仍是 Core 一类；不是独立放置层/第三模式，见下方新条目。
- Evidence / 证据: `scenes/field_mods/barricade_template_editor.gd`（`PaintMode.RANDOM`、`_paint_at_hovered()` 强制 variant 0、`_save_to()` 写 `Random` 层）；`scenes/field_mods/barricade.gd::_pick_terrain_chunks()`（Random 优先于 Optional 加入 `wall_set`）。
- Notes / 说明: Core = 必放固定外观；Optional = 按 `optional_keep_chance` 随机存在、固定外观；Random = 必定生成、运行时每格随机外观。同一格手工重叠时优先级 Core > Random > Optional；工具绘制会从另外两层擦除，正常不会重叠。
- Source / 来源: code
- Date / 日期: 2026-11-05

### [Godot/工具] Random 模板格统一存 variant 0，绿色 tint 只是编辑器标识

SUPERSEDED: 2026-11-06 改为 Core/Optional 内的 source 1 随机贴图标记，不是独立 Random 层，见下方新条目。
- Evidence / 证据: `barricade_template_editor.gd::_copy_layer()` 把 atlas.x 夹到 0..3 后写 variant 0；`_save_to()` 给 `Random` 层 `modulate=Color(0.55,1,0.65,0.85)`；`barricade.gd::_build_overlay()` 对 `_random_variant_cells` 调 `_pick_variant()`（默认 `variant_weights=0.7/0.1/0.1/0.1`）。
- Notes / 说明: 模板文件不记录随机结果；Random 格的外观完全由运行时 RNG/`variant_weights` 决定，所以同一模板重开回合会变化。要四种等概率就把 `variant_weights` 改成 `[1,1,1,1]`；绿色 tint 不会进入战斗渲染，只用于工具/模板场景里区分“随机”。
- Source / 来源: code
- Date / 日期: 2026-11-05

### [Godot/工具] 删除模板用 DirAccess.remove_absolute，失败回退到目录 remove；删除当前模板要清空编辑区
- Evidence / 证据: `barricade_template_editor.gd::_delete_path()`；实测工具保存 `probe_random.tscn` 后 `_load_path()` 计数恢复、`_delete_path()` 返回后 `FileAccess.file_exists=false`、当前模板被清成 New（`Core 0 / Optional 0 / 随机贴图 0`）。
- Notes / 说明: 编辑器内运行工具时 `res://` 可写；`DirAccess.remove_absolute(ProjectSettings.globalize_path(path))` 正常，失败再 `DirAccess.open(TEMPLATE_DIR).remove(file)`。导出游戏不能写 `res://`，该工具是编辑器开发工具。删除非当前模板保留当前编辑内容；删除当前模板必须 `_new_template()`，避免继续保存到已删路径。
- Source / 来源: code + test
- Date / 日期: 2026-11-05

### [Godot/工具] 模板工具预览层也要 Y-Sort；只修战斗墙层不够
- Evidence / 证据: `scenes/field_mods/barricade_template_editor.tscn` 的 `World` 与 `CoreEdit`/`OptionalEdit` 现在都 `y_sort_enabled=true`、`y_sort_origin=-3`；`barricade_template_editor.gd::_setup_editor_y_sort()` 在 `_ready()` 里防御性再设一次。用户截图（红边界 + 绿色随机贴图方块）里前方墙不遮挡后方墙，是工具预览层没有 y-sort，不是战斗表现。
- Notes / 说明: 战斗的 `ObstacleWall` 已经在上一轮修好，但模板工具的编辑层默认 `y_sort_enabled=false`，墙块按绘制顺序画；Core/Optional 两层还要父节点 `World` 也开 y-sort，才能跨层正确交错。排查“墙不遮挡墙”时先看红边界/绿色 tint，确认是编辑器预览还是战斗；两者要分别设置，不能只修一边。
- Source / 来源: user + code
- Date / 日期: 2026-11-05

### [Godot/工具] Random 是 Core/Optional 的随机贴图标记，不是独立放置层
- Evidence / 证据: `scenes/field_mods/barricade_tileset.tres` 新增 source 1（`tile_wall_random.png`，第一墙体改绿色）；`barricade_template_editor.gd` 调色板第 5 项 `RANDOM_VARIANT=4`，绘制时 `set_cell(cell, RANDOM_SOURCE_ID=1, (0,0))`；`barricade.gd::_read_layer_cells()` 读 source 1 返回 `-1`，`_pick_terrain_chunks()` 只把该格加入 `_random_variant_cells`，`_build_overlay()` 用 `variant_weights` 随机 0~3。
- Notes / 说明: 放置语义完全由 Core/Optional 决定：Core 必放、Optional 按概率保留；“随机贴图”只影响外观，不改变是否生成。模板 Core/Optional 里 source 0 是固定变体（atlas 0~3），source 1 是随机贴图标记；工具里 5 个调色板选项（4 变体 + 绿色随机）。旧版独立 `Random` 层只作兼容：效果按 Core 类必放随机贴图处理，工具加载时迁移到 Core source 1，保存后不再写该层。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] EnemyNavField 可直接从 NavObstacle TileMapLayer 生成阻挡场
- Evidence / 证据: `script/enemy_nav_field.gd` 的 `_scan_static_obstacles()`/`_mark_obstacle_tilemap()`/`has_obstacle_tilemaps()`；`scenes/field_mods/barricade.tscn` 的 `ObstacleWall` 组 `["BulletWall","NavObstacle"]`；`scenes/field_mods/terrain_field_effect.gd` 的 `nav_use_obstacle_tilemap` 跳过 `add_block` 并在 `_build_overlay()` 后 invalidate。
- Notes / 说明: 运行时障碍 tilemap 的 used cells 经 `map_to_local`/`to_global` 映射到 `MapChunks` 格，写入 `_solid_auto`；`has_blocks()` 包含 `has_obstacle_tilemaps()`，所以只有 tilemap 源、没有手动 `add_block` 时 AI 也会建场。cells 改变后必须 `invalidate()`，否则场缓存旧墙；`on_stop()` 先移出 `NavObstacle` 组再释放层，避免 `queue_free` 延迟期间重建扫到旧墙。身体安全用 `is_cell_body_safe`/`nearest_body_safe_point`（8 邻域无阻挡才算安全），刷怪/贴墙槽位/卡墙逃逸共用。
- Source / 来源: code + test
- Date / 日期: 2026-11-06

### [Map/Barricade] 模板工具所见 ≠ 实机：建墙先做避让减法，Optional 再随机删
- Evidence / 证据: `scenes/field_mods/barricade.gd:208`（`_pick_terrain_chunks` 分层 Core/Optional）、`barricade.gd:406`（`_build_carve_ctx`：player 64 / portal cells+96 / 敌人 96 / 召唤物 80 / 预留格）、`barricade.gd:43`（`connectivity_scope=RANDOM_ONLY`）；`scenes/field_mods/barricade_layout.gd:32`（`carve_out`）。
- Notes / 说明: 实机最终墙 = Core − 避让 − Boss 出场清墙 + 按 `optional_keep_chance` 保留的 Optional（再被随机墙连通回收）。编辑器以前只提供红边界/网格，所以“满环”在实机必然缺墙。模板工具新增实机避让圈、`PreviewEdit` 与页脚预计数量；调模板时先看页脚的“实机预计”。
- Source / 来源: code + user + test
- Date / 日期: 2026-11-06

### [Map/Nav] 寻路场用主地图 TileMap 的格子（菱形），不是世界坐标正方形格
- Evidence / 证据: `script/map_chunks.gd::ensure_ready()/get_all_cells()`（`map.get_used_cells()` + `map.local_to_map`/`map_to_local`，格子即主地图 TileMap 的 cell）；`script/enemy_nav_field.gd:53-57`（`NEIGHBORS8` + `DIAGONAL_COST`）、`:777-786`（`_diagonal_ok` 要求两侧正交格都可通行）、`:788-847`（`_rebuild_flow` 用 NEIGHBORS8 建流场）；`script/map_chunk_grid.gd:86-90`（4×4 只是按格坐标分块，块内仍是 TileMap 格）。
- Notes / 说明: 寻路场的格子来自 64×32 等距 TileMap，视觉上是菱形；索引空间是方格坐标，但邻接是 tile 的 cell 邻接，不是另建的世界正方形网格。AI flow 用 8 邻域（直 1、对角 √2），对角步要求两侧正交格可通行，因此**可达连通块与 4 邻接完全等价**；8 邻域只改变流向/路径长度，不会让“4 邻接断开、8 邻接连通”的区域变成可走。壁垒模板的 4 邻接连通判定用的就是同一套 `MapChunks` 格坐标，和寻路场的连通块一致。`MapChunkGrid` 的 4×4 分块是索引空间的分块（选块/刷怪用），不是移动图的格。调试 overlay 只在小方块标记/箭头上画，不代表底层是正方形格。
- Source / 来源: code + user
- Date / 日期: 2026-11-06

### [Map/Barricade] 可通行 = 实心墙不可通行 + 可行走格 4 邻接连通（2026-11-06 用户裁定）
- Evidence / 证据: `scenes/field_mods/barricade_layout.gd`（`bfs_reachable` 4 邻接、`repair_optional_connectivity`）、`scenes/field_mods/barricade.gd`（`connectivity_scope=RANDOM_ONLY` 分支）。
- Notes / 说明: **模板连通判定不使用 body-safe / clearance / 8 邻域 / 窄缝 3×3 扩宽**。solid 墙格不可通行；其余可行走格只按 4 邻接判断。Core 是作者基线（只读）；Core 自身不可达的区域（大块实心墙围住）视为不可通行，只进编辑器“信息”。只有 Optional（随机墙）把 Core 原本可走的区域隔断时才回收（拆 Optional 桥，拆不动则本轮 Optional 全丢），Core 不拆、不整图回退。1 格缺口按格连通可通过。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Map/Barricade] body-safe 用 16px clearance，不是 8 邻域；整图回退是误判
- Evidence / 证据: `script/enemy_nav_field.gd:107,316`（AI 侧 clearance 主判据）；旧壁垒曾用 8 邻域近似。
- Notes / 说明: 这是 AI 侧 body-safe 的判据（一格宽通道约 32px，窄缝 <16px 挡住）。**模板连通判定已按用户裁定改为“可行走格 4 邻接连通”，不再使用该 clearance**；不要再把 AI body-safe 与模板可通行混为一谈。
- Source / 来源: code + user
- Date / 日期: 2026-11-06
- SUPERSEDED: 2026-11-06 模板判定不再使用 body-safe/clearance，见上条“可通行 = 可行走格 4 邻接连通”。

### [Map/Barricade] Core 只作基线、Optional 才回收（RANDOM_ONLY）
- Evidence / 证据: `scenes/field_mods/barricade_layout.gd`（`repair_optional_connectivity`：Core 基线只读，Optional 拆桥/本轮全丢）、`scenes/field_mods/barricade.gd`（RANDOM_ONLY 分支）。
- Notes / 说明: 作者负责 Core 连通；运行时只保护 Core 基线下原本可达的**可行走格**（4 邻接）。Core 自身不可达只作信息，不拆、不整图回退。`connectivity_scope=ALL` 保留纯格连通的可拆 Core 兼容路径。
- Source / 来源: user + code
- Date / 日期: 2026-11-06

### [Map/Barricade] Boss 中心保护延后到 Boss 出现；玩家起点 64
- Evidence / 证据: `scenes/field_mods/barricade.gd:870`（boss 事件连接）、`barricade.gd:903`（`_clear_walls_in_radius`）、`barricade.gd:965`（`on_stop`）；`scenes/field_mods/barricade.tscn`（`avoid_player_start_radius=64`、`connectivity_scope=0`、`defer_boss_avoidance=true`）。
- Notes / 说明: 建墙时只清玩家 64 / portal / 敌人 / 召唤物 / 预留格；中心 240 改为 `on_start` 扫描现有 `BOSS` + `boss_encounter_started` 计划位置 + `boss_joined` 实际位置再清。玩家碰撞半径约 12~16，最近的 ±y/斜墙格心 32~36px，64 足够清掉贴身墙；±x 的 64px 墙保留也有约 32px 余量。
- Source / 来源: user + code
- Date / 日期: 2026-11-06

### [Godot/Tween] 效果 stop 后立刻 queue_free，淡出必须挂父节点 ghost
- Evidence / 证据: `scenes/manager/field_mod_manager.gd`（`_remove_entry` 调 `stop()` 后立刻 `effect.queue_free()`）、`scenes/field_mods/barricade.gd:941`（`_spawn_fade_ghost`）、`barricade.gd:965`（`on_stop` 捕获 cells/variants，`super.on_stop()` 前隐藏主层，ghost 挂 `get_parent()`）。
- Notes / 说明: 直接在 `on_stop()` 里 `await` tween 会被效果的 `queue_free` 连带释放；用 `collision_enabled=false`、不挂 `BulletWall`/`NavObstacle` 的临时 `TileMapLayer` 挂到父节点（`FieldModRoot`，y-sort 正确）做视觉淡出。主层碰撞/导航立即更新，Boss 清墙不会被淡出延迟。
- Source / 来源: code
- Date / 日期: 2026-11-06

### [Map/Barricade] 当前 6 个模板实测 Core 数量与新策略
- Evidence / 证据: 真实 `main.tscn` + 6 个模板复算（player 64 / portal cells+96 / 中心延后 / 无敌人/召唤物/预留格）。
- Notes / 说明: `dark_forest_1` 184→120；`dark_forest_2` 499→355（Core 自身不可达区域只作信息，不处理）；`dark_forest_3` 144→108；`dark_forest_4` 288→226；`dark_forest_5` 125→77；`room_1` 236→236。Optional 全保留时由 Optional 桥回收；运行时当前 `keep=0` 不生成。表中不含 Boss 登场后的 240 清除。
- Source / 来源: test
- Date / 日期: 2026-11-06

### [Map/Barricade] EnemyNavField 菱形常量与 tileset 碰撞多边形差 8px（AI 侧，待确认）
- Evidence / 证据: `script/enemy_nav_field.gd` 的本地菱形常量 `(0,0),(-32,-16),(0,-32),(32,-16)` 与 `scenes/field_mods/barricade_tileset.tres` 的 `(0,8),(-32,-8),(0,-24),(32,-8)`。
- Notes / 说明: 这是 **AI 侧** body-safe 的遗留 8px 偏差；模板连通判定已改为纯格连通，不再引用它。是否把 AI 的 clearance 改成 tileset 实际多边形另做确认，不在此次擅自改手感。
- Source / 来源: code
- Date / 日期: 2026-11-06

### [Enemy/AI] flow 可走 = 非 solid（2026-11-06 用户要求；后被实机极限环推翻）
- Evidence / 证据: `script/enemy_nav_field.gd::_flow_passable()`（只排除 `_solid`）、`_diagonal_ok()`（对角只要求两侧非 solid）、`_build_body_ok()`/`_update_safe_cell()`（body_ok 仍给 safe/attack/刷怪锚点）；`ui/ai_debug_overlay.gd::_draw_priority()`（数字=场距离；`-`=free 但 flow 未到且 body-unsafe；`x`=free+body-safe 但未到）。
- Notes / 说明: 曾试过把 flow 改成只避 solid，让 1 格宽/格心离墙 <16px 的 free 格也入流；验证：x=15 全列加 block、只留 y=27 的 1 格缺口，缺口 `body_safe=false`，右侧 136 个 free 格 `far_inf=0`。但实机在墙边 body-unsafe 带出现 7↔8 往复：避障为了身体宽度绕到 dist 更高的格，flow 又按自由格把敌人拉回低 dist 格。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06
- SUPERSEDED: 2026-11-06 实机 7↔8 极限环，flow 恢复 body-safe（见下条）。

### [Enemy/AI] 纯场模式（MoveMode.PURE_FIELD）在夹墙/三只 CHASE#0 场景更顺（用户实机反馈）
- Evidence / 证据: `EnemyNavField.move_mode = MoveMode.PURE_FIELD`、`Enemy.ai_steer()` 直接返回 `EnemyAI._smooth_field_flow()`；实机 10/11 夹墙三只的往复明显改善；AI probe 182/39（比 body-safe 基线多 3 条，含“竖直方向上每一点都应朝向玩家 worst_dot=0.000”）。
- Notes / 说明: 纯场跳过阵型切向、密度/队列、`wall_push` 和 `_ai_avoid_blocked_ahead()`；黄色 `wall_push` 仍计算但不参与转向。它解决的是“避障选高 dist 格、flow 拉回低 dist 格”的合成冲突，但纯按格场流缺少直线/竖直稳定。现在作为**对照/回退模式**保留；默认已是 `FIELD_STRATEGY`（见下条）。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] FIELD_STRATEGY：场主方向 + 受约束横向（2026-11-06 用户拍板默认）
- Evidence / 证据: `EnemyNavField.MoveMode`（`PURE_FIELD/FIELD_STRATEGY/LEGACY`）；`Enemy.ai_steer()`、`_ai_steer_field_strategy()`、`_steer_intent(..., project_strategy=true)`、`_project_perp()`、`_wall_safe_push()`、`_field_blend_direct()`、`_field_progress_worse()`、`_field_side_step()`；`_ai_dir_body_clear()` 整段采样。
- Notes / 说明: 场负责绕墙/前进；阵型切向、密度、队列只投影到场垂直面并封顶；墙推去掉与场相反的分量；直线整段身体可过且场进度不变差时才补正上/正下/正左/正右；最终方向过 body-clear + 场进度校验，失败退回场方向或场相邻格侧步（180ms 滞后）。无 profile 单位保持旧行为；`PURE_FIELD`/`LEGACY` 保留。**路线模式默认关闭（2026-11-06 修正）**：`EnemyAI.local_route_mode=true` 会让 `solve_now()` 走 `_simple_follow()` 并绕过 `_assign_melee_slots/_assign_ranged_slots`，所有敌人保持默认 CHASE#0、无 rank/槽位（用户实机截图现象）；改成 false 后 AI probe 222/2，旧 36 条预存失败随 route mode 消失。剩余 2 条是“贴边槽位合法 3”（`_apply_slot` 平滑/attack anchor 边界）和“方位偏离横向修正”（测试用 toward 垂直面、代码用场垂直面）的边缘用例，未处理。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] flow 恢复 body-safe：body-unsafe 格会造成 7↔8 极限环
- Evidence / 证据: `script/enemy_nav_field.gd::_flow_passable()`（`field.body_ok` / `_cell_body_safe_local` / `_cell_flow_blocked`）、`script/entity_ENEMY.gd::_ai_dir_body_clear()`/`_ai_avoid_blocked_ahead()`、实机截图（7/8 往复）、`tests/_tmp_flow_check`（body-unsafe 缺口 `far_inf>0`）。
- Notes / 说明: **用户观察到的循环机制成立**：避障选 dist 更高的 body-unsafe 格，下一帧 flow 又拉回 dist 更低的格。只改避障会让敌人卡在低 dist 格（身体过不去），根因是 flow 把身体过不去的格当成可走。已恢复 flow 的 body-safe 过滤；模板/壁垒仍用可行走格 4 邻接 free 连通（那一层不受影响）。真正的 1 格宽 body-safe 通道（≈32px）仍会入流；墙边 body-unsafe 带显示 `-`（flow 未到）或 `x`（body-safe 但被断开），这是敌人身体宽度的真实信号。调试 overlay 新增品红色 `direction`（实际合成转向），黄色仍是 `wall_push`。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 斜向墙/窄缝：BFS 场、视线与局部避障都必须 body-safe
- Evidence / 证据: `script/enemy_nav_field.gd` 的 `_cell_flow_blocked()`/`_rebuild_field()`（BFS 跳过 `_near_solid`，seed 落墙边改取最近 body-safe 格）；`script/enemy_ai.gd::_has_line_of_sight()` 改用 `is_body_safe`、`_smooth_field_flow()` 的 lookahead 拒绝 body-blocked；`script/entity_ENEMY.gd::_ai_dir_body_clear()` 与 `_ai_avoid_blocked_ahead()` 的左右侧身体探针。
- Notes / 说明: 斜向墙的墙块在角上相接，点可以从缝里穿过、身体（半径约 12）不能；只按 `_solid` 建 BFS/视线会把这种缝当通路，敌人堆在墙边。修法是让 **流场可走格 = 非 solid 且 8 邻域无 solid**，LOS 采样用同一 body-safe 判定，局部方向再查中心+两侧。注意：这是 **AI 移动**的 body-safe；模板可通行判定已改为纯格连通（2026-11-06 用户裁定），两者不要混用。**2026-11-06 曾试 flow 只避 solid，实机 7↔8 极限环，已恢复 body-safe；见上条。**
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 玩家贴墙时：goal 与 standable 必须分开
- Evidence / 证据: `script/enemy_nav_field.gd::ensure_rebuilt()`（仅 solid/越界才换 seed，`_near_solid` 保留）、`_rebuild_field()`（start 可 body-blocked；flow 允许 `next_index == start` 作为 goal）、`script/enemy_ai.gd::_smooth_field_flow()`（lookahead 在目标格/攻击距离内允许）、`script/entity_ENEMY.gd::_ai_dir_body_clear()`（目标格/攻击距离内豁免 body-safe）。
- Notes / 说明: 玩家站在墙边时，玩家格是 `_near_solid`（敌人身体不能站），但它是**寻路终点**。把 seed 换成“最近 body-safe 格”会让流场指向远处，敌人不靠近。正确做法：玩家/锚点格只作为 goal 保留在场上，BFS 从它出发、flow 指向它；敌人仍只站 body-safe 格。`dist(player)=0`、旁边安全格 flow 指向玩家；攻击距离内 `_ai_dir_body_clear` 放行，靠碰撞阻止真正穿墙。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 小角落/深 nook：goal_zone + 同 free 连通域安全起点
- Evidence / 证据: `script/enemy_nav_field.gd` 的 `GOAL_ZONE_RADIUS_CELLS=3`、`GOAL_FALLBACK_MAX_CELLS=12`、`_build_goal_zone()`、`_nearest_body_safe_in_free_component()`、`_rebuild_flow()`、`Field.start_cell`；`script/enemy_ai.gd` 的 front/ring goal slot（`_fit_slot<0` 时 radius 0 + CHASE）。
- Notes / 说明: 玩家在 1~3 格小角落时，玩家格和 4 邻格都可能 `_near_solid`，纯 body-safe BFS 会被隔离成“只有 seed 的零流场”。修法是把请求 seed 周围 3 格内的**非 solid 自由格**作为 goal_zone，仅允许流场穿越（不改变 `is_body_safe`/spawn/slot）；若 goal_zone 接不到任何 body-safe，沿**同一 free 连通域**找最近 body-safe（最多 12 步）作为有效 BFS 起点，不能取全局欧氏最近（会跨墙到另一侧）。深到 1 格窄走廊时敌人应停在走廊口/最近可达点，玩家在深处是安全的；不要为了靠近而穿墙。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 外围反复走：attack anchor + hold，不是继续扩大 goal 区
- Evidence / 证据: `script/enemy_nav_field.gd` 的 `Field.attack_cell`、`get_attack_point()`、`_choose_attack_index(seed, from_pos)`（从敌人所在 body-safe 连通域取离玩家最近点）、`_nearest_cell_in_component()`；`script/enemy_ai.gd::solve_now()` 的 `from_pos=最近敌人`、`_assign_melee_slots(attack_anchor, body_unreachable)`、`_assign_ranged_slots(attack_anchor, target_pos, body_unreachable)`；`script/entity_ENEMY.gd` 的 `_ai_attack_unreachable`/`_ai_hold_pos` 与 `ai_steer()` 驻留。
- Notes / 说明: 玩家在墙环/安全孤岛里时，field 的 seed/goal 仍是玩家，但敌人实际可站的是**敌人连通域内离玩家最近的点**。如果阵型锚点仍留在玩家，front/ring、goal slot、16 方向兜底会把敌人往墙里推；流场再拉回可达点，就形成外围反复走。修法：attack_cell 从敌人侧连通域算；近战/远程阵型围绕 attack_cell；attack_cell != 玩家锚点时 `body_unreachable=true`，到 attack 点/槽位后 `ai_steer` 返回 ZERO 驻留，不再追进墙。远程 LOS 仍以玩家为目标，不能隔墙开火。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 空旷地停住：不可达判定不能用世界距离
- Evidence / 证据: `script/enemy_nav_field.gd::is_target_reachable_from(target, from_pos)`（玩家与最近敌人是否在同一 body-safe 连通域）；`script/enemy_ai.gd::solve_now()` 的 `body_unreachable := not is_target_reachable_from(...)`。
- Notes / 说明: 上一版用 `attack_anchor.distance_squared_to(anchor) > 1.0` 判定不可达；attack 是格心，anchor 是玩家/预判世界坐标，空旷地也常差 >1 格，导致所有敌人被标 `_ai_attack_unreachable`，到玩家附近就 `ai_steer → ZERO` 停住。正确判定是**玩家格与最近敌人格是否同一 body-safe 连通域**：同域=可达（正常追/攻击），异域或玩家格 body-blocked=不可达（到 attack 点驻留）。墙环宽开口同域应正常进环；窄开口/身体不可达 nook 停在 attack 点是预期，不是丢寻路。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 目标点取撞墙碰撞箱中心，不是脚下/精灵中心/第一个 CollisionShape2D
- Evidence / 证据: `script/enemy_nav_field.gd::target_anchor()`/`_find_wall_body()`/`_wall_body_shapes()`；玩家 `scenes/player/momoi/momoi.tscn:264-276` 根 `CharacterBody2D` 在脚下、根 `CollisionShape2D=(0,-6)`、`HurtboxShape=(0,-8)`、`PickBox CollisionShape2D=(0,-11)`、`AnimatedSprite2D=(0,-17)`；敌人 `scenes/enemies/sweeper.tscn:161-192` 根 `collision_mask=256`、身体 `(0,-11)`。
- Notes / 说明: 只取 `collision_mask & WALL_LAYER(256)` 的 `PhysicsBody2D`，并且只取它的**直接** `CollisionShape2D`/`CollisionPolygon2D`；`HurtBox`/`PickBox`/武器等 `Area2D` 或非直接子树全部排除。多个身体碰撞箱取中心均值，再 `MapBounds.nearest_inside` 夹回可走边界。玩家贴墙时脚下可能已经在墙内约 1.63px，裸 `global_position` 会把 field seed/reachability 带到墙格；用身体中心后目标格回到可走区。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 组 field 不能只用最近敌人：优先“能到达玩家”的敌人
- Evidence / 证据: `script/enemy_ai.gd::_nearest_reachable_group_enemy_position()`；`solve_now()` 在 `_nearest_reachable...` 为空时才回退 `_nearest_group_enemy_position()`；`EnemyNavField.is_target_reachable_from()` 用玩家与敌人的 body-safe 连通域。
- Notes / 说明: 最近敌人可能在墙的另一侧/另一个 body-safe 连通域；若只用它算 `from_pos`，`Field.attack_cell`/`is_target_reachable_from`/`body_unreachable` 会把**整组**判成不可达，实际可达的敌人也一起 hold。正确顺序：组内先找任意能到达玩家的敌人作为 `from_pos`；全都不可达才用最近敌人 + hold。无人机 `ShirokoDrone` 是 `CharacterBody2D` 默认 layer 1/mask 1，敌人 layer 8/mask 256，不会物理挡路，也不在 Player/RemotePlayer/Converted/Summoned 组，不是目标。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] RING 视觉“卡住”：hold 半径覆盖槽位 + 环带无上限
- Evidence / 证据: `script/entity_ENEMY.gd::ai_steer()` 的 hold 条件；`script/enemy_ai.gd::_assign_melee_slots()` 的 `MAX_MELEE_RINGS=3`、环带循环、溢出内圈；`ui/ai_debug_overlay.gd` 的 `_ai_attack_unreachable/_ai_hold_pos/_ai_ring_index`。
- Notes / 说明: 旧 hold 用 `max(AI_HOLD_RADIUS, _ai_target_radius+6)`；RING 敌人到槽位时距离≈target_radius，必在 hold 半径内 → 整圈 RING 被提前 ZERO。改为只对 `_ai_attack_slot` / CHASE / CUTOFF / RUSH 且在 attack 点 `AI_ATTACK_REACH+8` 内生效；RING/queue 不触发。RING 环带最多 3 圈；溢出优先复用 `ring_base` 压缩角度，站不下才退第二圈，不再铺第 4 圈。实机 7 敌人验证：RING(r=120) `unreachable=true` 但 `_ai_ring_index=0`、不再被 hold；前排 CHASE(r=13) 仍驻留。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 障碍聚集先用 simple follow 隔离“阵型 vs field”
- Evidence / 证据: `script/enemy_ai.gd::simple_follow_debug`、`_simple_follow()`、`last_melee_debug`；`ui/cheat_menu.gd` 的 SimpleFollow 按钮；`ui/ai_debug_overlay.gd` 的 SIMPLE FOLLOW/melee 计数。
- Notes / 说明: 可视化出现 CHASE=0、RING/NONE 大量时，先别盲改 field。开关打开后跳过 density/melee/ranged/queue 阵型，所有 candidate 强制 `INTENT_CHASE`、anchor=target_anchor、radius 0、slot_valid/attack_slot=true、unreachable=false、hold ZERO、flow_direct=false，仍用 EnemyNavField 绕障。实机 4 敌人：全部 intent=1 CHASE、ring=-4、unreachable=false、hold=ZERO。若 simple follow 能靠近而原策略不能，问题在阵型/槽位/hold；若仍聚集，再查 field/目标点/墙簇连通域。`last_melee_debug` 输出 melee/press/front/cutoff/attack_count，用于解释 CHASE=0。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 寻路场 flow 根必须是玩家/seed；attack_cell 只是阵型锚点
- Evidence / 证据: `script/enemy_nav_field.gd::_rebuild_field()` 的 `start` 现在从 `seed` 取，`attack` 只写 `field.attack_cell`；`debug_field()`/`debug_cell()`/`debug_field_cells()`；`ui/ai_debug_overlay.gd` 的 per-cell nav flow + seed/start/attack/target markers。
- Notes / 说明: 旧版 `start = attack`，BFS/flow 指向 attack 点而不是玩家；玩家体旁的敌人会沿流场往外走（尤其墙簇 attack 在环外时）。改为 start=seed/玩家（body-blocked 时靠 goal_zone 接 body-safe），attack 仅用于 AI 阵型/攻击锚点。实机：seed=start=target=(11,32)，probe 格 flow 点积 0.979 指向玩家。Nav overlay 打开时默认显示每 2 格 flow 箭头 + seed(黄)/start(绿)/attack(红)/target(蓝) 标记。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 玩家 target 贴墙会归到墙格：target_anchor 需同 free 连通域 body-safe snap
- Evidence / 证据: `script/enemy_nav_field.gd::target_anchor()` 的 snap；`debug_field()` 的 `target_safe/target_solid/target_body_safe`；`_choose_attack_index()` 的玩家侧优先；`EnemyAI.solve_now()` field seed 用 `target_anchor`。
- Notes / 说明: `MapBounds.nearest_inside` 只夹地图外边界，不避开 barricade/ObstacleWall；玩家贴墙时身体中心格可能 solid/body-blocked，target_cell/field seed 会落在墙上。target_anchor 现在：身体中心 → MapBounds → 若 cell 非 body-safe，则在同一 free 连通域找最近安全格（cell 不可通行时退到脚下格），找到则返回安全格世界点。实机 target_solid=false、target_safe=true；但安全格是**格子中心**，贴墙时 target 会比玩家身体远约一格，这是为了不把目标放进墙里。attack 玩家侧优先、field seed=target 已同步。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] target 只取局部安全格：U 形地形不能用全局最近安全点
- Evidence / 证据: `script/enemy_nav_field.gd::target_anchor()`（不再 snap）、`target_safe_anchor()`（`TARGET_SAFE_RADIUS=3`，free BFS 同连通域）、`target_safe_cell()`；`debug_field()` 的 `target_safe_cell/target_safe/target_solid`；overlay 的 `safe` 标记。
- Notes / 说明: target 只取 body-safe 格是对的，但“全局最近安全格”会在 U 形地形从开口跑到外面，导致 flow/target 整体外移。`target_anchor` 保留玩家身体点；`target_safe_anchor` 只在玩家附近 3 格、同一 free 连通域内找最近 body-safe 格，找不到才用现有 fallback。field seed=target_safe；ranged LOS target 仍用实际 target_anchor；刷怪/槽位用 target_safe。实机空地：target_anchor=safe=身体中心，seed/start/attack 同格。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] target 用玩家脚下 + 8 邻域 flow
- Evidence / 证据: `script/enemy_nav_field.gd::target_anchor()`（`target.global_position` + MapBounds）、`target_safe_anchor()`（局部 3 格同 free 连通域）、`_rebuild_flow()` 的 `NEIGHBORS8`/`DIAGONAL_COST`/小顶堆；`EnemyAI.solve_now()` field seed=target_anchor。
- Notes / 说明: body-center/collision-center target 会带来额外偏移；target 改回玩家脚下 `global_position`，只做 MapBounds 夹回。field seed 用脚下 target；attack/reachability/spawn 用 `target_safe_anchor`（局部安全格）。flow 从 4 邻域改 8 邻域，直线 1.0、对角 √2，Dijkstra 小顶堆；对角步要求两侧正交格都可通行，避免穿墙角。headless 项目加载无脚本错误；编辑器内旧 `diagonal` parse error 是脚本缓存未刷新，plugin reload 后编辑器连接断开，需要重新打开/连接 Godot 编辑器。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] target 脚下 solid 只做局部非 solid snap；safe/attack 跟 field.dist
- Evidence / 证据: `script/enemy_nav_field.gd::target_anchor()` 的 `_nearest_free_cell_local(TARGET_SOLID_SNAP_RADIUS=3)`；`target_safe_anchor()` 先取 `field.dist` 最小 body-safe；`ensure_rebuilt()` 在 `_rebuild_field` 后用 `target_safe_cell` 覆盖 `field.attack_cell`。
- Notes / 说明: 玩家贴 U 形左夹角时脚下点可能 solid；只做局部 3 格“非 solid” snap，不要求 body-safe、不取全局最近。safe/attack 不再用 12 步自由 BFS 的几何最近，而是取 field.dist 最小的 body-safe（与 flow 同侧），并在 ensure 后用 target_safe 覆盖 field.attack_cell，保证 attack=safe。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 简化：一张按玩家的场 + 近似路线参考 + 局部避障
- Evidence / 证据: `script/enemy_ai.gd::local_route_mode`、`_route_points`、`ensure_route()`、`route_direction()`；`script/enemy_nav_field.gd::route_points()`/`_route_next()`；`script/entity_ENEMY.gd::ai_steer()` 的 route 分支。
- Notes / 说明: per-target 729 格 Dijkstra + `target_safe` 729 遍历 + debug nav 729/帧在 48+ 敌人下过重且 safe/attack 仍偏。改为 `local_route_mode`：只按玩家建一张 field（低频），从敌人侧沿 field.dist 抽 10~20 个 waypoint 的近似路线；敌人取最近 segment 切线做参考，最终仍用 `_ai_dir_body_clear`/`_ai_avoid_blocked_ahead`/wall push/unstuck 局部避障。route 模式跳过 `_nearest_reachable` 的 target_safe 遍历，减少每敌开销。headless 项目加载无脚本错误；编辑器插件断开需重开。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 极简模式：flow 只指向玩家，去 safe/attack/local 避障
- Evidence / 证据: `script/enemy_nav_field.gd::simple_field_mode`、`_flow_passable`（not solid）、`_rebuild_field` simple 分支（start=player/nearest free，attack=start）；`script/enemy_ai.gd::solve_now` simple 分支；`script/entity_ENEMY.gd::ai_steer` simple 分支（`sample` 直接返回）。
- Notes / 说明: 之前 safe/attack + body-safe/near-solid + 局部避障叠加，既会偏移又卡顿。极简模式只做：field 从玩家脚下出发，`_flow_passable` 只排除 solid；敌人直接 `EnemyNavField.sample` 的 flow，不做 `_ai_dir_body_clear`/`_ai_avoid_blocked_ahead`/wall push/hold/RING/queue；窄缝/墙角交给物理碰撞。headless 项目加载无脚本错误；编辑器插件断开需重开。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 一格宽通道用墙面 clearance，不用 8 邻域 near-solid
- Evidence / 证据: `script/enemy_nav_field.gd::_wall_clearance`/`BODY_CLEARANCE`/`_rebuild_wall_clearance()`/`_measure_wall_clearance()`；`is_cell_body_safe()`/`_cell_flow_blocked()` 改用 clearance；`_local_wall_component()`/`_cell_body_safe_local()`；`Field.local_walls` 传入 `_flow_passable`/`_rebuild_flow`/`route_points`。
- Notes / 说明: 8 邻域 near-solid 会把一格宽长通道整条判死（每格 8 邻域都有墙），但 64px 通道远宽于敌身直径约 24px。改为格心到 solid 格 diamond 边缘的 clearance（阈值 16px）；1 格通道中心约 32px 可通过，真正窄缝仍挡。玩家脚下格相邻的 solid 连通块记 `local_walls`，这组墙的 clearance 不计入，避免 target/safe 被推远；其它墙仍挡。`simple_field_mode` 默认改为 false，保留开关对比。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 玩家场 body_ok/safe 预计算 + 玩家相连 free 口袋
- Evidence / 证据: `script/enemy_nav_field.gd::Field.body_ok`/`player_pocket`/`safe_cell`；`_player_pocket_cells()`（4 邻接、限 16 格）；`_build_body_ok()`；`_update_safe_cell()`；`_field_reusable()`（seed≤1、300ms）；`_flow_passable()` 读 body_ok；`target_safe_anchor()` 读 safe_cell。
- Notes / 说明: 原来每次查询都跑 `_cell_body_safe_local`→`_wall_clearance_excluding`，且玩家沿墙每格重建 field，导致墙边卡。改为一张玩家场：重建时一次算 `player_pocket`/`body_ok`（clearance 通过或属于玩家口袋）/`safe_cell`，查询 O(1)；field 在 seed≤1 且 <300ms 时复用。玩家相连 free 口袋（限 16 格）额外放行，保留原墙面判断给其它格；1 格宽通道仍按 clearance 通过。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 路线 lookahead + 平滑 + 末端锁定玩家
- Evidence / 证据: `script/enemy_ai.gd::route_direction()` 沿 route 推进 `ROUTE_LOOKAHEAD=32`；`ROUTE_SMOOTH_RATE=10`；`PLAYER_LOCK_RANGE=96`/`PLAYER_UNLOCK_RANGE=112`；`script/entity_ENEMY.gd::_update_route_lock()` 与 `ai_steer()` 的 route 分支（`_ai_route_smooth` lerp）。
- Notes / 说明: 之前 route 模式直接返回最近 segment 切线，segment 边界会“被场推”一样顿；改成 lookahead 方向 + 每敌 `_ai_route_smooth` 指数平滑，减少抖动。进入 96px 或身体直线可走时锁定玩家，`desired=toward` 直接朝玩家；超过 112px 或隔墙才退出，做滞回。field 只生成 route，不参与每帧推力。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 多 lane 优先级选路：场只给距离，敌人按优先级分散
- Evidence / 证据: `script/enemy_nav_field.gd::route_lanes()`（玩家口袋边界入口，3~5 条 lane）；`script/enemy_ai.gd::ensure_lanes()`/`lane_direction()`/`assign_lane()`（`LANE_CAPACITY=8`，拥挤/绕路/换道评分）；`script/entity_ENEMY.gd::_ai_route_lane`（每 300ms 重选）。
- Notes / 说明: 单 route 在 48+ 敌人时会堆在同一侧。改为多 lane：场只给 field.dist/口袋边界，lane 从入口沿 dist 到玩家；敌人按 `到入口距离 + 拥挤*80 + length*0.02 + 换道 60 + 超容量 1000` 选 lane，容量 8。route 方向仍用 lookahead 32 + `_ai_route_smooth` 10，末端 96/112 锁定玩家。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 玩家场改为格子距离优先级，敌人跟 dist 梯度
- Evidence / 证据: `script/enemy_nav_field.gd::sample()` 返回朝低 dist 邻居的方向；`script/entity_ENEMY.gd::ai_steer()` route 分支直接 `EnemyNavField.sample(position, target)`；`script/enemy_ai.gd::solve_now()` route 分支只 `ensure_rebuilt`；`ui/ai_debug_overlay.gd::show_priority`/`_draw_priority()`。
- Notes / 说明: 不再抽 lane/route/safe/attack 做移动；`field.dist` 就是优先级（玩家 0，越远越大），敌人采样梯度自然绕墙。保留末端锁定（96/112）和 `_ai_route_smooth` 平滑。overlay 默认 `show_priority=true`、`show_nav_flow=false`，只画优先级热力/数字，隐藏箭头/seed/start/attack/target/safe。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 移动恢复 route lookahead/平滑 + 末端锁定；优先级仅显示
- Evidence / 证据: `script/entity_ENEMY.gd::ai_steer()` route 分支恢复 `EnemyAI.route_direction()`；`script/enemy_ai.gd::solve_now()` route 分支恢复 `ensure_route()`；`ui/ai_debug_overlay.gd::show_priority` 保持不变。
- Notes / 说明: 直接跟 `sample()` 的 cell flow 会有“被场推”的顿挫；恢复单 route 的 lookahead(32) + `_ai_route_smooth`(10) + 末端锁定(96/112)。优先级 dist 仍用于显示/兜底，不再直接作为移动方向。lane 代码保留但休眠，不参与当前移动。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 凹口 3↔2 徘徊：距离场 3→2 正常；修 route 稀/身后段/无死区
- Evidence / 证据: `script/enemy_nav_field.gd::route_points()` 默认 `step_cells=1`；`script/enemy_ai.gd::_direction_from_points()` 投影 t>0.9 时推进到下一段；`ROUTE_DEADBAND_DEG=18`；`PLAYER_UNLOCK_RANGE=128`；`script/entity_ENEMY.gd::ai_steer()` 死区保持上一帧方向。
- Notes / 说明: 距离场相邻步最多 1（对角 √2），3→2 是正确梯度，3→1 是跳过一格。凹口徘徊来自 waypoint 太稀、最近 segment 可能选到身后、lookahead 32 太短、无方向死区。改为 step=1、只选前方段、18° 死区内保持旧方向、锁定退出 112→128。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 斜向格近距离：统一 8 邻域 corner-cut（_diagonal_ok）
- Evidence / 证据: `script/enemy_nav_field.gd::_diagonal_ok()`；`_rebuild_flow()` 的 Dijkstra 与 flow 循环用它；`_route_next()` 也加同一检查。
- Notes / 说明: 8 邻域 Dijkstra 允许从两个墙块夹角斜穿时，格本身非 solid、clearance 够，dist 会被算低；物理碰撞又走不过去。把“对角步必须两侧正交格都可通行”抽成 `_diagonal_ok`，flow 与 route 共用；斜穿路径不再产生低 dist。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 性能：overlay 10Hz/隔格数字、route 方向缓存、body_ok nearest-wall 剪枝
- Evidence / 证据: `ui/ai_debug_overlay.gd::REFRESH_INTERVAL=1/10`、`_draw_priority()` 数字每 2 格；`script/enemy_ai.gd::route_epoch`（ensure_route 重建 +1）；`script/entity_ENEMY.gd::_ai_route_dir_epoch/_cell/_vec`；`script/enemy_nav_field.gd::_wall_nearest`/`_wall_probe_nearest`，`_cell_body_safe_local()` 最近墙非 local 直接 false；`_field_reusable()` 300→400ms。
- Notes / 说明: 掉帧主因是 15Hz 画 729 格 + 365 个字符串、每敌每帧遍历整条 route、body_ok 逐格全扫 solid。改为 10Hz/数字隔格、route 方向按 route_epoch+格缓存、body_ok 先看最近墙（非 local 直接 false）、field 复用 400ms。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 调试优先级每格都标数字（solid=#，INF=-）
- Evidence / 证据: `ui/ai_debug_overlay.gd::_draw_priority()` 去掉 `i % 2`，每格 `draw_string`；`solid` 显示 `#`，`dist>=INF` 显示 `-`，可达显示 `dist`；字号 6，10Hz。
- Notes / 说明: 之前只画 `i % 2 == 0` 且跳过 INF/solid，看起来像中间空了一块。现在每格都有标签；solid 暗红 `#`、INF 深灰 `-`、body_safe=false 数字变暗。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [Enemy/AI] 3→4 而非 2：共享 route 覆盖本地 field 梯度，45° 兜底
- Evidence / 证据: `script/entity_ENEMY.gd::ai_steer()` route 分支新增 `field_dir = EnemyNavField.sample()`；`ROUTE_FIELD_GUARD_DEG=45`，route 与 field 夹角超过时用 field。
- Notes / 说明: route 从一个 `_nearest_group_enemy_position()` 出发，站在 3 的其他敌人可能不在 route 起点附近，route lookahead 会指向 4 侧，覆盖 field 的 3→2。加本地梯度兜底后，route 只做平滑，明显冲突时用 field。headless 项目加载无脚本错误。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06
- SUPERSEDED: 2026-11-06 实测无明显区别，已回退 route-only。

### [Coop] buff `value` 数组在联机消毒里只保留 3 项 → 条目标记改走 `source_id`
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_sanitize_buff_value`（`mini(value.size(), 3)`）；`scenes/manager/buff_manager_base.gd:apply_buff`（`entry["source_id"] = source_id`）；`scenes/manager/enemy_buff_manager.gd:_refresh_dot_crit_source`。
- Notes / 说明: 想给 buff 条目带标记（如「该来源的异常 DOT 可暴击」）时**不要**塞 `value[3+]`：客机 `apply_buff` 会被 `enemy_buff_apply_gate` 转发到 host，而 host 侧 `_sanitize_buff_value` 只保留前 3 项 → 单机正常、联机静默失效。`source_id` 不在消毒范围内（恶寒按来源计层本就依赖它），故标记放在 `entry["source_id"]` 上。`entry["can_crit"]` 采用粘滞语义（被白名单来源施加过即保持到条目销毁），避免被其它道具的后续施加覆盖成时有时无。headless 探针 `tests/maki_passive_probe.gd` 覆盖（maki_ps 可暴击 / 其它来源不可）。
- Source / 来源: code + test
- Date / 日期: 2026-11-06
- SUPERSEDED: 2026-11-07 机制已改为「HealthComponent 统一异常暴击口 + 本机玩家被动 meta」（见下文「异常伤害暴击统一到结算口」）；`entry["source_id"]` / `entry["can_crit"]` 已移除，不再需要 per-entry 白名单。

### [Coop] 镜像玩家 PS 的 `_ready` 早于 mod 断开全局信号 → 新 PS 必须自带本地守卫
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:spawn_remote_player`（先 `remove_from_group("Player")` 再 `add_child`，随后 `_attach_player_proxy` → `setup` → `_disconnect_remote_global_signals`）；`scenes/player/maki/maki_ps.gd:_is_local_player`。
- Notes / 说明: 远端玩家镜像会实例化**整个**玩家场景（含 PS），其 `_ready` 在 `add_child` 期间就执行并订阅 `GameEvents`；mod 只是事后按节点断开连接。若 PS 有全局副作用（开火掷概率、命中施加 buff、改 `PlayerData` 乘区），必须在 `_ready` 首行判「本机玩家」（组 `Player` + 无 `network_remote_player` meta），镜像直接不订阅、不注册；否则镜像 PS 会重复结算。探针验证镜像 `_local=false` 且未订阅 `player_shot_position`。
- Source / 来源: code + test
- Date / 日期: 2026-11-06

### [Buff] 恶寒按来源独立叠层：上限取来源自己的 value[0]，不要动全局上限
- Evidence / 证据: `scenes/manager/enemy_buff_manager.gd:_uses_source_caps`（`chill_dot` 恒真）/`_add_source_layer`/`_source_cap_total`；`scenes/bullet/chill_ring.gd`（`chill_layer_cap=5`、`source_id`）；`scenes/update_item/nagusa_doll.gd:42-43`（cap=5+quantity、`source_id=item_id`）；`scenes/player/maki/maki_ps.gd:_element_value`（CHILL `[cap, 0, 3]`）。
- Notes / 说明: 恶寒 `entry["layer"]` 是各来源层数之和、`max_layer` 是各来源上限之和；**一次 `apply_buff` 只加 1 层**（`value[0]` 只是该来源的上限）。给角色/道具新增恶寒来源时，只设自己的 `value[0]` 上限并传独立 `source_id`（Maki 用 `max(1, round(5 × stats.chill_layer_mult))`），不要改全局上限、也不要复用别人的 `source_id`，否则会互相侵占。另：`chill_dot.tres` 未设 `remove_by_layer`，整条 buff 到期时所有来源一起清空（既有行为，本次不改）。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-06

### [FX] 多元素配色的粒子：每个颜色一个 GPUParticles2D（floor_paint 范式）
- Evidence / 证据: `script/floor_paint.tscn`（Pink/Blue/Yellow 三个 GPUParticles2D，各自独立 `ParticleProcessMaterial`）；`scenes/effects/anomaly_paint.tscn`（Fire/Poison/Chill 同构，颜色取 `DamageData.TYPE_COLORS`）；`scenes/effects/goliath_cannon_particles.tscn`（需要运行期改参时才用 `resource_local_to_scene=true`）。
- Notes / 说明: `.tscn` 里的 `ParticleProcessMaterial`/`Gradient` 是**场景内共享子资源**；同一场景被池化复用多个实例时，运行期改 `process_material.color`/`color_initial_ramp` 会串到所有实例（包括正在播放的旧实例）。固定几种颜色就用「一色一个发射器 + 按需 `restart()`」（floor_paint / anomaly_paint），只有确实要按实例调参时才 `resource_local_to_scene=true`（Goliath 粒子即此）。另：2D 粒子最终颜色按线性空间呈现，场景里填的 sRGB 常量看起来会比色卡更暗/更饱和；与伤害数字同源（`DamageData.TYPE_COLORS`）即可保持一致观感。
- Source / 来源: code + test
- Date / 日期: 2026-11-07

### [Coop/Field] 壁垒联机的首帧不能只读 `field_mod_started` 时的 `_cells`
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:_attach_barricade_effect`；`scenes/field_mods/barricade.gd:on_start`（`FieldModEffect.start()` 内 await `MapBounds`）与 `walls_built`（`_build_overlay`/`_clear_walls_in_radius`）。
- Notes / 说明: `FieldModManager._start_chip()` 调 `effect.call("start")` 后立刻 emit `field_mod_started`，而 `FieldModEffect.start()` 是 async，`on_start()` 可能还没跑；此时 `_cells` 为空。Host 必须连接 `walls_built` 并全量转发，同时用 `get_wall_data()` 补一次当前快照；客机 `apply_network_walls()` 只重建 tilemap/碰撞/NavObstacle，不跑模板/随机/避让/连通。客机 `field_mod_spawn_gate` 拦本地 `barricade.tscn`，否则 host 镜像 + 本地随机墙两套。单进程镜像测试 `[BARRICADE_NET_CHECK] ok=1`。
- Source / 来源: code + test
- Date / 日期: 2026-11-07

### [Coop/Field] 壁垒重连：handshake 早于场景 ready，且空快照必须显式 stop
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd` 的 `_client_hello`（`_migrate_peer_state` → `_accept_peer`）、`_accept_peer`（`_send_barricade_state_to_peer`）、`_client_scene_ready`（battle 分支末尾补发）、`_finish_reconnect`（`_clear_barricade_mirror`）、`_send_barricade_state_to_peer`（cache/现场为空 → `_remote_barricade_stop`）。
- Notes / 说明: 重连握手在客机 `_hello_accept`/`_finish_reconnect` 之前完成，且客机可能仍停在旧场景；只在 `_accept_peer` 发壁垒快照会落到旧场景或与旧 mirror 竞争，所以 `_client_scene_ready` 必须再补一次。客机断线期间壁垒结束/清墙时 host 的 `_barricade_walls_cache` 为空；旧实现直接 `return`，客机会一直保留旧墙，因此空数据必须显式发 `_remote_barricade_stop`。客机 `_finish_reconnect` 先清 mirror，随后由 host 的 `_remote_barricade_walls` 全量重建或 `_remote_barricade_stop` 保持清空；两条路径都幂等，不需要迁移 per-peer 壁垒状态。实测：双进程 dev battle（host `--coop-devbarricade`、client `--coop-devbarricade --coop-devdrop=2`）host `cells=324`，客机重连后再打印 `cells=324`；`run_coop_recovery_checks.py --cases rejoin3` 为 PASS。
- Source / 来源: code + test
- Date / 日期: 2026-11-07

### [Field/Item] 医疗包随机 tile 可能是壁垒格；`MapBounds.nearest_inside()` 只管外边界
- Evidence / 证据: `scenes/manager/pick_item_manager.gd:51-70`（旧随机 `tilemap.get_used_cells(0)` 无墙检查，`randi_range(0, cells.size()) - 1` 还会取到 `-1`）；`script/enemy_nav_field.gd:1450-1479`（`is_solid`/`nearest_body_safe_point`）；`scenes/field_mods/barricade.gd:714-730`（客机镜像只重建 overlay）。
- Notes / 说明: 医疗包刷新取的是 `SpawnMap` 地面格，壁垒/地形词条可以在同一格放墙；`MapBounds.nearest_inside()` 只按外边界内缩，不能把内部墙格拉出来。修法：`EnemyNavField.safe_pickup_point()` 用 `is_solid()` 判墙并回退 `nearest_body_safe_point()`；`PickItemManager` 随机/玩家脚下、联机 host `_spawn_medkit_networked()` 都走它，找不到安全点就跳过生成。另加 `MapBounds` 1s 卡墙兜底：`HealthItem`/玩家/敌人/召唤物/Boss 中心格 solid 时复用 `_pull_lock` 拉到最近 body-safe 点；只认 `is_solid`，贴墙不误拉。客户端镜像 `apply_network_walls()` 后必须 `EnemyNavField.invalidate()`，否则仍用旧阻挡集。实测 `[MEDKIT_WALL_CHECK] ok=1 fail=0`（墙格生成被挪出、假 `HealthItem` 一次拉出、第二次不回弹）。
- Source / 来源: code + test
- Date / 日期: 2026-11-07

### [Tooling] `res://` 下的第三方参考源码必须带 `.gdignore`，否则会被导入
- Evidence / 证据: `third_party/.gdignore`（空文件）；同惯例 `mod_sdk/.gdignore`、`android/build/.gdignore`；`third_party/pixelfx-godot/godot/addons/pixelfx` 含 581 个脚本。
- Notes / 说明: Godot 扫描 `res://` 下所有目录，第三方源码会被导入并注册其 `class_name`（如 `PixelFx2D`/`PixelFxAct2D`），与本体命名空间冲突且拖慢首启。空文件 `.gdignore` 要放在**目标目录本身**（不是子目录）才能整棵跳过；校验方式是编辑器里搜 `res://third_party` 应返回空。被跳过的目录也不进导包。
- Source / 来源: code
- Date / 日期: 2026-11-07

### [Tooling] pixelfx 按 id 播放时路径硬编码为 `res://addons/pixelfx/...`
- Evidence / 证据: `third_party/pixelfx-godot/godot/addons/pixelfx/nodes/pixel_fx_2d.gd:25,148-156`（`REGISTRY_PATH`、`_resolve()`）；`pixel_fx_act_2d.gd:16,58-59,81`。
- Notes / 说明: 放在别的目录不报错，只会静默不播（`_mod == null` 直接返回），排查很费时。要么保持 `addons/pixelfx` 目录名，要么用 `effect_script`（脚本优先于 id），要么只拷 `core`/`nodes`/`bake` 自建。详见 `docs/REFERENCE_PIXELFX.md` §9。
- Source / 来源: code
- Date / 日期: 2026-11-07

### [FX] pixelfx 的美术基准是 24×38 角色，ENN 是 64×64，照抄像素会偏小偏密
- Evidence / 证据: `third_party/pixelfx-godot/godot/docs/AUTHORING.md:76`（"The stock character is 24 x 38 px"）；`scenes/player/kotori/kotori.tscn` 帧 `region = Rect2(x,y,64,64)`；`sprites/tile_map/tile_map.png` 64×64；`sprites/enemies/droid_helmet.png` 512×192 + `hframes = 8`（Camera2D 无 zoom，640×360 下世界像素 = 屏幕像素）。
- Notes / 说明: 库里为 1px 细节、24×38 角色画的配方，贴到 64px 角色旁会读成噪点。复用时应按其相位/光逻辑**按 ENN 尺度重画**（线宽、光半径约 2–3 px）；要整包套用只能整数缩放 `PixelFx2D.scale = 2`（角色约 48×76，仍略小），非整数缩放会破坏像素锐利。全屏类（`transitions`/`weather`，320×180）在 640×360 下是半屏。
- Source / 来源: code
- Date / 日期: 2026-11-07

### [FX] pixelfx BAKED 帧缓存吃内存，单个大特效可达数十 MB
- Evidence / 证据: `third_party/pixelfx-godot/godot/addons/pixelfx/bake/baker.gd`（`Track.frames` 每帧 3 张 `Image`，`Track.textures` 每帧最多 3 张 `ImageTexture`）；`nodes/pixel_fx_2d.gd` 的 `static var _cache`（仅 `tree_exiting` 时清空）。
- Notes / 说明: 288×192 画布 ≈ 221 KB/张 → 约 1.3 MB/帧，`ice/frost-nova`（103 帧）跑一轮 ≈ 66 MB，且不会自动回收。移动端优先烘焙成 `SpriteFrames`（落磁盘），或在切场景/回合结束时调 `PixelFx2D.clear_cache()`；LIVE 则是每帧 CPU 成本（README 口径 0.2–20 ms，需 `pfx bench` 实测）。
- Source / 来源: code
- Date / 日期: 2026-11-07

### [FX] 范围提示的三条硬约束：半径=判定、形状=判定、层级在地面
- Evidence / 证据: `scenes/update_item/cathedral_candle.tscn`（`Area2D` + `CircleShape2D.radius = 85`）与 `scenes/effects/cathedral_candle_aura.tscn`（`z_index = 1`、shader `radius_px = 85.0`）；Y 排序见 `scenes/main/main.tscn:241-247`（`FloorLayer`/`YSort` 同级、`PlayerRoot` 在 `YSort` 下），玩家精灵 `z_index = 20`（`scenes/player/kotori/kotori.tscn:449`），子弹 `z_index = 2/3`。
- Notes / 说明: ①**半径要对齐**：旧蜡烛的可视光斑只有 ~32px 与 103px 两个，和 85 的判定半径都不一致，玩家读不出"近身"边界；②**形状要对齐**：判定是 `CircleShape2D`，视觉必须各向同性正圆，用像素空间 `length()` 而不是侧视库的 `SY` 椭圆压扁；③**层级要在地面**：`z_index = -1` 会被 `FloorLayer`（z 0）盖住而完全看不见，应该取 1——高于地面、低于玩家(20)与子弹(2,3)。判定与视觉的半径/形状/层级三者任一错位，"范围提示"就失效。
- Source / 来源: code
- Date / 日期: 2026-11-07

- Follow-up / 后续（2026-11-07，来源：code）：观感最终按原版 `holy/heal-aoe` 重做，但**没有引入 pixelfx 运行时**——环走 shader（`shaders/cathedral_candle_aura.gdshader`：颗粒环 + 光刃 + 8 向光晕 + 呼吸，几何仍是 `length()` 正圆），"+" 用预渲染 glyph + 加法材质的 `_draw`（`scenes/effects/cathedral_candle_aura.gd`）。原版的中心光柱与"种子→滚出"一次性相位按要求去掉，环改为常驻呼吸，符号分「常态 5px 小号 / 治疗 5·7·9px 成簇」两档。原因：`core/` 是逐像素 CPU 绘制，常驻光环跑 LIVE 太重、BAKED 又要 ~36MB 帧缓存。对照工程在 `third_party/_heal_aoe_demo`（独立项目，ENN 不扫描）。
- SUPERSEDED: 2026-11-07 上面这条"不引入 pixelfx 运行时"的决定已被推翻——按用户要求直接搬原版。最终形态：`addons/pixelfx/{core,nodes,bake,fx/holy/_lib.gd}` 进项目，`scenes/effects/pixelfx_heal_ring.gd` 是 `holy/heal-aoe` 的 fork（只改 ①`SY 0.2→1.0` ②画布 256×264/origin[128,128] ③删中心光柱）。实测 LIVE `update+draw` = **58.6ms/帧**（256×264 逐像素 wash），常驻光环不可用，于是**烘焙成 SpriteFrames**：`scenes/effects/heal_ring_frames.res`（88 帧 / 30fps / 1.1MB，`combined` 模式，光烘进 alpha），运行时由 `AnimatedSprite2D` 播放（`pixel_fx_sheet.gd`，0.4s 后循环、回血时 `play()` 重播），CPU 成本≈0。**注意**：`light` 缓冲单独成图集没有意义（实测 alpha≈84/255 而 rgb≈6/255，加法混合几乎不可见），只能用 `combined`；代价是辉光比 LIVE 略柔。旧 shader 版 `cathedral_candle_aura.*` 当时保留未删；2026-11-07 清理时已确认无引用并删除（历史见本节与 git）。来源：code。
- Follow-up / 后续（2026-11-07，来源：code）：按观感反馈又改一版——**环与"+"拆成两套烘焙**：`pixelfx_heal_ring.gd`（只画环，GOLD 调色，208×208，2.0s@45fps=90 帧（loop=true））与 `pixelfx_heal_plus.gd`（单符号 0.6s@45fps=28 帧）。环用**两个** `AnimatedSprite2D` 错相 1.0s 循环（恒有 2 环交叠，第二个环在第一个淡完前滚出）；"+" 由 `heal_plus_spawner.gd` 在**世界坐标**生成（`top_level = true`），常态只冒小号、回血 `burst()` 才冒大号——因此符号不再跟随玩家。显存：90×208×208×4 ≈ **15.6MB**（此前的 30fps/256×264 是 23.8MB）。实测 LIVE `update+draw` 仍是 58.6ms/帧，所以运行时只播帧、不跑效果代码。后续清理：删掉旧 shader 版与未使用的 `addons/pixelfx/nodes/`；符号改**对象池**（预热 18 个，播完归还、正常流程零分配零释放）；烘焙脚本入库为 `script/bake_pixelfx_fx.gd`（后续又扩成通用入口）；环的循环标志改由 `meta.loop=true` 落进 `.res`，运行时不再改资源。
- Follow-up / 后续（2026-11-07，来源：code）：按"中毒"的观感补**腐化**视觉。①敌人：`scenes/effects/pixelfx_corruption_aura.gd` 只取 `status/poisoned` 的毒汗/气泡/光晕（去掉 0.8s 地面脉冲环，也不重绘身体——身体已有 tint），45fps/72 帧，由 `scenes/debuff/corruption_aura.tscn` 跟随目标播放，`corruption_field_component.gd` 在 `_apply_tint()` 后生成、`deactivate()/_on_dead()` 释放（远端镜像 `_remote_visual_only` 跳过）。②残留地坑：新增 `pixelfx_corruption_bubbles.gd`（45fps/108 帧/116×116），每个泡泡在自己的循环开始时按**圆盘均匀采样**取点（`r = min(R_MAX*sqrt(rand), R_MAX-rmax-2)`，R_MAX=36），替换原来那路 GPU `Bubbles` 粒子；烘焙脚本对两份资源做**逐帧不透明包围盒断言**（aura ≤70、bubbles ≤112），保证不裁切。显存 +≈7.3MB，运行时仍零 CPU。
- Follow-up / 后续（2026-11-07，来源：user + code）：实机发现光环整体沉在敌人脚下——ENN 的敌人 body 原点**就是脚底**（如 `droid_helmet_smg.tscn`：sprite 在 `(0,-24)`、capsule 在 `(0,-27)`），而代码里写了固定的 `FEET_OFFSET (0,20)`。修法：改用 `HurtBoxMeasure.measure(body, 48)` 取 hurtbox 的本地 `center/size`，脚底 = `center + (0, size.y/2)`，`global_position = body.to_global(feet)`；缩放 = `clamp(size.y/36, 0.9, 1.8)`（36 是效果虚拟身体高）。同时把躯干那层不透明 `glow` 去掉，只留脚边地面光晕，避免烘焙后的 combined alpha 盖住敌人贴图。地坑气泡按用户要求：半径 6–8 → 3–4、数量 8 → 14、整体 `modulate.a = 0.65`。 另外发现多池叠加时后画的池面会盖住先前池的气泡：把 `corruption_field.tscn` 根节点 z 从 -1 改为 0（参与 Y 排序），`PaintBase` 单独设 -1（池面观感不变），`Bubbles` 为 0 —— 所有气泡统一在池面之上、按池的 y 与敌人排序，多池时气泡自然累积。

### [PS] 一次性 proc 的子弹：先校验后记账 + meta 字典按目标去重（Maki 异常附带次数）
- Evidence / 证据: `scenes/player/maki/maki_ps.gd`（`_on_player_shot` 的 `_clear_anomaly_marks` 与 `maki_anomaly_limit`；`_on_bullet_hit_enemy` 的校验顺序、`maki_anomaly_hits` 字典、`ANOMALY_TRIGGERS = [1,4,7,10]`）；`script/player_bullet.gd:83-101`（`player_bullet_hit_enemy` 由 `on_damage_dealt` 发射，自管理命中按 0.1s 重击）。
- Notes / 说明: 一次性 proc（子弹附带元素/印记）**不要在回调入口就消费标记**：`on_damage_dealt` 在扣血之后回调，`victim` 可能已被子弹自身打死、或不在 `Enemy` 组、或缺 `enemy_buff_manager`/`health_component`，先消费会把这一发的 proc 白白吞掉（后续穿透目标也拿不到）；应「先校验、全部通过后记账并结算」。同一发子弹想对多个目标各生效一次时，不能只看「有没有标记」——`HitBox.rehit_interval_seconds=0.1` 会对同一目标反复回调，必须用 `instance_id` 字典去重；次数上限在**开火时**按等级快照写进 meta（升级只影响之后发射的子弹），无效目标不消耗次数、同一敌人不重复消耗。探针 `tests/maki_passive_probe.gd` 覆盖：上限 3 时 3 个不同沙袋各触发一次、第 4 个不触发、同一目标重复命中不重复结算、无效目标不消耗次数。
- Source / 来源: code + test
- Date / 日期: 2026-11-07

### [Tooling] MCP `filesystem_manage(reimport)` 对 CSV 本地化可能不生效，要再 `scan`
- Evidence / 证据: 改 `ETN_player_localization.csv` 后 `filesystem_manage(op="reimport", paths=["res://ETN_player_localization.csv"])` 回包 `reimported`，但 `ETN_player_localization.*.translation` 与 `.godot/imported/ETN_player_localization.csv-*.md5` 的 mtime/体积均未变化（游戏内 `tr()` 仍是旧文案）；补一次 `filesystem_manage(op="scan")` 后 4 个 `.translation` 立即按新 CSV 重新生成（mtime 更新、体积变大）。
- Notes / 说明: 改本地化 CSV 后判定「真的生效」要看两处时间戳/体积：`ETN_*localization.<locale>.translation` 与 `.godot/imported/<csv>-<hash>.md5`；只看 MCP 的 reimport 回包会误判。稳妥流程：`reimport` → `scan` → 核对 `.translation` 已更新 → 需要时 headless 起一次游戏用 `tr()` 抽查。`tests/check_localization.py` 只校验源 CSV 格式（BOM/CRLF/列宽/key 唯一），**不检查是否已重新导入**。
- Source / 来源: code + test
- Date / 日期: 2026-11-07
- Follow-up / 后续（2026-11-07，来源：user + code）：狂怒词条（`chip_frenzy`）的敌人特效从"地面光环 shader + 两路 GPU 粒子"换成参考库 `status/rage` 的身体特效：怒气符号（7/9px 两档随心跳切换）、头部蒸汽、拍点应力线、常驻余烬、头部红光；按需求**去掉**地面热光与裂纹，也不重绘身体（无 actor）。图集 1.2s/45fps/80×80 单层烘焙（`frenzy_aura_frames.res`），运行时 `AnimatedSprite2D` 循环播放。锚点沿用 `HurtBoxMeasure`：脚底 = center + size.y/2，缩放 = size.y/36（夹 0.8–2.0）。烘焙脚本新增**空白帧断言**（每帧必须有像素）。`BurnBar` 与濒死延迟接口（`fit_to_enemy/begin_burn/set_burn_progress/flash_blocked/finish_burn`）未改。

### [Combat] 异常伤害暴击统一到 `HealthComponent._resolve_damage`（被动 meta 门控 + 排除复合标签）
- Evidence / 证据: `script/anomaly_damage.gd`（`META_PASSIVE`/`is_anomaly_damage`/`can_roll`/`roll_crit`）；`script/health_component.gd::_resolve_damage` 末尾调用 `_apply_anomaly_crit`；`scenes/player/maki/maki_ps.gd:_ready`（本地写 meta）与 `_on_bullet_hit_enemy`（不再自行掷暴击）；`script/fire_field_base.gd`、`script/fire_damage.gd`、`scenes/update_item/kikyou_doll.gd` 的纯元素伤害均走同一结算口。
- Notes / 说明: 「所有异常类伤害可暴击」逐个来源改会漏掉火场/火伤圈/毒环，且共享 `DamageData` 的复位要各写一遍；集中到 `_resolve_damage` 的最终数值口一处即可。关键点：① 用「排除 BULLET/MELEE/EXPLOSION/CRIT 复合标签」判定纯异常，避免子弹/近战/爆炸/策反（它们会带元素标签且已各自掷骰）被二次掷骰；② 门控用「本机玩家节点 meta」而不是 buff 白名单，才能覆盖所有来源、天然不跨端/不误伤其它角色（MakiPS 在本地 `_ready` 置位，镜像 PS 被本地守卫挡住）；③ 火场/毒环的 `hit_box.damage_data` 会跨目标、跨 tick 复用，`is_crit` 会残留——每次结算先复位再掷，否则会出现「显示暴击色但没乘倍率」或一次暴击后整场都暴击；④ 真伤（火场 `TRUE_DAMAGE`）同样经过该口，暴击乘在最终 result 上；⑤ 被动关（其它角色/镜像）时 `can_roll` 直接 false，零行为变化。联机：客机预测在本地掷、host 收 `resolved_damage` 不重复掷；host 为客机 Maki 结算 DOT 时用 host 本机玩家数据（已知限制）。探针 `tests/maki_passive_probe.gd` 覆盖：非 `maki_ps` 来源 DOT 可暴击、移除 meta 后不暴击、纯火直伤可暴击、子弹复合伤害不重复掷、恶寒反击可暴击。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-07
- 2026-11-07（来源：code）：把 pixelfx 制作管线沉淀成 3 个 DSH skill，放在工作区 `.agents/skills/`（DSH 会扫 `<cwd>/.agents/skills` 与全局 `~/.agents/skills`，加完即时出现在 skill 目录，无需改 `skills-lock.json`——那个只登记 GitHub 来源）。分工：`pixelfx-effect-authoring` = 怎么干（fork→适配→烘焙→接入→验证 + 坑表 + 5 个配方），`pixelfx-catalog` = 挑蓝本（244 效果分类/标签/27 调色板/许可/质量条），`godot-baked-vfx` = 运行时通用（SpriteFrames 契约、池化、跟随、`HurtBoxMeasure` 锚点、z 分层、显存预算）。原则：`docs/` 讲"是什么/为什么"，skill 讲"怎么干"，改管线时两边同步；244 个效果不拆成一效一 skill（描述常驻上下文，会污染选型）。
### [FX] 烘焙特效实测：50 敌人双光环 < 0.2ms，瓶颈不在特效本身
- Evidence / 证据: 临时探针 `tests/_tmp_perf_probe.gd`（不进库）在 640×360、vsync 关闭、`Engine.max_fps=0` 下采样 2s：空场景基线 2673–2805fps（≈0.36ms/帧）。`corruption_aura` 50 个 → 2612fps（0.383ms，增量≈0.005ms）；`frenzy_effect` 50 个，改前 1315fps（0.760ms，增量 0.403ms）→ 改成"每帧只跟随位置、0.25s 或缩放变化才 measure"后 2245fps（0.445ms，增量 0.088ms，−78%）；`corruption_field` 50 个 → 1718fps（+0.206ms，含旧 `PaintBase` 粒子）；治疗环 40 个 `AnimatedSprite2D`（20 组）→ 2460fps（+0.048ms）。锚点缓存与现场 `HurtBoxMeasure` 结果完全一致（`pos`/`scale` 全等）。
- Notes / 说明: 烘焙特效运行时是纯播帧，成本 = draw call + 填充率，不是脚本；`frenzy_effect` 原来每帧每敌人一次 measure + 两次 `set_shader_parameter`（`bar_size_px` 每帧写）是纯浪费，现已缓存，`_sync_bar_shader_size` 只在 `resized` 信号里调。`Performance.RENDER_VIDEO_MEM_USED` 对 `PortableCompressedTexture2D` 不精确（加载五个资源只 +4MB），VRAM 以 RGBA8 上界估：治疗环 90×208²×4≈15.6MB、腐化冒泡 108×116²×4≈5.8MB、其余 ≈3MB，合计 ≈24.9MB（共享资源，一次占用）。60fps（16.7ms）预算下最坏场景（50 敌人双光环 + 10 池 + 2 环）合计 <0.3ms，**结论：当前不需要为特效做额外优化**。尚未做的可选项：治疗环画布 208→196（省约 1MB，同时要改 `pixel_fx_sheet.gd` 的 `RING_ORIGIN`）、>60 敌人时再考虑把帧打包成图集合批。旧 `PaintBase` 池面（每池 12 粒子 × 最大 3.5² 缩放）是填充率最大项，属既有实现，未在本次范围。
- Source / 来源: test
- Date / 日期: 2026-11-07

### [Chip/Perf] 「亚子策反敌人进腐化池卡顿」：不是状态冲突死循环，成本在池数量×填充率与逐感染节点
- Evidence / 证据: 引擎内实测（Godot 4.7 + `test_room` + `game_eval`，桌面）：池子单 tick 3–5µs；一次 tick 感染 30 个敌人 506µs（节点每感染约 +7：buff 卡 + 光环）；**策反单位站进活跃池 `infected.size()==0`、`converted_infected==0`**（`scenes/debuff/corruption_field.gd:_infect_enemies()` 的 `Faction.of_entity != ENEMY_SIDE` 过滤生效）；单次策反约 516µs；30 个感染光环 + 61 个活跃池 + 30 敌人仍 60fps / 16.4ms（draw call 213→340）。回合清场走 `scenes/main/main.gd:enemy_clear_unit()` 的 `queue_free()`，不触发组件 `deactivate()`。
- Notes / 说明: **结论**：不存在「策反 × 腐化池」的逻辑级热点或死循环，池子连 Buff 都不会给策反单位，所以玩家侧「状态冲突」的直觉在逻辑层不成立；真正会随「腐化残留 + 亚子」放大的是 ①池子数量（感染→死亡→再留池，旧上限 100，同一点可叠十几个重叠池）、②单池填充率（`PaintBase` 12 粒子 × 最大 3.5² 缩放，文档已记为最大填充率项）、③每次感染的节点/材质开销。桌面有富余，风险面在中低端 Android/iOS，所以修复方向是**削峰**而不是找循环。本次落地：池并发上限 100→24；同点 24px 内只 `refresh_field()` 续命（不新开池、不重播整池）；感染窗口 10→12 tick 且**每 tick 最多新感染 6 个**（把 32 连击的 ~12ms 尖峰摊到多帧）；生命末 15 tick 淡出；`_infect_enemies()` 每 tick 剪掉失效节点并把**策反中的目标从 `infected` 剔除**（旧实现会让「已感染」永久留在表里，解除策反后再也不上 Buff——这是真实的跨状态不同步）；组件 `_exit_tree()` 兜底释放光环、光环发现 `target` 失效即 `queue_free()`（旧实现只隐藏，孤儿节点跨回合累积）；染色材质 `duplicate(true)`→`duplicate(false)`（深拷贝会连 `Shader` 一起复制）；`_clear_tint()` 先复位 `corruption_tint/corruption_amount` 再换回原材质（策反描边写同一材质，旧顺序会把残留染色压在描边上）。**故意外光环跟随仍按物理帧、不做 10Hz 节流**：敌人 60fps 移动，10Hz 跟随会肉眼脱节；改为「位置每帧写、scale 仅变化时写」即可。验证用本地探针 `tests/_tmp_corruption_pool_check.gd`（不入库，14 项全 PASS，含单 tick 感染=6、24 池上限、合并续命、淡出复位、策反剔除/解除后重感染、光环随 queue_free 释放）。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-07
- 2026-11-08（来源：user + code）：Serina EX 视觉重做（`serina_as.tscn`）：弃用 `shock_wave_2` 双环 + 粉色粒子 + AnimationPlayer，改成 5 张烘焙图集（小光环 90 帧/爆发 42/光尘 32/入场光柱 26/退场光柱 21）由 `scenes/effects/serina_aura.gd` 编排。坐标约定：光环跟玩家（`Aura.top_level` + 每帧 `global_position`）；光尘/“+”/入退场光柱**世界坐标**（`top_level` 精灵或池），播完留原地；`heal_tick()` 每次回血发一个上浮“+”。踩坑：① `Painter.put/dot` 在 alpha<1 时走 4×4 Bayer 抖动，**1px 光柱/细环用 dot 会碎成网点/棋盘**——改为 `p.px` + 调色板降级（`C[6]→C[4]→C[2]`）表达明暗，只有辉光用 `p.glow`；② 环形采样必须 `int(ceil(TAU*r))*2`（间距 ≤0.5px），否则虚线；③ 一次性效果的烘焙断言放宽为"首尾可空、中间不许断片"（`bake_pixelfx_fx.gd` 的 `ONESHOT` 集合）。
- 2026-11-08（来源：user）：Serina EX 二次调整——① 回血符号从“+”换成 `holy/heal` 的「光点螺旋上升 → 顶端绽成小心形」，3× 位图（15×12）才在 64px 角色旁读得出来，心形/光点必须用 `p.px`（alpha 抖动会碎）；② 入/退场光束改用 `holy/heal-aoe` 的 `p.beam()` 写法，向上 190px（原 140），粉色；③ `serina_burst` 画布 `96×96` 的 origin 从 `(48,72)` 改 **`(48,48)`**——原来下方只有 24px，环扩到 r=40 时底部被裁，居中后完整；环体同时加粗到 2px（`r` 与 `r-0.8` 各画一像素）。
- 2026-11-08（来源：user）：Serina EX 三改——① 去掉退场光束（`BeamOut` 连同图集/脚本/烘焙项一并删除），改为**结束倒放 burst 环**；注意 burst 末尾 10 帧是淡出空帧，`play_backwards` 必须先从最后有内容的帧（第 31 帧）`set_frame` 再播，否则前 0.2s 什么也看不到。② 回血特效改为 `holy/heal` 的 `riders` 光点螺旋（7 点拖尾 + 轨道），按用户要求**去掉光瓣/光圈/心形**，只留螺旋；`pixelfx_serina_heal.gd` 80×104 / 1.6s / 73 帧。③ 回血特效不再世界坐标，`heal_spawner.spawn()` 直接 `reparent` 到 `group("Player")` 的玩家节点下（`top_level=false`），随玩家移动；池 3，`stop()` 清空。
- 2026-11-08（来源：user）：① 结束倒放的环“不在脚下”：`Burst` 是 `top_level` 世界坐标精灵，位置只在激活时设过一次；8 秒里玩家会走开，`stop()` 必须先 `_burst.global_position = global_position`（Aura 每帧跟随玩家）再倒放。② 脚下光环加“扩散收缩呼吸”：半径 `roundf(15 + 2*sin(t/D*TAU))` → 在 13↔17 之间**按整数像素跳变**（不缩放、不插值），另加半径 `rr-3` 的内环与扩张段的 `rr+2` 稀疏回声环；这比节点缩放更有像素感。
- 2026-11-08（来源：code）：Serina EX 显存/结构优化。① 画布按内容 bbox 收紧：halo 64²→56²、dust 40²→32²、beam 56×260→44×240、heal 80×104→48×72；烘焙新增 `_trim_tail()` 裁掉一次性效果末尾全空帧（burst 42→32、beam 26→25、heal 73→62、dust 不变）。5 张图集合计 7.16MB → **4.35MB（−39%）**，45fps 不变；`BBOX_LIMIT` 与场景/生成器 offset 同步，bbox 断言全过。② 结构：新增共用池 `scenes/effects/pooled_sprite_spawner.gd`（`frames/origin/scale/pool_cap/attach_to_target` + `spawn/clear/set_target`），`mote_spawner`/`heal_spawner` 变薄；`heal` 的整池在 `set_target()` 时一次性 `reparent` 到玩家（热路径不再做树操作）；`serina_aura` 去掉 `has_method` 鸭子调用与 `BURST_LAST_VISIBLE` 魔数（裁尾后倒放直接从头播）。

### [Buff] `apply_buff` 只刷新时长、不更新已有条目的 `value` → 升级换每层值必须清标记重上
- Evidence / 证据: `scenes/manager/buff_manager_base.gd:apply_buff`（已有条目：`entry["now_time"] = 0` 后若 `entry["layer"] >= entry["max_layer"]` 直接 return，不写 `entry["value"]`）；`scenes/player/maki/maki_ps.gd:_clear_paint_marks` 在 `ps_upgrade` 时对场上带标记敌人 `remove_buff`。
- Notes / 说明: 标记类 buff 的每层数值随 PS 升级变化时（Maki 颜料标记 T1 10%/层 → T2 20%/层），**只靠再次 `apply_buff` 不会更新已存在条目的 `value`**，旧层会一直按旧值算；要么在升级时清掉重上（本项目选用，升级发生在轮间商店，清层可接受），要么直接改 `entry["value"]` 并手动补 `host` 属性差（不推荐，绕过 manager 封装）。
- Source / 来源: code
- Date / 日期: 2026-11-08

### [Buff] `Buff.ability` 是宿主属性的直接字段名，不走 `BuffStatMap`
- Evidence / 证据: `scenes/manager/buff_manager_base.gd:_apply_ability`（`host.set(resource.ability, host.get(resource.ability) + entry["value"] * layers)`）；`resources/buff/enemy_buff/maki_paint_mark.tres`（`ability = "anomaly_hurt_damage_mult"`）与 `script/EnemyStats.gd` 新字段；`_apply_modifiers` 才走 `BuffStatMap`。
- Notes / 说明: 想给敌人加一个新的乘区（如「异常伤害易伤」），只要在 `EnemyStats` 加同名字段、buff 的 `ability` 填字段名即可，**不需要**改 `BuffStatMap`（那是 `modifiers` 的 key→字段映射）；读取点自行决定在 `update_body_ability`（折叠）还是结算时直接读（本项目异常易伤在 `HealthComponent._apply_anomaly_vulnerability` 直接读，避免影响真伤/护盾折叠）。
- Source / 来源: code
- Date / 日期: 2026-11-08

### [PS] 充能统计挂 `enemy_damage_taken`：DOT 跳伤/火场/毒环都会计入
- Evidence / 证据: `scenes/player/maki/maki_ps.gd:_on_enemy_damage_taken`（`AnomalyDamage.is_anomaly_damage(data)` + `Faction.of_source(source_type)==PLAYER_SIDE` → `_energy += 1`）；`script/health_component.gd:_resolve_damage` 的 `emit_enemy_damage_taken`。
- Notes / 说明: Maki 彩弹按「每次玩家侧异常伤害 +1 能量」充能，因此燃烧/中毒 DOT 每跳、火场/毒环、自身异常直伤都会计入；若后续只想统计自身 proc，改过滤条件为 `source_type.has(GameTags.PS_DAMAGE)` 即可（一行）。**投掷不要放在该信号回调里**：它发生在 `take_damage` 结算内部，嵌套 `apply_buff` 容易在属性重算中途改敌人属性；本实现只累加能量，投掷统一放到 10Hz `global_time_count`。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-08

### [Damage] 异常易伤在 `HealthComponent` 结算口读取，真伤也吃；常驻标记靠 `clear_all_buff` 回滚
- Evidence / 证据: `script/health_component.gd:_apply_anomaly_vulnerability`（`AnomalyDamage.is_anomaly_damage` 才乘 `stats.anomaly_hurt_damage_mult`，位于 `_apply_anomaly_crit` 之前）；`script/entity_ENEMY.gd:idle_state`（`clear_all_buff()`）→ `BuffManagerBase._remove_ability` 回滚 `anomaly_hurt_damage_mult` / `global_hurt_damage_mult`。
- Notes / 说明: 异常易伤乘区对 `TRUE_DAMAGE`（火场）也生效（因为不看 `is_true`），而 T3 的全局易伤走 `global_hurt_damage`，按既有语义**不作用于真伤**——两者语义不同，文档/卡面要写清。标记设计为常驻（`value[2]=9999.0`，每次投掷刷新）时，务必确认敌人回池走 `clear_all_buff()`，否则 999 层的属性会留在池化敌人身上泄漏到下一波。
- Source / 来源: code + test
- Date / 日期: 2026-11-08

### [Buff] 同 id 的多个 Buff 资源按 tier 切换：单一条目/单张卡承载两套效果
- Evidence / 证据: `resources/buff/enemy_buff/maki_paint_mark.tres`（T1/T2，仅 `ability=anomaly_hurt_damage_mult`）与 `maki_paint_mark_t3.tres`（T3，**同 `id="maki_paint_mark"`**，额外 `modifiers=[{"key":"hurt_mult_mult","source":"const","amount":0.1}]`）；`scenes/player/maki/maki_ps.gd:_throw_paintball`（按 `_tier()` 选 `mark_res`）；`scenes/manager/buff_manager_base.gd:_apply_modifiers`（`source:"const"` → `amount × layers`，字段由 `BuffStatMap` 解析到 `global_hurt_damage_mult`）。
- Notes / 说明: 想给同一个 debuff 在更高等级加「额外属性」又不想多一个 buff 图标时，可准备**同 id 的多个 Buff 资源**，由施加方按等级选择：`apply_buff` 用资源建条目、之后按 id 复用/移除，卡面与层数只有一份。三个前提：① `apply_buff` 在已有条目上**不会替换** `entry["resource"]`，升级时必须先清旧标记（`_clear_paint_marks`），否则会继续用旧档位资源；② `modifiers` 的 `source` 只有 `"value"` 取 `entry["value"]`，其余（如 `"const"`）按 `amount` 且会 `× layers`，正好表达「每层 X%」；③ 联机 `enemy_buff_apply_gate` 转发的是 `buff.resource_path`，host 会 `load` 到同档资源，变体不需要额外协议。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-08

### [FX] 飞行类烘焙特效：单发蓝本 + 运行时旋转/位移，颜色用多套 palette 分别烘焙
- Evidence / 证据: `scenes/effects/pixelfx_maki_paintball_bolt.gd` / `pixelfx_maki_paintball_pop.gd`（参考 `third_party/pixelfx-godot/godot/addons/pixelfx/fx/arcane/arcane-missiles.gd` 的单发弹头/尾带/爆点，MIT）；`scenes/effects/maki_paintball_fx.gd`（`active_state(from,to,color)`：`rotation=(to-from).angle()`、`offset=-origin`、tween 位置，到达后换 pop 帧再回池）；`script/bake_pixelfx_fx.gd` 的 `MAKI_PAINT_RAMPS` 三色循环 bake。
- Notes / 说明: ① 参考库的整段 1.75s 五连发/锁定括号/施法者身体不适合本作短途投掷——**只取单发弹体**（弹头 + 扭尾 + pop），飞行/朝向/落点交给运行时节点，烘焙产物小、可复用。② AnimatedSprite2D 用 `centered=false` + `offset = -meta.origin`，把 **origin 对齐到节点位置**，再旋转节点，弹头就不会绕圈；飞行段与 pop 段 origin 不同，切换时同时改 `offset` + `sprite_frames`。③ 随机颜色不要用 `modulate` 染单套烘焙帧（白核会被一起染色、失去亮度层次）；本项目改为**同结构 3 套 palette 分别烘焙**，运行时按颜色索引选帧资源，且索引与 `floor_paint` 的 0=Pink/1=Blue/2=Yellow 对齐，落地颜料同色。④ 细长尾带用 `p.px` 实心绘制而不是带 alpha 的 `p.dot`（后者 4×4 Bayer 抖动会把细带打碎成网点）；尾带按 u 渐变色、避免逐列亮芯造成“梯子”分段。⑤ 一次性帧用 `_trim_tail` 裁尾，画布留 8px 边距避免 `edge_fade` 方框。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-08

### [FX] 抛射弹道与发射音效：贝塞尔 + `tween_method` + `speed_scale`，PS 内挂 `AudioStreamPlayer2D`
- Evidence / 证据: `scenes/effects/maki_paintball_fx.gd`（`active_state` 里 `fly_seconds=clampf(dist/900,0.32,0.55)`、`arc_height=clampf(dist*0.16,16,40)`、`mid=(from+to)/2+(0,-arc)`、`tween_method(_set_arc_t,0,1,fly)`、`rotation=tangent.angle()`、`sprite.speed_scale=(帧数/45)/fly_seconds`）；`scenes/player/maki/maki_ps.gd:_play_paintball_sound` 与 `_spawn_paint_splat`（落地 `SoundManager.play_sfx("ExplosionSounds")`）；`scenes/player/maki/maki_ps.tscn` 的 `PaintballSound`（`sounds/magic3.wav`，`process_mode=3`/`volume_db=6`/`bus=SFX`）。
- Notes / 说明: ① 抛物线直接对**节点 `global_position`** 用 `tween_method` 驱动二次贝塞尔，`rotation` 取切线角即可让弹头沿弧线抬头/俯冲；不要用 `tween_property(global_position)` 走直线。② 烘焙帧是固定 one-shot 时长的，慢速飞行不要重烘焙：用 `sprite.speed_scale = 动画时长 / fly_seconds` 把动画拉到整段飞行，到达时复位为 1 再播 pop。③ 时长/弧高按距离缩放（`clampf(dist/900,0.32,0.55)`、`clampf(dist*0.16,16,40)`），贴脸和远距离都自然；落地颜料/爆炸音都由 FX 的 `arrive_cb` 触发，PS 不再自己计时。④ 武器/技能音效直接给 PS 挂 `AudioStreamPlayer2D`（照抄对应 gun 的 `FireSounds` 设置：`process_mode=3`、音量、SFX 总线），投掷时 `pitch_scale=randf_range(0.9,1.1)` 再 `play()`；音效不受 `fx_allowed` 门控，关特效时仍会响。⑤ 复用全局爆炸音用 `SoundManager.play_sfx("ExplosionSounds")`（与 `explosion_damage.gd` 同一个播放器）：简单可靠，但会重启正在播的爆炸音；要“绝不打断”可改 `play_sfx_once`（代价是撞上其它爆炸时可能不响）。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-08

### [FX] 烘焙拖尾太死板 → 运行时像素飘带（轨迹点 + 1×1 `draw_rect` + `top_level`）
- Evidence / 证据: `scenes/effects/maki_paintball_trail.gd`（`_pos`/`_age` 平行 Packed 数组、`begin/push/finish/clear/point_count`、`_draw` 沿相邻点法线画 1px 像素带、`top_level`）；`scenes/effects/maki_paintball_fx.gd` 在 `_set_arc_t` 里 `trail.push(global_position)`、`_on_arrive` 里 `finish`、`idle_state` 里 `clear`；`scenes/effects/pixelfx_maki_paintball_bolt.gd` 已去掉尾带、只留弹头（`BBOX_LIMIT` 94→62）。
- Notes / 说明: 烘焙尾带随弹体刚性旋转，弧线飞行时不会弯曲，观感死板 → 拖尾改为运行时按**真实飞行轨迹**绘制：记录世界坐标点 + 年龄，`top_level` 脱离弹体变换；宽度 `4.6*k+1.0` 随年龄渐细、`sin(age*30+i*0.6)` 做横向扭转、三套 ramp 用亮色（`ramp[0]` 深色在深背景上会消失，尾端只用最暗一阶会断成虚线）；1×1 `draw_rect` 保持像素风，所有矩形在同一个 CanvasItem 内合批（实测整场 draw call 只 +1）；无点时 `set_process(false)`，空闲零开销。性能兜底顺序：2px 块绘制 → 缩短 `MAX_AGE`（0.24→0.18）→ 隔帧重绘（30Hz）→ 改成 `draw_colored_polygon` 单条网格飘带。**发光（2026-11-08）**：需要“微光”时给 Trail 挂 `CanvasItemMaterial`（`blend_mode=1`，ADD），颜色改半透明亮色（alpha 即强度：主体 0.38 / 外沿 0.22 / 头芯 0.80 / 尾端 0.26）；ADD 只做加法、永远不会把地面压暗，深色 `ramp[0]` 在 ADD 下等于无效而不是发黑——这同时解决了亮蓝地面上的“黑边/黑点”。亮背景要降 alpha（0.38/0.22 起步），否则泛白；暗背景预览会掩盖该问题，需用接近实机地面色验证。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-08

### [Pool] Maki 特效链池化优化：prewarm + 固定环形缓冲 + 到达回调
- Evidence / 证据: `scenes/manager/PoolManager.gd:prewarm`（`pool_total>0` 跳过、按 `layer_group` 挂载、`idle_state` 收尾）；`scenes/player/maki/maki_ps.gd:_ready` 三行预热（`maki_paintball` 2 / `anomaly_paint` 4 / `floor_paint` 2）；`scenes/effects/maki_paintball_trail.gd` 固定 `PackedVector2Array(64)`/`PackedFloat32Array(64)` + `_head/_count` 环形缓冲；`scenes/effects/maki_paintball_fx.gd:active_state(..., arrive_cb)` 与 `_on_arrive` 回调；`maki_ps._spawn_paintball_visual` 已删除延迟 Tween，改传 `_spawn_paint_splat.bind(center, color)`。
- Notes / 说明: ① “有池”不等于“不卡”：首次 `instantiate()` + `_ready()` 仍在战斗中发生，用 `prewarm` 在玩家 `_ready` 提前垫 2/4/2，并做幂等（池里已有节点就跳过），避免换角色/重建时越垫越多。② 高频轨迹历史不要用 `append`/`remove_at(0)`（会扩容/搬移），改固定长度环形缓冲，`Packed*Array` 只 `resize` 一次。③ 跨系统计时收口到效果自身：FX 到达时回调铺地面颜料，比 PS 另建 Tween 少一次分配，也不会出现“弹体被池回收但颜料照铺”。④ 明确不池化：`DamageData`（`_pending_extra` 同帧引用，共享槽位有别名风险）、Tween（一次性对象）、飘带的 `draw_rect` 命令（不是节点）。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-08

### [Shader] 竖向液体充能条：ColorRect + ShaderMaterial（方框 + 液面波动 + 三色循环）
- Evidence / 证据: `shaders/maki_paint_charge_bar.gdshader`（`fill` / `size_px` / `border_px`、`paint_cycle(TIME)` 三色分段 `mix`、`wave_amp/freq/speed`）；`scenes/player/maki/maki_ps.tscn` 的 `PaintEnergy`（ColorRect 16×24 + `ShaderMaterial`，`resource_local_to_scene = true`）；`scenes/player/maki/maki_ps.gd:_update_energy_bar()`（写 `fill` uniform）；写法仿 `scenes/debuff/frenzy_effect.tscn` 的 `BurnBar`。
- Notes / 说明: ① 竖向充能条不需要贴图：方框/内衬/液体全在 canvas_item shader 里按 `UV * size_px` 画，`fill` uniform 由脚本写；② 材质必须 `resource_local_to_scene = true`，否则联机镜像/多实例共享同一 ShaderMaterial，液面互相影响；③ 颜色周期用 `fract(TIME/period)*3` 分三段 `mix(a,b,c)`，`period` 做成 uniform；④ uniform 更新放在扣数值之后（`_tick_paintball` 先更新再扣会让条短暂停在满格）；⑤ **Godot shader 已内置 `TAU`**，不要再 `const float TAU = ...`，否则编译报 `Redefinition of 'TAU'`；⑥ 预览/截图是线性空间，颜色会比 sRGB 观感发暗，判断颜色时看渲染色相即可。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-08
- 2026-11-08（来源：user + code）：恶寒（chill）buff 的 tick 视觉从 `chill_dot.tscn`（PooledFollowFx + 蓝色 GPUParticles2D）换成参考库 `ice/freeze` 的冰晶段：`pixelfx_chill_frost.gd`（48×64 / 0.65s / 30 帧，45fps）——6 根棱柱贴身体生长、扫光、2 条裂纹、降级淡出；按用户要求**去掉地面霜**（不用 `freeze.gd` 的 `floorFrost`），并按 `HurtBoxMeasure` 脚底锚定 + `size.y/36` 缩放适配体型（0.8–2.0，measure 0.25s 缓存）。跟随节点 `scenes/debuff/chill_freeze_fx.tscn/.gd` 保持 `PoolManager.spawn_fx` 的 `is_idle/follow_body/play_anim/idle_state` 契约与池 key `"chill"`；`enemy_buff_manager` 只换 preload 一行，1s tick/层数/伤害逻辑未动。旧 `chill_dot.tscn/.gd` 已删除（buff 资源 id `chill_dot` 不变）。
- 2026-11-08（来源：user）：恶寒 tick 特效**重做 v2**——上一版用的是 `ice/freeze`（施法冰冻）做成了冰刺，与用户要的 `status/frozen`（状态冻结）完全不像。定稿方案：① 不画冰壳（bodyless 下任何实体壳都会盖住敌人贴图），改为在跟随节点里把敌人 `sprite_2d` 的 modulate 乘上 HDR `Color(1.9,2.15,2.6)` → 身体被“冻白/冻蓝”，`idle_state()` 时若 `enemy_buff_manager.current_buff` 里还有 `chill_dot` 就保留 tint（否则 1s tick 之间角色会闪回原色）；② 烘焙层只画**霜饰**：一圈向内爬的霜蕨（椭圆近似轮廓）、64 点稀疏霜斑、头顶积雪、下缘小冰锥（带滴水）、飘雪、1Hz 抖动，`56×80 / 0.95s / 43 帧`；③ 非等比缩放 `(size.x/24, size.y/36)` 适配宽体型。坑：`modulate` 是**乘算**，`<1` 的“冷色 tint”只会把贴图压暗（第一版就是这个问题），要提亮必须走 HDR `>1`；预览里的 mock 敌人需要真提供 `sprite_2d` 属性，否则 tint 静默不生效。
- 2026-11-08（来源：user）：恶寒 tick v3（按“上面下雪 / 身上冰晶闪烁 / 粒子左右抖动下坠”收敛）：去掉霜蕨、霜斑、积雪、冰锥、实体冰壳，只保留 ① 落雪（14 片 1px + 柔光，y -46→+6，左右摆）② 身体 5 个固定点亮斑（最亮一瞬才出 4 向 1px 十字，`Px.sparkle` 尺寸别 >2px，否则像白花）③ 7 颗碎晶先 `sin(age*40)` 左右抖 0.12s 再 `g=320` 下坠淡出。身体冻白仍用跟随节点的 HDR `modulate`（`Color(1.55,1.7,1.95)`，`idle` 时按 `current_buff` 决定是否保留）。画布 56×80、43 帧、45fps。
- 2026-11-08（来源：user）：恶寒 tick v4：① 左右抖落改成**一次向两侧爆开**再抛物线（`t0=0.14`、`vx=±(55..85)`、`g=300`），不再是持续 sin 抖；② 细雪向中间收窄（`x *= 1-0.55u`）；③ 底部另起一组垂直慢落粒子（`vy=25..45`，与左右爆开分开画）；④ 新增吐息白雾 `chill_mist`（48×48/0.8s/36 帧），由跟随节点放在 `top_level` 精灵上、播放瞬间定位到嘴部世界坐标 → **雾团留在世界坐标**，敌人走开不跟随。主效果画布加宽到 80×80 以容纳 ±38px 的侧向碎晶；身体冻白仍用 HDR modulate。
- 2026-11-08（来源：user）：恶寒 v4.1：左右爆开的水平初速减半（`vx = ±(27..42)`，落点整体向身体收拢一半，bbox 78→52）；消散改为**像素化**——每颗 2×2 碎块在 0.22–0.42s 内按 `Px.rand(px_x*13+i, px_y*7+i, 71) < dissolve` 逐格剔除，同时颜色 `C[6]→C[5]→C[4]` 降级，拖尾与柔光在 `dissolve>0.6` 后一起消失。比整体 alpha 淡出更有像素碎屑感。
- 2026-11-08（来源：user）：恶寒 v5 冗余清理。① 画布按内容 bbox 收紧：`chill_frozen` 80²→**64×72**（origin 40,68→32,64，bbox 52）、`chill_mist` 48²→**24×24**（origin 24,34→8,14，bbox 9），两套合计 1.43MB→**0.87MB（−39%）**；② 删掉 v4 我自行加的身体 tint（`ICE_TINT`/`_apply_tint`/`_chill_present` 等约 30 行）——不在需求内、且与腐化 `corruption_tint` 互斥；③ `chill_mist` 去掉与雾团重复的 2 条细丝；④ `chill_freeze_fx.tscn` 的 Mist offset 交给脚本统一设置；⑤ manager 常量 `CHILL_DOT`→`CHILL_FX`（只改名，`CHILL_DOT_ID` 仍指 buff id）。坑：收紧画布后必须同步 `meta.origin`、节点 `ORIGIN` 与场景 `offset` 三处，否则特效会整体偏移。
- 2026-11-08（来源：user + code + test）：通用参数化视觉通道（颜料弹首个接入）。① `ExtensionHooks.on_visual_activated` 支持第二参数 `params: Dictionary`；节点实现 `network_apply_visual(params)` 后，mod 的 `_on_visual_activated` 会用 `network_apply_visual` 方法并带参广播（`_sanitize_visual_params` 白名单：≤8 键、键≤24 字符、值仅 Vector2/Vector2i/Color/int/float/bool/String、float 有限），接收端 `CoopVisualSync.spawn_visual_effect` 直接调 `network_apply_visual`（旧节点仍走 `set` 属性 + `active_state()`）。② 白名单补 `res://scenes/effects/` 与 `network_apply_visual`；`_maybe_broadcast_visual_node` 对实现该方法的节点**跳过 child_entered_tree 的无参广播**，否则首次激活会先发一个漏参克隆。③ 颜料弹 `network_apply_visual` 用 `{from,to,color,splat_at}` 重放，远端到达在本地铺同色 `floor_paint`（纯表现、不结算、不播本机音效）；本地投掷端仍走 PS 回调，避免双份。④ 两份 mod 副本（`mods/etn_coop` 与 `mod_sdk/coop_mod`）必须逐字节一致；单机/无 mod 时 hook 为空、`notify_named` no-op。⑤ 审查：子弹/爆炸走 `ProjectileSpawner`+`on_projectile_spawned` 已通用；一次性场景特效走 `on_visual_activated`（本次补参数）；持续视觉走 `network_get_visual_state`/`network_apply_visual_state`；轨道/场地/召唤/道具/敌人为专用；异常颜料/地面颜料/Serina 等仍本地-only，高频迁移需限流/合批。⑥ RPC 签名变更必须递增 `PROTOCOL_VERSION`（v7→v8）并同步 `MOD_VERSION`（0.1.16→0.1.17），两份副本一致。
- 2026-11-08（来源：user + code + test）：异常颜料/地面颜料/Serina 回血同步。① `anomaly_paint.network_apply_visual({"element"})`，MakiPS 在 `_spawn_anomaly_paint` 后广播（节流 100ms）；`floor_paint.network_apply_visual({"color"})`，`ink_cartridge` 先选色再 `active_state(color)` 并广播（节流 120ms）；本地表现频率不变，彩弹落地颜料仍由颜料弹克隆本地铺、不二次广播。② Serina 远端支援光环克隆只剥根脚本（`inst.set_script(null)`），`Aura` 子脚本保留，所以逐秒回血可用 `ExtensionHooks.on_support_heal` + mod `_server_support_heal`/`_remote_support_heal` 调 `Aura.spawn_heal()`；host 转发、发送端不回显，EX 光环本身已由 `_apply_support_aura_visual` 同步。③ `floor_paint` 场景在 `script/` 下，视觉白名单要补精确路径 `res://script/floor_paint.tscn`。④ RPC 变更后协议 v8→v9、`MOD_VERSION` 0.1.17→0.1.18，两份副本逐字节一致；探针覆盖 `anomaly_paint`/`floor_paint` 的 `network_apply_visual`。
- 2026-11-08（来源：user + code + test）：Serina 重做后 EX 视觉在联机的真正缺口。① 重做后的 `serina_as.tscn` 没有 AnimationPlayer，mod 的 `_apply_support_aura_visual` 仍找 `new_animation` → `ap == null`；克隆根脚本被 `set_script(null)`，`Aura.play()` 没人调 → 远端只有 `_ready` 的 `_hide_all()`，什么都看不到。② 修法：`serina_aura.play(target: Node = null)` 支持传目标（默认本机 Player），mod 在 serina 克隆 `add_child` 后 `Aura.play(镜像玩家)`；`play` 里 `_heal.set_target(target)`，上轮的 `spawn_heal` 才会挂到正确的人。③ 结束用 `Aura.stop()` + 0.35s 延迟释放，保留环倒放收拢；旧 AnimationPlayer 分支保留兼容。④ 教训：改本体重做特效后要回头审 mod 的远端克隆分支（可能仍在等旧节点/旧方法名），不能只看单机效果。⑤ 其余重做特效复核：恶寒/燃烧/中毒状态 FX 由各端 buff tick 本地 `spawn_fx`（镜像只抑制伤害不抑制 FX）已同步；腐蚀领域走专用 field RPC；Maki/异常/地面颜料已走通用视觉通道。

### [Combat] 感电（shock_dot）用「单链跳转 + 链命中易伤」实现群体异常
- Evidence / 证据: `script/shock_chain.gd`（`ShockChain.tick` / `_build_path`（候选表 + `{body, manager, entry}`）/ `_candidate_pool` / `SHOCK_RETRY_TICKS=2` / `GLOBAL_GAP_MS=90` / `HOP_DECAY=0.85` / `replay_remote` / `on_shock_chain` 通知）；`scenes/manager/enemy_buff_manager.gd`（`SHOCK_DOT_ID`、`shock_chain_hit`、`add_shock_vuln`、`network_set_shock_vuln`、`reset_shock_cd`、`_update_shock_timing`、`_rollback_shock_vuln`）；`script/Stats.gd:shock_layer`；`script/PlayerData.gd:base_shock_layer/shock_layer_add`；`scenes/player/maki/maki_ps.gd:Element.SHOCK`；`scenes/debuff/shock_chain_arc.tscn`；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（`_on_shock_chain` / `_remote_shock_chain` / `_remote_shock_vuln` / `PROTOCOL_VERSION=10`）；`script/extension_hooks.gd:on_shock_chain`；`tests/shock_chain_probe.gd`（本地，不入库）。
- Notes / 说明: ① 形态是「一条链走到底」，不是两两独立连线：链头 = 谁先到 `shock_cd` 谁发起；每跳选最近的、未被本链访问过的感电目标，跳距 ≤ 当前节点层数的射程，节点数 ≤ `min(6, 1+链头层数)`。② 链走完**先重置整条链的 `shock_cd`、出表现，再按跳序结算伤害，最后给仍存活的节点叠易伤**；本次命中不吃自己这层 5%，下一次链才吃。顺序反了会让本次链的易伤提前生效（5 层单跳会从 32 涨到 34）。孤立目标（路径 <2）把 `shock_cd` 置 2 tick 重试，避免每 tick 全表扫描。③ **易伤只在链命中时叠**（Maki 的感电直伤不叠）：链只由 host 跑、客机回放同一链；直伤只有拥有者端跑。④ 易伤写 `EnemyStats.anomaly_hurt_damage_mult`（与颜料标记同一乘区、加法共存），靠 `_on_entry_removed` 按 `0.05×vuln_stacks` 回滚；`EnemyStats.update_body_ability()` 不重置该字段，所以不会被属性重算冲掉。⑤ 层上限走施加者的 `shock_layer`（燃烧同机制）、时长恒定 4s/层；客机转发 buff 时 mod 的 `_applier_stats` / `_sanitize_applier_stats` 必须带上 `shock_layer`，否则 host 侧静默退回默认 5。⑥ 占位电弧接口冻结为 `play(points, power)`；正式特效留待后续参考 pixelfx `lightning/chain-lightning`（它是固定路径 + 施法者动作，不能直接当动态链用）。⑦ 联机链路（2026-11-09）：原实现客机镜像也本地跑链（`_tick_shock_dot` 无 gate）并本地 `add_shock_vuln`，而客机的 `resolved_damage` 由自身镜像的 `anomaly_hurt_damage_mult` 算出、被 host 直接采信（`HealthComponent.take_damage(..., resolved_damage)` 在 `resolved_damage>=0` 时不再重算），两端链路径不同会让同一发伤害在两个玩家端数值不同。现改为：host 链走完通过 `ExtensionHooks.on_shock_chain` 广播 net_id 序列 + 每节点 `vuln_stacks`；客机 `ShockChain.replay_remote` 只回放 VFX + `network_set_shock_vuln`，镜像 `_tick_shock_dot` 跳过本地建链；`shock_dot` apply/刷新时 host 补发 `_remote_shock_vuln`，中途加入/重连从 host 当前层数起步。协议 9→10。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-09

### [FX] 感电链：动态连线走运行时绘制，不套用 pixelfx 整画布烘焙
- Evidence / 证据: `scenes/debuff/shock_chain_arc.gd`（`play(points, power)`、`_rebuild`、`_update_glow`、`zigzag/bowed` 移植、`_draw_paths` 三层描边、`_draw_node`、`REDRAW=0.033`、`_sfx`）；`scenes/debuff/shock_chain_arc_glow.gd`（ADD 12/8/4px + 节点柔光）；`scenes/debuff/shock_chain_arc.tscn`（`Glow` 子节点 + `CanvasItemMaterial blend_mode=1`、`AudioStreamPlayer` `elliottklein__spark.wav`）；`script/shock_chain.gd:_spawn_arc`；`docs/REFERENCE_PIXELFX.md:163`（LIVE 58.6ms/帧）。
- Notes / 说明: ① pixelfx 的 `lightning/chain-lightning` 是固定 248×104 画布 + 固定 HAND/HOPS + 施法者动作的一次性演出，**不能直接当任意长度/角度的链**；逐跳烘焙固定长度贴图再拉伸会拉宽像素、跳与跳之间出接缝，所以链本体走运行时 `draw_polyline`（只画几十条折线，远低于整画布 LIVE 的 58.6ms/帧）。② 视觉只借参考库的**形状与笔触**：`zigzag` 中点位移到 ~3px、`bowed` 中点法线偏移 `-L×0.05..0.15`、分叉 `forks=0.35`；描边为深靛光晕(5px, α0.72)→蓝紫外体(2px)→浅紫亮芯(1px)，所有点 `roundf` 保像素锐利；背后另有 ADD `Glow` 子节点（12/8/4px 三层加色，alpha 见脚本常量，`CanvasItemMaterial blend_mode=1`、`show_behind_parent`）+ 节点柔光。`_rebuild` 缓存 `packed` 供 `draw`/`Glow` 共用，节点爬行电弧 `play` 时预计算，`_to_packed` 只在 `_rebuild` 调。③ 时序：`WIND=0.02` + 每跳 `LEAP=0.03` 的逐步 reveal（亮头 + `circular_1.png` 柔光），落地节点白核 + 扩散环 + 爬行电弧 + 火花；每 0.033s（30Hz）用 `play_id+跳号+redraw` 重播抖动，其余帧不 `queue_redraw`，淡出走 `modulate.a`。④ 调色与伤害数字同源：外体 `#754DFF` / 亮芯 `#F2EDFF` / 光晕 `#120D33` / 火花 `#B39EFF`，整体读作蓝紫，和恶寒蓝/腐化紫各拉开约 26°。⑤ 音效放 FX 内的 `AudioStreamPlayer`（`elliottklein__spark.wav` 0.28s，-10dB，pitch 1.05–1.30，90ms 静态节流）；wav 比链短、不会拖尾，pitch 抖动让每次链略有差异。⑥ 池契约不变（`is_idle/idle_state` + `shock_chain` 池/门控），`ShockChain` 结算零改动；抓帧时若用 `Engine.time_scale` 冻结会被 `GameEvents` 的慢放管理覆盖，正确做法是停掉自动循环、手动 `play` 后设 `_age` 再 `get_tree().paused = true`。⑦ **本项目 2D canvas 不参与 Environment glow**：实测 `WorldEnvironment`（`glow_enabled`、strength 0.3、levels 2/3/4 非零、阈值 1.0、screen 混合）配 HDR `Line2D(Color(3,3,3))` 与 `Line2D(Color(0.3,0.35,1.8))` **完全没有 bloom**，所以 HDR>1 不能当发光手段；发光必须用 `CanvasItemMaterial.BLEND_MODE_ADD` 手动叠层。`shock_chain_arc` 的 `Glow` 子节点（`show_behind_parent`）画 12/8/4px 三层加色（0.06/0.10/0.28）+ 节点 `circular_1.png` 柔光，根节点再用 5px 深靛外圈保证亮地面的轮廓；ADD 的 alpha 即发光强度，宽层别超过 ~0.08，否则糊成一条宽带。⑧ 成本模型（实测 10 目标×5 层、6 跳链，test_room，vsync 60）：`TIME_PROCESS` 8.34→9.55ms、`RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 95→264；逻辑（10Hz tick/候选扫描/伤害结算）低于测量噪声，成本主要是每链约 85 条绘制命令（节点白核/扩散环/爬行电弧/火花 + 3 层描边 + ADD 光晕）。`packed` 缓存/电弧预计算只减少分配，不减少 draw calls；要再降成本应合并火花/电弧的 `draw_*` 或减少节点特效，而不是继续抠逻辑。
- Source / 来源: user + code + test
- Date / 日期: 2026-11-09