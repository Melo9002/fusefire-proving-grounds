extends SceneTree
## Explicit graphics-only strategy-A evidence. Never grants content approval.
class Editor extends "res://tools/map_editor.gd":
	func _ready(): pass
func _initialize(): run.call_deferred()
func tile(parent: Node3D, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.85,0.04,0.85)
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	if DisplayServer.get_name() == "headless": print("SKIP: graphics required"); quit(); return
	root.size = Vector2i(1440,1000)
	var editor := Editor.new()
	editor.layout_preset = &"fixed_population"
	root.add_child(editor)
	editor._build_ui()
	editor.population_save_directory = "res://artifacts/t08-ui-save-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(editor.population_save_directory)
	for population_seed in [17,42]:
		editor.generation_seed = population_seed
		var started := Time.get_ticks_msec()
		editor._rebuild()
		print("Population editor seed ",population_seed," ms=",Time.get_ticks_msec()-started)
		if editor.displayed_data == null or not editor.displayed_data.battlefield_layout_document.provenance.has("population"): push_error("Population UI build failed"); editor.free(); quit(1); return
		var saved_signature := TacticalPopulationPass.canonical(editor.displayed_data.battlefield_layout_document.to_dictionary())
		editor._save_population()
		editor._reload_population()
		if TacticalPopulationPass.canonical(editor.displayed_data.battlefield_layout_document.to_dictionary()) != saved_signature:
			push_error("Editor save/reload changed accepted population"); editor.free(); quit(1); return
		print("PASS: editor save/reload retains exact population for seed ",population_seed)
		editor._frame_camera()
		editor._set_camera_view(0.65,0.8)
		editor.content.get_node("TacticalGrid").hide()
		editor.find_child("MapEditorUI", true, false).hide()
		await capture("res://artifacts/t08-%d-clean.png" % population_seed)
		var overlay := Node3D.new()
		editor.content.add_child(overlay)
		var data: MapData = editor.displayed_data
		var offset := Vector3(-29.5,0.16,-24.5)
		var info: Dictionary = data.battlefield_layout_document.provenance.population
		for route in info.rules.routes:
			for at in route: tile(overlay,offset+Vector3(at[0],at[1],at[2]),Color.GREEN)
		for region in info.rules.regions:
			var r := Rect2i(region.bounds[0],region.bounds[1],region.bounds[2],region.bounds[3])
			for x in range(r.position.x,r.end.x):
				for z in range(r.position.y,r.end.y):
					if x in [r.position.x,r.end.x-1] or z in [r.position.y,r.end.y-1]: tile(overlay,offset+Vector3(x,0,z),Color.CYAN)
		for zone in data.zones.values():
			for at in zone.cells: tile(overlay,offset+Vector3(at)+Vector3.UP*0.04,Color.MAGENTA)
		for at in data.cells:
			var cell: MapCellData = data.cells[at]
			if cell.cover_type != MapCellData.CoverType.NONE: tile(overlay,offset+Vector3(at)+Vector3.UP*maxf(cell.cover_height,0.2),Color.RED if cell.cover_type == MapCellData.CoverType.FULL else Color.ORANGE)
		editor._set_camera_view(0,1.50)
		await capture("res://artifacts/t08-%d-tactical.png" % population_seed)
		overlay.hide()
		editor.find_child("MapEditorUI", true, false).show()
		await capture("res://artifacts/t08-%d-editor.png" % population_seed)
	editor.free()
	print("T08 rendered capture complete")
	quit()
