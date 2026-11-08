# Battlefield polish

## Service Depot playtest

Use Service Depot, seed `66566043`, two units per side and Eliminate. The supplied recording contains 62 actions and finishes in victory. Its exact manifest uses compiler revision 1.

- After action index 24, the shot from `(18, 0, 13)` to `(22, 0, 14)` was blocked by the delivery truck's cell-sized obstruction. After index 43, the shot from `(22, 0, 14)` to `(24, 0, 22)` was blocked by the warehouse corner. Each of the five shot samples missed the corresponding imported mesh in both cases.
- New battles use compiler revision 2. The loading parcels' authored rectangular solids clip shot obstruction within occupied cells. A shot through the truck still hits its obstruction. Movement, stopping and directional cover retain their cell contracts. Revision 1 replays keep the original obstruction because the change can alter attack odds and Guard reactions.
- EnemyUnit2 had 72 legal movement destinations before its recorded Wait at index 38. The recorded decision rejected 49 as outside its preferred route corridor and 23 as below its move score threshold. It subsequently aimed and attacked. Retain this case for evaluating AI willingness to flank and leave cover, including how quickly it should relax its threshold after repeated passive turns.
- Dark red tiles indicate committed enemy Guard. Purple indicates friendly Guard or the brighter pre-commit preview. Shared coverage blends the two committed tints. Move and Attack previews take priority over committed Guard on the same cell and floor. Tiles communicate potential reaction coverage. Attack legality depends on the selected unit, target, range, resources and target exposure. A disabled Attack button lists the hostile targets' rejection reasons.
- Remaining asset authoring issue. A solid box can reserve flat ground beyond the visible walls, especially when a building asset includes a planter, step or other low detail. The loading-parcel sightline fix clips obstruction to the authored box and retains the movement reservation. Review similar assets by separating the wall or shell from low details and keeping adjacent open ground walkable. Give each authored part its own movement, cover and sightline contract, and verify each in gameplay.

## AI frame pacing

On this depot state, checking hypothetical routes for all 72 reachable destinations took about 180 ms in a headless probe. The isolated route loop includes candidates the live scorer can reject before querying a route. Repeating an in-range shot evaluation 120 times took about 573 ms before narrowing the candidate cells to the ray corridor and about 22 ms afterward. These are CPU probe measurements from one battlefield state.

Movement scoring yields between candidates after a 5 ms work slice. Candidate ordering and RNG consumption follow the same sequence. A single path query can overrun a slice. Animation and the intentional activation/action holds have their own timing. For further profiling, record the longest frame during enemy movement, a shot and a Guard reaction in a normal rendered battle. Separate path scoring, presentation, rendering and the intentional holds before changing turn pacing.

## Cinematic replay

Try both shoulders and a higher angle when a cinematic subject is obscured. Candidate checks include terrain collision and registered static visual bounds. If the selected view is still obstructed, hide the registered visual meshes between the lens and actor and restore them when the sightline clears or the shot ends. This is presentation only. Bounds approximate open meshes, so check overhead decks, open frames and shots with two actors in frame during camera polish. A completed cinematic replay returns to the tactical view for the results screen.

Replay Save As owns keyboard and pointer input while open. The battle pauses to stop camera controls that poll keys every frame, then resumes its previous pause state when the dialog closes.
