extends RefCounted
## Starting boundaries for newly placed ordinary objects. Save the resulting
## explicit parts with the scene; battle/replay never infer geometry at runtime.
## Per-mesh boxes are an approximation, not polygon collision or walkable floors.
const VERSION := 1
const STANDING_CLEARANCE := 2.0

static func add_to(object: Node3D) -> int:
	# Never replace an authored exception, including historical shape parts.
	if _has_solids(object): return 0
	var parts: Array[Dictionary] = []
	_collect(object, Transform3D.IDENTITY, parts, true)
	if parts.is_empty(): return 0
	var shapes := Node3D.new()
	shapes.name = "MeshBoundaries"
	object.add_child(shapes)
	shapes.owner = object
	for part in parts:
		var volume := Node3D.new()
		volume.name = "Part%d" % shapes.get_child_count()
		var bounds: AABB = part.bounds
		volume.transform = part.transform * Transform3D(Basis.IDENTITY, bounds.get_center())
		volume.set_meta("solid_size", bounds.size)
		volume.set_meta("precise_shot_bounds", true)
		# A body raised slightly above the floor still prevents standing inside it.
		# Its shot bounds stay at their visible height instead of extending down.
		volume.set_meta("standing_clearance", STANDING_CLEARANCE)
		shapes.add_child(volume)
		volume.owner = object
	object.set_meta("mesh_boundary_version", VERSION)
	return parts.size()

static func _has_solids(node: Node) -> bool:
	if node.has_meta("solid_size"): return true
	for child in node.get_children():
		if _has_solids(child): return true
	return false

static func _collect(node: Node, parent: Transform3D, parts: Array[Dictionary], is_root := false) -> void:
	var transform := parent
	if node is Node3D:
		if not node.visible: return
		if not is_root: transform *= node.transform
	if node is MeshInstance3D and node.mesh:
		# Geometry, not custom culling bounds, defines the starting part.
		var bounds: AABB = node.mesh.get_aabb()
		if bounds.has_volume(): parts.append({"transform": transform, "bounds": bounds})
	for child in node.get_children(): _collect(child, transform, parts)
