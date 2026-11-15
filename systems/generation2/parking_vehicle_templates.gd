extends RefCounted
## Calibrated vehicle sources shared by draft previews and battle population.
const BAY_WIDTH := 3
const BAY_DEPTH := 5
const HEADROOM := 2.5
# Keep this order: it participates in deterministic seeded asset selection.
const VEHICLES := [
	preload("res://art/environments/authored/objects/sedan.tscn"),
	preload("res://art/environments/authored/objects/suv.tscn"),
	preload("res://art/environments/authored/objects/taxi.tscn"),
]
const MIXED_VEHICLES := [
	preload("res://art/environments/authored/objects/ambulance.tscn"),
	preload("res://art/environments/authored/objects/van.tscn"),
]
const CLASSIC := "classic"
const MIXED := "mixed"
const CLASSIC_IDS := ["car_kit/sedan", "car_kit/suv", "car_kit/taxi"]
const ShapeRules = preload("res://systems/generation2/tactical_shape_rules.gd")
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")
var _loaded_pools := {}
var _loaded_scenes := {}
var _vehicle_templates: Array[Dictionary] = []

func candidate(bay: Dictionary, map_seed: int, parcel_id: String) -> Dictionary:
	var assets := asset_ids(String(bay.get("vehicle_pool", CLASSIC)))
	if assets.is_empty(): return {}
	var key := JSON.stringify([map_seed, parcel_id, bay.id, "parking_vehicle_v1"])
	return candidate_for_asset(bay, assets[posmod(key.sha256_text().substr(0, 8).hex_to_int(), assets.size())])

func asset_ids(pool := CLASSIC) -> PackedStringArray:
	if pool not in [CLASSIC, MIXED]: return PackedStringArray()
	if not _loaded_pools.has(pool):
		_loaded_pools[pool] = true
		var scenes: Array = VEHICLES + MIXED_VEHICLES if pool == MIXED else VEHICLES
		for scene: PackedScene in scenes:
			if _loaded_scenes.has(scene.resource_path): continue
			_loaded_scenes[scene.resource_path] = true
			var vehicle := scene.instantiate() as Node3D
			var bounds := AssetPlacement.mesh_bounds(vehicle, vehicle.transform.affine_inverse())
			bounds = _include_solids(vehicle, Transform3D.IDENTITY, bounds)
			if maxf(absf(bounds.position.x), absf(bounds.end.x)) > BAY_WIDTH * 0.5 or maxf(absf(bounds.position.z), absf(bounds.end.z)) > BAY_DEPTH * 0.5 or bounds.position.y < -0.05 or bounds.end.y > HEADROOM:
				vehicle.free()
				continue
			_vehicle_templates.append({"template": vehicle, "asset_id": String(vehicle.get_meta("asset_id")), "bounds": bounds})
	var result := PackedStringArray()
	for option in _vehicle_templates:
		if pool == MIXED or option.asset_id in CLASSIC_IDS: result.append(option.asset_id)
	return result

func _include_solids(node: Node, transform: Transform3D, bounds: AABB) -> AABB:
	if ShapeRules.is_active_solid(node):
		var dimensions: Vector3 = node.get_meta("solid_size")
		bounds = bounds.merge(transform * AABB(-dimensions * 0.5, dimensions))
	for child in node.get_children():
		bounds = _include_solids(child, transform * child.transform if child is Node3D else transform, bounds)
	return bounds

func candidate_for_asset(bay: Dictionary, asset_id: String) -> Dictionary:
	if not _vehicle_templates.any(func(option): return option.asset_id == asset_id): asset_ids(MIXED)
	for option in _vehicle_templates:
		if option.asset_id == asset_id:
			return _position_candidate(bay, option)
	return {}

func _position_candidate(bay: Dictionary, option: Dictionary) -> Dictionary:
	var rect: Rect2i = bay.rect
	var pivot := Vector3(rect.position.x + (rect.size.x - 1) * 0.5, bay.level, rect.position.y + (rect.size.y - 1) * 0.5)
	var transform := Transform3D(Basis(Vector3.UP, -int(bay.heading) * PI * 0.5), pivot)
	return {"socket_id": StringName(bay.id), "surface_id": bay.surface, "asset_id": option.asset_id, "allowed_yaw_turns": PackedInt32Array([0, 2]), "local_position": pivot, "local_bounds": transform * option.bounds, "heading": bay.heading, "template": option.template}

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for option in _vehicle_templates:
			option.template.free()
