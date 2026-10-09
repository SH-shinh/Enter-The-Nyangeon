# 制作一个 Mod 角色 — 完整指南

> 面向 mod 制作者。目标：从零做出一个可在游戏内选中、进战斗、正常显示的 mod 角色。
> 关键原则：**能引用本体就引用本体；改行为用 mod 副本或 entry 脚本，不要指望覆盖本体。**
> 术语与代码符号（`PlayerCard`、`player.gd` 等）保持原文。

## 0. 前置条件

- **Godot 4.7**（必须与本体引擎版本一致；版本不符 pck 无法挂载）。
- 一份**本体工程副本**（版本与本体对齐）。mod 的打包工程就是它——因为 mod 会引用本体 `res://script/...`、`res://sprites/...`。
- 仓库内的 `mod_sdk/`（含 `setup_mod_project.ps1`、`build_mod.ps1`、示例）。

## 1. 一个角色由什么组成

| 组成 | 载体 | 必需 | 说明 |
|---|---|---|---|
| 战斗场景 | `.tscn`（根 `CharacterBody2D` + `res://script/player.gd`） | ✅ | 所有角色共用 `Player` 脚本 |
| 角色数据 `PlayerCard` | `defs/characters/<id>.tres` | ✅ | id/名字/立绘/场景路径等 |
| 立绘 | PNG（`sprite_path`） | ✅ | 选人界面 + HUD 图标 |
| PS 卡 `PSCard` | `.tres`（`weapon_icon`） | 建议 | 商店读 `weapon_icon`，缺失会崩 |
| 换装/分支 | `PlayerCard.branches` | 可选 | 同角色多形态 |
| 自定义选人卡 | `.tscn`（`PlayerCard.card_scene` 或 manifest `characters[].card_scene`） | 可选 | 缺省用通用卡 |
| 社团卡 | `defs/societies/<name>.tscn` | 可选 | 缺省进内置「MOD」社团卡 |
| 商店卡 | `defs/shop_characters/<id>.tres`（`CharacterCard`） | `unlock_mode=shop` 时必需 | 见 §3.13 |
| 本地化 / 语音 | CSV / `sounds/voice/` | 可选 / 受限 | 见 §4.11 / §4.12 |

## 2. 目录结构

```
mods/<mod_id>/
  mod.json
  icon.png                          # 可选，zip 根级图标
  defs/characters/<char_id>.tres    # PlayerCard（char_id 必带 <mod_id>_ 前缀）
  scenes/<name>.tscn                # 战斗场景
  resources/ps/<char_id>_ps.tres    # 可选 PSCard
  sprites/...                       # 立绘/精灵（或复用本体）
  defs/societies/<name>.tscn        # 可选社团卡
  defs/shop_characters/<char_id>.tres # 可选，unlock_mode=shop 时必需（CharacterCard）
```

> 场景/资源放 `mods/<mod_id>/` 下任意位置，用 `scene_path` / `sprite_path` 指过去即可。打包时 `ModPack` 预设会把 `res://mods/**` 收进 pck。

## 3. 分步制作

### 3.1 准备工作区 + 注入 ModPack 预设

1. 复制本体工程到工作目录（**编辑器关闭**——编辑器打开时会回写覆盖 `export_presets.cfg`）。
2. 运行：

```powershell
.\setup_mod_project.ps1 -Project "C:\path\to\project_copy"
```

自动完成：

- `project.godot`：设置 `[editor] export/convert_text_resources_to_binary=false`（否则运行时读不到 mod 的 `.tres`）。
- `export_presets.cfg`：注入 `ModPack` 预设（`export_filter=all_resources` + `exclude_filter` 排除本体目录 → **pck 只含 `res://mods/**`**；双纹理 `s3tc_bptc`/`etc2_astc`；`encrypt_pck=false`）。

### 3.2 `mod.json`

放 `mods/<mod_id>/mod.json`。

| 字段 | 必需 | 说明 |
|---|---|---|
| `id` | ✅ | `^[a-z0-9_]+$`；所有角色 id 以 `<id>_` 开头 |
| `name` / `version` / `author` | | 显示用 |
| `game_version` | | 声明**最低支持**的本体版本；本体低于它才告警（忽略 `-test` 等后缀） |
| `load_order` | | 越小越先；相同按 id 字母序 |
| `dependencies` / `conflicts` | | 依赖/互斥（缺失/成环/冲突 → 停用） |
| `overrides` | | 显式允许覆盖同名 id |
| `replace_files` | | 覆盖本体 `res://`（需 `ModPackReplace` 预设，见 §9 / `README.md` §13） |
| `replace_paths` | | 覆盖构建用：要覆盖的本体 `res://` 文件列表（见 §9） |
| `entry` | | 启动时实例化的 Node 脚本（深度修改，可用 `ModAPI`） |
| `characters` | | 显式角色声明（见 §4.8，可带 `card_scene`） |
| `societies` | | 显式社团卡场景列表 |
| `pck` | | 默认 `<id>.pck` |

