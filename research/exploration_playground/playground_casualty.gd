class_name PlaygroundCasualty
extends RefCounted
## One physical casualty in the sandbox: a body of its own that lies on the floor, is lifted, carried and put down. Playground-local bookkeeping, not a rescue objective and not a tactical actor.
##
## Two identities, deliberately apart: `id` names THIS body in the world (two casualties may be the same character), `character_id` names the model it is (the project's own character id, the same one
## `PassengerDefinition` resolves). The body keeps both from the floor, through the lift, the carry and the put-down, and back to the floor.

enum State {
	GROUNDED,   ## lying in the world: `node` is its body, and it can be picked up
	LIFTING,    ## the lift is running: the rig shows the body, `node` is hidden and kept so a lift that does not finish puts it back
	CARRIED,    ## on the carrier: the rig owns the body, `node` is gone
	RELEASING,  ## the put-down is running: the rig still shows the body
}

var id: StringName
var character_id: StringName
var label: String
var definition: PassengerDefinition
var node: Node3D
var state := State.GROUNDED
## Where it started and how it lay, for a reset.
var home := Vector3.ZERO
var home_yaw := 0.0


func _init(body_id: StringName, body_definition: PassengerDefinition, body_label: String, at: Vector3, yaw: float) -> void:
	id = body_id
	definition = body_definition
	character_id = body_definition.character_id
	label = body_label
	home = at
	home_yaw = yaw


## Where it lies now, or where it was last seen while the rig has it.
func world_position() -> Vector3:
	return node.global_position if is_instance_valid(node) else home


func is_grounded() -> bool:
	return state == State.GROUNDED and is_instance_valid(node)
