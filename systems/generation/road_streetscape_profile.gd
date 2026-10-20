class_name RoadStreetscapeProfile
extends RefCounted
## Shared visual and placement contract for the ten-cell road grammar.
##
## The profile describes presentation geometry and safe furniture slots. It
## never changes MapData: road cells remain ordinary authored ground, while
## tactical obstacles continue to opt into explicit module cell effects.

const TILE_SIZE := 10
const CARRIAGEWAY_WIDTH := 6.0
const SIDEWALK_WIDTH := 2.0
const SIDEWALK_HEIGHT := 0.10
const CURB_WIDTH := 0.12
const CURB_HEIGHT := 0.16
const ROAD_HEIGHT := 0.035
const MARKING_HEIGHT := 0.012

const ASPHALT := &"asphalt"
const SIDEWALK := &"sidewalk"
const CURB := &"curb"
const MARKING := &"marking"

static func surface_sections(component_id: StringName) -> Array[Dictionary]:
	match component_id:
		&"road_straight":
			return _straight_sections()
		&"road_crossroad":
			return _crossroad_sections()
		&"road_intersection_t":
			return _t_sections()
	return []

static func approach_fixture(direction: Vector2i) -> Dictionary:
	# One fixture per active approach. Slots occupy the outer sidewalk corner,
	# leaving the inner two-cell pedestrian route and the carriageway open.
	match direction:
		Vector2i.UP: return {"cell": Vector2i(8, 1), "yaw": 1}
		Vector2i.RIGHT: return {"cell": Vector2i(8, 8), "yaw": 2}
		Vector2i.DOWN: return {"cell": Vector2i(1, 8), "yaw": 3}
		Vector2i.LEFT: return {"cell": Vector2i(1, 1), "yaw": 0}
	return {}

static func straight_fixture_slot(index: int, opposite_side := false) -> Dictionary:
	# Longitudinal positions 2 and 7 stay outside the central frontage band
	# used by building entrances. X 0/9 is the outer sidewalk lane; X 1/8
	# remains a clear pedestrian path beside the carriageway.
	var side := 9 if posmod(index, 2) != 0 else 0
	if opposite_side:
		side = 9 - side
	var pair_index := floori(float(index) / 2.0)
	var along := 7 if posmod(pair_index, 2) != 0 else 2
	return {
		"cell": Vector2i(side, along),
		"yaw": 0 if side == 0 else 2,
		# Curved and square lamp heads extend toward model-local -Z. These
		# quarter turns point that working face inward from either sidewalk.
		"inward_yaw": 1 if side == 0 else 3,
	}

static func sidewalk_cells(component_id: StringName) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	match component_id:
		&"road_straight":
			for z in TILE_SIZE:
				for x in [0, 1, 8, 9]:
					result.append(Vector2i(x, z))
		&"road_crossroad":
			for z in TILE_SIZE:
				for x in TILE_SIZE:
					if (x < 2 or x > 7) and (z < 2 or z > 7):
						result.append(Vector2i(x, z))
		&"road_intersection_t":
			for z in TILE_SIZE:
				for x in TILE_SIZE:
					if z < 2 or (z > 7 and (x < 2 or x > 7)):
						result.append(Vector2i(x, z))
	return result

static func _straight_sections() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		_section(ASPHALT, Vector2(4.5, 4.5), Vector2(CARRIAGEWAY_WIDTH, 10.0)),
		_section(SIDEWALK, Vector2(0.5, 4.5), Vector2(SIDEWALK_WIDTH, 10.0)),
		_section(SIDEWALK, Vector2(8.5, 4.5), Vector2(SIDEWALK_WIDTH, 10.0)),
		_section(CURB, Vector2(1.5, 4.5), Vector2(CURB_WIDTH, 10.0)),
		_section(CURB, Vector2(7.5, 4.5), Vector2(CURB_WIDTH, 10.0)),
	]
	for z in [1.0, 4.5, 8.0]:
		result.append(_section(MARKING, Vector2(4.5, z), Vector2(0.10, 1.8)))
	return result

static func _crossroad_sections() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		_section(ASPHALT, Vector2(4.5, 4.5), Vector2(CARRIAGEWAY_WIDTH, 10.0)),
		_section(ASPHALT, Vector2(4.5, 4.5), Vector2(10.0, CARRIAGEWAY_WIDTH)),
	]
	for center in [Vector2(0.5, 0.5), Vector2(8.5, 0.5), Vector2(0.5, 8.5), Vector2(8.5, 8.5)]:
		result.append(_section(SIDEWALK, center, Vector2(2.0, 2.0)))
	_add_corner_curbs(result, Vector2(0.5, 0.5), 1, 1)
	_add_corner_curbs(result, Vector2(8.5, 0.5), -1, 1)
	_add_corner_curbs(result, Vector2(0.5, 8.5), 1, -1)
	_add_corner_curbs(result, Vector2(8.5, 8.5), -1, -1)
	return result

static func _t_sections() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		_section(ASPHALT, Vector2(4.5, 4.5), Vector2(10.0, CARRIAGEWAY_WIDTH)),
		_section(ASPHALT, Vector2(4.5, 8.5), Vector2(CARRIAGEWAY_WIDTH, 2.0)),
		_section(SIDEWALK, Vector2(4.5, 0.5), Vector2(10.0, 2.0)),
		_section(SIDEWALK, Vector2(0.5, 8.5), Vector2(2.0, 2.0)),
		_section(SIDEWALK, Vector2(8.5, 8.5), Vector2(2.0, 2.0)),
		_section(CURB, Vector2(4.5, 1.5), Vector2(10.0, CURB_WIDTH)),
	]
	_add_corner_curbs(result, Vector2(0.5, 8.5), 1, -1)
	_add_corner_curbs(result, Vector2(8.5, 8.5), -1, -1)
	return result

static func _add_corner_curbs(result: Array[Dictionary], center: Vector2, x_sign: int, z_sign: int) -> void:
	result.append(_section(CURB, Vector2(center.x + 1.0 * x_sign, center.y), Vector2(CURB_WIDTH, 2.0)))
	result.append(_section(CURB, Vector2(center.x, center.y + 1.0 * z_sign), Vector2(2.0, CURB_WIDTH)))

static func _section(kind: StringName, center: Vector2, size: Vector2) -> Dictionary:
	return {"kind": kind, "center": center, "size": size}