示例：

```json
{
  "id": "mychar", "name": "My Char Mod", "version": "1.0.0",
  "author": "you", "api_version": 1, "game_version": "v0.4.1.4",
  "load_order": 0, "pck": "mychar.pck"
}
```

### 3.3 战斗场景（**最省事：复制现有角色场景**）

1. 复制 `scenes/player/momoi/momoi.tscn` → `mods/<mod_id>/scenes/<name>.tscn`。
2. 根节点：`CharacterBody2D`（组 `Player`），脚本 `res://script/player.gd`（`class_name Player`）。

**根导出字段**（`script/player.gd:12-21`）：

- `player_card`：**必须**指向你的 `defs/characters/<char_id>.tres`。
- `ps_card`：建议指向你的 `PSCard`。
- `stats`：指向子节点 `Stats`（`script/Stats.gd`）。
- `player_color`、`long_hair`、`mortar`、`hat_position`、`halo_root_position`、`gun_root`、`base_pitch_scale`：按需。

**固定节点名依赖**（`script/player.gd:53-81`，缺一个就报错）：见 §4.3.1。

> ⚠️ 这些是硬依赖，**不要从零搭**——复制现有角色场景再改最稳。

- 战斗内动画：`%AnimatedSprite2D` 的 `SpriteFrames`（idle/run/jump/fly/fall）。
- 武器：`%Gun`（`PlayerGun`）——复制现有角色并把武器场景换成你的（或复用本体的）。
- PS 技能：场景里的 `<Char>PS` 节点（自定义脚本，如 `MomoiPS.gd`）。
- HUD：`GameUI` 节点为 `ui/game_ui.tscn` 实例（读 `player.player_card`）。

#### 4.3.1 战斗场景骨架（节点清单）

以「根 `CharacterBody2D`（`res://script/player.gd`，组 `Player`）」为基准：

| 节点（相对根） | 类型 / 脚本 | 用途 | `player.gd` 引用 |
|---|---|---|---|
| `Stats` | `script/Stats.gd` | 战斗属性（基准值在此） | 根导出 `stats` |
| `StateMachine` | `StateMachine.gd` | 状态机驱动 | `$StateMachine` |
| `Graphics/AnimatedSprite2D` | `AnimatedSprite2D` | 角色逐帧动画（`SpriteFrames`） | `$%AnimatedSprite2D` |
| `Graphics/Halo` | `Sprite2D` | 光环/头饰 | `$%Halo` |
| `Graphics/HaloRoot` | `Node2D` | 光环挂点 | `$%HaloRoot` |
| `Graphics/Gun` | `PlayerGun` 实例 | 武器/开火 | `$%Gun` |
| `HurtBox` | `script/hurt_box.gd`（`is_player=true`） | 受击区 | `$HurtBox` |
| `HurtBox/HurtboxShape` | `CollisionShape2D` | 受击形状 | `$HurtBox/HurtboxShape` |
| `CollisionShape2D` | `CollisionShape2D` | 本体物理碰撞 | `$CollisionShape2D` |
| `PickBox/CollisionShape2D` | `Area2D` + 形状 | 拾取范围 | `$PickBox/CollisionShape2D` |
| `Kick` | 近战实例 | 近战（节点名必须 `Kick`） | `$Kick` |
| `HealthComponent` | `script/player_health_component.gd` | 玩家血量结算 | `$HealthComponent` |
| `PlayerBuffManager` | 玩家 buff 管理器实例 | buff 引擎 | `$PlayerBuffManager` |
| `<Char>PS` | 自定义 PS 脚本 | 角色技能 | 场景约定 |
| `GameUI` | `ui/game_ui.tscn` 实例 | HUD | `$GameUI` |
| `Camera2D` | 相机实例 | 跟随 | `$Camera2D` |
| `CanvasLayer/PauseScreen` | `pause_screen` 实例 | 暂停菜单 | `$CanvasLayer/PauseScreen` |
| `JumpTimer` / `FlyTimer` / `JumpCDTimer` | `Timer` | 跳跃/飞行/冷却 | 同名 |
| `RunSoundsTimer` / `InvincibleFrame` | `Timer` | 跑步音/无敌帧 | 同名 |
| `JumpSounds` / `RunSounds` / `OnHitSounds` / `CoinSounds` | `AudioStreamPlayer2D` | 音效 | 同名 |
| `AnimationPlayer` / `AnimationPlayer2` | `AnimationPlayer` | 无敌帧 / 近战动画 | 同名 |
| `GPUParticles2D` | `GPUParticles2D` | 烟尘特效 | `$GPUParticles2D` |
| `JumpCDBar` | `TextureProgressBar` | 跳跃冷却条 | `$JumpCDBar` |

