extends SceneTree

const Spatial = preload("res://systems/generation/environment_spatial_queries.gd")
const Ledger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var centered := AABB(Vector3(0.6, 0, -0.4), Vector3(0.8, 1, 0.8))
	check(Spatial.visual_intersects_cells(centered, [Vector2i(1, 0)], Vector2(0, 2)) and not Spatial.visual_intersects_cells(centered, [Vector2i.ZERO], Vector2(0, 2)), "Visual/cell intersection uses cell-centered canonical coordinates")
	var prop := EnvironmentModuleDefinition.new(&"prop", &"test", Vector2i(2, 3))
	prop.set_effect(Vector2i.ZERO, {"walkable": false})
	var floor_module := EnvironmentModuleDefinition.new(&"floor", &"test", Vector2i(2, 3))
	floor_module.placement_layer = EnvironmentModuleDefinition.PlacementLayer.OVERHEAD
	floor_module.occupancy_height = 0.0
	for cell in floor_module.footprint_cells: floor_module.add_elevated_surface(cell, 4)
	floor_module.add_vertical_link(Vector3i(1, 0, 2), Vector3i(1, 4, 2), GeneratedTraversalData.Kind.LADDER)
	var catalog := {&"prop": prop, &"floor": floor_module}
	for rotation in 4:
		for reverse in [false, true]:
			var rotated_layout := EnvironmentModuleLayout.new(&"supported_floors")
			var ordered := [EnvironmentModulePlacement.new(&"prop", Vector2i(3, 4), rotation), EnvironmentModulePlacement.new(&"prop", Vector2i(3, 4), rotation, 0, 4), EnvironmentModulePlacement.new(&"floor", Vector2i(3, 4), rotation)]
			if reverse: ordered.reverse()
			for placement in ordered: check(rotated_layout.try_add(catalog[placement.component_id], placement, Vector2i(16, 16)), "Separate floor placement accepted r%d: %s" % [rotation, rotated_layout.errors])
			check(Spatial.source_support_errors(rotated_layout, catalog, Vector2i(16, 16)).is_empty(), "Authoring uses the same order-independent support contract")
			var rotated_data := FlatMapGenerator.generate(16, 16, 1.0, 1)
			var compilation_errors := EnvironmentModuleMapWriter.apply(rotated_data, rotated_layout, catalog, 1.0)
			check(compilation_errors.is_empty(), "Supported floors compile in either order r%d: %s" % [rotation, compilation_errors])
			var corner: Vector2i = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 2), Vector2i(0, 1)][rotation] + Vector2i(3, 4)
			check(not rotated_data.get_cell(Vector3i(corner.x, 0, corner.y)).walkable and not rotated_data.get_cell(Vector3i(corner.x, 4, corner.y)).walkable, "Independent expected rotated rectangular corners are occupied")
			var end: Vector2i = [Vector2i(1, 2), Vector2i(0, 1), Vector2i(0, 0), Vector2i(2, 0)][rotation] + Vector2i(3, 4)
			check(rotated_data.traversal_links.size() == 1 and rotated_data.traversal_links[0].to_cell == Vector3i(end.x, 4, end.y), "Rotated traversal reaches supported floor")
			var graph := Pathfinder.new()
			MapGraphBuilder.build(rotated_data, graph)
			check(not graph.calculate_3d_path(Vector3i(end.x, 0, end.y), Vector3i(end.x, 4, end.y)).is_empty(), "Traversal is usable by gameplay graph")

	var layout := EnvironmentModuleLayout.new(&"tall")
	prop.occupancy_height = 5.0
	check(layout.try_add(prop, EnvironmentModulePlacement.new(&"prop", Vector2i(3, 4)), Vector2i(16, 16)), "Tall initial occupant accepted")
	check(not layout.try_add(prop, EnvironmentModulePlacement.new(&"prop", Vector2i(3, 4), 0, 0, 4), Vector2i(16, 16)), "Different base floors do not excuse intersecting occupied volumes")
	check(not layout.try_add(floor_module, EnvironmentModulePlacement.new(&"floor", Vector2i(3, 4)), Vector2i(16, 16)), "Floor cannot cut through tall occupant")
	prop.occupancy_height = 1.0
	var visual := EnvironmentModuleDefinition.new(&"visual", &"test", Vector2i.ONE)
	visual.set_visual_envelope(AABB(Vector3.ZERO, Vector3(1, 5, 1)))
	layout = EnvironmentModuleLayout.new(&"visual")
	check(layout.try_add(visual, EnvironmentModulePlacement.new(&"visual", Vector2i(2, 2)), Vector2i(16, 16)), "Visual initial occupant accepted")
	visual.placement_layer = EnvironmentModuleDefinition.PlacementLayer.OVERHEAD
	check(not layout.try_add(visual, EnvironmentModulePlacement.new(&"visual", Vector2i(2, 2), 0, 0, 4), Vector2i(16, 16)), "Visual intersections across layers/floors reject")

	var door := EnvironmentModuleDefinition.new(&"door", &"test", Vector2i.ONE)
	door.clearance_cells = [Vector2i(1, 0)]
	door.clearance_height = 3.0
	var box := EnvironmentModuleDefinition.new(&"box", &"test", Vector2i.ONE)
	for reverse in [false, true]:
		layout = EnvironmentModuleLayout.new(&"headroom")
		var a := EnvironmentModulePlacement.new(&"door", Vector2i(2, 2))
		var b := EnvironmentModulePlacement.new(&"box", Vector2i(3, 2), 0, 0, 2)
		if reverse:
			check(layout.try_add(box, b, Vector2i(16, 16)), "Upper occupant first")
			check(not layout.try_add(door, a, Vector2i(16, 16)), "Headroom rejection is symmetric")
		else:
			check(layout.try_add(door, a, Vector2i(16, 16)), "Door first")
			check(not layout.try_add(box, b, Vector2i(16, 16)), "Upper occupant violates clearance headroom")
			b.elevation = 3
			check(layout.try_add(box, b, Vector2i(16, 16)), "Touching clearance boundary is legal")

	layout = EnvironmentModuleLayout.new(&"unsupported_visual")
	layout.placements.append(EnvironmentModulePlacement.new(&"box", Vector2i(3, 3), 0, 0, 4))
	var data := FlatMapGenerator.generate(16, 16, 1.0, 1)
	var errors := EnvironmentModuleMapWriter.apply(data, layout, {&"box": box}, 1.0)
	check(errors.any(func(e): return e.code == "MISSING_PLACEMENT_SUPPORT"), "Visual-only occupants cannot float without surfaces")
	var low_floor := EnvironmentModuleDefinition.new(&"low_floor", &"test", Vector2i.ONE)
	low_floor.occupancy_height = 0.0
	low_floor.add_elevated_surface(Vector2i.ZERO, 1)
	layout = EnvironmentModuleLayout.new(&"low_floor")
	layout.placements.append(EnvironmentModulePlacement.new(&"low_floor", Vector2i(3, 3)))
	errors = EnvironmentModuleMapWriter.apply(data, layout, {&"low_floor": low_floor}, 1.0)
	check(errors.any(func(e): return e.code == "INSUFFICIENT_HEADROOM") and not data.has_cell(Vector3i(3, 1, 3)), "Inadequate floor headroom rejects transactionally")
	data.add_cell(MapCellData.new(Vector3i(3, 2, 3), Vector3(3, 2, 3)))
	box.occupancy_height = 3.0
	layout = EnvironmentModuleLayout.new(&"existing_floor")
	layout.placements.append(EnvironmentModulePlacement.new(&"box", Vector2i(3, 3)))
	errors = EnvironmentModuleMapWriter.apply(data, layout, {&"box": box}, 1.0)
	check(errors.any(func(e): return e.code == "SURFACE_INTERSECTS_VOLUME"), "Population respects floors already present in MapData")
	box.occupancy_height = 1.0
	var editor = load("res://tools/map_editor.gd").new()
	editor.editor_catalog = {&"box": box}
	var previous_layout := EnvironmentModuleLayout.new(&"previous")
	editor.custom_layout = previous_layout
	layout.placements[0].elevation = 4
	check(not editor._accept_custom_layout(layout) and editor.custom_layout == previous_layout and editor.custom_document == null, "Editor rejects unsupported edit before mutating current state")
	editor.free()
	_reservations(box)
	print("Elevation spatial contracts: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

func _reservations(box: EnvironmentModuleDefinition) -> void:
	var ledger := Ledger.new()
	var floor_record := {"reservation_id": "lower", "owner_ref": "zone:lower", "role": Ledger.DEPLOYMENT_REGION, "cells": [Vector2i(3, 3)], "scope": Ledger.FLOOR, "elevation": 0, "height": 2.0}
	check(ledger.try_reserve(floor_record), "Floor reservation accepted")
	var upper := floor_record.duplicate(true)
	upper.reservation_id = "upper"
	upper.owner_ref = "zone:upper"
	upper.elevation = 4
	check(ledger.try_reserve(upper), "Otherwise incompatible owners can reserve separate floors")
	var layout := EnvironmentModuleLayout.new()
	check(ledger.placement_allowed(box, EnvironmentModulePlacement.new(&"box", Vector2i(3, 3), 0, 0, 2), layout).ok, "Middle unreserved floor remains available")
	check(not ledger.placement_allowed(box, EnvironmentModulePlacement.new(&"box", Vector2i(3, 3), 0, 0, 4), layout).ok, "Reserved upper floor remains protected")
	check(not ledger.contains_at(Ledger.DEPLOYMENT_REGION, Vector3i(3, 2, 3)) and ledger.contains_at(Ledger.DEPLOYMENT_REGION, Vector3i(3, 4, 3)), "Point queries respect floor spans")
	var restored := Ledger.new()
	for record in Ledger.decoded_records(JSON.parse_string(JSON.stringify(Ledger.encoded_records(ledger.reservations)))): check(restored.try_reserve(record), "Reservation JSON round trip")
	check(restored.reservations == ledger.reservations, "Floor spans survive serialization")
	var legacy := floor_record.duplicate(true)
	legacy.erase("scope")
	ledger = Ledger.new()
	check(ledger.try_reserve(legacy) and ledger.reservations[0].scope == Ledger.WHOLE_COLUMN, "Legacy scope preserves whole-column protection")
	check(not ledger.placement_allowed(box, EnvironmentModulePlacement.new(&"box", Vector2i(3, 3), 0, 0, 8), layout).ok, "Whole-column protection cannot be bypassed by elevation")
	var mission_map := MapData.new()
	mission_map.add_spawn_cell(TacticalUnit.Faction.PLAYER, Vector3i(3, 4, 3))
	var mission_ledger := Ledger.from_map(mission_map)
	check(mission_ledger.reservations[0].scope == Ledger.WHOLE_COLUMN and not mission_ledger.placement_allowed(box, EnvironmentModulePlacement.new(&"box", Vector2i(3, 3), 0, 0, 8), layout).ok, "Mission zones explicitly protect the entire column")
	var invalid := floor_record.duplicate(true)
	invalid.reservation_id = "invalid"
	invalid.height = -1
	check(not Ledger.new().try_reserve(invalid), "Invalid floor interval rejects")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)
