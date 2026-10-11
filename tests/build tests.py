# Connected Discord-GitHub
"""Extract current controller functions into local tests without executing startup."""
from pathlib import Path

tests = Path(__file__).resolve().parent
source = (tests.parent / 'ServerScriptService/maze agent controller (server).luau').read_text(encoding='utf-8')
output = tests / 'generated'
output.mkdir(exist_ok=True)
header = '-- Connected Discord-GitHub\n-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.\n'

def section(start, end):
    assert source.count(start) == source.count(end) == 1, f'Changed extraction boundary: {start} / {end}'
    return source[source.index(start):source.index(end)]

pure = section('type grid =', 'local players =')
wrapper = '''
local function findroute(map: grid, start: number, goal: number): ({number}, number)
    local job = newsearch(map, start, goal)
    while job.route == nil do stepsearch(job, 64) end
    return job.route :: {number}, job.cost
end
'''
baseline = (tests / 'core tests.luau').read_text(encoding='utf-8')
(output / 'core tests.luau').write_text(header + pure + wrapper + baseline, encoding='utf-8')

rng = '''
local Random = {}
function Random.new(seed)
    local value = seed
    return {NextNumber = function(self, low, high)
        value = (value * 48271) % 2147483647
        local unit = value / 2147483647
        return if low then low + (high - low) * unit else unit
    end}
end
'''
dispatch = section('local function compatible(', 'local function collidable(')
search = header + rng + pure + wrapper + '\nlocal baseline = (function()\n' + baseline + '\nend)()\n'
search += (tests / 'search prelude.luau').read_text(encoding='utf-8') + '\nlocal goalcell = 900\n' + dispatch
search += (tests / 'search tests.luau').read_text(encoding='utf-8')
(output / 'search tests.luau').write_text(search, encoding='utf-8')

attributes = section('local function attributes(', 'local function collisions(')
turning = section('function agentmethods.stopturn(', 'local function cancel(')
turning = header + 'local agentmethods = {}\nlocal agentmetatable = {__index = agentmethods}\n' + attributes + turning
turning += (tests / 'turning tests.luau').read_text(encoding='utf-8')
(output / 'turning tests.luau').write_text(turning, encoding='utf-8')
print(f'Built core, search and turning tests in {output}')
