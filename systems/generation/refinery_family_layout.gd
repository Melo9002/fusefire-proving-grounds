class_name RefineryFamilyLayout
extends RefCounted
## Bounded refinery-family proof: two authored plots and four reviewed parcels.

const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
const PlotCatalog = preload("res://systems/generation/refinery_plot_catalog.gd")
const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Compiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
const SiteA = preload("res://art/environments/authored/plots/refinery_site_a.tscn")
const SiteB = preload("res://art/environments/authored/plots/refinery_site_b.tscn")
const SOURCE_KIND := "authored_refinery_family"

static func generate(seed: int, cell_size: float = 1.0, requested: Dictionary = {}, population_enabled: bool = true) -> MapData:
	var resolved := Resolver.resolve(seed, population_enabled, requested)
	var data := FlatMapGenerator.generate(PlotCatalog.MAP_SIZE.x, PlotCatalog.MAP_SIZE.y, cell_size, seed)
	data.source_kind = SOURCE_KIND
	data.content_manifest = resolved.duplicate(true)
	data.generation_errors.assign(resolved.get("errors", []))
	if not data.generation_errors.is_empty():
		return data
	for placement: Dictionary in resolved.placements:
		var parcel = ParcelCatalog.get_definition(StringName(placement.parcel_id))
		if parcel == null or parcel.revision != int(placement.parcel_revision):
			data.generation_errors.append({"code": "STALE_PARCEL_DEPENDENCY", "detail": String(placement.parcel_id)})
			continue
		var root: Node3D = parcel.instantiate()
		root.transform = ParcelTransform.scene_transform(parcel.size, placement.origin, placement.rotation, PlotCatalog.MAP_SIZE, cell_size)
		Compiler.compile(root, data, cell_size)
		root.free()
	return data

static func present(data: MapData, parent: Node3D, cell_size: float) -> bool:
	var resolved := data.content_manifest
	if not Resolver.is_valid(resolved):
		return false
	var plot_scene: PackedScene = SiteA if StringName(resolved.plot_id) == PlotCatalog.SITE_A else SiteB if StringName(resolved.plot_id) == PlotCatalog.SITE_B else null
	if plot_scene == null:
		return false
	var plot_root := plot_scene.instantiate() as Node3D
	plot_root.scale = Vector3.ONE * cell_size
	parent.add_child(plot_root)
	_apply_industrial_atmosphere(parent)
	for placement: Dictionary in resolved.placements:
		var parcel = ParcelCatalog.get_definition(StringName(placement.parcel_id))
		if parcel == null or parcel.revision != int(placement.parcel_revision):
			return false
		var root: Node3D = parcel.instantiate()
		root.transform = ParcelTransform.scene_transform(parcel.size, placement.origin, placement.rotation, PlotCatalog.MAP_SIZE, cell_size)
		parent.add_child(root)
	return true

static func _apply_industrial_atmosphere(parent: Node3D) -> void:
	if not parent.is_inside_tree():
		return
	var world_environment := parent.get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
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
