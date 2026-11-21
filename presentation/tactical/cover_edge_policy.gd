class_name CoverEdgePolicy
extends Resource
## The TACTICAL policy for choosing which end of a cover wall a unit peeks around, and when a target-aware attack uses that edge. It is what CoverEdgeSelector reads: geometry of walls and edges, hysteresis between
## sides, and the target-aware thresholds. It belongs to the tactical host (the adapter, and the workbench's cover bench standing in for it), not to the body: how the body then stands, crouches and turns is
## CoverPostureProfile (reusable motion parameters that know nothing about walls or targets).

@export_group("Edge selection")
## How far along the wall (metres) an edge may be and still count as a usable peek position.
@export_range(0.5, 6.0, 0.05, "suffix:m") var edge_reach := 2.2
## When the two usable edges are within this many metres of each other, `tie_side` wins.
@export_range(0.0, 1.0, 0.01, "suffix:m") var tie_tolerance := 0.25
## +1 right, -1 left.
@export_range(-1, 1, 2) var tie_side := 1
## The current side is kept unless the other edge is nearer by more than this (stops flicker from tiny position changes).
@export_range(0.0, 1.5, 0.01, "suffix:m") var hysteresis := 0.35
## How many extra wall cells along the wall are scanned for its end (tile maps).
@export_range(1, 12) var wall_scan_limit := 6

@export_group("Attack posture")
## Target-aware firing (an authorized attack is being presented). `along` is the cosine between the direction to the target and the wall's normal.
## At or below this the wall is not between the unit and the target (it is behind or beside): an ordinary firing posture, no peeking.
@export_range(-1.0, 1.0, 0.01) var open_side_threshold := -0.1
## Target's lateral component (cosine against the wall's tangent) below which it is "straight ahead": no side is better, the passive choice stands.
@export_range(0.0, 0.5, 0.01) var straight_ahead_threshold := 0.12
## A side chosen for a previous attack is kept while the target's lateral component stays within this of straight ahead.
@export_range(0.0, 0.6, 0.01) var attack_side_hysteresis := 0.25
