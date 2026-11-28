class_name PlaygroundCarry
extends Node
## Casualties and carrying (sandbox package). Several bodies lie about at once (`casualties`, each a PlaygroundCasualty with its own world identity and its own model); E near one lifts it onto her shoulders (the shared
## rescue lift), she walks with the loaded gait (slower, no rifle), E puts it down in front of her (after PlaygroundPlacement has found room for it) and it stays where it was put. One body is carried at a time.
## A lying body is a RescuePassenger; the carried one is the character rig's own. Nothing here is a rescue objective.
##
## Ownership: a body is GROUNDED (its node lies in the world), LIFTING (its node is hidden while the rig shows it, and comes back if the lift does not finish), CARRIED (the rig's) or RELEASING (the rig's, until the
## body is lying again). A lift or put-down that does not finish never loses the body.

const RESCUE := preload("res://presentation/characters/rig/rescue_passenger.gd")
const REACH := 2.0
const CARRY_SPEED_FACTOR := 0.7

var ctx: Node
var casualties: Array[PlaygroundCasualty] = []
var carried: PlaygroundCasualty
var busy := false
var _lifting: PlaygroundCasualty
var _releasing: PlaygroundCasualty
var _planned_spot := Vector3.ZERO
var _planned_yaw := 0.0
var _handle: ActionHandle


## `specs`: one dictionary per default casualty: {id, character (a character id), position, yaw}.
func setup(controller: Node, specs: Array) -> void:
	ctx = controller
	for spec: Dictionary in specs:
		add_casualty(spec)


func add_casualty(spec: Dictionary) -> PlaygroundCasualty:
	var definition := PassengerDefinition.for_character(StringName(spec.character))
	if definition == null:
		return null
	var casualty := PlaygroundCasualty.new(StringName(spec.id), definition, ctx.label_of(definition.character_id), spec.position, float(spec.yaw))
	casualties.append(casualty)
	_lie(casualty, casualty.home, casualty.home_yaw)
	return casualty


func remove_casualty(casualty: PlaygroundCasualty) -> void:
	if is_instance_valid(casualty.node):
		casualty.node.queue_free()
	casualties.erase(casualty)


func find(body_id: StringName) -> PlaygroundCasualty:
	for casualty in casualties:
		if casualty.id == body_id:
			return casualty
	return null


## Puts the casualty's body on the floor at `at` (the floor point under its abdomen), heading `yaw`.
func _lie(casualty: PlaygroundCasualty, at: Vector3, yaw: float) -> void:
	if is_instance_valid(casualty.node):
		casualty.node.queue_free()
	var rig: CharacterRig = ctx.visual.rig
	var lying: Node3D = RESCUE.new()
	lying.name = "Casualty_%s" % casualty.id
	ctx.add_child(lying)
	lying.build_from(casualty.definition)
	# lie_on_ground places the body in its parent's space; the playground is at the world origin.
	lying.lie_on_ground(Vector3(at.x, at.y + rig.rescue_interaction.ground_height, at.z), yaw)
	casualty.node = lying
	casualty.state = PlaygroundCasualty.State.GROUNDED


func carrying() -> bool:
	return ctx.visual.is_carrying()


func _blocked() -> bool:
	return busy or carrying() or ctx.dead or ctx.cover.active or ctx.traversal.on_ladder or ctx.traversal.on_stairs


## The body E would lift: the nearest lying one in reach (the lift turns her to it, so a body behind her counts); of two at nearly the same distance, the one more ahead of her; a tie goes to the one that came first. Null when none is in reach.
func target() -> PlaygroundCasualty:
	if _blocked():
		return null
	var feet: Vector3 = ctx.body.global_position
	var forward: Vector3 = ctx.visual.rig.character_root.global_basis.orthonormalized().z
	forward.y = 0.0
	forward = forward.normalized()
	var best: PlaygroundCasualty
	var best_score := INF
	for casualty in casualties:
		if not casualty.is_grounded():
			continue
		var offset: Vector3 = casualty.node.global_position - feet
		offset.y = 0.0
		var distance := offset.length()
		if distance > REACH:
			continue
		var ahead := forward.dot(offset / maxf(distance, 0.001))
		var score := distance - 0.4 * ahead
		if score < best_score - 0.0001:
			best_score = score
			best = casualty
	return best


