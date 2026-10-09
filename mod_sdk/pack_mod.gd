extends SceneTree

## mod 打包器（开发用，不依赖导出预设）。
## 用法：
##   godot --headless --path <本体工程> --script res://tool/pack_mod.gd -- \
##     --mod-source=<mod 源目录> --out=<输出 pck> --mod-id=<id>
## 将源目录下所有文件按 res://mods/<id>/<相对路径> 打进 pck。

func _initialize() -> void:
	var src := ""
	var out := ""
	var id := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mod-source="):
			src = a.substr("--mod-source=".length())
		elif a.begins_with("--out="):
			out = a.substr("--out=".length())
		elif a.begins_with("--mod-id="):
			id = a.substr("--mod-id=".length())
	if src == "" or out == "" or id == "":
		push_error("usage: -- --mod-source=<dir> --out=<pck> --mod-id=<id>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var pck := PCKPacker.new()
	var err := pck.pck_start(out)
	if err != OK:
		push_error("pck_start failed: %s" % err)
		quit(1)
		return
	var count := _add_dir(pck, src, "res://mods/%s" % id, "")
	err = pck.flush()
	if err != OK:
		push_error("flush failed: %s" % err)
		quit(1)
		return
	print("PACK_MOD: %d files -> %s" % [count, out])
	quit(0)


func _add_dir(pck: PCKPacker, root_abs: String, res_prefix: String, rel: String) -> int:
	var dir_abs := root_abs if rel == "" else root_abs.path_join(rel)
	var d := DirAccess.open(dir_abs)
	if d == null:
		return 0
	var n := 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var child_rel := name if rel == "" else rel.path_join(name)
		if d.current_is_dir():
			n += _add_dir(pck, root_abs, res_prefix, child_rel)
		else:
			var target := res_prefix.path_join(child_rel.replace("\\", "/"))
			var source := root_abs.path_join(child_rel)
			var e := pck.add_file(target, source)
			if e != OK:
				push_error("add_file failed (%s): %s" % [e, source])
			else:
				n += 1
		name = d.get_next()
	d.list_dir_end()
	return n
