extends SceneTree
## Graphics-only evidence using the isolated registration fixture, never owner approval.
class Editor extends "res://tools/map_editor.gd":
	func _ready(): pass
func _initialize(): run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless": push_error("Graphics required"); quit(1); return
	var location := GenerationJsonStore.parse(FileAccess.get_file_as_string("res://artifacts/t10-fixture-location.json"))
	if not location.ok: push_error("Run plot_composition_test first"); quit(1); return
	root.size = Vector2i(1440,1000)
	var editor := Editor.new(); editor.layout_preset = &"plot_authoring"; root.add_child(editor); editor._build_ui(); editor._update_composer_visibility()
	for name in ["through_street_industrial","yard_service_access"]:
		var source: EnvironmentPlotSource = EnvironmentPlotSource.load_file("res://content/plots/"+name+".json").source
		for street in source.data.fixed_streets: street.revision = location.value.revisions[street.chunk_id]
		var context := EnvironmentResolutionContext.new(); context.chunk_library = ChunkPublicationLibrary.new(location.value.directory.path_join("library"))
		var result := AuthoredPlotComposer.compose(source,17 if name.begins_with("through") else 42,context)
		if not result.ok: push_error(str(result)); editor.free(); quit(1); return
		if is_instance_valid(editor.content): editor.content.free()
		editor.content = Node3D.new(); editor.add_child(editor.content)
		editor.preview_map_size = result.data.map_size; editor.displayed_data = result.data
		editor.plot_authoring.source = source
		editor.plot_authoring.marker(Rect2i(Vector2i.ZERO,result.data.map_size),Color("303a3f"),"",-0.06)
		GeneratedTerrainPresenter.build(result.data,editor.content,1.0)
		editor._frame_camera(); editor._set_camera_view(0.65,0.8)
		editor.plot_authoring.panel.hide()
		editor.status.text = "T10 COMPOSITION PROOF · %s\nISOLATED AUTOMATED TEST LIBRARY — NOT OWNER APPROVED\nExact chunk revisions + bounded population; shared tactical compiler and renderer." % name
		await create_timer(1).timeout; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/t10-"+name+".png")
		print("Captured ",name)
	editor.free(); quit()
