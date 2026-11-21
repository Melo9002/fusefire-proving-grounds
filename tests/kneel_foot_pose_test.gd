extends SceneTree
## Half-kneel rear leg and foot (visual correction pass). The rear foot used to be folded UP and FORWARD over the calf (about 150 degrees from the shin line, an ankle dorsiflexed far past
## anything a person can do) because the kneel's foot term was applied in the wrong direction and sized for a different shin angle. This pins the anatomy and the ground clearance, for both
## kneel sides and at different world elevations (the pose is relative to the character's floor, so the feet must be exactly as clear of the ground at any height).
## Structural headless geometry; the look was reviewed from front, side and rear renders.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const BONES := ["UpLeg", "Leg", "Foot", "ToeBase", "Toe_End"]
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## Bone positions relative to the character's floor point, in the character's own frame (x right, y up, z forward).
func _measure(rig: UnitVisualAdapter, attachments: Dictionary, side: String) -> Dictionary:
	var forward := rig.rig.character_root.global_basis.z.slide(Vector3.UP).normalized()
	var frame := Basis(Vector3.UP.cross(forward).normalized(), Vector3.UP, forward)
	var result := {}
	for bone in BONES:
		var world: Vector3 = (attachments["%s%s" % [side, bone]] as BoneAttachment3D).global_position
		result[bone] = frame.inverse() * (world - rig.global_position)
	return result

func _pose(elevation: float, rear: int) -> Dictionary:
	var stage := Node3D.new()
	stage.position = Vector3(0.0, elevation, 0.0)
	root.add_child(stage)
	var rig: UnitVisualAdapter = VISUAL.instantiate()
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 15:
		await process_frame
	var attachments := {}
	for side in ["Left", "Right"]:
		for bone in BONES:
			var a := BoneAttachment3D.new()
			a.bone_name = "mixamorig_%s%s" % [side, bone]
			rig.rig.skeleton.add_child(a)
			attachments["%s%s" % [side, bone]] = a
	rig.rig.crouch_modifier.kneel_leg = rear
	rig.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": 0.4, "direction": Vector3.FORWARD}
	rig.rig.animation_controller.play(&"cover_low")
	for i in 90:
		await process_frame
	var rear_side := "Right" if rear == 1 else "Left"
	var front_side := "Left" if rear == 1 else "Right"
	var out := {"rear": _measure(rig, attachments, rear_side), "front": _measure(rig, attachments, front_side), "kneel": rig.rig.crouch_modifier.kneel, "rig": rig, "stage": stage}
	return out

func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))

func _run() -> void:
	var reference := {}
	for rear in [1, 0]:
		var tag := "right knee down" if rear == 1 else "left knee down"
		var pose: Dictionary = await _pose(0.0, rear)
		var r: Dictionary = pose.rear
		var f: Dictionary = pose.front
		check(pose.kneel > 0.99, "%s: the very low cover is a full half-kneel (kneel %.2f)" % [tag, pose.kneel])
		var shin: Vector3 = r.Foot - r.Leg
		var foot: Vector3 = r.Toe_End - r.Foot
		var fold := _angle_deg(shin, foot)
		check(fold < 80.0, "%s: the rear foot is NOT folded back over the calf (%.0f degrees from the shin line; the broken pose was about 150)" % [tag, fold])
		# Mirrored: the toes turn a little OUTWARD (away from the other leg) on either side (this frame's +x is the character's left).
		var outward := foot.x > 0.0 if rear == 0 else foot.x < 0.0
		check(outward and absf(foot.x) < absf(foot.z) * 0.6, "%s: the toes point back and slightly outward, mirrored for the other leg (x %.2f, z %.2f)" % [tag, foot.x, foot.z])
		check(foot.normalized().dot(shin.normalized()) > 0.5, "%s: the toes point the way the shin points (back), not toward the knee" % tag)
		# Ground clearance. The planted front foot's toes rest on the floor; nothing of the rear foot may go below that, and it must not hover either.
		var floor_y: float = minf(f.ToeBase.y, f.Toe_End.y)
		check(r.Toe_End.y >= floor_y - 0.02 and r.ToeBase.y >= floor_y - 0.02 and r.Foot.y >= floor_y - 0.02, "%s: the rear foot does not sink below the floor (toe tip %.3f, floor %.3f)" % [tag, r.Toe_End.y, floor_y])
		check(r.Toe_End.y <= floor_y + 0.08, "%s: ...and rests on it rather than hovering (toe tip %.3f above the floor)" % [tag, r.Toe_End.y - floor_y])
		check(r.Leg.y <= floor_y + 0.12, "%s: the rear knee is down on the ground (%.3f above the floor)" % [tag, r.Leg.y - floor_y])
		# The front foot is planted flat and level with the floor.
		check(absf(f.Toe_End.y - f.ToeBase.y) < 0.06 and f.Foot.y < floor_y + 0.15, "%s: the front foot stays planted (ankle %.3f above the floor)" % [tag, f.Foot.y - floor_y])
		reference[rear] = pose
		pose.stage.queue_free()

	# ---- The pose is relative to the character's floor, so the same clearance holds at any elevation.
	var high: Dictionary = await _pose(7.5, 1)
	var low: Dictionary = reference[1]
	var worst := 0.0
	for bone in BONES:
		worst = maxf(worst, (high.rear[bone] - low.rear[bone]).length())
		worst = maxf(worst, (high.front[bone] - low.front[bone]).length())
	check(worst < 0.002, "At +7.5 m of elevation every leg bone sits exactly where it does at ground level, relative to the floor (worst difference %.4f m)" % worst)
	high.stage.queue_free()

	print("Kneel foot pose: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
