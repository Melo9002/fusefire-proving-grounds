class_name IndustrialBuildingCatalog
extends RefCounted
## Reusable architectural assemblies.  Individual mesh modules continue to
## live in IndustrialModuleCatalog; procedural parcels consume these validated
## whole-building contracts instead of treating facades as buildings.

const INDUSTRIAL := "res://art/environments/kenney/city_kit_industrial/models/"
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")

static func create() -> Dictionary:
	var result := {}
	for building in [_service_building(), _loading_canopy(), _prebuilt_industrial_shell()]:
		result[building.assembly_id] = building
	return result

static func modules() -> Dictionary:
	var result := {}
	for building: EnvironmentBuildingDefinition in create().values():
		var definition := building.apply_metadata()
		result[definition.component_id] = definition
	return result

static func validation_errors() -> PackedStringArray:
	var result := PackedStringArray()
	for building: EnvironmentBuildingDefinition in create().values():
		for message in building.validate():
			result.append(message)
	return result

static func _service_building() -> EnvironmentBuildingDefinition:
	var building := EnvironmentBuildingDefinition.new(&"service_building", &"street_service_shop", EnvironmentBuildingDefinition.Enclosure.CLOSED, Vector2i(10, 10))
	building.notes = "Exact derived shell with one four-cell street entrance, a walkable interior and complete roof coverage."
	building.source_assets = ["factory_kit/structure-wall", "factory_kit/structure-window-wide", "factory_kit/structure-doorway-wide", "factory_kit/top-large"]
	var item := EnvironmentModuleDefinition.new(&"complete_service_building", &"authored_buildings", building.parcel_size)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.SHOP)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ONE, "Validated closed shell; exact derived walls replace overlapping four-metre-deep Factory facade blocks.")
	item.set_visual_envelope(AABB(Vector3(-0.6, 0.0, -0.6), Vector3(10.2, 3.7, 10.2)))
	var entrance_columns := [3, 4, 5, 6]
	for x in 10:
		for z in 10:
			var cell := Vector2i(x, z)
			var boundary := x == 0 or x == 9 or z == 0 or z == 9
			var entrance := z == 9 and x in entrance_columns
			if boundary and not entrance:
				building.wall_cells.append(cell)
				item.set_effect(cell, _full_cover())
			elif entrance:
				building.entrance_cells.append(cell)
				building.entrance_directions[cell] = Vector2i.DOWN
			else:
				building.usable_floor_cells.append(cell)
				building.roof_cells.append(cell)
	for x in entrance_columns:
		item.clearance_cells.append(Vector2i(x, 10))
		item.add_connection(Vector2i(x, 9), Vector2i.DOWN, EnvironmentModuleConnection.Type.EXTERIOR_ACCESS)
		item.add_connection(Vector2i(x, 8), Vector2i.UP, EnvironmentModuleConnection.Type.INTERIOR_ACCESS)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.OBJECTIVE, [Vector2i(4, 4), Vector2i(5, 4)])
	item.add_suitability(EnvironmentModuleDefinition.Suitability.SPAWN, [Vector2i(2, 2), Vector2i(3, 2)])
	_add_service_shell_visuals(item)
	building.module = item
	return building

static func _add_service_shell_visuals(item: EnvironmentModuleDefinition) -> void:
	var wall := Color("515a78")
	var roof := Color("30384f")
	var floor_color := Color("687176")
	var accent := Color("d99d35")
	var glass := Color("87a9bc")
	item.add_box_visual("InteriorFloor", Vector3(4.5, 0.04, 4.5), Vector3(8.0, 0.08, 8.0), floor_color)
	item.add_box_visual("BackWall", Vector3(4.5, 1.7, 0.0), Vector3(10.0, 3.4, 0.22), wall)
	item.add_box_visual("LeftWall", Vector3(0.0, 1.7, 4.5), Vector3(0.22, 3.4, 8.8), wall)
	item.add_box_visual("RightWall", Vector3(9.0, 1.7, 4.5), Vector3(0.22, 3.4, 8.8), wall)
	item.add_box_visual("FrontWallLeft", Vector3(1.0, 1.7, 9.0), Vector3(3.0, 3.4, 0.22), wall)
	item.add_box_visual("FrontWallRight", Vector3(8.0, 1.7, 9.0), Vector3(3.0, 3.4, 0.22), wall)
	item.add_box_visual("EntranceLintel", Vector3(4.5, 3.12, 9.0), Vector3(4.0, 0.56, 0.22), accent)
	item.add_box_visual("Roof", Vector3(4.5, 3.52, 4.5), Vector3(10.2, 0.20, 10.2), roof)
	# Flush facade details provide readable windows without changing the shell's
	# structural envelope or tactical line-of-sight contract.
	item.add_box_visual("BackWindow", Vector3(4.5, 2.0, -0.12), Vector3(3.8, 1.25, 0.04), glass, &"decorative")
	item.add_box_visual("LeftWindow", Vector3(-0.12, 2.0, 4.5), Vector3(0.04, 1.25, 3.8), glass, &"decorative")
	item.add_box_visual("RightWindow", Vector3(9.12, 2.0, 4.5), Vector3(0.04, 1.25, 3.8), glass, &"decorative")

