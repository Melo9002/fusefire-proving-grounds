extends Resource
## Task 05 PROTOTYPE. What a piece of equipment needs from a body. Equipment is chosen by gameplay; this only says which sockets it would physically attach to. Unarmed needs none.
@export var display_name := ""
@export var required_sockets: Array[StringName] = []
@export var two_handed := false
