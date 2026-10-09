# Systems / 核心系统原理

> Combat, health, buffs, resource data, entities, managers, game flow.
> 战斗、血量、Buff、资源数据、实体、管理器、游戏流程。
> 证据以 `file:line` 标注；发现与实现不符处以 ⚠️ 标出。
> 用户纠正优先于本文推断；来源标记（code/user/test）见 `docs/LEARNINGS.md`。

---

## 1. Data model / 数据模型

### 1.1 `HealthChangeData` — `script/health_change_data.gd`
- `base_damage: int`（正数=伤害，**不由符号判治疗**）, `source_node: NodePath`, `source_type: Array[String]`, `flags: Array[String]`, `damage_modifier: Array[Callable]`, `on_damage_dealt: Array[Callable]`, `is_heal: bool`, `convert_power: int`。
- `append_to(arr, value)` 供各 build 复用。

### 1.2 `DamageData` (extends HealthChangeData) — `script/damage_data.gd`
- 额外：`is_crit`, `knockback_force`, `knockback_direction`, `hit_box_center`, `damage_type: Array[String]`（`:33-37`）。
- Builders：`make(cfg)` / `fill(slot,cfg)`（复用池化实例，先 `reset_data()`）, `bullet`, `melee`, `explosion`, `equip_hit`, `dot(element, ...)`, `true_hit()`（`:57-119`）。
- `_apply_cfg` 键：`damage,crit,convert,knockback,direction,center,type,source,flags,modifiers,on_hit,node`（`:121-151`）。⚠️ `node` 仅在节点**已入树**时才写 `source_node`（`is_inside_tree()` 守卫；未入树留空，避免 `Node.get_path()` 刷红字）。`from(node)` 同守卫。
- 显示颜色：`TYPE_COLORS` + 多类型加权混合 + 暴击色偏（`:233-256`）。
- ⚠️ `check()` 无调用者（死代码）。

### 1.3 `HealData` (extends HealthChangeData) — `script/heal_data.gd`
- `make/fill`（键 `amount,crit,source,flags,node`）、`heal(amount, source_tag, node)`；`reset_data` 设 `is_heal=true`。`node` 同样仅在已入树时才写 `source_node`。
- ⚠️ 不可把 HealData 槽传给 `DamageData.fill`（会设 `is_heal=false`）。

### 1.4 Tags — `script/game_tags.gd`
- Source：`PLAYER, PS_DAMAGE, EQUIP, SUMMONED, CONVERTED, NEUTRAL, MAP, ENEMY`。
- Type：`CRIT_DAMAGE, BULLET_DAMAGE, MELEE_DAMAGE, EXPLOSION_DAMAGE, FIRE_DAMAGE, POISON_DAMAGE, CHILL_DAMAGE, EQUIP_DAMAGE, DOT_DAMAGE, HEAL_DAMAGE`。
- Flags：`KNOCKBACK_ATTRACT, TRUE_DAMAGE, WEAK_DAMAGE, CONVERT`（⚠️ 无读者）, `EXTRA_DAMAGE`。

### 1.5 Faction — `script/faction.gd`
- `PLAYER_SIDE=0, ENEMY_SIDE=1, NEUTRAL=2, ANY=-1`。
- `of_source()`：`NEUTRAL`→中性；`ENEMY`→敌方；**其余（含空、PLAYER、SUMMONED、CONVERTED、EQUIP、MAP、DOT）→ PLAYER_SIDE**（`:9-14`）。
- ⚠️ 空的 `source_type` 被当成玩家方 —— 易致误伤/免疫。
- `hostile_to(source_type, target_team)` = `of_source(...) != target_team`。
- `of_entity()`：看 `faction` 字段，否则组 `Summoned`/`Converted`/`Player` → 玩家方，默认敌方。

---

## 2. Combat pipeline / 战斗结算管线

### 2.1 玩家子弹产出 DamageData（暴击在此 roll）
1. `PlayerGun._shoot_bullet` 取池化子弹，设速度/穿透等，加入 `BulletRoot`，emit `player_shot_position`（`script/player_gun.gd:141-229`）。
2. `Player` 在 `_ready` 连接 `player_shot_position → bullet_hit_damage`（`script/player.gd:90`）。
3. `bullet_hit_damage`（`player.gd:390-426`）：`DamageData.fill(bullet_body.damage_data, {... source=PLAYER, node=bullet_body})` → `apply_penetrate_dealt()` → `randf_range(0,100) < stats.critical_luck` roll 暴击 → `base_damage = max(1, round(bullet_damage * global_damage [* critical_damage]))` → emit `player_shot_critical`/`player_shot_not_critical` → 追加玩家的 `damage_types`/`damage_modifier`/`damage_dealt`/`flags` → 缩放子弹。
4. 敌方/召唤物/近战各自构造：`bullet_launcher.gd:45-51,85-91`、`entity_ENEMY.create_damage_data`（`:138-150`）、`enemy_bullet.gd`、`turret_summoned.gd:113-133`、`kick.gd:28-43`。

### 2.1b 子弹移动与追踪（数值安全）

- `PlayerBullet`（`script/player_bullet.gd`）的 `direction` **恒为单位朝向**：`r_move()` 只写单位方向，期望速度用 `direction * speed`。`slow_down` 的 `velocity = direction * v_value` 依赖此约定；若 `direction` 被写成速度量级，会指数放大到 inf/NaN，把子弹 `CollisionShape2D` 丢到非有限坐标而触发 Rapier broad-phase panic。
- 追踪：`homing` 分支仅在 `_homing_target != null` 且 `global_position.distance_to(target) <= homing_range`（默认 `1400` ≈ 地图对角）时 `r_move`；超范围/无目标则跳过、回到原 `slow_down` 直线飞行（不回收）。`active_state()` 重置 `acceleration`，避免池复用带旧值。
- 同类处理：`normal_bullet.gd`（`SummonedBullet`）`r_move` 同样保持单位 `direction`；`shiro_missile.gd` 在 `active_state` 重置 `acceleration` 并防空 `enemy_body[0]`；`enemy_bullet.gd` 的 decay `ACCELERATION` 防除零；`yuzu_bullet.gd` 反弹方向归一化。
- 参照：`enemy_bullet.gd` 的 `direction` 本就单位（decay 安全）；`enemy_missile_1.gd` 用局部 `dir_v` 且每帧 `limit_length(max(speed,1))`，安全。
- ⚠️ 重写 `active_state()` 的 `PlayerBullet` 子类**必须重新启用墙壁射线**（`ray_cast_2d.enabled = true` + `ray_cast_2d.target_position.x = speed * 0.0167`）或调用 `super.active_state()`；否则子弹回池（`idle_state()` 关了射线）后复用将**永不撞墙**（`megu_bullet` 曾漏此，2026-09-27 修复）。
- **子弹 rotation 更新策略（2026-10-02）**：`PlayerBullet` 朝向在 `active_state()` 定型一次（`rotation = direction.angle()`），仅在 `r_move()`（homing/`can_r`）与反弹时更新，`_physics_process` **不再每帧重算**（直线弹省下每帧 normalize+atan2+写 transform）。`flight_time += delta` 仍保留（`mint_chocolate_parfait.gd` 依赖）。`megu_bullet` 自写 `active_state`（不调 super）+ 自反弹，需自行补 `rotation`；`yuzu_bullet`/`normal_bullet` 各有 `_physics_process`，不受影响。子弹拖尾 `scenes/line.gd` 的 `is_idle` 改为带 setter 属性：空闲 `set_physics_process(false)`、激活开启（**未改更新频率**），池中空闲拖尾不再每帧空转。
- **敌方子弹（`EnemyBullet`，`scenes/bullet/enemy_bullet.gd`）撞墙改走 HitBox（Area2D）`body_entered`（2026-10-02）**：三个场景（`enemy_bullet.tscn`/`enemy_bullet_2.tscn`/`enemy_bullet_3.tscn`）Area2D `collision_mask` 含 `bullet_wall`(2)（`2048→2050`），`_ready` 连 `body_entered`；与墙/可挡子弹道具（`BulletWall` 组，均为 `StaticBody2D`/TileMap）重叠即 `bulletSmoke + idle_state()`。**已删除 RayCast2D 判墙与反弹分支**（三个 `.tscn` 的 `RayCast2D` 节点一并移除）。原因：阵型子弹（`FormationController.add_bullet` 置 `speed=0`）旧射线长度为 0 → 永不撞墙（`enemy_gun_7` 的 `enemy_bullet_3` 穿墙）；且敌人子弹 `collision_num` 全为 0，不需要反弹。⚠️ `PlayerBullet`/`normal_bullet`/`megu_bullet` 等仍用射线（见上条），未受影响。
- **命中结算改为「按目标冷却」（2026-10-04）**：玩家侧直击弹（`PlayerBullet` / `SummonedBullet`）由 `HitBox.manages_own_hits = true` 开启自管理（`PlayerBullet` 经 `does_direct_hit()` 钩子判定；迫击炮弹 `PlayerMortarBullet` 覆写为 `false`，**不直击、只靠落点爆炸**），由子弹**自检** HurtBox（自身 `area_entered/exited` 维护 `_hit_contacts`）并结算；`HurtBox._on_area_entered` 对自管理 HitBox 直接 `return`（避免目标侧双结算）。**判定形状常开**，故穿透弹不会再在命中盲窗内穿过/漏掉其它敌人；同一目标按 `rehit_interval_seconds`（秒，默认 0.1；0 = 本次接触只命中一次）重复结算，保留低速多段。进入即结算一次，`_tick_self_hits(delta)` 只处理重复。`EnemyBullet`（打玩家）**不**自管理，仍走目标侧，保留玩家无敌帧语义（`set_invulnerable` 只切 `monitoring`，来源侧检测会绕过）。⚠️ 旧方案（命中后**整体关 `CollisionShape2D`** + `hit_shape_cd_frames`）已废弃：单个形状无法区分「同一敌人 / 另一个敌人」，关形状那一帧必然漏敌（Aris 高速穿透漏敌根因，2026-09-28 首修、2026-10-04 改为按目标冷却）。`_emit_self_hit` 的运行时通知（`GameEvents.emit_player_projectile_hit` + `ExtensionHooks` gate）收在 `_runtime_self_hit()`，并受开关 `HitBox.runtime_self_hit_notify`（默认 true）控制——编辑器 `@tool` 单测置 false 隔离占位 autoload。测试 `tests/test_bullet_self_hits.gd`。
- ⚠️ **形状启停统一走 deferred（2026-10-02）**：`PlayerBullet`/`SummonedBullet` 的 `_request_shape_disabled(value)`（`_shape_gen += 1` + `call_deferred("_set_shape_disabled_guarded", value, _shape_gen)`）是唯一出口，`close_shape()`、冷却重开、`idle_state()`、`active_state()` **全部经它**。子类（如 `megu_bullet` 重写 `active_state()`）也须用 `_request_shape_disabled`，**不得**直写 `collision_shape_2d.disabled`——`idle_state()` 会在命中/死亡结算（物理 query flush 期）被调用，直写触发 `area_set_shape_disabled(): "Can't change this state while flushing queries"`。代价：形状状态最多晚 1 帧生效（`close_shape`/`coin.gd` 早已是此约定）。`_set_shape_disabled_guarded` 的 `_shape_gen` 校验作废「回池后同帧复用」的旧延迟写入。同批把其余非子弹实体（`entity_ENEMY` 的 idle/active、`modded_sweeper`/`enhanced_sweeper`/`erosion_tower`/`goliath` 的 `on_dead`、`explosion_damage`、`fire_damage`、`summoned_hit_box`、`pyroxenes`、`soft_collision`、`murky_hand_scythe_icon`、`cross_bullet`、`UtahaPS`、`kei_as`）的同步写改为 `set_deferred("disabled", ...)`；`kick.gd`/`chinatsu_melee.gd`（近战，enable 决定当帧判定，且调用点非 flush）与 `enemy_part.gd`（依赖立即启停重置残留）保持同步。
- **等距墙面反射 + 子弹量产优化（2026-10-03）**：地图为等距投影（`main.tscn` TileSet `tile_shape=1`、`tile_size=64×32`，墙碰撞菱形 `(0,8)(-32,-8)(0,-24)(32,-8)`），屏幕空间 `velocity.bounce(normal)` 与地面真实镜面反射不符。新增静态 `IsoProjection`（`script/iso_projection.gd`）：按 2:1 等距基 `M`（列 `(1,0.5)`/`(1,-0.5)`）`vg = M⁻¹v` → `ng = normalize(Mᵀn)` → `vg - 2(vg·ng)ng` → `v = M vg`。菱形边法线 `(1,±2)` 映射为地面轴 `(1,0)/(0,1)`；只在反弹帧执行，**无每帧开销**。接入点：`player_bullet.gd`、`normal_bullet.gd`（`SummonedBullet`）、`mashiro_sniper_bullet.gd`（`get_bullet_collision`），属性墙（`PropWallBody`）一并按地面空间处理。同批微优化：反弹缓存 `get_collision_point()`、`rotation = velocity.angle()` 去掉多余 `normalized()`。**量产优化**：`PlayerBullet`/`SummonedBullet`/`mashiro_sniper_bullet` 的 `idle_state()` → `set_physics_process(false)`、`active_state()` → `true`，空闲子弹不再每帧空转（对齐 `entity_ENEMY`/`BuffCard`/`Line` 约定）；`normal_bullet` 删除每帧 `rotation = velocity.normalized().angle()`，改为 `active_state()` 定型 + `r_move()`/反弹时更新。⚠️ `megu_bullet` 已于 2026-10-04 改为 `_ready`/`active_state` 调 `super`（仅额外开关粒子），不再自维护开关；`PlayerBullet` 子类重写 `idle_state`/`active_state` 仍应调 `super` 或自行同步物理开关与 `rotation` 复位。测试 `tests/test_iso_projection.gd`、`tests/test_bullet_self_hits.gd`。

