extends SceneTree
const Content = preload("res://systems/generation2/local_parcel_content.gd")
var failures := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/paint-scope-output"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var editor := load("res://tools/parcel_editor/parcel_editor.tscn").instantiate() as ParcelEditor
	root.add_child(editor)
	await process_frame
	editor.select_parcel(AuthoredParcelCatalog.LOADING_YARD_A)
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	var ambulance := editor.PlacementLibrary.create("car_kit/ambulance")
	ambulance.position = Vector3(5.5, 0, 25)
	editor.draft.add_fixed(ambulance)
	ambulance.free()
	editor._apply_draft()
	check(editor.draft_badge.text.contains("object changes"), "Adding the ambulance is described as an object change")
	var panel = editor.field_panel
	check(panel.rule_context.text.contains("Other object types and floors keep their rules"), "Permission scope is explained before the first stroke")
	panel.session.add("ground", "parking", Rect2i(6, 21, 2, 2))
	panel.refresh()
	panel.preview()
	check(panel.preview_context.text.begins_with("No parking bays fit") and not panel.status.visible, "A too-small paint has one prominent error, not a duplicate")
	await capture("small-parking-error")
	var preserved: Array[Dictionary] = panel._fitting_sockets()
	check(preserved.any(func(socket): return socket.asset_id == "car_kit/delivery") and preserved.any(func(socket): return String(socket.asset_id).contains("shipping-container")), "Even failed parking paint keeps truck/container permission")
	panel.session.undo()
	var fitted := false
	for rect in [Rect2i(5, 17, 8, 8), Rect2i(5, 20, 8, 8), Rect2i(5, 23, 8, 8)]:
		panel.session.add("ground", "parking", rect)
		if not panel.build_current().has("error"):
			fitted = true
			break
		panel.session.undo()
	check(fitted, "Parking paint fits alongside the retained reservations")
	panel.density.value = 100
	panel.preview()
	check(is_instance_valid(panel._runtime_preview), "Preview accepts type-scoped paint")
	if is_instance_valid(panel._runtime_preview):
		var choices: Array = panel.preview_manifest.placements[0].population
		check(choices.any(func(choice): return choice.asset_id == "car_kit/delivery") and choices.any(func(choice): return String(choice.asset_id).contains("shipping-container")) and choices.any(func(choice): return choice.asset_id in PopulationFieldDraft.PRESETS.parking), "Parking Preview retains a truck and container alongside the new car")
		var archived := Content.archive(panel.preview_definition.scene)
		check(not archived.has("error"), "Preserve the preview for runtime parity")
		if not archived.has("error"):
			var data := BattlefieldCatalog.generate(BattlefieldCatalog.PARCEL_TEST, Vector2i(16, 32), 17, 1, {"local_content": archived.content})
			check(data.generation_errors.is_empty() and data.content_manifest.placements == panel.preview_manifest.placements, "Battle reconstructs the same retained and painted population")
			if archived.created: DirAccess.remove_absolute(Content.snapshot_path(archived.content.snapshot))
		await capture("parking-with-original-population")
		var preview: Node3D = panel._runtime_preview
		for tab in [ParcelEditor.Task.MOVE_OBJECTS, ParcelEditor.Task.POPULATION_FIELDS, ParcelEditor.Task.INSPECT]:
			editor.task_tabs.current_tab = tab
			check(panel._runtime_preview == preview and is_instance_valid(preview) and not editor.displayed_parcel.visible, "Tab navigation preserves the visible preview")
	panel.density.value = 0
	panel.preview()
	check(is_instance_valid(panel._runtime_preview), "0% parking still previews with unrelated population")
	if is_instance_valid(panel._runtime_preview):
		var empty_parking: Array = panel.preview_manifest.placements[0].population
		check(empty_parking.any(func(choice): return choice.asset_id == "car_kit/delivery") and empty_parking.any(func(choice): return String(choice.asset_id).contains("shipping-container")) and not empty_parking.any(func(choice): return choice.asset_id in PopulationFieldDraft.PRESETS.parking), "Parking density zero removes parking cars without removing trucks/containers")
	var fingerprint := editor._session_fingerprint()
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	panel.preview_registered()
	await capture("compare-original-return")
	check(panel.guides_button.text == "Return to my parcel", "Original comparison names the return action clearly")
	panel.reset_preview()
	check(panel.guides_button.text == "Show guides" and editor._session_fingerprint() == fingerprint, "Returning restores the edited layout without changing it")
	# A parking stroke does not take over the same car type on another floor.
	var roof := {"surface_id": "roof", "asset_id": "car_kit/sedan"}
	check(not panel.session.edits_socket(roof), "Permission is scoped to the painted floor as well as type")
	editor.free()
	print("Parcel paint scope: %d failure(s)" % failures)
	quit(1 if failures else 0)

func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(args[1])
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[1].path_join(name + ".png")) == OK, "Capture " + name)
