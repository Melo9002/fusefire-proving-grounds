class_name MapBatchTestResult
extends RefCounted

var first_seed: int
var seed_count: int
var failures: Dictionary = {}
var minimum_low_cover: int = 2147483647
var maximum_low_cover: int = 0
var total_low_cover: int = 0
var minimum_full_cover: int = 2147483647
var maximum_full_cover: int = 0
var total_full_cover: int = 0
var minimum_cohesive_cover: int = 2147483647
var maximum_cohesive_cover: int = 0
var total_cohesive_cover: int = 0

func _init(start_seed: int, count: int) -> void:
	first_seed = start_seed
	seed_count = count

func record_success(low_cover: int, full_cover: int, cohesive_cover: int) -> void:
	minimum_low_cover = mini(minimum_low_cover, low_cover)
	maximum_low_cover = maxi(maximum_low_cover, low_cover)
	total_low_cover += low_cover
	minimum_full_cover = mini(minimum_full_cover, full_cover)
	maximum_full_cover = maxi(maximum_full_cover, full_cover)
	total_full_cover += full_cover
	minimum_cohesive_cover = mini(minimum_cohesive_cover, cohesive_cover)
	maximum_cohesive_cover = maxi(maximum_cohesive_cover, cohesive_cover)
	total_cohesive_cover += cohesive_cover

func record_failure(map_seed: int, messages: Array[String]) -> void:
	failures[map_seed] = messages

func passed() -> bool:
	return failures.is_empty()

func successful_count() -> int:
	return seed_count - failures.size()

func average_low_cover() -> float:
	return float(total_low_cover) / float(successful_count()) if successful_count() > 0 else 0.0

func average_full_cover() -> float:
	return float(total_full_cover) / float(successful_count()) if successful_count() > 0 else 0.0

func average_cohesive_cover() -> float:
	return float(total_cohesive_cover) / float(successful_count()) if successful_count() > 0 else 0.0
