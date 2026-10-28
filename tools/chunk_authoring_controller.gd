class_name ChunkAuthoringController
extends RefCounted
## Draft authoring adapter for the existing Map Editor viewport. No play certification.
const Assets = preload("res://tools/asset_lab/asset_catalog.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")
const Draw = preload("res://tools/diagnostics/fusefire_debug_draw_3d.gd")
var host: Node3D
var session := ChunkEditorSession.new()
var directory := ChunkSourceStore.DEFAULT_DIRECTORY
var context: EnvironmentResolutionContext
var panel: ScrollContainer
var column: VBoxContainer
var filename: LineEdit
var search: LineEdit
var gallery_filter: OptionButton
var gallery_summary: Label
var gallery_directories := {}
var gallery: ItemList
var instances: ItemList
var feedback: Label
var selection_label: Label
var numbers := {}
var port_id: LineEdit
var port_role: LineEdit
var port_profile: LineEdit
var port_edge: OptionButton
var port_connection: OptionButton
var ports: ItemList
var selected_gallery := ""
var preview: SubViewport
var preview_root: Node3D
var preview_camera: Camera3D
var preview_orbit: InspectionOrbitCamera
var asset_ids: Array[String] = []
var objects := {}
var notices: Array[String] = []
var armed := false
var undo_button: Button
var redo_button: Button
var operation_message := ""
var tabs: TabContainer
var ghost: Node3D
var pending := {}
var pending_mode := ""
var pending_source_id := ""
var pending_gallery := ""
var ghost_at := Vector3.ZERO
var pending_actions: HBoxContainer
var pending_error := ""
var ghost_material: StandardMaterial3D
const PILOT_DIRECTORY := "res://content/chunks/industrial"
var pending_obstacles: EnvironmentModuleLayout
var discard_dialog: ConfirmationDialog
var requested_document := {}
var publication: ChunkPublicationPanel

func _init(editor: Node3D) -> void:
	host = editor
	session.new_draft()

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return row
func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func():
		# Return keys to construction after activating a button. Otherwise the
		# focused button consumes arrows as UI navigation instead of movement.
		button.release_focus()
		action.call())
	parent.add_child(button)
	return button
func _number(parent: Node, key: String, initial: int, minimum := 0, maximum := 256) -> SpinBox:
	var label := _label(parent, key)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = initial
	spin.step = 1
	spin.custom_minimum_size.x = 65
	parent.add_child(spin)
	numbers[key] = spin
	return spin
