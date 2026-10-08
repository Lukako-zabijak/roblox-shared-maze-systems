# Run the checks

Requires Python 3 and Roblox Studio. No Python packages, MCP server or live game access are needed

1. From the repository root, run `python tests/build%20tests.py`
2. Open a blank baseplate in Studio and stay in Edit mode
3. Create two ModuleScripts in ServerStorage named `coretests` and `behaviortests`
4. Paste `tests/generated/core tests.luau` into coretests and `tests/generated/behavior tests.luau` into behaviortests
5. Run this in Studio's Command Bar:

```luau
-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
for _, name in {"coretests", "behaviortests"} do
    local module = game.ServerStorage[name]:Clone()
    module.Parent = game.ServerStorage
    local ok, result = pcall(require, module)
    module:Destroy()
    assert(ok, result)
    print(name, result)
end
```

Expected output for the Edit-mode suites: `coretests 880` and `behaviortests 29`. A failed assertion stops with its message. Rebuild and repaste after changing the production source; the runner clones modules so each invocation avoids require's cached result

## What runs

- `core tests.luau`: grid boundaries, discovery revisions, route costs and shortcuts; compares A* with an independent exhaustive search on 100 seeded maps and checks returned routes
- `world fixture.luau` and `behavior tests.luau`: isolated parts at (10000, 0, 10000), real overlap queries, moving debris, stale/duplicate collapse events, route changes, crossing evidence, recovery limits and stopped-controller cleanup
- `build tests.py`: extracts functions from the current main script instead of keeping a second planner implementation. Exact-match substitutions fail if the expected adapter changes

The behavior fixture replaces rig drawing, humanoid movement commands and client notifications with stubs, redirects world ownership checks to its folder, and uses the Default collision group. It removes startup and the scheduler. Its folder is destroyed after assertions, including assertion failure

The two existing suites contain 909 assertions, not 909 independent scenarios. They do not test actual walking, multiplayer delivery, camera/HUD loading, replay scheduling or publication. The separate observed Studio run reached 15 arrivals, eight collapses and a 31-to-19 shortcut; watch those events in the demo to inspect the full integration

Generated modules are local test artifacts, not submission scripts or game runtime files. Delete the two imported modules after testing

## Constraint ownership tests

The builder also creates `tests/generated/turning tests.luau`. Import that file as a ModuleScript named `turningtests` in ServerStorage. Start Play and select the **Server** Command Bar context before running:

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

Expected output: `turningtests 23`. The anchored-root denial intentionally emits one warning, then checks that no partial objects or borrowed setting survive. The fixture is removed after success or failure. These checks exercise real ownership APIs, attachment and constraint properties, goal directions, near-zero guards, repeated setup, missing owned objects, true/false restoration and cleanup after removal. They also check shared inherited methods and independent per-agent route storage. They run synchronously and do not establish the solver's response during a full walk

Full movement, corners, recovery, replay and client replication require the separate game integration checks. Remove imported test modules before saving or publishing the place