### 2.2 Area2D 碰撞 → HurtBox
- `HitBox extends Area2D`（`script/hit_box.gd`）：携带可变 `damage_data` 与 `source_faction`（默认 ENEMY_SIDE）；`_enter_tree` 兜底 `damage_data = DamageData.new()`（防命中时空引用，覆盖不调 `super._ready()` 的子类）。新增自管理命中开关 `manages_own_hits`（默认 false）与 `rehit_interval_seconds`（秒，默认 0.1），及 `_setup_self_hits`/`_on_self_hit_area_entered`/`_tick_self_hits`/`_emit_self_hit`（见上方 §2.1b 按目标冷却）。
- `HurtBox extends Area2D`（`script/hurt_box.gd`）：`signal hit_received(damage_data)`；`_ready` 连接 `area_entered` 并 `collision_mask |= 8`；`_on_area_entered` 先跳过 `manages_own_hits` 的 HitBox、并对 `damage_data == null` 早退，其余命中时设 `hit_box_center` 后 emit。
- 玩家 hurtbox（`is_player=true`）用 mask 8 的接触探针；敌/其他用 `body_entered`/`body_exited` 接触列表。
- `_emit_contact` 用 `Faction.hostile_to(...)` 过滤（`:114-125`）。
- ⚠️ `area_entered`/`area_exited`/`body_*` 回调里取 `.owner` 前必须 `is_instance_valid`：钻头 `_on_hit_box_exited` 曾对已释放的 HurtBox 取 `owner.is_in_group(...)` 触发 `0xC0000005`（2026-09-30 修复）；取集合中对象前先 `is_instance_valid`，取 `owner` 前再判空+有效（参考 `script/enemy_part.gd:136-137`）。同批加固循环内 `i.owner.*`：`script/fire_damage.gd`、`scenes/debuff/fire_field.gd`、`scenes/update_item/kitchen_knife.gd`、`scenes/update_item/renge_fire_field.gd`、`scenes/enemies/enemy_fire_field.gd`、`scenes/player/utaha/melee.gd`（`upgrade_summoned`）。注意 emit 可能在同一循环内释放 owner（`fire_field.gd`），owner 相关访问尽量置于 emit 前或 emit 后重新校验。
- ⚠️ 无敌帧分两档（`script/hurt_box.gd:27-37`）：`set_invulnerable(v)` = 普通档，切 `monitoring`/`contact_invincible`、**不切 `monitorable`**；`set_dodge(v)` = 闪避档，在其上再切 `monitorable`。
- 是否吃无敌帧取决于**检测发起方**：**目标侧**（HurtBox 自身 `area_entered` = 普通子弹/近战、接触探针 `_poll_probe`/`_poll_contacts` = 敌人本体接触）受 `monitoring`/`contact_invincible` 门控 → 被无敌帧挡；**来源侧**（来源自己维护命中集合后直接 `hit_received.emit`，如 `scenes/bullet/laser_bullet.gd:95-106` 的 erosion_tower 激光）只看目标 `monitorable` + 形状启用 → 普通档无敌帧不动 `monitorable`，故激光无视无敌帧；`set_dodge` 关掉 `monitorable` 才连激光一起挡。

### 2.2b 玩家蓄力激光 `player_laser_beam`
- 节点：`scenes/bullet/player_laser_beam.tscn`（`RayCast2D`）。命中检测为**场景预置** `BeamHitBox`（`Area2D`：`monitoring=true`、`monitorable=false`、`collision_layer=0`、`collision_mask=16384`=`enemy_hurtbox`），其下预置 N 个 `CollisionShape2D`（当前 10 个）。段数由 `_ready` 收集后推导（`segment_count = _seg_shapes.size()`），每个形状 `duplicate()` 成独立 `RectangleShape2D`（防 PackedScene 子资源跨实例共享串写，参照 `scenes/bullet/laser_bullet.gd:23-26`）。
- 命中：`BeamHitBox.area_entered/exited` 维护 `_contacts`（HurtBox 集合）；`_time_count`（`GameEvents.global_time_count`，`damage_tick_interval` 节流）遍历集合 `hit_received.emit(damage_data)`。`active_state()` 先清空 `_contacts` 并做**一次** `get_overlapping_areas()` 种子查询（补「激活瞬间已重叠、不补发 `area_entered`」）。
- 形状贴合：`_update_segments(pts)` 按折线设置每个 `CollisionShape2D` 的 `position/rotation/size`；超过折线点数的段**退化到端点并 `disabled`**（不再 `queue_free`）。写入前 `is_finite` 校验，且 `_build_beam_points_tracking`/`_wall_ray` 有非有限守卫，阻断 NaN/∞ 进入 Rapier（见 §2.1b）。
- ⚠️ 闪退加固（2026-09-29）：`follow()` 入口校验 `muzzle_global`/`aim_angle` 有限——`BeamHitBox` 是激光子节点，**激光自身 transform** 被 NaN 污染时其全局 transform 仍会带 NaN 进 Rapier，形状级守卫覆盖不到；lag 路径（`_build_beam_points_lag`）同样过滤目标坐标并保证 `p` 有限；`charge_laser_gun` 对 `laser` 统一用 `is_instance_valid`（防已释放引用）。
- 结算前过滤 `is_instance_valid` 与 `monitorable`（敌人 `set_dodge` 期跳过；`Area2D.monitorable` 变化不清既有重叠）。
- `aris_armed_ps` 的 `_last_hit_time`（敌人 `instance_id` → ticks）在 `GameEvents.round_end`（`_reset_energy_buff`）清空，防长局无界增长。
- 语义同「来源侧检测」（见上条 §2.2 无敌帧）：激光无视普通无敌帧、被 `set_dodge` 躲。
- ⚠️ 不再运行期 `Area2D.new()` 增删、也不再逐 tick `get_overlapping_areas()` 轮询。`homing_bullet` 仍只经 `set_point_target`/`segment_count`/`get_max_tracked_enemies` 驱动追踪，未改接口。
- 联机同步（2026-10-08）：`player_laser_beam` 无 `velocity`，本体走 mod 的**一次性特效通道**（只发激活瞬间坐标），原位无持续更新 → 远端不跟随、停在上一发位置、追踪无效。修法：本体加 `network_get_beam_state()`/`network_apply_beam_state(p, angles)`，mod `coop_net.gd` 新增**光束跟随状态通道**——拥有者在 `_on_projectile_spawned`（`has_method("network_get_beam_state")`）按 `net_effect_id` 登记 `_follow_nodes`，每 `FOLLOW_SYNC_INTERVAL=0.05s` 采集 `{枪口 global_position, _angles, 各段锁定敌人 net_id}` 走 unreliable 广播（client→host `_server_effect_follow_batch` 消毒/限流后转发并本地套用，host 直接 `_remote_effect_follow_batch`）；接收端经 `CoopVisualSync.get_effect(eid)` 取回克隆，套角度 + 由 `enemy_by_net_id` 反查 net_id 写入 `set_point_target`；远端位置在 `_physics_process` 向 `_net_target_pos` 指数插值（`active_state` 重置 `_net_remote_driven`）。`idle_state` 经 `on_projectile_despawned` 从 `_follow_nodes` 注销（`_reset_player_sync`/`_clear_round_visuals` 亦清）。本体无 helper 的旧版本经 `has_method` 自动跳过、不报错。两份 mod 副本同步改，`MOD_VERSION` 0.1.2→0.1.3。
- **同通道泛化（2026-10-08）**：该通道升级为通用「持续视觉状态通道」，同时支持 `network_get_visual_state()`/`network_apply_visual_state(p, r, sc)`（世界坐标 + 朝向 + 缩放）。`_on_visual_activated` 也登记带该方法的节点。首个接入：`murky_hand_scythe`（墨手镰）——其 `_physics_process` 回程段 `player` 取自**接收端本机玩家**（挂 `on_visual_activated` 一次性广播，克隆按本机玩家归位 → 飞错人）；现由通道持续同步世界坐标/朝向/缩放，镜像 `_net_remote_driven` 时跳过本地归位、只保留 `sprite_2d` 自旋。采集端跳过 `is_idle==1` 的隐藏态（视觉通道节点 idle 不回收 `net_effect_id`）。**判据**：自驱型（`laser_launcher` 自行旋转计时）无需此通道；外部驱动型（跟随/追踪/归位玩家）才需要。

### 2.2c 敌人激光 `laser_launcher`（erosion_tower）
- `scenes/bullet/launcher/laser_launcher.gd`（`laser_launcher.tscn`，每座 erosion_tower 两实例）驱动环绕光束的预警/旋转/出光/淡出。
- `@export life_time` = **出光持续时间**（0.1s tick，**不含预警**）。每次 `active_state()` 用 `life_time_left = life_time` 重装；⚠️ **不要直接自减 `life_time`**（旧实现把 `@export` 当运行期倒计时，配置值被一次性消耗 → 第二次及以后永不停止；且 `life_time ≤ WARNING_TICKS` 时预警后反转不停。2026-10-02 修复）。
- 时间轴：`active_state()`（同时重置 `warning_time`/`end_time`/`is_stop`）→ `laser_shoot()` 置 `warning_time = WARNING_TICKS(15)` → 预警结束 `start_rotating()` → 每 tick `life_time_left--`，归零 `stop_rotating()`（`end_time = END_TICKS(15)` 淡出 → `idle_state()`）。`life_time == 0` 时预警结束直接 `idle_state()` 不出光。
- `total_active_ticks() = WARNING_TICKS + life_time + END_TICKS`（单一真源，供塔组算窗口）。
- 光束命中检测（`scenes/bullet/laser_bullet.gd`）：**边沿事件** `HitBox.area_entered/exited` 维护 `_contacts`（HurtBox 集合），`laser_shoot()` 清空后做**一次** `get_overlapping_areas()` 种子查询，`laser_end()` 清空（淡出会禁用形状、Rapier 不补发 `area_exited`）；`add_damage()`（`global_time_count` tick）遍历集合，过滤 `is_instance_valid` + `monitorable` 再 `hit_received.emit`。不再逐 tick 轮询 `get_overlapping_areas()`——Rapier2D 下轮询会残留、`monitorable` 变化不清既有重叠（`LEARNINGS.md` 321/463），旧实现导致玩家跳出/跳跃后激光仍持续掉血（2026-10-03 修复）。
- 塔组 `erosion_tower_group.attack_state()` 用 `_active_attack_ticks()` 把单次攻击窗口 `shoot_time` 抬到 ≥ 当前开火激光的 `total_active_ticks()`，使激光只受自身 `life_time` 约束；非激光攻击仍为 `shoot_time_max`（`erosion_tower_group.gd:19,60-79`）。⚠️ `erosion_tower_group.enemy_fever_time()` 是**死代码**（塔组从未连 `GameEvents.fever_time_start`，全局只有 `goliath.gd:86` 连）。

### 2.3 HealthComponent 结算（敌方）
`script/health_component.gd`：
- `_ready` 连接 `hurt_box.hit_received → take_damage`。
- `_is_friendly_fire`：非治疗友方=非敌对；**治疗的友方判定相反**。
- `take_damage` 维护 `_hit_depth`，深度归零后 drain `pending_extra` 队列（`:31-36`）。
- `_take_damage_internal`（`:57-179`）：
  - `is_invincible` 直接返回。
  - 友方 → 仅 `apply_conversion_power`（若有 `convert_power`）后返回。
  - `raw_damage = base_damage * PlayerData.player.stats.dot_damage`。
  - 若 `source_type.has(CONVERTED)` 且非 TRUE_DAMAGE：近战乘 `PlayerData.kick_damage_mult`，逐击 roll 暴击（`:71-85`）。
  - 治疗分支：`final=max(1,raw)`，emit `enemy_heal_taken`，跑 modifier，`stats.hp += final`。
  - 伤害分支（`:105-157`）：`final=max(1, raw * stats.global_hurt_damage)`；`TRUE_DAMAGE` 跳过该乘数；emit `enemy_damage_taken`；跑 `damage_modifier`；非 TRUE 时应用并重置 `damage_multiplier`；`final>stats.hp` → emit `enemy_over_kill_damage`；`stats.hp -= final`；`damage_taken.emit`；闪白/受击音；`on_damage_dealt`；`stats.hp<=0` → emit `enemy_damage_taken_dead`。
  - 击退：方向默认 `(owner.pos - dmg.hit_box_center).normalized()`；`KNOCKBACK_ATTRACT` 反向；力度 `force * resist_factor * melee_mult`。
- 🚩 **顺序**：`emit_enemy_damage_taken` 在 modifier / `damage_multiplier` / hp 扣减**之前**，但 `enemy_over_kill_damage` 用**后置**值 —— 订阅者不可假设二者一致。
- 🚩 `damage_multiplier` 仅在 `!TRUE_DAMAGE` 时重置（`:130-132`），TRUE_DAMAGE 会漏掉重置，残留到下一次非真实伤害。

### 2.4 玩家血量 — `script/player_health_component.gd`
- `is_invincible` 早退；`base_damage<=0` 时改走“仅击退”分支（有 `knockback_force` 则只结算击退，不扣血 / 不吃 `hurt_invalid` / 不进无敌帧 / 不触发 `on_hit_effects`）；正常伤害下 `hurt_invalid>0` 消耗一次免疫并显示 "IMMUNE!"（`:67-78`）。
- 护甲减伤走指数曲线 `_armor_reduction() = armor_cap * (1 - exp(-hurt_resis / armor_k))`（`armor_cap=0.8`、`armor_k=20`，脚本默认值；`player_health_component.gd:34-35`）；`mitigated = max(1, floor(raw * (1 - reduction)))` × `hurt_mult` × `damage_multiplier`（`:79-95`）。前期陡、后期趋近 80% 上限（`armor_k` 越小前期越快；2026-09-27 由旧 `1/(1+hurt_resis*0.02)` 替换）。
- `t_hp>0` 先扣 `t_hp` 再扣 `hp`；emit `player_hurt_t_hp`/`player_hurt_hp`，起无敌帧。
- 击退：`_apply_player_knockback()`（`player_health_component.gd:146+`）按 `force * resist_factor(knockback_resis) * melee_mult` 调 `Player.apply_knockback()`（直接覆盖 `velocity`，**不封顶**）；正常伤害与 0 伤害（`base_damage<=0`）共用此入口。
- 接触击退（盾兵，参考 `kasumi_drill`）：`EnemyPart`（`script/enemy_part.gd`）用**场景预置 `HitBox`**（`shield.tscn`，Area2D `monitorable=false`、`collision_mask=10240` = `player_box`(12)+`summoned_box`(14)），`area_entered/exited` 维护 `_kb_targets` 数组；每 `contact_interval` 调 `add_damage_data()`：对数组内**全部**目标 `hit_received.emit(damage_data)`，随后切换 `HitBox/CollisionShape2D.disabled`（false→发送→true）并 `clear()` 数组、进入冷却。`DamageData.fill({damage:0, knockback:contact_knockback, type:MELEE_DAMAGE, source:ENEMY, node:self})`、`hit_box_center=护盾位置`（推出方向）。玩家走 0 伤害击退分支；召唤物走 `summoned_health_component._apply_knockback`（本就支持 0 伤害）。无敌帧/跳跃免疫由 **Area2D 检测层**处理（玩家 HurtBox 的 `monitorable`/`monitoring` 状态），代码里无需 `contact_invincible` 门（`enemy_part` 已移除该门与 `contact_range`）。⚠️ **不要用运行期 `Area2D + get_overlapping_areas()` 做持续判定**——Rapier2D 下会残留导致隔空推。
- ⚠️ **玩家死亡不在此处理**（`:142-145` 空块）；死亡/复活/game_over 在 `Stats.hp` setter（`script/Stats.gd:142-161`，含 `await create_timer(0.1)`）。

