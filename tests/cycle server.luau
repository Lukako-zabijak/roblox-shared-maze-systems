-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
local service = game:GetService("StudioTestService")
if service:GetTestArgs() ~= "single cycle" then return end
assert(game.PlaceId == 113425488924507)
for _, item in game.ServerScriptService:GetChildren() do
	if item:IsA("Script") and item ~= script then item.Enabled = false end
end
local fixture = game.ServerStorage.candidatefixture
fixture.Parent = workspace
local focus = fixture.Maze.MazeFloor
game.Players.PlayerAdded:Connect(function(player) player.ReplicationFocus = focus end)
for _, player in game.Players:GetPlayers() do player.ReplicationFocus = focus end
local remote = Instance.new("RemoteEvent")
remote.Name = "candidateobserver"
remote.Parent = fixture
local reports = {}
local rotation = {}
local index = 0
for _, model in fixture.MazeAgents:GetChildren() do
 if model:IsA("Model") then
  index += 1
  if index <= 2 then model.Humanoid.AutoRotate = false end
  rotation[model.Name] = model.Humanoid.AutoRotate
 end
end
local observer = remote.OnServerEvent:Connect(function(player, report) reports[player.Name] = report end)
local proof = {current = 0, cycles = {}, events = {}, samples = 0, minup = 1, maxangular = 0, maxwork = 0}
local function cycle()
	local id = math.max(1, proof.current)
	proof.cycles[id] = proof.cycles[id] or {chunks = 0, fragments = 0, highlights = 0, warningparts = 0, markers = 0}
	return proof.cycles[id]
