# ETN Coop Mod（骨架）

联机以 **mod 形式注入**，本体零改动（仅通过 `ExtensionHooks` 挂接）。当前进度：**传输层 + 玩家/敌人/召唤物同步 + 敌人伤害权威 + 子弹与爆炸/特效广播 + 金币共享 + 倒地救援/团队流程 + 场景切换广播 + 主菜单 COOP 按钮（置于 QUIT 之上）+ 联机覆盖层（option 菜单式布局，页签复用 `option_button.tscn` 绿色高亮，4 语）+ 开房后自动进准备房（测试房作为准备房）+ 开始球/选人/就绪/房主难度流程 + 玩家 ID 常驻顶部 + LAN 全员选定握手 + 出生点居中 + 测试场菜单 get_player 修复 + 玩家 ID 输入/持久化 + 头顶名牌同步 + 房间聊天室（右侧小窗，回车/手机按钮）**。

## 目录

```
mod_sdk/coop_mod/mods/etn_coop/
  mod.json                        # manifest，entry 指向 entry/coop_entry.gd
  entry/coop_entry.gd             # 创建 CoopNet、注册 ExtensionHooks、注入菜单 COOP 按钮、打开覆盖层、开发热键/自测
  ui/coop_menu.tscn              # 联机覆盖层（option 菜单式布局：左侧 option_button 页签 + 右侧内容面板）
  ui/coop_menu.gd                # 覆盖层逻辑（NetworkManager → CoopNet.instance；页签动画/面板滑入/本地 Game.is_*）
  ui/coop_icon.png               # 顶部滚动横幅贴图（运行时 Image.load_png_from_buffer 载入）
  ui/coop_select.tscn / .gd      # 选人覆盖层（静态布局在场景，可在编辑器调；脚本动态填充社团/角色/支援）
  ui/coop_ready.tscn / .gd       # 已就绪遮罩（半透明黑底 + 居中白字，ESC 取消 / 等待房主）
  ui/coop_difficulty.tscn / .gd  # 房主难度面板（instance gamemode_button + 关卡 VBox 动态实例化 level_button）
  ui/coop_start_ball.tscn / .gd  # 绿色开始球（instance scenes/yellow_ball.tscn + 脚本；绿 shader 见下）
  ui/coop_room_label.gd          # 右上角常驻房间标识（LAN IP:端口 / Relay 房间码）
  net/coop_flow.gd               # 准备房流程编排：进准备房/选人/就绪/难度/进关卡
  i18n/coop_i18n.gd              # 运行时构建 zh_CN/en/pt/vi_VN 四语 coop_* 翻译并注册
  net/coop_net.gd                 # 核心：连接/场景同步/玩家/敌人/子弹/特效/金币/召唤物/倒地/团队流程
  net/coop_player_proxy.gd        # 远程玩家表现驱动 + 禁用本地控制/信号
  net/coop_enemy_proxy.gd         # 镜像敌人：按快照插值 + 禁物理
  net/coop_summoned_proxy.gd      # 召唤物：拥有者上报 / 镜像插值
  net/coop_visual_sync.gd         # 视觉弹池 + 特效生成 + 伤害禁用/敌方弹伤害洞
  net/coop_network_transport.gd   # LAN(ENet) / Relay(WebSocket) 工厂
  net/coop_relay_peer.gd          # MultiplayerPeerExtension（需外部中继服务端）
```

> **编辑器镜像**：完整源另复制一份到本体工程 `res://mods/etn_coop/`（`H:\Enter The Nyangeon\mods\etn_coop\`），供 Godot 编辑器打开编辑（`mod_sdk/.gdignore` 使编辑器看不到 `mod_sdk`）。**构建始终从 `mod_sdk/coop_mod/mods/etn_coop/` 打包**；镜像仅用于编辑器/本地调试。因 `ModManager` 默认 `replace_files=false`（本体优先），运行期 `res://mods/etn_coop/` 会遮蔽 pck 同名文件——开发时改镜像立即生效。两处需保持一致（改完一方由负责方同步另一方）。导出时已用 `exclude_filter` 排除 `mods/etn_coop/*`，正式包不含镜像源码。

> **约定**：pck 不含全局类缓存，mod 内脚本**不使用 `class_name`**，一律用 `const X = preload(...)` 互引。

## 构建 / 安装

`mod_sdk/build_coop_mod.ps1` 直接用 Godot `PCKPacker` 打包（无需工程副本/导出预设；打包器为 `mod_sdk/pack_mod.gd`，位于 `.gdignore` 目录，**不会进任何导出包**）。

```powershell
# 仅打包：生成 mod_sdk/coop_mod/build/etn_coop.zip
.\mod_sdk\build_coop_mod.ps1

# 打包 + 安装到 user://mods/etn_coop（重启游戏生效）
.\mod_sdk\build_coop_mod.ps1 -Install
```

安装位置：`%APPDATA%\Godot\app_userdata\Enter The Nyangeon\mods\etn_coop\`（`mod.json` + `etn_coop.pck`）。

> 也可用官方流程：`setup_mod_project.ps1` + `build_mod.ps1`（需工程副本 + `ModPack` 导出预设 + 编辑器关闭）。本脚本是免副本的替代。

## 运行 / 自测

- 游戏内：`F10` 开服（LAN，端口 24591）、`F11` 加入 `127.0.0.1`、`F12` 断开。
- 无头自测（`--coop-devbattle` 会在 1.5s 后自动进 `test_room` 并选 momoi，5s 后打印状态）：
  ```powershell
  # 主机
  godot --headless --path <本体工程> -- --coop-host --coop-devbattle
  # 客户端（另开一个进程）
  godot --headless --path <本体工程> -- --coop-join=127.0.0.1 --coop-devbattle
  ```
  两侧应各打印一条 `spawned remote player peer=<对方 id>`，状态里 `remotes=1`。

### WebSocket 中继（跨网/在线）

中继**服务端不自带**（仓库外，另有实现；协议见 `coop_relay_peer.gd`）。默认地址 `127.0.0.1:7716`。

- 游戏内：`COOP` 面板 → “Relay” 区填服务器地址与房间号 → `Relay Host` / `Relay Join`；状态栏显示连接与房间号（host 创建后打印 `RELAY_ROOM_CODE=<4位码>`）。
- 无头自测：
  ```powershell
  # 主机（先启服务端；日志里提取 RELAY_ROOM_CODE）
  godot --headless --path <本体工程> -- --coop-relay-host=127.0.0.1:7716 --coop-devbattle --coop-devenemy
  # 客户端（用上面拿到的房间码）
  godot --headless --path <本体工程> -- --coop-relay-join=127.0.0.1:7716|<CODE> --coop-devbattle
  ```
- 协议对接点：控制帧为 TEXT JSON（`create_room`/`join_room`/`client_ready` → `room_created`/`join_prepared`/`join_admitted`/`peer_pending`/`peer_disconnected`/`error`）；数据帧为 BINARY（`le32(target)+payload`，服务端转发为 `le32(sender)+payload`）。host=1、client≥2。

## 已实现

- 传输：LAN(ENet) 主机/加入；中继(WebSocket) 客户端（需自建服务端）。
- 玩家同步：各端在 `first_round_add` 时交换 roster，互相生成对方角色（移出 `Player` 组、加入 `RemotePlayer`），挂 `CoopPlayerProxy`（禁用输入/相机/UI/碰撞/信号、按快照插值位置/朝向/动画/血量）；本机以 ~20Hz 上报状态，经服务端转发。
- 敌人同步（服务端权威）：host 在 `on_enemy_spawned` 登记 net_id 并广播；client 生成镜像（挂 `CoopEnemyProxy`，禁物理、按快照插值位置/速度/血量）；host 以 ~8Hz 发快照；死亡经 `is_dead` → despawn 广播；client 镜像不本地判死。
- 敌人伤害权威：client 的子弹命中经 `enemy_damage_interceptor` 转交 host（序列化 DamageData 字段），host 结算并快照回传；client 不本地结算（镜像血量只来自快照）。
- 子弹广播：任意端的本地弹道经 `on_projectile_spawned` 按帧批量广播（scene/位置/朝向/缩放/速度/kill_time）；其它端用 `CoopVisualSync` 生成**纯视觉弹**（从本体池移除、清零碰撞、禁伤害、自带 kill_time 回池）；`on_projectile_despawned` 广播**提前终止**（撞墙/命中）让对方立即消失，`ended` 集合防迟到复活。
- 爆炸/特效广播：`on_projectile_spawned` 中**无 velocity** 的作用域走特效通道（scene/位置/朝向/缩放/所属组 + **白名单属性** `explosion_range/damage_mult/range_mult/scale_mult/is_crit/color/modulate/bullet_scale`），对方生成不池化、超时释放的纯视觉特效（禁伤害）。
- 敌人→玩家伤害：client 的**敌方视觉弹**对本地玩家开放"伤害洞"（置 `enemy_bullet` 层 + monitorable、合成 enemy DamageData），玩家 HurtBox 正常结算；镜像敌人物理/AI 停用，不会二次开火。
- 金币权威/共享：host 登记金币 net_id 并广播，client 生成金币视觉；拾取经 `coin_pickup_gate` 转交 host，host 广播**共享增益**（所有玩家 +相同金币）。
- 召唤物同步（拥有者权威）：`on_summoned_spawned` 登记 net_id（client 经服务端中转）→ 其它端生成镜像挂 `CoopSummonedProxy`；拥有者 ~12Hz 上报位置/速度/朝向。
- 团队流程：`player_death_gate` 把本地死亡转为**倒地**并广播；附近队友按住 `use` 达 2.5s 请求救援；host 统一判定**全员倒地 → 团队 game over**；`round_upgrade_end_gate` 等待全员升级就绪后统一推进。
- 倒地视觉 / 受击反馈：倒地时本地与远程镜像都套用冷色 tint + `DOWN!/REVIVED!` 飘字（本体 `player.set_downed_state` 内实现）；救援时靠近倒地队友按住 `use` 会用 `interact_prompt` 显示**进度气泡**；`player_is_hurt` 广播使**非拥有端**也能看到远程玩家受击白闪；服务器把敌人 `damage_taken` 的**实际伤害**广播回各端，client 在镜像敌人上重发 `enemy_damage_taken` → 全端都能看到伤害数字与受击闪。
- Boss：`boss_round_start/end` 由 host 广播；本体 `GameEvents.boss_event(name, data)` 事件总线（`goliath` 的 `random/strafe/big_gun_end`、`hit_wall` 与 `idle/run/shoot_ready/shoot/charge/turret_ready` 动画态，`erosion_tower` 的 `stop_shoot`/`tower_dead` 与 `idle/attack/defense/enter/death` 动画态）经 host 广播并在 client 重发；**goliath / erosion_tower 镜像**监听 `boss_event` 回放动画态（仅表现、带 `_net_visual_replaying` 重入保护，不重复攻击）。塔的攻击：**子弹**经 `ProjectileSpawner` 随子弹广播、**激光**经 `laser_launcher.active_state` 的 `notify_local` 走特效通道，且 client 的敌方激光视觉副本会开**伤害洞**（`laser_bullet.open_network_player_damage_hole`：只命中 `player_box` 层、只对本地玩家）——因此激光在其它端**可见且可伤害本地玩家**。另提供通用 `CoopNet.instance.broadcast_boss_pattern_event(net_id, data)` + `boss_pattern_event_received`。
- 角色专属通道：玩家状态携带 `character_state:int` + `heading:Vector2`；本体 `script/player.gd` 默认**汇总子节点（PS）**的 `get/apply_network_character_state`；已接 `aris_armed`（悬浮喷气 `is_hovering`）与 `mashiro` PS（蓄力发光）；其它角色/PS 覆写同名方法即自动同步。
- 场景切换广播：host 调 `change_scene` 时广播 `_remote_change_scene(path, roster)`，client 跟随并用各自选择的角色场景实例化（`_server_player_selected` 上报选择）。
- 主菜单 COOP 按钮 + 覆盖层：经 `ExtensionHooks.populate_menu_buttons` 注入 `res://ui/menu_button.tscn`（`button_id="coop"`，**扫描 `game_quit` 索引后 `move_child` 置于 QUIT 之上**）；点击发 `GameEvents.menu_button("coop")` → entry 打开 `ui/coop_menu.tscn` 覆盖层（挂菜单 `CanvasLayer` 下）。
  - 覆盖层为 **option 菜单式布局**：左侧 `LAN` / `RELAY` 页签**实例化本体 `res://ui/option_button.tscn`**，放在 `Node2D` 下的 `VBoxContainer` 中（自上而下 `LAN`→`RELAY`，宽 97 对齐本体 option 按钮；`button_id="coop_lan"/"coop_relay"`，高亮条改为绿色 `Color(0.0, 0.837, 0.295)`；受容器管理，覆盖层可见时才排序）。因 `option_button` 根为 `MOUSE_FILTER_IGNORE` 且未选中时高亮 `ColorRect` 宽度为 0，运行时把页签根设为 `STOP`、其子节点与 `VBoxContainer` 设为 `IGNORE`，让整块页签成为唯一命中目标（否则未选中页签无悬停/点击）；右侧 `Panel` 内容顶部常驻「玩家 ID」行（`Label` + `LineEdit %PlayerIdInput` + `Button %PlayerIdConfirm`，所有页签可见），下方含 Host/Join + 本机 IP、Relay 服务器/房间号/创建/加入 + `Saki 服务器` 快捷填充、底部状态点 + 状态文案。
  - 顶部为滚动横幅（`coop_icon.png` + `res://shaders/scrolling_bkgd.gdshader`，绿色 tint）；进场/退场照搬联机版：整页 `coop_in`/`coop_out`（`anchor_left/right` 左右擦除）+ 内容面板 `panel_option_in/out`（滑入 (146,48) 并回弹）。
  - 页签点击由 `option_button` 自身播放 `selected` 并发 `GameEvents.menu_button("coop_lan"/"coop_relay")`，覆盖层据此切模式；取消选中用 `play_backwards("on_select")` 而非 `on_out`——因为 `option_button` 的 `on_out`/`RESET` 把 `.:position` 写死为 (24,40)，会破坏容器排版（`on_select` 只动 `offset_transform_position`，不碰 `position`）。
  - 适配点：`NetworkManager.*` → `CoopNet.instance.*`；联机版的 `Game.is_ui_cancel/is_ui_accept/is_gamepad_event` 在本 mod 内本地实现；本体 `return.tscn` 的 `pause_press` 行为被改写为「关闭覆盖层」；覆盖层关闭时 `visible=false`（开启时根 Control `mouse_filter=STOP` 整屏拦截）。
  - 联机流程入口：开房成功（LAN `host_game` / Relay `relay_room_created`）后 `CoopNet` 自动 `enter_lobby()` 进入准备房（测试房），不再有 `Start`/`Test Room` 按钮。选人→就绪→房主难度→进关卡见下文「准备房流程」。
  - 本地化：`i18n/coop_i18n.gd` 运行时构建 **zh_CN/en/pt/vi_VN** 四语 `coop_*` 翻译并 `TranslationServer.add_translation`，无需改本体 CSV。
