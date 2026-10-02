class_name ObjectiveZoneVisualizer
extends Node3D

@export var grid_manager: GridManager

func show_mission(mission: MissionDefinition) -> void:
	for child in get_children():
		child.queue_free()
	if mission == null or mission.objectives.is_empty():
		return
	var zone_id := StringName()
	var enemy_owned := false
	var is_extraction := false
	for objective in mission.objectives:
		if objective.kind == MissionObjectiveDefinition.Kind.EXTRACT:
			is_extraction = true
			zone_id = objective.zone_id if not objective.zone_id.is_empty() else &"extract"
			enemy_owned = objective.is_pursued_by(TacticalUnit.Faction.ENEMY)
		elif objective.kind == MissionObjectiveDefinition.Kind.REACH and zone_id.is_empty(): zone_id = &"reach"
	if zone_id.is_empty(): return
	var color := Color(1.0, 0.45, 0.1, 0.6) if enemy_owned else (Color(0.15, 0.9, 0.4, 0.55) if zone_id == &"extract" else Color(0.65, 0.2, 0.95, 0.55))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_mesh(grid_manager.map_data.get_objective_zone(zone_id))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	add_child(mesh_instance)
	if is_extraction:
		var cells := grid_manager.map_data.get_objective_zone(zone_id)
		var transport := preload("res://presentation/overlays/extraction_transport.gd").new()
		transport.name = "ExtractionTransport"
		add_child(transport)
		transport.setup(grid_manager, cells, enemy_owned, grid_manager.map_data.transport_footprints.get(zone_id, []))
		if not cells.is_empty():
			var label := Label3D.new()
			label.text = "BOARDING AREA"
			label.position = to_local(grid_manager.grid_to_world(cells[0]) + Vector3.UP * 0.3)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 32
			add_child(label)

func _build_mesh(cells: Array[Vector3i]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := grid_manager.cell_size * 0.44
	for cell in cells:
		var center := grid_manager.grid_to_world(cell) + Vector3.UP * 0.07
		var a := center + Vector3(-half, 0, -half)
		var b := center + Vector3(half, 0, -half)
		var c := center + Vector3(half, 0, half)
		var d := center + Vector3(-half, 0, half)
		surface.add_vertex(a); surface.add_vertex(b); surface.add_vertex(c)
		surface.add_vertex(a); surface.add_vertex(c); surface.add_vertex(d)
	return surface.commit()
