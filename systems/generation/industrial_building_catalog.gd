class_name IndustrialBuildingCatalog
extends RefCounted
## Reusable architectural assemblies.  Individual mesh modules continue to
## live in IndustrialModuleCatalog; procedural parcels consume these validated
## whole-building contracts instead of treating facades as buildings.

const INDUSTRIAL := "res://art/environments/kenney/city_kit_industrial/models/"
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const ShellProfiles = preload("res://systems/generation/industrial_building_placement_profiles.gd")

static func create() -> Dictionary:
	var result := {}
	for building in [_service_building(), _loading_canopy(), _prebuilt_industrial_shell()]:
		result[building.assembly_id] = building
	for asset_id in ShellProfiles.ids():
		var building := _profiled_industrial_shell(asset_id)
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

static func certified_assemblies() -> Dictionary:
	var result := {}
	for building: EnvironmentBuildingDefinition in create().values():
		if building.assembly_contract != null and building.assembly_contract.is_certified(building):
			result[building.assembly_id] = building
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

static func _profiled_industrial_shell(asset_id: String) -> EnvironmentBuildingDefinition:
	var profile := ShellProfiles.profile_for_asset(asset_id)
	var suffix := asset_id.get_file().trim_prefix("building-")
	var module_id := ShellProfiles.module_id_for_asset(asset_id)
	var footprint: Vector2i = profile.size
	var building := EnvironmentBuildingDefinition.new(
		StringName("city_industrial_shell_%s" % suffix),
		&"sealed_industrial_building",
		EnvironmentBuildingDefinition.Enclosure.PREBUILT_SHELL,
		footprint
	)
	building.notes = "Reviewed complete exterior shell with a calibrated per-asset footprint and a protected street/service apron."
	building.source_assets = [asset_id]
	var item := EnvironmentModuleDefinition.new(module_id, &"city_industrial_buildings", footprint)
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.STRUCTURE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.SHOP)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ZERO, "Calibrated sealed City Kit shell; local +Z is the normalized frontage.")
	for cell in item.footprint_cells:
		item.set_effect(cell, _full_cover(float(profile.bounds.y)))
	# The three-cell apron protects visible doors/loading faces and provides a
	# readable transition to the road-facing paved parcel.  It remains walkable
	# because clearance is a placement rule, not tactical occupancy.
	var apron_width := mini(6, footprint.x)
	var apron_start := floori(float(footprint.x - apron_width) * 0.5)
	for z in range(footprint.y, footprint.y + ShellProfiles.FRONTAGE_DEPTH):
		for x in range(apron_start, apron_start + apron_width):
			item.clearance_cells.append(Vector2i(x, z))
	var calibrated_size: Vector3 = profile.bounds
	var center := Vector2(float(footprint.x - 1) * 0.5, float(footprint.y - 1) * 0.5)
	item.set_visual_envelope(AABB(
		Vector3(center.x - calibrated_size.x * 0.5, 0.0, center.y - calibrated_size.z * 0.5),
		calibrated_size
	))
	var visual_yaw := 2 if profile.face == "-z" else 0
	item.add_catalog_visual([asset_id], center, visual_yaw, Vector3.ZERO, &"structural")
	building.module = item
	if asset_id == "city_kit_industrial/building-i":
		building.assembly_contract = _certified_building_i_contract()
	return building

static func _certified_building_i_contract() -> EnvironmentAssemblyContract:
	# These values are deliberately pinned rather than copied from the current
	# module. A changed placement profile must fail revalidation instead of
	# silently rewriting the certification record around the new values.
	var contract := EnvironmentAssemblyContract.new(&"city_industrial_shell_i")
	contract.role = EnvironmentAssemblyContract.AssemblyRole.SEALED_BUILDING_SHELL
	contract.completeness = EnvironmentAssemblyContract.Completeness.COMPLETE_EXTERIOR
	contract.components = [{
		"asset_id": "city_kit_industrial/building-i",
		"role": "shell",
		"required": true,
		"local_position": Vector3(5.0, 0.0, 6.0),
		"yaw_quarters": 2,
		"source_working_face": "-z",
		"geometry_sha256": "12d9be598becf2b6d3758d23aba6c573ca2701fca5e77870d2ee5645647765ca",
		"calibration_signature": "de03f9924c7afc0064c141aaec79605049453dddc10390bccbd461c6e415e773",
	}]
	for x in 11:
		for z in 13:
			contract.tactical_footprint.append(Vector2i(x, z))
	contract.approved_visual_envelope = AABB(
		Vector3(-0.1406890153885, 0.0, -0.50000035762785),
		Vector3(10.281378030777, 7.33541011810303, 13.0000007152557)
	)
	for z in range(13, 16):
		for x in range(2, 8):
			contract.required_clearance_cells.append(Vector2i(x, z))
	contract.relationships = {
		"street_frontage": {
			"direction": Vector2i.DOWN,
			"access_kind": "exterior_frontage_apron",
			"access_cells": contract.required_clearance_cells.duplicate(),
			"interior_access": false,
		}
	}
	contract.supported_rotations = [0, 1, 2, 3]
	contract.certification_state = EnvironmentAssemblyContract.CertificationState.CERTIFIED
	return contract

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