- 对齐联机版的生成/流程（**纯 mod 侧，不改本体**）：
  - **出生点居中**：`CoopNet._get_room_center_position()`（`CenterPosition` 组 → 当前场景内按名找 `BattleRoom/CenterPosition/SpawnPoint` → `(0,0)`）；本地玩家就绪后归位到 `_spawn_position_for_peer(本机)`，远端镜像同样在中心生成（本体 `test_room` 的 `BattleRoom` 无分组，靠按名兜底）。
  - **测试场点球报错修复**：本体 `test_room.reset_data` 在玩家未就绪时提前 `return`、不发 `get_player`，导致 `enemy_test_menu.player` 为 null。mod 在本地玩家就绪后补发 `GameEvents.emit_get_player()` 并 `PlayerData.player = 本地玩家`（对齐联机版 `bind_player_data_to_local_player`）。
  - **LAN 角色选择握手**：host 在 `change_scene_gate` 里记录各端选择，**等全员选定**后才广播 roster 并放行本体加载；未齐时状态栏显示「等待其它玩家选择」。按约定**跳过关卡选择与自动选卡**（联机版由本体 `menu_screen` 提供，本 mod 不改本体）。
  - 本地玩家也挂轻量 `CoopPlayerProxy`（本地分支仅缓存/meta，不注册进 `player_by_peer_id` 以免被 `_reset_player_sync` 误释放）。
- 与联机版 0.4.1.3 的进一步对齐（**纯 mod 侧 + 少量本体最小 hook**）：
  - **救援服务端校验**：`_server_try_revive` 增加「请求者≠目标、双方倒地状态、请求者存活、距离≤96」；`RESCUE_RADIUS`→96；复活补 `stats.player_dead=false`（`set_downed_state(false)` 复位 `player_stop`）。
  - **团队 game over**：`_gate_game_over` 团队判定（单人倒地不结束；全员倒地/主动投降(false) 才结束）；`_force_team_game_over_authoritative`/`_server_request_team_game_over`；host 自己最后倒地也触发；`paused=false` + 去重。
  - **升级复活**：`GameEvents.round_upgrade` → host 满血统一复活倒地队友。
  - **返回菜单广播**：`change_scene(path,"")` → host `rpc("_remote_return_to_menu")`（并修掉此前 host 等待死锁）。
  - **近战/换弹通道**：本体 `ExtensionHooks.on_player_melee/on_player_reload`（在 `kick.gd`/`player_gun.gd` 调用点 notify）→ mod 广播 + 远端回放动画/音效。
  - **pyroxenes 共享**：本体 `ExtensionHooks.on_pyroxenes_gain`（`scenes/item/pyroxenes.gd` notify）→ mod host 权威共享。
  - **有序通道 + 快照变化检测**：玩家状态 RPC `unreliable_ordered,1`、敌人快照 `unreliable_ordered,2`；快照位置/速度 epsilon + 600ms 心跳 + hp 比较。
  - **敌人死亡演出广播**：`_play_enemy_death_remote`（`death_gpu.tscn` + 敌人图标 + `DeadSounds`）。
  - **子弹属性同步**：`BULLET_PROP_NAMES` 白名单随包发送（penetrate/collision_num/homing/slow_*/target_position/decay_* 等）；`spawn_visual_bullet` 支持 `pre_method`/`method` 且改为「先方法、后禁伤」。
  - **召唤物 host 权威 + pending**：host 统一分配 net_id；client 本地生成入 `pending_local_summons`，host 回发同 net_id 时认领；补 `summoned_scene/owner_by_net_id`、`_send_existing_summons_to_peer`、`_server_summoned_despawn` 校验 owner。
  - **`get_local_player` 改 meta 判定**（`PlayerRoot` 子节点 + `peer_id`，回退 `Player` 组）；**远程玩家保留 `CharacterBody2D` 本体碰撞**（只禁 Area2D），避免穿模；**level_state** 随 roster 同步（`PlayerData.level_*`）。
  - **scene_ready 上报**：客户端场景切换后 `rpc_id(1, "_client_scene_ready")`，host 记录 `scene_ready_peers`（不改变现有生成时序，避免回归）。
  - **本地换人链路**：本体 `ExtensionHooks.local_player_change_gate`（在 `ui/character_test_menu.gd`/`ui/test_menu.gd` 的 free+re-add 处拦截）→ mod `request_local_player_change`/`_server_request_player_change`/`_replace_player_remote`/`_replace_player_for_peer`。
  - 判定为「参考死代码 / 无对应本体接口」而跳过：`mashiro_charge_state`（联机版未接线）、`character_event`（本基无 mika/seia）、`register_test_room_target`（联机版未接线）、`state` 状态机/`update_network_remote_visual`（本基无）。

## 网络补偿：快照缓冲插值 / 自适应延迟 / 快照分频（2026-10-07）
- **快照缓冲**（新增 `net/coop_snapshot_buffer.gd`）：远端实体（敌人/玩家/召唤物）`apply_snapshot` 只入缓冲；`_physics_process` 用 `render_t = 本地now - interp_delay` 采样 → 两快照间线性插值；早于首条取首条；晚于末条按末速度**外推**（**缓入衰减**：越接近上限速度越小，消除过冲回弹），上限 `EXTRAP_MAX_MS=120` 后**冻结**；单帧位移 > `TELEPORT_DIST=220` 视为传送 → 清缓冲瞬移（避免横穿地图的插值滑行）并置 `teleported`。另维护**实测快照间隔（EMA）**供延迟估计。
- **自适应延迟**：`interp_delay = clamp(max(2×快照间隔, 1.8×实测快照间隔(EMA), rtt/2 + 2×jitter), 0.05, 0.20)`（`SnapshotBuffer.compute_delay`）。RTT/抖动**常开采集**（`_diag_ping` 已与 F9 HUD 解耦；`net_rtt_ms`/`net_jitter_ms`）。
- **传送残影**：`net/coop_dash_ghost.gd`——硬校正/传送（缓冲清空）时在旧位置生成一个 `Sprite2D` 残影（取当前帧贴图，0.25s 淡出后释放），降低瞬移突兀感。
- **快照分频**：敌人快照 8Hz→**15Hz**（`ENEMY_SNAPSHOT_INTERVAL=0.066`）；`_send_enemy_snapshot` 按「距最近玩家」分频（近 `≤420` 每 tick、中 `≤900` 每 2 tick、远 每 3 tick），hp 变化（受伤/死亡）立即发，保留位置/速度 epsilon 变化检测 + 600ms 心跳。召唤物上报 12.5Hz→15Hz；玩家状态仍 20Hz。
- **敌人快照分包**：`_send_enemy_snapshot` 按 `ENEMY_SNAPSHOT_ENTITY_LIMIT=32`（运行期可 `--coop-devsnapbatch=<n>` 覆盖）切包发送，避免单包 >ENet MTU 被整包丢弃（unreliable 不重组）导致该帧所有敌人一起卡顿；接收端无需改。
- **子弹延迟补偿（仅直线弹）**：`_spawn_one_visual` → `_compensate_bullet_spawn` 按单向延迟 `clamp(rtt/2,0,250ms)` 把直线弹生成位置沿朝向前推 `speed*delay`、并把 `kill_time`（0.1s tick）扣 `delay*10`；**仅匀速直行弹**生效，`homing`/`slow_down`/`decay_time`/`can_r`/`collision_num` 弹原样（前推会失真）。
- **硬校正**：仅越界（敌人/召唤 128、玩家 96）时瞬移 + 清缓冲；普通情形由插值兜底（消除橡皮筋）。
- **调试/压测**：F9 HUD 增 `jitter` 与 `comp extrap/snap`；`--coop-devnetlag=N`（接收端按 N% 丢弃敌人快照）压测缓冲/外推；`dev status` 附 `ext=/snap=` 计数。
- **命中轻量校验**（保持客户端权威，favor-the-shooter）：客户端命中转发 host 时附**受害者位置**；host `_server_enemy_hit` 增加校验——目标存活（`hp>0`）、攻击者→敌人距离 ≤ `HIT_VALIDATE_MAX_DIST=2400`、**回滚合理性**（客户端所见位置 vs host 位置历史中最接近 `now-(rtt/2+插值延迟)` 的点，偏差 > `HIT_VALIDATE_TOL=200` 才拒；客户端位置为 `(0,0)` 视为未同步则跳过）。仅拦明显异常；`net_hits_accepted/rejected` 计入 F9 HUD 与 `dev status`（`hit=ok/rej`）。
- **压测回归工具**：`--coop-devsim=lat=<ms>,jit=<ms>,loss=<pct>`（作用于收到的敌人快照：按概率丢包 + 延迟/抖动投递队列）；`--coop-devsimreport` 每 2s 打印 `sim-report`（role/rtt/jitter/extrap_rate/hard_snaps/extrap_events/snap_sends/snap_entities/带宽）；`--coop-devautoquit=<sec>` 优雅退出以刷新 stdout。脚本 `mod_sdk/coop_sim_regression.ps1` 跑一组条件、解析 `sim-report` 并断言（出现 `SCRIPT ERROR` 或 `extrap_rate`/`extrap_events` 超阈值即失败，退出码非 0）。
- **取舍（本轮未改）**：远端实体引入 ~50–200ms 自适应渲染延迟；命中仍**客户端权威**（仅加轻量校验）、玩家受伤仍本地「伤害洞」结算，未做服务器回滚 hitreg。

