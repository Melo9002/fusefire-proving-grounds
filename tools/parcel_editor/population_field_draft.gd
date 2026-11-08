class_name PopulationFieldDraft
extends RefCounted
## Editor-only permission fields over reviewed authored occupant sockets.
## A field cannot manufacture compatible geometry or tactical contracts.
const PRESETS := {
	"parking": ["car_kit/sedan", "car_kit/suv", "car_kit/taxi"],
	"containers": ["city_kit_industrial/shipping-container-a", "city_kit_industrial/shipping-container-b", "city_kit_industrial/shipping-container-c"],
	"equipment": ["factory_kit/machine", "factory_kit/machine-fortified"],
	"protected": [],
}
const PARKING_ROW := "parking_row"
const BAY_WIDTH := 3
const BAY_DEPTH := 5
const AISLE_DEPTH := 4
const PARKING_HEADROOM := 2.5
var parcel_id := ""
var revision := 0
var surfaces: Dictionary = {}
var fields: Array[Dictionary] = []
var history: Array = []
var future: Array = []
var next_id := 1
var last_error := ""
var preview_seed := 17
var occupancy := 65
var conflict_count := 0
var field_excluded_sockets := {}
var _saved_fields: Array[Dictionary] = []
var _saved_preview_settings := Vector2i(17, 65)

func is_dirty() -> bool:
	return fields != _saved_fields or Vector2i(preview_seed, occupancy) != _saved_preview_settings

func _mark_saved() -> void:
	_saved_fields = fields.duplicate(true)
	_saved_preview_settings = Vector2i(preview_seed, occupancy)

func begin(definition, scene_root: Node3D) -> void:
	parcel_id = String(definition.parcel_id)
	revision = definition.revision
	surfaces.clear()
	var authored: Dictionary = definition.population_surfaces(scene_root)
	for id in authored:
		var rect: Rect2i = authored[id].rect
		surfaces[String(id)] = {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "level": authored[id].level}
	fields.clear()
	history.clear()
	future.clear()
	next_id = 1
	preview_seed = 17
	occupancy = 65
	last_error = ""
	_mark_saved()

