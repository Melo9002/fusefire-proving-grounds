class_name PlotAuthoringController
extends RefCounted
## Plot authoring inside the existing editor/camera; no runtime selection or packing.
var host: Node3D
var source := EnvironmentPlotSource.new()
var directory := "res://content/plots"
var saved_signature := ""
var library := {}
var assessment := {}
var composed := {}
var composition_context: EnvironmentResolutionContext
var compose_seed: SpinBox
var compose_budget: SpinBox
var panel: ScrollContainer
var column: VBoxContainer
var plot_identity: LineEdit
var filename: LineEdit
var saved_picker: OptionButton
var mission: OptionButton
var records: ItemList
var form: VBoxContainer
var validation_details: Label
var feedback: Label
var guide: Label
var edit_settings: VBoxContainer
var settings_toggle: CheckButton
var build_button: Button
var save_map_button: Button
var play_map_button: Button
var fields := {}
var selected_group := ""
var selected_id := ""
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var moving := false
var move_origin := Vector2i.ZERO
var move_bounds := Rect2i()
var move_ghost: Node3D
var move_tint: StandardMaterial3D
var move_actions: HBoxContainer
var discard: ConfirmationDialog
var pending_open := ""
var port_picker: OptionButton
var target_picker: OptionButton
var obligations: ItemList
func _init(editor: Node3D): host = editor
func signature() -> String: return ChunkPublicationCompiler.canonical(source.data)
func label(parent: Node, text: String) -> Label:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item
func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.pressed.connect(func(): item.release_focus(); action.call())
	parent.add_child(item)
	return item
func row(parent: Node) -> HBoxContainer:
	var item := HBoxContainer.new(); parent.add_child(item); return item
func text_field(parent: Node, key: String, value: String) -> LineEdit:
	label(parent,key)
	var item := LineEdit.new(); item.text = value; parent.add_child(item); fields[key] = item; return item
func number(parent: Node, key: String, value: int, minimum := 0, maximum := 256) -> SpinBox:
	var caption := label(parent,key)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	var item := SpinBox.new(); item.min_value = minimum; item.max_value = maximum; item.step = 1; item.value = value; parent.add_child(item); fields[key] = item; return item