## 连接体验与信息面板（LAN 发现 / 版本握手 / 队友 HUD / 战绩）
- **LAN 房间发现**（`net/coop_lan_discovery.gd`，常驻于 `CoopNet`）：独立 UDP，`DISCOVERY_PORT=24592`；host 开服后每 1s 广播 JSON（`{magic:ETN_COOP, pv, name, port, players, max, mode, game_version}`），**只发不收、绑临时端口**；client 在 LAN 页自动 `browse_start()` 收包、按 `ip:port` 去重、`2.5s` 超时剔除。`ui/coop_menu.gd` 在 `JoinRow` 下动态构建房间列表（点击即填 IP 并加入）。同机自测兜底：额外单播一份到 `127.0.0.1:24592`。
- **版本/协议握手**（`coop_net.gd`）：`PROTOCOL_VERSION` + `MOD_VERSION` + `Game.version_number`；client 连接后 `rpc_id(1,"_client_hello",...)`，host 校验，不一致 `_hello_reject(reason)` 并**延迟 0.5s 再踢**（立即 disconnect 会丢可靠包）；`_on_peer_connected` 不再立即发 lobby/roster，改由握手通过后 `_accept_peer` 执行；未握手连接 5s 超时踢除。i18n `coop_version_mismatch`。
- **实时战绩面板（可编辑场景）**：`ui/coop_scoreboard.tscn`（+ 行模板 `ui/coop_scoreboard_row.tscn`，脚本 `ui/coop_scoreboard.gd`）。按住 `coop_scoreboard`（运行时注册，默认 `Tab`/手柄 Back）显示，居中、无压暗底，行按伤害降序。**静态布局（面板/标题/表头/列宽/字体/颜色/位置）全在 `.tscn` 里，可直接在编辑器手动调整**；脚本只负责输入、按 `CoopNet.team_stats` 实例化行并填 `%Name/%Kills/%Damage/%Coins`（伤害/击杀/金币大数用 **K/M/B/T 缩写**：1 位小数去尾零 + 进位保护，如 `999950→1M`）。
- **战绩数据（host 权威）**：按 peer 累计 `team_stats={kills,damage,coins}`——伤害在 `_on_server_enemy_damage_taken`（本地命中）与 `_server_enemy_hit`（客机转发命中，`suppress_feedback=true` 不发 `damage_taken` 故需单列）两处累加；击杀在 `_on_server_enemy_dead` 按 `last_attacker_by_net_id` 归属；每 1s `_remote_team_stats` 广播。i18n `coop_sb_*`。
- **自测**：`--coop-devdiscover`（只浏览进程，打印 `dev-discover rooms=N`）；`--coop-devbadver`（模拟版本不一致，验证被拒）；`dev status` 附 `team=`。
- **调试窗口开关（OPTION 页，供手机无 F9）**：`ui/coop_menu.tscn` 的 OPTION 页**拉杆下方**新增 `RowDebugHud`（`Label` + 复用 `res://ui/option_toggle.tscn` 开关，样式同本体 FullScreen/Shake/VSync：18×18、不横向拉伸、无 ON/OFF 文本），持久化到 `coop_settings` 的 `[debug] debug_hud`；`entry` 启动即按存档 `set_shown`。菜单经组 `CoopNetDebugHud` 查找 HUD。F9 / `--coop-devhud` 仍保留。
- **调试 HUD 外观**：`ui/net_debug_hud.gd` 改为**顶部居中**（`PRESET_CENTER_TOP` + `GROW_DIRECTION_BOTH` + `offset_top=12`）、字号 **8**；提示文案 `(F9/菜单关闭)`。

## 后续（未实现 / 已知限制）

1. 子弹**提前终止已同步**（撞墙/命中广播 `_despawn_visual_bullet`，`ended` 集合防迟到复活）；特效属性按白名单收集（缺失则跳过）——更特殊的自定义视觉参数仍可能不还原。
2. 中继(WebSocket)**服务端需自备**（仓库不含；协议见 `coop_relay_peer.gd`）；默认 `127.0.0.1:7716`。LAN 开箱可用。
3. 倒地/救援：冷色 tint + `DOWN!/REVIVED!` 飘字 + **救援进度气泡**均已实现（按住 `use`）。
4. 角色专属同步：本体 `player.gd` 汇总子节点 PS 状态，已接 `aris_armed`/`mashiro`；**其余角色/PS 需自行覆写** `get/apply_network_character_state` 才生效。
5. Boss：生成/移动/血量 + `boss_round_start/end` + `GameEvents.boss_event` 总线已同步；**goliath / erosion_tower 动画态已在 client 回放**（仅表现）。其它 Boss 的专属演出可按同一模式（监听 `boss_event`，仅做表现）自行接上。

## Android 导出要求（联机必需）
- `export_presets.cfg` 的 Android preset 必须开启 `permissions/internet=true`（本工程已开；同时开了 `permissions/access_network_state=true`）。缺 `INTERNET` 权限时：ENet/WebSocket 建 socket 失败 → 无法开服/加入、中继连不上、`你的IP` 显示不可用。日志表现：`_inet_open FAILED` / `bind ERR_UNCONFIGURED` / `Host failed: 20` / `Relay connection failed`。
- 手机上中继服务器地址不要填 `127.0.0.1`（那是手机自己）；用实际服务器（如 `mc.yqst.top:32085`）。

## 退出 / 断线 / 失败反馈
- 暂停 `Quit → Yes`：**正常关卡** → 团队 game over 页；**测试房** → 回标题。实现：`_gate_game_over` 在 LAN 下**不再抑制**（host 权威 `_force_team_game_over_authoritative`，client `rpc_id(1,_server_request_team_game_over)`）；玩家死亡仍由 `player_death_gate`（`_gate_player_death`）单独接管，不受影响。
- **客机看不到主机**：host 在收到客机 `_client_scene_ready` 后补发 `_client_sync_roster` + 已存在敌人/召唤物（对齐联机版 `_mark_scene_ready`），确保客机场景就绪后再生成主机镜像。
- **relay 失败可见**：`coop_relay_peer` 在 WS 未连上即关闭 / 初始连接超时（10s）时 `emit relay_error`；`coop_net.close_connection(silent=true)` 避免失败状态被 “offline” 覆盖；覆盖层显示失败原因并复位，不再静默卡“创建中”。
- 已知未处理：客机非正常退出后主机侧镜像可能**短暂保留**（ENet 超时前），无“重连保留”机制，超时后应随 `_on_peer_disconnected` 释放；若长期不消失再排查。

## 加固：场景重置补生镜像 / 返回标题复位（Fix 1+2）
- **远端镜像被本体测试房重置清除**：`scenes/main/test_room.gd:reset_clear_unit()` 会 `queue_free` `PlayerRoot` 下**不在 `"Player"` 组**的子节点；我们的远端镜像在 `"RemotePlayer"` 组 → 被清。修复：`CoopNet._respawn_remote_players()` + `_schedule_respawn_remotes()`（进入一局后 +0.3s/+0.9s 各补生一次）并在 `_client_scene_ready`（host 侧）补生；对已被释放的节点会重造。
- **返回标题未彻底复位**：`change_scene_gate` 的 `player==""` 分支现在调用 `_reset_run_state()`（清 `battle_active`/roster/`selected`/`scene_ready`/`_applying_change`/`_force_release`/`_pending_scene_path` + 取消补生），host 先 `rpc("_remote_return_to_menu")` 再复位；`close_connection()` 也走 `_reset_run_state()`。→ 同进程内回标题后可干净地再次开服/加入/进测试房，无需重启。
- **开发自测**：`--coop-devreset` 在双方进入测试房后调用 `GameEvents.emit_test_room_reset()` 触发一次 `reset_clear_unit`，随后打印 `after-reset remotes`；预期 host/client 均 `remotes=1`（验证补生）。

## 报错清理（`already connected` 红字）
- **`Signal 'coin_changed' is already connected`（`ui/player_up_screen_date.gd`）**：本体该 handler 每次 `GameEvents.get_player` 都无条件 `connect`。**最终修法**：本体 `get_player()` 改为幂等（`player==null` 早退 + `coin_changed.is_connected` 才 `connect`），mod 侧 LAN 下**无条件补发** `get_player`（见「LAN 下 get_player 补发」节）。
  - SUPERSEDED: 2026-10-05 曾用「mod 仅在 `not test_room and not server` 时补发」规避；该启发式在 test_room 本体 `reset_data` 早退时误判，导致客户端/主机都拿不到 player。
- **`Signal 'damage_taken' is already connected`（`register_enemy_spawn`）**：原按 `net_id` 绑定并无条件 `connect`，敌人（池化复用/再次登记）会重连报错。修复：改为**绑定敌人节点**（稳定 callable）+ `is_connected` 去重；`is_dead`（ONE_SHOT）同样改绑敌人并去重；处理函数 `_on_server_enemy_dead(enemy)` / `_on_server_enemy_damage_taken(actual_damage, damage_data, enemy)` 内部再读 `enemy.get_meta("net_id")` 解析 net_id。

## 暂停（LAN 对齐联机版）
- **语义**：LAN 下按暂停**不暂停世界**，只冻结本地玩家（`player_stop = visible` + meta `pause_menu_open`），其他人/敌人/子弹照常；暂停菜单 `process_mode = PROCESS_MODE_ALWAYS` 保持可操作。非 LAN（单机/未开房）仍 `get_tree().paused = visible`。根因：LAN 下若 `get_tree().paused=true` 会停掉 `CoopNet._physics_process`，暂停期间停发本地状态/停收快照，恢复时跳变。
- **本体最小 hook**：`script/extension_hooks.gd` 新增 `pause_visibility`（通知，参数 `[visible, pause_screen]`）与 `is_lan_session`（返回 bool）；`ui/pause_screen.gd` 的 `visibility_changed` 优先走 `pause_visibility`（**未注入即原 `get_tree().paused` 行为，单机零回归**），`_input` 在 LAN 且隐藏时提前 return（打开交给 `player._unhandled_input`）。
- **mod 实现**：`CoopNet._on_pause_visibility(visible, pause_screen)` / `_is_lan_session()`；`pause_menu_open` 用 `player.set_meta()` 记录（本体 `player.gd` 不读）。
- **自测**：`--coop-devpause`（配合 `--coop-devbattle`）打印 `before/open/closed`，随后发一次 `GameEvents.emit_game_over(true)` 并打印 `crosshair player`（复现团队结束路径）；预期 `open paused=false player_stop=true meta=true process_mode=3`、`crosshair player=<本地玩家>`、无 `SCRIPT ERROR`。

## LAN 下 get_player 补发（修复 crosshair/UP 面板空引用）
- **现象**：LAN 测试房内主机暂停 `Quit→Yes`（或收到团队结束）时报 `SCRIPT ERROR: Invalid access to property or key 'stats' on a base object of type 'Nil'`（`scenes/crosshair/crosshair.gd:46 game_over_hide`，`player` 为 null）；客机同样会崩。
- **根因**：本体 `scenes/main/test_room.gd:36-51` 的 `reset_data()` 开头 `player = get_first_node_in_group("Player"); if player == null: return` 早退——LAN 下本地玩家此刻尚未生成，故 `emit_get_player()` 从未执行；mod 旧的 `base_emits` 启发式又误判「测试房本体一定发」，导致双方都不补发 `get_player`，`crosshair`/`player_up_screen_date`/`game_over_page` 等的 `player` 恒为 null。
- **修法**：① mod `_place_and_refresh_local_player` 放下本地玩家后**无条件** `GameEvents.emit_get_player.call_deferred()`（该函数仅 LAN 流程调用）；② 本体 `ui/player_up_screen_date.gd:get_player()` 幂等化（唯一会重复 `connect` 的监听器）；③ 本体 `scenes/crosshair/crosshair.gd:game_over_hide()` 加 `player == null` 空值守卫（纵深，防时序异常）。
- **验证**（`--coop-host/--coop-join` + `--coop-devbattle --coop-devpause`）：双端 `crosshair player=<本地玩家>`、团队结束无 `SCRIPT ERROR`、无 `already connected`。

## 跨端命中反馈互通 + 远程反馈频率选单（对齐联机版）

### 命中"视觉结算"回放（Phase 1）
- 本体 `script/health_component.gd` / `player_health_component.gd` / `summoned_health_component.gd` 新增 `play_hit_feedback(actual_damage, damage_data, do_flash, do_text)`：只做 `damage_taken.emit`（驱动飘字/血条）+ `owner._hurt_flash()` / `_on_invincible_frame`，**不扣血、不发 gameplay 信号**。
- 本体 `health_component.gd:take_damage` 新增第三参 `suppress_feedback`（host 处理客机命中时抑制自然表现，改由 mod 统一回放）。
- mod：host 应用客机命中（`_server_enemy_hit`）时 `take_damage(data, true, true)` 抑制自然表现 → 计算实际伤害 → 本地 `_replay_hit_feedback`（远程来源门）+ `rpc("_remote_hit_feedback", ...)`；host 自身命中由 `_on_server_enemy_damage_taken` 广播（`attacker=host`）。客机 `_remote_hit_feedback` 在镜像上 `play_hit_feedback` + 通用命中火花（`bullet_smoke`）。
- 不再使用旧的 `_remote_enemy_hit`（它只 `_hurt_flash` + 发错信号 `GameEvents.enemy_damage_taken`，而飘字监听的是 `health_component.damage_taken`，导致客机无飘字）。

### 测试房预置敌人确定性注册（Phase 2）
- 测试房 10 个沙包是 `test_room.tscn` 预置，双方各自副本、不走 `spawn_anim` → 从不注册。mod `_register_existing_test_room_enemies()`（`_on_first_round_add` 后）扫描 `EnemiesRoot`，按**子节点索引**分配 `TEST_ROOM_NET_BASE+i` 的相同 net_id：host `_attach_enemy_proxy(server_owned=true)` + 连接 `is_dead/damage_taken`，client `server_owned=false`。此后血量/命中/快照走现有通道，**不生成镜像、不重复**。

