extends SceneTree

const Plots = preload("res://systems/generation/refinery_plot_catalog.gd")
const Parcels = preload("res://systems/generation/authored_parcel_catalog.gd")
const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
const Recording = preload("res://systems/replay/battle_replay_recording.gd")
var failures := 0

class ReorderedPlots:
	static func choose(map_seed: int) -> Dictionary:
		return get_definition(Plots.choose(map_seed).plot_id)

	static func get_definition(id: StringName) -> Dictionary:
		var plot := Plots.get_definition(id)
		plot.slots.reverse()
		return plot

class PopulationFixture:
	var parcel_id: StringName
	var regions: Array
	var sockets: Array[Dictionary]

	func population_regions() -> Array:
		return regions.duplicate()

	func population_sockets() -> Array[Dictionary]:
		return sockets.duplicate()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for map_seed in [16, 17, 18, 19]:
		var original := Resolver.resolve(map_seed)
		var reversed := Resolver.resolve(map_seed, true, {}, ReorderedPlots)
		_check(Resolver.is_valid(original) and Resolver.is_valid(reversed), "Both orders resolve seed %d" % map_seed)
		_check(original.placements.front().slot_id != reversed.placements.front().slot_id, "Fixture actually changes slot ordering")
		_check(_by_slot(original.placements) == _by_slot(reversed.placements), "Reordering slots keeps each slot's exact choices for seed %d" % map_seed)
		var reconstructed := Resolver.resolve(999, true, original, ReorderedPlots)
		_check(reconstructed == original, "Replay retains original seed, placements, population and compile order")

	var parcel = Parcels.get_definition(Parcels.PARKING_GARAGE_A)
	var fixture := PopulationFixture.new()
	fixture.parcel_id = parcel.parcel_id
	fixture.regions = parcel.population_regions()
	fixture.sockets = parcel.population_sockets()
	var baseline := Resolver._resolve_population(fixture, 17, {}, true, "service_garage/garage")
	fixture.regions.reverse()
	fixture.sockets.reverse()
	_check(Resolver._resolve_population(fixture, 17, {}, true, "service_garage/garage") == baseline, "Reordering real garage regions and bays preserves choices and serialization order")
	var removed = fixture.regions.pop_front()
	fixture.sockets = fixture.sockets.filter(func(socket): return socket.region_id != removed.region_id)
	var smaller := Resolver._resolve_population(fixture, 17, {}, true, "service_garage/garage")
	var unaffected: Array = baseline.choices.filter(func(choice): return choice.region_id != removed.region_id)
	_check(smaller.choices == unaffected, "Removing an unrelated region preserves count, selected sockets and headings in the remaining regions")

	var manifest := Resolver.resolve(16)
	manifest.erase("compiler_revision")
	manifest.placements.reverse()
	var legacy := Resolver.resolve(999, true, _json_round_trip(manifest))
	_check(Resolver.is_valid(legacy) and legacy.compiler_revision == Resolver.COMPILER_REVISION and legacy.placements == manifest.placements, "Unversioned exact recordings use the baseline compiler and retain recorded choices")
	for revision in [99, 1.5, "1"]:
		manifest.compiler_revision = revision
		var rejected := Resolver.resolve(16, true, _json_round_trip(manifest))
		_check(not Resolver.is_valid(rejected) and rejected.errors[0].code == "UNSUPPORTED_COMPILER_REVISION", "Recorded compiler revision %s rejects explicitly" % str(revision))
	print("Parcel population streams: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _json_round_trip(manifest: Dictionary) -> Dictionary:
	var recording := Recording.new()
	recording.configuration = {"content_manifest": manifest}
	return Recording.from_dictionary(JSON.parse_string(JSON.stringify(recording.to_dictionary()))).configuration.content_manifest

func _by_slot(placements: Array) -> Dictionary:
	var result := {}
	for placement: Dictionary in placements:
		result[placement.slot_id] = placement
	return result

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
