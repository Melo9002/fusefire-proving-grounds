class_name AuthoredBattlefieldLayout
extends RefCounted
## Shared current pipeline: accepted plot/parcel choices -> MapData and presentation.
const Resolver = preload("res://systems/generation2/authored_plot_resolver.gd")
const ParcelCatalog = preload("res://systems/generation2/authored_parcel_catalog.gd")
const Compiler = preload("res://systems/generation2/authored_scene_map_compiler.gd")
const DeploymentRepair = preload("res://systems/generation2/authored_deployment_repair.gd")
const SlotContract = preload("res://systems/generation2/parcel_slot_contract.gd")

static func compile_resolved(resolved: Dictionary, map_seed: int, cell_size: float, source_kind: String, extra_ally_slots: int = 0) -> MapData:
	var size: Vector2i = resolved.get("map_size", Vector2i(40, 40))
	var data := TacticalMapBuilder.generate(size.x, size.y, cell_size, int(resolved.get("seed", map_seed)), 5, extra_ally_slots)
	data.source_kind = source_kind
	data.content_manifest = resolved.duplicate(true)
	data.generation_errors.assign(resolved.get("errors", []))
	if not data.generation_errors.is_empty():
		return data
	var interfaces: Array[Dictionary] = []
	var precise_shot_bounds := int(resolved.compiler_revision) != Resolver.LEGACY_COMPILER_REVISION
	for placement: Dictionary in resolved.placements:
		var parcel = ParcelCatalog.get_definition(StringName(placement.parcel_id))
		if parcel == null or parcel.revision != int(placement.parcel_revision):
			data.generation_errors.append({"code": "STALE_PARCEL_DEPENDENCY", "detail": String(placement.parcel_id)})
			continue
		var root: Node3D = parcel.instantiate()
		var connection := ParcelConnection.from_scene(root)
		interfaces.append({
			"slot_path": "%s/%s" % [resolved.plot_id, placement.slot_id],
			"span": connection.world_span(parcel.size, placement.origin, placement.rotation),
			"outward": connection.world_outward(placement.rotation),
		})
		parcel.apply_population(root, placement.get("population", []))
		root.transform = ParcelTransform.scene_transform(parcel.size, placement.origin, placement.rotation, size, cell_size)
		Compiler.compile(root, data, cell_size, Transform3D.IDENTITY, precise_shot_bounds, int(resolved.compiler_revision))
		root.free()
	for interface in interfaces:
		var failure := SlotContract.validate_compiled_span(data, interface.slot_path, interface.span, interface.outward)
		if not failure.is_empty():
			data.generation_errors.append(failure)
	if not data.generation_errors.is_empty():
		return data
	if not DeploymentRepair.apply(data):
		data.generation_errors.append({"code": "UNSATISFIABLE_DEPLOYMENT", "detail": "No connected stopping cells remain in a required deployment column"})
	return data

static func present_resolved(data: MapData, parent: Node3D, cell_size: float, plot_scene: PackedScene, world_environment: WorldEnvironment = null) -> bool:
	var resolved := data.content_manifest
	if not data.generation_errors.is_empty() or not Resolver.is_valid(resolved):
		return false
	var plot_root := plot_scene.instantiate() as Node3D
	plot_root.scale = Vector3.ONE * cell_size
	parent.add_child(plot_root)
	_apply_industrial_atmosphere(world_environment)
	for placement: Dictionary in resolved.placements:
		var parcel = ParcelCatalog.get_definition(StringName(placement.parcel_id))
		if parcel == null or parcel.revision != int(placement.parcel_revision):
			return false
		var root: Node3D = parcel.instantiate()
		parcel.apply_population(root, placement.get("population", []))
		root.transform = ParcelTransform.scene_transform(parcel.size, placement.origin, placement.rotation, data.map_size, cell_size)
		parent.add_child(root)
	return true

static func _apply_industrial_atmosphere(world_environment: WorldEnvironment) -> void:
	# The owning battle supplies its environment; never search the scene-tree root.
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	var environment := world_environment.environment.duplicate(true) as Environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("263139")
	environment.ambient_light_color = Color("b8c2c5")
	environment.ambient_light_energy = 0.58
	environment.fog_enabled = true
	environment.fog_light_color = Color("7b8585")
	environment.fog_light_energy = 0.75
	environment.fog_density = 0.006
	environment.fog_sky_affect = 0.65
	environment.fog_height = 3.0
	environment.fog_height_density = 0.02
	world_environment.environment = environment
