class_name RefineryPlotCatalog
extends RefCounted
## Two deliberately authored refinery sites. A plot owns the required parcel
## slots and exact service interfaces; parcels declare what they offer.

const SITE_A := &"refinery_site_a"
const SITE_B := &"refinery_site_b"
const REVISION := 2
const MAP_SIZE := Vector2i(64, 64)

static func all() -> Array[Dictionary]:
	return [_site_a(), _site_b()]

static func get_definition(plot_id: StringName) -> Dictionary:
	for definition in all():
		if definition.plot_id == plot_id:
			return definition.duplicate(true)
	return {}

static func choose(seed: int) -> Dictionary:
	var definitions := all()
	return definitions[posmod(seed, definitions.size())].duplicate(true)

static func _slot(id: StringName, role: StringName, size: Vector2i, origin: Vector3i, rotation: int, cell: Vector3i, outward: Vector2i, width: int) -> Dictionary:
	return {
		"slot_id": id,
		"role": role,
		"size": size,
		"origin": origin,
		"rotation": rotation,
		"required_interface": {"kind": &"service", "cell": cell, "outward": outward, "width": width},
	}

static func _site_a() -> Dictionary:
	return {
		"plot_id": SITE_A, "display_name": "Split-yard refinery", "revision": REVISION, "map_size": MAP_SIZE,
		"circulation": "Two northern work pads feed a southern loading apron.",
		"road_rects": [Rect2i(0, 24, 64, 5)],
		"slots": [
			_slot(&"process", &"process", Vector2i(16, 16), Vector3i(8, 0, 8), 0, Vector3i(15, 0, 23), Vector2i.DOWN, 2),
			_slot(&"storage", &"storage", Vector2i(16, 16), Vector3i(40, 0, 8), 0, Vector3i(46, 0, 23), Vector2i.DOWN, 4),
			_slot(&"loading", &"loading_service", Vector2i(16, 32), Vector3i(24, 0, 29), 2, Vector3i(33, 0, 29), Vector2i.UP, 4),
		],
	}

static func _site_b() -> Dictionary:
	return {
		"plot_id": SITE_B, "display_name": "Service-spine refinery", "revision": REVISION, "map_size": MAP_SIZE,
		"circulation": "A service spine joins a sideways loading yard to separated process and storage pads.",
		"road_rects": [Rect2i(40, 0, 5, 64)],
		"slots": [
			_slot(&"process", &"process", Vector2i(16, 16), Vector3i(45, 0, 0), 1, Vector3i(45, 0, 7), Vector2i.LEFT, 2),
			_slot(&"loading", &"loading_service", Vector2i(16, 32), Vector3i(8, 0, 16), 3, Vector3i(39, 0, 25), Vector2i.RIGHT, 4),
			_slot(&"storage", &"storage", Vector2i(16, 16), Vector3i(45, 0, 32), 1, Vector3i(45, 0, 38), Vector2i.LEFT, 4),
		],
	}