> 建议整段节点结构直接从本体角色场景复制，逐节点替换贴图/字段，不要手工从零搭。

### 3.4 `PlayerCard` .tres

放 `defs/characters/<char_id>.tres`，脚本 `resources/player/player.gd`（`class_name PlayerCard`）。

| 字段 | 说明 |
|---|---|
| `id` | **必带 `<mod_id>_` 前缀**（如 `mychar_hero`） |
| `name` | 显示名（**直接字符串**，可任意语言，不走翻译） |
| `weapon` | 武器名（直接字符串） |
| `sprite_path` | 立绘 PNG 路径（`@export_file("*.png")`） |
| `halo` | 光环/头饰贴图（可选） |
| `color` | 主题色（HUD/名字颜色） |
| `description` | 描述（当前选人界面不显示） |
| `voice_name` | 语音目录名（可选） |
| `scene_path` | **战斗场景路径**（§3.3） |
| `card_scene` | 自定义选人卡场景路径（可选；缺省用通用卡，等价于 manifest 的 `characters[].card_scene`） |
| `unlock_mode` | `auto`（默认，进游戏自动解锁）/ `shop`（需在商店购买，见 §3.13） |
| `branches` | 分支形态（§4.7） |

### 3.5 立绘 / 精灵

- `sprite_path`：选人/HUD 用的立绘 PNG（按需加载，`LazyTexture`）。
- 贴图**导入设置与本体一致**：mod 工程 `import_etc2_astc=true`（双编码，桌面+Android 通用）。`ModPack` 预设已含双纹理。
- 战斗内逐帧动画在场景的 `AnimatedSprite2D` 里（`SpriteFrames`）。

### 3.6 PS 卡 `PSCard`

- 脚本 `resources/player/PS/ps_card.gd`：`weapon_icon: Texture` + `t_level: Array[String]`。
  - `t_level` **目前未被读取**；PS 描述文本走本地化键 `<char_id>_ps_0..3`（见 §4.11）。
- 赋给场景根 `ps_card`；PS 商店读 `player.ps_card.weapon_icon`（缺失会崩 → 尽量自备）。
- 战斗内 PS 逻辑 = 场景 `<Char>PS` 脚本自行实现（可复制现有角色的 PS 脚本改）。

### 3.7 换装 / 分支（`branches`）

- `PlayerCard.branches: Array[PlayerCard]`：每个分支是子 `PlayerCard`（`id` 带前缀、各自 `scene_path`）。
- 选人卡会有「分支」按钮切换（通用 `ui/mod_player_card.tscn` 已支持）。
- 切换后进入的是分支的 `scene_path`。

### 3.8 自定义选人卡（可选）

- 缺省用通用卡 `ui/mod_player_card.tscn`（显示立绘/名字/武器 + 分支）。
- 想用自己的选人卡，两种等价写法：
  - 在角色的 `PlayerCard` 资源里设 `card_scene`（推荐，`defs/characters/` 扫描也能生效）；或
  - 在 `mod.json` 显式声明角色：

```json
{
  "id": "mychar",
  "characters": [
    { "card": "res://mods/mychar/defs/characters/mychar_hero.tres",
      "card_scene": "res://mods/mychar/cards/mychar_hero_card.tscn" }
  ]
}
```

> `manifest.characters` 是**显式声明的补充**而非互斥开关：它只跳过 `characters` 这一种 kind 的目录扫描，其余 kind（`upgrades`/`enemies`/…）照常扫描。显式声明与 `defs/characters/` 扫描命中同一 id 时按「先注册者」保留（同 mod 重复静默跳过）。

### 3.9 社团卡（可选）

- 放 `defs/societies/<name>.tscn`，根**必须继承 `res://ui/mod_society_base.gd`**，场景内设置：
  - `group_id`：带 `<mod_id>_` 前缀、全局唯一（默认解锁）。
  - `members`：`Array[String]` 本社团角色 id。
  - 含一个 `AnimationPlayer` 节点（即使为空；父类会取 `$AnimationPlayer`）。
- 不带 → 角色进内置「MOD」通用社团卡（只收未认领角色；每 4 个一张、超出自动续卡 `MOD` / `MOD 2` / …）。
- 去重规则：某 mod 提供 ≥1 社团卡 → 其全部角色进自带卡，不进通用卡。

最小示例（`defs/societies/my_team.tscn`）：

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://ui/mod_society_base.gd" id="1"]

[node name="MyTeam" type="PanelContainer"]
custom_minimum_size = Vector2(93, 28)
mouse_filter = 0
script = ExtResource("1")
group_id = "mychar_team"
members = Array[String](["mychar_hero"])

[node name="AnimationPlayer" type="AnimationPlayer" parent="."]
```

### 3.10 引用本体资源 / 脚本

可直接引用，**无需复制**：

- **脚本继承**：`extends "res://script/player.gd"`，或按 `class_name`（`extends Player` / `EquipItem` / `SummonedFollower` / `Enemy`…）。
- **静态助手**：`Faction` / `GameTags` / `DamageData` / `HealData` / `DamageRouter` / `Targeting` / `LazyTexture` 等。
- **autoload**：`GameEvents` / `PlayerData` / `PoolManager` / `SupportData` / `ModManager` / `ModAPI`。
- **资源/场景/贴图/音效**：`ext_resource path="res://..."` 或 `preload("res://...")`。

原理：本体是 pack 0（`res://` 全量）；mod pck 以 `replace_files=false` 叠加 → 本体资源由本体提供，mod pck 里不含本体文件（`ModPack` 的 `exclude_filter` 排除了本体目录）。要**覆盖本体文件**见 `README.md` §13（`ModPackReplace` 预设 + `replace_files=true`/`replace_paths`）。

**注意**：

- 优先用**路径**引用而非仅 `uid://`（更稳）。
- 引用本体 = 绑定本体版本；本体改名/改接口会让 mod 失效（`game_version` 声明最低支持版本，本体低于它才告警）。

示例：

```gdscript
extends "res://script/player.gd"

func _ready() -> void:
    super._ready()
    GameEvents.first_round_add.connect(_on_first_round)

func _on_first_round() -> void:
    var ft = preload("res://ui/floating_text.tscn").instantiate()
    add_child(ft)
```

### 3.11 本地化（PS 文本）

- 角色 `name` / `weapon` 是直接字符串，**不走翻译**。
- PS 描述键为 `<char_id>_ps_0..3`（见 `ETN_player_localization.csv` 的模式，如 `momoi_ps_0..3`）。
- mod 自带翻译：在 `mod.json.entry` 脚本里用 `ModAPI.add_translation(locale, key, value)` 注入（每个 locale 各调一次）。未翻译的键会**回退到 `PlayerCard.description`**（不再显示原始键）。
- 新增/覆盖语言（选择器中的语言项与字体）：`ModAPI.register_language(locale, display_name, opts)`，详见 `README.md` §15。
- 批量翻译（CSV→`.translation`，推荐）：`ModAPI.register_translations_from_dir("res://mods/<id>/i18n")`，详见 `README.md` §15.1。

### 3.12 语音（可选）

- `PlayerCard.voice_name` → `SoundManager.play_voice(voice_name, type)`（读 `sounds/voice/<voice_name>/`）。
- 缺失时 `play_voice` **静默返回、不崩**（`scenes/manager/SoundManager.gd:81-85`）。

### 3.13 解锁方式（`auto` / `shop`）

`PlayerCard.unlock_mode`（枚举）决定角色怎么获得：

- `auto`（默认）：进游戏即自动解锁，出现在社团/通用「MOD」卡里，**不进商店**。
- `shop`：不自动解锁，需在商店购买。此时必须额外提供一份**商店卡**：
  - 放 `defs/shop_characters/<id>.tres`，类型 `CharacterCard`（脚本 `resources/shop/character/character_card.gd`），**`id` 与角色的 `PlayerCard.id` 相同**。
  - `CharacterCard` 字段：`cost`、`name_1`/`name_2`、`weapon_name`/`weapon_type_name`/`weapon_icon`、`school_name`/`school_icon`、`character_sprite_path`、`group`（通常填该 mod 社团的 `group_id`）。
  - 购买后由本体 `ui/character_shop_card.gd` 自动把 id/group 写入 `PlayerData` 并刷新。
  - 若声明 `shop` 却没有对应 `shop_characters` 条目，注册时会**告警**且该角色永远无法获得。
