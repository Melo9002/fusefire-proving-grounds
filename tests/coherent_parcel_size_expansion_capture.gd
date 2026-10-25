extends SceneTree
## Explicit Task 7.2 visual matrix. Normal captures hide engineering overlays;
## diagnostic captures expose accepted parcel/frontage relationships separately.

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
	for item in [[&"industrial_district", 17], [&"mixed_service", 11027], [&"commercial_street", 7319]]:
		await _rebuild(editor, item[0], item[1])
		editor._set_plan_overlay_visible(false)
		editor._set_spatial_contracts_visible(false)
		editor._frame_camera()
		editor._set_camera_view(0.0, 1.50)
		await _save("%s-%d-overhead.png" % [item[0], item[1]], output)
		if item[0] == &"commercial_street": continue
		if not _focus_elongated_parcel(editor): editor._frame_camera()
		editor._set_camera_view(0.48, 0.20)
		await _save("%s-%d-loading-strip.png" % [item[0], item[1]], output)
		editor._set_plan_overlay_visible(true)
		editor._set_spatial_contracts_visible(true)
		if not _focus_elongated_parcel(editor): editor._frame_camera()
		editor._set_camera_view(0.18, 0.82)
		await _save("%s-%d-loading-strip-diagnostic.png" % [item[0], item[1]], output)
	print("Parcel-size expansion captures saved to " + output)
	quit()

func _rebuild(editor: Node, environment_id: StringName, map_seed: int) -> void:
	editor.layout_preset = environment_id
	editor.generation_seed = map_seed
	for index in editor.preset_picker.item_count:
		if editor.preset_picker.get_item_metadata(index) == environment_id:
			editor.preset_picker.select(index)
			break
	editor._rebuild()
	await process_frame

func _focus_elongated_parcel(editor: Node) -> bool:
	var plan: EnvironmentLayoutPlan = editor.displayed_data.environment_layout_plan
	var target: Dictionary = {}
	for parcel in plan.parcels:
		if parcel.get("template", &"") == &"loading_service_strip":
			target = parcel
			break
	if target.is_empty(): return false
	var bounds: Rect2i = target.bounds
	var modular_root: Node = editor.content.get_node_or_null("ModularEnvironment")
	if modular_root == null: return false
	var visual_bounds := AABB()
	var found := false
	for module in modular_root.get_children():
		if not module is Node3D: continue
		var origin: Vector2i = module.get_meta("origin", Vector2i(-1, -1))
		if not bounds.has_point(origin): continue
		var measured := AssetPlacement.mesh_bounds(module as Node3D)
		if measured.size == Vector3.ZERO: continue
		visual_bounds = measured if not found else visual_bounds.merge(measured)
		found = true
	if not found: return false
	editor.orbit.frame(visual_bounds.grow(0.6))
	editor.inspection_target = "%s elongated loading/service parcel" % plan.environment_id
	editor._refresh_status_target()
	return true

func _save(filename: String, output: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(filename))
	if error != OK:
		push_error("Parcel-size capture failed: %s" % error)
		quit(1)
