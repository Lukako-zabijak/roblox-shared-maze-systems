# Run the checks

From the repository root run `python "tests/build tests.py"`, then run these with the standalone Luau interpreter on PATH

```text
luau "tests/generated/search tests.luau"
luau "tests/generated/reachability tests.luau"
```

Expected outputs are `baseline=960 additional=1182 dispatches=11` and `reachability=7382`. Deadline-based scheduling can change the dispatch count and its associated assertion count on a slower machine. Generated files are ignored and extracted from the current main source

The baseline uses an independent exhaustive shortest-path reference. Additional search assertions cover immutable snapshots, charged pops, sliced costs, deadlines, fairness, generations, compatibility and the open/closed passage comparison. Reachability uses independent queue traversal on seeded rectangular maps. The command-line suite uses a fixed PRNG substitute and mock attribute adapters; it does not simulate Roblox physics

## Recorded engine runs

[Cycle evidence](evidence/cycle.json) records startup from ServerScriptService on copied version-49 assets, all 15 arrivals, eight ordered collapses, 96 chunks, 144 fragments, 630 dots and a physically crossed 31-to-19 shortcut, then replay startup. Both clients observed upright rigs, probe colors, HUD and camera. Exactly one server controller ran in the fixture

[Lifetime evidence](evidence/lifetime.json) requires two rigs moving horizontally faster than one stud per second before each live, detached and destroyed shutdown case. Active world resources disappeared, horizontal velocity fell below the test tolerance and all 15 original rotation values stayed unchanged. Live shutdown published stopped/offline states. Unexpected owner loss kept the last cached attributes; an explicitly held detached Script kept inactive children until destroyed

[Source review](evidence/source.json) records the earlier fully annotated source, including its hash and layout. [Reachability evidence](evidence/reachability.json) records the pure-mode checks

These reports were issued by Codex for the source at commit `a084cbaf`. The later cleanup changes comments and documentation only; its executable lines match that source. The reports remain historical results, not fresh engine tests of this revision

The actual test harnesses are [cycle server](cycle%20server.luau), [cycle client](cycle%20client.luau), [lifetime server](lifetime%20server.luau) and [lifetime client](lifetime%20client.luau). They require a temporary copied `candidatefixture`, copied HUD/camera, test event names and a disabled controller under ServerScriptService. The test source uses exactly three namespace substitutions to address the copied world and events. They are StudioTestService harnesses, not production scripts or automatic place importers. Full integration cannot be reproduced from this repository without the authored assets

Remove test fixtures and harnesses after testing. The JSON records document observed runs; the unit builder does not rerun those engine tests or publish the place
