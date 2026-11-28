extends SceneTree
## The Exploration Playground's casualties, interaction and ladder mounting (Prototype 1.5 playground assignment), driven through the playground's own entry points and real input: two physical casualties from the start,
## E's prompt and action as one decision, the lift and put-down for the four carrier/casualty pairings, the body put down only where it fits and is supported (and refused where it does not), the walk-at-the-ladder mount,
## and what happens to a body when the carrier is defeated, reset or the scene is left. Real time (a minute or two).
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


func _place(position: Vector3, camera_yaw: float) -> void:
	world.body.global_position = position
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.pivot_position = world._focus_point()


## The world positions of a lying body's bones.
func _bones(node: Node3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		var sk := skeleton as Skeleton3D
		for index in sk.get_bone_count():
			points.append(sk.global_transform * sk.get_bone_global_pose(index).origin)
	return points


## How many of the body's bones lie inside solid geometry.
func _bones_in_solids(w: Node, node: Node3D) -> int:
	var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
	var inside := 0
	for point in _bones(node):
		var query := PhysicsPointQueryParameters3D.new()
		query.position = point + Vector3.UP * 0.03   # a bone sits a centimetre or two into the floor it lies on; that is not a solid in the way
		query.exclude = [w.body.get_rid()]
		if not space.intersect_point(query, 1).is_empty():
			inside += 1
	return inside


func _pick_up(id: StringName, standing_at: Vector3) -> void:
	world.carry.reset_all() if false else null
	_place(standing_at, PI)
	await _wait(0.4)
	world.interact()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 8000 and (world.carry.busy or not world.visual.is_carrying()):
		await process_frame
	await _wait(0.3)


func _put_down() -> void:
	world.interact()
	var started := Time.get_ticks_msec()
	await process_frame
	while Time.get_ticks_msec() - started < 8000 and world.carry.busy:
		await process_frame
	await _wait(0.3)


func _run() -> void:
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	await _both_casualties_exist()
	await _targeting_and_prompts()
	await _release_placement()
	await _pairings_and_alternation()
	await _lifecycle()
	await _ladder_mounting()
	world.queue_free()
	await _wait(0.3)
	await _scene_reentry()
	print("playground_casualties_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


func _both_casualties_exist() -> void:
	var carry: PlaygroundCarry = world.carry
	check(carry.casualties.size() == 2, "Both default casualties exist from the start (%d)" % carry.casualties.size())
	var regular := carry.find(REGULAR)
	var small := carry.find(SMALL)
	check(regular != null and small != null and regular != small, "They are two world bodies with their own ids")
	check(regular.character_id == &"mira_0" and small.character_id == &"small_mira_0", "...of the two models (%s, %s)" % [regular.character_id, small.character_id])
	for casualty in [regular, small]:
		var model: Node3D = casualty.node.find_child("PassengerModel", true, false)
		check(casualty.is_grounded() and casualty.node.visible and model != null and is_equal_approx(model.scale.x, casualty.definition.scale), "%s lies at the station at its own scale (%.2f)" % [casualty.id, casualty.definition.scale])
	check(regular.node.global_position.distance_to(small.node.global_position) > 2.0, "and they are far enough apart to reach one without the other")
	# Two bodies of one model: identity is the world body, not the model.
	var twin := carry.add_casualty({"id": &"twin", "character": &"mira_0", "position": Vector3(8.0, 0.0, -9.5), "yaw": 0.0})
	check(twin != null and twin.character_id == regular.character_id and twin.id != regular.id and twin.node != regular.node, "Two casualties of the same model are two bodies")
	carry.remove_casualty(twin)
	check(carry.find(&"twin") == null and carry.casualties.size() == 2, "and a body can be removed again")


func _targeting_and_prompts() -> void:
	var carry: PlaygroundCarry = world.carry
	_place(Vector3(0.0, 0.0, 0.0), PI)
	await _wait(0.4)
	check(carry.target() == null and not world.interact(), "Far from both, nothing is offered and E does nothing")
	_place(Vector3(6.5, 0.0, -5.2), PI)
	await _wait(0.4)
	check(world._prompt_text() == "Press E to pick up MIRA" and carry.target() == carry.find(REGULAR), "At the regular casualty the prompt names it (%s)" % world._prompt_text())
	_place(Vector3(9.5, 0.0, -5.2), PI)
	await _wait(0.4)
	check(world._prompt_text() == "Press E to pick up Small MIRA" and carry.target() == carry.find(SMALL), "At the small casualty the prompt names it (%s)" % world._prompt_text())
	_place(Vector3(8.0, 0.0, -5.2), PI)
	await _wait(0.4)
	var near_regular: bool = world.body.global_position.distance_to(carry.find(REGULAR).node.global_position) < world.body.global_position.distance_to(carry.find(SMALL).node.global_position)
	check(not near_regular or carry.target() == carry.find(REGULAR), "Between the two, the nearer one is the target (deterministic)")
	check(carry.target() == carry.target(), "...and asking again gives the same answer")
	# The prompt and the action are the same decision: whatever it says, E does exactly that.
	_place(Vector3(9.5, 0.0, -5.2), PI)
	await _wait(0.4)
	var decision: PlaygroundInteraction = world.decide_interaction()
	check(decision.kind == &"pick_up" and decision.target == carry.find(SMALL) and world._prompt_text() == decision.prompt, "The prompt is the decision's text")
	world.interact()
	await _wait(0.3)
	check(carry.busy and carry.find(SMALL).state == PlaygroundCasualty.State.LIFTING, "E ran that decision: the small casualty is being lifted, not the other")
	check(carry.find(REGULAR).is_grounded(), "The other casualty is untouched meanwhile")
	check(world._prompt_text() == "" and not world.interact(), "During the lift there is no prompt and E does nothing")
	await _wait(4.5)
	check(world.visual.is_carrying() and carry.carried == carry.find(SMALL) and carry.find(SMALL).state == PlaygroundCasualty.State.CARRIED, "The lift completes: the small casualty is carried")
	check(not is_instance_valid(carry.find(SMALL).node), "Its ground body is gone, so there is one body, not two")
	check(carry.target() == null, "While carrying, no other body is a pickup target")
	check(world._prompt_text().begins_with("Press E to put down Small MIRA"), "The prompt names the carried body (%s)" % world._prompt_text())
	await _put_down()
	check(not world.visual.is_carrying() and carry.carried == null and carry.find(SMALL).is_grounded(), "Put down, it lies in the world again")


func _release_placement() -> void:
	var carry: PlaygroundCarry = world.carry
	# At the foot of the ladder, facing the tower: straight ahead is inside the tower. The control: the playground's check says so, and the shared release would indeed have put the body there (below, in a second scene).
	await _pick_up(REGULAR, Vector3(6.5, 0.0, -5.2))
	check(world.visual.is_carrying(), "Carrying the regular casualty")
	world.traversal.place_at_approach(false)
	await _wait(0.4)
	var ahead_blocked: bool = not PlaygroundPlacement.is_clear(world.get_world_3d(), world.body.global_position, 0.0, 1.0, [world.body.get_rid()])
	check(ahead_blocked, "At the ladder foot the place in front of her (inside the tower) is not clear")
	check(world.carry.can_put_down() and absf(angle_difference(world.carry.release_direction(), 0.0)) > deg_to_rad(40.0), "...but there is room another way, and the direction is not straight ahead")
	await _put_down()
	var body: PlaygroundCasualty = carry.find(REGULAR)
	check(body.is_grounded() and _bones_in_solids(world, body.node) == 0, "The body is lying clear of every solid (%d bones inside)" % _bones_in_solids(world, body.node))
	check(absf(body.node.global_position.y - 0.13) < 0.03, "...on the floor (y %.2f)" % body.node.global_position.y)
	check(body.node.find_child("PassengerModel", true, false) != null and body.node.definition.character_id == &"mira_0", "...and it is still itself")
	# On an elevated platform, supported.
	await _pick_up(REGULAR, body.node.global_position + Vector3(0.0, 0.0, 0.9))
	_place(Vector3(16.0, 1.5, 8.0), PI)
	await _wait(0.5)
	await _put_down()
	check(body.is_grounded() and _bones_in_solids(world, body.node) == 0 and body.node.global_position.y > 1.55 and body.node.global_position.y < 1.7, "On the raised platform it lies on the platform, not in it or under it (y %.2f)" % body.node.global_position.y)
	# At an unsupported edge: not put down over the drop.
	await _pick_up(REGULAR, body.node.global_position + Vector3(0.0, 0.0, -0.9))
	_place(Vector3(16.0, 1.5, 9.25), PI)
	world.visual.reset_motion(0.0)
	await _wait(0.5)
	var over_edge: bool = not PlaygroundPlacement.is_clear(world.get_world_3d(), world.body.global_position, 0.0, 1.0, [world.body.get_rid()])
	check(over_edge, "Facing the platform's edge, the place in front of her is over the drop and is not clear")
	await _put_down()
	check(body.is_grounded() and absf(body.node.global_position.y - 1.63) < 0.1 and _bones_in_solids(world, body.node) == 0, "It was put down on the platform, not over the edge (y %.2f)" % body.node.global_position.y)
	# Nowhere to put it: refused, and it stays on her.
	await _pick_up(REGULAR, body.node.global_position + Vector3(0.0, 0.0, -0.9))
	var ring: Array[Node] = []
	for side in [[1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0]]:
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.2, 3.0, 1.6) if side[0] != 0.0 else Vector3(1.6, 3.0, 0.2)
		shape.shape = box
		wall.add_child(shape)
		wall.position = Vector3(-6.0 + side[0] * 0.75, 1.5, 8.0 + side[1] * 0.75)
		world.add_child(wall)
		ring.append(wall)
	_place(Vector3(-6.0, 0.0, 8.0), PI)
	await _wait(0.5)
	check(is_nan(carry.release_direction()) and not carry.can_put_down(), "Walled in on every side there is nowhere to put the body")
	check(world._prompt_text() == "No room to put MIRA down here", "The prompt says so (%s)" % world._prompt_text())
	check(not world.interact() and world.visual.is_carrying() and carry.carried == body and not body.is_grounded(), "E is refused and the body stays on her")
	check(not carry.busy and not world.visual.rig.interaction_active(), "...with no put-down started")
	for wall in ring:
		wall.queue_free()
	await _wait(0.3)
	await _put_down()
	check(not world.visual.is_carrying() and body.is_grounded(), "Out of the walls she can put it down again")
	# The control: the shared release, with no placement check, does put the body into the tower.
	var control: Node = load(PLAYGROUND).instantiate()
	root.add_child(control)
	await _wait(1.0)
	control.body.global_position = Vector3(6.5, 0.0, -5.2)
	control.carry.pick_up(control.carry.find(REGULAR))
	await _wait(5.0)
	control.body.global_position = control.traversal.ladder_foot()
	control.visual.reset_motion(0.0)
	await _wait(0.3)
	control.visual.put_down()   # the shared release as it was: straight ahead, whatever is there
	await _wait(4.5)
	var intruded := 0
	for child in control.body.get_children():
		if child.get_script() == PlaygroundCarry.RESCUE:
			intruded = _bones_in_solids(control, child)
	check(intruded > 0, "Control: the shared release alone lays the body into the tower (%d bones inside), which the placement check prevents" % intruded)
	control.queue_free()
	await _wait(0.3)


func _pairings_and_alternation() -> void:
	var carry: PlaygroundCarry = world.carry
	carry.reset_all()
	for carrier in [0, 1]:
		world._select_character(carrier)
		await _wait(0.5)
		for id in [REGULAR, SMALL, REGULAR]:
			var casualty: PlaygroundCasualty = carry.find(id)
			var other: PlaygroundCasualty = carry.find(SMALL if id == REGULAR else REGULAR)
			await _pick_up(id, Vector3(6.5 if id == REGULAR else 9.5, 0.0, -5.2) if casualty.is_grounded() and casualty.node.global_position.distance_to(casualty.home) < 0.5 else casualty.node.global_position + Vector3(0.0, 0.0, 0.9))
			var label := "carrier %d carries %s" % [carrier, id]
			var rig: CharacterRig = world.visual.rig
			check(world.visual.is_carrying() and carry.carried == casualty and rig.carry_passenger.definition.character_id == casualty.character_id, "%s: the casualty is the one on her shoulders, its own model" % label)
			check(is_equal_approx(rig.carry_passenger.find_child("PassengerModel", true, false).scale.x, casualty.definition.scale), "%s: at its own scale" % label)
			check(other.is_grounded() or other.state == PlaygroundCasualty.State.GROUNDED, "%s: the other casualty is still lying where it was" % label)
			_place(Vector3(-2.0, 0.0, -2.0 + carrier), PI)
			await _wait(0.3)
			await _put_down()
			check(not world.visual.is_carrying() and casualty.is_grounded() and carry.carried == null, "%s: put down, it lies in the world" % label)
			check(casualty.node.definition.character_id == casualty.character_id and _bones_in_solids(world, casualty.node) == 0, "%s: still itself, clear of solids" % label)


func _lifecycle() -> void:
	var carry: PlaygroundCarry = world.carry
	carry.reset_all()
	world._select_character(0)
	await _wait(0.5)
	# Interrupted lift: she walks away mid-lift; the body must come back to the floor.
	_place(Vector3(6.5, 0.0, -5.2), PI)
	await _wait(0.4)
	world.interact()
	await _wait(1.0)
	check(carry.busy and carry.find(REGULAR).state == PlaygroundCasualty.State.LIFTING, "A lift is under way")
	carry.cancel_action()
	await _wait(0.5)
	var regular := carry.find(REGULAR)
	check(not carry.busy and not world.visual.is_carrying() and regular.is_grounded() and regular.node.visible, "A lift that is cancelled puts the body back on the floor and loses nothing")
	check(carry.casualties.size() == 2, "...with no duplicate and no missing body (%d)" % carry.casualties.size())
	# Defeat while carrying: the body is laid down beside her.
	await _pick_up(REGULAR, Vector3(6.5, 0.0, -5.2))
	check(carry.carried == regular, "Carrying again")
	world.player_health.damage(1000.0)   # the real path: health to zero, then the defeat
	await _wait(0.5)
	check(carry.carried == null and regular.is_grounded() and regular.node.global_position.distance_to(world.body.global_position) < 1.6, "Defeated while carrying, the body is laid on the floor beside her, not lost (%.2f m)" % regular.node.global_position.distance_to(world.body.global_position))
	world.player_health.respawn()
	await _wait(1.5)
	check(not world.dead and not world.visual.is_carrying() and carry.casualties.size() == 2 and regular.is_grounded(), "After the respawn both casualties are there")
	# Reset: even with the body on her shoulders.
	await _pick_up(SMALL, Vector3(9.5, 0.0, -5.2))
	check(carry.carried == carry.find(SMALL), "Carrying the small one")
	check(carry.reset_all() and not world.visual.is_carrying() and carry.carried == null, "Reset casualties lets go of a carried body")
	await _wait(0.3)
	for casualty in carry.casualties:
		check(casualty.is_grounded() and casualty.node.global_position.distance_to(casualty.home) < 0.3, "%s is back at its station" % casualty.id)
	# An extra body of any model, without touching the default two.
	check(carry.set_extra(&"small_mira_0", world.props.extra_spot, 0.0) and carry.casualties.size() == 3 and carry.find(&"extra").character_id == &"small_mira_0", "The menu's extra casualty adds a third body")
	check(carry.set_extra(&"", world.props.extra_spot, 0.0) and carry.casualties.size() == 2, "...and removes it again, leaving the two defaults")
	# The controlled character can change with the casualties in place.
	world._select_character(1)
	await _wait(0.5)
	check(world.character_index == 1 and carry.casualties.size() == 2 and carry.find(REGULAR).is_grounded() and carry.find(SMALL).is_grounded(), "Changing the controlled character leaves both casualties alone")
	world._select_character(0)
	await _wait(0.3)


func _ladder_mounting() -> void:
	var traversal: PlaygroundTraversal = world.traversal
	world.carry.reset_all()
	# Walking past the ladder (along the tower face) does not mount it.
	_place(Vector3(-2.5, 0.0, 14.3), -PI * 0.5)
	await _wait(0.4)
	_press(&"playground_forward", true)
	var started := Time.get_ticks_msec()
	var mounted_passing := false
	while Time.get_ticks_msec() - started < 2600:
		await process_frame
		mounted_passing = mounted_passing or traversal.on_ladder
	_press(&"playground_forward", false)
	check(not mounted_passing and world.body.global_position.x > 0.8, "Walking along the tower past the ladder does not mount it (x %.2f)" % world.body.global_position.x)
	# Standing at the foot does not mount it; walking away from it does not.
	_place(traversal.ladder_foot(), PI)
	await _wait(0.8)
	check(not traversal.on_ladder, "Standing at the foot does not mount it")
	_press(&"playground_back", true)
	await _wait(0.8)
	_press(&"playground_back", false)
	check(not traversal.on_ladder, "Walking away from it does not")
	# Walking at it does; stopping stops her on the rungs.
	_place(Vector3(0.0, 0.0, 13.9), PI)
	await _wait(0.4)
	_press(&"playground_forward", true)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 3000 and not traversal.on_ladder:
		await process_frame
	check(traversal.on_ladder, "Walking at the ladder from the foot mounts it")
	await _wait(1.6)
	_press(&"playground_forward", false)
	var stopped_at: float = world.body.global_position.y
	await _wait(0.6)
	check(stopped_at > 0.4 and absf(world.body.global_position.y - stopped_at) < 0.02 and traversal.on_ladder, "Releasing the key stops her on the ladder (y %.2f)" % stopped_at)
	# Down again and off: no immediate remount while still holding the key.
	_press(&"playground_back", true)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 6000 and traversal.on_ladder:
		await process_frame
	check(not traversal.on_ladder and world.body.global_position.y < 0.2, "Climbing down and off returns her to the floor")
	await _wait(1.6)
	check(not traversal.on_ladder, "Holding the key on does not put her straight back on the ladder")
	_press(&"playground_back", false)
	# From the head: walking toward the rungs from the platform, before the edge.
	_place(Vector3(0.0, 3.0, float(traversal.ladder.top_z) + 0.3), PI)
	await _wait(0.5)
	_press(&"playground_back", true)
	started = Time.get_ticks_msec()
	var min_z := INF
	while Time.get_ticks_msec() - started < 3000 and not traversal.on_ladder:
		await process_frame
		min_z = minf(min_z, world.body.global_position.z)
	_press(&"playground_back", false)
	check(traversal.on_ladder and min_z > float(traversal.ladder.deck_edge) + 0.1, "Walking at the ladder from the platform mounts it before the edge (z %.2f, edge %.2f)" % [min_z, float(traversal.ladder.deck_edge)])
	traversal.dismount_bottom()
	await _wait(0.4)


## Leaving the playground and entering it again starts clean: both casualties, nothing held over.
func _scene_reentry() -> void:
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	check(world.carry.casualties.size() == 2 and world.carry.carried == null and not world.visual.is_carrying(), "Entering the playground again starts with both casualties and nobody carried")
	check(world.carry.find(REGULAR).is_grounded() and world.carry.find(SMALL).is_grounded(), "...lying at the station")
	world.queue_free()
