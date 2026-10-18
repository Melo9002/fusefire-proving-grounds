class_name IndustrialModuleCatalog
extends RefCounted

const FACTORY := "res://art/environments/kenney/factory_kit/models/"
const INDUSTRIAL := "res://art/environments/kenney/city_kit_industrial/models/"
const ROADS := "res://art/environments/kenney/city_kit_roads/models/"
const STRUCTURE_PRESENTATION_SCALE := 2.01

static func create() -> Dictionary:
	var catalog := {}
	_register(catalog, _wall_straight())
	_register(catalog, _wall_corner())
	_register(catalog, _doorway())
	_register(catalog, _interior_floor())
	_register(catalog, _road_straight())
	_register(catalog, _road_corner())
	_register(catalog, _paving())
	_register(catalog, _cargo_container())
	_register(catalog, _construction_barrier())
	_register(catalog, _window_wall())
	_register(catalog, _alley())
	_register(catalog, _road_intersection())
	_register(catalog, _road_crossroad())
	_register(catalog, _shop_front())
	_register(catalog, _courtyard())
	_register(catalog, _loading_dock())
	_register(catalog, _machine())
	_register(catalog, _machine_cover_cluster())
	_register(catalog, _stairs())
	_register(catalog, _ramp())
	_register(catalog, _elevated_platform())
	_register(catalog, _elevated_walkway())
	_register(catalog, _complete_service_building())
	_register(catalog, _industrial_building_shell())
	_register(catalog, _street_light())
	_register(catalog, _traffic_signal())
	_register(catalog, _stop_sign())
	_register(catalog, _dumpster())
	_register(catalog, _utility_pole())
	_register(catalog, _yard_fence())
	return catalog

static func _register(catalog: Dictionary, definition: EnvironmentModuleDefinition) -> void:
	catalog[definition.component_id] = definition

static func _full_cover() -> Dictionary:
	return {"interaction": EnvironmentModuleDefinition.CellInteraction.BLOCKED, "cover_type": MapCellData.CoverType.FULL, "cover_height": 3.0, "walkable": false, "can_stop": false, "blocks_los": true, "movement_cost": 1}

static func _vaultable_low_cover(height := 0.65) -> Dictionary:
	return {"interaction": EnvironmentModuleDefinition.CellInteraction.VAULT, "cover_type": MapCellData.CoverType.LOW, "cover_height": height, "walkable": true, "can_stop": false, "blocks_los": false, "movement_cost": 2}

static func _perimeter_clearance(size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(-1, size.x + 1):
		result.append(Vector2i(x, -1))
		result.append(Vector2i(x, size.y))
	for z in size.y:
		result.append(Vector2i(-1, z))
		result.append(Vector2i(size.x, z))
	return result

static func _wall_straight() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_wall_straight", &"factory_structure", Vector2i(4, 1))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.WALL)
	item.set_visual_convention(Vector2.ONE, Vector2(2, 2), "Two scale-2 Factory wall bays form this four-cell run on integer grid boundaries.")
	item.allowed_rotations = [0, 1, 2, 3]
	for x in 4:
		item.set_effect(Vector2i(x, 0), _full_cover())
	item.add_visual(FACTORY + "structure-wall.glb", Vector2(1, 0), STRUCTURE_PRESENTATION_SCALE, 0, 1)
	item.add_visual(FACTORY + "structure-wall.glb", Vector2(3, 0), STRUCTURE_PRESENTATION_SCALE, 0, 1)
	item.add_connection(Vector2i(0, 0), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(3, 0), Vector2i.RIGHT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	return item

static func _wall_corner() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_wall_corner", &"factory_structure", Vector2i(2, 2))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.CORNER)
	item.set_visual_convention(Vector2.ONE, Vector2(2, 2), "Scale-2 corner uses the Factory Kit's native two-unit pitch on integer grid boundaries.")
	for cell in item.footprint_cells:
		item.set_effect(cell, _full_cover())
	item.add_connection(Vector2i(0, 1), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(1, 0), Vector2i.UP, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	# Factory pieces join at their source origins. At scale 2 the concave corner
	# and both straight runs share an integer two-cell pitch without overlap.
	# Closed modular meshes retain end caps. The tiny presentation-scale bleed
	# keeps those coplanar faces from z-fighting at otherwise exact seams.
	item.add_visual(FACTORY + "structure-corner-inner.glb", Vector2.ONE, STRUCTURE_PRESENTATION_SCALE, 0, 1)
	return item

static func _doorway() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_doorway_wide", &"factory_structure", Vector2i(4, 1))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.DOORWAY)
	item.set_visual_convention(Vector2.ONE, Vector2(2, 2), "The scale-2 wide doorway spans four cells and keeps two center lanes open.")
	item.clearance_cells = [Vector2i(1, -1), Vector2i(2, -1), Vector2i(1, 1), Vector2i(2, 1)]
	item.set_effect(Vector2i(0, 0), _full_cover())
	item.set_effect(Vector2i(3, 0), _full_cover())
	item.add_connection(Vector2i(0, 0), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(3, 0), Vector2i.RIGHT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(1, 0), Vector2i.UP, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	item.add_connection(Vector2i(2, 0), Vector2i.UP, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	item.add_connection(Vector2i(1, 0), Vector2i.DOWN, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
	item.add_connection(Vector2i(2, 0), Vector2i.DOWN, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
	item.add_visual(FACTORY + "structure-doorway-wide.glb", Vector2(2, 0), STRUCTURE_PRESENTATION_SCALE, 0, 1)
	return item

static func _interior_floor() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_interior_floor", &"factory_structure", Vector2i(12, 8))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.FLOOR)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2.ONE, "Authored tactical floor; the neutral floor marker has no imported collision.")
	item.add_connection(Vector2i(5, 7), Vector2i.DOWN, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	item.add_connection(Vector2i(6, 7), Vector2i.DOWN, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.SPAWN, [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)])
	item.add_suitability(EnvironmentModuleDefinition.Suitability.OBJECTIVE, [Vector2i(9, 3), Vector2i(9, 4)])
	return item

static func _road_straight() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"road_straight", &"city_roads", Vector2i(10, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.ROAD)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(10, 10), "City Roads tiles use the calibrated ten-unit pitch; surfaces sit 0.02 units above the base plane to prevent z-fighting.")
	item.add_connection(Vector2i(4, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(5, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(4, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(5, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(9, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_visual(ROADS + "road-straight.glb", Vector2(4.5, 4.5), 10.0, 0, 2, Vector3(0, 0.02, 0))
	return item

static func _road_corner() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"road_corner", &"city_roads", Vector2i(20, 20))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.ROAD)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(20, 20), "The calibrated curve occupies two ten-unit road pitches.")
	item.add_connection(Vector2i(9, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(19, 9), Vector2i.RIGHT, EnvironmentModuleConnection.Type.ROAD)
	item.add_visual(ROADS + "road-curve.glb", Vector2(9.5, 9.5), 10.0, 0, 2, Vector3(0, 0.02, 0))
	return item

static func _paving() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"paving_square", &"city_roads", Vector2i(10, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.GROUND)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(10, 10), "Paving shares the calibrated ten-unit City Roads pitch.")
	item.add_connection(Vector2i(4, 0), Vector2i.UP, EnvironmentModuleConnection.Type.SIDEWALK)
	# The scale-two doorway is layered over the first paving row, so its open
	# lanes connect to the next traversable paving cells rather than the same row.
	item.add_connection(Vector2i(5, 1), Vector2i.UP, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(6, 1), Vector2i.UP, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(9, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_visual(ROADS + "tile-low.glb", Vector2(4.5, 4.5), 10.0, 0, 2, Vector3(0, 0.02, 0))
	return item

static func _cargo_container() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"cargo_container", &"industrial_cargo", Vector2i(2, 5))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ZERO, "The calibrated container is a solid authored obstacle; its visual length slightly exceeds four cells.")
	for cell in item.footprint_cells:
		item.set_effect(cell, {"interaction": EnvironmentModuleDefinition.CellInteraction.BLOCKED, "cover_type": MapCellData.CoverType.FULL, "cover_height": 1.74, "walkable": false, "can_stop": false, "blocks_los": true, "movement_cost": 1})
	item.set_visual_envelope(AABB(Vector3(-0.15, 0.0, -0.15), Vector3(2.3, 2.0, 5.3)))
	item.visuals = [{
		"asset_variants": [INDUSTRIAL + "shipping-container-a.glb", INDUSTRIAL + "shipping-container-b.glb", INDUSTRIAL + "shipping-container-c.glb"],
		"local_cell": Vector2(0.5, 2.0), "scale": 5.0, "yaw_quarters": 0, "anchor": 0,
	}]
	return item

static func _construction_barrier() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"construction_barrier_vault", &"road_furniture", Vector2i.ONE)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.VAULTABLE_OBSTACLE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ZERO, "One-cell low obstacle: traversable, non-stoppable and presented as a vault.")
	item.set_effect(Vector2i.ZERO, _vaultable_low_cover())
	item.add_visual(ROADS + "construction-barrier.glb", Vector2.ZERO, 5.0, 0, 0)
	return item

static func _window_wall() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_window_wall", &"factory_structure", Vector2i(4, 1))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.WINDOW)
	item.set_visual_convention(Vector2.ONE, Vector2(2, 2), "Window bay shares the Factory wall pitch; glazing remains LOS-blocking until transparent-window rules are authored.")
	for x in 4:
		item.set_effect(Vector2i(x, 0), _full_cover())
	item.add_connection(Vector2i(0, 0), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(3, 0), Vector2i.RIGHT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_visual(FACTORY + "structure-window-wide.glb", Vector2(2, 0), STRUCTURE_PRESENTATION_SCALE, 0, 1)
	return item

static func _alley() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"paved_alley", &"civic_ground", Vector2i(4, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.ALLEY)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(4, 10), "Narrow authored ground strip; neutral marker avoids stretching a road mesh.")
	item.add_connection(Vector2i(1, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ALLEY)
	item.add_connection(Vector2i(1, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.ALLEY)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
	item.add_connection(Vector2i(3, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.SPAWN, [Vector2i(1, 1), Vector2i(2, 1)])
	item.add_suitability(EnvironmentModuleDefinition.Suitability.EXTRACTION, [Vector2i(1, 8), Vector2i(2, 8)])
	return item

static func _road_intersection() -> EnvironmentModuleDefinition:
	var item := _road_tile(&"road_intersection_t", "road-intersection.glb", EnvironmentModuleDefinition.ModuleType.INTERSECTION)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(0, 5), Vector2i.LEFT, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(9, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(9, 5), Vector2i.RIGHT, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(4, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(5, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	return item

static func _road_crossroad() -> EnvironmentModuleDefinition:
	var item := _road_tile(&"road_crossroad", "road-crossroad.glb", EnvironmentModuleDefinition.ModuleType.INTERSECTION)
	item.add_connection(Vector2i(4, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(5, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(4, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(5, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(0, 5), Vector2i.LEFT, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(9, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(9, 5), Vector2i.RIGHT, EnvironmentModuleConnection.Type.ROAD)
	return item

static func _road_tile(id: StringName, model: String, type: EnvironmentModuleDefinition.ModuleType) -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(id, &"city_roads", Vector2i(10, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(type)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(10, 10), "City Roads ten-unit connection pitch.")
	item.add_visual(ROADS + model, Vector2(4.5, 4.5), 10.0, 0, 2, Vector3(0, 0.02, 0))
	return item

static func _shop_front() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_shop_front", &"factory_composite", Vector2i(8, 1))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.SHOP)
	item.set_visual_convention(Vector2.ONE, Vector2(2, 2), "Reusable storefront: window bay plus wide entrance on the Factory pitch.")
	for x in [0, 1, 2, 3, 4, 7]:
		item.set_effect(Vector2i(x, 0), _full_cover())
	item.clearance_cells = [Vector2i(5, -1), Vector2i(6, -1), Vector2i(5, 1), Vector2i(6, 1)]
	item.add_connection(Vector2i(0, 0), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(7, 0), Vector2i.RIGHT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	for x in [5, 6]:
		item.add_connection(Vector2i(x, 0), Vector2i.UP, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
		item.add_connection(Vector2i(x, 0), Vector2i.DOWN, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
	item.add_visual(FACTORY + "structure-window-wide.glb", Vector2(2, 0), STRUCTURE_PRESENTATION_SCALE, 0, 1)
	item.add_visual(FACTORY + "structure-doorway-wide.glb", Vector2(6, 0), STRUCTURE_PRESENTATION_SCALE, 0, 1)
	return item

static func _courtyard() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"paved_courtyard", &"civic_ground", Vector2i(10, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.COURTYARD)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(10, 10), "Open mission-capable paved space on the City Roads pitch.")
	for side in [[Vector2i(4, 0), Vector2i.UP], [Vector2i(4, 9), Vector2i.DOWN], [Vector2i(0, 4), Vector2i.LEFT], [Vector2i(9, 4), Vector2i.RIGHT]]:
		item.add_connection(side[0], side[1], EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.OBJECTIVE, [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)])
	item.add_suitability(EnvironmentModuleDefinition.Suitability.SPAWN, [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)])
	item.add_suitability(EnvironmentModuleDefinition.Suitability.EXTRACTION, [Vector2i(1, 7), Vector2i(2, 7), Vector2i(1, 8), Vector2i(2, 8)])
	item.add_visual(ROADS + "tile-low.glb", Vector2(4.5, 4.5), 10.0, 0, 2, Vector3(0, 0.02, 0))
	return item

static func _loading_dock() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"industrial_loading_dock", &"industrial_space", Vector2i(10, 6))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.LOADING_DOCK)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(10, 6), "Loading apron is authored ground; cargo and machines occupy its independent occupant layer.")
	item.add_connection(Vector2i(4, 0), Vector2i.UP, EnvironmentModuleConnection.Type.LOADING)
	item.add_connection(Vector2i(4, 5), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.OBJECTIVE, [Vector2i(8, 1), Vector2i(8, 2)])
	item.add_suitability(EnvironmentModuleDefinition.Suitability.SPAWN, [Vector2i(1, 4), Vector2i(2, 4)])
	return item

static func _machine() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_machine", &"industrial_machinery", Vector2i(2, 2))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.MACHINERY)
	for cell in item.footprint_cells:
		item.set_effect(cell, _full_cover())
	item.clearance_cells = [Vector2i(0, -1), Vector2i(1, -1)]
	item.set_visual_envelope(AABB(Vector3(-0.2, 0.0, -0.3), Vector3(2.4, 2.7, 2.6)))
	item.add_visual(FACTORY + "machine.glb", Vector2(0.5, 0.5), 2.0, 0, 0)
	return item

static func _complete_service_building() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"complete_service_building", &"factory_buildings", Vector2i(10, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.SHOP)
	item.set_visual_convention(Vector2.ONE, Vector2(2, 2), "Closed four-sided Factory assembly with an authored two-cell street entrance and roof.")
	# The Factory meshes are four cells deep at the reviewed scale. Their source
	# origins are inset so the complete assembly stays inside its ten-cell parcel.
	for x in 10:
		for z in 10:
			if x in [2, 7] or z in [2, 7]:
				var north_south_door := z in [2, 7] and x in [4, 5]
				var east_west_door := x in [2, 7] and z in [4, 5]
				if not north_south_door and not east_west_door:
					item.set_effect(Vector2i(x, z), _full_cover())
	item.clearance_cells = [Vector2i(4, 1), Vector2i(5, 1), Vector2i(4, 8), Vector2i(5, 8), Vector2i(1, 4), Vector2i(1, 5), Vector2i(8, 4), Vector2i(8, 5)]
	item.set_visual_envelope(AABB(Vector3.ZERO, Vector3(10.0, 6.2, 10.0)))
	item.add_visual(FACTORY + "structure-window-wide.glb", Vector2(2, 3), STRUCTURE_PRESENTATION_SCALE, 2, 1)
	item.add_visual(FACTORY + "structure-doorway-wide.glb", Vector2(6, 3), STRUCTURE_PRESENTATION_SCALE, 2, 1)
	item.add_visual(FACTORY + "structure-window-wide.glb", Vector2(2, 7), STRUCTURE_PRESENTATION_SCALE, 0, 1)
	item.add_visual(FACTORY + "structure-doorway-wide.glb", Vector2(6, 7), STRUCTURE_PRESENTATION_SCALE, 0, 1)
	item.add_visual(FACTORY + "structure-window-wide.glb", Vector2(3, 2), STRUCTURE_PRESENTATION_SCALE, 1, 1)
	item.add_visual(FACTORY + "structure-doorway-wide.glb", Vector2(3, 6), STRUCTURE_PRESENTATION_SCALE, 1, 1)
	item.add_visual(FACTORY + "structure-window-wide.glb", Vector2(7, 2), STRUCTURE_PRESENTATION_SCALE, 3, 1)
	item.add_visual(FACTORY + "structure-doorway-wide.glb", Vector2(7, 6), STRUCTURE_PRESENTATION_SCALE, 3, 1)
	for x in [2, 6]:
		for z in [2, 6]:
			item.add_visual(FACTORY + "top-large.glb", Vector2(x, z), 2.0, 0, 1, Vector3(0, 6.04, 0))
	for x in [4, 5]:
		item.add_connection(Vector2i(x, 8), Vector2i.DOWN, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
		item.add_connection(Vector2i(x, 7), Vector2i.UP, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
		item.add_connection(Vector2i(x, 1), Vector2i.UP, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
		item.add_connection(Vector2i(x, 2), Vector2i.DOWN, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	for z in [4, 5]:
		item.add_connection(Vector2i(1, z), Vector2i.RIGHT, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
		item.add_connection(Vector2i(2, z), Vector2i.LEFT, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
		item.add_connection(Vector2i(8, z), Vector2i.LEFT, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
		item.add_connection(Vector2i(7, z), Vector2i.RIGHT, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.OBJECTIVE, [Vector2i(4, 4), Vector2i(5, 4)])
	return item

static func _industrial_building_shell() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"industrial_building_shell", &"city_industrial_buildings", Vector2i(14, 14))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.SHOP)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ZERO, "Complete reviewed City Kit shell; exterior-only until a matching interior is authored.")
	for cell in item.footprint_cells:
		item.set_effect(cell, _full_cover())
	item.set_visual_envelope(AABB(Vector3.ZERO, Vector3(14.0, 10.0, 14.0)))
	item.add_catalog_visual([
		"city_kit_industrial/building-h", "city_kit_industrial/building-i",
		"city_kit_industrial/building-j", "city_kit_industrial/building-k",
		"city_kit_industrial/building-o",
	], Vector2(6.5, 6.5))
	return item

static func _street_light() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"street_light", &"road_furniture", Vector2i.ONE)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.VISUAL_ONLY)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	item.set_visual_envelope(AABB(Vector3(-0.3, 0.0, -1.2), Vector3(0.6, 6.2, 2.4)))
	item.add_catalog_visual(["city_kit_roads/light-square", "city_kit_roads/light-curved"], Vector2.ZERO)
	return item

static func _traffic_signal() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"traffic_signal", &"road_furniture", Vector2i.ONE)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.VISUAL_ONLY)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	item.set_visual_envelope(AABB(Vector3(-0.6, 0.0, -0.5), Vector3(1.2, 5.3, 1.0)))
	item.add_catalog_visual(["city_kit_roads/traffic-light"], Vector2.ZERO)
	return item

static func _stop_sign() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"stop_sign", &"road_furniture", Vector2i.ONE)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.VISUAL_ONLY)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	item.set_visual_envelope(AABB(Vector3(-0.4, 0.0, -0.7), Vector3(0.8, 5.1, 1.4)))
	item.add_catalog_visual(["city_kit_roads/road-sign-stop"], Vector2.ZERO)
	return item

static func _dumpster() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"service_dumpster", &"service_props", Vector2i(2, 2))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	for cell in item.footprint_cells:
		item.set_effect(cell, _vaultable_low_cover(1.05))
	item.set_visual_envelope(AABB(Vector3(-0.2, 0.0, -0.2), Vector3(2.0, 1.2, 2.2)))
	item.add_catalog_visual(["city_kit_roads/dumpster"], Vector2(0.5, 0.5))
	return item

static func _utility_pole() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"utility_pole", &"road_utilities", Vector2i.ONE)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.VISUAL_ONLY)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	item.set_visual_envelope(AABB(Vector3(-0.45, 0.0, -1.1), Vector3(0.9, 5.4, 2.2)))
	item.add_catalog_visual(["city_kit_roads/electricity-pole-single"], Vector2.ZERO)
	return item

static func _yard_fence() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"yard_fence", &"industrial_boundaries", Vector2i(1, 4))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.VAULTABLE_OBSTACLE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	for cell in item.footprint_cells:
		item.set_effect(cell, _vaultable_low_cover(0.9))
	item.set_visual_envelope(AABB(Vector3(-0.25, 0.0, -0.25), Vector3(0.5, 1.0, 4.5)))
	item.add_catalog_visual(["city_kit_roads/construction-fence"], Vector2(0, 0.5))
	item.add_catalog_visual(["city_kit_roads/construction-fence"], Vector2(0, 2.5))
	return item

static func _machine_cover_cluster() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"machine_cover_cluster", &"industrial_machinery", Vector2i(6, 4))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.COVER_CLUSTER)
	for cell in [Vector2i(0, 1), Vector2i(1, 1), Vector2i(4, 2), Vector2i(5, 2)]:
		item.set_effect(cell, _full_cover())
	for cell in [Vector2i(2, 1), Vector2i(3, 2)]:
		item.set_effect(cell, _vaultable_low_cover())
	item.clearance_cells = _perimeter_clearance(item.size)
	item.set_visual_envelope(AABB(Vector3(-0.3, 0.0, -0.3), Vector3(6.6, 3.0, 4.6)))
	item.add_visual(FACTORY + "machine.glb", Vector2(0.5, 1.5), 2.0, 0, 0)
	item.add_visual(FACTORY + "machine-fortified.glb", Vector2(4.5, 2.5), 2.0, 2, 0)
	return item

static func _stairs() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"catwalk_stairs", &"factory_vertical", Vector2i(4, 3))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.STAIRS)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.OCCUPANT)
	for x in 4:
		item.add_elevated_surface(Vector2i(x, 2), 2)
	item.add_connection(Vector2i(1, 0), Vector2i.UP, EnvironmentModuleConnection.Type.VERTICAL, 0)
	item.add_connection(Vector2i(1, 2), Vector2i.DOWN, EnvironmentModuleConnection.Type.VERTICAL, 2)
	item.add_vertical_link(Vector3i(1, 0, 0), Vector3i(1, 2, 2), GeneratedTraversalData.Kind.STAIRS)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.SPAWN, [Vector2i(1, 0), Vector2i(2, 0)])
	item.add_visual(FACTORY + "catwalk-stairs.glb", Vector2(1.5, 1.0), 2.0, 0, 0)
	return item

static func _ramp() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"service_ramp", &"road_vertical", Vector2i(10, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.RAMP)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.OCCUPANT)
	for x in 10:
		item.add_elevated_surface(Vector2i(x, 9), 3)
	item.add_connection(Vector2i(4, 0), Vector2i.UP, EnvironmentModuleConnection.Type.VERTICAL, 0)
	item.add_connection(Vector2i(4, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.VERTICAL, 3)
	item.add_vertical_link(Vector3i(4, 0, 0), Vector3i(4, 3, 9), GeneratedTraversalData.Kind.RAMP)
	item.add_visual(ROADS + "road-slant.glb", Vector2(4.5, 4.5), 10.0, 0, 2, Vector3(0, 0.02, 0))
	return item

static func _elevated_platform() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"maintenance_platform", &"factory_vertical", Vector2i(4, 4))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PLATFORM)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.OVERHEAD)
	for cell in item.footprint_cells:
		item.add_elevated_surface(cell, 2)
	item.add_connection(Vector2i(0, 1), Vector2i.LEFT, EnvironmentModuleConnection.Type.VERTICAL, 2)
	item.add_connection(Vector2i(3, 1), Vector2i.RIGHT, EnvironmentModuleConnection.Type.VERTICAL, 2)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.OBJECTIVE, [Vector2i(1, 1), Vector2i(2, 1)])
	return item

static func _elevated_walkway() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"maintenance_walkway", &"factory_vertical", Vector2i(2, 6))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.WALKWAY)
	item.set_placement_layer(EnvironmentModuleDefinition.PlacementLayer.OVERHEAD)
	for cell in item.footprint_cells:
		item.add_elevated_surface(cell, 2)
	item.add_connection(Vector2i(0, 0), Vector2i.UP, EnvironmentModuleConnection.Type.VERTICAL, 2)
	item.add_connection(Vector2i(0, 5), Vector2i.DOWN, EnvironmentModuleConnection.Type.VERTICAL, 2)
	item.add_connection(Vector2i(0, 1), Vector2i.LEFT, EnvironmentModuleConnection.Type.VERTICAL, 2)
	item.add_connection(Vector2i(1, 1), Vector2i.RIGHT, EnvironmentModuleConnection.Type.VERTICAL, 2)
	item.add_visual(FACTORY + "catwalk-straight.glb", Vector2(0.5, 2.5), 2.0, 0, 0, Vector3(0, 2, 0))
	return item
