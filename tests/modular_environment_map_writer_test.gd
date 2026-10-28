extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var ground := _definition(&"ground", {"walkable": true, "can_stop": true, "blocks_los": false}, 0)
	var obstacle := _definition(&"obstacle", {"walkable": false, "blocks_los": true, "cover_type": MapCellData.CoverType.FULL}, 1)
	var cost := _definition(&"cost", {"movement_cost": 3}, 2)
	var catalog := {&"ground": ground, &"obstacle": obstacle, &"cost": cost}
	var expected := {}
	for ids in [[&"ground", &"obstacle", &"cost"], [&"ground", &"cost", &"obstacle"], [&"obstacle", &"ground", &"cost"], [&"obstacle", &"cost", &"ground"], [&"cost", &"ground", &"obstacle"], [&"cost", &"obstacle", &"ground"]]:
		var data := _map()
		var errors := EnvironmentModuleMapWriter.apply(data, _layout(ids), catalog, 1.0)
		check(errors.is_empty(), "Legal permutation compiles")
		var cell := data.get_cell(Vector3i.ZERO)
		check(not cell.walkable and not cell.can_stop and cell.blocks_line_of_sight and cell.cover_type == MapCellData.CoverType.FULL and cell.movement_cost == 3, "Ground cannot reopen occupant; sparse cost preserves blocking")
		if expected.is_empty(): expected = _snapshot(data)
		check(_snapshot(data) == expected, "Permutation preserves complete tactical output")
	var baseline := _map()
	baseline.get_cell(Vector3i.ZERO).walkable = false
	baseline.get_cell(Vector3i.ZERO).movement_cost = 5
	baseline.get_cell(Vector3i.ZERO).elevation = 0.25
	EnvironmentModuleMapWriter.apply(baseline, _layout([&"ground"]), catalog, 1.0)
	check(not baseline.get_cell(Vector3i.ZERO).walkable and baseline.get_cell(Vector3i.ZERO).movement_cost == 5 and baseline.get_cell(Vector3i.ZERO).elevation == 0.25, "Baseline restrictions and omitted properties survive")

	var surface := _definition(&"surface", {}, 2)
	surface.add_elevated_surface(Vector2i.ZERO, 2)
	surface.add_vertical_link(Vector3i.ZERO, Vector3i(0, 2, 0), GeneratedTraversalData.Kind.STAIRS)
	var upper := _definition(&"upper", {"movement_cost": 2}, 1)
	catalog[&"surface"] = surface
	catalog[&"upper"] = upper
	var output := {}
	for reverse in [false, true]:
		var layout := _layout([&"upper", &"surface"])
		layout.placements[0].elevation = 2
		if reverse: layout.placements.reverse()
		var data := _map()
		check(EnvironmentModuleMapWriter.apply(data, layout, catalog, 1.0).is_empty(), "Elevated consumer resolves after surface regardless of order")
		check(data.get_cell(Vector3i(0, 2, 0)).movement_cost == 2 and data.traversal_links.size() == 1, "Surface effects and traversal compile")
		if output.is_empty(): output = _snapshot(data)
		check(output == _snapshot(data), "Surface and traversal order independent")
	var same_surface := _definition(&"same", {}, 1)
	same_surface.add_elevated_surface(Vector2i.ZERO, 2)
	catalog[&"same"] = same_surface
	check(EnvironmentModuleMapWriter.apply(_map(), _layout([&"surface", &"same"]), catalog, 1.0).is_empty(), "Agreeing surface declarations can share an edge")
	same_surface.elevated_surfaces[Vector2i.ZERO]["walkable"] = false
	_reject(_layout([&"cost", &"surface", &"same"]), catalog, "CONFLICTING_SURFACE")
	var conflict := _definition(&"conflict", {"walkable": true}, 1)
	catalog[&"conflict"] = conflict
	_reject(_layout([&"obstacle", &"conflict"]), catalog, "CONFLICTING_EFFECT")
	var missing := _layout([&"cost", &"upper"])
	missing.placements[1].elevation = 2
	_reject(missing, catalog, "MISSING_EFFECT_SURFACE")
	missing = _layout([&"cost", &"surface"])
	missing.placements[1].elevation = 1
	_reject(missing, catalog, "MISSING_SURFACE_SUPPORT")
	var link := _definition(&"link", {}, 2)
	link.add_vertical_link(Vector3i.ZERO, Vector3i(0, 4, 0), GeneratedTraversalData.Kind.LADDER)
	catalog[&"link"] = link
	_reject(_layout([&"cost", &"link"]), catalog, "MISSING_TRAVERSAL_ENDPOINT")
	_reject(_layout([&"surface", &"obstacle"]), catalog, "BLOCKED_TRAVERSAL_ENDPOINT")
	var authored := EnvironmentModuleLayout.new(&"missing_upper_floor")
	authored.placements.append(EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(12, 12), 0, 0, 2))
	var document := BattlefieldLayoutDocument.from_authored(authored, Vector2i(32, 32), &"industrial_service_pad", "missing_upper_floor")
	var compiled := BattlefieldLayoutDocumentCompiler.compile(document)
	check(not compiled.ok and compiled.data == null and compiled.errors.any(func(e): return e.code == "MISSING_PLACEMENT_SUPPORT"), "Document compiler rejects missing support before tactical effects and exposes no partial map")
	print("T02 writer regressions: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _definition(id: StringName, effect: Dictionary, layer: int) -> EnvironmentModuleDefinition:
	var result := EnvironmentModuleDefinition.new(id, &"test", Vector2i.ONE)
	result.placement_layer = layer as EnvironmentModuleDefinition.PlacementLayer
	if not effect.is_empty(): result.set_effect(Vector2i.ZERO, effect)
	return result

func _map() -> MapData:
	var data := MapData.new()
	data.add_cell(MapCellData.new(Vector3i.ZERO, Vector3.ZERO))
	return data

func _layout(ids: Array) -> EnvironmentModuleLayout:
	var layout := EnvironmentModuleLayout.new(&"writer_unit")
	# Direct inputs isolate compilation from spatial reservations (T03).
	for id in ids:
		# Change stable IDs with input order so lexical sorting cannot conceal
		# last-writer-wins behavior in permutation assertions.
		layout.placements.append(EnvironmentModulePlacement.new(id, Vector2i.ZERO, 0, 0, 0, "instance_%d" % layout.placements.size()))
	return layout

func _snapshot(data: MapData) -> Dictionary:
	var result := {"cells": {}, "links": [], "generated": []}
	for at in data.cells:
		var c := data.get_cell(at)
		result.cells[at] = [c.world_position, c.elevation, c.walkable, c.can_stop, c.cover_type, c.cover_height, c.blocks_line_of_sight, c.movement_cost, c.hazard_condition]
	for link in data.traversal_links: result.links.append([link.from_cell, link.to_cell, link.bidirectional])
	for link in data.generated_traversals: result.generated.append([link.from_cell, link.to_cell, link.kind])
	return result

func _reject(layout: EnvironmentModuleLayout, catalog: Dictionary, code: String) -> void:
	var data := _map()
	var before := _snapshot(data)
	var errors := EnvironmentModuleMapWriter.apply(data, layout, catalog, 1.0)
	check(errors.any(func(e): return e.code == code), "Explicit rejection: %s (%s)" % [code, errors])
	check(before == _snapshot(data), "Rejected compile is atomic: %s" % code)

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
