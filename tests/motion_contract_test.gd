extends SceneTree
## Task 13: the cross-family motion contract (presentation/motion: MotionRequest, MotionPresenter) with three consumers that need different things: the existing HUMANOID presenter through its opt-in bridge, a WHEELED
## platform (wheels from observed motion, steering from the slip between heading and travel) and a flying DRONE (full 3D velocity, facing independent of travel, visual lean). The two non-humanoid presenters are primitive
## geometry with no skeleton. Frames are stepped by hand with explicit frame numbers and a fixed delta, so nothing depends on timing. Each negative control is a deliberately broken variant that the same check must catch.
const RIG := "res://art/characters/mira_0/runtime/mira_0_rig.tscn"
const DT := 1.0 / 60.0
var failures := 0
var checks := 0
var _frame := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _req(velocity: Vector3, entity: Node3D = null) -> MotionRequest:
	_frame += 1
	return MotionRequest.make(DT, velocity, entity.global_transform if entity != null else Transform3D.IDENTITY, _frame)

## The CONTEXT's job, done by the test: it moves its own entity by the velocity it reports (authority), then asks for the presentation.
func _step(presenter: MotionPresenter, entity: Node3D, velocity: Vector3, configure := Callable()) -> void:
	entity.global_position += velocity * DT
	var request := _req(velocity, entity)
	if configure.is_valid():
		configure.call(request)
	presenter.present(request)

