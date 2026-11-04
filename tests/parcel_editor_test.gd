extends SceneTree

const EditorScene = preload("res://tools/parcel_editor/parcel_editor.tscn")
const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
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
	editor.free()
	var menu: Control = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu.find_child("ParcelEditorButton", true, false) != null, "Match Setup exposes the Parcel Editor without a hidden debug flag")
	menu.free()
	print("Parcel Editor: %d failure(s)" % failures)
	quit(1 if failures else 0)