### 2.5 召唤物血量 — `script/summoned_health_component.gd`
- 玩家近战只击退不伤害（`:35-43`；该友好击退不受下方开关影响，始终生效）。
- `can_hurt` 门；`final=max(0, raw*global_hurt_damage)`；若 `stats.max_hp<=0` 则 emit `deal_damage_to_player` 转发给玩家而非扣血（`:84-93`）。
- 受伤击退由 `@export knockback_on_hurt`（默认 `false`）控制召唤物本体，并再乘 `@export_range(0.0,1.0) knockback_mult`（百分比系数，默认 `1.0`）；转发给玩家是否保留击退由 `@export transfer_knockback`（默认 `false`）控制——为 `false` 时先 `duplicate(true)` 再清 `knockback_force` 再转发，避免污染被 AoE/穿透弹复用的共享 `DamageData`（`:85-91,118-124`）。现有 3 个召唤物（`mobu_trinity`/`kei_summoned`/`utaha_turret_body`）均未序列化这些字段 → 脚本默认值生效（均不击退）。近战友伤击退（`:35-43`）不乘 `knockback_mult`。
- `invincibility_frames` 用 `call_deferred` 调用（`:96-97`）：在 `hurt_box` 的 `area_entered` 信号锁内同步改 `Area2D.monitoring` 会被引擎拒绝（`Function blocked during in/out signal`），同时规避 `HurtAnim` 动画轨道 `.:monitoring` 在 `play()` 时的同步写入。
- 召唤物无敌帧（`script/summoned_follower.gd`）：`jump_start/jump_end` → `hurt_box.set_dodge(true/false)`（闪避档，连激光也躲）；受击 `invincibility_frames()` → `hurt_box.set_invulnerable(true)`（普通档，挡普通子弹/近战/接触，激光仍命中），还原由 `mobu_trinity.tscn` 的 `HurtAnim` 轨道 `.:monitoring` + `.:contact_invincible` 完成。
- 击退用 `DamageRouter.diminishing_factor(summoned_knockback_resis)`。
- **召唤物顶部伤害闸门（联机，2026-10-08）**：`take_damage()` 最顶部先 `ExtensionHooks.intercept(summoned_damage_interceptor, [owner, damage_data])`（`summoned_health_component.gd:32-35`）。未装 mod 返回 false 走本体；装了 coop mod 且受击者是**远端召唤物镜像**时由 mod 接管——友方近战转发拥有者、其它伤害直接丢弃（镜像 HurtBox 被 mod 设为「探测专用」可被本机近战命中，若不丢弃敌方爆炸/激光等会误触 `max_hp<=0 → emit_deal_damage_to_player` 打到本机玩家）。

### 2.6 Healing path / 治疗
- 统一模式：`HealData.fill(slot,{amount,source,node})` → `health_component.take_damage(heal_data)`。
- 敌/玩家治疗分别 emit `enemy_heal_taken`/`player_heal_taken`；召唤物不 emit。
- 玩家侧 `PlayerHealthComponent` 治疗分支应用 `stats.heal_mult`（modifier 之后、加血之前；飘字/加血同值，`:65`）；`HealData.ignore_heal_mult=true` 可跳过该乘算（固定数值治疗，如 serina EX 每秒 5% max_hp）。
- **治疗溢出转临时生命统一收口在 `Stats.hp` setter**（`script/Stats.gd`）：`heal_overflow_to_t_hp` 为真时，`hp` 超过 `max_hp` 的部分转入 `t_hp`（`t_hp` setter 自动 clamp 到 `max_hp/2`，超出丢弃）。因此覆盖**所有** `stats.hp += N` 与统一治疗路径（含直接加血的 `school_bag`/`tactical_satchel`）。开关只在 EX 期间开启，回合边界由 `t_hp_count.gd:t_hp_clear()` 兜底关闭。
- 旧接口 `player.health_hp + emit_signal("is_health")` 已移除（`is_health` 信号、`health_hp`、`is_health_request`、`_on_health`、`_on_is_health` 及 22 个玩家 `.tscn` 连接全删）；`grs_grilled_corn`、`last_stand_component._do_heal()` 已迁到上面统一模式。

### 2.7 WeakPart / 弱点 — `script/weak_part.gd`
- `extends HurtBox`；`weak_mult = 4.0`；命中时 `duplicate(true)` 后 `base_damage *= weak_mult`，追加 `WEAK_DAMAGE` + `TRUE_DAMAGE`（`:19-28`）。
- ⚠️ 跳过 `super._ready()`，故基类 `collision_mask |= 8` 与 contact 逻辑不生效。
- ⚠️ TRUE_DAMAGE 使其绕过 `global_hurt_damage` 与 `damage_multiplier`。

### 2.8 Routers / 路由器
- `script/damage_router.gd`（静态）：
  - `converted_damage(player, source)` = `max(1, int((bullet_damage+ally_damage_add)*summoned_damage*global_damage*ally_damage_mult))`。
  - `source_tag(faction)`：玩家方→`CONVERTED`，否则 `ENEMY`。
  - `resist_factor(pct)=1-clamp(pct/100,0,1)`。
  - 击退递减：`KNOCKBACK_RESIS_SOFT=70, CAP=90, SCALE=50`；`diminish_resist` 线性→指数饱和；`apply_knockback_resist` 硬顶 100；`diminishing_factor` 保持因子。
  - `MELEE_KNOCKBACK_MULT=1.5`；`melee_knockback_mult(damage_type)`。
  - `scaled_damage(source_faction, base, node)`：玩家方走 `converted_damage`，否则原值。
- `script/convert_router.gd`：唯一静态 `refresh(target)` —— 若目标 `is_converted` 则 `refresh_converted_buff()`。
- `script/extra_damage_manager.gd`（autoload `ExtraDamage`）：见 `ARCHITECTURE.md` §1.8。

### 2.9 Damage-type specifics / 分类型处理
- **Fire DOT**：`EnemyBuffManager` 每 `FIRE_DOT_INTERVAL/layer` tick，伤害 `FIRE_DOT_BASE_DAMAGE * dot_damage * global_damage * layer * 1.2^floor(layer/10)`（`enemy_buff_manager.gd:116-136`）。
- **Poison DOT**：`entry["value"] * dot_damage`，`POISON_DAMAGE`（`:142-148`）。
- **DOT 跳伤复用槽（2026-10-02）**：`add_damage_data(base, type, as_extra=false, slot=null)` 用 `DamageData.fill(slot, …)`；fire/poison tick 各传成员槽 `_fire_dot_ddata`/`_poison_dot_ddata`（消费方均在 `take_damage` 内同步读取，不跨跳持有）。chill 走 `request_extra_damage`，嵌套时会进 `_pending_extra` 暂存，**必须 `slot=null` 每次新建**。`fire_diffuse.fire_dot_add` 的 `value` 数组由每敌一次改为每激活一次。
- **Chill**：减速 buff + 近战命中按实际近战伤害 × 层数复利 `1.1^layer` 追加伤害（`:88-102,150-154`）。
- **Explosion**：`ExplosionDamage extends HitBox`（`script/explosion_damage.gd`）：收集敌对 hurtbox，Timer 超时后对每个目标发**同一个** `damage_data`。玩家侧爆炸的「爆炸伤害」加成已**收口**在该节点：`add_damage_data()` 对 `damage_type` 含 `EXPLOSION_DAMAGE` 且 `source_type` 非空、`Faction.of_source()==PLAYER_SIDE`（`PLAYER`/`EQUIP`/`CONVERTED`/`SUMMONED`）的伤害，`duplicate(true)` 后乘 `player.stats.explosion_damage`（低倍率保底 1）；`NEUTRAL`（`oil_barrel`/`enemy_tank`）与 `ENEMY` 不吃。判据见静态 `should_apply_player_explosion_bonus` / `apply_player_explosion_bonus`（`:103-142`）。各创建点（`ink_cartridge`/`matcha_ramune`/`cherino_matryoshka`/`kasumi_drill`/`ayane_as`/`shiroko_drone_icon_2`/`yuzu_bullet`）**不再手写** `* player.stats.explosion_damage`；yuzu/hibiki 迫击炮弹（共用 `yuzu_bullet.gd`，`:95-99`）在爆炸本身打 `EXPLOSION_DAMAGE` 标签，PS 不再给全部子弹打标。变体：`enemy_explosion_damage.gd`、`fire_field.gd`、`enemy_fire_field.gd`。
- ⚠️ `GameEvents.enemy_critical_hurt/fire_hurt/explosion_hurt/poison_hurt/normal_hurt` **无发射者**（遗留）；`entity_ENEMY.is_*_hit` 为只写。

### 2.10 Floating damage text / 伤害数字显示
- 敌人伤害数字由每个敌人身上的 `script/enemy_hurt_floating_text.gd`（场景 `script/enemy_hurt_floating_text.tscn`，多数敌人场景实例化）**聚合**，而非逐次弹出：`health_component.damage_taken` → 按样式（前缀+颜色+字号）合并进 `_pending`，再统一 `_flush()` 出飘字（`enemy_hurt_floating_text.gd:47-70`）；离屏敌人直接跳过（`_on_screen`）。
- **驱动 tick**：`GameEvents.global_time_count`，由 `ui/round_timer.tscn` 的 `GlobalTimer`（`wait_time=0.1`，10Hz）发射（`round_timer.gd:173`）；`test_room.tscn` 同为 0.1s。⚠️ **该 tick 被 `EnemyStats`/状态机/子弹等大量系统共用，不可改其频率来降频。**
- **自适应节流（2026-09-27）**：`PoolManager` 在 `_on_global_time_count` 里对 `Engine.get_frames_per_second()` 做 EMA（α=0.2），按档位算出 `text_tick_skip`：`1`(10Hz，FPS≥55) / `2`(5Hz，35–55 滞回带) / `3`(~3.3Hz，25–35) / `4`(2.5Hz，<18)；每次变档停留 `TEXT_RATE_DWELL_TICKS=10`(~1s) 抑制抖动（`PoolManager.gd:17-28,181-209`）。消费者：`_on_tick` 累计 `_tick_accum`，达到 `skip` 才 flush；`skip=1` 保留首击即时反馈，`skip>1` 时首击不立即弹、只由 tick 节流合并（`enemy_hurt_floating_text.gd:49-73`）。仅作用于敌人聚合伤害数字，不含玩家/道具/旧直连敌人的飘字。
- **手动上限（2026-10-03，设置项）**：`Game.damage_text_freq`（存 `config.ini` `[game]`，默认 `4`）：`0`=关 / `1`=低(上限 skip4) / `2`=中(3) / `3`=高(2) / `4`=最高(1)。`PoolManager.get_text_tick_skip()` = `max(手动上限, FPS 自适应 _text_tick_skip)` —— 手动档是**上限**、自适应只在此基础上再降（更疏），不会更密；`0` 直接返回 0，消费者清空 `_pending` 停止飘字（避免 `skip=0` 时 `0>=0` 每 tick 都 flush）。UI 在 `ui/game_option.tscn` Graphics 第 3 行（`DamageFreq` 滑条 + `DamageFreqValue` 数值），`script/game_option.gd:_on_damage_freq_value_changed` 写盘；滑条场景 `ui/damage_freq_slider.tscn`（触屏按 x 比例吸附、桌面走 HSlider 原生；`project.godot` 关闭了 `emulate_mouse_from_touch`）。

### 2.11 Effect frequency / 特效频率节流
- **设置项**：`Game.effect_freq`（`config.ini [game]`，默认 `4`）：`0`=关 / `1`=×4间隔 / `2`=×3 / `3`=×2 / `4`=×1(最高)。最短间隔 = `基准间隔 * 手动系数 * FPS 系数`，FPS 系数只增（帧越低越大）；与伤害数字共用 `_fps_ema`（`PoolManager.gd` 的 `_fx_manual_mult/_fx_fps_mult/_fx_interval_ms`）。
- **两种粒度**：固定类按 `category` 全局一个间隔（`fx_allowed(category)`）；按实体类按 `[category, body]`（`fx_allowed_body(category, body)`），多敌人互不挤占。`base_ms<0` 时取 `FX_BASE_MS[category]`。
- **分类/基准/接入点**：枪口闪光 `&"muzzle_flash"`(25ms，`player_gun.gd`、`script/enemy_gun.gd`、`enemy_gun_5/7/8.gd`、`tank_gun_1.gd`、`goliath.gd`、`charge_laser_gun.gd`、`turret_summoned.gd`、`luminous_nova.gd` 的调用点包 `if PoolManager.fx_allowed(&"muzzle_flash")`)；命中火花 `&"hit_spark"`(40ms，`scenes/bullet/hit_flash.gd:active_state()` 拦截并 `idle_state()`，覆盖 `hit_flash`/`hit_flash_2`)；子弹烟 `&"bullet_smoke"`(50ms，`bullet_smoke.gd`/`bullet_smoke_2.gd:smoke_anim()`)；爆炸粒子 `&"explosion"`(50ms，`script/explosion.gd:shoot_particles()`)；地面涂装 `&"floor_paint"`(80ms，`scenes/update_item/ink_cartridge.gd`)。
- **跟随类**（燃烧/中毒/恶寒/策反/蒸汽）只在 `PoolManager.spawn_fx()` 内拦：`effect_freq==0` 跳过；同一 `body` 已有该类 FX 在飞则跳过（扫池 `is_idle==0 and target==body`）；再走按实体间隔 `FX_FOLLOW_BASE_MS=200`。**不改调用点**（`enemy_buff_manager.gd:134/150/158` 每 DOT tick、`entity_ENEMY.gd:274` 每次策反都会调 `spawn_fx`，是高频来源）。
- **受击闪白独立设置（2026-10-03）**：`Game.hit_flash_freq`（`config.ini [game]`，默认 `4`，档位同 `effect_freq`）**完全独立于** `effect_freq`。`PoolManager.hit_flash_allowed(body)` = `HIT_FLASH_BASE_MS(60) * _fx_manual_mult_of(hit_flash_freq) * _fx_fps_mult()`，**按实体**用 `_fx_body_last_ms`（key `hit_flash_white:<id>`）；`script/health_component.gd:151` 调 `owner._hurt_flash()` 前判它。`effect_freq=0` 时闪白仍按自身档位决定；`hit_flash_freq=0` 才停闪。
- ⚠️ FX 节点 `is_idle` 初值不统一（`hit_flash`=1，`bullet_smoke`/`shoot_flash_2`=0）。在 `active_state()`/`smoke_anim()` 内「拦截即不播」时必须调 `idle_state()`，否则永久占池槽。UI 在 `ui/game_option.tscn` Graphics：伤害数字（第 3 行 `DamageFreq`）、特效（第 4 行 `EffectFreq`）、受击闪白（第 5 行 `HitFlashFreq`），均复用 `ui/damage_freq_slider.tscn`，`script/game_option.gd:_on_*_freq_value_changed` 写盘；档位名复用 `damage_freq_*`，新增 key `option_effect_freq` / `option_hit_flash_freq`。

---

## 3. Buff system / Buff 系统

### 3.1 `Buff` 资源 — `resources/buff/buff.gd`
- 字段：`id, icon, name, ability, remove_by_layer=false, description, audience=Faction.ANY, is_debuff=false, modifiers: Array[Dictionary], consume_event="", component_scene: PackedScene`。
- **没有 duration / max_layer / stack / value 字段**：时长、层数、数值由调用方以 `value: Array` 传入。
- `ability`：直接加到宿主某属性字段（`buff_manager_base.gd:260-261`）。
- `remove_by_layer=true`：到期减 1 层而非删除（fire/poison/chill 用）。
- `audience` 过滤可获得者；`consume_event` 命名信号，匹配信号触发时消耗 1 层/移除。
- `component_scene` 可选，持有一个 `BuffComponent`。

