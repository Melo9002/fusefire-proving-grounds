# Controlled combat examples

**Play it directly:** Match Setup → Battlefield → **Tactical Test Range — Test map**. This launches the same authored range and map ID used below, with the ordinary mission, roster, seed and replay flow. Population starts off to keep the controlled examples clear.

Milestone 04 step 3, extended by the step-4 raised-beam regression on 2026-11-16. The existing **Tactical Test Range** now contains repeatable geometry examples for the [intended rules](combat-2-rules.md). It uses the current shared combat formula: physical cover, the range plateau/falloff and continuous height accuracy have shipped. Step 7 also ships +35 Aim and editable fixed hit damage; chance colors remain pending. Passing a geometry check alone is not proof of balanced encounters.

## Open and edit

From Match Setup choose **Open Parcel Editor**, select **Tactical Test Range**, then **Test battle**. The added stations are fixed; optional cars and cargo occupy their existing separate bays. The automated command below starts with population off, then checks both settings. The three normal map choices remain Depot, Freight and Fleet; this range is an authoring/mechanics fixture, not another procedural system. Local test battle uses the same Generation 2 pipeline.

For scene editing open `art/environments/authored/parcels/tactical_test_range.tscn` in Godot. Existing ramps, stairs, galleries and mission stations remain in that scene. Its ordinary child scene, `art/environments/authored/components/combat_examples.tscn`, contains the added stations. Edit that scene directly, or open its instance from the range. No boundary-draft export or new registration step is required.

Visible ramps, stairs and landings can be clicked in Move mode while **Ground** is selected. The view controls inspect/cut away floors; they do not limit how high you can move. Use **Alt + wheel** to choose between stacked surfaces under the cursor. Hidden cutaway roofs do not intercept ordinary ground clicks.

Gold ground labels identify stations; **S** and **T** mark shooter and target positions. They are reference marks, not spawning commands or interactive buttons. The table uses parcel-local `(x, y, z)` coordinates, which match grid coordinates in the registered 32×32 range. World coordinates are centered by the existing parcel transform. Some markers are ray probes above the floor, not places to stand a unit.

## Stations and expected geometry

| Station | Repeatable setup | Expected result |
| --- | --- | --- |
| **01 Ramp / stairs** | Ground `(11,0,15)` via ramp, or `(6,0,15)` via stairs, to the gallery at level 3 | Both routes reach the lower gallery. The existing slope is available for future fractional-height comparisons; its current tactical surface still uses stepped elevations. |
| **Stacked galleries** | Shared columns `(6,*,6)` and `(8,*,7)` at levels 0, 3 and 6; ladder `(7,3,9)` to `(7,6,8)` | Surfaces remain distinct; the ladder reaches the upper gallery. A vertical ray through the decks is blocked by their slabs. |
| **02 Cover / reactions** | Retained barriers and small crates east of the gallery | Existing movement, low obstacles and Guard playtesting remain available. Reactions are covered by the existing action/Overwatch suites, not newly proven by this scene alone. |
| **03 Vehicle occlusion / 04 Cargo** | Retained sedan, stacked cargo and optional population sockets | Retain the existing visual/occlusion and population comparisons without moving their original objects. |
| **05 Low / full crates** | Low: `(23,0,13)` → `(23,0,17)`, crate at `(23,0,16)`, height 0.8. Full: same Z coordinates at X=27, height 1.3 | Both allow partially exposed body shots, with distinct low/full cover labels. Shooting from two tiles east of the target removes the local directional cover. Physical 20/40 cover penalties are now active. The level low-crate setup gives 80% (20 cover versus 10 exposure); the level full-crate setup gives 50% because its one clear sample imposes 50 exposure, stronger than 40 cover. |
| **06 Cargo / low hood** | Truck at `(17,0,7)`. Rays from X=14 to X=20 at Y=1.2: Z=6 through cargo; Z=9 over hood | Cargo ray blocked, above-hood ray clear, in both directions. Reuses the standalone delivery scene and its current compound shapes. |
| **07 Open door / solid wall** | Rays from Z=20 to Z=24: X=17 at Y=1 through the opening; X=15 at Y=1 through the wall; X=17 at Y=2.9 through the beam | Door ray clear and ground traversable; wall and beam rays blocked, in both directions. Ladder `(15,0,23)` reaches the wall top `(15,3,22)`. |
| **08 Sealed / grazing corners** | Sealed: `(25,1,3)` → `(26,1,4)` between touching blocks. Single: `(27,1,7)` → `(28,1,8)` | Touching pair blocks both ways; a single tangent corner clears both ways. Raising the sealed-pair ray to Y=3 clears both blocks. These coordinates are ray endpoints. |
| **10 Raised beam** | Beam at `(17,2.65,17)`; ray `(17,2.7,15)` → `(17,2.7,19)` | Beam blocks both directions at its real height without a supporting deck. The same ray at Y=1 stays clear and the ground remains usable. |
| **09 Clear range** | Shooter `(1,0,16)`; targets at Z=22, 24, 26 and 27, labeled T6/T8/T10/T11 | With weapon range 10, the first three targets are in reach and T11 is out of range. Current clear, level normal-shot expectations are 100%, 83%, 30%, and illegal respectively. Aim raises the maximum-range shot to 65%; damage stays 25 if it hits. |

