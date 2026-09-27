extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_authored_map()
	await _check_generated_map()
	print("Debug map inspector smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_authored_map() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1)
	root.add_child(level)
	await create_timer(0.2).timeout
	var tools := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	var inspector = tools._map_inspector
	check(inspector != null and inspector.is_inside_tree(), "F3 tools attach the modular map inspector")
	inspector.set_inspection_enabled(true)
	check(inspector.visible and inspector._zone_mesh.mesh != null, "Map inspection builds visible zone markers")
	check(inspector._link_mesh.mesh != null, "Map inspection builds traversal-link lines")
	var summary := "\n".join(inspector.get_map_summary())
	check(summary.contains("authored") and summary.contains("links 4"), "Authored metadata reports source and traversal count")
	var elevated: MapCellData
	for cell: MapCellData in level.battle_controller.grid_manager.map_data.cells.values():
		if cell.grid_position.y > 0:
			elevated = cell
			break
	check(elevated != null, "Authored inspection fixture contains elevation")
	inspector.hovered_cell = elevated
	var hover := "\n".join(inspector.get_hover_summary())
	check(hover.contains(str(elevated.grid_position)) and hover.contains("Elevation"), "Hover details identify an elevated cell")
	tools._set_map_zones_visible(false)
	tools._set_traversal_links_visible(false)
	check(not inspector._zone_mesh.visible and not inspector._link_mesh.visible, "F3 toggles independently hide zones and traversal links")
	level.queue_free()
	await process_frame

func _check_generated_map() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, true, 24680, 0, Vector2i(24, 20))
	root.add_child(level)
	await create_timer(0.25).timeout
	var tools := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	var inspector = tools._map_inspector
	var summary := "\n".join(inspector.get_map_summary())
	check(summary.contains("generated") and summary.contains("24x20") and summary.contains("seed 24680"), "Generated metadata reports map kind, dimensions, and reproducible seed")
	check(level.battle_controller.grid_manager.map_data.zones.size() >= 2, "Generated inspector can enumerate deployment zones")
	level.queue_free()
	await process_frame