### 通用命中火花（Phase 3）
- `play_hit_feedback(do_effect)` 在命中点生成 `bullet_smoke`（经 `CoopVisualSync.spawn_visual_effect`），不区分武器。

### OPTION 页：其它玩家攻击反馈频率（Phase 4）
- 设置：`net/coop_settings.gd` → `user://etn_coop_settings.cfg`，三档独立 `remote_effect_freq` / `remote_flash_freq` / `remote_text_freq`（0=关 / 1=×4 / 2=×3 / 3=×2 / 4=×1，同本体）。
- 频率门（mod）：`remote_effect_allowed(category)` / `remote_flash_allowed(body)` / `_remote_text_should_emit()`；应用到 `_replay_hit_feedback` 与远程视觉弹/特效（`_spawn_one_visual`/`_spawn_one_effect`）。
- **仅作用于其它联机玩家来源**（`is_remote = attacker_peer != 本地`）；本地玩家与敌人/Boss 来源走本体全局设置。
- UI：COOP 菜单新增第 3 个 `OPTION` 页签（`button_id="coop_option"`），内容 `OptionPanel` 三条复用 `res://ui/damage_freq_slider.tscn`。

### dev 自测
- `--coop-devpreplaced`（配合 `--coop-devbattle`）：双端打印预置敌人数量与 #0 血量，host/客机各造成伤害后应两端一致（客机命中走 suppress+回放）。
- `--coop-devmenu`：实例化 COOP 覆盖层并校验 OPTION 面板/三滑条存在。
- 实测：两端 `count=10`；host `35→25`、客机 `25`；客机命中后 host `25→15`、客机 `15`；无 `SCRIPT ERROR`。

### 假人复活（预置沙包）不能当永久死亡
- **现象**：客机击杀测试房沙包后，客机镜像直接消失；主机沙包仍在并回满血。
- **根因**：沙包 `scenes/enemies/sandbag.gd:on_dead()` → `stats.spawn_hp()`（`script/EnemyStats.gd:134-136`，复位 `dead_lock`）**回满血复活**，且 `on_dead` 为 `call_deferred`；而 `_on_server_enemy_dead` 在 `is_dead` 一触发就立即 `erase` net_id + `rpc("_despawn_enemy_remote")`，**发生在复活之前** → 客机镜像被删、主机 net_id 已丢且 `is_dead`（ONE_SHOT）未重连。
- **修法**：`_on_server_enemy_dead` 先发死亡演出，`await get_tree().process_frame ×2` 后判 `enemy.stats.hp > 0`：**复活** → 保留 net_id + `_connect_enemy_dead()` 重连、不发 despawn（快照把满血同步给客机）；否则真死 → 原 despawn。`is_dead` 连接抽出 `_connect_enemy_dead()` 复用。
- **实测**（`--coop-devpreplaced` 客机致命 999）：两端 `count=10 hp#0=35`（客机镜像不消失、两端回满血）；无 `SCRIPT ERROR`。正常（非致命）命中同步仍一致。

## 正常关卡：回合/升级同步、客机敌人朝向、客机子弹穿透

### 回合结束 / 升级（联机版同款：host 驱动 + 客机分支）
- **根因**：`_gate_first_round` 让客机不跑 `round_manager.first_round_start()` → 客机不发 `round_start` → `round_timer.init_round` 不执行 → **客机永不 `emit_round_end`**，故客机不转场/不升级、可移动、敌人不清；主机进升级页后等全员 ready 永远等不到 → 选继续不推进。
- **本体 hook**：`script/extension_hooks.gd` 新增 `round_end_emit_gate`（本端不自发 round_end）、`round_end_proceed_gate`（清场后 return，不本地转场/升级）。
  - `ui/round_timer.gd`：3 处 `emit_round_end` 前加 `round_end_emit_gate`；并移植联机版**客机首轮本地计时**（`_on_first_round_add`/`_start_client_round_countdown`，`init_round` 抽 `_start_round_countdown`；LAN 判定用 `ExtensionHooks.is_lan_session`）。
  - `scenes/manager/round_manager.gd:_on_round_end`：game_over 判断后加 `round_end_proceed_gate`。
- **mod**：`round_end`(host,非 test_room) → `_remote_round_end` → 客机 `emit_round_end()`；`round_upgrade`(host,非 test_room) → `_remote_round_upgrade` → 客机 `emit_round_upgrade()` + `emit_player_buff_clear()` + `paused=true`。两端各自"继续"经现有 `round_upgrade_end_gate` → `_server_round_upgrade_ready` → host 集齐后 `_remote_round_upgrade_end` 推进下一轮。
- **升级独立**：天然按端——`upgrade_manager.add_upgrade_card` 由本端 `emit_round_upgrade` 触发；选卡 `apply_upgrade` 加到本机 `Player` 组的本地玩家、写本机 `PlayerData.current_upgrades`；`level_state` 同步不碰 `current_upgrades`。故每个玩家独立三选一、独立生效。

### 客机敌人朝向（mod）
- **根因**：本体敌人靠自身 `_physics_process` 的 `move()` 按移动方向翻 `graphics.scale.x`；镜像物理帧被关 → 永远默认朝右。
- **修法**：`net/coop_enemy_proxy.gd` 在 `_physics_process` 按快照 `target_velocity.x` 符号设 `enemy.graphics.scale.x`（保留幅值）；并把 `_disable_physics_recursive` 收敛为仅 `enemy.set_physics_process(false)`（对齐联机版，避免误停子节点动画）。

### 客机子弹无限穿透（mod + 本体 hook；保留穿透）
- **根因**：玩家子弹命中走 `HitBox._emit_self_hit` → `HealthComponent.take_damage` → 我们的 `_intercept_enemy_damage` 返回 true → `_take_damage_internal` 跳过；而子弹生命周期（命中烟、`penetrate`、`idle_state` 回池）都在 `damage_data.on_damage_dealt` 里，只有 `_take_damage_internal` 会跑 → 客机子弹不降穿透也不回池 → 无限穿透。
- **本体 hook**：`script/extension_hooks.gd` 新增 `projectile_self_hit_gate`；`script/hit_box.gd` 加 `on_remote_hit: Array` + `run_remote_hit(victim)`，并在 `_emit_self_hit` 的 `hit_received.emit` 前加 gate；`player_bullet.gd`/`normal_bullet.gd`/`megu_bullet.gd` 的 `apply_penetrate_dealt` 把生命周期闭包同时登记到 `on_remote_hit`（开头 `clear()` 防池化复用累积）。
- **mod**：`_gate_projectile_self_hit(bullet, hb)`：客机命中带 net_id 敌人时 `rpc_id(1,"_server_enemy_hit", net_id, _damage_to_dict(bullet.damage_data))` + `bullet.run_remote_hit(enemy)`（本地复刻穿透/命中烟/回池）+ return true（跳过本地结算）。`mashiro_sniper_bullet` 为持续光束（RayCast2D，非投影物），本就经 `_intercept_enemy_damage` 逐目标转发、无穿透问题，未加 gate。

## LAN 报错修复：镜像全局组污染 / 池残留 / Buff 事件 lambda 悬空
- **`Can't add child 'BlackNinperoIcon' ... already has a parent 'PlayerRoot'`**：每个玩家场景带 `Follow` 节点且在**全局 `Follow` 组**（`script/follow.tscn`）；升级道具（`black_ninpero` 等 ~10 个）`_on_equip` 遍历 `get_nodes_in_group("Follow")`、对每个 `follow_use==false` 的节点都 `add_child(同一个 sprite)`。LAN 下远端镜像的 Follow 也在组里 → 同一图标被 add 两次。**修法（mod）**：`spawn_remote_player` 把镜像**及其后代**移出 `Follow` 组。验证 `--coop-devfollow`：两端 `dev-follow total=1 remote=0`。
- **`Invalid access ... 'is_idle' ... previously freed` @ `PoolManager.get_pool`**：清场（`test_room.reset_clear_unit`/`main.bullet_clear_unit`）`queue_free` BulletRoot 子节点但未从池注销，池内残留已释放项。**修法（本体）**：`PoolManager.get_pool`/`get_pool_idle` 取用前 `_prune_freed_bodies(entry)` 剔除失效项并 clamp index；`test_room.reset_clear_unit` 释放前 `erase_pool(pool_id)`。
- **`Lambda capture at index 0 was freed`**：① `BuffManagerBase._ensure_event` 把 lambda 连到 `GameEvents`/`stats`，manager 释放后连接仍在 → 事件触发时 `self` 捕获已释放。**修法（本体）**：`_event_subs[evt]` 存 `{sig, cb}`，`_exit_tree` 逐个 `disconnect`。② mod `CoopVisualSync._queue_free_after` 的 `timer.timeout` lambda 捕获 Node，特效被提前释放（如测试房重置）后定时器触发报错。**修法（mod）**：改用 `WeakRef`。
- 验证：双进程 LAN `--coop-devbattle --coop-devreset --coop-devpause --coop-devpreplaced` 无 `SCRIPT ERROR`/`Invalid`/`Lambda`/`previously freed`，重置后 `remotes=1 enemies=10`。

## 命中飘字同屏重复 + 敌人 buff 权威同步

### 命中飘字同屏重复（客机端 2 次）
- **根因**：host 回放反馈时 `_replay_hit_feedback` 调 `component.play_hit_feedback`（`script/health_component.gd`），其内部 `damage_taken.emit`；而 `_on_server_enemy_damage_taken` 正**连在同一个 `damage_taken` 信号上** → 被这次 emit 触发 → 又 `rpc("_remote_hit_feedback", ..., attacker=host)`。于是客机对同一次命中收到两条（`attacker=client` + `attacker=host`）→ 同屏飘字两次。
- **修法（mod）**：加 `_replaying_feedback` 守卫，`_replay_hit_feedback` 调 `play_hit_feedback` 前置 true、后置 false；`_on_server_enemy_damage_taken` 开头 `if _replaying_feedback: return`。

### 敌人 buff 权威同步（buff_card + DOT）
- **根因**：敌人 buff 由道具/子弹本地直接 `enemy_buff_manager.apply_buff`（多在 `on_damage_dealt` 闭包内），客机被拦截跳过 `_take_damage_internal` → 客机镜像与 host 真敌人都拿不到 buff（无 card、DOT 不可靠）；DOT 结算又用 host 的 `player.stats`。
- **本体**：`script/extension_hooks.gd` 加 `enemy_buff_apply_gate`、`on_enemy_buff_removed`；`scenes/manager/buff_manager_base.gd`：`apply_buff(buff, value, source_id, applier_stats)` 增参并存 `entry["applier_stats"]`、入口 gate、`_remove_buff_entry` 发 `on_enemy_buff_removed`；`scenes/manager/enemy_buff_manager.gd`：DOT/配置改用 `_estat(entry, key)`（施加者属性优先，回退本地 `player.stats`），并加 `_is_remote_mirror()` 在 `add_damage_data`/`count_chill_damage` 跳过（镜像不结算 DOT）。
- **mod**：客机对带 net_id 镜像加 buff → `_gate_enemy_buff_apply` → `rpc_id(1,"_server_apply_enemy_buff", ...)`（host 权威 `apply_buff`，出 card + DOT 在 host 结算 + 经 `_remote_hit_feedback` 播飘字）→ host `rpc("_remote_enemy_buff", ...)` 让客机镜像表现 card（`_applying_remote_buff` 放行 gate）；到期/移除 `_on_enemy_buff_removed` → `_remote_enemy_buff_remove`。
- **验证**（`--coop-devbuff`：客机对预置敌人加 `poison_dot`）：host `keys=["poison_dot"]` 且 hp `35→5`（权威 DOT）；客机镜像 `keys=["poison_dot"]` 且 hp 同步（10）；无 `SCRIPT ERROR`。

