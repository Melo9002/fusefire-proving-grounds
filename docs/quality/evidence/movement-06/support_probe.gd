extends SceneTree
## Audit reproduction for a safe alternative in a rejected tile. Exit 2 if the
## fixture cannot establish its controls. Prints the current solver outcome.

func _initialize() -> void:
	var rejected := _resolve(false)
	var control := _resolve(true)
	print("[Support] missing_east=", rejected, " full_floor=", control)
	var valid_fixture: bool = rejected.fit_clears and not rejected.fit_supported and rejected.alternate_clears and rejected.alternate_supported and rejected.alternate_edge and control.can_stop
	quit(0 if valid_fixture else 2)

func _resolve(east_support: bool) -> Dictionary:
	var data := TacticalMapBuilder.generate(7, 7, 1.0, 16)
	data.surface_placement_enabled = true
	var tile := data.get_cell(Vector3i(3, 0, 3))
	data.get_cell(Vector3i(4, 0, 3)).support_surface = east_support
	var obstacle := AABB(Vector3(-0.45, 0, -0.10), Vector3(0.46, 1.8, 0.2))
	data.movement_parts.append(obstacle)
	var fit := SurfacePlacement.resolve(tile.support_center, [obstacle], 0.28, 1.8, 0.04, 1.0, Vector3.INF, true)
	var point: Vector3 = fit.position
	point = (point * 10000.0).round() / 10000.0
	SurfaceNavigation.resolve_map(data, 1.0)
	var alternate := tile.support_center + Vector3(0, 0, 0.43)
	var approach := data.get_cell(Vector3i(3, 0, 4)).world_position
	return {
		"fit": point, "fit_clears": SurfaceNavigation.body_clear(data, point),
		"fit_supported": SurfaceNavigation.supported(data, point, data.body_radius),
		"alternate": alternate, "alternate_clears": SurfaceNavigation.body_clear(data, alternate),
		"alternate_supported": SurfaceNavigation.supported(data, alternate, data.body_radius),
		"approach": approach, "alternate_edge": SurfaceNavigation.edge_clear(data, approach, alternate),
		"can_stop": tile.can_stop,
	}
