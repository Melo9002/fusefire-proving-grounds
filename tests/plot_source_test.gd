extends SceneTree
# T09 contract: authored feasibility is not runtime composition or owner approval.
var failures := 0
var library: Dictionary
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	if value: print("PASS: ",label)
	else: failures += 1; push_error(label)
func plot(name := "through_street_industrial") -> EnvironmentPlotSource:
	return EnvironmentPlotSource.load_file("res://content/plots/"+name+".json").source
func has_code(source: EnvironmentPlotSource, code: String) -> bool:
	return PlotFeasibility.assess(source,library).errors.any(func(e): return e.code == code)
func run():
	library = PlotFeasibility.library_catalog().entries
	for name in ["through_street_industrial","yard_service_access"]:
		var source := plot(name)
		for mission in ["eliminate","terminal"]:
			source.data.active_mission = mission
			var result := PlotFeasibility.assess(source,library)
			check(result.ok,name+" / "+mission+" feasible: "+str(result.errors))
			check(result.plan.parcels.size() == source.data.slots.size() and result.plan.reservations.size() == source.data.reservations.size(),"existing plan reflects authored records")
			check(result.street_owners.size() == source.data.fixed_streets.size()*100,"street owns every bundled sidewalk cell once")
	var source := plot()
	var result := PlotFeasibility.assess(source,library)
	var slot: Dictionary = source.data.slots[2]
	var choice: Dictionary = result.candidates[slot.id][0]
	check(PlotFeasibility.extent(library[choice.chunk_id].source,choice.rotation) == Vector2i(12,10) and slot.bounds.slice(2) == [14.0,12.0],"variable slot retains actual content size without stretching")
	source.data.fixed_streets[1].origin = source.data.fixed_streets[0].origin.duplicate()
	check(has_code(source,"STREET_OWNERSHIP_CONFLICT"),"overlapping street/sidewalk owners reject")
	source = plot(); source.data.slots[0].bounds[1] = 20
	check(has_code(source,"SLOT_STREET_OVERLAP"),"slots cannot claim owned sidewalks")
	source = plot(); source.data.slots[0].bounds[2] = 2
	check(has_code(source,"IMPOSSIBLE_SLOT"),"undersized slot explains unavailable fit")
	source = plot(); source.data.slots[0].obligations[0].profile = "not_a_profile"
	check(has_code(source,"IMPOSSIBLE_SLOT"),"wrong port profile rejects")
	source = plot(); source.data.slots[0].obligations[0].target_ref = "street_5"
	check(has_code(source,"IMPOSSIBLE_SLOT"),"matching port name cannot bypass actual frontage geometry")
	source = plot(); source.data.slots[0].obligations.clear()
	check(has_code(source,"IMPOSSIBLE_SLOT"),"required local ports cannot silently disappear")
	source = plot(); source.data.fixed_streets[1].exits = ["street_0"]
	check(has_code(source,"INTERIOR_STREET_EXIT"),"interior disconnected road cannot claim a map exit")
	source = plot(); source.data.mission_requirements[0].capacity = 99
	check(has_code(source,"INSUFFICIENT_MISSION_CAPACITY"),"mission capacity counts real cells")
	source = plot(); source.data.mission_requirements[0].access_ref = "missing"
	check(has_code(source,"MISSING_MISSION_ACCESS"),"mission access loss explicit")
	source = plot(); source.data.mission_requirements = source.data.mission_requirements.filter(func(r): return r.mission != "terminal")
	check(PlotFeasibility.assess(source,library).ok,"inactive Terminal does not constrain Eliminate")
	source.data.active_mission = "terminal"
	check(has_code(source,"MISSING_TERMINAL"),"active Terminal requires objective capacity")
	source = plot(); source.data.reservations[0].cells.append([59,49])
	check(has_code(source,"DISCONNECTED_RESERVATION"),"disconnected access reservation rejects")
	var draft := EnvironmentPlotSource.new()
	var path := "res://artifacts/t09-incomplete.json"
	check(draft.save_file(path).is_empty(),"incomplete draft saves")
	var loaded := EnvironmentPlotSource.load_file(path)
	check(loaded.ok and ChunkPublicationCompiler.canonical(loaded.source.data) == ChunkPublicationCompiler.canonical(draft.data),"incomplete draft round trips")
	draft.data.schema_version = 999
	check(not EnvironmentPlotSource.source_errors(draft.data).is_empty(),"unsupported versions reject")
	draft = EnvironmentPlotSource.new(); draft.data.slots = [null]
	check(not EnvironmentPlotSource.source_errors(draft.data).is_empty(),"malformed records reject without mutation")
	# Synthetic eligibility cannot be granted merely by matching a content ID.
	var unapproved := library.duplicate(true)
	for id in unapproved: unapproved[id].eligible = false
	check(not PlotFeasibility.assess(plot(),unapproved).generation_ready,"feasible drafts remain ineligible for generation")
	# Deliberate column reservations differ from floor clearance, using shared geometry.
	var overhead_source := EnvironmentChunkSource.new()
	overhead_source.data.bounds = [4,2]
	var overhead := {"source":overhead_source,"compiled":{"resolved":[{"definition":null,"placement":EnvironmentModulePlacement.new(&"overhead",Vector2i.ZERO),"visual_bounds":AABB(Vector3(-0.4,3,-0.4),Vector3(0.8,1,0.8))}]}}
	check(PlotFeasibility.reservation_conflict(overhead,Vector2i.ZERO,0,{Vector2i.ZERO:[Vector2(0,2)]}).is_empty(),"ground-floor clearance permits overhead volume")
	check(not PlotFeasibility.reservation_conflict(overhead,Vector2i.ZERO,0,{Vector2i.ZERO:[Vector2(0,INF)]}).is_empty(),"whole-column reservation rejects overhead volume")
	check(not PlotFeasibility.reservation_conflict(overhead,Vector2i(10,10),1,{Vector2i(11,10):[Vector2(0,INF)]}).is_empty(),"rotated rectangular content queries retain volume alignment")
	print("T09 source failures: ",failures)
	quit(1 if failures else 0)
