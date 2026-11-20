extends Node3D
## Task 03 feasibility probe (disposable evidence, not a gameplay context): can the production character presentation run with NO TacticalUnit, NO grid, NO AP and no
## battle at all? One small floor, one chair (a box), one marker, and the production visual scene driven by a scripted trajectory through the public calls a future
## controller would use (`present_move`, `update_locomotion`, `face_world_position`, `present_idle`, `stow_weapon`). Nothing here is production code and nothing in
## production was changed for it. "CHECK" lines are things that worked; "OBSERVED" lines are obstacles or absences that need the architecture task.
##
## Interactive: open host_probe.tscn and press F6. Headless measurement:
##   godot_console --headless --path . res://research/animation_host_probe/host_probe.tscn -- --auto
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const WALK_SPEED := 1.3

var visual: Node3D
var chair: MeshInstance3D
var marker: MeshInstance3D
var checks := 0
var failures := 0
var auto := false
var states_seen: Array[StringName] = []
var phase := 0
var clock := 0.0
var phase_clock := 0.0
var target := Vector3.ZERO
var max_cadence := 0.0
var max_speed := 0.0
var max_twist := 0.0
var frames := 0
# Pose samples taken inside skeleton_updated (the only place modifier results exist).
var hips_y := NAN
var foot_gap := 0.0
var hips_range := Vector2(99.0, -99.0)
var foot_gap_peak := 0.0
var errors_before := 0

func _ready() -> void:
	set_process(false)
	auto = "--auto" in OS.get_cmdline_user_args()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 16)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.2
	disc.bottom_radius = 0.2
	disc.height = 0.02
	marker.mesh = disc
	marker.position = Vector3(3.0, 0.01, 2.0)
	add_child(marker)
	chair = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	chair.mesh = box
	chair.position = Vector3(3.0, 0.25, -1.5)
	add_child(chair)
	var camera := Camera3D.new()
	camera.position = Vector3(7.0, 4.5, 6.0)
	add_child(camera)
	camera.look_at(Vector3(1.5, 0.8, 0.5))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)
	visual = VISUAL.instantiate()
	add_child(visual)
	# The production scene is authored 1 m BELOW its tactical unit (the unit's origin is its centre): a standalone host must undo that offset to stand on the floor.
	visual.position = Vector3.ZERO
	visual.presentation_state_changed.connect(func(state: StringName) -> void:
		if state not in states_seen:
			states_seen.append(state))
	visual.skeleton.skeleton_updated.connect(_sample_pose)
	for i in 20:
		await get_tree().process_frame
	set_process(true)

func _sample_pose() -> void:
	var skeleton: Skeleton3D = visual.skeleton
	var hips := skeleton.find_bone("mixamorig_Hips")
	var left := skeleton.find_bone("mixamorig_LeftFoot")
	var right := skeleton.find_bone("mixamorig_RightFoot")
	if hips < 0 or left < 0 or right < 0:
		return
	var to_world := skeleton.global_transform
	hips_y = (to_world * skeleton.get_bone_global_pose(hips)).origin.y
	var a := to_world * skeleton.get_bone_global_pose(left).origin
	var b := to_world * skeleton.get_bone_global_pose(right).origin
	var forward := visual.global_basis.z
	foot_gap = absf((a - b).dot(forward))
	if phase in [1, 4]:
		hips_range = Vector2(minf(hips_range.x, hips_y), maxf(hips_range.y, hips_y))
		foot_gap_peak = maxf(foot_gap_peak, foot_gap)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	print("  CHECK %s: %s" % ["ok  " if ok else "FAIL", message])

func observed(message: String) -> void:
	print("  OBSERVED: ", message)

func _process(delta: float) -> void:
	frames += 1
	clock += delta
	phase_clock += delta
	var report: Dictionary = visual.locomotion_report
	max_cadence = maxf(max_cadence, float(report.get("cadence", 0.0)))
	max_speed = maxf(max_speed, float(report.get("speed", 0.0)))
	max_twist = maxf(max_twist, absf(float(visual.locomotion_modifier.twist_degrees)))
	match phase:
		0:   # idle
			if phase_clock > 1.5:
				check(not _has_tactical_nodes(), "No TacticalUnit exists anywhere in the scene tree")
				check(visual.get("tactical_unit") == null, "The adapter's tactical_unit is null: the character runs on its own")
				check(visual.get_presentation_state() == &"rifle_idle", "Idle state reached with no controller input (%s)" % visual.get_presentation_state())
				target = Vector3(marker.position.x, 0.0, marker.position.z)
				visual.face_world_position(target)   # production call: yaw plus the turn presentation
				visual.present_move()                # the caller must request the movement clip itself
				_next()
		1:   # walk to the marker with the same calls a tactical unit makes each frame
			var to := target - visual.global_position
			to.y = 0.0
			if to.length() > 0.05:
				var step := minf(WALK_SPEED * delta, to.length())
				visual.global_position += to.normalized() * step
				visual.update_locomotion(to.normalized() * (step / delta), delta)
			else:
				visual.present_idle()
				check(visual.global_position.distance_to(target) < 0.1, "The character reaches the marker on a scripted trajectory (%.3f m off)" % visual.global_position.distance_to(target))
				check(max_speed > 0.9 and max_cadence > 0.0, "Production locomotion presentation responds: visual speed %.2f m/s, cadence %.2f" % [max_speed, max_cadence])
				check(&"move" in states_seen, "The walking clip state was entered (states seen %s)" % [states_seen])
				check(foot_gap_peak > 0.15, "The feet actually step (peak fore-aft foot separation %.2f m, hips %.3f..%.3f m)" % [foot_gap_peak, hips_range.x, hips_range.y])
				_next()
		2:   # stop
			if phase_clock > 1.2:
				var settled := float(report.get("speed", 9.0))
				check(settled < 0.1, "Stopping settles the gait to idle (visual speed %.3f)" % settled)
				_next()
		3:   # turn toward the chair
			if phase_clock < 0.05:
				max_twist = 0.0
				visual.face_world_position(Vector3(chair.position.x, 0.0, chair.position.z))
			if phase_clock > 1.6:
				var to := chair.position - visual.global_position
				var error := absf(rad_to_deg(angle_difference(visual.global_rotation.y, atan2(to.x, to.z))))
				check(error < 2.0, "Turning toward an object: the body faces it within 2 degrees (%.2f)" % error)
				check(max_twist > 5.0, "The production turn presentation ran (hips twist peak %.1f degrees, then unwinds)" % max_twist)
				_next()
		4:   # "unarmed": the rifle slung (an approximation: the rifle still exists)
			if phase_clock < 0.05:
				visual.stow_weapon()
				max_speed = 0.0
				foot_gap_peak = 0.0
				visual.present_move()
			if phase_clock < 0.6:
				return
			var goal := Vector3(2.0, 0.0, 0.5)
			var to := goal - visual.global_position
			to.y = 0.0
			if to.length() > 0.05:
				var step := minf(WALK_SPEED * delta, to.length())
				visual.global_position += to.normalized() * step
				visual.update_locomotion(to.normalized() * (step / delta), delta)
			else:
				visual.present_idle()
				check(visual.is_weapon_stowed(), "Weapon slung (the only unarmed approximation available)")
				check(max_speed > 0.9 and foot_gap_peak > 0.15, "Walking with the weapon slung still steps (speed %.2f, foot separation %.2f m)" % [max_speed, foot_gap_peak])
				_next()
		5:   # a crouch request outside cover
			if phase_clock < 0.05:
				visual.crouch_modifier.depth = 0.3
			if phase_clock > 0.8:
				var depth := float(visual.crouch_modifier.depth)
				if depth > 0.25:
					observed("a direct crouch request persisted (depth %.2f)" % depth)
				else:
					observed("a direct crouch request is overwritten every frame by the adapter's cover sync (depth %.2f): crouching exists only as a cover/tactical function today" % depth)
				_next()
		6:
			if phase_clock > 0.3:
				_finish()

func _next() -> void:
	phase += 1
	phase_clock = 0.0

func _has_tactical_nodes() -> bool:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is TacticalUnit:
			return true
		stack.append_array(node.get_children())
	return false

func _finish() -> void:
	set_process(false)
	observed("no generic interaction request exists (present_interact: %s); the only interaction is the rescue pickup/carry, triggered by the objective system" % visual.has_method("present_interact"))
	observed("no sitting or lowering-to-object capability exists (sit: %s)" % visual.has_method("sit"))
	observed("the production visual scene carries a built-in -1 m offset that assumes a tactical unit origin at the body centre (standing_height); a host has to undo it")
	observed("the rig always builds a rifle (assert in CharacterRig); 'unarmed' can only be a slung rifle")
	observed("the movement clip must be requested by the caller (present_move / present_idle); update_locomotion only feeds speed and heading")
	observed("update_locomotion turns the whole body toward the velocity at 360 deg/s: facing control belongs to the adapter, there is no separate facing intent")
	print("RESULT states seen: %s" % [states_seen])
	print("RESULT frames %d, scripted time %.1f s, checks %d, failures %d" % [frames, clock, checks, failures])
	if auto:
		get_tree().quit(1 if failures else 0)
