# Destructible cover — milestone 04, step 10

Decision, 2026-11-17: **defer in-game destruction; retain the offline crate proof.** Step 10 asks for an investigation and a scope choice, so this completes that step without adding breakable objects to battles. Accuracy, damage and existing cover rules are unchanged.

## What the crate proves

The [investigation](../tests/destructible_cover_investigation_test.gd) duplicates the existing range’s `Crates/FullCrate` into an isolated scene: a 0.9 × 1.3 × 0.9 box. It compiles intact and removed versions through the current tactical compiler, supported standing-point resolver and navigation graph.

| Effect | Intact | Recompiled without crate |
| --- | --- | --- |
| Stand inside its footprint | Rejected | Allowed |
| Reach its former cell from adjacent ground | Blocked | Reachable |
| Chest-height shot through its body | Blocked | Clear |
| Directional protection for adjacent target | Full cover | None |
| Geometry/standing-point signature | Intact signature | Different signature |

Hiding the mesh does **not** remove its tactical metadata. Deleting the source node and rebuilding only the LOS index also leaves the already compiled obstacle behind. Visibility, physics collision and tactical data must change together.

The proof serializes a tiny object identity/removed-state record to JSON and reconstructs matching post-removal geometry. **This is not a playable saved battle replay.** The current replay validator correctly rejects an unsupported destruction action.

## Why defer the live feature

The source scene describes individual objects, but compiled movement parts and cell flags combine their contributions. Identical overlapping movement boxes are deduplicated without retaining separate owner identities. Removing a box or clearing a cell by location could therefore erase another object’s protection. The proof confirms that recompiling with the independent overlapping blocker still present preserves its obstruction.

A fresh standing-point solve can also move someone who never changed cells. With the crate offset 0.35 tiles, an adjacent supported point changes from X=12.62 to X=12.50 after removal: **0.12 tile**. A live update must preserve occupied positions and check body clearance instead of silently recentering units.

Ordinary attacks currently target living units. There is no committed object-damage/destruction action or object HP state in the replay journal. Existing geometry signatures distinguish intact/removed geometry, but do not establish stable object identity or capture HP before an object breaks. Cached paths, previews and AI evaluations also need invalidation when the geometry changes.

## Smallest future implementation

Start with one explicitly breakable crate, intact or removed. Reuse the existing action service and compilation/navigation code; no destruction framework, debris simulation, collapsing floors or building damage is necessary.

1. Give the crate a stable identity derived from accepted content. Decide the damage trigger and whether it needs HP; do not silently make ordinary misses damage scenery.
2. Commit removal as one validated action. Build replacement tactical data while preserving occupied points, other objects, traversal, mission zones and transport reservations. Reject an unsafe update.
3. Replace movement, LOS, cover and navigation together; advance the action revision once and invalidate cached evaluations. Remove the corresponding visible mesh and physical collider as part of the same committed result.
4. Record object state and resolved evidence, include it in fingerprints, and version simulation compatibility. Reconstruct the original accepted content, then replay the same removal.
5. Verify a unit beside the crate stays put, the opening becomes usable, independent overlapping blockers survive, previews agree with execution, and a saved battle replay reproduces the outcome.

These are prerequisites for enabling that single object, not a new asset-authoring workflow. Ordinary asset placement remains unchanged.

## Evidence and limits

- Offline investigation: **15 checks, 0 failures**.
- Existing authored tactical shapes: **0 failures**.
- Ironclad smoke: **11 passed, 0 failed, 0 skipped** (51.52 seconds).
- Godot reported the existing root-certificate environment error; inspected logs contained no script errors.

No rendered destruction test or full AI/replay suite was run. No production scene, attack or replay format was changed. The proof establishes reconstruction behavior, not safe live mutation. The subsequent [reliability baseline](combat-reliability.md) and [prototype closure report](quality/combat-closure-2026-11-17.md) now record steps 11–12. Destruction remains deferred.
