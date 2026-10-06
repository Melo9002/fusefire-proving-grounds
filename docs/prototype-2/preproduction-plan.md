# 🔥 FuseFire — Pre-production Workshop

> **Purpose:** decide what the next prototype should prove before giving it a
> version number, feature list, or release promise.

The Idea Vault preserves possibilities. This workshop turns those possibilities
into questions, cheap proofs, and informed decisions. It is deliberately allowed
to produce **Prototype 2, several smaller prototypes, or no implementation at
all for a particular idea**.

Prototype 1 remains the behavioral baseline. Experimental work must happen on a
separate branch or in isolated scenes/resources, and it must not quietly change
the released `v1.0.0` project.

## 🧭 The four destinations for an idea

| Destination | Meaning | Required result |
|---|---|---|
| 🛠️ **Proof now** | Small, reversible work can answer an important question | A runnable proof, notes, and a keep/change/stop decision |
| 💬 **Design first** | The player-facing decision is still unclear | A short decision record with examples and rejected alternatives |
| 🔬 **Research first** | We need outside references, technical evidence, or asset inspection | Findings, source/license notes, risks, and a recommendation |
| 🧊 **Park** | Valuable, but it would distract from the next useful proof | A preserved idea and a clear trigger for reconsidering it |

None of these labels means “promised feature.” Even **Proof now** means “learn
now,” not “ship forever.”

## 🟢 Work we can begin now

These tasks improve our ability to experiment without committing us to a large
game design. They also support the MIRA-0 work already in progress.

### W0 — Protect the successful prototype

**Ideas supported:** every future experiment  
**Destination:** 🛠️ Proof now  
**Why now:** every experiment needs a trustworthy comparison point.

- [x] Record the exact P1 release tag and protected invariants in each experiment.
- [x] Keep experiments off `main` until their behavior and removal path are understood.
- [x] Define a tiny regression checklist: pause, replay, deterministic seed,
  diagonal movement, AI turn completion, rescue/extraction, and Compatibility mode.
- [x] Give each experiment a reusable note and its own folder or scene when practical.
- [x] End every experiment with **adopt**, **revise**, **archive**, or **discard**.

**Done when:** a contributor can experiment without wondering whether a result
silently broke Prototype 1.

### W1 — MIRA-0 asset intake and first clean round-trip

**Ideas:** MIRA-01, MIRA-02, MIRA-03, MIRA-05; prepares MIRA-04 and MIRA-07  
**Destination:** 🛠️ Proof now  
**Question:** can one real FuseFire character travel from Blender to Godot, use
one edited animation, and return for revision without code surgery?

- [ ] Inventory the current MIRA-0 source files, mesh objects, materials, rig,
  actions, scale, forward axis, and known unfinished areas.
- [ ] Choose the canonical editable source and preserve an untouched backup.
- [ ] Compare its skeleton with the current gameplay animation expectations.
- [ ] Write the smallest provisional bone contract needed for one locomotion clip.
- [ ] Export one model and one animation into an isolated Godot test scene.
- [ ] Validate height, feet, root motion policy, facing, looping, and deformation.
- [ ] Edit the clip, re-export it, and confirm that the update does not require
  shared gameplay-script changes.
- [ ] Record every manual import step that should later become a preset or tool.

**Stop condition:** one model/clip round-trip works and its awkward parts are
known. Do not finish the whole animation library during this proof.

### W2 — Character presentation profile spike

**Ideas:** MIRA-03, MIRA-04, MIRA-07; later supports MIRA-06  
**Destination:** 🛠️ Proof now, after W1 reveals real data  
**Question:** what must vary per body or model without infecting gameplay code?

- [ ] List current per-character assumptions: scene, height, camera anchor,
  weapon sockets, muzzle, IK contacts, clips, offsets, materials, and team accents.
- [ ] Separate facts owned by the model from temporary correction values.
- [ ] Sketch one small Godot resource/profile containing only proven variation.
- [ ] Make MIRA-0 use it in the isolated test scene.
- [ ] Attempt a deliberately crude second profile to expose hidden assumptions.
- [ ] Reject fields that exist only because they “might be useful someday.”

**Stop condition:** replacing the test character is understandable from the
Inspector and does not require editing unrelated combat or mission scripts.

### W3 — Modular graybox kit experiment

**Ideas:** MAP-01, MAP-02, MAP-04, TOOL-04, TOOL-05, EXT-01  
**Destination:** 🛠️ Proof now, kept outside production maps  
**Question:** can authored and generated battlefields use the same small set of
pieces without making either workflow miserable?

- [ ] Record the exact Prototype Texture version, license, source, and removal path.
- [ ] Import it into an isolated experiment area rather than replacing P1 materials.
- [ ] Build 5–10 crude pieces: floor, wall, corner, doorway, ramp/stair, platform,
  railing/edge, and one obstacle.
- [ ] Add only metadata required by an actual placement: footprint, traversable
  cells, cover, connectors, elevation, and clearance.
- [ ] Hand-author one tiny encounter from the pieces.
- [ ] Assemble a second tiny layout with the simplest useful placement script.
- [ ] Run reachability, spawn, objective, LOS, and camera-readability checks.
- [ ] Compare authoring time, repair work, visual coherence, and metadata burden.

**Stop condition:** we can explain whether a shared representation helps. A
finished map editor is explicitly outside this experiment.

### W4 — External-resource ledger

**Ideas:** EXT-01 through EXT-05; supports all production work  
**Destination:** 🔬 Research now  

- [ ] Create one entry per candidate with URL, author, exact version, license,
  engine/tool compatibility, last activity, and attribution needs.
- [ ] State the concrete labor it saves.
- [ ] Record runtime/editor coupling and export risk.
- [ ] Describe how to remove or replace it.
- [ ] Mark it **adopt**, **adapt**, **study only**, or **reject**.

**Done when:** using a plugin or asset is an explicit engineering decision rather
than an invisible dependency.

The living ledger is [`external-resources.md`](external-resources.md). Prototype
Texture is its first concrete experiment; the remaining entries stay conditional.

### W5 — Define the next playable slice

**Ideas sampled:** MIRA-01/03/04/05/07, MAP-01/02, COM-01/02/03, PRE-06,
AI-04/11, TOOL-05/06  
**Destination:** 💬 Design now  
**Question:** what small battle would prove that the rectangles are becoming
FuseFire while retaining what made P1 fun?

- [ ] Describe one 10–15 minute mission in plain language.
- [ ] Select one proper MIRA body, two contrasting weapons, one modular map,
  one familiar objective, and complete audiovisual feedback.
- [ ] State what the player should learn and feel.
- [ ] List reused P1 systems and the minimum new behavior.
- [ ] Define success using observable play rather than number of systems built.
- [ ] Decide whether this becomes Prototype 2 or merely the first laboratory build.

**Stop condition:** the slice fits on one page and has an obvious “done.”

## 🧪 Incubation work packages

Each package contains ideas with a shared question. We open one only when its
entry condition is met; we do not run the entire table as a sequential roadmap.

| Package | Ideas | Destination now | First tasks | Entry condition |
|---|---|---|---|---|
| **Character foundation** | MIRA-01–07 | 🛠️ W1/W2, then 💬 | Prove MIRA-0 round-trip; derive skeleton/profile/socket rules; test team materials | MIRA-0 source is ready enough to export |
| **Body families** | MIRA-06, MIRA-08–10 | 💬 / 🧊 | Decide what a second body must share; distinguish cosmetic parts, gameplay parts, and damage parts | One body works cleanly and MIRA-00 has a gameplay reason |
| **Battlefield language** | MAP-01–06, TOOL-04/05 | 🛠️ W3 | Compare one authored and one assembled map; validate actual traversal metadata | Isolated graybox kit exists |
| **World framing** | MAP-07–11, PRE-01/02 | 🔬 / 💬 | Choose one dense scene; study boundary, obstruction, cutaway, roof, and destruction costs separately | Denser maps create a demonstrated readability problem |
| **Combat identity** | COM-01–08, PRE-06 | 💬, then 🛠️ | Choose two weapon fantasies; specify accuracy language and one equipment-granted action; build one end-to-end shot | W5 names the battle and desired decisions |
| **Advanced combat** | COM-09–17 | 💬 / 🧊 | Give each mechanic a decision, counterplay, AI burden, feedback, and cheaper alternative before prototyping | Base weapon language is stable |
| **Simulation foundations** | AI-01–05, AI-08, AI-11, AI-14 | 💬 / 🔬 | Map faction/controller assumptions; preserve explainable scoring and deterministic AI-vs-AI cases | A new scenario proves P1 assumptions insufficient |
| **Coordination and personality** | AI-06/07/09/10/12/13/15 | 💬 / 🧊 | Define two roles in the same state; describe shared information, mistakes, deadlock recovery, and rescue-specific limits | Shared evaluator and objective semantics are understood |
| **Camera and UI** | PRE-01–05, PRE-08 | 🔬 / 💬 | Capture concrete obstruction/UI failures; storyboard desired information and camera behavior before editing systems | W3/W5 provides representative environments |
| **Mission memory** | PRE-07, LIFE-01–06 | 💬 / 🧊 | Mock one mission photo and one short MIRA reaction; decide what state must persist | A stable battle presentation provides usable subjects |
| **Recon and campaign** | CAM-01–09, LIFE-07 | 🧊, with paper design allowed | Describe information decisions on paper; test a tiny deterministic loop before real-time exploration | Tactical/content production no longer dominates uncertainty |
| **Production tools** | MAP-03, TOOL-01–08 | 🛠️ only when demanded | Build the smallest validator, overlay, or importer that removes measured repeated work | At least two real pieces of content reveal repetition |
| **Relics and content pool** | RELIC-01–05, weapon candidates | 🧊 / curate | Preserve artifacts intentionally; select archetype representatives instead of implementing the catalog | A museum/cheat surface or content brief exists |

