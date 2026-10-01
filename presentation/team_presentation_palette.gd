class_name TeamPresentationPalette
extends Resource

## Shared faction colors and ground-ring appearance used by tactical units.

@export_group("Faction Colors")
@export var player := Color(0.05, 0.65, 1.0, 1.0)
@export var ally := Color(0.2, 1.0, 0.35, 1.0)
@export var enemy := Color(1.0, 0.12, 0.08, 1.0)
@export var neutral := Color(0.85, 0.85, 0.85, 1.0)

@export_group("Ground Ring")
@export_range(0.05, 2.0, 0.01, "suffix:m") var inner_radius := 0.31
@export_range(0.05, 2.0, 0.01, "suffix:m") var outer_radius := 0.37
@export_range(3, 64, 1) var radial_segments := 12
@export_range(3, 96, 1) var ring_segments := 24
@export_range(0.0, 0.25, 0.005, "suffix:m") var height := 0.025
@export_range(0.0, 8.0, 0.1) var emission_energy := 2.2