- **分支各自声明**：每个 `branches` 里的子 `PlayerCard` 也各有 `unlock_mode`；`shop` 主卡的分支若为 `auto` 会被免费解锁，注册时告警（应一并设为 `shop`）。

## 4. 打包

```powershell
# 1) 注入预设（一次即可）
.\setup_mod_project.ps1 -Project "C:\path\to\project_copy"
# 2) 放内容到 <副本>/mods/<mod_id>/
# 3) 打包
.\build_mod.ps1 -Godot "godot" -Project "C:\path\to\project_copy" -ModId "mychar"
```

产出 `build/mychar.zip`（含 `mod.json` + `mychar.pck` + 可选 `icon.png`）。

## 5. 安装与测试

1. 运行游戏 → 主菜单左下角 **MOD** → `导入 zip` → 选 `mychar.zip` → **重启游戏**。
2. 选人界面出现「MOD」社团卡（或你的自带社团卡）→ 选中角色 → 选关 → 进战斗。
3. 手动安装：`<id>.pck` + `mod.json` 放 `user://mods/<id>/`
   （Windows：`%APPDATA%\Godot\app_userdata\Enter The Nyangeon\mods\`）。

## 6. 校验规则与常见错误

| 现象 | 原因 | 处理 |
|---|---|---|
| 角色不出现 | id 缺 `<mod_id>_` 前缀 / 与本体冲突 | 加前缀；覆盖本体需写进 `overrides` |
| 角色不出现 | 缺 `scene_path` | 补 `scene_path`（缺失会被**跳过**） |
| 注册日志告警 | 场景根 `player_card` 为空或 id 不一致 | 让它指向你的 `defs/characters/<id>.tres`；运行期会自动对齐，但应修正 |
| PS 商店崩 | 场景根 `ps_card` 为空 | 自备 `ps_card` |
| `player.gd` 报节点缺失 | 少了固定节点名 | 从现有角色场景复制 |
| 纹理花屏/缺失 | 纹理未双编码 | mod 工程 `import_etc2_astc=true` + `ModPack` 预设 |
| 编辑器报 `Identifier not found: ModManager` | 新增 autoload 的静态分析滞后 | 重启编辑器（运行/导出正常） |

## 7. 最小可行示例

见 `mod_sdk/example_mod/mods/example/`：

```
example/
  mod.json
  icon.png
  defs/characters/example_hero.tres
  patches/example.json
```

- `mod.json.id="example"` → 角色 id `example_hero`。
- 该示例 `scene_path` 复用本体 `momoi.tscn`，故会触发 `player_card` 对齐告警（演示容错），换成你自己的场景即无告警。

## 8. 限制与注意事项（当前版本）

- **覆盖本体文件**（改写 `res://script/...`、`res://scenes/main/main.tscn`）：用 `ModPackReplace` 预设 + `mod.json` 的 `replace_files=true`（可选 `replace_paths` 列本体文件），见 `README.md` §13；默认 `ModPack` 预设排除本体目录，做不到。
- **autoload 脚本不可覆盖**（启动即加载）。
- **mod 脚本的 `class_name` 不全局注册**（导出后引擎不扫描挂载 pck）→ mod 间用路径或 `ModAPI` 引用，且避免与本体 `class_name` 撞名。
- **翻译/语言已接入**：`ModAPI.add_translation` 逐条注入、`ModAPI.register_language` 注册新语言（见 §3.11 与 `README.md` §15）；仍无 CSV/`.translation` 自动扫描（需自行 `load` 后注册）。
- **引用本体 = 绑定本体版本**；`game_version` 声明最低支持版本，本体低于它才告警。
- 启用/禁用需**重启**（pck 挂载后不可卸载）。

## 9. 相关文档

- `mod_sdk/README.md`：包契约、manifest 全字段、补丁、社团、entry/ModAPI。
- `docs/MOD_TESTING.md`：导出/真机验证清单。
- `docs/CONVENTIONS.md` §10、`docs/ARCHITECTURE.md` §1.11、`docs/SYSTEMS.md` §11：实现内幕。
