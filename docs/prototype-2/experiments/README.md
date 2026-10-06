# Prototype 2 experiment notebook

Every experiment begins by copying [`template.md`](template.md). Keep its scope
small enough to remove cleanly. Screenshots, measurements, test seeds, and brief
observations belong with the experiment note rather than in somebody's memory.

Research and implementation are separate decisions. An observed technique is
evidence, not an instruction to reproduce another game's architecture. Record
the source, the inference, and the proposed FuseFire rule before changing code.

Operation XCOM uses the [research ledger](../operation-xcom/research-ledger.md)
to turn SDK observations into small, reversible FuseFire experiments.

## Active experiments

- [EXP-001 — MIRA-0 asset intake and clean round-trip](exp-001-mira-0-intake.md)

## Protected baseline

- **Release:** `v1.0.0`
- **Commit:** `43c95675d2abb5c61fa964c55aed27b51a292a9f`
- **Reference:** [Prototype 1 release](../../prototype-1-release.md)
- **Architecture evidence:** [27A audit](../../prototype-1-audit-27a.md)

## Minimum regression check

Use focused checks while working and the full release suite before adopting a
cross-cutting experiment.

- [ ] Project imports and parses cleanly.
- [ ] Live pause freezes AI, movement, action resolution, objectives, and turns.
- [ ] Replay pause freezes the battle while allowing its intended camera control.
- [ ] A recorded battle replays without divergence.
- [ ] Repeating a fixed seed preserves authoritative results and ordering.
- [ ] Diagonal movement and targeting preserve corner blocking.
- [ ] AI-controlled turns always complete or explain why they wait.
- [ ] Rescue, carrying, extraction, and optional departure still complete.
- [ ] Eligible zero-AP extraction still works and agrees with replay.
- [ ] Forward+ and Compatibility renderers receive a visual smoke check when
  presentation, shaders, materials, cameras, or imported assets change.

## Invariants an experiment must respect

1. Gameplay truth belongs to tactical units, the grid, action gateways, AP/HP,
   and objective state—not animation, IK, cameras, root motion, or overlays.
2. Action validation, mutation, presentation, completion, and event order remain
   explicit and deterministic.
3. Pause stops tactical mutation and continuation.
4. Seeded randomness, neighbor ordering, tie-breaking, movement history, and
   reservations remain deterministic.
5. Stable actor names, UIDs, animation paths, exports, and replay identifiers do
   not change accidentally.
6. `BattleLevel` remains the composition root unless a separately reviewed
   experiment proves that ownership inadequate.
7. Human editing remains a design constraint: important rules and tunables must
   have a discoverable owner, useful name, and practical edit path.
8. A prototype should remain enjoyable to build and test. Complexity must earn
   its cost through clearer behavior, better tools, or meaningful play.

## Evidence and reversibility rules

- Label claims as **observed**, **inferred**, or **tested in FuseFire**.
- Cite an exact local file, class, package, scene, recording, seed, or profiler
  capture whenever one exists.
- Keep proprietary reference assets outside Git. Operation XCOM local exports
  belong under ignored `research/xcom-local/` and must never ship.
- Give every code experiment a narrow activation point and a written removal
  path before implementation.
- Record baseline behavior before changing a rule that affects simulation,
  replay, AI, input commitment, or animation-event timing.
- Do not let a successful technical proof silently become final game design.
  Close the experiment with an explicit outcome.

## Outcomes

Every closed experiment receives exactly one result:

- **Adopt** — the proof solved its stated problem and has passed its checks.
- **Revise** — useful evidence exists, but the proposed form needs another proof.
- **Archive** — preserve the learning; current scope does not justify adoption.
- **Discard** — the approach failed or solved the wrong problem; remove its code.

