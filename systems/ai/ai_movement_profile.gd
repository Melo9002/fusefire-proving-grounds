class_name AIMovementProfile
extends Resource
## A situational layer of multipliers on the movement position score (AIPositionScorer): what a unit is
## doing right now (marching to an objective, carrying someone, guarding, flanking...), not how well it
## plays (AIDifficultyPolicy) and not the team's doctrine (AICommanderPolicy). 1.0 leaves a term unchanged.
## Authored as Resources in res://systems/ai/profiles/ so a preset can be tuned in the Inspector.
## A profile never changes which cells are legal: it only re-weights cells the shared queries allow.

@export var profile_id: StringName = &"default"
@export var display_name := "Default"
@export_multiline var description := ""

@export_group("Multipliers")
## Reward for getting along the route to the goal (progress along the path).
@export_range(0.0, 5.0, 0.05) var route_progress := 1.0
## Reward for getting closer to the goal as the crow flies.
@export_range(0.0, 5.0, 0.05) var goal_progress := 1.0
@export_range(0.0, 5.0, 0.05) var cover := 1.0
@export_range(0.0, 5.0, 0.05) var exposure := 1.0
## Reward for cells with a legal shot at a hostile. Zero ignores firing lanes entirely.
@export_range(0.0, 5.0, 0.05) var firing := 1.0
@export_range(0.0, 5.0, 0.05) var danger := 1.0
## How much the soft crowding preference counts (hard squad commitments are never softened).
@export_range(0.0, 5.0, 0.05) var crowding := 1.0

@export_group("Additional terms")
## Reward for a cell that spreads fire onto a target from a new bearing and lessens the target's cover.
@export_range(0.0, 20.0, 0.5) var flank_weight := 0.0
## Reward for staying near allies (the nearer the better, up to a few cells).
@export_range(0.0, 20.0, 0.5) var ally_cohesion_weight := 0.0

func summary() -> String:
	var parts: Array[String] = []
	for entry in [["route", route_progress], ["goal", goal_progress], ["cover", cover], ["exposure", exposure], ["firing", firing], ["danger", danger], ["crowding", crowding]]:
		if not is_equal_approx(float(entry[1]), 1.0):
			parts.append("%s x%.2f" % [entry[0], float(entry[1])])
	if flank_weight > 0.0: parts.append("flank %.1f" % flank_weight)
	if ally_cohesion_weight > 0.0: parts.append("cohesion %.1f" % ally_cohesion_weight)
	return "%s (%s)" % [display_name, ", ".join(parts) if not parts.is_empty() else "no change"]