func n(key: String) -> int: return int(fields[key].value)
func build_ui(parent: Control) -> void:
	panel = ScrollContainer.new(); parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -370; panel.offset_right = -10; panel.offset_top = 145; panel.offset_bottom = -10
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var background := StyleBoxFlat.new(); background.bg_color = Color("172631"); panel.add_theme_stylebox_override("panel",background)
	column = VBoxContainer.new(); column.custom_minimum_size.x = 340; column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.add_child(column)
	label(column,"BUILD A BATTLEFIELD")
	guide = label(column,"1. Open a layout below.\n2. Build map to fill its spaces.\n3. Save or play the result.")
	saved_picker = OptionButton.new(); column.add_child(saved_picker)
	button(column,"Open selected plot",func():
		if saved_picker.selected >= 0: request_open(str(saved_picker.get_item_metadata(saved_picker.selected))))
	button(column,"Open saved battlefield",choose_composed)
	var options := row(column)
	mission = OptionButton.new(); mission.add_item("Eliminate"); mission.add_item("Terminal"); options.add_child(mission)
	mission.tooltip_text = "Choose the mission before building the map."
	mission.item_selected.connect(func(index): checkpoint(); source.data.active_mission = "eliminate" if index == 0 else "terminal"; changed())
	compose_seed = number(options,"Seed",17,0,2147483647)
	compose_seed.tooltip_text = "The same seed and content produce the same arrangement. Change it, then Build map."
	build_button = button(column,"Build map",build_map)
	build_button.custom_minimum_size.y = 42
	build_button.tooltip_text = "Fill the layout with approved chunks. Unset streets use their registered revision; existing pins stay unchanged. This does not approve content."
	var actions := row(column)
	save_map_button = button(actions,"Save map",save_composed)
	play_map_button = button(actions,"Play map",play_composed)
	save_map_button.disabled = true; play_map_button.disabled = true
	save_map_button.tooltip_text = "Build a valid map first. Saves the exact arrangement."
	play_map_button.tooltip_text = "Build a valid map first. Starts the selected mission."
	button(actions,"Back to plan",changed)
	button(column,"Move selected (M)",begin_move)
	move_actions = row(column)
	button(move_actions,"Place here (Enter)",confirm_move)
	button(move_actions,"Cancel (Esc)",cancel_move)
	move_actions.hide()
	label(column,"Save name")
	filename = LineEdit.new(); filename.text = "new_plot"; column.add_child(filename)
	feedback = label(column,"")
	settings_toggle = CheckButton.new(); settings_toggle.text = "Edit layout / advanced settings"; column.add_child(settings_toggle)
	edit_settings = VBoxContainer.new(); column.add_child(edit_settings); edit_settings.hide()
	settings_toggle.toggled.connect(func(enabled): edit_settings.visible = enabled)
	label(edit_settings,"Blue areas hold chunks. Green strips keep access clear. Pink cells mark mission positions. Click an area to edit it.")
	var files := row(edit_settings); button(files,"New",func(): request_open("__new__")); button(files,"Save draft",save)
	var history := row(edit_settings); button(history,"Undo",undo); button(history,"Redo",redo); button(history,"Refresh library",refresh_library)
	plot_identity = LineEdit.new(); plot_identity.text = source.data.plot_id; plot_identity.tooltip_text = "Persistent plot source ID"; edit_settings.add_child(plot_identity)
	var bounds := row(edit_settings); number(bounds,"Map W",60,1); number(bounds,"Map D",50,1)
	button(edit_settings,"Apply plot ID / boundary",func(): checkpoint(); source.data.plot_id = plot_identity.text.strip_edges(); source.data.map_size = [n("Map W"),n("Map D")]; changed())
	records = ItemList.new(); records.custom_minimum_size.y = 110; edit_settings.add_child(records); records.item_selected.connect(select_record)
	var add := row(edit_settings); button(add,"+ Street",func(): add_record("fixed_streets")); button(add,"+ Slot",func(): add_record("slots")); button(add,"+ Access",func(): add_record("reservations")); button(add,"+ Mission",func(): add_record("mission_requirements"))
	var edits := row(edit_settings); button(edits,"Move on grid",begin_move); button(edits,"Delete selected",delete_selected)
	form = VBoxContainer.new(); edit_settings.add_child(form)
	button(edit_settings,"Check plot feasibility",validate)
	validation_details = label(edit_settings,"")
	compose_budget = number(edit_settings,"Budget",64,0,128)
	button(edit_settings,"Pin registered streets",pin_streets).tooltip_text = "Explicitly update all streets to their current approved revision. Build map only fills missing pins."
	discard = ConfirmationDialog.new(); discard.title = "Discard unsaved plot changes?"; discard.dialog_text = "Open another plot without saving these edits? Saved files remain intact."; discard.ok_button_text = "Discard and open"; discard.cancel_button_text = "Keep editing"; panel.add_child(discard)
	discard.confirmed.connect(open_pending); discard.canceled.connect(func(): pending_open = "")
	populate_files(); panel.hide()
func populate_files() -> void:
	saved_picker.clear()
	if not DirAccess.dir_exists_absolute(directory): return
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".json"): saved_picker.add_item(file.get_basename().capitalize()); saved_picker.set_item_metadata(saved_picker.item_count-1,file)
func checkpoint() -> void: undo_stack.append(source.data.duplicate(true)); redo_stack.clear()
func undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(source.data.duplicate(true)); source.data = undo_stack.pop_back(); changed()
func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(source.data.duplicate(true)); source.data = redo_stack.pop_back(); changed()
func request_open(name: String) -> void:
	pending_open = name
	if signature() != saved_signature and (not undo_stack.is_empty() or not source.data.slots.is_empty()): discard.popup_centered(Vector2i(480,160))
	else: open_pending()
func open_pending() -> void:
	var requested := pending_open; pending_open = ""; discard.hide()
	if requested.is_empty(): return
	if requested.begins_with("battlefield:"): load_composed(requested.trim_prefix("battlefield:")); return
	if requested == "__new__": source = EnvironmentPlotSource.new(); filename.text = "new_plot"
	else:
		var path := ChunkSourceStore.path_for(directory,requested)
		var loaded := EnvironmentPlotSource.load_file(path)
		if not loaded.ok: feedback.text = loaded.error; return
		source = loaded.source; filename.text = requested.get_basename()
		for index in saved_picker.item_count:
			if str(saved_picker.get_item_metadata(index)).get_basename() == requested.get_basename(): saved_picker.select(index)
	saved_signature = signature(); undo_stack.clear(); redo_stack.clear(); selected_id = ""; moving = false; changed(); host._frame_camera()