static func _loading_canopy() -> EnvironmentBuildingDefinition:
	var building := EnvironmentBuildingDefinition.new(&"loading_canopy", &"covered_loading_area", EnvironmentBuildingDefinition.Enclosure.OPEN_SHELTER, Vector2i(8, 6))
	building.notes = "Intentionally open on every side; four supports carry a roof over usable loading space."
	var item := EnvironmentModuleDefinition.new(&"industrial_loading_canopy", &"authored_buildings", building.parcel_size)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.LOADING_DOCK)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ONE, "Open shelter contract: supports and roof are deliberate; missing walls are not an incomplete building.")
	item.set_visual_envelope(AABB(Vector3(-0.35, 0.0, -0.35), Vector3(7.7, 3.5, 5.7)))
	var supports: Array[Vector2i] = [Vector2i.ZERO, Vector2i(7, 0), Vector2i(0, 5), Vector2i(7, 5)]
	for x in 8:
		for z in 6:
			var cell := Vector2i(x, z)
			building.roof_cells.append(cell)
			if cell in supports:
				building.wall_cells.append(cell)
				item.set_effect(cell, _full_cover(3.2))
			else:
				building.usable_floor_cells.append(cell)
	item.add_connection(Vector2i(3, 5), Vector2i.DOWN, EnvironmentModuleConnection.Type.LOADING)
	item.add_connection(Vector2i(4, 5), Vector2i.DOWN, EnvironmentModuleConnection.Type.LOADING)
	item.add_suitability(EnvironmentModuleDefinition.Suitability.OBJECTIVE, [Vector2i(3, 2), Vector2i(4, 2)])
	var steel := Color("535f78")
	var roof := Color("343d50")
	var stripe := Color("d99d35")
	for support in supports:
		item.add_box_visual("CanopySupport", Vector3(support.x, 1.55, support.y), Vector3(0.38, 3.1, 0.38), steel)
	item.add_box_visual("CanopyRoof", Vector3(3.5, 3.25, 2.5), Vector3(7.7, 0.22, 5.7), roof)
	item.add_box_visual("CanopyStripe", Vector3(3.5, 2.85, 5.16), Vector3(7.2, 0.28, 0.08), stripe, &"decorative")
	building.module = item
	return building

static func _prebuilt_industrial_shell() -> EnvironmentBuildingDefinition:
	var building := EnvironmentBuildingDefinition.new(&"city_industrial_shell", &"sealed_industrial_building", EnvironmentBuildingDefinition.Enclosure.PREBUILT_SHELL, Vector2i(14, 14))
	building.notes = "Complete vendor-authored exterior used as a sealed tactical mass until a matching interior and entrance are authored."
	var shell_candidates := [
		"city_kit_industrial/building-h", "city_kit_industrial/building-i",
		"city_kit_industrial/building-j", "city_kit_industrial/building-k",
		"city_kit_industrial/building-o",
	]
	building.source_assets = Semantics.generation_candidates(shell_candidates, {}, "complete_building")
	var item := EnvironmentModuleDefinition.new(&"industrial_building_shell", &"city_industrial_buildings", building.parcel_size)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.SHOP)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ZERO, "Complete reviewed City Kit shell; sealed and exterior-only until an interior is authored.")
	for cell in item.footprint_cells:
		item.set_effect(cell, _full_cover())
	item.set_visual_envelope(AABB(Vector3.ZERO, Vector3(14.0, 10.0, 14.0)))
	# These vendor scenes are monolithic exterior shells. Their decoration cannot
	# be separated without deriving a replacement scene, so the complete asset is
	# classified as structural for shell inspection.
	item.add_catalog_visual(building.source_assets, Vector2(6.5, 6.5), 0, Vector3.ZERO, &"structural")
	building.module = item
	return building

static func _full_cover(height := 3.4) -> Dictionary:
	return {
		"interaction": EnvironmentModuleDefinition.CellInteraction.BLOCKED,
		"cover_type": MapCellData.CoverType.FULL,
		"cover_height": height,
		"walkable": false,
		"can_stop": false,
		"blocks_los": true,
		"movement_cost": 1,
	}
