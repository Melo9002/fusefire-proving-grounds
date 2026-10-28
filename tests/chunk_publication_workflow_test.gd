extends SceneTree
class Editor extends "res://tools/map_editor.gd":
	func _ready(): pass
var failures := 0
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	if value: print("PASS: ",label)
	else: failures+=1; push_error(label)
func press(node: Node, text: String) -> bool:
	if node is Button and node.text == text: node.pressed.emit(); return true
	for child in node.get_children():
		if press(child,text): return true
	return false
func run():
	root.size = Vector2i(1440,1000)
	var editor := Editor.new()
	editor.layout_preset = &"chunk_authoring"
	root.add_child(editor)
	editor._build_ui()
	editor._rebuild()
	var ui: ChunkAuthoringController = editor.chunk_authoring
	var output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	if output.is_empty(): output = "res://artifacts"
	ui.directory = output.path_join("t07-ui-" + str(Time.get_ticks_usec()))
	ui.publication.library = ChunkPublicationLibrary.new(ui.directory.path_join("library"))
	ui.numbers.W.value = 4
	ui.numbers.D.value = 4
	ui.numbers.H.value = 4
	press(ui.panel,"Apply chunk bounds")
	ui.search.text = "construction-cone"
	ui.populate_gallery()
	for index in ui.gallery.item_count:
		if ui.gallery.get_item_metadata(index)=="asset:city_kit_roads/construction-cone": ui.gallery.item_selected.emit(index); break
	ui.click(editor.camera.unproject_position(ui.world_offset()+Vector3(0,0,1)))
	press(ui.panel,"Declare visual-only decoration")
	press(ui.panel,"Add ground across chunk bounds")
	ui.port_id.text = "access"
	ui.port_role.text = "pedestrian"
	ui.port_profile.text = "walkway_2"
	ui.numbers.Width.value = 2
	ui.numbers.Start.value = 1
	press(ui.panel,"Set port")
	ui.filename.text = "Manual proof"
	press(ui.panel,"Save draft")
	press(ui.panel,"Open name")
	press(ui.panel,"1. Validate saved draft")
	check(not ui.publication.revision.is_empty(),"UI-created raw-asset chunk saves/reopens/validates without a code recipe")
	if ui.publication.revision.is_empty(): print(ui.publication.message.text); editor.free(); quit(1); return
	press(ui.panel,"4. Register approved revision")
	check(ui.publication.library.eligible().is_empty(),"UI registration cannot bypass human gate")
	if DisplayServer.get_name() != "headless": await ui.publication.capture_views()
	else:
		var picture := Image.create(32,32,false,Image.FORMAT_RGBA8)
		picture.fill(Color.DARK_CYAN)
		for view in ["overview","opposite","overhead"]: ui.publication.library.capture_evidence(ui.publication.revision,picture,view)
	ui.publication.show_review()
	await process_frame
	await process_frame
	check(ui.publication.review_dialog.get_ok_button().disabled,"owner approval starts unchecked and disabled")
	check(ui.publication.review_dialog.size.y <= root.size.y and ui.publication.review_dialog.size.x <= root.size.x,"review dialog and approval controls fit window")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("t07-owner-review-dialog.png"))
	# Exercise actual confirmation handler only inside this isolated test library.
	ui.publication.reviewer.text = "AUTOMATED UI TEST FIXTURE ONLY"
	ui.publication.reviewer.text_changed.emit(ui.publication.reviewer.text)
	ui.publication.affirmation.button_pressed = true
	check(not ui.publication.review_dialog.get_ok_button().disabled,"explicit fixture name and affirmation enable confirmation")
	ui.publication.review_dialog.confirmed.emit()
	press(ui.panel,"4. Register approved revision")
	check(ui.publication.library.eligible().size()==1,"test-only owner confirmation enables separate registration action")
	ui.instances.item_selected.emit(0)
	press(ui.panel,"Rotate right")
	check(int(ui.session.selected().rotation)==1,"select and rotate the reopened instance")
	press(ui.panel,"Save draft")
	check(ui.publication.library.eligible().is_empty(),"UI edits create an ineligible draft")
	print("Publication UI failures: ",failures)
	editor.free()
	quit(1 if failures else 0)
