class_name UrbanPlotCatalog
extends RefCounted
## Bounded urban proof: two authored places, not a road or city grammar.

const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const STREET_A := &"urban_service_street_a"
const STREET_A_REVISION := 1
const COURTYARD_B := &"urban_signal_courtyard_b"
const COURTYARD_B_REVISION := 1
const MAP_SIZE := Vector2i(64, 64)
const StreetScene = preload("res://art/environments/authored/plots/urban_service_street_a.tscn")
const CourtyardScene = preload("res://art/environments/authored/plots/urban_signal_courtyard_b.tscn")

static func definition(id: StringName = STREET_A) -> Dictionary:
	for candidate in all():
		if candidate.plot_id == id:
			return candidate
	return {}

static func all() -> Array[Dictionary]:
	return [_street_definition(), _courtyard_definition()]

static func get_definition(id: StringName) -> Dictionary:
	return definition(id)

static func choose(map_seed: int) -> Dictionary:
	var plots := all()
	return plots[posmod(map_seed, plots.size())].duplicate(true)

static func _street_definition() -> Dictionary:
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

static func _courtyard_definition() -> Dictionary:
	return {
		"plot_id": COURTYARD_B,
		"display_name": "Industrial signal courtyard",
		"revision": COURTYARD_B_REVISION,
		"map_size": MAP_SIZE,
		"scene": CourtyardScene,
		"road_rects": [],
		"circulation_rects": [Rect2i(16, 16, 32, 32), Rect2i(0, 48, 64, 16)],
		"slots": [
			_slot(&"north_process", ParcelCatalog.PROCESS, Vector2i(16, 16), Vector3i(16, 0, 0), 0, Vector3i(23, 0, 15), Vector2i.DOWN, 2, &"service"),
			_slot(&"north_storage", ParcelCatalog.STORAGE, Vector2i(16, 16), Vector3i(32, 0, 0), 0, Vector3i(38, 0, 15), Vector2i.DOWN, 4, &"service"),
			_slot(&"west_gallery", ParcelCatalog.URBAN_GALLERY, Vector2i(16, 32), Vector3i(0, 0, 16), 2, Vector3i(15, 0, 35), Vector2i.RIGHT, 8, &"courtyard_edge"),
			_slot(&"signal_courtyard", ParcelCatalog.URBAN_COURTYARD, Vector2i(32, 32), Vector3i(16, 0, 16), 0, Vector3i(28, 0, 47), Vector2i.DOWN, 8, &"courtyard_entry"),
			_slot(&"east_gallery", ParcelCatalog.URBAN_GALLERY, Vector2i(16, 32), Vector3i(48, 0, 16), 0, Vector3i(48, 0, 28), Vector2i.LEFT, 8, &"courtyard_edge"),
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
