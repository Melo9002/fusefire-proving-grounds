class_name UrbanPlotCatalog
extends RefCounted
## First bounded urban proof. This is one authored street, not a road grammar.

const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const STREET_A := &"urban_service_street_a"
const STREET_A_REVISION := 1
const MAP_SIZE := Vector2i(64, 64)
const StreetScene = preload("res://art/environments/authored/plots/urban_service_street_a.tscn")

static func definition() -> Dictionary:
	return {
		"plot_id": STREET_A,
		"display_name": "Industrial office service street",
		"revision": STREET_A_REVISION,
		"map_size": MAP_SIZE,
		"scene": StreetScene,
		"road_rects": [Rect2i(0, 27, 64, 5)],
		"slots": [
			_slot(&"process", ParcelCatalog.PROCESS, Vector2i(16, 16), Vector3i(8, 0, 11), 0, Vector3i(15, 0, 26), Vector2i.DOWN, 2, &"service"),
			_slot(&"storage", ParcelCatalog.STORAGE, Vector2i(16, 16), Vector3i(40, 0, 11), 0, Vector3i(46, 0, 26), Vector2i.DOWN, 4, &"service"),
			_slot(&"office_frontage", ParcelCatalog.URBAN_FRONTAGE, Vector2i(32, 32), Vector3i(16, 0, 32), 0, Vector3i(28, 0, 32), Vector2i.UP, 8, &"street_frontage"),
		],
	}

static func _slot(id: StringName, role: StringName, size: Vector2i, origin: Vector3i, rotation: int, cell: Vector3i, outward: Vector2i, width: int, kind: StringName) -> Dictionary:
	return {
		"slot_id": id,
		"role": role,
		"size": size,
		"origin": origin,
		"rotation": rotation,
		"required_interface": {"kind": kind, "cell": cell, "outward": outward, "width": width},
	}
