class_name AuthoredParcelDefinition
extends RefCounted
## Small runtime-safe contract for one reviewed authored parcel scene.

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