## 🧩 The task card used for every individual idea

Before implementing any vault entry, copy this card into an experiment note or
decision record. This is the “set of tasks” every idea receives, including ideas
that never become code.

```markdown
## ID — Idea name

**Problem:** What player, creator, or engineering problem does it solve?
**Why now:** What evidence makes this timely?
**Destination:** Proof now / Design first / Research first / Park
**Dependencies:** What must already be stable?
**Prototype:** What is the smallest honest test?
**Non-goals:** What tempting adjacent work is excluded?

### Tasks
- [ ] Gather examples, current behavior, and constraints.
- [ ] Write the player-facing or creator-facing rule in plain language.
- [ ] Identify affected P1 invariants and regression checks.
- [ ] Build or mock the smallest proof in isolation.
- [ ] Observe it in a representative scenario.
- [ ] Record content cost, technical cost, and newly discovered dependencies.
- [ ] Decide: adopt, revise, split, archive, or discard.

**Acceptance evidence:**
**Removal path:**
**Decision:**
```

## 📋 Idea disposition board

This is the quick answer to “what do we do with every idea?” Detailed tasks live
in its work package and eventual task card.

| Family | Proof now | Design first | Research first | Park until triggered |
|---|---|---|---|---|
| Battlefield | MAP-01, MAP-02, MAP-04 | MAP-03, MAP-05, MAP-06, MAP-08 | MAP-07, MAP-09, MAP-10 | MAP-11 |
| Presentation | — | PRE-03–08 | PRE-01, PRE-02 | — |
| MIRAs | MIRA-01–05, MIRA-07 | MIRA-06, MIRA-08, MIRA-09 | — | MIRA-10 |
| Combat | — | COM-01–10, COM-13–15, COM-17 | COM-11, COM-12, COM-16 | — |
| AI | — | AI-01–14 | AI-15 | — |
| Recon/campaign | — | CAM-04 | CAM-03, CAM-05 | CAM-01, CAM-02, CAM-06–09 |
| MIRA life | — | LIFE-01, LIFE-02 | LIFE-07 | LIFE-03–06 |
| Tools | TOOL-04, TOOL-05 | TOOL-06–08 | — | TOOL-01–03 already exist in useful P1 form; extend only from need |
| External resources | EXT-01 experiment | — | EXT-02–05 | — |
| Archaeology/content | — | Choose representative weapon archetypes | — | RELIC-01–05 and the unused content pool |

“Design first” is intentionally broad. Its first implementation task is to write
and discuss the rule; it is not permission to build the whole system.

## 🚥 Choosing what follows W0–W5

Score a proposed proof from **0–2** in each column. This is a conversation aid,
not an automatic design machine.

| Criterion | 0 | 1 | 2 |
|---|---|---|---|
| Makes FuseFire recognizable | Barely | Supports the identity | Defines the identity |
| Enables Miku vs. Teto | Unrelated | Helpful | Required |
| Answers a risky question | Little learning | Useful evidence | Resolves a major uncertainty |
| Reuses P1 safely | Threatens foundations | Manageable | Exercises foundations cleanly |
| Content burden | Large/unknown | Moderate | Small and bounded |
| Reversibility | Entangled | Removable with work | Isolated and disposable |

A high score earns discussion and a task card. It still does not automatically
earn implementation.

## 🗓️ Suggested first workshop session

1. Preserve W0's regression checklist.
2. Fill the W1 inventory together from the actual MIRA-0 Blender file.
3. Write W5's one-page playable-slice brief while the asset imports are tested.
4. Start W4 with Prototype Texture as the first ledger entry.
5. Choose the next proof using evidence from those three activities.

This gives us useful work today while leaving room for the next prototype to
discover what it actually wants to be.

---

*Incubation is allowed to kill ideas. The vault keeps their ghosts comfortable.* 👻🫘
