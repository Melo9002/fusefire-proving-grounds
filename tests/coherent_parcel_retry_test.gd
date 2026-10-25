extends SceneTree

const Search = preload("res://systems/generation/environment_parcel_candidate_search.gd")
const ReservationLedger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")

const CASES := [
	[&"industrial_district", 17],
	[&"industrial_district", 2208],
	[&"commercial_street", 7319],
	[&"commercial_street", 2208],
	[&"mixed_service", 11027],
	[&"mixed_service", 2208],
]

var failures := 0
var catalog := IndustrialModuleCatalog.create()

func _init() -> void:
	_test_candidate_enumeration_and_budget()
	_test_transactional_rejection()
	_test_seed_matrix()
	_test_editor_size_matrix()
	print("Coherent bounded parcel retries: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_candidate_enumeration_and_budget() -> void:
	var parcel := _two_frontage_parcel()
	var templates: Array[StringName] = [
		&"building_frontage/industrial_shell_i",
		&"building_frontage/industrial_shell_j",
		&"building_frontage/industrial_shell_k",
		&"building_frontage/industrial_shell_n",
		&"building_frontage/industrial_shell_o",
		&"building_frontage/industrial_shell_p",
	]
	var first := Search.specifications(parcel, templates, catalog)
	var repeated := Search.specifications(parcel, templates, catalog)
	check(_spec_signature(first) == _spec_signature(repeated), "candidate ordering is deterministic")
	check(first.size() > Search.MAX_CANDIDATE_ATTEMPTS_PER_PARCEL, "fixture exposes more supported local choices than the fixed parcel budget")
	check(first.slice(0, templates.size()).all(func(spec): return spec.frontage_id == "frontage_a" and spec.tangent_offset == 0), "each compatible template receives its primary frontage before refinements")
	check(first.any(func(spec): return spec.frontage_id == "frontage_b"), "disconnected supported frontage spans are explored independently")
	check(first.any(func(spec): return absi(int(spec.tangent_offset)) == 1), "complete shells expose only their bounded one-cell authored offsets")
	check(Search.budget_exhausted(first.size(), Search.MAX_CANDIDATE_ATTEMPTS_PER_PARCEL, false), "unresolved work beyond twelve attempts reports explicit budget exhaustion")
	check(not Search.budget_exhausted(first.size(), 1, true), "an accepted candidate never reports budget exhaustion")
	check(Search.candidate_seed(17, "parcel", first[0]) == Search.candidate_seed(17, "parcel", first[0]), "candidate-local variation seeds reproduce exactly")
	check(Search.candidate_seed(17, "parcel", first[0]) != Search.candidate_seed(17, "parcel", first[1]), "different candidate identities receive independent deterministic variation streams")

func _test_transactional_rejection() -> void:
	var parcel := _two_frontage_parcel()
	var specification := Search.specifications(parcel, [&"building_frontage/industrial_shell_i"], catalog)[0].duplicate(true)
	specification.rotation = 2 # Deliberately turn the visible entrance away from the selected street.
	var source := EnvironmentModuleLayout.new(&"transaction_source", 17)
	var reservations := ReservationLedger.new()
	var result := CoherentEnvironmentAssembler._evaluate_candidate(source, reservations, parcel, specification, catalog, Vector2i(40, 40), 17)
	check(not result.ok and result.code == "INVALID_FRONTAGE_ORIENTATION", "an essential frontage failure rejects the candidate with its actionable cause")
	check(source.placements.is_empty() and source.errors.is_empty(), "a rejected candidate leaves the accepted layout unchanged")
	check(reservations.reservations.is_empty() and reservations.failures.is_empty(), "a rejected candidate leaves no orphaned reservation")

func _test_seed_matrix() -> void:
	for item in CASES:
		var environment_id: StringName = item[0]
		var map_seed: int = item[1]
		var started := Time.get_ticks_usec()
		var first := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, map_seed, environment_id)
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var repeated := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, map_seed, environment_id)
		var plan: EnvironmentLayoutPlan = first.environment_layout_plan
		var repeated_plan: EnvironmentLayoutPlan = repeated.environment_layout_plan
		var label := "%s seed %d" % [environment_id, map_seed]
		check(plan.signature() == repeated_plan.signature() and _placement_signature(first) == _placement_signature(repeated), "%s reproduces placements and search outcomes" % label)
		check(plan.parcel_search_reports.size() == plan.parcels.size(), "%s reports one bounded search outcome per parcel" % label)
		check(plan.parcel_search_reports.all(func(report): return int(report.attempts) > 0 and int(report.attempts) <= Search.MAX_CANDIDATE_ATTEMPTS_PER_PARCEL), "%s stays inside the per-parcel attempt budget" % label)
		check(plan.relationship_failures.is_empty(), "%s accepts no parcel with a failed functional relationship" % label)
		check(plan.parcels.all(func(parcel): return parcel.template == &"district_buffer" or not str(parcel.get("selected_frontage_id", "")).is_empty()), "%s records the chosen exact frontage for every functional parcel" % label)
		check(plan.parcels.filter(func(parcel): return parcel.template == &"district_buffer").all(func(parcel): return parcel.occupants.is_empty()), "%s keeps intentional or fallback buffers explicitly empty" % label)
		var summary := plan.generation_summary()
		check(int(summary.candidate_attempts) == plan.search_attempts and int(summary.candidate_rejections) == plan.candidate_rejections.size(), "%s summary matches structured candidate diagnostics" % label)
		check(_tactical_errors(first).is_empty(), "%s retains authoritative tactical and deployment validity" % label)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(first, graph)
		var quality := MapQualityEvaluator.evaluate(first, graph)
		check(is_finite(quality.overall_score) and quality.overall_score >= 0.0 and quality.overall_score <= 100.0 and quality.player_route_options > 0.0 and quality.enemy_route_options > 0.0, "%s retains bounded tactical quality metrics and routes" % label)
		var document := BattlefieldLayoutDocument.from_generated(first, "bounded_%s_%d" % [environment_id, map_seed])
		check(document.validate(catalog).is_empty(), "%s produces a valid unified layout document" % label)
		var reconstructed := document.to_environment_layout_plan()
		check(_selected_frontage_signature(plan) == _selected_frontage_signature(reconstructed), "%s preserves selected frontage and offsets through document reconstruction" % label)
		var compiled := BattlefieldLayoutDocumentCompiler.compile(document)
		check(compiled.ok, "%s reconstructs tactical MapData from the same document: %s" % [label, compiled.errors])
		print("[ParcelSearch] %s | %.2f ms | %s | quality %.1f" % [label, elapsed_ms, JSON.stringify(summary), quality.overall_score])
		if environment_id == &"commercial_street" and map_seed == 7319:
			var reviewed: Dictionary = plan.parcels.filter(func(parcel): return parcel.id == &"parcel_00")[0]
			var report: Dictionary = plan.parcel_search_reports.filter(func(value): return value.parcel_id == "parcel_00")[0]
			check(reviewed.template != &"district_buffer" and reviewed.selected_frontage_id == "parcel_00_frontage_01", "commercial seed 7319 recovers the previously empty parcel through its second supported frontage")
			check(int(report.attempts) > 1 and plan.candidate_rejections.any(func(value): return value.parcel_id == "parcel_00"), "commercial seed 7319 retains the rejected alternatives that led to recovery")

