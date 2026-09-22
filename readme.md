# PathfindPractice

**One learns. All know.** A Roblox maze demonstration where 15 agents share discoveries, change their routes, and use passages opened by collapsing walls

[Read the main script](ServerScriptService/mazeagentcontroller%20%28server%29.luau) · [Play the demo](https://www.roblox.com/games/113425488924507/PathfindPractice) · [Code walkthrough](docs/navigation.md)

## start here

The main example is **mazeagentcontroller (server).luau** — one 878-line script with 730 nonblank, noncomment code lines
It contains the grid search, shared map, replanning, movement recovery and collapse-event handling
The other files support the authored rigs, wall physics, HUD and camera

For a direct code-file link, use [mazeagentcontroller on GitHub](https://github.com/Lukako-zabijak/roblox-shared-maze-systems/blob/main/ServerScriptService/mazeagentcontroller%20%28server%29.luau)

## watch the demonstration

Join on desktop — the camera frames the first example even if its wall has already collapsed

1. **A discovery is shared** — Maze Dummy 04 finds a wall, and Maze Dummy 02 changes its planned route before reaching the blockage
2. **The wall collapses** — the runner pauses while the marked wall flashes orange and breaks into physical debris
3. **The opening becomes usable** — navigation keeps the passage blocked until the debris clears, then compares routes through it
4. **The runner takes the shortcut** — in the recorded Studio run, the remaining route fell from **31 grid moves to 19**, and the runner crossed the opened passage
5. **The full maze continues** — the other agents head toward the goal while the remaining selected walls collapse

The first run waits until a viewer's HUD is ready, then gives the first three agents a five-second countdown
The background agents start later

**The demonstration repeats automatically** after the full run and a 15-second pause
The changed walls, agent positions and shared navigation knowledge are restored for the next cycle
If you arrive halfway through, the HUD loads the current demo status and you can watch the next cycle without changing servers
A run has a 240-second completion deadline after startup so a stuck agent cannot prevent replay indefinitely

The first wall, starting positions and pause are staged so the interaction is visible
Routes are still calculated by the planner at runtime, and the completion event requires an actual crossing rather than just a changed route or HUD message

### camera controls

| Input | Action |
| --- | --- |
| W / A / S / D | Move the freecam |
| E / Q | Move up / down |
| Hold right mouse and move | Look around |
| Hold middle mouse and move | Pan |
| Mouse wheel | Move along the viewing direction |
| Shift / Ctrl | Move faster / slower |
| F3 | Toggle between freecam and the player camera |

The current viewing controls are built for keyboard and mouse

## how it works

| Component | What it does and why |
| --- | --- |
| Partial shared map | Agents learn their current cell and four neighbors, then write discoveries into one server-owned map so peers can react before reaching the same obstacle |
| A* with a binary min-heap | Searches a four-way grid using Manhattan distance; known clear cells cost 1 and unknown cells cost 1.15, giving checked passages a small preference |
| Selective replanning | A blockage invalidates affected remaining routes; an opening first passes a distance check, then a real search decides whether it improves the route |
| Movement states | Keeps the last reached center separate from the current target, with progress checks and limited recovery attempts when a humanoid stalls |
| Collapse phases | Checks warning, falling and cleared updates against their revision and owning debris folder, rejecting old or repeated updates |
| Debris clearance | Rechecks the space an agent's body needs, including cells covered or vacated by moving fragments |
| Shared search budget | Starts at most two searches per controller update, on a 0.16-second interval; this is a search-count limit, not a hard CPU-time budget |

Navigation decisions and physical changes stay on the server
`ServerStorage.maze_world_changed` is a BindableEvent from the collapse controller to the navigation controller
`ReplicatedStorage.maze_knowledge_event` sends ordinary display messages to clients and accepts only a one-time viewer-ready action from each player
Important demo messages are also stored in a single replicated `demosnapshot` attribute so a late viewer can read the current state
The ready action cannot supply routes, declare discoveries or request a restart

The rig setup reads the authored maze to select reachable spawn positions, but does not copy that map into the navigation system
The colored raycast probes show direction and clearance; body-space overlap queries provide the grid's obstacle observations

## reading the main script

| Start at | Topic |
| --- | --- |
| [Line 14](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L14) | Grid coordinates, bounds and neighbors |
| [Line 51](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L51) | Binary heap operations |
| [Line 122](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L122) | A* search and unknown-cell costs |
| [Line 283](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L283) | Publishing shared discoveries |
| [Line 377](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L377) | Route comparisons and demonstration evidence |
| [Line 476](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L476) | Movement recovery and crossing checks |
| [Line 620](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L620) | Rotated debris footprints |
| [Line 675](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L675) | Collapse-event validation |
| [Line 748](ServerScriptService/mazeagentcontroller%20%28server%29.luau#L748) | Cleanup and scheduling |

[The walkthrough](docs/navigation.md) explains the reasoning, state transitions and tradeoffs in more detail

## files and Studio placement

Script filenames are lowercase; the table maps them to the actual Studio names

| Repository file | Studio location | Type |
| --- | --- | --- |
| [mazeagentcontroller (server).luau](ServerScriptService/mazeagentcontroller%20%28server%29.luau) | `ServerScriptService.MazeAgentController` | Script |
| [mazecollapsecontroller (server).luau](ServerScriptService/mazecollapsecontroller%20%28server%29.luau) | `ServerScriptService.maze_collapse_controller` | Script |
| [mazerigs.luau](ServerScriptService/mazerigs.luau) | `ServerScriptService.mazerigs` | ModuleScript |
| [mazeknowledgecontroller (client).luau](StarterGui/MazeKnowledgeGui/mazeknowledgecontroller%20%28client%29.luau) | `StarterGui.maze_knowledge_gui.controller` | LocalScript |
| [freecamcontroller (client).luau](StarterPlayer/StarterPlayerScripts/freecamcontroller%20%28client%29.luau) | `StarterPlayer.StarterPlayerScripts.freecam_controller` | LocalScript |

These files use the authored maze, agents and UI from PathfindPractice
They depend on `Workspace.Maze` with `MazeFloor`, `GoalPad` and the authored walls, `Workspace.MazeAgents`, and the two events listed above
The HUD expects its existing `title`, `legend` and `notification` labels
Cloning this repository alone does not recreate the place or its assets; the published game is the working demonstration

## verification

Release checked on 22 September 2026, with recorded Studio results from development

| Check | Result |
| --- | --- |
| Navigation checks in Studio | 880 passed, including comparison with an independent exhaustive shortest-path search on 100 seeded small maps |
| Behavior checks in Studio | 29 passed, covering shared changes, stale collapse events, debris clearance, recovery limits and cleanup |
| Full Studio run | All 15 agents arrived; all eight selected collapses completed |
| Shortcut witness in Studio | Maze Dummy 02 crossed cell 1262 from cell 1221 to cell 1303 after its remaining route changed from 31 moves to 19 |
| Source release | All five GitHub scripts matched the Studio sources used for the release |
| Delayed viewer readiness | All 15 agents stayed queued until the HUD was enabled and acknowledged |
| Late component initialization | Remounted HUD restored the current snapshot; remounted camera framed the example after its wall was gone |
| Automatic replay | A natural second cycle finished with 15 arrivals, eight collapses and the same 31-to-19 shortcut |
| Reset guards | Duplicate ready messages did not reset the run; duplicate and wrong-owner reset events were rejected |

The 909 total is a count of assertions/checks, not 909 independent scenarios
The current release was exercised in Studio; its full sequence has not been independently measured in the published client
Remounting client components checks delayed initialization, not a separate multiplayer connection
The temporary test fixtures are not part of this source-only repository, so the table reports recorded results rather than an included one-command test suite

## scope

The system targets this flat maze with eight-stud tiles and the existing rigs
It has been exercised with 15 agents; large crowds, multiplayer load and mobile viewing controls have not been validated
Shared knowledge is reset for each demonstration cycle and is not saved between sessions

## credit

Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox
