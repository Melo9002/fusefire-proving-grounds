extends SceneTree

const LayoutStore = preload("res://tools/map_editor_layout_store.gd")
var failures := 0

func _init() -> void:
	var catalog := IndustrialModuleCatalog.create()
	var layout := EnvironmentModuleLayout.new(&"author_fixture", 0)
	check(layout.try_add(catalog[&"paving_square"], EnvironmentModulePlacement.new(&"paving_square", Vector2i(2, 3)), Vector2i(20, 20)), "Ground module is valid in the fixture")
	check(layout.try_add(catalog[&"service_dumpster"], EnvironmentModulePlacement.new(&"service_dumpster", Vector2i(4, 5), 1, 0), Vector2i(20, 20)), "Occupant can share its cells with authored ground")
	var encoded := LayoutStore.encode(layout, Vector2i(20, 20))
	var decoded := LayoutStore.decode(encoded, catalog)
	check(decoded.ok, "A composed layout round-trips through human-readable JSON")
	if decoded.ok:
		check(decoded.map_size == Vector2i(20, 20), "Map dimensions persist")
		check(decoded.layout.signature() == layout.signature(), "Component IDs, origins, rotations, variants and elevations persist")
	var test_output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	var persistence_path := test_output.path_join("map_editor_layout_store_test.json") if not test_output.is_empty() else "user://map_editor_layout_store_test.json"
	var save_error := LayoutStore.save(layout, Vector2i(20, 20), persistence_path)
	check(save_error.is_empty(), "A composed layout saves to disk%s" % ("" if save_error.is_empty() else ": " + save_error))
	var persisted := LayoutStore.load(catalog, persistence_path)
	check(persisted.ok and persisted.layout.signature() == layout.signature(), "A saved composition reloads with the same placements")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(persistence_path))
	var starter := LayoutStore.load(catalog, LayoutStore.STARTER_PATH)
	check(starter.ok and starter.layout.placements.size() == 6, "The tracked starter composition remains loadable")
	var invalid := JSON.stringify({
		"schema_version": LayoutStore.SCHEMA_VERSION,
		"layout_id": "bad_fixture",
		"map_size": [10, 10],
		"placements": [{"component_id": "missing_component", "origin": [0, 0]}],
	})
	var rejected := LayoutStore.decode(invalid, catalog)
	check(not rejected.ok and "unknown component" in rejected.error, "Unknown component IDs fail explicitly")
	var overlap := JSON.stringify({
		"schema_version": LayoutStore.SCHEMA_VERSION,
		"layout_id": "overlap_fixture",
		"map_size": [20, 20],
		"placements": [
			{"component_id": "cargo_container", "origin": [4, 4]},
			{"component_id": "cargo_container", "origin": [4, 4]},
		],
	})
	var overlap_result := LayoutStore.decode(overlap, catalog)
	check(not overlap_result.ok and "overlaps" in overlap_result.error, "Invalid overlaps cannot be loaded as valid authored layouts")
	print("Map Editor layout store: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
