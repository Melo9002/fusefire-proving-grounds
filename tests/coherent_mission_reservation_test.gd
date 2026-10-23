extends SceneTree

const ReservationLedger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")
const LayoutStore = preload("res://tools/map_editor_layout_store.gd")

var failures := 0

func _init() -> void:
	_test_reservation_contract()
	_test_generation_and_furniture_priority()
	_test_unsatisfiable_mission_space()
	_test_document_revalidation_and_persistence()
	print("Coherent mission/access reservations: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_reservation_contract() -> void:
	var data := FlatMapGenerator.generate(40, 30, 1.0, 91, 2)
	data.set_objective_zone(&"terminal", [Vector3i(20, 0, 15)])
	var ledger := ReservationLedger.from_map(data)
	check(ledger.failures.is_empty(), "valid deployment and objective zones establish early reservations")
	check(ledger.reservations.any(func(value): return value.role == ReservationLedger.DEPLOYMENT_REGION), "deployment zones receive an explicit reservation role")
	check(ledger.reservations.any(func(value): return value.role == ReservationLedger.OBJECTIVE_REGION), "objective zones receive an explicit reservation role")

	var shared := ReservationLedger.new()
	check(shared.try_reserve(_reservation("walk", "parcel:a", ReservationLedger.PEDESTRIAN_ACCESS, [Vector2i(4, 4)])), "pedestrian access may be reserved")
	check(shared.try_reserve(_reservation("service", "parcel:b", ReservationLedger.LOADING_SERVICE_APPROACH, [Vector2i(4, 4)])), "compatible functional access reservations may overlap")
	var count_before := shared.reservations.size()
	check(not shared.try_reserve(_reservation("deployment", "zone:player", ReservationLedger.DEPLOYMENT_REGION, [Vector2i(4, 4)])), "incompatible mission and loading reservations are rejected")
	check(shared.reservations.size() == count_before, "failed reservation leaves the ledger transaction unchanged")

	var bounds := Rect2i(10, 10, 10, 10)
	var span := {"start": [10, 20], "end": [20, 20], "outward_direction": [0, 1]}
	var access := ReservationLedger.frontage_access_cells(span, bounds, ReservationLedger.LOADING_SERVICE_APPROACH)
	check(access.size() == 8 and access.has(Vector2i(13, 19)) and access.has(Vector2i(13, 20)), "loading access protects a centered four-cell frontage across parcel and roadside space")

	var catalog := IndustrialModuleCatalog.create()
	var layout := EnvironmentModuleLayout.new(&"reservation_contract", 1)
	var blocked := shared.placement_allowed(catalog.construction_barrier_vault, EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(4, 4)), layout)
	check(not blocked.ok and blocked.code == "RESERVED_REGION_BLOCKED", "occupant placement cannot consume required access")
	var supported := shared.placement_allowed(catalog.paved_courtyard, EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO), layout)
	check(supported.ok, "ground support surfaces remain distinct from access reservations")

func _test_generation_and_furniture_priority() -> void:
	var data := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 2208, &"industrial_district")
	var repeated := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 2208, &"industrial_district")
	var plan: EnvironmentLayoutPlan = data.environment_layout_plan
	check(not plan.reservations.is_empty(), "coherent generation publishes mission and functional access reservations")
	check(plan.signature() == repeated.environment_layout_plan.signature(), "reservation-aware assembly remains deterministic for a fixed seed")
	check(plan.reservations.any(func(value): return value.role == ReservationLedger.DEPLOYMENT_REGION), "generated deployments are protected before parcel placement")
	check(plan.reservations.any(func(value): return value.role in [ReservationLedger.PEDESTRIAN_ACCESS, ReservationLedger.LOADING_SERVICE_APPROACH]), "selected parcel functions reserve exact frontage approaches")
	var ledger := ReservationLedger.new()
	for record in plan.reservations: check(ledger.try_reserve(record), "generated reservation %s is mutually compatible" % record.reservation_id)
	var catalog := IndustrialModuleCatalog.create()
	var helper := EnvironmentModuleLayout.new(&"furniture_check", 0)
	var furniture_ids := [&"street_light", &"utility_pole", &"traffic_signal", &"stop_sign", &"construction_barrier_vault"]
	for placement in data.environment_modules:
		if placement.component_id not in furniture_ids: continue
		var allowed := ledger.placement_allowed(catalog[placement.component_id], placement, helper)
		check(allowed.ok, "optional furniture %s does not displace required reservation space" % placement.signature())
	for zone in data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT):
		for cell in zone.cells:
			var tactical := data.get_cell(cell)
			check(tactical != null and tactical.walkable and tactical.can_stop, "reserved deployment %s remains tactically legal after compilation" % cell)

