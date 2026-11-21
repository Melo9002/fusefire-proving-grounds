class_name PathPresentationProfile
extends Resource
## How the visual walk may smooth the tactical route (PathRefiner). PRESENTATION ONLY and opt-in: the walk visits the same cells and ends on the same point; nothing here can
## make a blocked cell usable, change AP, occupancy, line of sight or cover, or enter the replay record. Off by default (experimental).

@export var enabled := false
## A corner of the route is cut with a curve this far (metres, each way) at most; the cut shrinks, then is dropped, if the curve would come closer to a physical part than the body.
@export_range(0.05, 1.0, 0.01, "suffix:m") var corner_cut := 0.45
## Turns gentler than this are left straight.
@export_range(1.0, 90.0, 1.0, "suffix:°") var min_turn_degrees := 20.0
@export_range(2, 12) var arc_samples := 5
## Extra clearance demanded of a smoothed segment beyond the body radius.
@export_range(0.0, 0.3, 0.005, "suffix:m") var clearance_margin := 0.0
