# Semantic-Driven Industrial Showcase

The industrial showcase converts reviewed asset meaning into explicit placement rules. It uses the calibrated City Kit Industrial buildings, the existing tactical module catalog, the coherent road plot, and authored parcel compositions. Imported geometry remains presentation data; `MapData` remains authoritative for movement, stopping, cover, line of sight, deployment, and mission routes.

## Building placement profiles

All twenty `city_kit_industrial/building-a` through `building-t` shells were inspected from six local-axis views. Each now has a stable module with:

- its calibrated X/Z bounds rounded outward to a conservative solid-cell footprint;
- its measured height for full-cover and visual-envelope validation;
- its reviewed working face normalized to module-local `+Z`;
- a three-cell road-facing apron reserved as placement clearance; and
- explicit `prebuilt_shell` and exterior-only semantics.

The apron protects doors, loading bays, and the readable facade transition. It remains ordinary walkable tactical ground. A sealed shell never gains an interior, entrance socket, or gameplay collision from its mesh.

The current 20 × 20 frontage parcel can use up to thirteen of the twenty profiles: `d`, `e`, `f`, `g`, `h`, `i`, `j`, `k`, `m`, `n`, `o`, `p`, and `t`, with the exact fitting set computed from footprint plus apron. Selection then filters those geometric candidates through confirmed semantics, procedural approval, completeness, working face, and environment context. Compact shells `i`, `k`, `p`, and `t` are also reviewed for commercial exterior use. Larger shells remain registered and reusable, but need a future 30-cell campus parcel before procedural selection.

## Parcel grammar

A road-facing frontage parcel now asks for specific fitting reviewed shells, centers each candidate at the rear of a paved 20 × 20 lot, rotates the normalized facade toward the road, and keeps the service apron clear. Bounded search can reject a conflicting building and try another actual asset. Context is added only where its dimensions allow it: a dumpster beside compact shells, street lighting along the public edge, and existing service-yard assets in adjacent functional parcels.

If a neighboring calibrated envelope or clearance prevents every industrial shell candidate, bounded search tries an authored industrial yard. That fallback contains a loading canopy, machinery cluster, staged container, and continuous paving. Small parcels are loading bays, equipment compounds, service alleys, industrial staging pads, or paved commercial forecourts. Landlocked reserved space is identified as a district buffer in the plan rather than being disguised with disconnected paving or clutter.

Roads continue to use the exact ten-cell streetscape contract: six-cell carriageway, two-cell sidewalks on each side, curb seams, markings, intersection controls, and context-specific outer-lane furniture. Entrances and aprons meet paved parcel ground without altering the road's tactical cells.

## Inspection

From the repository root:

```powershell
godot_console --path . res://tools/map_editor.tscn -- 17 industrial_district
```

Seed `17` is the primary showcase: it contains several reviewed industrial shells, a connected crossroad, continuous sidewalks, and functional service parcels. Seeds `2208`, `7319`, and `11027` exercise different topology and fallback choices. `mixed_service 11027` and `commercial_street 7319` remain useful identity comparisons. The editor opens on this showcase by default; legacy component maps are available only through **Engineering fixtures**.

Right-drag to orbit, middle-drag to pan, use the wheel to zoom, and left-click a piece to select it. `P` toggles the road/parcel plan. `D` shows the selected module's tactical footprint, placement clearance, visual envelope, and sockets. The seed controls regenerate identical layouts from identical inputs.

The explicit rendered review workflow is:

```powershell
godot_console --path . --script res://tests/coherent_layout_capture.gd -- artifacts/semantic-district-review
```

It records overview, overhead, intersection, building-frontage, and service-area views for the representative identities. Headless success does not replace this visual review.

## Limits and next improvements

- Seven large shells require a wider campus parcel before they can be selected without shrinking their calibrated presentation.
- The road grammar still has one primary crossroad or T-junction with straight approaches. Secondary streets, access lanes, parking/loading markings, and multiple intersections are the next district-level expansion.
- Monolithic vendor shells remain inaccessible exteriors. Playable interiors need separate authored assemblies and cutaway behavior.
- The existing machinery yard proves contextual composition, but additional authored refinery, power, and storage-yard parcels are needed for stronger seed-to-seed identity.
- Street furniture is context-aware at the road and parcel level; it does not yet model a continuous power network or traffic phases.