func save() -> void:
	if moving: feedback.text = "Place or cancel the moving piece before saving."; return
	var path := ChunkSourceStore.path_for(directory,filename.text)
	if path.is_empty(): feedback.text = "Choose a valid plot filename"; return
	var error := source.save_file(path)
	if not error.is_empty(): feedback.text = error; return
	saved_signature = signature(); populate_files(); feedback.text = "Saved plot draft. Feasibility and publication remain separate."
func refresh_library() -> void:
	library = PlotFeasibility.library_catalog().entries; changed()
func selected() -> Dictionary:
	if selected_group.is_empty(): return {}
	for record in source.data[selected_group]:
		if record.id == selected_id: return record
	return {}
func add_record(group: String) -> void:
	checkpoint()
	var used := {}
	for state in undo_stack + redo_stack + [source.data]:
		for records_group in ["fixed_streets","slots","reservations","mission_requirements"]:
			for entry in state[records_group]:
				used[entry.id] = true
				if entry.has("access_ref"): used[entry.access_ref] = true
				for obligation in entry.get("obligations",[]): used[obligation.target_ref] = true
	var suffix := 1
	var prefix: String = {"fixed_streets":"street","slots":"slot","reservations":"access","mission_requirements":"mission"}[group]
	while used.has("%s_%d" % [prefix,suffix]): suffix += 1
	var id := "%s_%d" % [prefix,suffix]
	var record: Dictionary
	match group:
		"fixed_streets": record = {"id":id,"chunk_id":"street_straight","revision":"","origin":[0,0],"rotation":0,"exits":[]}
		"slots": record = {"id":id,"bounds":[0,0,20,20],"candidates":["service_yard"],"rotations":[0],"required":true,"obligations":[]}
		"reservations": record = {"id":id,"role":"pedestrian_access","cells":[[0,0]],"scope":"whole_column","elevation":0,"height":3}
		_: record = {"id":id,"mission":"all","kind":"deployment","faction":0,"capacity":2,"cells":[[0,0],[1,0]],"access_ref":""}
	source.data[group].append(record); selected_group = group; selected_id = id; changed()
func delete_selected() -> void:
	if selected().is_empty(): return
	checkpoint(); source.data[selected_group] = source.data[selected_group].filter(func(r): return r.id != selected_id); selected_id = ""; changed()
func select_record(index: int) -> void:
	cancel_move()
	settings_toggle.button_pressed = true
	var key: Array = records.get_item_metadata(index); selected_group = key[0]; selected_id = key[1]; records.release_focus(); moving = false; build_form()
func choices(parent: Node, key: String, options: Array, current: String) -> OptionButton:
	label(parent,key)
	var picker := OptionButton.new(); parent.add_child(picker); fields[key] = picker
	for value in options:
		picker.add_item(str(value)); picker.set_item_metadata(picker.item_count-1,str(value))
		if str(value) == current: picker.select(picker.item_count-1)
	return picker
func pick(key: String) -> String:
	var picker: OptionButton = fields[key]
	return str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""
func cell_bounds(cells: Array) -> Rect2i:
	if cells.is_empty(): return Rect2i(0,0,1,1)
	var rect := Rect2i(Vector2i(cells[0][0],cells[0][1]),Vector2i.ONE)
	for cell in cells: rect = rect.merge(Rect2i(Vector2i(cell[0],cell[1]),Vector2i.ONE))
	return rect
func build_form() -> void:
	for child in form.get_children():
		form.remove_child(child)
		child.queue_free()
	for key in fields.keys():
		if key not in ["Map W","Map D","Seed","Budget"]: fields.erase(key)
	var record := selected()
	if record.is_empty(): return
	label(form,record.id + " · " + selected_group.replace("_"," "))
	var bounds: Rect2i
	if selected_group == "fixed_streets": bounds = Rect2i(Vector2i(record.origin[0],record.origin[1]),Vector2i.ONE)
	elif selected_group == "slots": bounds = PlotFeasibility.rect(record.bounds)
	else: bounds = cell_bounds(record.cells)
	var position_row := row(form); number(position_row,"X",bounds.position.x); number(position_row,"Z",bounds.position.y)
	if selected_group != "fixed_streets":
		if selected_group in ["reservations","mission_requirements"]: label(form,"Moving preserves cell shape; resizing replaces it with a rectangle.")
		var size_row := row(form); number(size_row,"Width",bounds.size.x,1); number(size_row,"Depth",bounds.size.y,1)
	match selected_group:
		"fixed_streets":
			choices(form,"Chunk",library.keys(),record.chunk_id); number(form,"Turn",record.rotation,0,3)
			text_field(form,"Boundary exit port IDs (comma separated)",", ".join(record.exits))
			label(form,"Street chunk owns the complete footprint, including sidewalk.")
			button(form,"Pin registered revision",func():
				if library.has(record.chunk_id) and library[record.chunk_id].eligible: checkpoint(); record.revision = library[record.chunk_id].revision; changed()
				else: feedback.text = "This street has no approved registered revision. Authoring can continue.")
		"slots":
			text_field(form,"Candidate chunk IDs",", ".join(record.candidates)); choices(form,"Add candidate",library.keys(),"")
			button(form,"Add candidate to slot",func():
				var id := pick("Add candidate")
				if not id.is_empty() and id not in record.candidates: checkpoint(); record.candidates.append(id); changed())
			text_field(form,"Allowed quarter turns",", ".join(record.rotations.map(func(v): return str(int(v)))))
			choices(form,"Required",["yes","no"],"yes" if record.required else "no")
			label(form,"Chunk anchors at the slot origin. Extra space remains free; no scaling.")
		"reservations":
			choices(form,"Role",EnvironmentSpatialReservationLedger.ROLES,record.role)
			choices(form,"Scope",["whole_column","floor"],record.scope); number(form,"Clearance height",record.height,1)
		"mission_requirements":
			choices(form,"Mission",["all","eliminate","terminal"],record.mission); choices(form,"Kind",["deployment","objective"],record.kind)
			number(form,"Faction",record.faction,-1,2); number(form,"Capacity",record.capacity,1)
			choices(form,"Access reservation",source.data.reservations.map(func(r): return r.id),record.access_ref)
	button(form,"Apply selected fields",apply_fields)
	if selected_group == "slots": build_obligations(record)
func strings(value: String) -> Array:
	var values: Array = []
	for part in value.split(","):
		if not part.strip_edges().is_empty(): values.append(part.strip_edges())
	return values
func edited_cells(existing: Array) -> Array:
	var old := cell_bounds(existing)
	if old.size == Vector2i(n("Width"),n("Depth")):
		var delta := Vector2i(n("X"),n("Z"))-old.position
		return existing.map(func(c): return [int(c[0])+delta.x,int(c[1])+delta.y])
	return rectangle_cells()
func rectangle_cells() -> Array:
	var values: Array = []
	for x in range(n("X"),n("X")+n("Width")):
		for z in range(n("Z"),n("Z")+n("Depth")): values.append([x,z])
	return values
func apply_fields() -> void:
	var record := selected()
	if record.is_empty(): return
	var rotations: Array = []
	if selected_group == "slots":
		for value in strings(fields["Allowed quarter turns"].text):
			if not value.is_valid_int() or int(value) not in [0,1,2,3]: feedback.text = "Quarter turns must be 0, 1, 2 or 3"; return
			rotations.append(int(value))
	checkpoint()
	match selected_group:
		"fixed_streets":
			if record.chunk_id != pick("Chunk"): record.revision = ""
			record.chunk_id = pick("Chunk"); record.origin = [n("X"),n("Z")]; record.rotation = n("Turn"); record.exits = strings(fields["Boundary exit port IDs (comma separated)"].text)
		"slots": record.bounds = [n("X"),n("Z"),n("Width"),n("Depth")]; record.candidates = strings(fields["Candidate chunk IDs"].text); record.rotations = rotations; record.required = pick("Required") == "yes"
		"reservations": record.cells = edited_cells(record.cells); record.role = pick("Role"); record.scope = pick("Scope"); record.height = n("Clearance height")
		"mission_requirements": record.cells = edited_cells(record.cells); record.mission = pick("Mission"); record.kind = pick("Kind"); record.faction = n("Faction"); record.capacity = n("Capacity"); record.access_ref = pick("Access reservation")
	changed()