func can_pick_up() -> bool:
	return target() != null


## Lifts `casualty` (default: the one `target()` names). Its body stays in the world, hidden, until the lift has finished.
func pick_up(casualty: PlaygroundCasualty = null) -> bool:
	if casualty == null:
		casualty = target()
	if casualty == null or _blocked() or not casualty.is_grounded():
		return false
	var point := casualty.node.global_position
	ctx.combat.set_aim(false)
	ctx.visual.set_crouched(false)
	casualty.node.visible = false
	casualty.state = PlaygroundCasualty.State.LIFTING
	_lifting = casualty
	busy = true
	var handle: ActionHandle = ctx.visual.pick_up(point, casualty.definition)
	_handle = handle
	handle.when_done(_lift_finished.bind(casualty))
	return true


func _lift_finished(outcome: PresentationTypes.Outcome, casualty: PlaygroundCasualty) -> void:
	busy = false
	_lifting = null
	if casualty.state != PlaygroundCasualty.State.LIFTING:
		return   # already dealt with (a reset)
	var finished := outcome == PresentationTypes.Outcome.COMPLETED or outcome == PresentationTypes.Outcome.SKIPPED
	if finished and ctx.visual.is_carrying():
		if is_instance_valid(casualty.node):
			casualty.node.queue_free()
		casualty.node = null
		casualty.state = PlaygroundCasualty.State.CARRIED
		carried = casualty
		return
	# The lift did not finish (interrupted, cancelled): whatever the rig holds is let go and the body is where it lay.
	if ctx.visual.is_carrying():
		ctx.visual.rig.end_carry(false)
	casualty.state = PlaygroundCasualty.State.GROUNDED
	if is_instance_valid(casualty.node):
		casualty.node.visible = true
	else:
		_lie(casualty, casualty.home, casualty.home_yaw)


## Whether the carried body could be put down now, and facing which way. NAN: nowhere around her is clear.
func release_direction() -> float:
	var rig: CharacterRig = ctx.visual.rig
	var forward: Vector3 = rig.character_root.global_basis.orthonormalized().z
	forward.y = 0.0
	return PlaygroundPlacement.find_direction(ctx.get_world_3d(), ctx.body.global_position, forward.normalized(), _carried_scale(), [ctx.body.get_rid()])


func _carried_scale() -> float:
	return carried.definition.scale if carried != null and carried.definition.scale > 0.0 else 1.0


func can_put_down() -> bool:
	return carried != null and not busy and carrying() and not ctx.traversal.on_ladder and not ctx.dead and not is_nan(release_direction())


## Puts the carried body down where PlaygroundPlacement found room: straight ahead when that is clear, else she turns to the nearest direction that is. Refused (and the body stays on her) when there is none.
func put_down() -> bool:
	if carried == null or busy or not carrying() or ctx.traversal.on_ladder or ctx.dead:
		return false
	var yaw := release_direction()
	if is_nan(yaw):
		ctx._show_toast("No room to put the body down here")
		return false
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	_planned_spot = ctx.body.global_position + forward * PlaygroundPlacement.AHEAD
	_planned_yaw = yaw   # the lying body's long axis is the carrier's right: lie_on_ground's heading is the carrier's own yaw
	var rig: CharacterRig = ctx.visual.rig
	var facing: Vector3 = rig.character_root.global_basis.orthonormalized().z
	if absf(angle_difference(atan2(facing.x, facing.z), yaw)) > deg_to_rad(1.0):
		ctx.visual.face_yaw(yaw)
	busy = true
	_releasing = carried
	carried.state = PlaygroundCasualty.State.RELEASING
	var handle: ActionHandle = ctx.visual.put_down()
	_handle = handle
	handle.when_done(_release_finished.bind(carried))
	return true


func _release_finished(outcome: PresentationTypes.Outcome, casualty: PlaygroundCasualty) -> void:
	busy = false
	_releasing = null
	if casualty.state != PlaygroundCasualty.State.RELEASING:
		return
	# The rig leaves the body it set down beside its host, under her physics body: put it in the world where it lies so it does not follow her.
	for child in ctx.body.get_children():
		if child.get_script() == RESCUE:
			(child as Node3D).reparent(ctx, true)
			child.name = "Casualty_%s" % casualty.id
			casualty.node = child as Node3D
			casualty.state = PlaygroundCasualty.State.GROUNDED
			carried = null
			return
	if ctx.visual.is_carrying():
		casualty.state = PlaygroundCasualty.State.CARRIED   # the put-down did not happen: the body is still on her
		return
	# The rig let the body go without leaving one (interrupted): it is where the put-down was heading.
	_lie(casualty, _planned_spot, _planned_yaw)
	carried = null


## The carried body, let go at once and laid on the floor in front of her (or the nearest clear place): for a carrier who is defeated or whose character is rebuilt. Never loses the body.
func drop_carried_now() -> void:
	var casualty := carried if carried != null else (_releasing if _releasing != null else _lifting)
	if casualty == null:
		return
	var rig: CharacterRig = ctx.visual.rig
	var feet: Vector3 = ctx.body.global_position
	var forward: Vector3 = rig.character_root.global_basis.orthonormalized().z
	forward.y = 0.0
	forward = forward.normalized()
	var yaw := PlaygroundPlacement.find_direction(ctx.get_world_3d(), feet, forward, _carried_scale(), [ctx.body.get_rid()])
	if is_nan(yaw):
		yaw = atan2(forward.x, forward.z)
	var spot := feet + Vector3(sin(yaw), 0.0, cos(yaw)) * PlaygroundPlacement.AHEAD
	if carrying():
		rig.end_carry(false)
	_lie(casualty, spot, yaw)
	carried = null
	_lifting = null
	_releasing = null
	busy = false


## The character was rebuilt (a respawn): a carried body is not lost with the old one.
func character_rebuilt() -> void:
	drop_carried_now()
	busy = false


## Cancels the lift or put-down that is running (the presentation settles CANCELLED): a lift puts the body back where it lay, a put-down leaves it on her.
func cancel_action() -> void:
	if _handle != null and not _handle.is_done():
		_handle.cancel()


func can_reset() -> bool:
	return not busy and not ctx.traversal.on_ladder


func why_reset_locked() -> String:
	return "" if can_reset() else "Finish the lift, put-down or climb before resetting the casualties."


## Every casualty back where it started, lying down; a carried one is let go first. Refused during a lift, a put-down or a climb.
func reset_all() -> bool:
	if not can_reset():
		return false
	if carrying():
		ctx.visual.rig.end_carry(false)
	carried = null
	for casualty in casualties:
		_lie(casualty, casualty.home, casualty.home_yaw)
	return true


func can_change_extra() -> bool:
	return not busy and not ctx.traversal.on_ladder


## The optional extra body (menu): a casualty of any character the project has, at a spare spot. An empty id removes it. Never touches the default casualties.
func set_extra(character: StringName, at: Vector3, yaw: float) -> bool:
	if not can_change_extra():
		return false
	var existing := find(&"extra")
	if existing != null:
		if existing == carried:
			return false   # carried: put it down first
		remove_casualty(existing)
	if character == &"":
		return true
	return add_casualty({"id": &"extra", "character": character, "position": at, "yaw": yaw}) != null