### 3.2 `BuffComponent` — `resources/buff/buff_component.gd`
- 接口 `setup(manager, body)` / `activate(entry)` / `refresh(entry)` / `deactivate()`；到期还会调 `on_timeout(entry)`。
- 现存 4 个（`resources/buff/components/`）：`critical_sure_component`（弹匣不满则移除）、`debt_component`（按 `value` 索引改 `ability_mult`；硬币加成由 `entry["raw_value"][3]` 开关，0/1，非 `erase_time`）、`last_stand_component`（99999 命、周期自伤、击杀回血；**成功=非超时移除（回满血 / `round_end` / `buff_clear`）时 `manager.buff_success.emit(resource)`**——取代旧 `last_stand_buff.gd:clear_buff()` 的 `emit_player_buff_success`，由 `PlayerBuffManager` 转发，供 `tsurugi_ps` 加永久加成）、`player_fire_dot_component`（玩家侧燃烧 DOT）。
- 组件成功广播契约（2026-10-08）：组件只 `manager.buff_success.emit(buff)`，**不直接触碰 autoload**；`PlayerBuffManager._relay_buff_success` 负责转发到 `GameEvents.player_buff_success(buff: Buff)`。`deactivate()` 把 autoload/body 清理抽到可覆写的 `_teardown()`，并带 `!= null` 短路守卫，使编辑器 `@tool` 测试（autoload 为占位实例）可隔离覆盖。

### 3.3 `apply_buff(buff, value, source_id)` 的 `value` 语义（`buff_manager_base.gd:69`）
- `value[0]` → base `max_layer`；实际 `entry["max_layer"] = _scale_max_layer(value[0])`，玩家版 = `max(1, floor(value[0] * stats.buff_layer_mult))`（`player_buff_manager.gd:23`），且**只在创建 entry 时定格**，之后不随属性变化重算。
- `value[1]` → `entry["value"]`（magnitude）。
- `value[2]` → 时长**秒**，转 tick：`erase_time = value[2] * TICKS_PER_SECOND * _duration_multiplier(buff)`（`TICKS_PER_SECOND := 10`，`:11`）。`_duration_multiplier` 默认 1；仅 `PlayerBuffManager` 覆写为 `body.stats.buff_duration`，且 `Buff.is_debuff=true` 时仍返回 1（有害 buff 不享受「有益 buff 持续时间」属性）。
- 全局 tick 信号 `GameEvents.global_time_count`（10Hz，由 `round_timer.gd:173-174` 与 `test_room.gd:117` 发射）。
- `entry["raw_value"]` = 原始 `value` 数组副本（`buff_manager_base.gd:225`）；供 component 读取约定外的扩展位（如 `debt_component` 用 `raw_value[3]` 作硬币开关）。
- 重复施加同 id：`layer < max_layer` 时加层。玩家 `stats.buff_layer_mult` = 场景导出基准 + `PlayerData.buff_layer_mult_add`（`PlayerData.gd:374`，`base_buff_layer_mult` 由 `get_player_base_ability()` 快照），**两者相加**；给「+上限」被动累加 `buff_layer_mult_add` 时，若场景基准已非 1 会叠加放大。
- **source-capped stacking**（仅 chill）：按 `source_id` 各记 `source_layers/source_caps`。

### 3.4 `BuffStatMap` — `script/buff_stat_map.gd`
- `PLAYER=0, ENEMY=1, SUMMONED=2`；`MAP[host_kind][logical_key] -> stat_field`；`resolve(host_kind,key)`。
- 例：`damage_mult` → 玩家 `bullet_damage_mult` / 敌 `ally_damage_mult` / 召唤 `summoned_damage_mult_add`；`hurt_mult_mult` → `hurt_mult_mult` / `global_hurt_damage_mult` / `global_hurt_damage_add`。

### 3.5 `buff_router.gd`
- 静态门面：`apply_buff/remove_buff/refresh_buff/resolve_manager/is_ally`；`resolve_manager` 先查属性 `player_buff_manager`/`summoned_buff_manager`/`enemy_buff_manager`，再按节点名 `find_child`。

### 3.6 每阵营 manager
- `BuffManagerBase`（`scenes/manager/buff_manager_base.gd`）：信号 `buff_applied/buff_layer_changed/buff_consumed/buff_expired/buff_success`（`buff_success(buff: Buff)` 由组件在"成功移除"时发出）；`body=get_parent()`；`host=_resolve_host()`（默认 `body.get("stats")`）；`_host_refresh()` 打脏并在 `_process` 调 `host.update_body_ability()`（**下一帧生效**）。
- `PlayerBuffManager`：`_resolve_host() = PlayerData`，`_host_kind()=PLAYER`；`_host_refresh()` 改为**每帧合并**的 `call_deferred`（高频 buff 如加特林每发只排一次 `PlayerData.update_player_ability()`，帧末生效），层上限用 `body.stats.buff_layer_mult`；`_relay_buff_success()` 把基类 `buff_success` 转发到 `GameEvents.player_buff_success`（角色 PS 的订阅入口）。
- `EnemyBuffManager`：`_host_kind()=ENEMY`；内建 fire/poison/chill DOT；`@export health_component`；需要 `player`（组 `"Player"`）。
- `SummonedBuffManager`：`_host_kind()=SUMMONED`，host=`body.stats`。
- `BuffCard`（`ui/BuffCard.gd`）：`active_state()` 开 `_physics_process`、`idle_state()` 关；池中空闲卡不再每物理帧空转（敌人场景普遍带 `BuffBox`，buff 多时会创建大量卡，2026-10-02）。
- **buff 卡池 O(1) 取用（2026-10-02）**：`PoolManager` 维护空闲栈 `_idle_buff_cards`/`_idle_buff_set`，`BuffCard.release_to_pool()` 末尾 `push_idle_buff_card(self)`（按 `instance_id` 去重、`[id,card]` 入栈），`get_buff_pool()` 改为出栈（无效项跳过并清 id）；栈空才退回 `_scan_buff_box_idle()` 线性兜底。`BuffManagerBase._obtain_buff_card`（`buff_manager_base.gd:362`）逻辑不变：仍先 `_find_idle_card(本容器)` 再取全局池。此前 `get_buff_pool` 是**对全局 `buff_box` 的裸线性扫描**，敌人死亡 `release_idle_cards()` 把卡 reparent 回全局池后池子越滚越大 → 每次取卡 O(N)（Profiler 曾 `_obtain_buff_card 2.47ms×12`）。`lear_buff_box()` 一并 `clear_idle_buff_cards()`。

---

## 4. Resource data model / 资源数据模型

| Class (`class_name`) | File | Key fields |
|---|---|---|
| `PlayerCard` | `resources/player/player.gd` | `name, weapon, sprite, halo, color, description, voice_name, id, branches: Array[PlayerCard], scene_path` |
| `PlayerGroup` | `resources/player/player_group.gd` | `player_group: Array[PlayerCard]` |
| `PSCard` | `resources/player/PS/ps_card.gd` | `weapon_icon, t_level: Array[String]` |
| `EnemyCard` | `resources/enemy/enemy.gd` | `id, body: PackedScene, description, icon` |
| `Equip` | `resources/equip/equip.gd` | `id, icon, value_1_name/id/value(Array[int]), value_2_..., value_3_..., name, description` |
| `ClothesCard` | `resources/clothes/clothes_card.gd` | `id, id_name, name_1/2, user_name, icon_1/2, cost, sprite` |
| `GameMode` | `resources/game_mode/game_mode.gd` | `game_mode_name, game_mode_id, game_mode_icon, gamemode_conflicting: Array[String]` |
| `Level` | `resources/level/level.gd` | `level_name, level_id, level_name_color, level_color, level_num, level_hp, level_damage, level_score_mult, level_reward` |
| `RaidFormwork` | `resources/raid_formwork/raid_formwork.gd` | `enemy: Array[EnemyCard], enemy_id, enemy_num, spawn_position: Dictionary` |
| `CharacterCard` | `resources/shop/character/character_card.gd` | `cost, name_1/2, character_sprite, weapon_name/type_name/icon, school_name/icon, id, group` |
| `SupportCard` | `resources/support/support_card.gd` | `support_id, support_name/name2, ex_cost=50, unlock_cost=20, max_lv=100, pa_ability, ability_id, pa_value: Curve, support_pack: PackedScene, ex_voice, lv_voice` |
| `TalkFormwork` | `resources/talk/talk_formwork.gd` | `talk_text, sprite_num, voice_name, voice_num, voice_time` |
| `AbilityUpgrade` | `resources/upgrades/ability_upgrade.gd` | `id, icon, name, rare(0-2), order_num, special_rules, description, forward, negative, item_tags(bit flags), tags: Array[String], weight=1.0` |
| `SceneData` (save) | `script/scene_data.gd` | `save_version, player_pyroxenes, character, group, clothes_group, now_clothes, game_mode, support_savedata, game_support` |

- **身份键 = `id`/`*_id` 字符串，通常等于 `.tres` 文件名**（`resources/enemy/sweeper.tres` → `id="sweeper"`）。
- 显示文本两条路：① 直接内嵌字符串（`name="负债buff"`）；② 按 **`<id>_name` / `<id>_description` / `<id>_forward` / `<id>_negative`** 本地化键约定（`ui/ability_upgrade_card.gd:75-78`）。
- `.tres` 结构：`[gd_resource type script_class load_steps format uid]` → `[ext_resource]` → `[sub_resource]` → `[resource]`（`load_steps = 1 + #ext + #sub`）。见 `CONVENTIONS.md` §3。
- 加载方式：`@export` 数组（编辑器中配置）、`preload`、按 id 动态 `load("res://resources/<type>/<id>.tres")`；`ui/enemy_test_menu.gd:24-40` 做目录扫描。**buff 无目录扫描**，一律显式引用。

---

## 5. Entities / 实体

### 5.1 Player — `script/player.gd`
- 所有角色场景（20 个）根节点共用此脚本（`class_name Player`）；角色目录不再自带 `<char>.gd`（仅 `hina`/`aris_armed` 例外有各自根脚本）。
- 节点结构（如 `scenes/player/momoi/momoi.tscn`）：根 `CharacterBody2D`（组 `Player`） + `Stats` + `StateMachine` + `Graphics/Gun`(`PlayerGun`) + `HurtBox`(`is_player=true`) + `HealthComponent` + `PickBox` + `Kick` + `PlayerBuffManager` + `<Char>PS` + `GameUI` + `Camera2D`。
- `StateMachine`（`scenes/player/StateMachine.gd`）只驱动 owner：`current_state` setter → `owner.transition_state()`；`_physics_process` 循环 `owner.get_next_state()` 直到稳定，再 `owner.tick_physics()`。
- 玩家状态 enum：`IDLE, RUNNING, JUMP, FLY, FALL`（`player.gd:4-10`）。
- 输入（`_unhandled_input` `:119`）：`move_jump`→跳；`pause`；`fire`→`gun.is_shoot`；`kick`；`reload`。控制开关 `reset_control_flags()`（`:97`）连 `GameEvents.round_start`，回合边界在 `hp>0` 时复位 `player_stop/can_control/can_move/can_jump`（防覆盖层/异常路径残留锁死）。
- 属性合成：`PlayerData.get_player_base_ability()` 快照 → 各种 add/mult → `update_player_ability()` 重算。重算期间来自信号回调的嵌套调用会被合并（`_ability_depth`/`_ability_pending`，至多 8 代），避免递归级联；`hp/max_ammo/pick_up_range_changed` 仅在对应数值变化时发出。

### 5.2 Enemy — `script/entity_ENEMY.gd`（真正的基类，⚠️ **不是** `scenes/enemies/base_enemy.gd`，后者是 2 行空 stub）
- 字段：`pool_id`, `stats: EnemyStats`, `enemy_buff_manager`, `body_part: Array[EnemyPart]`, `faction=ENEMY_SIDE`, `is_idle`(1=池中/关), `frozen`, `aggro_override`, `route_target`(路线目标，path 敌人专用), `convert_gauge`。
- `idle_state()` 全量复位；`active_state()` 重启并 `stats.spawn_hp()`。
- `get_target()`：缓存 + 按物理帧节流（`_target_cache`/`TARGET_CACHE_FRAMES≈0.1s`，**null 也缓存**；原选择逻辑抽到 `_select_target()`）；玩家方（策反）取最近敌人，否则按优先级 `aggro_override` → `route_target`（路线型敌人）→ `player`。`active_state()`/`idle_state()` 重置缓存（`enemy_tank` 未调 super，已自行重置）。
- 策反索敌 `get_nearest_enemy()`：先扫 `enemy_body`（贴脸接触）取最近，否则 `Targeting.nearest_enemy(global_position)`（`script/targeting.gd` 按物理帧缓存，且只取 `PoolManager` 活跃敌人、天然排除 `is_idle`/`EnemyPart`/`PLAYER_SIDE`）；**不再 `get_nodes_in_group("Enemy")` 全组扫描**（2026-09-29，后期大量策反敌人的卡顿根因）。
- 待机：`is_standby()` = 策反且 `get_target()==null`；子类据此**不移动、炮塔/枪/头不转向、不射击**（`automaton`/`tester_automaton_shield`/`enemy_tank` 短路移动与瞄准；`sweeper`/`sandbag` 停在自身移动）。
- 策反 `apply_conversion_power()`：用 `convert_resist/threshold`，成功后 `faction=PLAYER_SIDE`、入组 `Converted`、加 `converted_buff`、改 `CONVERTED` 伤害来源；`converted_buff` 到期回退；打断时 10% max HP TRUE_DAMAGE。
- 死亡：`_on_enemy_stats_is_dead` → `_coin_drops()` + `on_dead()`；`settle_converted_clear()` 回合清理给币。
- 具体敌人 `extends Enemy`（如 `automaton.gd`, `sweeper.gd`）声明自身 `enum State` + `get_next_state`/`tick_physics`/`transition_state`，由 `EnemyStateMachine` 每 3 tick 重评 AI（`script/EnemyStateMachine.gd`）；`frozen` 时零速早退。多数敌人场景复用少数脚本：`sweeper.gd`（mystic/red/enhanced/modded_sweeper）、`automaton.gd`（soldier_*/mp/menacing/tester_automaton*）、`tester_automaton_shield.gd`（droid_helmet_smg）、`enemy_tank.gd`、`sandbag.gd`（`modded_sweeper.gd`/`enhanced_sweeper.gd` 经核未被任何 tscn 引用，属死代码，已于 2026-10-07 删除；两场景根脚本本就是 `sweeper.gd`）。
- `enemy_tank.rand_target_position()` 随机巡逻点改为有限次尝试（`MAX_ATTEMPTS=20`）+ 最接近 `rand_length` 兜底，修正原 `randi_range(0, size)` 越界与潜在长循环。
- **路线型敌人（`EnemyCard.route != null`，如 `red_sweeper.tres` 挂 `enemy_path.tscn`）**：路线目标用**独立字段 `route_target`**，不再只靠改写 `player`——即使任何逻辑重置 `player`，路线也不会丢。`spawn_anim.spawn_enemy_body()` 解析路线来源 = `path_spawn` 显式传入的 `path`（为 null 时兜底 `DEFAULT_ROUTE`）否则 `EnemyCard.route`；`_setup_path()` 挂 `enemy_path` 子节点（复用已存在的），`enemy_path.set_body_target()` 写 `enemy_body.player`（兼容旧读取）**和** `enemy_body.route_target`（权威）。`route_scene == null` 或 `route_target` 未设都会 `push_error`（不再静默失败）。`enemy_path.idle_state()`（死亡）与 `entity_ENEMY.idle_state()`（池化）清 `route_target`，每次生成重设。数据驱动后 `path_spawn`/`enemies_spawn`/`raid_spawn`/`test_room.spawn_test_enemy()` 全部自动为路线敌人挂路线。

