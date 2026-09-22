# Navigation walkthrough

Source: [main navigation script](../ServerScriptService/mazeagentcontroller%20%28server%29.luau)

Line references below match the submission overhaul

## Overview

> The agents share one map on the server, but that navigation map starts without the walls filled in
>
> Each agent checks nearby cells, then A* plans using whatever the group has learned so far
>
> A new blockage only asks for another plan when it affects the remaining route, while a reopened cell is checked for whether it could make the route cheaper
>
> The collapse controller handles the physical wall, and the navigation controller decides when the opening is usable

## Reading order

| Main script lines | Read for | Main point to explain |
| --- | --- | --- |
| 13-48 | Grid and four-way neighbors | One numeric cell ID per tile; bounds prevent row wrapping |
| 50-90 | Binary min-heap | Pop the lowest estimated total cost without sorting the whole frontier |
| 92-102 | Discovery and revision | Repeating the same observation does not invalidate routes again |
| 105-172 | A*, route reconstruction and costs | Plan from partial knowledge and compare the remaining route |
| 175-277 | Roblox adapter | Convert between floor-relative cells and world positions |
| 279-370 | Shared discoveries and sensing | Keep decision-making on the server; use body-space overlap checks |
| 372-468 | Plan comparisons and demo evidence | A notification alone is not counted as a route change |
| 470-599 | Movement and recovery | Plan from reached cell centers and bound stalled recovery |
| 601-737 | Debris and collapse events | Check physical clearance, event order and current-run identity |
| 739-869 | Cleanup and scheduler | Disconnect work on teardown and cap searches per update |

## 1. How the map represents knowledge

`map.cells` has three useful meanings: no entry means unknown, an entry with `blocked = false` means checked clear, and `blocked = true` means blocked. Every agent's plan reads the same table. They do not exchange separate copies of an entire map, and there is no cross-server memory. Each replay starts with fresh navigation knowledge.

`discover` only increments the revision when a cell's known state changes. `publish` then checks which agents are affected and marks their plans dirty. The revision is an observation counter; it is not a separate pathfinding algorithm.

`sense` learns the reached cell and its four neighbors. `readcell` queries a 2.6 × 4 × 2.6 stud body space, with the agents excluded and collision rules matched to their group. The visible raycast probes belong to `mazerigs.draw`; they illustrate direction and clearance, while the grid overlap query supplies navigation discoveries.

The setup module does inspect the authored maze to choose reachable spawn positions. That setup information is not copied into the navigation map. Spawn selection and navigation knowledge have separate responsibilities.

## 2. Why A* uses these costs

The cost already travelled is stored in `costs`. The heap score adds Manhattan distance to the goal. A known clear cell costs 1; an unknown cell costs 1.15. Blocked cells are skipped.

The extra 0.15 is a small preference for checked passages, not a measured probability of danger. Unknown cells must remain searchable, otherwise the agents cannot explore beyond their first observations.

Manhattan distance is suitable for this four-way grid: each move changes one coordinate by one and costs at least 1. Ignoring obstacles and the unknown-cell surcharge gives a lower bound, so the estimate does not overstate that remaining grid cost. Adding diagonal moves would require changing both movement rules and the estimate.

The binary heap orders the frontier by score. An improved route to a cell adds another entry rather than editing an older heap entry. When an older entry is popped, its stored cost is compared with the current best cost and stale entries are skipped. Parent pointers reconstruct the final route in reverse, then the route is reversed for movement.

A* finds the cheapest route under the current knowledge and cost model. It cannot guarantee the shortest route through walls it has not discovered. The current grid also assumes this authored flat, eight-stud-tile maze; this is not a general navigation system for arbitrary terrain, stairs or jumping.

## 3. What actually changes another agent's route

The discovery is written to the shared map before any HUD notice. An agent is marked dirty when a new blockage appears on its remaining route. An opening can also trigger a check when its best-case distance might beat the remaining cost, or when an agent is waiting without a route.

`couldshorten` is only an inexpensive rejection check. A promising opening still requires a real search. `plan` compares the new result with the old route's remaining cost and keeps the old valid route if the opening does not improve it. Pending openings are kept in a set so one discovery cannot overwrite another before planning consumes it.

HUD notices are throttled separately from map changes. Suppressing a repeated visual message does not suppress the discovery or the agent updates.

For the demonstration, `recordshared` checks that the route really changed, that the discovered blocked cell was on the old route, and that it is absent from the new one. It also checks the receiver is at least two grid edges away for the staged shared-change event. A cyan pulse by itself is not proof of rerouting.

## 4. Why movement needs an anchor

`anchor` is the last reached cell center. `target` is the cell currently being approached. Replanning from an arbitrary position halfway between centers could produce a diagonal cut across a wall corner, so recovery first returns toward the anchor.

Movement commands go through `drive`, which calls `Humanoid:MoveTo`. The controller checks horizontal distance to the target rather than treating the command itself as arrival. It permits a 1.1-stud arrival tolerance for the rig.

There are two stall checks: 1.5 seconds without enough progress, or 2.5 seconds overall on a movement attempt. Reissuing the command every 0.5 seconds does not reset those timers. Recovery attempts are limited, and a rig that cannot recover enters `stopped`. A shoved rig's candidate cell must fit its body query before it is accepted as a new anchor.

