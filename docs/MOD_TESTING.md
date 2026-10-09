# Mod 导出 / 真机验证清单

> 目标：验证 PCK Mod 系统在**导出后**（Windows 单 exe / Android APK）的实际行为。
> 编辑器内已验证的功能不重复（见 `docs/LEARNINGS.md` 的 `[Mod]` 条目）；本文聚焦**导出后才能暴露**的问题。
> 结果填入 §8 表格；失败项回填 `docs/LEARNINGS.md`。
> 造 mod 角色的完整步骤见 `mod_sdk/CHARACTER_GUIDE.md`。
> Last updated / 最后更新: 2026-10-04

## 0. 前置准备

- [ ] **重启一次编辑器**（消除新增 autoload `ModManager` 的静态分析误报；`Identifier not found: ModManager` 属正常滞后）。
- [ ] `project.godot` 确认：
  - [ ] `[autoload]` 含 `ModManager="*res://script/mod_manager.gd"`。
  - [ ] `[editor] export/convert_text_resources_to_binary=false`。
- [ ] `export_presets.cfg` 确认：
  - [ ] `encrypt_pck=false`（保持关闭，否则 mod 无密钥无法挂载）。
  - [ ] `exclude_filter` 含 `addons/godot_ai/*, addons/.godot_ai_update/*`（勿排除 `godot-rapier2d`）。
  - [ ] **改完 export_presets.cfg 后必须重启编辑器**（否则内存旧预设回写覆盖）。
- [ ] 记录本次验证用的**本体版本**（`Game.version_number`，当前 `v0.4.1.4`）与 Godot 版本（`4.7`）。

## 1. 构建测试 Mod（SDK）

- [ ] 用**本体工程副本**作为打包工程（版本与本体对齐）。
- [ ] 运行 `.\setup_mod_project.ps1 -Project <工程副本>`：自动设 `convert_text_resources_to_binary=false` 并注入 `ModPack` 预设（`export_filter=all_resources` + `exclude_filter` 排除本体目录 → pck 只含 `res://mods/**`；双纹理 `s3tc_bptc`/`etc2_astc`；`encrypt_pck=false`）。
  - [ ] 校验：`export_presets.cfg` 出现 `name="ModPack"`；`project.godot` 有 `[editor] export/convert_text_resources_to_binary=false`。
- [ ] 放入内容：`<工程副本>/mods/<id>/`（`mod.json` + `defs/**`；可参考 `mod_sdk/example_mod/mods/example/`）。
- [ ] 运行 `.\build_mod.ps1 -Godot <godot> -Project <工程副本> -ModId <id>` 生成 `build/<id>.zip`。
- [ ] **最小 mod**：至少 1 个角色（`defs/characters/`）+ 1 个自带**非压缩纹理**（验证 `.ctex` 双编码）。
- [ ] **pck 内容**：确认 `<id>.pck` 只含 `mods/**`（无 `script/`、`scenes/` 等本体目录）——`ModPack` 预设是否生效的关键。

## 2. 桌面单 exe（Windows）

- [ ] 导出 `binary_format/embed_pck=true` 的单 exe。
- [ ] 空 `user://mods/` 启动：无报错、无 mod。
- [ ] 把 `<id>.zip` 通过游戏内 option 面板「MOD」页签导入 → 提示「重启生效」→ 重启。
  - [ ] `ModManager.list_mods()` 显示该 mod 且 `mounted=true`、`error=""`（可在「MOD」页签查看；有 `icon.png` 时显示图标）。
  - [ ] 该页签内拖动任一行、或选中后用上下箭头调整顺序 → 重启后 `_resolve_order` 按新顺序（`user://mods/mods_order.json`）。
- [ ] 重启后：选人界面出现 **MOD 社团** → 选中 mod 角色 → 选关 → 进战斗，**立绘/纹理正常**。
- [ ] **便携目录**：把 `<id>.pck` + `mod.json` 放到 **exe 同目录 `mods/<id>/`**，启动后同样加载。
- [ ] **优先级**：同 id 同时存在于 `user://mods/` 与 exe 同目录时，`user://` 胜（看日志告警）。
- [ ] **覆盖场景**：用 `ModPackReplace` 预设构建（`setup_mod_project.ps1 -Replace` + `build_mod.ps1 -Preset ModPackReplace`，`mod.json` 置 `replace_files=true`）覆盖 `res://scenes/main/main.tscn` 后，进入战斗用的是 mod 版本。

## 3. Android 真机

- [ ] 导出 APK（arm64）并安装。
- [ ] 游戏内 **MOD** 面板 → `导入 zip` → 弹出**系统文件选择器**（SAF）：
  - [ ] 能从「下载/文档」选到 `.zip`（**若选择器不可用** → 记录为阻塞项，评估 SAF 插件）。
  - [ ] 导入成功 → 重启。
- [ ] 重启后 MOD 社团出现、角色可选、进战斗。
- [ ] **纹理正常**（ETC2/ASTC；无花屏/串图）。
- [ ] 自定义 shader 的 mod：在 Android 上**不崩溃**（shader_baker 不含 mod shader，注意运行时编译）。
- [ ] 无需 INTERNET、无需存储权限（确认未触发权限申请）。

## 4. 跨平台通用性

- [ ] **同一个 `<id>.zip`** 在 Windows 与 Android 都能加载并渲染正常。
- [ ] 若失败：记录是纹理格式还是 pck/引擎问题。