### 5.3 EnemyStats — `script/EnemyStats.gd`
- 信号 `hp_changed/hp_hurt/is_dead`；`hp` setter 通过 `hp_change_cd`/`hurt_count` 批处理，emit `enemy_hurt_hp`/`enemy_dead_hurt_damage`/`enemy_dead_score`/`is_dead`。
- ⚠️ setter 中 `hurt_hp = hp - v; if hurt_hp > hp: emit_enemy_dead_overflow_hp(...)` 用旧 `hp` 比较（`:73-76`），与 `HealthComponent` 的 overkill 重复/不一致。
- ⚠️ `hurt_resis` 对敌方减伤**无效**（公式被注释掉，`health_component.gd:108-110`），仅 `global_hurt_damage` 生效；`hurt_resis` 只影响飘字 "Resis " 前缀。
- `update_body_ability()`：`Enemy_damage`/`Enemy_bullet_damage = max(1, ceili(base * Enemy_damage_mult))`，`base<=0` 保持 0（`shield`/`sandbag` 无伤害单位）。⚠️ 旧实现用 `int()` 截断，会把低基数敌人压成 0（如 base1 × 难度 0.8 = 0），2026-09-27 改为 `ceili` 向上取整（`:161-162`）。
- **移动加速度 `move_acceleration()`（2026-10-02）**：`maxf(base_MAX_SPEED, MAX_SPEED) / maxf(SPEED_TIME, 0.001)`。以 `base_MAX_SPEED` 为下限——恶寒把 `MAX_SPEED` 压到 `0.1×base` 时加速度**不再随之归零**（否则 `move_toward` 无法减速、击退后持续滑行）；仅当当前 `MAX_SPEED` 大于基准（如 `goliath` fever `MAX_SPEED_mult=1.5`）时才提高。7 个敌人脚本统一改用 `stats.move_acceleration()`（`automaton`/`sweeper`/`tester_automaton_shield`/`enemy_tank`/`sandbag`/`boss/goliath`/`boss/erosion_tower`）；`player.gd` 仍用旧式（玩家 `MAX_SPEED` 有 `clamp(50,…)` 下限，不受影响）。

### 5.4 Summoned — `script/summoned.gd`
- `SummonedFollowers`（跟随玩家、自动索敌开火）、`TurretSummoned`（炮台，固定/随机点位）、`SummonedGun`（`luminous_nova.gd`）、`KeiSummoned`（支援 kei 召唤物，`scenes/player_support/kei/kei_summoned.gd`）。
- `idle_state()` 隐藏并放到 `(10000,-10000)`、清 buff、停处理。
- 索敌列表 `enemy_body`：`_on_area_2d_body_entered/exited`、`_on_target_converted` 只置脏 `_mark_sort_dirty()`，同帧多次变更由 `sort_enemy.call_deferred()` **合并为每帧最多排一次**；比较器改用 `distance_squared_to`（省 sqrt）。`enemy_body[0]` 为最近目标（`summoned_follower.gd:78-89`、`turret_summoned.gd:82-85` 读取）（2026-10-02）。
- `SummonedStats`：`summoned_damage, summoned_damage_mult, global_hurt_damage, ...`；`update_body_ability()` 从 `PlayerData.player.stats.summoned_damage` 取值。**不再各自订阅** `player_ability_changed`（原先每个召唤物订一次 → O(n) 扇出）。
- `SummonedManager`（组 `SummonedManager`）用 Area2D 跟踪召唤物，emit `summoned_changed`；`_ready` 订阅 `PlayerData.player_ability_changed`，在 `_refresh_summoned_stats()` 里批量刷新 `summoned_group` 各 `stats.update_body_ability()`。
- 可受伤召唤物（挂 `SummonedHealthComponent`：`mobu_trinity`/`kei_summoned`/`utaha_turret_body`）默认**受伤不击退**、**转发伤害给玩家时不带击退**；两行为分别由 `knockback_on_hurt` / `transfer_knockback` 开关控制（受伤击退另有 `knockback_mult` 百分比系数），详见 §2.5。召唤物无敌帧与玩家同构：跳跃=闪避档（挡激光），受击=普通档（激光照打）。
- **联机召唤物镜像（mod，2026-10-07）**：`CoopSummonedProxy` 镜像端 `_disable_remote_simulation()` 关掉 StateMachine + physics → 本体 `SummonedFollower.tick_physics/transition_state` 不跑，故**动画/朝向/瞄准/开火必须由 proxy 直接驱动**。快照 `send_summoned_state` 除位置/速度/朝向角外，增 `state`(IDLE/RUNNING/JUMP) + `facing`(±1)；`SummonedFollower` 实现 `get/apply_network_visual_rotation`（枪口角复用 rotation 通道）与 `apply_network_state(state,facing)`（只切 `sprite_2d` 动画/`graphics.scale.x`/`halo.flip_h`/`jump_anim`，不移动不开火）；开火由拥有者在 `SummonedGun.shoot_bullet` 时 `notify(on_summoned_action,...)` 广播，镜像端 `network_play_action("shoot")` 播后坐（子弹本体仍由 `ProjectileSpawner` 广播）。`TurretSummoned`（`extends Summoned`）早有同名接口，不受影响；kei/mobu 等 `SummonedFollower` 全部受益。
- **召唤物固有等级/经验系统（2026-10-08）**：等级从「utaha 角色被动」改为**召唤物自身固有属性**，任何来源（utaha 近战 / 未来道具）经统一入口 `Summoned.add_summon_exp(amount, source_id, damage_add_override)` 喂经验（`script/summoned.gd:83-106`）；`set_summon_level/add_summon_level` 供道具直接给级。配置在 `SummonedStats`（`level_enabled` 默认 true、`max_level`、`level_damage_add` 默认 **6**、`level_up_exp_base=3`、`level_exp_growth=10`），阈值/曲线等价旧 utaha 逻辑（原 `utaha/melee.gd` 的 `summoned_group` 字典已删）。每级加成写 `stats.summoned_damage_add`（与召唤物 buff 同路叠加）：`damage_add_override>0` 用之，否则固有 `level_damage_add` → utaha 近战传 `up_v`（6，其被动升级后 12）覆盖固有 6。`summon_level_changed(state)` 信号驱动头顶显示。
- **召唤物等级头顶显示（2026-10-08）**：`scenes/summoned/summon_level_display.tscn` + `script/summon_level_display.gd`，外观复刻旧 UtahaPS 进度节点（LVNum / LEVEL UP↑ / 竖直 ProgressBar，字体 `BoutiqueBitmap7x7_1.7`）。走**对象池**（pool id `"summon_level_display"`，`PoolManager.IDLE_LIMITS` 16），`Summoned._ready` 经 `_setup_level_display()` 取用/实例化到 `SELayer` 并 `bind(self)`，`idle_state()/_exit_tree()` 释放回池；每帧 `global_position = summon.get_level_display_position()`。高度适配用**场景锚点 `LevelDisplayAnchor`（Marker2D，`unique_name_in_owner`）**：mobu/kei 挂在 `%AnimatedSprite2D` 下（随跳跃动画上下），turret 挂根；缺失回退 `global_position + (0,-level_display_height)`。旧 UtahaPS 进度节点保留但隐藏，`show_progress` 不再被调用。
- **联机召唤物固有等级 / 友方近战击退（mod，2026-10-08）**：镜像召唤物的 `HurtBox` 被 `CoopSummonedProxy._enable_melee_detect()` 恢复为「探测专用」（`collision_layer=8192` summoned_box、`monitorable=true`、`monitoring=false`、形状启用），使**本机近战 HitBox 能检测到队友召唤物镜像**。两个闸门：① `summoned_damage_interceptor` → 镜像收到友方近战（`PLAYER`+`MELEE_DAMAGE`）则转发 `{net_id, kb_force, kb_dir}` 给拥有者（`_server_summoned_melee_kb`/`_remote_summoned_melee_kb`），拥有者对真实召唤物 `apply_network_melee_knockback`；其它镜像伤害丢弃。② `summoned_upgrade_interceptor` → 镜像收到升级则转发 `{net_id, amount, source_id, override}`（`_server_summoned_upgrade`/`_remote_summoned_upgrade`），拥有者调 `add_summon_exp`。拥有者 `summon_level_changed` → `_on_local_summon_level_changed` → host 直发 / client 经 `_server_summoned_level_state` 中继 → 各端镜像 `apply_network_summon_level_state`（驱动头顶显示）。**来源无关**：未来道具升级召唤物自动复用该通道。所有 `any_peer` handler 有 `_server_sender_ok` + owner 校验 + `clampi`。

### 5.5 Stats — `script/Stats.gd`（玩家）
- 分类：base、coin、bullet、`global_damage`、explosion、`summoned_damage`、`kick_damage`、`equip_damage`、status(`dot_time/dot_damage/convert_*`)、defense(`hurt_resis/hurt_mult`)、shake、`buff_layer_mult`。
- 拾取相关：`pick_up_range`（PickBox 半径）、`pick_up_speed`（长按拾取速度乘区，默认 1；由 `PlayerData.base_pick_up_speed × pick_up_speed_mult` 重算）。
- `hp` setter：`life_num` 消耗/复活，或在 `life_num<=0` 时 `GameEvents.emit_game_over(true)`（`:142-161`）。
- ⚠️ 少数 `crit_chance_bonus` 字段（三处 health component）无读者。

### 5.6 Support — 支援角色
- 数据：`SupportCard`（`resources/support/support_card.gd`）定义被动（`ability_id`：PlayerData 变量名 + `pa_value: Curve` 等级曲线）与主动（`ex_cost`、`support_pack`）。
- 装配：`SupportData.game_add_support()`（`script/support_data.gd:59-74`）实例化 `support_pack` 到 `"PlayerRoot"` 并注入 `ins.support_card`，UI 挂 `"GameUI".support_box`；被动数值不再由 `SupportData` 写入。⚠️ `game_support` 可为 `null`（全新档/从未选过支援时初值为 `null` 而非 `null_support`），`game_add_support()` 对 `null` 与 `support_id == "null"` 一律早退；正常流程由 `reset_game_support()`/`Game.load_playerdata()`/`support_select_ui.check_data()` 把 `null` 归一为 `null_support`，避免 HUD 出现空卡与结算 Nil 访问。
- **`SupportCharacter`**（`script/support_character.gd`，`extends Node2D`）：`support_pack` 根基类。`_ready()` 调 `_apply_passive_boost()`（读存档 `support_data[id].LV` → `pa_value.sample(lv/100)` → `PlayerData.set(ability_id, …)` + `update_player_ability()`）与虚函数 `_special_effect()`。
- **`SupportAS`**（`script/support_as.gd`，`extends Node2D`）：局内主动 EX 基类。内聚 `_on_score_owned()`（`enemy_dead_score_owned` 归属充能）、`EX_skill` 输入、`skill_active()/skill_end()` 守卫、`SupportData.now_cost` 归零、`emit_support_ex_*`、`round_upgrade → skill_end`；子类覆写 `_on_ready()/_on_skill_active()/_on_skill_end()`（`_on_skill_active` 可为协程，基类 `await`）。
- 商店升级按钮（`ui/support_ui/upgrade_button.gd`，实例于 `ui/shop_menu.tscn` 的 `support_shop/exp/lv_up`）：1 青辉石 = `SupportData.EXP_PER_PYROXENE`(200) exp；滑条上限 = `min(PlayerData.player_pyroxenes, SupportData.get_upgrade_max_stones())`，确认时 `n = min(滑条值, 所需)` 只花到上限。**满级口径**：`max_exp = SupportData._total_exp_to_lv(max_lv)`，与实际升级阈值同源（`count_exp` 用 `_total_exp_to_lv(now_lv)` 及相邻差算 `last_exp`/`next_exp`），二者严格一致；`get_upgrade_max_stones()` 在 `now_lv < max_lv` 且 `max_exp - now_exp <= 0` 时至少返回 1，避免 99→100 锁死滑条（详见 `docs/LEARNINGS.md`）。交互：悬停展开、移出 2s 收回；滑条区仅拖动，非滑条区点按生效；激活期间按钮后方全屏 `ClickCatcher` 拦截点击即收回（详见 `docs/LEARNINGS.md`）。
- 角色：
  - `ayane`（`scenes/player_support/ayane/`）：根 `Node2D`（`ayane.gd extends SupportCharacter`，特殊效果=刷医疗包），子 `ayane_as`（爆炸铺图）。
  - `kei`（`scenes/player_support/kei/`）：`kei.tscn` 为支援根（`SupportCharacter`，特殊效果=生成召唤物）；召唤物实体拆到 `kei_summoned.tscn`（`KeiSummoned extends SummonedFollower`，承接 aris 起飞携带彩蛋），其子 `kei_as` 承载 EX 光环 buff/射速。
  - `serina`（`scenes/player_support/serina/`）：`serina.gd extends SupportCharacter`（被动 `heal_mult_add`；特殊效果=医疗箱生成概率翻倍且必定落在玩家脚下、长按拾取速度 +100%——写 `PickItemManager.spawn_at_player/spawn_rate_mult` 与 `PlayerData.pick_up_speed_mult`）；子 `serina_as`（EX：施加 `serina_buff`（`ability="heal_mult_add"`, +0.5）8s、每秒回复 5% max_hp（`ignore_heal_mult` 固定值）、期间 `stats.heal_overflow_to_t_hp=true`；视觉参考 `ginseng_doll` 双 `shock_wave_2` 环+上升粒子，改粉色并跟随玩家）。
