extends SceneTree

const Apertures := preload("res://presentation/overlays/environment_camera_apertures.gd")
const Car := preload("res://art/environments/kenney/car_kit/models/sedan.glb")
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scenery := Node3D.new()
	root.add_child(scenery)
	var floor_mesh := CSGBox3D.new()
	floor_mesh.size = Vector3(20, 1, 20)
	scenery.add_child(floor_mesh)
	var wall := CSGBox3D.new()
	wall.material = StandardMaterial3D.new()
	wall.size = Vector3(3, 3, 0.4)
	wall.position = Vector3(0, 1, -4)
	scenery.add_child(wall)
	var car := Car.instantiate() as Node3D
	scenery.add_child(car)
	var car_mesh := car.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var original := car_mesh.get_active_material(0) as StandardMaterial3D
	var bounds := car_mesh.global_transform * car_mesh.get_aabb()
	var center := bounds.get_center()
	var apertures := Apertures.new()
	apertures.register_environment(scenery, floor_mesh)
	_check(car_mesh.get_active_material(0) == original, "Registration leaves imported assets untouched")
	apertures.update_view(center + Vector3(0, 0, 5), center + Vector3(0, 0, -2), 0.2)
	var adapted := car_mesh.get_active_material(0) as ShaderMaterial
	_check(apertures.active.has(car_mesh) and adapted != null, "Actual imported car participates without per-map setup (bounds %s, cull %s, transparency %s, roughness texture %s)" % [bounds, original.cull_mode, original.transparency, original.roughness_texture])
	if adapted and original:
		_check(original.albedo_texture != null and adapted.get_shader_parameter(&"surface_texture") == original.albedo_texture, "The cutout preserves the imported car's palette texture")
	_check(not apertures.active.has(floor_mesh), "The ground stays outside the aperture pass")
	apertures.update_view(Vector3(10, 1, 5), Vector3(10, 1, -5), 0.2)
	_check(car_mesh.get_active_material(0) == original, "Clearing the sightline restores the original surface resource")
	apertures.update_view(Vector3(0, 1, -8), Vector3(0, 1, -2), 0.2)
	_check(apertures.active.has(wall) and wall.material_override is ShaderMaterial, "Authored CSG walls support the same aperture")
	apertures.restore_view()
	_check(wall.material_override == null, "Clearing the camera mode restores the authored CSG material binding")
	var emissive := StandardMaterial3D.new()
	emissive.emission_enabled = true
	wall.material = emissive
	apertures.update_view(Vector3(0, 1, -8), Vector3(0, 1, -2), 0.2)
	_check(not apertures.active.has(wall) and wall.material_override == null and wall.material == emissive, "A material with unsupported features retains its rendering")
	scenery.free()

	for battlefield_id in Catalog.DEFINITIONS:
		_check_catalog_environment(battlefield_id)
	print("Environment camera apertures: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_catalog_environment(battlefield_id: StringName) -> void:
	var generated := Node3D.new()
	root.add_child(generated)
	var map := Catalog.generate(battlefield_id, Vector2i(32, 24), 17, 1.0)
	GeneratedTerrainPresenter.build(map, generated, 1.0)
	var apertures := Apertures.new()
	apertures.register_environment(generated, null)
	var verified := false
	for node in generated.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh or not mesh.is_visible_in_tree():
			continue
		var bounds := mesh.global_transform * mesh.get_aabb()
		if bounds.size.y < 0.8:
			continue
		var center := bounds.get_center()
		apertures.update_view(center + Vector3(0, 0, 5), center + Vector3(0, 0, -2), 0.2)
		verified = apertures.active.has(mesh)
		apertures.restore_view()
		if verified:
			break
	_check(verified, "%s has compatible geometry through the shared environment presenter" % battlefield_id)
	generated.free()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
