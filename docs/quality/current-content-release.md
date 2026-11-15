# Current map content release — 2026-11-15

This is a bounded content release for the existing Generation 2 pipeline. It is a stopping point for generator work, not a claim that every future mesh or AI situation is solved.

## Content

| Selectable site | Seed 16 | Seed 17 |
| --- | --- | --- |
| Service Depot | Existing loading crossing | Existing service spine |
| Freight Yard | Container apron west, fleet apron east | Aprons exchanged |
| Fleet Station | North street frontage | South street frontage |

All three are 40 × 40 and use the same resolver, scene compiler, tactical systems, mission initialization and replay machinery. Service Depot's original parcel candidates and fresh-seed ordering remain intact. The menu now exposes three curated IDs; the old one-menu-map assertion intentionally changes while legacy-map retirement and generator independence assertions remain.

New ordinary editable Godot scenes:

- `art/environments/authored/parcels/container_staging_apron.tscn`: 16 × 32, small dispatch office, low supply-cover clusters, four possible container positions; one to four containers can appear.
- `art/environments/authored/parcels/fleet_service_apron.tscn`: 16 × 32, fleet office, four vehicle bays, clear central approach and side cover.
- `art/environments/authored/parcels/fleet_service_court.tscn`: 32 × 32, two service offices, six vehicle bays, pedestrian/service approaches and low supply cover.

Their Freight/Fleet labels are available in Parcel Editor. Source scenes open with empty guides; Preview and Test battle populate them through the existing runtime rules. Existing manual placement, save/open and return paths remain available. New data-only parking bays now also reject fixed-object placement over their future occupants, with the existing gold reservation feedback. The focused regression reproduced a failure before that correction and passes afterward.

The new site definitions live alongside Depot in `systems/generation2/generator.gd`. Freight uses two compatible aprons with explicit service connections; Fleet uses a 32 × 32 court with explicit north/south street connections. Plot scenes under `art/environments/authored/plots/` own roads, circulation and visual surroundings. Outside scenery is not stamped into tactical data. No old generator or retired map was restored.

## Vehicles and compatibility

New parking bays use the mixed set: sedan, SUV, taxi, ambulance and van. Older bay records without a set tag retain the ordered classic three. New exports explicitly save the mixed tag; the editor gains no new required selector or boundary workflow. Existing source bays are not silently upgraded.

The reusable ambulance and van scenes in `art/environments/authored/objects/` contain boundaries derived by the same mesh helper used by ordinary editor placement. Their measured calibrated visual bounds are 1.875 × 2.25 × 4.0625 and 1.875 × 1.6875 × 3.4375 respectively (width × height × depth), within the existing 3 × 5 bay and 2.5 headroom. Vehicle fitting merges visible and active tactical bounds. The office component reuses the current warehouse's compound shapes; the original warehouse scene is unchanged.

Both new vehicle types actually appear in the known-seed sweep. These are tactical obstacles/cover using existing combat rules; no medical or driving system is introduced. Per-mesh boxes remain approximations. The temporary scene-authoring scripts were removed after producing the editable scene assets; runtime never imports authoring tools.

## Verification scope

- `current_content_pack_test.gd`: 32 seeds across the two new sites, valid parcel scenes, candidate/fixed-geometry clearance, fixed aisle clearance, supported 5/5/5 deployment, population off, exact manifest reconstruction, both plot arrangements and actual ambulance/van selection. Historical bay allow-lists remain classic.
- `current_mission_replay_matrix_test.gd`: expanded to **48 cases**, covering all eight missions, seeds 16/17, and all three sites, with alternating population on/off and an authoritative action replay. These are validated starts/action replays, not AI wins on every mission.
- `current_content_playthrough_test.gd`: final content at seed 16 completed Freight Yard in six rounds (69 actions, victory) and Fleet Station in four rounds (47 actions, defeat). Saved-file playback verified every action and the same final outcomes. A defeat counts as a completed core loop, not a balance recommendation.
- Clean site views for both layouts and guide/Preview views for all three parcels are in `artifacts/current-content-review/`. These bounded rendered checks do not establish visual correctness at every cinematic angle or for future content edits.
- Local generation diagnostics were roughly 140–170 ms per new 40 × 40 map on this machine, with observed maxima around 230 ms. They are development observations with other work running, not a performance budget or portable benchmark.

The first full-run aisle assertion used the placement-obstacle list, which intentionally includes reserved aisles, and therefore compared each aisle against itself. This was a **defective test input**, not a geometry correction. The assertion now checks fixed physical geometry directly; its 32-seed focused rerun passed with all intended overlap and clearance assertions retained. The full run recorded **127 pass, 2 fail, 14 explicit-only checks skipped** (`artifacts/test-results/20261115-152508-full`). The other failure was a real dependency regression: the new vehicle fitter preloaded the map compiler just to select active shape metadata, transitively loading example parcels. The metadata predicate now lives in a small shared `tactical_shape_rules.gd`; the compiler keeps its existing public predicate/revision, while vehicle fitting no longer loads map compilation. The unchanged isolation assertions passed on the focused rerun, and coverage now explicitly loads both vehicle sets before checking the cache. Historical geometry/metadata baseline assertions remain intact.

The final generation subsystem run passed **46 checks, 0 failed, 7 explicit-only checks skipped** in 367.48 seconds (`artifacts/test-results/20261115-183915-subsystem-generation`). It includes both corrected suites, the 32-seed sweep, both complete saved-replay playthroughs, the 48-case mission matrix, camera handoff, reservation feedback, population parity, save/open, export and legacy fixture checks. The full run was not wholly green; focused follow-ups must be read alongside that result. Rendered capture plus the corrected 32-seed check also completed with zero failures. The 14 skipped checks are the runner's existing explicit-only captures/stress checks, not removed assertions. Sandbox certificate/log-store errors are environment diagnostics; the existing allied-faction ObjectDB warning remains outside this content change.

## Stopping point

Use the three sites for ordinary battles and move development to tactical feedback/AI. Keep the everyday guide focused on how to choose a site, compare seeds, edit a parcel and launch a test. Reopen generator work for a reproducible bug or a real new content requirement; do not add another general framework to this release.

Quick owner pass: F5 → choose Freight Yard or Fleet Station → disable Automatic New Seed → compare 16/17 and population on/off → play a mission → save/reopen its replay. In Parcel Editor, choose the three new Freight/Fleet entries and compare Guides/Preview/Next seed. Save current in-memory work before restarting the application; this release does not claim to recover an earlier unsaved live session.
