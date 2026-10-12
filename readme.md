# PathfindPractice

15 agents share discoveries, change routes and use shortcuts opened by collapsing walls

[Main script](ServerScriptService/maze%20agent%20controller%20%28server%29.luau) · [Demo place](https://www.roblox.com/games/113425488924507/PathfindPractice) · [Walkthrough](docs/navigation.md) · [Tests](tests/readme.md)

Join on desktop. After the HUD loads, watch the scout share a blockage, the nearby runner change route, and the marked wall open a usable shortcut once its debris clears. The full demonstration includes eight collapses and repeats after a 15-second pause

Camera controls are WASD, E/Q for height, right mouse to look, middle mouse to pan, wheel to dolly, Shift/Ctrl for speed and F3 to toggle

One server Script handles rig setup, probes, shared observations, sliced searches, recovery, turning, collapse physics and replay. It has no guardian clone or authored server-module dependency

Spawn checks and route planning share a search kernel, but the rigs learn their own map through sensing. Searches use fixed snapshots and fair work slices, then check new discoveries before accepting a route

The controller owns its move targets, turning constraints, probes and debris. Engine cleanup stops movement after owner loss. Authored attachments and AutoRotate stay unchanged; unexpected destruction leaves status attributes at their last snapshot

| Source | Initial Studio placement |
| --- | --- |
| [maze agent controller (server).luau](ServerScriptService/maze%20agent%20controller%20%28server%29.luau) | ServerScriptService.MazeAgentController |
| [maze knowledge controller (client).luau](StarterGui/MazeKnowledgeGui/maze%20knowledge%20controller%20%28client%29.luau) | StarterGui.maze_knowledge_gui.controller |
| [freecam controller (client).luau](StarterPlayer/StarterPlayerScripts/freecam%20controller%20%28client%29.luau) | StarterPlayer.StarterPlayerScripts.freecam_controller |

The server controller moves itself under the authored Maze for native resource operation. Keep the authored Maze, MazeAgents, floor, goal, focus wall, HUD and existing event names. This repository contains source and fixtures, not the full place assets

The [test notes](tests/readme.md) cover command-line checks and recorded Studio runs with 15 arrivals, eight collapses, a crossed **31-to-19** shortcut, replay, two clients and shutdown during movement

Tests used copies of place version 49. A repository push does not update the published Roblox place. Full Roblox editor type analysis, larger crowds and mobile controls remain unverified

Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox
