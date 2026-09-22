# PathfindPractice

15 agents share discoveries, change routes and use shortcuts opened by collapsing walls

[Main script](ServerScriptService/mazeagentcontroller%20%28server%29.luau) · [Play the demo](https://www.roblox.com/games/113425488924507/PathfindPractice) · [Walkthrough](docs/navigation.md) · [Run the tests](tests/readme.md)

## Watch

Join on desktop. The first run waits for the HUD to load, then starts after five seconds

1. Maze Dummy 04 discovers a wall and Maze Dummy 02 changes route
2. The marked wall collapses; its passage stays blocked while debris occupies it
3. The runner finds a shorter route and crosses the opening

The full run includes 15 agents and eight collapses. After completion and a 15-second pause, the demonstration resets and repeats. Late viewers receive the current status

Camera: WASD to move, E/Q for height, right mouse to look, middle mouse to pan, wheel to dolly, Shift/Ctrl for speed, F3 to toggle

## Code

The main example is one **885-line Luau script with 730 nonblank, noncomment code lines**. It combines A* with a binary heap, a partially known shared grid, selective replanning, bounded movement recovery and collapse-event validation

Routes are calculated at runtime. Starting positions and the first collapse are staged to make the interaction visible

| File | Studio placement |
| --- | --- |
| [mazeagentcontroller (server).luau](ServerScriptService/mazeagentcontroller%20%28server%29.luau) | ServerScriptService.MazeAgentController |
| [mazecollapsecontroller (server).luau](ServerScriptService/mazecollapsecontroller%20%28server%29.luau) | ServerScriptService.maze_collapse_controller |
| [mazerigs.luau](ServerScriptService/mazerigs.luau) | ServerScriptService.mazerigs (ModuleScript) |
| [mazeknowledgecontroller (client).luau](StarterGui/MazeKnowledgeGui/mazeknowledgecontroller%20%28client%29.luau) | StarterGui.maze_knowledge_gui.controller |
| [freecamcontroller (client).luau](StarterPlayer/StarterPlayerScripts/freecamcontroller%20%28client%29.luau) | StarterPlayer.StarterPlayerScripts.freecam_controller |

The scripts depend on the authored maze, rigs and existing HUD in the demo; cloning this repo alone does not recreate the place

## Checks and limits

[Included tests](tests/readme.md) reproduce **880 core assertions and 29 behavior assertions**, including an independent shortest-path comparison on 100 seeded maps. The instructions explain the fixture substitutions and exclusions

A separate Studio run completed two cycles; the second recorded 15 arrivals, eight collapses and a shortcut from **31 remaining grid moves to 19**. This is recorded integration evidence, not a result produced by the unit fixtures

Designed for this flat eight-stud grid and 15 agents. Multiplayer load, large crowds and mobile controls have not been validated

Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox
