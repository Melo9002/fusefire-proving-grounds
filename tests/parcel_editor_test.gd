extends SceneTree

const EditorScene = preload("res://tools/parcel_editor/parcel_editor.tscn")
const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Definition = preload("res://systems/generation/authored_parcel_definition.gd")
const DraftSession = preload("res://tools/parcel_editor/parcel_draft_session.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var editor: Node3D = EditorScene.instantiate()
	root.add_child(editor)
	await process_frame
	check(editor.parcel_picker.item_count == Catalog.all().size(), "Parcel Editor lists every registered parcel")
	check(editor.select_parcel(Catalog.MAINTENANCE_GALLERY_A), "Parcel Editor opens the maintenance gallery by stable ID")
	check(editor.displayed_parcel != null and editor.displayed_parcel_id == Catalog.MAINTENANCE_GALLERY_A, "Selected registered scene is instantiated")
	check(editor.validation_label.text.begins_with("VALID"), "Registered parcel validation is visible")
	check(editor.tactical_overlay.get_child_count() >= 4, "Maintenance gallery exposes solid, deck, and access contracts independently of its meshes")
	check(editor.select_parcel(Catalog.LOADING_YARD_A), "Parcel Editor opens a populated loading parcel")
	var population_nodes: Array = editor.displayed_parcel.find_children("*", "Node3D", true, false).filter(func(node): return node.has_meta("population_socket_id"))
	check(not population_nodes.is_empty(), "Loading parcel exposes authored population nodes")
	editor.set_population_visible(false)
	check(population_nodes.all(func(node): return not (node as Node3D).visible), "Population toggle can isolate the fixed parcel assembly")
	var draft = DraftSession.new()
	var test_definition = Definition.new(&"parcel_editor_test", "Test draft", &"test", 1, Vector2i(16, 32), null)
	draft.begin(test_definition, editor.displayed_parcel)
	check(not draft.placements.is_empty(), "Draft starts from stable imported-asset scene paths")
	var selected: Dictionary = draft.placement()
	var selected_node := editor.displayed_parcel.get_node(NodePath(String(selected.path))) as Node3D
	var original_position := selected_node.position
	check(draft.translate_selected(Vector3(0.5, 0, -0.5)), "Selected visual placement accepts a snapped edit")
	check(draft.apply(editor.displayed_parcel).is_empty() and selected_node.position.is_equal_approx(original_position + Vector3(0.5, 0, -0.5)), "Draft transform applies to the preview scene")
	check(draft.undo() and draft.apply(editor.displayed_parcel).is_empty() and selected_node.position.is_equal_approx(original_position), "Undo restores the authored visual transform")
	check(draft.redo() and draft.apply(editor.displayed_parcel).is_empty() and selected_node.position.is_equal_approx(original_position + Vector3(0.5, 0, -0.5)), "Redo reapplies the visual transform")
	var test_draft_path := "res://.godot/parcel_editor_test.draft.json"
	check(draft.save_to(test_draft_path), "Visual draft saves outside registered runtime content")
	var loaded = DraftSession.new()
	check(loaded.load_from(test_draft_path, test_definition, editor.displayed_parcel), "Saved draft reloads against its exact parcel revision")
	var loaded_selected: Dictionary = loaded.placement(String(selected.path))
	check(String(loaded_selected.get("asset_id", "")) == String(selected.asset_id) and Vector3(float(loaded_selected.position[0]), float(loaded_selected.position[1]), float(loaded_selected.position[2])).is_equal_approx(original_position + Vector3(0.5, 0, -0.5)), "Draft save/load preserves stable identity and transform")
	var stale_definition = Definition.new(&"parcel_editor_test", "Test draft", &"test", 2, Vector2i(16, 32), null)
	check(not loaded.load_from(test_draft_path, stale_definition, editor.displayed_parcel) and loaded.last_error.contains("STALE_PARCEL_REVISION"), "A changed source parcel revision invalidates its visual draft")
	if FileAccess.file_exists(test_draft_path):
		DirAccess.remove_absolute(test_draft_path)
	editor.free()
	var menu: Control = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu.find_child("ParcelEditorButton", true, false) != null, "Match Setup exposes the Parcel Editor without a hidden debug flag")
	menu.free()
	print("Parcel Editor: %d failure(s)" % failures)
	quit(1 if failures else 0)
