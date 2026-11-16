extends SceneTree
## Contract: ordinary editor placement acquires saved, inspectable tactical parts
## automatically; authored exceptions and existing registered content stay intact.
const Library = preload("res://tools/parcel_editor/parcel_placement_library.gd")
const Bounds = preload("res://tools/parcel_editor/mesh_tactical_bounds.gd")
const Catalog = preload("res://systems/generation2/authored_parcel_catalog.gd")
const Draft = preload("res://tools/parcel_editor/parcel_draft_session.gd")
const Fields = preload("res://tools/parcel_editor/population_field_draft.gd")
const Export = preload("res://tools/parcel_editor/population_scene_export.gd")
# Simulate a rebake changing geometry while asset IDs and object poses stay
# identical. The export must get a new identity even though the draft is the same.
class RecalibratedDraft extends ParcelDraftSession:
	func preview_root(source: Node3D) -> Node3D:
		var copy := super.preview_root(source)
		var part := copy.get_node(selected_path + "/MeshBoundaries").get_child(0)
		part.set_meta("solid_size", part.get_meta("solid_size") * 1.1)
		return copy

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	check(Library.entries().has("factory_kit/box-small"), "An ordinary cargo box is discoverable in the placement browser")
	var object := Library.create("factory_kit/box-small")
	var shapes := object.find_children("*", "Node3D", true, false).filter(func(node): return node.has_meta("solid_size"))
	check(not shapes.is_empty(), "An ordinary calibrated box gets tactical boundaries without a template")
	var map := TacticalMapBuilder.generate(15, 15, 1.0, 0)
	AuthoredSceneMapCompiler.compile(object, map, 1.0)
	check(not map.get_cell(Vector3i(7, 0, 7)).can_stop, "The visible box occupies its actual placement")
	check(map.get_cell(Vector3i(7, 0, 7)).cover_height > 0, "Automatic box participates in existing cover rules")
	check(map.get_cell(Vector3i(7, 0, 7)).cover_type == MapCellData.CoverType.LOW, "The calibrated 0.825-tile box uses existing low-cover rules")
	object.free()
	_check_parts()
	_check_small_footprint()
	_check_saved_placement()
	await _check_editor()
	print("Mesh boundaries: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _box(parent: Node3D, at: Vector3, dimensions: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = dimensions
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _check_parts() -> void:
	var object := Node3D.new()
	# Separate raised bodies with an open aisle and a beam safely overhead.
	_box(object, Vector3(-2, 1, 0), Vector3(1, 1.2, 4))
	_box(object, Vector3(2, 1, 0), Vector3(1, 1.2, 4))
	_box(object, Vector3(0, 3.5, 0), Vector3(6, 0.4, 0.4))
	# These two parts reserve the same grid cell, but leave a bullet-sized gap.
	_box(object, Vector3(-0.3, 1, 6), Vector3(0.2, 2, 2))
	_box(object, Vector3(0.3, 1, 6), Vector3(0.2, 2, 2))
	var hidden := _box(object, Vector3(0, 1, 0), Vector3(8, 2, 8))
	hidden.hide()
	check(Bounds.add_to(object) == 5, "Only visible mesh parts acquire separate starting shapes")
	check(Bounds.add_to(object) == 0, "Creating boundaries again does not duplicate or replace shapes")
	for unit: float in [1.0, 0.5]:
		var floor_mesh := CSGBox3D.new()
		floor_mesh.size = Vector3(23 * unit, 0.2, 23 * unit)
		floor_mesh.position.y = -0.1
		root.add_child(floor_mesh)
		var grid := GridManager.new()
		grid.cell_size = unit
		grid.map_floor = floor_mesh
		for turn in 4:
			object.transform = Transform3D(Basis(Vector3.UP, turn * PI * 0.5).scaled(Vector3(1.25, 1, 1.5)), Vector3(1, 0, -1))
			grid.map_data = TacticalMapBuilder.generate(23, 23, unit, 0)
			AuthoredSceneMapCompiler.compile(object, grid.map_data, unit)
			var center := grid.world_to_grid(object.transform.origin * unit)
			var body := grid.world_to_grid((object.transform * Vector3(-2, 0, 0)) * unit)
			check(not grid.map_data.get_cell(body).can_stop, "A raised body blocks standing inside it at unit %s, rotation %d" % [unit, turn])
			check(grid.map_data.get_cell(center).can_stop, "The aisle and high beam do not become an invisible wall")
			var from := (object.transform * Vector3(-4, 1, 0)) * unit
			var to := (object.transform * Vector3(-0.5, 1, 0)) * unit
			check(CombatRules.get_blocking_cell(from, to, grid) != null, "Visible raised body blocks the real shot query")
			from = (object.transform * Vector3(-4, 0.15, 0)) * unit
			to = (object.transform * Vector3(-0.5, 0.15, 0)) * unit
			check(CombatRules.get_blocking_cell(from, to, grid) == null, "Movement clearance does not invent shot geometry below a raised body")
			from = (object.transform * Vector3(0, 1, -4)) * unit
			to = (object.transform * Vector3(0, 1, 4)) * unit
			check(CombatRules.get_blocking_cell(from, to, grid) == null, "The gap between separate mesh parts stays shootable")
			from = (object.transform * Vector3(0, 3.5, -4)) * unit
			to = (object.transform * Vector3(0, 3.5, 4)) * unit
			check(CombatRules.get_blocking_cell(from, to, grid) != null, "An automatically derived overhead mesh blocks rays at its real height")
			check(CombatRules.get_blocking_cell(to, from, grid) != null, "The automatically derived overhead mesh blocks in reverse too")
			from = (object.transform * Vector3(0, 1, 4)) * unit
			to = (object.transform * Vector3(0, 1, 8)) * unit
			var gap_cell := grid.map_data.get_cell(grid.world_to_grid((object.transform * Vector3(0, 0, 6)) * unit))
			check(not gap_cell.can_stop and gap_cell.authored_shot_parts.size() == 2, "The narrow gap has a real occupied cell with both separate shot parts")
			check(CombatRules.get_blocking_cell(from, to, grid) == null, "Parts sharing a reserved grid cell still leave their visible shot gap open")
		grid.free()
		floor_mesh.free()
	object.free()

func _check_saved_placement() -> void:
	var source = Catalog.get_definition(Catalog.LOADING_YARD_A)
	var parcel: Node3D = source.instantiate()
	var draft := Draft.new()
	draft.begin(source, parcel)
	var box := Library.create("factory_kit/box-small")
	box.position = Vector3(8, 0, 22)
	box.rotation_degrees.y = 90
	box.scale = Vector3.ONE * 1.5
	draft.add_fixed(box)
	var path := String(draft.selected_path)
	box.free()
	check(draft.apply(parcel).is_empty(), "Ordinary mesh placement applies without a hand-authored tactical template")
	var fields := Fields.new()
	fields.begin(source, parcel)
	var draft_path := "res://.godot/mesh_boundary_test.draft.json"
	check(draft.save_to(draft_path), "Save the ordinary object through the existing draft format")
	var restored := Draft.new()
	var fresh: Node3D = source.instantiate()
	check(restored.load_from(draft_path, source, fresh) and restored.apply(fresh).is_empty(), "Save/reopen reconstructs the object and its automatic shapes")
	var reopened_box := fresh.get_node(path) as Node3D
	check(reopened_box.has_node("MeshBoundaries") and reopened_box.transform.is_equal_approx((parcel.get_node(path) as Node3D).transform), "Rotation, scale and boundaries follow the saved object together")
	var result := Export.build(source, fields, null, restored)
	check(not result.has("error"), "The ordinary object exports through the normal route checks: %s" % result.get("error", ""))
	if not result.has("error"):
		var changed := RecalibratedDraft.new()
		var unchanged_source: Node3D = source.instantiate()
		changed.begin(source, unchanged_source)
		unchanged_source.free()
		changed.placements = restored.placements.duplicate(true)
		changed.selected_path = path
		var rebaked := Export.build(source, fields, null, changed)
		check(not rebaked.has("error") and rebaked.definition.parcel_id != result.definition.parcel_id, "Rebaking different geometry with the same asset IDs and poses changes export identity")
		var scene_path := "res://.godot/mesh_boundary_export_test.tscn"
		check(ResourceSaver.save(result.definition.scene, scene_path) == OK, "Export saves the explicit derived parts")
		var scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var scene_root := scene.instantiate() as Node3D
		var saved_box := scene_root.get_node(path) as Node3D
		check(saved_box.get_node("MeshBoundaries").get_child_count() == reopened_box.get_node("MeshBoundaries").get_child_count(), "Export/reopen retains one copy of every derived part")
		var signature := Export._derived_boundaries(scene_root)
		var volume := saved_box.get_node("MeshBoundaries").get_child(0)
		var dimensions: Vector3 = volume.get_meta("solid_size")
		volume.set_meta("solid_size", dimensions * 1.1)
		check(signature != Export._derived_boundaries(scene_root), "Export identity includes derived geometry, not just the asset ID and pose")
		volume.set_meta("solid_size", dimensions)
		source.apply_population(scene_root, [])
		scene_root.transform = ParcelTransform.scene_transform(source.size, Vector3i.ZERO, 0, source.size)
		var grid := GridManager.new()
		grid.map_data = TacticalMapBuilder.generate(16, 32, 1, 0)
		AuthoredSceneMapCompiler.compile(scene_root, grid.map_data, 1)
		check(not grid.map_data.get_cell(Vector3i(8, 0, 22)).can_stop, "Reopened geometry blocks stopping at the object's edited position")
		# Its calibrated height is 0.825; scaling by 1.5 crosses the existing
		# 1.2-tile full-cover threshold. Do not change the rule to fit the test.
		check(CombatRules.get_directional_cover(Vector3i(4, 0, 22), Vector3i(9, 0, 22), grid) == MapCellData.CoverType.FULL, "Existing directional cover queries recognize the enlarged box as full cover")
		grid.free()
		scene_root.free()
		DirAccess.remove_absolute(scene_path)
	fresh.free()
	parcel.free()
	DirAccess.remove_absolute(draft_path)
	var authored := Library.create("car_kit/delivery")
	check(Bounds.add_to(authored) == 0 and not authored.has_node("MeshBoundaries"), "An authored truck keeps its existing compound and historical shapes")
	authored.free()

func _check_small_footprint() -> void:
	var object := Node3D.new()
	_box(object, Vector3(0, 1, 0), Vector3(0.4, 2, 0.4))
	Bounds.add_to(object)
	object.position = Vector3(0.5, 0, 0.5)
	object.scale = Vector3.ONE * 0.5
	var map := TacticalMapBuilder.generate(15, 15, 1, 0)
	AuthoredSceneMapCompiler.compile(object, map, 1)
	# The visible footprint crosses four cell corners. Shrinking an object must
	# not accidentally make it disappear from all four tactical cells.
	for x in [7, 8]:
		for z in [7, 8]:
			check(not map.get_cell(Vector3i(x, 0, z)).can_stop, "A small scaled object still reserves every cell touched by its visible footprint")
	object.free()

func _check_editor() -> void:
	var editor: ParcelEditor = load("res://tools/parcel_editor/parcel_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.select_parcel(Catalog.LOADING_YARD_A)
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor._top_view()
	editor._asset_filter.text = "box-small"
	editor._refresh_asset_browser()
	check(editor._asset_picker.item_count == 1, "The new object is selectable through the normal editor browser")
	editor._start_library_placement()
	var cursor := editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(7, 0, 17)))
	editor._update_library_placement(cursor)
	check(editor._pending_asset.visible and editor._placement_issue.is_empty() and editor._ghost_material.albedo_color.b > 0.9, "An automatically bounded object gets a legal blue placement ghost")
	editor._finish_library_placement(true)
	var path := String(editor.draft.selected_path)
	check(editor.displayed_parcel.get_node(path).has_node("MeshBoundaries"), "Click-to-place keeps the generated boundaries on the fixed object")
	editor._start_library_placement()
	editor._update_library_placement(cursor)
	check(editor._placement_issue.contains(path) and editor._ghost_material.albedo_color.r > 0.9, "A second ordinary object cannot overlap the first object's automatic boundary")
	editor._finish_library_placement(false)
	editor._undo()
	check(not editor.displayed_parcel.has_node(path), "Undo removes the object and automatic shapes together")
	editor._redo()
	check(editor.displayed_parcel.get_node(path).has_node("MeshBoundaries"), "Redo reconstructs the automatic shapes")
	editor.tactical_scope.select(1)
	editor.tactical_toggle.button_pressed = true
	editor._refresh_active_tactical_overlay()
	check(editor.tactical_overlay.get_child_count() > 0, "Existing selected-only tactical inspection shows the generated parts")
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(args[1])
		editor._camera_target = (editor.displayed_parcel.get_node(path) as Node3D).global_position + Vector3.UP * 0.4
		editor._distance = 7
		editor._yaw = -0.8
		editor._pitch = 0.6
		editor._update_camera()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(args[1].path_join("ordinary-box-boundaries.png")) == OK, "Capture the real editor's automatically bounded object")
	editor.free()
