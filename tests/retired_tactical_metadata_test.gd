extends SceneTree
var failures := 0

func _initialize() -> void:
	for key in ["deck_rect", "ladder_bottom", "ladder_top", "grid_origin", "faction"]:
		var old := Node3D.new()
		old.name = "ArchivedRecipe"
		old.set_meta(key, Vector3i.ZERO)
		var data := TacticalMapBuilder.generate(16, 16, 1, 0)
		AuthoredSceneMapCompiler.compile(old, data, 1)
		check(data.generation_errors.size() == 1 and data.generation_errors[0].code == "RETIRED_ABSOLUTE_TACTICAL_METADATA", "An old absolute-coordinate export rejects explicitly: " + key)
		check(data.cells.size() == 256 and data.traversal_links.is_empty(), "Rejected metadata cannot partially stamp an incorrect map")
		old.free()
	var current := Node3D.new()
	current.set_meta("deck_local_rect", Rect2i(0, 0, 2, 2))
	current.set_meta("deck_level", 3)
	current.set_meta("ladder_local_bottom", Vector3i.ZERO)
	current.set_meta("ladder_local_top", Vector3i(0, 3, 0))
	var valid := TacticalMapBuilder.generate(16, 16, 1, 0)
	AuthoredSceneMapCompiler.compile(current, valid, 1)
	check(valid.generation_errors.is_empty() and valid.traversal_links.size() == 1 and valid.get_cell(Vector3i(8, 3, 8)) != null, "Supported local decks and connections still compile")
	current.free()
	print("Retired tactical metadata: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
