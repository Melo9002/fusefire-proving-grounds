class_name PlaygroundCarry
extends Node
## Carry a body (sandbox package): E near the body lifts it onto her shoulders (the shared rescue lift), she walks with the loaded gait (slower, no rifle), E again puts it down in front of her and it stays where it was put.
## A lying body is a RescuePassenger; the carried one is the character rig's own. Nothing here is a rescue objective.

const RESCUE := preload("res://presentation/characters/rig/rescue_passenger.gd")
const REACH := 2.0
## Who the casualty is until someone chooses; independent of the controlled character.
const DEFAULT_PASSENGER: StringName = &"mira_0"
const CARRY_SPEED_FACTOR := 0.7

var ctx: Node
var prop: Node3D
var busy := false
## Who the casualty is (a character id the project already has: art/characters/<id>/runtime/<id>_rig.tscn), chosen independently of the controlled character. It is kept on the body itself (`prop.definition`), so it survives being lifted and put down.
var passenger_id: StringName = DEFAULT_PASSENGER
var _spot := Vector3.ZERO


func setup(controller: Node, spot: Vector3) -> void:
	ctx = controller
	_spot = spot
	_place_prop(spot, 0.6)


func _place_prop(world_position: Vector3, yaw: float) -> void:
	prop = RESCUE.new()
	prop.name = "BodyProp"
	ctx.add_child(prop)
	var rig: CharacterRig = ctx.visual.rig
	var definition := PassengerDefinition.for_character(passenger_id)
	prop.build_from(definition if definition != null else PassengerDefinition.from_rig(rig))
	# lie_on_ground places the body in its parent's space; the playground is at the world origin, so the spot is the local origin.
	prop.lie_on_ground(Vector3(world_position.x, rig.rescue_interaction.ground_height, world_position.z), yaw)


func carrying() -> bool:
	return ctx.visual.is_carrying()


func can_pick_up() -> bool:
	if busy or carrying() or ctx.dead or not is_instance_valid(prop) or ctx.cover.active or ctx.traversal.on_ladder or ctx.traversal.on_stairs:
		return false
	var offset: Vector3 = prop.global_position - ctx.body.global_position
	offset.y = 0.0
	return offset.length() <= REACH


func pick_up() -> void:
	var point: Vector3 = prop.global_position
	ctx.combat.set_aim(false)
	ctx.visual.set_crouched(false)
	# The body that was lying there is the one lifted: it hands over its own identity, whatever the selector says now.
	var handle: ActionHandle = ctx.visual.pick_up(point, prop.definition)
	prop.queue_free()
	prop = null
	busy = true
	handle.when_done(func(_outcome: PresentationTypes.Outcome) -> void: busy = false)


func put_down() -> void:
	if busy or not carrying():
		return
	busy = true
	var handle: ActionHandle = ctx.visual.put_down()
	handle.when_done(func(_outcome: PresentationTypes.Outcome) -> void:
		busy = false
		# The body is left lying where it was put: it is the next one to pick up.
		# The rig leaves it beside its host, here under her physics body: put it in the world where it lies so it does not follow her.
		for child in ctx.body.get_children():
			if child.get_script() == RESCUE:
				(child as Node3D).reparent(ctx, true)
				prop = child as Node3D)


## The body is dropped with the character when it is rebuilt (a respawn): the lying one stays, a carried one is gone.
func character_rebuilt() -> void:
	busy = false


## The selector may only change the casualty while it is lying about: not while it is being lifted, carried, climbed with or put down.
func can_change_passenger() -> bool:
	return not busy and not carrying() and not ctx.traversal.on_ladder


func why_passenger_locked() -> String:
	return "" if can_change_passenger() else "Put the casualty down (and get off the ladder) before changing its model."


## Chooses who the casualty is. A lying one is replaced where it lies; the choice never changes the controlled character.
func set_passenger(id: StringName) -> bool:
	if id == passenger_id and is_instance_valid(prop):
		return true
	if PassengerDefinition.for_character(id) == null or not can_change_passenger():
		return false
	passenger_id = id
	respawn(true)
	return true


## The casualty back at the spot it started at (or, with `where_it_lies`, rebuilt in place: a changed model keeps its position and heading).
func respawn(where_it_lies := false) -> void:
	if not can_change_passenger():
		return
	var at := _spot
	var yaw := 0.6
	if where_it_lies and is_instance_valid(prop):
		at = prop.global_position
		var along := prop.global_basis.x   # the body lies on its back: its own x runs along the heading
		yaw = atan2(-along.z, along.x)
	if is_instance_valid(prop):
		prop.queue_free()
	prop = null
	_place_prop(at, yaw)
