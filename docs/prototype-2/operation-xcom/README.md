# Operation XCOM

Operation XCOM studies a mature tactics game to ask better questions about
FuseFire. It is research, not a port. We may inspect source, packages, tools,
animation organization, cameras, and player-facing behavior, then build small
FuseFire-native proofs that fit this project's simpler architecture.

Start with the [research ledger](research-ledger.md). It records what we actually
saw, what we only infer, what FuseFire rule might be worth testing, and how to
remove each experiment.

## Research passes

- [OX-01 — Research rules](research-rules.md): experiment records, restart
  corrections, acceptance checks, human editing paths, and rollback requirements.

- [OX-02 — Animation inventory](animation-inventory.md): human animation
  packages, naming grammar, sockets, IK, notifies, and FuseFire opportunities.

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
8. **Keep FuseFire assets when they already fill the role.** MIRA-0 remains the
   character test body, the AUG remains the current rifle, and the existing
   FuseFire animation work remains the fallback. Research does not justify
   remaking or replacing a working project asset merely to resemble XCOM.
9. **Keep proprietary material local.** XCOM animations and untextured reference
   assets may be copied into the ignored `research/xcom-local/` area as private
   placeholders for study and local experiments. Remove or omit textures when a
   mesh is used to describe proportions, sockets, modular boundaries, collision,
   or another production target. Never commit, push, package, distribute, or
   release XCOM code, packages, animations, meshes, audio, textures, or extracted
   derivatives. Removing textures does not make an extracted asset releasable.
10. **Track every borrowed placeholder.** A local XCOM asset used in an experiment
   needs its source, purpose, visible identifying label, FuseFire fallback, and
   replacement task recorded in the [placeholder manifest](placeholder-manifest.md).
   Do not let a useful placeholder disappear into the project as if it were
   production content.
11. **Make our own release content.** Every borrowed asset must be replaced by
   original or properly licensed FuseFire content before distribution. We may
   reproduce useful functional roles and workflow ideas in our own work.
12. **Block out only missing requirements.** When research reveals a requirement
    FuseFire does not yet represent—such as a new cover shape, interaction prop,
    traversal helper, or modular environment boundary—we may create a simple
    original blockout that satisfies the functional contract. It should not
    imitate XCOM's appearance or replace a suitable FuseFire asset.
13. **Have fun on purpose.** Prefer experiments that are satisfying to inspect,
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

## Borrowed placeholder checklist

Use this only for private local experiments:

- [ ] Store the copied asset under ignored `research/xcom-local/`.
- [ ] Remove or omit textures from copied reference meshes.
- [ ] Give the runtime placeholder an unmistakable `XCOM REFERENCE` label.
- [ ] Record its package/object or animation name in the
  [placeholder manifest](placeholder-manifest.md).
- [ ] State what question the placeholder is answering.
- [ ] Keep a release-safe FuseFire fallback available.
- [ ] Add a named replacement task describing the FuseFire asset Pedro needs to
  create: role, scale, contacts, modular boundaries, motion, and acceptance test.
- [ ] Verify that Git, exported builds, screenshots intended for publication,
  and release packages contain none of the borrowed data.

## Asset decision order

Before making a proxy, choose the first applicable path:

1. **Use FuseFire's existing asset.** MIRA-0, the AUG, current environments, and
   current animations remain in place when they can answer the experiment.
2. **Use a borrowed local placeholder.** A private XCOM animation or reference
   asset may temporarily expose behavior we need to understand; add it to the
   manifest and keep the release-safe FuseFire fallback.
3. **Create an original blockout.** Do this only when the experiment introduces
   a functional asset requirement that FuseFire does not yet have.
4. **Produce the FuseFire version.** Replace every borrowed placeholder with an
   original or properly licensed asset once its requirements are understood.