The doorway is an open wall section with a supported top beam, not a complete building or new asset template. Its beam uses the existing deck/slab contract, so it is represented above the open ground cell. Initial testing of an isolated floating lintel exposed a compiler limitation: a raised part with no intersecting tactical surface can be absent from LOS. Step 4 fixes raised precise parts through a shot-only index and adds station 10 to reproduce this case without a deck. Exact concave/polygon geometry is still not implied by per-mesh boxes.

## Repeat the checks

```powershell
godot_console --headless --path . --script res://tests/combat_controlled_examples_test.gd
```

The check starts a real range battle, tests body exposure and ray geometry, verifies standing/traversal, checks seed/population combinations, reconstructs the exact accepted manifest and rejects the old parcel revision. The range parcel revision is now 3 (revision 2 added the first controlled examples; revision 3 adds the raised beam); older range recordings must not silently acquire them. This does not change Depot, Freight or Fleet content revisions or combat balance.

For review captures, run the same script with graphics:

```powershell
godot_console --path . --script res://tests/combat_controlled_examples_test.gd -- capture
```

It saves overview, doorway/crate, doorway-front, truck/corner and raised-beam views under `artifacts/combat-examples/`, then closes its own test window. It does not alter an already-running editor session. Captures show the real generated presentation; they are inspection aids, not automated visual comparisons or a completed manual battle.

## Verification recorded for this change

- Step-3 headless controlled-example run: **97 checks, 0 failures**; the step-4 range adds four raised-beam checks. Includes seeds 16/17, population on/off, bidirectional probes, crate exposure/flanks, doorway passage, gallery traversal, range reach, exact reconstruction and stale-content rejection.
- Companion suites: diagonal combat, elevation combat, authored tactical shapes, authored parcel catalog and current generation all exited successfully with zero assertion failures. The current-generation suite's intentional stale-plot rejection is expected negative-test output.
- Real Parcel Editor → Test battle → return smoke: **4 checks, 0 failures**, including retention of the examples, the open doorway and unchanged editor session. This was a temporary isolated check, not a saved user draft.
- Headless editor scan passed. The step-3 rendered run passed **101 checks**, including four saved captures. See the [step-4 report](quality/combat-geometry-los-2026-11-16.md) for current verification. Graphics captures were inspected; those checks establish presentation of these examples, not full playability, camera coverage or future balance correctness.
- Some verification processes reported the existing Windows root-certificate-store error. The first immediate-free test teardown also reported resource leaks; queued teardown with two frames completed cleanly in the final headless run. No claim of a full-project leak audit is made.

Steps 4 and 5 are now complete for the demonstrated geometry and cover mismatches. See the [cover/flanking checks and rendered comparisons](quality/combat-cover-flanking-2026-11-16.md). Step 6 now tests actual ramp/stair/deck heights and fractional-height/range cases; see [height/range verification](quality/combat-height-range-2026-11-16.md). Add future-rule assertions alongside their implementation; do not rewrite today's balance tests as if the intended numbers were already running.