## 伤害/proc 按 peer id 归属（host 权威 → 归属端发射）
- **问题**：host 结算全部伤害时 `GameEvents.emit_enemy_damage_taken(_dead)` 在 host 发射 → host 自己的道具/PS 被客机伤害误触发；而客机自己的道具/PS 对自身命中完全不触发。
- **数据（独立 id 落点）**：`script/health_change_data.gd` 新增 `owner_peer: int`（0=本地）；`script/damage_data.gd` reset/`_apply_cfg` 支持 `owner_peer`/`source_node`；mod `_damage_to_dict` 带 `owner_peer`/`source_node`。
- **本体 hook**：`script/extension_hooks.gd` 加 `enemy_proc_owner_suppress`；`script/health_component.gd:_take_damage_internal` 计算 `suppress_proc = suppress_feedback or intercept(enemy_proc_owner_suppress,[damage_data])`，据此跳过 `emit_enemy_damage_taken`/`_dead`/`emit_enemy_over_kill_damage`。
- **host 分发**：`_server_enemy_hit` 设 `data.owner_peer = get_remote_sender_id()`、记 `last_attacker_by_net_id`、按 `killed`（`hp_before>0 and hp_after<=0`）`rpc_id(attacker, "_remote_enemy_proc", ...)`；自然路径 `_on_server_enemy_damage_taken`（含客机归属 DOT）按 `damage_data.owner_peer` 回传归属端。
- **归属端**：`_remote_enemy_proc` → 本地 `GameEvents.emit_enemy_damage_taken(actual, data, mirror_path)`（`killed` 再 `_dead`）→ 只触发归属玩家的道具/PS。
- **DOT**：`enemy_buff_manager.add_damage_data(..., owner_peer=entry.applier_peer)`，host 每跳按施加者回传。
- **β（活来源）**：`script/GameEvents.gd` 加 `player_projectile_hit(bullet, hit_body)`；`script/hit_box.gd:_emit_self_hit` 在 gate 前发射（命中瞬间、live bullet）；`scenes/player/iori/iori_ps.gd`（分裂）与 `scenes/update_item/mint_chocolate_parfait.gd` 改监听它（否则权威延迟回传时 `source_node` 子弹已回池）。
- **验证**（`--coop-devowner`：客机对预置敌人造成伤害）：host `proc=0`、客机 `proc=1`（`op=<客机 id>`），即 host 不被误触发、客机自己触发。

## 命中闭包本地回放 + 测试房重置/换角色同步 + 道具视觉同步

### 问题1：命中 `on_damage_dealt` 客机本地回放（修 poison DOT 无 buff_card / 只跳一次）
- **根因**：`poison_ring.apply_poison_dealt` 把「施加 poison」写在 `hit_box.damage_data.on_damage_dealt` 闭包里；该闭包只在 `_take_damage_internal` 执行。客机命中镜像被 `_intercept_enemy_damage` 跳过 → 闭包不跑、转发又不带闭包 → 两边都不加 buff（无 card、只有 ring 直接命中一下）。
- **修法（mod）**：`_intercept_enemy_damage` / `_gate_projectile_self_hit` 在客机转发前**本地跑 `damage_data.on_damage_dealt`**（用 `data.base_damage`）；host 转发伤害无闭包不重复。**移除** `HitBox.on_remote_hit`/`run_remote_hit`（及 `player_bullet`/`normal_bullet`/`megu_bullet` 的 append，上批为保留穿透所加；`player_projectile_hit` 保留）。
- **验证**（`--coop-devring`：客机生成真实 `poison_ring` 命中预置敌人）：host 与客机镜像 `keys=["poison_dot"]`（card 生成），host hp `35→15`（DOT 多跳）；buff ~1.1s 后过期是 `poison_ring.tscn` 的 `buff_erase_timer=1.1` 设计值（与单机一致）。

### 问题2：测试房重置/换角色同步（清空并只清该玩家）
- **根因**：`character_test_menu.reset_player()` → `emit_test_room_reset` → `reset_clear_unit()` 在**本机**清远端镜像/敌人镜像/本地召唤物/特效；无补生、无 despawn 广播。且 `_replace_player_for_peer` 远端分支**未写回 `player_scene_by_peer`** → 之后按旧路径重建镜像（"切换后仍显示旧角色"）。
- **修法（mod）**：`_replace_player_for_peer` 远端分支补 `player_scene_by_peer[peer_id] = path`、本地分支末尾 `_schedule_respawn_remotes()`；连接 `GameEvents.test_room_reset` → `_on_local_test_room_reset()`：`_schedule_respawn_remotes()` + （host `_respawn_remote_players()` / 客机 `rpc_id(1,"_client_scene_ready")`）+ `_despawn_owned_summons_local()`（只对本机拥有的召唤物广播 despawn，其它玩家的镜像不动）。

### 道具视觉同步（仅视觉）
- **A 常驻图标**：`GameEvents.ability_upgrade_added` → `_remote_item_visual(owner_peer, item_id)` → **非拥有者**端按约定 `res://scenes/update_item/<id>_icon.tscn` 实例化纯视觉图标、挂到镜像的 Follow 标记（依次占用未用 Follow）；`_clear_item_visuals()` 随换人/重置清理。
- **B 生成视觉节点**：`_hook_visual_roots()` 对 `SELayer`/`ForegroundLayer`/`BulletRoot` 挂 `child_entered_tree`；延迟一帧过滤掉 `remote_visual`/`net_visual_id`/`_coop_ps_broadcast`（ProjectileSpawner 已在 `_on_projectile_spawned` 打标）/已广播节点，其余带 `scene_file_path` 者 `_server_visual_node`/`_remote_visual_node` → 对端 `CoopVisualSync.spawn_visual_effect`（禁伤、纯表现）。覆盖 `murky_hand_scythe.shoot_scythe()` 这类直接 `SELayer.add_child` 的道具特效。

## 手感补齐：敌人命中预测 + 远程表现 + 网络诊断 HUD（对齐联机版）

### #1 敌人命中预测（客机）
- **`net/coop_enemy_proxy.gd`（重写）**：维护 `auth_hp` 与 `pending_damage` 列表；`note_predicted_damage(amount)` 即时下调镜像显示血量并返回预测值；`apply_snapshot` 用 host 快照校正/确认 pending；若镜像被预测死亡而快照仍 `hp>0`，`_revive_local_mirror()` 复活（清 `predicted_dead`、`active_state`）。仍按快照速度驱动位置与 `graphics.scale.x` 朝向。
- **`net/coop_net.gd`**：`_get_predicted_enemy_damage`（叠 `global_hurt_damage`）、`_predict_enemy_death`；`_intercept_enemy_damage` / `_gate_projectile_self_hit` 在命中瞬间 `_replay_hit_feedback`（闪白+飘字）+ `_predict_enemy_death`，随后才转发 host。
- **回声去重**：`_remote_hit_feedback(net_id, actual, cfg, attacker, predicted)`；`_server_enemy_hit` 发 `predicted=true`（攻击者已本地预测，跳过）、`_on_server_enemy_damage_taken` 发 `predicted=false`（DOT/自然伤害仍回放）。

### #6 远程表现（纯视觉）
- `_play_remote_enemy_spawn_anim`：远程敌人生成补 `res://script/spawn_anim.tscn` 生成动画（`active_state` + `new_animation`，3s 后释放）。
- `_play_remote_scene_transition_start`：`_remote_change_scene` 前补 `Transition.play_left_start()` 转场并等待 `left_end_start`。
- `_play_coin_pickup_visual`：`_despawn_coin_remote(net_id, picker_peer)` 让金币飞向拾取者再 `idle_state`。

### #3 网络诊断 HUD
- `_update_network_diagnostics`：每 `0.5s` ping/pong 估 RTT、丢包与子弹/特效收发速率；`get_network_debug_text()` / `get_network_quality_debug_text()`。
- `ui/net_debug_hud.gd`：**代码构建** CanvasLayer + 半透明 Label；`entry/coop_entry.gd` 常驻创建，**F9** 切换，开关联动 `set_network_diag_enabled`；`--coop-devhud` 自测。

### 验证
- 双进程 LAN：`--coop-devpreplaced` 客机 `dev preplaced#0 predicted=1 pending=999` → host 权威后镜像回满 `hp#0=35 count=10`；HUD `rtt=7ms loss=0%`；综合回归无 `SCRIPT ERROR`/`Invalid`/`Lambda`/`previously freed`。

## 道具视觉全量复刻 + 红字根治

### 红字根治
- `_remote_item_visual` 改 `@rpc("any_peer")`（纯视觉，避免客机升级时 `authority is 1`）。
- 镜像/视觉副本禁用 Area2D 时同时 `set_physics_process(false)`+`set_process(false)`（`coop_player_proxy._disable_areas`、`coop_summoned_proxy._disable_damage_nodes`、`coop_visual_sync._disable_damage`），根治 `Can't find overlapping bodies when monitoring is off.`。
- `utaha_turret_icon.tscn` 不再当独立图标（它内嵌于 body 场景）。

### 视觉清单（`net/coop_item_visuals.gd`）
- **A 常驻图标**：follow 15 / hat 8 / rail 6 / muzzle 4（id→`<id>_icon.tscn`），挂到**镜像子树内**的对应标记（follow 因镜像 Follow 已移出全局组，按字段查找）。实例化后 `_sanitize_groups` 把图标内嵌挂点移出全局组。
- **内部视觉 7**：`cathedral_candle/energy_supplement/ginseng_doll/kitchen_knife/spiked_shell/life_jacket/little_kei`，`set_script(null)` + 递归剥玩法（Area2D/CollisionShape2D/Timer/Label），`net/coop_visual_driver.gd` 做最小位置驱动。
- **持久身体**：`utaha_turret`（已由召唤同步覆盖）；`shiroko_drone`/`robotic_vacuum_cleaner` 经 `_hook_visual_roots` 检测后接入召唤通道（`PERSISTENT_BODY_SCENES` + `_register_persistent_body`），仅视觉镜像 + 变换同步。
- **B 生成型**：`_hook_visual_roots` 扩到 `EquipLayer/FloorLayer`；`player_bullet_launcher` 跳过。

### 武器同步
本体无运行时换枪（枪是角色场景静态实例），镜像按角色场景同步即含正确枪；镜像 `Gun` 置惰性避免朝本机玩家开火（`coop_player_proxy`）。

### 验证
双进程 LAN 双向授予 9 件代表道具：镜像端全部建成、`summons=2`、无 `%Sprite2D`/RPC/`monitoring` 红字；综合回归零错误。

## 远端投射物销毁同步（修 shiro_missile 穿过敌人）

- **根因**：远端投射物是纯视觉克隆（`_disable_damage` 关了 `monitoring`），不会自行命中；其销毁靠拥有者广播 `on_projectile_despawned`。`shiro_missile.idle_state()` 漏了该通知 → 远端只等自身超时才消失（表现为"穿过敌人"）。
- **本体**：`scenes/update_item/shiro_missile.gd`、`scenes/player/mashiro/cross_bullet.gd` 的 `idle_state()` 补 `ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned,[self])`；`shiro_missile.gd` 新增 `visual_idle_state()`（复位但不 `add_explosion`，避免观察端重复爆炸）。
- **mod**：`net/coop_visual_sync.gd` 新增 `_visual_idle()`（优先 `visual_idle_state`，回退 `idle_state`），`despawn_visual_bullet` 与 `_acquire` 淘汰分支均改用它。
- **回归修复**：撤销 `_disable_damage` 对运动节点的 `set_physics_process(false)`（会把远端子弹冻住）；process 关停只保留在 player/summon 镜像禁用路径。
- **验证**：双进程 LAN，客机 shiroko_drone 打敌人 → host 收到同 sync_id 的 `_despawn_visual_bullet` 并移除导弹；无红字；综合回归零错误。

## 远端命中反馈按来源还原

- **子弹**：订阅 `GameEvents.player_projectile_hit`（拥有者命中瞬间）→ 按子弹类广播 `bullet_smoke`（`PlayerBullet`）/`bullet_smoke_2`（`SummonedBullet`）；`PlayerMortarBullet` 跳过（走爆炸）。
- **爆炸**：本体 `ExtensionHooks.on_explosion_effect`（`explosion_damage.is_explosion`/`is_small_explosion` 通知）→ 广播 `explosion.tscn`/`small_explosion.tscn` + `ExplosionSounds`。
- **近战/装备额外命中音**：本体 `ExtensionHooks.on_hit_sfx`（各 `HurtSounds2` 调用点通知）→ 广播该 key。
- **通用受击**：`_replay_hit_feedback` 去掉通用 spark，补 `HurtSounds`（与本体一致，每端每击一次）。
- **远端音效限流**：每 key `80/mult` ms + 全局 `33ms`，复用「远端效果频率」档位（0=关远端命中音）；本地自身不受限。
- **对象池**：`_remove_effect_from_gameplay_pools` 按场景路径剔除 `big_explosion`/`small_explosion`，避免新实例污染本体池。
- **验证**：双进程 LAN，客机爆炸 → 观察端 `ExplosionSounds` 与爆炸次数一致；子弹烟/近战音按来源广播；综合回归零错误。

## 修复：远端"123456789"飘字 + 主机属性被重置

- **飘字**：`ui/floating_text.tscn` 的 Label 默认文本是占位符 `"123456789"`；mod 原先把 `ForegroundLayer` 的飘字当通用视觉广播，接收端实例化不调 `start()` → 显示占位符。改：`_maybe_broadcast_visual_node` 跳过 `ui/floating_text.tscn`；`_remove_effect_from_gameplay_pools` 补 `floating_text` 映射。
- **属性重置**：`ui/AbilityBox` 用全局组 `Player` 缓存本机玩家；`spawn_remote_player` 原先"先入树再移出 `Player` 组"，入树窗口内容易被缓存到镜像（显示镜像基础属性）。改：**入树前** `p.remove_from_group("Player")` + `add_to_group("RemotePlayer")`。实测镜像 `in Player group? false`、`PlayerGroupSize=1`。

