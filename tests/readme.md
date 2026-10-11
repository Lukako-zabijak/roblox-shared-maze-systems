# Run the checks

From the repository root, run `python "tests/build tests.py"`. The builder extracts the current production functions and writes ignored files under `tests/generated`; it fails if its source boundaries change

With the standalone Luau interpreter on PATH, run `luau "tests/generated/search tests.luau"`. Expected output is `baseline=960 additional=1182 dispatches=11`; elapsed-time slicing can change the dispatch count on a slower machine

The baseline compares returned paths with an independent exhaustive shortest-path search on 100 small maps. The added assertions check immutable snapshots, sliced costs, charged pops, expired deadlines, all 15 queued agents receiving work, generation cancellation, route compatibility and an actual open/closed passage comparison

The command-line fixture uses a deterministic PRNG substitute and mock attribute adapters. It does not run Roblox physics, client delivery or controller startup

## Studio fixtures

Import `tests/generated/core tests.luau` as a ModuleScript in ServerStorage of a blank baseplate and require a fresh clone in Edit mode. This version uses Roblox Random, so the assertion count depends on the generated maps and differs from the command-line substitute

Import `tests/generated/turning tests.luau` as a ModuleScript named `turningtests`. Start Play and run the following in the Server Command Bar

```luau
-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
local module = game.ServerStorage.turningtests:Clone()
module.Parent = game.ServerStorage
local ok, result = pcall(require, module)
module:Destroy()
assert(ok, result)
print("turningtests", result)
```

The turning fixture has 23 assertions covering real network ownership, constraint settings, horizontal and near-zero goals, shared methods, separate route storage, repeated setup, missing owned objects, true/false restoration, ownership denial and model destruction. The anchored-root denial intentionally emits a warning. Its isolated fixture is removed after success or failure; remove imported test modules before saving or publishing

## Recorded integration evidence

[Cycle evidence](evidence/cycle.json) records one complete run on copied version-49 assets: 15 arrivals, zero stopped rigs, eight ordered collapse lifetimes, 96 chunks, 144 fragments, 630 probe dots and a 31-to-19 shortcut, followed by replay startup

[Multiplayer evidence](evidence/multiplayer.json) records two real clients seeing the rigs, upright turning, three probe colors, HUD and camera. Controller destruction during an active collapse and ancestry removal each left zero owned turning pairs, attachments, dots, debris, guardians or registry records and restored all 15 humanoids. A test-only setup variant checked mixed saved rotation values

[Source equivalence](evidence/source%20equivalence.json) records five later comment corrections with identical executable text and compiled bytes. The final source SHA identifies the submitted version; runtime SHA fields identify the tested snapshot. These JSON records describe observed integration runs, not results automatically reproduced by the unit builder

Full walking, phase effects, replay and guardian teardown require a separate isolated game test. The repository does not contain the authored place assets or automatically publish them
