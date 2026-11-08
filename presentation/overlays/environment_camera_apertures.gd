extends RefCounted
## Camera-only adaptation of static environment surfaces. Original materials
## stay on the scene until an eligible mesh actually crosses the aperture.

const Aperture = preload("res://presentation/overlays/tactical_camera_aperture.gd")
const CutoutShader = preload("res://presentation/overlays/tactical_camera_aperture.gdshader")

var _geometry: Array[GeometryInstance3D] = []
var _bounds: Array[AABB] = []
var _local_bounds: Array[AABB] = []
var _variants: Dictionary = {}
var _double_sided_shader: Shader
var active: Dictionary = {}

func register_environment(root: Node3D, floor_mesh: GeometryInstance3D) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if node == floor_mesh or node is TacticalCameraAperture or not (node is MeshInstance3D or node is CSGBox3D):
			continue
		if node is MeshInstance3D and node.mesh == null:
			continue
		if node is CSGBox3D and not node.is_root_shape():
			continue
		var local_bounds: AABB = AABB(-node.size * 0.5, node.size) if node is CSGBox3D else node.get_aabb()
		var bounds: AABB = node.global_transform * local_bounds
		if bounds.size.y <= 0.08:
			continue
		_geometry.append(node)
		_bounds.append(bounds.grow(Aperture.APERTURE_RADIUS))
		_local_bounds.append(local_bounds)

func cinematic_blockers(eye: Vector3, subject: Vector3, already_hidden: Dictionary, first_only := false) -> Array[GeometryInstance3D]:
	var blockers: Array[GeometryInstance3D] = []
	for index in _geometry.size():
		if _bounds[index].intersects_segment(eye, subject) == null:
			continue
		var geometry := _geometry[index]
		if not is_instance_valid(geometry) or (not geometry.is_visible_in_tree() and not already_hidden.has(geometry)):
			continue
		if _local_bounds[index].intersects_segment(geometry.to_local(eye), geometry.to_local(subject)) != null:
			blockers.append(geometry)
			if first_only:
				break
	return blockers

func update_view(eye: Vector3, subject: Vector3, delta: float) -> void:
	if not subject.is_finite():
		restore_view()
		return
	var blocking := {}
	for index in _geometry.size():
		var geometry := _geometry[index]
		if _bounds[index].intersects_segment(eye, subject) == null or not is_instance_valid(geometry) or not geometry.is_visible_in_tree():
			continue
		if not active.has(geometry) and not _begin(geometry):
			continue
		blocking[geometry] = true
		geometry.set_instance_shader_parameter(&"aperture_eye", eye)
		geometry.set_instance_shader_parameter(&"aperture_subject", subject)
	for geometry in active.keys():
		if not is_instance_valid(geometry):
			active.erase(geometry)
			continue
		var state: Dictionary = active[geometry]
		state.strength = move_toward(state.strength, 1.0 if blocking.has(geometry) else 0.0, delta / Aperture.TRANSITION_SECONDS)
		if state.strength == 0.0 and not blocking.has(geometry):
			_restore(geometry)
		else:
			geometry.set_instance_shader_parameter(&"opening", state.strength)

func restore_view() -> void:
	for geometry in active.keys():
		if is_instance_valid(geometry):
			_restore(geometry)
	active.clear()

func _begin(geometry: GeometryInstance3D) -> bool:
	var originals: Array[Material] = []
	var materials: Array[ShaderMaterial] = []
	var original := geometry.material_override
	if original or geometry is CSGBox3D:
		var source: Material = original if original else geometry.material
		var converted := _variant(source)
		if not converted:
			return false
		geometry.material_override = converted
	else:
		var mesh := geometry as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var converted := _variant(mesh.get_active_material(surface))
			if not converted:
				return false
			materials.append(converted)
			originals.append(mesh.get_surface_override_material(surface))
		for surface in materials.size():
			mesh.set_surface_override_material(surface, materials[surface])
	geometry.set_instance_shader_parameter(&"aperture_radius", Aperture.APERTURE_RADIUS)
	active[geometry] = {"material_override": original, "surfaces": originals, "strength": 0.0}
	return true

func _restore(geometry: GeometryInstance3D) -> void:
	var state: Dictionary = active[geometry]
	geometry.set_instance_shader_parameter(&"opening", 0.0)
	geometry.material_override = state.material_override
	if geometry is MeshInstance3D:
		for surface in state.surfaces.size():
			geometry.set_surface_override_material(surface, state.surfaces[surface])
	active.erase(geometry)

func _variant(source: Material) -> ShaderMaterial:
	if _variants.has(source):
		return _variants[source]
	var original := source as StandardMaterial3D
	# Keep custom, transparent and special lighting materials on their existing
	# path. The shared shader covers flat colors and the kit's opaque atlases.
	if source and (not original or original.next_pass or original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
	or original.cull_mode == BaseMaterial3D.CULL_FRONT or original.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
	or original.albedo_texture_msdf or original.uv1_triplanar or original.metallic_texture or original.roughness_texture \
	or original.no_depth_test or original.disable_receive_shadows or original.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED \
	or original.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED):
		_variants[source] = null
		return null
	if original:
		for feature in range(BaseMaterial3D.FEATURE_MAX):
			if original.get_feature(feature):
				_variants[source] = null
				return null
	var result := ShaderMaterial.new()
	result.shader = CutoutShader
	if original:
		if original.cull_mode == BaseMaterial3D.CULL_DISABLED:
			if not _double_sided_shader:
				_double_sided_shader = Shader.new()
				_double_sided_shader.code = CutoutShader.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;")
			result.shader = _double_sided_shader
		result.set_shader_parameter(&"surface_color", original.albedo_color)
		result.set_shader_parameter(&"surface_texture", original.albedo_texture)
		result.set_shader_parameter(&"surface_uv_scale", Vector2(original.uv1_scale.x, original.uv1_scale.y))
		result.set_shader_parameter(&"surface_uv_offset", Vector2(original.uv1_offset.x, original.uv1_offset.y))
		result.set_shader_parameter(&"surface_vertex_color", original.vertex_color_use_as_albedo)
		result.set_shader_parameter(&"surface_roughness", original.roughness)
		result.set_shader_parameter(&"surface_metallic", original.metallic)
		result.set_shader_parameter(&"surface_specular", original.metallic_specular)
	_variants[source] = result
	return result
