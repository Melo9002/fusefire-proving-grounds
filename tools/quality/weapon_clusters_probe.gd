extends SceneTree
## Finds the parts that hang below the weapon's body (magazine, pistol grip, trigger guard, front
## handle) by clustering the mesh vertices below a height along the barrel axis.
##   godot_console --headless --path . --script res://tools/quality/weapon_clusters_probe.gd
const BELOW_Y := -0.03
const GAP := 0.012

func _initialize() -> void:
	var probe := (load("res://art/weapons/aug/models/aug_runtime_socketed.glb") as PackedScene).instantiate() as Node3D
	root.add_child(probe)
	var mesh_node := probe.find_child("AUG_Runtime", true, false) as MeshInstance3D
	var to_weapon := probe.global_transform.affine_inverse() * mesh_node.global_transform
	var points: Array[Vector3] = []
	for surface in mesh_node.mesh.get_surface_count():
		for vertex: Vector3 in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point := to_weapon * vertex
			if point.y < BELOW_Y:
				points.append(point)
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	var clusters: Array = []
	var current: Array[Vector3] = []
	for point in points:
		if not current.is_empty() and point.z - current[-1].z > GAP:
			clusters.append(current)
			current = []
		current.append(point)
	if not current.is_empty():
		clusters.append(current)
	for cluster: Array in clusters:
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		for p: Vector3 in cluster:
			low = low.min(p)
			high = high.max(p)
		print("CLUSTER z %.3f..%.3f  y %.3f..%.3f  x %.3f..%.3f  (%d vertices)" % [low.z, high.z, low.y, high.y, low.x, high.x, cluster.size()])
	quit(0)
