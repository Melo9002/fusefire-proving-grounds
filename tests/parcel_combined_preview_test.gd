extends SceneTree

const EditorScene = preload("res://tools/parcel_editor/parcel_editor.tscn")
const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Containers = preload("res://tools/parcel_editor/container_field_placements.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var editor := EditorScene.instantiate() as ParcelEditor
	root.add_child(editor)
	await process_frame
	editor.select_parcel(Catalog.LOADING_YARD_A)
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	var panel = editor.field_panel
	panel.session.add("ground", "containers", Rect2i(2, 21, 3, 5))
	panel.refresh()
	check(panel.fit_feedback.text.contains("Reserved by existing placement container_west"), "A 3 × 5 strip over an existing guide names the reservation before Preview")
	check(panel.overlay.get_child_count() > 1, "Rejected container positions are outlined before Preview")
	panel.fit_feedback.mouse_entered.emit()
	check(is_instance_valid(panel._conflict_marker) and panel._conflict_marker.get_child_count() == 2, "Hovering a fitting reason highlights the candidate and its reservation")
	panel.locate_fit_conflict(true)
	check(editor._camera_target.distance_to(editor.displayed_parcel.to_global(Vector3(3, 1, 23))) < 3, "Clicking a conflict frames the real west reservation")
	panel.fit_feedback.mouse_exited.emit()
	check(not is_instance_valid(panel._conflict_marker), "Leaving the reason clears its temporary highlight")
	panel.preview()
	check(panel.fit_feedback.text.contains("Reserved by existing placement container_west"), "The same fitting reason survives Preview beside the controls")
	panel.reset_preview()
	panel.session.undo()
	panel.session.add("ground", "containers", Rect2i(7, 20, 3, 10))
	panel.density.value = 100
	panel.refresh()
	check(panel.fit_feedback.text.contains("2 positions fit"), "The unobstructed strip fits both original new container positions")
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	var truck := Containers.Library.create("car_kit/delivery")
	truck.position = Vector3(8, 0, 22)
	truck.rotation_degrees.y = 90
	editor.draft.add_fixed(truck)
	truck.free()
	editor._apply_draft()
	var added_path: String = editor.draft.selected_path
	var before: Array = editor.draft.placements.duplicate(true)
	var paint: Array = panel.session.fields.duplicate(true)
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	panel.preview()
	check(is_instance_valid(panel._runtime_preview) and panel._runtime_preview.has_node(NodePath(added_path)), "Combined Preview includes the manually placed delivery truck")
	check(panel.compiled_preview != null and not panel.compiled_preview.get_cell(Vector3i(10, 0, 22)).can_stop, "The rotated truck's authored tactical footprint follows its visible rotation")
	check(panel.preview_context.text.begins_with("Containers") and not panel.status.visible and panel._result_details.visible, "The main result leads with containers and collapses technical counts")
	panel._result_details.button_pressed = true
	check(panel.status.visible and panel.status.text.contains("authored sockets"), "Technical preview details remain available")
	editor.tactical_scope.select(1)
	editor.tactical_scope.item_selected.emit(1)
	check(editor.tactical_overlay.get_child_count() == 1, "Selected-only bounds show the fixed truck without tinting other structures")
	var truck_node: Node3D = panel._runtime_preview.get_node(NodePath(added_path))
	check(editor.tactical_overlay.get_child(0).global_transform.is_equal_approx(truck_node.get_node("TacticalVolume").global_transform), "The selected overlay matches the real rotated volume")
	editor.tactical_scope.select(0)
	editor.tactical_scope.item_selected.emit(0)
	check(panel.fit_feedback.text.contains("Overlaps a fixed object"), "The rotated fixed truck explains rejected container candidates")
	var clone: Node3D = panel._runtime_preview
	var volumes: Array[AABB] = []
	for node in clone.find_children("*", "Node3D", true, false):
		if node.has_meta("solid_size"):
			var dimensions: Vector3 = node.get_meta("solid_size")
			volumes.append(node.global_transform * AABB(-dimensions * 0.5, dimensions))
	for a in volumes.size():
		for b in range(a + 1, volumes.size()):
			check(not volumes[a].grow(-0.01).intersects(volumes[b]), "Accepted combined preview keeps authored tactical volumes clear")
	var positions: Array = clone.get_children().map(func(node): return [node.name, node.transform if node is Node3D else null])
	panel.preview()
	check(panel._runtime_preview.get_children().map(func(node): return [node.name, node.transform if node is Node3D else null]) == positions, "Repeating the combined preview preserves accepted transforms")
	panel.reset_preview()
	check(editor.draft.placements == before and panel.session.fields == paint and editor.draft.dirty and panel.has_unsaved_changes(), "Show guides preserves fixed-object and paint drafts")
	var export_path := "res://.godot/combined_preview_export.tscn"
	check(panel.export_scene(export_path), "Combined fixed truck and container rules export together: " + panel.status.text)
	check(panel.handoff_steps.text.contains("✓ 2. Export") and panel.handoff_next.text == "Save object draft", "The handoff records a current export while keeping unsaved drafts visible")
	if FileAccess.file_exists(export_path):
		var scene := ResourceLoader.load(export_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var reopened := scene.instantiate() as Node3D
		check(reopened.has_node(NodePath(added_path)) and reopened.get_node(NodePath(added_path)).has_node("TacticalVolume"), "Reopening the scene retains the added truck and its authored volume")
		var map := FlatMapGenerator.generate(16, 32, 1.0, 17)
		reopened.transform = ParcelTransform.scene_transform(Vector2i(16, 32), Vector3i.ZERO, 0, Vector2i(16, 32))
		var exported := AuthoredParcelDefinition.new(reopened.get_meta("parcel_id"), "Export", Catalog.LOADING_SERVICE, 1, Vector2i(16, 32), scene)
		exported.apply_population(reopened, [])
		AuthoredSceneMapCompiler.compile(reopened, map, 1.0)
		check(not map.get_cell(Vector3i(10, 0, 22)).can_stop, "The reopened export compiles the truck at its edited rotation")
		reopened.free()
		DirAccess.remove_absolute(export_path)
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor._remove_selected()
	check(panel.handoff_steps.text.contains("Scene changed since export"), "Editing an exported scene invalidates the current-export checklist state")
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	check(panel.fit_feedback.text.contains("2 positions fit"), "Removing the fixed truck restores both fitting positions")
	panel.preview()
	check(not panel._runtime_preview.has_node(NodePath(added_path)) and panel.compiled_preview.get_cell(Vector3i(10, 0, 22)).can_stop, "Removed objects leave no invisible tactical blocker in combined Preview")
	panel.reset_preview()
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor.draft.select("CrateA")
	editor._remove_selected()
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	check(panel.export_scene(export_path), "Removing an original fixed object exports with the current paint")
	if FileAccess.file_exists(export_path):
		var scene := ResourceLoader.load(export_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var reopened := scene.instantiate() as Node3D
		check(not reopened.has_node("CrateA") and not reopened.has_node(NodePath(added_path)), "The reopened scene preserves removals of original and added objects")
		reopened.free()
		DirAccess.remove_absolute(export_path)
	editor.free()
	print("Combined parcel preview: %d failure(s)" % failures)
	quit(1 if failures else 0)
