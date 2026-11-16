# Controlled combat examples

Milestone 04 step 3, 2026-11-16. The existing **Tactical Test Range** now contains repeatable geometry examples for the [intended rules](combat-2-rules.md). It still uses today's combat formula. In particular, a passing geometry check does not mean the new cover penalties, accuracy plateau, chance colors or continuous height bonus have shipped.

## Open and edit

From Match Setup choose **Open Parcel Editor**, select **Tactical Test Range**, then **Test battle**. The added stations are fixed; optional cars and cargo occupy their existing separate bays. The automated command below starts with population off, then checks both settings. The three normal map choices remain Depot, Freight and Fleet; this range is an authoring/mechanics fixture, not another procedural system. Local test battle uses the same Generation 2 pipeline.

For scene editing open `art/environments/authored/parcels/tactical_test_range.tscn` in Godot. Existing ramps, stairs, galleries and mission stations remain in that scene. Its ordinary child scene, `art/environments/authored/components/combat_examples.tscn`, contains the added stations. Edit that scene directly, or open its instance from the range. No boundary-draft export or new registration step is required.

Gold ground labels identify stations; **S** and **T** mark shooter and target positions. They are reference marks, not spawning commands or interactive buttons. The table uses parcel-local `(x, y, z)` coordinates, which match grid coordinates in the registered 32×32 range. World coordinates are centered by the existing parcel transform. Some markers are ray probes above the floor, not places to stand a unit.

## Stations and expected geometry

| Station | Repeatable setup | Expected result |
| --- | --- | --- |
| **01 Ramp / stairs** | Ground `(11,0,15)` via ramp, or `(6,0,15)` via stairs, to the gallery at level 3 | Both routes reach the lower gallery. The existing slope is available for future fractional-height comparisons; its current tactical surface still uses stepped elevations. |
| **Stacked galleries** | Shared columns `(6,*,6)` and `(8,*,7)` at levels 0, 3 and 6; ladder `(7,3,9)` to `(7,6,8)` | Surfaces remain distinct; the ladder reaches the upper gallery. A vertical ray through the decks is blocked by their slabs. |
| **02 Cover / reactions** | Retained barriers and small crates east of the gallery | Existing movement, low obstacles and Guard playtesting remain available. Reactions are covered by the existing action/Overwatch suites, not newly proven by this scene alone. |
| **03 Vehicle occlusion / 04 Cargo** | Retained sedan, stacked cargo and optional population sockets | Retain the existing visual/occlusion and population comparisons without moving their original objects. |
| **05 Low / full crates** | Low: `(23,0,13)` → `(23,0,17)`, crate at `(23,0,16)`, height 0.8. Full: same Z coordinates at X=27, height 1.3 | Both allow partially exposed body shots, with distinct low/full cover labels. Shooting from two tiles east of the target removes the local directional cover. The intended 20/40 penalties come later. |
| **06 Cargo / low hood** | Truck at `(17,0,7)`. Rays from X=14 to X=20 at Y=1.2: Z=6 through cargo; Z=9 over hood | Cargo ray blocked, above-hood ray clear, in both directions. Reuses the standalone delivery scene and its current compound shapes. |
| **07 Open door / solid wall** | Rays from Z=20 to Z=24: X=17 at Y=1 through the opening; X=15 at Y=1 through the wall; X=17 at Y=2.9 through the beam | Door ray clear and ground traversable; wall and beam rays blocked, in both directions. Ladder `(15,0,23)` reaches the wall top `(15,3,22)`. |
| **08 Sealed / grazing corners** | Sealed: `(25,1,3)` → `(26,1,4)` between touching blocks. Single: `(27,1,7)` → `(28,1,8)` | Touching pair blocks both ways; a single tangent corner clears both ways. Raising the sealed-pair ray to Y=3 clears both blocks. These coordinates are ray endpoints. |
| **09 Clear range** | Shooter `(1,0,16)`; targets at Z=22, 24, 26 and 27, labeled T6/T8/T10/T11 | With weapon range 10, the first three targets are in reach and T11 is out of range. Future clear, level normal-shot expectations are 100%, 83%, 30%, and illegal respectively; current tests deliberately do not assert those future odds. |

The doorway is an open wall section with a supported top beam, not a complete building or new asset template. Its beam uses the existing deck/slab contract, so it is represented above the open ground cell. Initial testing of an isolated floating lintel exposed a compiler limitation: a raised part with no intersecting tactical surface can be absent from LOS. General raised/concave mesh handling remains a concrete step-4 investigation; this supported fixture does not establish that every floating asset works.

## Repeat the checks

```powershell
godot_console --headless --path . --script res://tests/combat_controlled_examples_test.gd
```

The check starts a real range battle, tests body exposure and ray geometry, verifies standing/traversal, checks seed/population combinations, reconstructs the exact accepted manifest and rejects the old parcel revision. The range parcel revision was raised from 1 to 2 because fixed obstacles changed; older range recordings must not silently acquire them. This does not change Depot, Freight or Fleet content revisions or combat balance.

For review captures, run the same script with graphics:

```powershell
godot_console --path . --script res://tests/combat_controlled_examples_test.gd -- capture
```

It saves overview, doorway/crate, doorway-front and truck/corner views under `artifacts/combat-examples/`, then closes its own test window. It does not alter an already-running editor session. Captures show the real generated presentation; they are inspection aids, not automated visual comparisons or a completed manual battle.

## Verification recorded for this change

- Final headless controlled-example run: **97 checks, 0 failures**. Includes seeds 16/17, population on/off, bidirectional probes, crate exposure/flanks, doorway passage, gallery traversal, range reach, exact reconstruction and stale-content rejection.
- Companion suites: diagonal combat, elevation combat, authored tactical shapes, authored parcel catalog and current generation all exited successfully with zero assertion failures. The current-generation suite's intentional stale-plot rejection is expected negative-test output.
- Real Parcel Editor → Test battle → return smoke: **4 checks, 0 failures**, including retention of the examples, the open doorway and unchanged editor session. This was a temporary isolated check, not a saved user draft.
- Headless editor scan passed. The rendered run passed **101 checks**, including four saved captures. Graphics captures were inspected; those checks establish presentation of these examples, not full playability, camera coverage or future balance correctness.
- Some verification processes reported the existing Windows root-certificate-store error. The first immediate-free test teardown also reported resource leaks; queued teardown with two frames completed cleanly in the final headless run. No claim of a full-project leak audit is made.

Next: step 4, make geometry and LOS predictable, using these fixtures to reproduce mismatches. Add future-rule assertions alongside their implementation; do not rewrite today's balance tests as if the intended numbers were already running.