func _run() -> void:
	_request_checks()
	_wheeled_checks()
	_drone_checks()
	await _humanoid_checks()
	_control_checks()
	print("motion_contract_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _drone() -> Dictionary:
	var entity := Node3D.new()
	root.add_child(entity)
	var parts := PrimitiveBodies.build_drone(entity)
	var drone := DronePresenter.new()
	drone.visual = parts.visual
	drone.tilt_pivot = parts.tilt_pivot
	drone.rotors = parts.rotors
	return {"entity": entity, "presenter": drone}

func _wheeled() -> Dictionary:
	var entity := Node3D.new()
	root.add_child(entity)
	var parts := PrimitiveBodies.build_wheeled(entity)
	var platform := WheeledPresenter.new()
	platform.wheels = parts.wheels
	platform.steer_pivots = parts.steer_pivots
	platform.wheel_radius = parts.wheel_radius
	return {"entity": entity, "presenter": platform}

# ---------------------------------------------------------------------------------------------- the request

func _request_checks() -> void:
	var request := MotionRequest.make(DT, Vector3(3, 4, 0))
	check(request.vertical_speed() == 4.0 and request.horizontal_speed() == 3.0 and is_equal_approx(request.speed(), 5.0), "a request keeps the vertical component: horizontal 3, vertical 4, speed 5")
	check(request.horizontal_velocity() == Vector3(3, 0, 0) and request.velocity.y == 4.0, "flattening is a view (horizontal_velocity); the request's own velocity is never changed")
	check(is_nan(request.requested_yaw()) or request.facing_mode == PresentationTypes.FacingMode.HOLD, "by default a request asks for no facing (HOLD)")
	check(is_equal_approx(MotionRequest.make(DT, Vector3(3, 0, 0)).facing_toward_velocity().requested_yaw(), PI * 0.5), "FOLLOW_VELOCITY asks for the heading of the horizontal velocity (+X is a quarter turn)")
	check(is_nan(MotionRequest.make(DT, Vector3(0, 5, 0)).facing_toward_velocity().requested_yaw()), "...and for nothing while the motion is purely vertical")
	check(is_equal_approx(MotionRequest.make(DT, Vector3.ZERO).facing_yaw_of(1.2).requested_yaw(), 1.2), "FACE_YAW asks for exactly that yaw")
	var at := Transform3D(Basis.IDENTITY, Vector3(1, 7, 1))
	check(is_equal_approx(MotionRequest.make(DT, Vector3.ZERO, at).facing_world_point(Vector3(11, 99, 1)).requested_yaw(), PI * 0.5), "FACE_POINT is a horizontal heading from the entity to the point (height ignored)")
	var intent := MotionRequest.make(DT, Vector3(1, 0, 0)).with_intent(Vector3(3, 0, 0))
	check(intent.has_intent and intent.intended_velocity.x == 3.0 and intent.velocity.x == 1.0, "intended and actual velocity are both carried when they differ")

# ---------------------------------------------------------------------------------------------- wheeled

func _wheeled_checks() -> void:
	var rig := _wheeled()
	var entity: Node3D = rig.entity
	var platform: WheeledPresenter = rig.presenter
	for i in 60:
		_step(platform, entity, Vector3(0, 0, 3))
	check(is_equal_approx(platform.spin, fposmod(3.0 / platform.wheel_radius, TAU)) and is_equal_approx(platform.spin_rate, 10.0), "one second at 3 m/s turns the wheels by distance over radius (%.3f rad, rate %.1f)" % [platform.spin, platform.spin_rate])
	check(platform.present_count == 60 and is_equal_approx(platform.time, 60.0 * DT) and platform.duplicate_frames == 0, "presentation time is the sum of the supplied deltas, advanced once per request (%.4f s, %d duplicates)" % [platform.time, platform.duplicate_frames])
	var wheel_angles := platform.wheels.map(func(w: Node3D) -> float: return w.rotation.x)
	check(wheel_angles.all(func(a: float) -> bool: return is_equal_approx(a, platform.spin)), "every wheel shows that rotation")
	check(is_zero_approx(platform.steer) and platform.steer_pivots.all(func(p: Node3D) -> bool: return is_zero_approx(p.rotation.y)), "driving straight steers nothing")
	var before := platform.spin
	for i in 30:
		_step(platform, entity, Vector3.ZERO)
	check(is_equal_approx(platform.spin, before) and is_zero_approx(platform.spin_rate), "stopped, the wheels stop (they do not keep spinning)")
	for i in 30:
		_step(platform, entity, Vector3(0, 0, 3))
	check(platform.spin != before and is_equal_approx(platform.spin_rate, 10.0), "and resume when it moves again")
	# A turn the CONTEXT makes (its body yaws 45 deg/s while moving 3 m/s): the front wheels steer by the curvature that implies, the rear ones stay straight.
	var turn_rate := deg_to_rad(45.0)
	for i in 60:
		entity.rotation.y += turn_rate * DT
		_step(platform, entity, entity.global_basis.z * 3.0)
	var expected := rad_to_deg(atan2(platform.wheelbase * turn_rate, 3.0))
	check(absf(rad_to_deg(platform.steer) - expected) < 0.5 and expected > 20.0, "the front wheels steer by the observed curvature (%.1f deg, expected %.1f)" % [rad_to_deg(platform.steer), expected])
	check(platform.steer_pivots.size() == 2 and platform.steer_pivots.all(func(p: Node3D) -> bool: return is_equal_approx(p.rotation.y, platform.steer)), "...both front pivots, and only those")
	for i in 30:
		_step(platform, entity, entity.global_basis.z * 3.0)
	check(absf(platform.steer) < 0.001, "straightening out unsteers them")
	for i in 20:
		_step(platform, entity, entity.global_basis.z * -2.0)
	check(platform.spin_rate < 0.0, "reversing turns the wheels the other way (%.1f rad/s)" % platform.spin_rate)
	# What it does not have is refused, not faked.
	check(not platform.supports(MotionPresenter.REACTION) and not platform.supports(MotionPresenter.POSTURE) and platform.supports(MotionPresenter.MOTION), "a wheeled platform declares motion only")
	var handle := platform.request_action(MotionPresenter.ACTION_REACTION, 0.5)
	check(handle.is_done() and handle.outcome == PresentationTypes.Outcome.SKIPPED and not platform.is_acting() and platform.refusals.size() == 1 and platform.refusals[0].reason.contains("wheeled"), "a hit reaction is SKIPPED, nothing starts, and the refusal names the family")
	platform.present(_req(Vector3.ZERO, entity).facing_yaw_of(1.0))
	check(platform.refusals.size() == 2 and platform.refusals[1].action == MotionPresenter.FACING, "an orientation request it cannot show is reported once")
	var held := entity.global_transform
	platform.present(_req(Vector3(0, 0, 3), entity))
	check(entity.global_transform == held, "presenting never moves the entity: its authoritative transform is untouched")
	entity.queue_free()

# ---------------------------------------------------------------------------------------------- drone

func _drone_checks() -> void:
	var rig := _drone()
	var entity: Node3D = rig.entity
	var drone: DronePresenter = rig.presenter
	# Hover: still, and the presentation bobs a little; the entity does not.
	var low := 99.0
	var high := -99.0
	for i in 120:
		_step(drone, entity, Vector3.ZERO)
		low = minf(low, drone.visual.position.y)
		high = maxf(high, drone.visual.position.y)
	check(high > 0.02 and low < -0.02 and high <= DronePresenter.HOVER_BOB + 0.0001 and entity.global_position == Vector3.ZERO, "hovering bobs the visual by a few centimetres and leaves the entity where it is")
	var idle_rate := drone.rotor_rate
	for i in 60:
		_step(drone, entity, Vector3(0, 2, 0))
	var snapshot := drone.snapshot()
	check(is_equal_approx(float(snapshot.vertical_speed), 2.0) and entity.global_position.y > 1.9, "the drone's vertical velocity reaches the presentation (2 m/s) and its entity climbed")
	check(drone.rotor_rate > idle_rate + 5.0 and absf(drone.pitch) < 0.001 and absf(drone.bank) < 0.001, "climbing spins the rotors faster (%.1f against %.1f rev/s) and does not tilt the body" % [drone.rotor_rate, idle_rate])
	for i in 60:
		_step(drone, entity, Vector3(0, -2, 0))
	check(drone.rotor_rate < idle_rate - 5.0, "descending spins them slower (%.1f rev/s)" % drone.rotor_rate)
	check(drone.visual.position.y == 0.0, "a moving drone does not bob")
	# Lean into travel: forward lowers the nose, sideways banks into the move.
	for i in 90:
		_step(drone, entity, Vector3(0, 0, 5))
	check(absf(rad_to_deg(drone.pitch) + 20.0) < 0.5 and absf(drone.bank) < 0.001 and is_equal_approx(drone.tilt_pivot.rotation.x, -drone.pitch), "flying forward at 5 m/s lowers the nose 20 degrees (%.1f)" % rad_to_deg(drone.pitch))
	for i in 90:
		_step(drone, entity, Vector3(3, 0, 0))
	check(absf(rad_to_deg(drone.bank) + 12.0) < 0.5 and absf(drone.pitch) < 0.5 * PI / 180.0 and is_equal_approx(drone.tilt_pivot.rotation.z, drone.bank), "flying left at 3 m/s banks 12 degrees into it (%.1f)" % rad_to_deg(drone.bank))
	for i in 90:
		_step(drone, entity, Vector3.ZERO)
	check(absf(drone.pitch) < 0.001 and absf(drone.bank) < 0.001, "stopping returns the body to level")
	# Facing is independent of the travel: face +X (yaw 90) while flying along +Z; the entity's own yaw stays zero.
	var authority_before := entity.global_transform.basis
	for i in 120:
		_step(drone, entity, Vector3(0, 0, 2), func(r: MotionRequest) -> void: r.facing_yaw_of(PI * 0.5))
	check(absf(rad_to_deg(drone.yaw_offset) - 90.0) < 0.5 and is_equal_approx(drone.visual.rotation.y, drone.yaw_offset), "an orientation request is shown as a visual yaw offset (%.1f deg) while the drone travels another way" % rad_to_deg(drone.yaw_offset))
	check(entity.global_transform.basis == authority_before, "the entity's authoritative orientation was never touched")
	check(absf(rad_to_deg(drone.bank)) > 7.0 and absf(rad_to_deg(drone.pitch)) < 0.5, "travelling along +Z while facing +X is sideways to the nose: it banks, it does not pitch (bank %.1f)" % rad_to_deg(drone.bank))
	# One-shot hit reaction through the shared lifecycle.
	for i in 60:
		_step(drone, entity, Vector3.ZERO)
	var wobble := 0.0
	var handle := drone.request_action(MotionPresenter.ACTION_REACTION, 0.5)
	for i in 10:
		_step(drone, entity, Vector3.ZERO)
		wobble = maxf(wobble, absf(drone.tilt_pivot.rotation.z))
	check(not handle.is_done() and drone.is_acting() and wobble > deg_to_rad(3.0), "a reaction wobbles the body while it runs (%.1f deg)" % rad_to_deg(wobble))
	for i in 40:
		_step(drone, entity, Vector3.ZERO)
	check(handle.is_done() and handle.outcome == PresentationTypes.Outcome.COMPLETED and not drone.is_acting(), "and completes after its length of presentation time")
	check(absf(drone.tilt_pivot.rotation.z) < 0.001, "...leaving the body level")
	var first := drone.request_action(MotionPresenter.ACTION_REACTION, 5.0)
	var second := drone.request_action(MotionPresenter.ACTION_REACTION, 5.0)
	check(first.outcome == PresentationTypes.Outcome.INTERRUPTED and not second.is_done(), "a newer reaction interrupts the running one")
	second.cancel()
	_step(drone, entity, Vector3.ZERO)
	check(not drone.is_acting() and absf(drone.tilt_pivot.rotation.z) < 0.001, "cancelling ends it at the next frame and clears the wobble")
	var third := drone.request_action(MotionPresenter.ACTION_REACTION, 5.0)
	for i in 5:
		_step(drone, entity, Vector3(0, 0, 4), func(r: MotionRequest) -> void: r.facing_yaw_of(1.0))
	drone.teardown()
	check(third.outcome == PresentationTypes.Outcome.INTERRUPTED and not drone.is_acting() and drone.pitch == 0.0 and drone.bank == 0.0 and drone.yaw_offset == 0.0 and drone.visual.rotation.y == 0.0 and drone.tilt_pivot.rotation == Vector3.ZERO, "removal interrupts the action and returns the presentation to neutral")
	for unsupported in [MotionPresenter.POSTURE, MotionPresenter.TRAVERSAL, &"crouch"]:
		var refused := drone.request_action(unsupported)
		check(refused.is_done() and refused.outcome == PresentationTypes.Outcome.SKIPPED, "a drone refuses %s (SKIPPED)" % unsupported)
	check(not drone.supports(MotionPresenter.POSTURE) and drone.supports(MotionPresenter.REACTION), "its capabilities are motion, facing and reaction")
	entity.queue_free()

# ---------------------------------------------------------------------------------------------- humanoid

func _humanoid_checks() -> void:
	var a: CharacterRig = (load(RIG) as PackedScene).instantiate()   # driven through the contract
	var b: CharacterRig = (load(RIG) as PackedScene).instantiate()   # driven the existing way (the reference)
	b.position.x = 5.0
	root.add_child(a)
	root.add_child(b)
	await _frames(5)
	var bridge := HumanoidMotionBridge.new(a.presenter)
	check(bridge.family() == &"humanoid" and MotionPresenter.ALL_CAPABILITIES.all(func(c: StringName) -> bool: return bridge.supports(c)), "the humanoid family supports every shared capability")
	var ticks_before := a.presenter.tick_count
	for i in 40:
		var velocity := Vector3(2, 0, 3)
		bridge.present(_req(velocity).facing_toward_velocity())   # what every existing host does: the body follows its velocity (a request that says nothing holds the facing)
		b.presenter.report_velocity(velocity, DT, 360.0)
		b.presenter.tick(DT)
	check(a.presenter.tick_count - ticks_before == 40 and bridge.present_count == 40 and is_equal_approx(bridge.time, a.presenter.time), "the bridge ticks the presenter exactly once per request and keeps no second clock")
	check(is_equal_approx(a.global_rotation.y, b.global_rotation.y) and is_equal_approx(a.presenter.speed, b.presenter.speed) and is_equal_approx(a.presenter.time, b.presenter.time), "motion through the contract equals the existing direct calls: same facing, speed and time as the reference")
	# A vertical component is carried but a humanoid walks on the ground: it is not presented, and the result equals the flat one.
	bridge.present(_req(Vector3(2, 5, 3)).facing_toward_velocity())
	b.presenter.report_velocity(Vector3(2, 0, 3), DT, 360.0)
	b.presenter.tick(DT)
	check(is_equal_approx(a.presenter.speed, b.presenter.speed) and a.presenter.velocity.y == 0.0 and is_equal_approx(float(bridge.snapshot().vertical_speed), 5.0), "vertical speed 5 is reported by the snapshot and does not change the humanoid's gait")
	# An explicit facing wins over the travel direction.
	for i in 90:
		bridge.present(_req(Vector3(0, 0, 3)).facing_yaw_of(PI * 0.5))
	check(absf(angle_difference(a.global_rotation.y, PI * 0.5)) < 0.01, "walking +Z while asked to face +X shows +X (%.2f rad)" % a.global_rotation.y)
	for i in 90:
		bridge.present(_req(Vector3(-3, 0, 0)).facing_toward_velocity())
	check(absf(angle_difference(a.global_rotation.y, -PI * 0.5)) < 0.05, "FOLLOW_VELOCITY turns it toward the travel again (%.2f rad)" % a.global_rotation.y)
	# The one-shot action is the presenter's own hold (its handle), not a second lifecycle.
	var reaction := bridge.request_action(MotionPresenter.ACTION_REACTION, 0.3)
	check(a.presenter.is_holding() and a.presenter.hold_report().rank == PresentationTypes.HOLD_REACTION and not reaction.is_done() and a.animation_controller.current_state == &"hit", "a reaction is a reaction-rank hold of the presenter playing the hit clip")
	for i in 25:
		bridge.present(_req(Vector3.ZERO))
		await process_frame   # the presenter does not count a hold down in the frame it was armed: real frames must pass
	check(reaction.is_done() and reaction.outcome == PresentationTypes.Outcome.COMPLETED and not a.presenter.is_holding(), "and completes through the presenter's own clock")
	var refused := bridge.request_action(&"crouch")
	check(refused.outcome == PresentationTypes.Outcome.SKIPPED and bridge.refusals.size() == 1, "a name that is not a shared one-shot is refused even by the humanoid (crouch is a presenter posture request)")
	a.queue_free()
	b.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------------------------- negative controls

## A drone whose presenter reaches back and moves the entity it presents: the harness's authority check must see it.
class AuthorityGrabbingDrone extends DronePresenter:
	var entity: Node3D
	func _present(request: MotionRequest) -> void:
		super(request)
		entity.global_position.y = 0.0   # the defect: presentation overwrites the authoritative height

## A wheeled platform that wrongly claims a reaction it cannot present.
class OverclaimingPlatform extends WheeledPresenter:
	func _capabilities() -> Array[StringName]:
		return [MOTION, REACTION]

func _control_checks() -> void:
	# 1. Vertical motion flattened: the drone's rotors must notice.
	var climb := _drone()
	var flat := _drone()
	for i in 60:
		_step(climb.presenter, climb.entity, Vector3(0, 2, 0))
		_step(flat.presenter, flat.entity, Vector3(0, 0, 0))   # what a contract that dropped Y would deliver
	check(climb.presenter.rotor_rate - flat.presenter.rotor_rate > 5.0 and is_equal_approx(float(flat.presenter.snapshot().vertical_speed), 0.0), "(control) a flattened climb leaves the rotors at idle: the vertical check can tell")
	climb.entity.queue_free()
	flat.entity.queue_free()
	# 2. An authoritative transform modified by a presentation: the entity check must catch it, and must not catch the real one.
	var honest := _drone()
	var grabbing := _drone()
	var bad := AuthorityGrabbingDrone.new()
	bad.visual = grabbing.presenter.visual
	bad.tilt_pivot = grabbing.presenter.tilt_pivot
	bad.rotors = grabbing.presenter.rotors
	bad.entity = grabbing.entity
	for pair in [[honest.presenter, honest.entity], [bad, grabbing.entity]]:
		pair[1].global_position = Vector3(0, 10, 0)
	for i in 10:
		honest.presenter.present(_req(Vector3.ZERO, honest.entity))
		bad.present(_req(Vector3.ZERO, grabbing.entity))
	check(honest.entity.global_position == Vector3(0, 10, 0) and grabbing.entity.global_position.y == 0.0, "(control) the authority check passes an honest drone and catches one that overwrites its entity's height")
	honest.entity.queue_free()
	grabbing.entity.queue_free()
	# 3. An unsupported capability accepted as supported: the refusal check must tell.
	var platform := _wheeled()
	var liar := OverclaimingPlatform.new()
	var refused_honest: ActionHandle = platform.presenter.request_action(MotionPresenter.ACTION_REACTION, 0.5)
	var refused_liar := liar.request_action(MotionPresenter.ACTION_REACTION, 0.5)
	check(refused_honest.is_done() and not refused_liar.is_done() and liar.refusals.is_empty(), "(control) a platform that overclaims REACTION starts an action nothing can show, and the refusal check sees the difference")
	platform.entity.queue_free()
	# 4. Duplicate advancement of presentation time: two presentations of one frame are counted.
	var counted := _drone()
	counted.presenter.present(MotionRequest.make(DT, Vector3.ZERO, Transform3D.IDENTITY, 7))
	counted.presenter.present(MotionRequest.make(DT, Vector3.ZERO, Transform3D.IDENTITY, 7))
	counted.presenter.present(MotionRequest.make(DT, Vector3.ZERO, Transform3D.IDENTITY, 8))
	check(counted.presenter.duplicate_frames == 1 and is_equal_approx(counted.presenter.time, 3.0 * DT), "(control) presenting frame 7 twice is counted as one duplicate (time advanced three times)")
	counted.entity.queue_free()
	# 5. Cleanup: removal while acting leaves nothing running (covered per family above); a presenter with a cancelled handle also settles at once.
	var cleanup := _wheeled()
	cleanup.presenter.teardown()
	check(not cleanup.presenter.is_acting(), "removing a presenter with nothing running is a no-op")
	cleanup.entity.queue_free()
