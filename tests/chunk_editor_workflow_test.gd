extends SceneTree
class Editor extends "res://tools/map_editor.gd":
	func _ready(): pass
var failures := 0
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	if value: print("PASS: ", label)
	else: failures += 1; push_error(label)
func press(node: Node, text: String) -> bool:
	if node is Button and node.text == text:
		node.grab_focus()
		node.pressed.emit()
		return true
	for child in node.get_children():
		if press(child, text): return true
	return false
func choose(ui: ChunkAuthoringController, key: String):
	ui.search.text = key
	ui.search.text_changed.emit(key)
	for index in ui.gallery.item_count:
		if ui.gallery.get_item_metadata(index) == key:
			ui.gallery.select(index)
			ui.gallery.item_selected.emit(index)
			return
	check(false, "gallery entry " + key)
func capture(name: String):
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_root().path_join(name + ".png"))
func run():
	root.size = Vector2i(1440, 1000)
	var editor := Editor.new()
	editor.layout_preset = &"chunk_authoring"
	root.add_child(editor)
	editor._build_ui()
	editor._rebuild()
	var ui: ChunkAuthoringController = editor.chunk_authoring
	ui.directory = output_root().path_join("t06-ui-drafts")
	await process_frame
	ui.search.text = "no such content"
	press(ui.panel, "Browse saved chunks")
	check(ui.search.text.is_empty() and ui.gallery.item_count >= 7, "saved chunk browser clears stale search and exposes industrial examples")
	await capture("chunk-browser-saved")
	ui.search.text = "loading yard"
	ui.search.text_changed.emit(ui.search.text)
	check(ui.gallery.item_count == 1 and ui.gallery.get_item_metadata(0) == "pilot:loading_yard", "natural name search finds saved example without a prefix")
	ui.gallery.item_selected.emit(0)
	check(not ui.armed and ui.session.source.data.instances.is_empty(), "browsing a saved chunk previews without starting placement")
	ui.search.text = "missing chunk"
	ui.search.text_changed.emit(ui.search.text)
	check(ui.selected_gallery.is_empty() and ui.gallery_summary.text.begins_with("No matches"), "empty search clears hidden selection and explains recovery")
	ui.gallery_filter.select(0)
	choose(ui, "component:cargo_container")
	press(ui.panel, "Place selected content (then click grid)")
	ui.click(editor.camera.unproject_position(ui.world_offset() + Vector3(4, 0, 5)))
	check(ui.session.source.data.instances.size() == 1, "gallery + viewport click constructs component")
	var original := ui.session.selected_id
	press(ui.panel, "Duplicate")
	check(ui.armed and is_instance_valid(ui.ghost) and ui.session.source.data.instances.size() == 1, "duplicate is a visible non-mutating preview")
	var motion := InputEventMouseMotion.new()
	motion.position = editor.camera.unproject_position(ui.world_offset() + Vector3(8, 0, 5))
	editor._unhandled_input(motion)
	check(ui.pending.origin == [8, 5] and ui.session.source.data.instances.size() == 1, "mouse moves preview without editing source")
	press(ui.panel, "Rotate right")
	press(ui.panel, "Raise")
	check(ui.pending.rotation == 1 and ui.pending.elevation == 1 and ui.session.source.data.instances[0].rotation == 0, "preview rotation/elevation never changes source")
	await capture("t06-mouse-preview")
	press(ui.panel, "Cancel (Esc)")
	check(not ui.armed and ui.session.source.data.instances.size() == 1, "cancel duplicate preserves source")
	press(ui.panel, "Duplicate")
	ui.click(editor.camera.unproject_position(ui.world_offset() + Vector3(4, 0, 5)))
	var duplicate := ui.session.selected_id
	check(duplicate != original and ui.session.source.data.instances.size() == 2, "UI duplicate assigns new stable identity")
	check(not ui.notices.is_empty() and ui.feedback.text.contains(duplicate) and ui.feedback.text.contains("overlap"), "invalid feedback identifies duplicate and overlap")
	check(root.gui_get_focus_owner() == null, "duplicate button releases focus to construction shortcuts")
	press(ui.panel, "Undo")
	check(ui.session.source.data.instances.size() == 1, "positioned duplicate is one undo command")
	press(ui.panel, "Redo")
	check(ui.session.selected_id == duplicate, "redo restores the positioned copy identity")
	var arrow := InputEventKey.new()
	arrow.keycode = KEY_RIGHT
	arrow.pressed = true
	root.push_input(arrow)
	await process_frame
	check(ui.session.selected().origin == [5, 5], "real arrow input after duplicate moves copy, not button focus")
	check(ui.session.source.data.instances[0].origin == [4, 5], "keyboard move leaves original unchanged")
	press(ui.panel, "Undo")
	await capture("t06-invalid-draft")
	ui.numbers.X.value = 12
	press(ui.panel, "Apply snapped transform")
	check(ui.session.selected().origin == [12, 5], "UI snapped move persists")
	press(ui.panel, "Undo")
	check(ui.session.selected_id == duplicate and ui.session.selected().origin == [4, 5], "UI undo transform retains identity")
	press(ui.panel, "Redo")
	var before_move := ui.session.signature()
	press(ui.panel, "Move")
	check(not ui.objects[duplicate].visible, "move hides original behind ghost")
	ui.move_pending(editor.camera.unproject_position(ui.world_offset() + Vector3(14, 0, 5)))
	press(ui.panel, "Cancel (Esc)")
	check(ui.session.signature() == before_move and ui.objects[duplicate].visible, "cancel move restores original without edits")
	press(ui.panel, "Move")
	ui.click(editor.camera.unproject_position(ui.world_offset() + Vector3(14, 0, 5)))
	check(ui.session.selected_id == duplicate and ui.session.selected().origin == [14, 5], "mouse move keeps stable identity")
	press(ui.panel, "Undo")
	ui.filename.text = "Manual yard"
	press(ui.panel, "Save draft")
	check(not ui.session.dirty(), "UI saves named draft")
	var saved := ui.session.signature()
	press(ui.panel, "Open name")
	check(saved == ui.session.signature(), "UI reopens exact named source")
	ui.port_id.text = "entry"
	ui.port_role.text = "pedestrian"
	ui.port_profile.text = "walkway_1"
	ui.numbers.Start.value = 4
	press(ui.panel, "Set port")
	check(ui.session.source.data.ports.size() == 1, "UI authors boundary port")
	choose(ui, "asset:factory_kit/structure-wall")
	press(ui.panel, "Place selected content (then click grid)")
	ui.click(editor.camera.unproject_position(ui.world_offset() + Vector3(9, 0, 13)))
	check(ui.session.source.data.instances.size() == 3, "raw calibrated asset placement")
	press(ui.panel, "Save draft")
	await capture("t06-chunk-authoring")
	ui.tabs.current_tab = 2
	await capture("t06-construction-controls")
	choose(ui, "draft:Manual yard")
	check(ui.preview_root.get_child_count() == 3, "saved draft gallery preview")
	press(ui.panel, "Place selected content (then click grid)")
	ui.click(editor.camera.unproject_position(ui.world_offset() + Vector3(1, 0, 1)))
	check(ui.session.source.data.instances.size() == 6, "saved draft inserts independent copy")
	press(ui.panel, "Undo")
	check(ui.session.source.data.instances.size() == 3, "entire copied draft undoes together")
	ui.session.set_bounds(21, 20, 12)
	var unsaved := ui.session.signature()
	choose(ui, "pilot:loading_yard")
	press(ui.panel, "Open selected draft for editing")
	check(ui.discard_dialog.visible and ui.session.signature() == unsaved, "opening dirty draft asks before changing source")
	await capture("chunk-discard-confirmation")
	ui.discard_dialog.canceled.emit()
	check(ui.session.signature() == unsaved and ui.requested_document.is_empty(), "keep editing preserves source and clears pending open")
	ui.filename.text = "does_not_exist"
	press(ui.panel, "Open name")
	ui.discard_dialog.confirmed.emit()
	check(ui.session.signature() == unsaved, "confirmed invalid load still preserves unsaved source")
	choose(ui, "pilot:loading_yard")
	press(ui.panel, "Open selected draft for editing")
	ui.discard_dialog.confirmed.emit()
	check(ui.session.filename == "loading_yard" and not ui.session.dirty(), "confirmed discard opens captured destination")
	ui.session.set_bounds(21, 12, 5)
	press(ui.panel, "New")
	check(ui.discard_dialog.visible, "new draft shares discard confirmation")
	ui.discard_dialog.confirmed.emit()
	check(ui.session.source.data.instances.is_empty(), "confirmed new starts empty draft")
	print("T06 UI failures: ", failures)
	editor.free()
	quit(1 if failures else 0)

func output_root() -> String:
	var output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	return "res://artifacts" if output.is_empty() else output
