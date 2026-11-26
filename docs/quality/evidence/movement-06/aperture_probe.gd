extends SceneTree
## Same rendered doorway geometry with split meshes versus one mesh. Exercise
## the authoring bake, compiler, graph sweep and independent shot index.
const Bake = preload("res://tools/parcel_editor/mesh_tactical_bounds.gd")

func _initialize() -> void:
	var merged := _check_shape(true)
	var split := _check_shape(false)
	print("[Aperture] merged=", merged, " split=", split)
	quit(0 if not merged.edge and merged.shot_blocked and split.edge and not split.shot_blocked else 2)

func _check_shape(merged: bool) -> Dictionary:
	var object := Node3D.new()
	var combined := SurfaceTool.new()
	combined.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [
		[AABB(Vector3(-1.4, 0, -0.15), Vector3(0.5, 2.5, 0.3))],
		[AABB(Vector3(0.9, 0, -0.15), Vector3(0.5, 2.5, 0.3))],
		[AABB(Vector3(-0.9, 2.2, -0.15), Vector3(1.8, 0.3, 0.3))],
	]:
		var bounds: AABB = part[0]
		var mesh := BoxMesh.new()
		mesh.size = bounds.size
		if merged:
			combined.append_from(mesh, 0, Transform3D(Basis.IDENTITY, bounds.get_center()))
		else:
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.position = bounds.get_center()
			object.add_child(instance)
	if merged:
		var instance := MeshInstance3D.new()
		instance.mesh = combined.commit()
		object.add_child(instance)
	var parts := Bake.add_to(object)
	var map := TacticalMapBuilder.generate(9, 9, 1.0, 16)
	map.surface_placement_enabled = true
	AuthoredSceneMapCompiler.compile(object, map, 1.0)
	SurfaceNavigation.resolve_map(map, 1.0)
	var grid := GridManager.new()
	grid.map_data = map
	var start := Vector3(0, 0, -1.0)
	var finish := Vector3(0, 0, 1.0)
	var result := {
		"parts": parts, "center_can_stop": map.get_cell(Vector3i(4, 0, 4)).can_stop,
		"edge": SurfaceNavigation.edge_clear(map, start, finish),
		"shot_blocked": CombatRules.get_blocking_cell(start + Vector3.UP, finish + Vector3.UP, grid) != null,
	}
	grid.free()
	object.free()
	return result
