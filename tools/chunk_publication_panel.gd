class_name ChunkPublicationPanel
extends RefCounted
var _editor: WeakRef
var editor: ChunkAuthoringController:
	get: return _editor.get_ref()
var library := ChunkPublicationLibrary.new()
var revision := ""
var validated_hash := ""
var message: Label
var busy := false
var review_dialog: ConfirmationDialog
var reviewer: LineEdit
var affirmation: CheckBox
func _init(controller: ChunkAuthoringController) -> void: _editor = weakref(controller)
func build(parent: Node) -> void:
	editor._label(parent, "PUBLISH A CHUNK\nValidate → Capture → Owner review → Register")
	editor._label(parent, "Saving a draft never approves it. Each gate belongs to an exact immutable revision.")
	editor._button(parent, "Add ground across chunk bounds", func(): editor.changed(editor.session.add_ground()))
	editor._button(parent, "Refresh dependency pins (new review required)", refresh_pins)
	editor._button(parent, "1. Validate saved draft", validate_saved)
	editor._button(parent, "2. Capture three review views", capture_views)
	editor._button(parent, "3. Owner review / approve…", show_review)
	editor._button(parent, "4. Register approved revision", register_revision)
	editor._button(parent, "Revoke review / unregister", revoke)
	message = editor._label(parent, "Draft — not generator eligible")
func source_changed() -> void:
	if message == null: return
	if revision.is_empty(): message.text = "Draft — not generator eligible"
	elif ChunkPublicationCompiler.source_hash(editor.session.source) != validated_hash: message.text = "Edited draft — prior validation/review does not apply. Save and validate a new revision."
func refresh_pins() -> void:
	if not ready_for_action(false): return
	var candidate := editor.session.source.copy()
	candidate.data.dependencies = []
	var result := ChunkPublicationCompiler.compile(candidate)
	candidate.data.dependencies = result.dependencies
	editor.changed(editor.session._commit(candidate, editor.session.selected_id, "Refresh dependency pins"))
	message.text = "Captured current dependency pins; this grants no approval. Save and validate."
func ready_for_action(require_revision := true) -> bool:
	if busy: return false
	if editor.armed:
		message.text = "Place or cancel the preview first."
		return false
	if require_revision and (revision.is_empty() or validated_hash != ChunkPublicationCompiler.source_hash(editor.session.source) or editor.session.dirty()):
		message.text = "Save and validate this exact draft first."
		return false
	return true
func validate_saved() -> void:
	if not ready_for_action(false): return
	if editor.session.dirty():
		message.text = "Save the draft before validation."
		return
	var result := library.validate_and_store(editor.session.source, ChunkSourceStore.path_for(editor.directory, editor.session.filename))
	if not result.ok:
		message.text = result.error
		for error in result.get("errors", []): message.text += "\n%s: %s" % [error.get("field", error.get("reference", "source")), error.message]
		return
	revision = result.revision
	validated_hash = ChunkPublicationCompiler.source_hash(editor.session.source)
	var record: Dictionary = library._index().revisions[revision]
	if library.review_error(record, revision).is_empty():
		message.text = ("Registered revision " if record.registered else "Owner-reviewed; ready to register: ") + revision.left(12)
	elif library.evidence_error(record).is_empty():
		message.text = "Valid revision %s already has captures. Open Owner review; no recapture needed." % revision.left(12)
	else: message.text = "Technically valid revision %s. Capture review views next; no owner approval yet." % revision.left(12)
func capture_views() -> void:
	if not ready_for_action(): return
	var checked := library.inspect(revision)
	if not checked.ok: message.text = checked.error; return
	if not checked.record.review.is_empty(): message.text = "Evidence is sealed by review. Revoke review to recapture."; return
	busy = true
	var host := editor.host
	var ui_root := editor.panel.get_parent() as Control
	var saved_transform: Transform3D = host.camera.transform
	var orbit = host.orbit
	var old_focus: Vector3 = orbit.focus
	var old_distance: float = orbit.distance
	var old_azimuth: float = orbit.azimuth
	var old_altitude: float = orbit.altitude
	ui_root.hide()
	var capture_root := Node3D.new()
	host.add_child(capture_root)
	ModularEnvironmentPresenter.build_chunk_snapshot(checked.compiled, capture_root)
	host.content.hide()
	var grid := host.content.get_node_or_null("TacticalGrid") as Node3D
	if grid != null: grid.hide()
	for object in editor.objects.values(): host._set_selection_outline(object, false)
	var views := [["overview",0.65,0.55],["opposite",3.79,0.55],["overhead",0.0,1.50]]
	var capture_error := ""
	for view in views:
		orbit.frame(EnvironmentAssetPlacement.mesh_bounds(capture_root))
		orbit.set_view(view[1], view[2])
		await host.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var result := library.capture_evidence(revision, host.get_viewport().get_texture().get_image(), view[0])
		if not result.ok: capture_error = result.error; break
	orbit.focus = old_focus
	orbit.distance = old_distance
	orbit.azimuth = old_azimuth
	orbit.altitude = old_altitude
	host.camera.transform = saved_transform
	if grid != null: grid.show()
	host.content.show()
	capture_root.free()
	ui_root.show()
	busy = false
	editor.sync_selection()
	message.text = "Three review captures saved for %s. Open Owner review to inspect them." % revision.left(12) if capture_error.is_empty() else capture_error
func show_review() -> void:
	if not ready_for_action(): return
	var checked := library.inspect(revision)
	if not checked.ok: message.text = checked.error; return
	var error := library.evidence_error(checked.record)
	if not error.is_empty(): message.text = error; return
	if is_instance_valid(review_dialog): review_dialog.free()
	review_dialog = ConfirmationDialog.new()
	review_dialog.title = "Owner visual approval — " + revision.left(12)
	review_dialog.ok_button_text = "Approve this exact revision"
	review_dialog.min_size = Vector2i(900, 600)
	var column := VBoxContainer.new()
	review_dialog.add_child(column)
	var instructions := editor._label(column, "Inspect orientation, completeness, access and street seams.\nTechnical checks do not establish visual quality.")
	instructions.autowrap_mode = TextServer.AUTOWRAP_OFF
	var images := editor._row(column)
	for evidence in checked.record.evidence:
		var group := VBoxContainer.new()
		images.add_child(group)
		var view_label := editor._label(group, evidence.view)
		view_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(Image.load_from_file(evidence.path))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(280, 330)
		group.add_child(picture)
		var capture_path := str(evidence.path)
		editor._button(group, "Open full size", func(): OS.shell_open(ProjectSettings.globalize_path(capture_path)))
	reviewer = editor._text(column, "Your name (project owner / authorized human reviewer)")
	affirmation = CheckBox.new()
	affirmation.text = "I personally inspected these captures and approve this exact chunk revision."
	column.add_child(affirmation)
	review_dialog.get_ok_button().disabled = true
	affirmation.toggled.connect(func(_value): review_dialog.get_ok_button().disabled = not affirmation.button_pressed or reviewer.text.strip_edges().is_empty())
	reviewer.text_changed.connect(func(_value): review_dialog.get_ok_button().disabled = not affirmation.button_pressed or reviewer.text.strip_edges().is_empty())
	var reviewed_revision := revision
	review_dialog.confirmed.connect(func():
		if not ready_for_action() or revision != reviewed_revision: return
		var result := library.approve_by_owner(reviewed_revision, reviewer.text, affirmation.button_pressed)
		message.text = "Owner review recorded. Registration is still an explicit separate action." if result.ok else result.error)
	editor.host.add_child(review_dialog)
	review_dialog.popup_centered(Vector2i(960, 600))
func register_revision() -> void:
	if not ready_for_action(): return
	var result := library.register(revision)
	message.text = "Registered exact revision %s for generation." % revision.left(12) if result.ok else result.error
func revoke() -> void:
	if revision.is_empty(): return
	var result := library.revoke_review(revision)
	message.text = "Review revoked; revision is not eligible for generation." if result.ok else result.error
