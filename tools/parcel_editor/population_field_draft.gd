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

func add(surface: String, preset: String, rect: Rect2i) -> bool:
	if fields.size() >= 256:
		last_error = "Draft field limit reached (256)."
		return false
	var record := {"id": "field_%d" % next_id, "surface": surface, "preset": preset, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
	if not _valid(record): return false
	_checkpoint()
	fields.append(record)
	next_id += 1
	return true

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
	var accepted: Array[Dictionary] = []
	var occupied: Array[AABB] = []
	var ordered := sockets.duplicate()
	ordered.sort_custom(func(a, b): return String(a.socket_id) < String(b.socket_id))
	for socket in ordered:
		var key := JSON.stringify([map_seed, parcel_id, String(socket.surface_id), String(socket.socket_id)])
		var turns: PackedInt32Array = socket.allowed_yaw_turns
		var turn_index := posmod((key + "/heading_v1").sha256_text().substr(0, 8).hex_to_int(), turns.size())
		var bounds: AABB = socket.get("local_bounds", AABB(socket.local_position, Vector3.ZERO))
		if bounds.size.x <= 0 or bounds.size.z <= 0:
			conflict_count += 1
			continue
		var pivot: Vector3 = socket.local_position
		bounds = Transform3D(Basis(Vector3.UP, -turns[turn_index] * PI * 0.5), pivot) * AABB(bounds.position - pivot, bounds.size)
		var point := Vector2i(roundi(socket.local_position.x), roundi(socket.local_position.z))
		var permitted := false
		var blocked := false
		var permission_cells := {}
		for field in fields:
			if field.surface != String(socket.surface_id): continue
			var rect := rectangle(field)
			var area := Rect2(Vector2(rect.position) - Vector2.ONE * 0.5, Vector2(rect.size))
			var footprint := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
			if field.preset == "protected":
				if area.intersects(footprint) or rect.has_point(point): blocked = true
			elif PRESETS[field.preset].has(String(socket.asset_id)):
				for x in range(rect.position.x, rect.end.x):
					for z in range(rect.position.y, rect.end.y):
						permission_cells[Vector2i(x, z)] = true
		permitted = true
		for x in range(floori(bounds.position.x + 0.5), ceili(bounds.end.x + 0.5 - 0.00001)):
			for z in range(floori(bounds.position.z + 0.5), ceili(bounds.end.z + 0.5 - 0.00001)):
				if not permission_cells.has(Vector2i(x, z)): permitted = false
		if blocked or not permitted: continue
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
	if not record.get("surface") is String or not surfaces.has(record.surface) or not PRESETS.has(record.get("preset")) or not record.get("id") is String:
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
