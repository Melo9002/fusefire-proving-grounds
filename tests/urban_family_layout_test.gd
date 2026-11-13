extends SceneTree

const Layout = preload("res://systems/generation/urban_family_layout.gd")
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
const Recording = preload("res://systems/replay/battle_replay_recording.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for seed in [16, 17, 18, 19, 20, 21]:
		var data := Catalog.generate(Catalog.URBAN_FAMILY, Vector2i.ONE, seed, 1.0)
		check(data.generation_errors.is_empty(), "seed %d resolves urban content: %s" % [seed, data.generation_errors])
		check(data.source_kind == Layout.SOURCE_KIND, "urban identity survives compilation")
		var manifest := data.content_manifest
		check(manifest == Layout.resolve(seed), "same seed reproduces exact accepted choices")
		for placement: Dictionary in manifest.placements:
			var sockets: Array = placement.population.map(func(choice): return choice.socket_id)
			var unique := {}
			for socket in sockets: unique[socket] = true
			check(unique.size() == sockets.size(), "population never repeats a socket")
		var recording := Recording.new()
		recording.configuration = {"battlefield_id": Catalog.URBAN_FAMILY, "content_manifest": manifest}
		var restored := Recording.from_dictionary(recording.to_dictionary())
		var reconstructed := Layout.generate(999, 1.0, restored.configuration.content_manifest)
		check(reconstructed.generation_errors.is_empty() and reconstructed.content_manifest.placements == manifest.placements, "recorded choices survive JSON and override a different generation seed")
		check(reconstructed.content_manifest.seed == seed, "reconstruction retains original generation provenance")
		check(data.cells.size() == reconstructed.cells.size(), "reconstruction retains ground and elevated cell counts")
		var tactical_equal := true
		for position in data.cells:
			var first: MapCellData = data.cells[position]
			var second: MapCellData = reconstructed.get_cell(position)
			if second == null or first.walkable != second.walkable or first.can_stop != second.can_stop or first.cover_height != second.cover_height or first.blocks_line_of_sight != second.blocks_line_of_sight:
				tactical_equal = false
		check(tactical_equal, "reconstruction retains authored traversal, stopping, cover and LOS cells")
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		check(MapValidator.validate(data, graph).is_valid(), "seed %d produces valid tactical data" % seed)
		var parent := Node3D.new()
		check(Catalog.present_special(data, parent, 1.0), "seed %d presents through shared catalog" % seed)
		check(parent.get_child_count() == manifest.placements.size() + 1, "presentation includes exact plot and parcel count")
		parent.free()
		var off := Layout.generate(seed, 1.0, {}, false)
		check(off.generation_errors.is_empty() and off.content_manifest.placements.all(func(p): return p.population.is_empty()), "population-off retains all required parcels")
		for mutation in ["revision", "transform", "missing", "population"]:
			var broken: Dictionary = manifest.duplicate(true)
			match mutation:
				"revision": broken.plot_revision = 999
				"transform": broken.placements[0].rotation = 3
				"missing": broken.placements.pop_back()
				"population": broken.placements[-1].population = [{"socket_id": &"missing"}]
			check(not Layout.generate(seed, 1.0, broken).generation_errors.is_empty(), "invalid recorded %s fails explicitly" % mutation)
	print("Urban family layout: %d failure(s)" % failures)
	quit(1 if failures else 0)
