extends SceneTree
const EditorScene = preload("res://tools/parcel_editor/parcel_editor.tscn")
const Content = preload("res://systems/generation2/local_parcel_content.gd")
var failures := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/population-parity-output"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var editor := EditorScene.instantiate() as ParcelEditor
	root.add_child(editor)
	await process_frame
	editor.select_parcel(AuthoredParcelCatalog.INDUSTRIAL_OFFICE_PARKING_A)
	var panel = editor.field_panel
	panel.session.add("ground", "parking", Rect2i(2, 4, 28, 8))
	panel.session.add("ground", "containers", Rect2i(0, 17, 4, 5))
	for occupancy in [0, 65, 100]:
		panel.density.value = occupancy
		for map_seed in [17, 18]:
			panel.seed_input.value = map_seed
			panel.preview()
			check(is_instance_valid(panel._runtime_preview), "Mixed parking/container paint previews through export validation: " + panel.preview_context.text)
			if not is_instance_valid(panel._runtime_preview): continue
			var archived := Content.archive(panel.preview_definition.scene)
			check(not archived.has("error"), "Preserve the exact mixed-content snapshot")
			if archived.has("error"): continue
			var data := BattlefieldCatalog.generate(BattlefieldCatalog.PARCEL_TEST, Vector2i(32, 32), map_seed, 1, {"local_content": archived.content})
			check(data.generation_errors.is_empty() and data.content_manifest.placements == panel.preview_manifest.placements, "Seed %d at %d%% has identical preview/battle population" % [map_seed, occupancy])
			check(_signature(data) == _signature(panel.compiled_preview), "Preview and runtime compile identical movement, cover and shot boundaries")
			var choices: Array = data.content_manifest.placements[0].population
			if occupancy == 0: check(choices.is_empty(), "0% remains empty in exported runtime rules")
			if occupancy == 100:
				check(choices.size() == 8 and choices.any(func(choice): return choice.asset_id.contains("shipping-container")), "100% fills seven car positions and the compatible container position")
			if archived.created: DirAccess.remove_absolute(Content.snapshot_path(archived.content.snapshot))
	editor._show_index(editor._definition_index(AuthoredParcelCatalog.INDUSTRIAL_OFFICE_PARKING_A))
	panel.session.add("ground", "protected", Rect2i(0, 0, 32, 32))
	panel.preview()
	check(is_instance_valid(panel._runtime_preview), "Protection-only edits may exclude every population position: " + panel.preview_context.text)
	if is_instance_valid(panel._runtime_preview):
		check(panel.preview_definition.population_sockets().is_empty() and panel.preview_manifest.placements[0].population.is_empty(), "Completely protected content remains valid with no population")
	editor.free()
	print("Parcel population runtime parity: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _signature(data: MapData) -> String:
	var rows := []
	for cell: MapCellData in data.cells.values():
		rows.append([cell.grid_position, cell.walkable, cell.can_stop, cell.cover_type, cell.cover_height, cell.authored_shot_parts])
	return str(rows).sha256_text()