func _test_editor_size_matrix() -> void:
	for item in [[&"industrial_district", 17], [&"commercial_street", 7319], [&"mixed_service", 11027]]:
		var data := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, item[1], item[0])
		var plan: EnvironmentLayoutPlan = data.environment_layout_plan
		var label := "editor 60x50 %s seed %d" % [item[0], item[1]]
		check(plan.relationship_failures.is_empty() and _tactical_errors(data).is_empty(), "%s remains functionally and tactically valid" % label)
		check(plan.parcel_search_reports.all(func(report): return int(report.attempts) <= Search.MAX_CANDIDATE_ATTEMPTS_PER_PARCEL), "%s retains bounded per-parcel work" % label)
		check(BattlefieldLayoutDocument.from_generated(data, "editor_matrix").validate(catalog).is_empty(), "%s produces a valid reconstructable document" % label)
		var fallbacks: Array = plan.parcels.filter(func(parcel): return not str(parcel.get("fallback_reason", "")).is_empty())
		if item[0] == &"commercial_street":
			check(fallbacks.size() == 1 and fallbacks[0].fallback_reason == "PROVEN_INCOMPATIBLE_WITHIN_SUPPORTED_CHOICES", "%s records the deployment-protected parcel as an explicit proven incompatibility" % label)
			var fallback_id := String(fallbacks[0].id) if fallbacks.size() == 1 else ""
			check(not fallback_id.is_empty() and plan.candidate_rejections.filter(func(value): return value.parcel_id == fallback_id).all(func(value): return value.code == "RESERVED_REGION_BLOCKED"), "%s retains the mission-reservation cause for every rejected supported alternative" % label)
		else:
			check(fallbacks.is_empty(), "%s requires no invalid-content fallback" % label)

func _two_frontage_parcel() -> Dictionary:
	return {
		"id": &"parcel_retry_fixture",
		"bounds": Rect2i(10, 10, 20, 20),
		"frontage_spans": [
			{"frontage_id": "frontage_a", "outward_direction": [0, 1], "start": [10, 30], "end": [30, 30], "width_cells": 20, "clearance_depth_cells": 1, "road_refs": ["road_a"]},
			{"frontage_id": "frontage_b", "outward_direction": [1, 0], "start": [30, 10], "end": [30, 30], "width_cells": 20, "clearance_depth_cells": 1, "road_refs": ["road_b"]},
		],
	}

func _spec_signature(specifications: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for spec in specifications:
		parts.append("%s:%s:%d:%d" % [spec.template_id, spec.frontage_id, spec.rotation, spec.tangent_offset])
	return "|".join(parts)

func _placement_signature(data: MapData) -> String:
	var parts: Array[String] = []
	for placement: EnvironmentModulePlacement in data.environment_modules: parts.append(placement.signature())
	return "|".join(parts)

func _selected_frontage_signature(plan: EnvironmentLayoutPlan) -> String:
	var parts: Array[String] = []
	for parcel in plan.parcels:
		parts.append("%s:%s:%d" % [parcel.id, parcel.get("selected_frontage_id", ""), int(parcel.get("placement_offset", 0))])
	parts.sort()
	return "|".join(parts)

func _tactical_errors(data: MapData) -> Array:
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	return MapValidator.validate(data, graph, {MapZoneData.Kind.DEPLOYMENT: 5}).errors

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
