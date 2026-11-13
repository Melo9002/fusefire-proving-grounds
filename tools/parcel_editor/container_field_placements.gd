extends RefCounted
## Fit ground-level container positions into contiguous painted permission.
## The seed picks occupancy from these positions through the parcel resolver.

const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const Library = preload("res://tools/parcel_editor/parcel_placement_library.gd")
const ASSET := "city_kit_industrial/shipping-container-a"
const SLOT_SIZE := Vector2i(3, 5)
const MAX_POSITIONS := 4

static func candidates(draft, definition, root: Node3D, sockets: Array[Dictionary], obstacles: Array[AABB], template: Node3D) -> Array[Dictionary]:
	return inspect(draft, definition, root, sockets, obstacles, template).accepted

static func inspect(draft, definition, root: Node3D, sockets: Array[Dictionary], obstacles: Array[AABB], template: Node3D, provisional := {}) -> Dictionary:
	var result: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	var report := {"accepted": result, "rejected": rejected, "causes": {}, "limit_reached": false}
	var permitted := {}
	var fields: Array = draft.fields.duplicate()
	if not provisional.is_empty():
		fields.append(provisional)
	for field in fields:
		if field.preset != "containers" or field.surface != "ground":
			continue
		var rect := Session.rectangle(field)
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				permitted[Vector2i(x, z)] = true
	if permitted.is_empty():
		return report
	var unavailable: Array[Dictionary] = []
	for obstacle in obstacles:
		unavailable.append({"bounds": obstacle, "reason": _obstacle_reason(root, obstacle)})
	for socket in sockets:
		for turn: int in socket.allowed_yaw_turns:
			unavailable.append({"bounds": Session.socket_bounds_at_turn(socket, turn), "reason": "Reserved by existing placement " + String(socket.socket_id)})
	var entrance := ParcelConnection.from_scene(root)
	for cell in entrance.world_span(definition.size, Vector3i.ZERO, 0):
		unavailable.append({"bounds": AABB(Vector3(cell) - Vector3(0.5, 0, 0.5), Vector3(1, 2, 1)), "reason": "Blocks the parcel entrance"})
	var template_bounds := EnvironmentAssetPlacement.mesh_bounds(template)
	var solid := template.get_node("TacticalVolume") as Node3D
	var solid_size: Vector3 = solid.get_meta("solid_size")
	template_bounds = template_bounds.merge(solid.transform * AABB(-solid_size * 0.5, solid_size))
	var covered_count := 0
	for z in range(definition.size.y - SLOT_SIZE.y + 1):
		for x in range(definition.size.x - SLOT_SIZE.x + 1):
			var rect := Rect2i(Vector2i(x, z), SLOT_SIZE)
			if not _covered(rect, permitted):
				continue
			covered_count += 1
			var pivot := Vector3(x + 1, 0, z + 2)
			var bounds := AABB(pivot + template_bounds.position, template_bounds.size)
			var space := AABB(Vector3(x - 0.5, 0, z - 0.5), Vector3(SLOT_SIZE.x, template_bounds.end.y, SLOT_SIZE.y))
			var reason := ""
			var blocker := AABB()
			if not space.grow(0.001).encloses(bounds):
				reason = "Calibrated container exceeds the candidate footprint"
			elif draft.has_protected_overlap("ground", space):
				reason = "Overlaps protected paint"
			for other in unavailable:
				if reason.is_empty() and space.grow(-0.001).intersects(other.bounds):
					reason = other.reason
					blocker = other.bounds
			if reason == "Overlaps another fitted container position":
				continue
			if not reason.is_empty():
				report.causes[reason] = int(report.causes.get(reason, 0)) + 1
				if rejected.size() < 24:
					rejected.append({"rect": rect, "reason": reason, "blocker_bounds": blocker})
				continue
			var id := StringName("painted_container_%d_%d" % [x, z])
			result.append({"socket_id": id, "region_id": id, "surface_id": &"ground", "asset_id": ASSET,
				"local_bounds": bounds, "local_position": pivot, "allowed_yaw_turns": PackedInt32Array([0]), "rect": rect})
			unavailable.append({"bounds": space, "reason": "Overlaps another fitted container position"})
			if result.size() >= MAX_POSITIONS:
				report.limit_reached = true
				return report
	if covered_count == 0:
		var reason := "Contiguous ground permission must fit a 3 × 5 position"
		report.causes[reason] = 1
		for field in fields:
			if field.preset == "containers" and rejected.size() < 24:
				rejected.append({"rect": Session.rectangle(field), "reason": reason})
	return report

static func _obstacle_reason(root: Node3D, bounds: AABB) -> String:
	for node in root.find_children("*", "Node3D", true, false):
		if not node.has_meta("solid_size"):
			continue
		var transform := Transform3D.IDENTITY
		var parent: Node = node
		while parent != root:
			if parent is Node3D:
				transform = parent.transform * transform
			parent = parent.get_parent()
		var dimensions: Vector3 = node.get_meta("solid_size")
		var measured := transform * AABB(-dimensions * 0.5, dimensions)
		if measured.position.is_equal_approx(bounds.position) and measured.size.is_equal_approx(bounds.size):
			parent = node
			while parent != root and not parent.has_meta("asset_id"):
				parent = parent.get_parent()
			return "Overlaps a fixed object · " + String(parent.name)
	return "Overlaps a fixed object or reserved clearance"

static func _covered(rect: Rect2i, permitted: Dictionary) -> bool:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not permitted.has(Vector2i(x, z)):
				return false
	return true

static func add_to_scene(root: Node3D, template: Node3D, candidate: Dictionary) -> void:
	var id := String(candidate.socket_id)
	var region := Node.new()
	region.name = id
	region.set_meta("population_region_id", candidate.region_id)
	region.set_meta("population_role", &"shipping_container")
	region.set_meta("local_rect", candidate.rect)
	region.set_meta("allowed_asset_ids", PackedStringArray([ASSET]))
	region.set_meta("max_count", 1)
	root.add_child(region)
	region.owner = root
	var container := template.duplicate() as Node3D
	container.name = "Container_" + id
	container.position = candidate.local_position
	container.set_meta("population_socket_id", candidate.socket_id)
	container.set_meta("population_region_id", candidate.region_id)
	container.hide()
	root.add_child(container)
	container.owner = root
	for child in container.get_children():
		child.owner = root
