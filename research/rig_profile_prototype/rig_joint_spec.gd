extends Resource
## Task 05 PROTOTYPE. One joint's articulation. Limits and pole direction are AUTHORED; bend axes are DERIVED from the rest pose by the resolver. Anatomy only.
@export var role: StringName = &""
@export var min_degrees := 0.0
@export var max_degrees := 150.0
## The direction the joint opens toward, in CHARACTER space (+Z forward, +Y up, +X the character's left): knees +Z, elbows -Z.
@export var pole_direction := Vector3.BACK
@export var mechanical := false
