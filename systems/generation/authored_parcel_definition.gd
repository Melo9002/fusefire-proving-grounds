class_name AuthoredParcelDefinition
extends RefCounted
## Small runtime-safe contract for one reviewed authored parcel scene.

const PopulationRegion = preload("res://systems/generation/parcel_population_region.gd")
const PaintedParking = preload("res://systems/generation/painted_parking_population.gd")

var parcel_id: StringName
var display_name: String
var role: StringName
var revision: int
var size: Vector2i
var scene: PackedScene

func _init(p_id: StringName, p_name: String, p_role: StringName, p_revision: int, p_size: Vector2i, p_scene: PackedScene) -> void:
	parcel_id = p_id
	display_name = p_name
	role = p_role
	revision = p_revision
	size = p_size
	scene = p_scene

func instantiate() -> Node3D:
	return scene.instantiate() as Node3D if scene else null

func validate() -> PackedStringArray:
	var failures := PackedStringArray()
	if parcel_id.is_empty() or role.is_empty() or revision < 1:
		failures.append("INVALID_IDENTITY")
	if size not in [Vector2i(16, 16), Vector2i(16, 32), Vector2i(32, 32)]:
		failures.append("UNSUPPORTED_PARCEL_SIZE")
	var root := instantiate()
	if root == null:
		failures.append("MISSING_PARCEL_SCENE")
		return failures
	if StringName(root.get_meta("parcel_id", &"")) != parcel_id:
		failures.append("PARCEL_ID_MISMATCH")
	if StringName(root.get_meta("parcel_role", &"")) != role:
		failures.append("PARCEL_ROLE_MISMATCH")
	if int(root.get_meta("revision", 0)) != revision:
		failures.append("PARCEL_REVISION_MISMATCH")
	if root.get_meta("parcel_size", Vector2i.ZERO) != size:
		failures.append("PARCEL_SIZE_MISMATCH")
	var rotations: PackedInt32Array = root.get_meta("allowed_rotations", PackedInt32Array())
	var rotations_valid := not rotations.is_empty()
	for turn in rotations:
		if turn < 0 or turn > 3:
			rotations_valid = false
			break
	if not rotations_valid:
		failures.append("INVALID_ALLOWED_ROTATIONS")
	var access_connection := ParcelConnection.from_scene(root)
	var connection_error := access_connection.validate(size)
	if not connection_error.is_empty():
		failures.append("INVALID_CONNECTION: " + connection_error)
	if asset_ids(root).is_empty():
		failures.append("MISSING_IMPORTED_CONTENT")
	var region_ids := {}
	var regions := population_regions(root)
	var surface_errors: Array[String] = []
	var surfaces := population_surfaces(root, surface_errors)
	failures.append_array(surface_errors)
	for region in regions:
		var region_error: String = region.validate(size)
		if not region_error.is_empty():
			failures.append("INVALID_POPULATION_REGION: " + region_error)
		if region_ids.has(region.region_id):
			failures.append("DUPLICATE_POPULATION_REGION")
		region_ids[region.region_id] = true
		if not surfaces.has(region.surface_id):
			failures.append("UNKNOWN_POPULATION_SURFACE: " + String(region.region_id))
		elif not (surfaces[region.surface_id].rect as Rect2i).encloses(region.local_rect):
			failures.append("POPULATION_REGION_OUTSIDE_SURFACE: " + String(region.region_id))
	var socket_ids := {}
	for socket: Dictionary in population_sockets(root):
		var socket_id := StringName(socket.socket_id)
		var region_id := StringName(socket.region_id)
		if socket_id.is_empty() or not region_ids.has(region_id):
			failures.append("INVALID_POPULATION_SOCKET")
		if socket_ids.has(socket_id):
			failures.append("DUPLICATE_POPULATION_SOCKET")
		socket_ids[socket_id] = true
		for region in regions:
			if region.region_id == region_id and not region.allowed_asset_ids.has(String(socket.asset_id)):
				failures.append("POPULATION_ASSET_NOT_ALLOWED")
			if region.region_id != region_id:
				continue
			if socket.surface_id != region.surface_id:
				failures.append("POPULATION_SOCKET_SURFACE_MISMATCH: " + String(socket_id))
			var position: Vector3 = socket.local_position
			if not region.local_rect.has_point(Vector2i(roundi(position.x), roundi(position.z))):
				failures.append("POPULATION_SOCKET_OUTSIDE_REGION: " + String(socket_id))
			if surfaces.has(region.surface_id) and not is_equal_approx(position.y, float(surfaces[region.surface_id].level)):
				failures.append("POPULATION_SOCKET_HEIGHT_MISMATCH: " + String(socket_id))
	root.free()
	return failures

