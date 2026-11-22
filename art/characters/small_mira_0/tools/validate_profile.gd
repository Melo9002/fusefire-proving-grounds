extends SceneTree
## godot_console --headless --path . --script res://art/characters/small_mira_0/tools/validate_profile.gd
## Resolves small_mira_0's rig profile against the imported model, prints diagnostics, measurements and capabilities,
## and reports per-clip Hips travel (root motion). Read-only.
const Resolver := preload("res://presentation/characters/rig_profile/rig_resolver.gd")
const MODEL := "res://art/characters/small_mira_0/models/small_mira_0.glb"
const PROFILE := "res://art/characters/small_mira_0/small_mira_0_rig_profile.tres"

func _initialize() -> void:
	var scene: PackedScene = load(MODEL)
	if scene == null:
		push_error("model failed to load"); quit(1); return
	var model := scene.instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	print("SKELETON bones=%d" % skeleton.get_bone_count())
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for m: MeshInstance3D in meshes:
		print("MESH %s verts=%d skin=%s aabb=%s" % [m.name, m.mesh.get_faces().size(), m.skin != null, m.get_aabb()])
	var profile = load(PROFILE)
	var result = Resolver.resolve(profile, skeleton)
	print(result.diagnostics.format())
	var m = result.measurements
	for key in ["up", "forward", "lateral", "hip_height", "ankle_height", "thigh_length", "shin_length", "leg_length", "upper_arm_length", "forearm_length", "shoulder_width", "hip_width", "standing_height"]:
		print("MEASURE %s = %s" % [key, m.get(key)])
	for cap in result.capabilities:
		var c = result.capabilities[cap]
		print("CAP %s %s %s" % [cap, Resolver.Status.keys()[c.status], c.reason])
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		print("NO AnimationPlayer")
	else:
		var player: AnimationPlayer = players[0]
		var hips_path := "%s:%s" % [model.get_path_to(skeleton), profile.skeleton_map.get_skeleton_bone_name(&"Hips")]
		for anim_name in player.get_animation_list():
			var anim := player.get_animation(anim_name)
			var track := anim.find_track(NodePath(hips_path), Animation.TYPE_POSITION_3D)
			if track < 0:
				print("CLIP %s len=%.2f loop=%d hips_track=none" % [anim_name, anim.length, anim.loop_mode]); continue
			var a: Vector3 = anim.position_track_interpolate(track, 0.0)
			var b: Vector3 = anim.position_track_interpolate(track, anim.length)
			var lo := a; var hi := a
			for i in 41:
				var p: Vector3 = anim.position_track_interpolate(track, anim.length * i / 40.0)
				lo = lo.min(p); hi = hi.max(p)
			print("CLIP %s len=%.2f loop=%d hips_start=%s net=%s range=%s" % [anim_name, anim.length, anim.loop_mode, a, b - a, hi - lo])
	quit(1 if result.diagnostics.has_errors() else 0)
