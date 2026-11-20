extends SceneTree
## Loads every project GDScript so Godot prints its compile warnings (file:line) to the console.
## Usage: godot_console --headless --path . --script res://tools/scan_script_warnings.gd


func _initialize() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	var count := 0
	for path in files:
		var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REPLACE) as GDScript
		if script != null:
			script.reload()
		count += 1
	print("SCANNED %d scripts" % count)
	quit(0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_collect(dir_path.path_join(sub), out)
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append(dir_path.path_join(file_name))