- ⚠️ kei 的 EX（`kei_as`）挂在**召唤物**上（光环 `Area2D` 需随实体移动），支援根只负责生成召唤物。
- **联机（mod `mods/etn_coop`）支援同步**：支援为"每人各自本地"（选择经 `report_local_support` 同步 `support_id` 到 `support_by_peer`，仅用于可见性/后续扩展；伤害/治疗/子弹仍只在拥有者端）。① **EX 充能归属**：`SupportAS` 改听 `GameEvents.enemy_dead_score_owned(score, owner_peer)`（由 `health_component` 死亡分支在 `not suppress_proc` 时发出）；host 不再为客机击杀充能，客机击杀经 `_remote_enemy_proc(score)` 在客机本机发该信号。② **kei 范围 buff 跨端**：`kei_as` 光环命中远端玩家镜像时经 `ExtensionHooks.player_buff_apply/remove_interceptor` 转交 mod → host 中继 `_remote_player_buff` → 目标端 `BuffRouter` 作用于真实玩家；EX 结束/离开范围/`_on_skill_end` 兜底移除。③ **EX 光环视觉镜像**：本体 `SupportAS` 发 `support_ex_active/end`，mod 广播 `_remote_support_ex`，接收端实例化本体 AS 场景后 `set_script(null)` 作纯视觉代理（serina 挂玩家镜像、kei 挂 kei 召唤物镜像），避免 `SupportAS._ready` 污染本机 `now_cost`。④ **kei_buff 多来源（`Buff.source_refcount`）**：`kei_buff.tres` 开 `source_refcount`，`BuffManagerBase` 按 `source_id`（= owner peer id）记录来源集合，**多光环只算 1 层数值、只维持存在**（不叠值），来源独立增删、最后来源离开才移除；卡片层数显示"当前来源数"（仅展示）。断线时 host 广播 `_remote_clear_player_buff_source` → `remove_source_all` 清掉该来源残留。
- 冷却类 buff 的来源独立上限（`enemy_buff_manager._uses_source_caps`，用于 `chill_ring`）与 `source_refcount` 是两套机制：前者按来源叠层加值（各自上限、总层求和），后者多来源只维持存在不叠值。`Buff.per_source_layers` 为通用字段（base `_uses_source_caps` 读它；enemy 额外保留 `chill` 判定）。
- **联机召唤物范围光环（kei / utaha）**：光环拥有者端扫描半径内的**远端召唤物镜像**并转发到其 owner peer 上真实召唤物。本体 `kei_as`/`UtahaPS` 入组 `"CoopSummonAura"` 并实现 `network_summon_aura_info()`（位置=碰撞形状中心、半径=场景 `CircleShape2D`、buff、value、source_id）；mod 连 `global_time_count`(10Hz) → `_tick_summon_auras()` 按 `key="<source_id>|<buff_id>|<net_id>"` diff → `_send_summoned_buff` → host 直发/client 经 `_server_relay_summoned_buff` → 目标端 `_remote_summoned_buff` 对 `summoned_by_net_id[net_id]` 真实召唤物 `BuffRouter.apply_buff/remove_source`。`kei_buff` 走 `source_refcount`（只算一个），`utaha_buff` 走 `per_source_layers`（按来源叠层、移除该来源全部层）。断线按 source 清玩家+本机召唤物。

### 5.7 敌人人数缩放（联机，mod `mods/etn_coop`，2026-10-08）

- **收口点（本体侧扩展点）**：血量/伤害在 `spawn_anim.spawn_enemy_body()`（`script/spawn_anim.gd:96` 前）读 `ExtensionHooks.enemy_spawn_stat_scale()` 注入 `{hp,damage}` 乘数后写入 `max_hp_mult`/`Enemy_damage_mult`/`Enemy_bullet_damage_mult`（部件同系数）——**所有刷怪路径**（`enemies_spawn`/`path_spawn`/`raid_spawn`/Boss 的 `enemy_spawn_launcher`）都经此。数量在 `enemies_spawn.get_level()`（`script/enemies_spawn.gd:48` 后）读 `ExtensionHooks.enemy_spawn_count_scale(now_round,max_round)` 乘到 `round_mult`。
- **mod 公式**（`coop_net.gd`，`N = get_peers().size()+1`，仅 `is_lan_game`；单机返回默认 → 零回归）：
  - 生命 `1 + 0.5·(N-1)` → ×1.5/2.0/2.5（2/3/4人）。
  - 伤害 `1 + 0.1·(N-1)` → ×1.1/1.2/1.3。
  - 数量 `1 + 0.5·(N-1)·taper`，`taper = clamp(1-(now_round-1)/(EARLY_ROUNDS-1),0,1)`、`EARLY_ROUNDS = max_round×0.5`（随关卡变；默认 20 → 第 10 回合归 1.0）。**仅前期加成**，后期归 1 避免性能与 `ENEMY_SPAWN_CAP=80` 压力。
- **同步**：host 权威；`max_hp_mult`/`Enemy_damage_mult`/绝对 `max_hp` 已由 `coop_net.gd:3609/4397` 随快照同步，客机自动跟随，无需新网络字段。客机战斗敌人经 `_spawn_enemy_remote` 生成、不走 `spawn_anim`，不会二次加成；客机被 `_gate_round_enemy_spawn` 拦截不调用数量钩子。
- **边界**：数量钩子对 `path_spawn`/`raid_spawn`（固定 `enemy_quantity`，不经 `round_mult`）不生效；血量/伤害仍生效。Boss 吃血量/伤害系数（数量无意义）。无尽/`hujiu` 的 `now_round` 超过 `EARLY_ROUNDS` 后数量自动归 1。

### 5.8 断线重连（联机，mod `mods/etn_coop` + 中继服务端，2026-10-08）

- **身份**：客户端 `coop_settings.ensure_client_token()`（UUID 持久化 `profile/client_token`）；LAN/Relay 加入帧带 token，host 记 `_peer_token`/`_token_peer`。
- **host 宽限**：`_on_peer_disconnected` 对已握手且有 token 的 peer 进入 `REJOIN_GRACE_MSEC=45s` 宽限——保留 `player_by_peer_id`/`player_scene_by_peer`/`player_name_by_peer`/`team_stats`/`support_*`/`down_peer_ids` 等与镜像（冻结 `player_stop`），超时 `_cleanup_peer`。宽限内 `_check_team_game_over` 直接 return（防其余人倒地误结束）。
- **重连迁移（方案 B：新 id + host 迁移）**：`_old_peer_for_rejoin(token)` 命中旧 id → `_migrate_peer_state(old,new)` 搬移所有 per-peer 字典键、`last_attacker_by_net_id`/`summoned_owner_by_net_id` 引用、镜像 proxy `peer_id`；`_accept_peer` 不再覆盖已迁移角色。ENet 由 host 分配新 id、Relay 由服务端 `next_peer_id` 分配。
- **客机自动重连**：`_on_server_disconnected`/`_on_connection_failed`/心跳超时 → `_begin_reconnect`（保持场景；`close_connection` 在 `_reconnecting` 时跳过 `_reset_run_state` 与清 `_last_join_params`），遮罩 + 冻结 + 退避（1.5→5s）；`_hello_accept` → `_finish_reconnect`；超宽限/拒绝 → `_abort_reconnect_to_menu`。传输释放走 `call_deferred`（严禁在 multiplayer 信号栈内改 peer）。
- **服务端**（`E:\QQfw\js\服务端5.0.py`）：`join_room` 在容量判断前对同 token 的旧 `clients` 先 `remove_peer`（释放名额，修满房误拒 + 半开幽灵占位）并广播 `peer_disconnected(old_id)` 让 host 进宽限；`heartbeat_peers` 主动 WebSocket PING，`PEER_TIMEOUT_MSEC` 无数据即回收半开连接。
- **回合切换冻结（掉线期间不停旧回合）**：host `_reconnecting_peers` 非空时——`_gate_round_end_emit` 暂缓本回合结束（`_deferred_round_end`）、`_maybe_finish_round_upgrade` 暂缓升级页推进；重连/超时后 `_on_rejoin_settled` 解冻（补发 `emit_round_end` / 重判升级）。重连识别后若 host 正处于升级页（`_round_upgrade_active`），补发 `_remote_round_end`+`_remote_round_upgrade`，让重连者进入升级页，不丢升级（客机 `_in_round_upgrade` 幂等；`_on_round_upgrade_end_local` 复位）。各端显示轻量等待遮罩（`wait_reconnect_show`/`wait_reconnect_hide` → `coop_round_wait` light 模式：无背景遮罩 + 小字号(12)顶部居中 + 鼠标穿透、世界仍可操作；名字按视口宽度换行不溢出）。
- **局限**：房主自身重连未做。详见 `LEARNINGS.md`。

### 5.9 联机网络补偿调优 / 诊断（mod，2026-10-08）

- **插值延迟下限调低**：`coop_snapshot_buffer.gd:compute_delay` 的 floor 从 `2×snapshot_interval` 降到 `1.35×`（`DELAY_BASE_MULT`），`DELAY_MIN` 0.05→0.033；`observed` 先封顶 `2.2×interval` 再乘 `1.2`（避免静止实体 600ms 心跳把 `observed` 抬到上限），jitter 系数 2.0→1.5。敌人/玩家固定滞后由 ~132/100ms 降到 ~89/68ms；LAN 与 Relay 均受益，**不改发送频率**。用于玩家/敌人/召唤三处代理。
- **中继发送失败诊断**：`coop_relay_peer.gd:_put_packet_script` 检查 `_ws.send()` 返回，失败 `send_fail_count++` 并节流告警（不再静默 `return OK`）；`coop_net.gd:get_network_debug_text`（F4 HUD）显示 `send_fail`。未加重试队列/缓冲参数调整。
- **sim-report 增 `delay=%.0f`**：按 `STATE_SEND_INTERVAL` + 当前 rtt/jitter 计算代表性插值延迟，供回归对比（`coop_sim_regression.ps1` 按字段名解析，不受影响）。
- **实测基线（同机两 peer，`--coop-*` headless）**：LAN RTT ~4–10ms；默认中继 `mc.yqst.top:32085` RTT ~115ms（基础 TCP RTT ~31ms）→ **中继链路/服务器转发**为主要延迟来源，mod 自身处理（LAN 回环）可忽略；插值约为固定加成。详见 `LEARNINGS.md`。

---

## 6. Managers / 管理器

| Manager | Responsibility / 职责 | 关键 API/信号 |
|---|---|---|
| `round_manager.gd` | 回合生命周期 + 每回合经济；回合结束清场 | 信号 `enemy_clear/coin_clear/bullet_clear/backlayer_clear/item_clear/player_portal`；`first_round_start()` `:70-85`, `_on_round_start()` `:87-105`, `_on_round_end()` `:107-136` |
| `enemy_manager.gd` | 按回合选生成组并实例化波次生成器；普通/闪击攻击曲线；无尽模式缩放 | `round_num_changed()` `:75-102`, `round_enemy_spawn_start()` `:100-116`；导出 `endless_mult`(HP，2026-09-28 起线性延长至 x=1000) / `endless_damage_curve`(2026-09-28 起线性延长，clamp 已移除) / `endless_damage_rounds` / `endless_damage_bonus` / `round_damage_curve` |
| `game_mode_manager.gd` | 开局应用模式修正 | `apply_game_mode_1`(闪击) / `_2`(无尽) / `_3`(护聚/hujiu) |
| `upgrade_manager.gd` | 加权 3 选 1 升级池、应用/叠加升级 | `apply_upgrade()` `:145-192`, `build_pool()` `:221-242`, `get_triple_choice()` `:245-253` |
| `pick_item_manager.gd` | 地图医疗包生成、金币返还结算 | `add_medical_kit()`, `coin_add()` |
| `weight_system.gd` | 加权随机算法 | `AliasMethod` O(1), `WeightTree` O(log n), `WeightGroup` |
| `item_weight_manager.gd` | 依稀有度/标签/玩家状态/历史算动态权重 | `calculate_item_weight()`, `calculate_special_rules()`, `record_selection()` |
| `interaction_manager.gd` | 选最近 `Interactable` 并触发 `use` | 评分 `interact_priority*100000 - dist`；`current.interact(player)` |
| `pickup_spawner.gd` | 测试房定点刷取物/重生 | `_spawn()`, `_on_test_room_reset()` |
| `summoned_manager.gd` | Area2D 跟踪召唤物 | `summoned_changed`, `summoned_group` |
| `PoolManager.gd` | 通用对象池 | 见 `ARCHITECTURE.md` §4 |
| `buff_manager_base.gd` 及阵营子类 | Buff 引擎 | 见 §3.6 |

### 6.1 Endless scaling / 无尽模式缩放（`enemy_manager.gd`）

- 触发：`now_round_num > round_manager.max_round`（普通关 `max_round=20`）进入 `round_num_changed()` 的 else 分支，`endless_round += 1`。
- **HP / Boss 血量**（2026-09-28 延长 `endless_mult` 与 `hp_growth_curve`）：`endless_hp = 1 + endless_mult.sample(endless_round/10)`；`endless_boss_hp = 1 + endless_mult.sample(x) * 0.2`；难度指数 `hp_growth = hp_growth_curve.sample(now_round/max_round)`。`Curve.sample` 本身不 extrapolate（超域钳到末点），故两条曲线的 domain 都扩到 `x=1000` 并在末点之后按切线续接远点（切线/端点值用户在编辑器里微调，勿硬编码）。结果：x≤1 段（第 ≤30 关 / 普通关）不变；x>1 后 `endless_hp`/`endless_boss_hp` 随无尽回合继续上涨，且 `hp_growth` 指数也随回合增大 —— `hp = hp_base × pow(max(1, level_hp), hp_growth)`，**指数项仅对 `level_hp>1` 的难度生效**（普通 `max(1,0.8)=1`，`pow(1,·)=1` 恒为 1）。⚠️ 因指数增长，HARD/EXTREME/INSANE 在高无尽关会迅速逼近 `EnemyStats` 的 int64 上限（`EnemyStats.gd:155`）。`round_hp_curve`/`round_boss_hp_curve` 未改（其 X 被 `enemies_spawn.gd:49` clamp 到 1，永远采不到 x>1）。
- **攻击力**（2026-09-28 改为无限增长）：`endless_damage = 1 + endless_damage_curve.sample(endless_round / endless_damage_rounds) × endless_damage_bonus`。原 `clamp(...,0,1)` 已从 `enemy_manager.gd:100` 移除，`endless_damage_curve` domain 扩到 `x=1000`；曲线为**起步平缓的加速型 `y=x²`**（起点切线 0、末端切线 2，`x>1` 后按末端切线线性续接）。当前 `endless_damage_rounds=80`、`endless_damage_bonus=24.0` → 第 100 关（er=80）`endless_damage=25`，之后继续增长。普通怪与 Boss 共用；**只改无尽项**，基础项 `round_damage_curve`（×10 平顶）仍被 `enemies_spawn.gd:55` clamp。
- 传播：`endless_damage` → `enemies_spawn.gd`(`spawn_anim.damage_mult`) → `spawn_anim.gd`(`Enemy_damage_mult`/`Enemy_bullet_damage_mult`) → `EnemyStats.update_body_ability()`；`raid_spawn.gd`/`path_spawn.gd` 同样读取。
- ⚠️ `enemy_spawn_launcher.gd` 声明了 `endless_hp`/`endless_damage` 但从不使用（侵蚀塔走 `stats.Enemy_damage_mult`）。
- **精英并发上限（2026-10-02）**：`PoolManager.ENEMY_SPAWN_CAPS = {"tester_automaton_shield": 12, "droid_helmet_smg": 15, "lighttank_helmet": 4}`（其余敌人不设限）。生成请求时 `enemies_spawn.enemy_spawn()` / `raid_spawn.enemy_spawn()` 先 `PoolManager.try_claim_spawn(id)`（`活跃 + 待生成 < cap` 才通过并占用 `_pending_by_id`），达上限则该类型/方向本轮 `break` 跳过。`spawn_anim.enemy_spawn_anim()` 记录 `_claimed_id`，在落地（`spawn_enemy_body` 里 `active_state()` 之后）或中止（`can_spawn==false` / `idle_state()` / `on_round_end()` / `_exit_tree()`）时 `release_spawn_claim`（pending→active 或释放）。活跃按 `pool_id` 计数（`register_active_enemy`/`unregister_active_enemy`；`_prune_active_enemies`/`reconcile_active_enemies` 重建；`clear_active_enemies` 清 active+pending），**仅计敌人本体、不含 `EnemyPart`**。全局 `ENEMY_SPAWN_CAP=80` 不变，两者叠加。

