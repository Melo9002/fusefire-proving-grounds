class_name FixedEnvironmentPopulation
extends RefCounted
## Data-backed proof adapter; no runtime chunk registration or chunk-composition dependency.
const BASE_PATH := "res://content/population/industrial_fixed.layout.json"
const RULES_PATH := "res://content/population/industrial_population.json"
static func build(population_seed: int) -> Dictionary:
	var context := EnvironmentResolutionContext.new()
	var loaded := MapEditorLayoutStore.load(context.catalog, BASE_PATH)
	if not loaded.ok: return TacticalPopulationPass.fail(str(loaded.get("error", "Cannot load fixed environment")))
	var parsed := GenerationJsonStore.parse(FileAccess.get_file_as_string(RULES_PATH))
	if not parsed.ok: return TacticalPopulationPass.fail(parsed.error)
	return TacticalPopulationPass.populate(loaded.document, parsed.value, population_seed, context)

static func configuration(population_seed: int, kind := MissionObjectiveDefinition.Kind.ELIMINATE) -> BattleConfiguration:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = BattleConfiguration.GENERATION_2_MAP_SIZE
	config.battle_seed = population_seed
	config.player_count = 2
	config.enemy_count = 2
	config.mission = MissionCatalog.create_mission(kind, config.enemy_count, false)
	return config
