class_name ParcelEditor
extends Node3D
## Small registered-parcel inspection shell. This deliberately does not restore
## the retired chunk generator, publication system, or runtime dependencies.

const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const DraftSession = preload("res://tools/parcel_editor/parcel_draft_session.gd")
const FieldPanel = preload("res://tools/parcel_editor/population_field_panel.gd")
const PlacementLibrary = preload("res://tools/parcel_editor/parcel_placement_library.gd")
const AssetPreview = preload("res://tools/parcel_editor/asset_preview.gd")
var field_panel

enum Task { INSPECT, MOVE_OBJECTS, POPULATION_FIELDS }
var task_tabs: TabContainer
var draft_badge: Label
var discard_dialog: ConfirmationDialog
var _selection_marker: Node3D
var _panel: PanelContainer
var _discard_action: Callable
var _draft_file_dialog: FileDialog
var _draft_file_action: Callable
var _visual_destination: Label
var _dragged: Node3D
var _drag_origin := Transform3D.IDENTITY
var _drag_start := Vector3.ZERO
var _drag_screen_start := Vector2.ZERO
var _drag_moved := false
var _drag_yaw := 0.0
var _placement_issue := ""
var _drag_materials := {}
var _ghost_material: StandardMaterial3D
var _placement_hint: Label
var _pending_asset: Node3D
var _asset_entries: Dictionary
var _asset_picker: OptionButton
var _asset_filter: LineEdit
var _asset_category: OptionButton
var _add_asset_button: Button
var asset_preview
var tactical_scope: OptionButton
var tactical_legend: Label
var thumbnail_toggle: CheckButton
var workflow_footer: Label
var export_path_display: LineEdit
var export_actions: HBoxContainer

var parcel_picker: OptionButton
var metadata_label: Label
var validation_label: Label
var population_toggle: CheckButton
var tactical_toggle: CheckButton
var placement_picker: OptionButton
var draft_status: Label
var undo_button: Button
var redo_button: Button
var camera: Camera3D
var displayed_parcel_id: StringName = &""
var displayed_parcel: Node3D
var tactical_overlay: Node3D
var draft = DraftSession.new()

var _definitions: Array = []
var _grid: MeshInstance3D
var _camera_target := Vector3(0, 1.5, 0)
var _yaw := deg_to_rad(45.0)
var _pitch := deg_to_rad(34.0)
var _distance := 32.0
var _orbiting := false
var _panning := false

func _ready() -> void:
	_build_stage()
	_build_ui()
	_definitions = Catalog.all()
	for definition in _definitions:
		parcel_picker.add_item("%s — %s" % [definition.display_name, _size_label(definition.size)])
		parcel_picker.set_item_metadata(parcel_picker.item_count - 1, definition.parcel_id)
	if not _definitions.is_empty():
		_show_index(0)
	get_viewport().size_changed.connect(_update_camera)
	get_window().focus_exited.connect(func(): _finish_object_drag(false))
	_update_camera()