end
local added = fixture.DescendantAdded:Connect(function(item)
	if item:IsA("Folder") and item.Name == "maze_collapse_debris" then proof.current += 1 end
	local c = cycle()
	if item:IsA("Highlight") and item.Name == "collapse_warning" then c.highlights += 1
	elseif item:IsA("BasePart") then
		if item:GetAttribute("CollapseDebris") then c.chunks += 1
		elseif item.Name == "falling_fragment" then c.fragments += 1
		elseif item.Name == "collapse_warning" then c.warningparts += 1
		elseif string.match(item.Name, "^Dot_") then c.markers += 1 end
	end
end)
local phase = fixture.maze_world_changed.Event:Connect(function(event)
	if event.phase then table.insert(proof.events, {id = event.id, phase = event.phase, parts = #event.parts, cycle = proof.current}) end
end)
local elapsed = 0
local sampler = game:GetService("RunService").Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.1 then return end
	elapsed = 0
	proof.samples += 1
	local c = cycle()
	local arrived, stopped, pairs, restored = 0, 0, 0, 0
	for _, model in fixture.MazeAgents:GetChildren() do
		if not model:IsA("Model") then continue end
		local mode = model:GetAttribute("PathState")
		if mode == "arrived" then arrived += 1 elseif mode == "stopped" then stopped += 1 end
		if model.Humanoid.AutoRotate == rotation[model.Name] then restored += 1 end
		local root = model.HumanoidRootPart
 assert(root:GetNetworkOwner() == nil, "every copied rig must keep server physics ownership")
		proof.minup = math.min(proof.minup, root.CFrame.UpVector.Y)
		proof.maxangular = math.max(proof.maxangular, root.AssemblyAngularVelocity.Magnitude)

	end
	for _, item in fixture:GetDescendants() do
        if item:IsA("AlignOrientation") and item.Name == "navturnalignment" then pairs += 1 end
    end
    c.arrived, c.stopped, c.pairs, c.autorotate = arrived, stopped, pairs, restored
	c.complete = fixture.MazeAgents:GetAttribute("democomplete")
	c.shared = fixture.MazeAgents:GetAttribute("demoshared")
	c.before, c.after = fixture.MazeAgents:GetAttribute("demobeforesteps"), fixture.MazeAgents:GetAttribute("demoaftersteps")
	c.phase = fixture.MazeAgents:GetAttribute("demophase")
	local owner = fixture:FindFirstChild("maze_collapse_debris", true)
	c.collapsed = if owner then owner:GetAttribute("CollapsedWalls") else 0
	proof.maxwork = math.max(proof.maxwork, fixture.MazeAgents:GetAttribute("searchwork") or 0)
end)
local controller = game.ServerScriptService.candidatecontroller
controller.Enabled = true
local deadline = os.clock() + 310
local ok, problem = pcall(function()
	while proof.current < 2 do
		assert(os.clock() < deadline, "full cycle and replay must finish within the bound")
		task.wait(0.25)
	end
	task.wait(0.3)
	local first, second = proof.cycles[1], proof.cycles[2]
	assert(first.arrived == 15 and first.stopped == 0 and first.collapsed == 8, "full cycle needs all arrivals and all collapses")
	assert(first.chunks == 96 and first.fragments == 144 and first.highlights == 8 and first.warningparts == 8, "all physical and warning features must be created")
	assert(first.markers == 630 and first.pairs == 0 and first.autorotate == 15, "normal retirement must clear turning after all probes were created")
	assert(first.shared and first.complete and first.after < first.before, "real shared reroute and physical shortcut crossing are required")
	assert(second.markers == 630 and second.pairs == 15 and second.collapsed == 0, "replay must rebuild rig resources and reset collapse history")
	local order = {}
	for _, event in proof.events do
		if event.cycle ~= 1 then continue end
		local expected = ({warning = 1, falling = 2, cleared = 3})[event.phase]
		assert(expected == (order[event.id] or 0) + 1, "each wall phase must advance once in order")
		order[event.id] = expected
	end
	local live = 0
 for _, item in fixture:GetDescendants() do if item:IsA("Script") and item.Enabled then live += 1 end end
 assert(live == 1, "the actual maze controller must be the only running server Script in its fixture")
 local viewers = 0
 for _, report in reports do
  assert(report.agents == 15 and report.maxpairs == 15 and report.maxdots == 630 and report.turns > 1, "both clients must observe the complete active rigs")
  assert(report.red and report.green and report.cyan and report.hud and report.camera and report.minup > 0.99, "both clients must see the real HUD camera probes and upright movement")
  viewers += 1
 end
 assert(viewers == 2, "two independent client reports are required")
 local complete = 0
	for _, value in order do if value == 3 then complete += 1 end end
	assert(complete == 8 and proof.maxwork <= 1024 and proof.minup > 0.99, "all phase lifetimes work with bounded planning and upright rigs")
end)
added:Disconnect()
phase:Disconnect()
sampler:Disconnect()
observer:Disconnect()
controller:Destroy()
task.wait(0.5)
local cleanup = {constraints = 0, dots = 0, goals = 0, highlights = 0, restored = 0, moving = 0}
for _, item in fixture:GetDescendants() do
    if item:IsA("AlignOrientation") and item.Name == "navturnalignment" then cleanup.constraints += 1 end
    if item:IsA("Highlight") and item.Name == "collapse_warning" then cleanup.highlights += 1 end
    if item:IsA("BasePart") and string.match(item.Name, "^Dot_") then cleanup.dots += 1 end
    if item.Name == "navgoal" then cleanup.goals += 1 end
    if item:IsA("Humanoid") then
        if item.AutoRotate == rotation[item.Parent.Name] then cleanup.restored += 1 end
        if item.MoveDirection.Magnitude > 0.01 then cleanup.moving += 1 end
    end
end
assert(cleanup.constraints == 0 and cleanup.dots == 0 and cleanup.goals == 0 and cleanup.highlights == 0 and cleanup.restored == 15 and cleanup.moving == 0)
fixture:Destroy()
service:EndTest({ok = ok, problem = if ok then "none" else tostring(problem), proof = proof, clients = reports, cleanup = cleanup})
