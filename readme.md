# PathfindPractice

15 agents share discoveries, change routes and use shortcuts opened by collapsing walls

[Main script](ServerScriptService/maze%20agent%20controller%20%28server%29.luau) · [Demo place](https://www.roblox.com/games/113425488924507/PathfindPractice) · [Walkthrough](docs/navigation.md) · [Tests](tests/readme.md)

Join on desktop. After the HUD loads, watch the scout share a blockage, the nearby runner change route, and the marked wall open a usable shortcut once its debris clears. The full demonstration includes eight collapses and repeats after a 15-second pause

Camera controls are WASD, E/Q for height, right mouse to look, middle mouse to pan, wheel to dolly, Shift/Ctrl for speed and F3 to toggle

The main file has **985 physical lines, 960 explained code lines and 22 blank separators**. One running server Script owns rig setup, probes, shared observations, resumable heap searches, recovery, constraint turning, collapse physics and replay. It has no guardian clone or authored server-module dependency

Spawn connectivity and route planning share one search kernel with separate physical and learned maps. Searches keep fixed snapshots, run in fair slices and validate results before adoption

Goals, turning constraints, probes and debris belong to the controller's world ancestry. Native cleanup stops movement after owner loss without changing authored attachments or AutoRotate settings. Normal shutdown and replay update stopped/offline states; unexpected destruction leaves inspection attributes at their last snapshot

| Source | Initial Studio placement |
| --- | --- |
| [maze agent controller (server).luau](ServerScriptService/maze%20agent%20controller%20%28server%29.luau) | ServerScriptService.MazeAgentController |
| [maze knowledge controller (client).luau](StarterGui/MazeKnowledgeGui/maze%20knowledge%20controller%20%28client%29.luau) | StarterGui.maze_knowledge_gui.controller |
| [freecam controller (client).luau](StarterPlayer/StarterPlayerScripts/freecam%20controller%20%28client%29.luau) | StarterPlayer.StarterPlayerScripts.freecam_controller |

The server controller moves itself under the authored Maze for native resource operation. Keep the authored Maze, MazeAgents, floor, goal, focus wall, HUD and existing event names. This repository contains source and fixtures, not the full place assets

Included fixtures reproduce 960 baseline, 1,182 search/scheduler and 7,382 reachability checks. Exact-source copied-asset tests recorded 15 arrivals, eight collapses, a **31-to-19** crossed shortcut, replay startup, two clients and active-motion shutdown

Tests used copies of place version 49. A repository push does not update the published Roblox place. Full Roblox editor type analysis, larger crowds and mobile controls remain unverified

Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox
