extends SceneTree

const Layout = preload("res://systems/generation/refinery_family_layout.gd")
const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
const ReplayRecording = preload("res://systems/replay/battle_replay_recording.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for seed in range(4):
		var data := Layout.generate(seed)
		check(data.generation_errors.is_empty(), "seed %d compiles without construction errors: %s" % [seed, data.generation_errors])
		check(data.source_kind == Layout.SOURCE_KIND and data.map_size == Vector2i(64, 64), "seed %d owns stable map identity and size" % seed)
		check(data.content_manifest == Resolver.resolve(seed), "seed %d stores exact resolved content manifest" % seed)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		var validation := MapValidator.validate(data, graph)
		check(validation.is_valid(), "seed %d compiles valid tactical MapData: %s" % [seed, validation.describe()])
		var parent := Node3D.new()
		check(Layout.present(data, parent, 1.0), "seed %d presents from its exact manifest" % seed)
		check(parent.get_child_count() == 4, "seed %d presents one plot and three parcels" % seed)
		var plot_root := parent.get_child(0) as Node3D
		check(int(plot_root.get_meta("revision", 0)) == int(data.content_manifest.plot_revision), "seed %d presents the exact plot revision" % seed)
		var road := plot_root.get_node_or_null("RoadAndNearPeriphery")
		check(road != null and String(road.get_meta("asset_id", "")) == "city_kit_roads/road-straight", "seed %d uses the calibrated imported road assembly" % seed)
		var road_bounds := Placement.mesh_bounds(road)
		check(road_bounds.position.y > 0.001, "seed %d imported asphalt base renders above the authoritative MapFloor top" % seed)
		check(road_bounds.position.x < -32.0 or road_bounds.end.x > 32.0 or road_bounds.position.z < -32.0 or road_bounds.end.z > 32.0, "seed %d road continues visually beyond the 64x64 tactical boundary" % seed)
		check(plot_root.get_node("FarBackdrop").get_child_count() == 0, "seed %d has no placeholder floating backdrop blocks" % seed)
		parent.free()
	var exact := Resolver.resolve(3)
	var replay := Layout.generate(999, 1.0, exact)
	check(replay.generation_errors.is_empty() and replay.content_manifest.plot_id == exact.plot_id, "requested manifest reconstructs exact plot despite different seed")
	check(replay.content_manifest.placements == exact.placements, "requested manifest reconstructs exact parcel choices")
	var recording := ReplayRecording.new()
	recording.configuration = {"battlefield_id": &"refinery_family", "map_size": Vector2i(64, 64), "content_manifest": exact}
	var restored_recording := ReplayRecording.from_dictionary(recording.to_dictionary())
	check(restored_recording.configuration.content_manifest == exact, "replay JSON contract round-trips exact resolved choices and transforms")
	var empty := Layout.generate(17, 1.0, {}, false)
	check(empty.generation_errors.is_empty() and empty.content_manifest.placements.is_empty(), "population-off compiles plot ground without parcels")
	var stale := exact.duplicate(true)
	stale.plot_revision = 99
	var rejected := Layout.generate(3, 1.0, stale)
	check(not rejected.generation_errors.is_empty(), "stale requested content returns fatal construction diagnostics")
	var rejected_parent := Node3D.new()
	check(not Layout.present(rejected, rejected_parent, 1.0), "invalid content is not partially presented")
	rejected_parent.free()
	print("Refinery family layout: %d failure(s)" % failures)
	quit(1 if failures else 0)
