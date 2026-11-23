class_name SkinnedSurface
extends RefCounted
## READ-ONLY (it never writes a pose): the character's actual mesh surface, skinned to the pose the skeleton has NOW, for the bones asked about. A clearance measured on capsules around bones is an approximation (the armor
## stands well off the bone axis in places and not in others); this is the mesh itself. It is a sample, not a collision shape: the vertices of the mesh that follow the chosen bones the most (the points
## the modeller put on the surface), so a thin crossing between two vertices can be missed and a vertex inside a bar is a real overlap of the visible surface.
##
## Linear-blend skinning, as the engine does it: for each vertex, the sum over its (up to 4) bones of weight * (bone's pose in the skeleton * the skin's bind pose) * the mesh-local vertex. Verified at rest
## against the mesh's own rest transform (`rest_error`). Costs work only when `points` is called; nothing is created or connected otherwise.

var skeleton: Skeleton3D
var _vertices: Array[Vector3] = []   # mesh-local
var _bones: Array[PackedInt32Array] = []   # skeleton bone indices of the up to 4 influences
var _weights: Array[PackedFloat32Array] = []
var _bind: Array[Transform3D] = []   # per influence: the inverse bind pose of that bone in the mesh's skin (indexed like _bones, flattened)
var _owner_bone: PackedInt32Array = PackedInt32Array()   # the dominant bone of each vertex
var _rest_points: Array[Vector3] = []   # where the mesh itself puts each vertex, in the skeleton frame
var _skin_bind_per_vertex: Array = []
## The bones' global poses AS THE LAST `capture()` SAW THEM. The modifiers' result exists only while `skeleton_updated` is being emitted: read afterwards, `get_bone_global_pose` gives the base animation pose.
## So the owner calls `capture()` from its `skeleton_updated` handler and `points()` skins with what was captured. Until a capture exists, `points()` reads the live pose (right at rest, wrong under modifiers).
var _captured := {}
var _used_bones := {}


## `bone_names` the bones whose surface to follow (a vertex counts when its dominant influence is one of them with at least `min_weight`).
static func create(character_skeleton: Skeleton3D, bone_names: Array[StringName], min_weight := 0.5) -> SkinnedSurface:
	var surface := SkinnedSurface.new()
	surface.skeleton = character_skeleton
	var wanted := {}
	for bone_name in bone_names:
		var index := character_skeleton.find_bone(bone_name)
		if index >= 0:
			wanted[index] = true
	for node in character_skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.skin == null:
			continue
		var skin := mesh_instance.skin
		var to_skeleton := character_skeleton.global_transform.affine_inverse() * mesh_instance.global_transform
		for s in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null or bones.is_empty() or verts.is_empty():
				continue
			var per := int(bones.size() / verts.size())
			for v in verts.size():
				var best := -1
				var best_w := 0.0
				var skeleton_bones := PackedInt32Array()
				var vertex_weights := PackedFloat32Array()
				var binds: Array[Transform3D] = []
				for k in per:
					var w := float(weights[v * per + k])
					var bind_index := int(bones[v * per + k])
					var bone_index := skin.get_bind_bone(bind_index) if skin.get_bind_bone(bind_index) >= 0 else character_skeleton.find_bone(skin.get_bind_name(bind_index))
					if w > best_w:
						best_w = w
						best = bone_index
					skeleton_bones.append(bone_index)
					vertex_weights.append(w)
					binds.append(skin.get_bind_pose(bind_index))
				if best_w < min_weight or not wanted.has(best):
					continue
				surface._vertices.append(verts[v])
				surface._rest_points.append(to_skeleton * verts[v])
				surface._bones.append(skeleton_bones)
				surface._weights.append(vertex_weights)
				surface._skin_bind_per_vertex.append(binds)
				surface._owner_bone.append(best)
				for used in skeleton_bones:
					surface._used_bones[used] = true
	return surface


func size() -> int:
	return _vertices.size()


## The surface points now, in the SKELETON's frame, with the bone each follows.
func points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	result.resize(_vertices.size())
	var pose_cache := {}
	for i in _vertices.size():
		var bones := _bones[i]
		var weights := _weights[i]
		var binds: Array = _skin_bind_per_vertex[i]
		var accumulated := Vector3.ZERO
		var total := 0.0
		for k in bones.size():
			var w := weights[k]
			if w <= 0.0:
				continue
			var bone := bones[k]
			if not pose_cache.has(bone):
				pose_cache[bone] = _captured[bone] if _captured.has(bone) else skeleton.get_bone_global_pose(bone)
			accumulated += w * ((pose_cache[bone] as Transform3D) * (binds[k] as Transform3D) * _vertices[i])
			total += w
		result[i] = accumulated / maxf(total, 0.0001)
	return result


func bone_of(point_index: int) -> int:
	return _owner_bone[point_index]


## A sanity check of the skinning: how far the skinned points are from the mesh's own rest places (`MeshInstance3D` transform times the vertex), in metres. Valid only while the skeleton is at its rest
## pose (`skeleton.reset_bone_poses()`); a value near 0 means this skinning is the engine's.
func rest_error(sample_count := 200) -> float:
	var worst := 0.0
	var stride := maxi(1, _vertices.size() / sample_count)
	var current := points()
	for i in range(0, _vertices.size(), stride):
		worst = maxf(worst, _rest_points[i].distance_to(current[i]))
	return worst


## The radius of a limb segment as the mesh really has it: the `percentile` (0..1) of the distances, in metres, from the vertices that follow `owner_bones` most (at the mesh's rest places) to the segment
## `a` to `b` (skeleton bones, both at rest). With `around_joint` the distance is measured to the joint `a` alone, for a knee-like bulge (only vertices within `limit` of it). A percentile, not the maximum:
## a few armor edges stand far out and one stray vertex should not decide a limb's thickness.
func measured_radius(owner_bones: Array[StringName], a: StringName, b: StringName, percentile := 0.9, around_joint := false, limit := 0.12) -> float:
	var owners := {}
	for bone_name in owner_bones:
		owners[skeleton.find_bone(bone_name)] = true
	var start := skeleton.get_bone_global_rest(skeleton.find_bone(a)).origin
	var end := skeleton.get_bone_global_rest(skeleton.find_bone(b)).origin
	var scale := skeleton.global_basis.get_scale().y
	var distances: Array[float] = []
	for i in _vertices.size():
		if not owners.has(_owner_bone[i]):
			continue
		var p := _rest_points[i]
		var distance := 0.0
		if around_joint:
			distance = p.distance_to(start) * scale
			if distance > limit:
				continue
		else:
			var axis := end - start
			var t := clampf((p - start).dot(axis) / maxf(axis.length_squared(), 0.000001), 0.0, 1.0)
			distance = p.distance_to(start + axis * t) * scale
		distances.append(distance)
	if distances.is_empty():
		return 0.0
	distances.sort()
	return distances[int(clampf(percentile, 0.0, 1.0) * float(distances.size() - 1))]


## How far the mesh of `owner_bones` reaches along `direction` (a unit vector in the SKELETON frame) from the bone `from_bone`, at rest, in metres: the `percentile` of the vertices' distances along it (0.98
## ignores a stray vertex). A boot's reach ahead of its ankle, a belly's ahead of the hips.
func reach_along(owner_bones: Array[StringName], from_bone: StringName, direction: Vector3, percentile := 0.98) -> float:
	var owners := {}
	for bone_name in owner_bones:
		owners[skeleton.find_bone(bone_name)] = true
	var origin := skeleton.get_bone_global_rest(skeleton.find_bone(from_bone)).origin
	var scale := skeleton.global_basis.get_scale().y
	var along: Array[float] = []
	for i in _vertices.size():
		if owners.has(_owner_bone[i]):
			along.append((_rest_points[i] - origin).dot(direction) * scale)
	if along.is_empty():
		return 0.0
	along.sort()
	return along[int(clampf(percentile, 0.0, 1.0) * float(along.size() - 1))]


## Caches the bones' global poses NOW. Call it inside the skeleton's `skeleton_updated` handler (where the modifiers' result is the pose); `points()` then skins with it.
func capture() -> void:
	for bone in _used_bones:
		_captured[bone] = skeleton.get_bone_global_pose(bone)
