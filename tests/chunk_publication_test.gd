extends SceneTree
var failures := 0
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	if value: print("PASS: ",label)
	else: failures+=1; push_error(label)
func has_code(result: Dictionary, code: String) -> bool:
	return result.errors.any(func(error): return error.code == code)
func run():
	var output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	if output.is_empty(): output = "res://artifacts"
	var root := output.path_join("t07-test-" + str(Time.get_ticks_usec()))
	var library := ChunkPublicationLibrary.new(root.path_join("library"))
	var source: EnvironmentChunkSource = ChunkSourceStore.load_named("res://content/chunks/industrial","street_straight").source
	check(ChunkPublicationCompiler.compile(source).ok,"street uses full actual sidewalk/carriageway profile")
	var broken := source.copy()
	broken.data.ports[0].cells.pop_back()
	check(has_code(ChunkPublicationCompiler.compile(broken),"PORT_PROFILE_MISMATCH"),"truncated street cross section rejects")
	broken = source.copy()
	broken.data.ports[0].normal = [1,0]
	check(has_code(ChunkPublicationCompiler.compile(broken),"PORT_NOT_ON_BOUNDARY"),"wrong outward normal rejects")
	broken = source.copy()
	broken.data.tactical.effects.append({"cell":[0,0,0],"layer":1,"values":{"walkable":false}})
	check(has_code(ChunkPublicationCompiler.compile(broken),"BLOCKED_PORT"),"blocked port surface rejects")
	broken = source.copy()
	broken.data.tactical.surfaces.clear()
	check(not ChunkPublicationCompiler.compile(broken).ok,"missing ground support rejects")
	broken = source.copy()
	broken.data.instances[0].component_id = "factory_wall_straight"
	broken.data.dependencies = []
	check(has_code(ChunkPublicationCompiler.compile(broken),"INCOMPLETE_STRUCTURE"),"building fragment cannot certify itself complete")
	broken = source.copy()
	broken.data.tactical.effects.append({"cell":[5,0,5],"layer":1,"values":{"walkable":false}})
	var compiled := ChunkPublicationCompiler.compile(broken)
	check(compiled.ok and not compiled.data.get_cell(Vector3i(5,0,5)).walkable,"ground declarations do not reopen a blocking effect")
	broken.data.tactical.effects.append({"cell":[5,0,5],"layer":1,"values":{"walkable":true}})
	check(has_code(ChunkPublicationCompiler.compile(broken),"CONFLICTING_EFFECT"),"explicit conflicting effects share writer rejection")
	var raw := EnvironmentChunkSource.new("manual_prop", "Manual prop")
	raw.data.bounds = [4,4]
	raw.data.height = 4
	var raw_id := raw.add_instance(EnvironmentModulePlacement.new(&"asset:city_kit_roads/construction-cone", Vector2i(0,1)),false)
	raw.data.tactical["visual_only"] = [raw_id]
	for x in 4:
		for z in 4: raw.data.tactical.surfaces.append({"cell":[x,0,z],"values":{}})
	raw.data.ports.append({"id":"access","role":"pedestrian","profile":"walkway_2","cells":[[1,0],[2,0]],"normal":[0,-1],"elevation":0,"minimum_width":2,"connection":"required"})
	var raw_result := ChunkPublicationCompiler.compile(raw)
	check(raw_result.ok,"raw downloaded decoration with explicit role needs no new code recipe")
	if not raw_result.ok: print(raw_result.errors)
	var unsupported := raw.copy()
	unsupported.data.instances[0].elevation = 2
	check(has_code(ChunkPublicationCompiler.compile(unsupported),"UNSUPPORTED_VISUAL"),"floating decoration needs a declared support surface")
	var blocked := raw.copy()
	blocked.data.clearances.append({"id":"protected_access","cells":[[0,0,1]],"height":2,"scope":"floor"})
	check(has_code(ChunkPublicationCompiler.compile(blocked),"BLOCKED_CLEARANCE"),"visual-only declaration cannot waive access clearance")
	raw.data.tactical["visual_only"] = []
	check(has_code(ChunkPublicationCompiler.compile(raw),"UNDECLARED_TACTICAL_ROLE"),"raw visuals cannot silently acquire tactical meaning")
	var permutation := source.copy()
	permutation.data.tactical.surfaces.reverse()
	permutation.data.instances.reverse()
	var ordered_result := ChunkPublicationCompiler.compile(source)
	var permuted_result := ChunkPublicationCompiler.compile(permutation)
	check(permuted_result.ok and permuted_result.data.cells.keys()==ordered_result.data.cells.keys(),"explicit surface permutations retain deterministic cell order")
	var frontage: EnvironmentChunkSource = ChunkSourceStore.load_named("res://content/chunks/industrial","warehouse_frontage").source
	frontage.data.tactical.effects.append({"cell":[4,0,14],"layer":1,"values":{"walkable":false}})
	check(has_code(ChunkPublicationCompiler.compile(frontage),"INACCESSIBLE_ASSEMBLY"),"sealed frontage still requires reachable exterior entrance clearance")
	var a: Dictionary = source.data.ports[0].duplicate(true)
	var b: Dictionary = a.duplicate(true)
	b.normal = [0,1]
	b.cells = b.cells.map(func(cell):return [int(cell[0]),-1])
	check(ChunkPublicationCompiler.ports_match(a,b),"opposed adjacent complete ports match")
	b.cells[0][0] = 99
	check(not ChunkPublicationCompiler.ports_match(a,b),"equal labels do not waive mismatched port geometry")
	check(library.eligible().is_empty(),"draft-only content cannot be selected for generation")
	check(ChunkSourceStore.save_named(source,root,"source").ok,"save publication fixture")
	var result := library.validate_and_store(source,ChunkSourceStore.path_for(root,"source"))
	check(result.ok,"saved valid source gets immutable technical revision")
	if not result.ok: print(result); quit(1); return
	var revision: String = result.revision
	check(not library.register(revision).ok,"technical validation alone cannot register")
	check(not library.approve_by_owner(revision,"Test fixture",true).ok,"approval without review captures rejects")
	var picture := Image.create(32,32,false,Image.FORMAT_RGBA8)
	picture.fill(Color.DARK_CYAN)
	for view in ["overview","opposite","overhead"]: check(library.capture_evidence(revision,picture,view).ok,"capture test evidence: "+view)
	check(not library.approve_by_owner(revision,"",true).ok and not library.approve_by_owner(revision,"Test fixture",false).ok,"human affirmation and reviewer name are explicit gates")
	# Simulated owner input is confined to the isolated artifact library.
	check(library.approve_by_owner(revision,"AUTOMATED TEST FIXTURE ONLY",true).ok,"test-only affirmation records exact revision")
	check(library.register(revision).ok and library.eligible().size()==1,"all gates permit fixture registration")
	check(not library.capture_evidence(revision,picture,"overview").ok,"reviewed evidence cannot silently change")
	var changed := source.copy()
	changed.data.name = "Edited draft"
	ChunkSourceStore.save_named(changed,root,"source")
	check(library.eligible().is_empty(),"editing registered source removes generator eligibility")
	var new_result := library.validate_and_store(changed,ChunkSourceStore.path_for(root,"source"))
	check(new_result.ok and new_result.revision != revision and not library.register(new_result.revision).ok,"new revision never inherits human approval")
	ChunkSourceStore.save_named(source,root,"source")
	var context := EnvironmentResolutionContext.new()
	context.catalog[&"road_straight"].clearance_height += 1.0
	check(library.eligible(context).is_empty(),"changed behavior invalidates registered content")
	var calibration := EnvironmentResolutionContext.new()
	calibration.calibration_data.asset_overrides["city_kit_roads/road-straight"] = {"scale":99.0}
	check(library.eligible(calibration).is_empty(),"changed calibration invalidates registered content")
	var evidence: Dictionary = library._index().revisions[revision].evidence[0]
	var saved_image := FileAccess.get_file_as_bytes(evidence.path)
	var evidence_file := FileAccess.open(evidence.path,FileAccess.WRITE)
	evidence_file.store_string("changed capture")
	evidence_file.close()
	check(library.eligible().is_empty(),"changed evidence invalidates review eligibility")
	evidence_file = FileAccess.open(evidence.path,FileAccess.WRITE)
	evidence_file.store_buffer(saved_image)
	evidence_file.close()
	check(library.revoke_review(revision).ok and library.eligible().is_empty(),"explicit revocation removes eligibility")
	for file in DirAccess.get_files_at("res://content/chunks/industrial"):
		if not file.ends_with(".json"): continue
		var pilot := ChunkSourceStore.load_named("res://content/chunks/industrial",file)
		check(pilot.ok and ChunkPublicationCompiler.compile(pilot.source).ok,"pilot validates: "+file)
	print("Chunk publication failures: ",failures)
	quit(1 if failures else 0)
