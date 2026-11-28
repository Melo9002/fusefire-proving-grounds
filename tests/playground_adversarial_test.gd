extends SceneTree
## The Exploration Playground against awkward use (Prototype 1.5 refinement): the ladder's approach mounting and the put-down's placement, each tried where a player would trip it.
## Ladder: walking past, a misaligned approach (inside and outside the alignment), letting go before the mount completes, reversing, running at it, the platform edge (the mount timer must not let her walk off), and E next to a casualty
## at the ladder. Placement: a body put down onto another lying body (they have no collider, so the physics query cannot see them), no free direction, the edge of the platform, the release followed at once by another pickup,
## and a put-down that is interrupted. Real time, headless-capable. The fixtures place the character (diagnostic); the approach itself is real input actions.
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
const REGULAR := &"casualty_mira"
const SMALL := &"casualty_small_mira"

var failures := 0
var checks := 0
var world: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_all() -> void:
	for action in [&"playground_forward", &"playground_back", &"playground_left", &"playground_right", &"playground_run"]:
		_press(action, false)


func _place(position: Vector3, camera_yaw: float) -> void:
	_release_all()
	if world.traversal.on_ladder:
		world.traversal._end_ladder()
	world.body.global_position = position
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.pivot_position = world._focus_point()
	world.visual.reset_motion(camera_yaw + PI)


func _settle() -> void:
	await _wait(0.5)


func _not_busy() -> void:
	var waited := 0.0
	while waited < 10.0 and world.carry.busy:
		await _wait(0.1)
		waited += 0.1