## 修复：测试房角色卡换人未同步
- `ui/character_test_card.gd` 的角色卡选人原先直接替换本地玩家，绕过 `local_player_change_gate` → mod 不广播换人。改为与 `character_test_menu`/`test_menu` 一致：`if not ExtensionHooks.intercept(ExtensionHooks.local_player_change_gate, [player_path, Vector2.ZERO]): ...`。修复后其它端镜像即时更新，无需按重置。

## 召唤物/道具：转向 + 开火表现同步
- **转向**：本体 `turret_summoned.gd` / `shiroko_drone_icon_2.gd` 实现 `get_network_visual_rotation`/`apply_network_visual_rotation`；`coop_summoned_proxy` 本就优先用它们同步（无需改代理）。镜像端炮台随敌人转向、无人机螺旋桨/机身朝目标转动。
- **开火**：本体 `turret_summoned._shoot_bullet` 发 `ExtensionHooks.on_summoned_action`（含 `GunSounds4` + 闪光场景/位置）；mod 广播，接收端 `network_play_action("shoot")`（后坐动画）+ 生成炮口闪光 + 音效（走远端限流）。host 在 `_server_summoned_action` 本地也应用一次。
- **去重**：owner 的炮口闪光打 `coop_action_flash` meta，`_maybe_broadcast_visual_node` 跳过，避免与动作广播重复。
- **范围**：无人机只做转向（开火视觉已是同步的导弹）；炮台做转向 + 开火动画/闪光/音效。

## 同步缺口大批修复（审计后）
- **敌人**：镜像不再本地跑 AI/开火（`active_state()` 后显式停 root 物理 + StateMachine）；快照带 `state` 位，代理端 `transition_state` 驱动镜像动画。
- **玩家镜像**：状态包带 `max_hp`（血条正确）；身体瞄准旋转；`player_gun_shoot` → 镜像重放开火后坐。
- **池化道具特效**：新增 `ExtensionHooks.on_visual_activated`，镰刀/火场/毒环/冰环在每次激活时广播（不再只首次）。
- **召唤**：炮台装弹动画走 `on_summoned_action("reload")`；扫地机补 `get/apply_network_visual_rotation`。
- **敌人部件**：镜像生成后激活 `body_part`。
- **Boss**：`goliath`/`erosion_tower_group` 镜像端跳过相机/暂停演出（避免镜像本地 pause），只播动画。
- **掉落**：`pyroxenes` 生成广播纯视觉副本（`CoinRoot` 纳入广播组）。
- **已知未做**：medkit（各端独立随机生成）、coin_box 抛物线只同步起点、SceneProp（未放置）。

## 批A：刷怪门 / 敌人选敌 / 角色事件通道
- **H1 客机不本地刷怪**：`ExtensionHooks.round_enemy_spawn_gate`；`enemy_manager.round_enemy_spawn_start` 前置门；mod 非 host 跳过。
- **H2 host 敌人锁定客机玩家**：`entity_ENEMY.get_nearest_player()`（host 加扫 `"RemotePlayer"` 组、过滤 `is_downed`）；子类 `enhanced/modded_sweeper`、`sweeper`、`goliath`、`enemy_tank`/`tank_gun_1` 改走 `get_target()/get_target_position()`。
- **M5 角色专属事件通道接口**：`ExtensionHooks.on_character_event`；`player.broadcast_character_event()` / `player.apply_network_character_event()`（子节点转发）；mod `_on/_server/_remote/_apply_character_event`。暂无调用点（供未来角色 EX 等）。

## 批B–E：稳健性/完整性/性能/低优先
- **批B**：子弹/特效批按 128 切包；特效通道改 `reliable`；新增 reliable 一次性投射物通道（`coop_reliable_visual` meta）；`player_gun` 每次开火广播枪口闪光。
- **批C**：升级页队友就绪 — `GameEvents.upgrade_ready_changed` + `UpgradeScreen` 代码构建就绪标签 + mod 广播/槽位映射。
- **批D**：远程特效池化（`CoopVisualSync._effect_pool`，仅可复用特效）。
- **批E**：pyroxenes 非拾取端补拾取事件；选人等待带人数；`shiroko_drone` 镜像挂 `EquipLayer`；敌方视觉弹"伤害洞"遍历全部 HitBox。
- **未做**：L1（同步替换无需等待）、L2（倒地全屏演出）。

## L2：本地倒地全屏表现
- 新增 `ui/motion_down_screen.gd`：复用本体 `shaders/motion_screen.gdshader` 的全屏灰度遮罩 + 0.5s 慢动作（`Engine.time_scale=0.1`，`ignore_time_scale` 计时恢复）。本地玩家倒地时显示、复活/重置时收起；纯本地、不影响其它端。

## 敌人策反同步 + host 敌人 buff 广播
- **策反**：`ExtensionHooks.enemy_conversion_interceptor`；客机 `apply_conversion_power`（ako/yukari 直接调用）转发 host；快照带 `converted`/`gauge`，镜像 `entity_ENEMY.apply_network_conversion` 只复刻阵营/组/描边/gauge（伤害型 `convert_power` 已随伤害转发）。
- **host 敌人 buff 广播**：`ExtensionHooks.on_enemy_buff_applied`（`apply_buff` 末尾）→ host 广播 `_remote_enemy_buff`；移除 `_server_apply_enemy_buff` 的显式 rpc（避免双播）；`converted_buff` 镜像不加 card。
- **dev**：`--coop-devconvert`（客机对敌人发起策反，验证转发+快照）；`--coop-devbuff` host 侧也施加 poison（验证 host→client 通道）。

## 敌人部件（body_part）：hp / 闪白 / 碎裂 / 预测同步
- **背景**：部件（`EnemyPart`）此前**完全没同步**——部件镜像没有 `net_id` meta，伤害拦截直接放行，客机打部件只在本地镜像掉血，host 真实部件也各算各的。
- **识别**：镜像部件打 `coop_owner_net_id`/`coop_part_index` meta；`_net_entity_of` 优先返回部件节点。
- **客机命中（与根同款即时预测）**：`_handle_part_hit` → `_get_predicted_enemy_damage` + `_replay_hit_feedback`（闪白；部件无飘字节点故无飘字）+ 乐观扣血/预测碎裂 → `rpc_id(1,"_server_enemy_part_hit",...)`。
- **host 权威**：`_server_enemy_part_hit` 用 `take_damage(data,true,false)`（不抑制 → host 原生闪白/受击音 + `damage_taken`）；`_connect_enemy_parts` 连部件 `damage_taken` → 广播 `_remote_enemy_part_hp(net_id,idx,hp,true)`（host 自身打 + 客机转发的单一广播点）。
- **镜像应用**：写 `predicted_hp`、撤销/触发 `predicted_dead`；`hp<=0` → `stats.hp=0` + `idle_state`（碎裂）；否则写 hp + 限流 `_hurt_flash`；`active_state()` 会重置满血，须在其后再写 hp。
- **晚加入**：`_enemy_part_hps` 随 `_spawn_enemy_remote(...,part_hps)` 一次性下发（`register_enemy_spawn` / `_send_existing_enemies_to_peer`）。
- **顺带修**：`_health_component_of` 改为优先取**直属子级** HealthComponent（此前纯递归会先取到 `Graphics` 下的**部件**组件，导致 `tester_automaton_shield` 根伤害/预测落到部件）。
- **dev**：`--coop-devpart`（host 生成 `tester_automaton_shield`；客机对部件/根分别施加伤害并打印两端 hp）。
- **验证**：双进程 LAN——host 部件 hp=[200]；客机打部件 → 两端 200→195（预测即时一致）；再打根 → 两端根 380→350 且部件不变；零红字。

### 补充验证：host 打部件 / 重发已存在敌人（part_hps）
- **host 打部件**（`--coop-devparthost`）：host 打自身真实部件 200→195；客机镜像 `early=200 late=195`，`dev_part_stats()={hp_applied:1, flash_applied:1}`（权威 hp 广播 + 闪白均到达）。
- **重发已存在敌人**（`--coop-devrejoin`）：客机 `dev_evict_enemy(1)` 移除镜像后，host `dev_resend_existing()`→`_send_existing_enemies_to_peer` 重发；客机重新生成 net=1 且 part0 回到 host 当前值（190=190）→ 该路径的 `_spawn_enemy_remote(...,part_hps)` 与常规广播一致。
- **说明**：`--coop-devbattle` 双端各自换场景，加入会触发 host 场景重入（`host battle start` 第二次），运行期敌人不会在“中途加入”中保留；这是加入/scene 同步的既有行为，与部件无关。

### 修复：utaha_turret 开火后坐远端 scale 持续放大
- **根因**：`script/turret_summoned.gd:_shootAnim` 的 tween **目标取"当前 scale"**；远端镜像 `dur` 与拥有者射速不一致（镜像不跑 `shoot_time_count`，`wait_time` 为场景默认），开火间隔 < `dur` 时两段 tween 重叠，每次把目标抬高 → 静止 scale 累积放大（拥有者本地 `dur==射速`，故只在远端暴露）。
- **修法**：`_shootAnim` **锚定基准 scale**（`_recoil_base` 首次记录）+ 保存 `_recoil_tween` 并在开新动画前 `kill()` → 幂等；`scenes/enemies/enemy_tank.gd:_shootAnim` 同款。
- **后坐时长同步**：`ExtensionHooks.on_summoned_action` 通知新增第 7 参 `dur`（开火传 `_recoil_duration()`、换弹 `0.0`）；mod `_on/_server/_remote_summoned_action` 透传，`network_play_action(action, dur)` → `_shootAnim(dur)`，镜像时长与拥有者射速一致。
- **dev**：`--coop-devscale` + `dev_turret_scale()` 打印本端炮台 `%Sprite2D` 子 scale。
- **验证**：双进程 LAN `--coop-devitems --coop-devscale`，6 次采样（含 0.24s/1.0s 两种射速、拥有端+镜像端）scale 恒回落 ~1.0、峰值 ≤ ~1.39，无累积；换弹正常；零红字。

### follow_icon 简化（去 CharacterBody2D）+ 远端跟随链式同步
- **简化**：`scenes/update_item/follow_icon.gd` 由 `CharacterBody2D` 改为 `Node2D`，`velocity` 自持，`move_and_slide()` → `global_position += velocity * delta`（无碰撞等价）；15 个 `*_icon.tscn` 根节点 `CharacterBody2D` → `Node2D`（确认无碰撞属性/形状）。
- **根因**：远端 follow 图标此前各自调用 `_ensure_marker(mirror,"follow")`，而镜像玩家 `Follow` 被移出全局组 → 每次在镜像玩家下新建标记 → 所有图标都追玩家，不成链。
- **修法（纯 mod）**：`coop_item_visuals.build_icon` 的 `follow` 分支取上一个图标 `mirror.get_meta("coop_last_follow_icon")` 的内部 `Follow` 作标记，首个回退镜像玩家 `Follow`；建好写回 meta。`_clear_peer_item_visuals`/`_clear_item_visuals` 移除 meta。
- **dev**：`--coop-devfollows`（授予 6 件 follow 道具）+ `dev_follow_marks()`。
- **验证**：双进程 LAN，两端链均为 `CoopRemote_X/Follow ← iconA/Follow ← iconB/Follow ← …`（一个跟一个），零红字（本地/远端同名图标被 Godot 自动改名 `@Node2D@id`，无害）。

### 修复：联机测试房主机首件道具属性被重置（base 未捕获）
- **根因**：`test_room.reset_data()` 在本地玩家尚未入 `"Player"` 组时**提前 return**（LAN 下玩家由 `change_scene` 延迟 `add_child`，而 `_ready` 只等 0.1s）→ 跳过 `PlayerData.reset_date()`/`get_player_base_ability()` → `base_*` 保持默认 0 → 首个道具触发 `update_player_ability()` 把属性重算成默认。
- **修法（本体）**：`test_room.reset_data()` 改为**有界等待玩家入组**（≤30 帧）+ 重置令牌；`main.first_round()` 加同款防御等待。
- **另修（mod）**：`_server_player_selected` 已开打时**不再重载整局**（原会清空主机进度/属性），改为只让新客机进入当前场景并补生在局镜像/敌人/召唤物。
- **验证**：主机 `base_max_hp=72`（修复前 0）；中途加入 `host battle start` 仅 1 次、新玩家正常入局；综合回归零红字。

