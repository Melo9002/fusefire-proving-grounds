extends SceneTree
## Lists the weapon model's nodes with local bounds so grip points can be read off the model.
##   godot_console --headless --path . --script res://tools/quality/weapon_nodes_probe.gd
func _initialize() -> void:
	var weapon := (load("res://art/weapons/aug/models/aug_runtime_socketed.glb") as PackedScene).instantiate() as Node3D
	root.add_child(weapon)
	_walk(weapon, weapon, 0)
	quit(0)

func _walk(node: Node, origin: Node3D, depth: int) -> void:
	var line := "WNODE %s%s (%s)" % ["  ".repeat(depth), node.name, node.get_class()]
	if node is Node3D:
		var local: Vector3 = origin.global_transform.affine_inverse() * (node as Node3D).global_position
		line += " at (%.3f, %.3f, %.3f)" % [local.x, local.y, local.z]
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var aabb: AABB = (node as MeshInstance3D).mesh.get_aabb()
		var box := (node as MeshInstance3D).global_transform * aabb
		var inverse := origin.global_transform.affine_inverse()
		var low: Vector3 = inverse * box.position
		var high: Vector3 = inverse * box.end
		line += " bounds (%.3f,%.3f,%.3f)-(%.3f,%.3f,%.3f)" % [minf(low.x, high.x), minf(low.y, high.y), minf(low.z, high.z), maxf(low.x, high.x), maxf(low.y, high.y), maxf(low.z, high.z)]
	print(line)
	for child in node.get_children():
		_walk(child, origin, depth + 1)
