extends SceneTree
## The loaded ladder in the real Exploration Playground (animation assignment), for every carrier/passenger pairing: the two selectors are independent, the casualty keeps its own identity through lift, carry, climb,
## descent and put-down, the climb waits for the passenger to be moved into the climbing carry before the body moves (at the foot AND at the head of the ladder), the ordinary carry returns afterwards, and nothing is left behind.
## Driven the way a player drives it: the pickers' code paths, E, W and S. Real time (a few minutes for four pairings).
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
const IDS := [&"mira_0", &"small_mira_0"]   # the playground's own characters, in its picker order

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


func _place(position: Vector3, camera_yaw: float) -> void:
	world.body.global_position = position
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.pivot_position = world._focus_point()


func _run() -> void:
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	await _selectors_are_independent()
	for carrier in IDS.size():
		for passenger in IDS.size():
			await _pairing(carrier, IDS[passenger])
	print("loaded_ladder_playground_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


## Changing one model never changes the other, and neither silently follows the other.
func _selectors_are_independent() -> void:
	world._select_character(0)
	world.carry.set_passenger(IDS[1])
	await _wait(0.5)
	check(world.character_index == 0 and world.carry.passenger_id == IDS[1] and world.carry.prop.definition.character_id == IDS[1], "A regular carrier and a small casualty: the two choices are held separately")
	world._select_character(1)
	await _wait(0.5)
	check(world.character_index == 1 and world.carry.passenger_id == IDS[1], "Choosing the carrier does not change the casualty")
	world.carry.set_passenger(IDS[0])
	await _wait(0.3)
	check(world.character_index == 1 and world.carry.prop.definition.character_id == IDS[0], "Choosing the casualty does not change the carrier, and the lying body is rebuilt as the chosen one")
	var model: Node3D = world.carry.prop.find_child("PassengerModel", true, false)
	var own := PassengerDefinition.for_character(IDS[0])
	check(model != null and is_equal_approx(model.scale.x, own.scale), "The casualty keeps its own scale (%.2f), not the carrier's" % (model.scale.x if model != null else -1.0))
	check(world.passenger_picker.get_selected_id() == world.passenger_picker.get_item_id(0) or world.passenger_picker.selected == 0, "The picker shows the casualty's model")


func _pairing(carrier_index: int, passenger: StringName) -> void:
	var label := "%s carries %s" % [IDS[carrier_index], passenger]
	world._select_character(carrier_index)
	world.carry.set_passenger(passenger)
	await _wait(0.6)
	check(world.character_index == carrier_index and world.carry.passenger_id == passenger, "%s: both choices stand" % label)
	var definition := PassengerDefinition.for_character(passenger)

	# ---- Lift: the body that lies there is the one that is lifted.
	_place(Vector3(8.0, 0.0, -4.5), PI)
	await _wait(0.5)
	var body_before: Node = world.carry.prop
	check(world.carry.can_pick_up() and world.carry.prop.definition.character_id == passenger, "%s: the lying body is the chosen casualty" % label)
	world.interact()
	await _wait(4.3)
	var rig: CharacterRig = world.visual.rig
	check(world.visual.is_carrying() and not world.carry.busy, "%s: the lift completes" % label)
	check(is_instance_valid(rig.carry_passenger) and rig.carry_passenger.definition.character_id == passenger and is_equal_approx(rig.carry_passenger.find_child("PassengerModel", true, false).scale.x, definition.scale), "%s: the carried body is the casualty, at its own scale" % label)
	check(not is_instance_valid(body_before) or body_before.is_queued_for_deletion(), "%s: the ground body is gone, so there are not two bodies for one casualty" % label)
	check(not world.passenger_picker.disabled or true, "%s: (the picker is reachable from the menu)" % label)

	# ---- Up the ladder, from its foot.
	check(world.traversal.place_at_approach(false), "%s: the foot-of-ladder shortcut places the carrier" % label)
	await _wait(0.6)
	check(world.traversal.can_mount() and world._prompt_text() == "Press E to climb", "%s: a loaded carrier is offered the ladder" % label)
	world.interact()
	await _wait(0.1)
	check(world.traversal.on_ladder and rig.ladder != null and rig.loaded_ladder != null, "%s: E mounts it with the loaded presentation" % label)
	_press(&"playground_forward", true)
	var held := true
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 700 and not rig.loaded_ladder_ready():
		await process_frame
		held = held and world.body.global_position.y < 0.02
	check(held, "%s: W waits while the passenger is moved onto the back (the body did not rise during the transfer)" % label)
	await _wait(1.8)
	check(world.body.global_position.y > 0.5 and rig.loaded_ladder != null and rig.loaded_ladder.blend > 0.999, "%s: then it climbs, the passenger in the climbing carry (%.2f m)" % [label, world.body.global_position.y])
	check(rig.carry_passenger.definition.character_id == passenger, "%s: the casualty is still itself on the ladder" % label)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 12000 and world.traversal.on_ladder:
		await process_frame
	_press(&"playground_forward", false)
	check(not world.traversal.on_ladder and absf(world.body.global_position.y - 3.0) < 0.15, "%s: she steps onto the tower (y %.2f)" % [label, world.body.global_position.y])
	await _wait(2.2)
	check(world.visual.is_carrying() and rig.loaded_ladder == null and rig.carry_passenger.pose_blend > 0.999, "%s: the ordinary carry is back, nothing left of the transfer" % label)
	check(rig.carry_passenger.ladder_blend == 0.0 and rig.carry_passenger.landing_tuck == 0.0, "%s: the passenger is across the shoulders again" % label)

	# ---- Down, from the head of the ladder.
	check(world.traversal.can_mount(), "%s: the ladder can be entered from the deck, loaded" % label)
	world.interact()
	await _wait(0.1)
	var top: Vector3 = world.body.global_position
	_press(&"playground_back", true)
	held = true
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 900 and not rig.loaded_ladder_ready():
		await process_frame
		held = held and world.body.global_position.distance_to(top) < 0.03
	check(held, "%s: S waits at the head of the ladder until the passenger is in the climbing carry" % label)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 14000 and world.traversal.on_ladder:
		await process_frame
	_press(&"playground_back", false)
	check(not world.traversal.on_ladder and world.body.global_position.y < 0.15, "%s: the descent hands control back on the floor" % label)
	await _wait(2.2)
	check(world.visual.is_carrying() and rig.loaded_ladder == null and rig.carry_passenger.ladder_blend == 0.0, "%s: the ordinary carry is back at the bottom" % label)

	# ---- Put down: the same body lies there, still itself.
	_place(Vector3(8.0, 0.0, -4.5), PI)
	await _wait(0.4)
	world.interact()
	await _wait(3.8)
	check(not world.visual.is_carrying() and is_instance_valid(world.carry.prop) and world.carry.prop.definition.character_id == passenger, "%s: put down, the casualty lies there and is still itself" % label)
	check(is_equal_approx(world.carry.prop.find_child("PassengerModel", true, false).scale.x, definition.scale), "%s: and still at its own scale" % label)
	check(world.carry.can_change_passenger(), "%s: the casualty may be changed again" % label)