### 修复：远端玩家镜像受击闪白卡住不恢复
- **根因**：`_remote_player_hurt` 只调 `_on_invincible_frame(true)`，未启动镜像的 `InvincibleFrame` 计时器；闪白归零在 `_on_invincible_frame_end()`（由计时器 `timeout` 触发），不启动则 `flash_opacity` 停在 0.3。
- **修法（mod）**：`_remote_player_hurt` 复刻本体组合——先 `invincible_frame.start()` 再 `_on_invincible_frame(true)`。无需改本体。
- **验证**：双进程 LAN，主机轮询客机镜像 `flash_opacity`：受击后 `1.00→0.30→0.00`，~0.5s 归零；零红字。

### 调整：联机倒地滤镜模糊降低
- `ui/motion_down_screen.gd` 的 shader 参数 `f`（mipmap LOD 偏移=模糊）由 `1.1` 降为固定 `0.3`，保留轻微模糊；`v`(15.0)/`grayscale` 不变。仅改 mod 倒地滤镜，本体死亡结算界面不动。

## 玩家 ID：选项页输入 + 持久化 + 头顶名牌同步
- **设置持久化**：`net/coop_settings.gd` 新增 `[profile] player_id`（`user://etn_coop_settings.cfg`），空串=未设置。`sanitize_name()` 去换行/首尾空白；`MAX_NAME_LEN=12`。
- **常驻顶部输入**：`ui/coop_menu.tscn` 将 `RowPlayerId`（`Label` + `LineEdit %PlayerIdInput` + `Button %PlayerIdConfirm`，按钮复用本体键 `button_confirm`）置于 **`ContentRoot` 顶部、`Header` 之上**（所有页签 LAN/RELAY/OPTION 均可见、显眼）；原 `Start`/`Test Room` 按钮已删除。`LineEdit` **不设 max_length**。
- **保存流程**（`ui/coop_menu.gd:_submit_player_id`，由「确定」按钮 `pressed` / 回车 `text_submitted` 触发）：调用 `CoopNet.set_local_display_name()` 单一校验入口 → `>12` 字符拒绝并弹底部 toast `coop_player_id_too_long`；否则存盘 + toast `coop_player_id_saved`（复用本体 `res://ui/mobile_notice.tscn`）。触屏点输入框弹虚拟键盘。
- **头顶名牌**：`net/coop_name_tag.gd`（`extends Label`，字体 `res://fonts/BoutiqueBitmap7x7_1.7.ttf`，字号 8、白字黑描边、半透明 `font_color.a=0.8`）。作为玩家节点子节点，`_process` 每帧 `position.y = sprite_2d.position.y - 49`，**跳跃时随 `sprite_2d` 同步上移**，且不随瞄准旋转；`z_index=10`。不做跨语言字体强锁。
- **名称同步**：`CoopNet.player_name_by_peer`；`_on_first_round_add` → `_report_local_name()`（主机直写并广播，客机 `rpc_id(1,"_server_player_info")`）；主机 `_server_player_info` 记表 → 向该端回发 `_remote_player_info_batch` 并通知其它端 `_remote_player_info`。挂载点：本机就位 / 换角色 / `spawn_remote_player`。复位（`_reset_player_sync`）清空。
- **未输入回退**：`_join_index_of()` 用 `{1} ∪ get_peers() ∪ {self}` 去重升序取 `index+1` → 显示 `Player1/2/3/4`（按加入顺序）。
- **i18n**：`coop_option_player_id` / `coop_option_player_id_placeholder` / `coop_player_id_saved` / `coop_player_id_too_long`（zh_CN/en/pt/vi_VN）。

## 联机玩家头顶生命条 + 倒地闪红/HELP!
- **仅远端**：`CoopNet._attach_name_tag()` 在 `peer_id != 本机 id` 时调 `tag.attach_health_bar(player)`；本地玩家自身血量见底部 HUD，不显示头顶血条。
- **头顶布局（上->下，名牌本地坐标）**：`HelpTag`（仅远端倒地）`y=-31` / `ReadyTag`（已准备，本地与远端一致）`y=-17` / `CoopHealthBar`（仅远端）`y=-6` / 名牌文本 `y=0`。均已抽为常量，位于 `net/coop_name_tag.gd`。
- **`net/coop_health_bar.gd`**（`extends Control`，`_draw()` 自绘，无 `class_name`，由名牌 `preload`）：深底 + 绿色 `hp/max_hp`；条内异色段（浅蓝）叠加临时生命，从 `hp%` 画到 `min(1,(hp+t_hp)/max_hp)`。纯血条，无数字。
- **临时生命同步**：玩家状态 RPC 新增 `t_hp`/`max_t_hp`（`_send_local_player_state` → `_server_receive_player_state` / `_apply_player_state` → `CoopPlayerProxy.apply_state`）。proxy 侧先同步 `max_t_hp` 再设 `t_hp`（setter 依赖上限钳制），并写 `player.set_meta("net_t_hp", …)`；`hp` 仍 clamp 至 ≥1（不本地判死）。
- **倒地表现**：读远端镜像的 `player.is_downed`（由 `_remote_player_down_changed → set_downed_state` 驱动，无需新增同步）。倒地时血条整条**平滑呼吸红**（`sin`，`FLASH_PERIOD=0.5`，暗红↔亮红），并显示 `HelpTag`（`tr("coop_help")`，字体 `BoutiqueBitmap7x7`、字号 12、白字红描边），`_process` 用 `sin` 上下轻微浮动（幅度 2px、周期约 1s）；恢复后自动收起。
- **i18n**：新增 `coop_help`（zh_CN/en/pt/vi_VN 均为 `HELP!`）。
- **验证**：`--coop-devhp`（等 `battle_active` → 打印 `dev_health_state()` → 本地造伤害/设临时血 → 再打印）；双进程 LAN 下 client 能看到 host 的 `hp`/`t_hp` 变化。定向脚本验证 `HelpTag`/`CoopHealthBar` 位置、倒地可见、浮动、恢复隐藏均符合预期。

## 房主离开：提示 + 过场回主菜单（LAN/Relay）
- **目标**：房主退出应用/掉线时，客机不再卡死 → 弹底部提示 → 过场动画 → 回 `res://scenes/main/menu_screen.tscn`。
- **触发（统一入口 `CoopNet._handle_host_left()`）**：
  - 优雅关闭：`multiplayer.peer_disconnected(1)`（`_on_peer_disconnected`）/ `server_disconnected`（`_on_server_disconnected`）。
  - 硬杀/掉线：ENet 在本机不一定及时触发 `server_disconnected`，故加**应用层心跳**——房主每 1s 广播 `_host_heartbeat`（`reliable`），客户端 `HOST_TIMEOUT_MSEC=8000` 未收到即判定房主离开；战斗期 `_apply_player_state`（~20Hz）亦刷新存活时间。心跳一律用**墙钟**（`Time.get_ticks_msec`）计时，避免场景切换 / `Engine.time_scale` 造成发送间隔漂移。
  - 仅 `客户端 + (is_lan_game or is_relay)` 判定（`_should_return_client_to_menu`）。
- **流程**（`_handle_host_left`，**deferred** 执行）：解除暂停（`_set_select_pause(false)` + `paused=false`）→ `close_connection(true)` → 底部 toast `coop_host_left`（复用 `ui/mobile_notice.tscn`，挂当前场景下新建 `CanvasLayer`，随切场景释放）→ 等 1.5s → `Transition` 左划过场（`_play_remote_scene_transition_start`）→ `GameEvents.change_scene(MENU_SCENE,"")` + `Input.mouse_mode = VISIBLE`。
- **去重**：`_returning_to_menu_due_to_close`（在 `_reset_run_state()` 清零）。
- **关键坑**：**严禁在 multiplayer 信号回调栈内释放传输**（`multiplayer.multiplayer_peer = null`）——会 segfault；故 `_schedule_host_left_return()` 先同步占位去重、再 `call_deferred("_handle_host_left")`，并在入口 `await tree.process_frame` 脱离回调栈。
- **i18n**：`coop_host_left`（zh_CN/en/pt/vi_VN）。
- **自测**：host `--coop-devhostdrop`（战斗后优雅断连并退出）；client 加 `--coop-devquit`（保持连接等待检测，回主菜单后优雅退出以刷新日志）；硬杀 host 进程亦可验证。预期 client 日志出现 `host session closed -> return to menu` 与 `returned to menu: res://scenes/main/menu_screen.tscn`。



## 修复：页签收回动画只作用于「上一个选中」的页签
- **旧行为**：`coop_menu._update_mode_visuals()` 每次切换都对 `lan/relay/option` **三个页签全部** `_deselect_tab()`（`play_backwards("on_select")`），于是未选中的页签也会播收回；且已选中页签的 `on_show` 被复位为 false，鼠标从其移开时会误触发 `option_button.mouse_exitedd_anim` 的收回。
- **新行为**：记录 `var _active_tab`，仅对**前一个**页签 `_deselect_tab()`；新页签 `on_show=true` 并仅在当前动画不是 `selected` 时 `play("selected")`；第三个页签完全不动。
- **验证**（`--coop-devmenu`）：`LAN->OPT` 时 `lan=on_select relay=(空) option=selected`；`OPT->LAN` 时 `lan=selected relay=(空) option=on_select`（relay 全程未被触碰），无报错。

## 准备房流程：测试房 → 开始球 → 选人 → 就绪 → 房主难度 → 进关卡

> 新流程：**测试房作为准备房**。开房后 host 自动进入测试房等待其它玩家；房主点绿色开始球进入选人；各端选角色（顶部支援选择行，首项「空」）+ 点角色即就绪；全员就绪后房主选难度+游戏模式，统一进入关卡。纯 mod 实现，本体仅加 1 行（见末尾）。

### 状态机（`net/coop_flow.gd` + `CoopNet`）
- `CoopNet._flow_phase`：`IDLE → LOBBY → SELECT → ALL_READY → BATTLE`；新增信号 `select_begin` / `select_all_ready` / `select_cancelled` / `select_ready_changed`。
- 编排层 `net/coop_flow.gd`（`CoopFlow.instance`，常驻）连接上述信号，负责覆盖层生命周期与玩家输入门控；覆盖层挂到当前场景下，切场景自动释放。
- **进准备房**：`CoopNet.enter_lobby()`（host）重置状态 → `_force_release=true` → 广播 `_remote_change_scene(test_room, roster)` → 本地切测试房。`host_game()` 成功 / `_on_relay_room_created()` 后自动调用（`auto_enter_lobby`，devbattle 时关闭）。绕过选人握手（走 gate 顶部 `_force_release` 短路）。
- **后加入者**：`_on_peer_connected` 在 `LOBBY` 且当前是 test_room 时 `rpc_id(id,"_remote_change_scene", test_room, roster)` 直接送入准备房。
- **选人**：房主与开始球交互 → `request_begin_select()`（`_flow_phase=SELECT`、`_select_flow_active=true`、广播 `_remote_select_begin`）。
- **选人阶段全局暂停**：进入选人即 `_set_select_pause(true)`（各端本地 `get_tree().paused=true`），测试房世界（敌人/子弹/特效/玩家）全部停止、切断操作；因此 `CoopNet` 常驻 `PROCESS_MODE_ALWAYS`（暂停下仍收发 RPC/握手），选人/已就绪/难度三个覆盖层也 `PROCESS_MODE_ALWAYS`（暂停下仍可鼠标/键盘操作、子节点 AnimationPlayer 继续跑，保证卡片 `add_card` 动画结束把 `mouse_filter` 置 STOP）。进关卡（gate `ALL_READY` 分支 / `begin_battle` / `_remote_change_scene`）与回准备房/回菜单（`_reset_run_state`）均解除暂停。
- **选人阶段守卫**：`_server_player_selected` 在 `_select_flow_active` 时**只记录** `selected_player_scene_by_peer`，不再自动 `_broadcast_roster`（否则选完人立刻开战、跳过难度）。
- **就绪**：`report_select_ready(bool)` → host `_set_select_ready`；全员就绪 → `_maybe_finish_select()` 广播 `_remote_select_all_ready`（非 host 转「等待房主选择」）。
- **ESC 分层语义**：① 选人层（房主尚未选角色）按 `ESC` → `abort_select_to_lobby()`：取消整轮选人、全员回准备房并**解除暂停**；客机在选人层按 `ESC` 仅被吞掉（不弹本体暂停菜单）。② 已就绪遮罩按 `ESC` → 仅取消**本人**就绪、回选人层（世界保持暂停）；全员就绪后客机锁定。③ 难度面板按 `ESC` → `cancel_select()` 广播 `_remote_select_cancelled`，全员清 ready、回选人层（世界保持暂停）。
- **进关卡**：难度按钮走本体 `level_button` → `GameEvents.change_scene(main, player)` → `_gate_change_scene` 的 `ALL_READY` 分支（先解除暂停）`_broadcast_roster()` 放行；`level_state` 现含 `game_mode` 数组（`_build/_apply_level_state`）。
- **`_on_character_confirmed` 顺序**：`report_local_selection` → 隐藏并延迟释放选人层 → `_open_ready` → **最后** `report_select_ready`。否则房主作为最后就绪者时，同步触发的 `select_all_ready` 会先开难度面板、随后才叠上「已就绪」把它盖住（已就绪 layer 101 < 难度 102，且 `_close_ready` 立即 `visible=false`）。

