# Planning before commitment

Milestone 04 step 9, 2026-11-17. Combat numbers and replay simulation rules are unchanged.

## Move

Choose Move, then hover a reachable cell. The blue route, translucent character and outgoing firing lines preview that destination. The hologram is a projected order: where the character would stand and the posture it would take. It uses the **same animation clips, weapon posing and idle/cover selection as the real unit**, evaluated at the destination. The path shows travel; the character previews the arrival posture. The projection spends nothing until you commit.

The panel shows movement AP and remaining AP, directional protection, normal incoming shot chances, outgoing chances and damage on hit. It explains Aim/Shield cancellation, missing AP or SP, and current enemy Shield/ammo restrictions. Incoming chances describe current positions/stances after arrival; enemies can change them. Guard can react along the route with its separate modifier.

By default, clicking commits the move immediately. **CANCEL MOVE** clears the planning preview without spending AP. In the optional movement-confirmation flow, the chosen destination freezes for review and Cancel returns to planning. Cancel operates before commitment; committed movement is not rewound.

## Shoot

Hover a hostile to inspect the firing line, physical blocker highlight, costs, fixed hit damage and accuracy breakdown. It includes base, strongest cover/exposure protection, range, height, Aim, Shield, raw chance, limits and final rounded chance. Attack mode plus a target click requests the shot; the default confirmation repeats those same facts before submission. Remaining AP/SP after the shot is shown too.

| Final chance | Color and label |
| --- | --- |
| 100% | Green — Guaranteed |
| 70–99% | Blue — Favorable, can miss |
| 40–69% | Orange — Risky |
| 0–39% | Red — Poor |
| Unavailable action | Neutral gray with its reason |

Numbers and words remain visible alongside color. A geometric firing lane with insufficient AP/SP stays neutral. A blocker is highlighted red using the existing nearest-obstruction/precise-part evidence. Friendly object names remain a later readability improvement; current blocker text can identify the highlighted cell.

## Confirmations

Pause exposes two independent, remembered preferences:

- **Confirm important actions**: on by default for shots, Aim, Shield, Skip and ending a turn with unused AP. Disable it to execute those choices directly. Guard retains its existing preview/Confirm step.
- **Confirm movement (two clicks)**: off by default. Enable it for destination review with large Confirm/Cancel buttons.

The dialog pauses gameplay and camera input. Cancel changes no AP, ammo, RNG or stance. Confirm resolves stable actor/target IDs and rechecks state before using the normal action service. Changed state or a removed target requires another review. Removing the battle closes its modal and releases its pause. AI/replay never open these player dialogs. Preferences live in `user://battle_ux.cfg`, outside battle/replay rules.

## Next reference check

**When the owner returns, ask for the GFL2 screenshot** and compare its destination hologram, stance, confirmation and large Cancel arrangement before further interaction polish. This is a saved follow-up, not a scheduled notification. The current projection is a prototype; custom action/traversal choreography and unrelated shader tuning remain separate.

[Verification](quality/combat-decision-previews-2026-11-17.md). Next milestone work is step 10: investigate and choose the scope of destructible cover, followed by balance and closure checks.