func add(surface: String, preset: String, rect: Rect2i, heading := 0) -> bool:
	if fields.size() >= 256:
		last_error = "Draft field limit reached (256)."
		return false
	var record := {"id": "field_%d" % next_id, "surface": surface, "preset": preset, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
	if preset == PARKING_ROW:
		record.heading = heading
	if not _valid(record): return false
	_checkpoint()
	fields.append(record)
	next_id += 1
	return true

## Drag along the aisle-facing edge. The selected heading points into the aisle.
static func parking_row_rect(first: Vector2i, last: Vector2i, heading: int) -> Rect2i:
	var direction := ParcelTransform.direction(Vector2i.DOWN, heading)
	if direction.y != 0:
		var horizontal_span := absi(last.x - first.x) + 1
		var horizontal_width := horizontal_span - posmod(horizontal_span, BAY_WIDTH)
		return Rect2i(mini(first.x, last.x), first.y - maxi(direction.y, 0) * (BAY_DEPTH - 1), horizontal_width, BAY_DEPTH)
	var span := absi(last.y - first.y) + 1
	var width := span - posmod(span, BAY_WIDTH)
	return Rect2i(first.x - maxi(direction.x, 0) * (BAY_DEPTH - 1), mini(first.y, last.y), BAY_DEPTH, width)

func parking_bays(sockets: Array[Dictionary], obstacles: Array[AABB], provisional: Dictionary = {}) -> Array[Dictionary]:
	var fixed := obstacles.duplicate()
	for socket in sockets:
		for turn: int in socket.allowed_yaw_turns:
			fixed.append(socket_bounds_at_turn(socket, turn))
	var results: Array[Dictionary] = []
	var accepted_bays: Array[AABB] = []
	var accepted_aisles: Array[AABB] = []
	var rows := fields.duplicate()
	if not provisional.is_empty():
		rows.append(provisional)
	for row: Dictionary in rows:
		if row.preset != PARKING_ROW:
			continue
		var heading := int(row.heading)
		var direction := ParcelTransform.direction(Vector2i.DOWN, heading)
		var bounds := rectangle(surfaces[row.surface])
		var level := int(surfaces[row.surface].level)
		var rect := rectangle(row)
		if not rect.has_area() or not bounds.encloses(rect):
			continue
		var aisle := rect
		if direction.y != 0:
			aisle.position.y = rect.end.y if direction.y > 0 else rect.position.y - AISLE_DEPTH
			aisle.size.y = AISLE_DEPTH
		else:
			aisle.position.x = rect.end.x if direction.x > 0 else rect.position.x - AISLE_DEPTH
			aisle.size.x = AISLE_DEPTH
		var aisle_volume := _parking_volume(aisle, level)
		var aisle_clear := bounds.encloses(aisle) and not _overlaps(aisle_volume, fixed) and not _overlaps(aisle_volume, accepted_bays)
		var length := rect.size.x if direction.y != 0 else rect.size.y
		var row_accepted := false
		for offset in range(0, length, BAY_WIDTH):
			var bay := Rect2i(rect.position + Vector2i(offset, 0), Vector2i(BAY_WIDTH, BAY_DEPTH)) if direction.y != 0 else Rect2i(rect.position + Vector2i(0, offset), Vector2i(BAY_DEPTH, BAY_WIDTH))
			var volume := _parking_volume(bay, level)
			var reason := ""
			if not aisle_clear:
				reason = "aisle blocked or outside surface"
			elif _overlaps(volume, fixed) or _overlaps(volume, accepted_bays) or _overlaps(volume, accepted_aisles):
				reason = "bay clearance conflict"
			elif not _parking_painted(row.surface, bay):
				reason = "outside parking paint or protected"
			if reason.is_empty():
				accepted_bays.append(volume)
				row_accepted = true
			var id := "row_bay_%s_%d_%d" % [row.surface, bay.position.x, bay.position.y]
			results.append({"id": id, "surface": row.surface, "level": level, "heading": heading, "rect": bay, "aisle": aisle, "reason": reason})
		if row_accepted:
			accepted_aisles.append(aisle_volume)
	return results

func parking_obstacles(definition, scene_root: Node3D) -> Array[AABB]:
	var obstacles: Array[AABB] = definition.fixed_population_obstacles(scene_root)
	for surface: Dictionary in surfaces.values():
		if surface.level <= 0:
			continue
		var rect := rectangle(surface)
		# Match the slab beneath an authored deck in AuthoredSceneMapCompiler.
		obstacles.append(AABB(Vector3(rect.position.x - 0.5, surface.level - 0.22, rect.position.y - 0.5), Vector3(rect.size.x, 0.22, rect.size.y)))
	return obstacles

func _parking_painted(surface: String, bay: Rect2i) -> bool:
	for x in range(bay.position.x, bay.end.x):
		for z in range(bay.position.y, bay.end.y):
			var covered := false
			for field in fields:
				if field.surface != surface or not rectangle(field).has_point(Vector2i(x, z)):
					continue
				if field.preset == "protected":
					return false
				if field.preset == "parking":
					covered = true
			if not covered:
				return false
	return true

static func _parking_volume(rect: Rect2i, level: int) -> AABB:
	return AABB(Vector3(rect.position.x - 0.5, level, rect.position.y - 0.5), Vector3(rect.size.x, PARKING_HEADROOM, rect.size.y))

static func _overlaps(volume: AABB, others: Array[AABB]) -> bool:
	for other in others:
		if volume.grow(-0.001).intersects(other):
			return true
	return false

static func socket_bounds_at_turn(socket: Dictionary, turn: int) -> AABB:
	var pivot: Vector3 = socket.local_position
	var bounds: AABB = socket.get("local_bounds", AABB(pivot, Vector3.ZERO))
	return Transform3D(Basis(Vector3.UP, -turn * PI * 0.5), pivot) * AABB(bounds.position - pivot, bounds.size)

func has_protected_overlap(surface: String, bounds: AABB) -> bool:
	var footprint := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
	for field in fields:
		if field.surface != surface or field.preset != "protected":
			continue
		var rect := rectangle(field)
		var area := Rect2(Vector2(rect.position) - Vector2.ONE * 0.5, Vector2(rect.size))
		if area.intersects(footprint):
			return true
	return false

func erase_at(surface: String, cell: Vector2i) -> bool:
	for index in range(fields.size() - 1, -1, -1):
		if fields[index].surface == surface and rectangle(fields[index]).has_point(cell):
			_checkpoint()
			fields.remove_at(index)
			return true
	return false

func _checkpoint() -> void:
	history.append(fields.duplicate(true))
	if history.size() > 64: history.pop_front()
	future.clear()

func undo() -> bool:
	if history.is_empty(): return false
	future.append(fields.duplicate(true))
	fields.assign(history.pop_back())
	return true

func redo() -> bool:
	if future.is_empty(): return false
	history.append(fields.duplicate(true))
	fields.assign(future.pop_back())
	return true

func preview(sockets: Array[Dictionary], map_seed: int, density: int, obstacles: Array[AABB] = []) -> Array[Dictionary]:
	preview_seed = map_seed
	occupancy = clampi(density, 0, 100)
	conflict_count = 0
	field_excluded_sockets.clear()
	var accepted: Array[Dictionary] = []
	var occupied: Array[AABB] = []
	var ordered := sockets.duplicate()
	ordered.sort_custom(func(a, b): return String(a.socket_id) < String(b.socket_id))
	for socket in ordered:
		var key := JSON.stringify([map_seed, parcel_id, String(socket.surface_id), String(socket.socket_id)])
		var turns: PackedInt32Array = socket.allowed_yaw_turns
		var turn_index := posmod((key + "/heading_v1").sha256_text().substr(0, 8).hex_to_int(), turns.size())
		var bounds := socket_bounds_at_turn(socket, turns[turn_index])
		if bounds.size.x <= 0 or bounds.size.z <= 0:
			conflict_count += 1
			continue
		if has_protected_overlap(String(socket.surface_id), bounds):
			field_excluded_sockets[socket.socket_id] = true
			continue
		var permission_cells := {}
		for field in fields:
			if field.surface != String(socket.surface_id) or field.preset == PARKING_ROW: continue
			var rect := rectangle(field)
			if PRESETS[field.preset].has(String(socket.asset_id)):
				for x in range(rect.position.x, rect.end.x):
					for z in range(rect.position.y, rect.end.y):
						permission_cells[Vector2i(x, z)] = true
		var permitted := true
		for x in range(floori(bounds.position.x + 0.5), ceili(bounds.end.x + 0.5 - 0.00001)):
			for z in range(floori(bounds.position.z + 0.5), ceili(bounds.end.z + 0.5 - 0.00001)):
				if not permission_cells.has(Vector2i(x, z)): permitted = false
		if not permitted:
			field_excluded_sockets[socket.socket_id] = true
			continue
		if posmod((key + "/occupancy_v1").sha256_text().substr(0, 8).hex_to_int(), 100) >= clampi(density, 0, 100): continue
		var intersects := false
		for obstacle in obstacles + occupied:
			if bounds.grow(-0.001).intersects(obstacle):
				intersects = true
				break
		if intersects:
			conflict_count += 1
			continue
		occupied.append(bounds)
		accepted.append({"socket_id": socket.socket_id, "asset_id": socket.asset_id, "yaw_turns": turns[turn_index]})
	return accepted

static func rectangle(record: Dictionary) -> Rect2i:
	var r: Array = record.rect
	return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))

