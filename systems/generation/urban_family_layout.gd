class_name UrbanFamilyLayout
extends RefCounted
## Urban content uses the same bounded resolver, tactical compiler and presenter
## as the refinery proof. Exact accepted choices own reconstruction.

const Catalog = preload("res://systems/generation/urban_plot_catalog.gd")
const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
const SharedLayout = preload("res://systems/generation/refinery_family_layout.gd")
const SOURCE_KIND := "authored_urban_family"

static func resolve(seed: int, population_enabled: bool = true, requested: Dictionary = {}) -> Dictionary:
	return Resolver.resolve(seed, population_enabled, requested, Catalog)

static func generate(seed: int, cell_size: float = 1.0, requested: Dictionary = {}, population_enabled: bool = true) -> MapData:
	return SharedLayout.compile_resolved(resolve(seed, population_enabled, requested), seed, cell_size, SOURCE_KIND)

static func present(data: MapData, parent: Node3D, cell_size: float) -> bool:
	var manifest := data.content_manifest
	var checked := resolve(int(manifest.get("seed", 0)), bool(manifest.get("population_enabled", true)), manifest)
	if not Resolver.is_valid(checked) or checked.placements != manifest.get("placements", []):
		return false
	var plot := Catalog.definition(StringName(manifest.get("plot_id", &"")))
	return not plot.is_empty() and SharedLayout.present_resolved(data, parent, cell_size, plot.scene)
