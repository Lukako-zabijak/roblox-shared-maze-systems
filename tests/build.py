"""Build Studio test modules from the current checked-out navigation source."""
from pathlib import Path

tests = Path(__file__).resolve().parent
source = (tests.parent / 'ServerScriptService/mazeagentcontroller (server).luau').read_text(encoding='utf-8')
output = tests / 'generated'
output.mkdir(exist_ok=True)

def before(text, marker):
    assert text.count(marker) == 1, f'Expected one source boundary: {marker}'
    return text.split(marker)[0]

def replace(text, old, new, count=1):
    assert text.count(old) == count, f'Adapter changed; review test substitution: {old}'
    return text.replace(old, new)

core = before(source, '-- runtime adapter')
(output / 'core.luau').write_text(core + (tests / 'core.luau').read_text(encoding='utf-8'), encoding='utf-8')

behavior = before(source, 'local function seed(')
for old, new, count in [
    ('local replicatedstorage = game:GetService("ReplicatedStorage")', 'local notices = 0', 1),
    ('local rigs = require(script.Parent:WaitForChild("mazerigs"))', 'local rigs = {clear = function() end, draw = function() end}', 1),
    ('workspace:WaitForChild("Maze")', 'testworld:WaitForChild("Maze")', 1),
    ('workspace:WaitForChild("MazeAgents")', 'testworld:WaitForChild("MazeAgents")', 1),
    ('local knowledgeevent = replicatedstorage:WaitForChild("maze_knowledge_event") :: RemoteEvent', 'local knowledgeevent = {FireAllClients = function() notices += 1 end}', 1),
    ('local worldevent = serverstorage:WaitForChild("maze_world_changed") :: BindableEvent', '', 1),
    ('local initialrigs = rigs.start(maze, agents)', '', 1),
    ('overlap.CollisionGroup = "MazeAgents"', 'overlap.CollisionGroup = "Default"', 1),
    ('part:IsDescendantOf(workspace)', 'part:IsDescendantOf(testworld)', 1),
    ('workspace:FindFirstChild("maze_collapse_debris")', 'testworld:FindFirstChild("maze_collapse_debris")', 2),
]:
    behavior = replace(behavior, old, new, count)

fixture = (tests / 'fixture.luau').read_text(encoding='utf-8')
checks = (tests / 'behavior.luau').read_text(encoding='utf-8')
(output / 'behavior.luau').write_text(fixture + behavior + checks, encoding='utf-8')
print(f'Built core.luau and behavior.luau in {output}')
