# Operation XCOM research ledger

This ledger is the boundary between studying XCOM and changing FuseFire. Rows
capture sourced evidence and candidate rules. They do not authorize a feature or
make it permanent. Implementation belongs in a linked experiment note.

Evidence labels:

- **Observed:** directly visible in source, assets, tools, or recorded behavior.
- **Inferred:** a plausible explanation that still needs verification.
- **Tested:** reproduced and evaluated inside FuseFire.

## Candidate rule ledger

| ID | Observation and evidence | Hypothesis | Smallest FuseFire translation | Status | Experiment | Rollback notes |
|---|---|---|---|---|---|---|
| `OX-R001` | **Observed:** movement is represented through action classes such as `X2Action_Move`, `X2Action_MoveBegin`, and `X2Action_MoveEnd` under `Development/SrcOrig/XComGame/Classes`. | Tactical truth and presentation are easier to reason about when an action has explicit stages instead of one long mixed procedure. | Document FuseFire's action lifecycle, then test explicit validation, commitment, presentation, and completion boundaries on one action. | proposed | TBD | Retain the current gateway and remove the staged adapter if ordering, replay, or editing becomes less clear. |
| `OX-R002` | **Observed:** animation behavior is addressed semantically through XCOM animation nodes and action intent rather than scattered clip-name calls. | A small semantic animation contract could let MIRA-0, MIRA-00, humans, and drones map the same intent to different clips. | Give one presentation adapter named requests such as `idle`, `move`, `aim`, `fire`, `hit`, and `defeat`; keep mappings in an editable profile. | study | TBD | Remove the profile and restore the existing adapter mappings; gameplay never depends on the new names. |
| `OX-R003` | **Observed:** `X2Action_Fire`, cover actions, and animation nodes coordinate meaningful moments during an action. | Named presentation events could place muzzle flashes, impacts, sounds, and camera beats more reliably than raw delays. | Test authored event markers for one firing presentation while preserving immediate deterministic combat resolution. | study | TBD | Fall back to current timing values; event markers remain presentation-only. |
| `OX-R004` | **Observed:** XCOM presents actions as selectable, previewable, confirmed, and then committed. Exact cancellation rules still need targeted study. | An explicit commitment boundary can allow safe cancellation without making authoritative actions reversible halfway through mutation. | Define `selected → previewing → confirmed → committed → presenting → completed`; initially allow cancel only before `committed`. | proposed | TBD | Keep current click-to-execute behavior if the extra states confuse input or duplicate existing selection state. |
| `OX-R005` | **Observed:** camera classes such as `X2Camera_OverTheShoulder` and `X2Camera_FrameAbility` frame action context through specialized camera requests. | FuseFire may gain clearer cinematics if actions provide context and a director chooses a camera, rather than actions owning camera motion. | Extend the existing action-camera request with subject, target, action type, importance, and valid framing candidates. | study | TBD | Keep the existing action camera director API and discard unused context fields. |
| `OX-R006` | **Observed:** `XGAIBehavior` separates high-level behavior concerns from individual presentation actions. Detailed scoring and mission coordination still require study. | Separating intent selection from spatial execution may make rescue behavior explainable without building a large general AI framework. | On one rescue decision, log mission intent, tactical intent, candidate action, spatial score, and final reason as distinct fields before changing behavior. | proposed | TBD | Remove added trace fields if they do not explain decisions; do not change AI scoring during the observation experiment. |

## Open questions

- At what exact point do XCOM movement and attacks stop accepting cancellation?
- Which animation events are gameplay-significant, and which only synchronize
  presentation?
- How are weapon grip, stock contact, cover poses, and aim offsets divided among
  animation assets, IK, sockets, and runtime correction?
- What information does a camera request receive, and who restores the tactical
  camera after interruption or cancellation?
- Which AI structures solve general tactical reasoning, and which are highly
  specific to XCOM missions, content, or Unreal conventions?

Add evidence before answers. When a question becomes actionable, create a small
experiment rather than expanding this ledger into an implementation document.
