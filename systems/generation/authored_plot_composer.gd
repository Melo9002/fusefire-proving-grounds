class_name AuthoredPlotComposer
extends RefCounted
## Bounded deterministic search over data-backed slots. Legacy recipe dispatch is not used.
const VERSION := 1
const MAX_ATTEMPTS := 128
var plot: EnvironmentPlotSource
var context: EnvironmentResolutionContext
var generation_seed: int
var budget: int
var attempts := 0
var diagnostics: Array = []
var slots: Array = []
var fixed: Array = []
var options := {}
var last_result := {}
static func compose(source: EnvironmentPlotSource, seed_value: int, operation: EnvironmentResolutionContext = null, attempt_budget := 64) -> Dictionary:
	var search := AuthoredPlotComposer.new()
	search.plot = source.copy(); search.context = operation if operation != null else EnvironmentResolutionContext.new()
	search.generation_seed = seed_value; search.budget = clampi(attempt_budget,0,MAX_ATTEMPTS)
	return search.run()
func fail(message: String, code: String) -> Dictionary:
	var result := TacticalPopulationPass.fail(message,code)
	result["attempts"] = attempts; result["diagnostics"] = diagnostics
	return result
func run() -> Dictionary:
	var malformed := EnvironmentPlotSource.source_errors(plot.data)
	if not malformed.is_empty(): return fail(str(malformed),"INVALID_PLOT")
	var library := {}; var index := context.chunk_library._index()
	if index.is_empty(): return fail("Chunk publication index is invalid","INVALID_LIBRARY")
	var active: Dictionary = index.active
	var wanted := {}
	for street in plot.data.fixed_streets: wanted[street.chunk_id] = true
	for slot in plot.data.slots:
		for id in slot.candidates: wanted[id] = true
	var ids := wanted.keys(); ids.sort()
	for id in ids:
		if not active.has(id): continue
		var revision: String = active[id]
		var checked := PlotCompositionSnapshot.registered(revision,context)
		if not checked.ok:
			diagnostics.append({"chunk":id,"reason":checked.error}); continue
		library[id] = {"source":checked.source,"compiled":checked.compiled,"eligible":true,"revision":revision,"ambiguous":false}
	var assessed := PlotFeasibility.assess(plot,library)
	if not assessed.ok: diagnostics.append_array(assessed.errors); return fail("Plot cannot be filled from registered content; see slot/port diagnostics","UNSATISFIABLE_PLOT")
	if not assessed.generation_ready: diagnostics.append_array(assessed.warnings); return fail("Pin approved fixed revisions and register required slot content","PUBLICATION_REQUIRED")
	for street in plot.data.fixed_streets: fixed.append({"id":street.id,"chunk_id":street.chunk_id,"revision":street.revision,"origin":street.origin.duplicate(),"rotation":int(street.rotation)})
	fixed.sort_custom(func(a,b): return a.id < b.id)
	slots = plot.data.slots.duplicate(true)
	for slot in slots:
		var candidates: Array = assessed.candidates[slot.id].filter(func(c): return c.eligible)
		candidates.sort_custom(func(a,b):
			var left := rank(slot.id,a); var right := rank(slot.id,b)
			return left < right if left != right else ChunkPublicationCompiler.canonical(a) < ChunkPublicationCompiler.canonical(b))
		options[slot.id] = candidates
	slots.sort_custom(func(a,b):
		if a.required != b.required: return a.required
		if options[a.id].size() != options[b.id].size(): return options[a.id].size() < options[b.id].size()
		var aa := int(a.bounds[2])*int(a.bounds[3]); var ba := int(b.bounds[2])*int(b.bounds[3])
		return aa > ba if aa != ba else a.id < b.id)
	if visit(0,fixed.duplicate(true)):
		last_result["attempts"] = attempts; last_result["diagnostics"] = diagnostics
		return last_result
	return fail("Search used %d/%d attempts; %s" % [attempts,budget,"increase budget or reduce alternatives" if attempts >= budget else "no complete arrangement satisfies compilation/population"],"SEARCH_BUDGET_EXHAUSTED" if attempts >= budget else "NO_VALID_COMPOSITION")
func rank(id: String, candidate: Dictionary) -> String:
	return ("%d|slot:%s|%s" % [generation_seed,id,ChunkPublicationCompiler.canonical(candidate)]).sha256_text()
func visit(depth: int, selected: Array) -> bool:
	if attempts >= budget: return false
	if depth == slots.size():
		attempts += 1
		var document := make_document(selected)
		var compiled := evaluate(document)
		if compiled.ok: last_result = compiled; return true
		diagnostics.append({"stage":"complete arrangement","choices":selected.duplicate(true),"errors":compiled.errors})
		return false
	var slot: Dictionary = slots[depth]
	var choices: Array = options[slot.id].duplicate(true)
	if not slot.required: choices.append(null)
	for candidate in choices:
		if attempts >= budget: return false
		attempts += 1
		var next := selected.duplicate(true)
		if candidate != null:
			var choice: Dictionary = candidate.duplicate(true); choice.erase("eligible"); choice["id"] = slot.id
			next.append(choice)
		if visit(depth+1,next): return true
	return false
func make_document(selected: Array) -> BattlefieldLayoutDocument:
	selected.sort_custom(func(a,b): return a.id < b.id)
	var empty := EnvironmentModuleLayout.new(&"authored_plot")
	var doc := BattlefieldLayoutDocument.from_authored(empty,Vector2i(plot.data.map_size[0],plot.data.map_size[1]),&"industrial_district","plot_%s_%d" % [plot.data.plot_id,generation_seed],null,context)
	doc.provenance = {"origin":"generated","generator_id":"authored_plot_composer","has_generation_seed":true,"generation_seed":generation_seed,"generation_config":{"topology":"authored_plot","attempt_budget":budget},"algorithm_revisions":{"plot_composer":VERSION},"composition":{"version":PlotCompositionSnapshot.VERSION,"implementation":PlotCompositionSnapshot.implementation_signature(),"plot":plot.data.duplicate(true),"choices":selected.duplicate(true),"attempts":attempts}}
	doc.spatial_layout["resolution_version"] = 2
	doc.mission_context = {"status":"preserved","zone_source":"authored_plot","zones":PlotCompositionSnapshot.zones(plot)}
	doc.spatial_layout["reservations"] = PlotCompositionSnapshot.reservations(plot)
	return doc

func evaluate(document: BattlefieldLayoutDocument) -> Dictionary:
	# Population already validates/compiles the base and the final accepted output.
	return TacticalPopulationPass.populate(document,plot.population_rules(),generation_seed,context)
