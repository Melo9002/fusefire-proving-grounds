class_name AuthoredParcelDefinition
extends RefCounted
## Small runtime-safe contract for one reviewed authored parcel scene.

const PopulationRegion = preload("res://systems/generation/parcel_population_region.gd")

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
	var connection := ParcelConnection.from_scene(root)
	var connection_error := connection.validate(size)
	if not connection_error.is_empty():
		failures.append("INVALID_CONNECTION: " + connection_error)
	if asset_ids(root).is_empty():
		failures.append("MISSING_IMPORTED_CONTENT")
	var region_ids := {}
	var regions := population_regions(root)
	for region in regions:
		var region_error: String = region.validate(size)
		if not region_error.is_empty():
			failures.append("INVALID_POPULATION_REGION: " + region_error)
		if region_ids.has(region.region_id):
			failures.append("DUPLICATE_POPULATION_REGION")
		region_ids[region.region_id] = true
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
		_collect_population_sockets(root, result)
	if owns_root and root:
		root.free()
	result.sort_custom(func(a, b): return String(a.socket_id) < String(b.socket_id))
	return result

func apply_population(root: Node, accepted: Array) -> void:
	var accepted_ids := {}
	for choice: Dictionary in accepted:
		accepted_ids[StringName(choice.get("socket_id", &""))] = true
	_remove_unaccepted_population(root, accepted_ids)

func _collect_population_sockets(node: Node, result: Array[Dictionary]) -> void:
	if node.has_meta("population_socket_id"):
		result.append({"socket_id": StringName(node.get_meta("population_socket_id")), "region_id": StringName(node.get_meta("population_region_id", &"")), "asset_id": String(node.get_meta("asset_id", ""))})
	for child in node.get_children():
		_collect_population_sockets(child, result)

func _remove_unaccepted_population(node: Node, accepted_ids: Dictionary) -> void:
	for child in node.get_children():
		if child.has_meta("population_socket_id") and not accepted_ids.has(StringName(child.get_meta("population_socket_id"))):
			child.free()
		else:
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
