# Navigation walkthrough

Source: [main controller](../ServerScriptService/maze%20agent%20controller%20%28server%29.luau)

One source owns navigation, physical setup, probes, wall effects and replay. It keeps shared map observations separate from private rig routes and from the physical maze used to select valid starts

| Functions | Reason for the boundary |
| --- | --- |
| newgrid, coordinates, cellat, neighbors | Bounded numeric cells prevent row wrapping and keep the same four-way grid everywhere |
| push, pop, newsearch, stepsearch | The heap serves both route frontiers and deadlines; each search can pause between charged pops |
| worldpoint, cellfromworld, readcell | Floor-space conversion keeps commands and body queries on the same centers |
| spawnpoints, setup, draw | Physical spawn reachability stays outside the learned map; probes illustrate clearance and peer messages |
| publish, refresh, sense | Fresh checked evidence reaches the shared map before selective replanning or HUD notices |
| compatible, searches, adopt | A finished result still needs current start, generation and observation compatibility |
| witnesses, update | Sharing and shortcuts need actual route changes and physical traversal |
| worldchanged, footprint, updatedebris | A disappeared wall is insufficient while debris or another part still blocks the opening |
| selectwalls, warnwall, release, effects | Explicit phases and generation-owned deadlines retain warning, launch, landing and fade behavior |
| pause, reset, stop | Movers stop before walls return; final teardown releases producers and owned resources |

## Knowledge and search

An absent map record means unknown. Checked clear records cost 1 to enter, unknown cells cost 1.15 and blocked cells cannot be entered. Manhattan distance is a lower bound because each four-way move costs at least 1

`discover` replaces changed records and advances the revision. A search shallow-copies the map table, so immutable records give it a fixed belief snapshot while other rigs keep sensing. Parent links reconstruct the cheapest route under that snapshot, not under undiscovered physical geometry

Improved cell prices add new heap entries. Stale entries are skipped after being charged to the work allowance. Dispatch rotates through eligible rigs, spends at most 1024 pops in slices of 128, and checks a three-millisecond elapsed deadline. That is a cooperative bound, not a hard frame-time guarantee

Changed anchors or replay generations cancel obsolete jobs. Completed jobs check whether newly blocked cells touch their route or newly clear cells could beat its price. The Manhattan lower bound rejects irrelevant openings; promising ones still need an actual search. Accepted routes are repriced against current knowledge

A focus opening can request a second search on the same snapshot with that passage closed. This supplies a valid detour comparison when the previous route is no longer usable. Both jobs use the same scheduling allowance

## Movement and probes

The reached `anchor` differs from the commanded `target`. Replanning from reached centers avoids treating a halfway position as a safe diagonal shortcut. Arrival, progress and bounded recovery use actual root positions; refreshed MoveTo commands do not restart stall clocks

One shared `__index` table supplies startturn, stopturn, drive and retire methods. Each rig keeps its own routes, evidence, clocks and owned instances. A finite mass-scaled AlignOrientation controls facing while Humanoid:MoveTo owns translation. Cleanup restores the exact saved AutoRotate boolean

Each rig owns seven probe directions with six dots per direction and three-ray clearance checks. Green marks a useful direction and cyan pulses mark received peer knowledge. These are presentation cues; body overlap queries supply navigation observations

The overlap box is 2.6 by 4.6 by 2.6 studs. Agents and the maze floor are excluded, and collision rules match the agent group so low collidable debris remains visible to navigation

## Collapses and replay

Eight seeded selected walls retain boundary, goal, spawn and spacing exclusions. Three warning pulses lead to twelve chunks in three release layers and eighteen fragments per wall. Physical landing, fading and cleanup remain separate scheduled work

The server BindableEvent carries warning, falling and cleared phases with owner identity, wall ID, revision, position and copied part lists. Validation rejects wrong owners, stale phases, invalid geometry and false clearance while a collidable piece survives

Collapse IDs hold cell gates independently. Rotated debris bounds plus the body margin determine which cells need fresh queries, including cells the debris has vacated. An opening is only usable after those physical checks

The demonstration requires a real shared route change and a cheaper route through the opening. Crossing is recorded from distinct entry and exit neighbors. Staged starts and a focus wall make these witnesses visible without supplying a waypoint route to the planner

Replay pauses movers before restoring captured wall templates, advances the generation, clears delayed work and learned observations, and rebuilds private rig resources. Ready viewers remain registered; the current JSON snapshot gives late viewers the current explanation

## Lifetime and clients

The same source is cloned into `maze guardian`, a second runtime Script in ServerScriptService. Its private server shared record names the controller and its idempotent stop function. Polling from this independent context survives deferred controller destruction; after cleanup it drops the record and destroys itself. No Source read or runtime Source rewrite is involved

The existing HUD and freecam remain client scripts. The remote accepts only readiness from actual connected players; it does not accept routes or map edits. The guardian is server lifetime machinery, not client authority or an authored module dependency

The observed full cycle and two-client tests are linked in [the test notes](../tests/readme.md). Those results cover copied assets from place version 49 and do not establish cloud publication, larger loads or arbitrary terrain support
