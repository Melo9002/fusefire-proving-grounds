extends SceneTree
const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")
func _initialize() -> void:
	var records := {}
	for id in Catalog.PROFILES:
		var instance = load(Catalog.path_for(id)).instantiate()
		var bounds := Placement.mesh_bounds(instance)
		records[id] = {"position": [bounds.position.x, bounds.position.y, bounds.position.z], "size": [bounds.size.x, bounds.size.y, bounds.size.z]}
		instance.free()
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Supply measurement JSON output path after --; existing file is overwritten.")
		quit(1)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(records, "\t") + "\n")
	print("Measured %d catalog assets" % records.size())
	quit()
