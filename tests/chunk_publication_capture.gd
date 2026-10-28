extends SceneTree
## Explicit rendered proof capture. Never records owner approval or registration.
class Editor extends "res://tools/map_editor.gd":
	func _ready(): pass
var failures := 0
func _initialize(): run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless":
		print("SKIP: publication captures require a graphics run")
		quit()
		return
	root.size = Vector2i(1440,1000)
	var editor := Editor.new()
	editor.layout_preset = &"chunk_authoring"
	root.add_child(editor)
	editor._build_ui()
	var ui: ChunkAuthoringController = editor.chunk_authoring
	ui.directory = ui.PILOT_DIRECTORY
	for name in ["warehouse_frontage","loading_yard","service_yard","alley_courtyard","street_straight","street_t","street_cross"]:
		ui.session.load_draft(ui.directory,name)
		editor._rebuild()
		ui.publication.validate_saved()
		if ui.publication.validated_hash != ChunkPublicationCompiler.source_hash(ui.session.source):
			push_error(name+": "+ui.publication.message.text)
			failures+=1
			continue
		await ui.publication.capture_views()
		var result := ui.publication.library.inspect(ui.publication.revision)
		if not result.ok or not ui.publication.library.evidence_error(result.record).is_empty():
			push_error(name+": capture failed "+ui.publication.message.text)
			failures+=1
		else:
			print("CAPTURED ",name," revision=",ui.publication.revision)
			for item in result.record.evidence: print("  ",item.view,": ",item.path)
			if not result.record.review.is_empty() or result.record.registered: push_error("Pilot must remain unapproved"); failures+=1
	ui.tabs.current_tab = 3
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/t07-publication-controls.png")
	ui.publication.show_review()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/t07-owner-review-dialog.png")
	print("Publication capture failures: ",failures)
	editor.free()
	quit(1 if failures else 0)
