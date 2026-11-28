extends SceneTree
## Compiles one Interaction Range parcel scene directly with the existing scene compiler (no plot, no resolver) and prints which solids it found and how the cells came out.
const Scene := preload("res://art/environments/authored/parcels/interaction_range_closed.tscn")


func _initialize() -> void:
	var root := Scene.instantiate()
	var solids := 0
	for node in root.find_children("*", "Node3D", true, false):
		if AuthoredSceneMapCompiler.is_active_solid(node):
			solids += 1
	print("active solids in the scene: ", solids)
	var data := TacticalMapBuilder.generate(16, 32, 1.0, 1)
	data.surface_placement_enabled = true
	AuthoredSceneMapCompiler.compile(root, data, 1.0, Transform3D(Basis.IDENTITY, Vector3(-8.0 + 0.5 * 0, 0, -16.0 + 0.5 * 0)))
	print("errors: ", data.generation_errors)
	for z in range(0, 32):
		var row := ""
		for x in range(0, 16):
			var cell := data.get_cell(Vector3i(x, 0, z))
			row += "?" if cell == null else ("." if cell.walkable and cell.can_stop else ("w" if cell.walkable else "#"))
		print("  z=%2d %s" % [z, row])
	root.free()
	quit()
