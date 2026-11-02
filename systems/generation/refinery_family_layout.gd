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
	for placement: Dictionary in resolved.placements:
		var parcel = ParcelCatalog.get_definition(StringName(placement.parcel_id))
		if parcel == null or parcel.revision != int(placement.parcel_revision):
			return false
		var root: Node3D = parcel.instantiate()
		root.transform = ParcelTransform.scene_transform(parcel.size, placement.origin, placement.rotation, PlotCatalog.MAP_SIZE, cell_size)
		parent.add_child(root)
	return true