func allowed_rotations() -> PackedInt32Array:
	var root := instantiate()
	if root == null:
		return PackedInt32Array()
	var result: PackedInt32Array = root.get_meta("allowed_rotations", PackedInt32Array())
	root.free()
	return result

func connection() -> ParcelConnection:
	var root := instantiate()
	if root == null:
		return null
	var result := ParcelConnection.from_scene(root)
	root.free()
	return result

func population_regions(root: Node = null) -> Array:
	var owns_root := root == null
	if owns_root:
		root = instantiate()
	var result: Array = []
	if root:
		_collect_population_regions(root, result)
		result.append_array(PaintedParking.regions(root))
	if owns_root and root:
		root.free()
	result.sort_custom(func(a, b): return String(a.region_id) < String(b.region_id))
	return result

func _collect_population_regions(node: Node, result: Array) -> void:
	if node.has_meta("population_region_id") and node.has_meta("population_role"):
		var region = PopulationRegion.new()
		region.region_id = StringName(node.get_meta("population_region_id", &""))
		region.role = StringName(node.get_meta("population_role", &""))
		region.local_rect = node.get_meta("local_rect", Rect2i())
		region.surface_id = StringName(node.get_meta("population_surface_id", &"ground"))
		region.allowed_asset_ids = node.get_meta("allowed_asset_ids", PackedStringArray())
		region.min_count = int(node.get_meta("min_count", 0))
		region.max_count = int(node.get_meta("max_count", 0))
		result.append(region)
	for child in node.get_children():
		_collect_population_regions(child, result)

func population_sockets(root: Node = null) -> Array[Dictionary]:
	var owns_root := root == null
	if owns_root:
		root = instantiate()
	var result: Array[Dictionary] = []
	if root:
		_collect_population_sockets(root, result, Transform3D.IDENTITY, true)
		result.append_array(PaintedParking.sockets(root))
	if owns_root and root:
		root.free()
	result.sort_custom(func(a, b): return String(a.socket_id) < String(b.socket_id))
	return result

func apply_population(root: Node, accepted: Array) -> void:
	var accepted_ids := {}
	for choice: Dictionary in accepted:
		accepted_ids[StringName(choice.get("socket_id", &""))] = choice
	_remove_unaccepted_population(root, accepted_ids)
	PaintedParking.apply(root, accepted_ids)

func _collect_population_sockets(node: Node, result: Array[Dictionary], parent_transform: Transform3D, is_root: bool = false) -> void:
	var local_transform := parent_transform
	if node is Node3D and not is_root:
		local_transform *= node.transform
	if node.has_meta("population_socket_id"):
		result.append({"socket_id": StringName(node.get_meta("population_socket_id")), "region_id": StringName(node.get_meta("population_region_id", &"")), "asset_id": String(node.get_meta("asset_id", "")), "allowed_yaw_turns": node.get_meta("population_yaw_turns", PackedInt32Array([0])), "surface_id": StringName(node.get_meta("population_surface_id", &"ground")), "local_position": local_transform.origin, "local_bounds": _population_bounds(node, local_transform)})
	for child in node.get_children():
		_collect_population_sockets(child, result, local_transform)

func _population_bounds(node: Node, socket_transform: Transform3D) -> AABB:
	var volumes: Array[AABB] = []
	_collect_population_bounds(node, socket_transform, volumes)
	var bounds := AABB(socket_transform.origin, Vector3.ZERO)
	for volume in volumes:
		bounds = volume if bounds.size == Vector3.ZERO else bounds.merge(volume)
	return bounds

