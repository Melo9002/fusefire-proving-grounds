extends SceneTree

const PlotCatalog = preload("res://systems/generation/refinery_plot_catalog.gd")
const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var seen_plots := {}
	var seen_loading := {}
	var seen_container_counts := {}
	for seed in range(8):
		var resolved := Resolver.resolve(seed)
		check(Resolver.is_valid(resolved), "seed %d resolves cleanly: %s" % [seed, resolved.get("errors", [])])
		check(resolved.placements.size() == 3, "seed %d resolves all three required parcels" % seed)
		seen_plots[resolved.plot_id] = true
		for placement: Dictionary in resolved.placements:
			if placement.slot_id == &"loading":
				seen_loading[placement.parcel_id] = true
				var container_count: int = placement.population.filter(func(choice): return choice.region_id == &"depot_containers").size()
				seen_container_counts[container_count] = true
				check(placement.population.any(func(choice): return choice.region_id == &"loading_vehicles"), "seed %d resolves an authored loading vehicle socket" % seed)
		check(resolved == Resolver.resolve(seed), "seed %d resolution is deterministic" % seed)
	check(seen_plots.size() == 2, "seed matrix exercises both authored plot layouts")
	check(seen_loading.size() == 2, "seed matrix exercises both loading-yard variants")
	check(seen_container_counts.has(1) and seen_container_counts.has(2), "seed matrix exercises bounded one- and two-container populations")
	var empty := Resolver.resolve(17, false)
	check(Resolver.is_valid(empty) and empty.placements.is_empty(), "population-off preserves the plot without movable parcels")
	check(empty.plot_id == PlotCatalog.SITE_B, "population-off retains deterministic plot identity")
	var exact := Resolver.resolve(6)
	var replayed := Resolver.resolve(999, true, exact)
	check(Resolver.is_valid(replayed), "stored exact choices reconstruct independently of seed selection")
	check(replayed.plot_id == exact.plot_id and replayed.placements == exact.placements, "exact reconstruction preserves placements")
	var stale := exact.duplicate(true)
	stale.plot_revision = 999
	var stale_result := Resolver.resolve(6, true, stale)
	check(not Resolver.is_valid(stale_result) and stale_result.errors[0].code == "STALE_PLOT_REVISION", "stale plot revision fails explicitly")
	var missing := exact.duplicate(true)
	missing.placements[0].parcel_id = &"missing_parcel"
	check(not Resolver.is_valid(Resolver.resolve(6, true, missing)), "missing exact parcel fails without substitution")
	var invalid_population := exact.duplicate(true)
	for placement: Dictionary in invalid_population.placements:
		if placement.slot_id == &"loading": placement.population[0].socket_id = &"unknown_socket"
	check(not Resolver.is_valid(Resolver.resolve(6, true, invalid_population)), "invalid recorded population socket fails without substitution")
	for plot: Dictionary in PlotCatalog.all(): _check_plot_geometry(plot)
	print("Refinery plot resolver: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_plot_geometry(plot: Dictionary) -> void:
	var occupied := {}
	for slot: Dictionary in plot.slots:
		var rotated := ParcelTransform.rotated_size(slot.size, slot.rotation)
		check(slot.origin.x >= 0 and slot.origin.z >= 0 and slot.origin.x + rotated.x <= plot.map_size.x and slot.origin.z + rotated.y <= plot.map_size.y, "%s/%s stays inside bounds" % [plot.plot_id, slot.slot_id])
		for x in range(slot.origin.x, slot.origin.x + rotated.x):
			for z in range(slot.origin.z, slot.origin.z + rotated.y):
				var key := Vector2i(x, z)
				check(not occupied.has(key), "%s has no overlapping slots at %s" % [plot.plot_id, key])
				for road_rect: Rect2i in plot.road_rects:
					check(not road_rect.has_point(key), "%s/%s does not overlap reserved road cell %s" % [plot.plot_id, slot.slot_id, key])
				occupied[key] = slot.slot_id
		var candidates := ParcelCatalog.candidates(slot.role, slot.size)
		check(not candidates.is_empty(), "%s/%s has registered content" % [plot.plot_id, slot.slot_id])
		for parcel in candidates:
			var connection = parcel.connection()
			check(connection.world_cell(parcel.size, slot.origin, slot.rotation) == slot.required_interface.cell, "%s/%s interface cell matches %s" % [plot.plot_id, slot.slot_id, parcel.parcel_id])
			check(connection.world_outward(slot.rotation) == slot.required_interface.outward, "%s/%s interface direction matches %s" % [plot.plot_id, slot.slot_id, parcel.parcel_id])
