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
>
> （暂无）

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
- Evidence / 证据: `script/transition_manager.gd`（未注册）, `scenes/game_camera/transition.gd`, `DamageData.check()`, `GameTags.CONVERT`（`FloatingPool.gd`/`scenes/manager/floating_pool.tscn` 已于 2026-10-08 删除）
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
- Evidence / 证据: `ui/society_card.gd:3-14`, `scenes/main/menu_screen.gd:276-281`
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
- Evidence / 证据: 客户端 `mods/etn_coop/net/coop_settings.gd:ensure_client_token`（UUID 持久化 `profile/client_token`）；`net/coop_relay_peer.gd:create_relay_host/join_relay_room`（控制帧带 `token`）、`net/coop_network_transport.gd:create_relay(...,token)`；`net/coop_net.gd`：`_client_hello(...,token)`/`_peer_token`/`_token_peer`/`_old_peer_for_rejoin`/`_migrate_peer_state`/`_begin_peer_grace`/`_update_rejoin_timeouts`/`_cleanup_peer`（原 `_on_peer_disconnected` 主体）、客机 `_begin_reconnect`/`_tick_reconnect`/`_try_reconnect`/`_finish_reconnect`/`_abort_reconnect_to_menu`/`_release_transport_for_reconnect`/`_show_reconnect_overlay`/`_freeze_local_player_for_reconnect`；`ui/coop_reconnect_overlay.gd`（代码构建 CanvasLayer）；`net/coop_name_tag.gd:set_offline`；`i18n/coop_i18n.gd`（`coop_reconnecting`/`coop_status_reconnected`/`coop_peer_offline`）；`entry/coop_entry.gd:--coop-devdrop=<sec>`；服务端 `E:\QQfw\js\服务端5.0.py`（`Peer.token/last_seen`、`join_room` 同 token 先 `remove_peer` 旧连接、`heartbeat_peers` 主动 PING + `PEER_TIMEOUT_MSEC`）。
- Notes / 说明: **方案 B（新 id + host 迁移）**：重连必然拿到新 peer id（ENet 由 host 分配、Relay 由服务端 `next_peer_id` 分配），故 host 用持久化 UUID token 识别「同一玩家」，把旧 id 的全部 per-peer 状态（角色/名字/team_stats/support/倒地/镜像字典）迁移到新 id；`_accept_peer` 改成只在缺失时填默认角色，避免覆盖迁移值。**宽限**：`_on_peer_disconnected` 对已握手且有 token 的 peer 不立即破坏性清理（保留镜像与字典、冻结 `player_stop`），`REJOIN_GRACE_MSEC=45s` 内等待 token 重连，超时才 `_cleanup_peer`；宽限期内 `_check_team_game_over` 直接 return（防其余人倒地误结束）。**客机保持场景**：断线不回菜单、不 `change_scene`，仅遮罩 + 冻结 + 退避（1.5→2→…→5s）重连，成功判定 `_hello_accept`；`close_connection` 在 `_reconnecting` 时**不** `_reset_run_state`、不清 `_last_join_params`，故本地升级/金币/位置自然保留。**严禁在 multiplayer 信号回调栈内改 peer** → `_begin_reconnect` 用 `_release_transport_for_reconnect.call_deferred()`。**服务端**：`join_room` 在容量判断前对同 token 的旧 `clients` 先 `remove_peer`（释放名额，解决满房误拒 + 半开幽灵占位）并广播 `peer_disconnected(old_id)` 让 host 进宽限；`heartbeat_peers` 主动 PING 清半开。**房主关房自动区分**：Relay 重连得 `Room not found` → `_on_relay_error` 立即回菜单（LAN 连接失败退避数次后回菜单）。**通用教训**：① 跨重连的稳定身份只能客户端自持 + host 侧迁移，服务端只负责连接生命周期；② 宽限必须冻结但不清，且团队结束/升级就绪判定要跳过掉线者；③ 半开旧连接不清理会占满名额，必须在服务端加同 token 替换 + 连接心跳；④ 任何"保持本地状态"的重连都要求断线路径绕过 `_reset_run_state`。**实测**：双进程 LAN `--coop-devdrop=5` → host `offline grace`→`migrate 1159166132->1260631889`→`accept`，client `reconnect attempt 1`→`reconnected`，0 SCRIPT ERROR；Relay（本地 7716）同流程、服务端 `assigned_peer_id=2→3`，0 错误；`coop_sim_regression.ps1` 4/4 PASS。**已知局限**：掉线期间 host 若推进回合，客机仍停旧回合；房主自身重连未做。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod] 掉线期间 host 的回合切换冻结：跨回合推进等待重连（不丢升级）
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`：`_deferred_round_end`/`_round_upgrade_active`/`_in_round_upgrade`/`_wait_reconnect_name`；`_gate_round_end_emit`（host 且 `_reconnecting_peers` 非空 → 记 `_deferred_round_end` 并 return true）；`_maybe_finish_round_upgrade`（宽限非空 → return）；`_on_rejoin_settled`（宽限清空后补发 `GameEvents.emit_round_end()` + `_maybe_finish_round_upgrade()` + 广播 `_remote_wait_reconnect("")`）；`_begin_peer_grace`（广播 `wait_reconnect_show`/`_remote_wait_reconnect(name)`）；`_client_hello` 重连识别后若 `_round_upgrade_active` 补发 `rpc_id(new,"_remote_round_end")`+`_remote_round_upgrade`；`_remote_round_upgrade` 幂等 + `_on_round_upgrade_end_local` 复位。UI：`ui/coop_round_wait.gd:show_message(text, light)`（light=隐藏 Background 遮罩 + 字号12、回合计时下方顶部居中 + `MOUSE_FILTER_IGNORE`）、`_apply_wrap`（按视口宽度换行）；`net/coop_flow.gd:_on_wait_reconnect_show/hide`；`i18n/coop_i18n.gd:coop_wait_reconnect`。本体触发点：`ui/round_timer.gd:147/153/181`（`_round_end_emit_blocked`）、`round_manager.gd:86-109`（`round_upgrade_end`→`_on_round_start`→`emit_round_start`→`init_round` 递增）、`script/GameEvents.gd:258-264`（`round_upgrade_end` gate / `force_round_upgrade_end`）。
- Notes / 说明: **根因**：回合号递增发生在两端各自的 `round_start`（`round_timer.init_round` → `now_round_num += 1` → `PlayerData.now_round`），而回合推进由 host 权威广播驱动；客机断线期间收不到 `_remote_round_end`/`_remote_round_upgrade`/`_remote_round_upgrade_end`，host 却继续推进 → 客机停旧回合。**修法（A：host 冻结回合切换）**：host 在重连宽限内暂缓两个跨回合卡点——① `emit_round_end` 触发（`_gate_round_end_emit` 记 `_deferred_round_end` 并阻止，覆盖普通/Boss）；② 升级页推进（`_maybe_finish_round_upgrade` 直接 return）。宽限清空（重连成功或超时清理）→ `_on_rejoin_settled` 解冻并补发。这样回合号在客机断线期间不变，客机回来无缝续上，无需回合 resync。**升级不丢（方案 B 补）**：重连识别后若 host 正在升级页（`_round_upgrade_active`），补发清场+升级页让重连者参与本次升级；客机 `_in_round_upgrade` 幂等防重复打开。**UI**：新增 `wait_reconnect_show/hide` 信号 + `coop_round_wait` light 模式（宽限期间世界仍可操作，故隐藏整屏黑底遮罩且鼠标穿透，文字字号12、置于回合计时下方顶部居中——2026-10-09：原 `LIGHT_TOP_MARGIN=12` 与 `ui/round_timer.tscn` 顶部居中计时（Control 高约 40px）重叠遮挡，改为 `LIGHT_TOP_MARGIN=44`、`LIGHT_BAND_HEIGHT=24` 下移到计时下方，避开左上 HUD 与 y≈82 的 FEVER 横幅），名字按视口宽度 `autowrap`（`MAX_NAME_LEN=12`）。**通用教训**：① "本地不回退的持续状态"（回合号）在断线重连下要么 host 冻结推进、要么做 resync；冻结更简单且语义符合"全员同步推进"；② 冻结必须在**所有**跨边界触发点，漏一个（如 Boss `end_boss_round`）就会穿透；③ 冻结只是 host 逻辑暂停，不暂停世界时 UI 遮罩必须鼠标穿透，否则玩家无法瞄准；④ 长玩家名要换行兜底（`MAX_NAME_LEN=12` 宽字符可超宽）。**实测**：`--coop-devfreeze` 白盒探针 host `{before:false, during:true, deferred:true, after:false}`；LAN `--coop-devdrop=5` 重连仍通、0 SCRIPT ERROR；`coop_sim_regression.ps1` 4/4 PASS。**未覆盖**：test_room 无回合计时器，回合冻结的真实端到端（正常关卡+升级页）留待实机验证。
- Source / 来源: code + test
- Date / 日期: 2026-10-08

### [Mod/Server] 中继加入加固：客机握手超时 + 拒绝容错 + 重复加入防抖 + 服务端 pending/id 回收
- Evidence / 证据: `mods/etn_coop/net/coop_net.gd`：`PROTOCOL_VERSION` 1→2、`HELLO_ACCEPT_TIMEOUT_MSEC=6000`、`_hello_sent_msec`/`_hello_acked`/`_relay_connect_in_flight`、`_update_client_handshake_timeout()`（`_physics_process` 调用）、`_hello_reject(reason: String = "")`、`_client_hello` 增 `mod_version` 校验、`create_relay_room`/`join_relay_room` 顶置 in-flight 守卫、`is_connect_in_flight()`、`close_connection`/`_reset_run_state`/`_on_*` 复位、`_update_rejoin_timeouts` 加 `multiplayer_peer==null` 守卫；`net/coop_relay_peer.gd:_close` 先发 `leave_room`；`ui/coop_menu.gd:_set_relay_busy` 锁定/解锁按钮；`i18n/coop_i18n.gd` 新增 `coop_status_host_version_old`/`coop_status_handshake_timeout`；服务端 `E:\QQfw\js\服务端5.0.py`：`Room.pending`、`all_peers`/`alloc_peer_id`、`join_room` 同 token 覆盖 pending+clients 且复用 id、容量含 pending、`client_ready` 移 pending→clients、`remove_peer` 仅对已准入广播、`cleanup_rooms`/`heartbeat_peers` 用 `all_peers`。
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

### [Mod] MOD 描述本地化用「中文原句作翻译键」+ PowerShell 读 mod.json 必须 UTF-8
- Evidence / 证据: `mods/etn_coop/mod.json`、`mod_sdk/coop_mod/mods/etn_coop/mod.json`（`author` / `description`）；`mods/etn_coop/i18n/coop_i18n.gd` 与打包源同名文件（`MESSAGES` 新增「中文原句」为键 + en，`install()` 对缺失语言回落 en）；`mod_sdk/build_coop_mod.ps1`（原 `Get-Content -Raw | ConvertFrom-Json` 改为 `[System.IO.File]::ReadAllText(path, UTF8) | ConvertFrom-Json`）。
- Notes / 说明: ① 本体 MOD 面板 tooltip 的 `TipDesc` 是**默认自动翻译的 Label**，故 mod.json `description` 可直接填中文原句（它同时作为翻译键），mod 侧在 `coop_i18n.gd` 以该原句为 key 提供 en 即可中英切换。相比用语义键（如 `coop_description`）：这样在 mod 未挂载/未启用、i18n 未注册时仍显示可读中文，而非露出原始键。未给 pt/vi 时 `install()` 自动回落 en。② **坑**：`mod.json` 一旦含中文，`build_coop_mod.ps1` 原用 `Get-Content -Raw | ConvertFrom-Json` 在 PowerShell 5.1 下按 ANSI(GBK) 读取 → JSON 解析失败、`$version` 变空（漏生成版本化 zip）并刷 `ConvertFrom-Json` 报错；改 `ReadAllText(..., UTF8)` 后正常。**通用规则：脚本/工具读取可能含非 ASCII 的 UTF-8 文件必须显式指定 UTF-8。**
- Source / 来源: user + code + test
- Date / 日期: 2026-10-08

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
- Source / 来源: user + code
- Date / 日期: 2026-10-10

### [GDScript] `Tween.set_parallel(true)` 会把"紧邻其前"的 tweener 一并纳入并行步（组"并行段+间隔"须用 `parallel()`）
- Evidence / 证据: `mod_sdk/coop_mod/mods/etn_coop/ui/coop_start_ball.gd:_show_not_ready_hint`（原 `set_parallel(true)` + `...chain().tween_interval(HOLD)` + `...chain().set_parallel(true)` → 停留失效；现改为 `tween_property(); parallel().tween_property(); tween_interval(); tween_property(); parallel().tween_property(); tween_callback()`）；引擎文档 `Tween.set_parallel()` 的 Note / `parallel()` 条目（`docs.godotengine.org` class_tween）
- Notes / 说明: **现象**（user）：开始球"需要所有玩家准备"红字"不会停留"——进场后立刻淡出、中间间隔时段处于隐形状态。**根因**：`Tween.set_parallel(true)` 官方注释明确"**Just like with `parallel()`, the tweener added right before this method will also be part of the parallel step**"；`chain().set_parallel(true)` 会把其**前一个** tweener（即 `tween_interval(HOLD)`）拉进并行组，于是随后的淡出 `tween_property` 与这个 interval **并行同时开始**（0.1s 内淡出），interval 剩余时间都在隐形——外观即"不停留/间隔被跳过"。**修法**：不要用全局 `set_parallel(true)` + `chain()` 混搭；要"两两并行成段、段间顺序"时用 `parallel()` 逐个配对：`tp(a); parallel().tp(b)` 即 a∥b，再直接 `tp(c)` 即接在 a∥b 之后。同理 `set_parallel(true)` 若紧跟某个 tweener 也会把那个 tweener 并入其后的并行段。**通用教训**：Tween 并行/顺序混排优先用 `parallel()`（局部、无状态）而非 `set_parallel()`（全局模式 + 回头吞前一个），可避免此类隐蔽的"间隔不生效"。
- Source / 来源: user + code
- Date / 日期: 2026-10-10