### 6.2 Normal / Blitz scaling curves / 普通与闪击的攻击·血量曲线（2026-09-27）

**攻击**（`round_damage_curve`）
- 攻击倍率不再由各 `enemies_spawn_lv_*` / Boss 场景的导出 `damage_mult` 决定（已回退默认 1.0），改由 `enemy_manager.round_damage_curve` 单点驱动。
- `script/enemies_spawn.gd:get_level()`：`x = clamp((now_round - 1) / (max_round - 1), 0, 1)`；`damage_mult = PlayerData.level_damage * round_damage_curve.sample(x)`（**`=` 覆盖而非 `*=`**，重复进入 `get_level()` 不叠加）。
- `damage_mult` 同时作用于 `Enemy_damage`（近战/接触）与 `Enemy_bullet_damage`（子弹），经 `spawn_anim.gd` → `EnemyStats.update_body_ability()`。

**血量**（`round_hp_curve` 杂兵 / `round_boss_hp_curve` Boss / `hp_growth_curve` 难度成长）
- 各场景的 `hp_mult` 已回退默认 1.0，改由两张 base 曲线（按 `boss_round` 选）提供"按组递增"，再由 `hp_growth_curve` 替换原 `pow(level_hp, now_round/(max_round*0.5))` 的指数：
  `hp_mult = hp_base.sample(x) * pow(hp_lv, hp_growth_curve.sample(now_round / max_round))`。
- `hp_growth_curve` 用 `now_round/max_round` 采样，默认线性 `0→2` 恰好等于原指数；`hp_lv` = `PlayerData.level_hp`（护聚 Boss 仍取 `min(level_hp, 3)`）。
- **Boss 单独一条曲线**：Boss 基础血量远高于杂兵（`erosion_tower` 18000 / `goliath` 25000 vs 杂兵 35~650），故 `hp_mult` 单独标定；初始 `round_boss_hp_curve` = `(0.737, 5.0) → (1.0, 6.5)`。
- 初始 `round_hp_curve` 复刻旧阶梯 `1 → … → 35`（g14 用孤儿的 13.0 平滑），可在 `enemy_manager.tscn` 的 Curve 编辑器直接调。

**模式归一化 / 无尽**
- `max_round` 由 `round_manager` 传入（普通 20 / 闪击 15 / 护聚 5），base 曲线按 `(round-1)/(max_round-1)` 归一化 → 自动**等比**（闪击第 15 关 = 普通第 20 关的曲线末端）。
- 无尽时 `now_round > max_round`：base 曲线的 x 被 `enemies_spawn.gd:49`（血量）与 `:55`（攻击）clamp 到 1（血量 base 取曲线末端：杂兵 35 / Boss 6.5；攻击 base 取 `round_damage_curve` 末端 ×10）。血量的持续项是 `endless_hp`/`endless_boss_hp`（`endless_mult`）与 `hp_growth` 指数：2026-09-28 起 `endless_mult` 与 `hp_growth_curve` 两条都已延长到 x>1，故无尽血量持续增长；指数项仅对 `level_hp>1` 难度生效。攻击的持续项是 `endless_damage`：2026-09-28 起已去掉 `:100` clamp 并把曲线线性延长到 x>1，故无尽攻击也随回合线性无限增长（第 100 关 ×10，详见 §6.1）。

### 6.3 Map bounds / 出界回位（autoload `MapBounds` → `script/map_bounds.gd`，2026-09-29）

- 目的：玩家 / 敌人 / 召唤物（含支援 kei 的召唤物）被击退或穿墙甩出地图时，拉回地图内最近点。
- 触发：连接 `GameEvents.global_time_count`（0.1s），每 `TICK_INTERVAL=10`（≈1s）执行一次；仅在出界时算最近点，平时为 O(边数) 多边形判定，无逐帧开销。
- 边界来源：从地图中心（组 `CenterPosition`，即 `BattleRoom`）向 ±x/±y 射射线（mask `WALL_MASK=256`，该层仅 `FloorWall` 使用），取内壁命中点构成菱形可行走边界；4 条射线全部命中才采用，否则回退 `SpawnMap`（组 `"Map"`）used cells 凸包。
  - **勿直接用 `SpawnMap` 凸包当边界**：它比物理墙内壁小（x±768 vs 可走 x±864），会把贴墙的正常单位误拉回。
- 实体来源：组 `"Player"`、`PoolManager.get_active_enemies()`（已剔 idle）、组 `"Summoned"`（**跳过 `is_idle==1`**，闲置召唤物坐标被设为 `(10000,-10000)`）。
- **触发判定与体型解耦**：`_is_out(pos)` 只用“真实边界 `_hull` 外扩 `OUT_MARGIN=24px`”的多边形（`_outer_hull`，`Geometry2D.offset_polygon(_hull, +24, JOIN_MITER)`）。圆心须越过墙 ≥24px 才算真出界 → **贴墙/被墙挤压不触发**（此前用半径内缩多边形当触发边界，导致贴墙即被误判出界、沿墙走反复传送）。24px 为外扩底线，尖角处 miter/bevel 会略大于 24（底/顶顶点实测约 26.8px）。
- **落点按本体碰撞半径内缩**：`_body_radius()` 取实体**直接子节点**的 `CollisionShape2D`/`CollisionPolygon2D` 外接半径最大值（不取 `HurtBox`/`PickBox` 等 Area 下的形状；也避开玩家 `collision_shape_2d` 实为 PickBox 的坑），再用 `Geometry2D.offset_polygon(_hull, -radius, JOIN_MITER)` 得到该实体的内缩多边形（4px 分桶缓存，`_erode_cache`）。否则大体型（如 goliath 本体 `CircleShape2D radius=23`）回位后仍压墙、被物理挤穿。
- 回位动作：`global_position = nearest_inside(pos, radius)`（半径内缩多边形边垂足最近点 + 再向中心内推 `INSET=8px`），`CharacterBody2D.velocity = 0`；静默、无特效、无冷却（回位即在内，幂等）。
- 无地图场景（菜单等组 `"Map"` 缺失）→ `_hull` 为空直接跳过。

---

## 7. Game / round flow / 游戏与回合流程

1. **标题** `title_screen.tscn`：`title_anim_end` → `Game.load_playerdata()` → `change_scene_to_file("res://scenes/main/menu_screen.tscn")`。
2. **菜单/选人/选关** `menu_screen.tscn`：New Game 走角色/社团选择与 LevelSelect；选关后 `level_button.gd` 设 `PlayerData.level_*` 并 `GameEvents.change_scene("res://scenes/main/main.tscn", <player_scene>)`。
3. **战斗初始化** `main.gd`：`first_round_add → first_round()`：重置池/日期、`game_mode_manager.get_player_game_mode()`、启动 BGM、快照+emit 玩家属性、`round_manager.first_round_start()`、加支援（`SupportData.game_add_support()` 实例化 `support_pack`，由 `SupportCharacter` 应用被动）、取 BuffBox。
4. **回合**：`round_timer.init_round()` 增加 `now_round_num`（emit `round_num_changed`、写 `PlayerData.now_round`），设 60s×`time_mult` 回合计时与全局计时（10Hz `global_time_count`）。
   - 超时：普通回合 → `emit_round_end`；Boss 回合 → 护聚结束或进入 `rage_mode`（每 5 tick 加一层 boss buff），boss 死或拾取 pyroxenes 结束。
   - **联机（mod `mods/etn_coop`）**：普通回合 `emit_round_end` 与 boss `rage_mode`/`fever_time_start`、`add_rage_buff` 都经 `ExtensionHooks` 门控为 **host 权威**（本体 `round_end_emit_gate`、`fever_time_gate`）：客机不本地触发，由 host 广播 `_remote_round_end` / `_remote_fever_time_start` 驱动；rage buff 只 host 施加经 `_remote_enemy_buff` 同步。Boss 进场/死亡过场的 `camera_move`/`ui_visible`/`pause_lock` 由 host 广播（`_remote_boss_camera_move` 传世界坐标，客机建临时 `Marker2D` 复刻 + `black` 时本地 `paused`），并有墙钟看门狗 `_tick_boss_cinematic` 兜底防卡暂停。
   - **Hina QTE 联机化（2026-10-07）**：`Engine.time_scale` 是**每进程**的——联机下只会慢 Hina 自己（客机镜像跳帧、敌人仍常速）、房主端还会把 mod 的 delta 发送节奏一起饿死 → 全场卡顿。故 LAN 下 `hina_ps` 改为**等比慢放 QTE 动画**（`hina_ps._qte_slow_begin/_qte_slow_end` → `qte_bar/AnimationPlayer.speed_scale=0.07`；bar 移动本就是 `qte_anim` 的 `bar:position` 轨道），世界不减速；单机仍用 `GameEvents.request_slow`。`apply_network_character_state` 回放角色状态时**只动视觉节点**（Aris 热条 / Chinatsu 充能 / Hoshino rank 条），Kasumi 钻头走 M5 角色事件（纯视觉）。
   - `round_manager._on_round_end()`：清敌/币；若 `now_round_num >= max_round` 且非 endless → `emit_game_over(false)`（胜利）；否则转场、清子弹/背景/道具、传送玩家、`emit_round_upgrade`、`emit_player_buff_clear`、`get_tree().paused = true`。
   - `upgrade_manager` 弹 `UpgradeScreen` 三选一；`UpgradeScreen.next_round_button()` 先 `emit_round_upgrade_closing`（收起属性/装备栏）再 `emit_round_upgrade_end` → `round_manager._on_round_start()` 开下一回合。
   - 联机（mod）下 `round_upgrade_end` 由 mod 的 `round_upgrade_end_gate` 接管：本机点继续即播过场前半到黑屏并保持、显示「等待所有人就绪」遮罩，全员就绪后本体 `_on_round_start()` 经 `round_upgrade_cover_hold` 跳过前半、只播后半揭示（详见 `docs/LEARNINGS.md`）。
5. **结束**：玩家死亡在 `Stats.hp` setter（`life_num>0` 复活/hujiu 50% 复活，否则 `emit_game_over(true)`）；`game_over_page.gd` 停表、胜负、记分、返回菜单。

---

## 8. Weights / items / pickups / interaction / 权重与拾取

- `AbilityUpgrade` 定义升级项（id/rare/tags/weight/special_rules…）。
- `ItemWeightManager.calculate_item_weight` = base `weight` × 稀有度权重 × 平均标签权重 × 玩家状态 × 历史 × 特殊规则 × modifiers；默认稀有度 `{0:1.0, 1:0.375, 2:0.1}`。
- `UpgradeManager.build_pool` 用 `AliasMethod` 建池；`get_triple_choice` 取 3 个不重复选项。
- `apply_upgrade` 记录数量/顺序、镜像到 `PlayerData.current_upgrades`、实例化 `res://scenes/update_item/<id>.tscn` 到玩家、记录选择、emit `ability_upgrade_added`；`EquipItem` 基类处理装备/叠加。
- 拾取（瞬时）：`coin.gd`（池 `"coins"`，组 `PickItem`，`pick_up` 后归位并加 `coin*coin_mult`）；`pyroxenes.gd`（加 `PlayerData.player_pyroxenes`）。
- 金币掉落/合并（`CoinManager`，2026-10-02）：掉落统一走 `CoinManager.drop_coin(pos, value, pick_up)`（`entity_ENEMY._coin_drops`/`sandbag._coin_drops`）。池上限 `COIN_POOL_CAP=150`：优先复用空闲金币 → 未满则实例化 → 满额则并入 `_nearest_active()`（仅可拾取、非 `is_idle`）并通过 `coin.absorb(value, pick_up)` **累加值、不新建节点**（总值守恒）。活跃集 `_active` 由 `coin.gd` 在 `active_state()`/`idle_state()`/`_exit_tree()` 上报（仿 `PoolManager._active_enemies`）。合并目标**排除 `can_pick==false`**（抛物线/Boss 金币演出，回合末 `coin_clear_unit` 不返还其值）。**`coins` 池不进 `IDLE_LIMITS`**（`limit>=0` 时满额 `get_pool` 会静默回收活跃金币 → 丢值；故 `coins` 一律只走 `get_pool_idle` + 自管计数）。视觉缩放 `coin_scale` 改边际递减（`0.8 + 1.7*(1-exp(-coins/56.7))`，小值≈旧线性、渐近上限 2.5）。
- 青辉石自动拾取全部金币（2026-10-02）：Boss 死生成 `coin_box`（100 枚抛物线金币，约 3s 掉完、每枚再 3s 落地）+ `pyroxenes`；拾取青辉石后 `round_timer.end_boss_round` 给 3.5s 清场缓冲。旧实现每枚金币各自连 `pyroxenes_pick_up`，**拾取信号发射之后才生成的金币收不到** → 只自动拾取已掉完的。修法：① `CoinManager` 监听 `pyroxenes_pick_up` → `auto_pick=true` + 遍历 `_active` 逐个 `auto_pick()`（含飞行中金币，置 `can_pick` 让磁吸接管）；② `coin.gd.active_state()`/`absorb()` 在 `CoinManager.auto_pick` 时置 `can_pick=true; pick_up=true`（覆盖之后生成的金币）；③ `coin_box` 监听同一信号置 `_flushed=true`，`add_coin()` 循环 `if _flushed: continue` 跳过 `await timer.timeout`，**立即补发剩余金币**（含拾取早于 `add_coin()` 的情况）；④ `round_start` 复位 `auto_pick`。逐枚 `pyroxenes_pick_up` 连接已移除（改由 `CoinManager` 单点驱动）。`game_eval` 验证：`emit_pyroxenes_pick_up()` 后 `auto_pick=true`、`box._flushed=true`、5 枚剩余同帧全生成、其后激活的金币 `can_pick && pick_up` 为真。
- 抛物线金币联机（2026-10-07，mod `mods/etn_coop`）：`coin_box` 的 `parabola_path` 金币在 `drop()` 里 `body.active_state()` 早于 `curve` 构建，故 host `on_coin_spawned` 对父节点为 `PathFollow2D` 的 coin 延后一帧读 `parabola.curve`、转世界坐标后 `rpc("_remote_parabola_coin", net_id, points, value, pick_up)`；客机按 `coin_traj` + 墙钟沿折线驱动镜像飞行，落地才 `can_pick`（拾取仍走 `_gate_coin_pickup → host 共享`）。
- 拾取（长按）：通用基类 `HoldPickupItem`（`scenes/item/hold_pickup_item.gd`）——玩家在 `Area2D` 范围内持续 `time_wait` 个 0.05s tick 完成拾取，进度按玩家 `pick_up_speed` 乘区加速（默认 1）；子类实现 `_on_pickup_complete(player)`，现有 `medical_kit.gd`（组 `HealthItem`，治疗 20% max HP 或满血给币）。固定子节点名约定：`Area2D` / `PickTimer` / 可选 `CanvasGroup/TextureProgressBar`；`Area2D.monitoring` **常开**（`_ready` 设 true），用 `can_pick` 门控是否可拾取：生成动画 method 轨道调 `emit_can_pick()` 置 `can_pick=true`，若玩家已在范围内则立即开始进度（避免运行时才开启 `monitoring`、不为已重叠 body 补发 `body_entered` 造成的漏拾取）。
- 医疗箱生成：`PickItemManager`（组 `"PickManager"`，`pick_item_manager.gd`）每秒 roll，命中阈值 `(player.stats.luck + pick_luck) * spawn_rate_mult`，命中后随机位置生成；`pick_luck` 每失败 +5。支援可覆写 `spawn_rate_mult`（概率乘区，serina=2.0）与 `spawn_at_player`（为真时 `add_medical_kit(Vector2.ZERO)` 改在玩家 `global_position` 生成）。**联机（mod `mods/etn_coop`）**：host **权威生成**（客机 `medkit_spawn_gate` 返回 true 不生成），生成后 `rpc("_remote_spawn_medkit")` 广播、全端同一批；各端支援影响经 `SupportCharacter.get_medkit_spawn_modifiers()`（`{rate_mult, at_player, on_take_spawn}`）随 `report_local_support(id, mods)` 同步到 `support_mods_by_peer`，host `_refresh_medkit_mods()` 聚合 `rate_mult=max`(≤2.0)/`at_player=any`/`on_take=any` 写入本机 `PickManager`；`at_player` 时 host 随机选一名 serina 携带者落其脚下（否则随机 tile），ayane 每次拾取额外生成 1 个（LAN 下 `ayane._special_effect` 跳过本地 `connect` 防双生成）；拾取在**拾取者本机**结算（治疗/满血转金币随玩家状态 RPC 传播），host 仅 `_mark_medkit_consumed` + 广播 `_remote_medkit_consumed`（客机 `medical_kit.consume_remote()` 只播消失演出）。单机未注入 hook 时逐字节一致。
- 交互：`InteractionManager` 每物理帧扫描组 `Interactable`，暂停或 `player.can_control==false` 时忽略；`PropInteract`（Area2D）是标准提供者，转发 `owner.interact`。
- 触屏交互：仅对气泡类提示（`wants_bubble_prompt()` 为真）生效。`InputEventScreenTouch` 按下时把屏幕点转世界坐标，命中 `interact_prompt.gd:get_touch_rect()`（气泡世界矩形外扩 `touch_margin`，默认 20 世界像素）即调用 `current.interact(player)`；鼠标/手柄路径不变。气泡 `Control` 设为 `MOUSE_FILTER_IGNORE` 以免吞掉触摸。