func build_obligations(record: Dictionary) -> void:
	label(form,"Port and frontage obligations")
	obligations = ItemList.new(); obligations.custom_minimum_size.y = 60; form.add_child(obligations)
	for obligation in record.obligations: obligations.add_item("%s → %s" % [obligation.port_id,obligation.target_ref])
	port_picker = OptionButton.new(); form.add_child(port_picker)
	var seen := {}
	for id in record.candidates:
		if not library.has(id): continue
		for port in library[id].source.data.ports:
			if seen.has(port.id): continue
			seen[port.id] = true; port_picker.add_item(port.id + " / " + port.profile); port_picker.set_item_metadata(port_picker.item_count-1,port)
	target_picker = OptionButton.new(); form.add_child(target_picker)
	for street in source.data.fixed_streets: target_picker.add_item("Frontage: " + street.id); target_picker.set_item_metadata(target_picker.item_count-1,{"kind":"frontage","id":street.id})
	for access in source.data.reservations: target_picker.add_item("Access: " + access.id); target_picker.set_item_metadata(target_picker.item_count-1,{"kind":"access","id":access.id})
	button(form,"Set port obligation",func():
		if port_picker.selected < 0 or target_picker.selected < 0: return
		var port: Dictionary = port_picker.get_item_metadata(port_picker.selected); var target: Dictionary = target_picker.get_item_metadata(target_picker.selected)
		checkpoint(); record.obligations = record.obligations.filter(func(o): return o.port_id != port.id); record.obligations.append({"port_id":port.id,"profile":port.profile,"kind":target.kind,"target_ref":target.id}); changed())
	button(form,"Remove selected obligation",func():
		if obligations.get_selected_items().is_empty(): return
		checkpoint(); record.obligations.remove_at(obligations.get_selected_items()[0]); changed())
func changed() -> void:
	cancel_move()
	composed = {}
	save_map_button.disabled = true; play_map_button.disabled = true
	guide.text = "This is the plan, not the finished map.\nClick Build map to place buildings and props."
	records.clear()
	for group in ["fixed_streets","slots","reservations","mission_requirements"]:
		for record in source.data[group]:
			records.add_item(record.id + " · " + group.replace("_"," ")); records.set_item_metadata(records.item_count-1,[group,record.id])
			if record.id == selected_id: records.select(records.item_count-1)
	plot_identity.text = source.data.plot_id
	fields["Map W"].value = source.data.map_size[0]; fields["Map D"].value = source.data.map_size[1]
	mission.select(0 if source.data.active_mission == "eliminate" else 1)
	build_form(); rebuild(); validate()
func validate() -> void:
	if library.is_empty(): library = PlotFeasibility.library_catalog().entries
	assessment = PlotFeasibility.assess(source,library)
	var lines: Array[String] = ["The layout fits. Click Build map to check its approved chunks." if assessment.ok and not assessment.generation_ready else ("Ready. Click Build map." if assessment.generation_ready else "The layout needs attention:")]
	for item in assessment.errors.slice(0,2): lines.append("%s: %s" % [item.field,item.message])
	if assessment.errors.size() > 2: lines.append("%d additional issues; fix these and recheck." % (assessment.errors.size()-2))
	var details: Array[String] = []
	for issue in assessment.errors + assessment.warnings: details.append("%s: %s" % [issue.field,issue.message])
	validation_details.text = "\n".join(details)
	feedback.text = "\n".join(lines)
	host.status.text = "PLOT DRAFT · %s%s · %s\nBlue = building spaces · green = clear access · pink = mission positions.\nThis is a plan. Use Build map on the right to see the finished arrangement." % [source.data.plot_id," *unsaved" if signature()!=saved_signature else "",source.data.active_mission]
func offset() -> Vector3: return Vector3(-float(source.data.map_size[0])*0.5+0.5,0,-float(source.data.map_size[1])*0.5+0.5)
func marker(bounds: Rect2i, color: Color, title: String, height := 0.14) -> void:
	var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(bounds.size.x,0.05,bounds.size.y); mesh.mesh = box
	mesh.position = offset()+Vector3(bounds.position.x+(bounds.size.x-1)*0.5,height,bounds.position.y+(bounds.size.y-1)*0.5)
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if color.a == 1.0 else BaseMaterial3D.TRANSPARENCY_ALPHA; material.no_depth_test = color.a < 1.0; material.render_priority = 1 if color.a < 1.0 else 0; material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mesh.material_override = material; host.content.add_child(mesh)
	if not title.is_empty():
		var tag := Label3D.new(); tag.text = title; tag.font_size = 48; tag.pixel_size = 0.025; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tag.no_depth_test = true; tag.render_priority = 2; tag.position = mesh.position+Vector3.UP*0.5; host.content.add_child(tag)
