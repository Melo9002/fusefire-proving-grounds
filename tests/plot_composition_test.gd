extends SceneTree
# The search test double changes only complete-arrangement acceptance, not publication.
class BacktrackingSearch extends AuthoredPlotComposer:
	var evaluated := 0
	func evaluate(document: BattlefieldLayoutDocument) -> Dictionary:
		evaluated += 1
		return {"ok":evaluated == 2,"errors":[],"document":document}
var failures := 0
var library: ChunkPublicationLibrary
var revisions := {}
var directory := "res://artifacts/t10-fixture-"+str(Time.get_ticks_usec())
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	if value: print("PASS: ",label)
	else: failures += 1; push_error(label)
func operation() -> EnvironmentResolutionContext:
	var context := EnvironmentResolutionContext.new(); context.chunk_library = library; return context
func source(name := "through_street_industrial") -> EnvironmentPlotSource:
	var plot: EnvironmentPlotSource = EnvironmentPlotSource.load_file("res://content/plots/"+name+".json").source
	for street in plot.data.fixed_streets: street.revision = revisions[street.chunk_id]
	return plot
func run():
	check(PlotCompositionSnapshot.leaf_identity("a/b","c") != PlotCompositionSnapshot.leaf_identity("a","b/c"),"namespaced identities cannot collide through separators")
	var fixture := preload("res://tests/fixtures/plot_test_library.gd").new()
	if not fixture.create(directory): quit(1); return
	library = fixture.library
	revisions = fixture.revisions
	GenerationJsonStore.write("res://artifacts/t10-fixture-location.json",JSON.stringify({"directory":directory,"revisions":revisions}))
	var shared_context := operation()
	var result := AuthoredPlotComposer.compose(source(),17,shared_context)
	check(result.ok,"through-street composes")
	if not result.ok: print(result); quit(1); return
	print("COMPOSED ",result.data.cells.size()," cells; ",result.data.environment_modules.size()," visuals; attempts ",result.attempts)
	check(result.repairs.is_empty(),"no mission repair")
	check(result.document.provenance.source_origin == "generated","population preserves generated-base provenance")
	check(result.document.spatial_layout.resolution_version == 2,"new snapshot cannot silently load in pre-chunk compiler")
	check(shared_context.chunk_revision_cache.size() == 4,"repeated instances reuse four required revision resolutions")
	var repeat := AuthoredPlotComposer.compose(source(),17,operation())
	check(repeat.ok and repeat.document.signature() == result.document.signature(),"same inputs reproduce accepted snapshot")
	var restored := BattlefieldLayoutDocument.from_dictionary(JSON.parse_string(result.document.to_json()))
	var recompiled := BattlefieldLayoutDocumentCompiler.compile(restored,1.0,2,operation())
	check(recompiled.ok,"accepted snapshot round trip compiles without reselection")
	var second := AuthoredPlotComposer.compose(source("yard_service_access"),42,operation())
	check(second.ok,"service-access plot composes")
	if not second.ok: print(second)
	check(second.ok and second.document.provenance.composition.choices != result.document.provenance.composition.choices,"two plots have distinct accepted arrangements")
	var exhausted := AuthoredPlotComposer.compose(source(),17,operation(),1)
	check(not exhausted.ok and exhausted.errors[0].code == "SEARCH_BUDGET_EXHAUSTED" and exhausted.attempts <= 1 and exhausted.document == null,"bounded search reports exhaustion without partial output")
	var broken := source(); broken.data.slots[0].obligations[0].target_ref = "street_5"
	check(not AuthoredPlotComposer.compose(broken,17,operation()).ok,"matching profile with wrong world geometry rejects")
	var denied := AuthoredPlotComposer.compose(source(),17,EnvironmentResolutionContext.new())
	check(not denied.ok,"production library never inherits synthetic approval")
	var permutation := source(); permutation.data.slots.reverse(); permutation.data.slots[0].rotations.reverse()
	var permuted := AuthoredPlotComposer.compose(permutation,17,operation())
	check(permuted.ok and permuted.document.provenance.composition.choices == result.document.provenance.composition.choices,"slot array order does not change selection")
	var tampered := BattlefieldLayoutDocument.from_dictionary(result.document.to_dictionary())
	tampered.provenance.composition.choices.pop_back()
	check(not BattlefieldLayoutDocumentCompiler.compile(tampered,1.0,2,operation()).ok,"missing mandatory chunk rejected on load")
	tampered = BattlefieldLayoutDocument.from_dictionary(result.document.to_dictionary())
	tampered.provenance.composition.choices[0].rotation = 3
	check(not BattlefieldLayoutDocumentCompiler.compile(tampered,1.0,2,operation()).ok,"edited accepted rotation cannot bypass connection geometry")
	tampered = BattlefieldLayoutDocument.from_dictionary(result.document.to_dictionary())
	tampered.provenance.population.rules.regions[0].bounds = [0,0,60,50]
	check(not BattlefieldLayoutDocumentCompiler.compile(tampered,1.0,2,operation()).ok,"population cannot expand beyond plot permission")
	tampered = BattlefieldLayoutDocument.from_dictionary(result.document.to_dictionary())
	tampered.provenance.erase("population")
	check(not BattlefieldLayoutDocumentCompiler.compile(tampered,1.0,2,operation()).ok,"removing population provenance cannot authorize arbitrary additions")
	tampered = BattlefieldLayoutDocument.from_dictionary(result.document.to_dictionary())
	tampered.provenance.erase("composition")
	check(not BattlefieldLayoutDocumentCompiler.compile(tampered,1.0,2,operation()).ok,"stripped composition provenance fails resolution contract")
	var stored := directory.path_join("accepted.layout.json")
	check(MapEditorLayoutStore.save(result.document,stored,operation()).is_empty(),"shared store saves composition")
	check(MapEditorLayoutStore.load({},stored,&"",operation()).ok,"shared store loads exact registered snapshot")
	var search := BacktrackingSearch.new(); search.plot = source(); search.context = operation(); search.budget = 8
	search.slots = [{"id":"fixture","required":true}]
	search.options = {"fixture":[{"chunk_id":"first"},{"chunk_id":"second"}]}
	check(search.visit(0,[]) and search.evaluated == 2 and search.attempts == 4,"bounded DFS backtracks after failed complete arrangement")
	var altered := source(); altered.data.population.regions[0].bounds = [0,0,30,40]
	check(not AuthoredPlotComposer.compose(altered,17,operation()).ok,"population permission overlapping immutable chunks rejects")
	var terminal := source("yard_service_access"); terminal.data.active_mission = "terminal"
	var terminal_result := AuthoredPlotComposer.compose(terminal,42,operation())
	check(terminal_result.ok and terminal_result.data.get_zone(&"terminal").cells.size() == 1,"active Terminal binding survives composition")
	GenerationJsonStore.write(directory.path_join("accepted.json"),result.document.to_json())
	if second.ok: GenerationJsonStore.write(directory.path_join("second.json"),second.document.to_json())
	# Stale source must invalidate new generation AND old snapshots in a fresh operation.
	var changed: EnvironmentChunkSource = ChunkSourceStore.load_named(directory,"street_straight").source
	changed.data.name += " changed"
	ChunkSourceStore.save_named(changed,directory,"street_straight")
	check(not BattlefieldLayoutDocumentCompiler.compile(restored,1.0,2,operation()).ok,"changed revision dependency rejects old snapshot")
	check(not AuthoredPlotComposer.compose(source(),17,operation()).ok,"changed revision excludes new generation")
	changed.data.name = changed.data.name.trim_suffix(" changed")
	ChunkSourceStore.save_named(changed,directory,"street_straight")
	print("T10 failures: ",failures); quit(1 if failures else 0)