func _build_stage() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17232d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c8d8")
	environment.ambient_light_energy = 0.68
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 44.0
	add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_placement_hint = Label.new()
	_placement_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placement_hint.add_theme_color_override("font_shadow_color", Color("121820"))
	_placement_hint.add_theme_constant_override("shadow_offset_x", 2)
	_placement_hint.add_theme_constant_override("shadow_offset_y", 2)
	_placement_hint.hide()
	layer.add_child(_placement_hint)
	_panel = PanelContainer.new()
	layer.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 16
	_panel.offset_right = 436
	_panel.offset_top = 16
	_panel.offset_bottom = -16
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title := Label.new()
	title.text = "PARCEL EDITOR"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	parcel_picker = OptionButton.new()
	parcel_picker.name = "ParcelPicker"
	parcel_picker.fit_to_longest_item = false
	parcel_picker.item_selected.connect(_request_parcel)
	column.add_child(parcel_picker)
	draft_badge = Label.new()
	column.add_child(draft_badge)
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 6)
	for spec in [["FRAME", _frame], ["TOP", _top_view], ["OBLIQUE", _oblique_view]]:
		var button := Button.new()
		button.text = spec[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(spec[1])
		views.add_child(button)
	column.add_child(views)
	var help := Label.new()
	help.text = "RMB orbit · MMB pan · wheel zoom · F frame"
	help.modulate = Color(0.62, 0.7, 0.78)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	task_tabs = TabContainer.new()
	task_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(task_tabs)
	var inspect_page := _add_task_page("Inspect")
	validation_label = Label.new()
	validation_label.name = "Validation"
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_page.add_child(validation_label)
	population_toggle = CheckButton.new()
	population_toggle.name = "PopulationToggle"
	population_toggle.text = "Show painted population guides"
	population_toggle.button_pressed = true
	inspect_page.add_child(population_toggle)
	tactical_toggle = CheckButton.new()
	tactical_toggle.name = "TacticalToggle"
	tactical_toggle.text = "Show tactical contracts"
	tactical_toggle.tooltip_text = "Cyan: elevated route/access. Orange: explicit tactical solid volumes. These overlays, not imported meshes, explain gameplay authority."
	tactical_toggle.button_pressed = false
	tactical_toggle.toggled.connect(func(enabled: bool): if tactical_overlay: tactical_overlay.visible = enabled)
	inspect_page.add_child(tactical_toggle)
	var details := CheckButton.new()
	details.text = "Technical details"
	inspect_page.add_child(details)
	metadata_label = Label.new()
	metadata_label.name = "Metadata"
	metadata_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metadata_label.hide()
	inspect_page.add_child(metadata_label)
	details.toggled.connect(func(expanded: bool): metadata_label.visible = expanded)

	var move_page := _add_task_page("Objects")
	var limits := Label.new()
	limits.text = "Draft only · Checks bounds and solid overlap. New objects use ground level. Battle routes and runtime registration are separate."
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	move_page.add_child(limits)
	var browser := VBoxContainer.new()
	move_page.add_child(browser)
	_asset_filter = LineEdit.new()
	_asset_filter.placeholder_text = "Search fixed assets"
	browser.add_child(_asset_filter)
	_asset_category = OptionButton.new()
	for category in ["All fixed assets", "Decoration", "Tactical"]:
		_asset_category.add_item(category)
	browser.add_child(_asset_category)
	_asset_picker = OptionButton.new()
	_asset_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_asset_picker.fit_to_longest_item = false
	browser.add_child(_asset_picker)
	thumbnail_toggle = CheckButton.new()
	thumbnail_toggle.text = "Asset preview"
	thumbnail_toggle.button_pressed = true
	browser.add_child(thumbnail_toggle)
	asset_preview = AssetPreview.new()
	browser.add_child(asset_preview)
	asset_preview.setup()
	thumbnail_toggle.toggled.connect(func(enabled): asset_preview.visible = enabled)
	_asset_picker.item_selected.connect(func(_index): asset_preview.show_asset(String(_asset_picker.get_selected_metadata())))
	var asset_actions := HBoxContainer.new()
	browser.add_child(asset_actions)
	for action in [["Place", _start_library_placement], ["Duplicate", _start_duplicate], ["Remove", _remove_selected]]:
		var button := Button.new()
		button.text = action[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(action[1])
		asset_actions.add_child(button)
		if action[0] == "Place":
			_add_asset_button = button
	_asset_entries = PlacementLibrary.entries()
	_asset_filter.text_changed.connect(func(_value): _refresh_asset_browser())
	_asset_category.item_selected.connect(func(_value): _refresh_asset_browser())
	_refresh_asset_browser()
	var move_help := Label.new()
	move_help.text = "Place adds a fixed object. Drag to move. R rotates, Shift+R reverses, Esc cancels. Attached tactical volumes move with the object in draft preview. Save and register the scene to use changes in battle."
	move_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	move_page.add_child(move_help)
	var compare := CheckButton.new()
	compare.text = "Show current tactical bounds"
	compare.toggled.connect(func(enabled: bool): tactical_toggle.button_pressed = enabled)
	tactical_toggle.toggled.connect(func(enabled: bool): compare.set_pressed_no_signal(enabled))
	move_page.add_child(compare)
	tactical_scope = OptionButton.new()
	tactical_scope.add_item("Bounds · all objects")
	tactical_scope.add_item("Bounds · selected object only")
	tactical_scope.item_selected.connect(func(_index): _refresh_active_tactical_overlay())
	move_page.add_child(tactical_scope)
	tactical_legend = Label.new()
	tactical_legend.text = "Orange · solid volumes\nCyan · floor and access contracts"
	tactical_legend.modulate = Color("93a8ba")
	tactical_legend.visible = tactical_toggle.button_pressed
	tactical_toggle.toggled.connect(func(enabled): tactical_legend.visible = enabled)
	move_page.add_child(tactical_legend)
	placement_picker = OptionButton.new()
	placement_picker.name = "PlacementPicker"
	placement_picker.fit_to_longest_item = false
	placement_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	placement_picker.tooltip_text = "Select an imported visual node. Tactical metadata remains unchanged."
	placement_picker.item_selected.connect(_select_placement_index)
	move_page.add_child(placement_picker)
	var planar := HBoxContainer.new()
	for spec in [["X−", Vector3(-0.5, 0, 0)], ["X+", Vector3(0.5, 0, 0)], ["Z−", Vector3(0, 0, -0.5)], ["Z+", Vector3(0, 0, 0.5)]]:
		var button := Button.new()
		button.text = spec[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): _translate_selected(spec[1]))
		planar.add_child(button)
	move_page.add_child(planar)
	var vertical := HBoxContainer.new()
	for spec in [["Y−", Vector3(0, -0.25, 0)], ["Y+", Vector3(0, 0.25, 0)], ["YAW −90", -1], ["YAW +90", 1], ["RESET", 0]]:
		var button := Button.new()
		button.text = spec[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if spec[1] is Vector3:
			button.pressed.connect(func(): _translate_selected(spec[1]))
		elif int(spec[1]) == 0:
			button.pressed.connect(_reset_selected)
		else:
			button.pressed.connect(func(): _rotate_selected(int(spec[1])))
		vertical.add_child(button)
	move_page.add_child(vertical)
	var history := HBoxContainer.new()
	undo_button = Button.new()
	undo_button.text = "Undo"
	undo_button.pressed.connect(_undo)
	history.add_child(undo_button)
	redo_button = Button.new()
	redo_button.text = "Redo"
	redo_button.pressed.connect(_redo)
	history.add_child(redo_button)
	var save := Button.new()
	save.text = "Save visuals"
	save.pressed.connect(_save_draft)
	var files := HBoxContainer.new()
	files.add_child(save)
	var load_draft := Button.new()
	load_draft.text = "Load visuals"
	load_draft.pressed.connect(_load_draft)
	files.add_child(load_draft)
	for button in history.get_children():
		(button as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_page.add_child(history)
	move_page.add_child(files)
	var named_files := HBoxContainer.new()
	for spec in [["Save visuals as…", _save_draft_as], ["Open visual draft…", _open_draft]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(spec[1])
		named_files.add_child(button)
	move_page.add_child(named_files)
	_visual_destination = Label.new()
	_visual_destination.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	move_page.add_child(_visual_destination)
	draft_status = Label.new()
	draft_status.name = "DraftStatus"
	draft_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draft_status.modulate = Color(0.68, 0.76, 0.84)
	move_page.add_child(draft_status)
	field_panel = FieldPanel.new()
	field_panel.name = "Population fields"
	field_panel.setup(self)
	task_tabs.add_child(field_panel)
	task_tabs.tab_changed.connect(_on_task_changed)
	workflow_footer = Label.new()
	workflow_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	workflow_footer.add_theme_font_size_override("font_size", 13)
	column.add_child(workflow_footer)
	export_actions = HBoxContainer.new()
	column.add_child(export_actions)
	export_path_display = LineEdit.new()
	export_path_display.editable = false
	export_path_display.placeholder_text = "Exported scene path"
	export_path_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_actions.add_child(export_path_display)
	for spec in [["Copy path", func(): DisplayServer.clipboard_set(export_path_display.text)], ["Folder", func(): OS.shell_open(export_path_display.text.get_base_dir())]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(spec[1])
		export_actions.add_child(button)
	export_actions.hide()
	var back := Button.new()
	back.text = "Back to Match Setup"
	back.pressed.connect(func(): _confirm_discard(func(): get_tree().change_scene_to_file("res://ui/match_setup.tscn")))
	column.add_child(back)

	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "Discard unsaved draft?"
	discard_dialog.ok_button_text = "Discard and continue"
	discard_dialog.transient = true
	discard_dialog.exclusive = true
	discard_dialog.confirmed.connect(func():
		var action := _discard_action
		_discard_action = Callable()
		if action.is_valid(): action.call())
	discard_dialog.canceled.connect(func(): _discard_action = Callable())
	add_child(discard_dialog)

func _add_task_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	task_tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	return page

func _on_task_changed(task: int) -> void:
	_finish_object_drag(false)
	_finish_library_placement(false)
	if task != Task.POPULATION_FIELDS:
		field_panel.cancel_drag()
		field_panel.clear_preview()
	if is_instance_valid(field_panel.overlay):
		field_panel.overlay.visible = task == Task.POPULATION_FIELDS
	if task == Task.MOVE_OBJECTS:
		_update_draft_status()
	else:
		_update_selection_marker()
	if task == Task.POPULATION_FIELDS:
		field_panel.sync_draft_context()
		field_panel.refresh()
		field_panel.update_preview_controls()
	update_workflow_footer()

func _request_parcel(index: int) -> void:
	if index < 0 or index >= _definitions.size() or _definitions[index].parcel_id == displayed_parcel_id:
		return
	# A clicked OptionButton changes selection before emitting its signal.
	parcel_picker.select(_definition_index(displayed_parcel_id))
	_confirm_discard(func(): _show_index(index))

func _confirm_discard(action: Callable) -> void:
	var scopes := _unsaved_scopes()
	if scopes.is_empty():
		action.call()
		return
	_confirm_draft_action("Discard unsaved draft?", "Unsaved changes in %s will be lost." % ", ".join(scopes), "Discard and continue", action)

func confirm_replace_draft(path: String, action: Callable) -> void:
	if not FileAccess.file_exists(path):
		action.call()
		return
	_confirm_draft_action("Replace saved draft?", ProjectSettings.globalize_path(path), "Replace draft", action)

func confirm_open_draft(path: String, unsaved: bool, action: Callable) -> void:
	if unsaved and FileAccess.file_exists(path):
		_confirm_draft_action("Replace unsaved draft?", "Open %s and replace the current draft?" % path, "Open draft", action)
	else:
		action.call()

func _confirm_draft_action(title: String, message: String, button: String, action: Callable) -> void:
	if discard_dialog.visible:
		return
	_discard_action = action
	discard_dialog.title = title
	discard_dialog.dialog_text = message
	discard_dialog.ok_button_text = button
	discard_dialog.popup_centered()

func choose_draft_file(path: String, saving: bool, action: Callable) -> void:
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		_confirm_draft_action("Cannot open draft folder", error_string(error), "Close", func(): pass)
		return
	if not _draft_file_dialog:
		_draft_file_dialog = FileDialog.new()
		_draft_file_dialog.access = FileDialog.ACCESS_USERDATA
		_draft_file_dialog.filters = PackedStringArray(["*.json ; FuseFire draft"])
		_draft_file_dialog.display_mode = FileDialog.DISPLAY_LIST
		_draft_file_dialog.transient = true
		_draft_file_dialog.exclusive = true
		_draft_file_dialog.file_selected.connect(func(destination: String): _draft_file_action.call(destination))
		add_child(_draft_file_dialog)
	_draft_file_action = action
	_draft_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	_draft_file_dialog.title = "Save draft as" if saving else "Open draft"
	_draft_file_dialog.current_dir = path.get_base_dir()
	_draft_file_dialog.current_file = path.get_file() if saving else ""
	_draft_file_dialog.popup_centered_ratio(0.72)

func _definition_index(id: StringName) -> int:
	for index in _definitions.size():
		if _definitions[index].parcel_id == id:
			return index
	return -1

func _unsaved_scopes() -> PackedStringArray:
	var scopes := PackedStringArray()
	if draft.dirty: scopes.append("visual moves")
	if field_panel.has_unsaved_changes(): scopes.append("population fields")
	return scopes

func update_draft_badge() -> void:
	var scopes := _unsaved_scopes()
	draft_badge.text = "No unsaved changes" if scopes.is_empty() else "Unsaved · %s" % ", ".join(scopes)
	draft_badge.modulate = Color("93a8ba") if scopes.is_empty() else Color("ffd077")
	if field_panel != null and is_instance_valid(field_panel.handoff_steps):
		field_panel.update_handoff()

func update_workflow_footer() -> void:
	if not is_instance_valid(workflow_footer):
		return
	var state := "Unsaved" if draft.dirty or field_panel.has_unsaved_changes() else "Saved"
	var differs: bool = draft.placements != draft.base_placements or not field_panel.session.fields.is_empty()
	workflow_footer.text = "%s · %s\n%s" % [state, "draft differs from registered parcel" if differs else "matches registered parcel", field_panel.export_state()]
	var active: String = field_panel.session.active_path if task_tabs.current_tab == Task.POPULATION_FIELDS else draft.active_path
	if not active.is_empty():
		workflow_footer.text = active.get_file() + "\n" + workflow_footer.text
	workflow_footer.tooltip_text = active
	var path: String = field_panel.last_export_path
	export_actions.visible = not path.is_empty()
	if export_path_display.text != path:
		export_path_display.text = path
		export_path_display.caret_column = path.length()
	export_path_display.tooltip_text = path

func select_parcel(parcel_id: StringName) -> bool:
	var index := _definition_index(parcel_id)
	if index < 0:
		return false
	_request_parcel(index)
	return true

func _show_index(index: int) -> void:
	if index < 0 or index >= _definitions.size():
		return
	parcel_picker.select(index)
	_finish_object_drag(false)
	_finish_library_placement(false)
	if is_instance_valid(displayed_parcel):
		field_panel.clear_preview()
		displayed_parcel.free()
	if is_instance_valid(_grid):
		_grid.free()
	if is_instance_valid(tactical_overlay):
		tactical_overlay.free()
	var definition = _definitions[index]
	displayed_parcel_id = definition.parcel_id
	displayed_parcel = definition.instantiate()
	displayed_parcel.name = "DisplayedParcel"
	displayed_parcel.position = Vector3(-(definition.size.x - 1) * 0.5, 0, -(definition.size.y - 1) * 0.5)
	add_child(displayed_parcel)
	_grid = _create_grid(definition.size)
	add_child(_grid)
	tactical_overlay = _create_tactical_overlay(definition)
	tactical_overlay.visible = tactical_toggle.button_pressed
	add_child(tactical_overlay)
	var connection = definition.connection()
	var connection_text := "none"
	if connection != null:
		connection_text = "%s · cell %s · outward %s · width %d" % [connection.kind, connection.cell, connection.outward, connection.width]
	metadata_label.text = "ID  %s\nRole  %s\nFootprint  %s\nRevision  %d\nService interface  %s" % [definition.parcel_id, definition.role, _size_label(definition.size), definition.revision, connection_text]
	var surfaces: Dictionary = definition.population_surfaces(displayed_parcel)
	for region in definition.population_regions(displayed_parcel):
		var surface: Dictionary = surfaces.get(region.surface_id, {})
		metadata_label.text += "\nPopulation  %s · %s · level %s · %s" % [region.region_id, region.surface_id, str(surface.get("level", "missing")), region.local_rect]
	var failures: PackedStringArray = definition.validate()
	validation_label.text = "VALID — registered scene and contracts agree" if failures.is_empty() else "INVALID — %s" % "; ".join(failures)
	validation_label.modulate = Color("79d99b") if failures.is_empty() else Color("ff7a7a")
	population_toggle.button_pressed = true
	population_toggle.disabled = definition.population_sockets().is_empty()
	set_population_visible(false)
	draft.begin(definition, displayed_parcel)
	_visual_destination.text = "Quick save / load · " + draft.draft_path()
	_visual_destination.tooltip_text = ProjectSettings.globalize_path(draft.draft_path())
	field_panel.begin(definition, displayed_parcel)
	_refresh_placement_picker()
	_update_draft_status("Source parcel loaded; runtime content is unchanged.")
	_frame()

func _refresh_placement_picker() -> void:
	placement_picker.clear()
	for record: Dictionary in draft.placements:
		if record.get("removed", false):
			continue
		var node := displayed_parcel.get_node_or_null(NodePath(record.path))
		var role := "Population rule" if node and node.has_meta("population_socket_id") else "Fixed"
		placement_picker.add_item("%s · %s" % [record.path, role])
		placement_picker.set_item_metadata(placement_picker.item_count - 1, String(record.path))
		placement_picker.set_item_tooltip(placement_picker.item_count - 1, String(record.asset_id))
		if String(record.path) == draft.selected_path:
			placement_picker.select(placement_picker.item_count - 1)
	_update_history_buttons()

func _refresh_asset_browser() -> void:
	_asset_picker.clear()
	var category := _asset_category.get_item_text(_asset_category.selected)
	var query := _asset_filter.text.strip_edges()
	for id: String in _asset_entries:
		var role: String = _asset_entries[id]
		if (_asset_category.selected != 0 and role != category) or (not query.is_empty() and not id.containsn(query)):
			continue
		var label := id.get_file().replace("-", " ").capitalize()
		_asset_picker.add_item("%s · %s" % [label, role])
		var index := _asset_picker.item_count - 1
		_asset_picker.set_item_metadata(index, id)
		_asset_picker.set_item_tooltip(index, "%s · fixed %s" % [id, role.to_lower()])
	_add_asset_button.disabled = _asset_picker.item_count == 0
	asset_preview.show_asset(String(_asset_picker.get_item_metadata(0)) if _asset_picker.item_count else "")

func _start_library_placement() -> void:
	if _asset_picker.selected >= 0:
		_start_fixed_placement(String(_asset_picker.get_selected_metadata()))

func _start_duplicate() -> void:
	var selected := _selected_object()
	if selected == null or selected.has_meta("population_socket_id"):
		_update_draft_status("Select a fixed object to duplicate.")
		return
	_start_fixed_placement(String(selected.get_meta("asset_id")), selected.rotation_degrees.y)

func _start_fixed_placement(id: String, yaw := 0.0) -> void:
	_finish_library_placement(false)
	if not _asset_entries.has(id):
		_update_draft_status("This object has no reusable fixed placement in the library.")
		return
	_pending_asset = PlacementLibrary.create(id)
	if _pending_asset == null:
		_update_draft_status("Asset could not be loaded.")
		return
	displayed_parcel.add_child(_pending_asset)
	_pending_asset.rotation_degrees.y = yaw
	_pending_asset.hide()
	_update_draft_status("Move onto the parcel, then click to place. R rotates. Esc cancels.")

func _update_library_placement(screen: Vector2) -> void:
	var on_canvas := not _panel.get_global_rect().has_point(screen) and get_viewport().get_visible_rect().has_point(screen)
	var hit: Variant = _drag_plane_hit(screen, displayed_parcel.global_position.y) if on_canvas else null
	if hit == null:
		_pending_asset.hide()
		_placement_hint.hide()
		return
	var point := displayed_parcel.to_local(hit)
	_pending_asset.position = Vector3(snappedf(point.x, 0.5), 0.0, snappedf(point.z, 0.5))
	_pending_asset.show()
	_placement_issue = _validate_visual_pose(_pending_asset)
	_tint_placement_ghost(_pending_asset)
	_placement_hint.text = "Click to place fixed object" if _placement_issue.is_empty() else _placement_issue
	_placement_hint.modulate = _ghost_color()
	_placement_hint.show()
	_position_placement_hint(screen)

func _finish_library_placement(commit: bool) -> void:
	if not is_instance_valid(_pending_asset):
		return
	_clear_placement_ghost()
	if commit:
		draft.add_fixed(_pending_asset)
	_pending_asset.free()
	_pending_asset = null
	if commit:
		_apply_draft("Added a fixed object to the draft.")
		_refresh_placement_picker()
	else:
		_update_selection_marker()

func _remove_selected() -> void:
	if draft.remove_fixed(displayed_parcel):
		_apply_draft("Removed the fixed object from the draft.")
		_refresh_placement_picker()
	else:
		_update_draft_status("Select a top-level fixed object to remove. Population guides belong to their rules.")

func _select_placement_index(index: int) -> void:
	if index >= 0 and index < placement_picker.item_count:
		draft.select(String(placement_picker.get_item_metadata(index)))
		_update_draft_status()

func _translate_selected(delta: Vector3) -> void:
	var selected := _selected_object()
	if selected:
		_try_visual_pose(selected, selected.position + delta, float(draft.placement().rotation_degrees[1]))

func _rotate_selected(turns: int) -> void:
	var selected := _selected_object()
	if selected:
		_try_visual_pose(selected, selected.position, snappedf(float(draft.placement().rotation_degrees[1]) + turns * 90.0, 90.0))

func _selected_object() -> Node3D:
	return displayed_parcel.get_node_or_null(NodePath(draft.selected_path)) as Node3D if not draft.selected_path.is_empty() else null

func _try_visual_pose(selected: Node3D, position: Vector3, yaw: float) -> void:
	var original := selected.transform
	selected.position = position
	selected.rotation_degrees.y = yaw
	var issue := _validate_visual_pose(selected)
	selected.transform = original
	if not issue.is_empty():
		_update_draft_status("Placement rejected · " + issue)
	elif draft.place_selected(position, yaw):
		_apply_draft("Placed visual draft object.")

func _validate_visual_pose(selected: Node3D) -> String:
	var local_bounds := EnvironmentAssetPlacement.mesh_bounds(selected, displayed_parcel.global_transform.affine_inverse() * (selected.get_parent() as Node3D).global_transform)
	var footprint := Rect2(Vector2(local_bounds.position.x, local_bounds.position.z), Vector2(local_bounds.size.x, local_bounds.size.z))
	var parcel_bounds := Rect2(Vector2(-0.5, -0.5), Vector2(draft.parcel_size))
	if footprint.has_area() and not parcel_bounds.grow(0.01).encloses(footprint):
		return "Outside parcel"
	var moving_solids := _visual_solid_bounds(selected)
	var library_placement := selected == _pending_asset or selected.has_meta("draft_added")
	if library_placement:
		if not is_zero_approx(selected.position.y):
			return "New fixed objects require ground support"
		var connection := ParcelConnection.from_scene(displayed_parcel)
		for cell in connection.world_span(draft.parcel_size, Vector3i.ZERO, 0):
			if footprint.intersects(Rect2(Vector2(cell.x - 0.49, cell.z - 0.49), Vector2.ONE * 0.98)):
				return "Blocks the parcel entrance"
		if moving_solids.is_empty() and local_bounds.has_volume():
			moving_solids.append(displayed_parcel.global_transform * local_bounds)
	for obstacle: Node3D in displayed_parcel.find_children("*", "Node3D", true, false):
		if not obstacle.has_meta("solid_size") or obstacle == selected or selected.is_ancestor_of(obstacle) or obstacle.is_ancestor_of(selected):
			continue
		var owner_node: Node = obstacle
		while owner_node != displayed_parcel and not owner_node.has_meta("asset_id"):
			owner_node = owner_node.get_parent()
		if owner_node.has_meta("draft_removed"):
			continue
		var bounds := _solid_world_bounds(obstacle)
		for solid in moving_solids:
			if solid.grow(-0.01).intersects(bounds):
				return "Overlaps %s" % (obstacle.name if owner_node == displayed_parcel else owner_node.name)
	return ""

func _visual_solid_bounds(object: Node3D) -> Array[AABB]:
	var bounds: Array[AABB] = []
	if object.has_meta("solid_size"):
		bounds.append(_solid_world_bounds(object))
	for node: Node3D in object.find_children("*", "Node3D", true, false):
		if node.has_meta("solid_size"):
			bounds.append(_solid_world_bounds(node))
	return bounds

func _solid_world_bounds(node: Node3D) -> AABB:
	var dimensions: Vector3 = node.get_meta("solid_size")
	return node.global_transform * AABB(-dimensions * 0.5, dimensions)

func _reset_selected() -> void:
	if draft.reset_selected(displayed_parcel):
		_apply_draft("Reset visual placement to its authored transform.")
	else:
		_update_draft_status(draft.last_error)

func _undo() -> void:
	if draft.undo():
		_apply_draft("Undid the last draft edit.")
		_refresh_placement_picker()

func _redo() -> void:
	if draft.redo():
		_apply_draft("Redid the draft edit.")
		_refresh_placement_picker()

func _apply_draft(message := "") -> void:
	field_panel.clear_preview()
	var failures := draft.apply(displayed_parcel)
	field_panel.sync_draft_context()
	refresh_tactical_overlay(displayed_parcel)
	_update_draft_status(message if failures.is_empty() else "; ".join(failures))
	_update_history_buttons()

func _save_draft() -> void:
	var path: String = draft.active_path if not draft.active_path.is_empty() else draft.draft_path()
	confirm_replace_draft(path, func(): _save_draft_to(path))

func _save_draft_as() -> void:
	choose_draft_file(draft.active_path if not draft.active_path.is_empty() else draft.draft_path(), true, _save_draft_to)

func _save_draft_to(path: String) -> void:
	_update_draft_status("Saved visual-only draft to %s." % path if draft.save_to(path) else draft.last_error)

func _load_draft() -> void:
	_load_draft_from(draft.active_path if not draft.active_path.is_empty() else draft.draft_path())

func _open_draft() -> void:
	choose_draft_file(draft.draft_path(), false, _load_draft_from)

func _load_draft_from(path: String) -> void:
	confirm_open_draft(path, draft.dirty, func(): _apply_loaded_draft(path))

func _apply_loaded_draft(path: String) -> void:
	var definition = Catalog.get_definition(displayed_parcel_id)
	if draft.load_from(path, definition, displayed_parcel):
		_apply_draft("Loaded visual-only draft from %s." % path)
		_refresh_placement_picker()
	else:
		_update_draft_status(draft.last_error)

func _update_draft_status(message := "") -> void:
	var record: Dictionary = draft.placement()
	var selection := "No visual placement selected."
	if not record.is_empty():
		selection = "%s\nposition %s · yaw %.1f°" % [record.path, record.position, float(record.rotation_degrees[1])]
		var selected := displayed_parcel.get_node_or_null(NodePath(String(record.path))) as Node3D
		if selected and not selected.is_visible_in_tree():
			selection += "\nPopulation template. Use Population fields → Preview to see placed objects."
	var state := "Unsaved draft"
	if not draft.dirty:
		state = "Registered source" if draft.placements == draft.base_placements else "Draft saved · differs from registered parcel"
	var active: String = draft.active_path
	_visual_destination.text = "Active draft · %s\nDefault copy · %s" % [active.get_file() if not active.is_empty() else "registered source", draft.draft_path().get_file()]
	_visual_destination.tooltip_text = "Save target · " + ProjectSettings.globalize_path(active if not active.is_empty() else draft.draft_path())
	draft_status.text = "%s · %s\n%s%s" % [String(draft.parcel_id), state, selection, "\n" + message if not message.is_empty() else ""]
	_update_history_buttons()
	_update_selection_marker()
	if tactical_scope.selected == 1:
		_refresh_active_tactical_overlay()
	update_draft_badge()

func _update_history_buttons() -> void:
	if undo_button:
		undo_button.disabled = draft.undo_stack.is_empty()
	if redo_button:
		redo_button.disabled = draft.redo_stack.is_empty()

func set_population_visible(enabled: bool) -> void:
	if not is_instance_valid(displayed_parcel):
		return
	for node in displayed_parcel.find_children("*", "Node3D", true, false):
		if node.has_meta("population_socket_id"):
			(node as Node3D).visible = enabled
	_update_selection_marker()

func _update_selection_marker() -> void:
	if is_instance_valid(_selection_marker):
		_selection_marker.free()
	if task_tabs.current_tab != Task.MOVE_OBJECTS or is_instance_valid(_pending_asset) or not is_instance_valid(displayed_parcel) or draft.selected_path.is_empty():
		return
	var selected := displayed_parcel.get_node_or_null(NodePath(draft.selected_path)) as Node3D
	if not selected or not selected.is_visible_in_tree():
		return
	var bounds := AABB()
	for mesh_node: MeshInstance3D in selected.find_children("*", "MeshInstance3D", true, false):
		if not mesh_node.mesh or not mesh_node.is_visible_in_tree():
			continue
		var world_bounds := mesh_node.global_transform * mesh_node.get_aabb()
		bounds = bounds.merge(world_bounds) if bounds.has_volume() else world_bounds
	if not bounds.has_volume():
		bounds = AABB(selected.global_position - Vector3.ONE * 0.25, Vector3.ONE * 0.5)
	bounds = bounds.grow(0.08)
	_selection_marker = Node3D.new()
	_selection_marker.name = "ObjectSelection"
	add_child(_selection_marker)
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	lines.surface_set_color(Color("ffdc83") if not is_instance_valid(_dragged) else _ghost_color())
	for corner in 8:
		for edge in [1, 2, 4]:
			if (corner & edge) == 0:
				lines.surface_add_vertex(bounds.get_endpoint(corner))
				lines.surface_add_vertex(bounds.get_endpoint(corner | edge))
	var pivot := selected.global_position
	var basis := (selected.get_parent() as Node3D).global_basis.orthonormalized()
	for spec in [[basis.x, "X+", Color("ff827d")], [basis.y, "Y+", Color("8deeb4")], [basis.z, "Z+", Color("83c8ff")]]:
		var axis: Vector3 = spec[0]
		var length := clampf(bounds.size.length() * 0.36, 1.5, 6.0)
		var tip := pivot + axis * length
		lines.surface_set_color(spec[2])
		lines.surface_add_vertex(pivot)
		lines.surface_add_vertex(tip)
		var side := (basis.x if spec[1] == "Y+" else basis.y) * length * 0.08
		for sign_value in [-1.0, 1.0]:
			lines.surface_add_vertex(tip)
			lines.surface_add_vertex(tip - axis * length * 0.15 + side * sign_value)
		var label := Label3D.new()
		label.text = spec[1]
		label.modulate = spec[2]
		label.no_depth_test = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.pixel_size = 0.022
		label.position = tip
		_selection_marker.add_child(label)
	lines.surface_end()
	var geometry := MeshInstance3D.new()
	geometry.mesh = lines
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_marker.add_child(geometry)

func _create_grid(size: Vector2i) -> MeshInstance3D:
	var immediate := ImmediateMesh.new()
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color(0.12, 0.78, 0.9, 0.45)
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	for x in range(size.x + 1):
		var px := float(x) - size.x * 0.5
		immediate.surface_add_vertex(Vector3(px, 0.025, -size.y * 0.5))
		immediate.surface_add_vertex(Vector3(px, 0.025, size.y * 0.5))
	for z in range(size.y + 1):
		var pz := float(z) - size.y * 0.5
		immediate.surface_add_vertex(Vector3(-size.x * 0.5, 0.025, pz))
		immediate.surface_add_vertex(Vector3(size.x * 0.5, 0.025, pz))
	immediate.surface_end()
	var result := MeshInstance3D.new()
	result.name = "FootprintGrid"
	result.mesh = immediate
	return result

func refresh_tactical_overlay(scene_root: Node3D) -> void:
	if is_instance_valid(tactical_overlay):
		tactical_overlay.free()
	tactical_overlay = _create_tactical_overlay(Catalog.get_definition(displayed_parcel_id), scene_root)
	tactical_overlay.visible = tactical_toggle.button_pressed
	add_child(tactical_overlay)

func _refresh_active_tactical_overlay() -> void:
	if not is_instance_valid(displayed_parcel):
		return
	var preview: Node3D = field_panel._runtime_preview if field_panel != null else null
	refresh_tactical_overlay(preview if is_instance_valid(preview) else displayed_parcel)

func _create_tactical_overlay(definition, scene_root: Node3D = displayed_parcel) -> Node3D:
	var overlay := Node3D.new()
	overlay.name = "TacticalContracts"
	var solid_material := _overlay_material(Color(1.0, 0.42, 0.12, 0.34))
	var selected := scene_root.get_node_or_null(NodePath(draft.selected_path)) if not draft.selected_path.is_empty() else null
	for node in scene_root.find_children("*", "Node3D", true, false):
		if not node.has_meta("solid_size") or _removed_from_draft(node, scene_root):
			continue
		if tactical_scope.selected == 1 and (selected == null or (node != selected and not selected.is_ancestor_of(node))):
			continue
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = node.get_meta("solid_size", Vector3.ONE)
		mesh.material = solid_material
		box.mesh = mesh
		# The overlay is added at the editor origin, so the already-instantiated
		# parcel node's world transform is also the overlay-local transform.
		box.transform = (node as Node3D).global_transform
		overlay.add_child(box)
	if tactical_scope.selected == 1:
		return overlay
	var cyan := _overlay_material(Color(0.08, 0.86, 1.0, 0.36))
	var deck_rect: Rect2i = displayed_parcel.get_meta("deck_local_rect", Rect2i())
	if deck_rect.has_area():
		var deck := MeshInstance3D.new()
		var deck_mesh := BoxMesh.new()
		deck_mesh.size = Vector3(deck_rect.size.x, 0.12, deck_rect.size.y)
		deck_mesh.material = cyan
		deck.mesh = deck_mesh
		deck.position = Vector3(deck_rect.position.x + deck_rect.size.x * 0.5 - definition.size.x * 0.5, float(displayed_parcel.get_meta("deck_level", 0)) + 0.08, deck_rect.position.y + deck_rect.size.y * 0.5 - definition.size.y * 0.5)
		overlay.add_child(deck)
	var access: Vector3i = displayed_parcel.get_meta("access_cell", Vector3i(-1, 0, -1))
	if access.x >= 0:
		var marker := MeshInstance3D.new()
		var marker_mesh := BoxMesh.new()
		marker_mesh.size = Vector3(0.8, 0.12, 0.8)
		marker_mesh.material = cyan
		marker.mesh = marker_mesh
		marker.position = Vector3(access.x - (definition.size.x - 1) * 0.5, access.y + 0.1, access.z - (definition.size.y - 1) * 0.5)
		overlay.add_child(marker)
	return overlay

func _removed_from_draft(node: Node, scene_root: Node) -> bool:
	while node != scene_root:
		if node.has_meta("draft_removed"):
			return true
		node = node.get_parent()
	return false

func _overlay_material(color: Color) -> StandardMaterial3D:
	var overlay_material := StandardMaterial3D.new()
	overlay_material.albedo_color = color
	overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay_material.no_depth_test = true
	return overlay_material

func _size_label(size: Vector2i) -> String:
	return "%d × %d" % [size.x, size.y]

func _frame() -> void:
	if displayed_parcel_id.is_empty():
		return
	var definition = Catalog.get_definition(displayed_parcel_id)
	_camera_target = Vector3(0, 1.8, 0)
	_distance = maxf(definition.size.x, definition.size.y) * 1.15 + 5.0
	_update_camera()

func _top_view() -> void:
	var definition = Catalog.get_definition(displayed_parcel_id)
	_camera_target = Vector3.ZERO
	_distance = maxf(definition.size.x, definition.size.y) * 1.25 + 5.0
	_yaw = 0.0
	_pitch = deg_to_rad(89.0)
	_update_camera()

func _oblique_view() -> void:
	_yaw = deg_to_rad(45.0)
	_pitch = deg_to_rad(34.0)
	_frame()

func _update_camera() -> void:
	if camera == null:
		return
	var horizontal := cos(_pitch) * _distance
	var offset := Vector3(sin(_yaw) * horizontal, sin(_pitch) * _distance, cos(_yaw) * horizontal)
	camera.position = _camera_target + offset
	camera.look_at(_camera_target)
	# Keep the framing target in the middle of the unobstructed viewport.
	var view := get_viewport().get_visible_rect().size
	if view.y > 0.0:
		var sidebar := minf(_panel.get_global_rect().end.x, view.x * 0.65)
		camera.h_offset = -sidebar / view.y * _distance * tan(deg_to_rad(camera.fov * 0.5))

func _pick_placement(screen: Vector2) -> String:
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	var closest := camera.far
	var picked := ""
	for mesh_node: MeshInstance3D in displayed_parcel.find_children("*", "MeshInstance3D", true, false):
		if not mesh_node.mesh or not mesh_node.is_visible_in_tree():
			continue
		var from := mesh_node.to_local(origin)
		var to := mesh_node.to_local(origin + ray * closest)
		if mesh_node.get_aabb().intersects_segment(from, to) == null:
			continue
		var placement: Node = mesh_node
		while placement != displayed_parcel and not placement.has_meta("asset_id"):
			placement = placement.get_parent()
		if placement == displayed_parcel:
			continue
		var faces := mesh_node.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, faces[index], faces[index + 1], faces[index + 2])
			if hit == null:
				continue
			var distance := origin.distance_to(mesh_node.to_global(hit))
			if distance < closest:
				closest = distance
				picked = String(displayed_parcel.get_path_to(placement))
	return picked

func _start_object_drag(screen: Vector2) -> bool:
	var path := _pick_placement(screen)
	if path.is_empty() or not draft.select(path):
		return false
	_refresh_placement_picker()
	_update_draft_status()
	var selected := displayed_parcel.get_node(NodePath(path)) as Node3D
	var hit: Variant = _drag_plane_hit(screen, selected.global_position.y)
	if hit != null:
		_dragged = selected
		_drag_origin = selected.transform
		_drag_start = hit
		_drag_screen_start = screen
		_drag_moved = false
		_drag_yaw = float(draft.placement().rotation_degrees[1])
	return true

func _drag_plane_hit(screen: Vector2, height: float) -> Variant:
	return Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func _preview_object_drag(screen: Vector2) -> void:
	if not _drag_moved and screen.distance_squared_to(_drag_screen_start) < 16.0:
		return
	var parent := _dragged.get_parent() as Node3D
	var hit: Variant = _drag_plane_hit(screen, _drag_start.y)
	if hit == null:
		return
	_drag_moved = true
	var offset := parent.to_local(hit) - parent.to_local(_drag_start)
	var target := _drag_origin.origin + Vector3(snappedf(offset.x, 0.5), 0.0, snappedf(offset.z, 0.5))
	if target != _dragged.position:
		_dragged.position = target
		_show_drag_preview()
	if _placement_hint.visible:
		_position_placement_hint(screen)

func _show_drag_preview() -> void:
	_placement_issue = _validate_visual_pose(_dragged)
	_tint_placement_ghost(_dragged)
	_placement_hint.text = "Visual placement clear" if _placement_issue.is_empty() else _placement_issue
	_placement_hint.modulate = _ghost_color()
	_placement_hint.show()
	_position_placement_hint(get_viewport().get_mouse_position())
	draft_status.text = "Visual draft · %s\n%s · yaw %.1f°\n%s · Esc to cancel" % [draft.selected_path, _dragged.position, _drag_yaw, "Clear · release to place" if _placement_issue.is_empty() else _placement_issue]
	_update_selection_marker()

func _tint_placement_ghost(object: Node3D) -> void:
	if _ghost_material == null:
		_ghost_material = StandardMaterial3D.new()
		_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for mesh_node: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
			_drag_materials[mesh_node] = mesh_node.material_override
			mesh_node.material_override = _ghost_material
	_ghost_material.albedo_color = Color(_ghost_color(), 0.55)

func _position_placement_hint(screen: Vector2) -> void:
	var view := get_viewport().get_visible_rect()
	_placement_hint.position = (screen + Vector2(16, 18)).min(view.end - _placement_hint.get_minimum_size() - Vector2.ONE * 8.0)

func _ghost_color() -> Color:
	return Color("61caff") if _placement_issue.is_empty() else Color("ff626b")

func _finish_object_drag(commit: bool) -> void:
	if not is_instance_valid(_dragged):
		return
	var position := _dragged.position
	var issue := _placement_issue
	_clear_placement_ghost()
	_dragged.transform = _drag_origin
	_dragged = null
	if commit and issue.is_empty() and draft.place_selected(position, _drag_yaw):
		_apply_draft("Placed visual draft object.")
	else:
		_update_draft_status("Placement rejected · " + issue if commit and not issue.is_empty() else "")

func _clear_placement_ghost() -> void:
	for mesh_node in _drag_materials:
		if is_instance_valid(mesh_node):
			mesh_node.material_override = _drag_materials[mesh_node]
	_drag_materials.clear()
	_ghost_material = null
	_placement_issue = ""
	_placement_hint.hide()

func _input(event: InputEvent) -> void:
	if is_instance_valid(_dragged):
		if event is InputEventMouseMotion:
			_preview_object_drag(event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var on_canvas := not _panel.get_global_rect().has_point(event.position) and get_viewport().get_visible_rect().has_point(event.position)
			if on_canvas: _preview_object_drag(event.position)
			_finish_object_drag(on_canvas)
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_finish_object_drag(false)
			elif event.keycode == KEY_R:
				_drag_yaw = snappedf(_drag_yaw + (-90.0 if event.shift_pressed else 90.0), 90.0)
				_dragged.rotation_degrees.y = _drag_yaw
				_show_drag_preview()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	# GUI controls can consume a release after a stroke began in the scene.
	if (field_panel != null and field_panel.start_cell != null and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _panel.get_global_rect().has_point(event.position)):
		field_panel.cancel_drag()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_pending_asset):
		if event is InputEventMouseMotion and not _orbiting and not _panning:
			_update_library_placement(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_update_library_placement(event.position)
			if _pending_asset.visible and _placement_issue.is_empty():
				_finish_library_placement(true)
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_finish_library_placement(false)
				_update_draft_status("Canceled fixed placement.")
			elif event.keycode == KEY_R:
				_pending_asset.rotation_degrees.y += -90.0 if event.shift_pressed else 90.0
				_update_library_placement(get_viewport().get_mouse_position())
			get_viewport().set_input_as_handled()
			return
	if task_tabs.current_tab == Task.POPULATION_FIELDS and field_panel.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		if task_tabs.current_tab == Task.MOVE_OBJECTS and event.keycode == KEY_R and not event.echo and not event.ctrl_pressed:
			_rotate_selected(-1 if event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_Z:
			if task_tabs.current_tab == Task.POPULATION_FIELDS: field_panel.undo()
			elif task_tabs.current_tab == Task.MOVE_OBJECTS: _undo()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_Y:
			if task_tabs.current_tab == Task.POPULATION_FIELDS: field_panel.redo()
			elif task_tabs.current_tab == Task.MOVE_OBJECTS: _redo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_frame()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if task_tabs.current_tab == Task.MOVE_OBJECTS and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _start_object_drag(event.position): get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(3.0, _distance * 0.88)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(140.0, _distance / 0.88)
			_update_camera()
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch + event.relative.y * 0.008, deg_to_rad(8.0), deg_to_rad(89.0))
			_update_camera()
		elif _panning:
			var pan_scale := _distance * 0.0018
			var right := camera.global_basis.x
			var forward := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
			_camera_target += right * -event.relative.x * pan_scale + forward * -event.relative.y * pan_scale
			_update_camera()
