extends SceneTree
class Editor extends "res://tools/map_editor.gd":
	func _ready(): pass
var failures := 0
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	if value: print("PASS: ",label)
	else: failures += 1; push_error(label)
func press(node: Node, text: String) -> bool:
	if node is Button and node.text == text: node.pressed.emit(); return true
	for child in node.get_children():
		if press(child,text): return true
	return false
func capture(name: String):
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/"+name+".png")
func run():
	root.size = Vector2i(1280,720)
	var editor := Editor.new(); editor.layout_preset = &"plot_authoring"; root.add_child(editor)
	editor._build_ui(); editor._rebuild()
	var ui: PlotAuthoringController = editor.plot_authoring
	check(ui.panel.visible and not editor.chunk_authoring.panel.visible,"workspace switches inside same editor")
	press(ui.panel,"Open selected plot")
	check(ui.assessment.ok and not ui.source.data.slots.is_empty(),"saved plot browser opens proof")
	await process_frame
	await process_frame
	check(not ui.edit_settings.visible,"advanced layout settings start collapsed")
	check(ui.build_button.get_global_rect().end.y < root.size.y and ui.play_map_button.get_global_rect().end.y < root.size.y,"build/save/play are visible without scrolling at 720p")
	check(ui.save_map_button.disabled and ui.play_map_button.disabled,"unbuilt plans cannot save or launch as accepted maps")
	var original := ui.source.copy()
	ui.source.data.fixed_streets[0].chunk_id = "missing_ui_test_chunk"
	ui.source.data.fixed_streets[0].revision = ""
	var before_block := ui.signature()
	ui.build_map()
	check(ui.feedback.text.contains("missing_ui_test_chunk") and ui.feedback.text.contains("Chunk Authoring"),"blocked build names the chunk and next action")
	check(ui.signature() == before_block,"blocked automatic pinning leaves source untouched")
	ui.source = original; ui.changed()
	ui.selected_group = "fixed_streets"; ui.selected_id = ui.source.data.fixed_streets[0].id; ui.build_form()
	var move_before := ui.signature()
	var history_before := ui.undo_stack.size()
	var original_street: Dictionary = ui.selected().duplicate(true)
	press(ui.panel,"Move selected (M)")
	check(ui.moving and is_instance_valid(ui.move_ghost),"move creates a visible preview")
	var destination := Vector2i(original_street.origin[0]+2,original_street.origin[1]+2)
	var screen := editor.camera.unproject_position(ui.offset()+Vector3(destination.x,0,destination.y))
	var motion := InputEventMouseMotion.new(); motion.position = screen
	editor._unhandled_input(motion)
	check(ui.move_origin == destination and ui.signature() == move_before and ui.undo_stack.size() == history_before,"mouse follows snapped grid without source edits or undo noise")
	await capture("plot-mouse-preview")
	ui.set_move_origin(Vector2i(-100,-100)); ui.confirm_move()
	check(ui.moving and ui.signature() == move_before,"out-of-bounds preview cannot commit")
	var escape := InputEventKey.new(); escape.pressed = true; escape.keycode = KEY_ESCAPE; ui.shortcut(escape)
	check(not ui.moving and not is_instance_valid(ui.move_ghost) and ui.signature() == move_before,"Escape cancels without changing the layout")
	ui.begin_move(); ui.move_pending(screen); ui.click(screen)
	check(not ui.moving and ui.selected().origin == [destination.x,destination.y] and ui.undo_stack.size() == history_before+1,"click confirms one undoable move")
	var expected_street := original_street.duplicate(true); expected_street.origin = [destination.x,destination.y]
	check(ChunkPublicationCompiler.canonical(ui.selected()) == ChunkPublicationCompiler.canonical(expected_street),"move preserves identity, revision and connection metadata")
	ui.undo(); check(ui.signature() == move_before,"undo restores moved street exactly")
	ui.redo(); check(ui.selected().origin == [destination.x,destination.y],"redo reapplies mouse placement")
	ui.undo()
	ui.selected_group = "reservations"; ui.selected_id = ui.source.data.reservations[0].id; ui.build_form()
	var old_cells: Array = ui.selected().cells.duplicate(true)
	var old_access: Dictionary = ui.selected().duplicate(true)
	ui.begin_move(); ui.set_move_origin(ui.move_bounds.position+Vector2i(1,0)); ui.confirm_move()
	var shifted: Array = old_cells.duplicate(true)
	for cell in shifted: cell[0] += 1
	old_access.cells = shifted
	check(ChunkPublicationCompiler.canonical(ui.selected()) == ChunkPublicationCompiler.canonical(old_access),"mouse move preserves access shape and reference identity")
	ui.undo()
	await capture("plot-ui-through-street")
	ui.request_open("yard_service_access.json")
	check(ui.assessment.ok,"second plot opens")
	ui.mission.select(1); ui.mission.item_selected.emit(1)
	check(ui.source.data.active_mission == "terminal" and ui.assessment.ok,"active mission picker updates requirements")
	await capture("plot-ui-service-access")
	ui.selected_group = "slots"; ui.selected_id = ui.source.data.slots[0].id; ui.build_form()
	var before := ui.signature()
	ui.fields.Width.value = 1; press(ui.panel,"Apply selected fields")
	check(not ui.assessment.ok and ui.feedback.text.contains("needs"),"impossible slot gives actionable feedback")
	press(ui.panel,"Undo"); check(ui.signature() == before,"undo restores plot and reference identities")
	press(ui.panel,"Redo"); check(not ui.assessment.ok,"redo restores invalid editable draft")
	ui.directory = "res://artifacts/t09-editor-drafts"; ui.filename.text = "edited_plot"; press(ui.panel,"Save draft")
	check(ui.signature() == ui.saved_signature,"invalid but well-formed plot saves")
	ui.request_open("edited_plot.json"); check(not ui.assessment.ok and ui.selected_id.is_empty(),"saved invalid draft reopens")
	var stable := ui.signature()
	GenerationJsonStore.write(ui.directory.path_join("broken.json"),"{}")
	ui.request_open("broken.json"); check(ui.signature() == stable,"rejected load preserves current state")
	press(ui.panel,"+ Access"); check(ui.selected_group == "reservations","access authoring needs no code")
	ui.fields.X.value = 10; ui.fields.Z.value = 20; ui.fields.Width.value = 4; press(ui.panel,"Apply selected fields")
	check(ui.selected().cells.size() == 4,"rectangle controls author reservation cells")
	press(ui.panel,"+ Mission"); check(ui.selected_group == "mission_requirements","mission authoring needs no code")
	press(ui.panel,"+ Slot"); check(ui.selected_group == "slots","slot authoring needs no code")
	press(ui.panel,"Set port obligation"); check(ui.selected().obligations.size() == 1,"port/frontage authoring uses actual content ports")
	ui.request_open("edited_plot.json"); check(ui.discard.visible,"unsaved switch requests discard")
	ui.discard.confirmed.emit(); check(ui.signature() == stable,"confirmed discard opens saved source")
	ui.selected_group = "reservations"; ui.selected_id = ui.source.data.reservations[0].id; ui.build_form()
	var removed_id := ui.selected_id
	press(ui.panel,"Delete selected")
	check(ui.assessment.errors.any(func(e): return e.message.contains(removed_id)),"deleting referenced access reports required-reference loss")
	press(ui.panel,"+ Access"); check(ui.selected_id != removed_id,"replacement cannot silently capture dangling reference")
	ui.plot_identity.text = "authored_in_editor"; press(ui.panel,"Apply plot ID / boundary")
	check(ui.source.data.plot_id == "authored_in_editor","source ID is authorable without code")
	print("T09 editor failures: ",failures)
	editor.free(); quit(1 if failures else 0)
