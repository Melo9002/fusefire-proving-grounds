extends Resource
## Task 05 PROTOTYPE. A named place on the body where equipment or an interaction can attach. The offset is in the parent bone's rest frame, in METRES at character scale.
@export var socket_name: StringName = &""
@export var parent_role: StringName = &""
@export var offset := Transform3D.IDENTITY
