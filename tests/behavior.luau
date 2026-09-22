-- Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox.
local checks = 0
local function check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end
for cell = 1, 15 do discover(map, cell, false) end
discover(map, 8, true)
local route = findroute(map, 6, 10)
local model = Instance.new("Model")
model.Name = "peer"
model.Parent = agents
local root = Instance.new("Part")
root.Anchored = true
root.CanCollide = false
root.Position = worldpoint(6)
root.Parent = model
local state = {
	rig = {model = model, root = root, humanoid = {Health = 100, Parent = model, MoveTo = function() end}},
	mode = "moving", anchor = 6, target = route[2], route = route, cursor = 2,
	dirty = false, reason = "fixture", started = 0, progress = 0, best = math.huge,
	nextplan = 0, nextcommand = 0, failures = 0, sharedat = 0, peerchanges = 0,
	peertrigger = nil, peersource = "", openings = {}, shortcuts = 0,
}
table.insert(states, state)
local fragment = Instance.new("Part")
fragment.Size = Vector3.new(3, 3, 3)
fragment.Anchored = true
fragment.Position = worldpoint(8) + Vector3.new(0, 2, 0)
fragment.Parent = owner
local function send(phase: string, revision: number, parts: {BasePart}, target: Instance?)
	worldchanged({owner = target or owner, id = "wall", phase = phase, revision = revision, position = worldpoint(8), parts = parts})
end
send("warning", 1, {})
send("falling", 2, {fragment})
check(gates[8] ~= nil and collapses.wall.revision == 2, "falling must hold the source cell closed")
publish(8, false, "local scout", os.clock())
check(map.cells[8].blocked, "local scans reopened an active collapse")
send("cleared", 3, {})
check(collapses.wall.revision == 2 and gates[8] ~= nil, "empty clear payload hid a live fragment")
local revision = map.revision
local noticecount = notices
send("warning", 1, {})
send("falling", 2, {})
check(map.revision == revision and notices == noticecount, "duplicate or reordered phase was applied")
fragment.Position = worldpoint(7) + Vector3.new(0, 2, 0)
updatedebris(os.clock())
check(map.cells[7].blocked and map.cells[8].blocked, "moving debris footprint was not refreshed")
fragment.CanCollide = false
nextnotice = math.huge
send("cleared", 3, {fragment})
check(not map.cells[7].blocked and not map.cells[8].blocked and gates[8] == nil, "vacated cells stayed blocked after clearance")
check(state.openings[7] and state.openings[8], "one opening overwrote another pending opening")
plan(state, os.clock())
check(state.shortcuts == 1 and table.find(state.route, 8) ~= nil, "agent failed to adopt the shorter route")
check(model:GetAttribute("shortcutaftercost") < model:GetAttribute("shortcutbeforecost"), "shortcut did not reduce actual remaining cost")
check(not next(state.openings), "consumed openings retained")
state.dirty = false
discover(map, 15, true)
publish(15, false, "structural change", os.clock())
check(not state.dirty, "irrelevant opening invalidated a shorter route")
local noticesbefore = notices
publish(9, true, "scout", os.clock())
check(state.dirty and map.cells[9].blocked and notices == noticesbefore, "notice throttle dropped a shared blockage")
publish(9, false, "structural change", os.clock())
state.openings[15] = true
local same = table.concat(state.route, ",")
plan(state, os.clock())
check(table.concat(state.route, ",") == same and state.shortcuts == 1, "no-benefit opening replaced valid route")
local oldowner = owner
owner = Instance.new("Folder")
owner.Name = "maze_collapse_debris"
oldowner.Parent = nil
owner.Parent = testworld
local nextfragment = fragment:Clone()
nextfragment.CanCollide = true
nextfragment.Position = worldpoint(8) + Vector3.new(0, 2, 0)
nextfragment.Parent = owner
send("falling", 2, {nextfragment})
check(collapses.wall.revision == 2 and map.cells[8].blocked, "new generation could not reuse wall id")
send("cleared", 3, {}, oldowner)
check(collapses.wall.revision == 2 and map.cells[8].blocked, "old generation reopened current collapse")
nextfragment.CanCollide = false
send("cleared", 3, {nextfragment})
send("falling", 2, {nextfragment})
check(collapses.wall.revision == 3 and not map.cells[8].blocked, "late falling event replaced cleared state")
worldchanged({owner = owner, id = "invalid", position = worldpoint(8), parts = {}})
check(collapses.invalid == nil, "missing phase accepted")
worldchanged({owner = owner, id = "invalid", position = Vector3.new(0/0, 0, 0), parts = {}, phase = "warning", revision = 1})
check(collapses.invalid == nil, "nonfinite position accepted")
oldowner:Destroy()
local now = os.clock()
state.mode = "queued"
state.nextplan = now + 10
state.dirty = true
check(not update(state, now), "queued agent moved before its start time")
state.mode = "observing"
state.demohold = true
state.dirty = true
state.anchor = 6
state.target = 6
state.route = {6, 7, 8, 9, 10}
state.cursor = 2
plan(state, now)
check(state.mode == "observing" and state.target == 6, "demo pause issued a movement target")
state.nextplan = now - 1
check(update(state, now) and not state.demohold, "demo pause did not expire when clearance never arrived")
state.mode = "moving"
state.demopath = true
state.anchor = 7
state.target = 8
state.route = {7, 8, 9, 10}
state.cursor = 2
state.dirty = false
state.peertrigger = nil
state.openings = {}
root.Position = worldpoint(8)
update(state, now)
check(state.demoentry == 7 and not agents:GetAttribute("democomplete"), "reaching the wall cell alone completed the demo")
state.mode = "moving"
state.anchor = 8
state.target = 7
root.Position = worldpoint(7)
update(state, now + 1)
check(not agents:GetAttribute("democomplete"), "turning back into the entrance counted as crossing")
state.mode = "moving"
state.anchor = 8
state.target = 9
state.demoentry = 7
root.Position = worldpoint(9)
update(state, now + 2)
check(agents:GetAttribute("democomplete") == true and agents:GetAttribute("demoexitcell") == 9, "actual crossing did not complete the demo")
state.mode = "moving"
state.anchor = 6
state.target = 7
state.failures = 0
state.started = now - 3
state.progress = now
root.Position = worldpoint(6)
maintainmove(state, now)
check(state.mode == "recovering" and state.target == 6 and state.failures == 1, "stalled move did not recover to its anchor")
state.failures = 3
state.started = now - 3
maintainmove(state, now)
check(state.mode == "recovering" and state.failures == 4, "last bounded recovery attempt was skipped")
state.started = now - 3
maintainmove(state, now)
check(state.mode == "stopped", "recovery exceeded its attempt limit")
stop()
check(not next(collapses) and not next(gates) and not next(map.cells), "teardown retained collapse state")
worldchanged({owner = owner, id = "afterstop", phase = "warning", revision = 1, position = worldpoint(8), parts = {}})
check(not next(collapses) and not next(map.cells), "late event repopulated a stopped controller")
return checks

end)
testworld:Destroy()
assert(ok, result)
return result