---

## 9. Vestigial / dead code to avoid depending on / 死代码（勿依赖）

- `scenes/enemies/base_enemy.gd`（空 `BaseEnemy` stub；真正基类是 `entity_ENEMY.gd`）。
- `scenes/enemies/enemies_spawn/enemy_path_spawn.gd`（空 stub；路径生成在 `path_spawn.gd` + `enemy_path.gd`）。
- `script/transition_manager.gd`、`scenes/game_camera/transition.gd`（未使用）。
- `DamageData.check()`、`GameTags.CONVERT`、`crit_chance_bonus`、`enemy_critical_hurt/fire_hurt/explosion_hurt/poison_hurt/normal_hurt` 信号、`entity_ENEMY.is_*_hit`、`ExplosionDamage.damage_mult`、`on_hit_effects`（无填充者）。

## 10. UI 大图按需加载（商店 / 支援 / 玩家卡，2026-09-29）

- **背景**：立绘按 `compress/mode=0`(Lossless) 导入，运行时是**未压缩 RGBA8**。单张 `ui/ark_of_Shittim/*_picture.png`（2400×4800）≈ 44MB，玩家/支援立绘（2400×1200）≈ 11MB；`shop_menu.tscn` 被 `menu_screen.tscn` 静态实例，其导出数组一次性引用全部卡资源 → 主菜单即载入 ~850MB → 低配移动端显存爆 → **单张精灵局部/整张串成别的角色**。
- **字段改路径**：`ClothesCard.sprite`→`sprite_path`、`CharacterCard.character_sprite`→`character_sprite_path`、`SupportCard.character_sprite`→`character_sprite_path`、`PlayerCard.sprite`→`sprite_path`（均 `@export_file("*.png")`）。加载资源**不再连带大图**。（`character_halo`/`halo` 保留 Texture，体积很小。）
- **助手** `script/lazy_texture.gd`（`class_name LazyTexture`）：`load_uncached(path)` = `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)`（**不缓存**，丢引用即释放）；`clear(node)`。
- **消费点**：`arona.gd`（店主）、`character_shop_card.gd`、`support_shop.gd`、`support_ui/support_shop_card.gd`、`support_ui/support_select_ui.gd`、`support_card.gd`(局内 HUD)、`score_card.gd`、`player_card.gd`、`game_ui.gd`、`pause_screen.gd`、`game_over_page.gd`、`menu_box_button.gd`、`test_character_card.gd` 一律 `LazyTexture.load_uncached(path)`。
- **滚动懒加载**：`shop_menu.gd`（角色 `ItemList1/CardBox`）、`support_shop.gd`（水平 `ScrollContainer/card_box`）、`menu_box_character.gd`（计分角色 `ScrollContainer/button_box`）在 `_process` 里按 `ScrollContainer.get_global_rect()` 与卡片 `get_global_rect().grow(余量)` 相交判定，只对可见卡 `reveal()`（载图）、滚出 `conceal()`（置 null）。列表项脚本统一暴露 `reveal()/conceal()`。
- **时机**：`arona.gd` 不再在 `_ready` 载当前套装；`shop_menu.emit_shop_open()`（由 `shop_open` 动画 method track 触发）载店主 + 开启懒加载；关闭时 `_on_shop_closed()` 释放全部大图并 emit `shop_close`（`support_shop` 订阅）。`support_shop.default_set()` 也由 `shop_open` 触发。
- **场景内嵌默认大图已清空**：`<char>_card.tscn`（21）、`character_shop_card.tscn`、`support_shop_card.tscn`、`support_card.tscn`、`support_select_ui.tscn`、`test_character_card.tscn`、`menu_box_button.tscn`、`score_card.tscn`、`arona.tscn`/`plana.tscn`、`game_ui.tscn`、`game_over_page.tscn` 里的大立绘 `texture` 默认值已移除（否则实例化即载入并显示错误默认图）。⚠️ 新增此类场景勿再内嵌大图。
- **性能坑（2026-09-29 修复）**：懒加载列表若**每帧**调 `reveal()`，而 `reveal()` 每次走 `LazyTexture.load_uncached`(`CACHE_MODE_IGNORE`) 会**每帧重新解码**大图（11–44MB）→ 严重卡顿（`menu_box_character` 因 `scoreboard` 默认可见尤为明显）。修法：① `reveal()/conceal()` **幂等**（记录 `_revealed_path`，同路径直接返回）；② `LazyTexture` 提供 `acquire/release` **引用计数共享缓存**（同路径多节点只解码一次，release 到 0 释放）；③ 列表 `_process` 仅在**滚动位置变化或刚打开的前几帧**（`_lazy_force`）重算；④ `menu_box_character` 以 `MenuBox.is_open` 门控（不再依赖默认可见）。

## 11. Mod 内容注册表 / Mod content registry（2026-10-04）

- 由 autoload `ModManager`（`script/mod_manager.gd`）维护：`kind -> id -> {res, scene, card_scene, mod}`。挂载/扫描时序见 `ARCHITECTURE.md` §1.11。
- **发现**：`res://mods/<id>/defs/<kind>/*.tres`（`ResourceLoader.list_directory`，返回编辑器原始名）或构建期 `content_index.json`（后者对某 kind 支持 `{"card":..,"card_scene":..}`）；类型经脚本 `class_name`（`_script_inherits` 沿 `get_base_script()` 判继承链，兼容无/自定义 class_name 的子类）。`manifest.characters` 只跳过 `characters` 的目录扫描，其余 kind 照常；同 mod 同 kind 同 id 重复注册静默跳过。
- **id 治理**：自动注册 id 必须带 `<mod_id>_` 前缀；与本体/其它 mod 冲突默认拒绝；`mod.json` 的 `overrides` 显式声明才允许覆盖（`load_order` 后者胜 + 稳定 tie-break）。
- **消费**：`characters`（`get_characters()` → 选人「MOD 社团」`ui/mod_society_card.gd` 覆写 `society_card.populate_player_cards()`，实例化 `ui/mod_player_card.tscn` 通用卡并由其 `branches` 切换形态；选中走 `GameEvents.emit_player_card_id(scene_path)`；`PlayerCard.card_scene` 可指定自带选人卡）；`shop_characters`（>`CharacterCard`，`ui/shop_menu.gd` 的 `shop_card_group` 追加 `get_content("shop_characters")`，走本体付费商店）；`clothes`（`ui/shop_menu.gd` 的 `shop_item_group` 追加 `get_content("clothes")`；`ui/ark_of_Shittim/cloth_change.gd` / `arona.gd` 经 `ModManager.get_resource("clothes", id)` 解析 mod 服装）；`upgrades`（`upgrade_manager._ready` 追加 `upgrade_pool`，`ui/test_menu.gd` 直接并 `get_content("upgrades")`；`apply_upgrade` 经 `ModManager.get_scene("upgrades", id)` 解析场景，mod 约定 `defs/upgrades/<id>.tscn` 同目录同名；`ui/score_card.gd` 经 `get_resource` 解析）；`supports`（`ModManager._inject_supports()` 追加 `SupportData.support_pool`，商店/选择界面自动收录）；`enemies`（`defs/enemies/` 注册并校验 `EnemyCard.id` ↔ `body` 根 `pool_id`（缺 `icon` 告警）；`ModManager.get_mod_waves()` 生成 `{group, PackedScene}`，`enemy_manager._ready` 按 `_group_index()` 追加到对应 lv 组，`enemy_group` 默认 `lv1`；`ui/enemy_test_menu.gd` 追加 `get_content("enemies")`）；`game_modes`/`levels`（`ui/gamemode_button.gd` / `ui/level_select.gd` 的 `_ready` 追加到选择 UI）。
- **解锁方式（2026-10-09）**：`PlayerCard.unlock_mode` 枚举 `auto`（默认，`ensure_unlocked()` 并入 `PlayerData.character`、可见）/ `shop`（不自动解锁，需同名 `defs/shop_characters/<id>.tres` 付费购买；缺条目注册告警）。`branches` 各自声明。`ModManager.is_character_locked(id)` 供社团卡过滤；`get_unclaimed_unlocked_characters()` 供通用「MOD」社团卡显隐/填充。可见性不再依赖 `PlayerData.character` 直接判断（改走 `is_character_locked`）。
- **社团卡**：`ui/mod_society_base.gd`（mod 自带社团卡基类，须继承）+ `defs/societies/*.tscn`（或 manifest `societies`）；`_scan_societies()` 注册 `{scene, mod, group_id}`（同 mod 同 group_id 去重），`group_id` 走前缀/唯一治理。**按 mod 认领**：有自带 → 其角色进自带卡（`members`）；无 → 进通用 `ui/mod_society_card.tscn`（只列 `get_unclaimed_unlocked_characters()`）。**通用卡自动续卡（2026-10-09）**：`ui/mod_society_card.gd` 改为继承 `ui/mod_society_base.gd`（复用 `members`/`check_group`/`populate_player_cards`，仅加 `set_page()` 页码标签）；由 `menu_screen._setup_societies()` / `coop_select._build_societies()` 按 `MOD_PAGE_SIZE = 4` 个未认领已解锁角色切片，每片实例化一张并 `set("members", slice)`（须在 `add_child` 前），标签 `MOD` / `MOD 2` / …。`menu_screen._current_unlocked_gids()` 的通用 token 改为带数量（`__mod_generic__:<n>`），人数跨页变化即触发 `_sync_societies()` 重建。`mod_society_base.check_group()` 覆写为「任一成员未锁即显示」，不再依赖 `PlayerData.group`。角色选择卡同样「自带 `card_scene` 优先，否则通用 `ui/mod_player_card.tscn`」。
- **深度修改（P4）**：`mod.json.entry`（Node 脚本）启动时由 `_run_entry_scripts()`（按 `_resolved_order`）实例化到 `ModManager` 下；`api_version > ModAPI.VERSION` 则跳过。mod 经 `ModAPI`（静态门面）+ `GameEvents` 挂流程；`replace_files=true` 可覆盖入口场景（`main.tscn` 等，加载晚于挂载）。`ModAPI` 稳定接口：只读 `get_content/get_resource/get_scene/get_characters/has_upgrade/get_content_mod/get_societies/get_unclaimed_characters/get_unclaimed_unlocked_characters/list_mods`；写入 `register_content(kind,id,res,mod_id,scene_path?,card_scene_path?)`（经 `_register_res` 治理）、`add_translation(locale,key,value)`（`TranslationServer.add_translation`）。
- **zip 导入健壮性（2026-10-09）**：`import_zip()` 重装先递归清空 `user://mods/<id>/`；校验 zip 含 `manifest.pck`（默认 `<id>.pck`）；条目数 >2000 或累计解压 >256MB 报错并清理。`_fail_mod()` 停用时 `mods_changed.emit.call_deferred()` 通知 UI。
- **补丁**（P0.5，已实现）：`patches/*.json`（loose `mods/<id>/patches/` 或 pck 内 `res://mods/<id>/patches/`）由 `script/mod_patch.gd`（`class_name ModPatch`）按 `load_order` 依次应用，对内存注册表做 `replace/add/remove/inherit`；`target`/字段不存在 → warning + skip。加载顺序由 `dependencies`/`load_order`/`conflicts` 拓扑排序（`ModManager._resolve_order`），依赖缺失/环/冲突 → 停用。
- **管理面板描述 tooltip（2026-10-08）**：`mod.json` 增可选 `description`（直接字符串，Label 自动翻译、命中翻译键即翻译），`ModManager.list_mods()` 返回 `description`（`version`/`author` 原已返回）。`script/mod_option.gd`（`ui/mod_option.tscn`）悬停行显示跟随鼠标的 tooltip（名字 + 版本 + 作者 + 描述）；触屏点按显示、再点同一行/点列表空白隐藏、拖动排序时隐藏。命中判定用整行 `get_global_rect()`（含开关）；面板在 CanvasLayer 下无缩放，故 `get_global_mouse_position()` 与 `get_global_rect()` 同系可直接比较。
- 打包/安装/导出设置见 `CONVENTIONS.md` §10 与 `mod_sdk/README.md`。