func rebuild() -> void:
	if library.is_empty(): library = PlotFeasibility.library_catalog().entries
	if is_instance_valid(host.content): host.content.free()
	host.content = Node3D.new(); host.content.name = "PlotPreview"; host.add_child(host.content)
	host.preview_map_size = Vector2i(source.data.map_size[0],source.data.map_size[1]); host.displayed_data = null; host.inspection_module = null
	marker(Rect2i(Vector2i.ZERO,host.preview_map_size),Color(0.15,0.19,0.21,1),"",-0.06)
	host._add_grid_overlay(host.content,host.preview_map_size,1.0)
	for street in source.data.fixed_streets:
		if not library.has(street.chunk_id) or not PlotFeasibility.available(library[street.chunk_id]): continue
		var entry: Dictionary = library[street.chunk_id]
		var size := PlotFeasibility.extent(entry.source,street.rotation)
		var node := Node3D.new(); host.content.add_child(node); node.position = offset()+Vector3(street.origin[0]+(size.x-1)*0.5,0.2,street.origin[1]+(size.y-1)*0.5); node.rotation.y = -int(street.rotation)*PI*0.5
		ModularEnvironmentPresenter.build_chunk_snapshot(entry.compiled,node)
	for slot in source.data.slots: marker(PlotFeasibility.rect(slot.bounds),Color(0.1,0.7,0.9,0.3),slot.id+"\n"+" / ".join(slot.candidates))
	for reservation in source.data.reservations:
		for cell in reservation.cells: marker(Rect2i(Vector2i(cell[0],cell[1]),Vector2i.ONE),Color(0.2,0.9,0.3,0.65),"")
	for requirement in source.data.mission_requirements:
		if requirement.mission not in ["all",source.data.active_mission]: continue
		for cell in requirement.cells: marker(Rect2i(Vector2i(cell[0],cell[1]),Vector2i.ONE),Color(0.9,0.2,0.8,0.9),"",0.22)
func click(screen: Vector2) -> void:
	var hit = Plane(Vector3.UP,0).intersects_ray(host.camera.project_ray_origin(screen),host.camera.project_ray_normal(screen))
	if hit == null: return
	var local: Vector3 = hit-offset(); var at := Vector2i(roundi(local.x),roundi(local.z))
	if moving:
		set_move_origin(at); confirm_move(); return
	for i in records.item_count:
		var key: Array = records.get_item_metadata(i)
		for record in source.data[key[0]]:
			if record.id != key[1]: continue
			var bounds: Rect2i
			if key[0] == "slots": bounds = PlotFeasibility.rect(record.bounds)
			elif key[0] == "fixed_streets":
				if not library.has(record.chunk_id): continue
				bounds = Rect2i(Vector2i(record.origin[0],record.origin[1]),PlotFeasibility.extent(library[record.chunk_id].source,record.rotation))
			else: bounds = cell_bounds(record.cells)
			if bounds.has_point(at): records.select(i); select_record(i); return
