extends RefCounted
## Isolated synthetic registration for automated tests only. Never production approval.
var library: ChunkPublicationLibrary
var revisions := {}
var directory: String
var failures := 0
func check(value: bool, message: String):
	if not value: failures += 1; push_error(message)
func operation() -> EnvironmentResolutionContext:
	var context := EnvironmentResolutionContext.new(); context.chunk_library = library; return context
func create(path: String) -> bool:
	directory = path
	library = ChunkPublicationLibrary.new(directory.path_join("library"))
	var context := operation()
	for id in ["street_straight","warehouse_frontage","service_yard","loading_yard","alley_courtyard"]:
		var chunk: EnvironmentChunkSource = ChunkSourceStore.load_named("res://content/chunks/industrial",id).source
		ChunkSourceStore.save_named(chunk,directory,id)
		var validated := library.validate_and_store(chunk,ChunkSourceStore.path_for(directory,id),context)
		check(validated.ok,"fixture validates "+id)
		if not validated.ok: print(validated); return false
		revisions[id] = validated.revision
		var image := Image.create(32,32,false,Image.FORMAT_RGBA8); image.fill(Color.DARK_CYAN)
		for view in ["overview","opposite","overhead"]: check(library.capture_evidence(validated.revision,image,view).ok,"isolated synthetic test evidence "+id+" "+view)
		# Simulated approval exists ONLY in disposable test storage, never production.
		check(library.approve_by_owner(validated.revision,"AUTOMATED TEST FIXTURE ONLY",true).ok and library.register(validated.revision).ok,"isolated registration fixture "+id)
	return failures == 0
