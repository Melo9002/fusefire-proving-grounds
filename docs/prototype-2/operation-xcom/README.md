# Operation XCOM

Operation XCOM studies a mature tactics game to ask better questions about
FuseFire. It is research, not a port. We may inspect source, packages, tools,
animation organization, cameras, and player-facing behavior, then build small
FuseFire-native proofs that fit this project's simpler architecture.

Start with the [research ledger](research-ledger.md). It records what we actually
saw, what we only infer, what FuseFire rule might be worth testing, and how to
remove each experiment.

## Working rules

1. **Observe before designing.** Record exact evidence before proposing a rule.
2. **Translate the purpose.** Recreate the useful behavior in FuseFire terms;
   do not reproduce Unreal/XCOM structure merely because it exists.
3. **Separate truth from presentation.** Animation, cameras, effects, and UI may
   present an action but cannot become the authority for tactical state.
4. **Experiment at one seam.** A proof should have one clear activation point
   and should be removable without unraveling unrelated systems.
5. **Protect the released game.** `v1.0.0` remains the behavioral baseline.
6. **Keep editing human-friendly.** New rules need a discoverable home, plain
   names, useful editor exposure where appropriate, and short guidance.
7. **Record failures.** A discarded idea can be valuable if its evidence and
   reason remain searchable.
8. **Keep proprietary material local.** Never commit or distribute XCOM code,
   packages, animations, meshes, audio, textures, or extracted derivatives.
   Local extraction work belongs in ignored `research/xcom-local/`.
9. **Make our own release content.** Any temporary private animation study must
   end in an original or properly licensed FuseFire asset before distribution.
10. **Have fun on purpose.** Prefer experiments that are satisfying to inspect,
    change, and play. Research should make the project livelier, not bury it.

## Status flow

`study → proposed → active → observing → closed`

- **Study:** evidence is being gathered; there is no implementation proposal.
- **Proposed:** the hypothesis and smallest proof are written.
- **Active:** an isolated proof exists or is being built.
- **Observing:** implementation is stable enough for playtests or measurements.
- **Closed:** the experiment has one notebook outcome: Adopt, Revise, Archive,
  or Discard.

Nothing becomes a permanent game rule merely by reaching `active` or
`observing`. Adoption is an explicit decision recorded in the experiment note.

## Research source roots

These paths are local evidence locations and must not be copied into Git.

- Base SDK source: `C:\Program Files (x86)\Steam\steamapps\common\XCOM 2 SDK\Development\SrcOrig`
- Base SDK content: `C:\Program Files (x86)\Steam\steamapps\common\XCOM 2 SDK\XComGame\Content`
- War of the Chosen SDK: `C:\Program Files (x86)\Steam\steamapps\common\XCOM 2 War of the Chosen SDK`

## Starting an experiment

1. Add or update a row in the research ledger.
2. Copy [`../experiments/template.md`](../experiments/template.md).
3. Link the ledger rule IDs from the experiment note.
4. Capture the current FuseFire behavior and relevant invariants.
5. Build the smallest proof behind a clear activation point.
6. Observe it, run focused regression checks, and record editing friction.
7. Close it deliberately: Adopt, Revise, Archive, or Discard.
