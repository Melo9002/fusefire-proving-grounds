extends SceneTree
## Explicit Task 7.1 visual matrix. Normal views keep engineering overlays off;
## one separate diagnostic view exposes the exact accepted plan/frontages.

const CAPTURE_SIZE := Vector2i(1600, 900)
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = CAPTURE_SIZE
	var editor = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	for item in [[&"industrial_district", 17], [&"commercial_street", 7319], [&"mixed_service", 11027]]:
		await _rebuild(editor, item[0], item[1])
		editor._set_plan_overlay_visible(false)
		editor._set_spatial_contracts_visible(false)
		editor._frame_camera()
		editor._set_camera_view(0.0, 1.50)
		await _save("%s-%d-overhead.png" % [item[0], item[1]], output)
	if await _rebuild(editor, &"industrial_district", 17):
		editor._set_plan_overlay_visible(false)
		editor._set_spatial_contracts_visible(false)
		if not _focus_secondary_intersection(editor): editor._frame_camera()
		editor._set_camera_view(0.24, 0.92)
		await _save("industrial_district-17-secondary-seam.png", output)
		editor._set_plan_overlay_visible(true)
		editor._frame_camera()
		editor._set_camera_view(0.0, 1.50)
		await _save("industrial_district-17-diagnostic.png", output)
	print("Secondary-road captures saved to " + output)
	quit()

func _rebuild(editor: Node, environment_id: StringName, map_seed: int) -> bool:
	editor.layout_preset = environment_id
	editor.generation_seed = map_seed
	for index in editor.preset_picker.item_count:
		if editor.preset_picker.get_item_metadata(index) == environment_id:
			editor.preset_picker.select(index)
			break
	editor._rebuild()
	await process_frame
	return editor.displayed_data != null and "secondary_branch" in String(editor.displayed_data.environment_layout_plan.topology)

func _focus_secondary_intersection(editor: Node) -> bool:
	var modular_root: Node = editor.content.get_node_or_null("ModularEnvironment")
	if modular_root == null: return false
	var matches: Array[Node] = []
	for module in modular_root.get_children():
		if module.get_meta("component_id", &"") == &"road_intersection_t": matches.append(module)
	if matches.is_empty(): return false
	var junction := matches.back() as Node3D
	var bounds := AssetPlacement.mesh_bounds(junction)
	for neighbor in modular_root.get_children():
		if neighbor == junction or neighbor.get_meta("component_id", &"") not in [&"road_straight", &"road_intersection_t", &"road_crossroad", &"road_corner"]: continue
		var neighbor_bounds := AssetPlacement.mesh_bounds(neighbor as Node3D)
		if bounds.grow(0.25).intersects(neighbor_bounds): bounds = bounds.merge(neighbor_bounds)
	editor.orbit.frame(bounds.grow(0.35))
	editor.inspection_target = "certified secondary-street junction"
	editor._refresh_status_target()
	return true

func _save(filename: String, output: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(filename))
	if error != OK:
		push_error("Secondary-road capture failed: %s" % error)
		quit(1)
