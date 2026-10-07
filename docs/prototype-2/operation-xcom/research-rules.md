# OX-01 — Research rules and experiment ledger

**Restarted:** 2026-10-07  
**Branch:** `p2-foundation`  
**Status:** research workflow ready; individual experiments remain undecided

Operation XCOM continues. Study the installed SDK, test useful ideas in Godot,
and make the resulting rules editable and recognizably FuseFire's. Experiments
may fail or change direction. Technical success alone does not adopt a rule.

## Where to work

- [Research ledger](research-ledger.md): observations, hypotheses, translations,
  status, linked proofs, and rollback notes.
- [Experiment template](../experiments/template.md): detailed proof and results.
- [Animation inventory](animation-inventory.md): existing OX-02 evidence.
- [Placeholder manifest](placeholder-manifest.md): borrowed content provenance
  and the requirements for its eventual replacement.

Use one stable `OX-Rxxx` ID per research question. Link a notebook experiment
when implementing a proof; update the existing row when correcting evidence.
Do not erase a failed hypothesis or describe an unfinished proof as tested.

## Minimum record for every experiment

| Field | What to write |
|---|---|
| Observation | Exact source file/class, package/object, clip, recording, seed, or measurement; distinguish what was seen from what was inferred. |
| Hypothesis | One claim we can disprove, plus a competing explanation where relevant. |
| FuseFire translation | Smallest useful Godot implementation and the player or editing benefit it should demonstrate. |
| Status | `study`, `proposed`, `active`, `observing`, or `closed`; closed rows name Adopt, Revise, Archive, or Discard. |
| Baseline and checks | Current behavior, a repeatable scenario, and the concrete result required to pass. |
| Editing path | Scene/resource/script owner, editable values, and how Pedro can test a change himself. |
| Rollback | Activation switch or seam, affected files/assets, removal steps, and observations that trigger rollback. |
| Decision | Result, remaining uncertainty, and explicit adoption decision if any. |

## Rules for the investigation

1. Source claims need exact evidence. Class names alone establish existence,
   not runtime behavior or architectural correctness.
2. Label direct observations, interpretations, and FuseFire test results
   separately. Record tool/version and sample scope when a tool fails.
3. Examine ownership and dependencies before transplanting a technique.
   Start with one action or presentation seam, then judge the result.
4. Preserve deterministic tactical authority, action order, pause, replay,
   and FuseFire's continuous stair/elevation traversal. Discuss a proposed
   traversal-rule change with Pedro before implementing it.
5. Important settings and clip mappings need an obvious editing home.
   Record how to change and preview them without tracing the whole runtime.
6. Borrowed local assets follow the existing research policy and manifest.
   Record original source, transformations, fallback, and replacement work.
7. Keep baseline evidence and a removal path before altering behavior.
   Use focused checks for each proof; broader checks follow its actual scope.
8. Keep each proof small enough to understand, play with, and remove. A useful
   result can remain an experiment while we decide what the game needs.

## Restart findings and corrections

- Existing `OX-R001` through `OX-R008` remain candidate research questions.
  None is newly adopted by this restart. Recheck broad claims against exact
  source and runtime evidence before implementing them.
- The previous investigation reported compression formats and track offsets
  in exported AnimSet T3Ds, but no keyframe byte stream in the inspected files.
  This supports a limitation of those particular text exports. It does not
  establish that all SDK export routes or conversion tools are unusable.
- Earlier advice to abandon XCOM extraction was premature as a general
  conclusion. Export feasibility is an open experiment, `OX-R009`.
- The current locomotion mismatch is a user-reported problem, `OX-R010`.
  Its cause remains unverified; another heuristic direction patch is not an
  adequate substitute for checking clip selection and coordinate conventions.

## OX-01 completion

This pass is complete when the ledger and experiment template provide the
fields above, the restart uncertainties have stable IDs, and the next proof
has a clear question. It does not require solving animation extraction or
adopting an animation architecture.

**Next proof:** investigate `OX-R009` with one known animation and its original
SDK package. Preserve package/object identity, compare the actual export
routes, and validate any conversion against a manually exported reference.
Only scale to batch conversion after a single clip preserves motion and timing.