func _test_unsatisfiable_mission_space() -> void:
	var data := FlatMapGenerator.generate(40, 30, 1.0, 71, 2)
	var spawn := data.get_spawn_cells(TacticalUnit.Faction.PLAYER)[0]
	data.set_objective_zone(&"conflicting_objective", [spawn])
	var layout := CoherentEnvironmentAssembler.apply(data, 1.0, 71, &"industrial_district")
	check(layout.errors.any(func(value): return "INCOMPATIBLE_RESERVATION" in value), "unsatisfiable required mission overlap fails explicitly")
	check(data.environment_modules.is_empty(), "failed early mission reservation does not partially commit environment placements")

func _test_document_revalidation_and_persistence() -> void:
	var data := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 2208, &"industrial_district")
	var source := BattlefieldLayoutDocument.from_generated(data, "reservation_lifecycle")
	check(source.validate().is_empty(), "generated reservation document validates")
	var decoded := LayoutStore.decode(LayoutStore.encode(source), IndustrialModuleCatalog.create())
	check(decoded.ok, "reservation-bearing document survives persistence")
	if decoded.ok:
		check(JSON.parse_string(JSON.stringify(decoded.document.spatial_layout.reservations)) == JSON.parse_string(JSON.stringify(source.spatial_layout.reservations)), "save/load preserves reservation intent and cells")
		check(decoded.document.to_environment_layout_plan().reservations.size() == source.spatial_layout.reservations.size(), "document reconstruction restores reservations")

	var edited := source.editable_copy()
	var catalog := IndustrialModuleCatalog.create()
	var layout := edited.to_module_layout(catalog)
	var blocked_cell := Vector2i(-1, -1)
	for reservation in ReservationLedger.decoded_records(edited.spatial_layout.reservations):
		if reservation.role != ReservationLedger.DEPLOYMENT_REGION: continue
		for cell: Vector2i in reservation.cells:
			var candidate := _clone_layout(layout, edited.map_size(), catalog)
			if candidate.try_add(catalog.construction_barrier_vault, EnvironmentModulePlacement.new(&"construction_barrier_vault", cell), edited.map_size()):
				layout = candidate
				blocked_cell = cell
				break
		if blocked_cell != Vector2i(-1, -1): break
	check(blocked_cell != Vector2i(-1, -1), "edited-copy fixture finds a geometrically placeable deployment obstruction")
	if blocked_cell == Vector2i(-1, -1): return
	edited.apply_edited_layout(layout)
	check(edited.spatial_layout.reservations.all(func(value): return value.validation_state == "requires_revalidation"), "placement edits invalidate dependent reservation validation")
	var errors := edited.validate(catalog)
	check(errors.any(func(value): return value.code == "RESERVED_REGION_BLOCKED"), "edited obstruction is rejected during reservation revalidation")
	check(source.validate(catalog).is_empty(), "failed edited-copy revalidation cannot mutate the valid source document")

func _reservation(id: String, owner: String, role: String, cells: Array[Vector2i]) -> Dictionary:
	return {"reservation_id": id, "owner_ref": owner, "role": role, "purpose": role, "cells": cells, "required": true}

func _clone_layout(source: EnvironmentModuleLayout, map_size: Vector2i, catalog: Dictionary) -> EnvironmentModuleLayout:
	var result := EnvironmentModuleLayout.new(source.layout_id, source.generation_seed)
	for placement in source.placements:
		if not result.try_add(catalog[placement.component_id], placement, map_size): return null
	return result

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
