# roblox shared maze systems

A Roblox maze demo where 15 autonomous agents share discoveries and update their routes as walls collapse

[Main navigation script](ServerScriptService/MazeAgentController%20%28Server%29.luau) · [Play PathfindPractice](https://www.roblox.com/games/113425488924507/PathfindPractice)

## what to watch

On a fresh server, Maze Dummy 04 discovers a wall and shares it with Maze Dummy 02, which changes route before reaching the blockage
The marked wall then collapses, the controller waits for the debris to stop blocking movement, and the runner compares routes through the new opening
The staged example reduces the remaining route from 31 grid moves to 19 and completes only after the runner crosses the passage

The other agents continue toward the goal while the remaining walls collapse
The opening sequence runs once per server

## scripts and placement

The filenames retain the original repository paths; use the Studio names below when installing the scripts

| Repository file | Studio location and type |
| --- | --- |
| `ServerScriptService/MazeAgentController (Server).luau` | `ServerScriptService.MazeAgentController` — Script |
| `ServerScriptService/MazeCollapseController (Server).luau` | `ServerScriptService.maze_collapse_controller` — Script |
| `ServerScriptService/mazerigs.luau` | `ServerScriptService.mazerigs` — ModuleScript |
| `StarterGui/MazeKnowledgeGui/MazeKnowledgeController (Client).luau` | `StarterGui.maze_knowledge_gui.controller` — LocalScript |
| `StarterPlayer/StarterPlayerScripts/FreecamController (Client).luau` | `StarterPlayer.StarterPlayerScripts.freecam_controller` — LocalScript |

The main script contains the grid search, shared knowledge, movement states, recovery, and collapse handling
The support module configures the rigs, collision groups, spawn positions, and scan markers
The collapse script handles the wall physics, and the two client scripts provide the existing HUD and freecam

These scripts use the authored maze, rigs, and UI from PathfindPractice
They are source files for that place, not a complete standalone place generator
The place also contains `ReplicatedStorage.maze_knowledge_event` (RemoteEvent) and `ServerStorage.maze_world_changed` (BindableEvent)

## verification

Studio checks passed: 880 navigation checks and 29 behavior checks, including stale collapse events, debris clearance, movement recovery, and cleanup
A full Studio run finished with all 15 agents at the goal, all eight selected wall collapses complete, and the runner crossing the 31-to-19-move shortcut