func _run() -> void:
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	await _ladder()
	await _placement()
	print("playground_adversarial_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------------------------------------ ladder

func _ladder() -> void:
	var ladder: Dictionary = world.traversal.ladder
	var foot: Vector3 = world.traversal.ladder_foot()
	var rungs_z := float(ladder.z)
	# Camera yaw PI: forward is +Z, toward the rungs.
	# Walking past it: sideways along the foot, never heading at the rungs.
	_place(Vector3(foot.x - 1.2, 0.0, foot.z + 0.1), PI)
	_press(&"playground_right", true)   # +X... along the face
	await _wait(1.8)
	_press(&"playground_right", false)
	check(not world.traversal.on_ladder, "Walking along the foot of the ladder does not mount it")
	# A diagonal at 45 degrees from just inside the rails: outside the alignment, no mount; at about 25 degrees, mounts.
	_place(Vector3(foot.x - 0.3, 0.0, foot.z - 1.2), PI)
	_press(&"playground_forward", true)
	_press(&"playground_right", true)
	await _wait(1.2)
	_release_all()
	check(not world.traversal.on_ladder, "A 45 degree approach (outside the alignment) does not mount")
	_place(Vector3(foot.x - 0.25, 0.0, foot.z - 1.2), PI + deg_to_rad(25.0) * 0.0)
	world.yaw = PI + deg_to_rad(20.0)   # heading 20 degrees toward the centre line of the rails
	world._apply_camera_rotation()
	_press(&"playground_forward", true)
	await _wait(1.8)
	_release_all()
	check(world.traversal.on_ladder, "A slightly misaligned approach (about 20 degrees) still mounts")
	await _end_ladder()
	# Letting go before the mount completes: no mount, then a full walk does.
	_place(Vector3(foot.x, 0.0, foot.z - 0.9), PI)
	_press(&"playground_forward", true)
	await _wait(0.12)
	_press(&"playground_forward", false)
	await _wait(0.6)
	check(not world.traversal.on_ladder, "Letting go of the stick before the mount timer completes does not mount")
	_press(&"playground_forward", true)
	await _wait(1.2)
	_release_all()
	check(world.traversal.on_ladder, "...and the next deliberate walk at the rungs does")
	await _end_ladder()
	# Reversing: a short step at it, then backwards.
	_place(Vector3(foot.x, 0.0, foot.z - 0.9), PI)
	_press(&"playground_forward", true)
	await _wait(0.1)
	_press(&"playground_forward", false)
	_press(&"playground_back", true)
	await _wait(1.0)
	_release_all()
	check(not world.traversal.on_ladder and world.body.global_position.z < foot.z - 0.5, "A step at the ladder then reversing leaves her off it, walking away")
	# Running at it.
	_place(Vector3(foot.x, 0.0, foot.z - 4.0), PI)
	_press(&"playground_run", true)
	_press(&"playground_forward", true)
	var waited := 0.0
	while waited < 4.0 and not world.traversal.on_ladder:
		await _wait(0.05)
		waited += 0.05
	_release_all()
	check(world.traversal.on_ladder and world.body.global_position.z <= rungs_z, "Running at the ladder mounts it, in front of the rungs (z %.2f, rungs %.2f)" % [world.body.global_position.z, rungs_z])
	await _end_ladder()
	# The control: without the approach pace (the behaviour before) the same run goes through the zone before the timer completes and she stands against the rungs, not on them.
	world.traversal.limit_approach = false
	_place(Vector3(foot.x, 0.0, foot.z - 4.0), PI)
	_press(&"playground_run", true)
	_press(&"playground_forward", true)
	await _wait(3.0)
	_release_all()
	check(not world.traversal.on_ladder, "Control: without the approach pace a run at the ladder does not mount it (z %.2f)" % world.body.global_position.z)
	world.traversal.limit_approach = true
	await _end_ladder()
	# Repeated ascents and descents: mount, climb a little, back down, three times.
	for i in 3:
		_place(Vector3(foot.x, 0.0, foot.z - 0.9), PI)
		_press(&"playground_forward", true)
		waited = 0.0
		while waited < 3.0 and not world.traversal.on_ladder:
			await _wait(0.05)
			waited += 0.05
		await _wait(1.0)
		_press(&"playground_forward", false)
		_press(&"playground_back", true)
		waited = 0.0
		while waited < 8.0 and world.traversal.on_ladder:
			await _wait(0.1)
			waited += 0.1
		_release_all()
		check(not world.traversal.on_ladder and world.body.global_position.y < 0.3, "Climb %d: mounted, climbed, came down and stepped off at the foot" % (i + 1))
		await _wait(1.1)
	# Platform edge: she walks toward the edge from the deck; she must be on the ladder before she is over the edge.
	var length := float(ladder.length)
	_place(Vector3(float(ladder.x), length, float(ladder.deck_edge) + 1.0), 0.0)
	_press(&"playground_forward", true)
	var lowest := length
	waited = 0.0
	while waited < 3.0 and not world.traversal.on_ladder:
		await _wait(0.02)
		waited += 0.02
		lowest = minf(lowest, world.body.global_position.y)
	_release_all()
	check(world.traversal.on_ladder and lowest > length - 0.1, "At the platform edge the mount takes her onto the ladder before she can step off (lowest y %.2f of deck %.2f)" % [lowest, length])
	await _end_ladder()
	# E next to a casualty at the ladder: it picks the casualty up, and does not mount.
	var casualty: PlaygroundCasualty = world.carry.find(REGULAR)
	world.carry._lie(casualty, foot + Vector3(0.9, 0.0, -0.4), 0.0)
	_place(foot + Vector3(0.0, 0.0, 0.1), 0.0)
	await _settle()
	var prompt: String = world._prompt_text()
	check(prompt.begins_with("Press E to pick up"), "Standing at the ladder foot next to a casualty, E is a pick-up (%s)" % prompt)
	world.interact()
	await _wait(0.3)
	check(not world.traversal.on_ladder, "...and does not mount the ladder")
	await _not_busy()
	check(world.carry.carrying(), "...the casualty is carried")
	world.carry.cancel_action()
	world.carry.reset_all()
	await _wait(0.5)


func _end_ladder() -> void:
	if world.traversal.on_ladder:
		world.traversal._end_ladder()
	_release_all()
	await _wait(1.1)   # the ladder re-arms after a short pause (REMOUNT_PAUSE)


# ------------------------------------------------------------------------------------------------ placement

func _placement() -> void:
	var space: World3D = world.get_world_3d()
	var feet := Vector3(-3.0, 0.0, -4.0)   # open flat floor
	# Another lying body where the body would go: the placement turns away, or says no room; the control (the others left out) puts it straight onto it.
	var open_yaw := PlaygroundPlacement.find_direction(space, feet, Vector3.BACK, 1.0, [], [])
	check(not is_nan(open_yaw), "The test spot has somewhere to put a body down")
	var open_forward := Vector3(sin(open_yaw), 0.0, cos(open_yaw))
	var ahead := feet + open_forward * PlaygroundPlacement.AHEAD
	var open_axis := Vector3(cos(open_yaw), 0.0, -sin(open_yaw))
	var others: Array = [{"position": ahead, "axis": open_axis, "scale": 1.0}]
	var turned := PlaygroundPlacement.find_direction(space, feet, Vector3.BACK, 1.0, [], others)
	var blind := PlaygroundPlacement.find_direction(space, feet, Vector3.BACK, 1.0, [], [])
	check(is_equal_approx(blind, open_yaw), "Control: ignoring the other body, the spot where it lies (onto it) is chosen")
	check(not is_nan(turned) and absf(angle_difference(turned, open_yaw)) > 0.4, "With the other body counted, the carrier turns away (%.0f degrees)" % rad_to_deg(angle_difference(turned, open_yaw)))
	var chosen_centre := feet + Vector3(sin(turned), 0.0, cos(turned)) * PlaygroundPlacement.AHEAD
	var chosen_axis := Vector3(cos(turned), 0.0, -sin(turned))
	check(not PlaygroundPlacement._footprints_overlap(chosen_centre, chosen_axis, 0.9, 0.34, ahead, open_axis, 0.9, 0.34), "...and the chosen spot does not overlap it")
	# No free direction: a ring of bodies around her.
	var ring: Array = []
	for step in 8:
		var yaw := TAU * float(step) / 8.0
		ring.append({"position": feet + Vector3(sin(yaw), 0.0, cos(yaw)) * PlaygroundPlacement.AHEAD, "axis": Vector3(cos(yaw), 0.0, -sin(yaw)), "scale": 1.0})
	check(is_nan(PlaygroundPlacement.find_direction(space, feet, Vector3.BACK, 1.0, [], ring)), "Surrounded by other bodies there is no direction: the put-down is refused")
	# Small carrying: the smaller body fits where the Regular one does not (scale is taken from the carried body).
	var tight: Array = [{"position": feet + Vector3(1.55, 0.0, 0.0), "axis": Vector3.BACK, "scale": 1.0}, {"position": feet + Vector3(-1.55, 0.0, 0.0), "axis": Vector3.BACK, "scale": 1.0}]
	var small_fit := PlaygroundPlacement.find_direction(space, feet, Vector3.BACK, 0.6, [], tight)
	check(not is_nan(small_fit), "A smaller carried body finds room beside two bodies")
	# The platform's edge: from the deck's edge facing the drop, straight ahead is not supported.
	var ladder: Dictionary = world.traversal.ladder
	var deck_feet := Vector3(float(ladder.x), float(ladder.length), float(ladder.deck_edge) + 0.35)
	check(not PlaygroundPlacement.is_clear(space, deck_feet, PI, 1.0, []), "At the platform's edge, a body put down over the drop is refused")
	# Integration: carry the Small casualty to where the Regular one lies and put it down facing it: it is not laid on top.
	var regular: PlaygroundCasualty = world.carry.find(REGULAR)
	var small: PlaygroundCasualty = world.carry.find(SMALL)
	world.carry.reset_all()
	await _wait(0.5)
	var stand := regular.node.global_position + Vector3(0.0, 0.0, -PlaygroundPlacement.AHEAD)
	stand.y = 0.0
	_place(Vector3(small.node.global_position.x, 0.0, small.node.global_position.z - 1.0), 0.0)
	await _settle()
	world.carry.pick_up(small)
	await _not_busy()
	check(world.carry.carrying(), "Picked up the Small casualty")
	_place(stand, PI)
	world.visual.face_yaw(0.0)
	await _wait(0.6)
	var other_spot: Vector3 = regular.node.global_position
	var put: bool = world.carry.put_down()
	await _not_busy()
	await _wait(0.3)
	if put:
		var d := Vector2(small.node.global_position.x - other_spot.x, small.node.global_position.z - other_spot.z).length()
		check(d > 0.6, "Put down facing another casualty, the body is not laid on it (%.2f m apart)" % d)
	else:
		check(world.carry.carrying() and not small.is_grounded(), "...or the put-down was refused and the body stayed on her")
	# Release followed at once by another pickup.
	if world.carry.carrying():
		world.carry.drop_carried_now()
	world.carry.reset_all()
	await _wait(0.5)
	_place(Vector3(small.node.global_position.x, 0.0, small.node.global_position.z - 1.0), 0.0)
	await _settle()
	world.carry.pick_up(small)
	await _not_busy()
	_place(Vector3(-3.0, 0.0, -4.0), 0.0)
	await _wait(0.4)
	var released: bool = world.carry.put_down()
	await _not_busy()
	check(released and small.is_grounded(), "Released the body")
	world.interact()
	await _not_busy()
	check(world.carry.carrying() and world.carry.carried == small, "Picked straight up again after the release, nothing lost")
	# An interrupted put-down: the body ends carried, or lying clear; never lost.
	world.carry.put_down()
	await _wait(0.5)
	world.carry.cancel_action()
	await _not_busy()
	await _wait(0.5)
	check(world.carry.carrying() or (small.is_grounded() and is_instance_valid(small.node)), "An interrupted put-down leaves the body either carried or lying on the ground, not lost")
	world.carry.reset_all()