func shortcut(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE: cancel_move()
	elif event.keycode == KEY_M: begin_move()
	elif event.keycode == KEY_ENTER and moving: confirm_move()
	elif event.ctrl_pressed and event.keycode == KEY_Z: redo() if event.shift_pressed else undo()
	elif event.ctrl_pressed and event.keycode == KEY_S: save()
	elif event.keycode == KEY_F: host._frame_camera()

func pin_streets() -> void:
	var approved := ChunkPublicationLibrary.new().eligible()
	var by_id := {}
	for entry in approved: by_id[entry.id] = entry.revision
	for street in source.data.fixed_streets:
		if not by_id.has(street.chunk_id): feedback.text = "Street %s has no eligible registered revision. Validate, review and register it in Chunk Authoring first." % street.chunk_id; return
	checkpoint()
	for street in source.data.fixed_streets: street.revision = by_id[street.chunk_id]
	refresh_library()
func build_map() -> void:
	if moving: feedback.text = "Place or cancel the moving piece before building."; return
	# Pin only missing revisions, from the existing approved registry. Never approve
	# content or silently upgrade an already pinned source while simplifying the UI.
	var missing: Array = source.data.fixed_streets.filter(func(street): return str(street.revision).is_empty())
	if not missing.is_empty():
		var by_id := {}
		for entry in ChunkPublicationLibrary.new().eligible(): by_id[entry.id] = entry.revision
		for street in missing:
			if not by_id.has(street.chunk_id):
				feedback.text = "Cannot build yet: '%s' needs an approved chunk.\nSwitch to Author - Chunk Authoring, open that chunk, then validate, review and register it. Return here and click Build map again." % street.chunk_id
				panel.scroll_vertical = 0
				return
		checkpoint()
		for street in missing: street.revision = by_id[street.chunk_id]
		changed()
	compose()

func compose() -> void:
	save_map_button.disabled = true; play_map_button.disabled = true
	composition_context = EnvironmentResolutionContext.new()
	composed = AuthoredPlotComposer.compose(source,int(compose_seed.value),composition_context,int(compose_budget.value))
	if not composed.ok:
		var messages: Array[String] = []
		for error in composed.errors: messages.append(error.message)
		for diagnostic in composed.get("diagnostics",[]).slice(0,4): messages.append(str(diagnostic.get("message",diagnostic)))
		feedback.text = "\n".join(messages)
		return
	show_composed()

func show_composed() -> void:
	save_map_button.disabled = false; play_map_button.disabled = false
	guide.text = "Map built. Save it or start playing.\nBack to plan lets you change the layout."
	settings_toggle.button_pressed = false
	panel.scroll_vertical = 0
	if is_instance_valid(host.content): host.content.free()
	host.content = Node3D.new(); host.add_child(host.content)
	host.displayed_data = composed.data
	marker(Rect2i(Vector2i.ZERO,composed.data.map_size),Color("303a3f"),"",-0.06)
	GeneratedTerrainPresenter.build(composed.data,host.content,1.0)
	host._frame_camera()
	host.status.text = "COMPOSED PLOT · %s · seed %d · %d search attempts\nExact registered chunks + declared population. Back to plan returns to editing." % [source.data.plot_id,int(compose_seed.value),composed.get("attempts",0)]
	feedback.text = "Map ready. Save map keeps this exact arrangement."
func save_composed() -> void:
	if not composed.get("ok",false): feedback.text = "Compose a valid registered battlefield first."; return
	var path := ChunkSourceStore.path_for("res://tools/map_editor/layouts",filename.text+"_composed_"+str(int(composed.document.provenance.generation_seed)))
	if path.is_empty(): feedback.text = "Choose a valid filename first."; return
	var error := MapEditorLayoutStore.save(composed.document,path)
	feedback.text = "Saved accepted battlefield: "+path if error.is_empty() else error

func play_composed() -> void:
	if not composed.get("ok",false): feedback.text = "Compose a valid registered battlefield first."; return
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.AUTHORED_PLOT
	config.map_size = composed.document.map_size()
	config.battle_seed = int(composed.document.provenance.generation_seed)
	config.player_count = 2
	config.enemy_count = 2
	var kind := MissionObjectiveDefinition.Kind.INTERACT_TERMINAL if source.data.active_mission == "terminal" else MissionObjectiveDefinition.Kind.ELIMINATE
	config.mission = MissionCatalog.create_mission(kind,config.enemy_count,false)
	var prepared := BattlefieldRuntimePreparation.compile_document(composed.document,config)
	if not prepared.ok: feedback.text = "Cannot play: " + str(prepared.errors[0].message); return
	var battle := host.BATTLE_SCENE.instantiate() as BattleLevel
	battle.configure_layout_document(config,prepared.document)
	host.get_tree().root.add_child(battle)
	host.get_tree().current_scene = battle
	host.queue_free()

func choose_composed() -> void:
	var picker := FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.access = FileDialog.ACCESS_RESOURCES
	picker.current_dir = "res://tools/map_editor/layouts"
	picker.filters = PackedStringArray(["*.json ; Saved battlefield"])
	panel.add_child(picker)
	picker.file_selected.connect(func(path): request_open("battlefield:"+path); picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.75)
func load_composed(path: String, context: EnvironmentResolutionContext = null) -> void:
	if context == null: context = EnvironmentResolutionContext.new()
	var loaded := MapEditorLayoutStore.load({},path,&"",context)
	if not loaded.ok: feedback.text = loaded.get("error","Cannot open battlefield"); return
	if not loaded.document.provenance.has("composition"): feedback.text = "This file is not an authored plot battlefield."; return
	var compiled := BattlefieldLayoutDocumentCompiler.compile(loaded.document,1.0,2,context)
	if not compiled.ok: feedback.text = str(compiled.errors[0].message); return
	checkpoint()
	source = EnvironmentPlotSource.new()
	source.data = loaded.document.provenance.composition.plot.duplicate(true)
	selected_id = ""; selected_group = ""; moving = false
	compose_seed.value = int(loaded.document.provenance.generation_seed)
	changed()
	composed = compiled
	composition_context = context
	show_composed()
	feedback.text = "Opened exact saved choices. Back to plan edits its layout; build again to accept a new arrangement."

func begin_move() -> void:
	if composed.get("ok",false): feedback.text = "Use Back to plan before moving layout pieces."; return
	var record := selected()
	if record.is_empty(): feedback.text = "Click a road or blue area first, then Move selected (M)."; return
	cancel_move()
	if selected_group == "fixed_streets":
		if not library.has(record.chunk_id) or not PlotFeasibility.available(library[record.chunk_id]): feedback.text = "This street's chunk is unavailable; choose a valid chunk first."; return
		move_bounds = Rect2i(Vector2i(record.origin[0],record.origin[1]),PlotFeasibility.extent(library[record.chunk_id].source,record.rotation))
	elif selected_group == "slots": move_bounds = PlotFeasibility.rect(record.bounds)
	else: move_bounds = cell_bounds(record.cells)
	move_ghost = Node3D.new(); host.content.add_child(move_ghost)
	if selected_group == "fixed_streets":
		var street := Node3D.new(); move_ghost.add_child(street)
		street.position = Vector3((move_bounds.size.x-1)*0.5,0.2,(move_bounds.size.y-1)*0.5)
		street.rotation.y = -int(record.rotation)*PI*0.5
		ModularEnvironmentPresenter.build_chunk_snapshot(library[record.chunk_id].compiled,street)
	else:
		var marker_mesh := MeshInstance3D.new(); var box := BoxMesh.new()
		box.size = Vector3(move_bounds.size.x,0.12,move_bounds.size.y); marker_mesh.mesh = box
		marker_mesh.position = Vector3((move_bounds.size.x-1)*0.5,0.3,(move_bounds.size.y-1)*0.5); move_ghost.add_child(marker_mesh)
	move_tint = StandardMaterial3D.new(); move_tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	move_tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh in move_ghost.find_children("*","MeshInstance3D",true,false):
		mesh.material_override = move_tint
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moving = true; move_actions.show(); panel.scroll_vertical = 0
	set_move_origin(move_bounds.position)

func move_pending(screen: Vector2) -> void:
	if not moving: return
	var hit = Plane(Vector3.UP,0).intersects_ray(host.camera.project_ray_origin(screen),host.camera.project_ray_normal(screen))
	if hit == null: return
	var local: Vector3 = hit-offset()
	set_move_origin(Vector2i(roundi(local.x),roundi(local.z)))

func move_inside_map() -> bool:
	return Rect2i(Vector2i.ZERO,Vector2i(source.data.map_size[0],source.data.map_size[1])).encloses(Rect2i(move_origin,move_bounds.size))

func set_move_origin(at: Vector2i) -> void:
	move_origin = at
	move_ghost.position = offset()+Vector3(at.x,0,at.y)
	move_tint.albedo_color = Color(0.2,0.9,1.0,0.55) if move_inside_map() else Color(1.0,0.2,0.2,0.65)
	feedback.text = "Moving %s to %s. Click / Enter to place; Esc cancels. Access is checked after placement." % [selected_id,at] if move_inside_map() else "Outside the map. Move the preview back onto the grid or press Esc."

func confirm_move() -> void:
	if not moving or selected().is_empty(): return
	if not move_inside_map(): feedback.text = "Cannot place outside the map. Move back onto the grid or press Esc."; return
	var delta := move_origin-move_bounds.position
	if delta == Vector2i.ZERO: cancel_move(); return
	checkpoint()
	var record := selected()
	if selected_group == "fixed_streets": record.origin = [move_origin.x,move_origin.y]
	elif selected_group == "slots": record.bounds[0] = move_origin.x; record.bounds[1] = move_origin.y
	else:
		for cell in record.cells: cell[0] += delta.x; cell[1] += delta.y
	changed()

func cancel_move() -> void:
	var was_moving := moving
	moving = false
	if is_instance_valid(move_ghost): move_ghost.free()
	move_ghost = null
	if is_instance_valid(move_actions): move_actions.hide()
	if was_moving: feedback.text = "Move cancelled. The original position is unchanged."
