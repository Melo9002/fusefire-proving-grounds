extends RefCounted
## Calibrated vehicle sources shared by preview and authored export.
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const ParkingReference = preload("res://art/environments/authored/parcels/industrial_office_parking.tscn")
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")
var _parking_reference: Node3D
var _vehicle_templates: Array[Dictionary] = []

func candidate(bay: Dictionary, map_seed: int, parcel_id: String) -> Dictionary:
	if not is_instance_valid(_parking_reference):
		_parking_reference = ParkingReference.instantiate()
		for node_name in ["SedanWest", "SuvMid", "TaxiEast"]:
			var vehicle := _parking_reference.get_node(node_name) as Node3D
			var bounds := AssetPlacement.mesh_bounds(vehicle, vehicle.transform.affine_inverse())
			var solid := vehicle.get_node("TacticalVolume") as Node3D
			var dimensions: Vector3 = solid.get_meta("solid_size")
			bounds = bounds.merge(solid.transform * AABB(-dimensions * 0.5, dimensions))
			if maxf(absf(bounds.position.x), absf(bounds.end.x)) > Session.BAY_WIDTH * 0.5 or maxf(absf(bounds.position.z), absf(bounds.end.z)) > Session.BAY_DEPTH * 0.5:
				continue
			if bounds.position.y < -0.05 or bounds.end.y > Session.PARKING_HEADROOM:
				continue
			_vehicle_templates.append({"template": vehicle, "asset_id": String(vehicle.get_meta("asset_id")), "bounds": bounds})
	if _vehicle_templates.is_empty(): return {}
	var key := JSON.stringify([map_seed, parcel_id, bay.id, "parking_vehicle_v1"])
	var index := posmod(key.sha256_text().substr(0, 8).hex_to_int(), _vehicle_templates.size())
	var option: Dictionary = _vehicle_templates[index]
	var rect: Rect2i = bay.rect
	var pivot := Vector3(rect.position.x + (rect.size.x - 1) * 0.5, bay.level, rect.position.y + (rect.size.y - 1) * 0.5)
	var transform := Transform3D(Basis(Vector3.UP, -int(bay.heading) * PI * 0.5), pivot)
	return {"socket_id": StringName(bay.id), "surface_id": bay.surface, "asset_id": option.asset_id, "allowed_yaw_turns": PackedInt32Array([0, 2]), "local_position": pivot, "local_bounds": transform * option.bounds, "heading": bay.heading, "template": option.template}

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_parking_reference):
		_parking_reference.free()