## 5. 功能回归（各内容类型，导出后）

- [ ] **角色**：MOD 社团选中 → 战斗场景为 mod 场景；`branches` 切换生效。
  - [ ] 战斗场景根 `player_card` 缺失/错 id → 注册时告警；进战斗后 HUD/暂停/结算显示与 `PlayerData.player_select`（存档/记分板键）均为注册 id（`ModManager` 已强制对齐）；`ps_card` 缺失仅告警。
- [ ] **社团卡**：mod 自带 `defs/societies/*.tscn`（继承 `mod_society_base.gd`）→ 其 `members` 角色进自带社团卡；未带社团的 mod 角色进通用「MOD」社团卡；`group_id` 默认解锁（并入 `PlayerData.group`）；两张卡成员填充正确。
- [ ] **通用卡自动续卡**：未认领角色 >4 时左侧出现 `MOD` / `MOD 2` / … 多张，各含 ≤4 个角色；点第 2 张能选到第 5 个起的角色；商店当场解锁角色后新增页/成员即时出现。
- [ ] **支援**：`defs/supports/` 的支援出现在支援商店/选择界面；EX/被动可运行。
- [ ] **道具**：`defs/upgrades/` + 同目录 `<id>.tscn` 的道具进入三选一池；拾取后效果生效；记分板装备列表能显示（`score_card`）。
- [ ] **敌人**：`defs/enemies/`（`id == body.pool_id`）在指定 `enemy_group` 出现；生成上限正常。
- [ ] **游戏模式**：`defs/game_modes/` 出现在模式选择；选中后 `PlayerData.game_mode` 含该 id；entry 脚本应用行为。
- [ ] **关卡**：`defs/levels/` 出现在选关列表；点击进入 `main.tscn` 且数值（hp/damage/reward）生效。
- [ ] **entry 脚本**：启动时实例化；`ModAPI` 可用；`GameEvents` 挂钩生效。

## 6. 兼容 / 容错 / 安全

- [ ] **pck 引擎版本不匹配** → 挂载失败被记 `error`，不崩、不影响其它 mod。
- [ ] **缺 pck / 坏 pck** → `error` 提示（如 `pck 不存在`），不崩。
- [ ] **依赖缺失 / 依赖环 / conflicts** → 相关 mod 被停用并报 error，其余正常启动。
- [ ] **坏 manifest / 非法 id / 路径穿越 zip** → 拒绝并提示。
- [ ] **`pool_id` 不一致的敌人** → 跳过 + 告警，不崩。
- [ ] **卸载 mod 后旧存档**（含其角色/支援 id）→ 不崩（失效 id 容错）。
- [ ] **`api_version` 过高** → entry 被跳过。

## 7. 深度修改（可选）

- [ ] `replace_files=true` + `ModPackReplace` 预设覆盖一个**后加载**场景（如入口 `main.tscn`）；autoload 脚本与已 `preload` 缓存的资源**预期覆盖不生效**（本工具不支持 autoload 覆盖）。
- [ ] entry 脚本订阅 `first_round_add`/`round_start`/`change_scene` 接管流程。
- [ ] 记录「可覆盖 / 不可覆盖」边界（autoload 脚本覆盖需 `ModManager` 置顶 + 重启编辑器）。

## 8. 结果记录表

| # | 项 | 平台 | 预期 | 实际 | 状态 | 证据/日志 |
|---|---|---|---|---|---|---|
| 1 | 桌面导入 zip | Win | 成功+重启生效 | | ☐ | |
| 2 | 桌面 MOD 社团选人 | Win | 可进战斗 | | ☐ | |
| 3 | exe 同目录 mods | Win | 加载成功 | | ☐ | |
| 4 | user:// 优先 | Win | 后者胜+告警 | | ☐ | |
| 5 | 覆盖 main.tscn | Win | 用 mod 版本 | | ☐ | |
| 6 | Android SAF 导入 | And | 能选 zip | | ☐ | |
| 7 | Android 纹理 | And | 正常 | | ☐ | |
| 8 | 同一 pck 双端 | 双端 | 通用 | | ☐ | |
| 9 | 支援/道具/敌人/模式/关卡 | 双端 | 生效 | | ☐ | |
| 10 | entry + ModAPI | 双端 | 生效 | | ☐ | |
| 11 | 容错（版本/依赖/坏包） | 双端 | 停用不崩 | | ☐ | |
| 12 | 存档卸载容错 | 双端 | 不崩 | | ☐ | |
| 13 | 角色 player_card 对齐 | 双端 | 告警 + 进战斗 id 一致 | | ☐ | |

## 9. 已知风险点（重点盯）

- `ResourceLoader.list_directory` 对**运行时挂载 pck** 是否返回原始文件名（不成立则需改用构建期 `content_index.json`）。
- `convert_text_resources_to_binary=false` 是否让运行时 `load()` 读到 mod/本体 `.tres`。
- 通用 preset 的 S3TC/BPTC + ETC2/ASTC 是否真能**一份 pck 双端可用**。
- Android **原生文件选择器**（SAF）可用性（Godot 4.7）。
- Android `shader_baker` 与 mod 自定义 shader。
- 单 exe 内嵌 pck 下 `load_resource_pack` 叠加。
- pck 必须与引擎版本 `4.7` 匹配。
