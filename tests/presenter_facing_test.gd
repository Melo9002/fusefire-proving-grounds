extends SceneTree
## Facing ownership (Task 07 package 7). The presenter decides where a character faces and the rig applies it: a world point, an explicit yaw, a held facing, the velocity-follow turn, an eased ladder turn,
## the absorption of a facing change into a cover pose, and a direction gameplay authority committed. The tactical adapter only translates (which cover holds the body, which direction is committed) and writes no
## yaw of its own; the workbench uses the same presenter calls and the same shot decision as the tactical host. Structural headless checks.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const WORKBENCH := preload("res://art/characters/mira_0/demo/mira_0_pose_workbench.tscn")
const UNIT_SCENE := preload("res://units/tactical_unit.tscn")
const FacingMode := PresentationTypes.FacingMode
var failures := 0
var checks := 0

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _visual() -> Array:
	var stage := Node3D.new()
	root.add_child(stage)
	var v: UnitVisualAdapter = VISUAL.instantiate()
	stage.add_child(v)
	await _frames(15)
	return [stage, v]

func _world_yaw(v: UnitVisualAdapter) -> float:
	return v.character_root.global_rotation.y

func _run() -> void:
	var pair := await _visual()
	var stage: Node3D = pair[0]
	var v: UnitVisualAdapter = pair[1]
	var p := v.presenter

	# ---- A world point: the node turns at once to it; the same point again changes nothing; a point on the vertical axis is ignored.
	var east := v.global_position + Vector3(5.0, 3.0, 1.0)
	p.face_point(east)
	var expected := atan2(5.0, 1.0)
	check(absf(angle_difference(v.rotation.y, expected)) < 0.0001 and p.facing_mode == FacingMode.FACE_POINT and not p.has_authority_yaw, "face_point turns the node to the point's horizontal bearing (%.1f degrees) and reports FACE_POINT" % rad_to_deg(v.rotation.y))
	var before := v.rotation.y
	p.face_point(east)
	check(is_equal_approx(v.rotation.y, before), "Facing the same point again changes nothing")
	p.face_point(v.global_position + Vector3(0.0, 4.0, 0.0))
	check(is_equal_approx(v.rotation.y, before), "A point straight above the character is ignored")

	# ---- An explicit yaw, and the hips showing the turn only for a visible change.
	p.face_yaw(deg_to_rad(-120.0))
	check(absf(angle_difference(v.rotation.y, deg_to_rad(-120.0))) < 0.0001 and p.facing_mode == FacingMode.FACE_YAW, "face_yaw sets the node's yaw and reports FACE_YAW")
	var twist_before: float = v._twist
	p.face_yaw(deg_to_rad(-120.5))
	check(is_equal_approx(v._twist, twist_before), "A change under one degree shows no hips turn")
	p.face_yaw(deg_to_rad(-60.0), false, false)
	check(is_equal_approx(v._twist, twist_before), "show_turn false changes the yaw without the hips catching up")
	p.face_yaw(deg_to_rad(40.0))
	check(absf(v._twist) > 1.0, "A visible change makes the hips catch up (twist %.1f degrees)" % v._twist)

	# ---- Following velocity, and holding facing.
	var yaw_start := v.rotation.y
	p.report_velocity(Vector3(0, 0, 2.0), 1.0 / 60.0, 360.0)
	var moved_toward := absf(angle_difference(v.rotation.y, 0.0)) < absf(angle_difference(yaw_start, 0.0))
	check(moved_toward and p.facing_mode == FacingMode.FOLLOW_VELOCITY and p.speed > 1.9, "Reported velocity turns the character toward it and reports FOLLOW_VELOCITY")
	p.face_yaw(deg_to_rad(90.0))
	p.hold_facing()
	var held_at := v.rotation.y
	for i in 30:
		p.report_velocity(Vector3(0, 0, 2.0), 1.0 / 60.0, 360.0)
	check(p.is_facing_held() and is_equal_approx(v.rotation.y, held_at) and p.speed > 1.9 and p.heading_rate == 0.0 and p.intent().facing_mode == FacingMode.HOLD,
		"A held facing keeps the yaw while the character still moves (speed %.1f), and the snapshot says HOLD" % p.speed)
	p.release_facing_hold()
	for i in 30:
		p.report_velocity(Vector3(0, 0, 2.0), 1.0 / 60.0, 360.0)
	check(not p.is_facing_held() and absf(angle_difference(v.rotation.y, 0.0)) < absf(angle_difference(held_at, 0.0)), "Releasing the hold lets velocity turn it again")

	# ---- Authority: shown exactly as supplied, reported, and replaced by the next request of any kind.
	p.face_authoritative(deg_to_rad(33.0))
	check(absf(angle_difference(v.rotation.y, deg_to_rad(33.0))) < 0.0001 and p.has_authority_yaw and is_equal_approx(p.authority_yaw, deg_to_rad(33.0)) and p.intent().facing_mode == FacingMode.FACE_YAW,
		"A committed yaw is shown exactly and reported as authoritative")
	p.face_point(v.global_position + Vector3(1.0, 0.0, 0.0))
	check(not p.has_authority_yaw, "A later facing request replaces it")
	v.face_committed_direction(Vector2(1.0, 1.0))
	check(absf(angle_difference(v.rotation.y, PI / 4.0)) < 0.0001 and p.has_authority_yaw, "The adapter turns a committed X/Z direction into the authoritative yaw (north-east is 45 degrees)")
	v.face_committed_direction(Vector2.ZERO)
	check(absf(angle_difference(v.rotation.y, PI / 4.0)) < 0.0001, "A zero direction is ignored")

	# ---- Eased turns: the node (a ladder's heading) and the visual root (the workbench's preview turn).
	p.face_yaw(0.0)
	p.turn_toward_yaw(deg_to_rad(170.0), 360.0, 0.1)
	check(absf(angle_difference(v.rotation.y, deg_to_rad(36.0))) < 0.0001, "turn_toward_yaw turns at the given rate (36 degrees in 0.1 s at 360 per second)")
	v.character_root.rotation.y = 0.0
	var rate := p.turn_root_toward(deg_to_rad(170.0), 360.0, 0.1)
	check(absf(v.character_root.rotation.y - deg_to_rad(36.0)) < 0.0001 and absf(rate - deg_to_rad(360.0)) < 0.001, "turn_root_toward turns the visual root and returns the heading rate (%.2f rad/s)" % rate)
	check(p.facing_direction().is_equal_approx(Vector3(sin(v.rotation.y), 0.0, cos(v.rotation.y))), "facing_direction is the read-only horizontal facing")
	v.character_root.rotation.y = 0.0
	await _frames(2)

	# ---- Cover: a facing change is absorbed into the cover yaw, so the body does not snap (the visual root's world yaw is continuous).
	v.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": 1.1, "direction": Vector3.FORWARD}
	v.animation_controller.play(&"cover_low")
	await _frames(40)
	p.face_yaw(0.0)
	await process_frame
	var world_before := _world_yaw(v)
	var cover_before := v._cover_yaw
	v.face_world_position(v.global_position + Vector3(4.0, 0.0, -3.0))
	var jump := absf(angle_difference(_world_yaw(v), world_before))
	check(jump < 0.001 and absf(angle_difference(v._cover_yaw, cover_before)) > 0.1, "In cover the facing change is absorbed into the cover yaw: the body's world yaw does not jump (%.4f rad) and the offset took it up" % jump)
	var ramp_before := absf(angle_difference(v._cover_yaw, v._cover_yaw_target(0.0)))
	await _frames(30)
	check(absf(angle_difference(v._cover_yaw, v._cover_yaw_target(0.0))) < ramp_before and p.postures.resolved_source() == v.COVER_POSTURE_SOURCE, "...and the cover posture then eases the body to its pose, still the cover request that wins")
	await _drop(stage)

	# ---- The shot decision is one function for both hosts (a pure table), and neither host repeats it.
	var plan_left := {"mode": CoverEdgeSelector.FiringMode.AROUND_LEFT}
	var plan_right := {"mode": CoverEdgeSelector.FiringMode.AROUND_RIGHT}
	var plan_ordinary := {"mode": CoverEdgeSelector.FiringMode.ORDINARY}
	var plan_protected := {"mode": CoverEdgeSelector.FiringMode.PROTECTED}
	check(CoverEdgeSelector.shot_state(true, plan_left, 1) == &"shoot_left" and CoverEdgeSelector.shot_state(true, plan_right, -1) == &"shoot_right" and CoverEdgeSelector.shot_state(true, plan_ordinary, -1) == &"shoot",
		"Full cover: the plan's lean, or an ordinary shot")
	check(CoverEdgeSelector.shot_state(true, plan_protected, -1) == &"shoot_left" and CoverEdgeSelector.shot_state(true, plan_protected, 1) == &"shoot_right" and CoverEdgeSelector.shot_state(true, {}, 0) == &"shoot_right",
		"Full cover with no honest peek: the passive lean side (right on a tie or none)")
	check(CoverEdgeSelector.shot_state(false, plan_left, -1) == &"shoot", "Low cover always shows the ordinary shot")
	for path in ["res://art/characters/mira_0/demo/mira_0_pose_workbench.gd", "res://presentation/characters/runtime/unit_visual_adapter.gd"]:
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("FiringMode.AROUND_LEFT: shot") and not text.contains("&\"shoot_left\" if cover_side"), "%s does not repeat the shot decision" % path.get_file())

	# ---- The workbench uses the same presenter calls (a cover target turns the body through the presenter, absorbed, no snap).
	var bench: Node3D = WORKBENCH.instantiate()
	root.add_child(bench)
	await _frames(15)
	bench.set_cover_demo({"full": false, "height": 1.1, "left": 0.4, "right": 0.4, "left_ok": true, "right_ok": true, "aim": true})
	await _frames(30)
	var bench_world: float = bench.character_root.global_rotation.y
	bench.set_cover_target(bench.global_position + Vector3(3.0, 0.0, 2.0))
	check(bench.presenter.facing_mode == FacingMode.FACE_YAW and absf(angle_difference(bench.character_root.global_rotation.y, bench_world)) < 0.001, "The workbench's cover target faces through the presenter and the body does not snap")
	bench.set_cover_demo({})
	bench.queue_free()
	await _frames(2)

	await _shield_wiring()

	print("Presenter facing: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _drop(stage: Node) -> void:
	stage.queue_free()
	await _frames(2)

## The Shield stance's committed facing reaches the presentation exactly as gameplay supplied it, and it is the direction the unit used to face (the threat's), within a fraction of a degree, so no
## observable Shield behaviour changed: the committed direction is built from the same cell centres the units stand on.
func _shield_wiring() -> void:
	var grid := GridManager.new()
	root.add_child(grid)
	var registry := TacticalActorRegistry.new()
	var presenter := TacticalActionPresenter.new()
	root.add_child(presenter)
	presenter.setup(registry, grid, null, func(): return false, Callable())
	var guard := UNIT_SCENE.instantiate() as TacticalUnit
	guard.tactical_id = &"guard"
	guard.show_world_hud = false
	root.add_child(guard)
	var threat := UNIT_SCENE.instantiate() as TacticalUnit
	threat.tactical_id = &"threat"
	threat.faction = TacticalUnit.Faction.ENEMY
	threat.show_world_hud = false
	root.add_child(threat)
	await _frames(3)
	registry.register_actor(guard)
	registry.register_actor(threat)
	var result := ShieldActionResult.new()
	result.request = TacticalActionRequest.mission(&"shield", &"guard", &"threat", 0, TacticalActionRequest.Source.SYSTEM)
	var worst := 0.0
	for offset in [Vector3(6, 0, 0), Vector3(4, 0, 4), Vector3(-3, 0, 5), Vector3(0, 0, -6), Vector3(5, 0, -2)]:
		guard.global_position = Vector3(2, 1, 2)
		threat.global_position = guard.global_position + offset
		var committed := Vector2(offset.x, offset.z).normalized()
		guard.tactical_state.reset()
		guard.tactical_state.establish_shield(committed)
		await presenter.present_shield(result)
		var shown := guard.visual_adapter.rotation.y
		var committed_yaw := atan2(committed.x, committed.y)
		var toward_threat := atan2(offset.x, offset.z)
		check(absf(angle_difference(shown, committed_yaw)) < 0.0001 and guard.visual_adapter.presenter.has_authority_yaw, "Shield presentation shows the committed facing exactly and reports it as authoritative (offset %s)" % [offset])
		worst = maxf(worst, absf(rad_to_deg(angle_difference(shown, toward_threat))))
	check(worst < 0.01, "...and it is the direction toward the threat the unit used to face (worst difference %.5f degrees)" % worst)
	guard.tactical_state.reset()
	guard.visual_adapter.rotation.y = 0.0
	await presenter.present_shield(result)
	check(absf(angle_difference(guard.visual_adapter.rotation.y, atan2(threat.global_position.x - guard.global_position.x, threat.global_position.z - guard.global_position.z))) < 0.0001 and not guard.visual_adapter.presenter.has_authority_yaw,
		"Without a committed shield facing the presentation still faces the threat's position, as before")
	guard.queue_free()
	threat.queue_free()
	presenter.queue_free()
	grid.queue_free()
	await _frames(2)
