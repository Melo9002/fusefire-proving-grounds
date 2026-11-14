extends RefCounted
## Offline authoring only: fit reviewed regions of imported triangles, never battle occupancy.
const MAX_TRIANGLES := 200000
const MAX_POINTS := 50000
const ROLES := ["unclassified", "solid", "movement", "shots", "low_cover", "visual_only"]

static func bake(source: Node3D, region: AABB) -> Dictionary:
	if not is_instance_valid(source): return {"error": "A source model is required."}
	if not region.has_volume() or not region.position.is_finite() or not region.size.is_finite():
		return {"error": "Choose finite clipping bounds with positive width, height and depth."}
	var unique := {}
	var triangles := 0
	for entry in _sources(source):
		var node: MeshInstance3D = entry.node
		var transform: Transform3D = entry.transform
		if node.skin != null: return {"error": "Skinned geometry needs a static authoring snapshot."}
		var faces := node.mesh.get_faces()
		triangles += int(faces.size() / 3.0)
		if triangles > MAX_TRIANGLES: return {"error": "Triangle budget exceeded; isolate a smaller source mesh."}
		for index in range(0, faces.size(), 3):
			var polygon: Array[Vector3] = [transform * faces[index], transform * faces[index + 1], transform * faces[index + 2]]
			for axis in 3:
				polygon = _clip(polygon, axis, region.position[axis], true)
				polygon = _clip(polygon, axis, region.end[axis], false)
			for point in polygon:
				if not point.is_finite(): return {"error": "Source contains non-finite geometry."}
				var key := Vector3i((point * 100000).round())
				if not unique.has(key): unique[key] = point
				if unique.size() > MAX_POINTS: return {"error": "Point budget exceeded; clip a smaller region."}
	var points := PackedVector3Array(unique.values())
	if not _has_volume(points): return {"error": "The region contains no three-dimensional mesh surface; adjust the clipping bounds."}
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var projected := PackedVector2Array()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
		projected.append(Vector2(point.x, point.z))
	return {"error": "", "points": points, "shape": shape, "bounds": bounds, "footprint": Geometry2D.convex_hull(projected), "region": region, "triangles": triangles}

static func _clip(polygon: Array[Vector3], axis: int, boundary: float, keep_above: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if polygon.is_empty(): return result
	var previous := polygon[-1]
	var previous_inside := previous[axis] >= boundary if keep_above else previous[axis] <= boundary
	for point in polygon:
		var inside := point[axis] >= boundary if keep_above else point[axis] <= boundary
		if inside != previous_inside:
			result.append(previous.lerp(point, (boundary - previous[axis]) / (point[axis] - previous[axis])))
		if inside: result.append(point)
		previous = point
		previous_inside = inside
	return result

static func read_profile(path: String, dependency: Dictionary) -> Dictionary:
	var packed := load(path) as PackedScene
	if not packed: return {"error": "Cannot read boundary scene."}
	var root := packed.instantiate()
	var parts: Array = []
	var error := ""
	if int(root.get_meta("boundary_schema", 0)) != 1 or root.get_meta("source_dependency", {}) != dependency or root.get_meta("asset_id", "") != dependency.get("asset_id", ""):
		error = "Unsupported profile or stale/different asset geometry or calibration."
	elif root.get_child_count() == 0 or root.get_child_count() > 32:
		error = "The profile must contain 1–32 parts."
	else:
		for node in root.get_children():
			var points: Variant = node.get_meta("points", null)
			var region: Variant = node.get_meta("region", null)
			var footprint: Variant = node.get_meta("footprint", null)
			var role: Variant = node.get_meta("role", "unclassified")
			if not points is PackedVector3Array or points.size() > MAX_POINTS or not _has_volume(points) or not region is AABB or not region.has_volume() or not region.position.is_finite() or not region.size.is_finite() or not footprint is PackedVector2Array or footprint.size() < 3 or role not in ROLES.slice(1):
				error = "Invalid part: " + String(node.name)
				break
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			parts.append({"name": String(node.name), "points": points, "shape": shape, "region": region, "footprint": footprint, "role": role})
	root.free()
	return {"error": error, "parts": parts if error.is_empty() else []}

static func _has_volume(points: PackedVector3Array) -> bool:
	if points.size() < 4: return false
	for point in points:
		if not point.is_finite(): return false
	var first := points[0]
	var edge := Vector3.ZERO
	var normal := Vector3.ZERO
	for point in points:
		if edge.length_squared() < 0.00000001:
			edge = point - first
		elif normal.length_squared() < 0.00000001:
			normal = edge.cross(point - first)
		elif absf(normal.normalized().dot(point - first)) > 0.00001:
			return true
	return false

static func export_profile(parts: Array, asset_id: String, dependency: Dictionary, path: String) -> Error:
	if parts.is_empty() or parts.size() > 32 or asset_id.is_empty() or dependency.get("asset_id", "") != asset_id: return ERR_INVALID_DATA
	var root := Node3D.new()
	root.name = "BoundaryProfile"
	root.set_meta("boundary_schema", 1)
	root.set_meta("asset_id", asset_id)
	root.set_meta("source_dependency", dependency)
	root.set_meta("review_state", "unreviewed_authoring_draft")
	for part: Dictionary in parts:
		if part.get("role", "unclassified") not in ROLES.slice(1) or not _has_volume(part.get("points", PackedVector3Array())) or not part.get("region") is AABB or not part.get("footprint") is PackedVector2Array:
			root.free()
			return ERR_INVALID_DATA
		var node := Node3D.new()
		node.name = part.name
		root.add_child(node)
		node.owner = root
		for key in ["role", "points", "footprint", "region"]: node.set_meta(key, part[key])
	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result == OK: result = ResourceSaver.save(scene, path)
	root.free()
	return result

static func _sources(source: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	if source is MeshInstance3D: meshes.push_front(source)
	for node: MeshInstance3D in meshes:
		if not node.mesh: continue
		var transform := Transform3D.IDENTITY
		var ancestor: Node = node
		var preview := false
		while ancestor != source:
			preview = preview or ancestor.has_meta("boundary_preview")
			if ancestor is Node3D: preview = preview or not ancestor.visible
			if ancestor is Node3D: transform = ancestor.transform * transform
			ancestor = ancestor.get_parent()
		if preview: continue
		# The source's calibrated transform is baked into its parent's local frame.
		transform = source.transform * transform
		result.append({"node": node, "transform": transform})
	return result

static func source_bounds(source: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for entry in _sources(source):
		var box: AABB = entry.transform * entry.node.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds
