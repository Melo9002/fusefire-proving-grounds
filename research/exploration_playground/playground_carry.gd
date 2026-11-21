class_name PlaygroundCarry
extends Node
## Carry a body (sandbox package): E near the body lifts it onto her shoulders (the shared rescue lift), she walks with the loaded gait (slower, no rifle), E again puts it down in front of her and it stays where it was put.
## A lying body is a RescuePassenger; the carried one is the character rig's own. Nothing here is a rescue objective.

const RESCUE := preload("res://presentation/characters/rig/rescue_passenger.gd")
const REACH := 2.0
const CARRY_SPEED_FACTOR := 0.7

var ctx: Node
var prop: Node3D
var busy := false


func setup(controller: Node, spot: Vector3) -> void:
	ctx = controller
	_place_prop(spot, 0.6)


func _place_prop(world_position: Vector3, yaw: float) -> void:
	prop = RESCUE.new()
	prop.name = "BodyProp"
	ctx.add_child(prop)
	var rig: CharacterRig = ctx.visual.rig
	prop.build(rig.character_scene, rig.character_scale, rig.rig_profile)
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
	var handle: ActionHandle = ctx.visual.pick_up(point)
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