func _valid(record: Dictionary) -> bool:
	if not record.get("surface") is String or not surfaces.has(record.surface) or (not PRESETS.has(record.get("preset")) and record.get("preset") != PARKING_ROW) or not record.get("id") is String:
		last_error = "Unknown surface, preset or field identity."
		return false
	var raw: Variant = record.get("rect")
	if not raw is Array or raw.size() != 4:
		last_error = "Invalid field rectangle."
		return false
	for value in raw:
		if not (value is int or value is float) or float(value) != int(value):
			last_error = "Field coordinates must be integer cells."
			return false
	var rect := rectangle(record)
	if record.preset == PARKING_ROW:
		var heading: Variant = record.get("heading")
		if not (heading is int or heading is float) or not is_finite(float(heading)) or float(heading) != int(heading) or int(heading) < 0 or int(heading) > 3:
			last_error = "Parking row needs a cardinal aisle heading."
			return false
		var along_x := posmod(int(heading), 2) == 0
		if (rect.size.y if along_x else rect.size.x) != BAY_DEPTH or posmod(rect.size.x if along_x else rect.size.y, BAY_WIDTH) != 0:
			last_error = "Parking row must contain whole 3 × 5 bays."
			return false
	var bounds: Array = surfaces[record.surface].rect
	if rect.size.x <= 0 or rect.size.y <= 0 or not Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3])).encloses(rect):
		last_error = "Field must remain inside the selected surface."
		return false
	return true

func path() -> String:
	return "user://parcel_fields/%s.fields.json" % parcel_id

func save_to(destination: String) -> bool:
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		last_error = "Cannot open field draft for writing."
		return false
	file.store_string(JSON.stringify({"schema": 1, "parcel_id": parcel_id, "revision": revision, "surfaces": surfaces, "fields": fields, "preview_seed": preview_seed, "occupancy": occupancy}, "\t"))
	file.close()
	_mark_saved()
	return true

func load_from(source: String) -> bool:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		last_error = "No saved field draft found."
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		last_error = "Invalid field draft JSON."
		return false
	var record: Variant = parser.data
	if not record is Dictionary or record.get("schema") != 1 or record.get("parcel_id") != parcel_id or record.get("revision") != revision or not _same_surfaces(record.get("surfaces")) or not record.get("fields") is Array:
		last_error = "Incompatible field draft, parcel revision or surfaces."
		return false
	var ids := {}
	if record.fields.size() > 256:
		last_error = "Draft exceeds the 256-field limit."
		return false
	for key in ["preview_seed", "occupancy"]:
		var number: Variant = record.get(key, 0)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != int(number):
			last_error = "Invalid preview settings."
			return false
	for field in record.fields:
		if not field is Dictionary or not _valid(field): return false
		if ids.has(field.id):
			last_error = "Duplicate field identity."
			return false
		ids[field.id] = true
	_checkpoint()
	fields.assign(record.fields)
	preview_seed = int(record.get("preview_seed", 17))
	occupancy = clampi(int(record.get("occupancy", 65)), 0, 100)
	next_id = 1
	while ids.has("field_%d" % next_id): next_id += 1
	_mark_saved()
	return true

func _same_surfaces(value: Variant) -> bool:
	if not value is Dictionary or value.size() != surfaces.size(): return false
	for id in surfaces:
		if not value.get(id) is Dictionary: return false
		var candidate: Dictionary = value[id]
		if candidate.get("level") != surfaces[id].level or not candidate.get("rect") is Array or candidate.rect.size() != 4: return false
		for index in 4:
			if candidate.rect[index] != surfaces[id].rect[index]: return false
	return true
