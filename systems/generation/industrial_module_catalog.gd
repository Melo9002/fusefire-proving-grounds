class_name IndustrialModuleCatalog
extends RefCounted

const FACTORY := "res://art/environments/kenney/factory_kit/models/"
const INDUSTRIAL := "res://art/environments/kenney/city_kit_industrial/models/"
const ROADS := "res://art/environments/kenney/city_kit_roads/models/"

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
	return catalog

static func _register(catalog: Dictionary, definition: EnvironmentModuleDefinition) -> void:
	catalog[definition.component_id] = definition

static func _full_cover() -> Dictionary:
	return {"interaction": EnvironmentModuleDefinition.CellInteraction.BLOCKED, "cover_type": MapCellData.CoverType.FULL, "cover_height": 3.0, "walkable": false, "can_stop": false, "blocks_los": true, "movement_cost": 1}

static func _vaultable_low_cover(height := 0.65) -> Dictionary:
	return {"interaction": EnvironmentModuleDefinition.CellInteraction.VAULT, "cover_type": MapCellData.CoverType.LOW, "cover_height": height, "walkable": true, "can_stop": false, "blocks_los": false, "movement_cost": 2}

static func _wall_straight() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_wall_straight", &"factory_structure", Vector2i(3, 1))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_visual_convention(Vector2(0.25, 0.25), Vector2(1.5, 1.5), "Two calibrated 1.5-unit Factory wall bays form this three-cell run.")
	item.allowed_rotations = [0, 1, 2, 3]
	for x in 3:
		item.set_effect(Vector2i(x, 0), _full_cover())
	item.add_visual(FACTORY + "structure-wall.glb", Vector2(0.75, 0), 1.5, 0, 0)
	item.add_visual(FACTORY + "structure-wall.glb", Vector2(2.25, 0), 1.5, 0, 0)
	item.add_connection(Vector2i(0, 0), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(2, 0), Vector2i.RIGHT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	return item

static func _wall_corner() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_wall_corner", &"factory_structure", Vector2i(2, 2))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_visual_convention(Vector2(0.25, 0.25), Vector2(1.5, 1.5), "Calibrated corner projects half a cell beyond its authored two-cell junction envelope.")
	for cell in item.footprint_cells:
		item.set_effect(cell, _full_cover())
	item.add_connection(Vector2i(0, 1), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(1, 0), Vector2i.UP, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_visual(FACTORY + "structure-corner-outer.glb", Vector2(0.75, 0.75), 1.5, 0, 0)
	return item

static func _doorway() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_doorway_wide", &"factory_structure", Vector2i(3, 1))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_visual_convention(Vector2(0.25, 0.25), Vector2(1.5, 1.5), "The calibrated wide doorway spans three cells and keeps its center lane open.")
	item.clearance_cells = [Vector2i(1, -1), Vector2i(1, 1)]
	item.set_effect(Vector2i(0, 0), _full_cover())
	item.set_effect(Vector2i(2, 0), _full_cover())
	item.add_connection(Vector2i(0, 0), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(2, 0), Vector2i.RIGHT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(1, 0), Vector2i.UP, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	item.add_connection(Vector2i(1, 0), Vector2i.DOWN, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
	item.add_visual(FACTORY + "structure-doorway-wide.glb", Vector2(1.5, 0), 1.5, 0, 0)
	return item

static func _interior_floor() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_interior_floor", &"factory_structure", Vector2i(9, 6))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2.ONE, "Authored tactical floor; the neutral floor marker has no imported collision.")
	item.add_connection(Vector2i(4, 5), Vector2i.DOWN, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	return item

static func _road_straight() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"road_straight", &"city_roads", Vector2i(10, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(10, 10), "City Roads tiles use the calibrated ten-unit pitch.")
	item.add_connection(Vector2i(4, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(4, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(9, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_visual(ROADS + "road-straight.glb", Vector2(4.5, 4.5), 10.0, 0, 2)
	return item

static func _road_corner() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"road_corner", &"city_roads", Vector2i(20, 20))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(20, 20), "The calibrated curve occupies two ten-unit road pitches.")
	item.add_connection(Vector2i(9, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(19, 9), Vector2i.RIGHT, EnvironmentModuleConnection.Type.ROAD)
	item.add_visual(ROADS + "road-curve.glb", Vector2(9.5, 9.5), 10.0, 0, 2)
	return item

static func _paving() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"paving_square", &"city_roads", Vector2i(10, 10))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.GROUND)
	item.set_visual_convention(Vector2.ONE, Vector2(10, 10), "Paving shares the calibrated ten-unit City Roads pitch.")
	item.add_connection(Vector2i(4, 0), Vector2i.UP, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(9, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_visual(ROADS + "tile-low.glb", Vector2(4.5, 4.5), 10.0, 0, 2)
	return item

static func _cargo_container() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"cargo_container", &"industrial_cargo", Vector2i(2, 5))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ZERO, "The calibrated container is a solid authored obstacle; its visual length slightly exceeds four cells.")
	for cell in item.footprint_cells:
		item.set_effect(cell, {"interaction": EnvironmentModuleDefinition.CellInteraction.BLOCKED, "cover_type": MapCellData.CoverType.FULL, "cover_height": 1.74, "walkable": false, "can_stop": false, "blocks_los": true, "movement_cost": 1})
	item.visuals = [{
		"asset_variants": [INDUSTRIAL + "shipping-container-a.glb", INDUSTRIAL + "shipping-container-b.glb", INDUSTRIAL + "shipping-container-c.glb"],
		"local_cell": Vector2(0.5, 2.0), "scale": 5.0, "yaw_quarters": 0, "anchor": 0,
	}]
	return item

static func _construction_barrier() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"construction_barrier_vault", &"road_furniture", Vector2i.ONE)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.VAULTABLE_OBSTACLE)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ZERO, "One-cell low obstacle: traversable, non-stoppable and presented as a vault.")
	item.set_effect(Vector2i.ZERO, _vaultable_low_cover())
	item.add_visual(ROADS + "construction-barrier.glb", Vector2.ZERO, 5.0, 0, 0)
	return item