### 界面（新增）
- `ui/coop_room_label.gd`：右上角房间标识（LAN=本机 IP:端口，Relay=房间码），`CoopNet.get_room_display_text()`；字体 `BoutiqueBitmap7x7_1.7`/字号 10（深色小面板 + 绿字）。**仅准备房（test_room）且未进入选人时显示**（选人/关卡内隐藏）。黑色底板**按文字宽度自适应**（`PanelContainer.reset_size()` + 每帧贴右上角 `vw - size.x - 8`，右缘固定距屏幕右 8px），不再固定 292px 宽。
  - **关卡内在暂停页显示**：`net/coop_net.gd:_on_pause_visibility` → `_update_pause_room_label()` 在暂停页 `Node2D10/Node2D9/langue_button`（LANGUAGE 下拉）下方 `+40px` 处插入房号 Label（深色小面板 + **白字 + 深绿描边**，字体 7x7/10），随暂停显隐；准备房暂停时也显示。
- `ui/coop_start_ball.tscn`（`instance` `res://scenes/yellow_ball.tscn` + 脚本 `coop_start_ball.gd`）：绿色开始球。**运动/碰撞/交互完全复用本体**（可被玩家与其它球推动、悬停描边、气泡提示），仅覆写 `prompt`/`interact`。气泡「开始游戏」。由 `CoopFlow` 在 test_room 的 `YSort` 下生成（组 `CoopStartBall` 去重）。
  - **大厅准备门槛**：非房主互动 → `CoopNet.toggle_local_ready()` 切换自己的「已准备」；房主互动 → `are_all_players_ready()`（**不含房主**，无客机即 true）成立则 `request_begin_select()`，否则在球气泡上方弹红字 `coop_players_not_ready`（0.1s 自下而上淡入 → 停 2s → 收回）。
  - **「已准备」显示**：`net/coop_name_tag.gd` 在玩家名牌上方建子标签 `ReadyTag`（`tr("coop_prepared")`，字体/字号同名牌 `BoutiqueBitmap7x7`/8）；`set_ready(bool)` 0.1s 自下而上淡入 / 倒放收回；子标签随名牌每帧定位（含跳跃同步）。联网同步：`CoopNet.lobby_ready_by_peer` + `toggle_local_ready`/`_server_lobby_ready`/`_remote_lobby_ready`（幂等）；进入选人 `_clear_lobby_ready()` 清空并广播，断线/回准备房/开战亦重置。
  - **染绿方式（贴图 + 运行时建帧）**：贴图随 mod 打包 `res://mods/etn_coop/sprites/item/green_ball.png`；因 mod pck 的 png 无导入资源，`coop_start_ball.gd:_ready` 用 `load()`（编辑器内命中）否则 `Image.load_png_from_buffer` 取图，再按**与本体黄球完全一致的 20 个 atlas 区域、相同顺序**构建 `SpriteFrames` 赋给 `$Sprite2D`。保留本体 `sprite_outline` 材质（`set_highlight` 高亮正常）。不再依赖本体 `res://sprites/item/green_ball.png`。
- `ui/coop_select.tscn` + `coop_select.gd`：选人覆盖层。**静态布局在场景**（可在编辑器调），脚本动态填充，且**只读取玩家已解锁内容、不实例化锁定项**：
  - 社团：来自本体注册表 `ModManager.get_base_societies()`（单一来源，见下）+ `get_mod_societies()` + MOD 通用卡；实例化前按 `PlayerData.group.has(gid)` 过滤。
  - 角色：复用 `ui/society_card.gd:populate_player_cards()`（已改为**先读卡内 `player_card.id` 再决定实例化**，只实例化 `PlayerData.character.has(id)` 的角色）。
  - 支援：顶部支援行复用 `ui/support_ui/support_shop_card.tscn`，**首项 `null_support`（空）**，其余只取 `SupportData.support_data`（已解锁），与本体关卡选择的支援选择一致。
  - 点角色卡（监听 `GameEvents.player_card_id`）即确认。
  - **动画 / 顺序**：场景内 `AnimationPlayer` 的 `show_anim`（0.1s：背景淡入 + 各容器从侧/上方滑入 + `PlayerScroll` 横向擦除）；`_ready` 播放进场，`play_hide()` 倒放。**确认角色不收回**：`_on_character_confirmed` 调 `set_interactive(false)`（`process_mode=DISABLED` 禁输入/动画）后打开 `coop_ready`（layer 101 **遮盖**选人层），此时选人层保留在底层。就绪层 ESC / 难度层 ESC → `_close_ready()`/`_close_difficulty()` 后 `set_interactive(true)` 恢复选人层；**仅房主整轮取消**（`_on_select_aborted`）才 `_close_select()` → `play_hide()` + 0.4s 延时 `queue_free()`。进关卡（场景切换）不收回选人层。
- `ui/coop_ready.tscn` + `coop_ready.gd`：半透明黑底 + 居中白字「已就绪」，`ESC` 取消；全员就绪后 `set_waiting()` 锁 ESC、文字转「等待房主选择」。静态布局在场景，脚本只切文字/锁定。
- `ui/coop_difficulty.tscn` + `coop_difficulty.gd`：房主难度面板。静态场景含 `instance=res://ui/gamemode_button.tscn` 与关卡 `VBox`；关卡列表来自 **`CoopNet.get_level_catalog()`**（基础 4 档 + `ModManager.get_content("levels")`，每项带 `scene_path`），脚本动态实例化 `ui/level_button.tscn`。
  - **激活按钮**：`level_button` 初始 `mouse_filter=IGNORE`，靠 `level_select.player_selected → open_mouse` 才可点；`_ready` 里 `_populate_levels()` 后 `player_selected.emit()` 激活全部关卡按钮。并播放 `AnimationPlayer.play("show_anim")`（0.2s 进场：`Node2D` 上下滑入 + `Control` 横向擦除 + `Motion`/`Background` 淡入）。
  - `play_hide()` 倒放；`CoopFlow._close_difficulty()` 释放前 `play_hide()` + 0.4s 延时 `queue_free()`（ESC 取消/整轮取消）。点关卡进战斗不收回（场景切换接管）；`ESC` → `cancel_select()`。

### 关卡扩展接口
- 关卡目录项 `{id, name, level, scene_path}`；`CoopNet.register_level(id, name, level, scene_path)` 供扩展，`get_level_catalog()` 读取。
- **本体 1 行改动**：`resources/level/level.gd` 增 `@export_file("*.tscn") var level_scene_path: String = ""`；Mod 新增 `Level` 资源可指定自己的关卡场景，留空回退 `main.tscn`。

### 社团扩展接口（本体单一来源）
- 本体 `script/mod_manager.gd` 新增 `const BASE_SOCIETIES: Array[Dictionary] = [{id, scene}...]`（GDD/ED/HSD/FTF/JTF/DC）+ `get_base_societies() -> [{scene, group_id}]`；`_build_reserved_ids()` 由它取 id。以后本体加社团只改这里一行。
- `scenes/main/menu_screen.tscn` 删除了 6 个内联社团节点，改由 `menu_screen.gd:_setup_societies()` 从注册表**运行时生成**（**只实例化 `PlayerData.group.has(gid)` 的已解锁社团**）；玩家在商店当场解锁新社团时，`ui/character_shop_card.gd:add_character()` 末尾 `GameEvents.emit_check_data()` → `menu_screen._sync_societies()` 检测到解锁集合变化后重建社团列（同会话内即时出现）。
- coop 选人界面同样读 `get_base_societies()`，并按解锁过滤。

### 角色卡“不实例化锁定项”
- `ui/society_card.gd:populate_player_cards()` 改为先 `PackedScene.get_state()` 读根节点导出的 `player_card.id`（兼容 `uid://` 路径），`PlayerData.character.has(id)` 不满足则**不实例化**；读不到时回退“实例化→判断→释放”。`ui/mod_society_base.gd`/`mod_society_card.gd` 同样先按 id 过滤。
- 实测 `_peek` 六个社团卡均能读出成员 id（含使用 uid 路径的 `DC_card`）。

### 自测
- `--coop-devflow`（配 `--coop-host` / `--coop-join=127.0.0.1`）：自动走 进准备房 → 房主开始选人（两端 `paused=true`）→ 双端选默认角色+就绪 → 房主走 gate 切 `main.tscn`，打印 `phase/paused/catalog/scene`。实测两端：host `phase 0→1→2→3→4`、`all players ready`、`host starts battle`，客机跟随进 `main.tscn`；选人阶段 `paused=true`、进关卡后解除；无 `SCRIPT ERROR`。
- `--coop-devflow --coop-devabort`：房主在选人阶段 `abort_select_to_lobby()`（等价按 Esc），实测两端 `phase=1(LoBBY) paused=false scene=test_room`、覆盖层关闭，无报错。
- `--coop-devflow --coop-devready`：客机自动 `toggle_local_ready()`；host 打印 `dev-ready before-all=false` → 轮询至 `after-all=true`（实测 wait≈1.0s）→ 再进选人。验证大厅准备门槛。
- 回归：`--coop-battle` 等旧 dev 参数通过 `auto_enter_lobby=false` 保持原语义。


## 房间聊天室（右侧小窗 + 回车/手机按钮）

- **通道（`net/coop_net.gd`）**：`signal chat_received(peer_id, name, text)` + `chat_log`（本房间全部消息，`CHAT_LOG_MAX=200`，单条 `CHAT_TEXT_MAX=120`，去换行/trim）。
  - `send_chat(text)`：本地先回显（立即显示自己的消息），再广播——host 经 `_fanout_chat` 逐 client `rpc_id` 且**排除发送者**（避免发送者重复收到自己的回显）；client `rpc_id(1,"_server_chat")`，host 用 `get_remote_sender_id()` 得真实 peer 再分发。显示名统一用既有 `_display_name_for(peer_id)`（自定义 ID / 回退 `PlayerN`）。
  - `_reset_run_state()` 里 `chat_log.clear()`：回菜单/重开/房主离开即清空，符合「本次房间」语义。
- **UI（`ui/coop_chat.tscn` + `coop_chat.gd`）**：`CanvasLayer`（`layer=119`，`process_mode=ALWAYS`），右侧中间 `PanelContainer`（200×160，字体 9）内含 `ScrollContainer`+`VBoxContainer` 消息列表 + 底部 `LineEdit`；消息行格式 `玩家id： 内容`，自动滚到底。
  - **Enter**（`coop_chat` 动作，`KEY_ENTER`/`KEY_KP_ENTER`）三态：窗口隐藏 → 开窗+聚焦+显示鼠标+冻结本地玩家；窗口可见且输入框**已聚焦** → 发送（`send_chat`）→ 清空并取消聚焦 → **2 秒后淡出隐藏**（无内容同样处理）；窗口可见但**未聚焦**（淡出期内）→ `_refocus()` **取消淡出并重新聚焦**，支持「输入→回车→再输入→回车」连续发送，无需等窗口消失。`ESC` 立即隐藏。
  - **隐藏收尾**还原鼠标模式与 `player_stop`（按开窗前原值，倒地时不误置 false）。
  - **手机按钮**：`TextureButton` 30×30、`texture_normal=res://ui/scoreboard_icon.png`、铺满 30×30、无边框、**半透明 `modulate.a=0.45`（恒定，无悬停反馈）**，挂到**本地玩家** `$GameUI/AmmoPosition` 右侧（战斗与准备房均显示；换人/重生后自动重挂）。
  - **点击门控（防游玩误触）**：按钮设 `mouse_filter=IGNORE`（**纯显示，不接收 GUI 鼠标事件、不吞游玩期鼠标**），点击改由 `coop_chat._input` 手动命中判定——`InputEventScreenTouch`（命中矩形）**始终可激活**（手机开聊）；`InputEventMouseButton` 左键**仅聊天窗激活时（`_is_open`）可激活**，游玩期鼠标不处理也不 consume（不挡瞄准/开火、不误触开窗）。`_last_touch_frame` 守卫忽略触摸模拟出的鼠标事件，避免双触发。
  - **音效**：开窗/重聚焦/发送均播 `SoundManager.play_sfx("ButtonSounds")`。
- **自测**：`--coop-devchat`（配 `--coop-host` / `--coop-join=127.0.0.1` + `--coop-devbattle`）双端各发一条，打印 `dev-chat id=.. log=..`。实测两端 `log=2`（含双方消息、无重复），无 `SCRIPT ERROR`。
- **备注**：聊天窗脚本的 `LineEdit` 引用名不可用 `_input`（与虚拟方法 `_input` 冲突 → Parse Error），已命名 `_input_box`。



