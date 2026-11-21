extends Resource
## Task 05 PROTOTYPE. The root rig profile. It REFERENCES Godot's own BoneMap (which references SkeletonProfileHumanoid) instead of copying the humanoid skeleton definition, and holds only
## anatomy: bone mapping, authored anatomy facts, sockets. Gait style, equipment and gameplay role live in other resources that reference this one.
const Anatomy := preload("res://presentation/characters/rig_profile/rig_anatomy.gd")
const Socket := preload("res://presentation/characters/rig_profile/rig_socket.gd")
@export var display_name := ""
@export var skeleton_map: BoneMap
@export var anatomy: Anatomy
@export var sockets: Array[Socket] = []
