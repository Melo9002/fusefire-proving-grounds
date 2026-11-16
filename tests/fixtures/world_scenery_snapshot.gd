extends RefCounted
## Initial-scene visual evidence; capture before playback/camera effects run.
static var _meshes := {}

static func clear_cache() -> void:
	_meshes.clear()

static func capture(plot: Node) -> Dictionary:
	var records := []
	var count := 0
	for area in ["Peripheral", "Distant"]:
		var node := plot.get_node_or_null(area)
		if node == null: continue
		count += _record(node, plot, records)
	return {"hash": var_to_str(records).sha256_text(), "meshes": count}

static func _record(node: Node, plot: Node, records: Array) -> int:
	var row: Array = [String(plot.get_path_to(node)), node.get_class()]
	if node is Node3D: row.append([node.transform, node.visible])
	var count := 0
	if node is MeshInstance3D and node.mesh:
		count = 1
		if not _meshes.has(node.mesh):
			var surfaces := []
			for index in node.mesh.get_surface_count(): surfaces.append(node.mesh.surface_get_arrays(index))
			_meshes[node.mesh] = var_to_str(surfaces).sha256_text()
		row.append(_meshes[node.mesh])
		row.append(node.cast_shadow)
		row.append(node.transparency)
		row.append(_material(node.material_override))
		for surface in node.mesh.get_surface_count(): row.append(_material(node.get_active_material(surface)))
	if node is Label3D: row.append([node.text, node.font_size, node.pixel_size, node.modulate])
	records.append(row)
	for child in node.get_children(): count += _record(child, plot, records)
	return count

static func _material(material: Material) -> Array:
	if material == null: return []
	if material is StandardMaterial3D:
		return ["standard", material.albedo_color, material.albedo_texture.resource_path if material.albedo_texture else "", material.roughness, material.shading_mode, material.cull_mode]
	if material is ShaderMaterial:
		return ["shader", material.shader.code if material.shader else ""]
	return [material.get_class(), material.resource_path]