func _text(parent: Node, placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field
func build_ui(parent: Control) -> void:
	panel = ScrollContainer.new()
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -360
	panel.offset_right = -10
	panel.offset_top = 150
	panel.offset_bottom = -10
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var background := StyleBoxFlat.new()
	background.bg_color = Color("172631")
	panel.add_theme_stylebox_override("panel", background)
	column = VBoxContainer.new()
	column.custom_minimum_size.x = 325
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(column)
	_label(column, "BUILD A CHUNK")
	_label(column, "Choose an item, then click the grid. Right-drag to orbit; scroll to zoom.")
	filename = _text(column, "Draft filename")
	var files := _row(column)
	_button(files, "New", new_draft)
	_button(files, "Save draft", save)
	_button(files, "Open name", open_draft)
	_button(column, "Browse saved chunks", browse_saved_chunks)
	var history := _row(column)
	undo_button = _button(history, "Undo", func(): changed(session.undo()))
	redo_button = _button(history, "Redo", func(): changed(session.redo()))
	_button(history, "Validate / refresh assets", refresh)
	var edit := _row(column)
	_button(edit, "Move", func(): begin_existing("move"))
	_button(edit, "Duplicate", duplicate_selected)
	_button(edit, "Delete", func(): changed(session.delete_selected()))
	var turns := _row(column)
	_button(turns, "Rotate left", func(): adjust_selection(-1, 0))
	_button(turns, "Rotate right", func(): adjust_selection(1, 0))
	_button(turns, "Lower", func(): adjust_selection(0, -1))
	_button(turns, "Raise", func(): adjust_selection(0, 1))
	feedback = _label(column, "")
	pending_actions = _row(column)
	_button(pending_actions, "Place here (Enter)", confirm_pending)
	_button(pending_actions, "Cancel (Esc)", cancel_pending)
	pending_actions.hide()
	tabs = TabContainer.new()
	column.add_child(tabs)
	var build_page := VBoxContainer.new()
	build_page.name = "Browse"
	tabs.add_child(build_page)
	var selected_page := VBoxContainer.new()
	selected_page.name = "Selected"
	tabs.add_child(selected_page)
	var details_page := VBoxContainer.new()
	details_page.name = "Chunk details"
	tabs.add_child(details_page)
	var bounds := _row(details_page)
	_number(bounds, "W", 20, 1)
	_number(bounds, "D", 20, 1)
	_number(bounds, "H", 12, 1)
	_button(details_page, "Apply chunk bounds", func(): changed(session.set_bounds(_n("W"), _n("D"), _n("H"))))
	gallery_filter = OptionButton.new()
	for category in ["All content", "Saved chunks", "Industrial examples", "Components", "Assets"]: gallery_filter.add_item(category)
	gallery_filter.item_selected.connect(func(_index): search.clear(); cancel_pending(); populate_gallery())
	build_page.add_child(gallery_filter)
	search = _text(build_page, "Search by name (e.g. loading yard)")
	search.clear_button_enabled = true
	gallery_summary = _label(build_page, "")
	search.text_changed.connect(func(_value): populate_gallery())
	gallery = ItemList.new()
	gallery.custom_minimum_size.y = 120
	gallery.item_selected.connect(select_gallery)
	build_page.add_child(gallery)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(310, 120)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_page.add_child(container)
	preview = SubViewport.new()
	preview.size = Vector2i(310, 120)
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(preview)
	preview_camera = Camera3D.new()
	preview.add_child(preview_camera)
	preview_orbit = InspectionOrbitCamera.new(preview_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	preview.add_child(sun)
	_button(build_page, "Place selected content (then click grid)", begin_gallery)
	_button(build_page, "Open selected draft for editing", open_gallery_draft)
	instances = ItemList.new()
	instances.custom_minimum_size.y = 90
	instances.item_selected.connect(func(index): session.select(str(instances.get_item_metadata(index))); instances.release_focus(); sync_selection())
	selected_page.add_child(instances)
	selection_label = _label(selected_page, "")
	var coords := _row(selected_page)
	_number(coords, "X", 0, -256)
	_number(coords, "Z", 0, -256)
	_number(coords, "Y", 0)
	var rotation := _row(selected_page)
	_number(rotation, "Turn", 0, 0, 3)
	_number(rotation, "Variant", 0, 0, 99999)
	_button(selected_page, "Apply snapped transform", apply_transform)
	_button(selected_page, "Declare visual-only decoration", func(): changed(session.declare_visual_only()))
	_button(selected_page, "Use component tactical behavior", func(): changed(session.declare_component_behavior()))
	_label(details_page, "Boundary ports — select an existing port to edit")
	ports = ItemList.new()
	ports.custom_minimum_size.y = 60
	ports.item_selected.connect(select_port)
	details_page.add_child(ports)
	port_id = _text(details_page, "Port ID")
	port_role = _text(details_page, "Role (e.g. pedestrian)")
	port_profile = _text(details_page, "Compatibility profile (e.g. walkway_1)")
	var port_options := _row(details_page)
	port_edge = OptionButton.new()
	for edge in ["North -Z", "East +X", "South +Z", "West -X"]: port_edge.add_item(edge)
	port_options.add_child(port_edge)
	port_connection = OptionButton.new()
	for policy in ["required", "optional", "terminated"]: port_connection.add_item(policy)
	port_options.add_child(port_connection)
	var port_extent := _row(details_page)
	_number(port_extent, "Start", 0)
	_number(port_extent, "Width", 1, 1)
	_number(port_extent, "Level", 0)
	var port_actions := _row(details_page)
	_button(port_actions, "Set port", set_port)
	_button(port_actions, "Remove port", func(): changed(session.remove_port(port_id.text)))
	var publication_page := VBoxContainer.new()
	publication_page.name = "Publish"
	tabs.add_child(publication_page)
	publication = ChunkPublicationPanel.new(self)
	publication.build(publication_page)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "Discard unsaved changes?"
	discard_dialog.ok_button_text = "Discard changes and continue"
	discard_dialog.cancel_button_text = "Keep editing"
	discard_dialog.confirmed.connect(confirm_document_change)
	discard_dialog.canceled.connect(cancel_document_change)
	panel.add_child(discard_dialog)
	panel.hide()

func _n(key: String) -> int: return int(numbers[key].value)
func ensure_context() -> void:
	if context != null: return
	context = EnvironmentResolutionContext.new(host.editor_catalog)
	asset_ids = Assets.all_ids()
	populate_gallery()
func populate_gallery() -> void:
	if context == null: return
	gallery.clear()
	var entries: Array[String] = []
	for id in context.catalog: entries.append("component:" + str(id))
	for id in asset_ids: entries.append("asset:" + id)
	gallery_directories.clear()
	var folders := {"draft": directory, "pilot": PILOT_DIRECTORY}
	if directory == PILOT_DIRECTORY: folders.erase("draft")
	if directory != ChunkSourceStore.DEFAULT_DIRECTORY:
		folders["current"] = ChunkSourceStore.DEFAULT_DIRECTORY
	for kind in folders:
		if not DirAccess.dir_exists_absolute(folders[kind]): continue
		for file in DirAccess.get_files_at(folders[kind]):
			if file.ends_with(".json"):
				var key := str(kind) + ":" + file.get_basename()
				entries.append(key)
				gallery_directories[key] = folders[kind]
	entries.sort()
	var query := search.text.strip_edges().to_lower().replace("_", " ")
	for entry in entries:
		var parts := entry.split(":", true, 1)
		var category := gallery_filter.selected
		if category == 1 and not is_gallery_draft(entry): continue
		if category == 2 and parts[0] != "pilot": continue
		if category == 3 and parts[0] != "component": continue
		if category == 4 and parts[0] != "asset": continue
		var label := "%s · %s" % [parts[0].capitalize(), parts[1].get_file().replace("_", " ").capitalize()]
		if parts[0] == "pilot": label = "Example · " + parts[1].capitalize().replace("_", " ")
		if not query.is_empty() and not (entry.to_lower().replace("_", " ") + " " + label.to_lower()).contains(query): continue
		gallery.add_item(label)
		gallery.set_item_tooltip(gallery.item_count - 1, entry)
		gallery.set_item_metadata(gallery.item_count - 1, entry)
	selected_gallery = ""
	gallery_summary.text = "%d items — select to preview; open a saved chunk below." % gallery.item_count if gallery.item_count else "No matches. Clear search or choose another category."

func browse_saved_chunks() -> void:
	cancel_pending()
	tabs.current_tab = 0
	gallery_filter.select(1)
	search.clear()
	populate_gallery()
	panel.set_deferred("scroll_vertical", 0)

func select_gallery(index: int) -> void:
	gallery.release_focus()
	selected_gallery = gallery.get_item_metadata(index)
	if is_instance_valid(preview_root): preview_root.free()
	preview_root = Node3D.new()
	preview.add_child(preview_root)
	if is_gallery_draft(selected_gallery):
		var result := load_gallery_draft(selected_gallery)
		if result.ok:
			for record in result.source.data.instances: render_record(preview_root, record, Vector3.ZERO)
		else: feedback.text = result.error
	else:
		var id := selected_gallery.trim_prefix("component:")
		render_record(preview_root, {"component_id": id, "placement_id": "preview", "origin": [0, 0], "elevation": 0, "rotation": 0, "variation": 0}, Vector3.ZERO)
	preview_orbit.frame(Placement.mesh_bounds(preview_root))
	if not is_gallery_draft(selected_gallery): begin_gallery()
	else:
		cancel_pending()
		feedback.text = "Previewing saved chunk. Open it for editing, or place an independent copy below."

func world_offset() -> Vector3:
	return Vector3(-float(session.source.data.bounds[0]) * 0.5 + 0.5, 0, -float(session.source.data.bounds[1]) * 0.5 + 0.5)
func render_record(parent: Node3D, record: Dictionary, offset: Vector3) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	node.set_meta("placement_id", record.placement_id)
	var placement := EnvironmentModulePlacement.from_record(record)
	var id := str(placement.component_id)
	if id.begins_with("asset:") and id.trim_prefix("asset:") in asset_ids:
		Assets.place(node, id.trim_prefix("asset:"), offset + Vector3(placement.origin.x, placement.elevation, placement.origin.y), -placement.rotation * PI * 0.5, context.calibration_data)
	elif context.catalog.has(placement.component_id):
		var definition: EnvironmentModuleDefinition = context.catalog[placement.component_id]
		var data := MapData.new()
		data.add_cell(MapCellData.new(Vector3i(placement.origin.x, 0, placement.origin.y), offset + Vector3(placement.origin.x, 0, placement.origin.y)))
		ModularEnvironmentPresenter._add_ground_marker(data, node, definition, placement, 1.0)
		for marker in node.get_children(): marker.position.y += placement.elevation
		for visual in context.visuals(definition, placement.variation):
			ModularEnvironmentPresenter._add_visual(data, node, definition, placement, visual, 1.0)
	if node.get_child_count() == 0:
		var marker := MeshInstance3D.new()
		marker.mesh = BoxMesh.new()
		marker.position = offset + Vector3(placement.origin.x, placement.elevation + 0.5, placement.origin.y)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.MAGENTA
		marker.material_override = material
		node.add_child(marker)
	cache_faces(node)
	return node
func cache_faces(node: Node3D) -> void:
	var path := str(node.get_meta("asset_path", ""))
	if path.begins_with(Assets.ROOT):
		var asset_id := path.trim_prefix(Assets.ROOT).replace("/models/", "/").trim_suffix(".glb")
		if asset_id in asset_ids:
			var meaning := Semantics.effective(asset_id, context.semantic_data)
			node.set_meta("draft_working_faces", meaning.working_faces)
	for child in node.get_children():
		if child is Node3D: cache_faces(child)
func draw_faces(node: Node3D) -> void:
	for face in node.get_meta("draft_working_faces", []):
		var direction: Vector3 = {"+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+z": Vector3.BACK, "-z": Vector3.FORWARD}.get(face, Vector3.ZERO)
		var center := Placement.mesh_bounds(node).get_center()
		Draw.draw_arrow(center, center + (node.global_basis * direction).normalized() * 2, Color.YELLOW)
	for child in node.get_children():
		if child is Node3D: draw_faces(child)
func rebuild() -> void:
	ensure_context()
	if is_instance_valid(host.content): host.content.free()
	host.content = Node3D.new()
	host.add_child(host.content)
	host.inspection_module = null
	host.preview_map_size = Vector2i(int(session.source.data.bounds[0]), int(session.source.data.bounds[1]))
	host._add_grid_overlay(host.content, host.preview_map_size, 1.0)
	objects.clear()
	instances.clear()
	for record in session.source.data.instances:
		objects[record.placement_id] = render_record(host.content, record, world_offset())
		instances.add_item("%s · %s" % [record.placement_id, record.component_id])
		instances.set_item_metadata(instances.item_count - 1, record.placement_id)
	ports.clear()
	for port in session.source.data.ports: ports.add_item("%s · %s" % [port.id, port.profile])
	numbers.W.value = session.source.data.bounds[0]
	numbers.D.value = session.source.data.bounds[1]
	numbers.H.value = session.source.data.height
	filename.text = session.filename
	host.preview_map_size = Vector2i(int(session.source.data.bounds[0]), int(session.source.data.bounds[1]))
	# Shared geometry diagnostics; no expensive dependency re-resolution per move.
	notices.clear()
	var layout := EnvironmentModuleLayout.new(&"chunk_draft")
	for record in session.source.data.instances:
		var definition: EnvironmentModuleDefinition = context.catalog.get(StringName(record.component_id))
		if definition == null:
			var declared: bool = record.placement_id in session.source.data.tactical.get("visual_only", []) and str(record.component_id).trim_prefix("asset:") in asset_ids
			if not declared: notices.append("%s at %s Y%s: choose a tactical role in Selected before publication." % [record.placement_id, record.origin, record.elevation])
			continue
		var placement := EnvironmentModulePlacement.from_record(record)
		if not layout.try_add(definition, placement, host.preview_map_size):
			notices.append("%s at %s Y%s: %s. Move, rotate or change bounds." % [record.placement_id, record.origin, record.elevation, layout.errors.back()])
		if EnvironmentSpatialQueries.record(definition, placement).visual.end.y > float(session.source.data.height):
			notices.append("%s: exceeds chunk height; raise H or lower the object." % record.placement_id)
	sync_selection()
func duplicate_selected() -> void:
	begin_existing("duplicate")
func begin_existing(mode: String) -> void:
	var record := session.selected()
	if record.is_empty():
		operation_message = "Click an object first, then choose Move or Duplicate."
		update_status()
		return
	cancel_pending()
	pending_mode = mode
	pending_source_id = session.selected_id
	pending = record.duplicate(true)
	armed = true
	cache_pending_obstacles()
	build_ghost()
	update_status()
func begin_gallery() -> void:
	if selected_gallery.is_empty(): return
	cancel_pending()
	pending_mode = "draft" if is_gallery_draft(selected_gallery) else "add"
	pending_gallery = selected_gallery
	pending = {"placement_id": "preview", "component_id": selected_gallery.trim_prefix("component:"), "origin": [_n("X"), _n("Z")], "elevation": _n("Y"), "rotation": _n("Turn"), "variation": 0}
	armed = true
	cache_pending_obstacles()
	build_ghost()
	update_status()
func cache_pending_obstacles() -> void:
	pending_obstacles = EnvironmentModuleLayout.new(&"preview")
	for record in session.source.data.instances:
		if pending_mode == "move" and record.placement_id == pending_source_id: continue
		var definition: EnvironmentModuleDefinition = context.catalog.get(StringName(record.component_id))
		if definition != null: pending_obstacles.try_add(definition, EnvironmentModulePlacement.from_record(record), host.preview_map_size)
func preview_diagnostics() -> void:
	pending_error = ""
	var definition: EnvironmentModuleDefinition = context.catalog.get(StringName(pending.component_id))
	if definition != null:
		pending_error = pending_obstacles.placement_error(definition, EnvironmentModulePlacement.from_record(pending), host.preview_map_size)
	if ghost_material != null: ghost_material.albedo_color = Color(1.0, 0.3, 0.25, 0.6) if not pending_error.is_empty() else Color(0.25, 0.9, 1.0, 0.55)
func adjust_selection(turns: int, levels: int) -> void:
	if armed:
		if pending_mode == "draft" and turns != 0:
			feedback.text = "Saved draft copies keep their authored orientation. Rotate individual objects after placing."
			return
		pending.rotation = posmod(int(pending.rotation) + turns, 4)
		pending.elevation = maxi(0, int(pending.elevation) + levels)
		build_ghost()
		update_status()
		return
	var record := session.selected()
	if record.is_empty():
		feedback.text = "Select an object first."
		return
	changed(session.transform_selected(Vector2i(int(record.origin[0]), int(record.origin[1])), int(record.rotation) + turns, maxi(0, int(record.elevation) + levels), int(record.variation)))
func sync_pending_fields() -> void:
	numbers.X.value = pending.origin[0]
	numbers.Z.value = pending.origin[1]
	numbers.Y.value = pending.elevation
	numbers.Turn.value = pending.rotation
	numbers.Variant.value = pending.variation
func build_ghost() -> void:
	sync_pending_fields()
	if is_instance_valid(ghost): ghost.free()
	ghost = Node3D.new()
	host.add_child(ghost)
	ghost_at = Vector3(pending.origin[0], pending.elevation, pending.origin[1])
	if pending_mode == "draft":
		var loaded := load_gallery_draft(pending_gallery)
		if not loaded.ok:
			cancel_pending()
			feedback.text = loaded.error
			return
		for record in loaded.source.data.instances: render_record(ghost, record, world_offset() + ghost_at)
	else: render_record(ghost, pending, world_offset())
	if ghost_material == null: ghost_material = StandardMaterial3D.new()
	var tint := ghost_material
	tint.albedo_color = Color(0.25, 0.9, 1.0, 0.55)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tint_ghost(ghost, tint)
	preview_diagnostics()
	if pending_mode == "move" and objects.has(pending_source_id): objects[pending_source_id].hide()
func _tint_ghost(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _tint_ghost(child, material)
func move_pending(screen: Vector2) -> void:
	if not armed: return
	var hit = Plane(Vector3.UP, float(pending.elevation)).intersects_ray(host.camera.project_ray_origin(screen), host.camera.project_ray_normal(screen))
	if hit == null: return
	var local: Vector3 = hit - world_offset()
	pending.origin = [roundi(local.x), roundi(local.z)]
	var next := Vector3(pending.origin[0], pending.elevation, pending.origin[1])
	if is_instance_valid(ghost): ghost.position += next - ghost_at
	ghost_at = next
	sync_pending_fields()
	preview_diagnostics()
	update_status()
func cancel_pending() -> void:
	if is_instance_valid(ghost): ghost.free()
	ghost = null
	if objects.has(pending_source_id): objects[pending_source_id].show()
	armed = false
	pending.clear()
	pending_error = ""
	pending_mode = ""
	pending_source_id = ""
	operation_message = ""
	if is_instance_valid(pending_actions): sync_selection()
func confirm_pending() -> void:
	if not armed: return
	var at := Vector2i(int(pending.origin[0]), int(pending.origin[1]))
	var ok := false
	if pending_mode == "move":
		session.select(pending_source_id)
		ok = session.transform_selected(at, int(pending.rotation), int(pending.elevation), int(pending.variation))
	elif pending_mode == "duplicate":
		# One source command: duplicate plus chosen transform, including references.
		var draft := ChunkEditorSession.new()
		draft.source = session._add_candidate()
		draft.selected_id = pending_source_id
		draft.duplicate_selected()
		draft.transform_selected(at, int(pending.rotation), int(pending.elevation), int(pending.variation))
		ok = session._commit(draft.source, draft.selected_id, "Duplicate")
	elif pending_mode == "draft":
		var result := load_gallery_draft(pending_gallery)
		if result.ok: ok = session.insert_copy(result.source, Vector3i(at.x, int(pending.elevation), at.y))
		else: session.last_error = result.error
	else: ok = session.add(str(pending.component_id), at, int(pending.rotation), int(pending.elevation))
	if not ok:
		feedback.text = session.last_error
		return
	cancel_pending()
	changed(true)
	tabs.current_tab = 1
func changed(ok: bool) -> void:
	cancel_pending()
	operation_message = ""
	if ok: rebuild()
	else: feedback.text = session.last_error
func sync_selection() -> void:
	for id in objects: host._set_selection_outline(objects[id], id == session.selected_id)
	var record := session.selected()
	selection_label.text = "No selection. Y is placement elevation." if record.is_empty() else "%s · %s" % [record.placement_id, record.component_id]
	if not record.is_empty():
		numbers.X.value = record.origin[0]
		numbers.Z.value = record.origin[1]
		numbers.Y.value = record.elevation
		numbers.Turn.value = record.rotation
		numbers.Variant.value = record.variation
	for index in instances.item_count:
		if instances.get_item_metadata(index) == session.selected_id: instances.select(index)
	update_status()
func update_status() -> void:
	if publication != null: publication.source_changed()
	host.status.text = "CHUNK DRAFT · %s%s · %d instances\n%s\nCamera changes are preview-only. Object transforms and ports are saved. No publication approval." % [session.filename, " *unsaved" if session.dirty() else "", session.source.data.instances.size(), "%s preview at %s · click to place · Q/E rotate · PgUp/PgDn height · Esc cancel" % [pending_mode.capitalize(), pending.get("origin", [])] if armed else "Select objects; arrows move, Q/E rotate, PgUp/PgDn elevation, Ctrl+Z/Y history."]
	pending_actions.visible = armed
	undo_button.disabled = session.undo_stack.is_empty()
	redo_button.disabled = session.redo_stack.is_empty()
	feedback.text = "Draft validity is separate from publication.\n" + "\n".join(notices.slice(0, 5))
	if armed: feedback.text = "Preview only — click the grid to place. Q/E rotate; Esc cancels. Overlaps can be kept as an unfinished draft."
	if armed and not pending_error.is_empty(): feedback.text += "\n" + pending_error + ". Placing keeps this as an unfinished draft."
	if not operation_message.is_empty():
		feedback.text = operation_message + "\n" + feedback.text
	if notices.size() > 5: feedback.text += "\n+%d more diagnostics" % (notices.size() - 5)
func apply_transform() -> void:
	if armed:
		pending.origin = [_n("X"), _n("Z")]
		pending.rotation = _n("Turn") if pending_mode != "draft" else 0
		pending.elevation = _n("Y")
		pending.variation = _n("Variant")
		build_ghost()
		update_status()
		return
	changed(session.transform_selected(Vector2i(_n("X"), _n("Z")), _n("Turn"), _n("Y"), _n("Variant")))
func save() -> void:
	if armed:
		feedback.text = "Place or cancel the preview before saving."
		return
	if session.save(directory, filename.text):
		populate_gallery()
		update_status()
		feedback.text = "Saved draft: " + session.filename + ". Validation/approval unchanged."
	else: feedback.text = session.last_error
func open_draft() -> void:
	request_document_change({"directory": directory, "name": filename.text})
func _unsaved_edits() -> bool:
	return session.dirty() and (not session.undo_stack.is_empty() or not session.source.data.instances.is_empty())
func new_draft() -> void:
	request_document_change({"new": true})
func request_document_change(target: Dictionary) -> void:
	requested_document = target.duplicate()
	if _unsaved_edits() or armed:
		var action: String = "start a new chunk" if target.has("new") else "open " + str(target.name)
		discard_dialog.dialog_text = "Discard unsaved changes to this chunk and %s?\nYour saved files will not be deleted. Any placement preview will be canceled." % action
		discard_dialog.popup_centered(Vector2i(520, 180))
		discard_dialog.get_cancel_button().grab_focus()
	else: confirm_document_change()
func cancel_document_change() -> void:
	requested_document.clear()
	discard_dialog.hide()
func confirm_document_change() -> void:
	if requested_document.is_empty(): return
	var target := requested_document.duplicate()
	requested_document.clear()
	discard_dialog.hide()
	# Load is transactional: an invalid destination must not discard current work.
	if not target.has("new") and not session.load_draft(target.directory, target.name):
		feedback.text = session.last_error
		return
	cancel_pending()
	if target.has("new"): session.new_draft()
	else: directory = target.directory
	rebuild()
	host._frame_camera()
	populate_gallery()
func refresh() -> void:
	cancel_pending()
	context = null
	ensure_context()
	rebuild()
	var errors := session.source.draft_diagnostics(context)
	for error in errors: notices.append("%s: %s" % [error.field, error.message])
	update_status()
func select_port(index: int) -> void:
	var port: Dictionary = session.source.data.ports[index]
	port_id.text = port.id
	port_role.text = port.role
	port_profile.text = port.profile
	port_edge.select([Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT].find(Vector2i(int(port.normal[0]), int(port.normal[1]))))
	port_connection.select(["required", "optional", "terminated"].find(port.connection))
	numbers.Level.value = port.elevation
	numbers.Width.value = port.minimum_width
	if not port.cells.is_empty(): numbers.Start.value = port.cells[0][0 if port_edge.selected in [0, 2] else 1]
func set_port() -> void:
	var cells: Array = []
	for index in _n("Width"):
		var at := _n("Start") + index
		cells.append([[at, 0], [int(session.source.data.bounds[0]) - 1, at], [at, int(session.source.data.bounds[1]) - 1], [0, at]][port_edge.selected])
	changed(session.set_port({"id": port_id.text, "role": port_role.text, "profile": port_profile.text, "cells": cells, "normal": [[0, -1], [1, 0], [0, 1], [-1, 0]][port_edge.selected], "elevation": _n("Level"), "minimum_width": _n("Width"), "connection": port_connection.get_item_text(port_connection.selected)}))
func click(screen: Vector2) -> void:
	var ray: Vector3 = host.camera.project_ray_origin(screen)
	var direction: Vector3 = host.camera.project_ray_normal(screen)
	if armed:
		move_pending(screen)
		confirm_pending()
		return
	var nearest := INF
	var chosen := ""
	for id in objects:
		var hit = Placement.mesh_bounds(objects[id]).intersects_ray(ray, direction)
		if hit != null and ray.distance_to(hit) < nearest:
			nearest = ray.distance_to(hit)
			chosen = id
	session.select(chosen)
	sync_selection()
	if not chosen.is_empty(): tabs.current_tab = 1
func shortcut(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if armed:
		if event.ctrl_pressed and event.keycode == KEY_S:
			save()
			return
		if event.keycode == KEY_ESCAPE: cancel_pending()
		elif event.keycode == KEY_ENTER: confirm_pending()
		elif event.keycode in [KEY_Q, KEY_E] and pending_mode != "draft":
			pending.rotation = posmod(int(pending.rotation) + (-1 if event.keycode == KEY_Q else 1), 4)
			build_ghost()
		elif event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
			pending.elevation = maxi(0, int(pending.elevation) + (1 if event.keycode == KEY_PAGEUP else -1))
			build_ghost()
		update_status()
		return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z: changed(session.redo() if event.shift_pressed else session.undo())
			KEY_Y: changed(session.redo())
			KEY_S: save()
			KEY_D: duplicate_selected()
		return
	match event.keycode:
		KEY_ESCAPE: armed = false; update_status()
		KEY_DELETE: changed(session.delete_selected())
		KEY_F: host._frame_camera()
		KEY_1: host._set_camera_view(0.0, 0.18)
		KEY_3: host._set_camera_view(PI * 0.5, 0.18)
		KEY_7: host._set_camera_view(0.0, 1.50)
		KEY_LEFT: numbers.X.value -= 1; apply_transform()
		KEY_RIGHT: numbers.X.value += 1; apply_transform()
		KEY_UP: numbers.Z.value -= 1; apply_transform()
		KEY_DOWN: numbers.Z.value += 1; apply_transform()
		KEY_PAGEUP: numbers.Y.value += 1; apply_transform()
		KEY_PAGEDOWN: numbers.Y.value -= 1; apply_transform()
		KEY_Q: numbers.Turn.value = posmod(_n("Turn") - 1, 4); apply_transform()
		KEY_E: numbers.Turn.value = posmod(_n("Turn") + 1, 4); apply_transform()
func draw() -> void:
	if publication != null and publication.busy: return
	var grid: Node3D = host.content.get_node_or_null("TacticalGrid")
	if grid != null: grid.position.y = float(pending.elevation) if armed else float(_n("Y"))
	var scope := Draw.begin_scope(host.get_viewport())
	var offset := world_offset()
	Draw.draw_aabb(AABB(offset - Vector3(0.5, 0, 0.5), Vector3(session.source.data.bounds[0], session.source.data.height, session.source.data.bounds[1])), Color.CYAN)
	for port in session.source.data.ports:
		for cell in port.cells:
			var at := offset + Vector3(cell[0], port.elevation + 0.1, cell[1])
			Draw.draw_arrow(at, at + Vector3(port.normal[0], 0, port.normal[1]), Color.CYAN)
	for region in session.source.data.clearances:
		for cell in region.cells:
			var bottom := 0.0 if region.scope == "whole_column" else float(cell[1])
			var extent := float(session.source.data.height) if region.scope == "whole_column" else float(region.height)
			var at := offset + Vector3(cell[0] - 0.5, bottom, cell[2] - 0.5)
			Draw.draw_aabb(AABB(at, Vector3(1, extent, 1)), Color.ORANGE)
	if objects.has(session.selected_id):
		var object: Node3D = objects[session.selected_id]
		var record := session.selected()
		var id := str(record.component_id)
		draw_faces(object)
		if context.catalog.has(StringName(id)):
			var definition: EnvironmentModuleDefinition = context.catalog[StringName(id)]
			var placement := EnvironmentModulePlacement.from_record(record)
			var geometry := EnvironmentSpatialQueries.record(definition, placement)
			var bounds: AABB = geometry.visual
			bounds.position += offset
			Draw.draw_aabb(bounds, Color.MAGENTA)
			for cell in geometry.clearance:
				Draw.draw_aabb(AABB(offset + Vector3(cell.x - 0.5, geometry.clearance_span.x, cell.y - 0.5), Vector3(1, geometry.clearance_span.y - geometry.clearance_span.x, 1)), Color.ORANGE)
			for connection in definition.connections:
				var cell := definition.rotate_cell(connection.local_cell, placement.rotation) + placement.origin
				var direction: Vector2i = definition.rotate_direction(connection.direction, placement.rotation)
				var at := offset + Vector3(cell.x, placement.elevation + connection.elevation + 0.2, cell.y)
				Draw.draw_arrow(at, at + Vector3(direction.x, 0, direction.y), Color.YELLOW)
	if scope != null: scope = null

func is_gallery_draft(entry: String) -> bool: return entry.begins_with("draft:") or entry.begins_with("pilot:") or entry.begins_with("current:")
func load_gallery_draft(entry: String) -> Dictionary:
	return ChunkSourceStore.load_named(str(gallery_directories.get(entry, PILOT_DIRECTORY if entry.begins_with("pilot:") else directory)), entry.get_slice(":", 1))
func open_gallery_draft() -> void:
	if not is_gallery_draft(selected_gallery):
		feedback.text = "Select a saved draft or pilot chunk in Browse first."
		return
	var destination: String = gallery_directories.get(selected_gallery, PILOT_DIRECTORY if selected_gallery.begins_with("pilot:") else directory)
	request_document_change({"directory": destination, "name": selected_gallery.get_slice(":", 1)})
