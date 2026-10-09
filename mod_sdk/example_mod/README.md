# Example Mod / 示例 mod

最小可安装角色 mod 源。`example/` 就是工程 `mods/<id>/` 的内容：

```
example/
  mod.json
  icon.png
  defs/characters/example_hero.tres
  patches/example.json
```

## 用法

1. 准备一份**本体工程副本**（版本与本体对齐）。
2. 运行 `mod_sdk/setup_mod_project.ps1 -Project <副本>` 注入 `ModPack` 预设。
3. 把本目录的 `example/` 拷到 `<副本>/mods/example/`。
4. 运行 `mod_sdk/build_mod.ps1 -Godot <godot> -Project <副本> -ModId example` → 生成 `build/example.zip`。
5. 游戏内 **MOD** 面板导入该 zip，重启。

## 说明

- `mod.json.id = "example"` → 角色 id 必须带前缀：`example_hero`。
- 本示例的 `scene_path` 复用本体 `res://scenes/player/momoi/momoi.tscn`，故战斗场景根 `player_card`（momoi）与注册 id（example_hero）不一致 → 注册时会**告警**，进战斗后由 `ModManager` 对齐为 `example_hero`（属预期，用于演示容错）。
- 若 mod 自带贴图：确保 mod 工程 `import_etc2_astc=true`，且 `ModPack` 预设双纹理（`setup_mod_project.ps1` 已含）。
- `patches/example.json` 演示补丁（`add` / `inherit`）。
