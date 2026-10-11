# PathfindPractice

15 agents share discoveries, change routes and use shortcuts opened by collapsing walls

[Main script](ServerScriptService/maze%20agent%20controller%20%28server%29.luau) · [Demo place](https://www.roblox.com/games/113425488924507/PathfindPractice) · [Walkthrough](docs/navigation.md) · [Tests](tests/readme.md)

Join on desktop. After the HUD loads, watch the scout share a blockage, the nearby runner change route, and the marked wall open a usable shortcut once its debris clears. The full demonstration includes eight collapses and repeats after a 15-second pause

Camera controls are WASD, E/Q for height, right mouse to look, middle mouse to pan, wheel to dolly, Shift/Ctrl for speed and F3 to toggle

The main source has **999 physical lines and 996 code lines**. It owns rig setup, probes, partial shared knowledge, heap A*, recovery, constraint turning, collapse physics and replay. Searches run in fair slices against fixed belief snapshots, with charged heap pops, an elapsed-time check and validation before adoption

It has no other authored server-script dependency. It clones the same source into a **second runtime Script**, `maze guardian`, so cleanup can outlive unexpected controller destruction. The guardian removes its private server record and itself after teardown

| Source | Studio placement |
| --- | --- |
| [maze agent controller (server).luau](ServerScriptService/maze%20agent%20controller%20%28server%29.luau) | ServerScriptService.MazeAgentController |
| [maze knowledge controller (client).luau](StarterGui/MazeKnowledgeGui/maze%20knowledge%20controller%20%28client%29.luau) | StarterGui.maze_knowledge_gui.controller |
| [freecam controller (client).luau](StarterPlayer/StarterPlayerScripts/freecam%20controller%20%28client%29.luau) | StarterPlayer.StarterPlayerScripts.freecam_controller |

Use the main controller in place of the old controller, collapse script and rig module. Keep the authored `Workspace.Maze`, `MazeAgents`, floor, goal, focus wall and existing HUD. The RemoteEvent `maze_knowledge_event` belongs in ReplicatedStorage and BindableEvent `maze_world_changed` in ServerStorage. This repo contains source, not the full place assets

Included fixtures reproduce 960 baseline and 1,182 additional search assertions with a fixed command-line PRNG substitute. Recorded Studio tests on copied assets completed one full cycle with 15 arrivals, eight collapses and a **31-to-19** shortcut, then rebuilt probes and turning for replay. Two clients saw the HUD, camera and probe effects; destruction and removal released owned resources and restored saved rotation values

The candidate was tested on copies of place version 49. A repository push does not update the published Roblox place. Full Roblox editor type analysis, large crowds and mobile controls have not been validated

Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox
