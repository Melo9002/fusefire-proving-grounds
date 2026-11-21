extends SceneTree
## Unarmed resting hands and the legs (Task 07 package 9 correction). The defect was real mesh penetration: a hand hung straight under the shoulder, the wrist turned inward across the hip, and the hand and forearm sat inside the thigh.
## Contact is fine (a hand may rest against the leg); only the surface being crossed is wrong. So this judges the SKINNED MESH, not the joints: every hand and forearm vertex is tested against the leg's skinned triangles
## (a ray outward from the vertex crosses the leg's surface an odd number of times when the vertex is inside it) and the depth is the distance to that surface. Standing, walking, crouched and kneeling.
## A negative control moves the hand into the leg and must be detected, so a pass means something.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const MAX_DEPTH := 0.01   # metres of allowed overlap: contact and the skinned surface's own rounding
var failures := 0
var checks := 0
var v: UnitVisualAdapter
var pending := ""
var _results := {}
var _control_inward := 0.0   # metres the hand vertices are moved toward the body's midline (the negative control)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).skin != null:
		return n
	for c in n.get_children():
		var r := _mesh(c)
		if r != null:
			return r
	return null

func _descendants(skeleton: Skeleton3D, bone: int, out: Dictionary) -> void:
	out[bone] = true
	for c in skeleton.get_bone_children(bone):
		_descendants(skeleton, c, out)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _sample(tag: String, walking := false) -> void:
	pending = tag
	for i in 2:
		if walking:
			v.update_locomotion(Vector3(0, 0, 3.0), 1.0 / 60.0)
		await process_frame

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	v = VISUAL.instantiate()
	v.rig.weapon_scene = null
	stage.add_child(v)
	# The finished pose, with its solved IK, is valid only where the skeleton updates.
	v.rig.skeleton.skeleton_updated.connect(func() -> void:
		if pending != "":
			var tag := pending
			pending = ""
			_results[tag] = _measure())
	await _frames(30)
	await _sample("standing")
	v.rig.animation_controller.play(&"move")
	for i in 80:
		v.update_locomotion(Vector3(0, 0, 3.0), 1.0 / 60.0)
		await process_frame
	await _sample("walking", true)
	v.rig.animation_controller.play(&"idle")
	for i in 60:
		v.update_locomotion(Vector3.ZERO, 1.0 / 60.0)
		await process_frame
	v.presenter.postures.set_posture(&"c", PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.0, 0.40)
	await _frames(60)
	await _sample("crouched")
	v.presenter.postures.set_posture(&"c", PresentationTypes.Posture.KNEEL, PresentationTypes.PRIORITY_CONTEXT, 0.0, v.rig.crouch_modifier.max_depth + CharacterRig.KNEEL_BLEND_RANGE)
	await _frames(80)
	await _sample("kneeling")
	v.presenter.postures.release(&"c")
	await _frames(60)
	for tag in ["standing", "walking", "crouched", "kneeling"]:
		var r: Dictionary = _results[tag]
		check(r.hand_vertices > 300 and r.leg_triangles > 1000, "%s: the measurement found the hand and the leg meshes (%d hand vertices, %d leg triangles)" % [tag, r.hand_vertices, r.leg_triangles])
		check(r.hand_depth <= MAX_DEPTH and r.forearm_depth <= MAX_DEPTH, "%s: the hands and forearms do not cross the legs' surface (hand %.1f cm, forearm %.1f cm deep)" % [tag, r.hand_depth * 100.0, r.forearm_depth * 100.0])
	# Negative control: the same measurement with the hand moved 12 cm toward the body must see the hand inside the leg.
	_control_inward = 0.12
	await _frames(30)
	await _sample("control")
	var control: Dictionary = _results["control"]
	check(control.hand_depth > 0.03, "The detector sees a hand pushed into the thigh (%.1f cm deep), so the passes above are not blind" % [control.hand_depth * 100.0])
	# Not a stance held wide to buy clearance: the resting arm stays a natural angle from vertical.
	var angle: float = _results["standing"].arm_angle_degrees
	check(angle > 0.0 and angle < 20.0, "The resting arm stays a natural angle from vertical (%.1f degrees)" % angle)
	print("Unarmed hand clearance: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## Hand and forearm vertex depth inside each leg, and the arm's angle from vertical, from the skinned mesh as the skeleton just posed it.
func _measure() -> Dictionary:
	var mesh_instance := _mesh(v)
	var skeleton := v.rig.skeleton
	var skin := mesh_instance.skin
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per := bone_ids.size() / verts.size()
	var world := PackedVector3Array()
	world.resize(verts.size())
	var dominant := PackedInt32Array()
	dominant.resize(verts.size())
	for i in verts.size():
		var accumulated := Vector3.ZERO
		var best := -1.0
		var best_bone := -1
		for k in per:
			var weight := weights[i * per + k]
			if weight <= 0.0:
				continue
			var slot := bone_ids[i * per + k]
			var bone := skin.get_bind_bone(slot)
			if bone < 0:
				bone = skeleton.find_bone(skin.get_bind_name(slot))
			accumulated += weight * ((skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(slot)) * verts[i])
			if weight > best:
				best = weight
				best_bone = bone
		world[i] = skeleton.global_transform * accumulated
		dominant[i] = best_bone
	var result := {"hand_depth": 0.0, "forearm_depth": 0.0, "hand_vertices": 0, "leg_triangles": 0, "arm_angle_degrees": 0.0}
	for side in 2:
		var arm: Array[StringName] = v.rig.bones.right_arm if side == 0 else v.rig.bones.left_arm
		var leg: Array[StringName] = v.rig.bones.right_leg if side == 0 else v.rig.bones.left_leg
		var hand_bones := {}
		_descendants(skeleton, skeleton.find_bone(arm[2]), hand_bones)
		var forearm_bone := skeleton.find_bone(arm[1])
		var leg_bones := {skeleton.find_bone(leg[0]): true, skeleton.find_bone(leg[1]): true}
		var outward: Vector3 = v.global_basis.x * (-1.0 if side == 0 else 1.0)   # the character's right side is -X
		var triangles: Array = []
		for t in range(0, indices.size(), 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c := indices[t + 2]
			if leg_bones.has(dominant[a]) or leg_bones.has(dominant[b]) or leg_bones.has(dominant[c]):
				triangles.append([world[a], world[b], world[c]])
		result.leg_triangles = maxi(result.leg_triangles, triangles.size())
		for i in range(0, verts.size(), 2):
			var kind := "hand" if hand_bones.has(dominant[i]) else ("forearm" if dominant[i] == forearm_bone else "")
			if kind == "":
				continue
			var point := world[i]
			if kind == "hand":
				point -= outward * _control_inward
				result.hand_vertices += 1
			var crossings: Array[float] = []
			for triangle in triangles:
				var hit = Geometry3D.ray_intersects_triangle(point, outward, triangle[0], triangle[1], triangle[2])
				if hit != null:
					crossings.append(point.distance_to(hit))
			if crossings.size() % 2 == 1:
				crossings.sort()
				result[kind + "_depth"] = maxf(result[kind + "_depth"], crossings[0])
		var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(arm[0])).origin
		var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(arm[2])).origin
		result.arm_angle_degrees = maxf(result.arm_angle_degrees, rad_to_deg(Vector3.DOWN.angle_to(wrist - shoulder)))
	return result
