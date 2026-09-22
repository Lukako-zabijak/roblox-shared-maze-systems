# PathfindPractice

**One learns. All know.** A Roblox maze demonstration where 15 agents share discoveries, change their routes, and use passages opened by collapsing walls

[Read the main script](ServerScriptService/MazeAgentController%20%28Server%29.luau) · [Play the demo](https://www.roblox.com/games/113425488924507/PathfindPractice) · [Code walkthrough](docs/navigation.md)

## start here

The main example is **MazeAgentController (Server).luau** — one 794-line script with 670 nonblank, noncomment code lines
It contains the grid search, shared map, replanning, movement recovery and collapse-event handling
The other files support the authored rigs, wall physics, HUD and camera

For a direct code-file link, use [MazeAgentController on GitHub](https://github.com/Lukako-zabijak/roblox-shared-maze-systems/blob/main/ServerScriptService/MazeAgentController%20%28Server%29.luau)

## watch the demonstration

Join a fresh server on desktop — the camera starts above the first example when its wall is present

1. **A discovery is shared** — Maze Dummy 04 finds a wall, and Maze Dummy 02 changes its planned route before reaching the blockage
2. **The wall collapses** — the runner pauses while the marked wall flashes orange and breaks into physical debris
3. **The opening becomes usable** — navigation keeps the passage blocked until the debris clears, then compares routes through it
4. **The runner takes the shortcut** — in the recorded Studio run, the remaining route fell from **31 grid moves to 19**, and the runner crossed the opened passage
5. **The full maze continues** — the other agents head toward the goal while the remaining selected walls collapse

The first three agents start about five seconds after server initialization; the background agents start later
The opening sequence runs **once per server**, so joining late or rejoining the same server will not replay it
There is no manual replay button

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
`ReplicatedStorage.maze_knowledge_event` sends display messages to clients

The rig setup reads the authored maze to select reachable spawn positions, but does not copy that map into the navigation system
The colored raycast probes show direction and clearance; body-space overlap queries provide the grid's obstacle observations

## reading the main script

| Start at | Topic |
| --- | --- |
| [Line 13](ServerScriptService/MazeAgentController%20%28Server%29.luau#L13) | Grid coordinates, bounds and neighbors |
| [Line 50](ServerScriptService/MazeAgentController%20%28Server%29.luau#L50) | Binary heap operations |
| [Line 116](ServerScriptService/MazeAgentController%20%28Server%29.luau#L116) | A* search and unknown-cell costs |
| [Line 262](ServerScriptService/MazeAgentController%20%28Server%29.luau#L262) | Publishing shared discoveries |
| [Line 356](ServerScriptService/MazeAgentController%20%28Server%29.luau#L356) | Route comparisons and demonstration evidence |
| [Line 455](ServerScriptService/MazeAgentController%20%28Server%29.luau#L455) | Movement recovery and crossing checks |
| [Line 598](ServerScriptService/MazeAgentController%20%28Server%29.luau#L598) | Rotated debris footprints |
| [Line 651](ServerScriptService/MazeAgentController%20%28Server%29.luau#L651) | Collapse-event validation |
| [Line 724](ServerScriptService/MazeAgentController%20%28Server%29.luau#L724) | Cleanup and scheduling |

[The walkthrough](docs/navigation.md) explains the reasoning, state transitions and tradeoffs in more detail

## files and Studio placement

Repository filenames retain their original paths; use the actual Studio names below

| Repository file | Studio location | Type |
| --- | --- | --- |
| [MazeAgentController (Server).luau](ServerScriptService/MazeAgentController%20%28Server%29.luau) | `ServerScriptService.MazeAgentController` | Script |
| [MazeCollapseController (Server).luau](ServerScriptService/MazeCollapseController%20%28Server%29.luau) | `ServerScriptService.maze_collapse_controller` | Script |
| [mazerigs.luau](ServerScriptService/mazerigs.luau) | `ServerScriptService.mazerigs` | ModuleScript |
| [MazeKnowledgeController (Client).luau](StarterGui/MazeKnowledgeGui/MazeKnowledgeController%20%28Client%29.luau) | `StarterGui.maze_knowledge_gui.controller` | LocalScript |
| [FreecamController (Client).luau](StarterPlayer/StarterPlayerScripts/FreecamController%20%28Client%29.luau) | `StarterPlayer.StarterPlayerScripts.freecam_controller` | LocalScript |

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
| Published client | The place loaded, with agents, the HUD, shared-information updates and collapse messages observed |

The 909 total is a count of assertions/checks, not 909 independent scenarios
The exact shortcut measurement and all-agent completion were verified in Studio, not independently measured in the published client
The temporary test fixtures are not part of this source-only repository, so the table reports recorded results rather than an included one-command test suite

## scope

The system targets this flat maze with eight-stud tiles and the existing rigs
It has been exercised with 15 agents; large crowds, multiplayer load and mobile viewing controls have not been validated
Shared knowledge lasts for the current server run and is not saved between sessions

## credit

Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox
