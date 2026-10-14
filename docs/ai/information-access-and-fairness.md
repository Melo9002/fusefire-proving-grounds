# Information access and fairness

## What the AI reads

The tactical AI can directly inspect:

- every valid player, ally, and enemy unit in TurnManager rosters;
- exact faction, position, HP, AP, SP, movement speed, attack range, defeat state, capabilities, mission-actor role, carried-unit state, and tactical state exposed by those objects;
- the complete `MapData`, including every cell, cover property, elevation, traversal link, objective zone, terminal location, and occupancy entry;
- exact current objective definitions, progress, faction ownership, and mission actors;
- authoritative action-query results, including legality reason, hit chance, expected damage, cover, obstruction, Shield effect, AP/SP before and after, legal movement destinations, and paths;
- exact line-of-sight and hypothetical geometry from every candidate position;
- the round-scoped reservations made by earlier friendly AI units;
- its own four-entry movement history and low-value-action counter.

It does not inspect future combat RNG rolls, replay future actions, player input, or an opponent's future chosen path. Guard plausibility uses a range-plus-speed estimate rather than knowing where the hostile will move.

## Fog, discovery, and hidden information

The current game has no fog-of-war, concealment, detection, or hidden-enemy model. `_get_hostile_units()` reads all hostile roster entries without a visibility filter, but those units are also present on the battlefield rather than intentionally hidden from the player. Under the current Prototype 1.5 rules this is not a violation of an implemented information boundary because no such boundary exists.

This must be revisited if Goal 2 or a later milestone introduces rooms that hide occupants, undiscovered map areas, stealth, sensors, sound-only contacts, concealed objectives, or decoys. Adding visual occlusion alone does not create a gameplay visibility rule; the AI would continue to know every roster unit and objective location unless candidate generation is explicitly filtered.

## Symmetries

- Player and AI action execution use the same `TacticalActionService` query, validation, resolution, cost, RNG, reaction, and commit paths.
- AI Move candidates come from the same authoritative movement inventory available to player controls.
- Attack range, line of sight, cover, elevation-aware distance, Shield, Aim, AP, SP, Guard, conditions, and objective interactions use shared rules.
- Player-controlled and AI-controlled factions can use the same per-unit AI controller in AI-versus-AI mode.
- AI decision RNG is separate from combat RNG, so difficulty lapses do not consume or predict attack rolls.

## Asymmetries

The AI has computational access that a player normally receives only indirectly:

- it evaluates exact LOS, cover, incoming lanes, path costs, and exposure across every legal movement cell in one decision;
- it knows exact numerical hit chance and expected damage for every legal target query;
- it reads exact objective-zone cells and terminal approach geometry;
- it remembers squad reservations perfectly for the round;
- it can test whether a hostile has a legal attack against every friendly when calculating threat;
- it uses complete occupancy and hypothetical future-origin path queries.

The player can inspect much of this through previews, world state, and the F3 scoring tools, but ordinary play does not present the same exhaustive candidate comparison. This is a transparency and cognitive-bandwidth asymmetry, not currently a rules asymmetry.

The AI also has disadvantages:

- it has no multi-unit forward plan;
- it does not model expected enemy movement, reaction coverage along candidate paths, or future AP sequences beyond its immediate loop;
- target score ignores hit chance and expected damage even though diagnostics expose them;
- Guard plausibility can overestimate a trigger;
- it cannot reason about player psychology, sacrifice plans, or objectives beyond implemented mission intent;
- Easy and Normal deliberately choose near-best alternatives at seeded rates.

## Fairness conclusion

Within current rules, action resolution is fair and shared. Decision information is omniscient because the game itself currently has perfect information. The largest practical advantage is exhaustive calculation, while the largest AI disadvantage is shallow planning. Future hidden-information mechanics require a formal observable-state query before they are fair; merely hiding visuals from the player would create accidental AI omniscience.

## Questions for Goal 2

- Will entering a building reveal its interior and occupants, or will all battlefield units remain public?
- Are terminal and extraction locations always known at mission start?
- Should AI path planning know the complete generated layout, or only discovered connectivity?
- Should doors, destructible walls, hazards, or vertical entrances be known before observation?
- Should the player receive a compact version of the AI's exposure and firing-lane analysis outside debug mode?

These questions are unresolved. This audit does not recommend adding fog of war merely because more detailed battlefields are planned.

