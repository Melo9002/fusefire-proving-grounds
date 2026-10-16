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
	return catalog

static func _register(catalog: Dictionary, definition: EnvironmentModuleDefinition) -> void:
	catalog[definition.component_id] = definition

static func _full_cover() -> Dictionary:
	return {"cover_type": MapCellData.CoverType.FULL, "cover_height": 3.0, "walkable": false, "can_stop": false, "blocks_los": true}

static func _wall_straight() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_wall_straight", &"factory_structure", Vector2i(3, 1))
	item.allowed_rotations = [0, 1, 2, 3]
	for x in 3:
		item.set_effect(Vector2i(x, 0), _full_cover())
		item.add_visual(FACTORY + "structure-wall.glb", Vector2(x, 0), 1.0, 0, 0)
	item.add_connection(Vector2i(0, 0), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(2, 0), Vector2i.RIGHT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	return item

static func _wall_corner() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_wall_corner", &"factory_structure", Vector2i.ONE)
	item.set_effect(Vector2i.ZERO, _full_cover())
	item.add_connection(Vector2i.ZERO, Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i.ZERO, Vector2i.UP, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_visual(FACTORY + "structure-corner-outer.glb", Vector2.ZERO, 1.0, 0, 0)
	return item

static func _doorway() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_doorway_wide", &"factory_structure", Vector2i(2, 1))
	item.clearance_cells = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 1), Vector2i(1, 1)]
	item.add_connection(Vector2i(0, 0), Vector2i.LEFT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(1, 0), Vector2i.RIGHT, EnvironmentModuleConnection.Type.STRUCTURE_EDGE)
	item.add_connection(Vector2i(0, 0), Vector2i.UP, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	item.add_connection(Vector2i(0, 0), Vector2i.DOWN, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
	item.add_visual(FACTORY + "structure-doorway-wide.glb", Vector2(0.5, 0), 1.0, 0, 0)
	return item

static func _interior_floor() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_interior_floor", &"factory_structure", Vector2i(8, 5))
	item.add_connection(Vector2i(3, 4), Vector2i.DOWN, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	return item

static func _road_straight() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"road_straight", &"city_roads", Vector2i(9, 9))
	item.add_connection(Vector2i(4, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(4, 8), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(8, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_visual(ROADS + "road-straight.glb", Vector2(4, 4), 9.0, 0, 2)
	return item

static func _road_corner() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"road_corner", &"city_roads", Vector2i(18, 18))
	item.add_connection(Vector2i(9, 0), Vector2i.UP, EnvironmentModuleConnection.Type.ROAD)
	item.add_connection(Vector2i(17, 9), Vector2i.RIGHT, EnvironmentModuleConnection.Type.ROAD)
	item.add_visual(ROADS + "road-curve.glb", Vector2(8.5, 8.5), 9.0, 0, 2)
	return item

static func _paving() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"paving_square", &"city_roads", Vector2i(9, 9))
	item.add_connection(Vector2i(3, 0), Vector2i.UP, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(0, 4), Vector2i.LEFT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_connection(Vector2i(8, 4), Vector2i.RIGHT, EnvironmentModuleConnection.Type.SIDEWALK)
	item.add_visual(ROADS + "tile-low.glb", Vector2(4, 4), 9.0, 0, 2)
	return item

static func _cargo_container() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"cargo_container", &"industrial_cargo", Vector2i(4, 8))
	for cell in item.footprint_cells:
		item.set_effect(cell, {"cover_type": MapCellData.CoverType.FULL, "cover_height": 3.13, "walkable": false, "can_stop": false, "blocks_los": true})
	item.visuals = [{
		"asset_variants": [INDUSTRIAL + "shipping-container-a.glb", INDUSTRIAL + "shipping-container-b.glb", INDUSTRIAL + "shipping-container-c.glb"],
		"local_cell": Vector2(1.5, 3.5), "scale": 9.0, "yaw_quarters": 0, "anchor": 0,
	}]
	return item