func fixed_population_obstacles(scene_root: Node3D) -> Array[AABB]:
	var result: Array[AABB] = []
	_collect_fixed_obstacles(scene_root, Transform3D.IDENTITY, result, true)
	return result

func _collect_fixed_obstacles(node: Node, parent_transform: Transform3D, result: Array[AABB], is_root: bool = false) -> void:
	if node.has_meta("population_socket_id"): return
	var transform := parent_transform
	if node is Node3D and not is_root: transform *= node.transform
	if node.has_meta("solid_size"):
		var dimensions: Vector3 = node.get_meta("solid_size")
		result.append(transform * AABB(-dimensions * 0.5, dimensions))
	for child in node.get_children():
		_collect_fixed_obstacles(child, transform, result)

func _collect_population_bounds(node: Node, transform: Transform3D, volumes: Array[AABB]) -> void:
	if node.has_meta("solid_size"):
		var dimensions: Vector3 = node.get_meta("solid_size")
		volumes.append(transform * AABB(-dimensions * 0.5, dimensions))
	for child in node.get_children():
		_collect_population_bounds(child, transform * child.transform if child is Node3D else transform, volumes)

## Ground is implicit for historical parcels. Elevated population surfaces must
## reference explicit deck cells compiled by AuthoredSceneMapCompiler.
func population_surfaces(root: Node, errors: Array[String] = []) -> Dictionary:
	var result := {&"ground": {"rect": Rect2i(Vector2i.ZERO, size), "level": 0}}
	_collect_population_surfaces(root, result, errors, Transform3D.IDENTITY, true)
	return result

func _collect_population_surfaces(node: Node, result: Dictionary, errors: Array[String], parent_transform: Transform3D, is_root: bool = false) -> void:
	var local_transform := parent_transform
	if node is Node3D and not is_root:
		local_transform *= node.transform
	if node.has_meta("deck_local_rect") and node.has_meta("population_surface_id"):
		var id := StringName(node.get_meta("population_surface_id"))
		var rect: Rect2i = node.get_meta("deck_local_rect")
		var level := int(node.get_meta("deck_level", 0))
		if id.is_empty() or result.has(id):
			errors.append("DUPLICATE_OR_INVALID_POPULATION_SURFACE: " + String(id))
		elif not local_transform.is_equal_approx(Transform3D.IDENTITY):
			errors.append("TRANSFORMED_POPULATION_SURFACE_UNSUPPORTED: " + String(id))
		elif level <= 0 or not Rect2i(Vector2i.ZERO, size).encloses(rect) or rect.size.x <= 0 or rect.size.y <= 0:
			errors.append("INVALID_POPULATION_DECK: " + String(id))
		else:
			result[id] = {"rect": rect, "level": level}
	for child in node.get_children():
		_collect_population_surfaces(child, result, errors, local_transform)

func _remove_unaccepted_population(node: Node, accepted_ids: Dictionary) -> void:
	for child in node.get_children():
		if child.has_meta("population_socket_id") and not accepted_ids.has(StringName(child.get_meta("population_socket_id"))):
			child.free()
		else:
			if child is Node3D and child.has_meta("population_socket_id"):
				child.show()
				var choice: Dictionary = accepted_ids[StringName(child.get_meta("population_socket_id"))]
				if not child.has_meta("population_base_yaw"):
					child.set_meta("population_base_yaw", child.rotation.y)
				# Apply to the whole authored occupant, including tactical volumes.
				child.rotation.y = float(child.get_meta("population_base_yaw")) - int(choice.get("yaw_turns", 0)) * PI * 0.5
			_remove_unaccepted_population(child, accepted_ids)

func asset_ids(root: Node = null) -> PackedStringArray:
	var owns_root := root == null
	if owns_root:
		root = instantiate()
	var result := PackedStringArray()
	if root:
		_collect_asset_ids(root, result)
	if owns_root and root:
		root.free()
	result.sort()
	return result

func _collect_asset_ids(node: Node, result: PackedStringArray) -> void:
	if node.has_meta("asset_id"):
		result.append(String(node.get_meta("asset_id")))
	for child in node.get_children():
		_collect_asset_ids(child, result)