| State | Meaning |
| --- | --- |
| queued | Waiting for the configured start delay |
| planning | Ready for a search when the shared budget permits |
| moving | Travelling toward the next planned cell |
| recovering | Returning to a usable cell center |
| waiting | No route was found; retry sensing after a delay |
| observing | Temporary pause for the staged collapse demonstration |
| arrived / stopped | Finished successfully / retired after failure or removal |

## 5. Why a destroyed wall is not immediately a passage

The collapse script replaces the wall with physical debris. Removing the wall's original part does not establish that a humanoid can fit through the opening.

The controller receives `warning`, `falling` and `cleared` phases through a server-side BindableEvent. Each payload names its owning debris folder, wall ID, position, revision and fragment list. Folder identity distinguishes runs even if the replacement folder has the same name. Repeated or older phases cannot replace the latest phase for that wall.

The source cell stays gated during an active collapse. Gates are held by collapse ID, so clearing one hold does not remove another. Falling fragments also have a calculated footprint: their rotated half-extents, expanded by the body half-width, identify nearby grid centers worth rechecking. This footprint is a conservative query area, not an exact mesh collision solver.

On a clear event, both the previous and incoming fragment lists are checked for surviving collidable pieces. The affected body spaces are then queried again. This catches another obstruction behind the cleared debris. When debris moves, both its new cells and the cells it vacated are refreshed.

## 6. How the demo proves the shortcut

The first wall, three starting cells, start delays and runner pause are intentionally staged to make the interaction visible. They do not supply a waypoint route to A*. The group still discovers cells, searches and moves through the normal controller.

`recordopenings` requires a cheaper route through a newly opened cell. The special demo check also requires fewer grid moves, so merely reducing the 1.15 unknown-cell penalty cannot produce the 31-to-19 claim.

`recordcrossing` runs when a target is reached. It records the entry side and only completes the example after the runner leaves the opened wall cell through a different neighboring cell. Touching the opening and turning back fails this check.

In the saved Studio run: Maze Dummy 04 supplied the discovery, Maze Dummy 02 changed route and traversed the shortcut, the opening cell was 1262, and the entry/exit cells were 1221 and 1303. The remaining route dropped from 31 grid moves to 19. These are results from that Studio run, not guaranteed wall-clock timings for every live server.

## 7. Server ownership, workload and cleanup

Search, shared map updates, movement and collapse handling run on the server. `maze_world_changed` is a BindableEvent in ServerStorage; `maze_knowledge_event` is a RemoteEvent used to display server messages on clients. The HUD is not an input source for navigation decisions.

The controller updates at a configured interval of 0.16 seconds and permits at most two searches per update. This limits how many searches start together; a single search still runs synchronously. It does not provide a hard CPU-time budget or establish performance at hundreds of agents. The tested workload was 15 agents.

`stop` first marks the controller inactive, then disconnects its stored connections, retires agent states and clears navigation tables. `mazerigs.watch` supplies the owner-removal callback from the module's lifetime. The module's watcher itself remains a module-owned connection; this is not a claim that every connection in the place disappears when the controller is removed.

## 8. What reduced nesting means here

Nesting is how many control blocks a reader must stay inside at once. The main script uses early returns and `continue` for invalid or irrelevant cases, then keeps the useful path at a shallower indentation level. Arrival checks, recovery, route comparison and event validation have named functions with separate responsibilities.

Examples to point to are `publish` at line 279, `maintainmove` at line 507, `update` at line 561 and `worldchanged` at line 667. Some nested loops are still appropriate, such as visiting x/z cells in a debris footprint. The support module also retains nested setup code. Nested iteration remains where the work needs it.

## 9. Viewer readiness and repeatable demonstrations

The HUD subscribes to `demosnapshot` before reading its current value. That single JSON attribute carries a message, kind and increasing serial together, so an already-running server can show its latest demo state to a new viewer. Older or repeated serials are ignored. Ordinary notices continue through the RemoteEvent.

After its labels and listeners are ready, the HUD sends `ready` through `maze_knowledge_event` until the server acknowledges that player. The server accepts only that exact action and records each connected player once. Repeated requests return before triggering any work. Departing players are removed from the ready set. A client cannot request a route, change the shared map or restart the demonstration through this handler.

The first movement countdown begins when at least one viewer is ready. Once started, the current cycle continues normally for other viewers. A late client gets its camera from `demofocus`, which persists after the wall is destroyed. The camera is framed once, so later cycles do not override someone manually looking around.

After the selected collapses and agent completion, or the 240-second completion deadline, the collapse controller asks the navigation controller to stop any remaining movers. Following a 15-second pause, it restores only the selected walls from their original templates and replaces the debris folder. The server sends a reset message carrying that new folder as the generation token. The navigation controller clears routes, gates, blockers and learned cells, resets the rig setup and starts the next cycle with ready viewers already registered.

Reset messages from another folder and duplicates for the same folder are ignored. Fragment callbacks remember their original folder, so the previous cycle cannot announce clearance for the replacement cycle. Old demo timestamps are cleared before seeding the new agents, preventing an earlier clearance time from releasing the new runner too soon.

The acknowledgement and snapshot contain presentation state, not evidence of applicant identity or authorship.
